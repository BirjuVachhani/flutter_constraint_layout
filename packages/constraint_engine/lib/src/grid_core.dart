// Copyright (C) 2022 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.utils.GridCore
// (upstream pinned in UPSTREAM.md).

import 'dart:math' as math;

import 'analyzer/basic_measure.dart';
import 'constraint_widget.dart';
import 'constraint_widget_container.dart';
import 'linear_system.dart';
import 'virtual_layout.dart';

/// The Grid helper in the core library. Ported from
/// androidx.constraintlayout.core.utils.GridCore.
///
/// Widgets referenced by the grid are constrained to invisible "box" widgets
/// that form the grid skeleton (one chain per axis).
class GridCore extends VirtualLayout {
  static const int HORIZONTAL = 0;
  static const int VERTICAL = 1;
  static const int SUB_GRID_BY_COL_ROW = 0;
  static const int SPANS_RESPECT_WIDGET_ORDER = 1;
  static const int _DEFAULT_SIZE = 3;
  static const int _MAX_ROWS = 50;
  static const int _MAX_COLUMNS = 50;

  /// Container for all the ConstraintWidgets.
  ConstraintWidgetContainer? mContainer;

  /// Box widgets created as anchor points for arranging the widgets.
  List<ConstraintWidget>? _boxWidgets;

  /// Whether skips/spans of a row or column have been handled.
  bool _extraSpaceHandled = false;

  int _rows = 0;
  int _rowsSet = 0;
  int _columns = 0;
  int _columnsSet = 0;

  double _horizontalGaps = 0;
  double _verticalGaps = 0;

  String? _rowWeights;
  String? _columnWeights;
  String? _spans;
  String? _skips;

  int _orientation = 0;

  /// Next available position to place a widget.
  int _nextAvailableIndex = 0;

  /// True marks an available position; false an occupied one.
  List<List<bool>>? _positionMatrix;

  /// Widgets whose spans are already handled.
  final Set<ConstraintWidget> _spanIds = <ConstraintWidget>{};

  /// Positions each widget constrains to: [left, top, right, bottom].
  List<List<int>>? _constraintMatrix;

  List<int>? _flags;

  /// Span-related information: [position, rowSpan, colSpan].
  List<List<int>>? _spanMatrix;

  /// Next span to be handled.
  int _spanIndex = 0;

  bool _spansRespectWidgetOrder = false;
  bool _subGridByColRow = false;

  GridCore() {
    _updateActualRowsAndColumns();
    _initMatrices();
  }

  GridCore.sized(int rows, int columns) {
    _rowsSet = rows;
    _columnsSet = columns;
    if (rows > _MAX_ROWS) {
      _rowsSet = _DEFAULT_SIZE;
    }
    if (columns > _MAX_COLUMNS) {
      _columnsSet = _DEFAULT_SIZE;
    }
    _updateActualRowsAndColumns();
    _initMatrices();
  }

  ConstraintWidgetContainer? getContainer() => mContainer;

  void setContainer(ConstraintWidgetContainer container) =>
      mContainer = container;

  void setSpans(String spans) {
    if (_spans != null && _spans == spans) {
      return;
    }
    _extraSpaceHandled = false;
    _spans = spans;
  }

  void setSkips(String skips) {
    if (_skips != null && _skips == skips) {
      return;
    }
    _extraSpaceHandled = false;
    _skips = skips;
  }

  double getHorizontalGaps() => _horizontalGaps;

  void setHorizontalGaps(double horizontalGaps) {
    if (horizontalGaps < 0) {
      return;
    }
    if (_horizontalGaps == horizontalGaps) {
      return;
    }
    _horizontalGaps = horizontalGaps;
  }

  double getVerticalGaps() => _verticalGaps;

  void setVerticalGaps(double verticalGaps) {
    if (verticalGaps < 0) {
      return;
    }
    if (_verticalGaps == verticalGaps) {
      return;
    }
    _verticalGaps = verticalGaps;
  }

  String? getRowWeights() => _rowWeights;

  void setRowWeights(String rowWeights) {
    if (_rowWeights != null && _rowWeights == rowWeights) {
      return;
    }
    _rowWeights = rowWeights;
  }

  String? getColumnWeights() => _columnWeights;

  void setColumnWeights(String columnWeights) {
    if (_columnWeights != null && _columnWeights == columnWeights) {
      return;
    }
    _columnWeights = columnWeights;
  }

  int getOrientation() => _orientation;

  void setOrientation(int orientation) {
    if (!(orientation == HORIZONTAL || orientation == VERTICAL)) {
      return;
    }
    if (_orientation == orientation) {
      return;
    }
    _orientation = orientation;
  }

  void setRows(int rows) {
    // 0 means "derive from the column count and the widget count"; anything
    // negative is nonsense and would size the matrices to a negative length.
    if (rows < 0 || rows > _MAX_ROWS) {
      return;
    }
    if (_rowsSet == rows) {
      return;
    }
    _rowsSet = rows;
    _updateActualRowsAndColumns();
    _initVariables();
  }

  void setColumns(int columns) {
    // See setRows: 0 derives, negative is rejected.
    if (columns < 0 || columns > _MAX_COLUMNS) {
      return;
    }
    if (_columnsSet == columns) {
      return;
    }
    _columnsSet = columns;
    _updateActualRowsAndColumns();
    _initVariables();
  }

  List<int>? getFlags() => _flags;

  void setFlags(List<int> flags) => _flags = flags;

  /// Handle the span use cases.
  void _handleSpans(List<List<int>> spansMatrix) {
    if (_spansRespectWidgetOrder) {
      return;
    }
    for (var i = 0; i < spansMatrix.length; i++) {
      final row = _getRowByIndex(spansMatrix[i][0]);
      final col = _getColByIndex(spansMatrix[i][0]);
      if (!_invalidatePositions(
        row,
        col,
        spansMatrix[i][1],
        spansMatrix[i][2],
      )) {
        return;
      }
      _connectWidget(
        mWidgets[i]!,
        row,
        col,
        spansMatrix[i][1],
        spansMatrix[i][2],
      );
      _spanIds.add(mWidgets[i]!);
    }
  }

  /// Arrange the widgets in the referenced ids.
  void _arrangeWidgets() {
    int position;

    // @TODO handle RTL
    for (var i = 0; i < mWidgetsCount; i++) {
      if (_spanIds.contains(mWidgets[i])) {
        // skip the widget that's already handled by handleSpans
        continue;
      }

      position = _getNextPosition();
      final row = _getRowByIndex(position);
      final col = _getColByIndex(position);
      if (position == -1) {
        // no more available position.
        return;
      }

      final spanMatrix = _spanMatrix;
      if (_spansRespectWidgetOrder && spanMatrix != null) {
        if (_spanIndex < spanMatrix.length &&
            spanMatrix[_spanIndex][0] == position) {
          // when invoke getNextPosition this position would be set to false
          _positionMatrix![row][col] = true;
          // if there is not enough space to constrain the span, don't do it.
          if (!_invalidatePositions(
            row,
            col,
            spanMatrix[_spanIndex][1],
            spanMatrix[_spanIndex][2],
          )) {
            continue;
          }
          _connectWidget(
            mWidgets[i]!,
            row,
            col,
            spanMatrix[_spanIndex][1],
            spanMatrix[_spanIndex][2],
          );
          _spanIndex++;
          continue;
        }
      }
      _connectWidget(mWidgets[i]!, row, col, 1, 1);
    }
  }

  /// Generate the grid based on the input attributes.
  void _setupGrid(bool isUpdate) {
    if (_rows < 1 || _columns < 1) {
      return;
    }

    _handleFlags();

    if (isUpdate) {
      final positionMatrix = _positionMatrix!;
      for (var i = 0; i < positionMatrix.length; i++) {
        for (var j = 0; j < positionMatrix[0].length; j++) {
          positionMatrix[i][j] = true;
        }
      }
      _spanIds.clear();
    }

    _nextAvailableIndex = 0;

    final skips = _skips;
    if (skips != null && skips.trim().isNotEmpty) {
      final skipsMatrix = _parseSpans(skips, false);
      if (skipsMatrix != null) {
        _handleSkips(skipsMatrix);
      }
    }

    final spans = _spans;
    if (spans != null && spans.trim().isNotEmpty) {
      _spanMatrix = _parseSpans(spans, true);
    }

    // Need to create boxes before handleSpans since the spanned widgets would
    // be constrained in this step.
    _createBoxes();

    if (_spanMatrix != null) {
      _handleSpans(_spanMatrix!);
    }
  }

  int _getRowByIndex(int index) {
    if (_orientation == 1) {
      return index % _rows;
    } else {
      return index ~/ _columns;
    }
  }

  int _getColByIndex(int index) {
    if (_orientation == 1) {
      return index ~/ _rows;
    } else {
      return index % _columns;
    }
  }

  /// Make positions in the grid unavailable based on the skips attr.
  void _handleSkips(List<List<int>> skipsMatrix) {
    for (final matrix in skipsMatrix) {
      final row = _getRowByIndex(matrix[0]);
      final col = _getColByIndex(matrix[0]);
      if (!_invalidatePositions(row, col, matrix[1], matrix[2])) {
        return;
      }
    }
  }

  /// Make the specified positions in the grid unavailable.
  bool _invalidatePositions(
    int startRow,
    int startColumn,
    int rowSpan,
    int columnSpan,
  ) {
    final positionMatrix = _positionMatrix!;
    for (var i = startRow; i < startRow + rowSpan; i++) {
      for (var j = startColumn; j < startColumn + columnSpan; j++) {
        if (i >= positionMatrix.length ||
            j >= positionMatrix[0].length ||
            !positionMatrix[i][j]) {
          // the position is already occupied.
          return false;
        }
        positionMatrix[i][j] = false;
      }
    }
    return true;
  }

  /// Parse the weights/pads in the string format into a list.
  List<double>? _parseWeights(int size, String? str) {
    if (str == null || str.trim().isEmpty) {
      return null;
    }
    final values = str.split(',');
    if (values.length != size) {
      return null;
    }
    final arr = List<double>.filled(size, 0);
    for (var i = 0; i < arr.length; i++) {
      final parsed = double.tryParse(values[i].trim());
      if (parsed == null) {
        return null;
      }
      arr[i] = parsed;
    }
    return arr;
  }

  /// Get the next available position for widget arrangement.
  int _getNextPosition() {
    var position = 0;
    var positionFound = false;

    while (!positionFound) {
      if (_nextAvailableIndex >= _rows * _columns) {
        return -1;
      }

      position = _nextAvailableIndex;
      final row = _getRowByIndex(_nextAvailableIndex);
      final col = _getColByIndex(_nextAvailableIndex);
      if (_positionMatrix![row][col]) {
        _positionMatrix![row][col] = false;
        positionFound = true;
      }

      _nextAvailableIndex++;
    }
    return position;
  }

  /// Compute the actual rows and columns given what was set:
  /// if 0,0 find the most square rows and columns that fits;
  /// if 0,n or n,0 scale to fit.
  void _updateActualRowsAndColumns() {
    if (_rowsSet == 0 || _columnsSet == 0) {
      if (_columnsSet > 0) {
        _columns = _columnsSet;
        _rows = (mWidgetsCount + _columns - 1) ~/ _columnsSet; // round up
      } else if (_rowsSet > 0) {
        _rows = _rowsSet;
        _columns = (mWidgetsCount + _rowsSet - 1) ~/ _rowsSet; // round up
      } else {
        // as close to square as possible favoring more rows
        _rows = (1.5 + math.sqrt(mWidgetsCount)).toInt();
        _columns = (mWidgetsCount + _rows - 1) ~/ _rows;
      }
    } else {
      _rows = _rowsSet;
      _columns = _columnsSet;
    }
  }

  /// Create a new box widget for constraining widgets.
  ConstraintWidget _makeNewWidget() {
    final widget = ConstraintWidget();
    widget.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] =
        DimensionBehaviour.matchConstraint;
    widget.mListDimensionBehaviors[ConstraintWidget.VERTICAL] =
        DimensionBehaviour.matchConstraint;
    return widget;
  }

  /// Connect the widget to the corresponding box widgets.
  void _connectWidget(
    ConstraintWidget widget,
    int row,
    int column,
    int rowSpan,
    int columnSpan,
  ) {
    final boxWidgets = _boxWidgets!;
    // Connect the 4 sides
    widget.mLeft.connect(boxWidgets[column].mLeft, 0);
    widget.mTop.connect(boxWidgets[row].mTop, 0);
    widget.mRight.connect(boxWidgets[column + columnSpan - 1].mRight, 0);
    widget.mBottom.connect(boxWidgets[row + rowSpan - 1].mBottom, 0);
  }

  /// Set chain between box widgets horizontally.
  void _setBoxWidgetHorizontalChains() {
    final maxVal = math.max(_rows, _columns);
    final boxWidgets = _boxWidgets!;

    var widget = boxWidgets[0];
    final columnWeights = _parseWeights(_columns, _columnWeights);
    // chain all the widgets on the longer side (either horizontal or vertical)
    if (_columns == 1) {
      _clearHorizontalAttributes(widget);
      widget.mLeft.connect(mLeft, 0);
      widget.mRight.connect(mRight, 0);
      return;
    }

    // chains are grid <- box <-> box <-> box -> grid
    for (var i = 0; i < _columns; i++) {
      widget = boxWidgets[i];
      _clearHorizontalAttributes(widget);
      if (columnWeights != null) {
        widget.setHorizontalWeight(columnWeights[i]);
      }
      if (i > 0) {
        widget.mLeft.connect(boxWidgets[i - 1].mRight, 0);
      } else {
        widget.mLeft.connect(mLeft, 0);
      }
      if (i < _columns - 1) {
        widget.mRight.connect(boxWidgets[i + 1].mLeft, 0);
      } else {
        widget.mRight.connect(mRight, 0);
      }
      if (i > 0) {
        widget.mLeft.mMargin = _horizontalGaps.toInt();
      }
    }
    // excess boxes are connected to grid those sides are not use
    // for efficiency they should be connected to parent
    for (var i = _columns; i < maxVal; i++) {
      widget = boxWidgets[i];
      _clearHorizontalAttributes(widget);
      widget.mLeft.connect(mLeft, 0);
      widget.mRight.connect(mRight, 0);
    }
  }

  /// Set chain between box widgets vertically.
  void _setBoxWidgetVerticalChains() {
    final maxVal = math.max(_rows, _columns);
    final boxWidgets = _boxWidgets!;

    var widget = boxWidgets[0];
    final rowWeights = _parseWeights(_rows, _rowWeights);
    // chain all the widgets on the longer side (either horizontal or vertical)
    if (_rows == 1) {
      _clearVerticalAttributes(widget);
      widget.mTop.connect(mTop, 0);
      widget.mBottom.connect(mBottom, 0);
      return;
    }

    // chains are constrained like this: grid <- box <-> box <-> box -> grid
    for (var i = 0; i < _rows; i++) {
      widget = boxWidgets[i];
      _clearVerticalAttributes(widget);
      if (rowWeights != null) {
        widget.setVerticalWeight(rowWeights[i]);
      }
      if (i > 0) {
        widget.mTop.connect(boxWidgets[i - 1].mBottom, 0);
      } else {
        widget.mTop.connect(mTop, 0);
      }
      if (i < _rows - 1) {
        widget.mBottom.connect(boxWidgets[i + 1].mTop, 0);
      } else {
        widget.mBottom.connect(mBottom, 0);
      }
      if (i > 0) {
        widget.mTop.mMargin = _verticalGaps.toInt();
      }
    }

    // excess boxes are connected to grid those sides are not use
    // for efficiency they should be connected to parent
    for (var i = _rows; i < maxVal; i++) {
      widget = boxWidgets[i];
      _clearVerticalAttributes(widget);
      widget.mTop.connect(mTop, 0);
      widget.mBottom.connect(mBottom, 0);
    }
  }

  /// Chain the box widgets and add constraints to the widgets.
  void _addConstraints() {
    _setBoxWidgetVerticalChains();
    _setBoxWidgetHorizontalChains();
    _arrangeWidgets();
  }

  /// Create all the box widgets used to constrain the referenced widgets.
  void _createBoxes() {
    final boxCount = math.max(_rows, _columns);
    var boxWidgets = _boxWidgets;
    if (boxWidgets == null) {
      // no box widgets, build all
      boxWidgets = List<ConstraintWidget>.generate(
        boxCount,
        (_) => _makeNewWidget(),
      );
      _boxWidgets = boxWidgets;
    } else {
      if (boxCount != boxWidgets.length) {
        final temp = List<ConstraintWidget>.generate(
          boxCount,
          (i) => i < boxWidgets!.length ? boxWidgets[i] : _makeNewWidget(),
        );
        // remove excess
        for (var j = boxCount; j < boxWidgets.length; j++) {
          final widget = boxWidgets[j];
          mContainer?.remove(widget);
        }
        _boxWidgets = temp;
      }
    }
  }

  void _clearVerticalAttributes(ConstraintWidget widget) {
    widget.setVerticalWeight(ConstraintWidget.UNKNOWN.toDouble());
    widget.mTop.reset();
    widget.mBottom.reset();
    widget.mBaseline.reset();
  }

  void _clearHorizontalAttributes(ConstraintWidget widget) {
    widget.setHorizontalWeight(ConstraintWidget.UNKNOWN.toDouble());
    widget.mLeft.reset();
    widget.mRight.reset();
  }

  void _initVariables() {
    _positionMatrix = List<List<bool>>.generate(
      _rows,
      (_) => List<bool>.filled(_columns, true),
    );
    if (mWidgetsCount > 0) {
      _constraintMatrix = List<List<int>>.generate(
        mWidgetsCount,
        (_) => List<int>.filled(4, -1),
      );
    }
  }

  /// Parse the skips/spans string ("index:RxC" or "index:N", comma separated)
  /// into a matrix of [index, rowSpan, colSpan] rows.
  List<List<int>>? _parseSpans(String str, bool isSpans) {
    try {
      var extraRows = 0;
      var extraColumns = 0;
      final spans = str.split(',');
      final spanMatrix = List<List<int>>.generate(
        spans.length,
        (_) => List<int>.filled(3, 0),
      );
      List<String> indexAndSpan;
      if (_rows == 1 || _columns == 1) {
        for (var i = 0; i < spans.length; i++) {
          indexAndSpan = spans[i].trim().split(':');
          spanMatrix[i][0] = int.parse(indexAndSpan[0]);
          spanMatrix[i][1] = 1;
          spanMatrix[i][2] = 1;

          if (_columns == 1) {
            spanMatrix[i][1] = int.parse(indexAndSpan[1]);
            extraRows += spanMatrix[i][1];
            if (isSpans) {
              extraRows--;
            }
          }
          if (_rows == 1) {
            spanMatrix[i][2] = int.parse(indexAndSpan[1]);
            extraColumns += spanMatrix[i][2];
            if (isSpans) {
              extraColumns--;
            }
          }
        }

        if (extraRows != 0 && !_extraSpaceHandled) {
          setRows(_rows + extraRows);
        }
        if (extraColumns != 0 && !_extraSpaceHandled) {
          setColumns(_columns + extraColumns);
        }
        _extraSpaceHandled = true;
      } else {
        List<String> rowAndCol;
        for (var i = 0; i < spans.length; i++) {
          indexAndSpan = spans[i].trim().split(':');
          rowAndCol = indexAndSpan[1].split('x');
          spanMatrix[i][0] = int.parse(indexAndSpan[0]);
          if (_subGridByColRow) {
            spanMatrix[i][1] = int.parse(rowAndCol[1]);
            spanMatrix[i][2] = int.parse(rowAndCol[0]);
          } else {
            spanMatrix[i][1] = int.parse(rowAndCol[0]);
            spanMatrix[i][2] = int.parse(rowAndCol[1]);
          }
        }
      }
      return spanMatrix;
    } catch (e) {
      return null;
    }
  }

  /// Fill the constraint matrix based on the input attributes.
  void _fillConstraintMatrix(bool isUpdate) {
    if (isUpdate) {
      final positionMatrix = _positionMatrix!;
      for (var i = 0; i < positionMatrix.length; i++) {
        for (var j = 0; j < positionMatrix[0].length; j++) {
          positionMatrix[i][j] = true;
        }
      }
      final constraintMatrix = _constraintMatrix!;
      for (var i = 0; i < constraintMatrix.length; i++) {
        for (var j = 0; j < constraintMatrix[0].length; j++) {
          constraintMatrix[i][j] = -1;
        }
      }
    }

    _nextAvailableIndex = 0;

    final skips = _skips;
    if (skips != null && skips.trim().isNotEmpty) {
      final skipsMatrix = _parseSpans(skips, false);
      if (skipsMatrix != null) {
        _handleSkips(skipsMatrix);
      }
    }

    final spans = _spans;
    if (spans != null && spans.trim().isNotEmpty) {
      final spansMatrix = _parseSpans(spans, true);
      if (spansMatrix != null) {
        _handleSpans(spansMatrix);
      }
    }
  }

  void _initMatrices() {
    final isUpdate =
        _constraintMatrix != null &&
        _constraintMatrix!.length == mWidgetsCount &&
        _positionMatrix != null &&
        _positionMatrix!.length == _rows &&
        _positionMatrix![0].length == _columns;

    if (!isUpdate) {
      _initVariables();
    }

    _fillConstraintMatrix(isUpdate);
  }

  /// If flags are given, set the values of the corresponding variables.
  void _handleFlags() {
    final flags = _flags;
    if (flags == null) {
      return;
    }
    for (final flag in flags) {
      switch (flag) {
        case SPANS_RESPECT_WIDGET_ORDER:
          _spansRespectWidgetOrder = true;
          break;
        case SUB_GRID_BY_COL_ROW:
          _subGridByColRow = true;
          break;
      }
    }
  }

  @override
  void measure(int widthMode, int widthSize, int heightMode, int heightSize) {
    super.measure(widthMode, widthSize, heightMode, heightSize);
    // Divergence from upstream: report the incoming exact sizes as the
    // measured size. Upstream leaves the measured size untouched (its Compose
    // host only ever sizes grids through the solver); without this a fixed or
    // match-parent grid measured through a host measurer would collapse to 0.
    setMeasure(
      widthMode == BasicMeasure.EXACTLY ? widthSize : getWidth(),
      heightMode == BasicMeasure.EXACTLY ? heightSize : getHeight(),
    );
    final parent = getParent()! as ConstraintWidgetContainer;
    mContainer = parent;

    // Re-derive the track counts here rather than trusting the ones computed
    // when setRows/setColumns ran. Deriving the missing dimension needs the
    // widget count, and a host naturally configures the grid before adding
    // the widgets to it, so at that point the count was still zero and the
    // derived side came out as 0. The matrices are sized from those counts,
    // so they have to be rebuilt whenever the derivation moves.
    final previousRows = _rows;
    final previousColumns = _columns;
    _updateActualRowsAndColumns();
    // Only for a usable pair: the matrices are sized from these counts, and a
    // caller is free to have set something nonsensical. _setupGrid rejects it
    // just below, so an invalid grid measures to its reported size and places
    // nothing.
    if (_rows > 0 &&
        _columns > 0 &&
        (_rows != previousRows ||
            _columns != previousColumns ||
            _positionMatrix == null)) {
      _initVariables();
    }

    _setupGrid(false);
    final boxWidgets = _boxWidgets;
    if (boxWidgets == null) {
      // Nothing to place: no widgets, or a track count that stayed invalid.
      // Leave the measured size as reported instead of failing the layout.
      return;
    }
    for (final box in boxWidgets) {
      parent.add(box);
    }
  }

  @override
  void addToSolver(LinearSystem system, bool optimize) {
    super.addToSolver(system, optimize);
    _addConstraints();
  }
}
