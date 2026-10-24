import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' hide Flow;

import 'constraint_layout.dart';
import 'constraint_parent_data.dart';
import 'dimension.dart';
import 'link.dart';
import 'types.dart';

/// A virtual layout inside a [ConstraintLayout] that arranges the widgets in
/// [referenced] in one or more chains, wrapping when it runs out of space.
/// Android's `Flow`.
///
/// The flow itself is positioned and sized like a `Constrained` child (links,
/// [width], [height]); the referenced widgets remain siblings and are moved
/// by the flow, so they can still be targeted by other constraints.
///
/// ```dart
/// ConstraintFlow(
///   id: #tags,
///   referenced: [#a, #b, #c],
///   start: .startOf(parent),
///   end: .endOf(parent),
///   top: .topOf(parent),
///   width: .matchConstraint,
///   wrap: .chain,
///   horizontalGap: 8,
///   verticalGap: 8,
/// ),
/// ```
class ConstraintFlow extends ParentDataWidget<ConstraintParentData> {
  /// Creates a flow arranging [referenced] along [orientation].
  const ConstraintFlow({
    required this.id,
    required this.referenced,
    super.key,
    this.orientation = Axis.horizontal,
    this.left,
    this.right,
    this.start,
    this.end,
    this.top,
    this.bottom,
    this.horizontalBias = 0.5,
    this.verticalBias = 0.5,
    this.width = .wrapContent,
    this.height = .wrapContent,
    this.wrap = FlowWrap.none,
    this.horizontalGap = 0,
    this.verticalGap = 0,
    this.horizontalChainStyle,
    this.verticalChainStyle,
    this.contentHorizontalBias = 0.5,
    this.contentVerticalBias = 0.5,
    this.horizontalAlign = FlowHorizontalAlign.center,
    this.verticalAlign = FlowVerticalAlign.center,
    this.maxElementsWrap,
    this.padding = 0,
    this.visibility = .visible,
  }) : super(child: const SizedBox.shrink());

  /// Unique id for this flow within its [ConstraintLayout].
  final Symbol id;

  /// Ids of the sibling widgets this flow arranges, in order.
  final List<Symbol> referenced;

  /// The main axis widgets are laid out along.
  final Axis orientation;

  /// Positions this flow's left edge (absolute).
  final HorizontalLink? left;

  /// Positions this flow's right edge (absolute).
  final HorizontalLink? right;

  /// Positions this flow's start edge (RTL-aware).
  final HorizontalLink? start;

  /// Positions this flow's end edge (RTL-aware).
  final HorizontalLink? end;

  /// Positions this flow's top edge.
  final VerticalLink? top;

  /// Positions this flow's bottom edge.
  final VerticalLink? bottom;

  /// Horizontal position of the flow itself between opposing links.
  final double horizontalBias;

  /// Vertical position of the flow itself between opposing links.
  final double verticalBias;

  /// How the flow's width is determined.
  final Dimension width;

  /// How the flow's height is determined.
  final Dimension height;

  /// Wrap behaviour when the main axis overflows.
  final FlowWrap wrap;

  /// Gap in logical pixels between widgets on the horizontal axis.
  final double horizontalGap;

  /// Gap in logical pixels between widgets on the vertical axis.
  final double verticalGap;

  /// Chain style of the horizontal chains the flow creates.
  final ChainStyle? horizontalChainStyle;

  /// Chain style of the vertical chains the flow creates.
  final ChainStyle? verticalChainStyle;

  /// Bias of the horizontal chains the flow creates (for packed chains).
  final double contentHorizontalBias;

  /// Bias of the vertical chains the flow creates (for packed chains).
  final double contentVerticalBias;

  /// Cross-axis alignment of widgets within a column.
  final FlowHorizontalAlign horizontalAlign;

  /// Cross-axis alignment of widgets within a row.
  final FlowVerticalAlign verticalAlign;

  /// Maximum number of widgets per chain before wrapping, or null for as many
  /// as fit.
  final int? maxElementsWrap;

  /// Padding in logical pixels inside the flow's bounds, on all sides.
  final double padding;

  /// Whether this flow (and its arrangement) is laid out and drawn.
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
    update(HelperKind.flow, data.helperKind, (v) => data.helperKind = v);
    if (!listEquals(data.flowReferenced, referenced)) {
      data.flowReferenced = referenced;
      changed = true;
    }
    update(orientation, data.flowOrientation, (v) => data.flowOrientation = v);
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
    update(wrap, data.flowWrap, (v) => data.flowWrap = v);
    update(horizontalGap, data.flowHorizontalGap,
        (v) => data.flowHorizontalGap = v);
    update(verticalGap, data.flowVerticalGap, (v) => data.flowVerticalGap = v);
    update(horizontalChainStyle, data.flowHorizontalStyle,
        (v) => data.flowHorizontalStyle = v);
    update(verticalChainStyle, data.flowVerticalStyle,
        (v) => data.flowVerticalStyle = v);
    update(contentHorizontalBias, data.flowHorizontalBias,
        (v) => data.flowHorizontalBias = v);
    update(contentVerticalBias, data.flowVerticalBias,
        (v) => data.flowVerticalBias = v);
    update(horizontalAlign, data.flowHorizontalAlign,
        (v) => data.flowHorizontalAlign = v);
    update(verticalAlign, data.flowVerticalAlign,
        (v) => data.flowVerticalAlign = v);
    update(maxElementsWrap, data.flowMaxElementsWrap,
        (v) => data.flowMaxElementsWrap = v);
    update(padding, data.flowPadding, (v) => data.flowPadding = v);
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
