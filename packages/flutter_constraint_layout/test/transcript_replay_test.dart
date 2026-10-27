// The replay of a layout's last engine run (see "What a layout pass does" in
// the README), and the optimization level ("Optimization levels").
//
// A layout whose configuration (the config epoch) and incoming constraints
// are those of the last full run of the engine, when that run repeated the
// one before it, asks every child again for each content measure of that
// run; when every answer is the same, it places the children where the run
// did without running the engine. These tests pin when a replay happens,
// what forces a full run instead, that a replay places exactly what the full
// run places, and that a layout whose second run differs from its first (as
// Android's own second layout can) is never replayed from the first.
//
// Run the file with --dart-define=cl.verifyReplay=true too: a replay then
// also runs the engine and reports any difference, and every test checks
// that none was found.
//
// Java values are VOpDriver's at the pin (view path, J257 unless a level is
// named), from the adapter's probes (each `p4:` and `p4a:` id names an op list
// of test/parity/probes.in, whose output is test/parity/probes.J257.txt) and
// the FL corpus (FL.J257.java, which
// packages/constraint_engine/tool/parity/gates/java_refs.sh writes for the
// corpus FL.txt).

import 'package:constraint_engine/constraint_engine.dart' show Optimizer;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether the suite runs with `--dart-define=cl.verifyReplay=true`, under
/// which a replayed layout also runs the engine to check itself.
const verifyReplay = bool.fromEnvironment('cl.verifyReplay');

/// A leaf sized as the parity corpora's content (FORMATS 6.2): a box of
/// [width] x [height], or with [text] a text [width] wide on one line and
/// [height] tall per line, which wraps at a narrower width (50 lines at a
/// width of 0). [baseline] is its alphabetic baseline, if any.
class Content extends LeafRenderObjectWidget {
  const Content(
    this.width,
    this.height, {
    this.text = false,
    this.baseline,
    super.key,
  });

  final double width;
  final double height;
  final bool text;
  final double? baseline;

  @override
  RenderContent createRenderObject(BuildContext context) => RenderContent(this);

  @override
  void updateRenderObject(BuildContext context, RenderContent renderObject) =>
      renderObject.content = this;
}

class RenderContent extends RenderBox {
  RenderContent(this._content);

  Content _content;
  set content(Content value) {
    if (value.width == _content.width &&
        value.height == _content.height &&
        value.text == _content.text &&
        value.baseline == _content.baseline) {
      return;
    }
    _content = value;
    markNeedsLayout();
  }

  /// The number of times this box ran its layout.
  int layouts = 0;

  Size _sizeFor(BoxConstraints constraints) {
    final width = constraints.constrainWidth(_content.width);
    var height = _content.height;
    if (_content.text) {
      height *= width <= 0 ? 50 : (_content.width / width).ceil();
    }
    return Size(width, constraints.constrainHeight(height));
  }

  @override
  void performLayout() {
    layouts++;
    size = _sizeFor(constraints);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _sizeFor(constraints);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _content.baseline;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) => _content.baseline;
}

/// [children] in a ConstraintLayout under exactly [constraints], at the top
/// left: an OverflowBox, as the FL runner builds a corpus layout.
Widget under(
  BoxConstraints constraints,
  List<Widget> children, {
  TextDirection direction = TextDirection.ltr,
  OptimizationLevel level = OptimizationLevel.standard,
  Key? key,
}) => Directionality(
  textDirection: direction,
  child: Align(
    alignment: Alignment.topLeft,
    child: OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: constraints.minWidth,
      maxWidth: constraints.maxWidth,
      minHeight: constraints.minHeight,
      maxHeight: constraints.maxHeight,
      child: ConstraintLayout(
        key: key,
        optimizationLevel: level,
        children: children,
      ),
    ),
  ),
);

RenderConstraintLayout layoutOf(WidgetTester tester) =>
    tester.renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout));

/// The geometry of the laid-out [ro] in VOpDriver's format (FORMATS 2):
/// `root W x H | name: (x, y) w x h | ...`, a child in [gone] printing its
/// size only.
String geometryOf(
  RenderConstraintLayout ro,
  List<String> names, {
  Set<String> gone = const {},
}) {
  String n(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
  final children = ro.getChildrenAsList();
  expect(children, hasLength(names.length));
  final sb = StringBuffer('root ${n(ro.size.width)} x ${n(ro.size.height)}');
  for (var i = 0; i < children.length; i++) {
    final child = children[i];
    final offset = (child.parentData! as BoxParentData).offset;
    final size = '${n(child.size.width)} x ${n(child.size.height)}';
    sb.write(
      gone.contains(names[i])
          ? ' | ${names[i]}: gone, $size'
          : ' | ${names[i]}: (${n(offset.dx)}, ${n(offset.dy)}) $size',
    );
  }
  return sb.toString();
}

/// Lays [ro] out again with nothing changed.
void relayout(RenderConstraintLayout ro) {
  ro.markNeedsLayout();
  ro.owner!.flushLayout();
}

/// p4:d5ltr: a 100 x 20 box at the left, a right barrier over it with a
/// margin of 8, and a 30 x 20 box to its right; E400 x E100.
List<Widget> barrierRow({double aWidth = 100, bool aText = false}) => [
  Constrained(
    id: #a,
    left: .leftOf(parent),
    top: .topOf(parent),
    child: Content(aWidth, 20, text: aText),
  ),
  const Barrier(id: #br, edge: .right, referenced: [#a], margin: 8),
  Constrained(
    id: #k,
    left: .rightOf(#br),
    top: .topOf(parent),
    child: const Content(30, 20),
  ),
];

const barrierNames = ['a', 'br', 'k'];

// Java J257: root 400 x 100 | a: (0, 0) 100 x 20 | br: (108, 0) 0 x 0 |
// k: (108, 0) 30 x 20 (VOpDriver view, p4:d5ltr).
const barrierRowJ257 =
    'root 400 x 100 | a: (0, 0) 100 x 20 | br: (108, 0) 0 x 0 | '
    'k: (108, 0) 30 x 20';

final exact400x100 = BoxConstraints.tight(const Size(400, 100));

void main() {
  group('replay', () {
    testWidgets('no replay on the first two identical layouts, a replay from '
        'the third', (tester) async {
      await tester.pumpWidget(under(exact400x100, barrierRow()));
      final ro = layoutOf(tester);
      expect(geometryOf(ro, barrierNames), barrierRowJ257);
      expect(ro.debugEnginePasses, 1);
      expect(ro.debugReplayPasses, 0);

      // The second layout runs the engine: the first run after a build is
      // never replayed. Its run repeats the first and confirms it.
      relayout(ro);
      expect(ro.debugEnginePasses, 2);
      expect(ro.debugReplayPasses, 0);
      expect(geometryOf(ro, barrierNames), barrierRowJ257);

      relayout(ro);
      relayout(ro);
      expect(ro.debugReplayPasses, 2);
      expect(ro.debugEnginePasses, 2 + (verifyReplay ? 2 : 0));
      expect(ro.debugReplayMismatches, 0);
      expect(ro.debugModelBuilds, 1);
      expect(geometryOf(ro, barrierNames), barrierRowJ257);
    });

    testWidgets('a replay asks every measured child again and places exactly '
        'what the full run placed', (tester) async {
      await tester.pumpWidget(under(exact400x100, barrierRow()));
      final ro = layoutOf(tester);
      relayout(ro);
      final full = geometryOf(ro, barrierNames);
      final offsets = [
        for (final child in ro.getChildrenAsList())
          (child.parentData! as BoxParentData).offset,
      ];
      final constraints = [
        for (final child in ro.getChildrenAsList()) child.constraints,
      ];

      relayout(ro);
      expect(ro.debugReplayPasses, 1);
      expect(geometryOf(ro, barrierNames), full);
      expect([
        for (final child in ro.getChildrenAsList())
          (child.parentData! as BoxParentData).offset,
      ], offsets);
      // The placement keeps the same layouts: the measured boxes their
      // measure constraints (A400/A100, loose), the barrier tight at 0 x 0.
      expect([
        for (final child in ro.getChildrenAsList()) child.constraints,
      ], constraints);
      expect(
        constraints[0],
        const BoxConstraints(maxWidth: 400, maxHeight: 100),
      );
      expect(constraints[1], BoxConstraints.tight(Size.zero));

      // A fresh tree places the same.
      await tester.pumpWidget(
        under(exact400x100, barrierRow(), key: UniqueKey()),
      );
      expect(geometryOf(layoutOf(tester), barrierNames), full);
    });

    testWidgets('a child whose answer changes forces a full run', (
      tester,
    ) async {
      await tester.pumpWidget(under(exact400x100, barrierRow()));
      final ro = layoutOf(tester);
      relayout(ro);
      final engine = ro.debugEnginePasses;

      // Only the leaf changes. The measure read its baseline, as a layout does
      // for every child it measures, so its relayout reaches the layout; the
      // replay asks it again, gets 120 where the run had 100, and runs the
      // engine instead.
      await tester.pumpWidget(under(exact400x100, barrierRow(aWidth: 120)));
      expect(ro.debugReplayPasses, 0);
      expect(ro.debugEnginePasses, engine + 1);
      // Java J257 (VOpDriver view, p4a:d5ltr120: p4:d5ltr with a 120-wide
      // box): k follows the barrier at 120 + 8.
      const moved =
          'root 400 x 100 | a: (0, 0) 120 x 20 | br: (128, 0) 0 x 0 | '
          'k: (128, 0) 30 x 20';
      expect(geometryOf(ro, barrierNames), moved);
      await tester.pumpWidget(
        under(exact400x100, barrierRow(aWidth: 120), key: UniqueKey()),
      );
      expect(geometryOf(layoutOf(tester), barrierNames), moved);
    });

    testWidgets('a child relaid out with the same answer replays', (
      tester,
    ) async {
      await tester.pumpWidget(under(exact400x100, barrierRow()));
      final ro = layoutOf(tester);
      relayout(ro);
      final engine = ro.debugEnginePasses;
      final leaf = tester.renderObject<RenderContent>(
        find.byType(Content).first,
      );
      final leafLayouts = leaf.layouts;

      // A text 100 wide on one line answers 100 x 20 under A400/A100, as the
      // box did: the leaf lays out again, the engine does not run. Java J257
      // gives the same frames (VOpDriver view, p4a:d5ltr_text).
      await tester.pumpWidget(under(exact400x100, barrierRow(aText: true)));
      expect(leaf.layouts, leafLayouts + 1);
      expect(ro.debugReplayPasses, 1);
      expect(ro.debugEnginePasses, engine + (verifyReplay ? 1 : 0));
      expect(ro.debugReplayMismatches, 0);
      expect(geometryOf(ro, barrierNames), barrierRowJ257);
    });

    testWidgets('new constraints force a full run', (tester) async {
      await tester.pumpWidget(under(exact400x100, barrierRow()));
      final ro = layoutOf(tester);
      relayout(ro);
      relayout(ro);
      final engine = ro.debugEnginePasses;
      final replays = ro.debugReplayPasses;

      final wider = BoxConstraints.tight(const Size(500, 100));
      await tester.pumpWidget(under(wider, barrierRow()));
      expect(ro.debugEnginePasses, engine + 1);
      expect(ro.debugReplayPasses, replays);
      expect(ro.debugModelBuilds, 1);
      // A loose constraint with the same maximum gives the same specs
      // (E500 x E100) but is another key: a full run again.
      await tester.pumpWidget(
        under(BoxConstraints.loose(const Size(500, 100)), barrierRow()),
      );
      expect(ro.debugEnginePasses, engine + 2);
      expect(ro.debugReplayPasses, replays);
      // Java J257 (VOpDriver view, p4a:d5ltr500, E500 x E100).
      expect(
        geometryOf(ro, barrierNames),
        'root 500 x 100 | a: (0, 0) 100 x 20 | br: (108, 0) 0 x 0 | '
        'k: (108, 0) 30 x 20',
      );
    });

    testWidgets('a configuration change forces a full run', (tester) async {
      List<Widget> children(double margin) => [
        ...barrierRow().take(2),
        Constrained(
          id: #k,
          left: .rightOf(#br, margin: margin),
          top: .topOf(parent),
          child: const Content(30, 20),
        ),
      ];
      await tester.pumpWidget(under(exact400x100, children(0)));
      final ro = layoutOf(tester);
      relayout(ro);
      relayout(ro);
      final engine = ro.debugEnginePasses;
      final replays = ro.debugReplayPasses;
      final applies = ro.debugConfigApplies;

      await tester.pumpWidget(under(exact400x100, children(12)));
      expect(ro.debugConfigApplies, applies + 1);
      expect(ro.debugModelBuilds, 1, reason: 'applied in place');
      expect(ro.debugEnginePasses, engine + 1);
      expect(ro.debugReplayPasses, replays);
      // Java J257 (VOpDriver view, p4a:d5ltr_m12: k's margin 12).
      expect(
        geometryOf(ro, barrierNames),
        'root 400 x 100 | a: (0, 0) 100 x 20 | br: (108, 0) 0 x 0 | '
        'k: (120, 0) 30 x 20',
      );

      // A second layout of the new configuration confirms it, and the third
      // replays it.
      relayout(ro);
      relayout(ro);
      expect(ro.debugReplayPasses, replays + 1);
    });

    testWidgets('a text direction change forces a full run', (tester) async {
      await tester.pumpWidget(under(exact400x100, barrierRow()));
      final ro = layoutOf(tester);
      relayout(ro);
      relayout(ro);
      final engine = ro.debugEnginePasses;
      final replays = ro.debugReplayPasses;

      await tester.pumpWidget(
        under(exact400x100, barrierRow(), direction: TextDirection.rtl),
      );
      expect(ro.debugModelBuilds, 2);
      expect(ro.debugEnginePasses, engine + 1);
      expect(ro.debugReplayPasses, replays);
      // Absolute links do not flip.
      expect(geometryOf(ro, barrierNames), barrierRowJ257);
    });

    testWidgets('an optimization level change forces a full run', (
      tester,
    ) async {
      await tester.pumpWidget(under(exact400x100, barrierRow()));
      final ro = layoutOf(tester);
      relayout(ro);
      relayout(ro);
      final engine = ro.debugEnginePasses;
      final replays = ro.debugReplayPasses;

      await tester.pumpWidget(
        under(exact400x100, barrierRow(), level: OptimizationLevel.none),
      );
      expect(ro.optimizationLevel, OptimizationLevel.none);
      expect(ro.debugModelBuilds, 1, reason: 'the level is not structural');
      expect(ro.debugEnginePasses, engine + 1);
      expect(ro.debugReplayPasses, replays);
      // Java J0: the same frames (VOpDriver view, p4:d5ltr at level 0).
      expect(geometryOf(ro, barrierNames), barrierRowJ257);
    });

    testWidgets('a layout whose second run differs from its first is never '
        'replayed from the first', (tester) async {
      // T-virtual:500004830: a vertical chain-wrapped flow, match constraint
      // on both axes between the layout's edges, in a layout of a fixed
      // width that wraps its height. Android's own second layout in the same
      // container differs from its first (the flow's addToSolver reads the
      // chains of its previous measure; see FORMATS.md 18.6 and 19.2 in
      // packages/constraint_engine/tool/parity), and so does the port's.
      List<Widget> children() => [
        Constrained(
          id: #m0,
          width: .fixed(49),
          height: .fixed(98),
          child: const Content(49, 98),
        ),
        Constrained(
          id: #m1,
          child: const Content(246, 14, text: true, baseline: 10),
        ),
        Constrained(
          id: #m2,
          child: const Content(150, 13, text: true, baseline: 10),
        ),
        Constrained(
          id: #m3,
          child: const Content(66, 16, text: true, baseline: 13),
        ),
        Constrained(
          id: #m4,
          width: .fixed(28),
          height: .fixed(56),
          child: const Content(28, 56),
        ),
        Constrained(
          id: #m5,
          visibility: .gone,
          child: const Content(144, 16, text: true, baseline: 12),
        ),
        ConstraintFlow(
          id: #flow,
          referenced: const [#m0, #m1, #m2, #m3, #m4, #m5],
          orientation: Axis.vertical,
          left: .leftOf(parent, margin: 5),
          right: .rightOf(parent, margin: 10),
          top: .topOf(parent, margin: 113),
          bottom: .bottomOf(parent, margin: 5),
          width: .matchConstraint,
          height: .matchConstraint,
          wrap: .chain,
          verticalGap: 12,
          horizontalChainStyle: .spread,
          verticalChainStyle: .spreadInside,
          contentVerticalBias: 0.9,
          verticalAlign: .baseline,
        ),
        Constrained(
          id: #badge,
          right: .rightOf(#m2, margin: -5),
          top: .topOf(#m2),
          width: .fixed(15),
          height: .fixed(13),
          child: const Content(15, 13),
        ),
      ];
      const names = ['m0', 'm1', 'm2', 'm3', 'm4', 'm5', 'flow', 'badge'];
      const gone = {'m5'};
      const fixedWidth = BoxConstraints(minWidth: 375, maxWidth: 375);

      await tester.pumpWidget(under(fixedWidth, children()));
      final ro = layoutOf(tester);
      // Java J257 (VOpDriver view, FL T-virtual:500004830).
      expect(
        geometryOf(ro, names, gone: gone),
        'root 375 x 216 | m0: (-84, 113) 49 x 98 | m1: (-35, 189) 246 x 14 | '
        'm2: (211, 190) 150 x 13 | m3: (361, 187) 66 x 16 | '
        'm4: (427, 151) 28 x 56 | m5: gone, 0 x 0 | '
        'flow: (5, 113) 360 x 98 | badge: (351, 190) 15 x 13',
      );

      // Java's dirty second layout of the same op list (the determinism
      // reference, DirtyTwice: tool/parity/java/dirty/ in the engine package,
      // on T2-virtual:500004830, a layout the twice step of
      // gates/corpus_gates.sh checks). Not a replay of the first.
      const second =
          'root 375 x 216 | m0: (14, 113) 49 x 98 | m1: (73, 113) 246 x 14 | '
          'm2: (121, 155) 150 x 13 | m3: (163, 195) 66 x 16 | '
          'm4: (328, 151) 28 x 56 | m5: gone, 0 x 0 | '
          'flow: (5, 113) 360 x 98 | badge: (261, 155) 15 x 13';
      relayout(ro);
      expect(ro.debugReplayPasses, 0);
      expect(geometryOf(ro, names, gone: gone), second);

      // The third layout repeats the second and confirms it; the fourth
      // replays it.
      relayout(ro);
      expect(ro.debugReplayPasses, 0);
      expect(geometryOf(ro, names, gone: gone), second);
      relayout(ro);
      expect(ro.debugReplayPasses, 1);
      expect(ro.debugReplayMismatches, 0);
      expect(geometryOf(ro, names, gone: gone), second);
    });

    group('the request transcript', () {
      setUp(() => RenderConstraintLayout.debugRecordTranscripts = true);
      tearDown(() => RenderConstraintLayout.debugRecordTranscripts = false);

      testWidgets('holds the last full run\'s requests, in the oracle\'s '
          'format', (tester) async {
        // p4:d8min: an unbounded layout with a minimum of 300 x 200 (its
        // minWidth and minHeight on Android), a 50 x 20 box linked to its four
        // edges.
        await tester.pumpWidget(
          under(const BoxConstraints(minWidth: 300, minHeight: 200), [
            Constrained(
              id: #a,
              left: .leftOf(parent),
              right: .rightOf(parent),
              top: .topOf(parent),
              bottom: .bottomOf(parent),
              child: const Content(50, 20),
            ),
          ]),
        );
        final ro = layoutOf(tester);
        // Java J257: root 300 x 200 | a: (125, 90) 50 x 20, T257
        // M:a:0:WW:0,0:U0/U0:50,20,-1,01 (VOpDriver view, p4:d8min).
        expect(
          geometryOf(ro, const ['a']),
          'root 300 x 200 | a: (125, 90) 50 x 20',
        );
        const t257 = 'M:a:0:WW:0,0:U0/U0:50,20,-1,01';
        expect(ro.debugViewHost!.measurer.transcript.toString(), t257);

        // A replay runs no engine and keeps the last full run's transcript.
        relayout(ro);
        relayout(ro);
        expect(ro.debugReplayPasses, 1);
        expect(ro.debugViewHost!.measurer.transcript.toString(), t257);
      });
    });
  });

  // A debug build answers a child's baseline again without asking the child
  // when Flutter's cache must still hold what the child answered: the child
  // has not needed layout, and its constraints have not changed, since the
  // layout read it. Every reused value is the child's (under cl.verifyReplay
  // each one is also asked and compared). Release and profile builds always
  // ask.
  group('reused baselines', () {
    /// a, a 100 x 20 text with its baseline at [aBaseline], and to its right
    /// k, a 30 x 20 box with its baseline at 10, on a's baseline.
    List<Widget> baselinePair({double aBaseline = 15}) => [
      Constrained(
        id: #a,
        left: .leftOf(parent),
        top: .topOf(parent, margin: 10),
        child: Content(100, 20, text: true, baseline: aBaseline),
      ),
      Constrained(
        id: #k,
        left: .rightOf(#a),
        baseline: .baselineOf(#a),
        child: const Content(30, 20, baseline: 10),
      ),
    ];
    const pairNames = ['a', 'k'];

    testWidgets('a layout reuses the baseline of every child it lays out '
        'again under the same constraints', (tester) async {
      await tester.pumpWidget(under(exact400x100, baselinePair()));
      final ro = layoutOf(tester);
      // The first layout reads both (fresh children); each later one, a full
      // run or a replay, measures both once under the same A400/A100 and
      // reuses both.
      expect(ro.debugReusedBaselines, 0);
      final first = geometryOf(ro, pairNames);
      relayout(ro);
      expect(ro.debugReplayPasses, 0);
      expect(ro.debugReusedBaselines, 2);
      relayout(ro);
      expect(ro.debugReplayPasses, 1);
      expect(ro.debugReusedBaselines, 4 + (verifyReplay ? 2 : 0));
      expect(ro.debugReusedBaselineMismatches, 0);
      expect(geometryOf(ro, pairNames), first);
      await tester.pumpWidget(
        under(exact400x100, baselinePair(), key: UniqueKey()),
      );
      expect(geometryOf(layoutOf(tester), pairNames), first);
    });

    testWidgets('a child that needed layout is asked again', (tester) async {
      await tester.pumpWidget(under(exact400x100, baselinePair()));
      final ro = layoutOf(tester);
      relayout(ro);
      final reused = ro.debugReusedBaselines;
      final before = geometryOf(ro, pairNames);

      // Only a's baseline changes. a needs layout, so the replay asks it
      // again and gets 12 where the run had 15; the full run that follows
      // then reuses that new read of a, and k's read, and k moves with a, as
      // in a fresh tree.
      await tester.pumpWidget(under(exact400x100, baselinePair(aBaseline: 12)));
      expect(ro.debugReplayPasses, 0);
      expect(ro.debugReusedBaselines, reused + 2);
      expect(ro.debugReusedBaselineMismatches, 0);
      final moved = geometryOf(ro, pairNames);
      expect(moved, isNot(before));
      await tester.pumpWidget(
        under(exact400x100, baselinePair(aBaseline: 12), key: UniqueKey()),
      );
      expect(geometryOf(layoutOf(tester), pairNames), moved);
    });

    testWidgets('a child laid out under other constraints is asked again', (
      tester,
    ) async {
      await tester.pumpWidget(under(exact400x100, baselinePair()));
      final ro = layoutOf(tester);
      relayout(ro);
      final reused = ro.debugReusedBaselines;

      // A wider layout measures both children under A500/A100: both are
      // laid out again and asked again.
      final wider = BoxConstraints.tight(const Size(500, 100));
      await tester.pumpWidget(under(wider, baselinePair()));
      expect(ro.debugReusedBaselines, reused);
      // Back to 400: both laid out again, under A400/A100, and asked again.
      await tester.pumpWidget(under(exact400x100, baselinePair()));
      expect(ro.debugReusedBaselines, reused);
      relayout(ro);
      expect(ro.debugReusedBaselines, reused + 2);
      expect(ro.debugReusedBaselineMismatches, 0);
      final geometry = geometryOf(ro, pairNames);
      await tester.pumpWidget(
        under(exact400x100, baselinePair(), key: UniqueKey()),
      );
      expect(geometryOf(layoutOf(tester), pairNames), geometry);
    });
  });

  group('optimization level', () {
    test('the values are Android\'s flags', () {
      const levels = <(OptimizationLevel, int)>[
        (OptimizationLevel.none, Optimizer.OPTIMIZATION_NONE),
        (OptimizationLevel.direct, Optimizer.OPTIMIZATION_DIRECT),
        (OptimizationLevel.barrier, Optimizer.OPTIMIZATION_BARRIER),
        (OptimizationLevel.chains, Optimizer.OPTIMIZATION_CHAIN),
        (OptimizationLevel.dimensions, Optimizer.OPTIMIZATION_DIMENSIONS),
        (OptimizationLevel.ratio, Optimizer.OPTIMIZATION_RATIO),
        (OptimizationLevel.groups, Optimizer.OPTIMIZATION_GROUPS),
        (OptimizationLevel.graph, Optimizer.OPTIMIZATION_GRAPH),
        (OptimizationLevel.graphWrap, Optimizer.OPTIMIZATION_GRAPH_WRAP),
        (
          OptimizationLevel.cacheMeasures,
          Optimizer.OPTIMIZATION_CACHE_MEASURES,
        ),
        (
          OptimizationLevel.dependencyOrdering,
          Optimizer.OPTIMIZATION_DEPENDENCY_ORDERING,
        ),
        (OptimizationLevel.grouping, Optimizer.OPTIMIZATION_GROUPING),
        (OptimizationLevel.standard, Optimizer.OPTIMIZATION_STANDARD),
      ];
      for (final (level, flag) in levels) {
        expect(level.value, flag);
      }
      // Android's values (ConstraintLayout's OPTIMIZATION_* constants).
      expect(OptimizationLevel.standard.value, 257);
      expect(OptimizationLevel.graph.value, 64);
      expect(
        OptimizationLevel.direct | OptimizationLevel.cacheMeasures,
        OptimizationLevel.standard,
      );
      expect(
        (OptimizationLevel.standard | OptimizationLevel.graph).value,
        321,
      );
    });

    testWidgets('standard is the default, and the level reaches the host', (
      tester,
    ) async {
      expect(
        const ConstraintLayout().optimizationLevel,
        OptimizationLevel.standard,
      );
      await tester.pumpWidget(under(exact400x100, barrierRow()));
      final ro = layoutOf(tester);
      expect(ro.optimizationLevel, OptimizationLevel.standard);
      expect(ro.debugViewHost!.optimizationLevel, 257);
      expect(ro.debugViewHost!.measurer.optimizationLevel, 257);

      final graph = OptimizationLevel.standard | OptimizationLevel.graph;
      await tester.pumpWidget(under(exact400x100, barrierRow(), level: graph));
      expect(ro.optimizationLevel, graph);
      expect(ro.debugViewHost!.optimizationLevel, 321);
      expect(ro.debugViewHost!.measurer.optimizationLevel, 321);
    });

    group('Direct', () {
      setUp(() => RenderConstraintLayout.debugRecordTranscripts = true);
      tearDown(() => RenderConstraintLayout.debugRecordTranscripts = false);

      // p4:mcunbounded: a layout unbounded in width and 100 tall; A, spread
      // match constraint between both edges, wraps a text 120 wide (20 per
      // line). Its width is measured for its content (UNSPECIFIED, so under
      // unbounded constraints), then at the solved width of 0.
      List<Widget> children() => [
        Constrained(
          id: #A,
          left: .leftOf(parent),
          right: .rightOf(parent),
          top: .topOf(parent),
          width: .matchConstraint,
          child: const Content(120, 20, text: true),
        ),
      ];
      const height100 = BoxConstraints(minHeight: 100, maxHeight: 100);
      const frames = 'root 0 x 100 | A: (0, 0) 0 x 100';

      for (final (level, t) in <(OptimizationLevel, String)>[
        // Java J257 T: Direct's post measure first (P).
        (
          OptimizationLevel.standard,
          'P:A:0:MW:0,0:U0/A100:120,20,-1,01 '
              'R:A:1:MW:0,20:E0/A100:0,100,-1,01 '
              'R:A:2:MW:0,100:E0/A100:0,100,-1,00',
        ),
        // Java J0 T: measureChildren first (M).
        (
          OptimizationLevel.none,
          'M:A:0:MW:0,0:U0/A100:120,20,-1,01 '
              'R:A:1:MW:0,20:E0/A100:0,100,-1,01 '
              'R:A:2:MW:0,100:E0/A100:0,100,-1,00',
        ),
      ]) {
        testWidgets('measures as Android at level ${level.value}', (
          tester,
        ) async {
          await tester.pumpWidget(under(height100, children(), level: level));
          final ro = layoutOf(tester);
          // Java J257 and J0 (VOpDriver view, p4:mcunbounded).
          expect(geometryOf(ro, const ['A']), frames);
          expect(ro.debugViewHost!.measurer.transcript.toString(), t);
        });
      }
    });
  });
}
