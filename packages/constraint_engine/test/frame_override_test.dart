// ConstraintWidget.setFrame, which updateFromSolver calls with the solved
// edges, corrects a fixed axis that rounding shrank, raises a size to the
// widget's minimum, and caps a match-constraint size at its maximum. When the
// minimum or the maximum changed a size, it records that size as an override
// (hasDimensionOverride): ConstraintWidgetContainer.layout then solves again,
// with the overridden size fixed, so the widget is placed at that size and
// whatever is linked to it follows. The solver never applies a widget's own
// minimum (setMinWidth, setMinHeight) to a match-constraint axis, so that
// re-solve is how such a widget ends up centered at its minimum.
//
// No upstream test exercises the override, so every expected value here was
// taken from upstream's Java engine at the pinned commit (see UPSTREAM.md),
// run on the same layouts: the results, solve counts included, are the same
// at OPTIMIZATION_NONE and OPTIMIZATION_STANDARD.

import 'dart:isolate';

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/solver_parity.dart';

String frame(ConstraintWidget w) =>
    '${w.getX()}, ${w.getY()}, ${w.getWidth()} x ${w.getHeight()}';

/// A cyclic barrier layout with a match-constraint widget below its minimum,
/// from the review fuzz: its third solve never returns upstream
/// (ArrayRow.updateFromSystem finds no fixed point). Sends 'returned' to
/// [done] once layout() returns.
void _cyclicBarrierLayout(SendPort done) {
  final root = ConstraintWidgetContainer.rect(0, 0, 254, 660);
  final g0 = Guideline()
    ..setOrientation(Guideline.vertical)
    ..setGuideBegin(20);
  final w0 = ConstraintWidget.sizeNamed('w0', 80, 38);
  final w1 = ConstraintWidget.sizeNamed('w1', 20, 74);
  final w2 = ConstraintWidget.sizeNamed('w2', 100, 108);
  final b0 = Barrier.named('b0')
    ..setBarrierType(Barrier.right)
    ..setMargin(-6)
    ..setAllowsGoneWidget(false);
  final b1 = Barrier.named('b1')..setBarrierType(Barrier.right);
  root.addAll([g0, w2, w0, b1, b0, w1]);
  b0.add(w1);
  b1.add(w2);
  w0.setVerticalDimensionBehaviour(.matchConstraint);
  w0.setMinHeight(64);
  w0.setVerticalBiasPercent(1);
  w1.connect(.left, b0, .right);
  w1.connect(.right, b0, .right);
  w1.setHorizontalDimensionBehaviour(.matchConstraint);
  w1.setMinWidth(26);
  w2.connect(.left, b1, .right, 10);
  w2.connect(.top, w0, .top);
  root.layout();
  done.send('returned');
}

void main() {
  group('setFrame', () {
    test('records the sizes a minimum or a maximum changed', () {
      final w = ConstraintWidget.named('frame');
      w.setHorizontalDimensionBehaviour(.matchConstraint);
      w.setVerticalDimensionBehaviour(.matchConstraint);
      w.setHorizontalMatchStyle(
        ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
        0,
        80,
        1,
      );
      w.setMinHeight(50);
      w.setFrame(10, 20, 210, 40);
      expect(frame(w), '10, 20, 80 x 50');
      expect(w.mWidthOverride, 80);
      expect(w.mHeightOverride, 50);
      expect(w.hasDimensionOverride(), isTrue);
    });

    test('corrects a fixed axis that rounding shrank, without an '
        'override', () {
      final w = ConstraintWidget.sizeNamed('fixed', 100, 30);
      w.setFrame(5, 5, 104, 34);
      expect(frame(w), '5, 5, 100 x 30');
      expect(w.hasDimensionOverride(), isFalse);
    });

    test('collapses a gone widget, without an override', () {
      final w = ConstraintWidget.sizeNamed('gone', 100, 30);
      w.setMinWidth(500);
      w.setVisibility(ConstraintWidget.GONE);
      w.setFrame(1, 2, 3, 4);
      expect(frame(w), '1, 2, 0 x 0');
      expect(w.hasDimensionOverride(), isFalse);
    });

    test('records nothing when the frame fits the bounds', () {
      final w = ConstraintWidget.named('fits');
      w.setHorizontalDimensionBehaviour(.matchConstraint);
      w.setMinWidth(20);
      w.setFrame(0, 0, 50, 10);
      expect(frame(w), '0, 0, 50 x 10');
      expect(w.hasDimensionOverride(), isFalse);
    });
  });

  group('layout solves again with the override', () {
    test('a fill narrower than its minimum width is placed at that width', () {
      // b fills 260 px between a and the container's end, below its 320 px
      // minimum. The second solve fixes it at 320 and centers it with its
      // 0.3 bias, overflowing the space by 60: 130 - 0.3 * 60 = 112. c
      // follows b's right edge.
      final root = SolveCountingContainer(400, 300);
      final a = ConstraintWidget.sizeNamed('a', 100, 20);
      final b = ConstraintWidget.sizeNamed('b', 0, 20);
      final c = ConstraintWidget.sizeNamed('c', 30, 20);
      root.addAll([a, b, c]);
      a.connect(.left, root, .left, 10);
      a.connect(.top, root, .top);
      b.setHorizontalDimensionBehaviour(.matchConstraint);
      b.setMinWidth(320);
      b.setHorizontalBiasPercent(0.3);
      b.connect(.left, a, .right, 20);
      b.connect(.right, root, .right, 10);
      b.connect(.top, a, .bottom);
      c.connect(.left, b, .right, 5);
      c.connect(.top, b, .bottom);

      root.layout();

      expect(frame(a), '10, 0, 100 x 20');
      expect(frame(b), '112, 20, 320 x 20');
      expect(frame(c), '437, 40, 30 x 20');
      expect(root.solves, 2);
      expect(b.hasDimensionOverride(), isFalse, reason: 'used by the re-solve');
    });

    test('a fill shorter than its minimum height is placed at that '
        'height', () {
      final root = SolveCountingContainer(300, 200);
      final top = ConstraintWidget.sizeNamed('top', 50, 120);
      final mid = ConstraintWidget.sizeNamed('mid', 50, 0);
      final below = ConstraintWidget.sizeNamed('below', 50, 10);
      root.addAll([top, mid, below]);
      top.connect(.left, root, .left);
      top.connect(.top, root, .top);
      mid.setVerticalDimensionBehaviour(.matchConstraint);
      mid.setMinHeight(100);
      mid.connect(.left, root, .left, 60);
      mid.connect(.top, top, .bottom);
      mid.connect(.bottom, root, .bottom);
      below.connect(.left, root, .left, 120);
      below.connect(.top, mid, .bottom);

      root.layout();

      expect(frame(mid), '60, 110, 50 x 100');
      expect(frame(below), '120, 210, 50 x 10');
      expect(root.solves, 2);
    });

    test('a fill wider than the container keeps solving until the limit', () {
      // Centered at its 150 px minimum in a 100 px container, the fill
      // starts at -25, which the solver reports as -24 (it rounds with
      // (int) (value + 0.5)). Its width then reads as 149, below the
      // minimum again, so every solve records a new override until
      // layout() stops after its ninth.
      final root = SolveCountingContainer(100, 100);
      final a = ConstraintWidget.sizeNamed('a', 0, 20);
      root.add(a);
      a.setHorizontalDimensionBehaviour(.matchConstraint);
      a.setMinWidth(150);
      a.connect(.left, root, .left);
      a.connect(.right, root, .right);
      a.connect(.top, root, .top);

      root.layout();

      expect(frame(a), '-24, 0, 150 x 20');
      expect(root.solves, 9);
      expect(a.hasDimensionOverride(), isTrue);
    });

    test('a minimum the space already meets needs no second solve', () {
      final root = SolveCountingContainer(400, 100);
      final a = ConstraintWidget.sizeNamed('a', 0, 20);
      root.add(a);
      a.setHorizontalDimensionBehaviour(.matchConstraint);
      a.setMinWidth(150);
      a.connect(.left, root, .left);
      a.connect(.right, root, .right);
      a.connect(.top, root, .top);

      root.layout();

      expect(frame(a), '0, 0, 400 x 20');
      expect(a.hasDimensionOverride(), isFalse);
    });

    test('the graph leaves those layouts to the solver', () {
      final passes = layoutBothWays(width: 400, height: 300, (root) {
        final a = ConstraintWidget.sizeNamed('a', 100, 20);
        final b = ConstraintWidget.sizeNamed('b', 0, 20);
        root.addAll([a, b]);
        a.connect(.left, root, .left, 10);
        b.setHorizontalDimensionBehaviour(.matchConstraint);
        b.setMinWidth(320);
        b.connect(.left, a, .right, 20);
        b.connect(.right, root, .right, 10);
      });
      expect(passes.single.differences, isEmpty);
      expect(passes.single.graphResolved, isFalse);
    });
  });

  group('an override left pending', () {
    test('is applied by the next pass, then never again', () {
      final root = SolveCountingContainer(100, 100);
      final a = ConstraintWidget.sizeNamed('a', 0, 20);
      root.add(a);
      a.setHorizontalDimensionBehaviour(.matchConstraint);
      a.setMinWidth(150);
      a.connect(.left, root, .left);
      a.connect(.right, root, .right);
      a.connect(.top, root, .top);
      root.layout();
      // Upstream's oscillation: 9 solves, and an override left pending.
      expect(a.hasDimensionOverride(), isTrue);
      root.setWidth(400);
      root.layout();
      // Upstream applies it on this pass, and on no later one.
      expect(frame(a), '125, 0, 150 x 20');
      expect(a.hasDimensionOverride(), isFalse);
      root.layout();
      expect(frame(a), '0, 0, 400 x 20');
    });
  });

  group('a cyclic barrier layout below a minimum', () {
    test('returns, where upstream never does', () async {
      // A synchronous loop cannot time out in its own isolate.
      final port = ReceivePort();
      final isolate = await Isolate.spawn(_cyclicBarrierLayout, port.sendPort);
      try {
        final result = await port.first.timeout(
          const Duration(seconds: 10),
          onTimeout: () => 'timed out',
        );
        expect(result, 'returned');
      } finally {
        isolate.kill(priority: Isolate.immediate);
        port.close();
      }
    });
  });
}
