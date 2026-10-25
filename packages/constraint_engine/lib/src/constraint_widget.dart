// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.ConstraintWidget
// (upstream pinned in UPSTREAM.md; debug output omitted).

import 'dart:math' as math;

import 'barrier.dart';
import 'cache.dart';
import 'constraint_anchor.dart';
import 'constraint_widget_container.dart';
import 'analyzer/chain_run.dart';
import 'analyzer/horizontal_widget_run.dart';
import 'analyzer/vertical_widget_run.dart';
import 'analyzer/widget_run.dart';
import 'guideline.dart';
import 'linear_system.dart';
import 'solver_variable.dart';
import 'virtual_layout.dart';

/// How a widget resizes along an axis.
enum DimensionBehaviour {
  /// Keep the stored size (see [ConstraintWidget.setWidth] and
  /// [ConstraintWidget.setHeight]). The default.
  fixed,

  /// Size to the content: the size the [Measurer] reports or, for a
  /// container, the size that wraps its children.
  wrapContent,

  /// Size from the constraints, according to the axis's match-constraint mode
  /// (see [ConstraintWidget.setHorizontalMatchStyle]).
  matchConstraint,

  /// Fill the parent, minus this widget's margins on that axis.
  matchParent,
}

/// Implements a constraint widget model supporting constraint relations
/// between other widgets.
///
/// A widget is a rectangle with anchors for its sides ([mLeft], [mTop],
/// [mRight], [mBottom]), its [mBaseline], and its center ([mCenterX],
/// [mCenterY], [mCenter]). Connecting an anchor to an anchor of another
/// widget with [connect] creates a constraint between the two. When both
/// opposite anchors of an axis are connected, the widget is pulled toward
/// both targets: a widget of fixed size is centered between them, or placed
/// by its bias, and a [DimensionBehaviour.matchConstraint] widget stretches
/// to fill the space between them.
///
/// Positions and sizes are integers. After a layout, read the result with
/// [getX], [getY], [getWidth], and [getHeight], or with [getLeft], [getTop],
/// [getRight], and [getBottom].
class ConstraintWidget {
  // ---- match constraint types ----
  /// Match-constraint mode that fills the space between the anchors. The
  /// default.
  static const int MATCH_CONSTRAINT_SPREAD = 0;

  /// Match-constraint mode that uses the content's size, capped at the space
  /// between the anchors.
  static const int MATCH_CONSTRAINT_WRAP = 1;

  /// Match-constraint mode that takes a fraction of the parent's size (see
  /// [setHorizontalMatchStyle]).
  static const int MATCH_CONSTRAINT_PERCENT = 2;

  /// Match-constraint mode the engine uses for an axis derived from the other
  /// one through the dimension ratio: a spread axis switches to it when a
  /// ratio is set.
  static const int MATCH_CONSTRAINT_RATIO = 3;

  /// Match-constraint mode for a ratio-derived axis whose size the engine has
  /// already computed from the other, non-match-constraint axis, so it is
  /// treated as fixed.
  static const int MATCH_CONSTRAINT_RATIO_RESOLVED = 4;

  /// Marker for an unset or unknown value, such as an unset ratio side or
  /// chain weight.
  static const int UNKNOWN = -1;

  /// The horizontal orientation (the x axis), also the index of horizontal
  /// entries in per-axis lists such as [mListDimensionBehaviors].
  static const int HORIZONTAL = 0;

  /// The vertical orientation (the y axis), also the index of vertical
  /// entries in per-axis lists such as [mListDimensionBehaviors].
  static const int VERTICAL = 1;

  /// Both orientations.
  static const int BOTH = 2;

  /// Visibility of a visible widget. The default.
  static const int VISIBLE = 0;

  /// Visibility of a widget that is hidden but keeps its space in the
  /// layout.
  static const int INVISIBLE = 4;

  /// Visibility of a widget that takes no space: it lays out as 0 x 0, its
  /// own margins stop applying, and anchors connected to it use their gone
  /// margin when one is set.
  static const int GONE = 8;

  /// Chain style that spreads the widgets out, with equal gaps at both ends
  /// and between the widgets. The default.
  static const int CHAIN_SPREAD = 0;

  /// Chain style that puts the first and last widgets against the chain's
  /// anchors and spreads the others between them.
  static const int CHAIN_SPREAD_INSIDE = 1;

  /// Chain style that keeps the widgets together, placed by the chain head's
  /// bias.
  static const int CHAIN_PACKED = 2;

  /// Index of the left anchor in [mListAnchors].
  static const int ANCHOR_LEFT = 0;

  /// Index of the right anchor in [mListAnchors].
  static const int ANCHOR_RIGHT = 1;

  /// Index of the top anchor in [mListAnchors].
  static const int ANCHOR_TOP = 2;

  /// Index of the bottom anchor in [mListAnchors].
  static const int ANCHOR_BOTTOM = 3;

  /// Index of the baseline anchor in [mListAnchors].
  static const int ANCHOR_BASELINE = 4;

  /// The default bias, 0.5: centered between two opposite constraints.
  static const double DEFAULT_BIAS = 0.5;

  /// Java's `Integer.MAX_VALUE`, which the engine uses as the "no bound"
  /// value of a maximum size.
  static const int intMaxValue = 0x7fffffff;

  /// Java's `Integer.MIN_VALUE`. [updateFromRuns] and [updateFromSolver]
  /// treat an edge at this value (or at [intMaxValue]) as unresolved.
  static const int intMinValue = -0x80000000;

  // ---- graph measurement fields ----
  bool measured = false;
  ChainRun? horizontalChainRun;
  ChainRun? verticalChainRun;

  /// The dependency-graph run of the horizontal axis, created by
  /// [ensureWidgetRuns].
  HorizontalWidgetRun? mHorizontalRun;

  /// The dependency-graph run of the vertical axis, created by
  /// [ensureWidgetRuns].
  VerticalWidgetRun? mVerticalRun;
  List<bool> isTerminalWidget = [true, true];
  bool mResolvedHasRatio = false;
  bool mMeasureRequested = true;

  // ---- match constraint config ----
  /// The match-constraint mode of the width, one of the `MATCH_CONSTRAINT_`
  /// constants; see [setHorizontalMatchStyle].
  int mMatchConstraintDefaultWidth = MATCH_CONSTRAINT_SPREAD;

  /// The match-constraint mode of the height, one of the `MATCH_CONSTRAINT_`
  /// constants; see [setVerticalMatchStyle].
  int mMatchConstraintDefaultHeight = MATCH_CONSTRAINT_SPREAD;
  List<int> mResolvedMatchConstraintDefault = [0, 0];

  /// The minimum of a match-constraint width, or 0 for none.
  int mMatchConstraintMinWidth = 0;

  /// The maximum of a match-constraint width, or 0 for none.
  int mMatchConstraintMaxWidth = 0;

  /// The fraction of the parent's width that [MATCH_CONSTRAINT_PERCENT]
  /// takes.
  double mMatchConstraintPercentWidth = 1;

  /// The minimum of a match-constraint height, or 0 for none.
  int mMatchConstraintMinHeight = 0;

  /// The maximum of a match-constraint height, or 0 for none.
  int mMatchConstraintMaxHeight = 0;

  /// The fraction of the parent's height that [MATCH_CONSTRAINT_PERCENT]
  /// takes.
  double mMatchConstraintPercentHeight = 1;
  bool mIsWidthWrapContent = false;
  bool mIsHeightWrapContent = false;

  int mResolvedDimensionRatioSide = UNKNOWN;
  double mResolvedDimensionRatio = 1.0;

  /// Whether the widget has a baseline; see [setBaselineDistance].
  bool mHasBaseline = false;
  bool mInVirtualLayout = false;

  // ---- anchors ----
  /// The left edge's anchor.
  late final ConstraintAnchor mLeft = ConstraintAnchor(
    this,
    ConstraintAnchorType.left,
  );

  /// The top edge's anchor.
  late final ConstraintAnchor mTop = ConstraintAnchor(
    this,
    ConstraintAnchorType.top,
  );

  /// The right edge's anchor.
  late final ConstraintAnchor mRight = ConstraintAnchor(
    this,
    ConstraintAnchorType.right,
  );

  /// The bottom edge's anchor.
  late final ConstraintAnchor mBottom = ConstraintAnchor(
    this,
    ConstraintAnchorType.bottom,
  );

  /// The baseline's anchor.
  late final ConstraintAnchor mBaseline = ConstraintAnchor(
    this,
    ConstraintAnchorType.baseline,
  );

  /// The horizontal center's anchor.
  late final ConstraintAnchor mCenterX = ConstraintAnchor(
    this,
    ConstraintAnchorType.centerX,
  );

  /// The vertical center's anchor.
  late final ConstraintAnchor mCenterY = ConstraintAnchor(
    this,
    ConstraintAnchorType.centerY,
  );

  /// The center point's anchor, used for circular positioning (see
  /// [connectCircularConstraint]).
  late final ConstraintAnchor mCenter = ConstraintAnchor(
    this,
    ConstraintAnchorType.center,
  );

  /// The left, right, top, bottom, baseline, and center anchors, in that
  /// order, so the `ANCHOR_` constants index them. A [Guideline] points every
  /// entry at its single anchor.
  late List<ConstraintAnchor> mListAnchors = [
    mLeft,
    mRight,
    mTop,
    mBottom,
    mBaseline,
    mCenter,
  ];

  /// Every anchor of this widget; see [getAnchors].
  final List<ConstraintAnchor> mAnchors = [];

  /// The dimension behaviour of each axis, indexed by [HORIZONTAL] and
  /// [VERTICAL].
  List<DimensionBehaviour> mListDimensionBehaviors = [
    DimensionBehaviour.fixed,
    DimensionBehaviour.fixed,
  ];

  /// The parent widget, or null for a root.
  ConstraintWidget? mParent;

  /// The stored width. A layout writes the resolved width back here, and
  /// [getWidth] reports 0 instead while the widget is [GONE].
  int mWidth = 0;

  /// The stored height. A layout writes the resolved height back here, and
  /// [getHeight] reports 0 instead while the widget is [GONE].
  int mHeight = 0;

  /// The dimension ratio, or 0 for none; see [setDimensionRatio].
  double mDimensionRatio = 0;

  /// The side the dimension ratio computes; see [setDimensionRatio].
  int mDimensionRatioSide = UNKNOWN;

  /// The stored x position, without the parent's padding (see [getX]).
  int mX = 0;

  /// The stored y position, without the parent's padding (see [getY]).
  int mY = 0;
  int mOffsetX = 0;
  int mOffsetY = 0;

  /// The baseline's distance from the top edge; see [setBaselineDistance].
  int mBaselineDistance = 0;

  /// The minimum width; see [setMinWidth].
  int mMinWidth = 0;

  /// The minimum height; see [setMinHeight].
  int mMinHeight = 0;

  /// The horizontal bias; see [setHorizontalBiasPercent].
  double mHorizontalBiasPercent = DEFAULT_BIAS;

  /// The vertical bias; see [setVerticalBiasPercent].
  double mVerticalBiasPercent = DEFAULT_BIAS;

  /// The visibility: [VISIBLE], [INVISIBLE], or [GONE].
  int mVisibility = VISIBLE;

  /// The name used in debug output; see [setDebugName].
  String? mDebugName;

  /// The type name that [toString] prints and [getType] returns, or null.
  String? mTypeName;

  /// The style of the horizontal chain this widget heads; see
  /// [setHorizontalChainStyle].
  int mHorizontalChainStyle = CHAIN_SPREAD;

  /// The style of the vertical chain this widget heads; see
  /// [setVerticalChainStyle].
  int mVerticalChainStyle = CHAIN_SPREAD;

  /// The chain weights, indexed by [HORIZONTAL] and [VERTICAL], or [UNKNOWN]
  /// (-1) when unset; see [setHorizontalWeight].
  List<double> mWeight = [UNKNOWN.toDouble(), UNKNOWN.toDouble()];

  // Solver integration state (see addToSolver).
  /// Value of [mHorizontalResolution] or [mVerticalResolution] for an axis
  /// resolved directly, whose constraints [addToSolver] then skips.
  /// [Optimizer.checkMatchParent] sets it for match-parent axes.
  static const int DIRECT = 2;
  static const int _WRAP = -2;
  static const bool _USE_WRAP_DIMENSION_FOR_SPREAD = false;

  /// Wrap behaviour of a widget that counts toward a wrap-content parent's
  /// size on both axes. The default; see [setWrapBehaviorInParent].
  static const int WRAP_BEHAVIOR_INCLUDED = 0;

  /// Wrap behaviour of a widget that counts toward a wrap-content parent's
  /// width only.
  static const int WRAP_BEHAVIOR_HORIZONTAL_ONLY = 1;

  /// Wrap behaviour of a widget that counts toward a wrap-content parent's
  /// height only.
  static const int WRAP_BEHAVIOR_VERTICAL_ONLY = 2;

  /// Wrap behaviour of a widget that does not count toward a wrap-content
  /// parent's size.
  static const int WRAP_BEHAVIOR_SKIPPED = 3;

  int mHorizontalResolution = UNKNOWN;
  int mVerticalResolution = UNKNOWN;
  int mWrapBehaviorInParent = WRAP_BEHAVIOR_INCLUDED;
  final List<int> mMaxDimension = [intMaxValue, intMaxValue];
  double mCircleConstraintAngle = double.nan;
  final List<bool> mIsInBarrier = [false, false];
  bool mAnimated = false;
  bool mResolvedHorizontal = false;
  bool mResolvedVertical = false;
  int mWidthOverride = -1;
  int mHeightOverride = -1;
  final bool _optimizeWrapO = false;
  final bool _optimizeWrapOnResolved = true;

  final List<ConstraintWidget?> mNextChainWidget = [null, null];
  final List<ConstraintWidget?> mListNextMatchConstraintsWidget = [null, null];

  int horizontalGroup = -1;
  int verticalGroup = -1;

  ConstraintWidget() {
    _addAnchors();
  }

  /// Creates a widget named [debugName] for debugging, at (0, 0) with a size
  /// of 0 x 0.
  ConstraintWidget.named(String debugName) {
    _addAnchors();
    setDebugName(debugName);
  }

  /// Creates a widget at ([x], [y]) with the given [width] and [height].
  ConstraintWidget.rect(int x, int y, int width, int height) {
    mX = x;
    mY = y;
    mWidth = width;
    mHeight = height;
    _addAnchors();
  }

  /// Creates a widget at (0, 0) with the given [width] and [height].
  ConstraintWidget.size(int width, int height) {
    mX = 0;
    mY = 0;
    mWidth = width;
    mHeight = height;
    _addAnchors();
  }

  /// Creates a widget at (0, 0) with the given [width] and [height], named
  /// [debugName] for debugging.
  ConstraintWidget.sizeNamed(String debugName, int width, int height) {
    mX = 0;
    mY = 0;
    mWidth = width;
    mHeight = height;
    _addAnchors();
    setDebugName(debugName);
  }

  void _addAnchors() {
    mAnchors.add(mLeft);
    mAnchors.add(mTop);
    mAnchors.add(mRight);
    mAnchors.add(mBottom);
    mAnchors.add(mCenterX);
    mAnchors.add(mCenterY);
    mAnchors.add(mCenter);
    mAnchors.add(mBaseline);
  }

  /// Create this widget's dependency-graph runs ([mHorizontalRun] and
  /// [mVerticalRun]) if they do not exist yet.
  void ensureWidgetRuns() {
    mHorizontalRun ??= HorizontalWidgetRun(this);
    mVerticalRun ??= VerticalWidgetRun(this);
  }

  /// The dependency-graph run of [orientation] ([HORIZONTAL] or [VERTICAL]),
  /// or null for another value or before [ensureWidgetRuns] created it.
  WidgetRun? getRun(int orientation) {
    if (orientation == HORIZONTAL) {
      return mHorizontalRun;
    } else if (orientation == VERTICAL) {
      return mVerticalRun;
    }
    return null;
  }

  bool isInVirtualLayout() => mInVirtualLayout;
  void setInVirtualLayout(bool v) => mInVirtualLayout = v;

  int getMaxHeight() => mMaxDimension[VERTICAL];
  int getMaxWidth() => mMaxDimension[HORIZONTAL];
  void setMaxWidth(int v) => mMaxDimension[HORIZONTAL] = v;
  void setMaxHeight(int v) => mMaxDimension[VERTICAL] = v;

  /// Set whether this widget has a baseline. [setBaselineDistance] also sets
  /// it, to whether the distance is positive.
  void setHasBaseline(bool v) => mHasBaseline = v;

  /// Whether this widget has a baseline (same as [hasBaseline]).
  bool getHasBaseline() => mHasBaseline;

  /// Set whether this widget needs to be measured again: a hint for
  /// measurers that cache their results. [Flow] sets it when it changes a
  /// widget's size, and a measurer typically clears it after measuring.
  void setMeasureRequested(bool v) => mMeasureRequested = v;

  /// Whether a measure was requested ([setMeasureRequested]) and the widget
  /// is not [GONE].
  bool isMeasureRequested() => mMeasureRequested && mVisibility != GONE;

  /// Returns true if the widget is the root widget (it has no parent).
  bool isRoot() => mParent == null;

  /// Returns the parent of this widget, or null for a root.
  ConstraintWidget? getParent() => mParent;

  /// Set the parent of this widget. [WidgetContainer.add] and
  /// [WidgetContainer.remove] set it.
  void setParent(ConstraintWidget? widget) => mParent = widget;

  /// Set the visibility of this widget: [VISIBLE], [INVISIBLE], or [GONE].
  void setVisibility(int visibility) => mVisibility = visibility;

  /// The visibility of this widget: [VISIBLE], [INVISIBLE], or [GONE].
  int getVisibility() => mVisibility;

  /// The name of this widget used in debug output such as [toString], or
  /// null.
  String? getDebugName() => mDebugName;

  /// Set the name of this widget used in debug output.
  void setDebugName(String? name) => mDebugName = name;

  /// The type name of this widget: [mTypeName], which is null unless set.
  /// [Guideline] and [ConstraintWidgetContainer] return fixed names.
  String? getType() => mTypeName;

  /// Return the x position of the widget, relative to its parent. When the
  /// parent is a [ConstraintWidgetContainer], this includes the parent's left
  /// padding.
  int getX() {
    final p = mParent;
    if (p is ConstraintWidgetContainer) {
      return p.mPaddingLeft + mX;
    }
    return mX;
  }

  /// Return the y position of the widget, relative to its parent. When the
  /// parent is a [ConstraintWidgetContainer], this includes the parent's top
  /// padding.
  int getY() {
    final p = mParent;
    if (p is ConstraintWidgetContainer) {
      return p.mPaddingTop + mY;
    }
    return mY;
  }

  /// Return the width of the widget, or 0 when it is [GONE].
  int getWidth() => mVisibility == GONE ? 0 : mWidth;

  /// Return the height of the widget, or 0 when it is [GONE].
  int getHeight() => mVisibility == GONE ? 0 : mHeight;

  /// Get the dimension of the widget in [orientation]: [getWidth] for
  /// [HORIZONTAL], [getHeight] for [VERTICAL], and 0 otherwise.
  int getLength(int orientation) {
    if (orientation == HORIZONTAL) {
      return getWidth();
    } else if (orientation == VERTICAL) {
      return getHeight();
    }
    return 0;
  }

  /// Return the minimum width of the widget; see [setMinWidth].
  int getMinWidth() => mMinWidth;

  /// Return the minimum height of the widget; see [setMinHeight].
  int getMinHeight() => mMinHeight;

  /// Return the left position of the widget (same as [getX]).
  int getLeft() => getX();

  /// Return the top position of the widget (same as [getY]).
  int getTop() => getY();

  /// Return the right position of the widget: [getX] plus the stored width.
  int getRight() => getX() + mWidth;

  /// Return the bottom position of the widget: [getY] plus the stored
  /// height.
  int getBottom() => getY() + mHeight;

  /// Return the horizontal bias, used when both horizontal sides are
  /// constrained; see [setHorizontalBiasPercent].
  double getHorizontalBiasPercent() => mHorizontalBiasPercent;

  /// Return the vertical bias, used when both vertical sides are constrained;
  /// see [setVerticalBiasPercent].
  double getVerticalBiasPercent() => mVerticalBiasPercent;

  /// Return the bias of [orientation] ([HORIZONTAL] or [VERTICAL]), or
  /// [UNKNOWN] (-1) for another value.
  double getBiasPercent(int orientation) {
    if (orientation == HORIZONTAL) {
      return mHorizontalBiasPercent;
    } else if (orientation == VERTICAL) {
      return mVerticalBiasPercent;
    }
    return UNKNOWN.toDouble();
  }

  /// Return true if this widget has a baseline.
  bool hasBaseline() => mHasBaseline;

  /// Return the baseline distance relative to the top of the widget.
  int getBaselineDistance() => mBaselineDistance;

  /// Return the anchors of this widget ([mAnchors]). A [Guideline] has only
  /// its single anchor.
  List<ConstraintAnchor> getAnchors() => mAnchors;

  /// Set the x position of the widget, relative to its parent ([getX] adds a
  /// container parent's left padding).
  void setX(int x) => mX = x;

  /// Set the y position of the widget, relative to its parent ([getY] adds a
  /// container parent's top padding).
  void setY(int y) => mY = y;

  /// Set both the x and y positions of the widget (see [setX] and [setY]).
  void setOrigin(int x, int y) {
    mX = x;
    mY = y;
  }

  /// Set the margin the [type] anchor uses when the widget it connects to is
  /// [GONE]. Only the side and baseline anchors take one. Set it after
  /// connecting the anchor: [connect] resets it.
  void setGoneMargin(ConstraintAnchorType type, int goneMargin) {
    switch (type) {
      case ConstraintAnchorType.left:
        mLeft.mGoneMargin = goneMargin;
        break;
      case ConstraintAnchorType.top:
        mTop.mGoneMargin = goneMargin;
        break;
      case ConstraintAnchorType.right:
        mRight.mGoneMargin = goneMargin;
        break;
      case ConstraintAnchorType.bottom:
        mBottom.mGoneMargin = goneMargin;
        break;
      case ConstraintAnchorType.baseline:
        mBaseline.mGoneMargin = goneMargin;
        break;
      default:
        break;
    }
  }

  /// Set the width of the widget, raised to [getMinWidth] if smaller.
  void setWidth(int w) {
    mWidth = w;
    if (mWidth < mMinWidth) {
      mWidth = mMinWidth;
    }
  }

  /// Set the height of the widget, raised to [getMinHeight] if smaller.
  void setHeight(int h) {
    mHeight = h;
    if (mHeight < mMinHeight) {
      mHeight = mMinHeight;
    }
  }

  /// Set the dimension of the widget in [orientation]: the width for
  /// [HORIZONTAL] (as [setWidth] does) or the height for [VERTICAL].
  void setLength(int length, int orientation) {
    if (orientation == HORIZONTAL) {
      setWidth(length);
    } else if (orientation == VERTICAL) {
      setHeight(length);
    }
  }

  /// Set how a [DimensionBehaviour.matchConstraint] width is sized.
  ///
  /// [horizontalMatchStyle] is [MATCH_CONSTRAINT_SPREAD],
  /// [MATCH_CONSTRAINT_WRAP], or [MATCH_CONSTRAINT_PERCENT]. [min] and [max]
  /// bound the width, where 0 means no bound (as does [intMaxValue] for
  /// [max]). [percent] is the fraction (0 to 1) of the parent's width that
  /// [MATCH_CONSTRAINT_PERCENT] takes; the spread style with a [percent]
  /// strictly between 0 and 1 switches to [MATCH_CONSTRAINT_PERCENT].
  void setHorizontalMatchStyle(
    int horizontalMatchStyle,
    int min,
    int max,
    double percent,
  ) {
    mMatchConstraintDefaultWidth = horizontalMatchStyle;
    mMatchConstraintMinWidth = min;
    mMatchConstraintMaxWidth = (max == intMaxValue) ? 0 : max;
    mMatchConstraintPercentWidth = percent;
    if (percent > 0 &&
        percent < 1 &&
        mMatchConstraintDefaultWidth == MATCH_CONSTRAINT_SPREAD) {
      mMatchConstraintDefaultWidth = MATCH_CONSTRAINT_PERCENT;
    }
  }

  /// Set how a [DimensionBehaviour.matchConstraint] height is sized.
  ///
  /// [verticalMatchStyle] is [MATCH_CONSTRAINT_SPREAD],
  /// [MATCH_CONSTRAINT_WRAP], or [MATCH_CONSTRAINT_PERCENT]. [min] and [max]
  /// bound the height, where 0 means no bound (as does [intMaxValue] for
  /// [max]). [percent] is the fraction (0 to 1) of the parent's height that
  /// [MATCH_CONSTRAINT_PERCENT] takes; the spread style with a [percent]
  /// strictly between 0 and 1 switches to [MATCH_CONSTRAINT_PERCENT].
  void setVerticalMatchStyle(
    int verticalMatchStyle,
    int min,
    int max,
    double percent,
  ) {
    mMatchConstraintDefaultHeight = verticalMatchStyle;
    mMatchConstraintMinHeight = min;
    mMatchConstraintMaxHeight = (max == intMaxValue) ? 0 : max;
    mMatchConstraintPercentHeight = percent;
    if (percent > 0 &&
        percent < 1 &&
        mMatchConstraintDefaultHeight == MATCH_CONSTRAINT_SPREAD) {
      mMatchConstraintDefaultHeight = MATCH_CONSTRAINT_PERCENT;
    }
  }

  /// Set the dimension ratio from a string: `width:height` (such as `16:9`)
  /// or a single number, optionally prefixed with the side to compute, `W,`
  /// for the width or `H,` for the height (case-insensitive). A single number
  /// is used as is, so it is width / height unless the `H,` prefix makes it
  /// height / width.
  ///
  /// A null or empty [ratio] removes the ratio, and one that does not parse
  /// to a positive value is ignored. The ratio applies when at least one
  /// axis is [DimensionBehaviour.matchConstraint]; see [setDimensionRatio].
  void setDimensionRatioString(String? ratio) {
    if (ratio == null || ratio.isEmpty) {
      mDimensionRatio = 0;
      return;
    }
    var dimensionRatioSide = UNKNOWN;
    double dimensionRatio = 0;
    final len = ratio.length;
    var commaIndex = ratio.indexOf(',');
    if (commaIndex > 0 && commaIndex < len - 1) {
      final dimension = ratio.substring(0, commaIndex);
      if (dimension.toUpperCase() == 'W') {
        dimensionRatioSide = HORIZONTAL;
      } else if (dimension.toUpperCase() == 'H') {
        dimensionRatioSide = VERTICAL;
      }
      commaIndex++;
    } else {
      commaIndex = 0;
    }
    final colonIndex = ratio.indexOf(':');
    if (colonIndex >= 0 && colonIndex < len - 1) {
      final nominator = ratio.substring(commaIndex, colonIndex);
      final denominator = ratio.substring(colonIndex + 1);
      if (nominator.isNotEmpty && denominator.isNotEmpty) {
        final nominatorValue = double.tryParse(nominator);
        final denominatorValue = double.tryParse(denominator);
        if (nominatorValue != null &&
            denominatorValue != null &&
            nominatorValue > 0 &&
            denominatorValue > 0) {
          if (dimensionRatioSide == VERTICAL) {
            dimensionRatio = (denominatorValue / nominatorValue).abs();
          } else {
            dimensionRatio = (nominatorValue / denominatorValue).abs();
          }
        }
      }
    } else {
      final r = ratio.substring(commaIndex);
      if (r.isNotEmpty) {
        final v = double.tryParse(r);
        if (v != null) {
          dimensionRatio = v;
        }
      }
    }
    if (dimensionRatio > 0) {
      mDimensionRatio = dimensionRatio;
      mDimensionRatioSide = dimensionRatioSide;
    }
  }

  /// Set the ratio of the widget and the side it computes.
  ///
  /// The ratio applies when at least one axis is
  /// [DimensionBehaviour.matchConstraint]: that dimension is derived from
  /// the other one. [dimensionRatioSide] is [HORIZONTAL] (derive the width),
  /// [VERTICAL] (derive the height), or [UNKNOWN] (let the engine pick).
  /// [ratio] is width / height, except with [VERTICAL], where it is
  /// height / width. A ratio of 0 removes it.
  void setDimensionRatio(double ratio, int dimensionRatioSide) {
    mDimensionRatio = ratio;
    mDimensionRatioSide = dimensionRatioSide;
  }

  /// Return the current ratio of this widget, or 0 when none is set.
  double getDimensionRatio() => mDimensionRatio;

  /// Return the side the ratio computes: [HORIZONTAL], [VERTICAL], or
  /// [UNKNOWN].
  int getDimensionRatioSide() => mDimensionRatioSide;

  /// Set the horizontal bias to apply when both horizontal sides are
  /// constrained: 0 puts the widget against the left target, 1 against the
  /// right one, and 0.5 (the default) centers it. The head of a packed chain
  /// places the whole chain with it.
  void setHorizontalBiasPercent(double v) => mHorizontalBiasPercent = v;

  /// Set the vertical bias to apply when both vertical sides are
  /// constrained: 0 puts the widget against the top target, 1 against the
  /// bottom one, and 0.5 (the default) centers it. The head of a packed
  /// chain places the whole chain with it.
  void setVerticalBiasPercent(double v) => mVerticalBiasPercent = v;

  /// Set the minimum width of the widget (a negative value becomes 0).
  /// [setWidth] and the layout raise smaller widths to it.
  void setMinWidth(int w) => mMinWidth = w < 0 ? 0 : w;

  /// Set the minimum height of the widget (a negative value becomes 0).
  /// [setHeight] and the layout raise smaller heights to it.
  void setMinHeight(int h) => mMinHeight = h < 0 ? 0 : h;

  /// Set both the width and the height of the widget, each raised to its
  /// minimum if smaller.
  void setDimension(int w, int h) {
    mWidth = w;
    if (mWidth < mMinWidth) mWidth = mMinWidth;
    mHeight = h;
    if (mHeight < mMinHeight) mHeight = mMinHeight;
  }

  /// Set the position and size of the widget from its [left], [top],
  /// [right], and [bottom] edges.
  ///
  /// A [GONE] widget gets a size of 0 x 0. A fixed axis never shrinks below
  /// its stored size, both sizes are raised to their minimums, and a
  /// match-constraint axis is capped at its match-constraint maximum. When
  /// a minimum or a maximum changed a size, that size is recorded as an
  /// override ([hasDimensionOverride]): the next solve treats it as fixed,
  /// and [ConstraintWidgetContainer.layout] solves again to apply it.
  void setFrame(int left, int top, int right, int bottom) {
    var w = right - left;
    var h = bottom - top;
    mX = left;
    mY = top;
    if (mVisibility == GONE) {
      mWidth = 0;
      mHeight = 0;
      return;
    }
    // correct dimensional instability caused by rounding errors
    if (mListDimensionBehaviors[HORIZONTAL] == DimensionBehaviour.fixed &&
        w < mWidth) {
      w = mWidth;
    }
    if (mListDimensionBehaviors[VERTICAL] == DimensionBehaviour.fixed &&
        h < mHeight) {
      h = mHeight;
    }
    mWidth = w;
    mHeight = h;
    if (mHeight < mMinHeight) mHeight = mMinHeight;
    if (mWidth < mMinWidth) mWidth = mMinWidth;
    if (mMatchConstraintMaxWidth > 0 &&
        mListDimensionBehaviors[HORIZONTAL] ==
            DimensionBehaviour.matchConstraint) {
      mWidth = mWidth < mMatchConstraintMaxWidth
          ? mWidth
          : mMatchConstraintMaxWidth;
    }
    if (mMatchConstraintMaxHeight > 0 &&
        mListDimensionBehaviors[VERTICAL] ==
            DimensionBehaviour.matchConstraint) {
      mHeight = mHeight < mMatchConstraintMaxHeight
          ? mHeight
          : mMatchConstraintMaxHeight;
    }
    if (w != mWidth) {
      mWidthOverride = mWidth;
    }
    if (h != mHeight) {
      mHeightOverride = mHeight;
    }
  }

  /// Set the horizontal position and the width only, from the [left] and
  /// [right] edges (the width is raised to its minimum if smaller).
  void setHorizontalDimension(int left, int right) {
    mX = left;
    mWidth = right - left;
    if (mWidth < mMinWidth) mWidth = mMinWidth;
  }

  /// Set the vertical position and the height only, from the [top] and
  /// [bottom] edges (the height is raised to its minimum if smaller).
  void setVerticalDimension(int top, int bottom) {
    mY = top;
    mHeight = bottom - top;
    if (mHeight < mMinHeight) mHeight = mMinHeight;
  }

  /// Set the baseline distance relative to the top of the widget. A positive
  /// distance also marks the widget as having a baseline ([hasBaseline]),
  /// and 0 or less clears it.
  void setBaselineDistance(int baseline) {
    mBaselineDistance = baseline;
    mHasBaseline = baseline > 0;
  }

  /// Set the horizontal weight (only used in chains): the match-constraint
  /// members of a chain share its leftover space in proportion to their
  /// weights.
  void setHorizontalWeight(double horizontalWeight) =>
      mWeight[HORIZONTAL] = horizontalWeight;

  /// Set the vertical weight (only used in chains): the match-constraint
  /// members of a chain share its leftover space in proportion to their
  /// weights.
  void setVerticalWeight(double verticalWeight) =>
      mWeight[VERTICAL] = verticalWeight;

  /// Set the style of the horizontal chain this widget heads:
  /// [CHAIN_SPREAD] (the default), [CHAIN_SPREAD_INSIDE], or [CHAIN_PACKED].
  /// Only the chain head's style is used.
  void setHorizontalChainStyle(int v) => mHorizontalChainStyle = v;

  /// Return the style of the horizontal chain this widget heads; see
  /// [setHorizontalChainStyle].
  int getHorizontalChainStyle() => mHorizontalChainStyle;

  /// Set the style of the vertical chain this widget heads: [CHAIN_SPREAD]
  /// (the default), [CHAIN_SPREAD_INSIDE], or [CHAIN_PACKED]. Only the chain
  /// head's style is used.
  void setVerticalChainStyle(int v) => mVerticalChainStyle = v;

  /// Return the style of the vertical chain this widget heads; see
  /// [setVerticalChainStyle].
  int getVerticalChainStyle() => mVerticalChainStyle;

  /// Returns true if this widget should be used by a [Barrier] that does not
  /// allow gone widgets (see [Barrier.setAllowsGoneWidget]): true unless the
  /// widget is [GONE].
  bool allowedInBarrier() => mVisibility != GONE;

  // ---- connections ----
  /// Connect the given anchors together, as [connect] does. [from] must be
  /// an anchor of this widget; otherwise nothing happens.
  void connectAnchors(ConstraintAnchor from, ConstraintAnchor to, int margin) {
    if (from.getOwner() == this) {
      connect(from.getType(), to.getOwner(), to.getType(), margin);
    }
  }

  /// Connect the [constraintFrom] anchor of this widget to the
  /// [constraintTo] anchor of [target], keeping [margin] as a minimum
  /// distance between the two.
  ///
  /// The margin is measured away from the target, so a margin on a right or
  /// bottom anchor moves the widget left or up. An invalid pair, such as
  /// left to top, is ignored (see [ConstraintAnchor.isValidConnection]).
  /// Connecting a baseline drops the top and bottom connections, and
  /// connecting a top or bottom drops the baseline connection.
  ///
  /// The center types connect pairs of sides, without a margin:
  /// [ConstraintAnchorType.centerX] connects both left and right (to the
  /// target's centerX, left, or right), and [ConstraintAnchorType.centerY]
  /// both top and bottom. [ConstraintAnchorType.center] is meant for
  /// [connectCircularConstraint]: connected to another center here, it
  /// connects the sides of each axis that has no connection yet, and when
  /// both axes are free it also connects the center anchor, which leaves the
  /// widget uncentered without an angle. Use centerX and centerY to center a
  /// widget.
  void connect(
    ConstraintAnchorType constraintFrom,
    ConstraintWidget target,
    ConstraintAnchorType constraintTo, [
    int margin = 0,
  ]) {
    if (constraintFrom == ConstraintAnchorType.center) {
      if (constraintTo == ConstraintAnchorType.center) {
        final left = getAnchor(ConstraintAnchorType.left);
        final right = getAnchor(ConstraintAnchorType.right);
        final top = getAnchor(ConstraintAnchorType.top);
        final bottom = getAnchor(ConstraintAnchorType.bottom);
        var centerX = false;
        var centerY = false;
        if ((left != null && left.isConnected()) ||
            (right != null && right.isConnected())) {
          // don't apply center here
        } else {
          connect(
            ConstraintAnchorType.left,
            target,
            ConstraintAnchorType.left,
            0,
          );
          connect(
            ConstraintAnchorType.right,
            target,
            ConstraintAnchorType.right,
            0,
          );
          centerX = true;
        }
        if ((top != null && top.isConnected()) ||
            (bottom != null && bottom.isConnected())) {
          // don't apply center here
        } else {
          connect(
            ConstraintAnchorType.top,
            target,
            ConstraintAnchorType.top,
            0,
          );
          connect(
            ConstraintAnchorType.bottom,
            target,
            ConstraintAnchorType.bottom,
            0,
          );
          centerY = true;
        }
        if (centerX && centerY) {
          final center = getAnchor(ConstraintAnchorType.center)!;
          center.connect(target.getAnchor(ConstraintAnchorType.center), 0);
        } else if (centerX) {
          final center = getAnchor(ConstraintAnchorType.centerX)!;
          center.connect(target.getAnchor(ConstraintAnchorType.centerX), 0);
        } else if (centerY) {
          final center = getAnchor(ConstraintAnchorType.centerY)!;
          center.connect(target.getAnchor(ConstraintAnchorType.centerY), 0);
        }
      } else if (constraintTo == ConstraintAnchorType.left ||
          constraintTo == ConstraintAnchorType.right) {
        connect(ConstraintAnchorType.left, target, constraintTo, 0);
        connect(ConstraintAnchorType.right, target, constraintTo, 0);
        final center = getAnchor(ConstraintAnchorType.center)!;
        center.connect(target.getAnchor(constraintTo), 0);
      } else if (constraintTo == ConstraintAnchorType.top ||
          constraintTo == ConstraintAnchorType.bottom) {
        connect(ConstraintAnchorType.top, target, constraintTo, 0);
        connect(ConstraintAnchorType.bottom, target, constraintTo, 0);
        final center = getAnchor(ConstraintAnchorType.center)!;
        center.connect(target.getAnchor(constraintTo), 0);
      }
    } else if (constraintFrom == ConstraintAnchorType.centerX &&
        (constraintTo == ConstraintAnchorType.left ||
            constraintTo == ConstraintAnchorType.right)) {
      final left = getAnchor(ConstraintAnchorType.left)!;
      final targetAnchor = target.getAnchor(constraintTo);
      final right = getAnchor(ConstraintAnchorType.right)!;
      left.connect(targetAnchor, 0);
      right.connect(targetAnchor, 0);
      final centerX = getAnchor(ConstraintAnchorType.centerX)!;
      centerX.connect(targetAnchor, 0);
    } else if (constraintFrom == ConstraintAnchorType.centerY &&
        (constraintTo == ConstraintAnchorType.top ||
            constraintTo == ConstraintAnchorType.bottom)) {
      final targetAnchor = target.getAnchor(constraintTo);
      final top = getAnchor(ConstraintAnchorType.top)!;
      top.connect(targetAnchor, 0);
      final bottom = getAnchor(ConstraintAnchorType.bottom)!;
      bottom.connect(targetAnchor, 0);
      final centerY = getAnchor(ConstraintAnchorType.centerY)!;
      centerY.connect(targetAnchor, 0);
    } else if (constraintFrom == ConstraintAnchorType.centerX &&
        constraintTo == ConstraintAnchorType.centerX) {
      final left = getAnchor(ConstraintAnchorType.left)!;
      final leftTarget = target.getAnchor(ConstraintAnchorType.left);
      left.connect(leftTarget, 0);
      final right = getAnchor(ConstraintAnchorType.right)!;
      final rightTarget = target.getAnchor(ConstraintAnchorType.right);
      right.connect(rightTarget, 0);
      final centerX = getAnchor(ConstraintAnchorType.centerX)!;
      centerX.connect(target.getAnchor(constraintTo), 0);
    } else if (constraintFrom == ConstraintAnchorType.centerY &&
        constraintTo == ConstraintAnchorType.centerY) {
      final top = getAnchor(ConstraintAnchorType.top)!;
      final topTarget = target.getAnchor(ConstraintAnchorType.top);
      top.connect(topTarget, 0);
      final bottom = getAnchor(ConstraintAnchorType.bottom)!;
      final bottomTarget = target.getAnchor(ConstraintAnchorType.bottom);
      bottom.connect(bottomTarget, 0);
      final centerY = getAnchor(ConstraintAnchorType.centerY)!;
      centerY.connect(target.getAnchor(constraintTo), 0);
    } else {
      final fromAnchor = getAnchor(constraintFrom)!;
      final toAnchor = target.getAnchor(constraintTo);
      if (fromAnchor.isValidConnection(toAnchor)) {
        if (constraintFrom == ConstraintAnchorType.baseline) {
          final top = getAnchor(ConstraintAnchorType.top);
          final bottom = getAnchor(ConstraintAnchorType.bottom);
          top?.reset();
          bottom?.reset();
        } else if (constraintFrom == ConstraintAnchorType.top ||
            constraintFrom == ConstraintAnchorType.bottom) {
          final baseline = getAnchor(ConstraintAnchorType.baseline);
          baseline?.reset();
          final center = getAnchor(ConstraintAnchorType.center)!;
          if (center.getTarget() != toAnchor) {
            center.reset();
          }
          final opposite = getAnchor(constraintFrom)!.getOpposite();
          final centerY = getAnchor(ConstraintAnchorType.centerY)!;
          if (centerY.isConnected()) {
            opposite?.reset();
            centerY.reset();
          }
        } else if (constraintFrom == ConstraintAnchorType.left ||
            constraintFrom == ConstraintAnchorType.right) {
          final center = getAnchor(ConstraintAnchorType.center)!;
          if (center.getTarget() != toAnchor) {
            center.reset();
          }
          final opposite = getAnchor(constraintFrom)!.getOpposite();
          final centerX = getAnchor(ConstraintAnchorType.centerX)!;
          if (centerX.isConnected()) {
            opposite?.reset();
            centerX.reset();
          }
        }
        fromAnchor.connect(toAnchor, margin);
      }
    }
  }

  /// Reset all connections of this widget's anchors (see
  /// [ConstraintAnchor.reset]).
  void resetAnchors() {
    for (final anchor in mAnchors) {
      anchor.reset();
    }
  }

  /// Given a type of anchor, returns the corresponding anchor of this widget,
  /// or null for [ConstraintAnchorType.none].
  ConstraintAnchor? getAnchor(ConstraintAnchorType anchorType) {
    switch (anchorType) {
      case ConstraintAnchorType.left:
        return mLeft;
      case ConstraintAnchorType.top:
        return mTop;
      case ConstraintAnchorType.right:
        return mRight;
      case ConstraintAnchorType.bottom:
        return mBottom;
      case ConstraintAnchorType.baseline:
        return mBaseline;
      case ConstraintAnchorType.centerX:
        return mCenterX;
      case ConstraintAnchorType.centerY:
        return mCenterY;
      case ConstraintAnchorType.center:
        return mCenter;
      case ConstraintAnchorType.none:
        return null;
    }
  }

  /// Accessor for the horizontal dimension behaviour (how the width is
  /// determined).
  DimensionBehaviour getHorizontalDimensionBehaviour() =>
      mListDimensionBehaviors[HORIZONTAL];

  /// Accessor for the vertical dimension behaviour (how the height is
  /// determined).
  DimensionBehaviour getVerticalDimensionBehaviour() =>
      mListDimensionBehaviors[VERTICAL];

  /// Get the dimension behaviour of [orientation] ([HORIZONTAL] or
  /// [VERTICAL]), or null for another value.
  DimensionBehaviour? getDimensionBehaviour(int orientation) {
    if (orientation == HORIZONTAL) {
      return getHorizontalDimensionBehaviour();
    } else if (orientation == VERTICAL) {
      return getVerticalDimensionBehaviour();
    }
    return null;
  }

  /// Set the widget's behaviour for the horizontal dimension: how its width
  /// is determined (see [DimensionBehaviour]).
  void setHorizontalDimensionBehaviour(DimensionBehaviour behaviour) =>
      mListDimensionBehaviors[HORIZONTAL] = behaviour;

  /// Set the widget's behaviour for the vertical dimension: how its height is
  /// determined (see [DimensionBehaviour]).
  void setVerticalDimensionBehaviour(DimensionBehaviour behaviour) =>
      mListDimensionBehaviors[VERTICAL] = behaviour;

  /// Returns true if this widget is in a horizontal chain: connected in both
  /// directions to a neighbour on its left or right.
  bool isInHorizontalChain() {
    if ((mLeft.mTarget != null && mLeft.mTarget!.mTarget == mLeft) ||
        (mRight.mTarget != null && mRight.mTarget!.mTarget == mRight)) {
      return true;
    }
    return false;
  }

  /// Return the previous member of this widget's chain along [orientation]
  /// ([HORIZONTAL] or [VERTICAL]), or null if this widget is the first chain
  /// element.
  ConstraintWidget? getPreviousChainMember(int orientation) {
    if (orientation == HORIZONTAL) {
      if (mLeft.mTarget != null && mLeft.mTarget!.mTarget == mLeft) {
        return mLeft.mTarget!.mOwner;
      }
    } else if (orientation == VERTICAL) {
      if (mTop.mTarget != null && mTop.mTarget!.mTarget == mTop) {
        return mTop.mTarget!.mOwner;
      }
    }
    return null;
  }

  /// Return the next member of this widget's chain along [orientation]
  /// ([HORIZONTAL] or [VERTICAL]), or null if this widget is the last chain
  /// element.
  ConstraintWidget? getNextChainMember(int orientation) {
    if (orientation == HORIZONTAL) {
      if (mRight.mTarget != null && mRight.mTarget!.mTarget == mRight) {
        return mRight.mTarget!.mOwner;
      }
    } else if (orientation == VERTICAL) {
      if (mBottom.mTarget != null && mBottom.mTarget!.mTarget == mBottom) {
        return mBottom.mTarget!.mOwner;
      }
    }
    return null;
  }

  /// Returns true if this widget is in a vertical chain: connected in both
  /// directions to a neighbour above or below it.
  bool isInVerticalChain() {
    if ((mTop.mTarget != null && mTop.mTarget!.mTarget == mTop) ||
        (mBottom.mTarget != null && mBottom.mTarget!.mTarget == mBottom)) {
      return true;
    }
    return false;
  }

  /// Copy the positions and sizes the dependency graph resolved into this
  /// widget, for the axes [updateHorizontal] and [updateVertical] select.
  ///
  /// An axis is only copied once its run is resolved. A fixed axis keeps a
  /// larger stored size, sizes are raised to their minimums, and a [GONE]
  /// widget gets a size of 0 x 0. Does nothing for a widget without runs
  /// (see [ensureWidgetRuns]).
  void updateFromRuns(bool updateHorizontal, bool updateVertical) {
    if (mHorizontalRun == null || mVerticalRun == null) {
      // Widgets that never entered a dependency graph (children of a nested
      // container laid out via the solver) have no runs to read from.
      return;
    }
    updateHorizontal = updateHorizontal && mHorizontalRun!.isResolved();
    updateVertical = updateVertical && mVerticalRun!.isResolved();
    var left = mHorizontalRun!.start.value;
    var top = mVerticalRun!.start.value;
    var right = mHorizontalRun!.end.value;
    var bottom = mVerticalRun!.end.value;
    var w = right - left;
    var h = bottom - top;
    if (w < 0 ||
        h < 0 ||
        left == intMinValue ||
        left == intMaxValue ||
        top == intMinValue ||
        top == intMaxValue ||
        right == intMinValue ||
        right == intMaxValue ||
        bottom == intMinValue ||
        bottom == intMaxValue) {
      left = 0;
      top = 0;
      right = 0;
      bottom = 0;
    }
    w = right - left;
    h = bottom - top;
    if (updateHorizontal) {
      mX = left;
    }
    if (updateVertical) {
      mY = top;
    }
    if (mVisibility == GONE) {
      mWidth = 0;
      mHeight = 0;
      return;
    }
    if (updateHorizontal) {
      if (mListDimensionBehaviors[HORIZONTAL] == DimensionBehaviour.fixed &&
          w < mWidth) {
        w = mWidth;
      }
      mWidth = w;
      if (mWidth < mMinWidth) {
        mWidth = mMinWidth;
      }
    }
    if (updateVertical) {
      if (mListDimensionBehaviors[VERTICAL] == DimensionBehaviour.fixed &&
          h < mHeight) {
        h = mHeight;
      }
      mHeight = h;
      if (mHeight < mMinHeight) {
        mHeight = mMinHeight;
      }
    }
  }

  /*-----------------------------------------------------------------------*/
  // Solver integration
  /*-----------------------------------------------------------------------*/

  /// Create all the system variables for this widget.
  void createObjectVariables(LinearSystem system) {
    system.createObjectVariable(mLeft);
    system.createObjectVariable(mTop);
    system.createObjectVariable(mRight);
    system.createObjectVariable(mBottom);
    if (mBaselineDistance > 0) {
      system.createObjectVariable(mBaseline);
    }
  }

  /// Whether the horizontal position and width are already resolved: set by
  /// [setFinalHorizontal], or final values on both the left and right
  /// anchors.
  bool isResolvedHorizontally() =>
      mResolvedHorizontal || (mLeft.hasFinalValue() && mRight.hasFinalValue());

  /// Whether the vertical position and height are already resolved: set by
  /// [setFinalVertical], or final values on both the top and bottom anchors.
  bool isResolvedVertically() =>
      mResolvedVertical || (mTop.hasFinalValue() && mBottom.hasFinalValue());

  /// Forget the positions [setFinalHorizontal] and [setFinalVertical] gave
  /// this widget, and the final value of every anchor. Upstream's
  /// ConstraintWidget.resetFinalResolution, less the solving-pass flags of
  /// the Direct pass this port has no use for.
  /// [ConstraintWidgetContainer.layout] calls it on the container and on
  /// every child first, as upstream's Direct pass does on every measure at
  /// Android's default optimization level.
  void resetFinalResolution() {
    mResolvedHorizontal = false;
    mResolvedVertical = false;
    for (final anchor in mAnchors) {
      anchor.resetFinalResolution();
    }
  }

  /// Resolve the horizontal axis to the left edge [x1] and the right edge
  /// [x2], as final values on the anchors. [addToSolver] then adds them as
  /// constants. Ignored once the axis was resolved this way.
  void setFinalHorizontal(int x1, int x2) {
    if (mResolvedHorizontal) {
      return;
    }
    mLeft.setFinalValue(x1);
    mRight.setFinalValue(x2);
    mX = x1;
    mWidth = x2 - x1;
    mResolvedHorizontal = true;
  }

  /// Resolve the vertical axis to the top edge [y1] and the bottom edge
  /// [y2], as final values on the anchors. [addToSolver] then adds them as
  /// constants. Ignored once the axis was resolved this way.
  void setFinalVertical(int y1, int y2) {
    if (mResolvedVertical) {
      return;
    }
    mTop.setFinalValue(y1);
    mBottom.setFinalValue(y2);
    mY = y1;
    mHeight = y2 - y1;
    mResolvedVertical = true;
  }

  /// Reset the solver variables of the anchors.
  void resetSolverVariables(Cache cache) {
    mLeft.resetSolverVariable(cache);
    mTop.resetSolverVariable(cache);
    mRight.resetSolverVariable(cache);
    mBottom.resetSolverVariable(cache);
    mBaseline.resetSolverVariable(cache);
    mCenter.resetSolverVariable(cache);
    mCenterX.resetSolverVariable(cache);
    mCenterY.resetSolverVariable(cache);
  }

  /// Mark whether a [Barrier] along [orientation] ([HORIZONTAL] or
  /// [VERTICAL]) references this widget. [Barrier.markWidgets] sets it
  /// before solving.
  void setInBarrier(int orientation, bool value) {
    mIsInBarrier[orientation] = value;
  }

  /// Whether a [Barrier] along [orientation] references this widget; see
  /// [setInBarrier].
  bool isInBarrier(int orientation) => mIsInBarrier[orientation];

  /// Set how this widget counts toward the size of a wrap-content parent:
  /// [WRAP_BEHAVIOR_INCLUDED] (the default), [WRAP_BEHAVIOR_HORIZONTAL_ONLY],
  /// [WRAP_BEHAVIOR_VERTICAL_ONLY], or [WRAP_BEHAVIOR_SKIPPED]. Other values
  /// are ignored.
  ///
  /// The solver ([addToSolver]) applies it. The dependency graph does not
  /// model it, so a layout where it has an effect, a parent that wraps its
  /// content on an axis this widget does not count toward, is resolved by
  /// the solver.
  void setWrapBehaviorInParent(int behavior) {
    if (behavior >= 0 && behavior <= WRAP_BEHAVIOR_SKIPPED) {
      mWrapBehaviorInParent = behavior;
    }
  }

  /// How this widget counts toward the size of a wrap-content parent; see
  /// [setWrapBehaviorInParent].
  int getWrapBehaviorInParent() => mWrapBehaviorInParent;

  /// Whether an anchor of another widget is connected to one of this
  /// widget's anchors.
  bool hasDependencies() {
    for (final anchor in mAnchors) {
      if (anchor.hasDependents()) {
        return true;
      }
    }
    return false;
  }

  /// Whether a width or height override is pending ([mWidthOverride] or
  /// [mHeightOverride] set), which makes the solver treat that size as fixed
  /// on its next pass. [setFrame] records one when a minimum or a maximum
  /// changed the size the solver gave the widget.
  bool hasDimensionOverride() => mWidthOverride != -1 || mHeightOverride != -1;

  /// Immediate connection to an anchor without any checks.
  void immediateConnect(
    ConstraintAnchorType startType,
    ConstraintWidget target,
    ConstraintAnchorType endType,
    int margin,
    int goneMargin,
  ) {
    final startAnchor = getAnchor(startType)!;
    final endAnchor = target.getAnchor(endType);
    startAnchor.connect(endAnchor, margin, goneMargin, true);
  }

  /// Connect the center of this widget to the center of [target], positioned
  /// on a circle at [angle] (degrees) and [radius].
  void connectCircularConstraint(
    ConstraintWidget target,
    double angle,
    int radius,
  ) {
    immediateConnect(
      ConstraintAnchorType.center,
      target,
      ConstraintAnchorType.center,
      radius,
      0,
    );
    mCircleConstraintAngle = angle;
  }

  /// Determine if the widget is the first element of a chain in a given
  /// orientation.
  bool _isChainHead(int orientation) {
    final offset = orientation * 2;
    return (mListAnchors[offset].mTarget != null &&
            !identical(
              mListAnchors[offset].mTarget!.mTarget,
              mListAnchors[offset],
            )) &&
        (mListAnchors[offset + 1].mTarget != null &&
            identical(
              mListAnchors[offset + 1].mTarget!.mTarget,
              mListAnchors[offset + 1],
            ));
  }

  /// Used to select which widgets should be added to the solver first.
  bool addFirst() => this is VirtualLayout || this is Guideline;

  /// Resolves the dimension ratio parameters.
  void setupDimensionRatio(
    bool hParentWrapContent,
    bool vParentWrapContent,
    bool horizontalDimensionFixed,
    bool verticalDimensionFixed,
  ) {
    if (mResolvedDimensionRatioSide == UNKNOWN) {
      if (horizontalDimensionFixed && !verticalDimensionFixed) {
        mResolvedDimensionRatioSide = HORIZONTAL;
      } else if (!horizontalDimensionFixed && verticalDimensionFixed) {
        mResolvedDimensionRatioSide = VERTICAL;
        if (mDimensionRatioSide == UNKNOWN) {
          // need to reverse the ratio as the parsing is done in horizontal mode
          mResolvedDimensionRatio = 1 / mResolvedDimensionRatio;
        }
      }
    }

    if (mResolvedDimensionRatioSide == HORIZONTAL &&
        !(mTop.isConnected() && mBottom.isConnected())) {
      mResolvedDimensionRatioSide = VERTICAL;
    } else if (mResolvedDimensionRatioSide == VERTICAL &&
        !(mLeft.isConnected() && mRight.isConnected())) {
      mResolvedDimensionRatioSide = HORIZONTAL;
    }

    // if dimension is still unknown... check parentWrap
    if (mResolvedDimensionRatioSide == UNKNOWN) {
      if (!(mTop.isConnected() &&
          mBottom.isConnected() &&
          mLeft.isConnected() &&
          mRight.isConnected())) {
        // only do that if not all connections are set
        if (mTop.isConnected() && mBottom.isConnected()) {
          mResolvedDimensionRatioSide = HORIZONTAL;
        } else if (mLeft.isConnected() && mRight.isConnected()) {
          mResolvedDimensionRatio = 1 / mResolvedDimensionRatio;
          mResolvedDimensionRatioSide = VERTICAL;
        }
      }
    }

    if (mResolvedDimensionRatioSide == UNKNOWN) {
      if (mMatchConstraintMinWidth > 0 && mMatchConstraintMinHeight == 0) {
        mResolvedDimensionRatioSide = HORIZONTAL;
      } else if (mMatchConstraintMinWidth == 0 &&
          mMatchConstraintMinHeight > 0) {
        mResolvedDimensionRatio = 1 / mResolvedDimensionRatio;
        mResolvedDimensionRatioSide = VERTICAL;
      }
    }
  }

  /// Add this widget to the solver. [optimize] is true when
  /// Optimizer.OPTIMIZATION_GRAPH is on.
  void addToSolver(LinearSystem system, bool optimize) {
    final left = system.createObjectVariable(mLeft);
    final right = system.createObjectVariable(mRight);
    final top = system.createObjectVariable(mTop);
    final bottom = system.createObjectVariable(mBottom);
    final baseline = system.createObjectVariable(mBaseline);

    var horizontalParentWrapContent = false;
    var verticalParentWrapContent = false;
    if (mParent != null) {
      horizontalParentWrapContent =
          mParent!.mListDimensionBehaviors[HORIZONTAL] ==
          DimensionBehaviour.wrapContent;
      verticalParentWrapContent =
          mParent!.mListDimensionBehaviors[VERTICAL] ==
          DimensionBehaviour.wrapContent;

      switch (mWrapBehaviorInParent) {
        case WRAP_BEHAVIOR_SKIPPED:
          horizontalParentWrapContent = false;
          verticalParentWrapContent = false;
        case WRAP_BEHAVIOR_HORIZONTAL_ONLY:
          verticalParentWrapContent = false;
        case WRAP_BEHAVIOR_VERTICAL_ONLY:
          horizontalParentWrapContent = false;
      }
    }

    if (!(mVisibility != GONE ||
        mAnimated ||
        hasDependencies() ||
        mIsInBarrier[HORIZONTAL] ||
        mIsInBarrier[VERTICAL])) {
      return;
    }

    if (mResolvedHorizontal || mResolvedVertical) {
      // For now apply all, but that won't work for wrap/wrap layouts.
      if (mResolvedHorizontal) {
        system.addEqualityConstant(left!, mX);
        system.addEqualityConstant(right!, mX + mWidth);
        if (horizontalParentWrapContent && mParent != null) {
          if (_optimizeWrapOnResolved) {
            final container = mParent! as ConstraintWidgetContainer;
            container.addHorizontalWrapMinVariable(mLeft);
            container.addHorizontalWrapMaxVariable(mRight);
          } else {
            const wrapStrength = SolverVariable.STRENGTH_EQUALITY;
            system.addGreaterThan(
              system.createObjectVariable(mParent!.mRight)!,
              right,
              0,
              wrapStrength,
            );
          }
        }
      }
      if (mResolvedVertical) {
        system.addEqualityConstant(top!, mY);
        system.addEqualityConstant(bottom!, mY + mHeight);
        if (mBaseline.hasDependents()) {
          system.addEqualityConstant(baseline!, mY + mBaselineDistance);
        }
        if (verticalParentWrapContent && mParent != null) {
          if (_optimizeWrapOnResolved) {
            final container = mParent! as ConstraintWidgetContainer;
            container.addVerticalWrapMinVariable(mTop);
            container.addVerticalWrapMaxVariable(mBottom);
          } else {
            const wrapStrength = SolverVariable.STRENGTH_EQUALITY;
            system.addGreaterThan(
              system.createObjectVariable(mParent!.mBottom)!,
              bottom,
              0,
              wrapStrength,
            );
          }
        }
      }
      if (mResolvedHorizontal && mResolvedVertical) {
        mResolvedHorizontal = false;
        mResolvedVertical = false;
        return;
      }
    }

    if (optimize &&
        mHorizontalRun != null &&
        mVerticalRun != null &&
        mHorizontalRun!.start.resolved &&
        mHorizontalRun!.end.resolved &&
        mVerticalRun!.start.resolved &&
        mVerticalRun!.end.resolved) {
      system.addEqualityConstant(left!, mHorizontalRun!.start.value);
      system.addEqualityConstant(right!, mHorizontalRun!.end.value);
      system.addEqualityConstant(top!, mVerticalRun!.start.value);
      system.addEqualityConstant(bottom!, mVerticalRun!.end.value);
      system.addEqualityConstant(baseline!, mVerticalRun!.baseline.value);
      if (mParent != null) {
        if (horizontalParentWrapContent &&
            isTerminalWidget[HORIZONTAL] &&
            !isInHorizontalChain()) {
          final parentMax = system.createObjectVariable(mParent!.mRight)!;
          system.addGreaterThan(
            parentMax,
            right,
            0,
            SolverVariable.STRENGTH_FIXED,
          );
        }
        if (verticalParentWrapContent &&
            isTerminalWidget[VERTICAL] &&
            !isInVerticalChain()) {
          final parentMax = system.createObjectVariable(mParent!.mBottom)!;
          system.addGreaterThan(
            parentMax,
            bottom,
            0,
            SolverVariable.STRENGTH_FIXED,
          );
        }
      }
      mResolvedHorizontal = false;
      mResolvedVertical = false;
      return; // we are done here
    }

    var inHorizontalChain = false;
    var inVerticalChain = false;

    if (mParent != null) {
      // Add this widget to a horizontal chain if it is the Head of it.
      if (_isChainHead(HORIZONTAL)) {
        (mParent! as ConstraintWidgetContainer).addChain(this, HORIZONTAL);
        inHorizontalChain = true;
      } else {
        inHorizontalChain = isInHorizontalChain();
      }

      // Add this widget to a vertical chain if it is the Head of it.
      if (_isChainHead(VERTICAL)) {
        (mParent! as ConstraintWidgetContainer).addChain(this, VERTICAL);
        inVerticalChain = true;
      } else {
        inVerticalChain = isInVerticalChain();
      }

      if (!inHorizontalChain &&
          horizontalParentWrapContent &&
          mVisibility != GONE &&
          mLeft.mTarget == null &&
          mRight.mTarget == null) {
        final parentRight = system.createObjectVariable(mParent!.mRight)!;
        system.addGreaterThan(
          parentRight,
          right!,
          0,
          SolverVariable.STRENGTH_LOW,
        );
      }

      // Upstream also guards this on `mBaseline == null`, which can never
      // hold (mBaseline is a non-null field), so the branch is dead there
      // and omitted here:
      // if (!inVerticalChain && verticalParentWrapContent && ...)
    }

    var width = mWidth;
    if (width < mMinWidth) {
      width = mMinWidth;
    }
    var height = mHeight;
    if (height < mMinHeight) {
      height = mMinHeight;
    }

    // Dimensions can be either fixed (a given value)
    // or dependent on the solver if set to MATCH_CONSTRAINT
    final horizontalDimensionFixed =
        mListDimensionBehaviors[HORIZONTAL] !=
        DimensionBehaviour.matchConstraint;
    final verticalDimensionFixed =
        mListDimensionBehaviors[VERTICAL] != DimensionBehaviour.matchConstraint;

    // We evaluate the dimension ratio here as the connections can change.
    var useRatio = false;
    mResolvedDimensionRatioSide = mDimensionRatioSide;
    mResolvedDimensionRatio = mDimensionRatio;

    var matchConstraintDefaultWidth = mMatchConstraintDefaultWidth;
    var matchConstraintDefaultHeight = mMatchConstraintDefaultHeight;

    if (mDimensionRatio > 0 && mVisibility != GONE) {
      useRatio = true;
      if (mListDimensionBehaviors[HORIZONTAL] ==
              DimensionBehaviour.matchConstraint &&
          matchConstraintDefaultWidth == MATCH_CONSTRAINT_SPREAD) {
        matchConstraintDefaultWidth = MATCH_CONSTRAINT_RATIO;
      }
      if (mListDimensionBehaviors[VERTICAL] ==
              DimensionBehaviour.matchConstraint &&
          matchConstraintDefaultHeight == MATCH_CONSTRAINT_SPREAD) {
        matchConstraintDefaultHeight = MATCH_CONSTRAINT_RATIO;
      }

      if (mListDimensionBehaviors[HORIZONTAL] ==
              DimensionBehaviour.matchConstraint &&
          mListDimensionBehaviors[VERTICAL] ==
              DimensionBehaviour.matchConstraint &&
          matchConstraintDefaultWidth == MATCH_CONSTRAINT_RATIO &&
          matchConstraintDefaultHeight == MATCH_CONSTRAINT_RATIO) {
        setupDimensionRatio(
          horizontalParentWrapContent,
          verticalParentWrapContent,
          horizontalDimensionFixed,
          verticalDimensionFixed,
        );
      } else if (mListDimensionBehaviors[HORIZONTAL] ==
              DimensionBehaviour.matchConstraint &&
          matchConstraintDefaultWidth == MATCH_CONSTRAINT_RATIO) {
        mResolvedDimensionRatioSide = HORIZONTAL;
        width = (mResolvedDimensionRatio * mHeight).toInt();
        if (mListDimensionBehaviors[VERTICAL] !=
            DimensionBehaviour.matchConstraint) {
          matchConstraintDefaultWidth = MATCH_CONSTRAINT_RATIO_RESOLVED;
          useRatio = false;
        }
      } else if (mListDimensionBehaviors[VERTICAL] ==
              DimensionBehaviour.matchConstraint &&
          matchConstraintDefaultHeight == MATCH_CONSTRAINT_RATIO) {
        mResolvedDimensionRatioSide = VERTICAL;
        if (mDimensionRatioSide == UNKNOWN) {
          // need to reverse the ratio as the parsing is done in horizontal mode
          mResolvedDimensionRatio = 1 / mResolvedDimensionRatio;
        }
        height = (mResolvedDimensionRatio * mWidth).toInt();
        if (mListDimensionBehaviors[HORIZONTAL] !=
            DimensionBehaviour.matchConstraint) {
          matchConstraintDefaultHeight = MATCH_CONSTRAINT_RATIO_RESOLVED;
          useRatio = false;
        }
      }
    }

    mResolvedMatchConstraintDefault[HORIZONTAL] = matchConstraintDefaultWidth;
    mResolvedMatchConstraintDefault[VERTICAL] = matchConstraintDefaultHeight;
    mResolvedHasRatio = useRatio;

    final useHorizontalRatio =
        useRatio &&
        (mResolvedDimensionRatioSide == HORIZONTAL ||
            mResolvedDimensionRatioSide == UNKNOWN);

    final useVerticalRatio =
        useRatio &&
        (mResolvedDimensionRatioSide == VERTICAL ||
            mResolvedDimensionRatioSide == UNKNOWN);

    // Horizontal resolution
    var wrapContent =
        (mListDimensionBehaviors[HORIZONTAL] ==
            DimensionBehaviour.wrapContent) &&
        (this is ConstraintWidgetContainer);
    if (wrapContent) {
      width = 0;
    }

    var applyPosition = true;
    if (mCenter.isConnected()) {
      applyPosition = false;
    }

    final isInHorizontalBarrier = mIsInBarrier[HORIZONTAL];
    final isInVerticalBarrier = mIsInBarrier[VERTICAL];

    if (mHorizontalResolution != DIRECT && !mResolvedHorizontal) {
      if (!optimize ||
          !(mHorizontalRun != null &&
              mHorizontalRun!.start.resolved &&
              mHorizontalRun!.end.resolved)) {
        final parentMax = mParent != null
            ? system.createObjectVariable(mParent!.mRight)
            : null;
        final parentMin = mParent != null
            ? system.createObjectVariable(mParent!.mLeft)
            : null;
        applyPosition = _applyConstraints(
          system,
          true,
          horizontalParentWrapContent,
          verticalParentWrapContent,
          isTerminalWidget[HORIZONTAL],
          parentMin,
          parentMax,
          mListDimensionBehaviors[HORIZONTAL],
          wrapContent,
          mLeft,
          mRight,
          mX,
          width,
          mMinWidth,
          mMaxDimension[HORIZONTAL],
          mHorizontalBiasPercent,
          useHorizontalRatio,
          mListDimensionBehaviors[VERTICAL] ==
              DimensionBehaviour.matchConstraint,
          inHorizontalChain,
          inVerticalChain,
          isInHorizontalBarrier,
          matchConstraintDefaultWidth,
          matchConstraintDefaultHeight,
          mMatchConstraintMinWidth,
          mMatchConstraintMaxWidth,
          mMatchConstraintPercentWidth,
          applyPosition,
        );
      } else if (optimize) {
        system.addEqualityConstant(left!, mHorizontalRun!.start.value);
        system.addEqualityConstant(right!, mHorizontalRun!.end.value);
        if (mParent != null) {
          if (horizontalParentWrapContent &&
              isTerminalWidget[HORIZONTAL] &&
              !isInHorizontalChain()) {
            final parentMax = system.createObjectVariable(mParent!.mRight)!;
            system.addGreaterThan(
              parentMax,
              right,
              0,
              SolverVariable.STRENGTH_FIXED,
            );
          }
        }
      }
    }

    var applyVerticalConstraints = true;
    if (optimize &&
        mVerticalRun != null &&
        mVerticalRun!.start.resolved &&
        mVerticalRun!.end.resolved) {
      system.addEqualityConstant(top!, mVerticalRun!.start.value);
      system.addEqualityConstant(bottom!, mVerticalRun!.end.value);
      system.addEqualityConstant(baseline!, mVerticalRun!.baseline.value);
      if (mParent != null) {
        if (!inVerticalChain &&
            verticalParentWrapContent &&
            isTerminalWidget[VERTICAL]) {
          final parentMax = system.createObjectVariable(mParent!.mBottom)!;
          system.addGreaterThan(
            parentMax,
            bottom,
            0,
            SolverVariable.STRENGTH_FIXED,
          );
        }
      }
      applyVerticalConstraints = false;
    }
    if (mVerticalResolution == DIRECT) {
      applyVerticalConstraints = false;
    }
    if (applyVerticalConstraints && !mResolvedVertical) {
      // Vertical Resolution
      wrapContent =
          (mListDimensionBehaviors[VERTICAL] ==
              DimensionBehaviour.wrapContent) &&
          (this is ConstraintWidgetContainer);
      if (wrapContent) {
        height = 0;
      }

      final parentMax = mParent != null
          ? system.createObjectVariable(mParent!.mBottom)
          : null;
      final parentMin = mParent != null
          ? system.createObjectVariable(mParent!.mTop)
          : null;

      if (mBaselineDistance > 0 || mVisibility == GONE) {
        // if we are GONE we might still have to deal with baseline,
        // even if our baseline distance would be zero
        if (mBaseline.mTarget != null) {
          system.addEquality(
            baseline!,
            top!,
            getBaselineDistance(),
            SolverVariable.STRENGTH_FIXED,
          );
          final baselineTarget = system.createObjectVariable(
            mBaseline.mTarget,
          )!;
          final baselineMargin = mBaseline.getMargin();
          system.addEquality(
            baseline,
            baselineTarget,
            baselineMargin,
            SolverVariable.STRENGTH_FIXED,
          );
          applyPosition = false;
          if (verticalParentWrapContent) {
            final end = system.createObjectVariable(mBottom)!;
            const wrapStrength = SolverVariable.STRENGTH_EQUALITY;
            system.addGreaterThan(parentMax!, end, 0, wrapStrength);
          }
        } else if (mVisibility == GONE) {
          system.addEquality(
            baseline!,
            top!,
            mBaseline.getMargin(),
            SolverVariable.STRENGTH_FIXED,
          );
        } else {
          system.addEquality(
            baseline!,
            top!,
            getBaselineDistance(),
            SolverVariable.STRENGTH_FIXED,
          );
        }
      }

      _applyConstraints(
        system,
        false,
        verticalParentWrapContent,
        horizontalParentWrapContent,
        isTerminalWidget[VERTICAL],
        parentMin,
        parentMax,
        mListDimensionBehaviors[VERTICAL],
        wrapContent,
        mTop,
        mBottom,
        mY,
        height,
        mMinHeight,
        mMaxDimension[VERTICAL],
        mVerticalBiasPercent,
        useVerticalRatio,
        mListDimensionBehaviors[HORIZONTAL] ==
            DimensionBehaviour.matchConstraint,
        inVerticalChain,
        inHorizontalChain,
        isInVerticalBarrier,
        matchConstraintDefaultHeight,
        matchConstraintDefaultWidth,
        mMatchConstraintMinHeight,
        mMatchConstraintMaxHeight,
        mMatchConstraintPercentHeight,
        applyPosition,
      );
    }

    if (useRatio) {
      const strength = SolverVariable.STRENGTH_FIXED;
      if (mResolvedDimensionRatioSide == VERTICAL) {
        system.addRatio(
          bottom!,
          top!,
          right!,
          left!,
          mResolvedDimensionRatio,
          strength,
        );
      } else {
        system.addRatio(
          right!,
          left!,
          bottom!,
          top!,
          mResolvedDimensionRatio,
          strength,
        );
      }
    }

    if (mCenter.isConnected() && !mCircleConstraintAngle.isNaN) {
      // Upstream does not guard on NaN; the angle is only ever set through
      // connectCircularConstraint, and plain center connects would otherwise
      // inject NaN rows (a path no upstream test exercises).
      system.addCenterPoint(
        this,
        mCenter.mTarget!.mOwner,
        _toRadians(mCircleConstraintAngle + 90),
        mCenter.getMargin(),
      );
    }

    mResolvedHorizontal = false;
    mResolvedVertical = false;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Apply the constraints in the system depending on the existing anchors,
  /// in one dimension. Returns the (possibly updated) applyPosition value for
  /// upstream parity, though upstream mutates a local.
  bool _applyConstraints(
    LinearSystem system,
    bool isHorizontal,
    bool parentWrapContent,
    bool oppositeParentWrapContent,
    bool isTerminal,
    SolverVariable? parentMin,
    SolverVariable? parentMax,
    DimensionBehaviour dimensionBehaviour,
    bool wrapContent,
    ConstraintAnchor beginAnchor,
    ConstraintAnchor endAnchor,
    int beginPosition,
    int dimension,
    int minDimension,
    int maxDimension,
    double bias,
    bool useRatio,
    bool oppositeVariable,
    bool inChain,
    bool oppositeInChain,
    bool inBarrier,
    int matchConstraintDefault,
    int oppositeMatchConstraintDefault,
    int matchMinDimension,
    int matchMaxDimension,
    double matchPercentDimension,
    bool applyPosition,
  ) {
    final begin = system.createObjectVariable(beginAnchor)!;
    final end = system.createObjectVariable(endAnchor)!;
    final beginTarget = system.createObjectVariable(beginAnchor.getTarget());
    final endTarget = system.createObjectVariable(endAnchor.getTarget());

    final isBeginConnected = beginAnchor.isConnected();
    final isEndConnected = endAnchor.isConnected();
    final isCenterConnected = mCenter.isConnected();

    var variableSize = false;

    var numConnections = 0;
    if (isBeginConnected) {
      numConnections++;
    }
    if (isEndConnected) {
      numConnections++;
    }
    if (isCenterConnected) {
      numConnections++;
    }

    if (useRatio) {
      matchConstraintDefault = MATCH_CONSTRAINT_RATIO;
    }
    switch (dimensionBehaviour) {
      case DimensionBehaviour.fixed:
      case DimensionBehaviour.wrapContent:
      case DimensionBehaviour.matchParent:
        variableSize = false;
      case DimensionBehaviour.matchConstraint:
        variableSize =
            matchConstraintDefault != MATCH_CONSTRAINT_RATIO_RESOLVED;
    }

    if (mWidthOverride != -1 && isHorizontal) {
      variableSize = false;
      dimension = mWidthOverride;
      mWidthOverride = -1;
    }
    if (mHeightOverride != -1 && !isHorizontal) {
      variableSize = false;
      dimension = mHeightOverride;
      mHeightOverride = -1;
    }

    if (mVisibility == GONE) {
      dimension = 0;
      variableSize = false;
    }

    // First apply starting direct connections (more solver-friendly)
    if (applyPosition) {
      if (!isBeginConnected && !isEndConnected && !isCenterConnected) {
        system.addEqualityConstant(begin, beginPosition);
      } else if (isBeginConnected && !isEndConnected) {
        system.addEquality(
          begin,
          beginTarget!,
          beginAnchor.getMargin(),
          SolverVariable.STRENGTH_FIXED,
        );
      }
    }

    // Then apply the dimension
    if (!variableSize) {
      if (wrapContent) {
        system.addEquality(end, begin, 0, SolverVariable.STRENGTH_HIGH);
        if (minDimension > 0) {
          system.addGreaterThan(
            end,
            begin,
            minDimension,
            SolverVariable.STRENGTH_FIXED,
          );
        }
        if (maxDimension < intMaxValue) {
          system.addLowerThan(
            end,
            begin,
            maxDimension,
            SolverVariable.STRENGTH_FIXED,
          );
        }
      } else {
        system.addEquality(
          end,
          begin,
          dimension,
          SolverVariable.STRENGTH_FIXED,
        );
      }
    } else {
      if (numConnections != 2 &&
          !useRatio &&
          ((matchConstraintDefault == MATCH_CONSTRAINT_WRAP) ||
              (matchConstraintDefault == MATCH_CONSTRAINT_SPREAD))) {
        variableSize = false;
        var d = math.max(matchMinDimension, dimension);
        if (matchMaxDimension > 0) {
          d = math.min(matchMaxDimension, d);
        }
        system.addEquality(end, begin, d, SolverVariable.STRENGTH_FIXED);
      } else {
        if (matchMinDimension == _WRAP) {
          matchMinDimension = dimension;
        }
        if (matchMaxDimension == _WRAP) {
          matchMaxDimension = dimension;
        }
        if (dimension > 0 && matchConstraintDefault != MATCH_CONSTRAINT_WRAP) {
          if (_USE_WRAP_DIMENSION_FOR_SPREAD &&
              (matchConstraintDefault == MATCH_CONSTRAINT_SPREAD)) {
            system.addGreaterThan(
              end,
              begin,
              dimension,
              SolverVariable.STRENGTH_HIGHEST,
            );
          }
          dimension = 0;
        }

        if (matchMinDimension > 0) {
          system.addGreaterThan(
            end,
            begin,
            matchMinDimension,
            SolverVariable.STRENGTH_FIXED,
          );
          dimension = math.max(dimension, matchMinDimension);
        }
        if (matchMaxDimension > 0) {
          var applyLimit = true;
          if (parentWrapContent &&
              matchConstraintDefault == MATCH_CONSTRAINT_WRAP) {
            applyLimit = false;
          }
          if (applyLimit) {
            system.addLowerThan(
              end,
              begin,
              matchMaxDimension,
              SolverVariable.STRENGTH_FIXED,
            );
          }
          dimension = math.min(dimension, matchMaxDimension);
        }
        if (matchConstraintDefault == MATCH_CONSTRAINT_WRAP) {
          if (parentWrapContent) {
            system.addEquality(
              end,
              begin,
              dimension,
              SolverVariable.STRENGTH_FIXED,
            );
          } else if (inChain) {
            system.addEquality(
              end,
              begin,
              dimension,
              SolverVariable.STRENGTH_EQUALITY,
            );
            system.addLowerThan(
              end,
              begin,
              dimension,
              SolverVariable.STRENGTH_FIXED,
            );
          } else {
            system.addEquality(
              end,
              begin,
              dimension,
              SolverVariable.STRENGTH_EQUALITY,
            );
            system.addLowerThan(
              end,
              begin,
              dimension,
              SolverVariable.STRENGTH_FIXED,
            );
          }
        } else if (matchConstraintDefault == MATCH_CONSTRAINT_PERCENT) {
          SolverVariable? percentBegin;
          SolverVariable? percentEnd;
          if (beginAnchor.getType() == ConstraintAnchorType.top ||
              beginAnchor.getType() == ConstraintAnchorType.bottom) {
            // vertical
            percentBegin = system.createObjectVariable(
              mParent!.getAnchor(ConstraintAnchorType.top),
            );
            percentEnd = system.createObjectVariable(
              mParent!.getAnchor(ConstraintAnchorType.bottom),
            );
          } else {
            percentBegin = system.createObjectVariable(
              mParent!.getAnchor(ConstraintAnchorType.left),
            );
            percentEnd = system.createObjectVariable(
              mParent!.getAnchor(ConstraintAnchorType.right),
            );
          }
          system.addConstraint(
            system.createRow().createRowDimensionRatio(
              end,
              begin,
              percentEnd!,
              percentBegin!,
              matchPercentDimension,
            ),
          );
          if (parentWrapContent) {
            variableSize = false;
          }
        } else {
          isTerminal = true;
        }
      }
    }

    if (!applyPosition || inChain) {
      // If we don't need to apply the position, let's finish now.
      if (numConnections < 2 && parentWrapContent && isTerminal) {
        system.addGreaterThan(
          begin,
          parentMin!,
          0,
          SolverVariable.STRENGTH_FIXED,
        );
        var applyEnd = isHorizontal || (mBaseline.mTarget == null);
        if (!isHorizontal && mBaseline.mTarget != null) {
          // generally we wouldn't take the current widget in the wrap content,
          // but if the connected element is a ratio widget, then we can
          // contribute (as the ratio widget may not be enough by itself) to it.
          final target = mBaseline.mTarget!.mOwner;
          if (target.mDimensionRatio != 0 &&
              target.mListDimensionBehaviors[0] ==
                  DimensionBehaviour.matchConstraint &&
              target.mListDimensionBehaviors[1] ==
                  DimensionBehaviour.matchConstraint) {
            applyEnd = true;
          } else {
            applyEnd = false;
          }
        }
        if (applyEnd) {
          system.addGreaterThan(
            parentMax!,
            end,
            0,
            SolverVariable.STRENGTH_FIXED,
          );
        }
      }
      return applyPosition;
    }

    // Ok, we are dealing with single or centered constraints, let's apply them

    var wrapStrength = SolverVariable.STRENGTH_EQUALITY;

    if (!isBeginConnected && !isEndConnected && !isCenterConnected) {
      // note we already applied the start position before, no need to redo it
    } else if (isBeginConnected && !isEndConnected) {
      // note we already applied the start position before, no need to redo it

      // If we are constrained to a barrier, make sure that
      // we are not bypassed in the wrap
      final beginWidget = beginAnchor.mTarget!.mOwner;
      if (parentWrapContent && beginWidget is Barrier) {
        wrapStrength = SolverVariable.STRENGTH_FIXED;
      }
    } else if (!isBeginConnected && isEndConnected) {
      system.addEquality(
        end,
        endTarget!,
        -endAnchor.getMargin(),
        SolverVariable.STRENGTH_FIXED,
      );
      if (parentWrapContent) {
        if (_optimizeWrapO && begin.isFinalValue && mParent != null) {
          final container = mParent! as ConstraintWidgetContainer;
          if (isHorizontal) {
            container.addHorizontalWrapMinVariable(beginAnchor);
          } else {
            container.addVerticalWrapMinVariable(beginAnchor);
          }
        } else {
          system.addGreaterThan(
            begin,
            parentMin!,
            0,
            SolverVariable.STRENGTH_EQUALITY,
          );
        }
      }
    } else if (isBeginConnected && isEndConnected) {
      var applyBoundsCheck = true;
      var applyCentering = false;
      var applyStrongChecks = false;
      var applyRangeCheck = false;
      var rangeCheckStrength = SolverVariable.STRENGTH_EQUALITY;

      var boundsCheckStrength = SolverVariable.STRENGTH_HIGHEST;
      var centeringStrength = SolverVariable.STRENGTH_BARRIER;

      if (parentWrapContent) {
        rangeCheckStrength = SolverVariable.STRENGTH_EQUALITY;
      }
      final beginWidget = beginAnchor.mTarget!.mOwner;
      final endWidget = endAnchor.mTarget!.mOwner;
      final parent = getParent();

      if (variableSize) {
        if (matchConstraintDefault == MATCH_CONSTRAINT_SPREAD) {
          if (matchMaxDimension == 0 && matchMinDimension == 0) {
            applyStrongChecks = true;
            rangeCheckStrength = SolverVariable.STRENGTH_FIXED;
            boundsCheckStrength = SolverVariable.STRENGTH_FIXED;
            // Optimization in case of centering in parent
            if (beginTarget!.isFinalValue && endTarget!.isFinalValue) {
              system.addEquality(
                begin,
                beginTarget,
                beginAnchor.getMargin(),
                SolverVariable.STRENGTH_FIXED,
              );
              system.addEquality(
                end,
                endTarget,
                -endAnchor.getMargin(),
                SolverVariable.STRENGTH_FIXED,
              );
              return applyPosition;
            }
          } else {
            applyCentering = true;
            rangeCheckStrength = SolverVariable.STRENGTH_EQUALITY;
            boundsCheckStrength = SolverVariable.STRENGTH_EQUALITY;
            applyBoundsCheck = true;
            applyRangeCheck = true;
          }
          if (beginWidget is Barrier || endWidget is Barrier) {
            boundsCheckStrength = SolverVariable.STRENGTH_HIGHEST;
          }
        } else if (matchConstraintDefault == MATCH_CONSTRAINT_PERCENT) {
          applyCentering = true;
          rangeCheckStrength = SolverVariable.STRENGTH_EQUALITY;
          boundsCheckStrength = SolverVariable.STRENGTH_EQUALITY;
          applyBoundsCheck = true;
          applyRangeCheck = true;
          if (beginWidget is Barrier || endWidget is Barrier) {
            boundsCheckStrength = SolverVariable.STRENGTH_HIGHEST;
          }
        } else if (matchConstraintDefault == MATCH_CONSTRAINT_WRAP) {
          applyCentering = true;
          applyRangeCheck = true;
          rangeCheckStrength = SolverVariable.STRENGTH_FIXED;
        } else if (matchConstraintDefault == MATCH_CONSTRAINT_RATIO) {
          if (mResolvedDimensionRatioSide == UNKNOWN) {
            applyCentering = true;
            applyRangeCheck = true;
            applyStrongChecks = true;
            rangeCheckStrength = SolverVariable.STRENGTH_FIXED;
            boundsCheckStrength = SolverVariable.STRENGTH_EQUALITY;
            if (oppositeInChain) {
              boundsCheckStrength = SolverVariable.STRENGTH_EQUALITY;
              centeringStrength = SolverVariable.STRENGTH_HIGHEST;
              if (parentWrapContent) {
                centeringStrength = SolverVariable.STRENGTH_EQUALITY;
              }
            } else {
              centeringStrength = SolverVariable.STRENGTH_FIXED;
            }
          } else {
            applyCentering = true;
            applyRangeCheck = true;
            applyStrongChecks = true;
            if (useRatio) {
              // useRatio is true if the side we base ourselves on for the
              // ratio is this one; if that's not the case, we need to have a
              // stronger constraint.
              final otherSideInvariable =
                  oppositeMatchConstraintDefault == MATCH_CONSTRAINT_PERCENT ||
                  oppositeMatchConstraintDefault == MATCH_CONSTRAINT_WRAP;
              if (!otherSideInvariable) {
                rangeCheckStrength = SolverVariable.STRENGTH_FIXED;
                boundsCheckStrength = SolverVariable.STRENGTH_EQUALITY;
              }
            } else {
              rangeCheckStrength = SolverVariable.STRENGTH_EQUALITY;
              if (matchMaxDimension > 0) {
                boundsCheckStrength = SolverVariable.STRENGTH_EQUALITY;
              } else if (matchMaxDimension == 0 && matchMinDimension == 0) {
                if (!oppositeInChain) {
                  boundsCheckStrength = SolverVariable.STRENGTH_FIXED;
                } else {
                  if (!identical(beginWidget, parent) &&
                      !identical(endWidget, parent)) {
                    rangeCheckStrength = SolverVariable.STRENGTH_HIGHEST;
                  } else {
                    rangeCheckStrength = SolverVariable.STRENGTH_EQUALITY;
                  }
                  boundsCheckStrength = SolverVariable.STRENGTH_HIGHEST;
                }
              }
            }
          }
        }
      } else {
        applyCentering = true;
        applyRangeCheck = true;

        // Let's optimize away if we can...
        if (beginTarget!.isFinalValue && endTarget!.isFinalValue) {
          system.addCentering(
            begin,
            beginTarget,
            beginAnchor.getMargin(),
            bias,
            endTarget,
            end,
            endAnchor.getMargin(),
            SolverVariable.STRENGTH_FIXED,
          );
          if (parentWrapContent && isTerminal) {
            var margin = 0;
            if (endAnchor.mTarget != null) {
              margin = endAnchor.getMargin();
            }
            if (!identical(endTarget, parentMax)) {
              // if not already applied
              system.addGreaterThan(parentMax!, end, margin, wrapStrength);
            }
          }
          return applyPosition;
        }
      }

      if (applyRangeCheck &&
          identical(beginTarget, endTarget) &&
          !identical(beginWidget, parent)) {
        // no need to apply range / bounds check if we are centered on the
        // same anchor
        applyRangeCheck = false;
        applyBoundsCheck = false;
      }

      if (applyCentering) {
        if (!variableSize &&
            !oppositeVariable &&
            !oppositeInChain &&
            identical(beginTarget, parentMin) &&
            identical(endTarget, parentMax)) {
          // for fixed size widgets, we can simplify the constraints
          centeringStrength = SolverVariable.STRENGTH_FIXED;
          rangeCheckStrength = SolverVariable.STRENGTH_FIXED;
          applyBoundsCheck = false;
          parentWrapContent = false;
        }

        system.addCentering(
          begin,
          beginTarget!,
          beginAnchor.getMargin(),
          bias,
          endTarget!,
          end,
          endAnchor.getMargin(),
          centeringStrength,
        );
      }

      if (mVisibility == GONE && !endAnchor.hasDependents()) {
        return applyPosition;
      }

      if (applyRangeCheck) {
        if (parentWrapContent &&
            !identical(beginTarget, endTarget) &&
            !variableSize) {
          if (beginWidget is Barrier || endWidget is Barrier) {
            rangeCheckStrength = SolverVariable.STRENGTH_BARRIER;
          }
        }
        system.addGreaterThan(
          begin,
          beginTarget!,
          beginAnchor.getMargin(),
          rangeCheckStrength,
        );
        system.addLowerThan(
          end,
          endTarget!,
          -endAnchor.getMargin(),
          rangeCheckStrength,
        );
      }

      if (parentWrapContent &&
          inBarrier // if we are referenced by a barrier
          &&
          !(beginWidget is Barrier || endWidget is Barrier) &&
          !identical(endWidget, parent)) {
        // ... but not directly constrained by it
        // ... then make sure we can hold our own
        boundsCheckStrength = SolverVariable.STRENGTH_BARRIER;
        rangeCheckStrength = SolverVariable.STRENGTH_BARRIER;
        applyBoundsCheck = true;
      }

      if (applyBoundsCheck) {
        if (applyStrongChecks &&
            (!oppositeInChain || oppositeParentWrapContent)) {
          var strength = boundsCheckStrength;
          if (identical(beginWidget, parent) || identical(endWidget, parent)) {
            strength = SolverVariable.STRENGTH_BARRIER;
          }
          if (beginWidget is Guideline || endWidget is Guideline) {
            strength = SolverVariable.STRENGTH_EQUALITY;
          }
          if (beginWidget is Barrier || endWidget is Barrier) {
            strength = SolverVariable.STRENGTH_EQUALITY;
          }
          if (oppositeInChain) {
            strength = SolverVariable.STRENGTH_EQUALITY;
          }
          boundsCheckStrength = math.max(strength, boundsCheckStrength);
        }

        if (parentWrapContent) {
          boundsCheckStrength = math.min(
            rangeCheckStrength,
            boundsCheckStrength,
          );
          if (useRatio &&
              !oppositeInChain &&
              (identical(beginWidget, parent) ||
                  identical(endWidget, parent))) {
            // When using ratio, relax some strength to allow other parts of
            // the system to take precedence rather than driving it
            boundsCheckStrength = SolverVariable.STRENGTH_HIGHEST;
          }
        }
        system.addEquality(
          begin,
          beginTarget!,
          beginAnchor.getMargin(),
          boundsCheckStrength,
        );
        system.addEquality(
          end,
          endTarget!,
          -endAnchor.getMargin(),
          boundsCheckStrength,
        );
      }

      if (parentWrapContent) {
        var margin = 0;
        if (identical(parentMin, beginTarget)) {
          margin = beginAnchor.getMargin();
        }
        if (!identical(beginTarget, parentMin)) {
          // already done otherwise
          system.addGreaterThan(begin, parentMin!, margin, wrapStrength);
        }
      }

      if (parentWrapContent &&
          variableSize &&
          minDimension == 0 &&
          matchMinDimension == 0) {
        if (variableSize && matchConstraintDefault == MATCH_CONSTRAINT_RATIO) {
          system.addGreaterThan(end, begin, 0, SolverVariable.STRENGTH_FIXED);
        } else {
          system.addGreaterThan(end, begin, 0, wrapStrength);
        }
      }
    }

    if (parentWrapContent && isTerminal) {
      var margin = 0;
      if (endAnchor.mTarget != null) {
        margin = endAnchor.getMargin();
      }
      if (!identical(endTarget, parentMax)) {
        // if not already applied
        if (_optimizeWrapO && end.isFinalValue && mParent != null) {
          final container = mParent! as ConstraintWidgetContainer;
          if (isHorizontal) {
            container.addHorizontalWrapMaxVariable(endAnchor);
          } else {
            container.addVerticalWrapMaxVariable(endAnchor);
          }
          return applyPosition;
        }
        system.addGreaterThan(parentMax!, end, margin, wrapStrength);
      }
    }
    return applyPosition;
  }

  /// Update the widget from the values generated by the solver.
  void updateFromSolver(LinearSystem system, bool optimize) {
    var left = system.getObjectVariableValue(mLeft);
    var top = system.getObjectVariableValue(mTop);
    var right = system.getObjectVariableValue(mRight);
    var bottom = system.getObjectVariableValue(mBottom);

    if (optimize &&
        mHorizontalRun != null &&
        mHorizontalRun!.start.resolved &&
        mHorizontalRun!.end.resolved) {
      left = mHorizontalRun!.start.value;
      right = mHorizontalRun!.end.value;
    }
    if (optimize &&
        mVerticalRun != null &&
        mVerticalRun!.start.resolved &&
        mVerticalRun!.end.resolved) {
      top = mVerticalRun!.start.value;
      bottom = mVerticalRun!.end.value;
    }

    final w = right - left;
    final h = bottom - top;
    if (w < 0 ||
        h < 0 ||
        left == intMinValue ||
        left == intMaxValue ||
        top == intMinValue ||
        top == intMaxValue ||
        right == intMinValue ||
        right == intMaxValue ||
        bottom == intMinValue ||
        bottom == intMaxValue) {
      left = 0;
      top = 0;
      right = 0;
      bottom = 0;
    }
    setFrame(left, top, right, bottom);
  }

  @override
  String toString() =>
      '${mTypeName != null ? "type: $mTypeName " : ""}'
      '${mDebugName != null ? "id: $mDebugName " : ""}'
      '($mX, $mY) - ($mWidth x $mHeight)';
}
