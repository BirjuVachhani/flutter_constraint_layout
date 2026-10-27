// A widget, or a packed chain, linked to both edges of a wrap-content root
// with a bias of exactly 1. RunGroup.computeWrapSize then divides a gap by
// 1 - bias = 0, which is NaN when the gap is 0 and infinite otherwise.
// Upstream converts the quotient with Java's (long) cast, which maps NaN to 0
// and saturates infinity; the port must not throw where toInt() would. A
// right-to-left layout reaches this with any start/end-linked child whose
// bias is 0, which it mirrors to 1.
//
// No upstream test lays out such a layout, so every expected value here was
// checked against upstream's Java engine at the pinned commit (see
// UPSTREAM.md), run on the same layouts: directMeasure(true) and layout() both
// resolve them without error, to the sizes asserted below.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

/// Reports the proposed size of every widget, as the engine's default
/// measurer does for fixed-size widgets.
class _EchoMeasurer implements Measurer {
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    measure.measuredWidth = measure.horizontalDimension;
    measure.measuredHeight = measure.verticalDimension;
    measure.measuredHasBaseline = false;
    measure.measuredBaseline = 0;
  }

  @override
  void didMeasures() {}
}

/// A root that wraps its content horizontally and is 600 tall.
ConstraintWidgetContainer wrapRoot() {
  final root = ConstraintWidgetContainer.rect(0, 0, 0, 600);
  root.setDebugName('root');
  root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
  root.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
  root.setMeasurer(_EchoMeasurer());
  return root;
}

/// A 100 x 50 widget between the root's left and right edges.
({ConstraintWidgetContainer root, ConstraintWidget a}) centered({
  required double bias,
  int leftMargin = 0,
  int rightMargin = 0,
}) {
  final root = wrapRoot();
  final a = ConstraintWidget.size(100, 50);
  a.setDebugName('A');
  root.add(a);
  a.connect(
    ConstraintAnchorType.left,
    root,
    ConstraintAnchorType.left,
    leftMargin,
  );
  a.connect(
    ConstraintAnchorType.right,
    root,
    ConstraintAnchorType.right,
    rightMargin,
  );
  a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
  a.setHorizontalBiasPercent(bias);
  return (root: root, a: a);
}

/// A packed chain of two 100 x 50 widgets between the root's edges, each
/// outer link with [margin].
({ConstraintWidgetContainer root, ConstraintWidget a, ConstraintWidget b})
packedChain({required double bias, int margin = 0}) {
  final root = wrapRoot();
  final a = ConstraintWidget.size(100, 50);
  final b = ConstraintWidget.size(100, 50);
  a.setDebugName('A');
  b.setDebugName('B');
  root.add(a);
  root.add(b);
  a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, margin);
  a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
  b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
  b.connect(
    ConstraintAnchorType.right,
    root,
    ConstraintAnchorType.right,
    margin,
  );
  a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
  b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
  a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
  a.setHorizontalBiasPercent(bias);
  return (root: root, a: a, b: b);
}

void main() {
  group('a bias of 1 along a wrap-content axis', () {
    test('the graph wraps a widget centered between both edges', () {
      final (:root, :a) = centered(bias: 1);
      expect(root.directMeasure(true), isTrue);
      expect(root.getWidth(), 100);
      expect(a.getLeft(), 0);
    });

    test('the graph wraps a centered widget and its margins', () {
      final (:root, :a) = centered(bias: 1, leftMargin: 10, rightMargin: 20);
      expect(root.directMeasure(true), isTrue);
      expect(root.getWidth(), 130);
      expect(a.getLeft(), 10);
    });

    test('the graph wraps a packed chain', () {
      // BasicMeasure never builds the graph for a layout with a chain, but a
      // direct call lays it out with ChainRun, as upstream's does.
      final (:root, :a, :b) = packedChain(bias: 1, margin: 16);
      expect(root.directMeasure(true), isTrue);
      expect(root.getWidth(), 232);
      expect(a.getLeft(), 16);
      expect(b.getLeft(), 116);
    });

    test('layout() resolves a packed chain with margins', () {
      final (:root, :a, :b) = packedChain(bias: 1, margin: 16);
      root.layout();
      expect(root.getWidth(), 232);
      expect(a.getLeft(), 16);
      expect(b.getLeft(), 116);
    });

    test('layout() resolves a centered widget', () {
      final (:root, :a) = centered(bias: 1, leftMargin: 10, rightMargin: 20);
      root.layout();
      expect(root.getWidth(), 130);
      expect(a.getLeft(), 10);
      expect(a.getWidth(), 100);
    });

    test('layout() resolves a packed chain', () {
      final (:root, :a, :b) = packedChain(bias: 1);
      root.layout();
      expect(root.getWidth(), 200);
      expect(a.getLeft(), 0);
      expect(b.getLeft(), 100);
    });

    test('matches a bias of 0.5, as upstream does', () {
      final one = centered(bias: 1, leftMargin: 10, rightMargin: 20);
      final half = centered(bias: 0.5, leftMargin: 10, rightMargin: 20);
      one.root.layout();
      half.root.layout();
      expect(one.root.getWidth(), half.root.getWidth());
      expect(one.a.getLeft(), half.a.getLeft());
    });
  });
}
