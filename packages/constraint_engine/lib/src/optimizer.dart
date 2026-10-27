// Copyright (C) 2018 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.Optimizer (upstream
// pinned in UPSTREAM.md): the optimization level constants, the solver flags,
// and checkMatchParent.

import 'constraint_widget.dart';
import 'constraint_widget_container.dart';
import 'linear_system.dart';

/// The optimization levels of [ConstraintWidgetContainer.setOptimizationLevel]
/// and the solver's match-parent shortcut ([checkMatchParent]).
///
/// The flags apply where upstream reads them. Upstream reads several of them
/// nowhere, and its Grouping and dependency-ordering passes are not ported,
/// so those flags are kept only for parity.
class Optimizer {
  /// No optimization.
  static const int OPTIMIZATION_NONE = 0;

  /// Direct resolution. Read by [ConstraintWidgetContainer.layout], which in
  /// the first measure pass runs the Direct pass and then measures every
  /// child Direct left with a measure request, by
  /// [BasicMeasure.measureChildren], which leaves the children Direct may
  /// size unmeasured, and by Android's view measurer, which measures a ratio
  /// itself only without it.
  static const int OPTIMIZATION_DIRECT = 1;

  /// Barrier optimization. Upstream reads it nowhere.
  static const int OPTIMIZATION_BARRIER = 1 << 1;

  /// Chain optimization. Upstream reads it nowhere.
  static const int OPTIMIZATION_CHAIN = 1 << 2;

  /// Dimension optimization. Upstream reads it nowhere.
  static const int OPTIMIZATION_DIMENSIONS = 1 << 3;

  /// Ratio optimization. Upstream reads it nowhere.
  static const int OPTIMIZATION_RATIO = 1 << 4;

  /// Group optimization. Upstream reads it nowhere.
  static const int OPTIMIZATION_GROUPS = 1 << 5;

  /// Dependency-graph resolution, in [BasicMeasure.solverMeasure] only:
  /// the graph runs first when no child is in a chain or is a virtual
  /// layout and both measure modes are [BasicMeasure.EXACTLY], and the
  /// solver then runs only when the graph left an axis unresolved. With it,
  /// [ConstraintWidgetContainer.layout] also passes `optimize` to
  /// [ConstraintWidget.addToSolver] and [ConstraintWidget.updateFromSolver].
  static const int OPTIMIZATION_GRAPH = 1 << 6;

  /// Dependency-graph resolution as [OPTIMIZATION_GRAPH], in
  /// [BasicMeasure.solverMeasure] only, but whatever the measure modes: the
  /// graph resolves the [BasicMeasure.EXACTLY] axes (on one where the
  /// container's own behaviour is wrap content, it computes the container's
  /// size itself when its runs allow it), and the solver runs as well when a
  /// mode is not EXACTLY.
  static const int OPTIMIZATION_GRAPH_WRAP = 1 << 7;

  /// Measure caching, read by Android's view measurer: a child measured
  /// before under similar specs keeps its size without a new measure. The
  /// core passes do not read it.
  static const int OPTIMIZATION_CACHE_MEASURES = 1 << 8;

  /// Dependency ordering: upstream adds the widgets to the solver in
  /// dependency order. Not ported; the engine ignores it.
  static const int OPTIMIZATION_DEPENDENCY_ORDERING = 1 << 9;

  /// Grouping: upstream's Grouping pass for wrap-content containers. Not
  /// ported; the engine ignores it.
  static const int OPTIMIZATION_GROUPING = 1 << 10;

  /// The default level: [OPTIMIZATION_DIRECT] and
  /// [OPTIMIZATION_CACHE_MEASURES].
  static const int OPTIMIZATION_STANDARD =
      OPTIMIZATION_DIRECT | OPTIMIZATION_CACHE_MEASURES;

  // Internal use.
  /// Flags the solver loop shares, indexed by the `FLAG_` constants.
  static final List<bool> sFlags = [false, false, false];

  /// Index in [sFlags] of upstream's "simple enough to use the optimizer"
  /// flag. Not read by this port.
  static const int FLAG_USE_OPTIMIZE = 0; // simple enough to use optimizer

  /// Index in [sFlags] of upstream's dangling-chain flag. Not read by this
  /// port.
  static const int FLAG_CHAIN_DANGLING = 1;

  /// Index in [sFlags] of the flag that asks the solver loop to recompute a
  /// wrap-content container's bounds and solve again.
  static const int FLAG_RECOMPUTE_BOUNDS = 2;

  /// Looks at optimizing match_parent.
  static void checkMatchParent(
    ConstraintWidgetContainer container,
    LinearSystem system,
    ConstraintWidget widget,
  ) {
    widget.mHorizontalResolution = ConstraintWidget.UNKNOWN;
    widget.mVerticalResolution = ConstraintWidget.UNKNOWN;
    if (container.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] !=
            DimensionBehaviour.wrapContent &&
        widget.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] ==
            DimensionBehaviour.matchParent) {
      final left = widget.mLeft.mMargin;
      final right = container.getWidth() - widget.mRight.mMargin;

      widget.mLeft.mSolverVariable = system.createObjectVariable(widget.mLeft);
      widget.mRight.mSolverVariable = system.createObjectVariable(
        widget.mRight,
      );
      system.addEqualityConstant(widget.mLeft.mSolverVariable!, left);
      system.addEqualityConstant(widget.mRight.mSolverVariable!, right);
      widget.mHorizontalResolution = ConstraintWidget.DIRECT;
      widget.setHorizontalDimension(left, right);
    }
    if (container.mListDimensionBehaviors[ConstraintWidget.VERTICAL] !=
            DimensionBehaviour.wrapContent &&
        widget.mListDimensionBehaviors[ConstraintWidget.VERTICAL] ==
            DimensionBehaviour.matchParent) {
      final top = widget.mTop.mMargin;
      final bottom = container.getHeight() - widget.mBottom.mMargin;

      widget.mTop.mSolverVariable = system.createObjectVariable(widget.mTop);
      widget.mBottom.mSolverVariable = system.createObjectVariable(
        widget.mBottom,
      );
      system.addEqualityConstant(widget.mTop.mSolverVariable!, top);
      system.addEqualityConstant(widget.mBottom.mSolverVariable!, bottom);
      if (widget.mBaselineDistance > 0 ||
          widget.getVisibility() == ConstraintWidget.GONE) {
        widget.mBaseline.mSolverVariable = system.createObjectVariable(
          widget.mBaseline,
        );
        system.addEqualityConstant(
          widget.mBaseline.mSolverVariable!,
          top + widget.mBaselineDistance,
        );
      }
      widget.mVerticalResolution = ConstraintWidget.DIRECT;
      widget.setVerticalDimension(top, bottom);
    }
  }

  /// Returns true if every flag of [optimization] is set in
  /// [optimizationLevel].
  static bool enabled(int optimizationLevel, int optimization) =>
      (optimizationLevel & optimization) == optimization;
}
