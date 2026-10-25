// Copyright (C) 2022 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.utils.GridEngine (upstream
// pinned in UPSTREAM.md; the released core 1.1.1 has the same file).

import 'dart:math' as math;

/// GridEngine class contains the main logic of the Grid Helper.
///
/// A standalone cell-placement engine: given a number of rows and columns,
/// spans, and skips, it works out which cells each of a number of widgets
/// covers, reported by [leftOfWidget], [topOfWidget], [rightOfWidget], and
/// [bottomOfWidget] as column and row indices. [GridCore], the grid virtual
/// layout, does not use it; it is ported for parity with upstream's
/// `utils` package, whose `GridEngineTest` exercises it.
///
/// ```dart
/// final engine = GridEngine.sizedWithWidgets(3, 3, 5);
/// engine.leftOfWidget(4); // 1: the fifth widget is in the second column
/// engine.topOfWidget(4); // 1: of the second row
/// ```
class GridEngine {
  /// Orientation that fills the grid column by column; see [setOrientation].
  static const int VERTICAL = 1;

  /// Orientation that fills the grid row by row. The default.
  static const int HORIZONTAL = 0;
  static const int _MAX_ROWS = 50; // maximum number of rows can be specified.
  // maximum number of columns can be specified.
  static const int _MAX_COLUMNS = 50;
  static const int _DEFAULT_SIZE = 3; // default rows and columns.

  /// number of rows of the grid
  int _rows = 0;

  /// number of rows set by the XML or API
  int _rowsSet = 0;

  /// How many widgets need to be placed in the Grid
  int _numWidgets = 0;

  /// number of columns of the grid
  int _columns = 0;

  /// number of columns set by the XML or API
  int _columnsSet = 0;

  /// string format of the input Spans
  String? _strSpans;

  /// string format of the input Skips
  String? _strSkips;

  /// orientation of the view arrangement - vertical or horizontal
  int _orientation = 0;

  /// Indicates what is the next available position to place an widget
  int _nextAvailableIndex = 0;

  /// A boolean matrix that tracks the positions that are occupied by skips and
  /// spans. true: available position; false: non-available position.
  List<List<bool>>? _positionMatrix;

  /// A int matrix that contains the positions where a widget would constraint
  /// to at each direction. Each row contains 4 values that indicate the
  /// position to constraint of a widget. Example row: [left, top, right,
  /// bottom]
  List<List<int>>? _constraintMatrix;

  /// Creates an engine with no rows, columns, or widgets; set them, then call
  /// [setup].
  GridEngine();

  /// Creates an engine of [rows] rows and [columns] columns (0 derives the
  /// count from the other one and the number of widgets, as in [setRows]); a
  /// count above 50 falls back to 3. Set the number of widgets with
  /// [setNumWidgets], then call [setup].
  GridEngine.sized(int rows, int columns) {
    _rowsSet = rows;
    _columnsSet = columns;
    if (rows > _MAX_ROWS) {
      _rowsSet = _DEFAULT_SIZE;
    }

    if (columns > _MAX_COLUMNS) {
      _columnsSet = _DEFAULT_SIZE;
    }

    _updateActualRowsAndColumns();
    _initVariables();
  }

  /// Creates an engine of [rows] rows and [columns] columns, as
  /// [GridEngine.sized] does, and places [numWidgets] widgets right away. A
  /// [numWidgets] below 1 or above the number of cells places one widget per
  /// cell.
  GridEngine.sizedWithWidgets(int rows, int columns, int numWidgets) {
    _rowsSet = rows;
    _columnsSet = columns;
    _numWidgets = numWidgets;

    if (rows > _MAX_ROWS) {
      _rowsSet = _DEFAULT_SIZE;
    }

    if (columns > _MAX_COLUMNS) {
      _columnsSet = _DEFAULT_SIZE;
    }

    _updateActualRowsAndColumns();

    if (numWidgets > _rows * _columns || numWidgets < 1) {
      _numWidgets = _rows * _columns;
    }

    _initVariables();
    _fillConstraintMatrix(false);
  }

  /// Initialize the relevant variables
  void _initVariables() {
    _positionMatrix = List<List<bool>>.generate(
      _rows,
      (_) => List<bool>.filled(_columns, true),
    );

    if (_numWidgets > 0) {
      _constraintMatrix = List<List<int>>.generate(
        _numWidgets,
        (_) => List<int>.filled(4, -1),
      );
    }
  }

  /// Convert a 1D index to a 2D index that has index for row and index for
  /// column.
  int _getRowByIndex(int index) {
    if (_orientation == 1) {
      return index % _rows;
    } else {
      return index ~/ _columns;
    }
  }

  /// Convert a 1D index to a 2D index that has index for row and index for
  /// column.
  int _getColByIndex(int index) {
    if (_orientation == 1) {
      return index ~/ _rows;
    } else {
      return index % _columns;
    }
  }

  /// Check if the value of the spans/skips is valid
  bool _isSpansValid(String? str) {
    if (str == null) {
      return false;
    }
    return true;
  }

  /// parse the skips/spans in the string format into a int matrix that each
  /// row has the information - [index, row_span, col_span]. The format of the
  /// input string is index:row_spanxcol_span: index is the index of the
  /// starting position, row_span the number of rows to span, and col_span
  /// the number of columns to span.
  ///
  /// Unlike [GridCore]'s parser, this one does not catch a malformed entry:
  /// as upstream's, it throws. Two kinds of entry upstream rejects pass here
  /// (see UPSTREAM.md): Dart's `int.parse` reads a hexadecimal position such
  /// as `0x2`, and a negative position wraps to the end of its row or column.
  List<List<int>>? _parseSpans(String? str) {
    if (!_isSpansValid(str)) {
      return null;
    }

    final spans = _splitLikeJava(str!, ',');
    final spanMatrix = List<List<int>>.generate(
      spans.length,
      (_) => List<int>.filled(3, 0),
    );

    List<String> indexAndSpan;
    List<String> rowAndCol;
    for (var i = 0; i < spans.length; i++) {
      indexAndSpan = spans[i].trim().split(':');
      rowAndCol = indexAndSpan[1].split('x');
      spanMatrix[i][0] = int.parse(indexAndSpan[0]);
      spanMatrix[i][1] = int.parse(rowAndCol[0]);
      spanMatrix[i][2] = int.parse(rowAndCol[1]);
    }
    return spanMatrix;
  }

  /// Splits [str] at [separator] as Java's `String.split` does, which
  /// upstream's parser relies on: trailing empty strings are dropped, so
  /// `'0:2x2,'` is one entry and `','` none, while a string without the
  /// separator comes back whole. Dart's [String.split] keeps the trailing
  /// empty strings, and an empty entry would make [_parseSpans] throw.
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

  /// fill the constraintMatrix based on the input attributes
  ///
  /// [isUpdate] is whether to update the existing grid (true) or create a new
  /// one (false).
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

    final strSkips = _strSkips;
    if (strSkips != null && strSkips.trim().isNotEmpty) {
      final skips = _parseSpans(strSkips);
      if (skips != null) {
        _handleSkips(skips);
      }
    }

    final strSpans = _strSpans;
    if (strSpans != null && strSpans.trim().isNotEmpty) {
      final spans = _parseSpans(strSpans);
      if (spans != null) {
        _handleSpans(spans);
      }
    }

    _addAllConstraintPositions();
  }

  /// Get the next available position for widget arrangement, or -1 when no
  /// cell is left.
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

  /// add the constraint position info of a widget based on the input params
  ///
  /// [widgetId] is the Id of the widget, [row] the row position to place the
  /// view, and [column] the column position to place the view.
  void _addConstraintPosition(
    int widgetId,
    int row,
    int column,
    int rowSpan,
    int columnSpan,
  ) {
    final constraintMatrix = _constraintMatrix!;
    constraintMatrix[widgetId][0] = column;
    constraintMatrix[widgetId][1] = row;
    constraintMatrix[widgetId][2] = column + columnSpan - 1;
    constraintMatrix[widgetId][3] = row + rowSpan - 1;
  }

  /// Handle the span use cases
  void _handleSpans(List<List<int>> spansMatrix) {
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
      _addConstraintPosition(
        i,
        row,
        col,
        spansMatrix[i][1],
        spansMatrix[i][2],
      );
    }
  }

  /// Make positions in the grid unavailable based on the skips attr
  void _handleSkips(List<List<int>> skipsMatrix) {
    for (var i = 0; i < skipsMatrix.length; i++) {
      final row = _getRowByIndex(skipsMatrix[i][0]);
      final col = _getColByIndex(skipsMatrix[i][0]);
      if (!_invalidatePositions(
        row,
        col,
        skipsMatrix[i][1],
        skipsMatrix[i][2],
      )) {
        return;
      }
    }
  }

  /// Make the specified positions in the grid unavailable: [rowSpan] rows and
  /// [columnSpan] columns from [startRow] and [startColumn]. Returns true if
  /// we could properly invalidate the positions else false.
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

  /// Arrange the views in the constraint_referenced_ids
  void _addAllConstraintPositions() {
    int position;

    for (var i = 0; i < _numWidgets; i++) {
      // Already added ConstraintPosition
      if (leftOfWidget(i) != -1) {
        continue;
      }

      position = _getNextPosition();
      final row = _getRowByIndex(position);
      final col = _getColByIndex(position);
      if (position == -1) {
        // no more available position.
        return;
      }
      _addConstraintPosition(i, row, col, 1, 1);
    }
  }

  /// Compute the actual rows and columns given what was set:
  /// if 0,0 find the most square rows and columns that fits;
  /// if 0,n or n,0 scale to fit.
  void _updateActualRowsAndColumns() {
    if (_rowsSet == 0 || _columnsSet == 0) {
      if (_columnsSet > 0) {
        _columns = _columnsSet;
        _rows = (_numWidgets + _columns - 1) ~/ _columnsSet; // round up
      } else if (_rowsSet > 0) {
        _rows = _rowsSet;
        _columns = (_numWidgets + _rowsSet - 1) ~/ _rowsSet; // round up
      } else {
        // as close to square as possible favoring more rows
        _rows = (1.5 + math.sqrt(_numWidgets)).toInt();
        _columns = (_numWidgets + _rows - 1) ~/ _rows;
      }
    } else {
      _rows = _rowsSet;
      _columns = _columnsSet;
    }
  }

  /// Set up the Grid engine: place the widgets with the current rows,
  /// columns, number of widgets, orientation, spans, and skips.
  void setup() {
    var isUpdate = true;

    if (_constraintMatrix == null ||
        _constraintMatrix!.length != _numWidgets ||
        _positionMatrix == null ||
        _positionMatrix!.length != _rows ||
        _positionMatrix![0].length != _columns) {
      isUpdate = false;
    }

    if (!isUpdate) {
      _initVariables();
    }

    _fillConstraintMatrix(isUpdate);
  }

  /// set new spans value: comma-separated `index:RxC` entries, each covering
  /// `R` rows and `C` columns from cell `index`. The first entry places the
  /// first widget, the second entry the second widget, and so on.
  void setSpans(String spans) {
    if (_strSpans != null && _strSpans == spans) {
      return;
    }

    _strSpans = spans;
  }

  /// set new skips value: comma-separated `index:RxC` entries, each leaving
  /// `R` rows and `C` columns from cell `index` empty.
  void setSkips(String skips) {
    if (_strSkips != null && _strSkips == skips) {
      return;
    }

    _strSkips = skips;
  }

  /// set new orientation value: [HORIZONTAL] (row by row, the default) or
  /// [VERTICAL] (column by column). Other values are ignored.
  void setOrientation(int orientation) {
    if (!(orientation == HORIZONTAL || orientation == VERTICAL)) {
      return;
    }

    if (_orientation == orientation) {
      return;
    }

    _orientation = orientation;
  }

  /// Set new NumWidgets value: how many widgets to be arranged in Grid. A
  /// number above the number of cells is ignored.
  void setNumWidgets(int num) {
    if (num > _rows * _columns) {
      return;
    }

    _numWidgets = num;
  }

  /// set new rows value: at most 50, or 0 to derive it from the number of
  /// columns and of widgets.
  void setRows(int rows) {
    if (rows > _MAX_ROWS) {
      return;
    }

    if (_rowsSet == rows) {
      return;
    }

    _rowsSet = rows;
    _updateActualRowsAndColumns();
  }

  /// set new columns value: at most 50, or 0 to derive it from the number of
  /// rows and of widgets.
  void setColumns(int columns) {
    if (columns > _MAX_COLUMNS) {
      return;
    }

    if (_columnsSet == columns) {
      return;
    }

    _columnsSet = columns;
    _updateActualRowsAndColumns();
  }

  /// Get the boxView for the widget [i] to add a constraint on the left: the
  /// first column the widget (in the order of the constraint_reference_ids)
  /// covers, -1 when it has no cell, or 0 when [i] is out of range.
  int leftOfWidget(int i) {
    final constraintMatrix = _constraintMatrix;
    if (constraintMatrix == null || i >= constraintMatrix.length) {
      return 0;
    }
    return constraintMatrix[i][0];
  }

  /// Get the boxView for the widget [i] to add a constraint on the top: the
  /// first row it covers (see [leftOfWidget]).
  int topOfWidget(int i) {
    final constraintMatrix = _constraintMatrix;
    if (constraintMatrix == null || i >= constraintMatrix.length) {
      return 0;
    }
    return constraintMatrix[i][1];
  }

  /// Get the boxView for the widget [i] to add a constraint on the right: the
  /// last column it covers (see [leftOfWidget]).
  int rightOfWidget(int i) {
    final constraintMatrix = _constraintMatrix;
    if (constraintMatrix == null || i >= constraintMatrix.length) {
      return 0;
    }
    return constraintMatrix[i][2];
  }

  /// Get the boxView for the widget [i] to add a constraint on the bottom:
  /// the last row it covers (see [leftOfWidget]).
  int bottomOfWidget(int i) {
    final constraintMatrix = _constraintMatrix;
    if (constraintMatrix == null || i >= constraintMatrix.length) {
      return 0;
    }
    return constraintMatrix[i][3];
  }
}
