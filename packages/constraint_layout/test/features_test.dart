// Feature tests for the adapter surface that exposes engine capabilities:
// percent / bounded / constrained-wrap dimensions, chain styles and weights,
// visibility modes, circular positioning, guidelines, and barriers.
//
// The default flutter_test surface is 800x600; hosts pin that size explicitly
// so golden positions are stable.

import 'package:constraint_layout/constraint_layout.dart';
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
}
