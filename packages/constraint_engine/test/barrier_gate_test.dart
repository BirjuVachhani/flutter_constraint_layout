// Barrier layouts the dependency graph must leave to the solver, because
// Android lays them out where the solver does and the graph does not, and
// some the graph keeps because Android lays them out as the graph does.
// Each case was a graph/Android difference found by fuzzing the barrier
// check (DependencyGraph._barriersMatchSolver) against upstream's compiled
// core once barrier layouts stopped going to the solver unconditionally.
//
// Every pinned value is Android's: upstream's compiled Java core at the
// pinned commit at OPTIMIZATION_STANDARD, its default, laid out through
// ConstraintWidgetContainer.measure with a measurer that answers each
// measure request, so the Direct pass runs as it does on a device (see
// UPSTREAM.md). Where the graph declines, the pinned values are also the
// solver's.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/solver_parity.dart';

/// Every pass went to the solver, so both paths agree by construction.
void expectSolver(List<ParityPass> passes) {
  for (final pass in passes) {
    expect(pass.differences, isEmpty);
    expect(pass.graphResolved, isFalse, reason: 'expected the solver path');
  }
}

/// Every pass resolved on the graph, as Android lays it out.
void expectAndroidOnGraph(List<ParityPass> passes) {
  for (final pass in passes) {
    expect(pass.android, isEmpty);
    expect(pass.graphResolved, isTrue, reason: 'expected the graph path');
  }
}

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

Barrier barrier(
  ConstraintWidgetContainer root,
  String name,
  int type,
  List<ConstraintWidget> references, {
  int margin = 0,
  bool allowsGone = true,
}) {
  final b = Barrier.named(name)
    ..setBarrierType(type)
    ..setMargin(margin)
    ..setAllowsGoneWidget(allowsGone);
  for (final reference in references) {
    b.add(reference);
  }
  root.add(b);
  return b;
}

String frame(ConstraintWidget w) =>
    '(${w.getX()}, ${w.getY()}) ${w.getWidth()} x ${w.getHeight()}';

ConstraintWidget child(ConstraintWidgetContainer root, String name) =>
    root.getChildren().firstWhere((c) => c.getDebugName() == name);

/// B2, a left barrier over M (which follows B), only may follow B when B
/// moves right, it does not have to: B2's bound is on its left. The solver
/// would move B right and leave B2 behind, because following would push D0
/// and D1 further past the container's right edge. Android's Direct pass
/// places R, then B over it, M, B2 and the rest, and Barrier.addToSolver
/// holds a barrier the pass placed, so nothing moves.
void optionalFollower(ConstraintWidgetContainer root) {
  final r = widget(root, 'R', 100, 20);
  r.connect(.left, root, .left);
  r.connect(.top, root, .top);
  final b = barrier(root, 'B', Barrier.right, [r]);
  final m = widget(root, 'M', 50, 20);
  m.connect(.left, b, .right);
  m.connect(.top, root, .top, 30);
  final b2 = barrier(root, 'B2', Barrier.left, [m]);
  for (var i = 0; i < 2; i++) {
    // 140 wide in the 100 px before B: they push B right by 40.
    final e = widget(root, 'E$i', 140, 20);
    e.connect(.left, root, .left);
    e.connect(.right, b, .left);
    e.setHorizontalBiasPercent(0);
    e.connect(.top, root, .top, 60 + 30 * i);
  }
  for (var i = 0; i < 2; i++) {
    // Exactly as wide as the space past B2.
    final d = widget(root, 'D$i', 500, 20);
    d.connect(.left, b2, .right);
    d.connect(.right, root, .right);
    d.connect(.top, root, .top, 200 + 30 * i);
  }
}

/// b is centered at exactly -1 (80 px in the 66 px between its links, which
/// start at 6), which the graph's (int) (0.5 + x) rounds to 0.
void centeredAtMinusOne(ConstraintWidgetContainer root) {
  final a = widget(root, 'a', 94, 34);
  final b = widget(root, 'b', 80, 14);
  final bar = barrier(
    root,
    'bar',
    Barrier.right,
    [b],
    margin: 28,
    allowsGone: false,
  );
  final after = widget(root, 'after', 40, 20);
  b.connect(.left, a, .left, 6);
  b.connect(.right, a, .right, 22);
  b.connect(.top, a, .bottom, 4);
  after.connect(.left, bar, .right);
  after.connect(.top, root, .top);
}

/// A wrap-content widget centered at -1, whose size the solver reports a
/// pixel smaller.
void wrapAtMinusOne(ConstraintWidgetContainer root) {
  final w0 = widget(root, 'w0', 104, 88);
  w0.setHorizontalDimensionBehaviour(.wrapContent);
  final b0 = barrier(root, 'b0', Barrier.right, [w0], margin: 6);
  final b1 = barrier(root, 'b1', Barrier.left, [w0]);
  final w1 = widget(root, 'w1', 80, 54);
  w1.setHorizontalDimensionBehaviour(.wrapContent);
  w1.connect(.left, b0, .left);
  w1.connect(.right, b1, .right, 32);
  w1.connect(.top, root, .top, 14);
  w0.connect(.top, w1, .bottom);
}

/// A spread width with a min, both links on w0's right edge, referenced by a
/// barrier that a wider widget holds further right: the solver is free to
/// size it anywhere between its min and its max.
void sameAnchorSpread(ConstraintWidgetContainer root, {int max = 0}) {
  final w0 = widget(root, 'w0', 60, 20);
  final x = widget(root, 'x', 300, 20);
  final m = widget(root, 'm', 30, 20);
  w0.connect(.left, root, .left, 200);
  w0.connect(.top, root, .top);
  x.connect(.left, root, .left);
  x.connect(.top, root, .top, 100);
  m.connect(.left, w0, .right, 6);
  m.connect(.right, w0, .right, 10);
  m.connect(.top, root, .top, 50);
  m.setHorizontalDimensionBehaviour(.matchConstraint);
  m.setHorizontalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
    8,
    max,
    1,
  );
  barrier(root, 'bar', Barrier.right, [m, x]);
}

/// A percent width whose min is above the percent.
void percentBelowMin(ConstraintWidgetContainer root) {
  final a = widget(root, 'a', 10, 40);
  a.connect(.left, root, .left, 10);
  a.connect(.right, root, .right, 10);
  a.connect(.top, root, .top);
  a.setHorizontalDimensionBehaviour(.matchConstraint);
  a.setHorizontalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
    200,
    0,
    0.25,
  );
  final b = barrier(root, 'bar', Barrier.right, [a]);
  final after = widget(root, 'after', 20, 20);
  after.connect(.left, b, .right);
  after.connect(.top, root, .top, 50);
}

/// A fill linked to a barrier, with a widget linked across it that cannot
/// fit: the fill's bounds checks against a barrier are soft, so the solver
/// shrinks it. (Android's Direct pass places both widgets itself, w2 at
/// 179, which the solver does not reproduce; the check declines such a fill
/// whether or not the Direct pass places it.)
void barrierFillWithDependent(ConstraintWidgetContainer root) {
  final w0 = widget(root, 'w0', 160, 20);
  w0.setHorizontalDimensionBehaviour(.wrapContent);
  w0.setHorizontalBiasPercent(0);
  w0.connect(.left, root, .left, 16);
  w0.connect(.right, root, .right);
  final b0 = barrier(root, 'b0', Barrier.right, [w0], margin: 28);
  final w1 = widget(root, 'w1', 128, 44);
  w1.setHorizontalDimensionBehaviour(.matchConstraint);
  w1.connect(.left, b0, .right);
  w1.connect(.right, b0, .right);
  w1.connect(.top, root, .top, 100);
  final w2 = widget(root, 'w2', 50, 50);
  w2.connect(.left, w1, .right);
  w2.connect(.right, w1, .left);
  w2.connect(.top, root, .top, 160);
}

/// A percent width (a quarter of 825 px, 206.25) centered between a barrier
/// and the container's end: the solver centers the exact size and rounds
/// each edge, the graph rounds the size first.
void percentCentered(ConstraintWidgetContainer root) {
  final label2 = ConstraintWidget.sizeNamed('label2', 84, 17);
  root.add(label2);
  final labelEnd = Barrier.named('labelEnd');
  labelEnd.add(label2);
  root.add(labelEnd);
  final value1 = ConstraintWidget.sizeNamed('value1', 180, 31);
  root.add(value1);
  value1.connect(.left, labelEnd, .right);
  value1.setHorizontalDimensionBehaviour(.matchConstraint);
  value1.setHorizontalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
    0,
    0,
    0.25,
  );
  value1.connect(.right, root, .right);
}

/// A percent width of 64.5 px linked only at its end: the solver rounds its
/// start from there.
void percentEnd(ConstraintWidgetContainer root) {
  final w0 = ConstraintWidget.sizeNamed('w0', 79, 47);
  final b0 = Barrier.named('b0');
  root.add(w0);
  root.add(b0);
  b0.add(w0);
  w0.connect(.right, root, .right);
  w0.setHorizontalDimensionBehaviour(.matchConstraint);
  w0.setHorizontalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
    0,
    0,
    0.25,
  );
}

/// A percent width (209.5 px) offset from a barrier over another percent
/// width (83.8 px): the solver adds the two fractions before it rounds.
void percentSum(ConstraintWidgetContainer root) {
  final w0 = ConstraintWidget.sizeNamed('w0', 126, 81);
  final w1 = ConstraintWidget.sizeNamed('w1', 63, 32);
  final b0 = Barrier.named('b0');
  b0.setBarrierType(Barrier.right);
  root.add(b0);
  root.add(w0);
  root.add(w1);
  b0.add(w1);
  w0.connect(.left, b0, .right);
  w0.setHorizontalDimensionBehaviour(.matchConstraint);
  w0.setHorizontalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
    0,
    0,
    0.5,
  );
  w1.setHorizontalDimensionBehaviour(.matchConstraint);
  w1.setHorizontalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
    0,
    0,
    0.2,
  );
}

/// A percent width (154 px) wider than the 151 px between its links, with a
/// max at the percent size: the solver gives up the percent size and keeps
/// it between its links.
void percentSqueezed(ConstraintWidgetContainer root) {
  final value0 = ConstraintWidget.sizeNamed('value0', 89, 22);
  root.add(value0);
  final label2 = ConstraintWidget.sizeNamed('label2', 129, 18);
  root.add(label2);
  label2.connect(.left, root, .left, 16);
  final labelEnd = Barrier.named('labelEnd');
  labelEnd.setBarrierType(Barrier.right);
  labelEnd.add(label2);
  root.add(labelEnd);
  value0.connect(.left, labelEnd, .right, 12);
  value0.setHorizontalDimensionBehaviour(.matchConstraint);
  value0.setHorizontalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
    0,
    154,
    0.5,
  );
  value0.connect(.right, root, .right);
}

/// A chain whose members do not fit between its ends (a guideline and the
/// same guideline 16 px up): the solver gives up the end margin.
void chainOverflow(ConstraintWidgetContainer root) {
  final g0 = Guideline()..setDebugName('g0');
  root.add(g0);
  g0.setGuideEnd(183);
  final w0 = ConstraintWidget.sizeNamed('w0', 122, 60);
  final w1 = ConstraintWidget.sizeNamed('w1', 59, 21);
  final b0 = Barrier.named('b0');
  root.add(w0);
  root.add(w1);
  root.add(b0);
  b0.add(w0);
  w0.connect(.top, g0, .top);
  w0.connect(.bottom, w1, .top);
  w1.connect(.top, w0, .bottom);
  w1.connect(.bottom, g0, .top, 16);
}

/// A chain with a percent member (97.5 px): the graph spreads the rounded
/// size, the solver the exact one.
void chainPercent(ConstraintWidgetContainer root) {
  final w1 = ConstraintWidget.sizeNamed('w1', 124, 50);
  final w2 = ConstraintWidget.sizeNamed('w2', 30, 90);
  final w3 = ConstraintWidget.sizeNamed('w3', 112, 32);
  final w4 = ConstraintWidget.sizeNamed('w4', 64, 58);
  final b0 = Barrier.named('b0');
  root.add(w1);
  root.add(w4);
  root.add(b0);
  root.add(w2);
  root.add(w3);
  b0.add(w3);
  w2.connect(.top, w1, .bottom);
  w2.connect(.bottom, w3, .top);
  w3.connect(.top, w2, .bottom);
  w3.connect(.bottom, w4, .top);
  w4.connect(.bottom, root, .bottom);
  w3.setVerticalDimensionBehaviour(.matchConstraint);
  w3.setVerticalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
    0,
    0,
    0.25,
  );
}

/// A bottom barrier over the members of a spread-inside chain: its pulls
/// tie with the chain's gaps (both STRENGTH_HIGHEST), and the solver moves
/// the members down to it.
void barrierOverChain(ConstraintWidgetContainer root) {
  final w0 = ConstraintWidget.sizeNamed('w0', 21, 86);
  final w1 = ConstraintWidget.sizeNamed('w1', 81, 19);
  final w2 = ConstraintWidget.sizeNamed('w2', 31, 46);
  final w3 = ConstraintWidget.sizeNamed('w3', 54, 22);
  final b1 = Barrier.named('b1');
  b1.setBarrierType(Barrier.bottom);
  root.add(w1);
  root.add(w3);
  root.add(b1);
  root.add(w2);
  root.add(w0);
  b1.add(w1);
  b1.add(w3);
  b1.add(w2);
  w0.connect(.top, root, .top);
  w0.connect(.bottom, w1, .top);
  w1.connect(.top, w0, .bottom);
  w1.connect(.bottom, w2, .top);
  w2.connect(.top, w1, .bottom);
  w2.connect(.bottom, w3, .top);
  w3.connect(.top, w2, .bottom);
  w3.connect(.bottom, root, .bottom);
  w0.setVerticalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
}

/// A caption centered under a spread chain member whose edges sit at a
/// third of a pixel: the graph centers it under the rounded edges.
void chainCascade(ConstraintWidgetContainer root) {
  final a = ConstraintWidget.sizeNamed('a', 50, 20);
  final b = ConstraintWidget.sizeNamed('b', 50, 20);
  final cap = ConstraintWidget.sizeNamed('cap', 31, 12);
  root.add(a);
  root.add(b);
  root.add(cap);
  a.connect(.left, root, .left);
  a.connect(.right, b, .left);
  b.connect(.left, a, .right);
  b.connect(.right, root, .right);
  a.connect(.top, root, .top);
  b.connect(.top, root, .top);
  cap.connect(.left, b, .left);
  cap.connect(.right, b, .right);
  cap.connect(.top, b, .bottom, 4);
  final bottom = Barrier.named('bottom');
  bottom.setBarrierType(Barrier.bottom);
  bottom.add(a);
  bottom.add(b);
  root.add(bottom);
  final f = ConstraintWidget.sizeNamed('f', 40, 20);
  root.add(f);
  f.connect(.top, bottom, .bottom, 8);
}

/// A widget centered with a negative margin between links that the Direct
/// pass does not place (one leads to an unlinked widget): the solver leaves
/// the negative margin out of its centering.
void negativeMarginCentered(ConstraintWidgetContainer root) {
  final w0 = ConstraintWidget.sizeNamed('w0', 148, 15);
  final w1 = ConstraintWidget.sizeNamed('w1', 57, 26);
  final b0 = Barrier.named('b0');
  root.add(w1);
  root.add(w0);
  root.add(b0);
  b0.add(w0);
  w1.connect(.left, root, .right, -11);
  w1.connect(.right, w0, .left);
}

/// A widget linked to a gone match-parent widget: the solver keeps the gone
/// widget against the container, the graph collapses it at 0.
void matchParentGone(ConstraintWidgetContainer root) {
  final w0 = ConstraintWidget.sizeNamed('w0', 14, 92);
  final w1 = ConstraintWidget.sizeNamed('w1', 72, 22);
  final w2 = ConstraintWidget.sizeNamed('w2', 102, 110);
  final b2 = Barrier.named('b2');
  root.add(w1);
  root.add(b2);
  root.add(w0);
  root.add(w2);
  b2.add(w0);
  w1.connect(.left, w2, .right);
  w2.setHorizontalDimensionBehaviour(.matchParent);
  w2.setVisibility(ConstraintWidget.GONE);
}

/// A widget centered between a barrier's top and its bottom, with a
/// negative margin: the Direct pass sees one position and centers the
/// widget on it without the margins, the graph applies them.
void directPoint(ConstraintWidgetContainer root) {
  final g0 = Guideline()..setDebugName('g0');
  g0.setGuidePercent(0.5);
  root.add(g0);
  final w2 = ConstraintWidget.sizeNamed('w2', 26, 12);
  final b0 = Barrier.named('b0');
  b0.setBarrierType(Barrier.top);
  root.add(b0);
  root.add(w2);
  b0.add(g0);
  w2.connect(.top, b0, .top);
  w2.connect(.bottom, b0, .bottom, -14);
}

/// A gone widget whose vertical links cross (its top on a guideline below
/// the container's top, which its bottom is linked to) on a half pixel:
/// the Direct pass floors the half pixel, the graph rounds it, and the
/// widget centered against it follows.
void crossedGone(ConstraintWidgetContainer root) {
  final g0 = Guideline()..setDebugName('g0');
  root.add(g0);
  g0.setGuideBegin(119);
  final w1 = ConstraintWidget.sizeNamed('w1', 52, 55);
  root.add(w1);
  w1.connect(.top, g0, .top);
  w1.connect(.bottom, root, .top);
  w1.setVisibility(ConstraintWidget.GONE);
  final w0 = ConstraintWidget.sizeNamed('w0', 12, 19);
  root.add(w0);
  w0.connect(.top, w1, .bottom);
  w0.connect(.bottom, root, .bottom);
  final b0 = Barrier.named('b0');
  root.add(b0);
  b0.add(w0);
}

/// A 1.5 ratio width over a 103 px height: Android truncates 154.5 to 154,
/// the graph rounds it to 155.
void ratioTruncated(ConstraintWidgetContainer root) {
  final w1 = ConstraintWidget.sizeNamed('w1', 95, 103);
  final b1 = Barrier.named('b1');
  root.add(b1);
  root.add(w1);
  b1.add(w1);
  w1.setHorizontalDimensionBehaviour(.matchConstraint);
  w1.setDimensionRatio(1.5, ConstraintWidget.HORIZONTAL);
}

/// A percent width that also has a ratio: Android sizes it by the percent,
/// the graph by the ratio.
void ratioWithPercent(ConstraintWidgetContainer root) {
  final w1 = ConstraintWidget.sizeNamed('w1', 70, 100);
  final b0 = Barrier.named('b0');
  root.add(b0);
  root.add(w1);
  b0.add(w1);
  w1.setHorizontalDimensionBehaviour(.matchConstraint);
  w1.setHorizontalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
    0,
    198,
    0.5,
  );
  w1.setDimensionRatio(0.5, ConstraintWidget.VERTICAL);
}

/// A chain member whose width is measured only once its height (linked to a
/// barrier) is known, after the chain was laid out: the graph leaves both
/// members at 0.
void chainUnmeasured(ConstraintWidgetContainer root) {
  final w0 = ConstraintWidget.sizeNamed('w0', 61, 21);
  final w1 = ConstraintWidget.sizeNamed('w1', 66, 21);
  final b0 = Barrier.named('b0');
  b0.setBarrierType(Barrier.bottom);
  root.add(w0);
  root.add(w1);
  root.add(b0);
  b0.add(w0);
  w0.connect(.left, root, .left);
  w0.connect(.right, w1, .left);
  w1.connect(.left, w0, .right);
  w1.connect(.right, root, .right);
  w1.setHorizontalDimensionBehaviour(.wrapContent);
  w1.connect(.top, b0, .bottom);
  w1.connect(.bottom, root, .bottom);
  w1.setVerticalDimensionBehaviour(.matchConstraint);
}

/// A width filling between the edges of a widget measured late: the graph
/// keeps the fill at its first measure.
void fillUnmeasured(ConstraintWidgetContainer root) {
  final w0 = ConstraintWidget.sizeNamed('w0', 130, 16);
  final w2 = ConstraintWidget.sizeNamed('w2', 22, 74);
  final b2 = Barrier.named('b2');
  root.add(w2);
  root.add(b2);
  root.add(w0);
  b2.add(w2);
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

/// A chain of match-constraint members between one guideline and itself:
/// the solver gives them no width, the graph leaves them at their measured
/// widths.
void chainZeroSpace(ConstraintWidgetContainer root) {
  final g0 = Guideline()..setDebugName('g0');
  g0.setOrientation(Guideline.vertical);
  root.add(g0);
  g0.setGuideEnd(139);
  final w0 = ConstraintWidget.sizeNamed('w0', 129, 81);
  final w1 = ConstraintWidget.sizeNamed('w1', 91, 51);
  final b1 = Barrier.named('b1');
  b1.setBarrierType(Barrier.top);
  root.add(w1);
  root.add(b1);
  root.add(w0);
  b1.add(w1);
  w0.connect(.left, g0, .left);
  w0.connect(.right, w1, .left);
  w1.connect(.left, w0, .right);
  w1.connect(.right, g0, .left);
  w0.setHorizontalDimensionBehaviour(.matchConstraint);
  w1.setHorizontalDimensionBehaviour(.matchConstraint);
}

/// A widget linked to a gone widget whose anchor was reset since: the reset
/// forgets the link, so the solver leaves the gone widget out and the link
/// reads a free variable.
void skippedGone(ConstraintWidgetContainer root) {
  final w4 = ConstraintWidget.sizeNamed('w4', 12, 90);
  final w5 = ConstraintWidget.sizeNamed('w5', 52, 88);
  final b0 = Barrier.named('b0');
  root.add(b0);
  root.add(w4);
  root.add(w5);
  b0.add(w4);
  w4.connect(.bottom, w5, .top);
  w5.connect(.bottom, root, .bottom);
  w5.getAnchor(.top)!.reset();
  w5.setVisibility(ConstraintWidget.GONE);
}

/// A match-constraint width with a min, filling up to a barrier with a
/// negative margin: the solver centers it in the space without the negative
/// margin.
void boundedFillNegativeMargin(ConstraintWidgetContainer root) {
  final w2 = ConstraintWidget.sizeNamed('w2', 98, 73);
  final w3 = ConstraintWidget.sizeNamed('w3', 45, 52);
  final b2 = Barrier.named('b2');
  b2.setBarrierType(Barrier.right);
  root.add(b2);
  root.add(w2);
  root.add(w3);
  b2.add(w2);
  w3.connect(.left, w2, .left);
  w3.connect(.right, b2, .right, -7);
  w3.setHorizontalDimensionBehaviour(.matchConstraint);
  w3.setHorizontalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
    30,
    0,
    1.0,
  );
}

/// value sits 4 px below the baseline of name, right of a barrier over it.
/// Upstream's graph links a baseline to its target without the link's
/// margin; Android's Direct pass and solver both add it, and so does this
/// port's graph (see graph_parity_test.dart for layouts without a barrier).
void baselineMargin(ConstraintWidgetContainer root) {
  final name = widget(root, 'name', 120, 20, baseline: 15);
  name.connect(.left, root, .left, 16);
  name.connect(.top, root, .top, 20);
  final labelEnd = barrier(root, 'labelEnd', Barrier.right, [name]);
  final value = widget(root, 'value', 80, 14, baseline: 11);
  value.connect(.left, labelEnd, .right, 8);
  value.connect(.baseline, name, .baseline, 4);
}

/// w has no baseline (a widget without text measures a baseline distance
/// of 0) and its baseline is linked to the top of x; a barrier hangs below
/// w. Android ignores that link, so w sits where nothing links it; the
/// graph puts its top on the link's target.
void baselineWithoutBaseline(ConstraintWidgetContainer root) {
  final x = widget(root, 'x', 60, 30);
  x.connect(.left, root, .left, 10);
  x.connect(.top, root, .top, 50);
  final w = widget(root, 'w', 40, 20);
  w.connect(.left, root, .left, 100);
  w.connect(.baseline, x, .top);
  barrier(root, 'b0', Barrier.bottom, [w]);
}

/// f is gone below a percent-height widget, which the Direct pass does not
/// place, and l is baseline-aligned to f; a barrier hangs below l. f has a
/// baseline distance, set through the engine API (Android's measurer, and so
/// the Flutter adapter, gives a gone widget a baseline of 0): Android's
/// solver puts a gone widget's baseline on its top, the graph adds the
/// distance.
void goneBaseline(ConstraintWidgetContainer root) {
  final p = widget(root, 'p', 50, 10);
  p.setVerticalDimensionBehaviour(.matchConstraint);
  p.setVerticalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_PERCENT, 0, 0, 0.5);
  p.connect(.left, root, .left);
  p.connect(.top, root, .top);
  final f = widget(root, 'f', 92, 56, baseline: 19);
  f.setVisibility(ConstraintWidget.GONE);
  f.connect(.left, root, .left);
  f.connect(.top, p, .bottom);
  final l = widget(root, 'l', 60, 17, baseline: 13);
  l.connect(.left, root, .left, 100);
  l.connect(.baseline, f, .baseline);
  final b0 = barrier(root, 'b0', Barrier.bottom, [l]);
  final c = widget(root, 'c', 30, 30);
  c.connect(.left, root, .left, 5);
  c.connect(.top, b0, .bottom);
}

/// w1 is 85% of 648 px (550.8) high, placed by its baseline; w4 is centered
/// between w1's top and bottom. The solver puts w1's bottom the exact
/// percent size below its top, so w4 rounds differently.
void baselinePercent(ConstraintWidgetContainer root) {
  final w0 = widget(root, 'w0', 22, 148, baseline: 131);
  final b1 = Barrier.named('b1');
  root.add(b1);
  final w3 = widget(root, 'w3', 156, 133);
  b1.add(w3);
  final w1 = widget(root, 'w1', 41, 122, baseline: 79);
  final w4 = widget(root, 'w4', 107, 128);
  w1.setVerticalDimensionBehaviour(.matchConstraint);
  w1.setVerticalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
    0,
    0,
    0.85,
  );
  w1.connect(.baseline, w0, .baseline);
  w4.connect(.centerY, w1, .centerY);
}

/// badge is centered with a bias of 0.7 between the top and a barrier at 79:
/// 0.7 x 45 is 31.5 in Java floats, which the Direct pass works in (32), and
/// 31.499999999999996 in doubles (the graph: 31).
void floatTie(ConstraintWidgetContainer root) {
  final a = widget(root, 'a', 60, 30);
  a.connect(.left, root, .left);
  a.connect(.top, root, .top, 49);
  final bottom = barrier(root, 'bottom', Barrier.bottom, [a]);
  final badge = widget(root, 'badge', 36, 34);
  badge.connect(.left, root, .left, 300);
  badge.setVerticalBiasPercent(0.7);
  badge.connect(.top, root, .top);
  badge.connect(.bottom, bottom, .bottom);
}

/// w0, 141 px in the 87 px right of a 70% guideline, is centered with a bias
/// of 0.4: the Direct pass truncates 0.4 x -54 to -21, the graph rounds it
/// to -22.
void overflowTruncated(ConstraintWidgetContainer root) {
  final gv = Guideline()
    ..setDebugName('gv')
    ..setOrientation(Guideline.vertical)
    ..setGuidePercent(0.7);
  root.add(gv);
  final w0 = widget(root, 'w0', 141, 21);
  w0.setHorizontalBiasPercent(0.4);
  w0.connect(.left, gv, .right, 7);
  w0.connect(.right, root, .right);
  barrier(root, 'b2', Barrier.right, [w0]);
}

/// w1's height is match-constraint with a max of 54 and no links, and its
/// minimum height (setMinHeight, engine API only: the Flutter adapter never
/// sets one) is 78. The graph applies the minimum over the max; the solver
/// keeps the max.
void minAboveMax(ConstraintWidgetContainer root) {
  final w0 = widget(root, 'w0', 65, 100);
  barrier(root, 'b2', Barrier.left, [w0]);
  final w1 = widget(root, 'w1', 35, 23);
  w1.setVerticalDimensionBehaviour(.matchConstraint);
  w1.setVerticalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 54, 1);
  w1.setMinHeight(78);
}

/// w0's percent height (62.1 px) is below its minimum height of 68, so
/// setFrame raises it and Android solves again without the Direct pass,
/// which leaves w1 centered right of the guideline at its exact 328.5 px.
void minOverride(ConstraintWidgetContainer root) {
  final g1 = Guideline()
    ..setDebugName('g1')
    ..setOrientation(Guideline.vertical)
    ..setGuidePercent(0.75);
  root.add(g1);
  final w0 = widget(root, 'w0', 41, 45);
  barrier(root, 'b0', Barrier.left, [w0]);
  w0.setVerticalDimensionBehaviour(.matchConstraint);
  w0.setVerticalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
    0,
    218,
    0.45,
  );
  w0.setMinHeight(68);
  final w1 = widget(root, 'w1', 52, 28);
  w1.connect(.left, g1, .left);
  w1.connect(.right, root, .right);
}

/// w2's left edge is linked to the guideline g1, then to the container, and
/// then reset: g1 still lists it as a dependent, now with no target. p's
/// percent width (121.5 px, centered) makes the barrier check model the
/// Direct pass, which reaches w2 from g1 and centers it. Upstream's Direct
/// pass throws a NullPointerException there (Android at
/// OPTIMIZATION_STANDARD crashes on this layout); the model must not throw,
/// and the layout goes to the solver.
void staleLink(ConstraintWidgetContainer root) {
  final a = widget(root, 'a', 50, 20);
  a.connect(.left, root, .left, 10);
  a.connect(.top, root, .top, 10);
  barrier(root, 'b0', Barrier.right, [a]);
  final g1 = Guideline()
    ..setDebugName('g1')
    ..setOrientation(Guideline.vertical)
    ..setGuideBegin(100);
  root.add(g1);
  final w2 = widget(root, 'w2', 55, 30);
  w2.connect(.left, g1, .left);
  w2.connect(.left, root, .left, 7);
  w2.mLeft.reset();
  w2.connect(.right, root, .right, 16);
  w2.connect(.top, root, .top, 50);
  final p = widget(root, 'p', 50, 20);
  p.setHorizontalDimensionBehaviour(.matchConstraint);
  p.setHorizontalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
    0,
    0,
    0.3,
  );
  p.connect(.left, root, .left);
  p.connect(.right, root, .right);
  p.connect(.top, root, .top, 100);
}

/// A tab indicator linked to the second tab of a packed chain whose first
/// tab fills the space, and a barrier on the left of the indicator and of a
/// widget at the left edge. The barrier stays at that widget and pulls the
/// indicator to itself, and the pull reaches the chain through the
/// indicator's link: the filling tab gives way as it does when the barrier
/// references a member, and Android's solver puts both tabs at the left.
void chainPulledThroughLink(ConstraintWidgetContainer root) {
  final nav = widget(root, 'nav', 40, 40);
  final indicator = widget(root, 'indicator', 40, 2);
  final tab0 = widget(root, 'tab0', 30, 40);
  final tab2 = widget(root, 'tab2', 60, 40);
  final tab1 = widget(root, 'tab1', 170, 20);
  indicator.connect(.left, tab1, .left);
  tab0
    ..setHorizontalDimensionBehaviour(.matchConstraint)
    ..setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
  tab0.connect(.left, root, .left);
  tab0.connect(.right, tab1, .left);
  tab2.connect(.right, root, .right);
  tab1.connect(.left, tab0, .right);
  tab1.connect(.right, tab2, .left);
  barrier(root, 'b', Barrier.left, [indicator, nav]);
}

/// A widget the Direct pass reaches from a percent guideline only in its
/// last pass: its height fills between two anchors, so it waits for a
/// measure when the guideline's pass first runs, and upstream never marks a
/// guideline's pass done, so the last pass runs it again. Direct then
/// truncates the offset of the widget, which does not fit between the
/// guideline and the right edge (-41.54 px at a bias of 0.67), where the
/// graph rounds it.
void guidelineLastPass(ConstraintWidgetContainer root) {
  final s0 = ConstraintWidget.sizeNamed('s0', 50, 120);
  final b0 = Barrier.named('b0')..add(s0);
  root.add(b0);
  root.add(s0);
  final gv = Guideline()..setDebugName('gv');
  root.add(gv);
  final w1 = widget(root, 'w1', 168, 20);
  s0.connect(.top, root, .top);
  gv
    ..setOrientation(Guideline.vertical)
    ..setGuidePercent(0.6);
  w1
    ..setVerticalDimensionBehaviour(.matchConstraint)
    ..setHorizontalBiasPercent(0.67);
  w1.connect(.left, gv, .left, 16);
  w1.connect(.right, root, .right, 12);
  w1.connect(.top, s0, .top);
  w1.connect(.bottom, s0, .bottom);
}

/// A list whose first row ends in a gone value label, baseline-aligned to
/// the row's title, in the state the Flutter adapter leaves it: flagged as
/// having a baseline, at a distance of 0. Android measures the gone label
/// before its Direct pass (its measurer answers 0 x 0 with a baseline of 0,
/// which clears the flag), so the pass cannot place the label by its
/// baseline, nor the barrier under the row that counts it, and Android's
/// solver places the rows below, whose icons are centered on half pixels
/// (30 px on 21 and 17 px titles) that the graph rounds a row earlier.
void goneBaselineLabel(ConstraintWidgetContainer root) {
  final t0 = widget(root, 't0', 60, 20, baseline: 18);
  final label = widget(root, 'label', 0, 0)..setHasBaseline(true);
  final row0 = barrier(root, 'row0', Barrier.bottom, [label]);
  final d0 = widget(root, 'd0', 100, 1);
  final i1 = widget(root, 'i1', 30, 30);
  final t1 = widget(root, 't1', 100, 21);
  final row1 = barrier(root, 'row1', Barrier.bottom, [i1]);
  final d1 = widget(root, 'd1', 100, 1);
  final i2 = widget(root, 'i2', 30, 30);
  final t2 = widget(root, 't2', 50, 17);
  t0.connect(.top, root, .top);
  label.setVisibility(ConstraintWidget.GONE);
  label.connect(.baseline, t0, .baseline);
  d0.connect(.top, row0, .bottom);
  i1.connect(.top, t1, .top);
  i1.connect(.bottom, t1, .bottom);
  t1.connect(.top, d0, .bottom);
  d1.connect(.top, row1, .bottom);
  i2.connect(.top, t2, .top);
  i2.connect(.bottom, t2, .bottom);
  t2.connect(.top, d1, .bottom);
}

void main() {
  group('percent and ratio sizes, to the solver', () {
    test('a percent size centered on a fraction', () {
      expectSolver(layoutBothWays(width: 825, height: 521, percentCentered));
      final root = SolveCountingContainer(825, 521);
      percentCentered(root);
      root.layout();
      expect(frame(child(root, 'value1')), '(309, 0) 207 x 31');
    });

    test('a percent size with a fraction, linked at its end', () {
      expectSolver(layoutBothWays(width: 258, height: 715, percentEnd));
      final root = SolveCountingContainer(258, 715);
      percentEnd(root);
      root.layout();
      expect(frame(child(root, 'w0')), '(194, 0) 64 x 47');
      expect(frame(child(root, 'b0')), '(194, 0) 0 x 0');
    });

    test('a percent size with a fraction, offset from a fraction', () {
      expectSolver(layoutBothWays(width: 419, height: 900, percentSum));
      final root = SolveCountingContainer(419, 900);
      percentSum(root);
      root.layout();
      expect(frame(child(root, 'w0')), '(84, 0) 209 x 81');
    });

    test('a percent size wider than its space, at its max', () {
      expectSolver(layoutBothWays(width: 308, height: 899, percentSqueezed));
      final root = SolveCountingContainer(308, 899);
      percentSqueezed(root);
      root.layout();
      expect(frame(child(root, 'value0')), '(157, 0) 151 x 22');
    });

    test('a ratio size Android truncates', () {
      expectSolver(layoutBothWays(width: 569, height: 380, ratioTruncated));
      final root = SolveCountingContainer(569, 380);
      ratioTruncated(root);
      root.layout();
      expect(frame(child(root, 'w1')), '(0, 0) 154 x 103');
    });

    test('a percent size with a ratio', () {
      expectSolver(layoutBothWays(width: 284, height: 380, ratioWithPercent));
      final root = SolveCountingContainer(284, 380);
      ratioWithPercent(root);
      root.layout();
      expect(frame(child(root, 'w1')), '(0, 0) 142 x 100');
    });
  });

  group('chains, to the solver', () {
    test('a chain that overflows its ends', () {
      expectSolver(layoutBothWays(width: 841, height: 509, chainOverflow));
      final root = SolveCountingContainer(841, 509);
      chainOverflow(root);
      root.layout();
      expect(frame(child(root, 'w0')), '(0, 286) 122 x 60');
      expect(frame(child(root, 'w1')), '(0, 346) 59 x 21');
    });

    test('a chain with a percent member', () {
      expectSolver(layoutBothWays(width: 404, height: 390, chainPercent));
      final root = SolveCountingContainer(404, 390);
      chainPercent(root);
      root.layout();
      expect(frame(child(root, 'w2')), '(0, 82) 30 x 90');
      expect(frame(child(root, 'w3')), '(0, 203) 112 x 98');
    });

    test('a barrier over a spread-inside chain', () {
      expectSolver(layoutBothWays(width: 521, height: 685, barrierOverChain));
      final root = SolveCountingContainer(521, 685);
      barrierOverChain(root);
      root.layout();
      expect(frame(child(root, 'w1')), '(0, 598) 81 x 19');
      expect(frame(child(root, 'w2')), '(0, 617) 31 x 46');
    });

    test('a widget centered on a chain member', () {
      expectSolver(layoutBothWays(width: 302, height: 300, chainCascade));
      final root = SolveCountingContainer(302, 300);
      chainCascade(root);
      root.layout();
      expect(frame(child(root, 'cap')), '(194, 24) 31 x 12');
    });

    test('a chain with no space for its members', () {
      expectSolver(layoutBothWays(width: 408, height: 702, chainZeroSpace));
      final root = SolveCountingContainer(408, 702);
      chainZeroSpace(root);
      root.layout();
      expect(frame(child(root, 'w0')), '(269, 0) 0 x 81');
      expect(frame(child(root, 'w1')), '(269, 0) 0 x 51');
    });

    test('a chain member measured after its chain', () {
      expectSolver(layoutBothWays(width: 267, height: 623, chainUnmeasured));
      final root = SolveCountingContainer(267, 623);
      chainUnmeasured(root);
      root.layout();
      expect(frame(child(root, 'w0')), '(47, 0) 61 x 21');
      expect(frame(child(root, 'w1')), '(154, 21) 66 x 602');
    });
  });

  group('centering and links, to the solver', () {
    test('a negative centering margin the solver handles', () {
      expectSolver(
        layoutBothWays(width: 357, height: 673, negativeMarginCentered),
      );
      final root = SolveCountingContainer(357, 673);
      negativeMarginCentered(root);
      root.layout();
      expect(frame(child(root, 'w1')), '(150, 0) 57 x 26');
    });

    test('centered between two anchors at one position', () {
      expectSolver(layoutBothWays(width: 426, height: 343, directPoint));
      final root = SolveCountingContainer(426, 343);
      directPoint(root);
      root.layout();
      expect(frame(child(root, 'w2')), '(0, 166) 26 x 12');
    });

    test('a gone widget whose links cross on a half pixel', () {
      expectSolver(layoutBothWays(width: 871, height: 480, crossedGone));
      final root = SolveCountingContainer(871, 480);
      crossedGone(root);
      root.layout();
      expect(frame(child(root, 'w0')), '(0, 260) 12 x 19');
    });

    test('a bounded fill with a negative margin', () {
      expectSolver(
        layoutBothWays(width: 702, height: 561, boundedFillNegativeMargin),
      );
      final root = SolveCountingContainer(702, 561);
      boundedFillNegativeMargin(root);
      root.layout();
      expect(frame(child(root, 'w3')), '(0, 0) 98 x 52');
    });

    test('a link to a gone match-parent widget', () {
      expectSolver(layoutBothWays(width: 574, height: 246, matchParentGone));
      final root = SolveCountingContainer(574, 246);
      matchParentGone(root);
      root.layout();
      expect(frame(child(root, 'w1')), '(574, 0) 72 x 22');
    });

    test('a link to a gone widget the solver leaves out', () {
      expectSolver(layoutBothWays(width: 700, height: 472, skippedGone));
      final root = SolveCountingContainer(700, 472);
      skippedGone(root);
      root.layout();
      expect(frame(child(root, 'w4')), '(0, 0) 12 x 90');
    });

    test('a fill measured before its space', () {
      expectSolver(layoutBothWays(width: 404, height: 736, fillUnmeasured));
      final root = SolveCountingContainer(404, 736);
      fillUnmeasured(root);
      root.layout();
      expect(frame(child(root, 'w2')), '(0, 0) 130 x 74');
    });
  });

  group('a barrier that may stay behind', () {
    test('stays on the graph where the Direct pass places it', () {
      expectAndroidOnGraph(
        layoutBothWays(
          width: 600,
          height: 400,
          optionalFollower,
          android: true,
        ),
      );
      final root = SolveCountingContainer(600, 400);
      optionalFollower(root);
      root.layout();
      expect(frame(child(root, 'B')), '(100, 0) 0 x 0');
      expect(frame(child(root, 'M')), '(100, 30) 50 x 20');
      expect(frame(child(root, 'B2')), '(100, 0) 0 x 0');
    });
  });

  group('a widget centered just below 0', () {
    test('sends a barrier over it to the solver', () {
      expectSolver(layoutBothWays(width: 484, height: 200, centeredAtMinusOne));
      final root = SolveCountingContainer(484, 200);
      centeredAtMinusOne(root);
      root.layout();
      expect(frame(child(root, 'bar')), '(107, 0) 0 x 0');
      expect(frame(child(root, 'after')), '(107, 0) 40 x 20');
    });

    test('sends its own wrap-content size to the solver', () {
      expectSolver(layoutBothWays(width: 408, height: 660, wrapAtMinusOne));
      final root = SolveCountingContainer(408, 660);
      wrapAtMinusOne(root);
      root.layout();
      expect(frame(child(root, 'w1')), '(0, 14) 79 x 54');
    });
  });

  group('match-constraint sizes the solver chooses softly', () {
    test('a spread with a min, both links on one anchor', () {
      expectSolver(layoutBothWays(width: 400, height: 300, sameAnchorSpread));
      final root = SolveCountingContainer(400, 300);
      sameAnchorSpread(root);
      root.layout();
      expect(frame(child(root, 'm')), '(220, 50) 80 x 20');
    });

    test('a spread with a min and a max, both links on one anchor', () {
      expectSolver(
        layoutBothWays(
          width: 400,
          height: 300,
          (root) => sameAnchorSpread(root, max: 66),
        ),
      );
    });

    test('a percent below its min', () {
      expectSolver(layoutBothWays(width: 400, height: 300, percentBelowMin));
      final root = SolveCountingContainer(400, 300);
      percentBelowMin(root);
      root.layout();
      expect(frame(child(root, 'a')), '(10, 0) 380 x 40');
    });

    test('a fill linked to a barrier, with a widget that cannot fit', () {
      expectSolver(
        layoutBothWays(width: 262, height: 230, barrierFillWithDependent),
      );
    });
  });

  group('the default measurer', () {
    for (final vertical in [false, true]) {
      test('keeps a one-link spread ${vertical ? 'height' : 'width'} within '
          'its max, so a barrier over it stays on the graph', () {
        void build(ConstraintWidgetContainer root) {
          final a = widget(root, 'a', 120, 50);
          a.connect(.left, root, .left, 10);
          a.connect(.top, root, .top, 5);
          if (vertical) {
            a.setVerticalDimensionBehaviour(.matchConstraint);
            a.setVerticalMatchStyle(
              ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
              0,
              30,
              1,
            );
          } else {
            a.setHorizontalDimensionBehaviour(.matchConstraint);
            a.setHorizontalMatchStyle(
              ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
              0,
              80,
              1,
            );
          }
          final b = barrier(
            root,
            'b',
            vertical ? Barrier.bottom : Barrier.right,
            [
              a,
            ],
          );
          final after = widget(root, 'after', 20, 20);
          if (vertical) {
            after.connect(.top, b, .bottom);
          } else {
            after.connect(.left, b, .right);
          }
        }

        final pass = layoutBothWays(width: 400, height: 300, build).single;
        expect(pass.differences, isEmpty);
        expect(pass.graphResolved, isTrue);
      });
    }
  });

  group('a baseline link with a margin', () {
    test('stays on the graph, which adds the margin as Android does', () {
      expectAndroidOnGraph(
        layoutBothWays(width: 400, height: 300, baselineMargin, android: true),
      );
      final root = SolveCountingContainer(400, 300);
      baselineMargin(root);
      root.layout();
      expect(frame(child(root, 'value')), '(144, 28) 80 x 14');
    });
  });

  group('a baseline link from a widget without a baseline', () {
    test('goes to the solver', () {
      expectSolver(
        layoutBothWays(width: 400, height: 300, baselineWithoutBaseline),
      );
      final root = SolveCountingContainer(400, 300);
      baselineWithoutBaseline(root);
      root.layout();
      expect(frame(child(root, 'w')), '(100, 0) 40 x 20');
      expect(frame(child(root, 'b0')), '(0, 20) 0 x 0');
    });
  });

  group('a baseline link to a gone widget with a baseline', () {
    test('goes to the solver', () {
      expectSolver(layoutBothWays(width: 400, height: 400, goneBaseline));
      final root = SolveCountingContainer(400, 400);
      goneBaseline(root);
      root.layout();
      expect(frame(child(root, 'l')), '(100, 187) 60 x 17');
      expect(frame(child(root, 'b0')), '(0, 204) 0 x 0');
      expect(frame(child(root, 'c')), '(5, 204) 30 x 30');
    });
  });

  group('a percent height placed by its baseline', () {
    test('goes to the solver', () {
      expectSolver(layoutBothWays(width: 652, height: 648, baselinePercent));
      final root = SolveCountingContainer(652, 648);
      baselinePercent(root);
      root.layout();
      expect(frame(child(root, 'w1')), '(0, 52) 41 x 551');
      expect(frame(child(root, 'w4')), '(0, 263) 107 x 128');
    });
  });

  group('a centering the Direct pass works out differently', () {
    test('in floats, on a half pixel, goes to the solver', () {
      expectSolver(layoutBothWays(width: 400, height: 300, floatTie));
      final root = SolveCountingContainer(400, 300);
      floatTie(root);
      root.layout();
      expect(frame(child(root, 'badge')), '(300, 32) 36 x 34');
    });

    test('truncated, for a widget that does not fit, goes to the solver', () {
      expectSolver(layoutBothWays(width: 312, height: 319, overflowTruncated));
      final root = SolveCountingContainer(312, 319);
      overflowTruncated(root);
      root.layout();
      expect(frame(child(root, 'w0')), '(204, 0) 141 x 21');
      expect(frame(child(root, 'b2')), '(345, 0) 0 x 0');
    });
  });

  group('a minimum height set on the widget', () {
    test('above a match-constraint max goes to the solver', () {
      expectSolver(layoutBothWays(width: 171, height: 874, minAboveMax));
      final root = SolveCountingContainer(171, 874);
      minAboveMax(root);
      root.layout();
      expect(frame(child(root, 'w1')), '(0, 0) 35 x 54');
    });

    test('that the solver overrides goes to the solver', () {
      expectSolver(layoutBothWays(width: 438, height: 138, minOverride));
      final root = SolveCountingContainer(438, 138);
      minOverride(root);
      root.layout();
      expect(frame(child(root, 'w0')), '(0, 0) 41 x 68');
      expect(frame(child(root, 'w1')), '(357, 0) 52 x 28');
    });
  });

  group('a gone widget placed by its baseline', () {
    test('that Android measures without one goes to the solver', () {
      expectSolver(
        layoutBothWays(width: 554, height: 1021, goneBaselineLabel),
      );
      final root = SolveCountingContainer(554, 1021);
      goneBaselineLabel(root);
      root.layout();
      expect(frame(child(root, 'i1')), '(0, 15) 30 x 30');
      expect(frame(child(root, 'i2')), '(0, 39) 30 x 30');
    });
  });

  group('a guideline the Direct pass comes back to', () {
    test(
      'places a widget that waited for a measure, so goes to the solver',
      () {
        expectSolver(
          layoutBothWays(width: 334, height: 923, guidelineLastPass),
        );
        final root = SolveCountingContainer(334, 923);
        guidelineLastPass(root);
        root.layout();
        expect(frame(child(root, 'w1')), '(175, 0) 168 x 120');
      },
    );
  });

  group('a barrier over a widget linked to a chain member', () {
    test('pulls the chain as through a member, so goes to the solver', () {
      expectSolver(
        layoutBothWays(width: 358, height: 244, chainPulledThroughLink),
      );
      final root = SolveCountingContainer(358, 244);
      chainPulledThroughLink(root);
      root.layout();
      expect(frame(child(root, 'tab0')), '(0, 0) 0 x 40');
      expect(frame(child(root, 'tab1')), '(0, 0) 170 x 20');
      expect(frame(child(root, 'indicator')), '(0, 0) 40 x 2');
    });
  });

  group('a stale dependent with no target', () {
    test('goes to the solver without a throw', () {
      final passes = layoutBothWays(width: 405, height: 300, staleLink);
      expect(passes.single.graphResolved, isFalse);
      expect(passes.single.differences, isEmpty);
    });
  });
}
