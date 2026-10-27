// Copyright (C) 2022 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.utils.GridCore as released in
// constraintlayout-core 1.1.0 and 1.1.1, which changed it after the pinned
// upstream commit (see UPSTREAM.md).

import 'dart:math' as math;

import 'analyzer/basic_measure.dart';
import 'constraint_widget.dart';
import 'constraint_widget_container.dart';
import 'jfloat.dart';
import 'linear_system.dart';
import 'virtual_layout.dart';

/// The Grid helper in the core library. Ported from
/// androidx.constraintlayout.core.utils.GridCore.
///
/// Widgets referenced by the grid are constrained to invisible "box" widgets
/// that form the grid skeleton (one chain per axis).
///
/// The grid places the widgets added to it into the cells of [setRows] rows
/// and [setColumns] columns, in order, skipping the cells [setSkips] names;
/// [setSpans] lets a widget cover several cells. Like every
/// [VirtualLayout], it needs a [Measurer] that calls [measure], which
/// builds the grid.
///
/// In a right-to-left container ([ConstraintWidgetContainer.setRtl]) the
/// columns mirror: the first column is the rightmost, so the cells fill from
/// the right edge, while cell positions (in spans and skips) and column
/// weights still count from the first column. Upstream leaves right-to-left
/// as a TODO; see UPSTREAM.md.
class GridCore extends VirtualLayout {
  // TODO: Handle padding from VirtualLayout. It should represent the padding
  //  applied around the Grid itself. Usually decreasing its size.

  /// Orientation that fills the grid row by row. The default; see
  /// [setOrientation].
  static const int HORIZONTAL = 0;

  /// Orientation that fills the grid column by column.
  static const int VERTICAL = 1;

  // Flags using incremental bit positions

  /// Flag bit (see [setFlags]) that reads the size of a span or a skip as
  /// columns x rows instead of rows x columns: `1:3x2` is read as `1:2x3`.
  static const int SUB_GRID_BY_COL_ROW = 1;

  /// Flag bit (see [setFlags]) that places the widgets strictly in order and
  /// gives a span to the widget that lands on its position. Without it, the
  /// spans go to the first widgets, in order of position.
  static const int SPANS_RESPECT_WIDGET_ORDER = 2;

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

  /// An int value containing flag information.
  int _flags = 0;

  /// Span-related information: [position, rowSpan, colSpan].
  List<List<int>>? _spanMatrix;

  /// Next span to be handled.
  int _spanIndex = 0;

  /// Creates a grid whose numbers of rows and columns are derived from the
  /// number of widgets (see [setRows]).
  GridCore() {
    _updateActualRowsAndColumns();
    _initMatrices();
  }

  /// Creates a grid of [rows] rows and [columns] columns (0 derives the
  /// count, as in [setRows]); a count above 50 falls back to 3.
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

  /// Get the parent [ConstraintWidgetContainer]; see [setContainer].
  ConstraintWidgetContainer? getContainer() => mContainer;

  /// Set the parent [ConstraintWidgetContainer], which the grid's box
  /// widgets belong to. [measure] sets it to the grid's parent.
  void setContainer(ConstraintWidgetContainer container) =>
      mContainer = container;

  /// Set the spans: comma-separated `position:rowsxcolumns` entries (such as
  /// `0:2x2`), each making a widget cover that many rows and columns from
  /// the cell at `position`. The entries are sorted by position, and the
  /// first widgets take them in that order (see [SPANS_RESPECT_WIDGET_ORDER]
  /// for the other way to assign them). In a grid of one row or one column,
  /// an entry is `position:span`.
  void setSpans(String spans) {
    if (_spans != null && _spans == spans) {
      return;
    }
    _extraSpaceHandled = false;
    _spans = spans;
  }

  /// Set the cells to leave empty: comma-separated `position:rowsxcolumns`
  /// entries (`position:count` in a grid of one row or one column), applied
  /// in order of position.
  void setSkips(String skips) {
    if (_skips != null && _skips == skips) {
      return;
    }
    _extraSpaceHandled = false;
    _skips = skips;
  }

  /// Get the gap between columns; see [setHorizontalGaps].
  double getHorizontalGaps() => _horizontalGaps;

  /// Set the gap between columns. Negative values are ignored. The gap is
  /// kept as the binary32 value upstream's float holds, and the grid uses
  /// its integer part.
  void setHorizontalGaps(double horizontalGaps) {
    // Upstream's parameter is a float: the binary32 value is both the one
    // compared and the one stored.
    final gaps = f32(horizontalGaps);
    if (gaps < 0) {
      return;
    }
    if (_horizontalGaps == gaps) {
      return;
    }
    _horizontalGaps = gaps;
  }

  /// Get the gap between rows; see [setVerticalGaps].
  double getVerticalGaps() => _verticalGaps;

  /// Set the gap between rows. Negative values are ignored. The gap is kept
  /// as the binary32 value upstream's float holds, and the grid uses its
  /// integer part.
  void setVerticalGaps(double verticalGaps) {
    final gaps = f32(verticalGaps);
    if (gaps < 0) {
      return;
    }
    if (_verticalGaps == gaps) {
      return;
    }
    _verticalGaps = gaps;
  }

  /// Get the row weights set by [setRowWeights], or null.
  String? getRowWeights() => _rowWeights;

  /// Set the row weights: comma-separated numbers, one per row (such as
  /// `1,2,1`), that share the grid's height between the rows. A shorter list
  /// is padded with weights of 1, a longer one is trimmed to the number of
  /// rows, and an entry that does not parse reads as 1.
  void setRowWeights(String rowWeights) {
    if (_rowWeights != null && _rowWeights == rowWeights) {
      return;
    }
    _rowWeights = rowWeights;
  }

  /// Get the column weights set by [setColumnWeights], or null.
  String? getColumnWeights() => _columnWeights;

  /// Set the column weights: comma-separated numbers, one per column (such
  /// as `1,2,1`), that share the grid's width between the columns. A shorter
  /// list is padded with weights of 1, a longer one is trimmed to the number
  /// of columns, and an entry that does not parse reads as 1.
  void setColumnWeights(String columnWeights) {
    if (_columnWeights != null && _columnWeights == columnWeights) {
      return;
    }
    _columnWeights = columnWeights;
  }

  /// Get the orientation: [HORIZONTAL] or [VERTICAL].
  int getOrientation() => _orientation;

  /// Set the order the cells fill in: [HORIZONTAL] (row by row, the
  /// default) or [VERTICAL] (column by column). Other values are ignored.
  void setOrientation(int orientation) {
    if (!(orientation == HORIZONTAL || orientation == VERTICAL)) {
      return;
    }
    if (_orientation == orientation) {
      return;
    }
    _orientation = orientation;
  }

  /// Set the number of rows, from 1 to 50, or 0 to derive it from the
  /// number of columns and of widgets (and when both counts are 0, the
  /// grid is made about square). Other values are ignored.
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

  /// Set the number of columns, from 1 to 50, or 0 to derive it from the
  /// number of rows and of widgets (see [setRows]). Other values are
  /// ignored.
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

  /// Get the flags set by [setFlags]: an int value containing flag
  /// information, 0 when no flag is set.
  int getFlags() => _flags;

  /// Set the flags of the grid: an int value containing flag information,
  /// the bitwise or of [SUB_GRID_BY_COL_ROW] and [SPANS_RESPECT_WIDGET_ORDER]
  /// (0 for none). It replaces the flags set before.
  void setFlags(int flags) => _flags = flags;

  /// Handle the span use cases.
  void _handleSpans(List<List<int>> spansMatrix) {
    if (_isSpansRespectWidgetOrder()) {
      return;
    }
    // Divergence from upstream, which reads a widget for every span entry
    // and throws once the entries outnumber the widgets: the entries past
    // the last widget have no widget to place, so they are ignored.
    final count = math.min(spansMatrix.length, mWidgetsCount);
    for (var i = 0; i < count; i++) {
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

    // @TODO handle RTL (upstream; this port mirrors the columns in
    // _connectWidget)
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
      if (_isSpansRespectWidgetOrder() && spanMatrix != null) {
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

    if (isUpdate) {
      final positionMatrix = _positionMatrix!;
      for (var i = 0; i < positionMatrix.length; i++) {
        for (var j = 0; j < positionMatrix[0].length; j++) {
          positionMatrix[i][j] = true;
        }
      }
      _spanIds.clear();
      // Not in upstream, which never updates a grid (see _addConstraints):
      // SPANS_RESPECT_WIDGET_ORDER hands the spans out again from the first.
      _spanIndex = 0;
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

  // Java's int `/` and `%`: both truncate toward zero, so a negative index
  // (a negative position in the spans or skips) gives a negative row or
  // column, which _invalidatePositions rejects.
  int _getRowByIndex(int index) {
    if (_orientation == 1) {
      return index.remainder(_rows);
    } else {
      return index ~/ _columns;
    }
  }

  int _getColByIndex(int index) {
    if (_orientation == 1) {
      return index ~/ _rows;
    } else {
      return index.remainder(_columns);
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
        // Divergence from upstream, which indexes the matrix with a negative
        // row or column (from a negative position) and throws: such a
        // position cannot be taken, like one past the last row or column.
        if (i < 0 ||
            j < 0 ||
            i >= positionMatrix.length ||
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

  /// Parse the weights/pads in the string format into a list. Note that
  /// weights are normally expected to match the size. But in case they
  /// don't, we trim or pad the weights with trailing 1 to match the expected
  /// size.
  List<double>? _parseWeights(int size, String? str) {
    if (str == null || str.trim().isEmpty) {
      return null;
    }

    final values = _splitLikeJava(str, ',');

    // Return array must be of the expected size, effectively trimming excess
    // weights
    final arr = List<double>.filled(size, 0);
    for (var i = 0; i < arr.length; i++) {
      if (i < values.length) {
        // Java's Float.parseFloat: surrounding whitespace is dropped, a
        // trailing f or d and hexadecimal floats ("2f", "0x1p3") are
        // numbers, and the value is rounded once to binary32. Upstream also
        // prints the parse error to System.err, which the port leaves out.
        final parsed = tryParseFloat32(values[i]);
        // Fallback to 1.
        arr[i] = parsed ?? 1;
      } else {
        // Fill in missing weights with 1
        arr[i] = 1;
      }
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
        // (int) (1.5 + Math.sqrt(mWidgetsCount)): double arithmetic, cast.
        _rows = jint(1.5 + math.sqrt(mWidgetsCount));
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
    // Divergence from upstream, which does not handle right-to-left: in a
    // right-to-left container the columns count from the right edge. The box
    // chain still runs left to right, so logical column c is box
    // _columns - 1 - c, and columns c to c + columnSpan - 1 start at box
    // _columns - c - columnSpan. Mirroring the column weights to match (see
    // _setBoxWidgetHorizontalChains) makes the result the mirror image of the
    // left-to-right grid.
    final leftColumn = _isInRtl() ? _columns - column - columnSpan : column;
    // Connect the 4 sides
    widget.mLeft.connect(boxWidgets[leftColumn].mLeft, 0);
    widget.mTop.connect(boxWidgets[row].mTop, 0);
    widget.mRight.connect(boxWidgets[leftColumn + columnSpan - 1].mRight, 0);
    widget.mBottom.connect(boxWidgets[row + rowSpan - 1].mBottom, 0);
  }

  /// Whether the container lays out right to left
  /// ([ConstraintWidgetContainer.isRtl]), which mirrors the columns. Read on
  /// every solve, as Flow reads it, so a change of direction takes effect at
  /// the next layout.
  bool _isInRtl() {
    final parent = getParent();
    return parent is ConstraintWidgetContainer && parent.isRtl();
  }

  /// Set chain between box widgets horizontally.
  void _setBoxWidgetHorizontalChains() {
    final maxVal = math.max(_rows, _columns);
    final boxWidgets = _boxWidgets!;

    var widget = boxWidgets[0];
    final columnWeights = _parseWeights(_columns, _columnWeights);
    // Box i holds logical column _columns - 1 - i in a right-to-left
    // container (see _connectWidget).
    final isInRtl = _isInRtl();
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
        widget.setHorizontalWeight(
          columnWeights[isInRtl ? _columns - 1 - i : i],
        );
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
        widget.mLeft.mMargin = jint(_horizontalGaps);
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
        widget.mTop.mMargin = jint(_verticalGaps);
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
    // Divergence from upstream, which arranges the widgets here on top of the
    // cells and the span cursor the previous solve left taken: a layout can
    // solve several times, and a later layout of the same grid solves again,
    // so each further solve moved the widgets on into the cells still free
    // (and kept the last ones once none was left). Placing them from scratch
    // on every solve, with setupGrid's update path, which upstream never
    // calls, gives every solve the placement the first one made.
    _setupGrid(true);
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
  /// into a matrix of [index, rowSpan, colSpan] rows, sorted by index.
  List<List<int>>? _parseSpans(String str, bool isSpans) {
    try {
      var extraRows = 0;
      var extraColumns = 0;
      // Sort the spans by the position
      final spans = _sortedByPosition(_splitLikeJava(str, ','));
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
          if (_isSubGridByColRow()) {
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

  /// The entries of a spans/skips string, sorted by position. Upstream sorts
  /// them in place with `Arrays.sort`, comparing
  /// `Integer.parseInt(span.split(":")[0])`.
  ///
  /// Java's object sort is stable, so entries at the same position keep the
  /// order they are listed in; Dart's [List.sort] is not, so the listed index
  /// breaks ties here. Like the comparator, this throws (and [_parseSpans]
  /// then returns null) when a position does not parse.
  ///
  /// Divergence from upstream: Java's Integer.parseInt rejects surrounding
  /// whitespace, so upstream's comparator throws on a string with a space
  /// after a comma (`'0:2x1, 4:1x2'`) and the whole string is ignored. Dart's
  /// int.parse ignores that whitespace, as every other parse in this class
  /// already did before the sort was added, so here such a string sorts and
  /// parses.
  static List<String> _sortedByPosition(List<String> spans) {
    final positions = [for (final span in spans) int.parse(span.split(':')[0])];
    final order = List<int>.generate(spans.length, (i) => i)
      ..sort((a, b) {
        final byPosition = positions[a] - positions[b];
        return byPosition != 0 ? byPosition : a - b;
      });
    return [for (final i in order) spans[i]];
  }

  /// Splits [str] at [separator] as Java's `String.split` does, which
  /// upstream's parsers rely on: trailing empty strings are dropped, so
  /// `'0:1x2,'` is one entry and `','` none, while a string without the
  /// separator comes back whole. Dart's [String.split] keeps the trailing
  /// empty strings, so a list ending in a comma failed to parse.
  static List<String> _splitLikeJava(String str, String separator) {
    final parts = str.split(separator);
    if (parts.length == 1) {
      return parts;
    }
    var end = parts.length;
    while (end > 0 && parts[end - 1].isEmpty) {
      end--;
    }
    return parts.sublist(0, end);
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

  /// Flag to implicitly reverse the order of width/height specified in spans
  /// & skips. E.g.: 1:3x2 is read as 1:2x3
  bool _isSubGridByColRow() => (_flags & SUB_GRID_BY_COL_ROW) > 0;

  /// Flag to respect the order of the Widgets when arranging for spans.
  bool _isSpansRespectWidgetOrder() =>
      (_flags & SPANS_RESPECT_WIDGET_ORDER) > 0;

  /// Build the grid: derive the numbers of rows and columns, apply the skips
  /// and spans, and create the box widgets (adding them to the parent
  /// container). The widgets are constrained to their cells when the grid is
  /// added to the solver. Reports the given size on a
  /// [BasicMeasure.EXACTLY] axis and the current size on the others.
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
    // Not in upstream: a container holding a grid keeps the priority goal
    // row's tie epsilon (grid layouts have no Android oracle; see
    // UPSTREAM.md). Every solve resets the system before adding the
    // children, so the flag holds exactly while this container holds a grid.
    system.goalTieEpsilon = true;
    super.addToSolver(system, optimize);
    // Divergence from upstream, which dereferences the box widgets
    // unconditionally: with nothing to place (no widgets, so a derived track
    // count of 0, or no measure pass at all) there are no boxes. Upstream then
    // throws here, and ConstraintWidgetContainer.layout catches the exception
    // and abandons that whole solve, leaving every other widget unplaced too.
    // The grid itself is still constrained by the call above.
    if (_boxWidgets == null) {
      return;
    }
    _addConstraints();
  }
}
