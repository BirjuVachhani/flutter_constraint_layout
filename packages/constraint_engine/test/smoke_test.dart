import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/echo_measurer.dart';
import 'support/op_replay.dart';

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

  // A spread width between two anchors 200 apart, with a min of 300 and a
  // max of 400: the min wins on Android's solver path, overflowing the
  // anchors evenly. Upstream's Java engine gives w=300 at x=250 with its
  // solver alone (OPTIMIZATION_NONE) and at x=251 at OPTIMIZATION_STANDARD,
  // its default, whose Direct pass places the widget and truncates its
  // -49.5 px offset towards zero. At the dependency-graph levels the graph
  // lays it out: WidgetRun.getLimitedDimension drops the min when a max is
  // set, so the width resolves to the 200 between the anchors at x=300, and
  // the measurer (which keeps a size within its match-constraint bounds)
  // reports 300.
  test(
    'a spread min above the space between the anchors wins over its max',
    () {
      // Java J0: A: (250, 0) 300 x 40; J257: A: (251, 0) 300 x 40, Direct
      // (VOpDriver core: R 800 600;w A 0 40;add A;hb A M;hm A 0 300 400 1.0;
      // c A L root L 300;c A R root R 300;c A T root T 0).
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.setMeasurer(const EchoMeasurer());
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

      root.measure(
        Optimizer.OPTIMIZATION_NONE,
        BasicMeasure.EXACTLY,
        800,
        BasicMeasure.EXACTLY,
        600,
        0,
        0,
        0,
        0,
      );

      expect(
        [a.getLeft(), a.getTop(), a.getWidth(), a.getHeight()],
        [250, 0, 300, 40],
      );
    },
  );

  test(
    'a spread min above the space between the anchors, at Android\'s '
    'default and at the dependency-graph levels',
    () {
      // Java (VOpDriver v2, core path).
      const ops =
          'R 800 600;w A 0 40;add A;hb A M;hm A 0 300 400 1.0;'
          'c A L root L 300;c A R root R 300;c A T root T 0';
      expect(
        replayCore(ops).geometry,
        'root 800 x 600 | A: (251, 0) 300 x 40',
        reason: 'Java J257',
      );
      for (final level in const [64, 321, 192, 449]) {
        expect(
          replayCore(ops, level: level).geometry,
          'root 800 x 600 | A: (300, 0) 300 x 40',
          reason: 'Java J$level',
        );
      }
    },
  );
}
