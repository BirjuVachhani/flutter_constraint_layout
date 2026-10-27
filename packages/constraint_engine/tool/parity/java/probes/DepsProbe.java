import androidx.constraintlayout.core.widgets.*;
import androidx.constraintlayout.core.widgets.ConstraintAnchor.Type;
import androidx.constraintlayout.core.widgets.ConstraintWidget.DimensionBehaviour;

import java.util.*;

/**
 * DepsProbe: the anchor state Android's view layer leaves after
 * ConstraintLayout.setChildrenConstraints (CL 1249-1351) and
 * applyConstraintsFromLayoutParams / setWidgetBaseline (CL 1354-1620),
 * emulated step by step on the pinned core classes ($CL_CORE).
 * Run with -XX:+UnlockExperimentalVMOptions -XX:hashCode=2 so every HashSet
 * of dependents iterates in insertion order.
 *
 * Each scenario configures its children twice (the second time after the
 * links of the first were edited in place), as two onMeasure calls with a
 * dirty hierarchy do, and prints the state after the second.
 */
public class DepsProbe {
    static final int GU = Integer.MIN_VALUE; // LayoutParams.GONE_UNSET

    /** One link of a child's layout params: from-type, target name, to-type. */
    static final class Link {
        final Type from; final String target; final Type to; final int margin; final int gone;
        Link(Type from, String target, Type to, int margin, int gone) {
            this.from = from; this.target = target; this.to = to; this.margin = margin; this.gone = gone;
        }
    }

    /** A child view: its widget and its layout params. */
    static final class Child {
        final String name; final ConstraintWidget widget;
        final List<Link> links = new ArrayList<>(); // LEFT, RIGHT, TOP, BOTTOM in CL order
        Link baseline; // baselineToBaseline / baselineToTop / baselineToBottom
        String circleTarget; float circleAngle; int circleRadius;
        DimensionBehaviour h = DimensionBehaviour.FIXED, v = DimensionBehaviour.FIXED;
        int width, height;
        int leftMargin, rightMargin, topMargin, bottomMargin; // match-parent margins
        int visibility = ConstraintWidget.VISIBLE;
        List<String> refs; // helpers
        int guideBegin = -1; int orientation = -1;
        boolean needsBaseline;
        Child(String name, ConstraintWidget widget) { this.name = name; this.widget = widget; widget.setDebugName(name); }
    }

    static Map<String, ConstraintWidget> byName = new HashMap<>();
    static Map<String, Child> children = new LinkedHashMap<>();
    static ConstraintWidgetContainer root;

    static Child child(String name, ConstraintWidget w) {
        Child c = new Child(name, w);
        children.put(name, c);
        byName.put(name, w);
        return c;
    }

    static void begin(int w, int h) {
        byName.clear();
        children.clear();
        root = new ConstraintWidgetContainer(0, 0, w, h);
        root.setDebugName("root");
        byName.put("root", root);
    }

    /** CL 1249-1351 and 1354-1620, as far as anchors and hasBaseline go. */
    static void setChildrenConstraints() {
        for (Child c : children.values()) {
            c.widget.reset();
        }
        root.removeAllChildren();
        for (Child c : children.values()) {
            if (c.refs != null) {
                HelperWidget hw = (HelperWidget) c.widget;
                hw.removeAllIds();
                for (String r : c.refs) hw.add(byName.get(r));
                hw.updateConstraints(root);
            }
        }
        for (Child c : children.values()) {
            root.add(c.widget);
            apply(c);
        }
    }

    static void apply(Child c) {
        ConstraintWidget w = c.widget;
        w.setVisibility(c.visibility);
        if (w instanceof Guideline) {
            Guideline g = (Guideline) w;
            if (c.orientation >= 0) g.setOrientation(c.orientation);
            if (c.guideBegin >= 0) g.setGuideBegin(c.guideBegin);
            return;
        }
        if (c.circleTarget != null) {
            w.connectCircularConstraint(byName.get(c.circleTarget), c.circleAngle, c.circleRadius);
        } else {
            for (Link l : c.links) {
                w.immediateConnect(l.from, byName.get(l.target), l.to, l.margin, l.gone);
            }
            if (c.baseline != null) setWidgetBaseline(c);
        }
        if (c.h == DimensionBehaviour.MATCH_PARENT) {
            w.setHorizontalDimensionBehaviour(DimensionBehaviour.MATCH_PARENT);
            w.getAnchor(Type.LEFT).mMargin = c.leftMargin;
            w.getAnchor(Type.RIGHT).mMargin = c.rightMargin;
        } else {
            w.setHorizontalDimensionBehaviour(c.h);
            w.setWidth(c.width);
        }
        if (c.v == DimensionBehaviour.MATCH_PARENT) {
            w.setVerticalDimensionBehaviour(DimensionBehaviour.MATCH_PARENT);
            w.getAnchor(Type.TOP).mMargin = c.topMargin;
            w.getAnchor(Type.BOTTOM).mMargin = c.bottomMargin;
        } else {
            w.setVerticalDimensionBehaviour(c.v);
            w.setHeight(c.height);
        }
    }

    /** CL 1598-1620. */
    static void setWidgetBaseline(Child c) {
        Child tc = children.get(c.baseline.target);
        if (tc == null) return; // only a child view can be a baseline target
        ConstraintWidget target = tc.widget;
        c.needsBaseline = true;
        if (c.baseline.to == Type.BASELINE) {
            tc.needsBaseline = true;
            target.setHasBaseline(true);
        }
        ConstraintAnchor baseline = c.widget.getAnchor(Type.BASELINE);
        baseline.connect(target.getAnchor(c.baseline.to), c.baseline.margin, c.baseline.gone, true);
        c.widget.setHasBaseline(true);
        c.widget.getAnchor(Type.TOP).reset();
        c.widget.getAnchor(Type.BOTTOM).reset();
    }

    static String letter(Type t) {
        switch (t) {
            case LEFT: return "L";
            case TOP: return "T";
            case RIGHT: return "R";
            case BOTTOM: return "B";
            case BASELINE: return "S";
            case CENTER: return "C";
            case CENTER_X: return "CX";
            case CENTER_Y: return "CY";
            default: return "N";
        }
    }

    static String name(ConstraintAnchor a) {
        return a.getOwner().getDebugName() + "." + letter(a.getType());
    }

    static String dump() {
        StringBuilder sb = new StringBuilder();
        List<ConstraintWidget> all = new ArrayList<>();
        all.add(root);
        all.addAll(root.getChildren());
        for (ConstraintWidget w : all) {
            for (ConstraintAnchor a : w.getAnchors()) {
                HashSet<ConstraintAnchor> d = a.getDependents();
                if (d == null) continue;
                sb.append(' ').append(name(a)).append("=[");
                boolean first = true;
                for (ConstraintAnchor x : d) {
                    if (!first) sb.append(',');
                    first = false;
                    sb.append(name(x));
                }
                sb.append(']');
            }
        }
        sb.append(" | links");
        for (ConstraintWidget w : root.getChildren()) {
            for (ConstraintAnchor a : w.getAnchors()) {
                if (a.getTarget() == null && a.mMargin == 0) continue;
                sb.append(' ').append(name(a)).append("->")
                        .append(a.getTarget() == null ? "-" : name(a.getTarget()))
                        .append('/').append(a.mMargin);
            }
        }
        sb.append(" | hb");
        for (ConstraintWidget w : root.getChildren()) {
            if (w.hasBaseline()) sb.append(' ').append(w.getDebugName());
        }
        sb.append(" | nb");
        for (Child c : children.values()) {
            if (c.needsBaseline) sb.append(' ').append(c.name);
        }
        return sb.toString();
    }

    static Link L(Type from, String target, Type to, int margin) { return new Link(from, target, to, margin, GU); }

    static ConstraintWidget fixed(String name, int w, int h) {
        return new ConstraintWidget(w, h);
    }

    static Child fixedChild(String name, int w, int h) {
        Child c = child(name, new ConstraintWidget(w, h));
        c.width = w; c.height = h;
        return c;
    }

    public static void main(String[] args) {
        // Dependents order: earlier children link into the top and bottom of
        // X, which has a baseline link; a later child links into X's bottom.
        begin(400, 800);
        Child e = fixedChild("E", 40, 10);
        e.links.add(L(Type.LEFT, "root", Type.LEFT, 0));
        e.links.add(L(Type.BOTTOM, "X", Type.TOP, 4));
        Child f = fixedChild("F", 20, 10);
        f.links.add(L(Type.LEFT, "root", Type.LEFT, 5));
        f.links.add(L(Type.TOP, "X", Type.BOTTOM, 2));
        Child x = fixedChild("X", 60, 30);
        x.links.add(L(Type.LEFT, "root", Type.LEFT, 20));
        x.links.add(L(Type.TOP, "root", Type.TOP, 30));
        x.links.add(L(Type.BOTTOM, "root", Type.BOTTOM, 0));
        x.baseline = L(Type.BASELINE, "B", Type.BASELINE, 0);
        Child b = fixedChild("B", 80, 40);
        b.links.add(L(Type.LEFT, "root", Type.LEFT, 100));
        b.links.add(L(Type.TOP, "root", Type.TOP, 50));
        Child l = fixedChild("L", 30, 10);
        l.links.add(L(Type.LEFT, "X", Type.LEFT, 0));
        l.links.add(L(Type.TOP, "X", Type.BOTTOM, 8));
        setChildrenConstraints();
        setChildrenConstraints();
        System.out.println("depsorder" + dump());

        // Order: two links of one child into one target, and links of several
        // children into one target.
        begin(400, 800);
        Child p = fixedChild("P", 100, 20);
        p.links.add(L(Type.LEFT, "root", Type.LEFT, 10));
        p.links.add(L(Type.TOP, "root", Type.TOP, 10));
        Child q = fixedChild("Q", 50, 20);
        q.links.add(L(Type.LEFT, "P", Type.RIGHT, 0));
        q.links.add(L(Type.RIGHT, "P", Type.RIGHT, 0));
        q.links.add(L(Type.TOP, "P", Type.BOTTOM, 5));
        Child w = fixedChild("W", 30, 20);
        w.links.add(L(Type.LEFT, "P", Type.RIGHT, 3));
        w.links.add(L(Type.TOP, "P", Type.BOTTOM, 0));
        w.links.add(L(Type.BOTTOM, "P", Type.BOTTOM, 0));
        setChildrenConstraints();
        setChildrenConstraints();
        System.out.println("order" + dump());

        // A match-parent height with margins and a baseline link.
        begin(400, 800);
        Child b2 = fixedChild("B2", 50, 40);
        b2.links.add(L(Type.LEFT, "root", Type.LEFT, 0));
        b2.links.add(L(Type.TOP, "root", Type.TOP, 20));
        Child m = fixedChild("M", 30, 0);
        m.v = DimensionBehaviour.MATCH_PARENT;
        m.topMargin = 7;
        m.bottomMargin = 9;
        m.links.add(L(Type.LEFT, "B2", Type.RIGHT, 4));
        m.links.add(L(Type.TOP, "root", Type.TOP, 7));
        m.links.add(L(Type.BOTTOM, "root", Type.BOTTOM, 9));
        m.baseline = L(Type.BASELINE, "B2", Type.BASELINE, 0);
        setChildrenConstraints();
        setChildrenConstraints();
        System.out.println("matchparent" + dump());

        // A baseline link to another child's top: only the linked child is
        // seeded.
        begin(400, 800);
        Child z = fixedChild("Z", 50, 20);
        z.links.add(L(Type.LEFT, "root", Type.LEFT, 0));
        z.links.add(L(Type.TOP, "root", Type.TOP, 0));
        Child y = fixedChild("Y", 50, 20);
        y.links.add(L(Type.LEFT, "Z", Type.RIGHT, 0));
        y.baseline = L(Type.BASELINE, "Z", Type.TOP, 3);
        setChildrenConstraints();
        setChildrenConstraints();
        System.out.println("basetotop" + dump());

        // Helpers and a circle.
        begin(400, 800);
        Child g = child("G", new Guideline());
        g.orientation = Guideline.VERTICAL;
        g.guideBegin = 50;
        Child a = fixedChild("A", 40, 40);
        a.links.add(L(Type.LEFT, "G", Type.LEFT, 0));
        a.links.add(L(Type.TOP, "root", Type.TOP, 0));
        Child c = fixedChild("C", 10, 10);
        c.circleTarget = "A";
        c.circleAngle = 45f;
        c.circleRadius = 30;
        Barrier barrier = new Barrier();
        barrier.setBarrierType(Barrier.RIGHT);
        Child bar = child("bar", barrier);
        bar.refs = Arrays.asList("A", "C");
        Child k = fixedChild("K", 20, 20);
        k.links.add(new Link(Type.LEFT, "bar", Type.RIGHT, 5, 7));
        k.links.add(L(Type.TOP, "root", Type.TOP, 0));
        setChildrenConstraints();
        setChildrenConstraints();
        System.out.println("helpers" + dump());

        // A Flow: its members carry no links of their own.
        begin(400, 800);
        Flow flow = new Flow();
        Child fl = child("FL", flow);
        fl.refs = Arrays.asList("m0", "m1");
        fl.h = DimensionBehaviour.WRAP_CONTENT;
        fl.v = DimensionBehaviour.WRAP_CONTENT;
        fl.links.add(L(Type.LEFT, "root", Type.LEFT, 7));
        fl.links.add(L(Type.TOP, "root", Type.TOP, 4));
        fixedChild("m0", 30, 20);
        fixedChild("m1", 40, 20);
        Child below = fixedChild("below", 50, 10);
        below.links.add(L(Type.LEFT, "root", Type.LEFT, 5));
        below.links.add(L(Type.TOP, "FL", Type.BOTTOM, 2));
        setChildrenConstraints();
        setChildrenConstraints();
        System.out.println("flow" + dump());
    }
}
