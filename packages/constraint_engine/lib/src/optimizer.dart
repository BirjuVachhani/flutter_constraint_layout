// Copyright (C) 2018 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.Optimizer (upstream
// pinned in UPSTREAM.md). The Direct/Grouping optimizer passes are not ported
// (the dependency graph plays that role in this engine); the optimization
// level constants, solver flags, and checkMatchParent are.

import 'constraint_widget.dart';
import 'constraint_widget_container.dart';
import 'linear_system.dart';

/// The optimization levels of [ConstraintWidgetContainer.setOptimizationLevel]
/// and the solver's match-parent shortcut ([checkMatchParent]).
///
/// Upstream's Direct and Grouping resolution passes are not ported (the
/// dependency graph plays their role), so several flags are kept only for
/// parity and not read by the engine.
class Optimizer {
  /// No optimization.
  static const int OPTIMIZATION_NONE = 0;

  /// Direct resolution. Upstream's direct pass is not ported; here the flag
  /// only lets [BasicMeasure] skip measuring the match-constraint children
  /// that the solver sizes.
  static const int OPTIMIZATION_DIRECT = 1;

  /// Barrier optimization. Not read by this port.
  static const int OPTIMIZATION_BARRIER = 1 << 1;

  /// Chain optimization. Not read by this port.
  static const int OPTIMIZATION_CHAIN = 1 << 2;

  /// Dimension optimization. Not read by this port.
  static const int OPTIMIZATION_DIMENSIONS = 1 << 3;

  /// Ratio optimization. Not read by this port.
  static const int OPTIMIZATION_RATIO = 1 << 4;

  /// Group optimization. Not read by this port.
  static const int OPTIMIZATION_GROUPS = 1 << 5;

  /// Dependency-graph resolution on the [ConstraintWidgetContainer.measure]
  /// path; with it, the solver also takes positions the graph resolved as
  /// constants ([ConstraintWidget.addToSolver]).
  static const int OPTIMIZATION_GRAPH = 1 << 6;

  /// Dependency-graph resolution on the [ConstraintWidgetContainer.measure]
  /// path, including wrap-content sizes, which the graph then computes
  /// itself.
  static const int OPTIMIZATION_GRAPH_WRAP = 1 << 7;

  /// Measure caching, read by upstream's Android measurer. Not read by the
  /// engine itself.
  static const int OPTIMIZATION_CACHE_MEASURES = 1 << 8;

  /// Dependency ordering. Not read by this port.
  static const int OPTIMIZATION_DEPENDENCY_ORDERING = 1 << 9;

  /// Grouping. Not read by this port.
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
