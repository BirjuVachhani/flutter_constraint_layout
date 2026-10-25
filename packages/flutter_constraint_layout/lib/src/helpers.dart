import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'constraint_layout.dart';
import 'constraint_parent_data.dart';
import 'types.dart';

/// An invisible anchor line inside a [ConstraintLayout] that siblings can
/// link to by [id], at a fixed distance from an edge or at a fraction of the
/// layout's size. Android's `Guideline`.
///
/// A *vertical* guideline is a vertical line: siblings anchor their
/// horizontal edges to it. Exactly one of `begin`, `end`, or `percent` must
/// be given. As on Android, a vertical guideline mirrors in a right-to-left
/// layout: `begin` and `percent` are then measured from the right edge and
/// `end` from the left. A horizontal guideline is placed the same way in both
/// text directions.
///
/// ```dart
/// Guideline.vertical(id: #middle, percent: 0.5),
/// Constrained(id: #a, start: .rightOf(#middle), ...),
/// ```
class Guideline extends ParentDataWidget<ConstraintParentData> {
  /// A vertical line at [begin] from the left, [end] from the right, or
  /// [percent] of the layout's width from the left. In a right-to-left layout
  /// the edges swap: [begin] and [percent] measure from the right and [end]
  /// from the left.
  const Guideline.vertical({
    required this.id,
    super.key,
    this.begin,
    this.end,
    this.percent,
  }) : axis = Axis.vertical,
       assert(
         (begin != null ? 1 : 0) +
                 (end != null ? 1 : 0) +
                 (percent != null ? 1 : 0) ==
             1,
         'Provide exactly one of begin, end, or percent.',
       ),
       super(child: const SizedBox.shrink());

  /// A horizontal line at [begin] from the top, [end] from the bottom, or
  /// [percent] of the layout's height.
  const Guideline.horizontal({
    required this.id,
    super.key,
    this.begin,
    this.end,
    this.percent,
  }) : axis = Axis.horizontal,
       assert(
         (begin != null ? 1 : 0) +
                 (end != null ? 1 : 0) +
                 (percent != null ? 1 : 0) ==
             1,
         'Provide exactly one of begin, end, or percent.',
       ),
       super(child: const SizedBox.shrink());

  /// Unique id siblings use to link to this guideline.
  final Symbol id;

  /// The axis of the line itself.
  final Axis axis;

  /// Distance in logical pixels from the left (vertical) or top (horizontal)
  /// edge. A vertical guideline in a right-to-left layout measures it from
  /// the right.
  final double? begin;

  /// Distance in logical pixels from the right (vertical) or bottom
  /// (horizontal) edge. A vertical guideline in a right-to-left layout
  /// measures it from the left.
  final double? end;

  /// Position as a fraction (0..1) of the layout's size on the cross axis,
  /// from the left (vertical) or top (horizontal) edge. A vertical guideline
  /// in a right-to-left layout measures it from the right.
  final double? percent;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as ConstraintParentData;
    var changed = false;

    if (data.id != id) {
      data.id = id;
      changed = true;
    }
    if (data.helperKind != HelperKind.guideline) {
      data.helperKind = HelperKind.guideline;
      changed = true;
    }
    if (data.guidelineAxis != axis) {
      data.guidelineAxis = axis;
      changed = true;
    }
    if (data.guidelineBegin != begin) {
      data.guidelineBegin = begin;
      changed = true;
    }
    if (data.guidelineEnd != end) {
      data.guidelineEnd = end;
      changed = true;
    }
    if (data.guidelinePercent != percent) {
      data.guidelinePercent = percent;
      changed = true;
    }

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

/// An invisible anchor line inside a [ConstraintLayout] that tracks an edge
/// of the widgets in [referenced], so siblings can constrain against
/// "whichever of these sticks out furthest". Android's `Barrier`.
///
/// ```dart
/// Barrier(id: #labelsEnd, edge: .end, referenced: [#name, #email]),
/// Constrained(id: #value, start: .rightOf(#labelsEnd, margin: 8), ...),
/// ```
class Barrier extends ParentDataWidget<ConstraintParentData> {
  /// Creates a barrier tracking [edge] of the widgets in [referenced].
  const Barrier({
    required this.id,
    required this.edge,
    required this.referenced,
    super.key,
    this.margin = 0,
    this.allowsGone = true,
  }) : super(child: const SizedBox.shrink());

  /// Unique id siblings use to link to this barrier.
  final Symbol id;

  /// Which edge of the referenced widgets to track.
  final BarrierEdge edge;

  /// Ids of the widgets whose edges the barrier tracks.
  final List<Symbol> referenced;

  /// Offset in logical pixels added to the barrier's position.
  ///
  /// For a `.left`, `.right`, `.top`, or `.bottom` barrier, a positive value
  /// moves it right or down in both text directions: past the tracked edge of
  /// a right or bottom barrier, back over the referenced widgets for a left
  /// or top one.
  ///
  /// A `.start` or `.end` barrier applies the margin along the text
  /// direction, like its edge: a positive value moves it toward the end,
  /// which is right in left-to-right text and left in right-to-left text. So
  /// a positive margin always moves an `.end` barrier past the referenced
  /// widgets and a `.start` barrier back over them, and a right-to-left
  /// layout is the exact mirror of its left-to-right twin. This is a
  /// deliberate difference from Android, where a positive margin moves every
  /// barrier right or down.
  final double margin;

  /// Whether gone widgets still contribute their (collapsed) position.
  final bool allowsGone;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as ConstraintParentData;
    var changed = false;

    if (data.id != id) {
      data.id = id;
      changed = true;
    }
    if (data.helperKind != HelperKind.barrier) {
      data.helperKind = HelperKind.barrier;
      changed = true;
    }
    if (data.barrierEdge != edge) {
      data.barrierEdge = edge;
      changed = true;
    }
    if (!listEquals(data.barrierReferenced, referenced)) {
      data.barrierReferenced = referenced;
      changed = true;
    }
    if (data.barrierMargin != margin) {
      data.barrierMargin = margin;
      changed = true;
    }
    if (data.barrierAllowsGone != allowsGone) {
      data.barrierAllowsGone = allowsGone;
      changed = true;
    }

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

/// Sets the visibility of the widgets in [referenced] all at once. Android's
/// `Group`.
///
/// The group's [visibility] replaces the referenced children's own: a `.gone`
/// group collapses every referenced child, even one declared `.visible`, and
/// a `.visible` group shows them all. When several groups reference the same
/// child, the group that comes last in the layout's children wins.
///
/// A group has no position or size and takes no part in the layout, so it
/// cannot be the target of a link or the `referenced` entry of a barrier,
/// flow, or grid. It can reference a `Constrained` child, a
/// `ConstraintFlow`, or a `ConstraintGrid`. Guidelines and barriers have no
/// visibility, so a group leaves them as they are.
///
/// ```dart
/// ConstraintGroup(
///   id: #details,
///   referenced: [#address, #phone],
///   visibility: showDetails ? .visible : .gone,
/// ),
/// ```
class ConstraintGroup extends ParentDataWidget<ConstraintParentData> {
  /// Creates a group that gives the widgets in [referenced] its [visibility].
  const ConstraintGroup({
    required this.id,
    required this.referenced,
    super.key,
    this.visibility = .visible,
  }) : super(child: const SizedBox.shrink());

  /// Unique id for this group within its [ConstraintLayout].
  final Symbol id;

  /// Ids of the widgets whose visibility this group sets.
  final List<Symbol> referenced;

  /// The visibility given to every widget in [referenced], in place of its
  /// own. See [ConstraintVisibility].
  final ConstraintVisibility visibility;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as ConstraintParentData;
    var structural = false;

    if (data.id != id) {
      data.id = id;
      structural = true;
    }
    if (data.helperKind != HelperKind.group) {
      data.helperKind = HelperKind.group;
      structural = true;
    }
    if (!listEquals(data.groupReferenced, referenced)) {
      data.groupReferenced = referenced;
      structural = true;
    }
    // A visibility change alone is not structural: the layout passes it on to
    // each referenced child as a change of that child's own visibility.
    final visibilityChanged = data.groupVisibility != visibility;
    if (visibilityChanged) {
      data.groupVisibility = visibility;
    }

    if (structural || visibilityChanged) {
      data.configDirty = true;
      if (structural) {
        data.structuralDirty = true;
      }
      final targetParent = renderObject.parent;
      if (targetParent is RenderObject) {
        targetParent.markNeedsLayout();
      }
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => ConstraintLayout;
}
