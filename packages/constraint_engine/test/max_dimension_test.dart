// setMaxWidth and setMaxHeight bound a wrap-content container. Upstream keeps
// both in ConstraintWidget.mMaxDimension: addToSolver passes it to
// applyConstraints, which caps a wrap-content container's size at it, and
// BasicMeasure.solverMeasure reads it through getMaxWidth and getMaxHeight to
// clamp an exact size. No upstream test sets a max, so every expected value
// here was checked against upstream's Java engine at the pinned commit (see
// UPSTREAM.md), run on the same layout.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

/// Upstream's NestedLayout shape: [inner] wraps A and B along one axis inside
/// a fixed 1000 x 1000 root that centers it. A sits between the container's
/// start edge and B, biased to the start, and B is pinned to the end edge, so
/// the content is 150 along the wrap axis.
({
  ConstraintWidgetContainer root,
  ConstraintWidgetContainer inner,
  ConstraintWidget a,
  ConstraintWidget b,
})
nestedWrap({required bool horizontal}) {
  final root = ConstraintWidgetContainer.rect(0, 0, 1000, 1000);
  final inner = horizontal
      ? ConstraintWidgetContainer.rect(0, 0, 0, 100)
      : ConstraintWidgetContainer.rect(0, 0, 100, 0);
  final a = horizontal
      ? ConstraintWidget.rect(0, 0, 100, 20)
      : ConstraintWidget.rect(0, 0, 20, 100);
  final b = horizontal
      ? ConstraintWidget.rect(0, 0, 50, 20)
      : ConstraintWidget.rect(0, 0, 20, 50);
  root.setDebugName('root');
  inner.setDebugName('inner');
  a.setDebugName('A');
  b.setDebugName('B');
  root.add(inner);
  inner.add(a);
  inner.add(b);
  final start = horizontal
      ? ConstraintAnchorType.left
      : ConstraintAnchorType.top;
  final end = horizontal
      ? ConstraintAnchorType.right
      : ConstraintAnchorType.bottom;
  inner.connect(start, root, start);
  inner.connect(end, root, end);
  a.connect(start, inner, start);
  a.connect(end, b, start);
  b.connect(end, inner, end);
  if (horizontal) {
    inner.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
    a.setHorizontalBiasPercent(0);
  } else {
    inner.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
    a.setVerticalBiasPercent(0);
  }
  return (root: root, inner: inner, a: a, b: b);
}

void main() {
  group('storage', () {
    test('a widget has no max by default', () {
      final widget = ConstraintWidget();
      expect(widget.getMaxWidth(), ConstraintWidget.intMaxValue);
      expect(widget.getMaxHeight(), ConstraintWidget.intMaxValue);
    });

    test('setMaxWidth and setMaxHeight write the bounds addToSolver reads', () {
      final widget = ConstraintWidget();
      widget.setMaxWidth(150);
      widget.setMaxHeight(80);
      expect(widget.mMaxDimension[ConstraintWidget.HORIZONTAL], 150);
      expect(widget.mMaxDimension[ConstraintWidget.VERTICAL], 80);
      expect(widget.getMaxWidth(), 150);
      expect(widget.getMaxHeight(), 80);
    });
  });

  group('solver', () {
    // A is centered along the wrap axis, which the dependency graph declines,
    // so the root's own addToSolver applies the cap. B keeps its width and
    // overflows; A is centered in the capped width.
    test('caps a wrap-content root at its max width', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 0, 100);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(200, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setMaxWidth(150);

      root.layout();
      expect(root.getWidth(), 150);
      expect(a.getLeft(), 25);
      expect(a.getWidth(), 100);
      expect(b.getLeft(), 0);
      expect(b.getWidth(), 200);
    });

    // The root's solver pass lays out the nested container first, and that
    // layout runs through the nested container's own solver (A sits between
    // two anchors along its wrap axis), where addToSolver applies the cap.
    test('caps a nested wrap-content container at its max width', () {
      final unbounded = nestedWrap(horizontal: true);
      unbounded.root.layout();
      expect(unbounded.inner.getWidth(), 150);
      expect(unbounded.inner.getLeft(), 425);

      final l = nestedWrap(horizontal: true);
      l.inner.setMaxWidth(120);
      l.root.layout();
      expect(l.inner.getWidth(), 120);
      expect(l.inner.getLeft(), 440);
      expect(l.a.getLeft(), 0);
      expect(l.a.getWidth(), 100);
      expect(l.b.getLeft(), 70);
      expect(l.b.getWidth(), 50);
    });

    test('caps a nested wrap-content container at its max height', () {
      final unbounded = nestedWrap(horizontal: false);
      unbounded.root.layout();
      expect(unbounded.inner.getHeight(), 150);
      expect(unbounded.inner.getTop(), 425);

      final l = nestedWrap(horizontal: false);
      l.inner.setMaxHeight(120);
      l.root.layout();
      expect(l.inner.getHeight(), 120);
      expect(l.inner.getTop(), 440);
      expect(l.a.getTop(), 0);
      expect(l.a.getHeight(), 100);
      expect(l.b.getTop(), 70);
      expect(l.b.getHeight(), 50);
    });
  });

  // The dependency graph resolves these layouts, but its wrap computation
  // ignores the max. Upstream solves every wrap-content axis, so a wrap size
  // above the max routes the layout to the solver, which applies the cap.
  group('graph', () {
    test('caps a wrap-content root at its max width', () {
      // (max, expected root width) for content 200 wide.
      for (final (max, width) in [
        (150, 150),
        (199, 199),
        (200, 200),
        (500, 200),
      ]) {
        final root = ConstraintWidgetContainer.rect(0, 0, 0, 100);
        final a = ConstraintWidget.size(200, 20);
        root.setDebugName('root');
        a.setDebugName('A');
        root.add(a);
        a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
        a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
        root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
        root.setMaxWidth(max);

        root.layout();
        expect(root.getWidth(), width, reason: 'max $max');
        expect(a.getLeft(), 0, reason: 'max $max');
        expect(a.getWidth(), 200, reason: 'max $max');
      }
    });

    test('caps each axis of a wrap-content root on its own', () {
      // (max width, max height, expected root width, expected root height)
      // for content 200 x 150; 0 sets no max.
      for (final (maxW, maxH, width, height) in [
        (150, 0, 150, 150),
        (0, 100, 200, 100),
        (150, 100, 150, 100),
      ]) {
        final root = ConstraintWidgetContainer();
        final a = ConstraintWidget.size(200, 150);
        root.setDebugName('root');
        a.setDebugName('A');
        root.add(a);
        a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
        a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
        root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
        root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
        if (maxW > 0) root.setMaxWidth(maxW);
        if (maxH > 0) root.setMaxHeight(maxH);

        root.layout();
        expect(root.getWidth(), width, reason: 'max $maxW x $maxH');
        expect(root.getHeight(), height, reason: 'max $maxW x $maxH');
      }
    });

    test('caps a nested wrap-content container at its max width', () {
      // (max, expected container left, expected container width): B follows
      // A from the container's left edge, so the content is 150 wide.
      for (final (max, left, width) in [(0, 425, 150), (120, 440, 120)]) {
        final root = ConstraintWidgetContainer.rect(0, 0, 1000, 1000);
        final inner = ConstraintWidgetContainer.rect(0, 0, 0, 100);
        final a = ConstraintWidget.rect(0, 0, 100, 20);
        final b = ConstraintWidget.rect(0, 0, 50, 20);
        root.add(inner);
        inner.add(a);
        inner.add(b);
        inner.connect(
          ConstraintAnchorType.left,
          root,
          ConstraintAnchorType.left,
        );
        inner.connect(
          ConstraintAnchorType.right,
          root,
          ConstraintAnchorType.right,
        );
        a.connect(ConstraintAnchorType.left, inner, ConstraintAnchorType.left);
        b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
        inner.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
        if (max > 0) inner.setMaxWidth(max);

        root.layout();
        expect(inner.getLeft(), left, reason: 'max $max');
        expect(inner.getWidth(), width, reason: 'max $max');
        expect(a.getLeft(), 0, reason: 'max $max');
        expect(b.getLeft(), 100, reason: 'max $max');
      }
    });

    // As upstream, the max bounds only a wrap-content axis.
    test('leaves a fixed axis alone', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 400, 100);
      final a = ConstraintWidget.size(200, 20);
      root.add(a);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      root.setMaxWidth(150);

      root.layout();
      expect(root.getWidth(), 400);
      expect(a.getWidth(), 200);
    });
  });

  group('measure', () {
    // With the graph optimizer on, solverMeasure clamps an exact size to the
    // max before resolving; A stays centered in the clamped width.
    test('clamps an exact size to the max', () {
      final root = ConstraintWidgetContainer();
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      root.setMeasurer(_EchoMeasurer());
      root.setMaxWidth(300);
      root.setMaxHeight(80);

      root.measure(
        Optimizer.OPTIMIZATION_GRAPH,
        BasicMeasure.EXACTLY,
        500,
        BasicMeasure.EXACTLY,
        200,
        0,
        0,
        0,
        0,
      );
      expect(root.getWidth(), 300);
      expect(root.getHeight(), 80);
      expect(a.getLeft(), 100);
    });
  });
}

/// Reports a wrap axis at the widget's stored size and echoes every other
/// axis, so the widgets keep the sizes the test gives them.
class _EchoMeasurer implements Measurer {
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    measure.measuredWidth =
        measure.horizontalBehavior == DimensionBehaviour.wrapContent
        ? widget.getWidth()
        : measure.horizontalDimension;
    measure.measuredHeight =
        measure.verticalBehavior == DimensionBehaviour.wrapContent
        ? widget.getHeight()
        : measure.verticalDimension;
    measure.measuredBaseline = 0;
    measure.measuredHasBaseline = false;
  }

  @override
  void didMeasures() {}
}
