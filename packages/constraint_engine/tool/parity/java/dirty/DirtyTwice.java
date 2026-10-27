// DirtyTwice (oracle, FORMATS.md 19; written by the Phase 3 gate as a scratch
// driver, moved into the oracle tree in Phase 4): Android's dirty-hierarchy
// second layout, emulated on the pinned VOpDriver v2 (view path). For each
// layout: build it fresh and measure (VOpDriver's own result), then do what
// ConstraintLayout.setChildrenConstraints does on a dirty hierarchy
// (CL 1249-1351): widget.reset() on every child, mLayoutWidget.removeAllChildren(),
// every helper's removeAllIds() (ConstraintHelper.updatePreLayout), then the
// layout params again: the op list's configuration replayed onto the SAME widget
// objects (creation ops reuse them; the views keep their measured state; L ops
// are not replayed). Then measure again (onMeasure's resolveSystem). Prints
// id, first result, second result.
//
// Guideline orientation (-Dorient=fresh, the default): before the replay every
// guideline goes back to its constructor orientation (HORIZONTAL), which it had
// when the fresh build ran the op list. An op list that orients a guideline after
// an earlier sibling links to its left or right edge (the VR and T corpora, and
// so FL) loses that link in the fresh build, because a horizontal guideline has
// no left or right anchor; the replay then loses it too, so the second layout is
// the second layout of the configuration the first layout had. Android's view
// layer orients a guideline before any link (LayoutParams.validate), so such a
// link never exists on Android, and the Flutter trees FL builds never have it.
// -Dorient=kept keeps the orientation of the first build (the Phase 3 scratch
// behaviour): the replayed links then succeed. The VR2 and T2 corpora orient
// every guideline at creation, where both modes give the same result.
//
//   java ... DirtyTwice <corpus> <ids|-> <out> <start> [level]
// <ids> restricts the run to the ids it lists (first tab field of each line); `-`
// runs every line of <corpus>. Exits 3 after writing `id\tHANG` when a layout
// takes longer than 20 s (jdirty.sh restarts after it).
import androidx.constraintlayout.core.widgets.*;
import androidx.constraintlayout.core.widgets.ConstraintAnchor.Type;
import androidx.constraintlayout.core.widgets.ConstraintWidget.DimensionBehaviour;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

public class DirtyTwice {
    static final PrintStream REAL = System.out;
    static void reapply(VOpDriver.Built b, String ops, Map<ConstraintWidget, Object> companions) {
        Map<String, ConstraintWidget> by = b.by;
        ProbeContainer root = b.root;
        for (String op : ops.split(";")) {
            op = op.trim();
            if (op.isEmpty()) continue;
            String[] t = op.split(" ");
            switch (t[0]) {
                case "R": case "L": case "ct": case "cspec": case "cpad": case "cmin": case "cmax":
                    break; // the root, the measures and the views persist
                case "rtl": root.setRtl(true); break;
                case "wrapw": root.setHorizontalDimensionBehaviour(DimensionBehaviour.WRAP_CONTENT); break;
                case "wraph": root.setVerticalDimensionBehaviour(DimensionBehaviour.WRAP_CONTENT); break;
                case "w": {
                    ConstraintWidget w = by.get(t[1]);
                    w.setWidth(Integer.parseInt(t[2]));
                    w.setHeight(Integer.parseInt(t[3]));
                    w.setCompanionWidget(companions.get(w));
                    break;
                }
                case "b": case "g": break; // reused as they are
                case "fl": {
                    ConstraintWidget w = by.get(t[1]);
                    w.setCompanionWidget(companions.get(w));
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
                    by.get(t[1]).connect(VOpDriver.anc(t[2]), by.get(t[3]), VOpDriver.anc(t[4]), Integer.parseInt(t[5]));
                    break;
                case "x": by.get(t[1]).getAnchor(VOpDriver.anc(t[2])).reset(); break;
                case "hb": by.get(t[1]).setHorizontalDimensionBehaviour(VOpDriver.beh(t[2])); break;
                case "vb": by.get(t[1]).setVerticalDimensionBehaviour(VOpDriver.beh(t[2])); break;
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
                case "gm": by.get(t[1]).setGoneMargin(VOpDriver.anc(t[2]), Integer.parseInt(t[3])); break;
                case "v": by.get(t[1]).setVisibility(Integer.parseInt(t[2])); break;
                case "bl": by.get(t[1]).setBaselineDistance(Integer.parseInt(t[2])); break;
                case "hc": by.get(t[1]).setHorizontalChainStyle(Integer.parseInt(t[2])); break;
                case "vc": by.get(t[1]).setVerticalChainStyle(Integer.parseInt(t[2])); break;
                case "hw": by.get(t[1]).setHorizontalWeight(Float.parseFloat(t[2])); break;
                case "vw": by.get(t[1]).setVerticalWeight(Float.parseFloat(t[2])); break;
                case "ra": by.get(t[1]).setDimensionRatio(Float.parseFloat(t[2]), Integer.parseInt(t[3])); break;
                case "hbl": by.get(t[1]).setHasBaseline(t[2].equals("1")); break;
                case "sw": by.get(t[1]).setWidth(Integer.parseInt(t[2])); break;
                case "sh": by.get(t[1]).setHeight(Integer.parseInt(t[2])); break;
                case "sx": by.get(t[1]).setX(Integer.parseInt(t[2])); break;
                case "sy": by.get(t[1]).setY(Integer.parseInt(t[2])); break;
                case "cw": root.setWidth(Integer.parseInt(t[1])); break;
                case "ch": root.setHeight(Integer.parseInt(t[1])); break;
                case "fixw": root.setHorizontalDimensionBehaviour(DimensionBehaviour.FIXED); break;
                case "fixh": root.setVerticalDimensionBehaviour(DimensionBehaviour.FIXED); break;
                case "ltr": root.setRtl(false); break;
                case "rm": root.remove(by.get(t[1])); break;
                case "cc":
                    by.get(t[1]).connectCircularConstraint(by.get(t[2]), Float.parseFloat(t[3]), Integer.parseInt(t[4]));
                    break;
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
                case "fset": VOpDriver.flowSet((Flow) by.get(t[1]), t[2], t[3]); break;
                case "ic":
                    by.get(t[1]).immediateConnect(VOpDriver.anc(t[2]), by.get(t[3]), VOpDriver.anc(t[4]),
                            Integer.parseInt(t[5]), VOpDriver.goneMargin(t[6]));
                    break;
                case "sbl": {
                    ConstraintWidget w = by.get(t[1]);
                    ConstraintWidget target = by.get(t[2]);
                    Type type = VOpDriver.anc(t[3]);
                    if (type == Type.BASELINE) target.setHasBaseline(true);
                    w.getAnchor(Type.BASELINE).connect(target.getAnchor(type),
                            Integer.parseInt(t[4]), VOpDriver.goneMargin(t[5]), true);
                    w.setHasBaseline(true);
                    w.getAnchor(Type.TOP).reset();
                    w.getAnchor(Type.BOTTOM).reset();
                    break;
                }
                case "rs": by.get(t[1]).setDimensionRatio(t[2]); break;
                case "ipr": VfAccess.inPlaceReset(by.get(t[1])); break;
                case "rereg": VfAccess.rereg(root); break;
                case "adeps": VfAccess.androidDeps(root); break;
                case "wb": by.get(t[1]).setWrapBehaviorInParent(Integer.parseInt(t[2])); break;
                default: throw new IllegalArgumentException("op " + op);
            }
        }
    }

    static final boolean FRESH_ORIENTATION =
            !"kept".equals(System.getProperty("orient", "fresh"));

    static String one(String ops, int level) {
        VOpDriver.Built b = VOpDriver.build(ops, level, true);
        String first = VOpDriver.measureAndReport(b, level);
        // setChildrenConstraints on a dirty hierarchy
        Map<ConstraintWidget, Object> companions = new IdentityHashMap<>();
        for (ConstraintWidget w : b.by.values()) {
            if (w == b.root) continue;
            companions.put(w, w.getCompanionWidget());
        }
        for (ConstraintWidget w : new ArrayList<>(b.root.getChildren())) {
            w.reset();
        }
        b.root.removeAllChildren();
        for (ConstraintWidget w : b.by.values()) {
            if (w instanceof HelperWidget) ((HelperWidget) w).removeAllIds();
        }
        if (FRESH_ORIENTATION) {
            for (ConstraintWidget w : b.by.values()) {
                if (w instanceof Guideline) ((Guideline) w).setOrientation(Guideline.HORIZONTAL);
            }
        }
        reapply(b, ops, companions);
        String second = VOpDriver.measureAndReport(b, level);
        return first + "\t" + second;
    }

    public static void main(String[] a) throws Exception {
        boolean all = a[1].equals("-");
        Set<String> want = new HashSet<>();
        if (!all) {
            for (String l : Files.readAllLines(Paths.get(a[1]))) {
                l = l.trim();
                if (!l.isEmpty()) want.add(l.split("\t")[0]);
            }
        }
        int start = Integer.parseInt(a[3]);
        int level = a.length > 4 ? Integer.parseInt(a[4]) : 257;
        List<String[]> rows = new ArrayList<>();
        try (BufferedReader r = Files.newBufferedReader(Paths.get(a[0]))) {
            String l;
            while ((l = r.readLine()) != null) {
                int tab = l.indexOf('\t');
                if (tab < 0 || l.startsWith("#")) continue;
                if (!all && !want.contains(l.substring(0, tab))) continue;
                rows.add(new String[] {l.substring(0, tab), l.substring(l.lastIndexOf('\t') + 1)});
            }
        }
        ExecutorService pool = Executors.newSingleThreadExecutor(r -> {
            Thread t = new Thread(r);
            t.setDaemon(true);
            return t;
        });
        try (PrintWriter out = new PrintWriter(new FileWriter(a[2], true))) {
            for (int i = start; i < rows.size(); i++) {
                final String ops = rows.get(i)[1];
                Future<String> f = pool.submit(() -> {
                    try {
                        return one(ops, level);
                    } catch (Throwable e) {
                        return "THREW " + e.toString().replace('\t', ' ').replace('\n', ' ');
                    }
                });
                String res;
                try {
                    res = f.get(20, TimeUnit.SECONDS);
                } catch (TimeoutException e) {
                    out.println(rows.get(i)[0] + "\tHANG");
                    out.flush();
                    REAL.println("NEXT " + (i + 1));
                    REAL.flush();
                    System.exit(3);
                    return;
                }
                out.println(rows.get(i)[0] + "\t" + res);
                out.flush();
            }
        }
        REAL.println("DONE " + rows.size());
        REAL.flush();
        System.exit(0);
    }
}
