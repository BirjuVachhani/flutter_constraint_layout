// Adapter-level behaviour of the two virtual layouts.
//
// The visual results are pinned by the goldens; what this covers is the part
// the goldens cannot show, notably `ConstraintGrid`'s documented promise that
// `rows` or `columns` may be omitted and derived from the other plus the
// widget count. Deriving needs the widget count, which the host only knows
// after it has added the referenced widgets, so this used to resolve to a zero
// track count and take the layout down with a null-check error.
//
// A flow is measured as Android measures a view Flow: the view measurer runs
// the flow's own measure, which measures each of its widgets through the view
// measurer in turn. Those frames and requests are checked against VOpDriver
// at the pin (view path, level 257; the `p4b:` probes are op lists of
// test/parity/probes.in, with their output in test/parity/probes.J257.txt).
// The grid has no Android oracle (it is outside the parity contract; see
// "Limitations and differences from Android" in the README), so its tests
// keep their own expectations.

import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(List<Widget> children, {Size size = const Size(400, 300)}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: ConstraintLayout(children: children),
        ),
      ),
    );

Rect rectOf(WidgetTester tester, Symbol id) {
  final box = tester.renderObject<RenderBox>(find.byKey(ValueKey(id)));
  final ro = tester.renderObject<RenderConstraintLayout>(
    find.byType(ConstraintLayout),
  );
  return box.localToGlobal(Offset.zero, ancestor: ro) & box.size;
}

List<Widget> cells(int count) => [
  for (var i = 0; i < count; i++)
    Constrained(
      id: Symbol('g$i'),
      width: .matchConstraint,
      height: .matchConstraint,
      child: SizedBox(key: ValueKey(Symbol('g$i'))),
    ),
];

const List<Symbol> sixIds = [#g0, #g1, #g2, #g3, #g4, #g5];

/// The distinct values in [values], ascending.
List<double> distinct(Iterable<double> values) =>
    values.toSet().toList()..sort();

void main() {
  group('grid track derivation', () {
    testWidgets('columns are derived when only rows is given', (tester) async {
      await tester.pumpWidget(
        host([
          ...cells(6),
          const ConstraintGrid(
            id: #grid,
            referenced: sixIds,
            rows: 2,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
          ),
        ]),
      );
      expect(tester.takeException(), isNull);

      final rects = [for (final id in sixIds) rectOf(tester, id)];
      // Six widgets in two rows is three columns.
      expect(distinct(rects.map((r) => r.top)), hasLength(2));
      expect(distinct(rects.map((r) => r.left)), hasLength(3));
    });

    testWidgets('rows are derived when only columns is given', (tester) async {
      await tester.pumpWidget(
        host([
          ...cells(6),
          const ConstraintGrid(
            id: #grid,
            referenced: sixIds,
            columns: 3,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
          ),
        ]),
      );
      expect(tester.takeException(), isNull);

      final rects = [for (final id in sixIds) rectOf(tester, id)];
      expect(distinct(rects.map((r) => r.left)), hasLength(3));
      expect(distinct(rects.map((r) => r.top)), hasLength(2));
    });

    testWidgets('both are derived when neither is given', (tester) async {
      await tester.pumpWidget(
        host([
          ...cells(6),
          const ConstraintGrid(
            id: #grid,
            referenced: sixIds,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
          ),
        ]),
      );
      expect(tester.takeException(), isNull);

      final rects = [for (final id in sixIds) rectOf(tester, id)];
      // Whatever shape it picks, every widget must land somewhere real.
      expect(rects.every((r) => r.width > 0 && r.height > 0), isTrue);
      expect(distinct(rects.map((r) => r.top)).length, greaterThan(1));
    });

    testWidgets('changing the track count re-places the cells', (tester) async {
      Widget grid({int? rows, int? columns}) => host([
        ...cells(6),
        ConstraintGrid(
          id: #grid,
          referenced: sixIds,
          rows: rows,
          columns: columns,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
        ),
      ]);

      await tester.pumpWidget(grid(rows: 2));
      final twoRows = [for (final id in sixIds) rectOf(tester, id)];
      expect(distinct(twoRows.map((r) => r.top)), hasLength(2));

      await tester.pumpWidget(grid(rows: 3));
      expect(tester.takeException(), isNull);
      final threeRows = [for (final id in sixIds) rectOf(tester, id)];
      expect(distinct(threeRows.map((r) => r.top)), hasLength(3));
    });

    testWidgets('a grid with no referenced widgets is harmless', (
      tester,
    ) async {
      await tester.pumpWidget(
        host([
          const ConstraintGrid(
            id: #grid,
            referenced: [],
            rows: 2,
            columns: 2,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
          ),
        ]),
      );
      expect(tester.takeException(), isNull);
    });

    for (final referenced in const [
      <Symbol>[],
      [#g0],
    ]) {
      testWidgets(
        'spans outnumbering ${referenced.length} referenced widgets lay out',
        (tester) async {
          // A grid fed from a list that is empty or shorter than its spans
          // expect. The extra entries used to throw out of performLayout.
          await tester.pumpWidget(
            host([
              ...cells(1),
              Constrained(
                id: #title,
                left: .leftOf(parent, margin: 150),
                top: .topOf(parent, margin: 20),
                width: .fixed(100),
                height: .fixed(50),
                child: const SizedBox(key: ValueKey(#title)),
              ),
              ConstraintGrid(
                id: #grid,
                referenced: referenced,
                rows: 2,
                columns: 2,
                spans: '0:1x2,2:1x1',
                start: .startOf(parent),
                end: .endOf(parent),
                top: .topOf(parent),
                bottom: .bottomOf(parent),
              ),
            ]),
          );
          expect(tester.takeException(), isNull);
          expect(rectOf(tester, #title), const Rect.fromLTWH(150, 20, 100, 50));
          if (referenced.isNotEmpty) {
            expect(rectOf(tester, #g0), const Rect.fromLTWH(0, 0, 400, 150));
          }
        },
      );
    }

    testWidgets('a resized grid keeps every widget in its cell', (
      tester,
    ) async {
      // Seven widgets in three columns derive three rows, so two cells stay
      // free. Each later solve used to move widgets on into them: after this
      // resize, #g0 and #g1 ended up in the last row.
      const seven = [#g0, #g1, #g2, #g3, #g4, #g5, #g6];
      Widget grid(double width) => host([
        ...cells(7),
        const ConstraintGrid(
          id: #grid,
          referenced: seven,
          columns: 3,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
        ),
      ], size: Size(width, 300));

      for (final width in const [300.0, 330.0, 360.0]) {
        await tester.pumpWidget(grid(width));
        final cell = width / 3;
        for (var i = 0; i < seven.length; i++) {
          expect(
            rectOf(tester, seven[i]).topLeft,
            Offset(i % 3 * cell, i ~/ 3 * 100.0),
            reason: '${seven[i]} at width $width',
          );
        }
      }
    });

    testWidgets('an empty grid with derived rows leaves its siblings alone', (
      tester,
    ) async {
      // A grid fed from a list that is empty: three columns and no widgets
      // derive zero rows. That used to abandon the engine's solve, which put
      // #title at 0, 0.
      await tester.pumpWidget(
        host([
          Constrained(
            id: #title,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent, margin: 20),
            width: .fixed(100),
            height: .fixed(50),
            child: const SizedBox(key: ValueKey(#title)),
          ),
          const ConstraintGrid(
            id: #grid,
            referenced: [],
            columns: 3,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .bottomOf(#title),
            bottom: .bottomOf(parent),
          ),
        ]),
      );
      expect(tester.takeException(), isNull);
      expect(rectOf(tester, #title), const Rect.fromLTWH(150, 20, 100, 50));
    });
  });

  // What constraintlayout-core 1.1.0 changed in the grid engine, as seen
  // through ConstraintGrid. The engine's grid_modes_test.dart checks the same
  // rules against values from the released core.
  group('grid weights and spans', () {
    List<Widget> row(List<double> columnWeights) => [
      ...cells(3),
      ConstraintGrid(
        id: #grid,
        referenced: const [#g0, #g1, #g2],
        rows: 1,
        columns: 3,
        columnWeights: columnWeights,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        bottom: .bottomOf(parent),
      ),
    ];

    List<double> widths(WidgetTester tester) => [
      for (final id in const [#g0, #g1, #g2]) rectOf(tester, id).width,
    ];

    testWidgets('a short weight list is padded with weights of 1', (
      tester,
    ) async {
      await tester.pumpWidget(host(row(const [2])));
      // [2] on three columns is [2, 1, 1].
      expect(widths(tester), [200, 100, 100]);
    });

    testWidgets('a long weight list is trimmed to the column count', (
      tester,
    ) async {
      await tester.pumpWidget(host(row(const [1, 2, 3, 4])));
      expect(widths(tester), [67, 133, 200]);
    });

    testWidgets('a short row weight list is padded too', (tester) async {
      await tester.pumpWidget(
        host([
          ...cells(2),
          const ConstraintGrid(
            id: #grid,
            referenced: [#g0, #g1],
            rows: 2,
            columns: 1,
            rowWeights: [3],
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
          ),
        ]),
      );
      expect(rectOf(tester, #g0).height, 225);
      expect(rectOf(tester, #g1).height, 75);
    });

    testWidgets('spans go to the widgets in order of cell index', (
      tester,
    ) async {
      const ids = [#g0, #g1, #g2, #g3, #g4, #g5, #g6];
      await tester.pumpWidget(
        host([
          ...cells(7),
          const ConstraintGrid(
            id: #grid,
            referenced: ids,
            rows: 3,
            columns: 3,
            // Listed out of order: cell 0's span still goes to #g0.
            spans: '4:1x2, 0:2x1',
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
          ),
        ], size: const Size(300, 300)),
      );
      expect(rectOf(tester, #g0), const Rect.fromLTWH(0, 0, 100, 200));
      expect(rectOf(tester, #g1), const Rect.fromLTWH(100, 100, 200, 100));
      // The rest fill the free cells in order: 1, 2, 6, 7, 8.
      expect(rectOf(tester, #g2), const Rect.fromLTWH(100, 0, 100, 100));
      expect(rectOf(tester, #g3), const Rect.fromLTWH(200, 0, 100, 100));
      expect(rectOf(tester, #g4), const Rect.fromLTWH(0, 200, 100, 100));
    });

    testWidgets('row weights hold when a tile fills its row exactly', (
      tester,
    ) async {
      // Rows of 112 and 28 px, and #g1 is exactly as tall as the second row.
      // The solver used to settle on a collapsed solution here, with #g1 at
      // 88. Expected tops from the released GridCore 1.1.1 on the JDK.
      await tester.pumpWidget(
        host([
          for (final id in const [#g0, #g1, #g2])
            Constrained(
              id: id,
              width: .fixed(5),
              height: .fixed(28),
              child: SizedBox(key: ValueKey(id)),
            ),
          const ConstraintGrid(
            id: #grid,
            referenced: [#g0, #g1, #g2],
            rows: 2,
            columns: 2,
            orientation: Axis.vertical,
            rowWeights: [4, 1],
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
          ),
        ], size: const Size(300, 140)),
      );
      expect(rectOf(tester, #g0).top, 42);
      expect(rectOf(tester, #g1).top, 112);
      expect(rectOf(tester, #g2).top, 42);
    });
  });

  group('flow', () {
    for (final bounded in [true, false]) {
      testWidgets('measures its widgets through the view measurer '
          '(${bounded ? 'bounded' : 'unbounded'} height)', (tester) async {
        // Java J257: a (33, 5) 150 x 20, b (217, 0) 150 x 30, c (125, 30)
        // 150 x 20, F (0, 0) 400 x 50, in a root 400 x 100 (bounded) or
        // 400 x 50 (VOpDriver view, p4b:flow and p4b:flow_u: a chain-wrapping
        // horizontal flow, MC x WRAP between both parent edges, of three
        // boxes 150 wide). The flow measures its widgets (F) inside its own
        // request (M), then again, from the cache, inside the re-measure
        // loop's (R).
        RenderConstraintLayout.debugRecordTranscripts = true;
        addTearDown(
          () => RenderConstraintLayout.debugRecordTranscripts = false,
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 400,
                maxWidth: 400,
                minHeight: bounded ? 100 : 0,
                maxHeight: bounded ? 100 : double.infinity,
                child: ConstraintLayout(
                  children: [
                    for (final (id, height) in const [
                      (#a, 20.0),
                      (#b, 30.0),
                      (#c, 20.0),
                    ])
                      Constrained(
                        id: id,
                        child: SizedBox(
                          key: ValueKey(id),
                          width: 150,
                          height: height,
                        ),
                      ),
                    const ConstraintFlow(
                      id: #F,
                      referenced: [#a, #b, #c],
                      left: .leftOf(parent),
                      right: .rightOf(parent),
                      top: .topOf(parent),
                      width: .matchConstraint,
                      wrap: FlowWrap.chain,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(rectOf(tester, #a), const Rect.fromLTWH(33, 5, 150, 20));
        expect(rectOf(tester, #b), const Rect.fromLTWH(217, 0, 150, 30));
        expect(rectOf(tester, #c), const Rect.fromLTWH(125, 30, 150, 20));
        final ro = tester.renderObject<RenderConstraintLayout>(
          find.byType(ConstraintLayout),
        );
        expect(ro.size, Size(400, bounded ? 100 : 50));
        final flow = ro.getChildrenAsList().last;
        expect(
          (flow.parentData! as BoxParentData).offset & flow.size,
          const Rect.fromLTWH(0, 0, 400, 50),
        );
        final h = bounded ? 'A100' : 'U0';
        expect(
          ro.debugViewHost!.measurer.transcript.toString(),
          'F:a:0:WW:0,0:A400/$h:150,20,-1,01 '
          'F:b:0:WW:0,0:A400/$h:150,30,-1,01 '
          'F:c:0:WW:0,0:A400/$h:150,20,-1,01 '
          'M:F:0:MW:0,0:A400/$h:300,50,-1,01 '
          'F:a:0:WW:150,20:c:150,20,-1,01 '
          'F:b:0:WW:150,30:c:150,30,-1,01 '
          'F:c:0:WW:150,20:c:150,20,-1,01 '
          'R:F:1:MW:400,50:E400/$h:400,50,-1,00',
        );
      });
    }

    testWidgets('a flow with no referenced widgets is harmless', (
      tester,
    ) async {
      await tester.pumpWidget(
        host([
          const ConstraintFlow(
            id: #flow,
            referenced: [],
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            width: .matchConstraint,
          ),
        ]),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('baseline alignment pulls real baselines from the children', (
      tester,
    ) async {
      // A baseline-aligned flow has to ask each referenced child for its
      // baseline, which is a different measure path from the other aligns.
      await tester.pumpWidget(
        host([
          for (var i = 0; i < 3; i++)
            Constrained(
              id: Symbol('t$i'),
              child: Text(
                'Ag',
                key: ValueKey(Symbol('t$i')),
                style: TextStyle(fontSize: 12.0 + i * 10),
              ),
            ),
          const ConstraintFlow(
            id: #flow,
            referenced: [#t0, #t1, #t2],
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent, margin: 40),
            width: .matchConstraint,
            verticalAlign: .baseline,
            horizontalGap: 8,
          ),
        ]),
      );
      expect(tester.takeException(), isNull);

      // Different font sizes on a shared baseline means different tops.
      final tops = distinct([
        for (final id in const [#t0, #t1, #t2]) rectOf(tester, id).top,
      ]);
      expect(tops.length, greaterThan(1));
    });
  });
}
