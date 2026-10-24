import 'package:flutter/foundation.dart';

/// Which edge of the target a [HorizontalLink] points at.
enum HorizontalEdge { left, right, start, end }

/// Which edge of the target a [VerticalLink] points at.
enum VerticalEdge { top, bottom, baseline }

/// Positions one of a widget's horizontal edges (left, right, start, end)
/// against a target's edge. Used by the `left`, `right`, `start`, and `end`
/// parameters of `Constrained`.
///
/// The parameter names *this* widget's edge; the constructor names the
/// *target's* edge:
///
/// ```dart
/// start: .endOf(#label, margin: 8),  // my start edge, at label's end edge, +8
/// ```
@immutable
class HorizontalLink {
  /// Align to the target's left edge (absolute).
  const HorizontalLink.leftOf(this.target, {this.margin = 0, this.goneMargin = 0})
      : edge = HorizontalEdge.left;

  /// Align to the target's right edge (absolute).
  const HorizontalLink.rightOf(this.target, {this.margin = 0, this.goneMargin = 0})
      : edge = HorizontalEdge.right;

  /// Align to the target's start edge (RTL-aware).
  const HorizontalLink.startOf(this.target, {this.margin = 0, this.goneMargin = 0})
      : edge = HorizontalEdge.start;

  /// Align to the target's end edge (RTL-aware).
  const HorizontalLink.endOf(this.target, {this.margin = 0, this.goneMargin = 0})
      : edge = HorizontalEdge.end;

  /// The id of the target (a sibling, or `parent`).
  final Symbol target;

  /// Which edge of [target] to align to.
  final HorizontalEdge edge;

  /// Gap in logical pixels between this edge and the target edge.
  final double margin;

  /// Margin used instead of [margin] when the target is gone.
  final double goneMargin;

  @override
  bool operator ==(Object other) =>
      other is HorizontalLink &&
      other.target == target &&
      other.edge == edge &&
      other.margin == margin &&
      other.goneMargin == goneMargin;

  @override
  int get hashCode => Object.hash(target, edge, margin, goneMargin);
}

/// Positions one of a widget's vertical edges (top, bottom, baseline) against a
/// target's edge. Used by the `top`, `bottom`, and `baseline` parameters of
/// `Constrained`.
///
/// ```dart
/// top: .bottomOf(#header, margin: 8),  // my top edge, at header's bottom, +8
/// ```
@immutable
class VerticalLink {
  /// Align to the target's top edge.
  const VerticalLink.topOf(this.target, {this.margin = 0, this.goneMargin = 0})
      : edge = VerticalEdge.top;

  /// Align to the target's bottom edge.
  const VerticalLink.bottomOf(this.target, {this.margin = 0, this.goneMargin = 0})
      : edge = VerticalEdge.bottom;

  /// Align to the target's text baseline.
  const VerticalLink.baselineOf(
    this.target, {
    this.margin = 0,
    this.goneMargin = 0,
  }) : edge = VerticalEdge.baseline;

  /// The id of the target (a sibling, or `parent`).
  final Symbol target;

  /// Which edge of [target] to align to.
  final VerticalEdge edge;

  /// Gap in logical pixels between this edge and the target edge.
  final double margin;

  /// Margin used instead of [margin] when the target is gone.
  final double goneMargin;

  @override
  bool operator ==(Object other) =>
      other is VerticalLink &&
      other.target == target &&
      other.edge == edge &&
      other.margin == margin &&
      other.goneMargin == goneMargin;

  @override
  int get hashCode => Object.hash(target, edge, margin, goneMargin);
}

/// Positions a widget's center on a circle around a target's center. Used by
/// the `circle` parameter of `Constrained`. Android's
/// `layout_constraintCircle`.
///
/// ```dart
/// circle: .around(#hub, angle: 45, radius: 96),
/// ```
@immutable
class CircularLink {
  /// Centers this widget at [angle] degrees (clockwise, 0 = straight up) and
  /// [radius] logical pixels from the center of [target].
  const CircularLink.around(
    this.target, {
    required this.angle,
    required this.radius,
  });

  /// The id of the target (a sibling, or `parent`).
  final Symbol target;

  /// Angle in degrees, clockwise, with 0 pointing straight up.
  final double angle;

  /// Distance between the two centers in logical pixels.
  final double radius;

  @override
  bool operator ==(Object other) =>
      other is CircularLink &&
      other.target == target &&
      other.angle == angle &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(target, angle, radius);
}
