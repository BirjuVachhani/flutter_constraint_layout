package androidx.constraintlayout.core.widgets;

/**
 * Package-private core state the RoboOracle reads back after replaying an op
 * list (p0-view). Loaded by the same class loader as the core, so the
 * package-private fields are reachable.
 */
public final class RoboAccess {
    private RoboAccess() {}

    /** The stored width, without the GONE short cut of getWidth(). */
    public static int rawWidth(ConstraintWidget w) {
        return w.mWidth;
    }

    /** The stored height, without the GONE short cut of getHeight(). */
    public static int rawHeight(ConstraintWidget w) {
        return w.mHeight;
    }

    /** The anchor's gone margin as set (Integer.MIN_VALUE when unset). */
    public static int goneMargin(ConstraintAnchor a) {
        return a.mGoneMargin;
    }

    /** The widget's wrap behaviour in its parent. */
    public static int wrapBehavior(ConstraintWidget w) {
        return w.getWrapBehaviorInParent();
    }
}
