// The content model of the parity corpora (see README.md here): a leaf
// RenderBox whose layout, dry layout, intrinsic sizes and baseline follow a
// `ct` op of an op list, so a ConstraintLayout of these children gets the
// measure answers the oracle's content views give.
//
//   box W H    a fixed natural size W x H
//   text W H   a text W wide on one line, H per line: at width w it takes
//              H * ceil(W / w) (H * 50 at w <= 0)
//   none       a bare view: per axis the maximum when bounded, else the
//              minimum
//
// The baseline is what Android's getBaseline() returns, -1 for none.
//
// Under tight constraints a box answers what the view answers under
// EXACTLY, under 0..s what it answers under AT_MOST(s), and under
// 0..infinity what it answers under UNSPECIFIED: the adapter's mapping of
// measure specs to box constraints.
import 'package:flutter/widgets.dart';

enum ContentKind { box, text, none }

class ContentModel {
  const ContentModel(this.kind, this.w, this.h, this.baseline);

  /// The `ct` op's fields as the corpus stores them: kind, W, H, baseline.
  factory ContentModel.fromJson(List<Object?> fields) => ContentModel(
    switch (fields[0]) {
      'box' => ContentKind.box,
      'text' => ContentKind.text,
      'none' => ContentKind.none,
      final kind => throw ArgumentError('content kind $kind'),
    },
    fields[1]! as int,
    fields[2]! as int,
    fields[3]! as int,
  );

  final ContentKind kind;

  /// The natural width (box) or one-line text width (text).
  final int w;

  /// The natural height (box) or line height (text).
  final int h;

  /// Android's getBaseline(): -1 for none.
  final int baseline;

  /// The height a text takes at [width], with Java's int arithmetic on an
  /// integral width (the only kind the adapter gives) and the same ceiling
  /// on any other.
  int textHeightAt(double width) {
    if (width <= 0) return (h * 50).toSigned(32);
    if (!width.isFinite) return h;
    if (width == width.roundToDouble()) {
      final iw = width.toInt();
      return (h * ((w + iw - 1) ~/ iw)).toSigned(32);
    }
    return (h * (w / width).ceil()).toSigned(32);
  }

  static double _clamp(num v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v.toDouble());

  /// The size under BoxConstraints(minW..maxW, minH..maxH).
  Size layout(BoxConstraints c) {
    switch (kind) {
      case ContentKind.box:
        return Size(
          _clamp(w, c.minWidth, c.maxWidth),
          _clamp(h, c.minHeight, c.maxHeight),
        );
      case ContentKind.text:
        final width = _clamp(w, c.minWidth, c.maxWidth);
        return Size(
          width,
          _clamp(textHeightAt(width), c.minHeight, c.maxHeight),
        );
      case ContentKind.none:
        return Size(
          c.maxWidth.isFinite ? c.maxWidth : c.minWidth,
          c.maxHeight.isFinite ? c.maxHeight : c.minHeight,
        );
    }
  }

  /// The baseline from the top, or null when there is none.
  double? get boxBaseline =>
      kind == ContentKind.none || baseline == -1 ? null : baseline.toDouble();

  /// The intrinsic width (min and max alike).
  double get intrinsicWidth => kind == ContentKind.none ? 0 : w.toDouble();

  /// The intrinsic height at [width] (min and max alike).
  double intrinsicHeight(double width) => switch (kind) {
    ContentKind.box => h.toDouble(),
    ContentKind.text => textHeightAt(width).toDouble(),
    ContentKind.none => 0,
  };

  @override
  bool operator ==(Object other) =>
      other is ContentModel &&
      other.kind == kind &&
      other.w == w &&
      other.h == h &&
      other.baseline == baseline;

  @override
  int get hashCode => Object.hash(kind, w, h, baseline);
}

/// A leaf whose size and baseline follow [content].
class ContentModelBox extends LeafRenderObjectWidget {
  const ContentModelBox({super.key, required this.content});

  final ContentModel content;

  @override
  RenderContentModelBox createRenderObject(BuildContext context) =>
      RenderContentModelBox(content);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderContentModelBox renderObject,
  ) {
    renderObject.content = content;
  }
}

class RenderContentModelBox extends RenderBox {
  RenderContentModelBox(this._content);

  ContentModel _content;

  ContentModel get content => _content;
  set content(ContentModel value) {
    if (value == _content) return;
    _content = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    size = _content.layout(constraints);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _content.layout(constraints);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _content.boxBaseline;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) => _content.boxBaseline;

  @override
  double computeMinIntrinsicWidth(double height) => _content.intrinsicWidth;

  @override
  double computeMaxIntrinsicWidth(double height) => _content.intrinsicWidth;

  @override
  double computeMinIntrinsicHeight(double width) =>
      _content.intrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _content.intrinsicHeight(width);
}
