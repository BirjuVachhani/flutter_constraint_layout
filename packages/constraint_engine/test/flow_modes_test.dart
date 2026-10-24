// Flow arranges referenced widgets into chains and wraps them. Each wrap mode
// is a separate measuring algorithm, and each is further split by orientation,
// cross-axis alignment, chain style, and bias. The existing flow_test covers
// the common horizontal chain; this walks the rest of the matrix, because a
// mode that is never measured is a mode that can silently stop working.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/virtual_layout_measurer.dart';

/// A root sized [width] x [height] with a flow already added to it.
({ConstraintWidgetContainer root, Flow flow, List<ConstraintWidget> items})
buildFlow({
  int count = 6,
  int width = 400,
  int height = 400,
  int itemWidth = 60,
  int itemHeight = 30,
  List<int>? itemHeights,
}) {
  final root = ConstraintWidgetContainer.rect(0, 0, width, height);
  root.setDebugName('root');
  root.setMeasurer(virtualLayoutMeasurer);

  final flow = Flow();
  flow.setDebugName('flow');
  root.add(flow);

  final items = <ConstraintWidget>[];
  for (var i = 0; i < count; i++) {
    final w = ConstraintWidget.size(
      itemWidth,
      itemHeights == null ? itemHeight : itemHeights[i % itemHeights.length],
    );
    w.setDebugName('item$i');
    root.add(w);
    flow.add(w);
    items.add(w);
  }
  return (root: root, flow: flow, items: items);
}

/// Anchors [flow] to every edge of [root] so it has a definite span.
void fillParent(ConstraintWidgetContainer root, Flow flow) {
  flow.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
  flow.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
  flow.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
  flow.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
}

/// Gives the flow the parent's span on its main axis and lets it wrap on the
/// cross axis. A flow only knows where to break a row once something has told
/// it how wide it is, and matchParent is what the measurer resolves against
/// the container.
void spanParent(Flow flow, {bool vertical = false}) {
  flow.setHorizontalDimensionBehaviour(
    vertical ? DimensionBehaviour.wrapContent : DimensionBehaviour.matchParent,
  );
  flow.setVerticalDimensionBehaviour(
    vertical ? DimensionBehaviour.matchParent : DimensionBehaviour.wrapContent,
  );
}

/// Measures then lays out, the two-step the virtual layouts need: the wrap
/// decisions happen during measure, and layout only places what it decided.
void resolve(ConstraintWidgetContainer root) {
  root.measure(Optimizer.OPTIMIZATION_NONE, 0, 0, 0, 0, 0, 0, 0, 0);
  root.layout();
}

/// The distinct left edges of [items], in ascending order: the column pattern.
List<int> columnsOf(List<ConstraintWidget> items) =>
    items.map((w) => w.getLeft()).toSet().toList()..sort();

/// The distinct top edges of [items], in ascending order: the row pattern.
List<int> rowsOf(List<ConstraintWidget> items) =>
    items.map((w) => w.getTop()).toSet().toList()..sort();

void main() {
  group('wrap modes', () {
    test('WRAP_NONE keeps one chain even when it overflows', () {
      final f = buildFlow(count: 8, width: 300);
      f.flow.setWrapMode(Flow.WRAP_NONE);
      spanParent(f.flow);
      fillParent(f.root, f.flow);
      resolve(f.root);

      // Eight 60px items in 300px: one row, so every top matches.
      expect(rowsOf(f.items), hasLength(1));
    });

    test('WRAP_CHAIN breaks into as many rows as it needs', () {
      final f = buildFlow(count: 8, width: 300);
      f.flow.setWrapMode(Flow.WRAP_CHAIN);
      spanParent(f.flow);
      fillParent(f.root, f.flow);
      resolve(f.root);

      expect(rowsOf(f.items).length, greaterThan(1));
    });

    test('WRAP_ALIGNED lines the rows up into a grid', () {
      final f = buildFlow(count: 8, width: 300);
      f.flow.setWrapMode(Flow.WRAP_ALIGNED);
      spanParent(f.flow);
      fillParent(f.root, f.flow);
      resolve(f.root);

      final rows = rowsOf(f.items);
      final columns = columnsOf(f.items);
      expect(rows.length, greaterThan(1));
      // Aligned means every row reuses the same column positions, so the
      // number of distinct lefts equals the widest row, not the item count.
      expect(columns.length, lessThan(f.items.length));
    });

    test('WRAP_CHAIN_NEW also wraps', () {
      final f = buildFlow(count: 8, width: 300);
      f.flow.setWrapMode(Flow.WRAP_CHAIN_NEW);
      spanParent(f.flow);
      fillParent(f.root, f.flow);
      resolve(f.root);

      expect(rowsOf(f.items).length, greaterThan(1));
    });

    test('maxElementsWrap caps a row before the space runs out', () {
      final f = buildFlow(count: 6, width: 400);
      f.flow.setWrapMode(Flow.WRAP_CHAIN);
      f.flow.setMaxElementsWrap(2);
      spanParent(f.flow);
      fillParent(f.root, f.flow);
      resolve(f.root);

      expect(f.flow.getMaxElementsWrap(), 2);
      // Six items, two per row: three rows, even though six would fit across.
      expect(rowsOf(f.items), hasLength(3));
    });
  });

  group('orientation', () {
    test('a vertical flow stacks into a column and wraps sideways', () {
      final f = buildFlow(count: 8, width: 400, height: 200);
      f.flow.setOrientation(ConstraintWidget.VERTICAL);
      f.flow.setWrapMode(Flow.WRAP_CHAIN);
      spanParent(f.flow, vertical: true);
      fillParent(f.root, f.flow);
      resolve(f.root);

      // Eight 30px items in 200px of height: more than one column.
      expect(columnsOf(f.items).length, greaterThan(1));
    });

    test('a vertical aligned flow builds columns of equal rows', () {
      final f = buildFlow(count: 6, width: 400, height: 130);
      f.flow.setOrientation(ConstraintWidget.VERTICAL);
      f.flow.setWrapMode(Flow.WRAP_ALIGNED);
      spanParent(f.flow, vertical: true);
      fillParent(f.root, f.flow);
      resolve(f.root);

      expect(columnsOf(f.items).length, greaterThan(1));
    });
  });

  group('cross-axis alignment', () {
    /// Lays out a ragged single row and returns the item tops.
    List<int> topsForVerticalAlign(int align) {
      final f = buildFlow(count: 3, width: 400, itemHeights: const [20, 60, 40]);
      f.flow.setWrapMode(Flow.WRAP_NONE);
      f.flow.setVerticalAlign(align);
      spanParent(f.flow);
      fillParent(f.root, f.flow);
      resolve(f.root);
      return f.items.map((w) => w.getTop()).toList();
    }

    test('top alignment puts every item on the same top edge', () {
      final tops = topsForVerticalAlign(Flow.VERTICAL_ALIGN_TOP);
      expect(tops.toSet(), hasLength(1));
    });

    test('bottom alignment puts every item on the same bottom edge', () {
      final f = buildFlow(count: 3, width: 400, itemHeights: const [20, 60, 40]);
      f.flow.setWrapMode(Flow.WRAP_NONE);
      f.flow.setVerticalAlign(Flow.VERTICAL_ALIGN_BOTTOM);
      spanParent(f.flow);
      fillParent(f.root, f.flow);
      resolve(f.root);

      expect(f.items.map((w) => w.getBottom()).toSet(), hasLength(1));
    });

    test('center alignment staggers the tops of a ragged row', () {
      final tops = topsForVerticalAlign(Flow.VERTICAL_ALIGN_CENTER);
      // Three different heights centred on one line means three tops.
      expect(tops.toSet().length, greaterThan(1));
    });

    test('horizontal alignment applies to the columns of a vertical flow', () {
      List<int> leftsFor(int align) {
        final root = ConstraintWidgetContainer.rect(0, 0, 400, 400);
        root.setMeasurer(virtualLayoutMeasurer);
        final flow = Flow();
        root.add(flow);
        for (final width in const [30, 90, 60]) {
          final w = ConstraintWidget.size(width, 30);
          root.add(w);
          flow.add(w);
        }
        flow.setOrientation(ConstraintWidget.VERTICAL);
        flow.setWrapMode(Flow.WRAP_NONE);
        flow.setHorizontalAlign(align);
        spanParent(flow, vertical: true);
        fillParent(root, flow);
        resolve(root);
        return [
          for (final w in [flow.mWidgets[0]!, flow.mWidgets[1]!, flow.mWidgets[2]!])
            w.getLeft(),
        ];
      }

      expect(leftsFor(Flow.HORIZONTAL_ALIGN_START).toSet(), hasLength(1));
      // End-aligned columns share a right edge instead, so the lefts differ.
      expect(leftsFor(Flow.HORIZONTAL_ALIGN_END).toSet().length, greaterThan(1));
      expect(leftsFor(Flow.HORIZONTAL_ALIGN_CENTER).toSet().length,
          greaterThan(1));
    });
  });

  group('chain styles and bias', () {
    test('a packed chain honours the bias along the main axis', () {
      int firstLeftForBias(double bias) {
        final f = buildFlow(count: 3, width: 400);
        f.flow.setWrapMode(Flow.WRAP_NONE);
        f.flow.setHorizontalStyle(ConstraintWidget.CHAIN_PACKED);
        f.flow.setHorizontalBias(bias);
        spanParent(f.flow);
        fillParent(f.root, f.flow);
        resolve(f.root);
        return f.items.first.getLeft();
      }

      final left = firstLeftForBias(0);
      final middle = firstLeftForBias(0.5);
      final right = firstLeftForBias(1);
      expect(left, lessThan(middle));
      expect(middle, lessThan(right));
    });

    test('spread and packed distribute a row differently', () {
      int gapForStyle(int style) {
        final f = buildFlow(count: 3, width: 400);
        f.flow.setWrapMode(Flow.WRAP_NONE);
        f.flow.setHorizontalStyle(style);
        spanParent(f.flow);
        fillParent(f.root, f.flow);
        resolve(f.root);
        return f.items[1].getLeft() - f.items[0].getRight();
      }

      expect(
        gapForStyle(ConstraintWidget.CHAIN_SPREAD),
        greaterThan(gapForStyle(ConstraintWidget.CHAIN_PACKED)),
      );
      expect(
        gapForStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE),
        greaterThan(gapForStyle(ConstraintWidget.CHAIN_PACKED)),
      );
    });

    test('first and last styles override the run they head', () {
      final f = buildFlow(count: 6, width: 300);
      f.flow.setWrapMode(Flow.WRAP_CHAIN);
      f.flow.setHorizontalStyle(ConstraintWidget.CHAIN_SPREAD);
      f.flow.setFirstHorizontalStyle(ConstraintWidget.CHAIN_PACKED);
      f.flow.setLastHorizontalStyle(ConstraintWidget.CHAIN_PACKED);
      f.flow.setFirstHorizontalBias(0);
      f.flow.setLastHorizontalBias(1);
      f.flow.setFirstVerticalStyle(ConstraintWidget.CHAIN_PACKED);
      f.flow.setLastVerticalStyle(ConstraintWidget.CHAIN_PACKED);
      f.flow.setFirstVerticalBias(0);
      f.flow.setLastVerticalBias(1);
      spanParent(f.flow);
      fillParent(f.root, f.flow);

      // The point is that the override path runs and produces a stable layout.
      expect(() => resolve(f.root), returnsNormally);
      expect(rowsOf(f.items).length, greaterThan(1));
    });
  });

  group('gaps, padding, and empty cases', () {
    test('gaps push the items apart on both axes', () {
      final f = buildFlow(count: 6, width: 300);
      f.flow.setWrapMode(Flow.WRAP_CHAIN);
      f.flow.setHorizontalGap(20);
      f.flow.setVerticalGap(15);
      f.flow.setHorizontalStyle(ConstraintWidget.CHAIN_PACKED);
      spanParent(f.flow);
      fillParent(f.root, f.flow);
      resolve(f.root);

      final rows = rowsOf(f.items);
      expect(rows.length, greaterThan(1));
      // Row pitch is the tallest item plus the vertical gap.
      expect(rows[1] - rows[0], 30 + 15);
    });

    test('padding grows the measured flow and narrows the wrap width', () {
      int heightWithPadding(int padding) {
        final f = buildFlow(count: 6, width: 300);
        f.flow.setWrapMode(Flow.WRAP_CHAIN);
        f.flow.setPadding(padding);
        spanParent(f.flow);
        fillParent(f.root, f.flow);
        resolve(f.root);
        return f.flow.getHeight();
      }

      // Padding is added back onto the measured content on both axes, so a
      // wrap-content flow reports the taller box.
      expect(heightWithPadding(25), heightWithPadding(0) + 50);

      // Vertical padding is stored as given. The horizontal sides are
      // start/end aware, so they only settle once a direction is applied,
      // which is what makes a padded flow mirror in RTL.
      final flow = Flow()..setPadding(20);
      expect(flow.getPaddingTop(), 20);
      expect(flow.getPaddingBottom(), 20);

      final asymmetric = Flow()
        ..setPaddingStart(30)
        ..setPaddingEnd(10);
      asymmetric.applyRtl(false);
      expect(asymmetric.getPaddingLeft(), 30);
      expect(asymmetric.getPaddingRight(), 10);

      asymmetric.applyRtl(true);
      expect(asymmetric.getPaddingLeft(), 10);
      expect(asymmetric.getPaddingRight(), 30);
    });

    test('a flow with no widgets collapses to nothing', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 400, 400);
      root.setMeasurer(virtualLayoutMeasurer);
      final flow = Flow();
      flow.setDebugName('flow');
      root.add(flow);
      flow.setWrapMode(Flow.WRAP_CHAIN);
      flow.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      flow.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      fillParent(root, flow);

      expect(() => resolve(root), returnsNormally);
      expect(flow.getWidth(), 0);
      expect(flow.getHeight(), 0);
    });

    test('gone widgets are skipped, not spaced around', () {
      final f = buildFlow(count: 4, width: 400);
      f.flow.setWrapMode(Flow.WRAP_NONE);
      f.flow.setHorizontalStyle(ConstraintWidget.CHAIN_PACKED);
      spanParent(f.flow);
      fillParent(f.root, f.flow);
      resolve(f.root);
      final packedWidth = f.items.last.getRight() - f.items.first.getLeft();

      f.items[1].setVisibility(ConstraintWidget.GONE);
      resolve(f.root);
      final withGone = f.items.last.getRight() - f.items[0].getLeft();

      // One fewer item in the run, so the packed group is narrower.
      expect(withGone, lessThan(packedWidth));
    });
  });
}
