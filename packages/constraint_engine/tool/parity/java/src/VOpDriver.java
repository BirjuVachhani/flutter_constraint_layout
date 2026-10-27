import androidx.constraintlayout.core.widgets.*;
import androidx.constraintlayout.core.widgets.ConstraintAnchor.Type;
import androidx.constraintlayout.core.widgets.ConstraintWidget.DimensionBehaviour;
import androidx.constraintlayout.core.widgets.analyzer.BasicMeasure;
import androidx.constraintlayout.core.widgets.analyzer.DirectProbe;
import androidx.constraintlayout.core.widgets.Flow;
import java.io.*;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;

/**
 * Phase 0 oracle (p0-java): the baseline suite's (BL's) Java driver OpDriver,
 * extended with the view path, DirectProbe fields and TraceJava hooks.
 *
 * Core path: byte for byte BL's OpDriver (echo measurer, root.measure(level, ...)).
 * View path: the op list builds the widgets, then ViewHost (a port of the view layer's
 * onMeasure and Measurer) measures them with the content views of the `ct` ops.
 *
 *   VOpDriver serve <levels>                  stdin "id\tops" -> stdout
 *   VOpDriver batch <in> <out> <progress> <startIdx> <levels>
 *   VOpDriver probes                          ViewProbe's three probes (view path, 257)
 *
 * Output: id \t status \t geometry(level1) \t geometry(level2) ... [\t extras]
 * Formats, properties and op syntax: tool/parity/FORMATS.md (2, 4.2, 7b, 8).
 */
public class VOpDriver {
    /** Build stamp; FORMATS.md 8.8 lists what changed in each version. */
    static final String VERSION = "v2 2026-10-25 helpers GONE on the view path";
    static final boolean RES = System.getProperty("res") != null;
    static String LAST_RES = "";
    static final boolean FINALS = System.getProperty("finals") != null;
    static final int BUILDS = Integer.getInteger("builds", 1);
    static final String PATH = System.getProperty("path", "auto");
    static final boolean PROBE = System.getProperty("probe") != null;
    static final boolean DIRECT_DUMP = System.getProperty("direct") != null;
    static final boolean TRANSCRIPT = System.getProperty("transcript") != null;
    static final String TRACE_FILE = System.getProperty("trace");
    /** Wrap the echo measurer so the probe counts and records its requests. */
    static final boolean RECORD = PROBE || TRANSCRIPT;

    static DimensionBehaviour beh(String s) {
        switch (s) {
            case "F": return DimensionBehaviour.FIXED;
            case "W": return DimensionBehaviour.WRAP_CONTENT;
            case "M": return DimensionBehaviour.MATCH_CONSTRAINT;
            case "P": return DimensionBehaviour.MATCH_PARENT;
        }
        throw new IllegalArgumentException("behaviour " + s);
    }

    static Type anc(String s) {
        switch (s) {
            case "L": return Type.LEFT;
            case "R": return Type.RIGHT;
            case "T": return Type.TOP;
            case "B": return Type.BOTTOM;
            case "S": return Type.BASELINE;
            case "C": return Type.CENTER;
            case "CX": return Type.CENTER_X;
            case "CY": return Type.CENTER_Y;
        }
        throw new IllegalArgumentException("anchor " + s);
    }

    static int specMode(String s) {
        switch (s) {
            case "E": return ViewHost.EXACTLY;
            case "A": return ViewHost.AT_MOST;
            case "U": return ViewHost.UNSPECIFIED;
        }
        throw new IllegalArgumentException("spec mode " + s);
    }

    static int goneMargin(String s) {
        return s.equals("U") ? Integer.MIN_VALUE : Integer.parseInt(s);
    }

    /** BL's echo measurer, unchanged. */
    static final class Echo implements BasicMeasure.Measurer {
        static int clamp(int v, int min, int max) {
            if (min > 0 && v < min) v = min;
            if (max > 0 && v > max) v = max;
            return v;
        }

        @Override
        public void measure(ConstraintWidget widget, BasicMeasure.Measure m) {
            int w = m.horizontalBehavior == DimensionBehaviour.WRAP_CONTENT
                    ? EchoAccess.rawWidth(widget) : m.horizontalDimension;
            int h = m.verticalBehavior == DimensionBehaviour.WRAP_CONTENT
                    ? EchoAccess.rawHeight(widget) : m.verticalDimension;
            if (widget.getHorizontalDimensionBehaviour() == DimensionBehaviour.MATCH_CONSTRAINT) {
                w = clamp(w, widget.mMatchConstraintMinWidth, widget.mMatchConstraintMaxWidth);
            }
            if (widget.getVerticalDimensionBehaviour() == DimensionBehaviour.MATCH_CONSTRAINT) {
                h = clamp(h, widget.mMatchConstraintMinHeight, widget.mMatchConstraintMaxHeight);
            }
            m.measuredWidth = w;
            m.measuredHeight = h;
            m.measuredHasBaseline = widget.hasBaseline();
            m.measuredBaseline = widget.getBaselineDistance();
            widget.setMeasureRequested(false);
        }

        @Override
        public void didMeasures() {}
    }

    /** The echo measurer seen by DirectProbe (counts and transcript); same answers. */
    static final class Recording implements BasicMeasure.Measurer {
        final BasicMeasure.Measurer inner;
        final DirectProbe probe;

        Recording(BasicMeasure.Measurer inner, DirectProbe probe) {
            this.inner = inner;
            this.probe = probe;
        }

        @Override
        public void measure(ConstraintWidget widget, BasicMeasure.Measure m) {
            probe.beforeMeasure(widget, m);
            inner.measure(widget, m);
            probe.afterMeasure(widget, m, "e");
        }

        @Override
        public void didMeasures() {
            inner.didMeasures();
        }
    }

    static BasicMeasure.Measurer coreMeasurer(ProbeContainer root) {
        BasicMeasure.Measurer m = new Echo();
        return RECORD ? new Recording(m, root.probe) : m;
    }

    // ------------------------------------------------------------------------------
    // Captured stdout and stderr: BL's "EXCEPTION" check, DirectProbe's exception list
    // and the trace's X events.
    // ------------------------------------------------------------------------------

    static final class Capture extends PrintStream {
        final ByteArrayOutputStream bytes;
        final ProbeContainer root;

        Capture(ByteArrayOutputStream bytes, ProbeContainer root) {
            super(bytes, true);
            this.bytes = bytes;
            this.root = root;
        }

        Capture(ProbeContainer root) {
            this(new ByteArrayOutputStream(), root);
        }

        @Override
        public void println(String x) {
            if (x != null && x.startsWith("EXCEPTION : ")) {
                String e = x.substring("EXCEPTION : ".length());
                if (root != null) root.probe.addException(e);
                if (TRACE != null) {
                    int colon = e.indexOf(':');
                    TRACE.append("X ").append(colon < 0 ? e : e.substring(0, colon)).append('\n');
                }
            }
            super.println(x);
        }

        String text() {
            return bytes.toString();
        }
    }

    /** Adds the top stack frame of each printed exception, from captured stderr. */
    static void attachFrames(ProbeContainer root, String err) {
        if (root == null || err.isEmpty()) return;
        List<String> frames = new ArrayList<>();
        String[] lines = err.split("\n");
        for (int i = 0; i < lines.length; i++) {
            String l = lines[i];
            if (!l.startsWith("\t") && !l.startsWith("Caused by") && i + 1 < lines.length
                    && lines[i + 1].startsWith("\tat ")) {
                frames.add(lines[i + 1].substring(4).trim());
            }
        }
        root.probe.attachFrames(frames);
    }

    // ------------------------------------------------------------------------------
    // TraceJava (FORMATS.md 7b). The patched solver writes to SolverTrace.sb; the driver
    // shares the same StringBuilder for T, PS, M, X and E. Null when not tracing.
    // ------------------------------------------------------------------------------

    static StringBuilder TRACE = null;
    static Field TRACE_FIELD = null;
    static Writer TRACE_OUT = null;

    static void initTrace() throws IOException {
        if (TRACE_FILE == null) return;
        try {
            Class<?> c = Class.forName("androidx.constraintlayout.core.SolverTrace");
            TRACE_FIELD = c.getField("sb");
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(
                    "-Dtrace needs the TraceJava classes (build_trace.sh, CL_CP) first on the classpath", e);
        }
        TRACE_OUT = new BufferedWriter(new OutputStreamWriter(
                new FileOutputStream(TRACE_FILE, true), StandardCharsets.UTF_8));
    }

    static void traceBegin(String id, int level, int build) {
        if (TRACE_FIELD == null) return;
        TRACE = new StringBuilder();
        try {
            TRACE_FIELD.set(null, TRACE);
        } catch (IllegalAccessException e) {
            throw new IllegalStateException(e);
        }
        TRACE.append("T ").append(id).append(' ').append(level).append(' ').append(build).append('\n');
    }

    static void traceEnd() {
        if (TRACE_FIELD == null || TRACE == null) return;
        TRACE.append("E\n");
        try {
            TRACE_FIELD.set(null, null);
            TRACE_OUT.write(TRACE.toString());
        } catch (IllegalAccessException | IOException e) {
            throw new IllegalStateException(e);
        }
        TRACE = null;
    }

    static final Consumer<String> TRACE_SINK = s -> {
        if (TRACE != null) TRACE.append(s).append('\n');
    };

    // ------------------------------------------------------------------------------
    // Building and measuring one layout
    // ------------------------------------------------------------------------------

    /** One build of an op list. */
    static final class Built {
        ProbeContainer root;
        final Map<String, ConstraintWidget> by = new HashMap<>();
        boolean view;
        ViewHost host;
        int level;
        boolean hasSpec;
        int widthSpec;
        int heightSpec;
    }

    static final Set<String> VIEW_OPS = new HashSet<>(Arrays.asList("ct", "cspec", "cpad", "cmin", "cmax"));

    static boolean isView(String ops) {
        if (PATH.equals("view")) return true;
        if (PATH.equals("core")) return false;
        if (!PATH.equals("auto")) throw new IllegalArgumentException("path " + PATH);
        for (String op : ops.split(";")) {
            op = op.trim();
            int sp = op.indexOf(' ');
            String name = sp < 0 ? op : op.substring(0, sp);
            if (VIEW_OPS.contains(name)) return true;
        }
        return false;
    }

    static String run(String id, String ops, int level, int build, boolean view) {
        traceBegin(id, level, build);
        try {
            Built b = build(ops, level, view);
            return measureAndReport(b, level);
        } finally {
            traceEnd();
        }
    }

    static ViewHost.ContentView newView(Built b, ConstraintWidget w) {
        ViewHost.ContentView v = new ViewHost.ContentView();
        if (b.view) w.setCompanionWidget(v);
        return v;
    }

    /** Replays [ops] into a new container (no final measure). */
    static Built build(String ops, int level, boolean view) {
        Built b = new Built();
        b.view = view;
        b.level = level;
        Map<String, ConstraintWidget> by = b.by;
        ProbeContainer root = null;
        for (String op : ops.split(";")) {
            op = op.trim();
            if (op.isEmpty()) continue;
            String[] t = op.split(" ");
            switch (t[0]) {
                case "R":
                    root = new ProbeContainer(0, 0, Integer.parseInt(t[1]), Integer.parseInt(t[2]));
                    root.setDebugName("root");
                    root.probe.trace = TRACE_FIELD != null ? TRACE_SINK : null;
                    root.probe.recordTranscript = TRANSCRIPT;
                    by.put("root", root);
                    b.root = root;
                    if (view) {
                        b.host = new ViewHost(root, root.probe);
                        b.host.mOptimizationLevel = level;
                    }
                    break;
                case "rtl": root.setRtl(true); break;
                case "wrapw": root.setHorizontalDimensionBehaviour(DimensionBehaviour.WRAP_CONTENT); break;
                case "wraph": root.setVerticalDimensionBehaviour(DimensionBehaviour.WRAP_CONTENT); break;
                case "w": {
                    ConstraintWidget w = new ConstraintWidget(Integer.parseInt(t[2]), Integer.parseInt(t[3]));
                    w.setDebugName(t[1]);
                    by.put(t[1], w);
                    newView(b, w);
                    break;
                }
                case "b": {
                    Barrier x = new Barrier();
                    x.setDebugName(t[1]);
                    by.put(t[1], x);
                    break;
                }
                case "g": {
                    Guideline g = new Guideline();
                    g.setDebugName(t[1]);
                    by.put(t[1], g);
                    break;
                }
                case "add": root.add(by.get(t[1])); break;
                case "bt": ((Barrier) by.get(t[1])).setBarrierType(Integer.parseInt(t[2])); break;
                case "bm": ((Barrier) by.get(t[1])).setMargin(Integer.parseInt(t[2])); break;
                case "bg": ((Barrier) by.get(t[1])).setAllowsGoneWidget(t[2].equals("1")); break;
                case "ref": ((HelperWidget) by.get(t[1])).add(by.get(t[2])); break;
                case "go": ((Guideline) by.get(t[1])).setOrientation(Integer.parseInt(t[2])); break;
                case "gb": ((Guideline) by.get(t[1])).setGuideBegin(Integer.parseInt(t[2])); break;
                case "ge": ((Guideline) by.get(t[1])).setGuideEnd(Integer.parseInt(t[2])); break;
                case "gp": ((Guideline) by.get(t[1])).setGuidePercent(Float.parseFloat(t[2])); break;
                case "c":
                    by.get(t[1]).connect(anc(t[2]), by.get(t[3]), anc(t[4]), Integer.parseInt(t[5]));
                    break;
                case "x": by.get(t[1]).getAnchor(anc(t[2])).reset(); break;
                case "hb": by.get(t[1]).setHorizontalDimensionBehaviour(beh(t[2])); break;
                case "vb": by.get(t[1]).setVerticalDimensionBehaviour(beh(t[2])); break;
                case "hm":
                    by.get(t[1]).setHorizontalMatchStyle(Integer.parseInt(t[2]), Integer.parseInt(t[3]),
                            Integer.parseInt(t[4]), Float.parseFloat(t[5]));
                    break;
                case "vm":
                    by.get(t[1]).setVerticalMatchStyle(Integer.parseInt(t[2]), Integer.parseInt(t[3]),
                            Integer.parseInt(t[4]), Float.parseFloat(t[5]));
                    break;
                case "mw": by.get(t[1]).setMinWidth(Integer.parseInt(t[2])); break;
                case "mh": by.get(t[1]).setMinHeight(Integer.parseInt(t[2])); break;
                case "hx": by.get(t[1]).setHorizontalBiasPercent(Float.parseFloat(t[2])); break;
                case "vx": by.get(t[1]).setVerticalBiasPercent(Float.parseFloat(t[2])); break;
                case "gm": by.get(t[1]).setGoneMargin(anc(t[2]), Integer.parseInt(t[3])); break;
                case "v": by.get(t[1]).setVisibility(Integer.parseInt(t[2])); break;
                case "bl": by.get(t[1]).setBaselineDistance(Integer.parseInt(t[2])); break;
                case "hc": by.get(t[1]).setHorizontalChainStyle(Integer.parseInt(t[2])); break;
                case "vc": by.get(t[1]).setVerticalChainStyle(Integer.parseInt(t[2])); break;
                case "hw": by.get(t[1]).setHorizontalWeight(Float.parseFloat(t[2])); break;
                case "vw": by.get(t[1]).setVerticalWeight(Float.parseFloat(t[2])); break;
                case "ra": by.get(t[1]).setDimensionRatio(Float.parseFloat(t[2]), Integer.parseInt(t[3])); break;
                // verify-final additions (ops.dart mirrors them).
                case "hbl": by.get(t[1]).setHasBaseline(t[2].equals("1")); break;
                case "sw": by.get(t[1]).setWidth(Integer.parseInt(t[2])); break;
                case "sh": by.get(t[1]).setHeight(Integer.parseInt(t[2])); break;
                case "sx": by.get(t[1]).setX(Integer.parseInt(t[2])); break;
                case "sy": by.get(t[1]).setY(Integer.parseInt(t[2])); break;
                case "ipr": VfAccess.inPlaceReset(by.get(t[1])); break;
                case "L":
                    if (view) {
                        viewMeasure(b);
                    } else {
                        boolean ww = root.getHorizontalDimensionBehaviour() == DimensionBehaviour.WRAP_CONTENT;
                        boolean wh = root.getVerticalDimensionBehaviour() == DimensionBehaviour.WRAP_CONTENT;
                        root.setMeasurer(coreMeasurer(root));
                        root.setOptimizationLevel(level);
                        root.probe.beginMeasure();
                        PrintStream sv = System.out;
                        PrintStream se = System.err;
                        System.setOut(new Capture(root));
                        System.setErr(new PrintStream(new ByteArrayOutputStream()));
                        try {
                            root.measure(level, ww ? BasicMeasure.AT_MOST : BasicMeasure.EXACTLY, root.getWidth(),
                                    wh ? BasicMeasure.AT_MOST : BasicMeasure.EXACTLY, root.getHeight(), 0, 0, 0, 0);
                        } finally {
                            System.setOut(sv);
                            System.setErr(se);
                        }
                    }
                    break;
                case "cw": root.setWidth(Integer.parseInt(t[1])); break;
                case "ch": root.setHeight(Integer.parseInt(t[1])); break;
                case "fixw": root.setHorizontalDimensionBehaviour(DimensionBehaviour.FIXED); break;
                case "fixh": root.setVerticalDimensionBehaviour(DimensionBehaviour.FIXED); break;
                case "ltr": root.setRtl(false); break;
                case "rm": root.remove(by.get(t[1])); break;
                case "rereg": VfAccess.rereg(root); break;
                case "adeps": VfAccess.androidDeps(root); break;
                // p0 ops (FORMATS.md 4.2)
                case "ct": {
                    ConstraintWidget w = by.get(t[1]);
                    if (w == null) throw new IllegalArgumentException("ct: unknown " + t[1]);
                    if (view) {
                        ViewHost.ContentView v = ViewHost.viewOf(w);
                        if (v == null) v = newView(b, w);
                        v.setContent(t[2], Integer.parseInt(t[3]), Integer.parseInt(t[4]), Integer.parseInt(t[5]));
                    }
                    break;
                }
                case "cc":
                    by.get(t[1]).connectCircularConstraint(by.get(t[2]), Float.parseFloat(t[3]), Integer.parseInt(t[4]));
                    break;
                case "fl": {
                    Flow f = new Flow();
                    f.setDebugName(t[1]);
                    by.put(t[1], f);
                    ViewHost.ContentView v = newView(b, f);
                    v.kind = ViewHost.ContentView.FLOW;
                    v.flow = f;
                    break;
                }
                case "fo": ((Flow) by.get(t[1])).setOrientation(Integer.parseInt(t[2])); break;
                case "fwm": ((Flow) by.get(t[1])).setWrapMode(Integer.parseInt(t[2])); break;
                case "fhs": ((Flow) by.get(t[1])).setHorizontalStyle(Integer.parseInt(t[2])); break;
                case "fvs": ((Flow) by.get(t[1])).setVerticalStyle(Integer.parseInt(t[2])); break;
                case "fhb": ((Flow) by.get(t[1])).setHorizontalBias(Float.parseFloat(t[2])); break;
                case "fvb": ((Flow) by.get(t[1])).setVerticalBias(Float.parseFloat(t[2])); break;
                case "fha": ((Flow) by.get(t[1])).setHorizontalAlign(Integer.parseInt(t[2])); break;
                case "fva": ((Flow) by.get(t[1])).setVerticalAlign(Integer.parseInt(t[2])); break;
                case "fhg": ((Flow) by.get(t[1])).setHorizontalGap(Integer.parseInt(t[2])); break;
                case "fvg": ((Flow) by.get(t[1])).setVerticalGap(Integer.parseInt(t[2])); break;
                case "fme": ((Flow) by.get(t[1])).setMaxElementsWrap(Integer.parseInt(t[2])); break;
                case "fpad": {
                    Flow f = (Flow) by.get(t[1]);
                    f.setPaddingLeft(Integer.parseInt(t[2]));
                    f.setPaddingTop(Integer.parseInt(t[3]));
                    f.setPaddingRight(Integer.parseInt(t[4]));
                    f.setPaddingBottom(Integer.parseInt(t[5]));
                    break;
                }
                case "frtl": ((VirtualLayout) by.get(t[1])).applyRtl(t[2].equals("1")); break;
                case "fset": flowSet((Flow) by.get(t[1]), t[2], t[3]); break;
                case "cspec":
                    b.hasSpec = true;
                    b.widthSpec = ViewHost.makeMeasureSpec(Integer.parseInt(t[2]), specMode(t[1]));
                    b.heightSpec = ViewHost.makeMeasureSpec(Integer.parseInt(t[4]), specMode(t[3]));
                    break;
                case "cpad":
                    if (view) {
                        b.host.mPaddingLeft = Integer.parseInt(t[1]);
                        b.host.mPaddingTop = Integer.parseInt(t[2]);
                        b.host.mPaddingRight = Integer.parseInt(t[3]);
                        b.host.mPaddingBottom = Integer.parseInt(t[4]);
                    }
                    break;
                case "cmin":
                    if (view) {
                        b.host.mMinWidth = Integer.parseInt(t[1]);
                        b.host.mMinHeight = Integer.parseInt(t[2]);
                    }
                    break;
                case "cmax":
                    if (view) {
                        b.host.mMaxWidth = Integer.parseInt(t[1]);
                        b.host.mMaxHeight = Integer.parseInt(t[2]);
                    }
                    break;
                // extra ops, VOpDriver's alone (not in FORMATS.md; p0-java)
                case "ic":
                    by.get(t[1]).immediateConnect(anc(t[2]), by.get(t[3]), anc(t[4]),
                            Integer.parseInt(t[5]), goneMargin(t[6]));
                    break;
                case "sbl": {
                    // ConstraintLayout.setWidgetBaseline (CL 1598-1620)
                    ConstraintWidget w = by.get(t[1]);
                    ConstraintWidget target = by.get(t[2]);
                    Type type = anc(t[3]);
                    if (type == Type.BASELINE) target.setHasBaseline(true);
                    w.getAnchor(Type.BASELINE).connect(target.getAnchor(type),
                            Integer.parseInt(t[4]), goneMargin(t[5]), true);
                    w.setHasBaseline(true);
                    w.getAnchor(Type.TOP).reset();
                    w.getAnchor(Type.BOTTOM).reset();
                    break;
                }
                case "rs": by.get(t[1]).setDimensionRatio(t[2]); break;
                case "wb": by.get(t[1]).setWrapBehaviorInParent(Integer.parseInt(t[2])); break;
                default: throw new IllegalArgumentException("op " + op);
            }
        }
        return b;
    }

    static void flowSet(Flow f, String prop, String v) {
        switch (prop) {
            case "fhs1": f.setFirstHorizontalStyle(Integer.parseInt(v)); break;
            case "fvs1": f.setFirstVerticalStyle(Integer.parseInt(v)); break;
            case "fhsl": f.setLastHorizontalStyle(Integer.parseInt(v)); break;
            case "fvsl": f.setLastVerticalStyle(Integer.parseInt(v)); break;
            case "fhb1": f.setFirstHorizontalBias(Float.parseFloat(v)); break;
            case "fvb1": f.setFirstVerticalBias(Float.parseFloat(v)); break;
            case "fhbl": f.setLastHorizontalBias(Float.parseFloat(v)); break;
            case "fvbl": f.setLastVerticalBias(Float.parseFloat(v)); break;
            case "pads": f.setPaddingStart(Integer.parseInt(v)); break;
            case "pade": f.setPaddingEnd(Integer.parseInt(v)); break;
            default: throw new IllegalArgumentException("fset " + prop);
        }
    }

    /** The specs onMeasure receives: cspec, else FIXED -> E(size), WRAP -> U(0). */
    static int[] specsOf(Built b) {
        if (b.hasSpec) return new int[] {b.widthSpec, b.heightSpec};
        ProbeContainer root = b.root;
        int ws = root.getHorizontalDimensionBehaviour() == DimensionBehaviour.WRAP_CONTENT
                ? ViewHost.makeMeasureSpec(0, ViewHost.UNSPECIFIED)
                : ViewHost.makeMeasureSpec(root.getWidth(), ViewHost.EXACTLY);
        int hs = root.getVerticalDimensionBehaviour() == DimensionBehaviour.WRAP_CONTENT
                ? ViewHost.makeMeasureSpec(0, ViewHost.UNSPECIFIED)
                : ViewHost.makeMeasureSpec(root.getHeight(), ViewHost.EXACTLY);
        return new int[] {ws, hs};
    }

    /** One onMeasure of the layout view (the `L` op on the view path). */
    static void viewMeasure(Built b) {
        int[] specs = specsOf(b);
        b.root.probe.beginMeasure();
        PrintStream sv = System.out;
        PrintStream se = System.err;
        System.setOut(new Capture(b.root));
        System.setErr(new PrintStream(new ByteArrayOutputStream()));
        try {
            b.host.measure(specs[0], specs[1]);
        } finally {
            System.setOut(sv);
            System.setErr(se);
        }
    }

    static String measureAndReport(Built b, int level) {
        ProbeContainer root = b.root;
        boolean wrapW = root.getHorizontalDimensionBehaviour() == DimensionBehaviour.WRAP_CONTENT;
        boolean wrapH = root.getVerticalDimensionBehaviour() == DimensionBehaviour.WRAP_CONTENT;
        int cw = root.getWidth(), ch = root.getHeight();
        int[] specs = b.view ? specsOf(b) : null;
        if (!b.view) {
            root.setMeasurer(coreMeasurer(root));
            root.setOptimizationLevel(level);
        }
        root.probe.beginMeasure();
        PrintStream saved = System.out;
        PrintStream savedErr = System.err;
        Capture captured = new Capture(root);
        ByteArrayOutputStream errBytes = new ByteArrayOutputStream();
        System.setOut(captured);
        System.setErr(new PrintStream(errBytes, true));
        String status = "ok";
        try {
            if (b.view) {
                b.host.measure(specs[0], specs[1]);
            } else {
                root.measure(level, wrapW ? BasicMeasure.AT_MOST : BasicMeasure.EXACTLY, cw,
                        wrapH ? BasicMeasure.AT_MOST : BasicMeasure.EXACTLY, ch, 0, 0, 0, 0);
            }
        } catch (StackOverflowError e) {
            status = "SO";
        } catch (Throwable e) {
            status = "EXC:" + e.toString().replace('\t', ' ').replace('\n', ' ');
        } finally {
            System.setOut(saved);
            System.setErr(savedErr);
        }
        attachFrames(root, errBytes.toString());
        // verify-final: the solver loop's caught exceptions (printed, as the
        // Dart port prints them).
        if (status.equals("ok") && captured.text().contains("EXCEPTION")) {
            status = "ok-printed";
        }
        StringBuilder sb = new StringBuilder();
        if (!status.equals("ok")) sb.append("!").append(status).append(" | ");
        if (RES && level == 257) {
            // Which axes the Direct pass resolved (final values survive the solve).
            StringBuilder r = new StringBuilder("RES");
            for (ConstraintWidget w : root.getChildren()) {
                boolean h, v;
                if (w instanceof Guideline) {
                    Guideline g = (Guideline) w;
                    boolean f = g.getAnchor().hasFinalValue();
                    h = g.getOrientation() == Guideline.VERTICAL && f;
                    v = g.getOrientation() == Guideline.HORIZONTAL && f;
                } else {
                    h = w.mLeft.hasFinalValue() && w.mRight.hasFinalValue();
                    v = w.mTop.hasFinalValue() && w.mBottom.hasFinalValue();
                }
                r.append(' ').append(w.getDebugName()).append(':').append(h ? 'h' : '-').append(v ? 'v' : '-');
                if (FINALS && !(w instanceof Guideline)) {
                    if (h) r.append('(').append(w.mLeft.getFinalValue()).append(',').append(w.mRight.getFinalValue()).append(')');
                    if (v) r.append('[').append(w.mTop.getFinalValue()).append(',').append(w.mBottom.getFinalValue()).append(']');
                }
            }
            LAST_RES = r.toString();
        }
        if (b.view) {
            sb.append("root ").append(b.host.getMeasuredWidth()).append(" x ").append(b.host.getMeasuredHeight());
        } else {
            sb.append("root ").append(root.getWidth()).append(" x ").append(root.getHeight());
        }
        for (ConstraintWidget w : root.getChildren()) {
            // Core path: BL's rule. View path: onLayout's (CL 2019-2028), which places
            // GONE guidelines and helpers (barriers, VirtualLayouts) too.
            boolean placed = b.view ? (w instanceof Guideline || w instanceof HelperWidget)
                    : w instanceof Barrier;
            if (w.getVisibility() == ConstraintWidget.GONE && !placed) {
                sb.append(" | ").append(w.getDebugName()).append(": gone, ")
                        .append(w.getWidth()).append(" x ").append(w.getHeight());
            } else {
                sb.append(" | ").append(w.getDebugName()).append(": (").append(w.getX()).append(", ")
                        .append(w.getY()).append(") ").append(w.getWidth()).append(" x ").append(w.getHeight());
            }
        }
        LAST_EXTRAS.setLength(0);
        if (PROBE) LAST_EXTRAS.append('\t').append(root.probe.summaryField(level));
        if (DIRECT_DUMP) LAST_EXTRAS.append('\t').append(root.probe.directField(level));
        if (TRANSCRIPT) LAST_EXTRAS.append('\t').append(root.probe.transcriptField(level));
        return sb.toString();
    }

    /** The extra fields of the last measureAndReport (FORMATS.md 8.2). */
    static final StringBuilder LAST_EXTRAS = new StringBuilder();

    static final ExecutorService POOL = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r);
        t.setDaemon(true);
        return t;
    });

    static String runAll(String id, String ops, int[] levels, long timeoutMs) {
        Future<String> f = POOL.submit(() -> {
            boolean view = isView(ops);
            StringBuilder sb = new StringBuilder("ok");
            StringBuilder extras = new StringBuilder();
            for (int level : levels) {
                String g = run(id, ops, level, 0, view);
                extras.append(LAST_EXTRAS);
                if (level == 257 && BUILDS > 1) {
                    // Direct walks HashSet dependents, so the result can depend
                    // on identity hash codes: more builds expose that.
                    boolean nd = false;
                    for (int k = 1; k < BUILDS; k++) {
                        String again = run(id, ops, level, k, view);
                        if (!again.equals(g)) nd = true;
                    }
                    if (nd) {
                        sb.setLength(0);
                        sb.append("ND");
                    }
                }
                sb.append('\t').append(g);
            }
            sb.append(extras);
            if (RES) sb.append('\t').append(LAST_RES);
            return sb.toString();
        });
        try {
            return f.get(timeoutMs, TimeUnit.MILLISECONDS);
        } catch (TimeoutException e) {
            return null;
        } catch (Exception e) {
            return "EXC:" + e.toString().replace('\t', ' ').replace('\n', ' ');
        }
    }

    static int[] levels(String s) {
        String[] p = s.split(",");
        int[] r = new int[p.length];
        for (int i = 0; i < p.length; i++) r[i] = Integer.parseInt(p[i]);
        return r;
    }

    // ------------------------------------------------------------------------------
    // ViewProbe's three probes (FORMATS.md 8.1 and 8.7)
    // ------------------------------------------------------------------------------

    static final String[][] PROBES = {
        {"match x match, one link per axis", "D",
            "R 400 800;w D 0 0;add D;hb D M;vb D M;c D L root L 10;c D T root T 10;"
                + "ct D box 300 50 -1;cspec E 400 E 800"},
        {"matchParent x wrap text", "A",
            "R 400 800;w A 0 0;add A;hb A P;vb A W;c A T root T 10;ct A text 1000 20 -1;cspec E 400 E 800"},
        {"fixed-size baseline pair", "B C",
            "R 400 800;w B 100 40;w C 100 20;add B;add C;hbl B 1;hbl C 1;ct B box 100 40 30;"
                + "ct C box 100 20 15;c B L root L 0;c B T root T 100;c C L B R 0;c C S B S 0;"
                + "cspec E 400 E 800"},
    };

    static String frame(ConstraintWidget w) {
        return w.getDebugName() + "=(" + w.getX() + "," + w.getY() + "," + w.getWidth() + "x" + w.getHeight() + ")";
    }

    static void probes() {
        for (String[] p : PROBES) {
            Built b = build(p[2], 257, true);
            measureAndReport(b, 257);
            StringBuilder sb = new StringBuilder(p[0]).append(':');
            for (String n : p[1].split(" ")) sb.append(' ').append(frame(b.by.get(n)));
            System.out.println(sb);
        }
    }

    public static void main(String[] args) throws Exception {
        long timeout = Long.parseLong(System.getProperty("timeoutMs", "4000"));
        if (args[0].equals("probes")) {
            probes();
            return;
        }
        if (args[0].equals("version")) {
            System.out.println(VERSION);
            return;
        }
        initTrace();
        if (args[0].equals("serve")) {
            int[] lv = levels(args[1]);
            BufferedReader in = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
            PrintStream out = new PrintStream(new FileOutputStream(FileDescriptor.out), true, "UTF-8");
            String line;
            while ((line = in.readLine()) != null) {
                if (line.isEmpty() || line.startsWith("#")) continue;
                int tab = line.indexOf('\t');
                String id = line.substring(0, tab);
                String r = runAll(id, line.substring(line.lastIndexOf('\t') + 1), lv, timeout);
                if (r == null) {
                    out.println(id + "\tHANG");
                    out.flush();
                    if (TRACE_OUT != null) TRACE_OUT.flush();
                    System.exit(3);
                }
                out.println(id + "\t" + r);
                out.flush();
                if (TRACE_OUT != null) TRACE_OUT.flush();
            }
            if (TRACE_OUT != null) TRACE_OUT.close();
            return;
        }
        // batch
        String inFile = args[1], outFile = args[2], progress = args[3];
        long start = Long.parseLong(args[4]);
        int[] lv = levels(args[5]);
        try (BufferedReader in = new BufferedReader(new FileReader(inFile));
             Writer out = new BufferedWriter(new FileWriter(outFile, true))) {
            String line;
            long idx = -1;
            while ((line = in.readLine()) != null) {
                idx++;
                if (idx < start || line.isEmpty() || line.startsWith("#")) continue;
                int tab = line.indexOf('\t');
                String id = line.substring(0, tab);
                // ops are the last field
                String ops = line.substring(line.lastIndexOf('\t') + 1);
                try (Writer p = new FileWriter(progress)) {
                    p.write(Long.toString(idx));
                }
                String r = runAll(id, ops, lv, timeout);
                if (r == null) {
                    out.write(id + "\tHANG\n");
                    out.flush();
                    if (TRACE_OUT != null) TRACE_OUT.flush();
                    System.exit(3);
                }
                out.write(id + "\t" + r + "\n");
            }
        }
        if (TRACE_OUT != null) TRACE_OUT.close();
        try (Writer p = new FileWriter(progress)) {
            p.write("DONE");
        }
        System.exit(0);
    }
}
