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
  ///
  /// The child is measured under the layout's size on the axis: up to that
  /// size where the layout is bounded, and with unbounded constraints where it
  /// is not (inside a scroll view, say). Its size rounds up to whole logical
  /// pixels, as `max(0, (v - 0.001).ceil())`: an Android view measures in
  /// whole pixels, and a text 99.4 wide is placed 100 wide rather than
  /// clipped at 99.
  static const WrapContentDimension wrapContent = WrapContentDimension._();

  /// Fill the `ConstraintLayout`. Android `match_parent`.
  ///
  /// Measured as Android measures `match_parent`: where the layout is bounded
  /// on the axis, at the layout's size less the child's margins on that axis
  /// (the margins of its links there). Where the layout is unbounded on the
  /// axis (inside a scroll view, say), there is no size to fill: the child is
  /// measured with unbounded constraints, as Android measures `match_parent`
  /// under an UNSPECIFIED measure spec, and takes its own size, rounded up to
  /// whole logical pixels as [wrapContent]'s is. A child that cannot size
  /// itself under unbounded constraints (a vertical `ListView` on an unbounded
  /// height, a `TextField` across an unbounded width) then fails the layout
  /// with an error that names the child and the axis, in every build. Give
  /// such a child a [Dimension.fixed] size on that axis, bound the layout, or
  /// use a child that sizes itself there (a `ListView` with `shrinkWrap`). The
  /// same holds for [wrapContent], and for a match-constraint size measured
  /// for its content on an unbounded axis.
  static const MatchParentDimension matchParent = MatchParentDimension._();

  /// Fill the space between the two opposing anchors. Android `0dp`.
  ///
  /// Needs both opposing anchors on the axis (start and end, or top and
  /// bottom) to fill anything: with only one of them, the child sizes to its
  /// content. A content size rounds up to whole logical pixels, as
  /// [wrapContent]'s does.
  static const MatchConstraintDimension matchConstraint =
      MatchConstraintDimension._();

  /// An exact size in logical pixels, rounded to the nearest whole pixel.
  ///
  /// `Dimension.fixed(0)` is a real size of 0: the child is laid out 0 wide
  /// (or tall). Android's `0dp` is not a fixed size but [matchConstraint].
  /// A negative size is 0.
  const factory Dimension.fixed(double pixels) = FixedDimension;

  /// Fill the space between the two opposing anchors, optionally bounded.
  ///
  /// The same as [matchConstraint] with an optional [min] and [max] size in
  /// logical pixels. Android `0dp` with `layout_constraintWidth_min` /
  /// `layout_constraintWidth_max`. With only one anchor on the axis, the
  /// child's content size is kept between [min] and [max], and when a bound
  /// changes it the child is measured again at the bounded size, so its other
  /// dimension follows.
  const factory Dimension.spread({double? min, double? max}) =
      MatchConstraintDimension.spread;

  /// Size to the child's content, but never beyond the space between the two
  /// opposing anchors, optionally bounded by [min] and [max].
  ///
  /// Android `0dp` with `layout_constraintWidth_default="wrap"`: unlike plain
  /// [wrapContent], the content size is capped by the constraints. A capped
  /// child is measured again at the capped size, so its other dimension
  /// follows: text that wraps takes the height it needs at the capped width.
  /// The content size rounds up to whole logical pixels, as [wrapContent]'s
  /// does.
  const factory Dimension.constrainedWrap({double? min, double? max}) =
      MatchConstraintDimension.constrainedWrap;

  /// A fraction of the parent `ConstraintLayout`'s size on this axis,
  /// optionally bounded by [min] and [max].
  ///
  /// [fraction] is between 0 and 1. The size comes from the parent, not from
  /// the links, so a single link is enough to place the child; two opposing
  /// links place it by the axis bias. Android `0dp` with
  /// `layout_constraintWidth_percent`.
  const factory Dimension.percent(double fraction, {double? min, double? max}) =
      MatchConstraintDimension.percent;
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
  const MatchConstraintDimension.percent(double fraction, {this.min, this.max})
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
