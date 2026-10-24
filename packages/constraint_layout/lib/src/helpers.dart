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
/// be given. `begin`/`end` are absolute (measured from the left/right or
/// top/bottom edge, not RTL-aware), matching Android.
///
/// ```dart
/// Guideline.vertical(id: #middle, percent: 0.5),
/// Constrained(id: #a, start: .rightOf(#middle), ...),
/// ```
class Guideline extends ParentDataWidget<ConstraintParentData> {
  /// A vertical line at [begin] from the left, [end] from the right, or
  /// [percent] of the layout's width.
  const Guideline.vertical({
    required this.id,
    super.key,
    this.begin,
    this.end,
    this.percent,
  })  : axis = Axis.vertical,
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
  })  : axis = Axis.horizontal,
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
  /// edge.
  final double? begin;

  /// Distance in logical pixels from the right (vertical) or bottom
  /// (horizontal) edge.
  final double? end;

  /// Position as a fraction (0..1) of the layout's size on the cross axis.
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

  /// Offset in logical pixels added past the tracked edge.
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
