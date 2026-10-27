// A ConstraintGroup is an engine widget in child order, as Android's Group
// view is: a ConstraintHelper whose widget is the plain widget of its layout
// params (wrap_content on both axes, no link), measured at 0 x 0 without a
// baseline and placed at the origin, or gone with the group. It holds solver
// variables like any other widget, so it shifts the ids of every later one.
//
// Every Java value is VOpDriver's at 257 on the view path: each probe id
// names an op list of test/parity/probes.in, whose output (frames, and the
// T257 request transcript) is test/parity/probes.J257.txt.

import 'package:constraint_engine/constraint_engine.dart' as engine;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// The probes' layout: #a, the group #G and #k.
ConstraintLayout groupLayout({
  required ConstraintVisibility group,
  List<Symbol> referenced = const [],
  Key? key,
}) => ConstraintLayout(
  key: key,
  children: [
    Constrained(
      id: #a,
      left: .leftOf(parent, margin: 10),
      top: .topOf(parent, margin: 10),
      child: const SizedBox(width: 100, height: 20),
    ),
    ConstraintGroup(id: #G, referenced: referenced, visibility: group),
    Constrained(
      id: #k,
      left: .rightOf(#a, margin: 5),
      top: .topOf(parent, margin: 10),
      child: const SizedBox(width: 30, height: 20),
    ),
  ],
);

/// [layouts], each under a tight 400 x 100 (the probes' E400 x E100).
Widget host(List<Widget> layouts) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final layout in layouts)
          SizedBox(width: 400, height: 100, child: layout),
      ],
    ),
  ),
);

RenderConstraintLayout layoutOf(WidgetTester tester, [Key? key]) =>
    tester.renderObject<RenderConstraintLayout>(
      key == null ? find.byType(ConstraintLayout) : find.byKey(key),
    );

/// The frame of every child, in child order, as placed: offset and size.
List<Rect> framesOf(RenderConstraintLayout ro) => [
  for (final child in ro.getChildrenAsList())
    (child.parentData! as BoxParentData).offset & child.size,
];

String transcriptOf(RenderConstraintLayout ro) =>
    ro.debugViewHost!.measurer.transcript.toString();

void main() {
  setUp(() => RenderConstraintLayout.debugRecordTranscripts = true);
  tearDown(() => RenderConstraintLayout.debugRecordTranscripts = false);

  testWidgets('a visible group is a plain widget measured 0 x 0 at the '
      'origin', (tester) async {
    await tester.pumpWidget(host([groupLayout(group: .visible)]));
    final ro = layoutOf(tester);
    // Java J257: a (10, 10) 100 x 20, G (0, 0) 0 x 0, k (115, 10) 30 x 20
    // (VOpDriver view, probe p4:group).
    expect(framesOf(ro), const [
      Rect.fromLTWH(10, 10, 100, 20),
      Rect.fromLTWH(0, 0, 0, 0),
      Rect.fromLTWH(115, 10, 30, 20),
    ]);
    // Java T257 (p4:group): the group's widget is measured between its
    // siblings, as the view measurer measures a Group view (0 x 0, no
    // baseline).
    expect(
      transcriptOf(ro),
      'M:a:0:WW:0,0:A400/A100:100,20,-1,01 '
      'M:G:0:WW:0,0:A400/A100:0,0,-1,00 '
      'M:k:0:WW:0,0:A400/A100:30,20,-1,01',
    );
  });

  testWidgets('a gone group is a gone widget', (tester) async {
    await tester.pumpWidget(host([groupLayout(group: .gone)]));
    final ro = layoutOf(tester);
    // Java J257: a (10, 10) 100 x 20, G: gone, 0 x 0, k (115, 10) 30 x 20
    // (VOpDriver view, probe p4:groupgone). A gone child is placed at the
    // origin, at 0 x 0.
    expect(framesOf(ro), const [
      Rect.fromLTWH(10, 10, 100, 20),
      Rect.fromLTWH(0, 0, 0, 0),
      Rect.fromLTWH(115, 10, 30, 20),
    ]);
    // Java T257 (p4:groupgone): the GONE short cut answers for the group.
    expect(
      transcriptOf(ro),
      'M:a:0:WW:0,0:A400/A100:100,20,-1,01 '
      'M:G:0:WW:0,0:g:0,0,0,00 '
      'M:k:0:WW:0,0:A400/A100:30,20,-1,01',
    );
  });

  testWidgets('the group widget sits in the container at its child index', (
    tester,
  ) async {
    for (final visibility in ConstraintVisibility.values) {
      await tester.pumpWidget(host([groupLayout(group: visibility)]));
      final children = layoutOf(tester).debugEngineContainer!.getChildren();
      expect(
        [for (final w in children) w.getDebugName()],
        ['a', 'G', 'k'],
        reason: 'one widget per child, in child order',
      );
      final group = children[1];
      expect(group.runtimeType, engine.ConstraintWidget);
      expect(
        group.getHorizontalDimensionBehaviour(),
        engine.DimensionBehaviour.wrapContent,
      );
      expect(
        group.getVerticalDimensionBehaviour(),
        engine.DimensionBehaviour.wrapContent,
      );
      expect(group.getVisibility(), switch (visibility) {
        ConstraintVisibility.visible => engine.ConstraintWidget.VISIBLE,
        ConstraintVisibility.invisible => engine.ConstraintWidget.INVISIBLE,
        ConstraintVisibility.gone => engine.ConstraintWidget.GONE,
      });
      for (final anchor in group.getAnchors()) {
        expect(anchor.isConnected(), isFalse, reason: 'a group has no link');
      }
    }
  });

  testWidgets('a group visibility change in place equals a fresh build', (
    tester,
  ) async {
    // Java J257 (f:groupmember): a (10, 10) 100 x 20, G (0, 0) 0 x 0,
    // k (115, 10) 30 x 20.
    const shown = [
      Rect.fromLTWH(10, 10, 100, 20),
      Rect.fromLTWH(0, 0, 0, 0),
      Rect.fromLTWH(115, 10, 30, 20),
    ];
    // Java J257 (f:groupmember:gone, where the group's visibility reaches
    // its member as a `v` op): a (10, 10) 100 x 20, G: gone, 0 x 0,
    // k: gone, 0 x 0.
    const hidden = [
      Rect.fromLTWH(10, 10, 100, 20),
      Rect.fromLTWH(0, 0, 0, 0),
      Rect.fromLTWH(0, 0, 0, 0),
    ];
    const key = ValueKey('layout');
    ConstraintLayout underTest(ConstraintVisibility visibility) =>
        groupLayout(group: visibility, referenced: const [#k], key: key);
    await tester.pumpWidget(host([underTest(.visible)]));
    final ro = layoutOf(tester, key);
    expect(framesOf(ro), shown);
    final builds = ro.debugModelBuilds;
    final container = ro.debugEngineContainer!;

    for (final (visibility, frames) in const [
      (ConstraintVisibility.gone, hidden),
      (ConstraintVisibility.visible, shown),
      (ConstraintVisibility.invisible, shown),
      (ConstraintVisibility.gone, hidden),
    ]) {
      // The layout under test, changed in place, next to the same
      // configuration built afresh.
      final freshKey = ValueKey('fresh $visibility');
      await tester.pumpWidget(
        host([
          underTest(visibility),
          groupLayout(
            group: visibility,
            referenced: const [#k],
            key: freshKey,
          ),
        ]),
      );
      expect(layoutOf(tester, key), same(ro));
      expect(
        ro.debugModelBuilds,
        builds,
        reason: 'a group visibility change is applied in place',
      );
      expect(ro.debugEngineContainer, same(container));
      expect(framesOf(ro), frames, reason: 'in place, $visibility');
      final fresh = layoutOf(tester, freshKey);
      expect(framesOf(fresh), frames, reason: 'fresh, $visibility');
      expect(
        [for (final w in container.getChildren()) w.getVisibility()],
        [
          for (final w in fresh.debugEngineContainer!.getChildren())
            w.getVisibility(),
        ],
        reason: 'the widgets of both have the same visibility',
      );
    }
  });
}
