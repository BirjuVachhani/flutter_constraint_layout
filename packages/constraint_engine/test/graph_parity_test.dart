// Layouts without a barrier where the dependency graph used to report
// something other than what Android lays out: a baseline link's margin,
// which the graph now adds, and layouts it now declines to the solver,
// which lays them out as Android does.
//
// Every pinned value is Android's: upstream's compiled Java core at the
// pinned commit at OPTIMIZATION_STANDARD, its default, laid out through
// ConstraintWidgetContainer.measure with a measurer that answers each
// measure request, so the Direct pass runs as it does on a device (see
// UPSTREAM.md). OPTIMIZATION_NONE gives the same values for each of them.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/solver_parity.dart';

ConstraintWidget widget(
  ConstraintWidgetContainer root,
  String name,
  int width,
  int height, {
  int baseline = 0,
}) {
  final w = ConstraintWidget.sizeNamed(name, width, height);
  if (baseline > 0) {
    w.setBaselineDistance(baseline);
  }
  root.add(w);
  return w;
}

String frame(ConstraintWidget w) =>
    '(${w.getX()}, ${w.getY()}) ${w.getWidth()} x ${w.getHeight()}';

ConstraintWidget child(ConstraintWidgetContainer root, String name) =>
    root.getChildren().firstWhere((c) => c.getDebugName() == name);

/// [build] laid out on the graph-first path.
ConstraintWidgetContainer laidOut(int width, int height, LayoutBuilder build) {
  final root = SolveCountingContainer(width, height);
  build(root);
  root.layout();
  return root;
}

/// The single pass of [build] resolved on the graph, as Android and the
/// solver lay it out.
void expectGraph(int width, int height, LayoutBuilder build) {
  final pass = layoutBothWays(
    width: width,
    height: height,
    build,
    android: true,
  ).single;
  expect(pass.graphResolved, isTrue, reason: 'expected the graph path');
  expect(pass.differences, isEmpty);
  expect(pass.android, isEmpty);
}

/// The single pass of [build] went to the solver.
void expectSolver(int width, int height, LayoutBuilder build) {
  final pass = layoutBothWays(width: width, height: height, build).single;
  expect(pass.graphResolved, isFalse, reason: 'expected the solver path');
  expect(pass.differences, isEmpty);
}

/// value sits right of name, its baseline linked to name's [targetEdge]
/// with [margin]. Direct.verticalSolvingPass (setFinalBaseline) and
/// ConstraintWidget.addToSolver both add the link's margin; upstream's
/// graph leaves it out.
LayoutBuilder baselineMargin(ConstraintAnchorType targetEdge, int margin) =>
    (root) {
      final name = widget(root, 'name', 120, 20, baseline: 15);
      name.connect(.left, root, .left, 16);
      name.connect(.top, root, .top, 20);
      final value = widget(root, 'value', 80, 14, baseline: 11);
      value.connect(.left, name, .right, 8);
      value.connect(.baseline, name, targetEdge, margin);
    };

/// w has no baseline (a widget without text measures a baseline distance of
/// 0) and its baseline is linked to the top of x. Android ignores the link,
/// so w sits where nothing links it.
void baselineWithoutBaseline(ConstraintWidgetContainer root) {
  final x = widget(root, 'x', 60, 30);
  x.connect(.left, root, .left, 10);
  x.connect(.top, root, .top, 50);
  final w = widget(root, 'w', 40, 20);
  w.connect(.left, root, .left, 100);
  w.connect(.baseline, x, .top);
}

/// w2 fills between the edges of w0, whose wrap width is measured only once
/// its crossed match-constraint height (min 26) is known: the graph used to
/// keep w2 at its first measure (22).
void fillUnmeasured(ConstraintWidgetContainer root) {
  final w2 = widget(root, 'w2', 22, 74);
  final w0 = widget(root, 'w0', 130, 16);
  w0.setHorizontalDimensionBehaviour(.wrapContent);
  w0.connect(.top, root, .bottom);
  w0.connect(.bottom, root, .top);
  w0.setVerticalDimensionBehaviour(.matchConstraint);
  w0.setVerticalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
    26,
    0,
    1.0,
  );
  w2.connect(.left, w0, .left);
  w2.connect(.right, w0, .right);
  w2.setHorizontalDimensionBehaviour(.matchConstraint);
}

/// A chain across the container whose second member's wrap width is
/// measured only once its match-constraint height, below the first member,
/// is known: the graph used to leave both members at x 0.
void chainUnmeasured(ConstraintWidgetContainer root) {
  final w0 = widget(root, 'w0', 61, 21);
  final w1 = widget(root, 'w1', 66, 21);
  w0.connect(.left, root, .left);
  w0.connect(.right, w1, .left);
  w1.connect(.left, w0, .right);
  w1.connect(.right, root, .right);
  w1.setHorizontalDimensionBehaviour(.wrapContent);
  w1.connect(.top, w0, .bottom);
  w1.connect(.bottom, root, .bottom);
  w1.setVerticalDimensionBehaviour(.matchConstraint);
}

/// w2 and w3 link to each other, so both count as a chain, but w3's right
/// edge links nowhere. w2's percent width (a fifth of 606 px, raised to its
/// min of 174) resolves through w2's own run, which upstream's graph then
/// centers between edge targets that the chain run owns: it used to throw
/// a RangeError on the graph-first path and on the solver fallback alike.
void chainWithoutEnd(ConstraintWidgetContainer root) {
  final w2 = widget(root, 'w2', 40, 66);
  final w3 = widget(root, 'w3', 154, 108);
  w2.connect(.left, root, .left, 30);
  w2.connect(.right, w3, .left);
  w3.connect(.left, w2, .right);
  w2.setHorizontalDimensionBehaviour(.matchConstraint);
  w2.setHorizontalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
    174,
    0,
    0.2,
  );
  w2.setVerticalDimensionBehaviour(.matchConstraint);
}

/// a and b spread across the container; b's width is a quarter of it (100
/// px) and its height is match-constraint, so its percent size resolves only
/// after the chain was laid out: the graph used to give b the chain's spare
/// space as a spread member (350 px).
void chainPercent(ConstraintWidgetContainer root) {
  final a = widget(root, 'a', 50, 20);
  final b = widget(root, 'b', 60, 30);
  a.connect(.left, root, .left);
  a.connect(.right, b, .left);
  b.connect(.left, a, .right);
  b.connect(.right, root, .right);
  b.setHorizontalDimensionBehaviour(.matchConstraint);
  b.setHorizontalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
    0,
    0,
    0.25,
  );
  b.setVerticalDimensionBehaviour(.matchConstraint);
  b.connect(.top, root, .top);
  b.connect(.bottom, root, .bottom);
}

/// A container that wraps its width from 0 (as an unbounded Flutter
/// constraint does), with a match-parent child: the graph used to give the
/// child the container's incoming width (0) and wrap around that.
void matchParentInWrap(ConstraintWidgetContainer root) {
  root.setHorizontalDimensionBehaviour(.wrapContent);
  final w1 = widget(root, 'w1', 44, 72);
  w1.setHorizontalDimensionBehaviour(.matchParent);
  final w2 = widget(root, 'w2', 30, 20);
  w2.connect(.left, w1, .right, 5);
}

/// A container that wraps its height, with a gone label centered on a field
/// and a button below the label: the graph used to wrap 28 px too tall.
void goneCenteredInWrap(ConstraintWidgetContainer root) {
  root.setVerticalDimensionBehaviour(.wrapContent);
  final label = widget(root, 'label', 165, 22);
  final field = widget(root, 'field', 77, 56);
  final button = widget(root, 'button', 49, 36);
  label.setVisibility(ConstraintWidget.GONE);
  label.connect(.top, field, .top);
  label.connect(.bottom, field, .bottom);
  button.connect(.top, label, .bottom);
}

void main() {
  group('a baseline link with a margin', () {
    test('to a baseline stays on the graph, with the margin', () {
      final build = baselineMargin(.baseline, 4);
      expectGraph(400, 300, build);
      final root = laidOut(400, 300, build);
      expect(frame(child(root, 'value')), '(144, 28) 80 x 14');
    });

    test('to a top stays on the graph, with the margin', () {
      final build = baselineMargin(.top, 6);
      expectGraph(400, 300, build);
      final root = laidOut(400, 300, build);
      expect(frame(child(root, 'value')), '(144, 15) 80 x 14');
    });

    test('to a bottom stays on the graph, with a negative margin', () {
      final build = baselineMargin(.bottom, -5);
      expectGraph(400, 300, build);
      final root = laidOut(400, 300, build);
      expect(frame(child(root, 'value')), '(144, 24) 80 x 14');
    });
  });

  group('a baseline link from a widget without a baseline', () {
    test('goes to the solver, which ignores the link as Android does', () {
      expectSolver(400, 300, baselineWithoutBaseline);
      final root = laidOut(400, 300, baselineWithoutBaseline);
      expect(frame(child(root, 'x')), '(10, 50) 60 x 30');
      expect(frame(child(root, 'w')), '(100, 0) 40 x 20');
    });
  });

  group('a size that resolves after the last measure', () {
    test('of a widget a fill reads goes to the solver', () {
      expectSolver(404, 736, fillUnmeasured);
      final root = laidOut(404, 736, fillUnmeasured);
      expect(frame(child(root, 'w2')), '(0, 0) 130 x 74');
      expect(frame(child(root, 'w0')), '(0, 355) 130 x 26');
    });

    test('of a chain member goes to the solver', () {
      expectSolver(267, 623, chainUnmeasured);
      final root = laidOut(267, 623, chainUnmeasured);
      expect(frame(child(root, 'w0')), '(47, 0) 61 x 21');
      expect(frame(child(root, 'w1')), '(154, 21) 66 x 602');
    });
  });

  group('a chain whose last member links nowhere', () {
    test('with a percent member goes to the solver without a throw', () {
      expectSolver(606, 248, chainWithoutEnd);
      final root = laidOut(606, 248, chainWithoutEnd);
      expect(frame(child(root, 'w2')), '(30, 0) 174 x 66');
      expect(frame(child(root, 'w3')), '(204, 0) 154 x 108');
    });
  });
  group('a chain with a percent member', () {
    test('goes to the solver', () {
      expectSolver(400, 300, chainPercent);
      final root = laidOut(400, 300, chainPercent);
      expect(frame(child(root, 'a')), '(83, 0) 50 x 20');
      expect(frame(child(root, 'b')), '(217, 0) 100 x 300');
    });
  });

  group('a wrap-content axis', () {
    test('with a match-parent child goes to the solver', () {
      expectSolver(0, 614, matchParentInWrap);
      final root = laidOut(0, 614, matchParentInWrap);
      expect(root.getWidth(), 79);
      expect(frame(child(root, 'w1')), '(0, 0) 44 x 72');
      expect(frame(child(root, 'w2')), '(49, 0) 30 x 20');
    });

    test('with a gone child centered along it goes to the solver', () {
      expectSolver(530, 459, goneCenteredInWrap);
      final root = laidOut(530, 459, goneCenteredInWrap);
      expect(root.getHeight(), 64);
      expect(frame(child(root, 'field')), '(0, 0) 77 x 56');
      expect(frame(child(root, 'button')), '(0, 28) 49 x 36');
    });
  });
}
