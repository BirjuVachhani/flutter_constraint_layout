// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.Flow
// (upstream pinned in UPSTREAM.md).

import 'analyzer/basic_measure.dart';
import 'constraint_anchor.dart';
import 'constraint_widget.dart';
import 'constraint_widget_container.dart';
import 'linear_system.dart';
import 'virtual_layout.dart';

/// Implements the Flow virtual layout.
///
/// A flow arranges the widgets added to it in a row (or in a column, see
/// [setOrientation]) like a chain, and can wrap them onto more rows or
/// columns ([setWrapMode]). Gone widgets are left out. Like every
/// [VirtualLayout], it needs a [Measurer] that calls [measure].
class Flow extends VirtualLayout {
  /// Horizontal alignment that lines up the widgets of a column on their
  /// start edge (left, or right in a right-to-left layout).
  static const int HORIZONTAL_ALIGN_START = 0;

  /// Horizontal alignment that lines up the widgets of a column on their end
  /// edge (right, or left in a right-to-left layout).
  static const int HORIZONTAL_ALIGN_END = 1;

  /// Horizontal alignment that centers the widgets of a column. The default.
  static const int HORIZONTAL_ALIGN_CENTER = 2;

  /// Vertical alignment that lines up the widgets of a row on their top
  /// edges.
  static const int VERTICAL_ALIGN_TOP = 0;

  /// Vertical alignment that lines up the widgets of a row on their bottom
  /// edges.
  static const int VERTICAL_ALIGN_BOTTOM = 1;

  /// Vertical alignment that centers the widgets of a row. The default.
  static const int VERTICAL_ALIGN_CENTER = 2;

  /// Vertical alignment that lines up the widgets of a row on their
  /// baselines.
  static const int VERTICAL_ALIGN_BASELINE = 3;

  /// Wrap mode that keeps every widget in a single row or column (one
  /// chain), whether or not they fit. The default.
  static const int WRAP_NONE = 0;

  /// Wrap mode that starts a new row or column, each its own chain, when the
  /// next widget does not fit or after [setMaxElementsWrap] widgets.
  static const int WRAP_CHAIN = 1;

  /// Wrap mode that wraps like [WRAP_CHAIN] but lines the widgets up in rows
  /// and columns, like a table.
  static const int WRAP_ALIGNED = 2;

  /// Wrap mode like [WRAP_CHAIN], measured with upstream's newer chain-wrap
  /// pass.
  static const int WRAP_CHAIN_NEW = 3;

  int _horizontalStyle = ConstraintWidget.UNKNOWN;
  int _verticalStyle = ConstraintWidget.UNKNOWN;
  int _firstHorizontalStyle = ConstraintWidget.UNKNOWN;
  int _firstVerticalStyle = ConstraintWidget.UNKNOWN;
  int _lastHorizontalStyle = ConstraintWidget.UNKNOWN;
  int _lastVerticalStyle = ConstraintWidget.UNKNOWN;

  double _horizontalBias = 0.5;
  double _verticalBias = 0.5;
  double _firstHorizontalBias = 0.5;
  double _firstVerticalBias = 0.5;
  double _lastHorizontalBias = 0.5;
  double _lastVerticalBias = 0.5;

  int _horizontalGap = 0;
  int _verticalGap = 0;

  int _horizontalAlign = HORIZONTAL_ALIGN_CENTER;
  int _verticalAlign = VERTICAL_ALIGN_CENTER;
  int _wrapMode = WRAP_NONE;

  int _maxElementsWrap = ConstraintWidget.UNKNOWN;

  int _orientation = ConstraintWidget.HORIZONTAL;

  final List<_WidgetsList> _chainList = <_WidgetsList>[];

  // Aligned management

  List<ConstraintWidget?>? _alignedBiggestElementsInRows;
  List<ConstraintWidget?>? _alignedBiggestElementsInCols;
  List<int>? _alignedDimensions;
  List<ConstraintWidget?> _displayedWidgets = const <ConstraintWidget?>[];
  int _displayedWidgetsCount = 0;

  // ---- accessors ----

  /// Set the orientation of the layout: rows for
  /// [ConstraintWidget.HORIZONTAL] (the default), columns for
  /// [ConstraintWidget.VERTICAL].
  void setOrientation(int value) => _orientation = value;

  /// Similar to [setHorizontalStyle], but only applies to the first row.
  void setFirstHorizontalStyle(int value) => _firstHorizontalStyle = value;

  /// Similar to [setVerticalStyle], but only applies to the first column.
  void setFirstVerticalStyle(int value) => _firstVerticalStyle = value;

  /// Similar to [setHorizontalStyle], but only applies to the last row.
  void setLastHorizontalStyle(int value) => _lastHorizontalStyle = value;

  /// Similar to [setVerticalStyle], but only applies to the last column.
  void setLastVerticalStyle(int value) => _lastVerticalStyle = value;

  /// Set the horizontal chain style: [ConstraintWidget.CHAIN_SPREAD] (the
  /// default), [ConstraintWidget.CHAIN_SPREAD_INSIDE], or
  /// [ConstraintWidget.CHAIN_PACKED]. It applies to each row, and to the
  /// chain of columns.
  void setHorizontalStyle(int value) => _horizontalStyle = value;

  /// Set the vertical chain style: [ConstraintWidget.CHAIN_SPREAD] (the
  /// default), [ConstraintWidget.CHAIN_SPREAD_INSIDE], or
  /// [ConstraintWidget.CHAIN_PACKED]. It applies to each column, and to the
  /// chain of rows.
  void setVerticalStyle(int value) => _verticalStyle = value;

  /// Set the horizontal bias (0 to 1, 0.5 by default) of each row's chain,
  /// and of the chain of columns in [WRAP_ALIGNED] mode. It is mirrored in a
  /// right-to-left layout.
  void setHorizontalBias(double value) => _horizontalBias = value;

  /// Set the vertical bias (0 to 1, 0.5 by default) of each column's chain,
  /// and of the chain of rows in [WRAP_ALIGNED] mode.
  void setVerticalBias(double value) => _verticalBias = value;

  /// Similar to [setHorizontalBias], but only applies to the first row, and
  /// only when [setFirstHorizontalStyle] is set.
  void setFirstHorizontalBias(double value) => _firstHorizontalBias = value;

  /// Similar to [setVerticalBias], but only applies to the first column, and
  /// only when [setFirstVerticalStyle] is set.
  void setFirstVerticalBias(double value) => _firstVerticalBias = value;

  /// Similar to [setHorizontalBias], but only applies to the last row, and
  /// only when [setLastHorizontalStyle] is set.
  void setLastHorizontalBias(double value) => _lastHorizontalBias = value;

  /// Similar to [setVerticalBias], but only applies to the last column, and
  /// only when [setLastVerticalStyle] is set.
  void setLastVerticalBias(double value) => _lastVerticalBias = value;

  /// Set how the widgets of a column line up horizontally (in a vertical
  /// flow): [HORIZONTAL_ALIGN_START], [HORIZONTAL_ALIGN_END], or
  /// [HORIZONTAL_ALIGN_CENTER] (the default).
  void setHorizontalAlign(int value) => _horizontalAlign = value;

  /// Set how the widgets of a row line up vertically (in a horizontal flow):
  /// [VERTICAL_ALIGN_TOP], [VERTICAL_ALIGN_BOTTOM], [VERTICAL_ALIGN_CENTER]
  /// (the default), or [VERTICAL_ALIGN_BASELINE].
  void setVerticalAlign(int value) => _verticalAlign = value;

  /// Set the wrap mode: [WRAP_NONE] (the default), [WRAP_CHAIN],
  /// [WRAP_ALIGNED], or [WRAP_CHAIN_NEW].
  void setWrapMode(int value) => _wrapMode = value;

  /// Set the horizontal gap between the widgets of a row, and between
  /// columns.
  void setHorizontalGap(int value) => _horizontalGap = value;

  /// Set the vertical gap between the widgets of a column, and between rows.
  void setVerticalGap(int value) => _verticalGap = value;

  /// Set the maximum number of widgets in a row or column before wrapping,
  /// whether or not more would fit, or [ConstraintWidget.UNKNOWN] (the
  /// default) for no maximum. Only the wrapping modes use it.
  void setMaxElementsWrap(int value) => _maxElementsWrap = value;

  /// The maximum set by [setMaxElementsWrap].
  int getMaxElementsWrap() => _maxElementsWrap;

  // ---- utility methods ----

  int _getWidgetWidth(ConstraintWidget? widget, int max) {
    if (widget == null) {
      return 0;
    }
    if (widget.getHorizontalDimensionBehaviour() ==
        DimensionBehaviour.matchConstraint) {
      if (widget.mMatchConstraintDefaultWidth ==
          ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
        return 0;
      } else if (widget.mMatchConstraintDefaultWidth ==
          ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
        final value = (widget.mMatchConstraintPercentWidth * max).toInt();
        if (value != widget.getWidth()) {
          widget.setMeasureRequested(true);
          measureWidget(
            widget,
            DimensionBehaviour.fixed,
            value,
            widget.getVerticalDimensionBehaviour(),
            widget.getHeight(),
          );
        }
        return value;
      } else if (widget.mMatchConstraintDefaultWidth ==
          ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
        return widget.getWidth();
      } else if (widget.mMatchConstraintDefaultWidth ==
          ConstraintWidget.MATCH_CONSTRAINT_RATIO) {
        return (widget.getHeight() * widget.mDimensionRatio + 0.5).toInt();
      }
    }
    return widget.getWidth();
  }

  int _getWidgetHeight(ConstraintWidget? widget, int max) {
    if (widget == null) {
      return 0;
    }
    if (widget.getVerticalDimensionBehaviour() ==
        DimensionBehaviour.matchConstraint) {
      if (widget.mMatchConstraintDefaultHeight ==
          ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
        return 0;
      } else if (widget.mMatchConstraintDefaultHeight ==
          ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
        final value = (widget.mMatchConstraintPercentHeight * max).toInt();
        if (value != widget.getHeight()) {
          widget.setMeasureRequested(true);
          measureWidget(
            widget,
            widget.getHorizontalDimensionBehaviour(),
            widget.getWidth(),
            DimensionBehaviour.fixed,
            value,
          );
        }
        return value;
      } else if (widget.mMatchConstraintDefaultHeight ==
          ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
        return widget.getHeight();
      } else if (widget.mMatchConstraintDefaultHeight ==
          ConstraintWidget.MATCH_CONSTRAINT_RATIO) {
        return (widget.getWidth() * widget.mDimensionRatio + 0.5).toInt();
      }
    }
    return widget.getHeight();
  }

  // ---- measure ----

  /// Measure the referenced widgets ([measureChildren]), arrange them into
  /// rows or columns as the wrap mode dictates, and size the flow:
  /// [BasicMeasure.EXACTLY] takes the given size, [BasicMeasure.AT_MOST] the
  /// content's size capped at it, and [BasicMeasure.UNSPECIFIED] the
  /// content's size. A flow with widgets but no [Measurer] measures as
  /// 0 x 0.
  @override
  void measure(int widthMode, int widthSize, int heightMode, int heightSize) {
    if (mWidgetsCount > 0 && !measureChildren()) {
      setMeasure(0, 0);
      needsCallbackFromSolver(false);
      return;
    }

    var width = 0;
    var height = 0;
    final paddingLeft = getPaddingLeft();
    final paddingRight = getPaddingRight();
    final paddingTop = getPaddingTop();
    final paddingBottom = getPaddingBottom();

    final measured = [0, 0];
    var max = widthSize - paddingLeft - paddingRight;
    if (_orientation == ConstraintWidget.VERTICAL) {
      max = heightSize - paddingTop - paddingBottom;
    }

    if (_orientation == ConstraintWidget.HORIZONTAL) {
      if (_horizontalStyle == ConstraintWidget.UNKNOWN) {
        _horizontalStyle = ConstraintWidget.CHAIN_SPREAD;
      }
      if (_verticalStyle == ConstraintWidget.UNKNOWN) {
        _verticalStyle = ConstraintWidget.CHAIN_SPREAD;
      }
    } else {
      if (_horizontalStyle == ConstraintWidget.UNKNOWN) {
        _horizontalStyle = ConstraintWidget.CHAIN_SPREAD;
      }
      if (_verticalStyle == ConstraintWidget.UNKNOWN) {
        _verticalStyle = ConstraintWidget.CHAIN_SPREAD;
      }
    }

    var widgets = mWidgets;

    var gone = 0;
    for (var i = 0; i < mWidgetsCount; i++) {
      final widget = mWidgets[i];
      if (widget!.getVisibility() == ConstraintWidget.GONE) {
        gone++;
      }
    }
    var count = mWidgetsCount;
    if (gone > 0) {
      widgets = List<ConstraintWidget?>.filled(mWidgetsCount - gone, null);
      var j = 0;
      for (var i = 0; i < mWidgetsCount; i++) {
        final widget = mWidgets[i];
        if (widget!.getVisibility() != ConstraintWidget.GONE) {
          widgets[j] = widget;
          j++;
        }
      }
      count = j;
    }
    _displayedWidgets = widgets;
    _displayedWidgetsCount = count;
    switch (_wrapMode) {
      case WRAP_ALIGNED:
        _measureAligned(widgets, count, _orientation, max, measured);
        break;
      case WRAP_CHAIN:
        _measureChainWrap(widgets, count, _orientation, max, measured);
        break;
      case WRAP_NONE:
        _measureNoWrap(widgets, count, _orientation, max, measured);
        break;
      case WRAP_CHAIN_NEW:
        _measureChainWrapNew(widgets, count, _orientation, max, measured);
        break;
    }

    width = measured[ConstraintWidget.HORIZONTAL] + paddingLeft + paddingRight;
    height = measured[ConstraintWidget.VERTICAL] + paddingTop + paddingBottom;

    var measuredWidth = 0;
    var measuredHeight = 0;

    if (widthMode == BasicMeasure.EXACTLY) {
      measuredWidth = widthSize;
    } else if (widthMode == BasicMeasure.AT_MOST) {
      measuredWidth = width < widthSize ? width : widthSize;
    } else if (widthMode == BasicMeasure.UNSPECIFIED) {
      measuredWidth = width;
    }

    if (heightMode == BasicMeasure.EXACTLY) {
      measuredHeight = heightSize;
    } else if (heightMode == BasicMeasure.AT_MOST) {
      measuredHeight = height < heightSize ? height : heightSize;
    } else if (heightMode == BasicMeasure.UNSPECIFIED) {
      measuredHeight = height;
    }

    setMeasure(measuredWidth, measuredHeight);
    setWidth(measuredWidth);
    setHeight(measuredHeight);
    needsCallbackFromSolver(mWidgetsCount > 0);
  }

  // ---- measure chain wrap ----

  /// Measure the virtual layout using a list of chains for the children.
  void _measureChainWrap(
    List<ConstraintWidget?> widgets,
    int count,
    int orientation,
    int max,
    List<int> measured,
  ) {
    if (count == 0) {
      return;
    }

    _chainList.clear();
    var list = _WidgetsList(
      this,
      orientation,
      mLeft,
      mTop,
      mRight,
      mBottom,
      max,
    );
    _chainList.add(list);

    var nbMatchConstraintsWidgets = 0;

    if (orientation == ConstraintWidget.HORIZONTAL) {
      var width = 0;
      for (var i = 0; i < count; i++) {
        final widget = widgets[i]!;
        final w = _getWidgetWidth(widget, max);
        if (widget.getHorizontalDimensionBehaviour() ==
            DimensionBehaviour.matchConstraint) {
          nbMatchConstraintsWidgets++;
        }
        var doWrap =
            (width == max || (width + _horizontalGap + w) > max) &&
            list.mBiggest != null;
        if (!doWrap &&
            i > 0 &&
            _maxElementsWrap > 0 &&
            (i % _maxElementsWrap == 0)) {
          doWrap = true;
        }
        if (doWrap) {
          width = w;
          list = _WidgetsList(
            this,
            orientation,
            mLeft,
            mTop,
            mRight,
            mBottom,
            max,
          );
          list.setStartIndex(i);
          _chainList.add(list);
        } else {
          if (i > 0) {
            width += _horizontalGap + w;
          } else {
            width = w;
          }
        }
        list.add(widget);
      }
    } else {
      var height = 0;
      for (var i = 0; i < count; i++) {
        final widget = widgets[i]!;
        final h = _getWidgetHeight(widget, max);
        if (widget.getVerticalDimensionBehaviour() ==
            DimensionBehaviour.matchConstraint) {
          nbMatchConstraintsWidgets++;
        }
        var doWrap =
            (height == max || (height + _verticalGap + h) > max) &&
            list.mBiggest != null;
        if (!doWrap &&
            i > 0 &&
            _maxElementsWrap > 0 &&
            (i % _maxElementsWrap == 0)) {
          doWrap = true;
        }
        if (doWrap) {
          height = h;
          list = _WidgetsList(
            this,
            orientation,
            mLeft,
            mTop,
            mRight,
            mBottom,
            max,
          );
          list.setStartIndex(i);
          _chainList.add(list);
        } else {
          if (i > 0) {
            height += _verticalGap + h;
          } else {
            height = h;
          }
        }
        list.add(widget);
      }
    }
    final listCount = _chainList.length;

    var left = mLeft;
    var top = mTop;
    var right = mRight;
    var bottom = mBottom;

    var paddingLeft = getPaddingLeft();
    var paddingTop = getPaddingTop();
    var paddingRight = getPaddingRight();
    var paddingBottom = getPaddingBottom();

    var maxWidth = 0;
    var maxHeight = 0;

    final needInternalMeasure =
        getHorizontalDimensionBehaviour() == DimensionBehaviour.wrapContent ||
        getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent;

    if (nbMatchConstraintsWidgets > 0 && needInternalMeasure) {
      // we have to remeasure them.
      for (var i = 0; i < listCount; i++) {
        final current = _chainList[i];
        if (orientation == ConstraintWidget.HORIZONTAL) {
          current.measureMatchConstraints(max - current.getWidth());
        } else {
          current.measureMatchConstraints(max - current.getHeight());
        }
      }
    }

    for (var i = 0; i < listCount; i++) {
      final current = _chainList[i];
      if (orientation == ConstraintWidget.HORIZONTAL) {
        if (i < listCount - 1) {
          final next = _chainList[i + 1];
          bottom = next.mBiggest!.mTop;
          paddingBottom = 0;
        } else {
          bottom = mBottom;
          paddingBottom = getPaddingBottom();
        }
        final currentBottom = current.mBiggest!.mBottom;
        current.setup(
          orientation,
          left,
          top,
          right,
          bottom,
          paddingLeft,
          paddingTop,
          paddingRight,
          paddingBottom,
          max,
        );
        top = currentBottom;
        paddingTop = 0;
        maxWidth = maxWidth > current.getWidth()
            ? maxWidth
            : current.getWidth();
        maxHeight += current.getHeight();
        if (i > 0) {
          maxHeight += _verticalGap;
        }
      } else {
        if (i < listCount - 1) {
          final next = _chainList[i + 1];
          right = next.mBiggest!.mLeft;
          paddingRight = 0;
        } else {
          right = mRight;
          paddingRight = getPaddingRight();
        }
        final currentRight = current.mBiggest!.mRight;
        current.setup(
          orientation,
          left,
          top,
          right,
          bottom,
          paddingLeft,
          paddingTop,
          paddingRight,
          paddingBottom,
          max,
        );
        left = currentRight;
        paddingLeft = 0;
        maxWidth += current.getWidth();
        maxHeight = maxHeight > current.getHeight()
            ? maxHeight
            : current.getHeight();
        if (i > 0) {
          maxWidth += _horizontalGap;
        }
      }
    }
    measured[ConstraintWidget.HORIZONTAL] = maxWidth;
    measured[ConstraintWidget.VERTICAL] = maxHeight;
  }

  // ---- measure chain wrap new ----

  /// Measure the virtual layout using a list of chains for the children in
  /// new "fixed way".
  void _measureChainWrapNew(
    List<ConstraintWidget?> widgets,
    int count,
    int orientation,
    int max,
    List<int> measured,
  ) {
    if (count == 0) {
      return;
    }

    _chainList.clear();
    var list = _WidgetsList(
      this,
      orientation,
      mLeft,
      mTop,
      mRight,
      mBottom,
      max,
    );
    _chainList.add(list);

    var nbMatchConstraintsWidgets = 0;

    if (orientation == ConstraintWidget.HORIZONTAL) {
      var width = 0;
      var col = 0;
      for (var i = 0; i < count; i++) {
        col++;
        final widget = widgets[i]!;
        final w = _getWidgetWidth(widget, max);
        if (widget.getHorizontalDimensionBehaviour() ==
            DimensionBehaviour.matchConstraint) {
          nbMatchConstraintsWidgets++;
        }
        var doWrap =
            (width == max || (width + _horizontalGap + w) > max) &&
            list.mBiggest != null;
        if (!doWrap &&
            i > 0 &&
            _maxElementsWrap > 0 &&
            (col > _maxElementsWrap)) {
          doWrap = true;
        }
        if (doWrap) {
          col = 1;
          width = w;
          list = _WidgetsList(
            this,
            orientation,
            mLeft,
            mTop,
            mRight,
            mBottom,
            max,
          );
          list.setStartIndex(i);
          _chainList.add(list);
        } else {
          if (i > 0) {
            width += _horizontalGap + w;
          } else {
            width = w;
          }
        }
        list.add(widget);
      }
    } else {
      var height = 0;
      var row = 0;
      for (var i = 0; i < count; i++) {
        row++;
        final widget = widgets[i]!;
        final h = _getWidgetHeight(widget, max);
        if (widget.getVerticalDimensionBehaviour() ==
            DimensionBehaviour.matchConstraint) {
          nbMatchConstraintsWidgets++;
        }
        var doWrap =
            (height == max || (height + _verticalGap + h) > max) &&
            list.mBiggest != null;
        if (!doWrap &&
            i > 0 &&
            _maxElementsWrap > 0 &&
            (row > _maxElementsWrap)) {
          doWrap = true;
        }
        if (doWrap) {
          row = 1;
          height = h;
          list = _WidgetsList(
            this,
            orientation,
            mLeft,
            mTop,
            mRight,
            mBottom,
            max,
          );
          list.setStartIndex(i);
          _chainList.add(list);
        } else {
          if (i > 0) {
            height += _verticalGap + h;
          } else {
            height = h;
          }
        }
        list.add(widget);
      }
    }
    final listCount = _chainList.length;

    var left = mLeft;
    var top = mTop;
    var right = mRight;
    var bottom = mBottom;

    var paddingLeft = getPaddingLeft();
    var paddingTop = getPaddingTop();
    var paddingRight = getPaddingRight();
    var paddingBottom = getPaddingBottom();

    var maxWidth = 0;
    var maxHeight = 0;

    final needInternalMeasure =
        getHorizontalDimensionBehaviour() == DimensionBehaviour.wrapContent ||
        getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent;

    if (nbMatchConstraintsWidgets > 0 && needInternalMeasure) {
      // we have to remeasure them.
      for (var i = 0; i < listCount; i++) {
        final current = _chainList[i];
        if (orientation == ConstraintWidget.HORIZONTAL) {
          current.measureMatchConstraints(max - current.getWidth());
        } else {
          current.measureMatchConstraints(max - current.getHeight());
        }
      }
    }

    for (var i = 0; i < listCount; i++) {
      final current = _chainList[i];
      if (orientation == ConstraintWidget.HORIZONTAL) {
        if (i < listCount - 1) {
          final next = _chainList[i + 1];
          bottom = next.mBiggest!.mTop;
          paddingBottom = 0;
        } else {
          bottom = mBottom;
          paddingBottom = getPaddingBottom();
        }
        final currentBottom = current.mBiggest!.mBottom;
        current.setup(
          orientation,
          left,
          top,
          right,
          bottom,
          paddingLeft,
          paddingTop,
          paddingRight,
          paddingBottom,
          max,
        );
        top = currentBottom;
        paddingTop = 0;
        maxWidth = maxWidth > current.getWidth()
            ? maxWidth
            : current.getWidth();
        maxHeight += current.getHeight();
        if (i > 0) {
          maxHeight += _verticalGap;
        }
      } else {
        if (i < listCount - 1) {
          final next = _chainList[i + 1];
          right = next.mBiggest!.mLeft;
          paddingRight = 0;
        } else {
          right = mRight;
          paddingRight = getPaddingRight();
        }
        final currentRight = current.mBiggest!.mRight;
        current.setup(
          orientation,
          left,
          top,
          right,
          bottom,
          paddingLeft,
          paddingTop,
          paddingRight,
          paddingBottom,
          max,
        );
        left = currentRight;
        paddingLeft = 0;
        maxWidth += current.getWidth();
        maxHeight = maxHeight > current.getHeight()
            ? maxHeight
            : current.getHeight();
        if (i > 0) {
          maxWidth += _horizontalGap;
        }
      }
    }
    measured[ConstraintWidget.HORIZONTAL] = maxWidth;
    measured[ConstraintWidget.VERTICAL] = maxHeight;
  }

  // ---- measure no wrap ----

  /// Measure the virtual layout using a single chain for the children.
  void _measureNoWrap(
    List<ConstraintWidget?> widgets,
    int count,
    int orientation,
    int max,
    List<int> measured,
  ) {
    if (count == 0) {
      return;
    }
    _WidgetsList list;
    if (_chainList.isEmpty) {
      list = _WidgetsList(this, orientation, mLeft, mTop, mRight, mBottom, max);
      _chainList.add(list);
    } else {
      list = _chainList[0];
      list.clear();
      list.setup(
        orientation,
        mLeft,
        mTop,
        mRight,
        mBottom,
        getPaddingLeft(),
        getPaddingTop(),
        getPaddingRight(),
        getPaddingBottom(),
        max,
      );
    }

    for (var i = 0; i < count; i++) {
      final widget = widgets[i]!;
      list.add(widget);
    }

    measured[ConstraintWidget.HORIZONTAL] = list.getWidth();
    measured[ConstraintWidget.VERTICAL] = list.getHeight();
  }

  // ---- measure aligned ----

  /// Measure the virtual layout arranging the children in a regular grid.
  void _measureAligned(
    List<ConstraintWidget?> widgets,
    int count,
    int orientation,
    int max,
    List<int> measured,
  ) {
    var done = false;
    var rows = 0;
    var cols = 0;

    if (orientation == ConstraintWidget.HORIZONTAL) {
      cols = _maxElementsWrap;
      if (cols <= 0) {
        // let's initialize cols with an acceptable value
        var w = 0;
        cols = 0;
        for (var i = 0; i < count; i++) {
          if (i > 0) {
            w += _horizontalGap;
          }
          final widget = widgets[i];
          if (widget == null) {
            continue;
          }
          w += _getWidgetWidth(widget, max);
          if (w > max) {
            break;
          }
          cols++;
        }
      }
    } else {
      rows = _maxElementsWrap;
      if (rows <= 0) {
        // let's initialize rows with an acceptable value
        var h = 0;
        rows = 0;
        for (var i = 0; i < count; i++) {
          if (i > 0) {
            h += _verticalGap;
          }
          final widget = widgets[i];
          if (widget == null) {
            continue;
          }
          h += _getWidgetHeight(widget, max);
          if (h > max) {
            break;
          }
          rows++;
        }
      }
    }

    _alignedDimensions ??= [0, 0];

    if ((rows == 0 && orientation == ConstraintWidget.VERTICAL) ||
        (cols == 0 && orientation == ConstraintWidget.HORIZONTAL)) {
      done = true;
    }

    while (!done) {
      // get a num of rows (or cols)
      // get for each row and cols the chain of biggest elements

      if (orientation == ConstraintWidget.HORIZONTAL) {
        rows = (count / cols).ceil();
      } else {
        cols = (count / rows).ceil();
      }

      if (_alignedBiggestElementsInCols == null ||
          _alignedBiggestElementsInCols!.length < cols) {
        _alignedBiggestElementsInCols = List<ConstraintWidget?>.filled(
          cols,
          null,
        );
      } else {
        _alignedBiggestElementsInCols!.fillRange(
          0,
          _alignedBiggestElementsInCols!.length,
          null,
        );
      }
      if (_alignedBiggestElementsInRows == null ||
          _alignedBiggestElementsInRows!.length < rows) {
        _alignedBiggestElementsInRows = List<ConstraintWidget?>.filled(
          rows,
          null,
        );
      } else {
        _alignedBiggestElementsInRows!.fillRange(
          0,
          _alignedBiggestElementsInRows!.length,
          null,
        );
      }

      for (var i = 0; i < cols; i++) {
        for (var j = 0; j < rows; j++) {
          var index = j * cols + i;
          if (orientation == ConstraintWidget.VERTICAL) {
            index = i * rows + j;
          }
          if (index >= widgets.length) {
            continue;
          }
          final widget = widgets[index];
          if (widget == null) {
            continue;
          }
          final w = _getWidgetWidth(widget, max);
          final colBiggest = _alignedBiggestElementsInCols![i];
          if (colBiggest == null || colBiggest.getWidth() < w) {
            _alignedBiggestElementsInCols![i] = widget;
          }
          final h = _getWidgetHeight(widget, max);
          final rowBiggest = _alignedBiggestElementsInRows![j];
          if (rowBiggest == null || rowBiggest.getHeight() < h) {
            _alignedBiggestElementsInRows![j] = widget;
          }
        }
      }

      var w = 0;
      for (var i = 0; i < cols; i++) {
        final widget = _alignedBiggestElementsInCols![i];
        if (widget != null) {
          if (i > 0) {
            w += _horizontalGap;
          }
          w += _getWidgetWidth(widget, max);
        }
      }
      var h = 0;
      for (var j = 0; j < rows; j++) {
        final widget = _alignedBiggestElementsInRows![j];
        if (widget != null) {
          if (j > 0) {
            h += _verticalGap;
          }
          h += _getWidgetHeight(widget, max);
        }
      }
      measured[ConstraintWidget.HORIZONTAL] = w;
      measured[ConstraintWidget.VERTICAL] = h;

      if (orientation == ConstraintWidget.HORIZONTAL) {
        if (w > max) {
          if (cols > 1) {
            cols--;
          } else {
            done = true;
          }
        } else {
          done = true;
        }
      } else {
        // VERTICAL
        if (h > max) {
          if (rows > 1) {
            rows--;
          } else {
            done = true;
          }
        } else {
          done = true;
        }
      }
    }
    _alignedDimensions![ConstraintWidget.HORIZONTAL] = cols;
    _alignedDimensions![ConstraintWidget.VERTICAL] = rows;
  }

  void _createAlignedConstraints(bool isInRtl) {
    if (_alignedDimensions == null ||
        _alignedBiggestElementsInCols == null ||
        _alignedBiggestElementsInRows == null) {
      return;
    }

    for (var i = 0; i < _displayedWidgetsCount; i++) {
      final widget = _displayedWidgets[i]!;
      widget.resetAnchors();
    }

    final cols = _alignedDimensions![ConstraintWidget.HORIZONTAL];
    final rows = _alignedDimensions![ConstraintWidget.VERTICAL];

    ConstraintWidget? previous;
    var horizontalBias = _horizontalBias;
    for (var i = 0; i < cols; i++) {
      var index = i;
      if (isInRtl) {
        index = cols - i - 1;
        horizontalBias = 1 - _horizontalBias;
      }
      final widget = _alignedBiggestElementsInCols![index];
      if (widget == null || widget.getVisibility() == ConstraintWidget.GONE) {
        continue;
      }
      if (i == 0) {
        widget.connectAnchors(widget.mLeft, mLeft, getPaddingLeft());
        widget.setHorizontalChainStyle(_horizontalStyle);
        widget.setHorizontalBiasPercent(horizontalBias);
      }
      if (i == cols - 1) {
        widget.connectAnchors(widget.mRight, mRight, getPaddingRight());
      }
      if (i > 0 && previous != null) {
        widget.connectAnchors(widget.mLeft, previous.mRight, _horizontalGap);
        previous.connectAnchors(previous.mRight, widget.mLeft, 0);
      }
      previous = widget;
    }
    for (var j = 0; j < rows; j++) {
      final widget = _alignedBiggestElementsInRows![j];
      if (widget == null || widget.getVisibility() == ConstraintWidget.GONE) {
        continue;
      }
      if (j == 0) {
        widget.connectAnchors(widget.mTop, mTop, getPaddingTop());
        widget.setVerticalChainStyle(_verticalStyle);
        widget.setVerticalBiasPercent(_verticalBias);
      }
      if (j == rows - 1) {
        widget.connectAnchors(widget.mBottom, mBottom, getPaddingBottom());
      }
      if (j > 0 && previous != null) {
        widget.connectAnchors(widget.mTop, previous.mBottom, _verticalGap);
        previous.connectAnchors(previous.mBottom, widget.mTop, 0);
      }
      previous = widget;
    }

    for (var i = 0; i < cols; i++) {
      for (var j = 0; j < rows; j++) {
        var index = j * cols + i;
        if (_orientation == ConstraintWidget.VERTICAL) {
          index = i * rows + j;
        }
        if (index >= _displayedWidgets.length) {
          continue;
        }
        final widget = _displayedWidgets[index];
        if (widget == null || widget.getVisibility() == ConstraintWidget.GONE) {
          continue;
        }
        final biggestInCol = _alignedBiggestElementsInCols![i]!;
        final biggestInRow = _alignedBiggestElementsInRows![j]!;
        if (widget != biggestInCol) {
          widget.connectAnchors(widget.mLeft, biggestInCol.mLeft, 0);
          widget.connectAnchors(widget.mRight, biggestInCol.mRight, 0);
        }
        if (widget != biggestInRow) {
          widget.connectAnchors(widget.mTop, biggestInRow.mTop, 0);
          widget.connectAnchors(widget.mBottom, biggestInRow.mBottom, 0);
        }
      }
    }
  }

  // ---- add constraints to solver ----

  @override
  void addToSolver(LinearSystem system, bool optimize) {
    super.addToSolver(system, optimize);

    final parent = getParent();
    final isInRtl =
        parent != null && (parent as ConstraintWidgetContainer).isRtl();
    switch (_wrapMode) {
      case WRAP_CHAIN:
        final count = _chainList.length;
        for (var i = 0; i < count; i++) {
          final list = _chainList[i];
          list.createConstraints(isInRtl, i, i == count - 1);
        }
        break;
      case WRAP_NONE:
        if (_chainList.isNotEmpty) {
          final list = _chainList[0];
          list.createConstraints(isInRtl, 0, true);
        }
        break;
      case WRAP_ALIGNED:
        _createAlignedConstraints(isInRtl);
        break;
      case WRAP_CHAIN_NEW:
        final count = _chainList.length;
        for (var i = 0; i < count; i++) {
          final list = _chainList[i];
          list.createConstraints(isInRtl, i, i == count - 1);
        }
        break;
    }
    needsCallbackFromSolver(false);
  }
}

/// A single chain of widgets inside a [Flow] (one row or column).
class _WidgetsList {
  _WidgetsList(
    this._flow,
    this._orientation,
    this._left,
    this._top,
    this._right,
    this._bottom,
    this._max,
  ) : _paddingLeft = _flow.getPaddingLeft(),
      _paddingTop = _flow.getPaddingTop(),
      _paddingRight = _flow.getPaddingRight(),
      _paddingBottom = _flow.getPaddingBottom();

  final Flow _flow;
  int _orientation;
  ConstraintWidget? mBiggest;
  int mBiggestDimension = 0;
  ConstraintAnchor _left;
  ConstraintAnchor _top;
  ConstraintAnchor _right;
  ConstraintAnchor _bottom;
  int _paddingLeft;
  int _paddingTop;
  int _paddingRight;
  int _paddingBottom;
  int _width = 0;
  int _height = 0;
  int _startIndex = 0;
  int _count = 0;
  int _nbMatchConstraintsWidgets = 0;
  int _max;

  void setup(
    int orientation,
    ConstraintAnchor left,
    ConstraintAnchor top,
    ConstraintAnchor right,
    ConstraintAnchor bottom,
    int paddingLeft,
    int paddingTop,
    int paddingRight,
    int paddingBottom,
    int max,
  ) {
    _orientation = orientation;
    _left = left;
    _top = top;
    _right = right;
    _bottom = bottom;
    _paddingLeft = paddingLeft;
    _paddingTop = paddingTop;
    _paddingRight = paddingRight;
    _paddingBottom = paddingBottom;
    _max = max;
  }

  void clear() {
    mBiggestDimension = 0;
    mBiggest = null;
    _width = 0;
    _height = 0;
    _startIndex = 0;
    _count = 0;
    _nbMatchConstraintsWidgets = 0;
  }

  void setStartIndex(int value) => _startIndex = value;

  int getWidth() {
    if (_orientation == ConstraintWidget.HORIZONTAL) {
      return _width - _flow._horizontalGap;
    }
    return _width;
  }

  int getHeight() {
    if (_orientation == ConstraintWidget.VERTICAL) {
      return _height - _flow._verticalGap;
    }
    return _height;
  }

  void add(ConstraintWidget widget) {
    if (_orientation == ConstraintWidget.HORIZONTAL) {
      var width = _flow._getWidgetWidth(widget, _max);
      if (widget.getHorizontalDimensionBehaviour() ==
          DimensionBehaviour.matchConstraint) {
        _nbMatchConstraintsWidgets++;
        width = 0;
      }
      var gap = _flow._horizontalGap;
      if (widget.getVisibility() == ConstraintWidget.GONE) {
        gap = 0;
      }
      _width += width + gap;
      final height = _flow._getWidgetHeight(widget, _max);
      if (mBiggest == null || mBiggestDimension < height) {
        mBiggest = widget;
        mBiggestDimension = height;
        _height = height;
      }
    } else {
      final width = _flow._getWidgetWidth(widget, _max);
      var height = _flow._getWidgetHeight(widget, _max);
      if (widget.getVerticalDimensionBehaviour() ==
          DimensionBehaviour.matchConstraint) {
        _nbMatchConstraintsWidgets++;
        height = 0;
      }
      var gap = _flow._verticalGap;
      if (widget.getVisibility() == ConstraintWidget.GONE) {
        gap = 0;
      }
      _height += height + gap;
      if (mBiggest == null || mBiggestDimension < width) {
        mBiggest = widget;
        mBiggestDimension = width;
        _width = width;
      }
    }
    _count++;
  }

  void createConstraints(bool isInRtl, int chainIndex, bool isLastChain) {
    final count = _count;
    for (var i = 0; i < count; i++) {
      if (_startIndex + i >= _flow._displayedWidgetsCount) {
        break;
      }
      final widget = _flow._displayedWidgets[_startIndex + i];
      if (widget != null) {
        widget.resetAnchors();
      }
    }
    if (count == 0 || mBiggest == null) {
      return;
    }

    final singleChain = isLastChain && chainIndex == 0;
    var firstVisible = -1;
    var lastVisible = -1;
    for (var i = 0; i < count; i++) {
      var index = i;
      if (isInRtl) {
        index = count - 1 - i;
      }
      if (_startIndex + index >= _flow._displayedWidgetsCount) {
        break;
      }
      final widget = _flow._displayedWidgets[_startIndex + index];
      if (widget != null &&
          widget.getVisibility() == ConstraintWidget.VISIBLE) {
        if (firstVisible == -1) {
          firstVisible = i;
        }
        lastVisible = i;
      }
    }

    ConstraintWidget? previous;
    if (_orientation == ConstraintWidget.HORIZONTAL) {
      final verticalWidget = mBiggest!;
      verticalWidget.setVerticalChainStyle(_flow._verticalStyle);
      var padding = _paddingTop;
      if (chainIndex > 0) {
        padding += _flow._verticalGap;
      }
      verticalWidget.mTop.connect(_top, padding);
      if (isLastChain) {
        verticalWidget.mBottom.connect(_bottom, _paddingBottom);
      }
      if (chainIndex > 0) {
        final bottom = _top.mOwner.mBottom;
        bottom.connect(verticalWidget.mTop, 0);
      }

      var baselineVerticalWidget = verticalWidget;
      if (_flow._verticalAlign == Flow.VERTICAL_ALIGN_BASELINE &&
          !verticalWidget.hasBaseline()) {
        for (var i = 0; i < count; i++) {
          var index = i;
          if (isInRtl) {
            index = count - 1 - i;
          }
          if (_startIndex + index >= _flow._displayedWidgetsCount) {
            break;
          }
          final widget = _flow._displayedWidgets[_startIndex + index]!;
          if (widget.hasBaseline()) {
            baselineVerticalWidget = widget;
            break;
          }
        }
      }

      for (var i = 0; i < count; i++) {
        var index = i;
        if (isInRtl) {
          index = count - 1 - i;
        }
        if (_startIndex + index >= _flow._displayedWidgetsCount) {
          break;
        }
        final widget = _flow._displayedWidgets[_startIndex + index];
        if (widget == null) {
          continue;
        }
        if (i == 0) {
          widget.connectAnchors(widget.mLeft, _left, _paddingLeft);
        }

        // ChainHead is always based on index, not i.
        // E.g. RTL would have head at the right most widget.
        if (index == 0) {
          var style = _flow._horizontalStyle;
          var bias = isInRtl
              ? (1 - _flow._horizontalBias)
              : _flow._horizontalBias;
          if (_startIndex == 0 &&
              _flow._firstHorizontalStyle != ConstraintWidget.UNKNOWN) {
            style = _flow._firstHorizontalStyle;
            bias = isInRtl
                ? (1 - _flow._firstHorizontalBias)
                : _flow._firstHorizontalBias;
          } else if (isLastChain &&
              _flow._lastHorizontalStyle != ConstraintWidget.UNKNOWN) {
            style = _flow._lastHorizontalStyle;
            bias = isInRtl
                ? (1 - _flow._lastHorizontalBias)
                : _flow._lastHorizontalBias;
          }
          widget.setHorizontalChainStyle(style);
          widget.setHorizontalBiasPercent(bias);
        }
        if (i == count - 1) {
          widget.connectAnchors(widget.mRight, _right, _paddingRight);
        }
        if (previous != null) {
          widget.mLeft.connect(previous.mRight, _flow._horizontalGap);
          if (i == firstVisible) {
            widget.mLeft.setGoneMargin(_paddingLeft);
          }
          previous.mRight.connect(widget.mLeft, 0);
          if (i == lastVisible + 1) {
            previous.mRight.setGoneMargin(_paddingRight);
          }
        }
        if (widget != verticalWidget) {
          if (_flow._verticalAlign == Flow.VERTICAL_ALIGN_BASELINE &&
              baselineVerticalWidget.hasBaseline() &&
              widget != baselineVerticalWidget &&
              widget.hasBaseline()) {
            widget.mBaseline.connect(baselineVerticalWidget.mBaseline, 0);
          } else {
            switch (_flow._verticalAlign) {
              case Flow.VERTICAL_ALIGN_TOP:
                widget.mTop.connect(verticalWidget.mTop, 0);
                break;
              case Flow.VERTICAL_ALIGN_BOTTOM:
                widget.mBottom.connect(verticalWidget.mBottom, 0);
                break;
              case Flow.VERTICAL_ALIGN_CENTER:
              default:
                if (singleChain) {
                  widget.mTop.connect(_top, _paddingTop);
                  widget.mBottom.connect(_bottom, _paddingBottom);
                } else {
                  widget.mTop.connect(verticalWidget.mTop, 0);
                  widget.mBottom.connect(verticalWidget.mBottom, 0);
                }
            }
          }
        }
        previous = widget;
      }
    } else {
      final horizontalWidget = mBiggest!;
      horizontalWidget.setHorizontalChainStyle(_flow._horizontalStyle);
      var padding = _paddingLeft;
      if (chainIndex > 0) {
        padding += _flow._horizontalGap;
      }
      if (isInRtl) {
        horizontalWidget.mRight.connect(_right, padding);
        if (isLastChain) {
          horizontalWidget.mLeft.connect(_left, _paddingRight);
        }
        if (chainIndex > 0) {
          final left = _right.mOwner.mLeft;
          left.connect(horizontalWidget.mRight, 0);
        }
      } else {
        horizontalWidget.mLeft.connect(_left, padding);
        if (isLastChain) {
          horizontalWidget.mRight.connect(_right, _paddingRight);
        }
        if (chainIndex > 0) {
          final right = _left.mOwner.mRight;
          right.connect(horizontalWidget.mLeft, 0);
        }
      }
      for (var i = 0; i < count; i++) {
        if (_startIndex + i >= _flow._displayedWidgetsCount) {
          break;
        }
        final widget = _flow._displayedWidgets[_startIndex + i];
        if (widget == null) {
          continue;
        }
        if (i == 0) {
          widget.connectAnchors(widget.mTop, _top, _paddingTop);
          var style = _flow._verticalStyle;
          var bias = _flow._verticalBias;
          if (_startIndex == 0 &&
              _flow._firstVerticalStyle != ConstraintWidget.UNKNOWN) {
            style = _flow._firstVerticalStyle;
            bias = _flow._firstVerticalBias;
          } else if (isLastChain &&
              _flow._lastVerticalStyle != ConstraintWidget.UNKNOWN) {
            style = _flow._lastVerticalStyle;
            bias = _flow._lastVerticalBias;
          }
          widget.setVerticalChainStyle(style);
          widget.setVerticalBiasPercent(bias);
        }
        if (i == count - 1) {
          widget.connectAnchors(widget.mBottom, _bottom, _paddingBottom);
        }
        if (previous != null) {
          widget.mTop.connect(previous.mBottom, _flow._verticalGap);
          if (i == firstVisible) {
            widget.mTop.setGoneMargin(_paddingTop);
          }
          previous.mBottom.connect(widget.mTop, 0);
          if (i == lastVisible + 1) {
            previous.mBottom.setGoneMargin(_paddingBottom);
          }
        }
        if (widget != horizontalWidget) {
          if (isInRtl) {
            switch (_flow._horizontalAlign) {
              case Flow.HORIZONTAL_ALIGN_START:
                widget.mRight.connect(horizontalWidget.mRight, 0);
                break;
              case Flow.HORIZONTAL_ALIGN_CENTER:
                widget.mLeft.connect(horizontalWidget.mLeft, 0);
                widget.mRight.connect(horizontalWidget.mRight, 0);
                break;
              case Flow.HORIZONTAL_ALIGN_END:
                widget.mLeft.connect(horizontalWidget.mLeft, 0);
                break;
            }
          } else {
            switch (_flow._horizontalAlign) {
              case Flow.HORIZONTAL_ALIGN_START:
                widget.mLeft.connect(horizontalWidget.mLeft, 0);
                break;
              case Flow.HORIZONTAL_ALIGN_CENTER:
                if (singleChain) {
                  widget.mLeft.connect(_left, _paddingLeft);
                  widget.mRight.connect(_right, _paddingRight);
                } else {
                  widget.mLeft.connect(horizontalWidget.mLeft, 0);
                  widget.mRight.connect(horizontalWidget.mRight, 0);
                }
                break;
              case Flow.HORIZONTAL_ALIGN_END:
                widget.mRight.connect(horizontalWidget.mRight, 0);
                break;
            }
          }
        }
        previous = widget;
      }
    }
  }

  void measureMatchConstraints(int availableSpace) {
    if (_nbMatchConstraintsWidgets == 0) {
      return;
    }
    final count = _count;

    // that's completely incorrect and only works for spread with no weights?
    final widgetSize = availableSpace ~/ _nbMatchConstraintsWidgets;
    for (var i = 0; i < count; i++) {
      if (_startIndex + i >= _flow._displayedWidgetsCount) {
        break;
      }
      final widget = _flow._displayedWidgets[_startIndex + i];
      if (_orientation == ConstraintWidget.HORIZONTAL) {
        if (widget != null &&
            widget.getHorizontalDimensionBehaviour() ==
                DimensionBehaviour.matchConstraint) {
          if (widget.mMatchConstraintDefaultWidth ==
              ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
            _flow.measureWidget(
              widget,
              DimensionBehaviour.fixed,
              widgetSize,
              widget.getVerticalDimensionBehaviour(),
              widget.getHeight(),
            );
          }
        }
      } else {
        if (widget != null &&
            widget.getVerticalDimensionBehaviour() ==
                DimensionBehaviour.matchConstraint) {
          if (widget.mMatchConstraintDefaultHeight ==
              ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
            _flow.measureWidget(
              widget,
              widget.getHorizontalDimensionBehaviour(),
              widget.getWidth(),
              DimensionBehaviour.fixed,
              widgetSize,
            );
          }
        }
      }
    }
    _recomputeDimensions();
  }

  void _recomputeDimensions() {
    _width = 0;
    _height = 0;
    mBiggest = null;
    mBiggestDimension = 0;
    final count = _count;
    for (var i = 0; i < count; i++) {
      if (_startIndex + i >= _flow._displayedWidgetsCount) {
        break;
      }
      final widget = _flow._displayedWidgets[_startIndex + i]!;
      if (_orientation == ConstraintWidget.HORIZONTAL) {
        final width = widget.getWidth();
        var gap = _flow._horizontalGap;
        if (widget.getVisibility() == ConstraintWidget.GONE) {
          gap = 0;
        }
        _width += width + gap;
        final height = _flow._getWidgetHeight(widget, _max);
        if (mBiggest == null || mBiggestDimension < height) {
          mBiggest = widget;
          mBiggestDimension = height;
          _height = height;
        }
      } else {
        final width = _flow._getWidgetWidth(widget, _max);
        final height = _flow._getWidgetHeight(widget, _max);
        var gap = _flow._verticalGap;
        if (widget.getVisibility() == ConstraintWidget.GONE) {
          gap = 0;
        }
        _height += height + gap;
        if (mBiggest == null || mBiggestDimension < width) {
          mBiggest = widget;
          mBiggestDimension = width;
          _width = width;
        }
      }
    }
  }
}
