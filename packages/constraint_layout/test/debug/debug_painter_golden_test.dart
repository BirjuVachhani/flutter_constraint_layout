// Golden tests for the debug-scene painter. Each test pumps a real layout,
// extracts its DebugScene, then paints that scene through a harness
// CustomPainter inside a RepaintBoundary and compares pixels.
//
// Bootstrap or refresh with: flutter test --update-goldens test/debug/

import 'package:constraint_layout/constraint_layout.dart';
import 'package:constraint_layout/src/debug/debug_painter.dart';
import 'package:constraint_layout/src/debug/debug_palette.dart';
import 'package:constraint_layout/src/debug/debug_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(List<Widget> children) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 800,
          height: 600,
          child: ConstraintLayout(children: children),
        ),
      ),
    );

class _SceneHarness extends CustomPainter {
  const _SceneHarness(this.scene, this.palette, this.blueprint,
      [this.labelStyle = DebugLabelStyle.both]);

  final DebugScene scene;
  final DebugPalette palette;
  final bool blueprint;
  final DebugLabelStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) => paintDebugScene(
        canvas,
        Offset.zero,
        size,
        scene,
        palette,
        blueprint: blueprint,
        labelStyle: labelStyle,
      );

  @override
  bool shouldRepaint(covariant _SceneHarness oldDelegate) => true;
}

Future<void> pumpScenePainting(
  WidgetTester tester,
  List<Widget> children, {
  required DebugPalette palette,
  required bool blueprint,
  DebugLabelStyle labelStyle = DebugLabelStyle.both,
}) async {
  await tester.pumpWidget(host(children));
  final scene = tester
      .renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout))
      .debugDescribeScene();
  await tester.pumpWidget(
    RepaintBoundary(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 800,
            height: 600,
            child: CustomPaint(
              foregroundPainter:
                  _SceneHarness(scene, palette, blueprint, labelStyle),
              // Opaque base under the overlay so goldens are stable in
              // chains mode.
              child: Container(color: const Color(0xFFFFFFFF)),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget box(Symbol id) => SizedBox(key: ValueKey(id));

List<Widget> chainRow() => [
      Constrained(
        id: #a,
        start: .startOf(parent, margin: 16),
        end: .startOf(#b),
        top: .topOf(parent, margin: 60),
        width: .fixed(120),
        height: .fixed(60),
        child: box(#a),
      ),
      Constrained(
        id: #b,
        start: .endOf(#a),
        end: .startOf(#c),
        top: .topOf(#a),
        width: .fixed(120),
        height: .fixed(60),
        child: box(#b),
      ),
      Constrained(
        id: #c,
        start: .endOf(#b),
        end: .endOf(parent, margin: 16),
        top: .topOf(#a),
        width: .fixed(120),
        height: .fixed(60),
        child: box(#c),
      ),
    ];

List<Widget> biasRow() => [
      Constrained(
        id: #floating,
        start: .startOf(parent, margin: 24),
        end: .leftOf(#anchor),
        top: .topOf(parent, margin: 200),
        width: .fixed(140),
        height: .fixed(70),
        horizontalBias: 0.25,
        child: box(#floating),
      ),
      Constrained(
        id: #anchor,
        end: .endOf(parent, margin: 24),
        top: .topOf(parent, margin: 200),
        width: .fixed(140),
        height: .fixed(70),
        child: box(#anchor),
      ),
    ];

/// A representative blueprint layout: a guideline, two labeled boxes in a
/// chain, and a one-sided margin link.
List<Widget> blueprintLayout() => [
      const Guideline.vertical(id: #split, percent: 0.3),
      Constrained(
        id: #photo,
        start: .startOf(parent, margin: 24),
        end: .startOf(#title),
        top: .topOf(parent, margin: 48),
        width: .fixed(160),
        height: .fixed(120),
        child: Container(key: const ValueKey(#photo)),
      ),
      Constrained(
        id: #title,
        start: .endOf(#photo, margin: 16),
        end: .endOf(parent, margin: 24),
        top: .topOf(#photo),
        width: .fixed(200),
        height: .fixed(60),
        child: const Text('Title', key: ValueKey(#title)),
      ),
      Constrained(
        id: #caption,
        start: .rightOf(#split, margin: 12),
        top: .bottomOf(#photo, margin: 32),
        width: .fixed(240),
        height: .fixed(48),
        child: const Text('Caption', key: ValueKey(#caption)),
      ),
    ];

List<Widget> helpersLayout() => [
      const Guideline.vertical(id: #g, percent: 0.25),
      Constrained(
        id: #a,
        start: .rightOf(#g, margin: 8),
        top: .topOf(parent, margin: 24),
        width: .fixed(120),
        height: .fixed(48),
        child: box(#a),
      ),
      Constrained(
        id: #b,
        start: .endOf(#a, margin: 12),
        top: .topOf(parent, margin: 24),
        width: .fixed(120),
        height: .fixed(72),
        child: box(#b),
      ),
      Barrier(id: #bar, edge: .bottom, referenced: const [#a, #b], margin: 16),
      Constrained(
        id: #below,
        start: .rightOf(#g, margin: 8),
        top: .bottomOf(#bar, margin: 8),
        width: .fixed(180),
        height: .fixed(40),
        child: box(#below),
      ),
      for (final id in const [#f1, #f2, #f3])
        Constrained(id: id, width: .fixed(90), height: .fixed(36), child: box(id)),
      ConstraintFlow(
        id: #flow,
        referenced: const [#f1, #f2, #f3],
        start: .startOf(parent, margin: 24),
        end: .endOf(parent, margin: 24),
        top: .bottomOf(#below, margin: 32),
        width: .matchConstraint,
        horizontalChainStyle: ChainStyle.packed,
        horizontalGap: 8,
      ),
      for (final id in const [#g1, #g2, #g3, #g4])
        Constrained(
          id: id,
          width: .fixed(30),
          height: .fixed(30),
          child: box(id),
        ),
      ConstraintGrid(
        id: #grid,
        referenced: const [#g1, #g2, #g3, #g4],
        rows: 2,
        columns: 2,
        start: .startOf(parent, margin: 24),
        end: .endOf(parent, margin: 24),
        top: .bottomOf(#flow, margin: 32),
        bottom: .bottomOf(parent, margin: 24),
      ),
    ];

void main() {
  testWidgets('golden: chain row in design (chains) palette', (tester) async {
    await pumpScenePainting(
      tester,
      chainRow(),
      palette: const DebugPalette.design(),
      blueprint: false,
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/chains_chain_row.png'),
    );
  });

  testWidgets('golden: biased spring pair in design palette', (tester) async {
    await pumpScenePainting(
      tester,
      biasRow(),
      palette: const DebugPalette.design(),
      blueprint: false,
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/chains_bias_spring.png'),
    );
  });

  for (final style in DebugLabelStyle.values) {
    testWidgets('golden: blueprint with label style ${style.name}',
        (tester) async {
      await pumpScenePainting(
        tester,
        blueprintLayout(),
        palette: const DebugPalette.blueprint(),
        blueprint: true,
        labelStyle: style,
      );
      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('goldens/blueprint_${style.name}.png'),
      );
    });
  }

  testWidgets('golden: blueprint helpers (guideline, barrier, flow, grid)',
      (tester) async {
    await pumpScenePainting(
      tester,
      helpersLayout(),
      palette: const DebugPalette.blueprint(),
      blueprint: true,
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/blueprint_helpers.png'),
    );
  });

  testWidgets('golden: tinted chains palette', (tester) async {
    await pumpScenePainting(
      tester,
      chainRow(),
      palette: DebugPalette.tinted(const Color(0xFFFF4081), blueprint: false),
      blueprint: false,
    );
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/chains_tinted.png'),
    );
  });
}
