// Links that loop back on themselves.
//
// A widget is a chain member when one of its anchors targets an anchor that
// targets it straight back, and the dependency graph's chain walk (ChainRun)
// does not check which sides those anchors are on. Two widgets whose
// matching anchors link to each other (two tops, for example), an anchor
// linked to itself, or two widgets linked both ways on both sides used to
// send the walk round the loop forever. Upstream's ChainRun has the same
// walk, but upstream never builds one for these layouts:
// BasicMeasure.solverMeasure keeps the graph off for any layout with a chain
// member, and its solver lays them out, so they finish on Android. The
// expected values are upstream's Java engine at the pinned commit (see
// UPSTREAM.md) at OPTIMIZATION_STANDARD, Android's default.
//
// The solver's own chain walk (ChainHead and Chain) never ended either for a
// chain whose first member's start links one way to its last member, while
// the last member's end links back to the first. Upstream's never does: of
// these loops, that is the only one Android never finishes laying out. So
// those layouts are only checked to finish, on both paths.
//
// Each layout runs in its own isolate, so a regression fails its test
// instead of hanging the run. The timeout is short because some of these
// loops also grow a list: before the fix, two widgets whose rights link to
// each other took about 1 GB of memory a second.

import 'dart:async';
import 'dart:isolate';

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/solver_parity.dart';

/// The geometry of [build]'s layout in a 375 x 600 container and whether
/// the graph resolved it, laid out graph first or, with [forceSolver], on
/// the solver fallback. Fails the test if the layout does not finish.
Future<(List<String>, bool)> layoutInIsolate(
  void Function(ConstraintWidgetContainer root) build, {
  bool forceSolver = false,
}) async {
  final port = ReceivePort();
  final isolate = await Isolate.spawn(_layout, (
    port.sendPort,
    build,
    forceSolver,
  ));
  try {
    return await port.first.timeout(const Duration(seconds: 2))
        as (List<String>, bool);
  } on TimeoutException {
    fail('the layout did not finish within 2 seconds');
  } finally {
    isolate.kill(priority: Isolate.immediate);
    port.close();
  }
}

void _layout(
  (SendPort, void Function(ConstraintWidgetContainer), bool) message,
) {
  final (reply, build, forceSolver) = message;
  final root = forceSolver
      ? ForcedSolverContainer(375, 600)
      : SolveCountingContainer(375, 600);
  root.setDebugName('root');
  build(root);
  root.layout();
  reply.send((geometryOf(root), root.solves == 0));
}

/// Adds `a` and `b` (100 x 50 each) to [root].
(ConstraintWidget, ConstraintWidget) twoWidgets(
  ConstraintWidgetContainer root,
) {
  final a = ConstraintWidget.sizeNamed('a', 100, 50);
  final b = ConstraintWidget.sizeNamed('b', 100, 50);
  root.addAll([a, b]);
  return (a, b);
}

void topsLinkedToEachOther(ConstraintWidgetContainer root) {
  final (a, b) = twoWidgets(root);
  a.connect(.top, b, .top);
  b.connect(.top, a, .top);
}

void bottomsLinkedToEachOther(ConstraintWidgetContainer root) {
  final (a, b) = twoWidgets(root);
  a.connect(.bottom, b, .bottom);
  b.connect(.bottom, a, .bottom);
}

void leftsLinkedToEachOther(ConstraintWidgetContainer root) {
  final (a, b) = twoWidgets(root);
  a.connect(.left, b, .left);
  b.connect(.left, a, .left);
}

void rightsLinkedToEachOther(ConstraintWidgetContainer root) {
  final (a, b) = twoWidgets(root);
  a.connect(.right, b, .right);
  b.connect(.right, a, .right);
}

void leftLinkedToItself(ConstraintWidgetContainer root) {
  final a = ConstraintWidget.sizeNamed('a', 100, 50);
  root.add(a);
  a.connect(.left, a, .left);
}

void rightLinkedToItself(ConstraintWidgetContainer root) {
  final a = ConstraintWidget.sizeNamed('a', 100, 50);
  root.add(a);
  a.connect(.right, a, .right);
}

/// `a` and `b` linked both ways on both sides: a chain with no ends.
void ring(ConstraintWidgetContainer root) {
  final (a, b) = twoWidgets(root);
  a.connect(.left, b, .right);
  a.connect(.right, b, .left);
  b.connect(.left, a, .right);
  b.connect(.right, a, .left);
}

/// The Flutter adapter's `top: .topOf(#b)` and `top: .topOf(#a)`, with both
/// widgets placed horizontally: `b` 8 to the right of `a`.
void topsLinkedInARow(ConstraintWidgetContainer root) {
  final (a, b) = twoWidgets(root);
  a.connect(.left, root, .left, 16);
  b.connect(.left, a, .right, 8);
  a.connect(.top, b, .top);
  b.connect(.top, a, .top);
}

/// In a right-to-left container, with `b` stacked under `a`.
void rightsLinkedInRtl(ConstraintWidgetContainer root) {
  root.setRtl(true);
  final (a, b) = twoWidgets(root);
  a.connect(.right, b, .right);
  b.connect(.right, a, .right);
  a.connect(.top, root, .top);
  b.connect(.top, a, .bottom);
}

/// `h` heads a chain (its left links one way to `a`, its right both ways),
/// and `a`'s right links back to `h`: the solver's walk returns to `h`.
void chainBackToItsHead(ConstraintWidgetContainer root) {
  final h = ConstraintWidget.sizeNamed('h', 100, 50);
  final a = ConstraintWidget.sizeNamed('a', 100, 50);
  root.addAll([h, a]);
  h.connect(.left, a, .left);
  h.connect(.right, a, .left);
  a.connect(.left, h, .right);
  a.connect(.right, h, .left);
}

/// A one-widget chain: `x`'s start and end both link to its own end.
void chainOfOneBackToItself(ConstraintWidgetContainer root) {
  final x = ConstraintWidget.sizeNamed('x', 100, 50);
  root.add(x);
  x.connect(.left, x, .right);
  x.connect(.right, x, .right);
}

void main() {
  group('links that loop', () {
    // Upstream lays every one of these out with both widgets unplaced.
    final unplaced = <String, void Function(ConstraintWidgetContainer)>{
      'tops linked to each other': topsLinkedToEachOther,
      'bottoms linked to each other': bottomsLinkedToEachOther,
      'lefts linked to each other': leftsLinkedToEachOther,
      'rights linked to each other': rightsLinkedToEachOther,
      'two widgets linked both ways on both sides': ring,
    };
    for (final MapEntry(key: name, value: build) in unplaced.entries) {
      test('$name lay out as upstream does, on the solver', () async {
        final (geometry, graphResolved) = await layoutInIsolate(build);
        expect(geometry, [
          'root 375 x 600',
          'a: (0, 0) 100 x 50',
          'b: (0, 0) 100 x 50',
        ]);
        expect(graphResolved, isFalse, reason: 'a cyclic chain declines');
        final (solverGeometry, _) = await layoutInIsolate(
          build,
          forceSolver: true,
        );
        expect(solverGeometry, geometry);
      });
    }

    for (final (name, build) in [
      ('a left linked to itself', leftLinkedToItself),
      ('a right linked to itself', rightLinkedToItself),
    ]) {
      test('$name lays out as upstream does', () async {
        final (geometry, graphResolved) = await layoutInIsolate(build);
        expect(geometry, ['root 375 x 600', 'a: (0, 0) 100 x 50']);
        expect(graphResolved, isFalse);
      });
    }

    test('tops linked to each other in a row of widgets', () async {
      final (geometry, _) = await layoutInIsolate(topsLinkedInARow);
      expect(geometry, [
        'root 375 x 600',
        'a: (16, 0) 100 x 50',
        'b: (124, 0) 100 x 50',
      ]);
    });

    test('rights linked to each other in a right-to-left layout', () async {
      final (geometry, _) = await layoutInIsolate(rightsLinkedInRtl);
      expect(geometry, [
        'root 375 x 600',
        'a: (0, 0) 100 x 50',
        'b: (0, 50) 100 x 50',
      ]);
    });

    // Upstream never returns from these two.
    for (final (name, build) in [
      (
        'a chain whose first member\'s start links one way to its last '
            'member, while the last member\'s end links back to the first',
        chainBackToItsHead,
      ),
      (
        'a widget whose start and end both link to its own end',
        chainOfOneBackToItself,
      ),
    ]) {
      test('$name: the layout finishes, the same on both paths', () async {
        final (geometry, _) = await layoutInIsolate(build);
        final (solverGeometry, _) = await layoutInIsolate(
          build,
          forceSolver: true,
        );
        expect(solverGeometry, geometry);
      });
    }
  });
}
