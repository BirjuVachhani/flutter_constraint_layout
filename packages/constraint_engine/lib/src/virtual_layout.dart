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

/// Base class for virtual layouts: helpers, such as [Flow] and [GridCore],
/// that arrange the widgets added to them.
///
/// A virtual layout sizes itself and works out its arrangement in [measure],
/// which the engine does not call itself: a host's [Measurer] calls it when
/// asked to measure the layout. The layout then constrains its widgets when
/// it is added to the solver.
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

  /// The [Measure] reused to measure the referenced widgets.
  final Measure mMeasure = Measure();

  /// The measurer [measureWidget] uses, taken from the parent container when
  /// unset.
  Measurer? mMeasurer;

  // ---- accessors ----

  /// Set the left, top, right, bottom, start, and end paddings to [value].
  ///
  /// The left and right paddings in effect ([getPaddingLeft] and
  /// [getPaddingRight]) only change when [applyRtl] resolves them from start
  /// and end, or through [setPaddingLeft], [setPaddingRight], and
  /// [setPaddingStart].
  void setPadding(int value) {
    _paddingLeft = value;
    _paddingTop = value;
    _paddingRight = value;
    _paddingBottom = value;
    _paddingStart = value;
    _paddingEnd = value;
  }

  /// Set the start padding. Until [applyRtl] resolves start and end, it is
  /// also the left and the right padding in effect.
  void setPaddingStart(int value) {
    _paddingStart = value;
    _resolvedPaddingLeft = value;
    _resolvedPaddingRight = value;
  }

  /// Set the end padding, which takes effect when [applyRtl] resolves it.
  void setPaddingEnd(int value) => _paddingEnd = value;

  /// Set the left padding, in effect immediately.
  void setPaddingLeft(int value) {
    _paddingLeft = value;
    _resolvedPaddingLeft = value;
  }

  /// Resolve the start and end paddings into the left and right paddings in
  /// effect, for a right-to-left layout when [isRtl] is true. Does nothing
  /// when neither the start nor the end padding is positive.
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

  /// Set the top padding.
  void setPaddingTop(int value) => _paddingTop = value;

  /// Set the right padding, in effect immediately.
  void setPaddingRight(int value) {
    _paddingRight = value;
    _resolvedPaddingRight = value;
  }

  /// Set the bottom padding.
  void setPaddingBottom(int value) => _paddingBottom = value;

  /// The top padding.
  int getPaddingTop() => _paddingTop;

  /// The bottom padding.
  int getPaddingBottom() => _paddingBottom;

  /// The left padding in effect; see [setPadding].
  int getPaddingLeft() => _resolvedPaddingLeft;

  /// The right padding in effect; see [setPadding].
  int getPaddingRight() => _resolvedPaddingRight;

  // ---- solver callback ----

  /// Set whether the layout needs another solver pass ([needSolverPass]).
  void needsCallbackFromSolver(bool value) => _needsCallFromSolver = value;

  /// Whether the layout asked for another solver pass, which
  /// [BasicMeasure] then runs. [Flow.measure] asks for one when it has
  /// widgets to place.
  bool needSolverPass() => _needsCallFromSolver;

  // ---- measure ----

  /// Measure the layout and work out the arrangement of its widgets, given
  /// a measure mode ([BasicMeasure.EXACTLY], [BasicMeasure.AT_MOST], or
  /// [BasicMeasure.UNSPECIFIED]) and a size for each axis. Read the result
  /// with [getMeasuredWidth] and [getMeasuredHeight].
  void measure(int widthMode, int widthSize, int heightMode, int heightSize) {
    // nothing
  }

  /// Mark the referenced widgets as in a virtual layout; see
  /// [captureWidgets].
  @override
  void updateConstraints(ConstraintWidgetContainer container) {
    captureWidgets();
  }

  /// Mark every referenced widget as in a virtual layout
  /// ([ConstraintWidget.setInVirtualLayout]), which keeps [BasicMeasure]
  /// from measuring it with the container's other children.
  void captureWidgets() {
    for (var i = 0; i < mWidgetsCount; i++) {
      final widget = mWidgets[i];
      if (widget != null) {
        widget.setInVirtualLayout(true);
      }
    }
  }

  /// The width computed by the last [measure].
  int getMeasuredWidth() => _measuredWidth;

  /// The height computed by the last [measure].
  int getMeasuredHeight() => _measuredHeight;

  /// Record the measured size that [getMeasuredWidth] and
  /// [getMeasuredHeight] return; subclasses call it from [measure].
  void setMeasure(int width, int height) {
    _measuredWidth = width;
    _measuredHeight = height;
  }

  /// Measure every referenced widget through the parent container's
  /// [Measurer], at its own size: a match-constraint axis is measured as
  /// wrap content. Guidelines are skipped, as are widgets that are match
  /// constraint (and not [ConstraintWidget.MATCH_CONSTRAINT_WRAP]) on both
  /// axes, which the solver sizes. Returns false when there is no measurer.
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

  /// Measure [widget] through the measurer with the given behaviours and
  /// proposed sizes, then apply the measured size and baseline to it.
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

  /// Whether this layout references any of [widgets].
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
