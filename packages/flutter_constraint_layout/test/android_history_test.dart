// A layout laid out again keeps what Android's ConstraintLayout keeps from
// one measure to the next: the engine's ViewHost resets every widget's
// measure state as Android's ConstraintWidget.reset() does before the layout
// params are applied again, and no more. So at a level where that history
// changes a layout, a layout laid out again, or changed in place, gives what
// Android's own views give, which can differ from a fresh build of the same
// configuration; and a dry layout, which measures a new model, gives the size
// of a first layout.
//
// The values are Android's real views: the engine's RoboOracle (the
// ConstraintLayout 2.2.1 view layer under Robolectric 4.16, FORMATS.md 10 in
// packages/constraint_engine/tool/parity) with -Drobo.inplace=1 and
// -Drobo.twice=dirty, at the level each test names. The scenario is
// ResetProbe's (packages/constraint_engine/tool/parity/java/probes and the
// engine's test/fresh_state_test.dart) in a layout that wraps its width: W,
// 50 x 50 at left 100; a right barrier over W that does not count gone
// widgets, with a margin of 5; and K, 30 x 30, linked to the barrier's right.
// The op lists: rpw:1-gone is `R 400 800;w W 50 50;add W;b bar;add bar;
// bt bar 1;bg bar 0;bm bar 5;ref bar W;w K 30 30;add K;v W 8;
// c W L root L 100;c K L bar R 0;ct W box 50 50 -1;ct K box 30 30 -1;
// cspec U 0 E 800`, with W gone; rpw:2-visible appends
// `;L;v W 0;sw W 50;sh W 50;sw K 30;sh K 30;adeps` (W made visible in place);
// rpw:3-gone appends that and then `;L;v W 8;sw W 50;sh W 50;sw K 30;sh K 30;
// adeps` (W gone again). The second layouts are the live views' dirty second
// layout of the same views (-Drobo.twice=dirty).
//
// Run the file with --dart-define=cl.verifyReplay=true too: a replay then also
// runs the engine and reports any difference, and every test checks that none
// was found.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// The layout's constraints: an unbounded width (Android's UNSPECIFIED, so
/// the layout wraps its children there) and a height of exactly 800.
const _wrapWidth = BoxConstraints(minHeight: 800, maxHeight: 800);

Widget _probe({required bool wGone, required OptimizationLevel level}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: _wrapWidth.minWidth,
          maxWidth: _wrapWidth.maxWidth,
          minHeight: _wrapWidth.minHeight,
          maxHeight: _wrapWidth.maxHeight,
          child: ConstraintLayout(
            optimizationLevel: level,
            children: [
              Constrained(
                id: #W,
                width: .fixed(50),
                height: .fixed(50),
                left: .leftOf(parent, margin: 100),
                visibility: wGone ? .gone : .visible,
                child: const SizedBox(),
              ),
              const Barrier(
                id: #bar,
                edge: .right,
                referenced: [#W],
                margin: 5,
                allowsGone: false,
              ),
              Constrained(
                id: #K,
                width: .fixed(30),
                height: .fixed(30),
                left: .rightOf(#bar),
                child: const SizedBox(),
              ),
            ],
          ),
        ),
      ),
    );

RenderConstraintLayout _layoutOf(WidgetTester tester) =>
    tester.renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout));

/// The layout's size and K's frame, as `root W x H | K: (x, y) w x h`.
String _frames(RenderConstraintLayout ro) {
  String n(double v) => '${v.toInt()}';
  final k = ro.getChildrenAsList()[2];
  final offset = (k.parentData! as BoxParentData).offset;
  return 'root ${n(ro.size.width)} x ${n(ro.size.height)} | '
      'K: (${n(offset.dx)}, ${n(offset.dy)}) '
      '${n(k.size.width)} x ${n(k.size.height)}';
}

/// Lays [ro] out again with nothing changed.
void _relayout(RenderConstraintLayout ro) {
  ro.markNeedsLayout();
  ro.owner!.flushLayout();
}

// The live views' frames: the barrier at its margin, 5, where allSolved
// places it; at 0, where its kept flag leaves it; and W visible.
const _atMargin = 'root 35 x 800 | K: (5, 0) 30 x 30';
const _atZero = 'root 30 x 800 | K: (0, 0) 30 x 30';
const _visible = 'root 185 x 800 | K: (155, 0) 30 x 30';

void main() {
  testWidgets('without direct, a barrier that resolves without the solver '
      'stays at 0 once laid out again (live views, level 0)', (tester) async {
    await tester.pumpWidget(_probe(wGone: true, level: .none));
    final ro = _layoutOf(tester);
    // rpw:1-gone.
    expect(_frames(ro), _atMargin);
    // Its dirty second layout: Barrier.allSolved resolved the barrier in the
    // first measure, and its flag outlives the position reset() zeroes.
    _relayout(ro);
    expect(_frames(ro), _atZero);
    // The third layout repeats the second, so the fourth replays it.
    _relayout(ro);
    expect(_frames(ro), _atZero);
    final replays = ro.debugReplayPasses;
    _relayout(ro);
    expect(_frames(ro), _atZero);
    expect(ro.debugReplayPasses, replays + 1);
    expect(ro.debugReplayMismatches, 0);
    // A dry layout measures a new model: the size of a first layout, which
    // Android's own first measure gives too.
    expect(ro.getDryLayout(_wrapWidth), const Size(35, 800));
    expect(ro.size, const Size(30, 800));
  });

  testWidgets('without direct, in place: W gone, visible, gone again (live '
      'views, level 0)', (tester) async {
    await tester.pumpWidget(_probe(wGone: true, level: .none));
    final ro = _layoutOf(tester);
    expect(_frames(ro), _atMargin);
    // rpw:2-visible.
    await tester.pumpWidget(_probe(wGone: false, level: .none));
    expect(_frames(ro), _visible);
    // rpw:3-gone: a fresh build of this state gives _atMargin.
    await tester.pumpWidget(_probe(wGone: true, level: .none));
    expect(_frames(ro), _atZero);
    expect(ro.debugReplayMismatches, 0);
  });

  testWidgets('at the default level, the same layouts give the fresh '
      "build's frames (live views, level 257)", (tester) async {
    // The Direct pass clears every resolved flag before anything reads it.
    await tester.pumpWidget(_probe(wGone: true, level: .standard));
    final ro = _layoutOf(tester);
    expect(_frames(ro), _atMargin);
    _relayout(ro);
    expect(_frames(ro), _atMargin);
    await tester.pumpWidget(_probe(wGone: false, level: .standard));
    expect(_frames(ro), _visible);
    await tester.pumpWidget(_probe(wGone: true, level: .standard));
    expect(_frames(ro), _atMargin);
    expect(ro.getDryLayout(_wrapWidth), const Size(35, 800));
    expect(ro.debugReplayMismatches, 0);
  });
}
