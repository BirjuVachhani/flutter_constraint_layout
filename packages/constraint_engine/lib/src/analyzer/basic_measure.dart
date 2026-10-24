// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.BasicMeasure
// (upstream pinned in UPSTREAM.md). VirtualLayout handling and Metrics are
// omitted.

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
  void measure(ConstraintWidget widget, Measure measure);
  void didMeasures();
}

class Measure {
  static const int SELF_DIMENSIONS = 0;
  static const int TRY_GIVEN_DIMENSIONS = 1;
  static const int USE_GIVEN_DIMENSIONS = 2;

  DimensionBehaviour? horizontalBehavior;
  DimensionBehaviour? verticalBehavior;
  int horizontalDimension = 0;
  int verticalDimension = 0;
  int measuredWidth = 0;
  int measuredHeight = 0;
  int measuredBaseline = 0;
  bool measuredHasBaseline = false;
  bool measuredNeedsSolverPass = false;
  int measureStrategy = 0;
}

class BasicMeasure {
  static const int MODE_SHIFT = 30;
  static const int UNSPECIFIED = 0;
  static const int EXACTLY = 1 << MODE_SHIFT;
  static const int AT_MOST = 2 << MODE_SHIFT;

  static const int MATCH_PARENT = -1;
  static const int WRAP_CONTENT = -2;
  static const int FIXED = -3;

  final List<ConstraintWidget> _variableDimensionsWidgets = [];
  final Measure _measure = Measure();

  final ConstraintWidgetContainer _constraintWidgetContainer;

  BasicMeasure(ConstraintWidgetContainer constraintWidgetContainer)
    : _constraintWidgetContainer = constraintWidgetContainer;

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

  /// Public entry for the solver fallback: measure all measurable children
  /// through the host measurer (upstream does this in solverMeasure before
  /// solving).
  void measureChildren(ConstraintWidgetContainer layout) {
    if (layout.getMeasurer() == null) {
      return;
    }
    _measureChildren(layout);
  }

  void _measureChildren(ConstraintWidgetContainer layout) {
    final childCount = layout.mChildren.length;
    final optimize = layout.optimizeFor(Optimizer.OPTIMIZATION_GRAPH);
    final measurer = layout.getMeasurer()!;
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

      if (!skip && layout.optimizeFor(Optimizer.OPTIMIZATION_DIRECT)) {
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
    // Children were already measured by solverMeasure; the layout() solver
    // fallback must not measure them again.
    _constraintWidgetContainer.mSkipFallbackRemeasure = true;
    _constraintWidgetContainer.layout();
    _constraintWidgetContainer.mSkipFallbackRemeasure = false;
  }

  /// Called by the host's onMeasure equivalent.
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
      widthSize = widthSize < layout.getMaxWidth()
          ? widthSize
          : layout.getMaxWidth();
      heightSize = heightSize < layout.getMaxHeight()
          ? heightSize
          : layout.getMaxHeight();

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
        if (widthMode == EXACTLY) {
          allSolved =
              allSolved &&
              layout.directMeasureWithOrientation(
                optimizeWrap,
                ConstraintWidget.HORIZONTAL,
              );
          computations++;
        }
        if (heightMode == EXACTLY) {
          allSolved =
              allSolved &&
              layout.directMeasureWithOrientation(
                optimizeWrap,
                ConstraintWidget.VERTICAL,
              );
          computations++;
        }
      }
      if (allSolved) {
        layout.updateFromRuns(widthMode == EXACTLY, heightMode == EXACTLY);
      }
    }

    if (!allSolved || computations != 2) {
      final optimizations = layout.getOptimizationLevel();
      if (childCount > 0 && measurer != null) {
        _measureChildren(layout);
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

      if (sizeDependentWidgetsCount > 0 && measurer != null) {
        var needSolverPass = false;
        final containerWrapWidth =
            layout.getHorizontalDimensionBehaviour() ==
            DimensionBehaviour.wrapContent;
        final containerWrapHeight =
            layout.getVerticalDimensionBehaviour() ==
            DimensionBehaviour.wrapContent;
        var minWidth =
            layout.getWidth() > _constraintWidgetContainer.getMinWidth()
            ? layout.getWidth()
            : _constraintWidgetContainer.getMinWidth();
        var minHeight =
            layout.getHeight() > _constraintWidgetContainer.getMinHeight()
            ? layout.getHeight()
            : _constraintWidgetContainer.getMinHeight();

        // Let's first apply sizes for VirtualLayouts if any
        for (var i = 0; i < sizeDependentWidgetsCount; i++) {
          final widget = _variableDimensionsWidgets[i];
          if (widget is! VirtualLayout) {
            continue;
          }
          final preWidth = widget.getWidth();
          final preHeight = widget.getHeight();
          final hasMeasure = measure(
            measurer,
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
              minWidth = w > minWidth ? w : minWidth;
            }
            needSolverPass = true;
          }
          if (measuredHeight != preHeight) {
            widget.setHeight(measuredHeight);
            if (containerWrapHeight && widget.getBottom() > minHeight) {
              final h = widget.getBottom() + widget.mBottom.getMargin();
              minHeight = h > minHeight ? h : minHeight;
            }
            needSolverPass = true;
          }
          needSolverPass = needSolverPass || widget.needSolverPass();
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
            final hasMeasure = measure(measurer, widget, measureStrategy);
            needSolverPass = needSolverPass || hasMeasure;

            final measuredWidth = widget.getWidth();
            final measuredHeight = widget.getHeight();

            if (measuredWidth != preWidth) {
              widget.setWidth(measuredWidth);
              if (containerWrapWidth && widget.getRight() > minWidth) {
                final w = widget.getRight() + widget.mRight.getMargin();
                minWidth = w > minWidth ? w : minWidth;
              }
              needSolverPass = true;
            }
            if (measuredHeight != preHeight) {
              widget.setHeight(measuredHeight);
              if (containerWrapHeight && widget.getBottom() > minHeight) {
                final h = widget.getBottom() + widget.mBottom.getMargin();
                minHeight = h > minHeight ? h : minHeight;
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

  /// Measure a widget through the host measurer using the given strategy.
  /// Returns true if another solver pass is needed.
  bool measure(
    Measurer measurer,
    ConstraintWidget widget,
    int measureStrategy,
  ) {
    _measure.horizontalBehavior = widget.getHorizontalDimensionBehaviour();
    _measure.verticalBehavior = widget.getVerticalDimensionBehaviour();
    _measure.horizontalDimension = widget.getWidth();
    _measure.verticalDimension = widget.getHeight();
    _measure.measuredNeedsSolverPass = false;
    _measure.measureStrategy = measureStrategy;

    final horizontalMatchConstraints =
        _measure.horizontalBehavior == DimensionBehaviour.matchConstraint;
    final verticalMatchConstraints =
        _measure.verticalBehavior == DimensionBehaviour.matchConstraint;
    final horizontalUseRatio =
        horizontalMatchConstraints && widget.mDimensionRatio > 0;
    final verticalUseRatio =
        verticalMatchConstraints && widget.mDimensionRatio > 0;

    if (horizontalUseRatio) {
      if (widget.mResolvedMatchConstraintDefault[ConstraintWidget.HORIZONTAL] ==
          ConstraintWidget.MATCH_CONSTRAINT_RATIO_RESOLVED) {
        _measure.horizontalBehavior = DimensionBehaviour.fixed;
      }
    }
    if (verticalUseRatio) {
      if (widget.mResolvedMatchConstraintDefault[ConstraintWidget.VERTICAL] ==
          ConstraintWidget.MATCH_CONSTRAINT_RATIO_RESOLVED) {
        _measure.verticalBehavior = DimensionBehaviour.fixed;
      }
    }

    measurer.measure(widget, _measure);
    widget.setWidth(_measure.measuredWidth);
    widget.setHeight(_measure.measuredHeight);
    widget.setHasBaseline(_measure.measuredHasBaseline);
    widget.setBaselineDistance(_measure.measuredBaseline);
    _measure.measureStrategy = Measure.SELF_DIMENSIONS;
    return _measure.measuredNeedsSolverPass;
  }
}
