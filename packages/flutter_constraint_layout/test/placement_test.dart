// Placement and the layout's size (Android's onLayout, CL 2001-2070, and
// resolveMeasuredDimension, CL 1733-1763).
//
// Every child is placed at its integer frame. A child whose last layout
// during the measure has exactly that size keeps it; any other child is laid
// out again, tight at the frame. Gone children and helpers are placed at
// 0 x 0. The layout's size is its measured size, constrained by the incoming
// constraints, and an empty layout fills its bounded axes as Android's fills
// an EXACTLY spec.
//
// Java values are VOpDriver's at the pin (view path, J257), from the
// adapter's probes: each `p4:` and `p4a:` id names an op list of
// test/parity/probes.in, whose output is test/parity/probes.J257.txt.
// Content rounding is the adapter's own rule ("Whole pixels" in the README),
// cited as such.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// A leaf of a natural [width] x [height] (constrained), with an optional
/// alphabetic [baseline]. Counts its layouts.
class Leaf extends LeafRenderObjectWidget {
  const Leaf(this.width, this.height, {this.baseline, super.key});

  final double width;
  final double height;
  final double? baseline;

  @override
  RenderLeaf createRenderObject(BuildContext context) => RenderLeaf(this);

  @override
  void updateRenderObject(BuildContext context, RenderLeaf renderObject) =>
      renderObject.leaf = this;
}

class RenderLeaf extends RenderBox {
  RenderLeaf(this._leaf);

  Leaf _leaf;
  set leaf(Leaf value) {
    if (value.width == _leaf.width &&
        value.height == _leaf.height &&
        value.baseline == _leaf.baseline) {
      return;
    }
    _leaf = value;
    markNeedsLayout();
  }

  /// The number of times this box ran its layout.
  int layouts = 0;

  @override
  void performLayout() {
    layouts++;
    size = constraints.constrain(Size(_leaf.width, _leaf.height));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(Size(_leaf.width, _leaf.height));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _leaf.baseline;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) => _leaf.baseline;
}

/// [children] in a ConstraintLayout under exactly [constraints], at the top
/// left.
Widget under(BoxConstraints constraints, List<Widget> children, {Key? key}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: constraints.minWidth,
          maxWidth: constraints.maxWidth,
          minHeight: constraints.minHeight,
          maxHeight: constraints.maxHeight,
          child: ConstraintLayout(key: key, children: children),
        ),
      ),
    );

RenderConstraintLayout layoutOf(WidgetTester tester) =>
    tester.renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout));

/// The children of the layout, in child order.
List<RenderBox> childrenOf(WidgetTester tester) =>
    layoutOf(tester).getChildrenAsList();

/// The frame the layout gave its child number [index].
Rect frameOf(WidgetTester tester, int index) {
  final child = childrenOf(tester)[index];
  return (child.parentData! as BoxParentData).offset & child.size;
}

final exact400x100 = BoxConstraints.tight(const Size(400, 100));

void main() {
  group('a measured child', () {
    testWidgets('rounds up to whole pixels and is laid out tight at its '
        'frame', (tester) async {
      // A measured size answers max(0, (v - 0.001).ceil()) ("Whole pixels" in
      // the README), so content 99.4 wide answers 100 and is placed tight at
      // 100 rather than clipped or wrapped again at 99, 99.0005 answers 99
      // (the tolerance absorbs glyph-metric noise), and 99.002 answers 100.
      // Each next box follows the edge of the one before.
      await tester.pumpWidget(
        under(exact400x100, [
          Constrained(
            id: #a,
            left: .leftOf(parent),
            top: .topOf(parent),
            child: const Leaf(99.4, 20),
          ),
          Constrained(
            id: #b,
            left: .rightOf(#a),
            top: .topOf(parent),
            child: const Leaf(99.0005, 19.6),
          ),
          Constrained(
            id: #c,
            left: .rightOf(#b),
            top: .topOf(parent),
            child: const Leaf(99.002, 20),
          ),
        ]),
      );
      expect(frameOf(tester, 0), const Rect.fromLTWH(0, 0, 100, 20));
      expect(frameOf(tester, 1), const Rect.fromLTWH(100, 0, 99, 20));
      expect(frameOf(tester, 2), const Rect.fromLTWH(199, 0, 100, 20));
      for (final child in childrenOf(tester)) {
        expect(child.constraints.isTight, isTrue);
        expect(child.constraints.biggest, child.size);
      }
    });

    testWidgets('whose measure size is its frame keeps its measure layout, '
        'and its content changes still reach the layout', (tester) async {
      List<Widget> children(double aWidth) => [
        Constrained(
          id: #a,
          left: .leftOf(parent),
          top: .topOf(parent),
          child: Leaf(aWidth, 20),
        ),
        const Barrier(id: #br, edge: .right, referenced: [#a], margin: 8),
        Constrained(
          id: #k,
          left: .rightOf(#br),
          top: .topOf(parent),
          child: const Leaf(30, 20),
        ),
      ];
      await tester.pumpWidget(under(exact400x100, children(100)));
      final ro = layoutOf(tester);
      // Java J257: a (0, 0) 100 x 20, br (108, 0) 0 x 0, k (108, 0) 30 x 20;
      // a and k measured A400/A100 (VOpDriver view, p4:d5ltr).
      expect(frameOf(tester, 0), const Rect.fromLTWH(0, 0, 100, 20));
      expect(frameOf(tester, 1), const Rect.fromLTWH(108, 0, 0, 0));
      expect(frameOf(tester, 2), const Rect.fromLTWH(108, 0, 30, 20));

      // The boxes keep the loose constraints of their measure (A400/A100),
      // laid out once, so neither is a relayout boundary.
      final a = tester.renderObject<RenderLeaf>(find.byType(Leaf).first);
      expect(
        a.constraints,
        const BoxConstraints(maxWidth: 400, maxHeight: 100),
      );
      expect(a.layouts, 1);
      expect(
        childrenOf(tester)[2].constraints,
        const BoxConstraints(maxWidth: 400, maxHeight: 100),
      );

      final passes = ro.debugLayoutPasses;
      await tester.pumpWidget(under(exact400x100, children(120)));
      expect(ro.debugLayoutPasses, passes + 1);
      // Java J257: k follows at 128 (VOpDriver view, p4a:d5ltr120).
      expect(frameOf(tester, 0), const Rect.fromLTWH(0, 0, 120, 20));
      expect(frameOf(tester, 2), const Rect.fromLTWH(128, 0, 30, 20));
    });

    testWidgets('measured tight at its frame stays as measured, and its '
        'content changes still reach the layout', (tester) async {
      // p4a:spread: a spread match-constraint box between the edges, inset
      // 10. Direct measures it E380/E80 after resolving it, so its measure
      // layout is already tight at the frame: no second layout. Java J257:
      // s (10, 10) 380 x 80, T257 P:s:0:FF:380,80:E380/E80:380,80,-1,00
      // R:s:1:MM:380,80:c:380,80,-1,00 (VOpDriver view, p4a:spread).
      List<Widget> children(double width) => [
        Constrained(
          id: #s,
          left: .leftOf(parent, margin: 10),
          right: .rightOf(parent, margin: 10),
          top: .topOf(parent, margin: 10),
          bottom: .bottomOf(parent, margin: 10),
          width: .matchConstraint,
          height: .matchConstraint,
          child: Leaf(width, 50),
        ),
      ];
      await tester.pumpWidget(under(exact400x100, children(50)));
      final ro = layoutOf(tester);
      final s = tester.renderObject<RenderLeaf>(find.byType(Leaf));
      expect(frameOf(tester, 0), const Rect.fromLTWH(10, 10, 380, 80));
      expect(s.constraints, BoxConstraints.tight(const Size(380, 80)));
      expect(s.layouts, 1);

      // Tight constraints make the box a relayout boundary, but the measure
      // read its baseline, as a layout does for every child it measures, so
      // Flutter still marks this layout when the box's layout is invalidated.
      final passes = ro.debugLayoutPasses;
      await tester.pumpWidget(under(exact400x100, children(60)));
      expect(ro.debugLayoutPasses, passes + 1);
      expect(frameOf(tester, 0), const Rect.fromLTWH(10, 10, 380, 80));
    });
  });

  group('children no measure lays out', () {
    testWidgets('a gone child is laid out at 0 x 0', (tester) async {
      await tester.pumpWidget(
        under(exact400x100, [
          Constrained(
            id: #g,
            left: .leftOf(parent, margin: 10),
            top: .topOf(parent, margin: 10),
            width: .fixed(50),
            height: .fixed(50),
            visibility: .gone,
            child: const Leaf(50, 50),
          ),
          Constrained(
            id: #k,
            left: .rightOf(#g, margin: 5),
            top: .topOf(parent),
            child: const Leaf(30, 20),
          ),
        ]),
      );
      // Java J257: g gone, 0 x 0; k (5, 0) 30 x 20 (VOpDriver view,
      // p4a:gone).
      final g = tester.renderObject<RenderLeaf>(find.byType(Leaf).first);
      expect(g.size, Size.zero);
      expect(g.constraints, BoxConstraints.tight(Size.zero));
      expect(frameOf(tester, 1), const Rect.fromLTWH(5, 0, 30, 20));
    });

    testWidgets('helpers are laid out at 0 x 0 at their position', (
      tester,
    ) async {
      await tester.pumpWidget(
        under(exact400x100, [
          const Guideline.vertical(id: #gl, begin: 50),
          Constrained(
            id: #k,
            left: .leftOf(#gl),
            top: .topOf(parent),
            child: const Leaf(30, 20),
          ),
        ]),
      );
      // Java J257: gl (50, 0) 0 x 0, k (50, 0) 30 x 20 (VOpDriver view,
      // p4a:guide). Android's view Guideline is GONE.
      expect(frameOf(tester, 0), const Rect.fromLTWH(50, 0, 0, 0));
      expect(
        childrenOf(tester)[0].constraints,
        BoxConstraints.tight(Size.zero),
      );
      expect(frameOf(tester, 1), const Rect.fromLTWH(50, 0, 30, 20));
    });

    for (final gone in [false, true]) {
      testWidgets('a group is laid out at 0 x 0 at the origin '
          '(${gone ? 'gone' : 'visible'})', (tester) async {
        await tester.pumpWidget(
          under(exact400x100, [
            Constrained(
              id: #a,
              left: .leftOf(parent, margin: 10),
              top: .topOf(parent, margin: 10),
              child: const Leaf(100, 20),
            ),
            ConstraintGroup(
              id: #G,
              referenced: const [],
              visibility: gone ? .gone : .visible,
            ),
            Constrained(
              id: #k,
              left: .rightOf(#a, margin: 5),
              top: .topOf(parent, margin: 10),
              child: const Leaf(30, 20),
            ),
          ]),
        );
        // Java J257: a (10, 10) 100 x 20, G (0, 0) 0 x 0 (gone: 0 x 0),
        // k (115, 10) 30 x 20 (VOpDriver view, p4:group, p4:groupgone).
        expect(frameOf(tester, 0), const Rect.fromLTWH(10, 10, 100, 20));
        expect(frameOf(tester, 1), Rect.zero);
        expect(frameOf(tester, 2), const Rect.fromLTWH(115, 10, 30, 20));
      });
    }

    testWidgets('a child whose links cross is placed at Android\'s zeroed '
        'frame', (tester) async {
      // Margins of 200 + 200 in a 300-wide layout: the solved edges cross,
      // so updateFromSolver zeroes the whole frame, and setFrame keeps the
      // fixed height (ConstraintWidget.java 3495-3528 and 1682-1733).
      // Java J257: s (0, 0) 0 x 40 (VOpDriver view, p4a:negsize). A size the
      // engine left negative would place at 0 too, since a Flutter box cannot
      // be negative.
      await tester.pumpWidget(
        under(BoxConstraints.tight(const Size(300, 100)), [
          Constrained(
            id: #s,
            left: .leftOf(parent, margin: 200),
            right: .rightOf(parent, margin: 200),
            top: .topOf(parent, margin: 50),
            width: .matchConstraint,
            height: .fixed(40),
            child: const Leaf(0, 0),
          ),
        ]),
      );
      expect(tester.takeException(), isNull);
      expect(frameOf(tester, 0), const Rect.fromLTWH(0, 0, 0, 40));
    });
  });

  group('the layout\'s size', () {
    testWidgets('is the measured size: an unbounded layout grows to its '
        'minimum', (tester) async {
      await tester.pumpWidget(
        under(const BoxConstraints(minWidth: 300, minHeight: 200), [
          Constrained(
            id: #a,
            left: .leftOf(parent),
            right: .rightOf(parent),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
            child: const Leaf(50, 20),
          ),
        ]),
      );
      // Java J257: root 300 x 200, a (125, 90) 50 x 20 (VOpDriver view,
      // p4:d8min).
      expect(layoutOf(tester).size, const Size(300, 200));
      expect(frameOf(tester, 0), const Rect.fromLTWH(125, 90, 50, 20));
    });

    testWidgets('is constrained by fractional constraints', (tester) async {
      List<Widget> children() => [
        Constrained(
          id: #a,
          left: .leftOf(parent),
          right: .rightOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
          child: const Leaf(50, 20),
        ),
      ];
      // A bounded axis is measured EXACTLY at its maximum, rounded: E300 x
      // E101 here. Java J257: root 300 x 101, a (125, 41) 50 x 20
      // (VOpDriver view, p4a:frac).
      const tight = BoxConstraints.tightFor(width: 300.4, height: 100.6);
      await tester.pumpWidget(under(tight, children()));
      expect(layoutOf(tester).size, const Size(300.4, 100.6));
      expect(frameOf(tester, 0), const Rect.fromLTWH(125, 41, 50, 20));

      const loose = BoxConstraints(maxWidth: 300.4, maxHeight: 100.6);
      await tester.pumpWidget(under(loose, children(), key: UniqueKey()));
      expect(layoutOf(tester).size, loose.constrain(const Size(300, 101)));
      expect(frameOf(tester, 0), const Rect.fromLTWH(125, 41, 50, 20));
    });
  });

  group('an empty layout', () {
    for (final (name, constraints, size) in <(String, BoxConstraints, Size)>[
      // Java J257: root 400 x 100 (VOpDriver view, p4:emptyexact).
      ('fills an exact size', exact400x100, const Size(400, 100)),
      // Android fills an EXACTLY spec, and a bounded axis is EXACTLY its
      // maximum ("Sizing and scrolling" in the README); the same as
      // p4:emptyexact.
      (
        'fills a bounded loose size',
        BoxConstraints.loose(const Size(400, 100)),
        const Size(400, 100),
      ),
      // Java J257: root 30 x 40 (VOpDriver view, p4:emptyunbounded, U0 x U0
      // with a minimum of 30 x 40).
      (
        'takes the minimum of an unbounded size',
        const BoxConstraints(minWidth: 30, minHeight: 40),
        const Size(30, 40),
      ),
      // Java J257: root 50 x 0 (VOpDriver view, p4a:empty50).
      (
        'fills a bounded axis and wraps an unbounded one',
        const BoxConstraints(minWidth: 10, maxWidth: 50),
        const Size(50, 0),
      ),
    ]) {
      testWidgets(name, (tester) async {
        await tester.pumpWidget(under(constraints, const []));
        final ro = layoutOf(tester);
        expect(ro.size, size);
        expect(ro.getDryLayout(constraints), size);
        expect(ro.debugEngineContainer, isNull);
      });
    }
  });
}
