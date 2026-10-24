import 'package:flutter/widgets.dart';

import 'constraint_layout.dart';
import 'constraint_parent_data.dart';
import 'dimension.dart';
import 'link.dart';
import 'types.dart';

/// Attaches constraint configuration to a single child of a [ConstraintLayout].
///
/// Each edge parameter takes a link built with a `...Of` constructor that names
/// the target's edge. The parameter is *this* widget's edge, so
/// `top: .bottomOf(#header)` places this widget's top at `#header`'s bottom.
/// Targets are a sibling id or [parent]. Margins live on the link.
///
/// ```dart
/// Constrained(
///   id: #title,
///   top: .topOf(parent, margin: 32),
///   start: .startOf(parent),
///   end: .endOf(parent),
///   child: Text('Hello'),
/// )
/// ```
class Constrained extends ParentDataWidget<ConstraintParentData> {
  /// Creates constraint configuration for [child].
  const Constrained({
    required this.id,
    required super.child,
    super.key,
    this.left,
    this.right,
    this.start,
    this.end,
    this.top,
    this.bottom,
    this.baseline,
    this.circle,
    this.horizontalBias = 0.5,
    this.verticalBias = 0.5,
    this.width = .wrapContent,
    this.height = .wrapContent,
    this.aspectRatio,
    this.horizontalChainStyle,
    this.verticalChainStyle,
    this.horizontalWeight,
    this.verticalWeight,
    this.zIndex,
    this.visibility = .visible,
  });

  /// Unique id for this child within its [ConstraintLayout].
  final Symbol id;

  /// Positions this widget's left edge (absolute).
  final HorizontalLink? left;

  /// Positions this widget's right edge (absolute).
  final HorizontalLink? right;

  /// Positions this widget's start edge (RTL-aware).
  final HorizontalLink? start;

  /// Positions this widget's end edge (RTL-aware).
  final HorizontalLink? end;

  /// Positions this widget's top edge.
  final VerticalLink? top;

  /// Positions this widget's bottom edge.
  final VerticalLink? bottom;

  /// Positions this widget's text baseline.
  final VerticalLink? baseline;

  /// Centers this widget on a circle around a target's center.
  final CircularLink? circle;

  /// Horizontal position between opposing links: 0.0 = start, 1.0 = end.
  final double horizontalBias;

  /// Vertical position between opposing links: 0.0 = top, 1.0 = bottom.
  final double verticalBias;

  /// How the width is determined.
  final Dimension width;

  /// How the height is determined.
  final Dimension height;

  /// Enforced `width / height` ratio; derives one dimension from the other.
  final double? aspectRatio;

  /// Chain style applied when this child heads a horizontal chain. A chain
  /// forms when consecutive children link to each other bidirectionally; the
  /// style set on the head member governs the whole chain. Defaults to
  /// [ChainStyle.spread].
  final ChainStyle? horizontalChainStyle;

  /// Chain style applied when this child heads a vertical chain. See
  /// [horizontalChainStyle].
  final ChainStyle? verticalChainStyle;

  /// Relative share of leftover space this child takes in a weighted
  /// horizontal chain. Only applies to members whose [width] is a
  /// match-constraint mode.
  final double? horizontalWeight;

  /// Relative share of leftover space this child takes in a weighted vertical
  /// chain. Only applies to members whose [height] is a match-constraint mode.
  final double? verticalWeight;

  /// Paint order override; higher paints on top. Defaults to child order.
  final int? zIndex;

  /// Whether this child is laid out and drawn. See [ConstraintVisibility].
  final ConstraintVisibility visibility;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as ConstraintParentData;
    var structural = false;
    var needsLayout = false;
    var needsPaint = false;

    if (data.id != id) {
      data.id = id;
      structural = true;
    }
    // The same render object can survive a switch from Guideline/Barrier to
    // Constrained (their child subtrees can share a type), so the helper kind
    // must be reclaimed here.
    if (data.helperKind != HelperKind.none) {
      data.helperKind = HelperKind.none;
      structural = true;
    }
    if (data.left != left) {
      data.left = left;
      needsLayout = true;
    }
    if (data.right != right) {
      data.right = right;
      needsLayout = true;
    }
    if (data.start != start) {
      data.start = start;
      needsLayout = true;
    }
    if (data.end != end) {
      data.end = end;
      needsLayout = true;
    }
    if (data.top != top) {
      data.top = top;
      needsLayout = true;
    }
    if (data.bottom != bottom) {
      data.bottom = bottom;
      needsLayout = true;
    }
    if (data.baseline != baseline) {
      data.baseline = baseline;
      needsLayout = true;
    }
    if (data.circle != circle) {
      data.circle = circle;
      needsLayout = true;
    }
    if (data.horizontalBias != horizontalBias) {
      data.horizontalBias = horizontalBias;
      needsLayout = true;
    }
    if (data.verticalBias != verticalBias) {
      data.verticalBias = verticalBias;
      needsLayout = true;
    }
    if (data.width != width) {
      data.width = width;
      needsLayout = true;
    }
    if (data.height != height) {
      data.height = height;
      needsLayout = true;
    }
    if (data.aspectRatio != aspectRatio) {
      data.aspectRatio = aspectRatio;
      needsLayout = true;
    }
    if (data.horizontalChainStyle != horizontalChainStyle) {
      data.horizontalChainStyle = horizontalChainStyle;
      needsLayout = true;
    }
    if (data.verticalChainStyle != verticalChainStyle) {
      data.verticalChainStyle = verticalChainStyle;
      needsLayout = true;
    }
    if (data.horizontalWeight != horizontalWeight) {
      data.horizontalWeight = horizontalWeight;
      needsLayout = true;
    }
    if (data.verticalWeight != verticalWeight) {
      data.verticalWeight = verticalWeight;
      needsLayout = true;
    }
    if (data.visibility != visibility) {
      data.visibility = visibility;
      needsLayout = true;
    }
    // zIndex only affects paint and hit-test order, which are read live from
    // parent data, so it never invalidates layout or the engine model.
    if (data.zIndex != zIndex) {
      data.zIndex = zIndex;
      needsPaint = true;
    }

    final targetParent = renderObject.parent;
    if (structural || needsLayout) {
      data.configDirty = true;
      if (structural) {
        data.structuralDirty = true;
      }
      if (targetParent is RenderObject) {
        targetParent.markNeedsLayout();
      }
    } else if (needsPaint) {
      if (targetParent is RenderObject) {
        targetParent.markNeedsPaint();
      }
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => ConstraintLayout;
}
