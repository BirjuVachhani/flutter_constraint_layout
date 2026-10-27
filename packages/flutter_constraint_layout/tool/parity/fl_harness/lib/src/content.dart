// The content model of the parity corpora (FORMATS.md section 6), the
// box-constraint form (6.2) that ContentModelBox follows. Pure Dart, so the
// ftree CLI can use it without Flutter.
//
//   box W H    a fixed natural size W x H
//   text W H   a text W wide on one line, H per line: at width w it takes
//              H * ceil(W / w) (H * 50 at w <= 0)
//   none       a bare View: per axis the maximum when bounded, else the minimum
//
// BL is what Android's getBaseline() returns: -1 for none.

enum ContentKind { box, text, none }

class ContentModel {
  const ContentModel(this.kind, this.w, this.h, this.baseline);

  /// Parses the fields of a `ct N KIND W H BL` op (split on spaces).
  factory ContentModel.parseOp(List<String> t) {
    if (t.length != 6 || t[0] != 'ct') {
      throw ArgumentError('ct op: ${t.join(' ')}');
    }
    final kind = switch (t[2]) {
      'box' => ContentKind.box,
      'text' => ContentKind.text,
      'none' => ContentKind.none,
      _ => throw ArgumentError('content kind ${t[2]}'),
    };
    return ContentModel(kind, int.parse(t[3]), int.parse(t[4]), int.parse(t[5]));
  }

  /// The model of a widget that has no `ct` op: a bare View.
  static const ContentModel bare = ContentModel(ContentKind.none, 0, 0, -1);

  final ContentKind kind;

  /// Natural width (box) or one-line text width (text); unused for none.
  final int w;

  /// Natural height (box) or line height (text); unused for none.
  final int h;

  /// Android's getBaseline(): -1 for none.
  final int baseline;

  /// The height a text takes at [width], with Java's int arithmetic on an
  /// integral width (the only kind the adapter produces) and the same
  /// ceiling on any other.
  int textHeightAt(double width) {
    if (width <= 0) return (h * 50).toSigned(32);
    if (width == width.roundToDouble() && width.isFinite) {
      final iw = width.toInt();
      return (h * ((w + iw - 1) ~/ iw)).toSigned(32);
    }
    if (!width.isFinite) return h;
    return (h * (w / width).ceil()).toSigned(32);
  }

  static double _clamp(num v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v.toDouble());

  /// The size under BoxConstraints(minW..maxW, minH..maxH) (6.2). Under
  /// tight constraints this is EXACTLY, under 0..s AT_MOST, under 0..inf
  /// UNSPECIFIED.
  ({double width, double height}) layout(
    double minW,
    double maxW,
    double minH,
    double maxH,
  ) {
    switch (kind) {
      case ContentKind.box:
        return (width: _clamp(w, minW, maxW), height: _clamp(h, minH, maxH));
      case ContentKind.text:
        final width = _clamp(w, minW, maxW);
        return (width: width, height: _clamp(textHeightAt(width), minH, maxH));
      case ContentKind.none:
        return (
          width: maxW.isFinite ? maxW : minW,
          height: maxH.isFinite ? maxH : minH,
        );
    }
  }

  /// The baseline from the top: null when there is none.
  double? get boxBaseline =>
      kind == ContentKind.none || baseline == -1 ? null : baseline.toDouble();

  /// Intrinsic width (min and max alike): the one-line width or the box
  /// width; a bare View has none.
  double get intrinsicWidth => kind == ContentKind.none ? 0 : w.toDouble();

  /// Intrinsic height at [width] (min and max alike).
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

  @override
  String toString() => 'ct ${kind.name} $w $h $baseline';
}
