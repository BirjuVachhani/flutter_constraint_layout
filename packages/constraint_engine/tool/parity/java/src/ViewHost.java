import androidx.constraintlayout.core.widgets.Barrier;
import androidx.constraintlayout.core.widgets.ConstraintAnchor;
import androidx.constraintlayout.core.widgets.ConstraintWidget;
import androidx.constraintlayout.core.widgets.ConstraintWidgetContainer;
import androidx.constraintlayout.core.widgets.Guideline;
import androidx.constraintlayout.core.widgets.Optimizer;
import androidx.constraintlayout.core.widgets.VirtualLayout;
import androidx.constraintlayout.core.widgets.analyzer.BasicMeasure;
import androidx.constraintlayout.core.widgets.analyzer.DirectProbe;

import java.util.ArrayList;

/**
 * Phase 0 oracle (p0-java): the view layer of ConstraintLayout at the pin
 * (constraintlayout/src/main/java/androidx/constraintlayout/widget/ConstraintLayout.java,
 * "CL" below), ported for the op-list oracle. The widgets are built by the op list (the
 * result of setChildrenConstraints); this class runs what onMeasure does with them.
 *
 * ViewHost.measure ports onMeasure's fresh path (CL 1768-1879), resolveSystem
 * (CL 1681-1721), setSelfDimensionBehaviour (CL 1907-1981) and resolveMeasuredDimension
 * (CL 1733-1763). ViewMeasurer ports ConstraintLayout.Measurer (CL 680-1039), with
 * CACHE_MEASURES. MeasureSpec, getChildMeasureSpec and resolveSizeAndState follow AOSP's
 * View and ViewGroup. ContentView is the child view: a pure function of its specs
 * (FORMATS.md 6.1) or the view Flow (helper/widget/Flow.java onMeasure).
 */
final class ViewHost {

    // ------------------------------------------------------------------------------
    // android.view.View.MeasureSpec and View constants (AOSP)
    // ------------------------------------------------------------------------------

    static final int MODE_SHIFT = 30;
    static final int MODE_MASK = 0x3 << MODE_SHIFT;
    static final int UNSPECIFIED = 0;
    static final int EXACTLY = 1 << MODE_SHIFT;
    static final int AT_MOST = 2 << MODE_SHIFT;

    static final int MEASURED_SIZE_MASK = 0x00ffffff;
    static final int MEASURED_STATE_MASK = 0xff000000;
    static final int MEASURED_STATE_TOO_SMALL = 0x01000000;
    static final int MEASURED_HEIGHT_STATE_SHIFT = 16;

    /** ViewGroup.LayoutParams.MATCH_PARENT and WRAP_CONTENT. */
    static final int LP_MATCH_PARENT = -1;
    static final int LP_WRAP_CONTENT = -2;

    /** View.sUseZeroUnspecifiedMeasureSpec: false for targetSdk 23 and later. */
    static final boolean USE_ZERO_UNSPECIFIED_MEASURE_SPEC = false;

    static int makeMeasureSpec(int size, int mode) {
        return (size & ~MODE_MASK) | (mode & MODE_MASK);
    }

    static int getMode(int measureSpec) {
        return measureSpec & MODE_MASK;
    }

    static int getSize(int measureSpec) {
        return measureSpec & ~MODE_MASK;
    }

    static String specString(int spec) {
        int mode = getMode(spec);
        char m = mode == EXACTLY ? 'E' : mode == AT_MOST ? 'A' : mode == UNSPECIFIED ? 'U' : '?';
        return m + Integer.toString(getSize(spec));
    }

    /** ViewGroup.getChildMeasureSpec (AOSP). */
    static int getChildMeasureSpec(int spec, int padding, int childDimension) {
        int specMode = getMode(spec);
        int specSize = getSize(spec);
        int size = Math.max(0, specSize - padding);
        int resultSize = 0;
        int resultMode = 0;
        switch (specMode) {
            case EXACTLY:
                if (childDimension >= 0) {
                    resultSize = childDimension;
                    resultMode = EXACTLY;
                } else if (childDimension == LP_MATCH_PARENT) {
                    resultSize = size;
                    resultMode = EXACTLY;
                } else if (childDimension == LP_WRAP_CONTENT) {
                    resultSize = size;
                    resultMode = AT_MOST;
                }
                break;
            case AT_MOST:
                if (childDimension >= 0) {
                    resultSize = childDimension;
                    resultMode = EXACTLY;
                } else if (childDimension == LP_MATCH_PARENT) {
                    resultSize = size;
                    resultMode = AT_MOST;
                } else if (childDimension == LP_WRAP_CONTENT) {
                    resultSize = size;
                    resultMode = AT_MOST;
                }
                break;
            case UNSPECIFIED:
                if (childDimension >= 0) {
                    resultSize = childDimension;
                    resultMode = EXACTLY;
                } else if (childDimension == LP_MATCH_PARENT) {
                    resultSize = USE_ZERO_UNSPECIFIED_MEASURE_SPEC ? 0 : size;
                    resultMode = UNSPECIFIED;
                } else if (childDimension == LP_WRAP_CONTENT) {
                    resultSize = USE_ZERO_UNSPECIFIED_MEASURE_SPEC ? 0 : size;
                    resultMode = UNSPECIFIED;
                }
                break;
        }
        return makeMeasureSpec(resultSize, resultMode);
    }

    /** View.resolveSizeAndState (AOSP). */
    static int resolveSizeAndState(int size, int measureSpec, int childMeasuredState) {
        final int specMode = getMode(measureSpec);
        final int specSize = getSize(measureSpec);
        final int result;
        switch (specMode) {
            case AT_MOST:
                if (specSize < size) {
                    result = specSize | MEASURED_STATE_TOO_SMALL;
                } else {
                    result = size;
                }
                break;
            case EXACTLY:
                result = specSize;
                break;
            case UNSPECIFIED:
            default:
                result = size;
        }
        return result | (childMeasuredState & MEASURED_STATE_MASK);
    }

    // ------------------------------------------------------------------------------
    // Child views
    // ------------------------------------------------------------------------------

    /** A child view: content per FORMATS.md 6.1, or the view Flow of a VirtualLayout. */
    static final class ContentView {
        static final int NONE = 0;
        static final int BOX = 1;
        static final int TEXT = 2;
        static final int FLOW = 3;

        int kind = NONE;
        int contentWidth;
        int contentHeight;
        int contentBaseline = -1;
        VirtualLayout flow;

        /** LayoutParams.mNeedsBaseline: set by setWidgetBaseline, never cleared. */
        boolean needsBaseline;

        // View state: a fresh view is measured 0 x 0 and reports no baseline.
        private int mMeasuredWidth;
        private int mMeasuredHeight;
        private int mBaseline = -1;

        void setContent(String k, int w, int h, int baseline) {
            if (kind == FLOW) {
                return; // the Flow helper is not a content view
            }
            switch (k) {
                case "box":
                    kind = BOX;
                    break;
                case "text":
                    kind = TEXT;
                    break;
                case "none":
                    kind = NONE;
                    break;
                default:
                    throw new IllegalArgumentException("content kind " + k);
            }
            contentWidth = w;
            contentHeight = h;
            contentBaseline = baseline;
        }

        /** FORMATS.md 6.1 resolve(n, spec). */
        static int resolve(int n, int spec) {
            int mode = getMode(spec);
            int size = getSize(spec);
            if (mode == EXACTLY) {
                return size;
            }
            if (mode == AT_MOST) {
                return Math.min(n, size);
            }
            return n;
        }

        /** View.getDefaultSize(0, spec): a bare View. */
        static int defaultSize(int spec) {
            int mode = getMode(spec);
            if (mode == AT_MOST || mode == EXACTLY) {
                return getSize(spec);
            }
            return 0;
        }

        /** View.measure: onMeasure then setMeasuredDimension, as a pure function. */
        void measure(int widthSpec, int heightSpec) {
            int w;
            int h;
            int b;
            switch (kind) {
                case BOX:
                    w = resolve(contentWidth, widthSpec);
                    h = resolve(contentHeight, heightSpec);
                    b = contentBaseline;
                    break;
                case TEXT: {
                    w = resolve(contentWidth, widthSpec);
                    int nat = w <= 0 ? contentHeight * 50
                            : contentHeight * ((contentWidth + w - 1) / w);
                    h = resolve(nat, heightSpec);
                    b = contentBaseline;
                    break;
                }
                case FLOW:
                    // helper/widget/Flow.onMeasure(VirtualLayout, widthSpec, heightSpec)
                    flow.measure(getMode(widthSpec), getSize(widthSpec),
                            getMode(heightSpec), getSize(heightSpec));
                    w = flow.getMeasuredWidth();
                    h = flow.getMeasuredHeight();
                    b = -1; // View.getBaseline()
                    break;
                default:
                    w = defaultSize(widthSpec);
                    h = defaultSize(heightSpec);
                    b = -1;
                    break;
            }
            mMeasuredWidth = w;
            mMeasuredHeight = h;
            mBaseline = b;
        }

        int getMeasuredWidth() {
            return mMeasuredWidth & MEASURED_SIZE_MASK;
        }

        int getMeasuredHeight() {
            return mMeasuredHeight & MEASURED_SIZE_MASK;
        }

        int getBaseline() {
            return mBaseline;
        }
    }

    static ContentView viewOf(ConstraintWidget widget) {
        return (ContentView) widget.getCompanionWidget();
    }

    // ------------------------------------------------------------------------------
    // ConstraintLayout.Measurer (CL 680-1039)
    // ------------------------------------------------------------------------------

    static final class ViewMeasurer implements BasicMeasure.Measurer {
        final ViewHost mHost;
        int mPaddingTop;
        int mPaddingBottom;
        int mPaddingWidth;
        int mPaddingHeight;
        int mLayoutWidthSpec;
        int mLayoutHeightSpec;


        ViewMeasurer(ViewHost host) {
            mHost = host;
        }

        void captureLayoutInfo(int widthSpec, int heightSpec, int top, int bottom,
                int width, int height) {
            mPaddingTop = top;
            mPaddingBottom = bottom;
            mPaddingWidth = width;
            mPaddingHeight = height;
            mLayoutWidthSpec = widthSpec;
            mLayoutHeightSpec = heightSpec;
        }

        @Override
        public final void measure(ConstraintWidget widget, BasicMeasure.Measure measure) {
            DirectProbe probe = mHost.mProbe;
            boolean record = probe != null && probe.recordTranscript;
            if (probe != null) {
                probe.beforeMeasure(widget, measure);
            }
            // Transcript detail of this request (FORMATS.md 8.5); a local, because a
            // VirtualLayout measures its members from inside its own request.
            StringBuilder detail = new StringBuilder();
            measureImpl(widget, measure, record, detail);
            if (probe != null) {
                probe.afterMeasure(widget, measure, detail.toString());
            }
        }

        private void childMeasure(ContentView child, int horizontalSpec, int verticalSpec,
                boolean record, StringBuilder detail) {
            if (record) {
                if (detail.length() > 0) {
                    detail.append('+');
                }
                detail.append(specString(horizontalSpec)).append('/')
                        .append(specString(verticalSpec));
            }
            child.measure(horizontalSpec, verticalSpec);
        }

        private void measureImpl(ConstraintWidget widget, BasicMeasure.Measure measure,
                boolean record, StringBuilder mDetail) {
            if (widget == null) {
                mDetail.append('n');
                return;
            }
            if (widget.getVisibility() == ConstraintWidget.GONE && !widget.isInPlaceholder()) {
                measure.measuredWidth = 0;
                measure.measuredHeight = 0;
                measure.measuredBaseline = 0;
                mDetail.append('g');
                return;
            }
            if (widget.getParent() == null) {
                mDetail.append('n');
                return;
            }

            ConstraintWidget.DimensionBehaviour horizontalBehavior = measure.horizontalBehavior;
            ConstraintWidget.DimensionBehaviour verticalBehavior = measure.verticalBehavior;

            int horizontalDimension = measure.horizontalDimension;
            int verticalDimension = measure.verticalDimension;

            int horizontalSpec = 0;
            int verticalSpec = 0;

            int heightPadding = mPaddingTop + mPaddingBottom;
            int widthPadding = mPaddingWidth;

            ContentView child = viewOf(widget);

            switch (horizontalBehavior) {
                case FIXED: {
                    horizontalSpec = makeMeasureSpec(horizontalDimension, EXACTLY);
                }
                break;
                case WRAP_CONTENT: {
                    horizontalSpec = getChildMeasureSpec(mLayoutWidthSpec,
                            widthPadding, LP_WRAP_CONTENT);
                }
                break;
                case MATCH_PARENT: {
                    // Horizontal spec must account for margin as well as padding here.
                    horizontalSpec = getChildMeasureSpec(mLayoutWidthSpec,
                            widthPadding + widget.getHorizontalMargin(),
                            LP_MATCH_PARENT);
                }
                break;
                case MATCH_CONSTRAINT: {
                    horizontalSpec = getChildMeasureSpec(mLayoutWidthSpec,
                            widthPadding, LP_WRAP_CONTENT);
                    boolean shouldDoWrap = widget.mMatchConstraintDefaultWidth
                            == ConstraintWidget.MATCH_CONSTRAINT_WRAP;
                    if (measure.measureStrategy == BasicMeasure.Measure.TRY_GIVEN_DIMENSIONS
                            || measure.measureStrategy
                            == BasicMeasure.Measure.USE_GIVEN_DIMENSIONS) {
                        boolean otherDimensionStable = child.getMeasuredHeight()
                                == widget.getHeight();
                        boolean useCurrent = measure.measureStrategy
                                == BasicMeasure.Measure.USE_GIVEN_DIMENSIONS
                                || !shouldDoWrap
                                || (shouldDoWrap && otherDimensionStable)
                                || widget.isResolvedHorizontally();
                        if (useCurrent) {
                            horizontalSpec = makeMeasureSpec(widget.getWidth(), EXACTLY);
                        }
                    }
                }
                break;
            }

            switch (verticalBehavior) {
                case FIXED: {
                    verticalSpec = makeMeasureSpec(verticalDimension, EXACTLY);
                }
                break;
                case WRAP_CONTENT: {
                    verticalSpec = getChildMeasureSpec(mLayoutHeightSpec,
                            heightPadding, LP_WRAP_CONTENT);
                }
                break;
                case MATCH_PARENT: {
                    // Vertical spec must account for margin as well as padding here.
                    verticalSpec = getChildMeasureSpec(mLayoutHeightSpec,
                            heightPadding + widget.getVerticalMargin(),
                            LP_MATCH_PARENT);
                }
                break;
                case MATCH_CONSTRAINT: {
                    verticalSpec = getChildMeasureSpec(mLayoutHeightSpec,
                            heightPadding, LP_WRAP_CONTENT);
                    boolean shouldDoWrap = widget.mMatchConstraintDefaultHeight
                            == ConstraintWidget.MATCH_CONSTRAINT_WRAP;
                    if (measure.measureStrategy == BasicMeasure.Measure.TRY_GIVEN_DIMENSIONS
                            || measure.measureStrategy
                            == BasicMeasure.Measure.USE_GIVEN_DIMENSIONS) {
                        boolean otherDimensionStable = child.getMeasuredWidth()
                                == widget.getWidth();
                        boolean useCurrent = measure.measureStrategy
                                == BasicMeasure.Measure.USE_GIVEN_DIMENSIONS
                                || !shouldDoWrap
                                || (shouldDoWrap && otherDimensionStable)
                                || widget.isResolvedVertically();
                        if (useCurrent) {
                            verticalSpec = makeMeasureSpec(widget.getHeight(), EXACTLY);
                        }
                    }
                }
                break;
            }

            ConstraintWidgetContainer container = (ConstraintWidgetContainer) widget.getParent();
            if (container != null && Optimizer.enabled(mHost.mOptimizationLevel,
                    Optimizer.OPTIMIZATION_CACHE_MEASURES)) {
                if (child.getMeasuredWidth() == widget.getWidth()
                        && child.getMeasuredWidth() < container.getWidth()
                        && child.getMeasuredHeight() == widget.getHeight()
                        && child.getMeasuredHeight() < container.getHeight()
                        && child.getBaseline() == widget.getBaselineDistance()
                        && !widget.isMeasureRequested()
                ) {
                    boolean similar = isSimilarSpec(widget.getLastHorizontalMeasureSpec(),
                            horizontalSpec, widget.getWidth())
                            && isSimilarSpec(widget.getLastVerticalMeasureSpec(),
                            verticalSpec, widget.getHeight());
                    if (similar) {
                        measure.measuredWidth = widget.getWidth();
                        measure.measuredHeight = widget.getHeight();
                        measure.measuredBaseline = widget.getBaselineDistance();
                        mDetail.append('c');
                        if (mHost.mProbe != null) {
                            mHost.mProbe.cacheHit();
                        }
                        return;
                    }
                }
            }

            boolean horizontalMatchConstraints = (horizontalBehavior
                    == ConstraintWidget.DimensionBehaviour.MATCH_CONSTRAINT);
            boolean verticalMatchConstraints = (verticalBehavior
                    == ConstraintWidget.DimensionBehaviour.MATCH_CONSTRAINT);

            boolean verticalDimensionKnown = (verticalBehavior
                    == ConstraintWidget.DimensionBehaviour.MATCH_PARENT
                    || verticalBehavior == ConstraintWidget.DimensionBehaviour.FIXED);
            boolean horizontalDimensionKnown = (horizontalBehavior
                    == ConstraintWidget.DimensionBehaviour.MATCH_PARENT
                    || horizontalBehavior == ConstraintWidget.DimensionBehaviour.FIXED);
            boolean horizontalUseRatio = horizontalMatchConstraints && widget.mDimensionRatio > 0;
            boolean verticalUseRatio = verticalMatchConstraints && widget.mDimensionRatio > 0;

            if (child == null) {
                return;
            }

            int width = 0;
            int height = 0;
            int baseline = 0;

            if ((measure.measureStrategy == BasicMeasure.Measure.TRY_GIVEN_DIMENSIONS
                    || measure.measureStrategy == BasicMeasure.Measure.USE_GIVEN_DIMENSIONS)
                    || !(horizontalMatchConstraints
                    && widget.mMatchConstraintDefaultWidth
                    == ConstraintWidget.MATCH_CONSTRAINT_SPREAD
                    && verticalMatchConstraints
                    && widget.mMatchConstraintDefaultHeight
                    == ConstraintWidget.MATCH_CONSTRAINT_SPREAD)) {

                // The VirtualLayout branch (child.onMeasure(layout, specs)) and
                // child.measure(specs) are the same call for a ContentView.
                childMeasure(child, horizontalSpec, verticalSpec, record, mDetail);
                widget.setLastMeasureSpec(horizontalSpec, verticalSpec);

                int w = child.getMeasuredWidth();
                int h = child.getMeasuredHeight();
                baseline = child.getBaseline();

                width = w;
                height = h;

                if (widget.mMatchConstraintMinWidth > 0) {
                    width = Math.max(widget.mMatchConstraintMinWidth, width);
                }
                if (widget.mMatchConstraintMaxWidth > 0) {
                    width = Math.min(widget.mMatchConstraintMaxWidth, width);
                }
                if (widget.mMatchConstraintMinHeight > 0) {
                    height = Math.max(widget.mMatchConstraintMinHeight, height);
                }
                if (widget.mMatchConstraintMaxHeight > 0) {
                    height = Math.min(widget.mMatchConstraintMaxHeight, height);
                }

                boolean optimizeDirect = Optimizer.enabled(mHost.mOptimizationLevel,
                        Optimizer.OPTIMIZATION_DIRECT);
                if (!optimizeDirect) {
                    if (horizontalUseRatio && verticalDimensionKnown) {
                        float ratio = widget.mDimensionRatio;
                        width = (int) (0.5f + height * ratio);
                    } else if (verticalUseRatio && horizontalDimensionKnown) {
                        float ratio = widget.mDimensionRatio;
                        height = (int) (0.5f + width / ratio);
                    }
                }

                if (w != width || h != height) {
                    if (w != width) {
                        horizontalSpec = makeMeasureSpec(width, EXACTLY);
                    }
                    if (h != height) {
                        verticalSpec = makeMeasureSpec(height, EXACTLY);
                    }
                    childMeasure(child, horizontalSpec, verticalSpec, record, mDetail);

                    widget.setLastMeasureSpec(horizontalSpec, verticalSpec);
                    width = child.getMeasuredWidth();
                    height = child.getMeasuredHeight();
                    baseline = child.getBaseline();
                }

            } else {
                mDetail.append('s');
            }

            boolean hasBaseline = baseline != -1;

            measure.measuredNeedsSolverPass = (width != measure.horizontalDimension)
                    || (height != measure.verticalDimension);
            if (child.needsBaseline) {
                hasBaseline = true;
            }
            if (hasBaseline && baseline != -1 && widget.getBaselineDistance() != baseline) {
                measure.measuredNeedsSolverPass = true;
            }
            measure.measuredWidth = width;
            measure.measuredHeight = height;
            measure.measuredHasBaseline = hasBaseline;
            measure.measuredBaseline = baseline;
        }

        /** CL 1009-1019. */
        private boolean isSimilarSpec(int lastMeasureSpec, int spec, int widgetSize) {
            if (lastMeasureSpec == spec) {
                return true;
            }
            int lastMode = getMode(lastMeasureSpec);
            int mode = getMode(spec);
            int size = getSize(spec);
            return mode == EXACTLY
                    && (lastMode == AT_MOST || lastMode == UNSPECIFIED)
                    && widgetSize == size;
        }

        @Override
        public final void didMeasures() {
            // CL 1022-1038: Placeholders and helpers' updatePostMeasure; none of the
            // helpers the oracle builds (Barrier, Guideline, Flow) does anything there.
        }
    }

    // ------------------------------------------------------------------------------
    // The layout view
    // ------------------------------------------------------------------------------

    final ConstraintWidgetContainer mLayoutWidget;
    final ViewMeasurer mMeasurer;
    final DirectProbe mProbe;
    int mOptimizationLevel = Optimizer.OPTIMIZATION_STANDARD;

    // android:padding (physical, resolved) and android:min/maxWidth, min/maxHeight.
    int mPaddingLeft;
    int mPaddingTop;
    int mPaddingRight;
    int mPaddingBottom;
    int mMinWidth = 0;
    int mMinHeight = 0;
    int mMaxWidth = Integer.MAX_VALUE;
    int mMaxHeight = Integer.MAX_VALUE;

    int mLastMeasureWidth = 0;
    int mLastMeasureHeight = 0;
    /** setMeasuredDimension's arguments (size with the MEASURED_STATE bits). */
    int mMeasuredWidthAndState;
    int mMeasuredHeightAndState;

    ViewHost(ConstraintWidgetContainer layoutWidget, DirectProbe probe) {
        mLayoutWidget = layoutWidget;
        mProbe = probe;
        mMeasurer = new ViewMeasurer(this);
        mLayoutWidget.setMeasurer(mMeasurer);
    }

    int getMeasuredWidth() {
        return mMeasuredWidthAndState & MEASURED_SIZE_MASK;
    }

    int getMeasuredHeight() {
        return mMeasuredHeightAndState & MEASURED_SIZE_MASK;
    }

    /**
     * The hierarchy state onMeasure's setChildrenConstraints leaves that the op list does
     * not set itself: the visibility of helper widgets (CL 1371, `widget.setVisibility(
     * child.getVisibility())`, where the view Guideline and Barrier are always GONE: their
     * constructors call super.setVisibility(GONE) and Guideline's setVisibility is empty),
     * LayoutParams.mNeedsBaseline (CL 1598-1620, sticky) and the VirtualLayout members
     * (ConstraintHelper.updatePreLayout, CH 508-541).
     */
    private void syncHierarchy() {
        ArrayList<ConstraintWidget> children = mLayoutWidget.getChildren();
        for (int i = 0; i < children.size(); i++) {
            ConstraintWidget c = children.get(i);
            if (c instanceof Guideline || c instanceof Barrier) {
                c.setVisibility(ConstraintWidget.GONE);
            }
        }
        for (int i = 0; i < children.size(); i++) {
            ConstraintWidget c = children.get(i);
            ConstraintAnchor target = c.mBaseline.mTarget;
            if (target == null) {
                continue;
            }
            ContentView v = viewOf(c);
            if (v != null) {
                v.needsBaseline = true;
            }
            if (target.getType() == ConstraintAnchor.Type.BASELINE) {
                ContentView tv = viewOf(target.getOwner());
                if (tv != null && target.getOwner() != mLayoutWidget) {
                    tv.needsBaseline = true;
                }
            }
        }
        for (int i = 0; i < children.size(); i++) {
            ConstraintWidget c = children.get(i);
            if (c instanceof VirtualLayout) {
                ((VirtualLayout) c).updateConstraints(mLayoutWidget);
            }
        }
    }

    /** ConstraintLayout.onMeasure (CL 1768-1879), fresh path. */
    void measure(int widthMeasureSpec, int heightMeasureSpec) {
        mLayoutWidget.setOptimizationLevel(mOptimizationLevel);
        syncHierarchy();
        mLayoutWidget.updateHierarchy();
        resolveSystem(mLayoutWidget, mOptimizationLevel, widthMeasureSpec, heightMeasureSpec);
        resolveMeasuredDimension(widthMeasureSpec, heightMeasureSpec,
                mLayoutWidget.getWidth(), mLayoutWidget.getHeight(),
                mLayoutWidget.isWidthMeasuredTooSmall(), mLayoutWidget.isHeightMeasuredTooSmall());
    }

    /** CL 1894-1905, with start and end resolved to left and right. */
    private int getPaddingWidth() {
        int widthPadding = Math.max(0, mPaddingLeft) + Math.max(0, mPaddingRight);
        int rtlPadding = Math.max(0, mPaddingLeft) + Math.max(0, mPaddingRight);
        if (rtlPadding > 0) {
            widthPadding = rtlPadding;
        }
        return widthPadding;
    }

    /** CL 1681-1721. */
    private void resolveSystem(ConstraintWidgetContainer layout, int optimizationLevel,
            int widthMeasureSpec, int heightMeasureSpec) {
        int widthMode = getMode(widthMeasureSpec);
        int widthSize = getSize(widthMeasureSpec);
        int heightMode = getMode(heightMeasureSpec);
        int heightSize = getSize(heightMeasureSpec);

        int paddingY = Math.max(0, mPaddingTop);
        int paddingBottom = Math.max(0, mPaddingBottom);
        int paddingHeight = paddingY + paddingBottom;
        int paddingWidth = getPaddingWidth();
        int paddingX;
        mMeasurer.captureLayoutInfo(widthMeasureSpec, heightMeasureSpec, paddingY, paddingBottom,
                paddingWidth, paddingHeight);

        // getPaddingStart/End resolve to left/right (RTL: start = right, end = left), so
        // paddingX is the left padding in both directions.
        int paddingStart = Math.max(0, layout.isRtl() ? mPaddingRight : mPaddingLeft);
        int paddingEnd = Math.max(0, layout.isRtl() ? mPaddingLeft : mPaddingRight);
        if (paddingStart > 0 || paddingEnd > 0) {
            if (layout.isRtl()) {
                paddingX = paddingEnd;
            } else {
                paddingX = paddingStart;
            }
        } else {
            paddingX = Math.max(0, mPaddingLeft);
        }

        widthSize -= paddingWidth;
        heightSize -= paddingHeight;

        setSelfDimensionBehaviour(layout, widthMode, widthSize, heightMode, heightSize);

        layout.measure(optimizationLevel, widthMode, widthSize, heightMode, heightSize,
                mLastMeasureWidth, mLastMeasureHeight, paddingX, paddingY);
    }

    /** CL 1733-1763. */
    private void resolveMeasuredDimension(int widthMeasureSpec, int heightMeasureSpec,
            int measuredWidth, int measuredHeight,
            boolean isWidthMeasuredTooSmall, boolean isHeightMeasuredTooSmall) {
        int childState = 0;
        int heightPadding = mMeasurer.mPaddingHeight;
        int widthPadding = mMeasurer.mPaddingWidth;

        int androidLayoutWidth = measuredWidth + widthPadding;
        int androidLayoutHeight = measuredHeight + heightPadding;

        int resolvedWidthSize = resolveSizeAndState(androidLayoutWidth,
                widthMeasureSpec, childState);
        int resolvedHeightSize = resolveSizeAndState(androidLayoutHeight, heightMeasureSpec,
                childState << MEASURED_HEIGHT_STATE_SHIFT);
        resolvedWidthSize &= MEASURED_SIZE_MASK;
        resolvedHeightSize &= MEASURED_SIZE_MASK;
        resolvedWidthSize = Math.min(mMaxWidth, resolvedWidthSize);
        resolvedHeightSize = Math.min(mMaxHeight, resolvedHeightSize);
        if (isWidthMeasuredTooSmall) {
            resolvedWidthSize |= MEASURED_STATE_TOO_SMALL;
        }
        if (isHeightMeasuredTooSmall) {
            resolvedHeightSize |= MEASURED_STATE_TOO_SMALL;
        }
        mMeasuredWidthAndState = resolvedWidthSize;
        mMeasuredHeightAndState = resolvedHeightSize;
        mLastMeasureWidth = resolvedWidthSize;
        mLastMeasureHeight = resolvedHeightSize;
    }

    /** CL 1907-1981. */
    private void setSelfDimensionBehaviour(ConstraintWidgetContainer layout,
            int widthMode, int widthSize, int heightMode, int heightSize) {
        int heightPadding = mMeasurer.mPaddingHeight;
        int widthPadding = mMeasurer.mPaddingWidth;

        ConstraintWidget.DimensionBehaviour widthBehaviour =
                ConstraintWidget.DimensionBehaviour.FIXED;
        ConstraintWidget.DimensionBehaviour heightBehaviour =
                ConstraintWidget.DimensionBehaviour.FIXED;

        int desiredWidth = 0;
        int desiredHeight = 0;
        final int childCount = layout.getChildren().size();

        switch (widthMode) {
            case AT_MOST: {
                widthBehaviour = ConstraintWidget.DimensionBehaviour.WRAP_CONTENT;
                desiredWidth = widthSize;
                if (childCount == 0) {
                    desiredWidth = Math.max(0, mMinWidth);
                }
            }
            break;
            case UNSPECIFIED: {
                widthBehaviour = ConstraintWidget.DimensionBehaviour.WRAP_CONTENT;
                if (childCount == 0) {
                    desiredWidth = Math.max(0, mMinWidth);
                }
            }
            break;
            case EXACTLY: {
                desiredWidth = Math.min(mMaxWidth - widthPadding, widthSize);
            }
        }
        switch (heightMode) {
            case AT_MOST: {
                heightBehaviour = ConstraintWidget.DimensionBehaviour.WRAP_CONTENT;
                desiredHeight = heightSize;
                if (childCount == 0) {
                    desiredHeight = Math.max(0, mMinHeight);
                }
            }
            break;
            case UNSPECIFIED: {
                heightBehaviour = ConstraintWidget.DimensionBehaviour.WRAP_CONTENT;
                if (childCount == 0) {
                    desiredHeight = Math.max(0, mMinHeight);
                }
            }
            break;
            case EXACTLY: {
                desiredHeight = Math.min(mMaxHeight - heightPadding, heightSize);
            }
        }

        if (desiredWidth != layout.getWidth() || desiredHeight != layout.getHeight()) {
            layout.invalidateMeasures();
        }
        layout.setX(0);
        layout.setY(0);
        layout.setMaxWidth(mMaxWidth - widthPadding);
        layout.setMaxHeight(mMaxHeight - heightPadding);
        layout.setMinWidth(0);
        layout.setMinHeight(0);
        layout.setHorizontalDimensionBehaviour(widthBehaviour);
        layout.setWidth(desiredWidth);
        layout.setVerticalDimensionBehaviour(heightBehaviour);
        layout.setHeight(desiredHeight);
        layout.setMinWidth(mMinWidth - widthPadding);
        layout.setMinHeight(mMinHeight - heightPadding);
    }
}
