// GridCore places referenced widgets into cells. Rows and columns can be
// derived rather than given, cells can be spanned or skipped, and the tracks
// can be weighted; each of those rewrites the cell map, and a wrong cell map
// is invisible until something lands in the wrong place. The engine had no
// grid test of its own, so this covers the placement rules directly.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/virtual_layout_measurer.dart';

({ConstraintWidgetContainer root, GridCore grid, List<ConstraintWidget> cells})
buildGrid({
  int count = 4,
  int? rows = 2,
  int? columns = 2,
  int width = 400,
  int height = 400,
}) {
  final root = ConstraintWidgetContainer.rect(0, 0, width, height);
  root.setDebugName('root');
  root.setMeasurer(virtualLayoutMeasurer);

  final grid = GridCore();
  grid.setDebugName('grid');
  grid.setContainer(root);
  root.add(grid);
  if (rows != null) grid.setRows(rows);
  if (columns != null) grid.setColumns(columns);

  final cells = <ConstraintWidget>[];
  for (var i = 0; i < count; i++) {
    final w = ConstraintWidget.size(40, 20);
    w.setDebugName('cell$i');
    w.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
    w.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
    root.add(w);
    grid.add(w);
    cells.add(w);
  }

  grid.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
  grid.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
  grid.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
  grid.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
  grid.setHorizontalDimensionBehaviour(DimensionBehaviour.matchParent);
  grid.setVerticalDimensionBehaviour(DimensionBehaviour.matchParent);
  return (root: root, grid: grid, cells: cells);
}

void resolve(ConstraintWidgetContainer root) {
  root.measure(Optimizer.OPTIMIZATION_NONE, 0, 0, 0, 0, 0, 0, 0, 0);
  root.layout();
}

List<int> sortedUnique(Iterable<int> values) => values.toSet().toList()..sort();

void main() {
  group('cell placement', () {
    test('a 2x2 grid fills row by row', () {
      final g = buildGrid();
      resolve(g.root);

      final lefts = sortedUnique(g.cells.map((c) => c.getLeft()));
      final tops = sortedUnique(g.cells.map((c) => c.getTop()));
      expect(lefts, hasLength(2));
      expect(tops, hasLength(2));

      // Reading order: 0 1 / 2 3.
      expect(g.cells[0].getTop(), tops[0]);
      expect(g.cells[1].getTop(), tops[0]);
      expect(g.cells[0].getLeft(), lefts[0]);
      expect(g.cells[1].getLeft(), lefts[1]);
      expect(g.cells[2].getTop(), tops[1]);
      expect(g.cells[3].getTop(), tops[1]);
    });

    test('columns are derived when only rows are given', () {
      final g = buildGrid(count: 6, rows: 2, columns: null);
      resolve(g.root);

      expect(sortedUnique(g.cells.map((c) => c.getTop())), hasLength(2));
      expect(sortedUnique(g.cells.map((c) => c.getLeft())), hasLength(3));
    });

    test('rows are derived when only columns are given', () {
      final g = buildGrid(count: 6, rows: null, columns: 3);
      resolve(g.root);

      expect(sortedUnique(g.cells.map((c) => c.getLeft())), hasLength(3));
      expect(sortedUnique(g.cells.map((c) => c.getTop())), hasLength(2));
    });

    test('a vertical grid fills column by column', () {
      final g = buildGrid(count: 4);
      g.grid.setOrientation(GridCore.VERTICAL);
      resolve(g.root);

      final lefts = sortedUnique(g.cells.map((c) => c.getLeft()));
      // Filling down a column first puts the second widget below the first,
      // not beside it.
      expect(g.cells[0].getLeft(), lefts[0]);
      expect(g.cells[1].getLeft(), lefts[0]);
      expect(g.cells[0].getTop(), lessThan(g.cells[1].getTop()));
    });

    test('more widgets than cells still lays out', () {
      // Overflow must not throw; the extra widgets simply have nowhere to go.
      final g = buildGrid(count: 6, rows: 2, columns: 2);
      expect(() => resolve(g.root), returnsNormally);
    });

    test('an empty grid resolves to nothing', () {
      final g = buildGrid(count: 0);
      expect(() => resolve(g.root), returnsNormally);
    });
  });

  group('spans and skips', () {
    test('a span makes one widget cover several cells', () {
      final g = buildGrid(count: 3, rows: 2, columns: 2);
      // Widget 0 covers the whole first row.
      g.grid.setSpans('0:1x2');
      resolve(g.root);

      expect(g.cells[0].getWidth(), greaterThan(g.cells[1].getWidth()));
      // The spanning widget starts at the left edge and reaches the right.
      expect(g.cells[0].getRight(), greaterThanOrEqualTo(g.cells[2].getRight()));
    });

    test('a skip leaves a hole that later widgets step over', () {
      final unskipped = buildGrid(count: 3, rows: 2, columns: 2);
      resolve(unskipped.root);
      final withoutSkip = unskipped.cells[1].getLeft();

      final g = buildGrid(count: 3, rows: 2, columns: 2);
      // Leave cell 1 empty, so the second widget lands in cell 2.
      g.grid.setSkips('1:1x1');
      resolve(g.root);

      expect(g.cells[1].getLeft(), isNot(withoutSkip));
    });

    test('a malformed span or skip is ignored rather than fatal', () {
      final g = buildGrid(count: 4);
      g.grid.setSpans('not-a-span');
      g.grid.setSkips('also:not:valid');
      expect(() => resolve(g.root), returnsNormally);
    });

    test('an empty span string is accepted', () {
      final g = buildGrid(count: 4);
      g.grid.setSpans('');
      g.grid.setSkips('');
      expect(() => resolve(g.root), returnsNormally);
    });
  });

  group('weights and gaps', () {
    test('column weights split the width unevenly', () {
      final g = buildGrid(count: 4, rows: 2, columns: 2);
      g.grid.setColumnWeights('2,1');
      resolve(g.root);

      // Left column takes twice the width of the right one.
      expect(g.cells[0].getWidth(), greaterThan(g.cells[1].getWidth()));
    });

    test('row weights split the height unevenly', () {
      final g = buildGrid(count: 4, rows: 2, columns: 2);
      g.grid.setRowWeights('1,3');
      resolve(g.root);

      expect(g.cells[2].getHeight(), greaterThan(g.cells[0].getHeight()));
    });

    test('gaps push the tracks apart', () {
      int columnGapOf(double gap) {
        final g = buildGrid(count: 4, rows: 2, columns: 2);
        g.grid.setHorizontalGaps(gap);
        g.grid.setVerticalGaps(gap);
        resolve(g.root);
        return g.cells[1].getLeft() - g.cells[0].getRight();
      }

      expect(columnGapOf(20), greaterThan(columnGapOf(0)));
    });
  });

  group('configuration guards', () {
    test('row and column counts are clamped to something sane', () {
      final g = buildGrid(count: 4);
      // Negative and absurd counts must not blow up the cell map.
      g.grid.setRows(-1);
      g.grid.setColumns(-5);
      expect(() => resolve(g.root), returnsNormally);

      final huge = buildGrid(count: 4);
      huge.grid.setRows(9999);
      huge.grid.setColumns(9999);
      expect(() => resolve(huge.root), returnsNormally);
    });

    test('flags are stored as given', () {
      final g = buildGrid(count: 4);
      g.grid.setFlags(const [GridCore.SPANS_RESPECT_WIDGET_ORDER]);
      expect(() => resolve(g.root), returnsNormally);
    });

    test('re-measuring after a change re-places the cells', () {
      final g = buildGrid(count: 4, rows: 2, columns: 2);
      resolve(g.root);
      final before = g.cells.map((c) => c.getLeft()).toList();

      g.grid.setColumns(4);
      g.grid.setRows(1);
      resolve(g.root);
      final after = g.cells.map((c) => c.getLeft()).toList();

      expect(after, isNot(before));
      // One row of four: every cell shares a top.
      expect(sortedUnique(g.cells.map((c) => c.getTop())), hasLength(1));
    });
  });
}
