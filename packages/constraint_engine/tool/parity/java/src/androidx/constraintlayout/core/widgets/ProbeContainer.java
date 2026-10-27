package androidx.constraintlayout.core.widgets;

import androidx.constraintlayout.core.ProbeSystem;
import androidx.constraintlayout.core.widgets.analyzer.BasicMeasure;
import androidx.constraintlayout.core.widgets.analyzer.DirectProbe;

import java.lang.reflect.Field;

/**
 * Phase 0 oracle (p0-java): upstream's ConstraintWidgetContainer with observation hooks
 * for DirectProbe. Every override calls upstream's code unchanged; the hooks only
 * record (pass numbers, iterations, the Direct state, measure requests).
 */
public class ProbeContainer extends ConstraintWidgetContainer {

    public final DirectProbe probe;
    private int mProbePass = 0;

    private static final Field BASIC_MEASURE_MEASURE;

    static {
        try {
            BASIC_MEASURE_MEASURE = BasicMeasure.class.getDeclaredField("mMeasure");
            BASIC_MEASURE_MEASURE.setAccessible(true);
        } catch (NoSuchFieldException e) {
            throw new IllegalStateException("BasicMeasure.mMeasure is missing", e);
        }
    }

    public ProbeContainer(int x, int y, int width, int height) {
        super(x, y, width, height);
        probe = new DirectProbe(this);
        ProbeSystem system = new ProbeSystem();
        system.hook = probe;
        mSystem = system;
    }

    @Override
    public void setPass(int pass) {
        mProbePass = pass;
        super.setPass(pass);
    }

    @Override
    public void layout() {
        probe.beginPass(mProbePass);
        try {
            super.layout();
        } finally {
            probe.endPass();
        }
    }

    /** The Measure object BasicMeasure reuses (measureChildren and the re-measure loop). */
    public BasicMeasure.Measure basicMeasureMeasure() {
        try {
            return (BasicMeasure.Measure) BASIC_MEASURE_MEASURE.get(mBasicMeasureSolver);
        } catch (IllegalAccessException e) {
            throw new IllegalStateException(e);
        }
    }

    /** True when m is the Measure a child VirtualLayout uses for its members. */
    public boolean isVirtualLayoutMeasure(BasicMeasure.Measure m) {
        for (int i = 0; i < mChildren.size(); i++) {
            ConstraintWidget c = mChildren.get(i);
            if (c instanceof VirtualLayout && ((VirtualLayout) c).mMeasure == m) {
                return true;
            }
        }
        return false;
    }

    public static int rawWidth(ConstraintWidget w) {
        return w.mWidth;
    }

    public static int rawHeight(ConstraintWidget w) {
        return w.mHeight;
    }
}
