// Feature tests for the adapter surface that exposes engine capabilities:
// percent / bounded / constrained-wrap dimensions, chain styles and weights,
// visibility modes, circular positioning, guidelines, barriers, and
// right-to-left mirroring.
//
// The default flutter_test surface is 800x600; hosts pin that size explicitly
// so golden positions are stable.

import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(List<Widget> children,
        {double width = 800,
        double height = 600,
        TextDirection direction = TextDirection.ltr}) =>
    Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: height,
          child: ConstraintLayout(children: children),
        ),
      ),
    );

Rect rectOf(WidgetTester tester, Symbol id, {Type of = SizedBox}) {
  final finder = find.byKey(ValueKey(id));
  final box = tester.renderObject<RenderBox>(finder);
  final ro = tester
      .renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout));
  final topLeft = box.localToGlobal(Offset.zero, ancestor: ro);
  return topLeft & box.size;
}

Widget box(Symbol id) => SizedBox(key: ValueKey(id));

/// Records [id] in [log] every time it paints.
class _RecordingPainter extends CustomPainter {
  _RecordingPainter(this.id, this.log);

  final Symbol id;
  final List<Symbol> log;

  @override
  void paint(Canvas canvas, Size size) => log.add(id);

  @override
  bool shouldRepaint(_RecordingPainter oldDelegate) => true;
}

void main() {
  group('dimensions', () {
    testWidgets('percent width sizes to a fraction of the parent',
        (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          width: .percent(0.5),
          height: .fixed(40),
          child: box(#a),
        ),
      ]));
      expect(rectOf(tester, #a), const Rect.fromLTWH(200, 0, 400, 40));
    });

    testWidgets('percent respects max bound', (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          width: .percent(0.9, max: 300),
          height: .fixed(40),
          child: box(#a),
        ),
      ]));
      expect(rectOf(tester, #a).width, 300);
    });

    testWidgets('percent respects min bound', (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          width: .percent(0.1, min: 200),
          height: .fixed(40),
          child: box(#a),
        ),
      ]));
      expect(rectOf(tester, #a).width, 200);
    });

    testWidgets('spread with max caps the filled space', (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          width: .spread(max: 250),
          height: .fixed(40),
          child: box(#a),
        ),
      ]));
      final r = rectOf(tester, #a);
      expect(r.width, 250);
      // Centered between the anchors.
      expect(r.left, 275);
    });

    testWidgets('constrainedWrap caps content at the available space',
        (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #big,
          start: .startOf(parent, margin: 200),
          end: .endOf(parent, margin: 200),
          top: .topOf(parent),
          width: .constrainedWrap(),
          height: .fixed(40),
          child: SizedBox(key: const ValueKey(#big), width: 700),
        ),
        Constrained(
          id: #small,
          start: .startOf(parent, margin: 200),
          end: .endOf(parent, margin: 200),
          top: .topOf(parent, margin: 100),
          width: .constrainedWrap(),
          height: .fixed(40),
          child: SizedBox(key: const ValueKey(#small), width: 100),
        ),
      ]));
      // 700 of content into 400 of space: capped.
      expect(rectOf(tester, #big).width, 400);
      // 100 of content into 400 of space: stays at content size, not spread.
      expect(rectOf(tester, #small).width, 100);
    });
  });

  // A match-constraint size with a min or a max resolves the same on both
  // engine paths. The dependency graph measures an axis with a single link as
  // wrap content and resolves it at the measured size, so the measurer keeps
  // that size within the bounds, as Android's view measurer does; the solver
  // applies the bounds itself. Each case is laid out alone, which the graph
  // resolves, and next to an unrelated circular link, which sends the whole
  // layout to the solver. Values marked as Android's were checked against
  // upstream's Java engine at OPTIMIZATION_STANDARD (its default, solver
  // path) with a port of the view layer's ConstraintLayout.Measurer.
  group('bounded match-constraint sizes', () {
    Widget sized(
      Dimension width,
      Dimension height, {
      bool twoLinksH = false,
      bool twoLinksV = false,
      double inset = 10,
      Size content = const Size(400, 40),
      double? aspectRatio,
    }) => Constrained(
      id: #a,
      start: .startOf(parent, margin: inset),
      end: twoLinksH ? .endOf(parent, margin: inset) : null,
      top: .topOf(parent, margin: 5),
      bottom: twoLinksV ? .bottomOf(parent, margin: 5) : null,
      width: width,
      height: height,
      aspectRatio: aspectRatio,
      child: SizedBox(
        key: const ValueKey(#a),
        width: content.width,
        height: content.height,
      ),
    );

    /// Lays [children] out next to a fixed widget in the bottom-end corner,
    /// plus a widget circling it when [solver] is set (the dependency graph
    /// never resolves a circular link, so the layout goes to the solver; a
    /// barrier no longer does), and returns whether the solver ran. Every
    /// call changes the children, so the engine model is built afresh and
    /// its solver has created variables only if this layout used it. (Its
    /// row count is no proof: a solve whose equalities all resolve directly
    /// ends with no rows.)
    Future<bool> layOut(
      WidgetTester tester,
      List<Widget> children, {
      required bool solver,
    }) async {
      await tester.pumpWidget(host([
        ...children,
        Constrained(
          id: #other,
          end: .endOf(parent),
          bottom: .bottomOf(parent),
          width: .fixed(10),
          height: .fixed(10),
          child: box(#other),
        ),
        if (solver)
          Constrained(
            id: #force,
            circle: .around(#other, angle: 270, radius: 20),
            width: .fixed(10),
            height: .fixed(10),
            child: box(#force),
          ),
      ]));
      final ro = tester.renderObject<RenderConstraintLayout>(
          find.byType(ConstraintLayout));
      return ro.debugEngineContainer!.mSystem.getNumVariables() > 0;
    }

    // (case, child, the rect both paths give, whether the graph resolves it)
    final cases = <(String, Widget, Rect, bool)>[
      // Android's: x=10 w=300.
      ('one-link spread max', sized(.spread(max: 300), .fixed(40)),
          const Rect.fromLTWH(10, 5, 300, 40), true),
      // Android's: x=10 w=500.
      ('one-link spread min', sized(.spread(min: 500), .fixed(40)),
          const Rect.fromLTWH(10, 5, 500, 40), true),
      ('one-link spread with the content inside its bounds',
          sized(.spread(min: 100, max: 500), .fixed(40)),
          const Rect.fromLTWH(10, 5, 400, 40), true),
      ('two-link spread max', sized(.spread(max: 300), .fixed(40),
          twoLinksH: true), const Rect.fromLTWH(250, 5, 300, 40), true),
      // 200 between the links. Android's: w=300 (at x=251, a pixel of float
      // rounding away).
      ('two-link spread min above the space, with a max',
          sized(.spread(min: 300, max: 400), .fixed(40),
              twoLinksH: true, inset: 300),
          const Rect.fromLTWH(250, 5, 300, 40), true),
      // Android's: w=300 and w=200 with one link, x=250 w=300 with two. Not
      // here: a min above the percent with two links, where the graph keeps
      // the documented min (UPSTREAM.md, the percent clamp) but the solver,
      // like Android's (x=10 w=780), fills the space between the links.
      ('one-link percent max', sized(.percent(0.9, max: 300), .fixed(40)),
          const Rect.fromLTWH(10, 5, 300, 40), true),
      ('one-link percent min', sized(.percent(0.1, min: 200), .fixed(40)),
          const Rect.fromLTWH(10, 5, 200, 40), true),
      ('two-link percent max', sized(.percent(0.9, max: 300), .fixed(40),
          twoLinksH: true), const Rect.fromLTWH(250, 5, 300, 40), true),
      ('one-link constrainedWrap max',
          sized(.constrainedWrap(max: 300), .fixed(40)),
          const Rect.fromLTWH(10, 5, 300, 40), false),
      ('two-link constrainedWrap min',
          sized(.constrainedWrap(min: 500), .fixed(40), twoLinksH: true),
          const Rect.fromLTWH(150, 5, 500, 40), false),
      // The same on the vertical axis, under a fixed width wider than the
      // content, which must be kept. Android's: w=100 h=30, and w=100 h=400
      // without bounds.
      ('one-link spread min and max height',
          sized(.fixed(100), .spread(min: 10, max: 30),
              content: const Size(40, 400)),
          const Rect.fromLTWH(10, 5, 100, 30), true),
      ('one-link spread min height',
          sized(.fixed(100), .spread(min: 500), content: const Size(40, 400)),
          const Rect.fromLTWH(10, 5, 100, 500), true),
      ('one-link match-constraint height',
          sized(.fixed(100), .matchConstraint, content: const Size(40, 400)),
          const Rect.fromLTWH(10, 5, 100, 400), true),
      ('two-link spread max height',
          sized(.fixed(100), .spread(max: 100),
              twoLinksV: true, content: const Size(40, 400)),
          const Rect.fromLTWH(10, 250, 100, 100), true),
      ('two-link percent max height',
          sized(.fixed(100), .percent(0.5, max: 200),
              twoLinksV: true, content: const Size(40, 400)),
          const Rect.fromLTWH(10, 200, 100, 200), true),
      ('one-link constrainedWrap max height',
          sized(.fixed(100), .constrainedWrap(max: 30),
              content: const Size(40, 400)),
          const Rect.fromLTWH(10, 5, 100, 30), false),
    ];

    for (final (name, child, expected, onGraph) in cases) {
      testWidgets('$name: both paths agree', (tester) async {
        final graphUsedSolver = await layOut(tester, [child], solver: false);
        expect(graphUsedSolver, !onGraph);
        final graph = rectOf(tester, #a);

        expect(await layOut(tester, [child], solver: true), isTrue);
        final solver = rectOf(tester, #a);

        expect(graph, expected, reason: 'graph');
        expect(solver, expected, reason: 'solver');
      });
    }

    testWidgets('text capped by a one-link max wraps at the capped width on '
        'both paths', (tester) async {
      // 20 px glyphs: the 780 px line wraps to one 180 px word per line at
      // 300. Android's: w=300 h=60 for content that wraps to 3 lines there.
      List<Widget> children() => [
            Constrained(
              id: #t,
              start: .startOf(parent, margin: 10),
              top: .topOf(parent),
              width: .spread(max: 300),
              child: const Text(
                'AAAAAAAAA BBBBBBBBB CCCCCCCCC DDDDDDDDD',
                key: ValueKey(#t),
                style: TextStyle(fontSize: 20),
              ),
            ),
            Constrained(
              id: #below,
              start: .startOf(parent),
              top: .bottomOf(#t),
              width: .fixed(10),
              height: .fixed(10),
              child: box(#below),
            ),
          ];
      for (final solver in [false, true]) {
        expect(await layOut(tester, children(), solver: solver), solver);
        expect(rectOf(tester, #t), const Rect.fromLTWH(10, 0, 300, 80),
            reason: solver ? 'solver' : 'graph');
        expect(rectOf(tester, #below).top, 80,
            reason: 'the sibling below follows the wrapped height');
      }
    });

    testWidgets('a ratio-derived width is capped by its max on both paths',
        (tester) async {
      // The ratio gives 160 from the fixed 80 height; the max caps it at 100,
      // centered between the links. Android's: x=350 w=100 h=80. The solver
      // path caps the width in setFrame, which records the capped size as an
      // override and solves again, so the width is centered at its capped
      // size there too.
      for (final solver in [false, true]) {
        expect(
          await layOut(tester, [
            sized(.spread(max: 100), .fixed(80),
                twoLinksH: true, aspectRatio: 2),
          ], solver: solver),
          solver,
        );
        expect(rectOf(tester, #a), const Rect.fromLTWH(350, 5, 100, 80),
            reason: solver ? 'solver' : 'graph');
      }
    });
  });

  group('chains', () {
    List<Widget> chain(ChainStyle? style, {double? weightA, double? weightB}) =>
        [
          Constrained(
            id: #a,
            start: .startOf(parent),
            end: .startOf(#b),
            top: .topOf(parent),
            width: weightA == null ? .fixed(100) : .matchConstraint,
            height: .fixed(50),
            horizontalChainStyle: style,
            horizontalWeight: weightA,
            child: box(#a),
          ),
          Constrained(
            id: #b,
            start: .endOf(#a),
            end: .endOf(parent),
            top: .topOf(parent),
            width: weightB == null ? .fixed(100) : .matchConstraint,
            height: .fixed(50),
            horizontalWeight: weightB,
            child: box(#b),
          ),
        ];

    testWidgets('default spread distributes gaps around members',
        (tester) async {
      await tester.pumpWidget(host(chain(null)));
      // 600 free space over 3 gaps of 200.
      expect(rectOf(tester, #a).left, 200);
      expect(rectOf(tester, #b).left, 500);
    });

    testWidgets('spreadInside pins the outer members to the edges',
        (tester) async {
      await tester.pumpWidget(host(chain(ChainStyle.spreadInside)));
      expect(rectOf(tester, #a).left, 0);
      expect(rectOf(tester, #b).left, 700);
    });

    testWidgets('packed groups the members in the middle', (tester) async {
      await tester.pumpWidget(host(chain(ChainStyle.packed)));
      expect(rectOf(tester, #a).left, 300);
      expect(rectOf(tester, #b).left, 400);
    });

    testWidgets('weights split leftover space proportionally', (tester) async {
      await tester.pumpWidget(host(chain(null, weightA: 1, weightB: 3)));
      expect(rectOf(tester, #a), const Rect.fromLTWH(0, 0, 200, 50));
      expect(rectOf(tester, #b), const Rect.fromLTWH(200, 0, 600, 50));
    });

    testWidgets('chain style change applies in place without a model rebuild',
        (tester) async {
      await tester.pumpWidget(host(chain(null)));
      final ro = tester.renderObject<RenderConstraintLayout>(
          find.byType(ConstraintLayout));
      final builds = ro.debugModelBuilds;
      await tester.pumpWidget(host(chain(ChainStyle.packed)));
      expect(rectOf(tester, #a).left, 300);
      expect(ro.debugModelBuilds, builds);
    });
  });

  group('visibility', () {
    List<Widget> pair(ConstraintVisibility vis) => [
          Constrained(
            id: #a,
            start: .startOf(parent),
            top: .topOf(parent),
            width: .fixed(100),
            height: .fixed(50),
            visibility: vis,
            child: box(#a),
          ),
          Constrained(
            id: #b,
            start: .endOf(#a, margin: 10),
            top: .topOf(parent),
            width: .fixed(100),
            height: .fixed(50),
            child: box(#b),
          ),
        ];

    testWidgets('invisible keeps its size and position for siblings',
        (tester) async {
      await tester.pumpWidget(host(pair(ConstraintVisibility.visible)));
      final visibleB = rectOf(tester, #b);
      await tester.pumpWidget(host(pair(ConstraintVisibility.invisible)));
      expect(rectOf(tester, #b), visibleB);
      expect(rectOf(tester, #a).width, 100);
    });

    testWidgets('gone collapses and applies goneMargins', (tester) async {
      await tester.pumpWidget(host(pair(ConstraintVisibility.gone)));
      // a collapses to a point at its position; b follows it.
      expect(rectOf(tester, #b).left, 10);
    });

    testWidgets('invisible and gone children are not painted or hit-testable',
        (tester) async {
      final log = <Symbol>[];
      Widget tappable(Symbol id, ConstraintVisibility vis) => Constrained(
            id: id,
            start: .startOf(parent),
            top: .topOf(parent),
            width: .fixed(100),
            height: .fixed(50),
            visibility: vis,
            child: GestureDetector(
              key: ValueKey(id),
              onTap: () => log.add(id),
              child: Container(color: const Color(0xFF00FF00)),
            ),
          );
      await tester.pumpWidget(
          host([tappable(#invis, ConstraintVisibility.invisible)]));
      await tester.tapAt(const Offset(50, 25));
      expect(log, isEmpty);

      await tester
          .pumpWidget(host([tappable(#vis, ConstraintVisibility.visible)]));
      await tester.tapAt(const Offset(50, 25));
      expect(log, [#vis]);
    });
  });

  // Android's Group: the group's visibility is set on every referenced view,
  // replacing the view's own, and the group declared last has the last word.
  group('groups', () {
    // #c follows #b, which follows #a, so collapsing a member moves #c.
    List<Widget> row({
      ConstraintVisibility a = .visible,
      ConstraintVisibility b = .visible,
      List<Widget> groups = const [],
    }) => [
      Constrained(
        id: #a,
        start: .startOf(parent, margin: 10),
        top: .topOf(parent, margin: 10),
        width: .fixed(100),
        height: .fixed(50),
        visibility: a,
        child: box(#a),
      ),
      Constrained(
        id: #b,
        start: .endOf(#a, margin: 10, goneMargin: 40),
        top: .topOf(#a),
        width: .fixed(100),
        height: .fixed(50),
        visibility: b,
        child: box(#b),
      ),
      Constrained(
        id: #c,
        start: .endOf(#b, margin: 10, goneMargin: 20),
        top: .topOf(#a),
        width: .fixed(100),
        height: .fixed(50),
        child: box(#c),
      ),
      ...groups,
    ];

    List<Rect> rects(WidgetTester tester) => [
      for (final id in const [#a, #b, #c]) rectOf(tester, id),
    ];

    testWidgets('a gone group lays out its members as gone', (tester) async {
      await tester.pumpWidget(host(row(b: .gone)));
      final ownGone = rects(tester);
      expect(ownGone[1].size, Size.zero);
      expect(ownGone[2].left, 130, reason: '#b is gone: 10 + 100 + 20');

      await tester.pumpWidget(host(row(
        groups: const [
          ConstraintGroup(id: #g, referenced: [#b], visibility: .gone),
        ],
      )));
      expect(rects(tester), ownGone);
    });

    testWidgets('a group overrides the visibility its members declare',
        (tester) async {
      // Both members declare gone, and a visible group shows them anyway.
      await tester.pumpWidget(host(row(
        a: .gone,
        b: .gone,
        groups: const [ConstraintGroup(id: #g, referenced: [#a, #b])],
      )));
      expect(rects(tester), const [
        Rect.fromLTWH(10, 10, 100, 50),
        Rect.fromLTWH(120, 10, 100, 50),
        Rect.fromLTWH(230, 10, 100, 50),
      ]);
    });

    testWidgets('a group declared before its members still applies',
        (tester) async {
      await tester.pumpWidget(host([
        const ConstraintGroup(id: #g, referenced: [#b], visibility: .gone),
        ...row(),
      ]));
      expect(rectOf(tester, #b).size, Size.zero);
      expect(rectOf(tester, #c).left, 130, reason: '10 + 100 + goneMargin 20');
    });

    testWidgets('the last group in child order wins', (tester) async {
      List<Widget> twoGroups(ConstraintVisibility first,
              ConstraintVisibility second) =>
          row(groups: [
            ConstraintGroup(id: #g1, referenced: const [#b], visibility: first),
            ConstraintGroup(
                id: #g2, referenced: const [#a, #b], visibility: second),
          ]);
      await tester.pumpWidget(host(twoGroups(.gone, .visible)));
      expect(rectOf(tester, #b).size, const Size(100, 50));

      await tester.pumpWidget(host(twoGroups(.visible, .gone)));
      expect(rectOf(tester, #a).size, Size.zero);
      expect(rectOf(tester, #b).size, Size.zero);
    });

    testWidgets(
        'an invisible group keeps its members in place but stops painting '
        'and hit testing them', (tester) async {
      final painted = <Symbol>[];
      final tapped = <Symbol>[];
      Widget member(Symbol id, HorizontalLink start) => Constrained(
            id: id,
            start: start,
            top: .topOf(parent),
            width: .fixed(100),
            height: .fixed(50),
            child: GestureDetector(
              key: ValueKey(id),
              onTap: () => tapped.add(id),
              child: CustomPaint(painter: _RecordingPainter(id, painted)),
            ),
          );
      List<Widget> children(ConstraintVisibility group) => [
            member(#a, .startOf(parent)),
            member(#b, .endOf(#a, margin: 10)),
            ConstraintGroup(id: #g, referenced: const [#a], visibility: group),
          ];

      await tester.pumpWidget(host(children(.visible)));
      expect(painted, containsAll([#a, #b]));
      await tester.tapAt(const Offset(50, 25));
      expect(tapped, [#a]);

      painted.clear();
      tapped.clear();
      await tester.pumpWidget(host(children(.invisible)));
      expect(painted, [#b]);
      await tester.tapAt(const Offset(50, 25));
      expect(tapped, isEmpty);
      // Laid out as before, so #b does not move.
      expect(rectOf(tester, #a), const Rect.fromLTWH(0, 0, 100, 50));
      expect(rectOf(tester, #b).left, 110);
    });

    testWidgets('a group sets the visibility of a flow as its own would',
        (tester) async {
      List<Widget> flowRow({
        ConstraintVisibility own = .visible,
        ConstraintVisibility? group,
      }) => [
        for (final id in const [#x, #y])
          Constrained(
            id: id,
            width: .fixed(100),
            height: .fixed(40),
            child: box(id),
          ),
        ConstraintFlow(
          id: #flow,
          referenced: const [#x, #y],
          start: .startOf(parent, margin: 20),
          top: .topOf(parent, margin: 20),
          horizontalGap: 10,
          visibility: own,
        ),
        Constrained(
          id: #after,
          start: .endOf(#flow, margin: 10, goneMargin: 5),
          top: .topOf(parent),
          width: .fixed(30),
          height: .fixed(30),
          child: box(#after),
        ),
        if (group != null)
          ConstraintGroup(id: #g, referenced: const [#flow], visibility: group),
      ];
      List<Rect> flowRects() => [
        for (final id in const [#x, #y, #after]) rectOf(tester, id),
      ];

      await tester.pumpWidget(host(flowRow()));
      final shown = flowRects();
      expect(shown[2].left, 240, reason: 'after the 210-wide flow at 20');

      await tester.pumpWidget(host(flowRow(own: .gone)));
      final ownGone = flowRects();
      expect(ownGone, isNot(shown));

      await tester.pumpWidget(host(flowRow(group: .gone)));
      expect(flowRects(), ownGone);
      await tester.pumpWidget(host(flowRow(own: .gone, group: .visible)));
      expect(flowRects(), shown);
    });

    testWidgets('a group leaves guidelines and barriers as they are',
        (tester) async {
      await tester.pumpWidget(host([
        const Guideline.vertical(id: #guide, begin: 200),
        Constrained(
          id: #a,
          start: .startOf(parent),
          top: .topOf(parent),
          width: .fixed(300),
          height: .fixed(20),
          child: box(#a),
        ),
        const Barrier(id: #bar, edge: .end, referenced: [#a]),
        Constrained(
          id: #onGuide,
          start: .endOf(#guide),
          top: .topOf(parent, margin: 50),
          width: .fixed(10),
          height: .fixed(10),
          child: box(#onGuide),
        ),
        Constrained(
          id: #onBarrier,
          start: .endOf(#bar),
          top: .topOf(parent, margin: 100),
          width: .fixed(10),
          height: .fixed(10),
          child: box(#onBarrier),
        ),
        const ConstraintGroup(
          id: #g,
          referenced: [#guide, #bar],
          visibility: .gone,
        ),
      ]));
      expect(rectOf(tester, #onGuide).left, 200);
      expect(rectOf(tester, #onBarrier).left, 300);
    });
  });

  group('circular positioning', () {
    testWidgets('places the satellite at angle and radius from the hub center',
        (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #hub,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
          width: .fixed(100),
          height: .fixed(100),
          child: box(#hub),
        ),
        Constrained(
          id: #east,
          circle: .around(#hub, angle: 90, radius: 200),
          width: .fixed(20),
          height: .fixed(20),
          child: box(#east),
        ),
        Constrained(
          id: #north,
          circle: .around(#hub, angle: 0, radius: 150),
          width: .fixed(20),
          height: .fixed(20),
          child: box(#north),
        ),
      ]));
      final hub = rectOf(tester, #hub);
      expect(hub.center, const Offset(400, 300));
      // angle 90 = 3 o'clock: center at hub center + (200, 0).
      expect(rectOf(tester, #east).center, const Offset(600, 300));
      // angle 0 = 12 o'clock: center at hub center - (0, 150).
      expect(rectOf(tester, #north).center, const Offset(400, 150));
    });
  });

  group('guidelines', () {
    testWidgets('vertical guideline at percent anchors siblings',
        (tester) async {
      await tester.pumpWidget(host([
        const Guideline.vertical(id: #g, percent: 0.25),
        Constrained(
          id: #a,
          start: .rightOf(#g),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          child: box(#a),
        ),
      ]));
      expect(rectOf(tester, #a).left, 200);
    });

    testWidgets('begin and end guidelines position from opposite edges',
        (tester) async {
      await tester.pumpWidget(host([
        const Guideline.vertical(id: #gb, begin: 150),
        const Guideline.horizontal(id: #ge, end: 100),
        Constrained(
          id: #a,
          start: .rightOf(#gb),
          bottom: .topOf(#ge),
          width: .fixed(100),
          height: .fixed(50),
          child: box(#a),
        ),
      ]));
      final r = rectOf(tester, #a);
      expect(r.left, 150);
      expect(r.bottom, 500);
    });

    testWidgets('a guideline later in the child list anchors siblings',
        (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          start: .rightOf(#g, margin: 8),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          child: box(#a),
        ),
        const Guideline.vertical(id: #g, begin: 120),
      ]));
      expect(rectOf(tester, #a).left, 128);
    });

    testWidgets('guideline percent change moves anchored siblings',
        (tester) async {
      Widget build(double percent) => host([
            Guideline.vertical(id: #g, percent: percent),
            Constrained(
              id: #a,
              start: .rightOf(#g),
              top: .topOf(parent),
              width: .fixed(100),
              height: .fixed(50),
              child: box(#a),
            ),
          ]);
      await tester.pumpWidget(build(0.25));
      expect(rectOf(tester, #a).left, 200);
      await tester.pumpWidget(build(0.75));
      expect(rectOf(tester, #a).left, 600);
    });
  });

  group('barriers', () {
    List<Widget> labeled(double bWidth, {double margin = 0}) => [
          Constrained(
            id: #name,
            start: .startOf(parent),
            top: .topOf(parent),
            width: .fixed(100),
            height: .fixed(30),
            child: box(#name),
          ),
          Constrained(
            id: #email,
            start: .startOf(parent),
            top: .bottomOf(#name),
            width: .fixed(bWidth),
            height: .fixed(30),
            child: box(#email),
          ),
          Barrier(
            id: #labelsEnd,
            edge: .end,
            referenced: const [#name, #email],
            margin: margin,
          ),
          Constrained(
            id: #value,
            start: .rightOf(#labelsEnd),
            top: .topOf(parent),
            width: .fixed(50),
            height: .fixed(30),
            child: box(#value),
          ),
        ];

    testWidgets('barrier tracks the furthest referenced edge', (tester) async {
      await tester.pumpWidget(host(labeled(250)));
      expect(rectOf(tester, #value).left, 250);
    });

    testWidgets('barrier margin offsets the tracked edge', (tester) async {
      await tester.pumpWidget(host(labeled(250, margin: 10)));
      expect(rectOf(tester, #value).left, 260);
    });

    testWidgets('barrier follows when a referenced widget resizes',
        (tester) async {
      await tester.pumpWidget(host(labeled(250)));
      expect(rectOf(tester, #value).left, 250);
      await tester.pumpWidget(host(labeled(60)));
      expect(rectOf(tester, #value).left, 100);
    });
  });

  group('flow', () {
    Widget cell(Symbol id, double w, double h) => Constrained(
          id: id,
          width: Dimension.fixed(w),
          height: Dimension.fixed(h),
          child: box(id),
        );

    testWidgets('no-wrap flow chains the referenced widgets', (tester) async {
      await tester.pumpWidget(host([
        cell(#a, 100, 40),
        cell(#b, 100, 40),
        cell(#c, 100, 40),
        ConstraintFlow(
          id: #flow,
          referenced: const [#a, #b, #c],
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          width: .matchConstraint,
          horizontalChainStyle: ChainStyle.packed,
          horizontalGap: 10,
        ),
      ]));
      // Packed chain of 320 total, centered in 800.
      expect(rectOf(tester, #a).left, 240);
      expect(rectOf(tester, #b).left, 350);
      expect(rectOf(tester, #c).left, 460);
    });

    testWidgets('chain wrap flows into multiple rows', (tester) async {
      await tester.pumpWidget(host([
        cell(#a, 300, 40),
        cell(#b, 300, 40),
        cell(#c, 300, 40),
        ConstraintFlow(
          id: #flow,
          referenced: const [#a, #b, #c],
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          width: .matchConstraint,
          height: .wrapContent,
          wrap: .chain,
        ),
      ]));
      // 3 x 300 does not fit into 800: two on the first row, one on the
      // second.
      final a = rectOf(tester, #a);
      final b = rectOf(tester, #b);
      final c = rectOf(tester, #c);
      expect(a.top, b.top);
      expect(c.top, greaterThan(a.top));
      expect(c.top, a.bottom);
    });

    testWidgets('maxElementsWrap forces earlier wrapping', (tester) async {
      await tester.pumpWidget(host([
        cell(#a, 100, 40),
        cell(#b, 100, 40),
        cell(#c, 100, 40),
        ConstraintFlow(
          id: #flow,
          referenced: const [#a, #b, #c],
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          width: .matchConstraint,
          height: .wrapContent,
          wrap: .chain,
          maxElementsWrap: 2,
        ),
      ]));
      final a = rectOf(tester, #a);
      final c = rectOf(tester, #c);
      expect(c.top, greaterThan(a.top));
    });

    // Wrap-content chips like the website's flow example, whose first row
    // holds chips 91, 66, 66 and 61 wide: 91 + 66 + 66 + 61 + 3 * 8 = 308.
    Widget chip(Symbol id, double width) => Constrained(
          id: id,
          child: SizedBox(key: ValueKey(id), width: width, height: 35),
        );

    // The flow is inset 12 from each side of the layout, so the layout needs
    // 308 + 2 * (12 + padding) to keep the four chips on one row.
    List<Widget> chipFlow(FlowWrap wrap, {double padding = 0}) => [
          chip(#c0, 91),
          chip(#c1, 66),
          chip(#c2, 66),
          chip(#c3, 61),
          ConstraintFlow(
            id: #flow,
            referenced: const [#c0, #c1, #c2, #c3],
            start: .startOf(parent, margin: 12),
            end: .endOf(parent, margin: 12),
            top: .topOf(parent, margin: 12),
            width: .matchConstraint,
            wrap: wrap,
            horizontalGap: 8,
            verticalGap: 8,
            horizontalChainStyle: .packed,
            contentHorizontalBias: 0,
            padding: padding,
          ),
        ];

    for (final wrap in [FlowWrap.chain, FlowWrap.aligned]) {
      testWidgets('${wrap.name} wrap keeps a row that exactly fits the flow',
          (tester) async {
        await tester.pumpWidget(host(chipFlow(wrap), width: 332));
        for (final id in const [#c0, #c1, #c2, #c3]) {
          expect(rectOf(tester, id).top, 12);
        }
        expect(rectOf(tester, #c0).left, 12);
        expect(rectOf(tester, #c3).right, 332 - 12);
      });

      testWidgets(
          '${wrap.name} wrap moves a widget that overflows the flow by one '
          'pixel to the next row', (tester) async {
        await tester.pumpWidget(host(chipFlow(wrap), width: 331));
        expect(rectOf(tester, #c2).top, 12);
        expect(rectOf(tester, #c3).top, rectOf(tester, #c0).bottom + 8);
        for (final id in const [#c0, #c1, #c2, #c3]) {
          expect(rectOf(tester, id).left, greaterThanOrEqualTo(12));
          expect(rectOf(tester, id).right, lessThanOrEqualTo(331 - 12));
        }
      });
    }

    testWidgets('padding insets every side and narrows the rows',
        (tester) async {
      await tester.pumpWidget(
          host(chipFlow(FlowWrap.chain, padding: 10), width: 352));
      expect(rectOf(tester, #c0).topLeft, const Offset(22, 22));
      expect(rectOf(tester, #c3).top, 22);
      expect(rectOf(tester, #c3).right, 352 - 22);

      await tester.pumpWidget(
          host(chipFlow(FlowWrap.chain, padding: 10), width: 351));
      expect(rectOf(tester, #c3).left, 22);
      expect(rectOf(tester, #c3).top, rectOf(tester, #c0).bottom + 8);
    });

    testWidgets('padding resolves to both sides in right-to-left layouts',
        (tester) async {
      await tester.pumpWidget(host(
        chipFlow(FlowWrap.chain, padding: 10),
        width: 352,
        direction: TextDirection.rtl,
      ));
      expect(rectOf(tester, #c0).right, 352 - 22);
      expect(rectOf(tester, #c3).left, 22);
    });

    testWidgets('the website flow example wraps within its margins',
        (tester) async {
      // At a 390 px viewport the home page gives the example a 316 x 188
      // layout, so the flow is 292 wide; these are the example's chips at
      // their widths in the site's font. The first four need 308.
      const chips = {
        #constraint: 90.95,
        #layout: 66.15,
        #wraps: 65.62,
        #when: 61.39,
        #it: 36.42,
        #runs: 55.3,
        #out: 48.42,
        #of: 40.83,
        #room: 59.41,
      };
      await tester.pumpWidget(host(width: 316, height: 188, [
        for (final MapEntry(key: id, value: width) in chips.entries)
          chip(id, width),
        ConstraintFlow(
          id: #flow,
          referenced: chips.keys.toList(),
          start: .startOf(parent, margin: 12),
          end: .endOf(parent, margin: 12),
          top: .topOf(parent, margin: 12),
          width: .matchConstraint,
          wrap: .chain,
          horizontalGap: 8,
          verticalGap: 8,
          horizontalChainStyle: .packed,
          contentHorizontalBias: 0,
        ),
      ]));
      final when = rectOf(tester, #when);
      expect(when.left, 12);
      expect(when.top, rectOf(tester, #constraint).bottom + 8);
      for (final id in chips.keys) {
        expect(rectOf(tester, id).left, greaterThanOrEqualTo(12));
        expect(rectOf(tester, id).right, lessThanOrEqualTo(316 - 12));
      }
    });

    testWidgets('grid arranges cells into rows and columns', (tester) async {
      await tester.pumpWidget(host([
        cell(#a, 10, 10),
        cell(#b, 10, 10),
        cell(#c, 10, 10),
        cell(#d, 10, 10),
        ConstraintGrid(
          id: #grid,
          referenced: const [#a, #b, #c, #d],
          rows: 2,
          columns: 2,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
        ),
      ]));
      // 2x2 grid over 800x600: cells centered in 400x300 boxes.
      expect(rectOf(tester, #a).center, const Offset(200, 150));
      expect(rectOf(tester, #b).center, const Offset(600, 150));
      expect(rectOf(tester, #c).center, const Offset(200, 450));
      expect(rectOf(tester, #d).center, const Offset(600, 450));
    });

    testWidgets('grid column weights split the width unevenly',
        (tester) async {
      await tester.pumpWidget(host([
        cell(#a, 10, 10),
        cell(#b, 10, 10),
        ConstraintGrid(
          id: #grid,
          referenced: const [#a, #b],
          rows: 1,
          columns: 2,
          columnWeights: const [1, 3],
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
        ),
      ]));
      // Column widths 200 / 600.
      expect(rectOf(tester, #a).center.dx, 100);
      expect(rectOf(tester, #b).center.dx, 500);
    });

    testWidgets('grid spans stretch a widget across cells', (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          width: .matchConstraint,
          height: .matchConstraint,
          child: box(#a),
        ),
        cell(#b, 10, 10),
        cell(#c, 10, 10),
        ConstraintGrid(
          id: #grid,
          referenced: const [#a, #b, #c],
          rows: 2,
          columns: 2,
          spans: '0:1x2',
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
        ),
      ]));
      // #a spans both columns of the first row.
      expect(rectOf(tester, #a), const Rect.fromLTWH(0, 0, 800, 300));
      expect(rectOf(tester, #b).center, const Offset(200, 450));
      expect(rectOf(tester, #c).center, const Offset(600, 450));
    });

    testWidgets('flow reflows when the referenced list changes',
        (tester) async {
      Widget build(List<Symbol> refs) => host([
            cell(#a, 300, 40),
            cell(#b, 300, 40),
            cell(#c, 300, 40),
            ConstraintFlow(
              id: #flow,
              referenced: refs,
              start: .startOf(parent),
              end: .endOf(parent),
              top: .topOf(parent),
              width: .matchConstraint,
              height: .wrapContent,
              wrap: .chain,
            ),
          ]);
      await tester.pumpWidget(build(const [#a, #b, #c]));
      expect(rectOf(tester, #c).top, greaterThan(rectOf(tester, #a).top));
      // With only two referenced widgets they fit on one row; #c is no
      // longer arranged by the flow.
      await tester.pumpWidget(build(const [#a, #b]));
      expect(rectOf(tester, #b).top, rectOf(tester, #a).top);
    });
  });

  // Android's ConstraintLayout.LayoutParams.resolveLayoutDirection mirrors two
  // values in a right-to-left layout: the horizontal bias of a child with any
  // start/end link, and the position of a vertical guideline.
  group('right-to-left', () {

    for (final direction in TextDirection.values) {
      testWidgets('start/end links replace both absolute links (${direction.name})',
          (tester) async {
        await tester.pumpWidget(host([
          Constrained(
            id: #start,
            start: .startOf(parent),
            left: .leftOf(parent),
            right: .rightOf(parent),
            top: .topOf(parent),
            horizontalBias: 0.25,
            width: .fixed(100),
            height: .fixed(20),
            child: box(#start),
          ),
          Constrained(
            id: #end,
            end: .endOf(parent),
            left: .leftOf(parent),
            right: .rightOf(parent),
            top: .bottomOf(#start),
            horizontalBias: 0.25,
            width: .fixed(100),
            height: .fixed(20),
            child: box(#end),
          ),
        ], direction: direction));
        expect(rectOf(tester, #start).left,
            direction == TextDirection.ltr ? 0 : 700);
        expect(rectOf(tester, #end).left,
            direction == TextDirection.ltr ? 700 : 0);
      });
    }

    const rtl = TextDirection.rtl;

    // 700 of free width around each child, and 500 of free height around
    // #startEnd.
    List<Widget> biased() => [
          Constrained(
            id: #startEnd,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
            width: .fixed(100),
            height: .fixed(100),
            horizontalBias: 0.25,
            verticalBias: 0.25,
            child: box(#startEnd),
          ),
          Constrained(
            id: #leftRight,
            left: .leftOf(parent),
            right: .rightOf(parent),
            top: .topOf(parent),
            width: .fixed(100),
            height: .fixed(50),
            horizontalBias: 0.25,
            child: box(#leftRight),
          ),
        ];

    testWidgets('a start/end-linked child measures its bias from the start',
        (tester) async {
      await tester.pumpWidget(host(biased(), direction: rtl));
      // A quarter of the free width sits on the right, the start side.
      expect(rectOf(tester, #startEnd).left, 525);
      // Vertical bias never mirrors.
      expect(rectOf(tester, #startEnd).top, 125);
    });

    testWidgets('a child linked only with left/right keeps its bias',
        (tester) async {
      await tester.pumpWidget(host(biased(), direction: rtl));
      expect(rectOf(tester, #leftRight).left, 175);
    });

    testWidgets('a left-to-right layout applies every bias as given',
        (tester) async {
      await tester.pumpWidget(host(biased()));
      expect(rectOf(tester, #startEnd).left, 175);
      expect(rectOf(tester, #startEnd).top, 125);
      expect(rectOf(tester, #leftRight).left, 175);
    });

    testWidgets('a packed start/end chain measures its bias from the start',
        (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          start: .startOf(parent),
          end: .startOf(#b),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          horizontalChainStyle: ChainStyle.packed,
          horizontalBias: 0,
          child: box(#a),
        ),
        Constrained(
          id: #b,
          start: .endOf(#a),
          end: .endOf(parent),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          child: box(#b),
        ),
      ], direction: rtl));
      // The head, #a, is the start-most member: against the right edge.
      expect(rectOf(tester, #a).left, 700);
      expect(rectOf(tester, #b).left, 600);
    });

    // Each marker's absolute left link puts its left edge on a vertical
    // guideline, and its top link its top edge on a horizontal one.
    Widget marker(Symbol id, Symbol vertical, Symbol horizontal) =>
        Constrained(
          id: id,
          left: .leftOf(vertical),
          top: .topOf(horizontal),
          width: .fixed(10),
          height: .fixed(10),
          child: box(id),
        );

    List<Widget> guided() => [
          const Guideline.vertical(id: #vPercent, percent: 0.25),
          const Guideline.vertical(id: #vBegin, begin: 100),
          const Guideline.vertical(id: #vEnd, end: 150),
          const Guideline.horizontal(id: #hPercent, percent: 0.25),
          const Guideline.horizontal(id: #hBegin, begin: 100),
          const Guideline.horizontal(id: #hEnd, end: 150),
          marker(#atPercent, #vPercent, #hPercent),
          marker(#atBegin, #vBegin, #hBegin),
          marker(#atEnd, #vEnd, #hEnd),
        ];

    testWidgets('a vertical guideline mirrors percent, begin, and end',
        (tester) async {
      await tester.pumpWidget(host(guided(), direction: rtl));
      // percent 0.25 lands at 1 - 0.25 of the width from the left, begin 100
      // at 100 from the right, and end 150 at 150 from the left.
      expect(rectOf(tester, #atPercent).left, 600);
      expect(rectOf(tester, #atBegin).left, 700);
      expect(rectOf(tester, #atEnd).left, 150);
    });

    testWidgets('a horizontal guideline is the same in both directions',
        (tester) async {
      await tester.pumpWidget(host(guided(), direction: rtl));
      expect(rectOf(tester, #atPercent).top, 150);
      expect(rectOf(tester, #atBegin).top, 100);
      expect(rectOf(tester, #atEnd).top, 450);
    });

    testWidgets('a left-to-right layout places guidelines as given',
        (tester) async {
      await tester.pumpWidget(host(guided()));
      expect(rectOf(tester, #atPercent).topLeft, const Offset(200, 150));
      expect(rectOf(tester, #atBegin).topLeft, const Offset(100, 100));
      expect(rectOf(tester, #atEnd).topLeft, const Offset(650, 450));
    });

    testWidgets('a flow linked with start/end mirrors its own bias',
        (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          width: .fixed(100),
          height: .fixed(40),
          child: box(#a),
        ),
        ConstraintFlow(
          id: #flow,
          referenced: const [#a],
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          width: .fixed(300),
          horizontalBias: 0.25,
        ),
      ], direction: rtl));
      final ro = tester.renderObject<RenderConstraintLayout>(
          find.byType(ConstraintLayout));
      final flow = tester.renderObject<RenderBox>(find.descendant(
          of: find.byType(ConstraintFlow), matching: find.byType(SizedBox)));
      // Like any start/end-linked child: a quarter of the 500 of free width
      // on the start side.
      expect(flow.localToGlobal(Offset.zero, ancestor: ro).dx, 375);
    });

    // What the docs say about the direction: a flow and a grid mirror their
    // own arrangement, and a barrier margin mirrors for start and end
    // barriers only.
    testWidgets('a flow starts its rows at the right edge', (tester) async {
      await tester.pumpWidget(host([
        for (final id in const [#a, #b, #c])
          Constrained(
            id: id,
            width: .fixed(100),
            height: .fixed(40),
            child: box(id),
          ),
        ConstraintFlow(
          id: #flow,
          referenced: const [#a, #b, #c],
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          width: .matchConstraint,
          horizontalChainStyle: ChainStyle.packed,
          contentHorizontalBias: 0,
        ),
      ], direction: rtl));
      // contentHorizontalBias 0 is the start: the row packs against the right.
      expect(rectOf(tester, #a).left, 700);
      expect(rectOf(tester, #b).left, 600);
      expect(rectOf(tester, #c).left, 500);
    });

    testWidgets('a grid fills its cells from the right', (tester) async {
      await tester.pumpWidget(host([
        for (final id in const [#a, #b])
          Constrained(
            id: id,
            width: .matchConstraint,
            height: .matchConstraint,
            child: box(id),
          ),
        ConstraintGrid(
          id: #grid,
          referenced: const [#a, #b],
          rows: 1,
          columns: 2,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
        ),
      ], direction: rtl));
      // The first cell is the start-most: the right half.
      expect(rectOf(tester, #a), const Rect.fromLTWH(400, 0, 400, 600));
      expect(rectOf(tester, #b), const Rect.fromLTWH(0, 0, 400, 600));
    });

    // Six tiles in three weighted columns with gaps, a span, and a skip. Every
    // track divides evenly, so every edge is a whole pixel.
    List<Widget> tiles({required bool directional, List<Widget> extra = const []}) => [
          for (var i = 0; i < 6; i++)
            Constrained(
              id: Symbol('t$i'),
              width: .matchConstraint,
              height: .matchConstraint,
              child: box(Symbol('t$i')),
            ),
          ConstraintGrid(
            id: #grid,
            referenced: const [#t0, #t1, #t2, #t3, #t4, #t5],
            rows: 3,
            columns: 3,
            columnWeights: const [2, 1, 1],
            horizontalGap: 12,
            verticalGap: 8,
            spans: '0:1x2', // #t0 covers the first two columns of row 0
            skips: '5:1x1',
            // 16 px from the start (or left), 24 px from the end (or right):
            // 760 px wide, columns of 368, 184, and 184 between the gaps,
            // and rows of 184.
            start: directional ? .startOf(parent, margin: 16) : null,
            end: directional ? .endOf(parent, margin: 24) : null,
            left: directional ? null : .leftOf(parent, margin: 16),
            right: directional ? null : .rightOf(parent, margin: 24),
            top: .topOf(parent, margin: 16),
            bottom: .bottomOf(parent, margin: 16),
          ),
          ...extra,
        ];

    const tileIds = [#t0, #t1, #t2, #t3, #t4, #t5];

    testWidgets('a start/end-linked grid mirrors with the layout',
        (tester) async {
      await tester.pumpWidget(host(tiles(directional: true)));
      final ltr = [for (final id in tileIds) rectOf(tester, id)];
      expect(ltr.first, const Rect.fromLTWH(16, 16, 564, 184));
      await tester.pumpWidget(host(tiles(directional: true), direction: rtl));
      // The grid trades its margins, and its cells fill from the right: the
      // whole arrangement is the mirror image.
      for (var i = 0; i < tileIds.length; i++) {
        final r = ltr[i];
        expect(rectOf(tester, tileIds[i]),
            Rect.fromLTWH(800 - r.right, r.top, r.width, r.height),
            reason: '${tileIds[i]}');
      }
    });

    testWidgets('a left/right-linked grid mirrors its cells in place',
        (tester) async {
      await tester.pumpWidget(host(tiles(directional: false)));
      final ltr = [for (final id in tileIds) rectOf(tester, id)];
      await tester.pumpWidget(host(tiles(directional: false), direction: rtl));
      // The grid keeps its absolute position, from x = 16 to x = 776, and
      // mirrors its cells within it.
      for (var i = 0; i < tileIds.length; i++) {
        final r = ltr[i];
        expect(rectOf(tester, tileIds[i]),
            Rect.fromLTWH(16 + 776 - r.right, r.top, r.width, r.height),
            reason: '${tileIds[i]}');
      }
    });

    testWidgets('a widget linked to a grid member follows it', (tester) async {
      // Centered under #t1, in cell 2: the end of the first row.
      final badge = Constrained(
        id: #badge,
        start: .startOf(#t1),
        end: .endOf(#t1),
        top: .bottomOf(#t1, margin: 4),
        width: .fixed(20),
        height: .fixed(10),
        child: box(#badge),
      );
      await tester.pumpWidget(host(tiles(directional: true, extra: [badge])));
      final ltrBadge = rectOf(tester, #badge);
      expect(ltrBadge.center.dx, rectOf(tester, #t1).center.dx);
      await tester.pumpWidget(host(tiles(directional: true, extra: [badge]),
          direction: rtl));
      // #t1 is now the leftmost cell of the first row, after the grid's
      // 24 px end margin, and the badge moved with it.
      final t1 = rectOf(tester, #t1);
      expect(t1, const Rect.fromLTWH(24, 16, 184, 184));
      expect(rectOf(tester, #badge),
          Rect.fromLTWH(t1.center.dx - 10, t1.bottom + 4, 20, 10));
      expect(rectOf(tester, #badge).left, 800 - ltrBadge.right);
    });

    testWidgets('a tile smaller than its cell keeps its bias from the start',
        (tester) async {
      // horizontalBias 0 puts each tile against the start of its cell, so
      // the right-to-left grid is the mirror image of the left-to-right one.
      List<Widget> biased() => [
            for (final id in const [#a, #b])
              Constrained(
                id: id,
                width: .fixed(40),
                height: .fixed(40),
                horizontalBias: 0,
                child: box(id),
              ),
            ConstraintGrid(
              id: #grid,
              referenced: const [#a, #b],
              rows: 1,
              columns: 2,
              start: .startOf(parent),
              end: .endOf(parent),
              top: .topOf(parent),
              bottom: .bottomOf(parent),
            ),
          ];
      await tester.pumpWidget(host(biased()));
      expect(rectOf(tester, #a), const Rect.fromLTWH(0, 280, 40, 40));
      expect(rectOf(tester, #b), const Rect.fromLTWH(400, 280, 40, 40));
      await tester.pumpWidget(host(biased(), direction: rtl));
      expect(rectOf(tester, #a), const Rect.fromLTWH(760, 280, 40, 40));
      expect(rectOf(tester, #b), const Rect.fromLTWH(360, 280, 40, 40));
    });

    // Two labels of different widths with an end barrier past them, and two
    // icons with a start barrier back over them; every other widget hangs
    // off a barrier through start/end links, so the layout as a whole can
    // mirror. A negative margin is in there too.
    const barrierIds = [
      #name, #email, #value, #icon, #badge, #marker, #after,
    ];
    List<Widget> barriered() => [
          Constrained(
            id: #name,
            start: .startOf(parent, margin: 16),
            top: .topOf(parent, margin: 16),
            width: .fixed(80),
            height: .fixed(30),
            child: box(#name),
          ),
          Constrained(
            id: #email,
            start: .startOf(parent, margin: 16),
            top: .bottomOf(#name, margin: 8),
            width: .fixed(120),
            height: .fixed(30),
            child: box(#email),
          ),
          const Barrier(
            id: #labelsEnd,
            edge: .end,
            referenced: [#name, #email],
            margin: 12,
          ),
          Constrained(
            id: #value,
            start: .endOf(#labelsEnd),
            top: .topOf(#name),
            width: .fixed(100),
            height: .fixed(30),
            child: box(#value),
          ),
          Constrained(
            id: #icon,
            start: .startOf(parent, margin: 300),
            top: .bottomOf(#email, margin: 20),
            width: .fixed(60),
            height: .fixed(40),
            child: box(#icon),
          ),
          Constrained(
            id: #badge,
            start: .startOf(parent, margin: 330),
            top: .topOf(#icon),
            width: .fixed(90),
            height: .fixed(20),
            child: box(#badge),
          ),
          const Barrier(
            id: #iconsStart,
            edge: .start,
            referenced: [#icon, #badge],
            margin: 10,
          ),
          Constrained(
            id: #marker,
            end: .startOf(#iconsStart),
            top: .bottomOf(#icon),
            width: .fixed(20),
            height: .fixed(20),
            child: box(#marker),
          ),
          const Barrier(
            id: #valueEnd,
            edge: .end,
            referenced: [#value],
            margin: -6,
          ),
          Constrained(
            id: #after,
            start: .endOf(#valueEnd),
            top: .bottomOf(#value),
            width: .fixed(40),
            height: .fixed(10),
            child: box(#after),
          ),
        ];

    testWidgets('start and end barriers with margins mirror exactly',
        (tester) async {
      await tester.pumpWidget(host(barriered()));
      final ltr = {for (final id in barrierIds) id: rectOf(tester, id)};
      // The end barrier sits 12 past the wider label, the start barrier 10
      // back over the icons, and the negative margin pulls 6 back over #value.
      expect(ltr[#value]!.left, 16 + 120 + 12);
      expect(ltr[#marker]!.right, 300 + 10);
      expect(ltr[#after]!.left, ltr[#value]!.right - 6);

      await tester.pumpWidget(host(barriered(), direction: rtl));
      for (final id in barrierIds) {
        final l = ltr[id]!;
        expect(
          rectOf(tester, id),
          Rect.fromLTWH(800 - l.left - l.width, l.top, l.width, l.height),
          reason: '$id must sit at the mirror of its left-to-right position',
        );
      }
    });

    testWidgets('left and right barriers keep their margin in right-to-left '
        'text', (tester) async {
      List<Widget> absolute() => [
            Constrained(
              id: #label,
              start: .startOf(parent, margin: 100),
              top: .topOf(parent),
              width: .fixed(100),
              height: .fixed(30),
              child: box(#label),
            ),
            const Barrier(
              id: #leftEdge,
              edge: .left,
              referenced: [#label],
              margin: 10,
            ),
            const Barrier(
              id: #rightEdge,
              edge: .right,
              referenced: [#label],
              margin: 10,
            ),
            for (final (id, barrier, top) in const [
              (#onLeft, #leftEdge, 40.0),
              (#onRight, #rightEdge, 60.0),
            ])
              Constrained(
                id: id,
                left: .leftOf(barrier),
                top: .topOf(parent, margin: top),
                width: .fixed(10),
                height: .fixed(10),
                child: box(id),
              ),
          ];
      // #label spans 600 to 700 in right-to-left text: a positive margin
      // still moves both barriers right.
      await tester.pumpWidget(host(absolute(), direction: rtl));
      expect(rectOf(tester, #onLeft).left, 610);
      expect(rectOf(tester, #onRight).left, 710);

      await tester.pumpWidget(host(absolute()));
      expect(rectOf(tester, #onLeft).left, 110);
      expect(rectOf(tester, #onRight).left, 210);
    });

    // Three 24-wide members between 24-px outer margins.
    List<Widget> marginChain(ChainStyle style) => [
          for (var i = 0; i < 3; i++)
            Constrained(
              id: Symbol('c$i'),
              start: i == 0
                  ? .startOf(parent, margin: 24)
                  : .endOf(Symbol('c${i - 1}')),
              end: i == 2
                  ? .endOf(parent, margin: 24)
                  : .startOf(Symbol('c${i + 1}')),
              top: .topOf(parent),
              width: .fixed(24),
              height: .fixed(24),
              horizontalChainStyle: i == 0 ? style : null,
              child: box(Symbol('c$i')),
            ),
        ];

    for (final style in ChainStyle.values) {
      testWidgets('a ${style.name} chain with margins mirrors',
          (tester) async {
        await tester.pumpWidget(host(marginChain(style)));
        final ltr = [
          for (var i = 0; i < 3; i++) rectOf(tester, Symbol('c$i')),
        ];
        await tester.pumpWidget(host(marginChain(style), direction: rtl));
        for (var i = 0; i < 3; i++) {
          expect(rectOf(tester, Symbol('c$i')).left, 800 - ltr[i].right);
        }
      });
    }

    testWidgets('a weighted chain with margins mirrors', (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #cancel,
          start: .startOf(parent, margin: 16),
          end: .startOf(#confirm, margin: 8),
          top: .topOf(parent),
          width: .matchConstraint,
          height: .fixed(40),
          horizontalWeight: 1,
          child: box(#cancel),
        ),
        Constrained(
          id: #confirm,
          start: .endOf(#cancel),
          end: .endOf(parent, margin: 16),
          top: .topOf(parent),
          width: .matchConstraint,
          height: .fixed(40),
          horizontalWeight: 2,
          child: box(#confirm),
        ),
      ], direction: rtl));
      expect(rectOf(tester, #cancel), const Rect.fromLTRB(531, 0, 784, 40));
      expect(rectOf(tester, #confirm), const Rect.fromLTRB(16, 0, 523, 40));
    });

    testWidgets('a vertical chain with margins ignores the text direction',
        (tester) async {
      await tester.pumpWidget(host([
        for (var i = 0; i < 3; i++)
          Constrained(
            id: Symbol('v$i'),
            start: .startOf(parent),
            top: i == 0
                ? .topOf(parent, margin: 40)
                : .bottomOf(Symbol('v${i - 1}')),
            bottom: i == 2
                ? .bottomOf(parent, margin: 40)
                : .topOf(Symbol('v${i + 1}')),
            width: .fixed(50),
            height: .fixed(50),
            verticalChainStyle: i == 0 ? ChainStyle.spreadInside : null,
            child: box(Symbol('v$i')),
          ),
      ], direction: rtl));
      expect(rectOf(tester, Symbol('v0')).top, 40);
      expect(rectOf(tester, Symbol('v1')).top, 275);
      expect(rectOf(tester, Symbol('v2')).top, 510);
    });
  });
}
