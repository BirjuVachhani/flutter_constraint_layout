// Extraction/classification tests for the debug-overlay scene builder.
//
// Pumps real layouts and asserts on the DebugScene produced by
// RenderConstraintLayout.debugDescribeScene(): connection types, endpoints,
// margins, chain grouping, helper lines. No pixels are compared here.

import 'package:constraint_layout/constraint_layout.dart';
import 'package:constraint_layout/src/debug/debug_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(List<Widget> children,
        {double width = 800, double height = 600}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: height,
          child: ConstraintLayout(children: children),
        ),
      ),
    );

Widget box(Symbol id) => SizedBox(key: ValueKey(id));

DebugScene sceneOf(WidgetTester tester) => tester
    .renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout))
    .debugDescribeScene();

List<Widget> chainRow(ChainStyle? style) => [
      Constrained(
        id: #a,
        start: .startOf(parent),
        end: .startOf(#b),
        top: .topOf(parent),
        width: .fixed(100),
        height: .fixed(50),
        horizontalChainStyle: style,
        child: box(#a),
      ),
      Constrained(
        id: #b,
        start: .endOf(#a),
        end: .startOf(#c),
        top: .topOf(parent),
        width: .fixed(100),
        height: .fixed(50),
        child: box(#b),
      ),
      Constrained(
        id: #c,
        start: .endOf(#b),
        end: .endOf(parent),
        top: .topOf(parent),
        width: .fixed(100),
        height: .fixed(50),
        child: box(#c),
      ),
    ];

void main() {
  group('chains', () {
    testWidgets('a 3-widget spread chain yields 2 chain links + outer springs',
        (tester) async {
      await tester.pumpWidget(host(chainRow(null)));
      final scene = sceneOf(tester);

      final chains = scene.connections
          .where((c) => c.type == DebugConnectionType.chain)
          .toList();
      expect(chains, hasLength(2));
      for (final c in chains) {
        expect(c.horizontal, isTrue);
        expect(c.chainStyle, ChainStyle.spread);
      }

      final springs = scene.connections
          .where((c) => c.type == DebugConnectionType.spring)
          .toList();
      expect(springs, hasLength(2),
          reason: 'the two outer parent connections are opposing pairs');
      expect(springs.every((c) => c.targetIsParent), isTrue);
    });

    testWidgets('chain style is read from the head for every link',
        (tester) async {
      for (final (style, expected) in [
        (ChainStyle.spreadInside, ChainStyle.spreadInside),
        (ChainStyle.packed, ChainStyle.packed),
      ]) {
        await tester.pumpWidget(host(chainRow(style)));
        final chains = sceneOf(tester)
            .connections
            .where((c) => c.type == DebugConnectionType.chain);
        expect(chains.map((c) => c.chainStyle), everyElement(expected));
      }
    });

    testWidgets('vertical chains are classified on the vertical axis',
        (tester) async {
      Widget cell(Symbol id, VerticalLink top, VerticalLink bottom) =>
          Constrained(
            id: id,
            start: .startOf(parent),
            top: top,
            bottom: bottom,
            width: .fixed(100),
            height: .fixed(50),
            child: box(id),
          );
      await tester.pumpWidget(host([
        cell(#a, .topOf(parent), .topOf(#b)),
        cell(#b, .bottomOf(#a), .topOf(#c)),
        cell(#c, .bottomOf(#b), .bottomOf(parent)),
      ]));
      final chains = sceneOf(tester)
          .connections
          .where((c) => c.type == DebugConnectionType.chain)
          .toList();
      expect(chains, hasLength(2));
      expect(chains.every((c) => !c.horizontal), isTrue);
    });
  });

  group('single-sided and opposing constraints', () {
    testWidgets('one-sided parent link is a normal connection with its margin',
        (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          start: .startOf(parent, margin: 16),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          child: box(#a),
        ),
      ]));
      final scene = sceneOf(tester);
      final horizontals =
          scene.connections.where((c) => c.horizontal).toList();
      expect(horizontals, hasLength(1));
      final c = horizontals.single;
      expect(c.type, DebugConnectionType.normal);
      expect(c.margin, 16);
      expect(c.targetIsParent, isTrue);
      expect(c.sourceEdge, DebugEdge.left);
      expect(c.sourcePoint, const Offset(16, 25));
      expect(c.targetPoint, const Offset(0, 25));
    });

    testWidgets('opposing constraints to different targets are springs; the '
        'longer side of a biased pair is dashed', (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          start: .startOf(parent),
          end: .leftOf(#b),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          horizontalBias: 0.2,
          child: box(#a),
        ),
        Constrained(
          id: #b,
          end: .endOf(parent),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          child: box(#b),
        ),
      ]));
      final springs = sceneOf(tester)
          .connections
          .where((c) => c.type == DebugConnectionType.spring)
          .toList();
      expect(springs, hasLength(2));
      final dashed = springs.where((c) => c.dashed).toList();
      expect(dashed, hasLength(1));
      expect(dashed.single.sourceEdge, DebugEdge.right,
          reason: 'bias 0.2 leaves the free space on the right side');
    });

    testWidgets('centering on one target collapses to a single center pair',
        (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          child: box(#a),
        ),
      ]));
      final scene = sceneOf(tester);
      final horizontals =
          scene.connections.where((c) => c.horizontal).toList();
      expect(horizontals, hasLength(1));
      final c = horizontals.single;
      expect(c.type, DebugConnectionType.center);
      expect(c.targetIsParent, isTrue);
      expect(c.centerDashedLine, isNotNull);
      expect(
        scene.connections.where((c) => c.type == DebugConnectionType.spring),
        isEmpty,
      );
    });
  });

  group('baseline and circular', () {
    testWidgets('baseline links produce a baseline connection and baseline '
        'marks on both boxes', (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          start: .startOf(parent),
          top: .topOf(parent, margin: 40),
          child: const Text('Hello', key: ValueKey(#a)),
        ),
        Constrained(
          id: #b,
          start: .endOf(#a, margin: 12),
          baseline: .baselineOf(#a),
          child: const Text('World', key: ValueKey(#b)),
        ),
      ]));
      final scene = sceneOf(tester);
      final baselines = scene.connections
          .where((c) => c.type == DebugConnectionType.baseline)
          .toList();
      expect(baselines, hasLength(1));
      expect(scene.boxes.where((b) => b.baselineY != null), hasLength(2));
    });

    testWidgets('circular constraints carry angle and radius', (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #hub,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
          width: .fixed(40),
          height: .fixed(40),
          child: box(#hub),
        ),
        Constrained(
          id: #sat,
          circle: .around(#hub, angle: 90, radius: 100),
          width: .fixed(20),
          height: .fixed(20),
          child: box(#sat),
        ),
      ]));
      final circulars = sceneOf(tester)
          .connections
          .where((c) => c.type == DebugConnectionType.circular)
          .toList();
      expect(circulars, hasLength(1));
      expect(circulars.single.circularAngle, 90);
      expect(circulars.single.circularRadius, 100);
      expect(circulars.single.dashed, isTrue);
    });
  });

  group('helpers', () {
    testWidgets('guidelines resolve to a line and a chip', (tester) async {
      await tester.pumpWidget(host([
        const Guideline.vertical(id: #g, percent: 0.25),
        Constrained(
          id: #a,
          start: .rightOf(#g, margin: 8),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          child: box(#a),
        ),
      ]));
      final scene = sceneOf(tester);
      expect(scene.guidelines, hasLength(1));
      final g = scene.guidelines.single;
      expect(g.vertical, isTrue);
      expect(g.position, 200);
      expect(g.chipText, '25%');
      // The sibling's link targets the guideline, not the parent.
      final link = scene.connections.singleWhere((c) => c.horizontal);
      expect(link.targetIsParent, isFalse);
      expect(link.targetPoint.dx, 200);
      expect(link.margin, 8);
    });

    testWidgets('begin and end guidelines label their chips accordingly',
        (tester) async {
      await tester.pumpWidget(host([
        const Guideline.vertical(id: #gb, begin: 150),
        const Guideline.horizontal(id: #ge, end: 100),
      ]));
      final scene = sceneOf(tester);
      expect(scene.guidelines, hasLength(2));
      expect(scene.guidelines[0].chipText, '150');
      expect(scene.guidelines[1].vertical, isFalse);
      expect(scene.guidelines[1].position, 500);
      expect(scene.guidelines[1].chipText, 'end 100');
    });

    testWidgets('barriers resolve to a line with the fade on the facing side',
        (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          start: .startOf(parent),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          child: box(#a),
        ),
        Constrained(
          id: #b,
          start: .endOf(#a),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(80),
          child: box(#b),
        ),
        Barrier(
          id: #bar,
          edge: .bottom,
          referenced: const [#a, #b],
          margin: 24,
        ),
      ]));
      final scene = sceneOf(tester);
      expect(scene.barriers, hasLength(1));
      final bar = scene.barriers.single;
      expect(bar.start.dy, 104, reason: 'tallest referenced (80) + margin 24');
      expect(bar.end.dy, 104);
      expect(bar.fadeDirection, const Offset(0, 1));
    });

    testWidgets('flow emits a virtual box over its solved bounds',
        (tester) async {
      Widget cell(Symbol id) => Constrained(
            id: id,
            width: .fixed(100),
            height: .fixed(40),
            child: box(id),
          );
      await tester.pumpWidget(host([
        cell(#a),
        cell(#b),
        cell(#c),
        ConstraintFlow(
          id: #flow,
          referenced: const [#a, #b, #c],
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          width: .matchConstraint,
          horizontalChainStyle: ChainStyle.packed,
        ),
      ]));
      final scene = sceneOf(tester);
      final virtuals = scene.boxes.where((b) => b.virtual).toList();
      expect(virtuals, hasLength(1));
      expect(virtuals.single.idLabel, 'flow');
      expect(virtuals.single.rect.width, 800);
      expect(virtuals.single.rect.top, 0);
    });

    testWidgets('grid members connect to synthesized box rects without boxes '
        'of their own leaking in', (tester) async {
      Widget cell(Symbol id) => Constrained(
            id: id,
            width: .fixed(10),
            height: .fixed(10),
            child: box(id),
          );
      await tester.pumpWidget(host([
        cell(#a),
        cell(#b),
        cell(#c),
        cell(#d),
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
      final scene = sceneOf(tester);
      // 4 member boxes + 1 virtual grid box; the grid's internal engine box
      // widgets never surface as scene boxes.
      expect(scene.boxes, hasLength(5));
      expect(scene.boxes.where((b) => b.virtual), hasLength(1));
      // Member constraints (to the internal boxes) still resolve.
      expect(scene.connections, isNotEmpty);
      expect(
        scene.connections.every(
            (c) => c.sourcePoint.isFinite && c.targetPoint.isFinite),
        isTrue,
      );
    });
  });

  group('visibility and labels', () {
    testWidgets('gone widgets lose their box but incoming links keep the '
        'gone margin', (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          start: .startOf(parent),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          visibility: .gone,
          child: box(#a),
        ),
        Constrained(
          id: #b,
          start: .endOf(#a, margin: 10, goneMargin: 24),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          child: box(#b),
        ),
      ]));
      final scene = sceneOf(tester);
      expect(scene.boxes, hasLength(1));
      expect(scene.boxes.single.idLabel, 'b');
      final link = scene.connections.singleWhere((c) => c.horizontal);
      expect(link.margin, 24);
    });

    testWidgets('invisible widgets keep their box, flagged invisible',
        (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          start: .startOf(parent),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          visibility: .invisible,
          child: box(#a),
        ),
      ]));
      final scene = sceneOf(tester);
      expect(scene.boxes.single.invisible, isTrue);
    });

    testWidgets('boxes carry the Symbol id and the user-facing widget type',
        (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #avatar,
          start: .startOf(parent),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          child: Container(color: const Color(0xFF112233)),
        ),
      ]));
      final b = sceneOf(tester).boxes.single;
      expect(b.idLabel, 'avatar');
      expect(b.typeLabel, 'Container');
      expect(b.connectedEdges, {DebugEdge.left, DebugEdge.top});
    });
  });
}
