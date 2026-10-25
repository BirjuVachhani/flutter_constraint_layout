import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  test('pinned top-left', () {
    final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
    final a = ConstraintWidget.size(100, 30);
    root.setDebugName('root');
    a.setDebugName('A');
    root.add(a);
    a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
    a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
    root.layout();
    expect(a.getLeft(), 0);
    expect(a.getTop(), 0);
    expect(a.getWidth(), 100);
    expect(a.getHeight(), 30);
  });

  test('centered horizontally', () {
    final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
    final a = ConstraintWidget.size(100, 30);
    root.setDebugName('root');
    a.setDebugName('A');
    root.add(a);
    a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
    a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
    a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
    root.layout();
    expect(a.getLeft(), 250);
    expect(a.getWidth(), 100);
  });

  test('margin + below', () {
    final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
    final a = ConstraintWidget.size(100, 30);
    final b = ConstraintWidget.size(100, 30);
    root.setDebugName('root');
    a.setDebugName('A');
    b.setDebugName('B');
    root.add(a);
    root.add(b);
    a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 20);
    a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 16);
    b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left);
    b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 8);
    root.layout();
    expect(a.getLeft(), 20);
    expect(a.getTop(), 16);
    expect(b.getLeft(), 20);
    expect(b.getTop(), 54);
  });

  test('right-to-left chains with margins', () {
    // A horizontal spread-inside chain with 24-px outer margins, and a
    // vertical one with 40-px outer margins, in a right-to-left container.
    final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
    root.setRtl(true);
    final h = [for (var i = 0; i < 3; i++) ConstraintWidget.size(24, 24)];
    final v = [for (var i = 0; i < 3; i++) ConstraintWidget.size(50, 50)];
    root.addAll([...h, ...v]);
    h[0].connect(
      ConstraintAnchorType.left,
      root,
      ConstraintAnchorType.left,
      24,
    );
    v[0].connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 40);
    for (var i = 0; i < 2; i++) {
      h[i].connect(
        ConstraintAnchorType.right,
        h[i + 1],
        ConstraintAnchorType.left,
      );
      h[i + 1].connect(
        ConstraintAnchorType.left,
        h[i],
        ConstraintAnchorType.right,
      );
      v[i].connect(
        ConstraintAnchorType.bottom,
        v[i + 1],
        ConstraintAnchorType.top,
      );
      v[i + 1].connect(
        ConstraintAnchorType.top,
        v[i],
        ConstraintAnchorType.bottom,
      );
    }
    h[2].connect(
      ConstraintAnchorType.right,
      root,
      ConstraintAnchorType.right,
      24,
    );
    v[2].connect(
      ConstraintAnchorType.bottom,
      root,
      ConstraintAnchorType.bottom,
      40,
    );
    // The right-to-left head of a horizontal chain is its rightmost widget.
    h[2].setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
    v[0].setVerticalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
    for (final w in h) {
      w.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
    }
    for (final w in v) {
      w.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
    }
    root.layout();
    expect([for (final w in h) w.getLeft()], [24, 388, 752]);
    expect([for (final w in v) w.getTop()], [40, 275, 510]);
  });

  // A spread width between two anchors 200 apart, with a min of 300 and a max
  // of 400: the min wins, overflowing the anchors evenly. Upstream's
  // WidgetRun.getLimitedDimension drops the min whenever a max is set, so its
  // graph resolved the width to the 200 between the anchors (see
  // UPSTREAM.md). Android keeps the min: upstream's Java engine gives w=300,
  // at x=250 with its solver alone (OPTIMIZATION_NONE), as this engine does
  // on both paths, and at x=251 at OPTIMIZATION_STANDARD, its default, whose
  // Direct pass places the widget and truncates its -49.5 px offset towards
  // zero.
  for (final solver in [false, true]) {
    test('a spread min above the space between the anchors wins over its max '
        '(${solver ? 'solver' : 'graph'})', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget()..setDebugName('A');
      root.add(a);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalMatchStyle(
        ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
        300,
        400,
        1,
      );
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setHeight(40);
      a.connect(
        ConstraintAnchorType.left,
        root,
        ConstraintAnchorType.left,
        300,
      );
      a.connect(
        ConstraintAnchorType.right,
        root,
        ConstraintAnchorType.right,
        300,
      );
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      if (solver) {
        // An unrelated circular constraint routes the layout through
        // the solver fallback. (A barrier no longer does: the graph
        // resolves barriers that sit on their widgets' outermost edge.)
        final g = ConstraintWidget.size(10, 10)..setDebugName('g');
        root.add(g);
        g.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
        g.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
        final h = ConstraintWidget.size(10, 10)..setDebugName('h');
        root.add(h);
        h.connectCircularConstraint(g, 90, 20);
      }

      root.layout();

      // The solver creates variables; a graph-resolved layout never reaches
      // it. (Its row count is no probe: a pass whose equations all resolve
      // directly ends with no rows.)
      expect(root.mSystem.getNumVariables() > 0, solver);
      expect([a.getLeft(), a.getWidth()], [250, 300]);
    });
  }
}
