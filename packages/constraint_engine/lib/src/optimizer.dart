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

class Optimizer {
  static const int OPTIMIZATION_NONE = 0;
  static const int OPTIMIZATION_DIRECT = 1;
  static const int OPTIMIZATION_BARRIER = 1 << 1;
  static const int OPTIMIZATION_CHAIN = 1 << 2;
  static const int OPTIMIZATION_DIMENSIONS = 1 << 3;
  static const int OPTIMIZATION_RATIO = 1 << 4;
  static const int OPTIMIZATION_GROUPS = 1 << 5;
  static const int OPTIMIZATION_GRAPH = 1 << 6;
  static const int OPTIMIZATION_GRAPH_WRAP = 1 << 7;
  static const int OPTIMIZATION_CACHE_MEASURES = 1 << 8;
  static const int OPTIMIZATION_DEPENDENCY_ORDERING = 1 << 9;
  static const int OPTIMIZATION_GROUPING = 1 << 10;

  static const int OPTIMIZATION_STANDARD =
      OPTIMIZATION_DIRECT | OPTIMIZATION_CACHE_MEASURES;

  // Internal use.
  static final List<bool> sFlags = [false, false, false];
  static const int FLAG_USE_OPTIMIZE = 0; // simple enough to use optimizer
  static const int FLAG_CHAIN_DANGLING = 1;
  static const int FLAG_RECOMPUTE_BOUNDS = 2;

  /// Looks at optimizing match_parent.
  static void checkMatchParent(ConstraintWidgetContainer container,
      LinearSystem system, ConstraintWidget widget) {
    widget.mHorizontalResolution = ConstraintWidget.UNKNOWN;
    widget.mVerticalResolution = ConstraintWidget.UNKNOWN;
    if (container.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] !=
            DimensionBehaviour.wrapContent &&
        widget.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] ==
            DimensionBehaviour.matchParent) {
      final left = widget.mLeft.mMargin;
      final right = container.getWidth() - widget.mRight.mMargin;

      widget.mLeft.mSolverVariable = system.createObjectVariable(widget.mLeft);
      widget.mRight.mSolverVariable = system.createObjectVariable(widget.mRight);
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
      widget.mBottom.mSolverVariable = system.createObjectVariable(widget.mBottom);
      system.addEqualityConstant(widget.mTop.mSolverVariable!, top);
      system.addEqualityConstant(widget.mBottom.mSolverVariable!, bottom);
      if (widget.mBaselineDistance > 0 ||
          widget.getVisibility() == ConstraintWidget.GONE) {
        widget.mBaseline.mSolverVariable =
            system.createObjectVariable(widget.mBaseline);
        system.addEqualityConstant(
            widget.mBaseline.mSolverVariable!, top + widget.mBaselineDistance);
      }
      widget.mVerticalResolution = ConstraintWidget.DIRECT;
      widget.setVerticalDimension(top, bottom);
    }
  }

  static bool enabled(int optimizationLevel, int optimization) =>
      (optimizationLevel & optimization) == optimization;
}
