// Invalidation and caching tests for the persistent engine model kept by
// RenderConstraintLayout.
//
// Two kinds of assertion appear throughout:
//  * geometry oracle: after any mutation of the persistent tree, geometry must
//    exactly equal a freshly built tree with the same configuration;
//  * path verification: the debug counters prove which cache path ran (fast
//    pass, engine pass, in-place config apply, full model rebuild), so caching
//    cannot silently degrade to rebuild-every-frame or, worse, skip work it
//    needed to do.

import 'package:constraint_layout/constraint_layout.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A leaf whose natural (intrinsic) size is a mutable widget parameter, so
/// tests can change a child's content size without touching its constraints.
class IntrinsicBox extends LeafRenderObjectWidget {
  const IntrinsicBox(this.natural, {super.key});
  final Size natural;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderIntrinsicBox(natural);

  @override
  void updateRenderObject(
          BuildContext context, RenderIntrinsicBox renderObject) =>
      renderObject.natural = natural;
}

class RenderIntrinsicBox extends RenderBox {
  RenderIntrinsicBox(this._natural);

  Size _natural;
  set natural(Size value) {
    if (_natural == value) return;
    _natural = value;
    markNeedsLayout();
  }

  int layoutCount = 0;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    layoutCount++;
    size = constraints.constrain(_natural);
  }
}

/// A leaf with a mutable natural size and alphabetic baseline.
class BaselineBox extends LeafRenderObjectWidget {
  const BaselineBox(this.natural, this.baseline, {super.key});
  final Size natural;
  final double baseline;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderBaselineBox(natural, baseline);

  @override
  void updateRenderObject(
      BuildContext context, RenderBaselineBox renderObject) {
    renderObject
      ..natural = natural
      ..baseline = baseline;
  }
}

class RenderBaselineBox extends RenderBox {
  RenderBaselineBox(this._natural, this._baseline);

  Size _natural;
  set natural(Size value) {
    if (_natural == value) return;
    _natural = value;
    markNeedsLayout();
  }

  double _baseline;
  set baseline(double value) {
    if (_baseline == value) return;
    _baseline = value;
    markNeedsLayout();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _baseline;

  @override
  void performLayout() {
    size = constraints.constrain(_natural);
  }
}

Widget host(
  List<Widget> children, {
  Size size = const Size(800, 600),
  TextDirection dir = TextDirection.ltr,
  Key? key,
}) =>
    Directionality(
      textDirection: dir,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: ConstraintLayout(key: key, children: children),
        ),
      ),
    );

RenderConstraintLayout layoutOf(WidgetTester tester) =>
    tester.renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout));

/// Container size plus every child's offset and size, in document order.
List<List<double>> geometryOf(WidgetTester tester) {
  final ro = layoutOf(tester);
  return [
    [ro.size.width, ro.size.height],
    for (final child in ro.getChildrenAsList())
      [
        child.localToGlobal(Offset.zero, ancestor: ro).dx,
        child.localToGlobal(Offset.zero, ancestor: ro).dy,
        child.size.width,
        child.size.height,
      ],
  ];
}

/// Rebuilds the same configuration as a brand-new tree (forced by a fresh key)
/// and asserts the persistent tree's geometry matched it exactly.
///
/// This replaces the persistent tree, so it must be the last interaction with
/// it; tests that keep mutating afterwards use record-then-replay instead.
Future<void> expectMatchesFresh(
  WidgetTester tester,
  List<Widget> Function() children, {
  Size size = const Size(800, 600),
  TextDirection dir = TextDirection.ltr,
  String? reason,
}) async {
  final live = geometryOf(tester);
  await tester.pumpWidget(
      host(children(), size: size, dir: dir, key: UniqueKey()));
  expect(live, geometryOf(tester), reason: reason);
}

/// The topmost hit-tested direct child at [position].
RenderBox? topChildAt(RenderConstraintLayout ro, Offset position) {
  final result = BoxHitTestResult();
  ro.hitTest(result, position: position);
  final children = ro.getChildrenAsList().toSet();
  for (final entry in result.path) {
    final target = entry.target;
    if (target is RenderBox && children.contains(target)) {
      return target;
    }
  }
  return null;
}

void main() {
  group('steady state', () {
    testWidgets('re-layout with no changes takes the fast path',
        (tester) async {
      final children = [
        Constrained(
          id: #a,
          left: .leftOf(parent, margin: 10),
          top: .topOf(parent, margin: 10),
          width: .fixed(100),
          height: .fixed(40),
          child: const SizedBox(),
        ),
        Constrained(
          id: #b,
          left: .rightOf(#a, margin: 8),
          top: .topOf(#a),
          width: .fixed(60),
          height: .fixed(40),
          child: const SizedBox(),
        ),
      ];
      await tester.pumpWidget(host(children));
      final ro = layoutOf(tester);
      final before = geometryOf(tester);
      expect(ro.debugModelBuilds, 1);
      expect(ro.debugEnginePasses, 1);
      expect(ro.debugFastPasses, 0);

      for (var i = 0; i < 3; i++) {
        ro.markNeedsLayout();
        ro.owner!.flushLayout();
      }
      expect(ro.debugEnginePasses, 1,
          reason: 'no change: the engine must not run again');
      expect(ro.debugFastPasses, 3);
      expect(ro.debugModelBuilds, 1);
      expect(geometryOf(tester), before);
    });

    testWidgets('re-layout with wrap children re-runs the engine',
        (tester) async {
      final children = [
        Constrained(
          id: #a,
          left: .leftOf(parent),
          top: .topOf(parent),
          child: const IntrinsicBox(Size(80, 40)),
        ),
      ];
      await tester.pumpWidget(host(children));
      final ro = layoutOf(tester);
      final before = geometryOf(tester);
      expect(ro.debugEnginePasses, 1);

      ro.markNeedsLayout();
      ro.owner!.flushLayout();
      expect(ro.debugFastPasses, 0,
          reason: 'wrap children depend on content: no fast path');
      expect(ro.debugEnginePasses, 2);
      expect(ro.debugModelBuilds, 1);
      expect(geometryOf(tester), before);
    });
  });

  group('incoming constraints', () {
    testWidgets('resize re-resolves without a model rebuild', (tester) async {
      List<Widget> children() => [
            Constrained(
              id: #centered,
              left: .leftOf(parent),
              right: .rightOf(parent),
              top: .topOf(parent),
              bottom: .bottomOf(parent),
              width: .fixed(80),
              height: .fixed(30),
              child: const SizedBox(),
            ),
            Constrained(
              id: #pinnedRight,
              right: .rightOf(parent, margin: 12),
              top: .topOf(parent, margin: 12),
              width: .fixed(50),
              height: .fixed(50),
              child: const SizedBox(),
            ),
          ];
      await tester.pumpWidget(host(children()));
      final ro = layoutOf(tester);
      expect(geometryOf(tester)[1], [360.0, 285.0, 80.0, 30.0]);
      expect(geometryOf(tester)[2], [738.0, 12.0, 50.0, 50.0]);

      await tester.pumpWidget(host(children(), size: const Size(640, 480)));
      expect(ro.debugModelBuilds, 1, reason: 'resize must not rebuild');
      expect(ro.debugConfigApplies, 0);
      expect(ro.debugEnginePasses, 2);
      expect(geometryOf(tester)[1], [280.0, 225.0, 80.0, 30.0]);
      expect(geometryOf(tester)[2], [578.0, 12.0, 50.0, 50.0]);
      await expectMatchesFresh(tester, children, size: const Size(640, 480));
    });

    testWidgets('boundedness flip to wrap-content root and back',
        (tester) async {
      List<Widget> children() => [
            Constrained(
              id: #a,
              left: .leftOf(parent, margin: 16),
              top: .topOf(parent, margin: 16),
              width: .fixed(80),
              height: .fixed(40),
              child: const SizedBox(),
            ),
            Constrained(
              id: #b,
              left: .leftOf(#a),
              top: .bottomOf(#a, margin: 12),
              width: .fixed(80),
              height: .fixed(40),
              child: const SizedBox(),
            ),
          ];
      Widget bounded(bool isBounded, {Key? key}) => Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 800,
                maxWidth: 800,
                minHeight: isBounded ? 600 : 0,
                maxHeight: isBounded ? 600 : double.infinity,
                child: ConstraintLayout(key: key, children: children()),
              ),
            ),
          );

      await tester.pumpWidget(bounded(true));
      final ro = layoutOf(tester);
      expect(ro.size.height, 600);

      await tester.pumpWidget(bounded(false));
      expect(ro.debugModelBuilds, 1,
          reason: 'boundedness flip must not rebuild the model');
      expect(ro.size.height, 108,
          reason: 'wrap root: 16 + 40 + 12 + 40 content height');
      final wrapGeometry = geometryOf(tester);
      await tester.pumpWidget(bounded(false, key: UniqueKey()));
      expect(wrapGeometry, geometryOf(tester));

      // Back to the persistent tree shape, then flip to bounded again.
      await tester.pumpWidget(bounded(false));
      await tester.pumpWidget(bounded(true));
      expect(layoutOf(tester).size.height, 600);
    });
  });

  group('in-place config changes', () {
    // Builds A pinned top-left and B whose links/dims are the mutation target.
    List<Widget> pair({
      required HorizontalLink bLeft,
      VerticalLink? bTop,
      VerticalLink? bBottom,
      Dimension bWidth = const Dimension.fixed(60),
      Dimension bHeight = const Dimension.fixed(20),
      double bBias = 0.5,
      double? bRatio,
      bool aGone = false,
    }) =>
        [
          Constrained(
            id: #a,
            left: .leftOf(parent, margin: 10),
            top: .topOf(parent, margin: 10),
            width: .fixed(100),
            height: .fixed(40),
            visibility: aGone ? .gone : .visible,
            child: const SizedBox(),
          ),
          Constrained(
            id: #b,
            left: bLeft,
            top: bTop ?? const VerticalLink.topOf(parent),
            bottom: bBottom,
            width: bWidth,
            height: bHeight,
            verticalBias: bBias,
            aspectRatio: bRatio,
            child: const SizedBox(),
          ),
        ];

    Future<void> expectInPlace(
      WidgetTester tester,
      RenderConstraintLayout ro,
      List<Widget> Function() config, {
      required int applies,
    }) async {
      expect(ro.debugModelBuilds, 1,
          reason: 'config change must be applied in place, not rebuilt');
      expect(ro.debugConfigApplies, applies);
      await expectMatchesFresh(tester, config);
    }

    testWidgets('margin change', (tester) async {
      await tester
          .pumpWidget(host(pair(bLeft: .rightOf(#a, margin: 8))));
      final ro = layoutOf(tester);
      expect(geometryOf(tester)[2][0], 118.0);

      await tester
          .pumpWidget(host(pair(bLeft: .rightOf(#a, margin: 40))));
      expect(geometryOf(tester)[2][0], 150.0);
      await expectInPlace(
          tester, ro, () => pair(bLeft: .rightOf(#a, margin: 40)),
          applies: 1);
    });

    testWidgets('link retarget and edge change', (tester) async {
      await tester
          .pumpWidget(host(pair(bLeft: .rightOf(#a, margin: 8))));
      final ro = layoutOf(tester);

      // Retarget: B now aligns to A's left edge instead of following its right.
      await tester.pumpWidget(host(pair(bLeft: .leftOf(#a))));
      expect(geometryOf(tester)[2][0], 10.0);
      await expectInPlace(tester, ro, () => pair(bLeft: .leftOf(#a)),
          applies: 1);
    });

    testWidgets('adding an opposing anchor centers, removing it restores',
        (tester) async {
      List<Widget> anchored() => pair(
            bLeft: .leftOf(parent),
            bTop: const VerticalLink.topOf(parent),
          );
      List<Widget> centered({double bias = 0.5}) => pair(
            bLeft: .leftOf(parent),
            bTop: const VerticalLink.topOf(parent),
            bBottom: const VerticalLink.bottomOf(parent),
            bBias: bias,
          );
      await tester.pumpWidget(host(anchored()));
      final ro = layoutOf(tester);
      expect(geometryOf(tester)[2][1], 0.0);

      await tester.pumpWidget(host(centered()));
      expect(geometryOf(tester)[2][1], 290.0);
      expect(ro.debugModelBuilds, 1);

      // Bias sweep on the persistent model.
      for (final bias in [0.0, 0.25, 0.75, 1.0]) {
        await tester.pumpWidget(host(centered(bias: bias)));
        expect(geometryOf(tester)[2][1], (600 - 20) * bias,
            reason: 'bias $bias');
        expect(ro.debugModelBuilds, 1);
      }

      await tester.pumpWidget(host(anchored()));
      expect(geometryOf(tester)[2][1], 0.0);
      await expectMatchesFresh(tester, anchored);
    });

    testWidgets('dimension type transitions', (tester) async {
      List<Widget> withWidth(Dimension width) => [
            Constrained(
              id: #a,
              left: .leftOf(parent, margin: 20),
              right: .rightOf(parent, margin: 20),
              top: .topOf(parent),
              width: width,
              height: .fixed(40),
              child: const IntrinsicBox(Size(88, 33)),
            ),
          ];
      await tester.pumpWidget(host(withWidth(.fixed(100))));
      final ro = layoutOf(tester);
      expect(geometryOf(tester)[1][2], 100.0);

      await tester.pumpWidget(host(withWidth(.wrapContent)));
      expect(geometryOf(tester)[1][2], 88.0);
      expect(ro.debugModelBuilds, 1);

      await tester.pumpWidget(host(withWidth(.matchConstraint)));
      expect(geometryOf(tester)[1][2], 760.0);
      expect(ro.debugModelBuilds, 1);

      await tester.pumpWidget(host(withWidth(.fixed(100))));
      expect(geometryOf(tester)[1][2], 100.0);
      await expectMatchesFresh(tester, () => withWidth(.fixed(100)));
    });

    testWidgets('aspect ratio add, change, remove', (tester) async {
      // matchConstraint width + fixed height + ratio derives the width from
      // the height (the phase-1-supported ratio pattern).
      List<Widget> withRatio(double? ratio) => [
            Constrained(
              id: #a,
              left: .leftOf(parent),
              right: .rightOf(parent),
              top: .topOf(parent),
              width: .matchConstraint,
              height: .fixed(40),
              aspectRatio: ratio,
              child: const SizedBox(),
            ),
          ];

      // All persistent-tree steps first, recording geometry.
      final ratios = <double?>[null, 2.0, 4.0, null];
      final expectedWidgetRect = <List<double>>[
        [0.0, 0.0, 800.0, 40.0],
        [360.0, 0.0, 80.0, 40.0],
        [320.0, 0.0, 160.0, 40.0],
        [0.0, 0.0, 800.0, 40.0],
      ];
      final snapshots = <List<List<double>>>[];
      await tester.pumpWidget(host(withRatio(ratios.first)));
      final ro = layoutOf(tester);
      snapshots.add(geometryOf(tester));
      for (final ratio in ratios.skip(1)) {
        await tester.pumpWidget(host(withRatio(ratio)));
        snapshots.add(geometryOf(tester));
      }
      expect(ro.debugModelBuilds, 1,
          reason: 'ratio changes must be applied in place');
      for (var i = 0; i < ratios.length; i++) {
        expect(snapshots[i][1], expectedWidgetRect[i],
            reason: 'ratio ${ratios[i]}');
      }

      // Fresh replay of every step. The final null step in particular proves
      // the removed ratio was fully cleared from the persistent widget.
      for (var i = 0; i < ratios.length; i++) {
        await tester
            .pumpWidget(host(withRatio(ratios[i]), key: UniqueKey()));
        expect(geometryOf(tester), snapshots[i],
            reason: 'fresh replay for ratio ${ratios[i]} diverged');
      }
    });

    testWidgets('gone round-trip with a dependent sibling and goneMargin',
        (tester) async {
      List<Widget> children({required bool aGone}) => [
            Constrained(
              id: #a,
              left: .leftOf(parent, margin: 10),
              top: .topOf(parent, margin: 10),
              width: .fixed(100),
              height: .fixed(40),
              visibility: aGone ? .gone : .visible,
              child: const SizedBox(),
            ),
            Constrained(
              id: #b,
              left: .rightOf(#a, margin: 8, goneMargin: 32),
              top: .topOf(#a),
              width: .fixed(60),
              height: .fixed(20),
              child: const SizedBox(),
            ),
          ];
      await tester.pumpWidget(host(children(aGone: false)));
      final ro = layoutOf(tester);
      final visible = geometryOf(tester);
      expect(visible[2][0], 118.0);

      await tester.pumpWidget(host(children(aGone: true)));
      final gone = geometryOf(tester);
      expect(gone[1], [0.0, 0.0, 0.0, 0.0],
          reason: 'gone child collapses to zero at origin');
      expect(gone[2][0], 32.0, reason: 'gone margin applies');
      expect(ro.debugModelBuilds, 1);

      // Un-gone on the persistent model must fully restore the configured
      // size (the engine zeroes a gone widget's stored dimensions).
      await tester.pumpWidget(host(children(aGone: false)));
      expect(geometryOf(tester), visible);
      expect(ro.debugModelBuilds, 1);

      // Fresh replay of both states.
      await tester
          .pumpWidget(host(children(aGone: true), key: UniqueKey()));
      expect(geometryOf(tester), gone);
      await tester
          .pumpWidget(host(children(aGone: false), key: UniqueKey()));
      expect(geometryOf(tester), visible);
    });

    testWidgets('several children changed in one frame', (tester) async {
      List<Widget> children(int margin, double bias, Dimension width) => [
            Constrained(
              id: #a,
              left: .leftOf(parent, margin: margin.toDouble()),
              top: .topOf(parent),
              width: .fixed(50),
              height: .fixed(20),
              child: const SizedBox(),
            ),
            Constrained(
              id: #b,
              left: .leftOf(parent),
              right: .rightOf(parent),
              top: .bottomOf(#a),
              horizontalBias: bias,
              width: .fixed(70),
              height: .fixed(20),
              child: const SizedBox(),
            ),
            Constrained(
              id: #c,
              left: .leftOf(parent),
              right: .rightOf(parent),
              top: .bottomOf(#b),
              width: width,
              height: .fixed(20),
              child: const SizedBox(),
            ),
          ];
      await tester.pumpWidget(host(children(10, 0.5, .fixed(100))));
      final ro = layoutOf(tester);
      final applies = ro.debugConfigApplies;

      await tester.pumpWidget(host(children(24, 0.25, .matchConstraint)));
      expect(ro.debugModelBuilds, 1);
      expect(ro.debugConfigApplies, applies + 3);
      await expectMatchesFresh(
          tester, () => children(24, 0.25, .matchConstraint));
    });
  });

  group('structural changes', () {
    testWidgets('id rename with a simultaneous sibling retarget',
        (tester) async {
      List<Widget> children(Symbol anchorId) => [
            Constrained(
              id: anchorId,
              left: .leftOf(parent, margin: 30),
              top: .topOf(parent),
              width: .fixed(100),
              height: .fixed(40),
              child: const SizedBox(),
            ),
            Constrained(
              id: #b,
              left: .rightOf(anchorId, margin: 8),
              top: .topOf(anchorId),
              width: .fixed(60),
              height: .fixed(20),
              child: const SizedBox(),
            ),
          ];
      await tester.pumpWidget(host(children(#a)));
      final ro = layoutOf(tester);
      final before = geometryOf(tester);

      await tester.pumpWidget(host(children(#renamed)));
      expect(ro.debugModelBuilds, 2, reason: 'id rename rebuilds the model');
      expect(geometryOf(tester), before);
      await expectMatchesFresh(tester, () => children(#renamed));
    });

    testWidgets('adding and removing a child', (tester) async {
      Widget cell(Symbol id, Symbol after, {Key? key}) => Constrained(
            key: key,
            id: id,
            left: .leftOf(parent, margin: 10),
            top: .bottomOf(after, margin: 6),
            width: .fixed(80),
            height: .fixed(30),
            child: const SizedBox(),
          );
      final head = Constrained(
        key: const ValueKey(#head),
        id: #head,
        left: .leftOf(parent, margin: 10),
        top: .topOf(parent, margin: 10),
        width: .fixed(80),
        height: .fixed(30),
        child: const SizedBox(),
      );

      List<Widget> two() =>
          [head, cell(#row1, #head, key: const ValueKey(#row1))];
      List<Widget> three() => [
            head,
            cell(#row1, #head, key: const ValueKey(#row1)),
            cell(#row2, #row1, key: const ValueKey(#row2)),
          ];

      // All persistent-tree steps first.
      await tester.pumpWidget(host(two()));
      final ro = layoutOf(tester);
      expect(ro.debugModelBuilds, 1);

      await tester.pumpWidget(host(three()));
      expect(ro.debugModelBuilds, 2);
      final withThree = geometryOf(tester);
      expect(withThree[3][1], 82.0, reason: '10 + 30+6 + 30+6');

      await tester.pumpWidget(host(two()));
      expect(ro.debugModelBuilds, 3);
      final withTwo = geometryOf(tester);

      // Fresh replay of both configurations.
      await tester.pumpWidget(host(three(), key: UniqueKey()));
      expect(geometryOf(tester), withThree);
      await tester.pumpWidget(host(two(), key: UniqueKey()));
      expect(geometryOf(tester), withTwo);
    });

    testWidgets('reordering children rebuilds and keeps anchor semantics',
        (tester) async {
      Widget box(Symbol id, HorizontalLink left, {Key? key}) => Constrained(
            key: key,
            id: id,
            left: left,
            top: .topOf(parent),
            width: .fixed(50),
            height: .fixed(20),
            child: const SizedBox(),
          );
      final a =
          box(#a, .leftOf(parent, margin: 5), key: const ValueKey(#a));
      final b = box(#b, .rightOf(#a, margin: 5), key: const ValueKey(#b));

      await tester.pumpWidget(host([a, b]));
      final ro = layoutOf(tester);
      final byIdBefore = {
        for (final e in geometryOf(tester).skip(1)) e[0]: e,
      };

      await tester.pumpWidget(host([b, a]));
      expect(ro.debugModelBuilds, 2, reason: 'move() rebuilds the model');
      final after = geometryOf(tester).skip(1).toList();
      // Same resolved positions, reported in the new document order.
      expect({for (final e in after) e[0]: e}, byIdBefore);
      await expectMatchesFresh(tester, () => [b, a]);
    });

    testWidgets('removing a referenced target reports an error',
        (tester) async {
      final a = Constrained(
        key: const ValueKey(#a),
        id: #a,
        left: .leftOf(parent),
        top: .topOf(parent),
        width: .fixed(50),
        height: .fixed(20),
        child: const SizedBox(),
      );
      final b = Constrained(
        key: const ValueKey(#b),
        id: #b,
        left: .rightOf(#a),
        top: .topOf(parent),
        width: .fixed(50),
        height: .fixed(20),
        child: const SizedBox(),
      );
      await tester.pumpWidget(host([a, b]));
      await tester.pumpWidget(host([b]));
      expect(tester.takeException(), isFlutterError);
    });

    testWidgets('retargeting a link to an unknown id reports an error',
        (tester) async {
      List<Widget> children(Symbol target) => [
            Constrained(
              id: #a,
              left: .leftOf(target),
              top: .topOf(parent),
              width: .fixed(50),
              height: .fixed(20),
              child: const SizedBox(),
            ),
          ];
      await tester.pumpWidget(host(children(parent)));
      await tester.pumpWidget(host(children(#missing)));
      expect(tester.takeException(), isFlutterError);
    });

    testWidgets('text direction flip re-resolves start/end links',
        (tester) async {
      List<Widget> children() => [
            Constrained(
              id: #a,
              start: .startOf(parent, margin: 24),
              top: .topOf(parent),
              width: .fixed(60),
              height: .fixed(20),
              child: const SizedBox(),
            ),
          ];
      await tester.pumpWidget(host(children()));
      final ro = layoutOf(tester);
      expect(geometryOf(tester)[1][0], 24.0);

      await tester.pumpWidget(host(children(), dir: TextDirection.rtl));
      expect(ro.debugModelBuilds, 2,
          reason: 'direction change rebuilds connections');
      expect(geometryOf(tester)[1][0], 800.0 - 24.0 - 60.0);
      await expectMatchesFresh(tester, children, dir: TextDirection.rtl);
    });
  });

  group('content changes', () {
    testWidgets('wrap child content growth re-resolves dependents',
        (tester) async {
      List<Widget> children(Size aNatural) => [
            Constrained(
              id: #a,
              left: .leftOf(parent),
              top: .topOf(parent),
              child: IntrinsicBox(aNatural),
            ),
            Constrained(
              id: #b,
              left: .rightOf(#a, margin: 8),
              top: .topOf(#a),
              width: .fixed(60),
              height: .fixed(20),
              child: const SizedBox(),
            ),
          ];
      await tester.pumpWidget(host(children(const Size(80, 40))));
      final ro = layoutOf(tester);
      expect(geometryOf(tester)[2][0], 88.0);
      final builds = ro.debugModelBuilds;
      final applies = ro.debugConfigApplies;
      final engine = ro.debugEnginePasses;

      // Only the leaf's natural size changes: no Constrained field differs,
      // so this must reach the container purely through layout dirtiness.
      await tester.pumpWidget(host(children(const Size(120, 40))));
      expect(geometryOf(tester)[1][2], 120.0);
      expect(geometryOf(tester)[2][0], 128.0,
          reason: 'dependent sibling must follow the grown wrap child');
      expect(ro.debugModelBuilds, builds);
      expect(ro.debugConfigApplies, applies);
      expect(ro.debugEnginePasses, engine + 1);
      await expectMatchesFresh(tester, () => children(const Size(120, 40)));
    });

    testWidgets('fixed child content change does not re-layout the container',
        (tester) async {
      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          left: .leftOf(parent),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          child: const IntrinsicBox(Size(80, 40)),
        ),
      ]));
      final ro = layoutOf(tester);
      final passes = ro.debugLayoutPasses;

      await tester.pumpWidget(host([
        Constrained(
          id: #a,
          left: .leftOf(parent),
          top: .topOf(parent),
          width: .fixed(100),
          height: .fixed(50),
          child: const IntrinsicBox(Size(200, 90)),
        ),
      ]));
      expect(ro.debugLayoutPasses, passes,
          reason: 'a fixed-size child is a relayout boundary; its content '
              'change must be absorbed by the child itself');
      expect(geometryOf(tester)[1], [0.0, 0.0, 100.0, 50.0]);
    });

    testWidgets('baseline shift of a fixed-size target re-resolves',
        (tester) async {
      List<Widget> children(double aBaseline) => [
            Constrained(
              id: #a,
              left: .leftOf(parent),
              top: .topOf(parent, margin: 10),
              width: .fixed(100),
              height: .fixed(40),
              child: BaselineBox(const Size(100, 40), aBaseline),
            ),
            Constrained(
              id: #b,
              left: .rightOf(#a, margin: 8),
              baseline: .baselineOf(#a),
              width: .fixed(80),
              height: .fixed(30),
              child: const BaselineBox(Size(80, 30), 10),
            ),
          ];
      await tester.pumpWidget(host(children(30)));
      final ro = layoutOf(tester);
      expect(geometryOf(tester)[2][1], 30.0,
          reason: 'B top = 10 + 30 - 10');
      final builds = ro.debugModelBuilds;

      await tester.pumpWidget(host(children(38)));
      expect(geometryOf(tester)[2][1], 38.0,
          reason: 'baseline change must propagate through the container');
      expect(ro.debugModelBuilds, builds);
      await expectMatchesFresh(tester, () => children(38));
    });
  });

  group('paint-only changes', () {
    testWidgets('zIndex change reorders hit testing without re-layout',
        (tester) async {
      List<Widget> children({required int aZ, required int bZ}) => [
            Constrained(
              id: #a,
              left: .leftOf(parent),
              top: .topOf(parent),
              width: .fixed(100),
              height: .fixed(100),
              zIndex: aZ,
              child: const IntrinsicBox(Size(100, 100)),
            ),
            Constrained(
              id: #b,
              left: .leftOf(parent),
              top: .topOf(parent),
              width: .fixed(100),
              height: .fixed(100),
              zIndex: bZ,
              child: const IntrinsicBox(Size(100, 100)),
            ),
          ];
      await tester.pumpWidget(host(children(aZ: 0, bZ: 1)));
      final ro = layoutOf(tester);
      final boxes = ro.getChildrenAsList();
      expect(topChildAt(ro, const Offset(50, 50)), boxes[1]);
      final passes = ro.debugLayoutPasses;

      await tester.pumpWidget(host(children(aZ: 2, bZ: 1)));
      expect(ro.debugLayoutPasses, passes,
          reason: 'zIndex is paint-only: no layout pass');
      expect(topChildAt(ro, const Offset(50, 50)), boxes[0]);
    });
  });

  group('mutation sequences', () {
    testWidgets('scripted sequence matches fresh at every step',
        (tester) async {
      List<Widget> config({
        int margin = 10,
        double bias = 0.5,
        bool cGone = false,
        Dimension bWidth = const Dimension.fixed(60),
        Size aNatural = const Size(80, 40),
      }) =>
          [
            Constrained(
              key: const ValueKey(#a),
              id: #a,
              left: .leftOf(parent, margin: margin.toDouble()),
              top: .topOf(parent, margin: 10),
              child: IntrinsicBox(aNatural),
            ),
            Constrained(
              key: const ValueKey(#b),
              id: #b,
              left: .rightOf(#a, margin: 8),
              right: .rightOf(parent, margin: 8),
              top: .topOf(#a),
              horizontalBias: bias,
              width: bWidth,
              height: .fixed(24),
              child: const SizedBox(),
            ),
            Constrained(
              key: const ValueKey(#c),
              id: #c,
              left: .leftOf(#a),
              top: .bottomOf(#a, margin: 12, goneMargin: 40),
              width: .fixed(120),
              height: .fixed(32),
              visibility: cGone ? .gone : .visible,
              child: const SizedBox(),
            ),
          ];

      final steps = <(String, List<Widget> Function(), Size)>[
        ('initial', () => config(), const Size(800, 600)),
        ('margin', () => config(margin: 32), const Size(800, 600)),
        ('resize', () => config(margin: 32), const Size(640, 480)),
        ('bias', () => config(margin: 32, bias: 0.2), const Size(640, 480)),
        (
          'gone',
          () => config(margin: 32, bias: 0.2, cGone: true),
          const Size(640, 480)
        ),
        (
          'content',
          () => config(
              margin: 32, bias: 0.2, cGone: true, aNatural: const Size(50, 60)),
          const Size(640, 480)
        ),
        (
          'match',
          () => config(
              margin: 32,
              bias: 0.2,
              cGone: true,
              aNatural: const Size(50, 60),
              bWidth: .matchConstraint),
          const Size(640, 480)
        ),
        (
          'ungone',
          () => config(
              margin: 32,
              bias: 0.2,
              aNatural: const Size(50, 60),
              bWidth: .matchConstraint),
          const Size(640, 480)
        ),
        (
          'resize back',
          () => config(
              margin: 32,
              bias: 0.2,
              aNatural: const Size(50, 60),
              bWidth: .matchConstraint),
          const Size(800, 600)
        ),
        ('restore', () => config(), const Size(800, 600)),
      ];

      // Run the whole sequence on the persistent tree, recording geometry.
      final snapshots = <List<List<double>>>[];
      for (final (name, children, size) in steps) {
        await tester.pumpWidget(host(children(), size: size));
        expect(tester.takeException(), isNull, reason: 'step $name');
        snapshots.add(geometryOf(tester));
      }
      final ro = layoutOf(tester);
      expect(ro.debugModelBuilds, 1,
          reason: 'no step in this sequence is structural');

      // Replay every step as a fresh tree and compare.
      for (var i = 0; i < steps.length; i++) {
        final (name, children, size) = steps[i];
        await tester
            .pumpWidget(host(children(), size: size, key: UniqueKey()));
        expect(geometryOf(tester), snapshots[i],
            reason: 'fresh replay of step "$name" diverged');
      }
    });
  });
}
