// A barrier is an invisible line that tracks the furthest edge of a group, so
// the rest of the layout can clear "whichever of these is biggest" without
// knowing which one that is. Each of the four types is a separate branch all
// the way through measuring, Direct's resolution and the solver, and gone
// widgets change which members count. The existing barrier_test covers one
// type against guidelines; this covers the matrix.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

/// A root with three widgets of different sizes pinned to the top-left, and a
/// barrier over all three.
({
  ConstraintWidgetContainer root,
  Barrier barrier,
  List<ConstraintWidget> widgets,
})
buildBarrier(int type, {int margin = 0, bool allowsGone = true}) {
  final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
  root.setDebugName('root');

  final widgets = <ConstraintWidget>[];
  const sizes = [(60, 20), (140, 40), (100, 80)];
  for (final (i, (w, h)) in sizes.indexed) {
    final widget = ConstraintWidget.size(w, h);
    widget.setDebugName('w$i');
    root.add(widget);
    // Staggered from the top-left so every edge of the group differs.
    widget.connect(
      ConstraintAnchorType.left,
      root,
      ConstraintAnchorType.left,
      10 * i,
    );
    widget.connect(
      ConstraintAnchorType.top,
      root,
      ConstraintAnchorType.top,
      15 * i,
    );
    widgets.add(widget);
  }

  final barrier = Barrier();
  barrier.setDebugName('barrier');
  barrier.setBarrierType(type);
  barrier.setMargin(margin);
  barrier.setAllowsGoneWidget(allowsGone);
  for (final w in widgets) {
    barrier.add(w);
  }
  root.add(barrier);

  return (root: root, barrier: barrier, widgets: widgets);
}

void main() {
  group('barrier types', () {
    test('left tracks the leftmost left edge', () {
      final b = buildBarrier(Barrier.left);
      b.root.layout();

      final expected = b.widgets.map((w) => w.getLeft()).reduce((a, c) => a < c ? a : c);
      expect(b.barrier.getLeft(), expected);
      expect(b.barrier.getOrientation(), ConstraintWidget.HORIZONTAL);
    });

    test('right tracks the rightmost right edge', () {
      final b = buildBarrier(Barrier.right);
      b.root.layout();

      final expected = b.widgets.map((w) => w.getRight()).reduce((a, c) => a > c ? a : c);
      expect(b.barrier.getLeft(), expected);
      expect(b.barrier.getOrientation(), ConstraintWidget.HORIZONTAL);
    });

    test('top tracks the topmost top edge', () {
      final b = buildBarrier(Barrier.top);
      b.root.layout();

      final expected = b.widgets.map((w) => w.getTop()).reduce((a, c) => a < c ? a : c);
      expect(b.barrier.getTop(), expected);
      expect(b.barrier.getOrientation(), ConstraintWidget.VERTICAL);
    });

    test('bottom tracks the bottommost bottom edge', () {
      final b = buildBarrier(Barrier.bottom);
      b.root.layout();

      final expected = b.widgets.map((w) => w.getBottom()).reduce((a, c) => a > c ? a : c);
      expect(b.barrier.getTop(), expected);
      expect(b.barrier.getOrientation(), ConstraintWidget.VERTICAL);
    });

    test('an unset type reports no orientation', () {
      final barrier = Barrier();
      barrier.setBarrierType(99);
      expect(barrier.getOrientation(), ConstraintWidget.UNKNOWN);
    });
  });

  group('margins', () {
    test('a margin pushes the line past the tracked edge', () {
      final plain = buildBarrier(Barrier.right);
      plain.root.layout();
      final withoutMargin = plain.barrier.getLeft();

      final margined = buildBarrier(Barrier.right, margin: 25);
      margined.root.layout();

      expect(margined.barrier.getMargin(), 25);
      expect(margined.barrier.getLeft(), withoutMargin + 25);
    });

    test('a bottom barrier margin moves it down', () {
      final plain = buildBarrier(Barrier.bottom);
      plain.root.layout();
      final withoutMargin = plain.barrier.getTop();

      final margined = buildBarrier(Barrier.bottom, margin: 12);
      margined.root.layout();
      expect(margined.barrier.getTop(), withoutMargin + 12);
    });
  });

  group('gone widgets', () {
    test('allowsGone keeps a collapsed widget in the group', () {
      final b = buildBarrier(Barrier.right);
      b.root.layout();
      final before = b.barrier.getLeft();

      // The widest widget goes away. With gone widgets still counted, the
      // barrier follows their collapsed position rather than ignoring them.
      b.widgets[1].setVisibility(ConstraintWidget.GONE);
      b.root.layout();
      expect(b.barrier.getLeft(), isNot(before));
      expect(b.barrier.getAllowsGoneWidget(), isTrue);
    });

    test('without allowsGone a collapsed widget stops counting', () {
      final b = buildBarrier(Barrier.right, allowsGone: false);
      expect(b.barrier.getAllowsGoneWidget(), isFalse);

      b.widgets[1].setVisibility(ConstraintWidget.GONE);
      b.root.layout();

      // The remaining two widgets decide the line.
      final expected = [b.widgets[0], b.widgets[2]]
          .map((w) => w.getRight())
          .reduce((a, c) => a > c ? a : c);
      expect(b.barrier.getLeft(), expected);
    });

    test('a barrier over an entirely gone group still resolves', () {
      final b = buildBarrier(Barrier.right, allowsGone: false);
      for (final w in b.widgets) {
        w.setVisibility(ConstraintWidget.GONE);
      }
      expect(b.root.layout, returnsNormally);
    });

    test('a barrier with no widgets at all still resolves', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final barrier = Barrier();
      barrier.setBarrierType(Barrier.left);
      root.add(barrier);
      expect(root.layout, returnsNormally);
    });
  });

  group('as a constraint target', () {
    test('a widget clears whichever member sticks out furthest', () {
      final b = buildBarrier(Barrier.right, margin: 8);
      final follower = ConstraintWidget.size(50, 20);
      follower.setDebugName('follower');
      b.root.add(follower);
      follower.connect(
        ConstraintAnchorType.left,
        b.barrier,
        ConstraintAnchorType.left,
      );
      follower.connect(ConstraintAnchorType.top, b.root, ConstraintAnchorType.top);
      b.root.layout();

      expect(follower.getLeft(), b.barrier.getLeft());
      // Past the widest member plus the barrier margin.
      final widest =
          b.widgets.map((w) => w.getRight()).reduce((a, c) => a > c ? a : c);
      expect(follower.getLeft(), widest + 8);
    });

    test('a barrier can track another barrier', () {
      final b = buildBarrier(Barrier.right);
      final second = Barrier();
      second.setDebugName('second');
      second.setBarrierType(Barrier.right);
      second.setMargin(30);
      second.add(b.barrier);
      b.root.add(second);

      expect(b.root.layout, returnsNormally);
      expect(second.getLeft(), b.barrier.getLeft() + 30);
    });

    test('the barrier is allowed inside another barrier', () {
      expect(Barrier().allowedInBarrier(), isTrue);
    });
  });

  group('resolution bookkeeping', () {
    test('markWidgets tags the group before the graph runs', () {
      final b = buildBarrier(Barrier.left);
      expect(b.barrier.markWidgets, returnsNormally);
    });

    test('a named barrier keeps its debug name', () {
      final barrier = Barrier.named('labels');
      expect(barrier.getDebugName(), 'labels');
    });

    test('the group is re-read on every layout', () {
      final b = buildBarrier(Barrier.right);
      b.root.layout();
      final before = b.barrier.getLeft();

      // Growing a member moves the line without any reconfiguration.
      b.widgets[1].setWidth(260);
      b.root.layout();
      expect(b.barrier.getLeft(), greaterThan(before));
    });
  });
}
