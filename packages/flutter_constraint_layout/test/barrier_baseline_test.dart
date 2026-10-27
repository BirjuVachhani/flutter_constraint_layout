// A child's baseline linked to the top or bottom of a barrier (Android's
// layout_constraintBaseline_toBottomOf or _toTopOf with a Barrier's id), laid
// out through the real ConstraintLayout ("Common mistakes" in the README).
//
// Barrier.addToSolver asks the sides of the barrier, whatever its edge,
// whether a widget is centered on them: the top, then the bottom only when
// the top has none (and the left before the right the same way). Each ask
// (ConstraintAnchor.hasCenteredDependents) reads the opposite anchor of each
// anchor linked to that side, in link order, until one is connected. A
// baseline has none, so when one is read before a centered dependent,
// Android's solver throws a NullPointerException there
// (ConstraintAnchor.java 68), and the engine fails the same null check at
// the same call. Only a barrier the solver places is asked: addToSolver
// returns first for a barrier already placed, which the Direct pass places
// once it has placed every widget the barrier references, and at
// OptimizationLevel.none there is no Direct pass. The solver loop catches the
// error and prints it, as Android's prints its NullPointerException, and the
// frames are read back from the abandoned solve: a child it had not settled
// sits at (0, 0), keeping its size only where that is fixed (setFrame
// restores a FIXED size alone), so a .wrapContent or percent size comes
// out 0. Linking the child's top or bottom to the barrier instead asks
// nothing of the baseline, and the layout resolves.
//
// Java values are VOpDriver's at the pin (view path), from the op list
// quoted with each layout, run through
// packages/constraint_engine/tool/parity/java/jrun.sh at levels 257,0 with
// -Dprobe. Every printing measure printed one NullPointerException, at
// ConstraintAnchor.hasCenteredDependents. A `!ok-printed` geometry is one
// whose measure printed. On real Android views (the RoboOracle:
// ConstraintLayout 2.2.1 under Robolectric, with the pinned core and with
// core 1.1.1) the first layout below prints too, with the same frames, and
// the control layout resolves as here.

import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// The line the solver loop prints when the baseline link fails.
const nullCheck = 'EXCEPTION : Null check operator used on a null value';

/// A leaf of a natural [width] x [height] (constrained), with an optional
/// alphabetic [baseline]: the oracle's `box` content.
class Leaf extends LeafRenderObjectWidget {
  const Leaf(this.width, this.height, {this.baseline, super.key});

  final double width;
  final double height;
  final double? baseline;

  @override
  RenderLeaf createRenderObject(BuildContext context) => RenderLeaf(this);

  @override
  void updateRenderObject(BuildContext context, RenderLeaf renderObject) =>
      renderObject.leaf = this;
}

class RenderLeaf extends RenderBox {
  RenderLeaf(this._leaf);

  Leaf _leaf;
  set leaf(Leaf value) {
    if (value.width == _leaf.width &&
        value.height == _leaf.height &&
        value.baseline == _leaf.baseline) {
      return;
    }
    _leaf = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    size = constraints.constrain(Size(_leaf.width, _leaf.height));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(Size(_leaf.width, _leaf.height));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _leaf.baseline;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) => _leaf.baseline;
}

/// [children] in a 400 x 300 ConstraintLayout at [level]: the oracle's
/// `R 400 300` measured under `cspec E 400 E 300`.
Widget host(
  List<Widget> children, {
  OptimizationLevel level = OptimizationLevel.standard,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 400,
      height: 300,
      child: ConstraintLayout(optimizationLevel: level, children: children),
    ),
  ),
);

/// [children] in a ConstraintLayout at [level] that is the one item of a
/// 400 wide ListView, so its height is unbounded and wraps its children: the
/// oracle's `R 400 0;wraph` measured under `cspec E 400 U 0`.
Widget listItem(
  List<Widget> children, {
  OptimizationLevel level = OptimizationLevel.standard,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 400,
      height: 600,
      child: ListView(
        children: [
          ConstraintLayout(optimizationLevel: level, children: children),
        ],
      ),
    ),
  ),
);

/// Pumps [widget] and returns the lines printed while it was laid out. A
/// Zone print override takes them, so the test's output stays clean.
Future<List<String>> pumpCapturingPrints(
  WidgetTester tester,
  Widget widget,
) async {
  final printed = <String>[];
  await runZoned(
    () => tester.pumpWidget(widget),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
  return printed;
}

/// The layout's size and the frame of each child, named by [ids] in child
/// order, in the oracle's geometry format.
String geometry(WidgetTester tester, List<String> ids) {
  // A list item that comes out 0 high counts as offstage.
  final layout = tester.renderObject<RenderConstraintLayout>(
    find.byType(ConstraintLayout, skipOffstage: false),
  );
  final children = layout.getChildrenAsList();
  expect(children, hasLength(ids.length));
  String n(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
  final parts = ['root ${n(layout.size.width)} x ${n(layout.size.height)}'];
  for (var i = 0; i < ids.length; i++) {
    final offset = (children[i].parentData! as BoxParentData).offset;
    final size = children[i].size;
    parts.add(
      '${ids[i]}: (${n(offset.dx)}, ${n(offset.dy)}) '
      '${n(size.width)} x ${n(size.height)}',
    );
  }
  return parts.join(' | ');
}

/// `b b0;add b0;bt b0 <edge>;ref b0 <referenced>`.
Widget barrier(BarrierEdge edge, Symbol referenced) =>
    Barrier(id: #b0, edge: edge, referenced: [referenced]);

/// `w r 50 20;add r;ct r box 50 20 -1;c r T root T 10`.
Widget placedR() => Constrained(
  id: #r,
  top: .topOf(parent, margin: 10),
  width: .fixed(50),
  height: .fixed(20),
  child: const Leaf(50, 20),
);

/// `w r 50 20;add r;ct r box 50 20 -1;w r2 50 20;add r2;ct r2 box 50 20 -1;
/// c r T root T 10;c r B r2 T 0;c r2 T r B 0;c r2 B root B 0`: a vertical
/// chain, which Direct leaves to the solver.
List<Widget> chainedR() => [
  Constrained(
    id: #r,
    top: .topOf(parent, margin: 10),
    bottom: .topOf(#r2),
    width: .fixed(50),
    height: .fixed(20),
    child: const Leaf(50, 20),
  ),
  Constrained(
    id: #r2,
    top: .bottomOf(#r),
    bottom: .bottomOf(parent),
    width: .fixed(50),
    height: .fixed(20),
    child: const Leaf(50, 20),
  ),
];

/// `w t 60 20;add t;ct t box 60 20 15;c t S b0 B 0;c t L root L 0`, or with
/// [top] `c t T b0 B 0` in place of the baseline link.
Widget t({bool top = false}) => Constrained(
  id: #t,
  left: .leftOf(parent),
  baseline: top ? null : .bottomOf(#b0),
  top: top ? .bottomOf(#b0) : null,
  width: .fixed(60),
  height: .fixed(20),
  child: const Leaf(60, 20, baseline: 15),
);

/// The children of a list item, `w icon 40 40;add icon;ct icon box 40 40 -1;
/// w title 100 20;add title;ct title box 100 20 15;b bar;add bar;bt bar 3;
/// w sub 0 0;add sub;hb sub W;vb sub W;ct sub box 120 20 15;ref bar icon;
/// ref bar title;c icon L root L 16;c icon T root T 0;c icon B root B 0;
/// c title L icon R 16;c title T root T 8;c sub L icon R 16;c sub S bar B 0`:
/// an icon centered on the item's height, a title, a bottom barrier over
/// both, and a .wrapContent subtitle whose baseline links to the barrier, or
/// with [top] `c sub T bar B 0` in place of the baseline link.
List<Widget> listItemChildren({bool top = false}) => [
  Constrained(
    id: #icon,
    left: .leftOf(parent, margin: 16),
    top: .topOf(parent),
    bottom: .bottomOf(parent),
    width: .fixed(40),
    height: .fixed(40),
    child: const Leaf(40, 40),
  ),
  Constrained(
    id: #title,
    left: .rightOf(#icon, margin: 16),
    top: .topOf(parent, margin: 8),
    width: .fixed(100),
    height: .fixed(20),
    child: const Leaf(100, 20, baseline: 15),
  ),
  const Barrier(id: #bar, edge: .bottom, referenced: [#icon, #title]),
  Constrained(
    id: #sub,
    left: .rightOf(#icon, margin: 16),
    baseline: top ? null : .bottomOf(#bar),
    top: top ? .bottomOf(#bar) : null,
    child: const Leaf(120, 20, baseline: 15),
  ),
];

void main() {
  group('a baseline linked to the bottom of a bottom barrier', () {
    testWidgets('throws in the solve when the barrier tracks a chain member: '
        'every child at (0, 0) with its size', (tester) async {
      // R 400 300;b b0;add b0;bt b0 3;w r 50 20;add r;ct r box 50 20 -1;
      // w r2 50 20;add r2;ct r2 box 50 20 -1;ref b0 r;c r T root T 10;
      // c r B r2 T 0;c r2 T r B 0;c r2 B root B 0;w t 60 20;add t;
      // ct t box 60 20 15;c t S b0 B 0;c t L root L 0;cspec E 400 E 300
      final printed = await pumpCapturingPrints(
        tester,
        host([barrier(.bottom, #r), ...chainedR(), t()]),
      );
      expect(printed, [nullCheck]);
      // J257: !ok-printed | root 400 x 300 | b0: (0, 0) 0 x 0 |
      // r: (0, 0) 50 x 20 | r2: (0, 0) 50 x 20 | t: (0, 0) 60 x 20
      expect(
        geometry(tester, ['b0', 'r', 'r2', 't']),
        'root 400 x 300 | b0: (0, 0) 0 x 0 | r: (0, 0) 50 x 20 | '
        'r2: (0, 0) 50 x 20 | t: (0, 0) 60 x 20',
      );
    });

    testWidgets('throws the same with .wrapContent children, each left at '
        '0 x 0', (tester) async {
      // The op list above with every widget wrap content (w r 0 0;add r;
      // hb r W;vb r W and the same for r2 and t), so a fixed size is kept
      // by no child.
      final printed = await pumpCapturingPrints(
        tester,
        host([
          barrier(.bottom, #r),
          Constrained(
            id: #r,
            top: .topOf(parent, margin: 10),
            bottom: .topOf(#r2),
            child: const Leaf(50, 20),
          ),
          Constrained(
            id: #r2,
            top: .bottomOf(#r),
            bottom: .bottomOf(parent),
            child: const Leaf(50, 20),
          ),
          Constrained(
            id: #t,
            left: .leftOf(parent),
            baseline: .bottomOf(#b0),
            child: const Leaf(60, 20, baseline: 15),
          ),
        ]),
      );
      expect(printed, [nullCheck]);
      // J257: !ok-printed | root 400 x 300 | b0: (0, 0) 0 x 0 |
      // r: (0, 0) 0 x 0 | r2: (0, 0) 0 x 0 | t: (0, 0) 0 x 0
      expect(
        geometry(tester, ['b0', 'r', 'r2', 't']),
        'root 400 x 300 | b0: (0, 0) 0 x 0 | r: (0, 0) 0 x 0 | '
        'r2: (0, 0) 0 x 0 | t: (0, 0) 0 x 0',
      );
    });

    testWidgets('lays the same layout out once the top links to the '
        'barrier instead', (tester) async {
      // The op list above with c t T b0 B 0 in place of c t S b0 B 0.
      final printed = await pumpCapturingPrints(
        tester,
        host([barrier(.bottom, #r), ...chainedR(), t(top: true)]),
      );
      expect(printed, isEmpty);
      // J257 (J0 the same): root 400 x 300 | b0: (0, 113) 0 x 0 |
      // r: (0, 93) 50 x 20 | r2: (0, 197) 50 x 20 | t: (0, 113) 60 x 20
      expect(
        geometry(tester, ['b0', 'r', 'r2', 't']),
        'root 400 x 300 | b0: (0, 113) 0 x 0 | r: (0, 93) 50 x 20 | '
        'r2: (0, 197) 50 x 20 | t: (0, 113) 60 x 20',
      );
    });

    testWidgets('resolves when Direct places the barrier: its one widget is '
        'placed', (tester) async {
      // R 400 300;b b0;add b0;bt b0 3;w r 50 20;add r;ct r box 50 20 -1;
      // ref b0 r;c r T root T 10;w t 60 20;add t;ct t box 60 20 15;
      // c t S b0 B 0;c t L root L 0;cspec E 400 E 300
      final printed = await pumpCapturingPrints(
        tester,
        host([barrier(.bottom, #r), placedR(), t()]),
      );
      expect(printed, isEmpty);
      // J257: root 400 x 300 | b0: (0, 30) 0 x 0 | r: (0, 10) 50 x 20 |
      // t: (0, 15) 60 x 20. The barrier sits at r's bottom, and t's
      // baseline (15 down) on it.
      expect(
        geometry(tester, ['b0', 'r', 't']),
        'root 400 x 300 | b0: (0, 30) 0 x 0 | r: (0, 10) 50 x 20 | '
        't: (0, 15) 60 x 20',
      );
    });

    testWidgets('throws at OptimizationLevel.none even where Direct would '
        'place the barrier', (tester) async {
      // The op list of the layout above, at level 0.
      final printed = await pumpCapturingPrints(
        tester,
        host([
          barrier(.bottom, #r),
          placedR(),
          t(),
        ], level: OptimizationLevel.none),
      );
      expect(printed, [nullCheck]);
      // J0: !ok-printed | root 400 x 300 | b0: (0, 0) 0 x 0 |
      // r: (0, 0) 50 x 20 | t: (0, 0) 60 x 20
      expect(
        geometry(tester, ['b0', 'r', 't']),
        'root 400 x 300 | b0: (0, 0) 0 x 0 | r: (0, 0) 50 x 20 | '
        't: (0, 0) 60 x 20',
      );
    });

    testWidgets('throws when the barrier tracks a percent height, which '
        'Direct leaves to the solver', (tester) async {
      // R 400 300;b b0;add b0;bt b0 3;w r 50 0;add r;vb r M;vm r 2 0 0 0.5;
      // ct r box 50 20 -1;ref b0 r;c r T root T 10;c r B root B 0;
      // w t 60 20;add t;ct t box 60 20 15;c t S b0 B 0;c t L root L 0;
      // cspec E 400 E 300
      final printed = await pumpCapturingPrints(
        tester,
        host([
          barrier(.bottom, #r),
          Constrained(
            id: #r,
            top: .topOf(parent, margin: 10),
            bottom: .bottomOf(parent),
            width: .fixed(50),
            height: .percent(0.5),
            child: const Leaf(50, 20),
          ),
          t(),
        ]),
      );
      expect(printed, [nullCheck]);
      // J257: !ok-printed | root 400 x 300 | b0: (0, 0) 0 x 0 |
      // r: (0, 0) 50 x 0 | t: (0, 0) 60 x 20. The percent height is what
      // the abandoned solve left: 0.
      expect(
        geometry(tester, ['b0', 'r', 't']),
        'root 400 x 300 | b0: (0, 0) 0 x 0 | r: (0, 0) 50 x 0 | '
        't: (0, 0) 60 x 20',
      );
    });
  });

  group('a top barrier over a chain member', () {
    // R 400 300;b b0;add b0;bt b0 2;w r 50 20;add r;ct r box 50 20 -1;
    // w r2 50 20;add r2;ct r2 box 50 20 -1;ref b0 r2;c r T root T 10;
    // c r B r2 T 0;c r2 T r B 0;c r2 B root B 0;w t 60 20;add t;
    // ct t box 60 20 15;c t S b0 T 0;c t L root L 100;cspec E 400 E 300,
    // and the same with c t B b0 T 0 in place of c t S b0 T 0.
    Widget above({required bool baseline}) => Constrained(
      id: #t,
      left: .leftOf(parent, margin: 100),
      baseline: baseline ? .topOf(#b0) : null,
      bottom: baseline ? null : .topOf(#b0),
      width: .fixed(60),
      height: .fixed(20),
      child: const Leaf(60, 20, baseline: 15),
    );

    testWidgets('makes a baseline linked to its top throw in the solve', (
      tester,
    ) async {
      final printed = await pumpCapturingPrints(
        tester,
        host([barrier(.top, #r2), ...chainedR(), above(baseline: true)]),
      );
      expect(printed, [nullCheck]);
      // J257: !ok-printed | root 400 x 300 | b0: (0, 0) 0 x 0 |
      // r: (0, 0) 50 x 20 | r2: (0, 0) 50 x 20 | t: (0, 0) 60 x 20
      expect(
        geometry(tester, ['b0', 'r', 'r2', 't']),
        'root 400 x 300 | b0: (0, 0) 0 x 0 | r: (0, 0) 50 x 20 | '
        'r2: (0, 0) 50 x 20 | t: (0, 0) 60 x 20',
      );
    });

    testWidgets('lays the layout out once the bottom links to its top '
        'instead', (tester) async {
      final printed = await pumpCapturingPrints(
        tester,
        host([barrier(.top, #r2), ...chainedR(), above(baseline: false)]),
      );
      expect(printed, isEmpty);
      // J257 (J0 the same): root 400 x 300 | b0: (0, 197) 0 x 0 |
      // r: (0, 93) 50 x 20 | r2: (0, 197) 50 x 20 | t: (100, 177) 60 x 20
      expect(
        geometry(tester, ['b0', 'r', 'r2', 't']),
        'root 400 x 300 | b0: (0, 197) 0 x 0 | r: (0, 93) 50 x 20 | '
        'r2: (0, 197) 50 x 20 | t: (100, 177) 60 x 20',
      );
    });
  });

  group('a list item, whose height wraps its children', () {
    // R 400 0;wraph, the children of [listItemChildren], cspec E 400 U 0.
    // Direct cannot place the icon's top: it is centered on the item's
    // height, which only the solver finds. So the barrier over the icon is
    // left to the solver at the default level too.
    for (final (level, name) in const [
      (OptimizationLevel.standard, 'the default level'),
      (OptimizationLevel.none, 'OptimizationLevel.none'),
    ]) {
      testWidgets('throws at $name: the item comes out 0 high', (
        tester,
      ) async {
        final printed = await pumpCapturingPrints(
          tester,
          listItem(listItemChildren(), level: level),
        );
        expect(printed, [nullCheck]);
        // J257 and J0: !ok-printed | root 400 x 0 | icon: (16, 0) 40 x 40 |
        // title: (72, 8) 100 x 20 | bar: (0, 0) 0 x 0 | sub: (0, 0) 0 x 0.
        // The solve had fixed the title and the icon's left before the
        // throw; the icon's top and the item's height read back as 0.
        expect(
          geometry(tester, ['icon', 'title', 'bar', 'sub']),
          'root 400 x 0 | icon: (16, 0) 40 x 40 | '
          'title: (72, 8) 100 x 20 | bar: (0, 0) 0 x 0 | sub: (0, 0) 0 x 0',
        );
      });

      testWidgets('lays the item out at $name once the subtitle\'s top '
          'links to the barrier instead', (tester) async {
        final printed = await pumpCapturingPrints(
          tester,
          listItem(listItemChildren(top: true), level: level),
        );
        expect(printed, isEmpty);
        // J257 and J0, with c sub T bar B 0: root 400 x 80 |
        // icon: (16, 20) 40 x 40 | title: (72, 8) 100 x 20 |
        // bar: (0, 60) 0 x 0 | sub: (72, 60) 120 x 20
        expect(
          geometry(tester, ['icon', 'title', 'bar', 'sub']),
          'root 400 x 80 | icon: (16, 20) 40 x 40 | '
          'title: (72, 8) 100 x 20 | bar: (0, 60) 0 x 0 | '
          'sub: (72, 60) 120 x 20',
        );
      });
    }
  });
}
