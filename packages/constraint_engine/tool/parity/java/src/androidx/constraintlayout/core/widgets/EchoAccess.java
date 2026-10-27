package androidx.constraintlayout.core.widgets;

// Package-private access for the oracle's echo measurer, which mirrors the
// Dart engine's _EchoMeasurer: a wrap-content axis reports the widget's raw
// mWidth / mHeight field (not getWidth(), which is 0 for a gone widget).
public final class EchoAccess {
    private EchoAccess() {}

    public static int rawWidth(ConstraintWidget w) {
        return w.mWidth;
    }

    public static int rawHeight(ConstraintWidget w) {
        return w.mHeight;
    }
}
