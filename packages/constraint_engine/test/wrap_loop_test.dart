// Links that make runs depend on each other in a loop, in a container that
// wraps its content along the loop's axis.
//
// Measured, these layouts never reach the dependency graph's wrap
// computation: BasicMeasure runs the graph on a wrapping axis only at the
// OPTIMIZATION_GRAPH_WRAP levels, and then only to resolve the other, exact
// axis (directMeasureWithOrientation), before the solver lays the layout
// out. The expected strings are the pinned oracle's (VOpDriver v2, core
// path, -XX:hashCode=2), the same at levels 257, 0, 64, 321, 192 and 449.
//
// A direct DependencyGraph.directMeasure(true) call does compute the wrap
// size, and RunGroup's traversals of the dependencies go round the loop.
// Upstream's recurse until the stack overflows (Java throws a
// StackOverflowError on all three layouts, checked on the pinned core);
// the port's stop and leave the axis to the solver.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/echo_measurer.dart';
import 'support/op_replay.dart';

/// `a` centered between the parent's left and `b`'s right, with `b`'s left
/// on `a`'s right: `a` depends on `b`, which depends on `a`.
const _centeredOnADependent =
    'R 800 600;wrapw;w a 100 50;add a;w b 100 50;add b;'
    'c a L root L 0;c a R b R 0;c b L a R 0';

/// The same loop along the vertical axis, in a container wrapping its
/// height.
const _centeredOnADependentVertically =
    'R 800 600;wraph;w a 100 50;add a;w b 100 50;add b;'
    'c a T root T 0;c a B b B 0;c b T a B 0';

/// The loop through a gone match-constraint widget.
const _throughAGoneWidget =
    'R 800 600;wrapw;w a 100 50;add a;w b 100 50;add b;hb a M;hb b M;'
    'v a 8;c a L root L 0;c a R b R 0;c b L a R 0';

/// The container [ops] builds, with the echo measurer, unmeasured: the
/// engine calls of the op list, as the oracle's core path makes them.
ConstraintWidgetContainer _build(String ops) {
  final list = ops.split(';');
  final size = list.first.split(' ');
  final root = ConstraintWidgetContainer.rect(
    0,
    0,
    int.parse(size[1]),
    int.parse(size[2]),
  )..setDebugName('root');
  final by = <String, ConstraintWidget>{'root': root};
  ConstraintAnchorType anchor(String s) => switch (s) {
    'L' => ConstraintAnchorType.left,
    'R' => ConstraintAnchorType.right,
    'T' => ConstraintAnchorType.top,
    _ => ConstraintAnchorType.bottom,
  };
  for (final op in list.skip(1)) {
    final t = op.split(' ');
    switch (t[0]) {
      case 'wrapw':
        root.setHorizontalDimensionBehaviour(.wrapContent);
      case 'wraph':
        root.setVerticalDimensionBehaviour(.wrapContent);
      case 'w':
        by[t[1]] = ConstraintWidget.sizeNamed(
          t[1],
          int.parse(t[2]),
          int.parse(t[3]),
        );
      case 'add':
        root.add(by[t[1]]!);
      case 'hb':
        by[t[1]]!.setHorizontalDimensionBehaviour(.matchConstraint);
      case 'v':
        by[t[1]]!.setVisibility(int.parse(t[2]));
      case 'c':
        by[t[1]]!.connect(
          anchor(t[2]),
          by[t[3]]!,
          anchor(t[4]),
          int.parse(t[5]),
        );
    }
  }
  return root..setMeasurer(const EchoMeasurer());
}

void main() {
  group('a wrap-content axis whose runs depend on each other in a loop', () {
    for (final (name, ops, java) in [
      (
        'centered on a widget that hangs off it',
        _centeredOnADependent,
        'root 300 x 600 | a: (100, 0) 100 x 50 | b: (200, 0) 100 x 50',
      ),
      (
        'centered on a widget that hangs off it, vertically',
        _centeredOnADependentVertically,
        'root 800 x 150 | a: (0, 50) 100 x 50 | b: (0, 100) 100 x 50',
      ),
      (
        'through a gone match-constraint widget',
        _throughAGoneWidget,
        'root 200 x 600 | a: gone, 0 x 0 | b: (100, 0) 100 x 50',
      ),
    ]) {
      test('$name lays out as upstream does', () {
        for (final level in const [257, 0, 64, 321, 192, 449]) {
          final r = replayCore(ops, level: level);
          expect(r.status, 'ok', reason: 'level $level');
          expect(r.geometry, java, reason: 'level $level');
        }
      });

      test('$name: the graph computes no wrap size and returns', () {
        final root = _build(ops);
        expect(root.directMeasure(true), isFalse);
      });
    }
  });
}
