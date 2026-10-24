// End-to-end tests for the debug flags on the real widget: toggling is
// paint-only (no layout, no engine work), blueprint hides children while
// keeping them hit-testable, and the overlay renders over real children.
//
// Bootstrap or refresh goldens with: flutter test --update-goldens test/debug/

import 'package:constraint_layout/constraint_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  List<Widget> children, {
  bool chains = false,
  bool blueprint = false,
  Color? tint,
}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          child: SizedBox(
            width: 800,
            height: 600,
            child: ConstraintLayout(
              debugShowChains: chains,
              debugShowBlueprint: blueprint,
              debugChainColor: tint,
              children: children,
            ),
          ),
        ),
      ),
    );

List<Widget> chainRow({required Color color}) => [
      for (final (i, id) in const [#a, #b, #c].indexed)
        Constrained(
          id: id,
          start: i == 0
              ? HorizontalLink.startOf(parent, margin: 16)
              : HorizontalLink.endOf(const [#a, #b, #c][i - 1]),
          end: i == 2
              ? HorizontalLink.endOf(parent, margin: 16)
              : HorizontalLink.startOf(const [#a, #b, #c][i + 1]),
          top: i == 0
              ? const VerticalLink.topOf(parent, margin: 60)
              : const VerticalLink.topOf(#a),
          width: .fixed(120),
          height: .fixed(60),
          child: Container(key: ValueKey(id), color: color),
        ),
    ];

void main() {
  testWidgets('toggling debug flags never re-runs layout or the engine',
      (tester) async {
    await tester.pumpWidget(host(chainRow(color: const Color(0xFF2196F3))));
    final ro = tester
        .renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout));
    final layouts = ro.debugLayoutPasses;
    final builds = ro.debugModelBuilds;
    final engine = ro.debugEnginePasses;
    final applies = ro.debugConfigApplies;
    final before = tester.getRect(find.byKey(const ValueKey(#b)));

    await tester
        .pumpWidget(host(chainRow(color: const Color(0xFF2196F3)), chains: true));
    await tester.pumpWidget(host(
      chainRow(color: const Color(0xFF2196F3)),
      blueprint: true,
      tint: const Color(0xFFFF4081),
    ));

    expect(ro.debugLayoutPasses, layouts, reason: 'paint-only toggles');
    expect(ro.debugModelBuilds, builds);
    expect(ro.debugEnginePasses, engine);
    expect(ro.debugConfigApplies, applies);
    expect(tester.getRect(find.byKey(const ValueKey(#b))), before);
  });

  testWidgets('children stay hit-testable in blueprint mode', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(host([
      Constrained(
        id: #button,
        start: .startOf(parent, margin: 100),
        top: .topOf(parent, margin: 100),
        width: .fixed(120),
        height: .fixed(48),
        child: GestureDetector(
          key: const ValueKey(#button),
          onTap: () => log.add('tap'),
          child: Container(color: const Color(0xFF4CAF50)),
        ),
      ),
    ], blueprint: true));
    await tester.tapAt(const Offset(160, 124));
    expect(log, ['tap']);
  });

  testWidgets('golden: chains overlay paints over the real children',
      (tester) async {
    await tester.pumpWidget(
        host(chainRow(color: const Color(0xFF90CAF9)), chains: true));
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/e2e_chains_overlay.png'),
    );
  });

  testWidgets('golden: blueprint hides the children entirely', (tester) async {
    // The children paint saturated red; the golden must contain none of it.
    await tester.pumpWidget(
        host(chainRow(color: const Color(0xFFFF0000)), blueprint: true));
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/e2e_blueprint_hides_children.png'),
    );
  });
}
