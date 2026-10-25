// ConstraintWidget.setWrapBehaviorInParent leaves a widget out of a
// wrap-content container's size, on one axis or both. Upstream reads it in
// addToSolver only; the dependency graph's wrap computation counts every
// widget, so a layout where the setting has an effect is resolved by the
// solver. No upstream test sets it, so every expected value here was taken
// from upstream's Java engine at the pinned commit (see UPSTREAM.md), run on
// the same layouts: the results are the same at OPTIMIZATION_NONE and
// OPTIMIZATION_STANDARD.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/solver_parity.dart';

/// A 1000 x 1000 container wrapping its width ([wrapWidth]) and its height
/// ([wrapHeight]), with `a` (100 x 20) at its top-left corner and `b`
/// (300 x 40) given [behavior]: 10 below `a`, or with [toEnd] against the
/// container's right and bottom edges.
void build(
  ConstraintWidgetContainer root,
  int behavior, {
  bool wrapWidth = true,
  bool wrapHeight = true,
  bool toEnd = false,
}) {
  if (wrapWidth) {
    root.setHorizontalDimensionBehaviour(.wrapContent);
  }
  if (wrapHeight) {
    root.setVerticalDimensionBehaviour(.wrapContent);
  }
  final a = ConstraintWidget.sizeNamed('a', 100, 20);
  final b = ConstraintWidget.sizeNamed('b', 300, 40);
  root.addAll([a, b]);
  a.connect(.left, root, .left);
  a.connect(.top, root, .top);
  if (toEnd) {
    b.connect(.right, root, .right);
    b.connect(.bottom, root, .bottom);
  } else {
    b.connect(.left, root, .left);
    b.connect(.top, a, .bottom, 10);
  }
  b.setWrapBehaviorInParent(behavior);
}

/// Lays out [build] with [behavior] and returns the container's size and
/// `b`'s frame as `w x h | x, y`, plus whether the graph resolved it.
(String, bool) layout(
  int behavior, {
  bool wrapWidth = true,
  bool wrapHeight = true,
  bool toEnd = false,
}) {
  final root = SolveCountingContainer(1000, 1000);
  build(
    root,
    behavior,
    wrapWidth: wrapWidth,
    wrapHeight: wrapHeight,
    toEnd: toEnd,
  );
  root.layout();
  final b = root.getChildren()[1];
  return (
    '${root.getWidth()} x ${root.getHeight()} | ${b.getX()}, ${b.getY()}',
    root.solves == 0,
  );
}

void main() {
  const included = ConstraintWidget.WRAP_BEHAVIOR_INCLUDED;
  const horizontalOnly = ConstraintWidget.WRAP_BEHAVIOR_HORIZONTAL_ONLY;
  const verticalOnly = ConstraintWidget.WRAP_BEHAVIOR_VERTICAL_ONLY;
  const skipped = ConstraintWidget.WRAP_BEHAVIOR_SKIPPED;

  test('the behavior is stored, and only valid values are taken', () {
    final w = ConstraintWidget();
    expect(w.getWrapBehaviorInParent(), included);
    w.setWrapBehaviorInParent(skipped);
    expect(w.getWrapBehaviorInParent(), skipped);
    w.setWrapBehaviorInParent(7);
    expect(w.getWrapBehaviorInParent(), skipped);
  });

  group('a container that wraps both axes', () {
    test('counts an included widget on both', () {
      expect(layout(included), ('300 x 70 | 0, 30', true));
    });

    test('counts a horizontal-only widget in its width', () {
      expect(layout(horizontalOnly).$1, '300 x 20 | 0, 30');
    });

    test('counts a vertical-only widget in its height', () {
      expect(layout(verticalOnly).$1, '100 x 70 | 0, 30');
    });

    test('leaves a skipped widget out', () {
      expect(layout(skipped).$1, '100 x 20 | 0, 30');
    });
  });

  group('a container that wraps one axis', () {
    test('wrapping its width only', () {
      expect(layout(included, wrapHeight: false).$1, '300 x 1000 | 0, 30');
      // A horizontal-only widget counts toward the only axis that wraps, so
      // the setting has no effect and the graph keeps the layout.
      expect(
        layout(horizontalOnly, wrapHeight: false),
        ('300 x 1000 | 0, 30', true),
      );
      expect(layout(verticalOnly, wrapHeight: false).$1, '100 x 1000 | 0, 30');
      expect(layout(skipped, wrapHeight: false).$1, '100 x 1000 | 0, 30');
    });

    test('wrapping its height only', () {
      expect(layout(included, wrapWidth: false).$1, '1000 x 70 | 0, 30');
      expect(layout(horizontalOnly, wrapWidth: false).$1, '1000 x 20 | 0, 30');
      expect(
        layout(verticalOnly, wrapWidth: false),
        ('1000 x 70 | 0, 30', true),
      );
      expect(layout(skipped, wrapWidth: false).$1, '1000 x 20 | 0, 30');
    });
  });

  test('a left-out widget linked to the container end sits past its '
      'start', () {
    // The container wraps `a` alone, so `b`, against its end, starts
    // before it. The solver reports -200 and -20 as -199 and -19.
    expect(layout(included, toEnd: true).$1, '300 x 40 | 0, 0');
    expect(layout(horizontalOnly, toEnd: true).$1, '300 x 20 | 0, -19');
    expect(layout(verticalOnly, toEnd: true).$1, '100 x 40 | -199, 0');
    expect(layout(skipped, toEnd: true).$1, '100 x 20 | -199, -19');
  });

  test('every layout comes out as on the solver path', () {
    for (final behavior in [included, horizontalOnly, verticalOnly, skipped]) {
      for (final (wrapWidth, wrapHeight, toEnd) in [
        (true, true, false),
        (true, false, false),
        (false, true, false),
        (true, true, true),
      ]) {
        final passes = layoutBothWays(
          width: 1000,
          height: 1000,
          (root) => build(
            root,
            behavior,
            wrapWidth: wrapWidth,
            wrapHeight: wrapHeight,
            toEnd: toEnd,
          ),
        );
        expect(passes.single.differences, isEmpty);
      }
    }
  });
}
