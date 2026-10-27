package oracle;

import androidx.constraintlayout.core.widgets.Barrier;
import androidx.constraintlayout.core.widgets.ConstraintAnchor;
import androidx.constraintlayout.core.widgets.ConstraintAnchor.Type;
import androidx.constraintlayout.core.widgets.ConstraintWidget;
import androidx.constraintlayout.core.widgets.ConstraintWidget.DimensionBehaviour;
import androidx.constraintlayout.core.widgets.ConstraintWidgetContainer;
import androidx.constraintlayout.core.widgets.Flow;
import androidx.constraintlayout.core.widgets.Guideline;
import androidx.constraintlayout.core.widgets.HelperWidget;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Replays a corpus op list (FORMATS.md section 4) on the pinned core, the way
 * VOpDriver builds its container, and keeps what the views need on top of the
 * core state: the content of each widget, the container's view settings and
 * every Flow setter. The final core state is then read back by RoboViews.
 *
 * An op list whose final state cannot be written as LayoutParams gets an
 * {@link #unmapped} reason instead (FORMATS.md section 10).
 */
final class RoboOps {
    /** A widget's content (ct op). */
    static final class Content {
        final int kind, w, h, baseline;

        Content(int kind, int w, int h, int baseline) {
            this.kind = kind;
            this.w = w;
            this.h = h;
            this.baseline = baseline;
        }
    }

    /** Every Flow setter the op list called, in order, as (setter, value). */
    static final class FlowConfig {
        final List<String[]> calls = new ArrayList<>();
    }

    ConstraintWidgetContainer root;
    final Map<String, ConstraintWidget> byName = new HashMap<>();
    final Map<String, Content> content = new HashMap<>();
    final Map<String, FlowConfig> flows = new LinkedHashMap<>();
    final Map<String, Boolean> flowRtl = new HashMap<>();
    /** cspec: {wMode, wSize, hMode, hSize} with modes 'E', 'A', 'U'; null when absent. */
    String[] cspec;
    int[] cpad;
    int[] cmin;
    int[] cmax;
    boolean anyContent;
    String unmapped;
    /** In-place mode (a state of a T-inplace sequence): ipr resets anchors, L is a cut. */
    boolean inplace;

    static DimensionBehaviour beh(String s) {
        switch (s) {
            case "F": return DimensionBehaviour.FIXED;
            case "W": return DimensionBehaviour.WRAP_CONTENT;
            case "M": return DimensionBehaviour.MATCH_CONSTRAINT;
            case "P": return DimensionBehaviour.MATCH_PARENT;
            default: throw new IllegalArgumentException("behaviour " + s);
        }
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
            default: throw new IllegalArgumentException("anchor " + s);
        }
    }

    private void unmap(String reason) {
        if (unmapped == null) unmapped = reason;
    }

    private ConstraintWidget n(String name) {
        ConstraintWidget w = byName.get(name);
        if (w == null) throw new IllegalArgumentException("unknown widget " + name);
        return w;
    }

    private FlowConfig flow(String name) {
        FlowConfig f = flows.get(name);
        if (f == null) throw new IllegalArgumentException("not a flow " + name);
        return f;
    }

    static int gone(String s) {
        return s.equals("U") ? Integer.MIN_VALUE : Integer.parseInt(s);
    }

    /** Replays [ops] (the last field of a corpus line). */
    static RoboOps replay(String ops) {
        return replay(ops.split(";"), Integer.MAX_VALUE, false);
    }

    /** Replays the first [cut] ops of [list]; in-place mode for sequence states. */
    static RoboOps replay(String[] list, int cut, boolean inplace) {
        RoboOps r = new RoboOps();
        r.inplace = inplace;
        for (int i = 0; i < list.length && i < cut; i++) {
            String op = list[i].trim();
            if (op.isEmpty()) continue;
            r.apply(op.split(" "));
        }
        if (!r.anyContent) r.unmap("nocontent");
        if (r.unmapped == null) r.checkFlowRtl();
        return r;
    }

    /**
     * The states of an in-place sequence: the op list cut before each L, then
     * the whole list (a list without L gives one state).
     */
    static java.util.List<RoboOps> states(String ops) {
        String[] list = ops.split(";");
        java.util.List<RoboOps> out = new java.util.ArrayList<>();
        for (int i = 0; i < list.length; i++) {
            if (list[i].trim().equals("L")) out.add(replay(list, i, true));
        }
        out.add(replay(list, list.length, true));
        return out;
    }

    private void checkFlowRtl() {
        for (Map.Entry<String, Boolean> e : flowRtl.entrySet()) {
            if (e.getValue() != root.isRtl()) unmap("flowrtl");
        }
    }

    private void apply(String[] t) {
        switch (t[0]) {
            case "R":
                root = new ConstraintWidgetContainer(0, 0, Integer.parseInt(t[1]), Integer.parseInt(t[2]));
                root.setDebugName("root");
                byName.put("root", root);
                break;
            case "rtl": root.setRtl(true); break;
            case "ltr": root.setRtl(false); break;
            case "wrapw": root.setHorizontalDimensionBehaviour(DimensionBehaviour.WRAP_CONTENT); break;
            case "wraph": root.setVerticalDimensionBehaviour(DimensionBehaviour.WRAP_CONTENT); break;
            case "fixw": root.setHorizontalDimensionBehaviour(DimensionBehaviour.FIXED); break;
            case "fixh": root.setVerticalDimensionBehaviour(DimensionBehaviour.FIXED); break;
            case "cw": root.setWidth(Integer.parseInt(t[1])); break;
            case "ch": root.setHeight(Integer.parseInt(t[1])); break;
            case "w": {
                ConstraintWidget w = new ConstraintWidget(Integer.parseInt(t[2]), Integer.parseInt(t[3]));
                w.setDebugName(t[1]);
                byName.put(t[1], w);
                break;
            }
            case "b": {
                Barrier b = new Barrier();
                b.setDebugName(t[1]);
                byName.put(t[1], b);
                break;
            }
            case "g": {
                Guideline g = new Guideline();
                g.setDebugName(t[1]);
                byName.put(t[1], g);
                break;
            }
            case "fl": {
                Flow f = new Flow();
                f.setDebugName(t[1]);
                byName.put(t[1], f);
                flows.put(t[1], new FlowConfig());
                break;
            }
            case "add": root.add(n(t[1])); break;
            case "rm": unmap("op:rm"); root.remove(n(t[1])); break;
            case "bt": ((Barrier) n(t[1])).setBarrierType(Integer.parseInt(t[2])); break;
            case "bm": ((Barrier) n(t[1])).setMargin(Integer.parseInt(t[2])); break;
            case "bg": ((Barrier) n(t[1])).setAllowsGoneWidget(t[2].equals("1")); break;
            case "ref": ((HelperWidget) n(t[1])).add(n(t[2])); break;
            case "go": ((Guideline) n(t[1])).setOrientation(Integer.parseInt(t[2])); break;
            case "gb": ((Guideline) n(t[1])).setGuideBegin(Integer.parseInt(t[2])); break;
            case "ge": ((Guideline) n(t[1])).setGuideEnd(Integer.parseInt(t[2])); break;
            case "gp": ((Guideline) n(t[1])).setGuidePercent(Float.parseFloat(t[2])); break;
            case "c":
                n(t[1]).connect(anc(t[2]), n(t[3]), anc(t[4]), Integer.parseInt(t[5]));
                break;
            case "ic":
                n(t[1]).immediateConnect(anc(t[2]), n(t[3]), anc(t[4]), Integer.parseInt(t[5]), gone(t[6]));
                break;
            case "sbl": {
                // setWidgetBaseline (CL 1598-1620): the baseline connect is
                // forced, and the widget's top and bottom are reset.
                ConstraintWidget w = n(t[1]);
                ConstraintWidget target = n(t[2]);
                Type type = anc(t[3]);
                if (type == Type.BASELINE) target.setHasBaseline(true);
                w.getAnchor(Type.BASELINE).connect(target.getAnchor(type), Integer.parseInt(t[4]), gone(t[5]), true);
                w.setHasBaseline(true);
                w.getAnchor(Type.TOP).reset();
                w.getAnchor(Type.BOTTOM).reset();
                break;
            }
            case "x": n(t[1]).getAnchor(anc(t[2])).reset(); break;
            case "hb": n(t[1]).setHorizontalDimensionBehaviour(beh(t[2])); break;
            case "vb": n(t[1]).setVerticalDimensionBehaviour(beh(t[2])); break;
            case "hm":
                n(t[1]).setHorizontalMatchStyle(Integer.parseInt(t[2]), Integer.parseInt(t[3]),
                        Integer.parseInt(t[4]), Float.parseFloat(t[5]));
                break;
            case "vm":
                n(t[1]).setVerticalMatchStyle(Integer.parseInt(t[2]), Integer.parseInt(t[3]),
                        Integer.parseInt(t[4]), Float.parseFloat(t[5]));
                break;
            case "mw": unmap("childmin"); n(t[1]).setMinWidth(Integer.parseInt(t[2])); break;
            case "mh": unmap("childmin"); n(t[1]).setMinHeight(Integer.parseInt(t[2])); break;
            case "hx": n(t[1]).setHorizontalBiasPercent(Float.parseFloat(t[2])); break;
            case "vx": n(t[1]).setVerticalBiasPercent(Float.parseFloat(t[2])); break;
            case "gm": n(t[1]).setGoneMargin(anc(t[2]), Integer.parseInt(t[3])); break;
            case "v": n(t[1]).setVisibility(Integer.parseInt(t[2])); break;
            case "bl": n(t[1]).setBaselineDistance(Integer.parseInt(t[2])); break;
            case "hc": n(t[1]).setHorizontalChainStyle(Integer.parseInt(t[2])); break;
            case "vc": n(t[1]).setVerticalChainStyle(Integer.parseInt(t[2])); break;
            case "hw": n(t[1]).setHorizontalWeight(Float.parseFloat(t[2])); break;
            case "vw": n(t[1]).setVerticalWeight(Float.parseFloat(t[2])); break;
            case "ra": n(t[1]).setDimensionRatio(Float.parseFloat(t[2]), Integer.parseInt(t[3])); break;
            case "rs": n(t[1]).setDimensionRatio(t[2]); break;
            case "wb": n(t[1]).setWrapBehaviorInParent(Integer.parseInt(t[2])); break;
            case "hbl": n(t[1]).setHasBaseline(t[2].equals("1")); break;
            case "sw": n(t[1]).setWidth(Integer.parseInt(t[2])); break;
            case "sh": n(t[1]).setHeight(Integer.parseInt(t[2])); break;
            case "sx": n(t[1]).setX(Integer.parseInt(t[2])); break;
            case "sy": n(t[1]).setY(Integer.parseInt(t[2])); break;
            case "ipr": if (!inplace) unmap("inplace"); n(t[1]).resetAnchors(); break;
            case "iprest": if (!inplace) unmap("inplace"); break;
            case "rereg": case "adeps": break; // dependents only; the views build their own
            case "L": if (!inplace) unmap("inplace"); break;
            case "ct": {
                int kind;
                switch (t[2]) {
                    case "box": kind = ContentView.BOX; break;
                    case "text": kind = ContentView.TEXT; break;
                    case "none": kind = ContentView.NONE; break;
                    default: throw new IllegalArgumentException("content kind " + t[2]);
                }
                content.put(t[1], new Content(kind, Integer.parseInt(t[3]), Integer.parseInt(t[4]), Integer.parseInt(t[5])));
                anyContent = true;
                break;
            }
            case "cc":
                n(t[1]).connectCircularConstraint(n(t[2]), Float.parseFloat(t[3]), Integer.parseInt(t[4]));
                break;
            case "fo": flowCall(t, "orientation"); ((Flow) n(t[1])).setOrientation(Integer.parseInt(t[2])); break;
            case "fwm": flowCall(t, "wrapMode"); ((Flow) n(t[1])).setWrapMode(Integer.parseInt(t[2])); break;
            case "fhs": flowCall(t, "hStyle"); ((Flow) n(t[1])).setHorizontalStyle(Integer.parseInt(t[2])); break;
            case "fvs": flowCall(t, "vStyle"); ((Flow) n(t[1])).setVerticalStyle(Integer.parseInt(t[2])); break;
            case "fhb": flowCall(t, "hBias"); ((Flow) n(t[1])).setHorizontalBias(Float.parseFloat(t[2])); break;
            case "fvb": flowCall(t, "vBias"); ((Flow) n(t[1])).setVerticalBias(Float.parseFloat(t[2])); break;
            case "fha": flowCall(t, "hAlign"); ((Flow) n(t[1])).setHorizontalAlign(Integer.parseInt(t[2])); break;
            case "fva": flowCall(t, "vAlign"); ((Flow) n(t[1])).setVerticalAlign(Integer.parseInt(t[2])); break;
            case "fhg": flowCall(t, "hGap"); ((Flow) n(t[1])).setHorizontalGap(Integer.parseInt(t[2])); break;
            case "fvg": flowCall(t, "vGap"); ((Flow) n(t[1])).setVerticalGap(Integer.parseInt(t[2])); break;
            case "fme": flowCall(t, "maxElements"); ((Flow) n(t[1])).setMaxElementsWrap(Integer.parseInt(t[2])); break;
            case "fpad": {
                Flow f = (Flow) n(t[1]);
                f.setPaddingLeft(Integer.parseInt(t[2]));
                f.setPaddingTop(Integer.parseInt(t[3]));
                f.setPaddingRight(Integer.parseInt(t[4]));
                f.setPaddingBottom(Integer.parseInt(t[5]));
                flow(t[1]).calls.add(new String[] {"pad", t[2], t[3], t[4], t[5]});
                break;
            }
            case "frtl":
                flowRtl.put(t[1], t[2].equals("1"));
                ((Flow) n(t[1])).applyRtl(t[2].equals("1"));
                break;
            case "fset": fset(t); break;
            case "cspec": cspec = new String[] {t[1], t[2], t[3], t[4]}; break;
            case "cpad":
                cpad = new int[] {Integer.parseInt(t[1]), Integer.parseInt(t[2]), Integer.parseInt(t[3]), Integer.parseInt(t[4])};
                break;
            case "cmin": cmin = new int[] {Integer.parseInt(t[1]), Integer.parseInt(t[2])}; break;
            case "cmax": cmax = new int[] {Integer.parseInt(t[1]), Integer.parseInt(t[2])}; break;
            default:
                unmap("op:" + t[0]);
        }
    }

    private void flowCall(String[] t, String setter) {
        flow(t[1]).calls.add(new String[] {setter, t[2]});
    }

    private void fset(String[] t) {
        Flow f = (Flow) n(t[1]);
        String v = t[3];
        switch (t[2]) {
            case "fhs1": f.setFirstHorizontalStyle(Integer.parseInt(v)); break;
            case "fvs1": f.setFirstVerticalStyle(Integer.parseInt(v)); break;
            case "fhsl": f.setLastHorizontalStyle(Integer.parseInt(v)); break;
            case "fvsl": f.setLastVerticalStyle(Integer.parseInt(v)); break;
            case "fhb1": f.setFirstHorizontalBias(Float.parseFloat(v)); break;
            case "fvb1": f.setFirstVerticalBias(Float.parseFloat(v)); break;
            case "fhbl": f.setLastHorizontalBias(Float.parseFloat(v)); break;
            case "fvbl": f.setLastVerticalBias(Float.parseFloat(v)); break;
            case "pads": unmap("flowpad"); f.setPaddingStart(Integer.parseInt(v)); return;
            case "pade": unmap("flowpad"); f.setPaddingEnd(Integer.parseInt(v)); return;
            default: unmap("flowset:" + t[2]); return;
        }
        flow(t[1]).calls.add(new String[] {t[2], v});
    }

    /** The anchor's target widget's name, or null. */
    static String targetName(ConstraintAnchor a) {
        return a.mTarget == null ? null : a.mTarget.getOwner().getDebugName();
    }
}
