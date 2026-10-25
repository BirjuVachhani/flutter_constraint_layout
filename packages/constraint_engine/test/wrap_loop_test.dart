// Links that make runs depend on each other in a loop, in a container that
// wraps its content along the loop's axis.
//
// The dependency graph never resolves such a loop, so in a container of a
// fixed size the layout goes to the solver. In a wrap-content container the
// graph first computes the wrap size, and RunGroup's traversals of the
// dependencies recursed round the loop until the stack overflowed: layout()
// threw a StackOverflowError. Upstream's traversals are the same, but
// upstream only computes a wrap size on the graph with OPTIMIZATION_GRAPH_WRAP,
// which Android's default leaves off. The expected values are upstream's Java
// engine at the pinned commit (see UPSTREAM.md) at OPTIMIZATION_STANDARD.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/solver_parity.dart';

/// `a` centered between the parent's left and `b`'s right, with `b`'s left
/// on `a`'s right: `a` depends on `b`, which depends on `a`.
void centeredOnADependent(ConstraintWidgetContainer root) {
  root.setHorizontalDimensionBehaviour(.wrapContent);
  final a = ConstraintWidget.sizeNamed('a', 100, 50);
  final b = ConstraintWidget.sizeNamed('b', 100, 50);
  root.addAll([a, b]);
  a.connect(.left, root, .left);
  a.connect(.right, b, .right);
  b.connect(.left, a, .right);
}

/// The same loop along the vertical axis, in a container wrapping its
/// height.
void centeredOnADependentVertically(ConstraintWidgetContainer root) {
  root.setVerticalDimensionBehaviour(.wrapContent);
  final a = ConstraintWidget.sizeNamed('a', 100, 50);
  final b = ConstraintWidget.sizeNamed('b', 100, 50);
  root.addAll([a, b]);
  a.connect(.top, root, .top);
  a.connect(.bottom, b, .bottom);
  b.connect(.top, a, .bottom);
}

/// The loop through a gone match-constraint widget.
void throughAGoneWidget(ConstraintWidgetContainer root) {
  root.setHorizontalDimensionBehaviour(.wrapContent);
  final a = ConstraintWidget.sizeNamed('a', 100, 50);
  final b = ConstraintWidget.sizeNamed('b', 100, 50);
  root.addAll([a, b]);
  a.setHorizontalDimensionBehaviour(.matchConstraint);
  b.setHorizontalDimensionBehaviour(.matchConstraint);
  a.setVisibility(ConstraintWidget.GONE);
  a.connect(.left, root, .left);
  a.connect(.right, b, .right);
  b.connect(.left, a, .right);
}

void main() {
  group('a wrap-content axis whose runs depend on each other in a loop', () {
    for (final (name, build, expected) in [
      (
        'centered on a widget that hangs off it',
        centeredOnADependent,
        ['root 300 x 600', 'a: (100, 0) 100 x 50', 'b: (200, 0) 100 x 50'],
      ),
      (
        'centered on a widget that hangs off it, vertically',
        centeredOnADependentVertically,
        ['root 800 x 150', 'a: (0, 50) 100 x 50', 'b: (0, 100) 100 x 50'],
      ),
      (
        'through a gone match-constraint widget',
        throughAGoneWidget,
        ['root 200 x 600', 'a: gone, 0 x 0', 'b: (100, 0) 100 x 50'],
      ),
    ]) {
      test('$name lays out as upstream does, on the solver', () {
        final passes = layoutBothWays(build);
        expect(passes.single.differences, isEmpty);
        expect(passes.single.graphResolved, isFalse);
        final root = SolveCountingContainer(800, 600)..setDebugName('root');
        build(root);
        root.layout();
        expect(geometryOf(root), expected);
      });
    }
  });
}
