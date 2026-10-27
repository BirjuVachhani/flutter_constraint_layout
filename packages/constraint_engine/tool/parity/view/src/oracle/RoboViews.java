package oracle;

import android.content.Context;
import android.view.View;
import android.view.ViewGroup;
import androidx.constraintlayout.core.widgets.Barrier;
import androidx.constraintlayout.core.widgets.ConstraintAnchor;
import androidx.constraintlayout.core.widgets.ConstraintAnchor.Type;
import androidx.constraintlayout.core.widgets.ConstraintWidget;
import androidx.constraintlayout.core.widgets.ConstraintWidget.DimensionBehaviour;
import androidx.constraintlayout.core.widgets.Flow;
import androidx.constraintlayout.core.widgets.Guideline;
import androidx.constraintlayout.core.widgets.HelperWidget;
import androidx.constraintlayout.core.widgets.RoboAccess;
import androidx.constraintlayout.widget.ConstraintLayout;
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Builds a real ConstraintLayout view tree from a replayed op list's final
 * core state (FORMATS.md section 10), measures and lays it out, and prints
 * the frames in section 2's geometry format.
 */
final class RoboViews {
    static final class Unmappable extends RuntimeException {
        Unmappable(String reason) {
            super(reason, null, false, false);
        }
    }

    final Context ctx;
    final RoboOps ops;
    /** The layout view's optimization level (setOptimizationLevel), set in build(). */
    final int level;
    /** The state the views show: ops, or the last state applied by update(). */
    RoboOps current;
    ConstraintLayout layout;
    final List<String> names = new ArrayList<>();
    final List<View> views = new ArrayList<>();
    final List<ConstraintWidget> widgets = new ArrayList<>();
    final Map<String, Integer> idOf = new HashMap<>();

    RoboViews(Context ctx, RoboOps ops, int level) {
        this.ctx = ctx;
        this.ops = ops;
        this.level = level;
        this.current = ops;
    }

    private int idOfTarget(ConstraintAnchor a) {
        ConstraintWidget owner = a.mTarget.getOwner();
        if (owner == ops.root) return LayoutParams.PARENT_ID;
        Integer id = idOf.get(owner.getDebugName());
        if (id == null || owner.getParent() != ops.root) throw new Unmappable("dangling");
        return id;
    }

    /** Dimension, match style and links of a regular widget or a Flow. */
    private LayoutParams regularParams(ConstraintWidget w) {
        LayoutParams lp = new LayoutParams(dim(w, true), dim(w, false));
        lp.matchConstraintDefaultWidth = w.mMatchConstraintDefaultWidth;
        lp.matchConstraintMinWidth = w.mMatchConstraintMinWidth;
        lp.matchConstraintMaxWidth = w.mMatchConstraintMaxWidth;
        lp.matchConstraintPercentWidth = w.mMatchConstraintPercentWidth;
        lp.matchConstraintDefaultHeight = w.mMatchConstraintDefaultHeight;
        lp.matchConstraintMinHeight = w.mMatchConstraintMinHeight;
        lp.matchConstraintMaxHeight = w.mMatchConstraintMaxHeight;
        lp.matchConstraintPercentHeight = w.mMatchConstraintPercentHeight;
        boolean circle = w.mCenter.mTarget != null;
        boolean others = false;
        for (Type type : new Type[] {Type.LEFT, Type.RIGHT, Type.TOP, Type.BOTTOM, Type.BASELINE}) {
            ConstraintAnchor a = w.getAnchor(type);
            if (a.mTarget == null) continue;
            others = true;
            int target = idOfTarget(a);
            Type to = a.mTarget.getType();
            int margin = a.mMargin;
            int gone = RoboAccess.goneMargin(a);
            switch (type) {
                case LEFT:
                    if (to == Type.LEFT) lp.leftToLeft = target;
                    else if (to == Type.RIGHT) lp.leftToRight = target;
                    else throw new Unmappable("link");
                    lp.leftMargin = margin;
                    lp.goneLeftMargin = gone;
                    break;
                case RIGHT:
                    if (to == Type.LEFT) lp.rightToLeft = target;
                    else if (to == Type.RIGHT) lp.rightToRight = target;
                    else throw new Unmappable("link");
                    lp.rightMargin = margin;
                    lp.goneRightMargin = gone;
                    break;
                case TOP:
                    if (to == Type.TOP) lp.topToTop = target;
                    else if (to == Type.BOTTOM) lp.topToBottom = target;
                    else throw new Unmappable("link");
                    lp.topMargin = margin;
                    lp.goneTopMargin = gone;
                    break;
                case BOTTOM:
                    if (to == Type.TOP) lp.bottomToTop = target;
                    else if (to == Type.BOTTOM) lp.bottomToBottom = target;
                    else throw new Unmappable("link");
                    lp.bottomMargin = margin;
                    lp.goneBottomMargin = gone;
                    break;
                case BASELINE:
                    if (to == Type.BASELINE) lp.baselineToBaseline = target;
                    else if (to == Type.TOP) lp.baselineToTop = target;
                    else if (to == Type.BOTTOM) lp.baselineToBottom = target;
                    else throw new Unmappable("link");
                    lp.baselineMargin = margin;
                    lp.goneBaselineMargin = gone;
                    break;
                default:
                    throw new Unmappable("link");
            }
        }
        if (w.getAnchor(Type.CENTER_X).mTarget != null || w.getAnchor(Type.CENTER_Y).mTarget != null) {
            throw new Unmappable("center");
        }
        if (circle) {
            if (others) throw new Unmappable("circle+links");
            if (Float.isNaN(w.mCircleConstraintAngle) || w.mCenter.mTarget.getType() != Type.CENTER) {
                throw new Unmappable("center");
            }
            lp.circleConstraint = idOfTarget(w.mCenter);
            lp.circleRadius = w.mCenter.mMargin;
            lp.circleAngle = w.mCircleConstraintAngle;
        }
        float hb = w.getHorizontalBiasPercent(), vb = w.getVerticalBiasPercent();
        if (hb < 0 || vb < 0) throw new Unmappable("negbias");
        lp.horizontalBias = hb;
        lp.verticalBias = vb;
        float ratio = w.getDimensionRatio();
        if (ratio > 0) {
            int side = w.getDimensionRatioSide();
            String prefix = side == ConstraintWidget.HORIZONTAL ? "W," : side == ConstraintWidget.VERTICAL ? "H," : "";
            lp.dimensionRatio = prefix + Float.toString(ratio);
        } else if (ratio < 0) {
            throw new Unmappable("negratio");
        }
        lp.horizontalChainStyle = w.getHorizontalChainStyle();
        lp.verticalChainStyle = w.getVerticalChainStyle();
        lp.horizontalWeight = w.mWeight[ConstraintWidget.HORIZONTAL];
        lp.verticalWeight = w.mWeight[ConstraintWidget.VERTICAL];
        lp.wrapBehaviorInParent = RoboAccess.wrapBehavior(w);
        return lp;
    }

    /** layout_width / layout_height for the widget's behaviour on one axis. */
    private static int dim(ConstraintWidget w, boolean horizontal) {
        DimensionBehaviour b = horizontal ? w.getHorizontalDimensionBehaviour() : w.getVerticalDimensionBehaviour();
        switch (b) {
            case FIXED: {
                int size = horizontal ? RoboAccess.rawWidth(w) : RoboAccess.rawHeight(w);
                // layout_width 0 is MATCH_CONSTRAINT in Android; a FIXED 0 has no LayoutParams.
                if (size <= 0) throw new Unmappable("fixed" + size);
                return size;
            }
            case WRAP_CONTENT: return ViewGroup.LayoutParams.WRAP_CONTENT;
            case MATCH_PARENT: return ViewGroup.LayoutParams.MATCH_PARENT;
            default: return 0; // MATCH_CONSTRAINT
        }
    }

    private int[] refIds(HelperWidget h) {
        int[] ids = new int[h.mWidgetsCount];
        for (int i = 0; i < h.mWidgetsCount; i++) {
            Integer id = idOf.get(h.mWidgets[i].getDebugName());
            if (id == null) throw new Unmappable("ref");
            ids[i] = id;
        }
        return ids;
    }

    private static void noLinks(ConstraintWidget w) {
        for (ConstraintAnchor a : w.getAnchors()) {
            if (a.mTarget != null) throw new Unmappable("helperlink");
        }
    }

    /** Builds the views; throws Unmappable when the state has no LayoutParams form. */
    void build() {
        ArrayList<ConstraintWidget> children = ops.root.getChildren();
        for (int i = 0; i < children.size(); i++) {
            ConstraintWidget w = children.get(i);
            String name = w.getDebugName();
            if (idOf.containsKey(name)) throw new Unmappable("dupname");
            idOf.put(name, i + 1);
        }
        layout = new ConstraintLayout(ctx);
        // ConstraintLayout.setOptimizationLevel (app:layout_optimizationLevel):
        // the view keeps it and gives it to its layout widget, so every measure
        // of these views, the in-place ones included, runs at this level.
        layout.setOptimizationLevel(level);
        if (ops.root.isRtl()) layout.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        else layout.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);
        if (ops.cpad != null) layout.setPadding(ops.cpad[0], ops.cpad[1], ops.cpad[2], ops.cpad[3]);
        if (ops.cmin != null) {
            layout.setMinWidth(ops.cmin[0]);
            layout.setMinHeight(ops.cmin[1]);
        }
        if (ops.cmax != null) {
            layout.setMaxWidth(ops.cmax[0]);
            layout.setMaxHeight(ops.cmax[1]);
        }
        for (int i = 0; i < children.size(); i++) {
            ConstraintWidget w = children.get(i);
            String name = w.getDebugName();
            View view;
            LayoutParams lp;
            if (w instanceof Guideline) {
                Guideline g = (Guideline) w;
                noLinks(g);
                view = new androidx.constraintlayout.widget.Guideline(ctx);
                lp = new LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                lp.orientation = g.getOrientation();
                lp.guidelineUseRtl = false;
                if (g.getRelativePercent() != -1) lp.guidePercent = g.getRelativePercent();
                else if (g.getRelativeBegin() != -1) lp.guideBegin = g.getRelativeBegin();
                else if (g.getRelativeEnd() != -1) lp.guideEnd = g.getRelativeEnd();
                else throw new Unmappable("guideline");
                if (g.getVisibility() != ConstraintWidget.VISIBLE) throw new Unmappable("guidelinevis");
            } else if (w instanceof Barrier) {
                Barrier b = (Barrier) w;
                noLinks(b);
                androidx.constraintlayout.widget.Barrier vb = new androidx.constraintlayout.widget.Barrier(ctx);
                vb.setType(b.getBarrierType());
                vb.setMargin(b.getMargin());
                vb.setAllowsGoneWidget(b.getAllowsGoneWidget());
                view = vb;
                lp = new LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                if (b.getVisibility() != ConstraintWidget.VISIBLE) throw new Unmappable("barriervis");
            } else if (w instanceof Flow) {
                androidx.constraintlayout.helper.widget.Flow vf = new androidx.constraintlayout.helper.widget.Flow(ctx);
                for (String[] call : ops.flows.get(name).calls) flowCall(vf, call);
                view = vf;
                lp = regularParams(w);
                view.setVisibility(w.getVisibility());
            } else if (w instanceof HelperWidget || w.getClass() != ConstraintWidget.class) {
                throw new Unmappable("widget:" + w.getClass().getSimpleName());
            } else {
                RoboOps.Content c = ops.content.get(name);
                view = c == null
                        ? new ContentView(ctx, ContentView.NONE, 0, 0, -1)
                        : new ContentView(ctx, c.kind, c.w, c.h, c.baseline);
                lp = regularParams(w);
                view.setVisibility(w.getVisibility());
            }
            view.setId(i + 1);
            names.add(name);
            views.add(view);
            widgets.add(w);
            layout.addView(view, lp);
        }
        // Helpers reference by id, so their ids are set once every view has one.
        for (int i = 0; i < widgets.size(); i++) {
            ConstraintWidget w = widgets.get(i);
            if (w instanceof Barrier || w instanceof Flow) {
                ((androidx.constraintlayout.widget.ConstraintHelper) views.get(i)).setReferencedIds(refIds((HelperWidget) w));
            }
        }
    }

    /**
     * Applies a later state of an in-place sequence to the views built from an
     * earlier one, the way an app changes a live layout: each view's existing
     * LayoutParams are rewritten and set again (as ConstraintSet.applyTo does,
     * so the view keeps its widget), contents and visibilities change in place,
     * and the layout is requested. The same children in the same order are
     * required (T-inplace keeps them).
     */
    void update(RoboOps next) {
        update(next, false);
    }

    /**
     * [update], or with [changedOnly] (robo.inplace=changed) the way an app
     * that touches only what changed does: a view's LayoutParams are rewritten
     * and set again only when they differ from its current ones (both compared
     * after LayoutParams.validate()), a content or a visibility only when it
     * changes, and nothing else requests a layout. A state that changes nothing
     * then requests no layout at all, as a Flutter rebuild with the same
     * configuration lays nothing out again.
     */
    void update(RoboOps next, boolean changedOnly) {
        ArrayList<ConstraintWidget> children = next.root.getChildren();
        if (children.size() != views.size()) throw new Unmappable("inplace-structure");
        RoboViews fresh = new RoboViews(ctx, next, level);
        for (int i = 0; i < children.size(); i++) {
            String name = children.get(i).getDebugName();
            if (!name.equals(names.get(i))) throw new Unmappable("inplace-order");
            fresh.idOf.put(name, i + 1);
        }
        for (int i = 0; i < children.size(); i++) {
            ConstraintWidget w = children.get(i);
            View view = views.get(i);
            if (w.getClass() != widgets.get(i).getClass()) throw new Unmappable("inplace-kind");
            if (w instanceof Guideline || w instanceof Barrier || w instanceof Flow) {
                // T-inplace changes regular children only; a helper change would be
                // a structural rebuild in the adapter.
                continue;
            }
            LayoutParams now = fresh.regularParams(w);
            LayoutParams lp = (LayoutParams) view.getLayoutParams();
            boolean setParams = true;
            if (changedOnly) {
                LayoutParams probe = fresh.regularParams(w);
                probe.validate();
                setParams = !sameParams(probe, lp);
            }
            if (setParams) copy(now, lp);
            RoboOps.Content c = next.content.get(names.get(i));
            if (c != null) ((ContentView) view).setContent(c.kind, c.w, c.h, c.baseline);
            else ((ContentView) view).setContent(ContentView.NONE, 0, 0, -1);
            if (view.getVisibility() != w.getVisibility()) view.setVisibility(w.getVisibility());
            if (setParams) view.setLayoutParams(lp);
            widgets.set(i, w);
        }
        current = next;
        if (!changedOnly) layout.requestLayout();
    }

    /** Whether [a] and [b] agree on every LayoutParams field [copy] writes. */
    private static boolean sameParams(LayoutParams a, LayoutParams b) {
        return a.width == b.width && a.height == b.height
                && a.constrainedWidth == b.constrainedWidth && a.constrainedHeight == b.constrainedHeight
                && a.matchConstraintDefaultWidth == b.matchConstraintDefaultWidth
                && a.matchConstraintMinWidth == b.matchConstraintMinWidth
                && a.matchConstraintMaxWidth == b.matchConstraintMaxWidth
                && Float.compare(a.matchConstraintPercentWidth, b.matchConstraintPercentWidth) == 0
                && a.matchConstraintDefaultHeight == b.matchConstraintDefaultHeight
                && a.matchConstraintMinHeight == b.matchConstraintMinHeight
                && a.matchConstraintMaxHeight == b.matchConstraintMaxHeight
                && Float.compare(a.matchConstraintPercentHeight, b.matchConstraintPercentHeight) == 0
                && a.leftToLeft == b.leftToLeft && a.leftToRight == b.leftToRight
                && a.rightToLeft == b.rightToLeft && a.rightToRight == b.rightToRight
                && a.topToTop == b.topToTop && a.topToBottom == b.topToBottom
                && a.bottomToTop == b.bottomToTop && a.bottomToBottom == b.bottomToBottom
                && a.baselineToBaseline == b.baselineToBaseline && a.baselineToTop == b.baselineToTop
                && a.baselineToBottom == b.baselineToBottom
                && a.circleConstraint == b.circleConstraint && a.circleRadius == b.circleRadius
                && Float.compare(a.circleAngle, b.circleAngle) == 0
                && a.leftMargin == b.leftMargin && a.rightMargin == b.rightMargin
                && a.topMargin == b.topMargin && a.bottomMargin == b.bottomMargin
                && a.baselineMargin == b.baselineMargin
                && a.goneLeftMargin == b.goneLeftMargin && a.goneRightMargin == b.goneRightMargin
                && a.goneTopMargin == b.goneTopMargin && a.goneBottomMargin == b.goneBottomMargin
                && a.goneBaselineMargin == b.goneBaselineMargin
                && Float.compare(a.horizontalBias, b.horizontalBias) == 0
                && Float.compare(a.verticalBias, b.verticalBias) == 0
                && java.util.Objects.equals(a.dimensionRatio, b.dimensionRatio)
                && a.horizontalChainStyle == b.horizontalChainStyle && a.verticalChainStyle == b.verticalChainStyle
                && Float.compare(a.horizontalWeight, b.horizontalWeight) == 0
                && Float.compare(a.verticalWeight, b.verticalWeight) == 0
                && a.wrapBehaviorInParent == b.wrapBehaviorInParent;
    }

    /** Every LayoutParams field regularParams writes, from [a] onto [b]. */
    private static void copy(LayoutParams a, LayoutParams b) {
        b.width = a.width;
        b.height = a.height;
        b.constrainedWidth = a.constrainedWidth;
        b.constrainedHeight = a.constrainedHeight;
        b.matchConstraintDefaultWidth = a.matchConstraintDefaultWidth;
        b.matchConstraintMinWidth = a.matchConstraintMinWidth;
        b.matchConstraintMaxWidth = a.matchConstraintMaxWidth;
        b.matchConstraintPercentWidth = a.matchConstraintPercentWidth;
        b.matchConstraintDefaultHeight = a.matchConstraintDefaultHeight;
        b.matchConstraintMinHeight = a.matchConstraintMinHeight;
        b.matchConstraintMaxHeight = a.matchConstraintMaxHeight;
        b.matchConstraintPercentHeight = a.matchConstraintPercentHeight;
        b.leftToLeft = a.leftToLeft;
        b.leftToRight = a.leftToRight;
        b.rightToLeft = a.rightToLeft;
        b.rightToRight = a.rightToRight;
        b.topToTop = a.topToTop;
        b.topToBottom = a.topToBottom;
        b.bottomToTop = a.bottomToTop;
        b.bottomToBottom = a.bottomToBottom;
        b.baselineToBaseline = a.baselineToBaseline;
        b.baselineToTop = a.baselineToTop;
        b.baselineToBottom = a.baselineToBottom;
        b.circleConstraint = a.circleConstraint;
        b.circleRadius = a.circleRadius;
        b.circleAngle = a.circleAngle;
        b.leftMargin = a.leftMargin;
        b.rightMargin = a.rightMargin;
        b.topMargin = a.topMargin;
        b.bottomMargin = a.bottomMargin;
        b.baselineMargin = a.baselineMargin;
        b.goneLeftMargin = a.goneLeftMargin;
        b.goneRightMargin = a.goneRightMargin;
        b.goneTopMargin = a.goneTopMargin;
        b.goneBottomMargin = a.goneBottomMargin;
        b.goneBaselineMargin = a.goneBaselineMargin;
        b.horizontalBias = a.horizontalBias;
        b.verticalBias = a.verticalBias;
        b.dimensionRatio = a.dimensionRatio;
        b.horizontalChainStyle = a.horizontalChainStyle;
        b.verticalChainStyle = a.verticalChainStyle;
        b.horizontalWeight = a.horizontalWeight;
        b.verticalWeight = a.verticalWeight;
        b.wrapBehaviorInParent = a.wrapBehaviorInParent;
    }

    private static void flowCall(androidx.constraintlayout.helper.widget.Flow f, String[] c) {
        switch (c[0]) {
            case "orientation": f.setOrientation(Integer.parseInt(c[1])); break;
            case "wrapMode": f.setWrapMode(Integer.parseInt(c[1])); break;
            case "hStyle": f.setHorizontalStyle(Integer.parseInt(c[1])); break;
            case "vStyle": f.setVerticalStyle(Integer.parseInt(c[1])); break;
            case "hBias": f.setHorizontalBias(Float.parseFloat(c[1])); break;
            case "vBias": f.setVerticalBias(Float.parseFloat(c[1])); break;
            case "hAlign": f.setHorizontalAlign(Integer.parseInt(c[1])); break;
            case "vAlign": f.setVerticalAlign(Integer.parseInt(c[1])); break;
            case "hGap": f.setHorizontalGap(Integer.parseInt(c[1])); break;
            case "vGap": f.setVerticalGap(Integer.parseInt(c[1])); break;
            case "maxElements": f.setMaxElementsWrap(Integer.parseInt(c[1])); break;
            case "pad":
                f.setPaddingLeft(Integer.parseInt(c[1]));
                f.setPaddingTop(Integer.parseInt(c[2]));
                f.setPaddingRight(Integer.parseInt(c[3]));
                f.setPaddingBottom(Integer.parseInt(c[4]));
                break;
            case "fhs1": f.setFirstHorizontalStyle(Integer.parseInt(c[1])); break;
            case "fvs1": f.setFirstVerticalStyle(Integer.parseInt(c[1])); break;
            case "fhsl": f.setLastHorizontalStyle(Integer.parseInt(c[1])); break;
            case "fvsl": f.setLastVerticalStyle(Integer.parseInt(c[1])); break;
            case "fhb1": f.setFirstHorizontalBias(Float.parseFloat(c[1])); break;
            case "fvb1": f.setFirstVerticalBias(Float.parseFloat(c[1])); break;
            case "fhbl": f.setLastHorizontalBias(Float.parseFloat(c[1])); break;
            case "fvbl": f.setLastVerticalBias(Float.parseFloat(c[1])); break;
            default: throw new Unmappable("flowcall:" + c[0]);
        }
    }

    static int spec(String mode, int size) {
        switch (mode) {
            case "E": return View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY);
            case "A": return View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.AT_MOST);
            case "U": return View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.UNSPECIFIED);
            default: throw new IllegalArgumentException("spec mode " + mode);
        }
    }

    /** The container specs: cspec, else FIXED E(cw) and WRAP U(0) (FORMATS.md 4.2). */
    int[] specs() {
        RoboOps o = current;
        if (o.cspec != null) {
            return new int[] {
                spec(o.cspec[0], Integer.parseInt(o.cspec[1])),
                spec(o.cspec[2], Integer.parseInt(o.cspec[3]))
            };
        }
        int w = o.root.getHorizontalDimensionBehaviour() == DimensionBehaviour.WRAP_CONTENT
                ? spec("U", 0) : spec("E", RoboAccess.rawWidth(o.root));
        int h = o.root.getVerticalDimensionBehaviour() == DimensionBehaviour.WRAP_CONTENT
                ? spec("U", 0) : spec("E", RoboAccess.rawHeight(o.root));
        return new int[] {w, h};
    }

    /** measure + layout, as a parent would. */
    void run() {
        int[] s = specs();
        layout.measure(s[0], s[1]);
        layout.layout(0, 0, layout.getMeasuredWidth(), layout.getMeasuredHeight());
    }

    /** Section 2's geometry string (no status prefix). */
    String geometry() {
        StringBuilder sb = new StringBuilder();
        sb.append("root ").append(layout.getMeasuredWidth()).append(" x ").append(layout.getMeasuredHeight());
        for (int i = 0; i < views.size(); i++) {
            View v = views.get(i);
            ConstraintWidget w = widgets.get(i);
            sb.append(" | ").append(names.get(i)).append(": ");
            if (w.getVisibility() == ConstraintWidget.GONE && !(w instanceof Barrier)) {
                // onLayout never places a GONE view, so after an in-place change its
                // frame can be a stale one; the real widget's size is what section 2
                // prints (0 x 0 for a GONE widget).
                ConstraintWidget real = layout.getViewWidget(v);
                sb.append("gone, ").append(real.getWidth()).append(" x ").append(real.getHeight());
            } else {
                sb.append('(').append(v.getLeft()).append(", ").append(v.getTop()).append(") ")
                        .append(v.getWidth()).append(" x ").append(v.getHeight());
            }
        }
        return sb.toString();
    }

    /** onMeasure calls per content view, in child order (for statistics). */
    String measureCounts() {
        StringBuilder sb = new StringBuilder("M");
        for (View v : views) {
            sb.append(' ').append(v instanceof ContentView ? ((ContentView) v).measures : -1);
        }
        return sb.toString();
    }
}
