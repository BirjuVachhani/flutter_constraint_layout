// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.VirtualLayout
// (upstream pinned in UPSTREAM.md).

import 'analyzer/basic_measure.dart';
import 'constraint_widget.dart';
import 'constraint_widget_container.dart';
import 'guideline.dart';
import 'helper_widget.dart';

/// Base class for virtual layouts.
class VirtualLayout extends HelperWidget {
  int _paddingTop = 0;
  int _paddingBottom = 0;
  // Kept for upstream parity; only the resolved values are read.
  // ignore: unused_field
  int _paddingLeft = 0;
  // ignore: unused_field
  int _paddingRight = 0;
  int _paddingStart = 0;
  int _paddingEnd = 0;
  int _resolvedPaddingLeft = 0;
  int _resolvedPaddingRight = 0;

  bool _needsCallFromSolver = false;
  int _measuredWidth = 0;
  int _measuredHeight = 0;

  final Measure mMeasure = Measure();
  Measurer? mMeasurer;

  // ---- accessors ----

  void setPadding(int value) {
    _paddingLeft = value;
    _paddingTop = value;
    _paddingRight = value;
    _paddingBottom = value;
    _paddingStart = value;
    _paddingEnd = value;
  }

  void setPaddingStart(int value) {
    _paddingStart = value;
    _resolvedPaddingLeft = value;
    _resolvedPaddingRight = value;
  }

  void setPaddingEnd(int value) => _paddingEnd = value;

  void setPaddingLeft(int value) {
    _paddingLeft = value;
    _resolvedPaddingLeft = value;
  }

  void applyRtl(bool isRtl) {
    if (_paddingStart > 0 || _paddingEnd > 0) {
      if (isRtl) {
        _resolvedPaddingLeft = _paddingEnd;
        _resolvedPaddingRight = _paddingStart;
      } else {
        _resolvedPaddingLeft = _paddingStart;
        _resolvedPaddingRight = _paddingEnd;
      }
    }
  }

  void setPaddingTop(int value) => _paddingTop = value;

  void setPaddingRight(int value) {
    _paddingRight = value;
    _resolvedPaddingRight = value;
  }

  void setPaddingBottom(int value) => _paddingBottom = value;

  int getPaddingTop() => _paddingTop;
  int getPaddingBottom() => _paddingBottom;
  int getPaddingLeft() => _resolvedPaddingLeft;
  int getPaddingRight() => _resolvedPaddingRight;

  // ---- solver callback ----

  void needsCallbackFromSolver(bool value) => _needsCallFromSolver = value;

  bool needSolverPass() => _needsCallFromSolver;

  // ---- measure ----

  void measure(int widthMode, int widthSize, int heightMode, int heightSize) {
    // nothing
  }

  @override
  void updateConstraints(ConstraintWidgetContainer container) {
    captureWidgets();
  }

  void captureWidgets() {
    for (var i = 0; i < mWidgetsCount; i++) {
      final widget = mWidgets[i];
      if (widget != null) {
        widget.setInVirtualLayout(true);
      }
    }
  }

  int getMeasuredWidth() => _measuredWidth;
  int getMeasuredHeight() => _measuredHeight;

  void setMeasure(int width, int height) {
    _measuredWidth = width;
    _measuredHeight = height;
  }

  bool measureChildren() {
    Measurer? measurer;
    final parent = mParent;
    if (parent != null) {
      measurer = (parent as ConstraintWidgetContainer).getMeasurer();
    }
    if (measurer == null) {
      return false;
    }

    for (var i = 0; i < mWidgetsCount; i++) {
      final widget = mWidgets[i];
      if (widget == null) {
        continue;
      }

      if (widget is Guideline) {
        continue;
      }

      var widthBehavior = widget.getDimensionBehaviour(
        ConstraintWidget.HORIZONTAL,
      )!;
      var heightBehavior = widget.getDimensionBehaviour(
        ConstraintWidget.VERTICAL,
      )!;

      final skip =
          widthBehavior == DimensionBehaviour.matchConstraint &&
          widget.mMatchConstraintDefaultWidth !=
              ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
          heightBehavior == DimensionBehaviour.matchConstraint &&
          widget.mMatchConstraintDefaultHeight !=
              ConstraintWidget.MATCH_CONSTRAINT_WRAP;

      if (skip) {
        // we don't need to measure here as the dimension of the widget
        // will be completely computed by the solver.
        continue;
      }

      if (widthBehavior == DimensionBehaviour.matchConstraint) {
        widthBehavior = DimensionBehaviour.wrapContent;
      }
      if (heightBehavior == DimensionBehaviour.matchConstraint) {
        heightBehavior = DimensionBehaviour.wrapContent;
      }
      mMeasure.horizontalBehavior = widthBehavior;
      mMeasure.verticalBehavior = heightBehavior;
      mMeasure.horizontalDimension = widget.getWidth();
      mMeasure.verticalDimension = widget.getHeight();
      measurer.measure(widget, mMeasure);
      widget.setWidth(mMeasure.measuredWidth);
      widget.setHeight(mMeasure.measuredHeight);
      widget.setBaselineDistance(mMeasure.measuredBaseline);
    }
    return true;
  }

  void measureWidget(
    ConstraintWidget widget,
    DimensionBehaviour horizontalBehavior,
    int horizontalDimension,
    DimensionBehaviour verticalBehavior,
    int verticalDimension,
  ) {
    while (mMeasurer == null && getParent() != null) {
      final parent = getParent()! as ConstraintWidgetContainer;
      mMeasurer = parent.getMeasurer();
    }
    mMeasure.horizontalBehavior = horizontalBehavior;
    mMeasure.verticalBehavior = verticalBehavior;
    mMeasure.horizontalDimension = horizontalDimension;
    mMeasure.verticalDimension = verticalDimension;
    mMeasurer!.measure(widget, mMeasure);
    widget.setWidth(mMeasure.measuredWidth);
    widget.setHeight(mMeasure.measuredHeight);
    widget.setHasBaseline(mMeasure.measuredHasBaseline);
    widget.setBaselineDistance(mMeasure.measuredBaseline);
  }

  bool containsAny(Iterable<ConstraintWidget> widgets) {
    final set = widgets is Set<ConstraintWidget> ? widgets : widgets.toSet();
    for (var i = 0; i < mWidgetsCount; i++) {
      final widget = mWidgets[i];
      if (widget != null && set.contains(widget)) {
        return true;
      }
    }
    return false;
  }
}
