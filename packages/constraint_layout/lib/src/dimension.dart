import 'package:flutter/foundation.dart';

/// Describes how a single dimension (width or height) of a `Constrained` child
/// is sized.
///
/// This is a sealed hierarchy, so a `switch` over a [Dimension] is exhaustive.
/// Construct values with the helper constructors on the root class:
///
/// ```dart
/// width: .matchConstraint,
/// height: .fixed(48),
/// width: .percent(0.5),
/// width: .spread(min: 100, max: 400),
/// ```
///
/// and match on them exhaustively:
///
/// ```dart
/// final double? resolved = switch (dimension) {
///   WrapContentDimension() => null,
///   MatchParentDimension() => parentSize,
///   MatchConstraintDimension() => spread,
///   FixedDimension(:final pixels) => pixels,
/// };
/// ```
@immutable
sealed class Dimension {
  const Dimension();

  /// Size to the child's own content. Android `wrap_content`.
  static const WrapContentDimension wrapContent = WrapContentDimension._();

  /// Fill the `ConstraintLayout`. Android `match_parent`.
  static const MatchParentDimension matchParent = MatchParentDimension._();

  /// Fill the space between the two opposing anchors. Android `0dp`.
  ///
  /// Requires both opposing anchors on the axis (start and end, or top and
  /// bottom).
  static const MatchConstraintDimension matchConstraint =
      MatchConstraintDimension._();

  /// An exact size in logical pixels.
  const factory Dimension.fixed(double pixels) = FixedDimension;

  /// Fill the space between the two opposing anchors, optionally bounded.
  ///
  /// The same as [matchConstraint] with an optional [min] and [max] size in
  /// logical pixels. Android `0dp` with `layout_constraintWidth_min` /
  /// `layout_constraintWidth_max`.
  const factory Dimension.spread({double? min, double? max}) =
      MatchConstraintDimension.spread;

  /// Size to the child's content, but never beyond the space between the two
  /// opposing anchors, optionally bounded by [min] and [max].
  ///
  /// Android `0dp` with `layout_constraintWidth_default="wrap"`: unlike plain
  /// [wrapContent], the content size is capped by the constraints.
  const factory Dimension.constrainedWrap({double? min, double? max}) =
      MatchConstraintDimension.constrainedWrap;

  /// A fraction of the parent `ConstraintLayout`'s size on this axis,
  /// optionally bounded by [min] and [max].
  ///
  /// [fraction] is between 0 and 1. Requires both opposing anchors on the
  /// axis. Android `0dp` with `layout_constraintWidth_percent`.
  const factory Dimension.percent(double fraction,
      {double? min, double? max}) = MatchConstraintDimension.percent;
}

/// Sizes to the child's own content. See [Dimension.wrapContent].
final class WrapContentDimension extends Dimension {
  const WrapContentDimension._();

  @override
  String toString() => 'Dimension.wrapContent';
}

/// Fills the `ConstraintLayout`. See [Dimension.matchParent].
final class MatchParentDimension extends Dimension {
  /// Creates a match-parent dimension.
  const MatchParentDimension._();

  @override
  String toString() => 'Dimension.matchParent';
}

/// Fills the space between the two opposing anchors, with optional bounds,
/// wrap behaviour, or percent sizing.
/// See [Dimension.matchConstraint], [Dimension.spread],
/// [Dimension.constrainedWrap], and [Dimension.percent].
final class MatchConstraintDimension extends Dimension {
  const MatchConstraintDimension._()
      : min = null,
        max = null,
        percent = null,
        wrap = false;

  /// Creates a spread match-constraint dimension. See [Dimension.spread].
  const MatchConstraintDimension.spread({this.min, this.max})
      : percent = null,
        wrap = false;

  /// Creates a constrained-wrap dimension. See [Dimension.constrainedWrap].
  const MatchConstraintDimension.constrainedWrap({this.min, this.max})
      : percent = null,
        wrap = true;

  /// Creates a percent-of-parent dimension. See [Dimension.percent].
  const MatchConstraintDimension.percent(double fraction,
      {this.min, this.max})
      : percent = fraction,
        wrap = false;

  /// Minimum size in logical pixels, or null for no minimum.
  final double? min;

  /// Maximum size in logical pixels, or null for no maximum.
  final double? max;

  /// Fraction of the parent size on this axis, or null for spread/wrap.
  final double? percent;

  /// When true, sizes to content capped by the constraints instead of
  /// spreading.
  final bool wrap;

  @override
  bool operator ==(Object other) =>
      other is MatchConstraintDimension &&
      other.min == min &&
      other.max == max &&
      other.percent == percent &&
      other.wrap == wrap;

  @override
  int get hashCode => Object.hash(min, max, percent, wrap);

  @override
  String toString() {
    final bounds = [
      if (min != null) 'min: $min',
      if (max != null) 'max: $max',
    ].join(', ');
    if (percent != null) {
      return 'Dimension.percent($percent${bounds.isEmpty ? '' : ', $bounds'})';
    }
    if (wrap) return 'Dimension.constrainedWrap($bounds)';
    if (bounds.isEmpty) return 'Dimension.matchConstraint';
    return 'Dimension.spread($bounds)';
  }
}

/// An exact size in logical pixels. See [Dimension.fixed].
final class FixedDimension extends Dimension {
  /// Creates a fixed dimension of [pixels] logical pixels.
  const FixedDimension(this.pixels);

  /// The size in logical pixels.
  final double pixels;

  @override
  bool operator ==(Object other) =>
      other is FixedDimension && other.pixels == pixels;

  @override
  int get hashCode => pixels.hashCode;

  @override
  String toString() => 'Dimension.fixed($pixels)';
}
