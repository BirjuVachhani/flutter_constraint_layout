// ContentModelBox (FORMATS.md 6.2 and 11): a RenderBox whose layout, dry
// layout, intrinsic sizes and baselines follow a `ct` content op exactly, so
// a real ConstraintLayout of these children answers its measures the way
// VOpDriver's content views do.
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'src/content.dart';

export 'src/content.dart';

/// Counts the layouts a parent asks of a child: calls to `layout()` and the
/// `performLayout` runs they lead to (a call under the child's current
/// constraints, while it is clean, runs nothing).
class LayoutCounter {
  int calls = 0;
  int runs = 0;

  void reset() {
    calls = 0;
    runs = 0;
  }
}

/// A leaf whose size and baseline follow [content].
class ContentModelBox extends LeafRenderObjectWidget {
  const ContentModelBox({super.key, required this.content, this.counter});

  final ContentModel content;

  /// Optional: counts this child's layouts (benchmarks).
  final LayoutCounter? counter;

  @override
  RenderContentModelBox createRenderObject(BuildContext context) =>
      RenderContentModelBox(content, counter: counter);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderContentModelBox renderObject,
  ) {
    renderObject
      ..content = content
      ..counter = counter;
  }
}

class RenderContentModelBox extends RenderBox {
  RenderContentModelBox(this._content, {this.counter});

  ContentModel _content;
  LayoutCounter? counter;

  ContentModel get content => _content;
  set content(ContentModel value) {
    if (value == _content) return;
    _content = value;
    markNeedsLayout();
  }

  Size _sizeFor(BoxConstraints c) {
    final s = _content.layout(c.minWidth, c.maxWidth, c.minHeight, c.maxHeight);
    return Size(s.width, s.height);
  }

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    counter?.calls++;
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  @override
  void performLayout() {
    counter?.runs++;
    size = _sizeFor(constraints);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _sizeFor(constraints);

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

  @override
  bool hitTestSelf(Offset position) => true;
}
