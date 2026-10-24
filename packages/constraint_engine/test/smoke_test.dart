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
}
