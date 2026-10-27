package androidx.constraintlayout.core.widgets.analyzer;

import androidx.constraintlayout.core.ProbeSystem;
import androidx.constraintlayout.core.widgets.Barrier;
import androidx.constraintlayout.core.widgets.ConstraintAnchor;
import androidx.constraintlayout.core.widgets.ConstraintWidget;
import androidx.constraintlayout.core.widgets.Guideline;
import androidx.constraintlayout.core.widgets.Optimizer;
import androidx.constraintlayout.core.widgets.ProbeContainer;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.function.Consumer;

/**
 * Phase 0 oracle (p0-java): observes one ConstraintWidgetContainer.measure call.
 *
 * Records the pass and iteration counts, the Direct state after Direct and the
 * post-Direct measures (taken at pass 0's first LinearSystem.reset), the residual
 * system of pass 0's first iteration (taken at its minimize), the measure-request
 * transcript and the exceptions the solver loop printed. Formats: FORMATS.md 8.3 to 8.5.
 * It only reads widget and solver state; nothing it does changes a result.
 */
public final class DirectProbe implements ProbeSystem.Hook {

    private static final Object DIRECT_MEASURE;

    static {
        try {
            Field f = Direct.class.getDeclaredField("sMeasure");
            f.setAccessible(true);
            DIRECT_MEASURE = f.get(null);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException("Direct.sMeasure is missing", e);
        }
    }

    private final ProbeContainer mContainer;

    /** Sink for the trace events this probe owns (PS, M); null when not tracing. */
    public Consumer<String> trace;
    /** When true, every measure request is written to the transcript. */
    public boolean recordTranscript;

    // Per measure call state, cleared by beginMeasure().
    private final ArrayList<Integer> mIterations = new ArrayList<>();
    private int mLayouts;
    private int mPass = -1;
    private int mIteration;
    private String mDirect;
    private int mResolved = -1;
    private int mAxes = -1;
    private boolean mFirstMinimizeSeen;
    private String mTrivial = "-";
    private int mRows = -1;
    private int mVars = -1;
    private int mFree = -1;
    private int mGoal = -1;
    private int mMeasures;
    private int mCacheHits;
    private final StringBuilder mTranscript = new StringBuilder();
    private final ArrayList<String> mExceptions = new ArrayList<>();

    // The requests being measured, a stack: a VirtualLayout measures its members from
    // inside its own measure call (set by beforeMeasure, popped by afterMeasure).
    private int mDepth;
    private char[] mSrc = new char[8];
    private int[] mStrategy = new int[8];
    private ConstraintWidget.DimensionBehaviour[] mHb = new ConstraintWidget.DimensionBehaviour[8];
    private ConstraintWidget.DimensionBehaviour[] mVb = new ConstraintWidget.DimensionBehaviour[8];
    private int[] mHdim = new int[8];
    private int[] mVdim = new int[8];

    public DirectProbe(ProbeContainer container) {
        mContainer = container;
    }

    /** Clears the state; called before every measure of the container. */
    public void beginMeasure() {
        mIterations.clear();
        mLayouts = 0;
        mPass = -1;
        mIteration = 0;
        mDirect = null;
        mResolved = -1;
        mAxes = -1;
        mFirstMinimizeSeen = false;
        mTrivial = "-";
        mRows = mVars = mFree = mGoal = -1;
        mMeasures = 0;
        mCacheHits = 0;
        mTranscript.setLength(0);
        mExceptions.clear();
        mDepth = 0;
    }

    public void beginPass(int pass) {
        mLayouts++;
        mPass = pass;
        mIteration = 0;
        mIterations.add(0);
        if (trace != null) {
            trace.accept("PS " + pass);
        }
    }

    public void endPass() {
        mPass = -1;
    }

    @Override
    public void onReset() {
        if (mPass < 0) {
            return;
        }
        mIteration++;
        mIterations.set(mIterations.size() - 1, mIteration);
        if (mPass == 0 && mIteration == 1 && mDirect == null
                && mContainer.optimizeFor(Optimizer.OPTIMIZATION_DIRECT)) {
            dumpDirect();
        }
    }

    @Override
    public void onMinimize(ProbeSystem system) {
        if (mPass < 0) {
            return;
        }
        if (trace != null) {
            trace.accept("M " + mPass + " " + mIteration);
        }
        if (mPass == 0 && mIteration == 1 && !mFirstMinimizeSeen) {
            mFirstMinimizeSeen = true;
            mRows = system.rows();
            mVars = system.variables();
            mFree = system.freeVariables();
            mGoal = system.goalSize();
            mTrivial = (mRows == 0 && system.goalEmpty()) ? "1" : "0";
        }
    }

    /** Records an exception the solver loop printed: its toString and top frame. */
    public void addException(String text) {
        mExceptions.add(text);
    }

    public int exceptionCount() {
        return mExceptions.size();
    }

    /** Appends to the i-th printed exception the top frame of its stack trace. */
    public void attachFrames(java.util.List<String> frames) {
        for (int i = 0; i < mExceptions.size() && i < frames.size(); i++) {
            mExceptions.set(i, mExceptions.get(i) + " @ " + frames.get(i));
        }
    }

    // ------------------------------------------------------------------------------
    // Measure requests
    // ------------------------------------------------------------------------------

    /** The caller of a Measurer.measure call, from the identity of its Measure object. */
    public char sourceOf(BasicMeasure.Measure m) {
        if (m == DIRECT_MEASURE) {
            return 'D';
        }
        if (m == mContainer.basicMeasureMeasure()) {
            return mLayouts == 0 ? 'M' : 'R';
        }
        if (mContainer.isVirtualLayoutMeasure(m)) {
            return 'F';
        }
        if (mPass == 0 && mIteration == 0) {
            return 'P';
        }
        return 'X';
    }

    public void beforeMeasure(ConstraintWidget widget, BasicMeasure.Measure m) {
        mMeasures++;
        if (!recordTranscript) {
            return;
        }
        if (mDepth == mSrc.length) {
            int n = mDepth * 2;
            mSrc = java.util.Arrays.copyOf(mSrc, n);
            mStrategy = java.util.Arrays.copyOf(mStrategy, n);
            mHb = java.util.Arrays.copyOf(mHb, n);
            mVb = java.util.Arrays.copyOf(mVb, n);
            mHdim = java.util.Arrays.copyOf(mHdim, n);
            mVdim = java.util.Arrays.copyOf(mVdim, n);
        }
        int d = mDepth++;
        mSrc[d] = sourceOf(m);
        mStrategy[d] = m.measureStrategy;
        mHb[d] = m.horizontalBehavior;
        mVb[d] = m.verticalBehavior;
        mHdim[d] = m.horizontalDimension;
        mVdim[d] = m.verticalDimension;
    }

    public void cacheHit() {
        mCacheHits++;
    }

    public void afterMeasure(ConstraintWidget widget, BasicMeasure.Measure m, String detail) {
        if (!recordTranscript || mDepth == 0) {
            return;
        }
        int d = --mDepth;
        StringBuilder t = mTranscript;
        if (t.length() > 0) {
            t.append(' ');
        }
        // Entries appear when a request completes, so a VirtualLayout's member requests
        // come before the VirtualLayout's own entry.
        t.append(mSrc[d]).append(':').append(widget == null ? "?" : widget.getDebugName())
                .append(':').append(mStrategy[d]).append(':')
                .append(beh(mHb[d])).append(beh(mVb[d])).append(':')
                .append(mHdim[d]).append(',').append(mVdim[d]).append(':')
                .append(detail).append(':')
                .append(m.measuredWidth).append(',').append(m.measuredHeight).append(',')
                .append(m.measuredBaseline).append(',')
                .append(m.measuredHasBaseline ? '1' : '0')
                .append(m.measuredNeedsSolverPass ? '1' : '0');
    }

    static char beh(ConstraintWidget.DimensionBehaviour b) {
        if (b == null) {
            return '?';
        }
        switch (b) {
            case FIXED:
                return 'F';
            case WRAP_CONTENT:
                return 'W';
            case MATCH_CONSTRAINT:
                return 'M';
            case MATCH_PARENT:
                return 'P';
        }
        return '?';
    }

    // ------------------------------------------------------------------------------
    // Direct dump
    // ------------------------------------------------------------------------------

    private static String fv(ConstraintAnchor a) {
        return a.hasFinalValue() ? Integer.toString(a.getFinalValue()) : "_";
    }

    private void dumpDirect() {
        StringBuilder sb = new StringBuilder();
        int resolved = 0;
        int axes = 0;
        ArrayList<ConstraintWidget> children = mContainer.getChildren();
        for (int i = 0; i < children.size(); i++) {
            ConstraintWidget w = children.get(i);
            if (sb.length() > 0) {
                sb.append(' ');
            }
            sb.append(w.getDebugName()).append(':');
            if (w instanceof Guideline) {
                Guideline g = (Guideline) w;
                ConstraintAnchor a = g.getAnchor();
                sb.append('g').append(g.getOrientation()).append(':').append(fv(a));
                axes++;
                boolean r = g.getOrientation() == Guideline.VERTICAL
                        ? g.isResolvedHorizontally() : g.isResolvedVertically();
                if (r) {
                    resolved++;
                }
            } else if (w instanceof Barrier) {
                Barrier b = (Barrier) w;
                boolean rh = b.isResolvedHorizontally();
                boolean rv = b.isResolvedVertically();
                sb.append('b').append(b.getBarrierType()).append(':')
                        .append(rh ? 'h' : '-').append(rv ? 'v' : '-').append(':')
                        .append(fv(b.mLeft)).append(',').append(fv(b.mTop)).append(',')
                        .append(fv(b.mRight)).append(',').append(fv(b.mBottom));
                axes++;
                boolean r = b.getOrientation() == ConstraintWidget.HORIZONTAL ? rh : rv;
                if (r) {
                    resolved++;
                }
            } else {
                boolean rh = w.isResolvedHorizontally();
                boolean rv = w.isResolvedVertically();
                axes += 2;
                if (rh) {
                    resolved++;
                }
                if (rv) {
                    resolved++;
                }
                sb.append(rh ? 'h' : '-').append(rv ? 'v' : '-').append(':')
                        .append(fv(w.mLeft)).append(',').append(fv(w.mTop)).append(',')
                        .append(fv(w.mRight)).append(',').append(fv(w.mBottom)).append(',')
                        .append(fv(w.mBaseline)).append(':')
                        .append(ProbeContainer.rawWidth(w)).append('x')
                        .append(ProbeContainer.rawHeight(w)).append(':')
                        .append(w.getBaselineDistance()).append(w.hasBaseline() ? '+' : '-')
                        .append(':')
                        .append(w.isMeasureRequested() ? 'm' : '-')
                        .append(w.isHorizontalSolvingPassDone() ? 'H' : '-')
                        .append(w.isVerticalSolvingPassDone() ? 'V' : '-');
            }
        }
        mDirect = sb.toString();
        mResolved = resolved;
        mAxes = axes;
    }

    // ------------------------------------------------------------------------------
    // Fields (FORMATS.md 8.3 to 8.5)
    // ------------------------------------------------------------------------------

    public String summaryField(int level) {
        StringBuilder sb = new StringBuilder("P").append(level);
        sb.append(" passes=").append(mLayouts).append(" it=");
        if (mIterations.isEmpty()) {
            sb.append('-');
        }
        for (int i = 0; i < mIterations.size(); i++) {
            if (i > 0) {
                sb.append(',');
            }
            sb.append(mIterations.get(i));
        }
        sb.append(" triv=").append(mTrivial);
        sb.append(" rows=").append(num(mRows)).append(" vars=").append(num(mVars))
                .append(" free=").append(num(mFree)).append(" goal=").append(num(mGoal));
        sb.append(" res=");
        if (mAxes < 0) {
            sb.append('-');
        } else {
            sb.append(mResolved).append('/').append(mAxes);
        }
        sb.append(" meas=").append(mMeasures).append(" hits=").append(mCacheHits);
        sb.append(" ts=").append(mContainer.isWidthMeasuredTooSmall() ? '1' : '0')
                .append(mContainer.isHeightMeasuredTooSmall() ? '1' : '0');
        sb.append(" exc=").append(mExceptions.size());
        if (!mExceptions.isEmpty()) {
            sb.append(" excs=").append(String.join(" | ", mExceptions));
        }
        return clean(sb.toString());
    }

    public String directField(int level) {
        return "D" + level + " " + (mDirect == null ? "-" : mDirect);
    }

    public String transcriptField(int level) {
        return clean("T" + level + " " + (mTranscript.length() == 0 ? "-" : mTranscript.toString()));
    }

    private static String num(int v) {
        return v < 0 ? "-" : Integer.toString(v);
    }

    private static String clean(String s) {
        return s.replace('\t', ' ').replace('\n', ' ').replace('\r', ' ');
    }
}
