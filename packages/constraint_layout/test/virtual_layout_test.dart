// Adapter-level behaviour of the two virtual layouts.
//
// The visual results are pinned by the goldens; what this covers is the part
// the goldens cannot show, notably `ConstraintGrid`'s documented promise that
// `rows` or `columns` may be omitted and derived from the other plus the
// widget count. Deriving needs the widget count, which the host only knows
// after it has added the referenced widgets, so this used to resolve to a zero
// track count and take the layout down with a null-check error.

import 'package:constraint_layout/constraint_layout.dart';
import 'package:flutter/material.dart';
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
  });

  group('flow', () {
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
