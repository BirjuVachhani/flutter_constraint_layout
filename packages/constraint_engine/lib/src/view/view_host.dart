// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.widget.ConstraintLayout
// (ConstraintLayout.java, "CL" below; upstream pinned in UPSTREAM.md): what
// the layout view's onMeasure does around the core engine, on the dirty path
// (CL 1768-1879, taken when a child requested layout), with resolveSystem
// (1681-1721), getPaddingWidth (1894-1905), setSelfDimensionBehaviour
// (1907-1981) and resolveMeasuredDimension (1733-1763). The widgets stand for
// the result of setChildrenConstraints; this file brings their measure state
// to what that rebuild leaves (CL 1249-1351) before every measure.

import 'dart:math' as math;

import '../barrier.dart';
import '../constraint_anchor.dart';
import '../constraint_widget.dart';
import '../constraint_widget_container.dart';
import '../guideline.dart';
import '../optimizer.dart';
import '../virtual_layout.dart';
import 'measure_spec.dart';
import 'view_dependents.dart';
import 'view_measurer.dart';

/// The ConstraintLayout view's `onMeasure`: Android's entry to the engine.
///
/// A host owns a [container] whose children are its child views' widgets, in
/// child order, configured as the views' layout params configure them, and a
/// [measurer] that measures those views. [measure] then measures the layout
/// under the specs its parent gives it, exactly as Android does at
/// [optimizationLevel]: it takes Android's dirty path, which rebuilds the
/// hierarchy on every measure in which a child requested layout (every
/// child's measure state reset as `ConstraintWidget.reset()` resets it, see
/// [ConstraintWidget.resetMeasureState]), measures the container through
/// [ConstraintWidgetContainer.measure], and resolves the layout's own
/// measured size ([measuredWidthAndState], [measuredHeightAndState]).
///
/// What `reset()` keeps, the widgets keep from one measure to the next, as
/// Android's do: the resolved flags, a guideline's and a barrier's own
/// resolved flag, and the dependency graph's runs and nodes. At
/// [Optimizer.OPTIMIZATION_STANDARD] the Direct pass clears the flags before
/// anything reads them and the graph does not run, so neither changes a
/// layout there. At the levels without `OPTIMIZATION_DIRECT`, and at the
/// GRAPH levels, a layout measured again can differ from a fresh build of
/// the same configuration, as Android's live views do.
///
/// The children's frames are then read from the widgets, as `onLayout` does
/// (CL 2001-2070): [ConstraintWidget.getX] and [ConstraintWidget.getY]
/// include the padding, with [ConstraintWidget.getWidth] and
/// [ConstraintWidget.getHeight]. A GONE child is not placed.
///
/// Guideline and Barrier widgets are made GONE at every measure, as Android's
/// view Guideline and Barrier always are: they report 0 x 0, their own
/// anchors' margins are 0, and a link with a gone margin into one uses that
/// gone margin.
class ViewHost {
  /// Creates the host of [container], measuring its children with
  /// [measurer], which it installs as the container's measurer.
  ViewHost(this.container, this.measurer) {
    container.setMeasurer(measurer);
  }

  /// The layout widget (CL `mLayoutWidget`).
  final ConstraintWidgetContainer container;

  /// The children's measurer (CL `mMeasurer`).
  final ViewMeasurer measurer;

  /// The layout view's optimization level (CL `mOptimizationLevel`):
  /// [Optimizer.OPTIMIZATION_STANDARD] by default, as on Android.
  int optimizationLevel = Optimizer.OPTIMIZATION_STANDARD;

  /// The layout view's left padding (`android:paddingLeft`, physical and
  /// resolved; a negative value counts as 0).
  int paddingLeft = 0;

  /// The layout view's top padding (a negative value counts as 0).
  int paddingTop = 0;

  /// The layout view's right padding (a negative value counts as 0).
  int paddingRight = 0;

  /// The layout view's bottom padding (a negative value counts as 0).
  int paddingBottom = 0;

  /// `android:minWidth` (CL `mMinWidth`), 0 by default.
  int minWidth = 0;

  /// `android:minHeight` (CL `mMinHeight`), 0 by default.
  int minHeight = 0;

  /// `android:maxWidth` (CL `mMaxWidth`), Java's `Integer.MAX_VALUE` by
  /// default.
  int maxWidth = ConstraintWidget.intMaxValue;

  /// `android:maxHeight` (CL `mMaxHeight`), Java's `Integer.MAX_VALUE` by
  /// default.
  int maxHeight = ConstraintWidget.intMaxValue;

  /// Whether the layout is right-to-left. It lives on the container
  /// (CL 1852 copies the view's direction there), and the caller sets it.
  bool isRtl() => container.isRtl();

  /// Set whether the layout is right-to-left, on the container.
  void setRtl(bool rtl) => container.setRtl(rtl);

  int _measuredWidthAndState = 0;
  int _measuredHeightAndState = 0;
  int _lastMeasureWidth = -1;
  int _lastMeasureHeight = -1;

  /// The width [measure] passed to `setMeasuredDimension`: the measured
  /// width with [MeasureSpec.MEASURED_STATE_TOO_SMALL] when the layout was
  /// measured too small (CL 1733-1763).
  int get measuredWidthAndState => _measuredWidthAndState;

  /// The height [measure] passed to `setMeasuredDimension`, with its
  /// measured-state bit, as [measuredWidthAndState].
  int get measuredHeightAndState => _measuredHeightAndState;

  /// The layout's measured width (`View.getMeasuredWidth`):
  /// [measuredWidthAndState] `& MEASURED_SIZE_MASK`.
  int getMeasuredWidth() =>
      _measuredWidthAndState & MeasureSpec.MEASURED_SIZE_MASK;

  /// The layout's measured height (`View.getMeasuredHeight`).
  int getMeasuredHeight() =>
      _measuredHeightAndState & MeasureSpec.MEASURED_SIZE_MASK;

  /// The last measured width with its state bit (CL `mLastMeasureWidth`, -1
  /// before the first [measure]), which [measure] passes to
  /// [ConstraintWidgetContainer.measure].
  int get lastMeasureWidth => _lastMeasureWidth;

  /// The last measured height with its state bit (CL `mLastMeasureHeight`).
  int get lastMeasureHeight => _lastMeasureHeight;

  /// Measure the layout under [widthMeasureSpec] and [heightMeasureSpec]
  /// ([MeasureSpec] values): `onMeasure` on its dirty path (CL 1768-1879).
  void measure(int widthMeasureSpec, int heightMeasureSpec) {
    assert(
      identical(container.getMeasurer(), measurer),
      'ViewHost measures every child through its own ViewMeasurer, which '
      'keeps the child views\' state; the container now has another '
      'measurer, so that state and the request transcript would be wrong',
    );
    measurer.beginMeasure();
    container.setOptimizationLevel(optimizationLevel);
    measurer.optimizationLevel = optimizationLevel;
    _setChildrenConstraints();
    // Android's onMeasure updates the layout widget's hierarchy here, and
    // solverMeasure updates it again before it reads it. Port only (Phase
    // 6): without a graph level the first update is skipped, as it is dead
    // there. Its two effects are the list of match-constraint children,
    // which solverMeasure rebuilds (BM 438) before its only read and does
    // not read at all when it returns earlier, and the graph's rebuild flag,
    // which only the dependency graph's measures read (BasicMeasure runs
    // them at the GRAPH and GRAPH_WRAP levels only) and solverMeasure sets
    // again in the same update. Nothing between the two reads either.
    if (Optimizer.enabled(optimizationLevel, Optimizer.OPTIMIZATION_GRAPH) ||
        Optimizer.enabled(
          optimizationLevel,
          Optimizer.OPTIMIZATION_GRAPH_WRAP,
        )) {
      container.updateHierarchy();
    }
    _resolveSystem(widthMeasureSpec, heightMeasureSpec);
    _resolveMeasuredDimension(
      widthMeasureSpec,
      heightMeasureSpec,
      container.getWidth(),
      container.getHeight(),
      container.isWidthMeasuredTooSmall(),
      container.isHeightMeasuredTooSmall(),
    );
  }

  /// The measure state Android's `setChildrenConstraints` leaves
  /// (CL 1249-1351): every child's measure state reset as `reset()` resets
  /// it, the helpers GONE, the virtual layouts' members marked, the
  /// dependents rebuilt from the links, and the layout params'
  /// needs-baseline flags.
  void _setChildrenConstraints() {
    final children = container.mChildren;
    final count = children.length;
    // Android does not reset the layout widget itself, only its children.
    for (var i = 0; i < count; i++) {
      children[i].resetMeasureState();
    }
    // The view Guideline and Barrier constructors call
    // super.setVisibility(GONE), and CL 1363 copies the view's visibility to
    // the widget.
    for (var i = 0; i < count; i++) {
      final child = children[i];
      if (child is Guideline || child is Barrier) {
        child.setVisibility(ConstraintWidget.GONE);
      }
    }
    // ConstraintHelper.updatePreLayout (CH 508-541) marks the members.
    for (var i = 0; i < count; i++) {
      final child = children[i];
      if (child is VirtualLayout) {
        child.updateConstraints(container);
      }
    }
    rebuildViewDependents(container);
    // setWidgetBaseline (CL 1598-1620): a baseline link makes the layout
    // params of its widget, and of the target's widget for a baseline to
    // baseline link, ask for the baseline. The flags are sticky.
    for (var i = 0; i < count; i++) {
      final child = children[i];
      final target = child.mBaseline.mTarget;
      if (target == null) {
        continue;
      }
      measurer.setNeedsBaseline(child);
      if (target.mType == ConstraintAnchorType.baseline &&
          !identical(target.mOwner, container)) {
        measurer.setNeedsBaseline(target.mOwner);
      }
    }
  }

  /// `getPaddingWidth` (CL 1894-1905), with start and end resolved to left
  /// and right.
  int _getPaddingWidth() =>
      math.max(0, paddingLeft) + math.max(0, paddingRight);

  /// `resolveSystem` (CL 1681-1721).
  void _resolveSystem(int widthMeasureSpec, int heightMeasureSpec) {
    final widthMode = MeasureSpec.getMode(widthMeasureSpec);
    var widthSize = MeasureSpec.getSize(widthMeasureSpec);
    final heightMode = MeasureSpec.getMode(heightMeasureSpec);
    var heightSize = MeasureSpec.getSize(heightMeasureSpec);

    final paddingY = math.max(0, paddingTop);
    final paddingBottom = math.max(0, this.paddingBottom);
    final paddingHeight = paddingY + paddingBottom;
    final paddingWidth = _getPaddingWidth();
    measurer.captureLayoutInfo(
      widthMeasureSpec,
      heightMeasureSpec,
      paddingY,
      paddingBottom,
      paddingWidth,
      paddingHeight,
    );

    // With start and end resolved to left and right, the start padding is
    // the left padding in LTR and the end padding is the left padding in
    // RTL, so paddingX is the left padding either way.
    final paddingX = math.max(0, paddingLeft);

    widthSize -= paddingWidth;
    heightSize -= paddingHeight;

    _setSelfDimensionBehaviour(widthMode, widthSize, heightMode, heightSize);

    container.measure(
      optimizationLevel,
      widthMode,
      widthSize,
      heightMode,
      heightSize,
      _lastMeasureWidth,
      _lastMeasureHeight,
      paddingX,
      paddingY,
    );
  }

  /// `resolveMeasuredDimension` (CL 1733-1763).
  void _resolveMeasuredDimension(
    int widthMeasureSpec,
    int heightMeasureSpec,
    int measuredWidth,
    int measuredHeight,
    bool isWidthMeasuredTooSmall,
    bool isHeightMeasuredTooSmall,
  ) {
    const childState = 0;
    final heightPadding = measurer.paddingHeight;
    final widthPadding = measurer.paddingWidth;

    final androidLayoutWidth = measuredWidth + widthPadding;
    final androidLayoutHeight = measuredHeight + heightPadding;

    var resolvedWidthSize = MeasureSpec.resolveSizeAndState(
      androidLayoutWidth,
      widthMeasureSpec,
      childState,
    );
    var resolvedHeightSize = MeasureSpec.resolveSizeAndState(
      androidLayoutHeight,
      heightMeasureSpec,
      childState << MeasureSpec.MEASURED_HEIGHT_STATE_SHIFT,
    );
    resolvedWidthSize &= MeasureSpec.MEASURED_SIZE_MASK;
    resolvedHeightSize &= MeasureSpec.MEASURED_SIZE_MASK;
    resolvedWidthSize = math.min(maxWidth, resolvedWidthSize);
    resolvedHeightSize = math.min(maxHeight, resolvedHeightSize);
    if (isWidthMeasuredTooSmall) {
      resolvedWidthSize |= MeasureSpec.MEASURED_STATE_TOO_SMALL;
    }
    if (isHeightMeasuredTooSmall) {
      resolvedHeightSize |= MeasureSpec.MEASURED_STATE_TOO_SMALL;
    }
    _measuredWidthAndState = resolvedWidthSize;
    _measuredHeightAndState = resolvedHeightSize;
    _lastMeasureWidth = resolvedWidthSize;
    _lastMeasureHeight = resolvedHeightSize;
  }

  /// `setSelfDimensionBehaviour` (CL 1907-1981): the container's behaviours,
  /// size, min and max from the layout's own specs, padding, min and max.
  void _setSelfDimensionBehaviour(
    int widthMode,
    int widthSize,
    int heightMode,
    int heightSize,
  ) {
    final heightPadding = measurer.paddingHeight;
    final widthPadding = measurer.paddingWidth;

    var widthBehaviour = DimensionBehaviour.fixed;
    var heightBehaviour = DimensionBehaviour.fixed;

    var desiredWidth = 0;
    var desiredHeight = 0;
    final childCount = container.mChildren.length;

    switch (widthMode) {
      case MeasureSpec.AT_MOST:
        widthBehaviour = DimensionBehaviour.wrapContent;
        desiredWidth = widthSize;
        if (childCount == 0) {
          desiredWidth = math.max(0, minWidth);
        }
      case MeasureSpec.UNSPECIFIED:
        widthBehaviour = DimensionBehaviour.wrapContent;
        if (childCount == 0) {
          desiredWidth = math.max(0, minWidth);
        }
      case MeasureSpec.EXACTLY:
        desiredWidth = math.min(maxWidth - widthPadding, widthSize);
    }
    switch (heightMode) {
      case MeasureSpec.AT_MOST:
        heightBehaviour = DimensionBehaviour.wrapContent;
        desiredHeight = heightSize;
        if (childCount == 0) {
          desiredHeight = math.max(0, minHeight);
        }
      case MeasureSpec.UNSPECIFIED:
        heightBehaviour = DimensionBehaviour.wrapContent;
        if (childCount == 0) {
          desiredHeight = math.max(0, minHeight);
        }
      case MeasureSpec.EXACTLY:
        desiredHeight = math.min(maxHeight - heightPadding, heightSize);
    }

    if (desiredWidth != container.getWidth() ||
        desiredHeight != container.getHeight()) {
      container.invalidateMeasures();
    }
    container.setX(0);
    container.setY(0);
    container.setMaxWidth(maxWidth - widthPadding);
    container.setMaxHeight(maxHeight - heightPadding);
    container.setMinWidth(0);
    container.setMinHeight(0);
    container.setHorizontalDimensionBehaviour(widthBehaviour);
    container.setWidth(desiredWidth);
    container.setVerticalDimensionBehaviour(heightBehaviour);
    container.setHeight(desiredHeight);
    container.setMinWidth(minWidth - widthPadding);
    container.setMinHeight(minHeight - heightPadding);
  }
}
