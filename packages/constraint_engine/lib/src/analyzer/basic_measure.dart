// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.BasicMeasure
// (upstream pinned in UPSTREAM.md). Metrics are omitted.

import 'dart:math' as math;

import '../barrier.dart';
import '../constraint_widget.dart';
import '../constraint_widget_container.dart';
import '../guideline.dart';
import '../helper.dart';
import '../optimizer.dart';
import '../virtual_layout.dart';

/// The host callback used to measure intrinsic child sizes.
/// In Flutter this is implemented by calling `RenderBox.layout`.
abstract class Measurer {
  /// Measure [widget] as [measure] requests, and write the result to its
  /// outputs.
  ///
  /// Report the content's natural size on a [DimensionBehaviour.wrapContent]
  /// axis (and on a [ConstraintWidget.MATCH_CONSTRAINT_WRAP] one, except on a
  /// re-measure after a solve; see [Measure.TRY_GIVEN_DIMENSIONS]), and the
  /// proposed size on the others. Set [Measure.measuredWidth],
  /// [Measure.measuredHeight], [Measure.measuredBaseline], and
  /// [Measure.measuredHasBaseline] on every call: the engine reuses its
  /// [Measure] objects, then copies the outputs onto [widget].
  ///
  /// Like Android's view measurer, keep each measured size within the
  /// widget's match-constraint min and max
  /// ([ConstraintWidget.mMatchConstraintMinWidth] and the like, where 0 means
  /// no bound), measuring the content again when that changes a size. The
  /// dependency graph measures a match-constraint axis with a single anchor
  /// as wrap content and resolves it at the reported size, while the solver
  /// applies the bounds itself.
  ///
  /// A [VirtualLayout] arranges its widgets in its own
  /// [VirtualLayout.measure], which only a measurer runs: call it, with
  /// [BasicMeasure.EXACTLY] and the proposed size on a fixed axis and on a
  /// match-constraint axis that is measured again after a solve, and report
  /// [VirtualLayout.getMeasuredWidth] and [VirtualLayout.getMeasuredHeight].
  void measure(ConstraintWidget widget, Measure measure);

  /// Called after [BasicMeasure] has measured all the children of a
  /// container, on the [ConstraintWidgetContainer.measure] path.
  /// [ConstraintWidgetContainer.layout] never calls it.
  void didMeasures();
}

/// The request and the result of one [Measurer.measure] call.
///
/// The engine fills in the request ([horizontalBehavior],
/// [verticalBehavior], [horizontalDimension], [verticalDimension], and
/// [measureStrategy]), and the measurer writes the `measured` outputs.
class Measure {
  /// Measure strategy of a measure made before the solver has sized the
  /// widget: a match-constraint axis is measured from its content.
  static const int SELF_DIMENSIONS = 0;

  /// Measure strategy after a solver pass: a match-constraint axis should be
  /// measured at the proposed size, unless the measurer has reason to
  /// measure its content again (as Android's does for a
  /// [ConstraintWidget.MATCH_CONSTRAINT_WRAP] axis whose other axis changed).
  static const int TRY_GIVEN_DIMENSIONS = 1;

  /// Measure strategy that requires a match-constraint axis to be measured
  /// at the proposed size, used for the last re-measure.
  static const int USE_GIVEN_DIMENSIONS = 2;

  /// Request: how the width is measured. Usually the widget's own
  /// behaviour, but the engine may pass another, such as
  /// [DimensionBehaviour.fixed] for a match-constraint axis it has resolved.
  DimensionBehaviour? horizontalBehavior;

  /// Request: how the height is measured. Usually the widget's own
  /// behaviour, but the engine may pass another, such as
  /// [DimensionBehaviour.fixed] for a match-constraint axis it has resolved.
  DimensionBehaviour? verticalBehavior;

  /// Request: the width the engine proposes. On a wrap-content axis it is
  /// not a limit: it holds the widget's stored width or 0.
  int horizontalDimension = 0;

  /// Request: the height the engine proposes. On a wrap-content axis it is
  /// not a limit: it holds the widget's stored height or 0.
  int verticalDimension = 0;

  /// Result: the measured width.
  int measuredWidth = 0;

  /// Result: the measured height.
  int measuredHeight = 0;

  /// Result: the baseline's distance from the top of the measured widget, or
  /// 0 for none.
  int measuredBaseline = 0;

  /// Result: whether the widget has a baseline. Report it together with
  /// [measuredBaseline]: the engine marks the widget as having a baseline
  /// when [measuredBaseline] is positive (see
  /// [ConstraintWidget.setBaselineDistance]).
  bool measuredHasBaseline = false;

  /// Result: true to ask [BasicMeasure] for another solver pass, as
  /// Android's measurer does when the measured size differs from the
  /// proposed one. [BasicMeasure.measure] clears it before each call.
  bool measuredNeedsSolverPass = false;

  /// Request: [SELF_DIMENSIONS], [TRY_GIVEN_DIMENSIONS], or
  /// [USE_GIVEN_DIMENSIONS].
  int measureStrategy = 0;
}

/// Implements basic measure for linear resolution: the passes of
/// [ConstraintWidgetContainer.measure], which measure the children through
/// the container's [Measurer], solve the layout, and measure again the
/// children whose size depends on the result.
class BasicMeasure {
  /// The bit shift of the mode in an Android `MeasureSpec`, used to build
  /// [EXACTLY] and [AT_MOST].
  static const int MODE_SHIFT = 30;

  /// Measure mode with no constraint on the size (Android's
  /// `MeasureSpec.UNSPECIFIED`).
  static const int UNSPECIFIED = 0;

  /// Measure mode where the size is exactly the given size (Android's
  /// `MeasureSpec.EXACTLY`).
  static const int EXACTLY = 1 << MODE_SHIFT;

  /// Measure mode where the size is at most the given size (Android's
  /// `MeasureSpec.AT_MOST`).
  static const int AT_MOST = 2 << MODE_SHIFT;

  /// Android's `LayoutParams.MATCH_PARENT` size. Kept from upstream; the
  /// engine itself does not read it.
  static const int MATCH_PARENT = -1;

  /// Android's `LayoutParams.WRAP_CONTENT` size. Kept from upstream; the
  /// engine itself does not read it.
  static const int WRAP_CONTENT = -2;

  /// The size value upstream uses for a fixed size. Kept from upstream; the
  /// engine itself does not read it.
  static const int FIXED = -3;

  final List<ConstraintWidget> _variableDimensionsWidgets = [];

  /// The one [Measure] that [measure] fills for every request of
  /// [measureChildren] and of the re-measure passes of [solverMeasure]
  /// (upstream's BasicMeasure.mMeasure). Each request writes only the
  /// request fields and [Measure.measuredNeedsSolverPass], so the other
  /// outputs of the previous measure stay visible to the measurer, as in
  /// upstream.
  final Measure mMeasure = Measure();

  final ConstraintWidgetContainer _constraintWidgetContainer;

  /// Creates the measure passes of [constraintWidgetContainer], which
  /// creates its own ([ConstraintWidgetContainer.mBasicMeasureSolver]).
  BasicMeasure(ConstraintWidgetContainer constraintWidgetContainer)
    : _constraintWidgetContainer = constraintWidgetContainer;

  /// Record which children of [layout] have a match-constraint axis (they
  /// are measured again after solving), and invalidate the layout's
  /// dependency graph.
  void updateHierarchy(ConstraintWidgetContainer layout) {
    _variableDimensionsWidgets.clear();
    final childCount = layout.mChildren.length;
    for (var i = 0; i < childCount; i++) {
      final widget = layout.mChildren[i];
      if (widget.getHorizontalDimensionBehaviour() ==
              DimensionBehaviour.matchConstraint ||
          widget.getVerticalDimensionBehaviour() ==
              DimensionBehaviour.matchConstraint) {
        _variableDimensionsWidgets.add(widget);
      }
    }
    layout.invalidateGraph();
  }

  /// The measurer of [layout], which the measure passes require: upstream
  /// dereferences it without a check and throws a NullPointerException.
  static Measurer _measurerOf(ConstraintWidgetContainer layout) {
    final measurer = layout.getMeasurer();
    if (measurer == null) {
      throw StateError(
        'ConstraintWidgetContainer.measure needs a Measurer to measure the '
        'children: call setMeasurer first.',
      );
    }
    return measurer;
  }

  /// Measure the children of [layout] before its first solve, as
  /// [solverMeasure] does (upstream's BasicMeasure.measureChildren), with
  /// [Measure.SELF_DIMENSIONS], then call [Measurer.didMeasures].
  ///
  /// Guidelines, barriers and the widgets of a [VirtualLayout] are not
  /// measured, nor are children the solver sizes on its own: match
  /// constraint on both axes (unless in the
  /// [ConstraintWidget.MATCH_CONSTRAINT_WRAP] style). At
  /// [Optimizer.OPTIMIZATION_DIRECT], children other than virtual layouts
  /// that upstream's Direct pass may size are left for it too: a spread
  /// match-constraint axis against a non-match-constraint one (outside a
  /// horizontal chain, as upstream checks both axes), and any
  /// match-constraint axis with a ratio. At
  /// [Optimizer.OPTIMIZATION_GRAPH], a child whose size the dependency graph
  /// resolved is not measured either. Throws a [StateError] when [layout]
  /// has no [Measurer].
  void measureChildren(ConstraintWidgetContainer layout) {
    final childCount = layout.mChildren.length;
    final optimize = layout.optimizeFor(Optimizer.OPTIMIZATION_GRAPH);
    final measurer = _measurerOf(layout);
    for (var i = 0; i < childCount; i++) {
      final child = layout.mChildren[i];
      if (child is Guideline) {
        continue;
      }
      if (child is Barrier) {
        continue;
      }
      if (child.isInVirtualLayout()) {
        continue;
      }

      if (optimize &&
          child.mHorizontalRun != null &&
          child.mVerticalRun != null &&
          child.mHorizontalRun!.mDimension.resolved &&
          child.mVerticalRun!.mDimension.resolved) {
        continue;
      }

      final widthBehavior = child.getDimensionBehaviour(
        ConstraintWidget.HORIZONTAL,
      );
      final heightBehavior = child.getDimensionBehaviour(
        ConstraintWidget.VERTICAL,
      );

      var skip =
          widthBehavior == DimensionBehaviour.matchConstraint &&
          child.mMatchConstraintDefaultWidth !=
              ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
          heightBehavior == DimensionBehaviour.matchConstraint &&
          child.mMatchConstraintDefaultHeight !=
              ConstraintWidget.MATCH_CONSTRAINT_WRAP;

      if (!skip &&
          layout.optimizeFor(Optimizer.OPTIMIZATION_DIRECT) &&
          child is! VirtualLayout) {
        if (widthBehavior == DimensionBehaviour.matchConstraint &&
            child.mMatchConstraintDefaultWidth ==
                ConstraintWidget.MATCH_CONSTRAINT_SPREAD &&
            heightBehavior != DimensionBehaviour.matchConstraint &&
            !child.isInHorizontalChain()) {
          skip = true;
        }

        if (heightBehavior == DimensionBehaviour.matchConstraint &&
            child.mMatchConstraintDefaultHeight ==
                ConstraintWidget.MATCH_CONSTRAINT_SPREAD &&
            widthBehavior != DimensionBehaviour.matchConstraint &&
            !child.isInHorizontalChain()) {
          skip = true;
        }

        // Don't measure yet: let the direct solver have a shot at it.
        if ((widthBehavior == DimensionBehaviour.matchConstraint ||
                heightBehavior == DimensionBehaviour.matchConstraint) &&
            child.mDimensionRatio > 0) {
          skip = true;
        }
      }

      if (skip) {
        // we don't need to measure here as the dimension of the widget
        // will be completely computed by the solver.
        continue;
      }

      measure(measurer, child, Measure.SELF_DIMENSIONS);
    }
    measurer.didMeasures();
  }

  void _solveLinearSystem(
    ConstraintWidgetContainer layout,
    String reason,
    int pass,
    int w,
    int h,
  ) {
    final minWidth = layout.getMinWidth();
    final minHeight = layout.getMinHeight();
    layout.setMinWidth(0);
    layout.setMinHeight(0);
    layout.setWidth(w);
    layout.setHeight(h);
    layout.setMinWidth(minWidth);
    layout.setMinHeight(minHeight);
    _constraintWidgetContainer.setPass(pass);
    _constraintWidgetContainer.layout();
  }

  /// Measure and lay out [layout] (upstream's BasicMeasure.solverMeasure,
  /// BM 181-453), called through [ConstraintWidgetContainer.measure].
  ///
  /// At the [Optimizer.OPTIMIZATION_GRAPH] levels, the dependency graph runs
  /// first when no child is in a chain or is a [VirtualLayout], and both
  /// [widthMode] and [heightMode] are [EXACTLY] (or the level has
  /// [Optimizer.OPTIMIZATION_GRAPH_WRAP]); when it resolves both axes,
  /// nothing else runs. Otherwise the children are measured
  /// ([measureChildren]) and the layout solved ([ConstraintWidgetContainer.layout],
  /// pass 0). The virtual layouts with a match-constraint axis are then
  /// measured again with [Measure.TRY_GIVEN_DIMENSIONS], and the other
  /// match-constraint children twice, with [Measure.TRY_GIVEN_DIMENSIONS]
  /// then [Measure.USE_GIVEN_DIMENSIONS], each round followed by another
  /// solve (passes 1 and 2) when a size, a baseline or the measurer's
  /// [Measure.measuredNeedsSolverPass] changed. Every solve starts from the
  /// size [layout] had on entry.
  void solverMeasure(
    ConstraintWidgetContainer layout,
    int optimizationLevel,
    int paddingX,
    int paddingY,
    int widthMode,
    int widthSize,
    int heightMode,
    int heightSize,
    int lastMeasureWidth,
    int lastMeasureHeight,
  ) {
    final measurer = layout.getMeasurer();

    final childCount = layout.mChildren.length;
    final startingWidth = layout.getWidth();
    final startingHeight = layout.getHeight();

    final optimizeWrap = Optimizer.enabled(
      optimizationLevel,
      Optimizer.OPTIMIZATION_GRAPH_WRAP,
    );
    var optimize =
        optimizeWrap ||
        Optimizer.enabled(optimizationLevel, Optimizer.OPTIMIZATION_GRAPH);

    if (optimize) {
      for (var i = 0; i < childCount; i++) {
        final child = layout.mChildren[i];
        final matchWidth =
            child.getHorizontalDimensionBehaviour() ==
            DimensionBehaviour.matchConstraint;
        final matchHeight =
            child.getVerticalDimensionBehaviour() ==
            DimensionBehaviour.matchConstraint;
        final ratio =
            matchWidth && matchHeight && child.getDimensionRatio() > 0;
        if (child.isInHorizontalChain() && ratio) {
          optimize = false;
          break;
        }
        if (child.isInVerticalChain() && ratio) {
          optimize = false;
          break;
        }
        if (child is VirtualLayout) {
          optimize = false;
          break;
        }
        if (child.isInHorizontalChain() || child.isInVerticalChain()) {
          optimize = false;
          break;
        }
      }
    }

    var allSolved = false;

    optimize =
        optimize &&
        ((widthMode == EXACTLY && heightMode == EXACTLY) || optimizeWrap);

    var computations = 0;

    if (optimize) {
      // For non-optimizer this doesn't seem to be a problem; for both cases,
      // having the width address max size early seems to work.
      widthSize = math.min(layout.getMaxWidth(), widthSize);
      heightSize = math.min(layout.getMaxHeight(), heightSize);

      if (widthMode == EXACTLY && layout.getWidth() != widthSize) {
        layout.setWidth(widthSize);
        layout.invalidateGraph();
      }
      if (heightMode == EXACTLY && layout.getHeight() != heightSize) {
        layout.setHeight(heightSize);
        layout.invalidateGraph();
      }
      if (widthMode == EXACTLY && heightMode == EXACTLY) {
        allSolved = layout.directMeasure(optimizeWrap);
        computations = 2;
      } else {
        allSolved = layout.directMeasureSetup(optimizeWrap);
        // Java's `allSolved &= x` evaluates x whatever allSolved is.
        if (widthMode == EXACTLY) {
          final resolved = layout.directMeasureWithOrientation(
            optimizeWrap,
            ConstraintWidget.HORIZONTAL,
          );
          allSolved = allSolved && resolved;
          computations++;
        }
        if (heightMode == EXACTLY) {
          final resolved = layout.directMeasureWithOrientation(
            optimizeWrap,
            ConstraintWidget.VERTICAL,
          );
          allSolved = allSolved && resolved;
          computations++;
        }
      }
      if (allSolved) {
        layout.updateFromRuns(widthMode == EXACTLY, heightMode == EXACTLY);
      }
    }

    if (!allSolved || computations != 2) {
      final optimizations = layout.getOptimizationLevel();
      if (childCount > 0) {
        measureChildren(layout);
      }

      updateHierarchy(layout);

      // let's update the size dependent widgets if any...
      final sizeDependentWidgetsCount = _variableDimensionsWidgets.length;

      // let's solve the linear system.
      if (childCount > 0) {
        _solveLinearSystem(
          layout,
          'First pass',
          0,
          startingWidth,
          startingHeight,
        );
      }

      if (sizeDependentWidgetsCount > 0) {
        // measureChildren ran (there are children) and threw when the
        // measurer is missing, so it is set here.
        final sizeMeasurer = measurer ?? _measurerOf(layout);
        var needSolverPass = false;
        final containerWrapWidth =
            layout.getHorizontalDimensionBehaviour() ==
            DimensionBehaviour.wrapContent;
        final containerWrapHeight =
            layout.getVerticalDimensionBehaviour() ==
            DimensionBehaviour.wrapContent;
        var minWidth = math.max(
          layout.getWidth(),
          _constraintWidgetContainer.getMinWidth(),
        );
        var minHeight = math.max(
          layout.getHeight(),
          _constraintWidgetContainer.getMinHeight(),
        );

        // Let's first apply sizes for VirtualLayouts if any
        for (var i = 0; i < sizeDependentWidgetsCount; i++) {
          final widget = _variableDimensionsWidgets[i];
          if (widget is! VirtualLayout) {
            continue;
          }
          final preWidth = widget.getWidth();
          final preHeight = widget.getHeight();
          final hasMeasure = measure(
            sizeMeasurer,
            widget,
            Measure.TRY_GIVEN_DIMENSIONS,
          );
          needSolverPass = needSolverPass || hasMeasure;
          final measuredWidth = widget.getWidth();
          final measuredHeight = widget.getHeight();
          if (measuredWidth != preWidth) {
            widget.setWidth(measuredWidth);
            if (containerWrapWidth && widget.getRight() > minWidth) {
              final w = widget.getRight() + widget.mRight.getMargin();
              minWidth = math.max(minWidth, w);
            }
            needSolverPass = true;
          }
          if (measuredHeight != preHeight) {
            widget.setHeight(measuredHeight);
            if (containerWrapHeight && widget.getBottom() > minHeight) {
              final h = widget.getBottom() + widget.mBottom.getMargin();
              minHeight = math.max(minHeight, h);
            }
            needSolverPass = true;
          }
          final needsPass = widget.needSolverPass();
          needSolverPass = needSolverPass || needsPass;
        }

        const maxIterations = 2;
        for (var j = 0; j < maxIterations; j++) {
          for (var i = 0; i < sizeDependentWidgetsCount; i++) {
            final widget = _variableDimensionsWidgets[i];
            if ((widget is Helper && widget is! VirtualLayout) ||
                widget is Guideline) {
              continue;
            }
            if (widget.getVisibility() == ConstraintWidget.GONE) {
              continue;
            }
            if (optimize &&
                widget.mHorizontalRun != null &&
                widget.mVerticalRun != null &&
                widget.mHorizontalRun!.mDimension.resolved &&
                widget.mVerticalRun!.mDimension.resolved) {
              continue;
            }
            if (widget is VirtualLayout) {
              continue;
            }

            final preWidth = widget.getWidth();
            final preHeight = widget.getHeight();
            final preBaselineDistance = widget.getBaselineDistance();

            var measureStrategy = Measure.TRY_GIVEN_DIMENSIONS;
            if (j == maxIterations - 1) {
              measureStrategy = Measure.USE_GIVEN_DIMENSIONS;
            }
            final hasMeasure = measure(sizeMeasurer, widget, measureStrategy);
            needSolverPass = needSolverPass || hasMeasure;

            final measuredWidth = widget.getWidth();
            final measuredHeight = widget.getHeight();

            if (measuredWidth != preWidth) {
              widget.setWidth(measuredWidth);
              if (containerWrapWidth && widget.getRight() > minWidth) {
                final w = widget.getRight() + widget.mRight.getMargin();
                minWidth = math.max(minWidth, w);
              }
              needSolverPass = true;
            }
            if (measuredHeight != preHeight) {
              widget.setHeight(measuredHeight);
              if (containerWrapHeight && widget.getBottom() > minHeight) {
                final h = widget.getBottom() + widget.mBottom.getMargin();
                minHeight = math.max(minHeight, h);
              }
              needSolverPass = true;
            }
            if (widget.hasBaseline() &&
                preBaselineDistance != widget.getBaselineDistance()) {
              needSolverPass = true;
            }
          }
          if (needSolverPass) {
            _solveLinearSystem(
              layout,
              'intermediate pass',
              1 + j,
              startingWidth,
              startingHeight,
            );
            needSolverPass = false;
          } else {
            break;
          }
        }
      }
      layout.setOptimizationLevel(optimizations);
    }
  }

  /// Measure [widget] through [measurer] with [measureStrategy] into
  /// [mMeasure], and copy the result onto [widget] (upstream's
  /// BasicMeasure.measure, BM 463-498). A match-constraint ratio axis that
  /// the solver already resolved from the ratio is measured fixed. Returns
  /// [Measure.measuredNeedsSolverPass].
  bool measure(
    Measurer measurer,
    ConstraintWidget widget,
    int measureStrategy,
  ) {
    mMeasure.horizontalBehavior = widget.getHorizontalDimensionBehaviour();
    mMeasure.verticalBehavior = widget.getVerticalDimensionBehaviour();
    mMeasure.horizontalDimension = widget.getWidth();
    mMeasure.verticalDimension = widget.getHeight();
    mMeasure.measuredNeedsSolverPass = false;
    mMeasure.measureStrategy = measureStrategy;

    final horizontalMatchConstraints =
        mMeasure.horizontalBehavior == DimensionBehaviour.matchConstraint;
    final verticalMatchConstraints =
        mMeasure.verticalBehavior == DimensionBehaviour.matchConstraint;
    final horizontalUseRatio =
        horizontalMatchConstraints && widget.mDimensionRatio > 0;
    final verticalUseRatio =
        verticalMatchConstraints && widget.mDimensionRatio > 0;

    if (horizontalUseRatio) {
      if (widget.mResolvedMatchConstraintDefault[ConstraintWidget.HORIZONTAL] ==
          ConstraintWidget.MATCH_CONSTRAINT_RATIO_RESOLVED) {
        mMeasure.horizontalBehavior = DimensionBehaviour.fixed;
      }
    }
    if (verticalUseRatio) {
      if (widget.mResolvedMatchConstraintDefault[ConstraintWidget.VERTICAL] ==
          ConstraintWidget.MATCH_CONSTRAINT_RATIO_RESOLVED) {
        mMeasure.verticalBehavior = DimensionBehaviour.fixed;
      }
    }

    measurer.measure(widget, mMeasure);
    widget.setWidth(mMeasure.measuredWidth);
    widget.setHeight(mMeasure.measuredHeight);
    widget.setHasBaseline(mMeasure.measuredHasBaseline);
    widget.setBaselineDistance(mMeasure.measuredBaseline);
    mMeasure.measureStrategy = Measure.SELF_DIMENSIONS;
    return mMeasure.measuredNeedsSolverPass;
  }
}
