// GridCore places referenced widgets into cells. Rows and columns can be
// derived rather than given, cells can be spanned or skipped, and the tracks
// can be weighted; each of those rewrites the cell map, and a wrong cell map
// is invisible until something lands in the wrong place. The engine had no
// grid test of its own, so this covers the placement rules directly.
//
// The "core 1.1.1" groups cover what the released constraintlayout-core
// 1.1.0 and 1.1.1 changed in GridCore after the pinned commit. Their expected
// frames come from that released GridCore itself: the 1.1.1 sources jar from
// Google Maven, compiled and run on the JDK with this file's layout and
// measurer. Those grids have no free cell, so the frames do not depend on how
// many times the layout is solved.

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

/// Each cell's [left, top, width, height].
List<List<int>> frames(List<ConstraintWidget> cells) => [
  for (final c in cells) [c.getLeft(), c.getTop(), c.getWidth(), c.getHeight()],
];

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

    test('an empty grid with a derived track count leaves the rest of the '
        'layout intact', () {
      // No widgets and three columns derive zero rows, so the grid builds no
      // boxes. Adding it to the solver must not abandon the solve (layout()
      // swallows the exception), which used to leave this sibling at 0, 0.
      final g = buildGrid(count: 0, rows: null, columns: 3);
      final title = ConstraintWidget.size(100, 50);
      title.setDebugName('title');
      g.root.add(title);
      title.connect(
        ConstraintAnchorType.left,
        g.root,
        ConstraintAnchorType.left,
      );
      title.connect(
        ConstraintAnchorType.right,
        g.root,
        ConstraintAnchorType.right,
      );
      title.connect(
        ConstraintAnchorType.top,
        g.root,
        ConstraintAnchorType.top,
        20,
      );
      resolve(g.root);
      expect([title.getLeft(), title.getTop()], [150, 20]);
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
      expect(
        g.cells[0].getRight(),
        greaterThanOrEqualTo(g.cells[2].getRight()),
      );
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

    test('span entries past the last widget are ignored', () {
      // Upstream throws from measure() here, which nothing catches.
      final g = buildGrid(count: 1, rows: 2, columns: 2);
      g.grid.setSpans('0:1x2,2:1x1');
      resolve(g.root);
      expect(frames(g.cells), [
        [0, 0, 400, 200],
      ]);
    });

    test('a grid with spans and no widgets resolves to nothing', () {
      final g = buildGrid(count: 0, rows: 2, columns: 2);
      g.grid.setSpans('0:1x2');
      expect(() => resolve(g.root), returnsNormally);
    });

    test('a negative position takes no cell (deliberate divergence)', () {
      // Java's % keeps the sign of a negative position, so its column is
      // -1; upstream then indexes the cell map with it and throws from
      // measure() (ArrayIndexOutOfBoundsException, checked on the JDK with
      // the released GridCore 1.1.1). Here the position is one the grid
      // cannot take, like one past its last cell, so the skip or span stops
      // there; Dart's % used to wrap it onto the last column instead.
      const unskipped = [
        [0, 0, 200, 200],
        [200, 0, 200, 200],
        [0, 200, 200, 200],
        [200, 200, 200, 200],
      ];
      final skipped = buildGrid(count: 4, rows: 2, columns: 2);
      skipped.grid.setSkips('-1:1x1');
      resolve(skipped.root);
      expect(frames(skipped.cells), unskipped);

      final spanned = buildGrid(count: 4, rows: 2, columns: 2);
      spanned.grid.setSpans('-1:1x1');
      resolve(spanned.root);
      expect(frames(spanned.cells), unskipped);
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

    test('a fractional gap is stored as a float and truncated', () {
      // Upstream keeps the gaps as floats and uses (int) gap as the margin.
      // Frames from the released GridCore 1.1.1 on the JDK.
      final g = buildGrid(count: 4, rows: 2, columns: 2);
      g.grid.setHorizontalGaps(15.7);
      g.grid.setVerticalGaps(10.2);
      expect(g.grid.getHorizontalGaps(), 15.699999809265137);
      expect(g.grid.getVerticalGaps(), 10.199999809265137);
      resolve(g.root);
      expect(frames(g.cells), [
        [0, 0, 193, 195],
        [208, 0, 192, 195],
        [0, 205, 193, 195],
        [208, 205, 192, 195],
      ]);
    });

    // Rows of 112 and 28 px. A tile as tall as its row, or taller,
    // over-constrains the weighted chain, and the solver used to settle on a
    // collapsed solution there (tops 35, 88, 35 for 28 px tiles). Expected
    // tops from the released GridCore 1.1.1 on the JDK, with the per-solve
    // placement this port documents.
    for (final (height, tops) in const [
      (20, [46, 116, 46]),
      (28, [42, 112, 42]),
      (40, [36, 106, 36]),
    ]) {
      test('row weights 4,1 hold with $height px tall tiles', () {
        final g = buildGrid(
          count: 3,
          rows: 2,
          columns: 2,
          width: 300,
          height: 140,
        );
        for (final c in g.cells) {
          c.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
          c.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
          c.setWidth(5);
          c.setHeight(height);
        }
        g.grid.setOrientation(GridCore.VERTICAL);
        g.grid.setRowWeights('4,1');
        resolve(g.root);
        expect([for (final c in g.cells) c.getTop()], tops);
      });
    }
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
      // Core 1.1.0 turned the flags from a list into a bitmask.
      final g = buildGrid(count: 4);
      g.grid.setFlags(GridCore.SPANS_RESPECT_WIDGET_ORDER);
      expect(g.grid.getFlags(), GridCore.SPANS_RESPECT_WIDGET_ORDER);
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

  // A layout can solve several times (resolve() alone solves four times
  // here), and laying out the same grid again solves again. Upstream's
  // GridCore arranges the widgets on top of the cells the previous solve
  // took, so in a grid with free cells each solve moved them on; these
  // grids all have free cells. See UPSTREAM.md.
  group('repeated solves', () {
    // 0:1x2 covers cells 0 and 1, cell 4 is skipped, and cells 6 to 8 stay
    // free: the widgets take cells 0-1, 2, 3, and 5.
    const firstPlacement = [
      [0, 0, 200, 100],
      [200, 0, 100, 100],
      [0, 100, 100, 100],
      [200, 100, 100, 100],
    ];

    ({
      ConstraintWidgetContainer root,
      GridCore grid,
      List<ConstraintWidget> cells,
    })
    spannedAndSkipped() {
      final g = buildGrid(
        count: 4,
        rows: 3,
        columns: 3,
        width: 300,
        height: 300,
      );
      g.grid.setSpans('0:1x2');
      g.grid.setSkips('4:1x1');
      return g;
    }

    test('every solve places the widgets where the first one did', () {
      final g = spannedAndSkipped();
      resolve(g.root);
      // Upstream ends with the last three in cells 6 to 8.
      expect(frames(g.cells), firstPlacement);
    });

    test('laying out again keeps the placement', () {
      final g = spannedAndSkipped();
      resolve(g.root);
      resolve(g.root);
      g.root.layout();
      expect(frames(g.cells), firstPlacement);
    });

    test('a resized grid keeps every widget in its cell', () {
      final g = spannedAndSkipped();
      resolve(g.root);
      g.root.setWidth(600);
      resolve(g.root);
      expect(frames(g.cells), [
        [0, 0, 400, 100],
        [400, 0, 200, 100],
        [0, 100, 200, 100],
        [400, 100, 200, 100],
      ]);
    });

    test('SPANS_RESPECT_WIDGET_ORDER spans survive repeated solves', () {
      final g = buildGrid(
        count: 4,
        rows: 3,
        columns: 3,
        width: 300,
        height: 300,
      );
      g.grid.setSpans('2:2x1');
      g.grid.setFlags(GridCore.SPANS_RESPECT_WIDGET_ORDER);
      resolve(g.root);
      resolve(g.root);
      // The third widget reaches cell 2 and covers it and cell 5.
      expect(frames(g.cells), [
        [0, 0, 100, 100],
        [100, 0, 100, 100],
        [200, 0, 100, 200],
        [0, 100, 100, 100],
      ]);
    });
  });

  group('core 1.1.1: flags', () {
    test('the flags are bits of one int', () {
      expect(GridCore.SUB_GRID_BY_COL_ROW, 1);
      expect(GridCore.SPANS_RESPECT_WIDGET_ORDER, 2);
      final g = buildGrid(count: 4);
      expect(g.grid.getFlags(), 0);
      g.grid.setFlags(
        GridCore.SUB_GRID_BY_COL_ROW | GridCore.SPANS_RESPECT_WIDGET_ORDER,
      );
      expect(g.grid.getFlags(), 3);
    });

    test('SUB_GRID_BY_COL_ROW reads a span as columns x rows', () {
      final g = buildGrid(count: 3, rows: 2, columns: 2);
      g.grid.setSpans('0:1x2');
      g.grid.setFlags(GridCore.SUB_GRID_BY_COL_ROW);
      resolve(g.root);
      // The first widget covers 2 rows of 1 column, not 1 row of 2 columns.
      expect(frames(g.cells), [
        [0, 0, 200, 400],
        [200, 0, 200, 200],
        [200, 200, 200, 200],
      ]);
    });

    test('SUB_GRID_BY_COL_ROW reads a skip as columns x rows', () {
      final g = buildGrid(count: 2, rows: 2, columns: 2);
      g.grid.setSkips('0:1x2');
      g.grid.setFlags(GridCore.SUB_GRID_BY_COL_ROW);
      resolve(g.root);
      expect(frames(g.cells), [
        [200, 0, 200, 200],
        [200, 200, 200, 200],
      ]);
    });

    test('setFlags replaces the flags set before', () {
      final g = buildGrid(count: 3, rows: 2, columns: 2);
      g.grid.setSpans('0:1x2');
      g.grid.setFlags(GridCore.SUB_GRID_BY_COL_ROW);
      g.grid.setFlags(0);
      resolve(g.root);
      // Read as rows x columns again: the first widget covers the top row.
      expect(frames(g.cells), [
        [0, 0, 400, 200],
        [0, 200, 200, 200],
        [200, 200, 200, 200],
      ]);
    });

    test(
      'without SPANS_RESPECT_WIDGET_ORDER the first widget takes a span',
      () {
        final g = buildGrid(
          count: 8,
          rows: 3,
          columns: 3,
          width: 300,
          height: 300,
        );
        g.grid.setSpans('2:2x1');
        resolve(g.root);
        expect(frames(g.cells), [
          [200, 0, 100, 200],
          [0, 0, 100, 100],
          [100, 0, 100, 100],
          [0, 100, 100, 100],
          [100, 100, 100, 100],
          [0, 200, 100, 100],
          [100, 200, 100, 100],
          [200, 200, 100, 100],
        ]);
      },
    );

    test('SPANS_RESPECT_WIDGET_ORDER gives a span to the widget that reaches '
        'it', () {
      final g = buildGrid(
        count: 8,
        rows: 3,
        columns: 3,
        width: 300,
        height: 300,
      );
      g.grid.setSpans('2:2x1');
      g.grid.setFlags(GridCore.SPANS_RESPECT_WIDGET_ORDER);
      resolve(g.root);
      // The third widget lands on cell 2 and covers it and the cell below.
      expect(frames(g.cells), [
        [0, 0, 100, 100],
        [100, 0, 100, 100],
        [200, 0, 100, 200],
        [0, 100, 100, 100],
        [100, 100, 100, 100],
        [0, 200, 100, 100],
        [100, 200, 100, 100],
        [200, 200, 100, 100],
      ]);
    });

    test('both flags combine', () {
      final g = buildGrid(
        count: 8,
        rows: 3,
        columns: 3,
        width: 300,
        height: 300,
      );
      // 1x2 read as 2x1, given to the widget that reaches cell 2.
      g.grid.setSpans('2:1x2');
      g.grid.setFlags(
        GridCore.SUB_GRID_BY_COL_ROW | GridCore.SPANS_RESPECT_WIDGET_ORDER,
      );
      resolve(g.root);
      expect(frames(g.cells), [
        [0, 0, 100, 100],
        [100, 0, 100, 100],
        [200, 0, 100, 200],
        [0, 100, 100, 100],
        [100, 100, 100, 100],
        [0, 200, 100, 100],
        [100, 200, 100, 100],
        [200, 200, 100, 100],
      ]);
    });
  });

  group('core 1.1.1: weights', () {
    List<List<int>> columnsWeighted(String weights) {
      final g = buildGrid(count: 3, rows: 1, columns: 3);
      g.grid.setColumnWeights(weights);
      resolve(g.root);
      return frames(g.cells);
    }

    List<List<int>> rowsWeighted(String weights) {
      final g = buildGrid(count: 2, rows: 2, columns: 1);
      g.grid.setRowWeights(weights);
      resolve(g.root);
      return frames(g.cells);
    }

    const twoOneOne = [
      [0, 0, 200, 400],
      [200, 0, 100, 400],
      [300, 0, 100, 400],
    ];

    test('a short list is padded with weights of 1', () {
      // '2' on three columns is '2,1,1'.
      expect(columnsWeighted('2'), twoOneOne);
      expect(columnsWeighted('2,1,1'), twoOneOne);
      // '3' on two rows is '3,1'.
      expect(rowsWeighted('3'), [
        [0, 0, 400, 300],
        [0, 300, 400, 100],
      ]);
    });

    test('a long list is trimmed to the track count', () {
      const oneTwoThree = [
        [0, 0, 67, 400],
        [67, 0, 133, 400],
        [200, 0, 200, 400],
      ];
      expect(columnsWeighted('1,2,3,4'), oneTwoThree);
      expect(columnsWeighted('1,2,3'), oneTwoThree);
      expect(rowsWeighted('1,3,5'), [
        [0, 0, 400, 100],
        [0, 100, 400, 300],
      ]);
    });

    test('an entry that does not parse reads as 1', () {
      expect(columnsWeighted('2,x,1'), twoOneOne);
      expect(columnsWeighted('1,,3'), [
        [0, 0, 80, 400],
        [80, 0, 80, 400],
        [160, 0, 240, 400],
      ]);
    });

    test('whitespace around an entry is ignored', () {
      // ' 2 , 1 ' pads to 2,1,1.
      expect(columnsWeighted(' 2 , 1 '), twoOneOne);
    });

    test('an entry in Java float syntax reads as its value', () {
      // Float.parseFloat takes a type suffix and hexadecimal floats, which a
      // double parse rejected (reading them as 1).
      expect(columnsWeighted('2f,1,1'), twoOneOne);
      expect(columnsWeighted('0x1p1,1,1'), twoOneOne);
      expect(columnsWeighted('2D,1d,1F'), twoOneOne);
      expect(rowsWeighted('3f,1'), [
        [0, 0, 400, 300],
        [0, 300, 400, 100],
      ]);
    });
  });

  group('core 1.1.1: span and skip order', () {
    // 0:2x1 covers cells 0 and 3, 4:1x2 covers cells 4 and 5.
    const sortedSpans = [
      [0, 0, 100, 200],
      [100, 100, 200, 100],
      [100, 0, 100, 100],
      [200, 0, 100, 100],
      [0, 200, 100, 100],
      [100, 200, 100, 100],
      [200, 200, 100, 100],
    ];

    List<List<int>> spanned(String spans, {int flags = 0}) {
      final g = buildGrid(
        count: 7,
        rows: 3,
        columns: 3,
        width: 300,
        height: 300,
      );
      g.grid.setSpans(spans);
      g.grid.setFlags(flags);
      resolve(g.root);
      return frames(g.cells);
    }

    test('spans are sorted by position before the widgets take them', () {
      // Listed out of order, the lower position still goes to the first
      // widget.
      expect(spanned('4:1x2,0:2x1'), sortedSpans);
      expect(spanned('0:2x1,4:1x2'), sortedSpans);
    });

    test('with SPANS_RESPECT_WIDGET_ORDER, out-of-order spans all apply', () {
      // Sorted, the spans are met in the order the widgets reach them.
      expect(
        spanned('4:1x2,0:2x1', flags: GridCore.SPANS_RESPECT_WIDGET_ORDER),
        [
          [0, 0, 100, 200],
          [100, 0, 100, 100],
          [200, 0, 100, 100],
          [100, 100, 200, 100],
          [0, 200, 100, 100],
          [100, 200, 100, 100],
          [200, 200, 100, 100],
        ],
      );
    });

    test('spans at the same position keep their listed order', () {
      final g = buildGrid(count: 3, rows: 2, columns: 2);
      // The first entry wins cell 0; the second then no longer fits.
      g.grid.setSpans('0:1x2,0:1x1');
      resolve(g.root);
      expect(frames(g.cells), [
        [0, 0, 400, 200],
        [0, 200, 200, 200],
        [200, 200, 200, 200],
      ]);
    });

    test('skips are applied in order of position', () {
      final g = buildGrid(
        count: 6,
        rows: 3,
        columns: 3,
        width: 300,
        height: 300,
      );
      // Sorted, 0:1x1 applies first; 1:1x3 then runs off the grid's right
      // edge after taking cells 1 and 2, which stops the skips, so 3:1x1 is
      // never applied. The widgets fill cells 3 to 8.
      g.grid.setSkips('3:1x1,1:1x3,0:1x1');
      resolve(g.root);
      expect(frames(g.cells), [
        [0, 100, 100, 100],
        [100, 100, 100, 100],
        [200, 100, 100, 100],
        [0, 200, 100, 100],
        [100, 200, 100, 100],
        [200, 200, 100, 100],
      ]);
    });

    test('a space after a comma is accepted (deliberate divergence)', () {
      // Upstream's sort comparator parses each position with
      // Integer.parseInt, which rejects the leading space, so released
      // GridCore ignores this whole string. Dart's int.parse ignores the
      // space, as the port's other parses already did. See UPSTREAM.md.
      expect(spanned('4:1x2, 0:2x1'), sortedSpans);
    });
  });

  // Upstream's parsers split their lists with Java's String.split, which drops
  // trailing empty strings. The expected values come from upstream's GridCore
  // and GridEngine (core 1.1.1) run on the JDK with the same input.
  group('list parsing', () {
    test('a trailing comma ends a span or skip list', () {
      final spanned = buildGrid(count: 3, rows: 2, columns: 2);
      spanned.grid.setSpans('0:1x2,');
      resolve(spanned.root);
      expect(frames(spanned.cells), [
        [0, 0, 400, 200],
        [0, 200, 200, 200],
        [200, 200, 200, 200],
      ]);

      final skipped = buildGrid(count: 2, rows: 2, columns: 2);
      skipped.grid.setSkips('0:1x2,');
      resolve(skipped.root);
      expect(frames(skipped.cells), [
        [0, 200, 200, 200],
        [200, 200, 200, 200],
      ]);
    });

    test('a lone comma is an empty list', () {
      final g = buildGrid(count: 4, rows: 2, columns: 2);
      g.grid.setSkips(',');
      resolve(g.root);
      expect(frames(g.cells), [
        [0, 0, 200, 200],
        [200, 0, 200, 200],
        [0, 200, 200, 200],
        [200, 200, 200, 200],
      ]);
    });

    test('GridEngine reads trailing commas the same way', () {
      // GridEngineTest.testSpansSkipsHorizontal, with a comma after each list.
      final engine = GridEngine.sizedWithWidgets(4, 4, 5);
      engine.setSkips('0:2x2,6:1x1,');
      engine.setSpans('12:1x3,');
      engine.setup();
      expect(
        [
          for (var i = 0; i < 5; i++)
            [
              engine.leftOfWidget(i),
              engine.topOfWidget(i),
              engine.rightOfWidget(i),
              engine.bottomOfWidget(i),
            ],
        ],
        [
          [0, 3, 2, 3],
          [2, 0, 2, 0],
          [3, 0, 3, 0],
          [3, 1, 3, 1],
          [0, 2, 0, 2],
        ],
      );

      final comma = GridEngine.sizedWithWidgets(3, 3, 5);
      comma.setSkips(',');
      comma.setup();
      expect(comma.leftOfWidget(0), 0);
    });
  });

  // Upstream's GridCore leaves right-to-left as a TODO; this port mirrors the
  // columns inside the grid's own bounds (see UPSTREAM.md). Each grid here is
  // fixed in size and sits off the container's center, linked by its left and
  // top only, so the grid itself does not move with the direction: only its
  // cells do. The sizes divide evenly, so every edge is a whole pixel.
  group('right-to-left', () {
    ({
      ConstraintWidgetContainer root,
      GridCore grid,
      List<ConstraintWidget> cells,
    })
    placedGrid({
      required bool rtl,
      int count = 6,
      int? rows = 2,
      int? columns = 3,
      int width = 330,
      int height = 240,
      void Function(GridCore grid)? configure,
    }) {
      final root = ConstraintWidgetContainer.rect(0, 0, 400, 300);
      root.setMeasurer(virtualLayoutMeasurer);
      root.setRtl(rtl);
      final grid = GridCore();
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
      grid.setWidth(width);
      grid.setHeight(height);
      grid.connect(
        ConstraintAnchorType.left,
        root,
        ConstraintAnchorType.left,
        40,
      );
      grid.connect(
        ConstraintAnchorType.top,
        root,
        ConstraintAnchorType.top,
        30,
      );
      configure?.call(grid);
      resolve(root);
      return (root: root, grid: grid, cells: cells);
    }

    /// Lays the same grid out in both directions and checks that each cell's
    /// right-to-left frame is the mirror of its left-to-right one within the
    /// grid: x_rtl = gridLeft + gridRight - (x_ltr + width).
    void expectMirrored({
      int count = 6,
      int? rows = 2,
      int? columns = 3,
      int width = 330,
      int height = 240,
      void Function(GridCore grid)? configure,
    }) {
      final ltr = placedGrid(
        rtl: false,
        count: count,
        rows: rows,
        columns: columns,
        width: width,
        height: height,
        configure: configure,
      );
      final rtl = placedGrid(
        rtl: true,
        count: count,
        rows: rows,
        columns: columns,
        width: width,
        height: height,
        configure: configure,
      );
      expect(frames([rtl.grid]), frames([ltr.grid]));
      final gridLeft = rtl.grid.getLeft();
      final gridRight = rtl.grid.getRight();
      final mirrored = [
        for (final f in frames(ltr.cells))
          [gridLeft + gridRight - (f[0] + f[2]), f[1], f[2], f[3]],
      ];
      expect(frames(rtl.cells), mirrored);
      // The left-to-right grid itself is unchanged: a cell moved, not just
      // its frame list.
      expect(frames(ltr.cells), isNot(frames(rtl.cells)));
    }

    test('the first column is the rightmost', () {
      final g = placedGrid(rtl: true, count: 3, rows: 1, columns: 3);
      // Columns of 110 between x = 40 and x = 370, filled from the right.
      expect(frames(g.cells), [
        [260, 30, 110, 240],
        [150, 30, 110, 240],
        [40, 30, 110, 240],
      ]);
    });

    test('a plain grid mirrors within its bounds', () {
      expectMirrored();
    });

    test('spans and skips keep their positions, counted from the start', () {
      expectMirrored(
        count: 5,
        rows: 3,
        columns: 3,
        configure: (grid) {
          grid.setSpans('0:1x2');
          grid.setSkips('5:1x1');
        },
      );
      final g = placedGrid(
        rtl: true,
        count: 5,
        rows: 3,
        columns: 3,
        configure: (grid) {
          grid.setSpans('0:1x2');
          grid.setSkips('5:1x1');
        },
      );
      // Cells 0 and 1 are the two rightmost cells of the first row.
      expect(frames(g.cells).first, [150, 30, 220, 80]);
    });

    test('column weights count from the first column', () {
      expectMirrored(configure: (grid) => grid.setColumnWeights('3,1,1'));
      final g = placedGrid(
        rtl: true,
        configure: (grid) => grid.setColumnWeights('3,1,1'),
      );
      // The first column, three fifths of 330, is the rightmost.
      expect(frames(g.cells).first, [172, 30, 198, 120]);
    });

    test('gaps mirror with the columns', () {
      expectMirrored(
        configure: (grid) {
          grid.setHorizontalGaps(15);
          grid.setVerticalGaps(10);
        },
      );
    });

    test('a vertical grid mirrors its columns', () {
      expectMirrored(
        count: 4,
        rows: 3,
        columns: 2,
        configure: (grid) {
          grid.setOrientation(GridCore.VERTICAL);
          // Column by column: cells 0 and 1 are the first column's top two.
          grid.setSpans('0:2x1');
          grid.setSkips('3:1x1');
          grid.setColumnWeights('2,1');
        },
      );
    });

    test('a one-row grid mirrors the columns an index:N span adds', () {
      // '0:2' on three columns adds one: four columns of 80.
      expectMirrored(
        count: 3,
        rows: 1,
        columns: 3,
        width: 320,
        configure: (grid) => grid.setSpans('0:2'),
      );
    });

    test('a widget linked to a grid member follows it', () {
      ({ConstraintWidget badge, ConstraintWidget member}) badged(bool rtl) {
        final g = placedGrid(rtl: rtl, configure: (_) {});
        final member = g.cells.first;
        final badge = ConstraintWidget.size(20, 10);
        badge.setDebugName('badge');
        g.root.add(badge);
        // Centered under the first cell.
        badge.connect(
          ConstraintAnchorType.left,
          member,
          ConstraintAnchorType.left,
        );
        badge.connect(
          ConstraintAnchorType.right,
          member,
          ConstraintAnchorType.right,
        );
        badge.connect(
          ConstraintAnchorType.top,
          member,
          ConstraintAnchorType.bottom,
          4,
        );
        resolve(g.root);
        return (badge: badge, member: member);
      }

      final ltr = badged(false);
      final rtl = badged(true);
      expect([ltr.badge.getLeft(), ltr.badge.getTop()], [85, 154]);
      // The first cell is the rightmost, and the badge moved with it.
      expect([rtl.member.getLeft(), rtl.member.getWidth()], [260, 110]);
      expect([rtl.badge.getLeft(), rtl.badge.getTop()], [305, 154]);
    });

    test('changing the direction of a laid-out grid mirrors it', () {
      final g = placedGrid(
        rtl: false,
        count: 5,
        rows: 3,
        columns: 3,
        configure: (grid) => grid.setSpans('0:1x2'),
      );
      final ltr = frames(g.cells);
      g.root.setRtl(true);
      resolve(g.root);
      expect(frames(g.cells), isNot(ltr));
      final expected = placedGrid(
        rtl: true,
        count: 5,
        rows: 3,
        columns: 3,
        configure: (grid) => grid.setSpans('0:1x2'),
      );
      expect(frames(g.cells), frames(expected.cells));
      g.root.setRtl(false);
      resolve(g.root);
      expect(frames(g.cells), ltr);
    });

    test('a column boundary on a half pixel is within 1 px of the mirror', () {
      // Two columns across 331 px meet at x = 40 + 165.5. The engine works in
      // whole pixels and rounds that boundary up in both directions, so the
      // right-to-left first column is 165 px wide where the left-to-right
      // one is 166, as with any other mirrored layout.
      final ltr = placedGrid(
        rtl: false,
        count: 2,
        rows: 1,
        columns: 2,
        width: 331,
      );
      final rtl = placedGrid(
        rtl: true,
        count: 2,
        rows: 1,
        columns: 2,
        width: 331,
      );
      expect(frames(ltr.cells), [
        [40, 30, 166, 240],
        [206, 30, 165, 240],
      ]);
      expect(frames(rtl.cells), [
        [206, 30, 165, 240],
        [40, 30, 166, 240],
      ]);
      // The exact mirror of the first cell would start at 40 + 371 - 206.
      final mirrorLeft =
          rtl.grid.getLeft() + rtl.grid.getRight() - ltr.cells[0].getRight();
      expect(mirrorLeft, 205);
      expect((rtl.cells[0].getLeft() - mirrorLeft).abs(), lessThanOrEqualTo(1));
    });
  });
}
