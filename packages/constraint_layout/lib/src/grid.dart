import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'constraint_layout.dart';
import 'constraint_parent_data.dart';
import 'dimension.dart';
import 'link.dart';
import 'types.dart';

/// A virtual layout inside a [ConstraintLayout] that arranges the widgets in
/// [referenced] in a grid of [rows] x [columns]. Android's `Grid` helper.
///
/// The grid itself is positioned and sized like a `Constrained` child (links,
/// [width], [height]); the referenced widgets remain siblings and are placed
/// into the grid's cells in order. [spans] and [skips] use Android's
/// `"index:RxC"` format (for example `spans: '0:1x2'` makes the first cell
/// span two columns).
///
/// ```dart
/// ConstraintGrid(
///   id: #board,
///   referenced: [#a, #b, #c, #d],
///   rows: 2,
///   columns: 2,
///   start: .startOf(parent),
///   end: .endOf(parent),
///   top: .topOf(parent),
///   bottom: .bottomOf(parent),
///   width: .matchConstraint,
///   height: .matchConstraint,
/// ),
/// ```
class ConstraintGrid extends ParentDataWidget<ConstraintParentData> {
  /// Creates a grid arranging [referenced].
  const ConstraintGrid({
    required this.id,
    required this.referenced,
    super.key,
    this.rows,
    this.columns,
    this.orientation = Axis.horizontal,
    this.left,
    this.right,
    this.start,
    this.end,
    this.top,
    this.bottom,
    this.horizontalBias = 0.5,
    this.verticalBias = 0.5,
    this.width = .matchConstraint,
    this.height = .matchConstraint,
    this.horizontalGap = 0,
    this.verticalGap = 0,
    this.rowWeights,
    this.columnWeights,
    this.spans,
    this.skips,
    this.visibility = .visible,
  }) : super(child: const SizedBox.shrink());

  /// Unique id for this grid within its [ConstraintLayout].
  final Symbol id;

  /// Ids of the sibling widgets this grid arranges, in cell order.
  final List<Symbol> referenced;

  /// Number of rows; null derives it from [columns] and the widget count.
  final int? rows;

  /// Number of columns; null derives it from [rows] and the widget count.
  final int? columns;

  /// The axis along which widgets fill the cells (horizontal fills row by
  /// row).
  final Axis orientation;

  /// Positions this grid's left edge (absolute).
  final HorizontalLink? left;

  /// Positions this grid's right edge (absolute).
  final HorizontalLink? right;

  /// Positions this grid's start edge (RTL-aware).
  final HorizontalLink? start;

  /// Positions this grid's end edge (RTL-aware).
  final HorizontalLink? end;

  /// Positions this grid's top edge.
  final VerticalLink? top;

  /// Positions this grid's bottom edge.
  final VerticalLink? bottom;

  /// Horizontal position of the grid itself between opposing links.
  final double horizontalBias;

  /// Vertical position of the grid itself between opposing links.
  final double verticalBias;

  /// How the grid's width is determined.
  final Dimension width;

  /// How the grid's height is determined.
  final Dimension height;

  /// Gap in logical pixels between columns.
  final double horizontalGap;

  /// Gap in logical pixels between rows.
  final double verticalGap;

  /// Relative row heights (one entry per row), or null for equal rows.
  final List<double>? rowWeights;

  /// Relative column widths (one entry per column), or null for equal
  /// columns.
  final List<double>? columnWeights;

  /// Spans in Android's `index:RxC` format (`'0:2x1, 4:1x2'`), or null.
  final String? spans;

  /// Skipped cells in Android's `index:RxC` format, or null.
  final String? skips;

  /// Whether this grid (and its arrangement) is laid out and drawn.
  final ConstraintVisibility visibility;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as ConstraintParentData;
    var changed = false;

    void update<T>(T value, T current, void Function(T) write) {
      if (current != value) {
        write(value);
        changed = true;
      }
    }

    update(id, data.id, (v) => data.id = v);
    update(HelperKind.grid, data.helperKind, (v) => data.helperKind = v);
    if (!listEquals(data.gridReferenced, referenced)) {
      data.gridReferenced = referenced;
      changed = true;
    }
    update(rows, data.gridRows, (v) => data.gridRows = v);
    update(columns, data.gridColumns, (v) => data.gridColumns = v);
    update(orientation, data.gridOrientation, (v) => data.gridOrientation = v);
    update(left, data.left, (v) => data.left = v);
    update(right, data.right, (v) => data.right = v);
    update(start, data.start, (v) => data.start = v);
    update(end, data.end, (v) => data.end = v);
    update(top, data.top, (v) => data.top = v);
    update(bottom, data.bottom, (v) => data.bottom = v);
    update(horizontalBias, data.horizontalBias, (v) => data.horizontalBias = v);
    update(verticalBias, data.verticalBias, (v) => data.verticalBias = v);
    update(width, data.width, (v) => data.width = v);
    update(height, data.height, (v) => data.height = v);
    update(horizontalGap, data.gridHorizontalGap,
        (v) => data.gridHorizontalGap = v);
    update(verticalGap, data.gridVerticalGap, (v) => data.gridVerticalGap = v);
    if (!listEquals(data.gridRowWeights, rowWeights)) {
      data.gridRowWeights = rowWeights;
      changed = true;
    }
    if (!listEquals(data.gridColumnWeights, columnWeights)) {
      data.gridColumnWeights = columnWeights;
      changed = true;
    }
    update(spans, data.gridSpans, (v) => data.gridSpans = v);
    update(skips, data.gridSkips, (v) => data.gridSkips = v);
    update(visibility, data.visibility, (v) => data.visibility = v);

    // Helper configuration is applied at model-build time, so any change is
    // structural: it forces a rebuild rather than an in-place update.
    if (changed) {
      data.configDirty = true;
      data.structuralDirty = true;
      final targetParent = renderObject.parent;
      if (targetParent is RenderObject) {
        targetParent.markNeedsLayout();
      }
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => ConstraintLayout;
}
