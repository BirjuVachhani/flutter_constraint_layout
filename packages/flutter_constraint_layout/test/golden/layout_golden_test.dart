// Golden tests for solved layouts: one image per feature, so a regression in
// the engine shows up as a picture rather than a wall of changed numbers.
//
// These complement the numeric assertions in features_test.dart. Numbers catch
// "this rect moved 2px"; goldens catch "the whole chain collapsed" at a glance,
// and they cover painting paths (visibility, z-order, RTL mirroring) that
// rect assertions cannot see.
//
// Every child is a solid swatch, so the image is the layout. Bootstrap or
// refresh with: flutter test --update-goldens test/golden/
//
// Goldens are generated on macOS with the Flutter version CI pins (see
// .github/workflows/test.yml); raster output differs across platforms.

import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Color kBackground = Color(0xFF12161B);
const Color kBlue = Color(0xFF3B82F6);
const Color kGreen = Color(0xFF22C55E);
const Color kAmber = Color(0xFFF59E0B);
const Color kRed = Color(0xFFEF4444);
const Color kPurple = Color(0xFFA855F7);
const Color kTeal = Color(0xFF14B8A6);

const List<Color> kPalette = [kBlue, kGreen, kAmber, kRed, kPurple, kTeal];

/// A child with no intrinsic size, for match-constraint and fixed dimensions.
Widget fill(Symbol id, Color color) =>
    ColoredBox(key: ValueKey(id), color: color);

/// A child with an intrinsic size, for wrap-content dimensions.
Widget sized(Symbol id, Color color, double width, double height) => SizedBox(
  key: ValueKey(id),
  width: width,
  height: height,
  child: ColoredBox(color: color),
);

/// Text sized for baseline tests. A fixed style keeps the raster stable.
Widget label(Symbol id, String text, double size, Color color) => Text(
  text,
  key: ValueKey(id),
  style: TextStyle(fontSize: size, color: color, height: 1.2),
);

/// Renders [children] in a fixed-size ConstraintLayout on an opaque ground and
/// compares the result to `goldens/[name].png`.
Future<void> expectLayoutGolden(
  WidgetTester tester,
  String name,
  List<Widget> children, {
  Size size = const Size(400, 300),
  TextDirection direction = TextDirection.ltr,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      child: Directionality(
        textDirection: direction,
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            width: size.width,
            height: size.height,
            color: kBackground,
            child: ConstraintLayout(children: children),
          ),
        ),
      ),
    ),
  );
  await expectLater(
    find.byType(RepaintBoundary).first,
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  group('anchoring', () {
    testWidgets('golden: pinned to each parent corner with margins', (
      tester,
    ) async {
      await expectLayoutGolden(tester, 'anchors_corners', [
        Constrained(
          id: #tl,
          start: .startOf(parent, margin: 16),
          top: .topOf(parent, margin: 16),
          width: .fixed(90),
          height: .fixed(50),
          child: fill(#tl, kBlue),
        ),
        Constrained(
          id: #tr,
          end: .endOf(parent, margin: 16),
          top: .topOf(parent, margin: 16),
          width: .fixed(90),
          height: .fixed(50),
          child: fill(#tr, kGreen),
        ),
        Constrained(
          id: #bl,
          start: .startOf(parent, margin: 16),
          bottom: .bottomOf(parent, margin: 16),
          width: .fixed(90),
          height: .fixed(50),
          child: fill(#bl, kAmber),
        ),
        Constrained(
          id: #br,
          end: .endOf(parent, margin: 16),
          bottom: .bottomOf(parent, margin: 16),
          width: .fixed(90),
          height: .fixed(50),
          child: fill(#br, kRed),
        ),
      ]);
    });

    testWidgets('golden: sibling chaining, each below the last', (
      tester,
    ) async {
      await expectLayoutGolden(tester, 'anchors_stacked_siblings', [
        Constrained(
          id: #a,
          start: .startOf(parent, margin: 20),
          top: .topOf(parent, margin: 20),
          width: .fixed(140),
          height: .fixed(44),
          child: fill(#a, kBlue),
        ),
        Constrained(
          id: #b,
          start: .startOf(#a, margin: 24),
          top: .bottomOf(#a, margin: 12),
          width: .fixed(140),
          height: .fixed(44),
          child: fill(#b, kGreen),
        ),
        Constrained(
          id: #c,
          start: .startOf(#b, margin: 24),
          top: .bottomOf(#b, margin: 12),
          width: .fixed(140),
          height: .fixed(44),
          child: fill(#c, kAmber),
        ),
      ]);
    });

    testWidgets('golden: centering and bias', (tester) async {
      await expectLayoutGolden(tester, 'centering_bias', [
        // Centered: opposing links with the default 0.5 bias.
        Constrained(
          id: #center,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
          width: .fixed(100),
          height: .fixed(60),
          child: fill(#center, kBlue),
        ),
        Constrained(
          id: #left,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent, margin: 12),
          horizontalBias: 0.1,
          width: .fixed(70),
          height: .fixed(36),
          child: fill(#left, kGreen),
        ),
        Constrained(
          id: #right,
          start: .startOf(parent),
          end: .endOf(parent),
          bottom: .bottomOf(parent, margin: 12),
          horizontalBias: 0.9,
          width: .fixed(70),
          height: .fixed(36),
          child: fill(#right, kAmber),
        ),
        Constrained(
          id: #high,
          start: .startOf(parent, margin: 12),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
          verticalBias: 0.15,
          width: .fixed(36),
          height: .fixed(70),
          child: fill(#high, kPurple),
        ),
      ]);
    });
  });

  group('chains', () {
    List<Widget> horizontalChain(ChainStyle style) => [
      Constrained(
        id: #a,
        start: .startOf(parent),
        end: .startOf(#b),
        top: .topOf(parent),
        bottom: .bottomOf(parent),
        horizontalChainStyle: style,
        width: .fixed(80),
        height: .fixed(60),
        child: fill(#a, kBlue),
      ),
      Constrained(
        id: #b,
        start: .endOf(#a),
        end: .startOf(#c),
        top: .topOf(#a),
        width: .fixed(80),
        height: .fixed(60),
        child: fill(#b, kGreen),
      ),
      Constrained(
        id: #c,
        start: .endOf(#b),
        end: .endOf(parent),
        top: .topOf(#a),
        width: .fixed(80),
        height: .fixed(60),
        child: fill(#c, kAmber),
      ),
    ];

    for (final style in ChainStyle.values) {
      testWidgets('golden: horizontal chain, ${style.name}', (tester) async {
        await expectLayoutGolden(
          tester,
          'chain_${style.name}',
          horizontalChain(style),
        );
      });
    }

    testWidgets('golden: weighted chain splits leftover space 1:2:1', (
      tester,
    ) async {
      await expectLayoutGolden(tester, 'chain_weighted', [
        Constrained(
          id: #a,
          start: .startOf(parent),
          end: .startOf(#b),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
          horizontalChainStyle: .spread,
          horizontalWeight: 1,
          width: .matchConstraint,
          height: .fixed(80),
          child: fill(#a, kBlue),
        ),
        Constrained(
          id: #b,
          start: .endOf(#a),
          end: .startOf(#c),
          top: .topOf(#a),
          horizontalWeight: 2,
          width: .matchConstraint,
          height: .fixed(80),
          child: fill(#b, kGreen),
        ),
        Constrained(
          id: #c,
          start: .endOf(#b),
          end: .endOf(parent),
          top: .topOf(#a),
          horizontalWeight: 1,
          width: .matchConstraint,
          height: .fixed(80),
          child: fill(#c, kAmber),
        ),
      ]);
    });

    testWidgets('golden: vertical packed chain, biased high', (tester) async {
      await expectLayoutGolden(tester, 'chain_vertical_packed', [
        Constrained(
          id: #a,
          top: .topOf(parent),
          bottom: .topOf(#b),
          start: .startOf(parent),
          end: .endOf(parent),
          verticalChainStyle: .packed,
          verticalBias: 0.2,
          width: .fixed(160),
          height: .fixed(50),
          child: fill(#a, kBlue),
        ),
        Constrained(
          id: #b,
          top: .bottomOf(#a, margin: 8),
          bottom: .topOf(#c),
          start: .startOf(#a),
          width: .fixed(160),
          height: .fixed(50),
          child: fill(#b, kGreen),
        ),
        Constrained(
          id: #c,
          top: .bottomOf(#b, margin: 8),
          bottom: .bottomOf(parent),
          start: .startOf(#a),
          width: .fixed(160),
          height: .fixed(50),
          child: fill(#c, kAmber),
        ),
      ]);
    });
  });

  group('helpers', () {
    testWidgets('golden: guidelines by percent, begin, and end', (
      tester,
    ) async {
      await expectLayoutGolden(tester, 'guidelines', [
        const Guideline.vertical(id: #third, percent: 0.33),
        const Guideline.vertical(id: #fromEnd, end: 60),
        const Guideline.horizontal(id: #fromTop, begin: 80),
        Constrained(
          id: #a,
          start: .startOf(parent),
          end: .leftOf(#third),
          top: .topOf(parent),
          bottom: .topOf(#fromTop),
          width: .matchConstraint,
          height: .matchConstraint,
          child: fill(#a, kBlue),
        ),
        Constrained(
          id: #b,
          start: .rightOf(#third, margin: 8),
          end: .leftOf(#fromEnd, margin: 8),
          top: .bottomOf(#fromTop, margin: 8),
          width: .matchConstraint,
          height: .fixed(60),
          child: fill(#b, kGreen),
        ),
        Constrained(
          id: #c,
          start: .rightOf(#fromEnd),
          end: .endOf(parent),
          top: .bottomOf(#fromTop, margin: 8),
          bottom: .bottomOf(parent, margin: 8),
          width: .matchConstraint,
          height: .matchConstraint,
          child: fill(#c, kAmber),
        ),
      ]);
    });

    testWidgets('golden: barrier tracks the widest of a group', (tester) async {
      await expectLayoutGolden(tester, 'barrier_end', [
        Constrained(
          id: #short,
          start: .startOf(parent, margin: 12),
          top: .topOf(parent, margin: 12),
          width: .fixed(60),
          height: .fixed(40),
          child: fill(#short, kBlue),
        ),
        Constrained(
          id: #long,
          start: .startOf(parent, margin: 12),
          top: .bottomOf(#short, margin: 8),
          width: .fixed(150),
          height: .fixed(40),
          child: fill(#long, kGreen),
        ),
        Constrained(
          id: #mid,
          start: .startOf(parent, margin: 12),
          top: .bottomOf(#long, margin: 8),
          width: .fixed(100),
          height: .fixed(40),
          child: fill(#mid, kAmber),
        ),
        const Barrier(
          id: #widest,
          edge: .end,
          referenced: [#short, #long, #mid],
        ),
        // Clears whichever label is widest, without knowing which that is.
        Constrained(
          id: #value,
          start: .rightOf(#widest, margin: 16),
          end: .endOf(parent, margin: 12),
          top: .topOf(#short),
          bottom: .bottomOf(#mid),
          width: .matchConstraint,
          height: .matchConstraint,
          child: fill(#value, kPurple),
        ),
      ]);
    });

    testWidgets('golden: bottom barrier over a ragged row', (tester) async {
      await expectLayoutGolden(tester, 'barrier_bottom', [
        for (final (i, height) in const [40.0, 90.0, 60.0].indexed)
          Constrained(
            id: Symbol('c$i'),
            start: i == 0
                ? .startOf(parent, margin: 16)
                : .endOf(Symbol('c${i - 1}'), margin: 10),
            top: .topOf(parent, margin: 16),
            width: .fixed(90),
            height: .fixed(height),
            child: fill(Symbol('c$i'), kPalette[i]),
          ),
        const Barrier(
          id: #below,
          edge: .bottom,
          referenced: [#c0, #c1, #c2],
          margin: 12,
        ),
        Constrained(
          id: #footer,
          start: .startOf(parent, margin: 16),
          end: .endOf(parent, margin: 16),
          top: .bottomOf(#below),
          width: .matchConstraint,
          height: .fixed(44),
          child: fill(#footer, kTeal),
        ),
      ]);
    });

    testWidgets('golden: circular positioning around a hub', (tester) async {
      await expectLayoutGolden(tester, 'circular_dial', [
        Constrained(
          id: #hub,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
          width: .fixed(40),
          height: .fixed(40),
          child: fill(#hub, kBlue),
        ),
        for (var i = 0; i < 8; i++)
          Constrained(
            id: Symbol('s$i'),
            circle: .around(#hub, angle: i * 45, radius: 100),
            width: .fixed(28),
            height: .fixed(28),
            child: fill(Symbol('s$i'), kPalette[i % kPalette.length]),
          ),
      ]);
    });
  });

  group('dimensions', () {
    testWidgets('golden: percent, spread bounds, and match parent', (
      tester,
    ) async {
      await expectLayoutGolden(tester, 'dimensions_modes', [
        // 50% of the parent width.
        Constrained(
          id: #half,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent, margin: 10),
          width: .percent(0.5),
          height: .fixed(40),
          child: fill(#half, kBlue),
        ),
        // Spread, but capped well under the available span.
        Constrained(
          id: #capped,
          start: .startOf(parent, margin: 10),
          end: .endOf(parent, margin: 10),
          top: .bottomOf(#half, margin: 10),
          width: .spread(max: 160),
          height: .fixed(40),
          child: fill(#capped, kGreen),
        ),
        // Spread with a floor larger than the span it was given.
        Constrained(
          id: #floored,
          start: .startOf(parent, margin: 140),
          end: .endOf(parent, margin: 140),
          top: .bottomOf(#capped, margin: 10),
          width: .spread(min: 200),
          height: .fixed(40),
          child: fill(#floored, kAmber),
        ),
        // Content-sized, but never wider than its span.
        Constrained(
          id: #wrapped,
          start: .startOf(parent, margin: 10),
          end: .endOf(parent, margin: 10),
          top: .bottomOf(#floored, margin: 10),
          width: .constrainedWrap(max: 120),
          height: .fixed(40),
          child: sized(#wrapped, kRed, 300, 40),
        ),
        Constrained(
          id: #full,
          top: .bottomOf(#wrapped, margin: 10),
          width: .matchParent,
          height: .fixed(30),
          child: fill(#full, kPurple),
        ),
      ]);
    });

    testWidgets('golden: aspect ratio fits a box to its span', (tester) async {
      // A ratio needs both axes on match-constraint and both pairs of anchors:
      // it then fits the largest box of that shape inside the span, so the
      // free axis is the one with slack. A guideline splits the two cases.
      await expectLayoutGolden(tester, 'aspect_ratio', [
        const Guideline.horizontal(id: #split, percent: 0.5),
        // Wide span, so height is the derived axis.
        Constrained(
          id: #wide,
          start: .startOf(parent, margin: 12),
          end: .endOf(parent, margin: 12),
          top: .topOf(parent, margin: 12),
          bottom: .topOf(#split, margin: 6),
          width: .matchConstraint,
          height: .matchConstraint,
          aspectRatio: 16 / 9,
          child: fill(#wide, kBlue),
        ),
        // Square in the lower half.
        Constrained(
          id: #square,
          start: .startOf(parent, margin: 12),
          end: .endOf(parent, margin: 12),
          top: .bottomOf(#split, margin: 6),
          bottom: .bottomOf(parent, margin: 12),
          width: .matchConstraint,
          height: .matchConstraint,
          aspectRatio: 1,
          child: fill(#square, kGreen),
        ),
      ]);
    });

    testWidgets('golden: wrap content sizes to the child', (tester) async {
      await expectLayoutGolden(tester, 'dimensions_wrap_content', [
        Constrained(
          id: #a,
          start: .startOf(parent, margin: 16),
          top: .topOf(parent, margin: 16),
          child: sized(#a, kBlue, 120, 44),
        ),
        Constrained(
          id: #b,
          start: .endOf(#a, margin: 16),
          top: .topOf(#a),
          child: sized(#b, kGreen, 60, 80),
        ),
        Constrained(
          id: #c,
          start: .startOf(#a),
          top: .bottomOf(#b, margin: 16),
          child: sized(#c, kAmber, 200, 30),
        ),
      ]);
    });
  });

  group('visibility', () {
    List<Widget> row(ConstraintVisibility middle) => [
      Constrained(
        id: #a,
        start: .startOf(parent, margin: 16),
        top: .topOf(parent, margin: 16),
        width: .fixed(80),
        height: .fixed(60),
        child: fill(#a, kBlue),
      ),
      Constrained(
        id: #b,
        start: .endOf(#a, margin: 12),
        top: .topOf(#a),
        width: .fixed(80),
        height: .fixed(60),
        visibility: middle,
        child: fill(#b, kGreen),
      ),
      // The gone margin replaces the normal one when #b collapses.
      Constrained(
        id: #c,
        start: .endOf(#b, margin: 12, goneMargin: 40),
        top: .topOf(#a),
        width: .fixed(80),
        height: .fixed(60),
        child: fill(#c, kAmber),
      ),
    ];

    for (final visibility in ConstraintVisibility.values) {
      testWidgets('golden: middle child ${visibility.name}', (tester) async {
        await expectLayoutGolden(
          tester,
          'visibility_${visibility.name}',
          row(visibility),
          size: const Size(400, 120),
        );
      });
    }
  });

  group('direction', () {
    List<Widget> startEndLayout() => [
      Constrained(
        id: #leading,
        start: .startOf(parent, margin: 16),
        top: .topOf(parent, margin: 16),
        width: .fixed(70),
        height: .fixed(50),
        child: fill(#leading, kBlue),
      ),
      Constrained(
        id: #next,
        start: .endOf(#leading, margin: 12),
        top: .topOf(#leading),
        width: .fixed(70),
        height: .fixed(50),
        child: fill(#next, kGreen),
      ),
      // Absolute left/right ignore direction, so this one should not mirror.
      Constrained(
        id: #absolute,
        left: .leftOf(parent, margin: 16),
        top: .bottomOf(#leading, margin: 16),
        width: .fixed(70),
        height: .fixed(50),
        child: fill(#absolute, kAmber),
      ),
    ];

    testWidgets('golden: start/end anchors in LTR', (tester) async {
      await expectLayoutGolden(
        tester,
        'direction_ltr',
        startEndLayout(),
        size: const Size(400, 160),
      );
    });

    testWidgets('golden: start/end anchors mirror in RTL', (tester) async {
      await expectLayoutGolden(
        tester,
        'direction_rtl',
        startEndLayout(),
        size: const Size(400, 160),
        direction: TextDirection.rtl,
      );
    });
  });

  group('virtual layouts', () {
    List<Widget> flowChildren(int count) => [
      for (var i = 0; i < count; i++)
        Constrained(
          id: Symbol('f$i'),
          width: .fixed(70),
          height: .fixed(34),
          child: fill(Symbol('f$i'), kPalette[i % kPalette.length]),
        ),
    ];

    for (final wrap in FlowWrap.values) {
      testWidgets('golden: flow wrap ${wrap.name}', (tester) async {
        await expectLayoutGolden(tester, 'flow_${wrap.name}', [
          ...flowChildren(7),
          ConstraintFlow(
            id: #flow,
            referenced: const [#f0, #f1, #f2, #f3, #f4, #f5, #f6],
            start: .startOf(parent, margin: 12),
            end: .endOf(parent, margin: 12),
            top: .topOf(parent, margin: 12),
            width: .matchConstraint,
            wrap: wrap,
            horizontalGap: 10,
            verticalGap: 10,
            horizontalChainStyle: .packed,
          ),
        ]);
      });
    }

    testWidgets('golden: vertical flow wraps into columns', (tester) async {
      await expectLayoutGolden(tester, 'flow_vertical', [
        ...flowChildren(6),
        ConstraintFlow(
          id: #flow,
          referenced: const [#f0, #f1, #f2, #f3, #f4, #f5],
          orientation: Axis.vertical,
          start: .startOf(parent, margin: 12),
          top: .topOf(parent, margin: 12),
          bottom: .bottomOf(parent, margin: 12),
          height: .matchConstraint,
          wrap: .chain,
          horizontalGap: 10,
          verticalGap: 10,
        ),
      ]);
    });

    testWidgets('golden: flow aligns rows to the top', (tester) async {
      await expectLayoutGolden(tester, 'flow_align_top', [
        for (var i = 0; i < 5; i++)
          Constrained(
            id: Symbol('f$i'),
            width: .fixed(70),
            // Ragged heights make the cross-axis alignment visible.
            height: .fixed(i.isEven ? 30.0 : 60.0),
            child: fill(Symbol('f$i'), kPalette[i % kPalette.length]),
          ),
        ConstraintFlow(
          id: #flow,
          referenced: const [#f0, #f1, #f2, #f3, #f4],
          start: .startOf(parent, margin: 12),
          end: .endOf(parent, margin: 12),
          top: .topOf(parent, margin: 12),
          width: .matchConstraint,
          wrap: .chain,
          horizontalGap: 10,
          verticalGap: 10,
          verticalAlign: .top,
        ),
      ]);
    });

    testWidgets('golden: grid fills cells row by row', (tester) async {
      await expectLayoutGolden(tester, 'grid_basic', [
        for (var i = 0; i < 6; i++)
          Constrained(
            id: Symbol('g$i'),
            width: .fixed(60),
            height: .fixed(40),
            child: fill(Symbol('g$i'), kPalette[i % kPalette.length]),
          ),
        ConstraintGrid(
          id: #grid,
          referenced: const [#g0, #g1, #g2, #g3, #g4, #g5],
          rows: 2,
          columns: 3,
          start: .startOf(parent, margin: 16),
          end: .endOf(parent, margin: 16),
          top: .topOf(parent, margin: 16),
          bottom: .bottomOf(parent, margin: 16),
          horizontalGap: 8,
          verticalGap: 8,
        ),
      ]);
    });

    testWidgets('golden: grid with spans and skips', (tester) async {
      await expectLayoutGolden(tester, 'grid_spans_skips', [
        for (var i = 0; i < 4; i++)
          Constrained(
            id: Symbol('g$i'),
            width: .matchConstraint,
            height: .matchConstraint,
            child: fill(Symbol('g$i'), kPalette[i % kPalette.length]),
          ),
        ConstraintGrid(
          id: #grid,
          referenced: const [#g0, #g1, #g2, #g3],
          rows: 3,
          columns: 3,
          // The first cell covers a 1x2 block; cell 4 is left empty.
          spans: '0:1x2',
          skips: '4:1x1',
          start: .startOf(parent, margin: 16),
          end: .endOf(parent, margin: 16),
          top: .topOf(parent, margin: 16),
          bottom: .bottomOf(parent, margin: 16),
          horizontalGap: 6,
          verticalGap: 6,
        ),
      ]);
    });

    testWidgets('golden: grid with uneven row and column weights', (
      tester,
    ) async {
      await expectLayoutGolden(tester, 'grid_weights', [
        for (var i = 0; i < 4; i++)
          Constrained(
            id: Symbol('g$i'),
            width: .matchConstraint,
            height: .matchConstraint,
            child: fill(Symbol('g$i'), kPalette[i % kPalette.length]),
          ),
        ConstraintGrid(
          id: #grid,
          referenced: const [#g0, #g1, #g2, #g3],
          rows: 2,
          columns: 2,
          rowWeights: const [1, 3],
          columnWeights: const [2, 1],
          start: .startOf(parent, margin: 16),
          end: .endOf(parent, margin: 16),
          top: .topOf(parent, margin: 16),
          bottom: .bottomOf(parent, margin: 16),
          horizontalGap: 6,
          verticalGap: 6,
        ),
      ]);
    });
  });

  group('baselines', () {
    testWidgets('golden: text of different sizes shares a baseline', (
      tester,
    ) async {
      await expectLayoutGolden(
        tester,
        'baseline_align',
        [
          Constrained(
            id: #big,
            start: .startOf(parent, margin: 16),
            top: .topOf(parent, margin: 40),
            child: label(#big, 'Ag', 42, kBlue),
          ),
          Constrained(
            id: #mid,
            start: .endOf(#big, margin: 12),
            baseline: .baselineOf(#big),
            child: label(#mid, 'Ag', 26, kGreen),
          ),
          Constrained(
            id: #small,
            start: .endOf(#mid, margin: 12),
            baseline: .baselineOf(#big),
            child: label(#small, 'Ag', 14, kAmber),
          ),
        ],
        size: const Size(400, 140),
      );
    });
  });

  group('composition', () {
    testWidgets('golden: a constraint layout nested in another', (
      tester,
    ) async {
      await expectLayoutGolden(tester, 'nested_layouts', [
        Constrained(
          id: #outer,
          start: .startOf(parent, margin: 20),
          end: .endOf(parent, margin: 20),
          top: .topOf(parent, margin: 20),
          bottom: .bottomOf(parent, margin: 20),
          width: .matchConstraint,
          height: .matchConstraint,
          child: ColoredBox(
            key: const ValueKey(#outer),
            color: const Color(0xFF1E2732),
            child: ConstraintLayout(
              children: [
                Constrained(
                  id: #inner1,
                  start: .startOf(parent, margin: 10),
                  top: .topOf(parent, margin: 10),
                  width: .fixed(80),
                  height: .fixed(50),
                  child: fill(#inner1, kBlue),
                ),
                Constrained(
                  id: #inner2,
                  end: .endOf(parent, margin: 10),
                  bottom: .bottomOf(parent, margin: 10),
                  width: .fixed(80),
                  height: .fixed(50),
                  child: fill(#inner2, kGreen),
                ),
                Constrained(
                  id: #inner3,
                  start: .startOf(parent),
                  end: .endOf(parent),
                  top: .topOf(parent),
                  bottom: .bottomOf(parent),
                  width: .fixed(60),
                  height: .fixed(60),
                  child: fill(#inner3, kAmber),
                ),
              ],
            ),
          ),
        ),
      ]);
    });

    testWidgets('golden: zIndex paints a lower child on top', (tester) async {
      await expectLayoutGolden(
        tester,
        'z_index',
        [
          Constrained(
            id: #back,
            start: .startOf(parent, margin: 20),
            top: .topOf(parent, margin: 20),
            width: .fixed(140),
            height: .fixed(90),
            // Declared first but painted last.
            zIndex: 10,
            child: fill(#back, kBlue),
          ),
          Constrained(
            id: #front,
            start: .startOf(parent, margin: 90),
            top: .topOf(parent, margin: 50),
            width: .fixed(140),
            height: .fixed(90),
            child: fill(#front, kAmber),
          ),
        ],
        size: const Size(300, 180),
      );
    });
  });

  group('edge cases', () {
    testWidgets('golden: no children at all', (tester) async {
      await expectLayoutGolden(
        tester,
        'edge_empty',
        const [],
        size: const Size(200, 100),
      );
    });

    testWidgets('golden: unconstrained child sits at the origin', (
      tester,
    ) async {
      await expectLayoutGolden(
        tester,
        'edge_unconstrained',
        [
          Constrained(id: #a, child: sized(#a, kBlue, 90, 40)),
          Constrained(
            id: #b,
            width: .fixed(60),
            height: .fixed(60),
            child: fill(#b, kGreen),
          ),
        ],
        size: const Size(200, 120),
      );
    });

    testWidgets('golden: fixed child wider than its span overflows evenly', (
      tester,
    ) async {
      await expectLayoutGolden(
        tester,
        'edge_oversized_child',
        [
          // Both edges pinned but the width is fixed and too big: the bias
          // splits the overflow instead of clipping to one side.
          Constrained(
            id: #wide,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent, margin: 10),
            width: .fixed(280),
            height: .fixed(40),
            child: fill(#wide, kBlue),
          ),
          Constrained(
            id: #tall,
            start: .startOf(parent, margin: 10),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
            width: .fixed(40),
            height: .fixed(200),
            child: fill(#tall, kGreen),
          ),
        ],
        size: const Size(200, 120),
      );
    });

    testWidgets('golden: a chain of one behaves like a centered child', (
      tester,
    ) async {
      await expectLayoutGolden(
        tester,
        'edge_single_chain',
        [
          Constrained(
            id: #only,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
            horizontalChainStyle: .packed,
            width: .fixed(80),
            height: .fixed(40),
            child: fill(#only, kBlue),
          ),
        ],
        size: const Size(200, 100),
      );
    });

    testWidgets('golden: barrier over an entirely gone group', (tester) async {
      await expectLayoutGolden(
        tester,
        'edge_barrier_all_gone',
        [
          Constrained(
            id: #a,
            start: .startOf(parent, margin: 16),
            top: .topOf(parent, margin: 16),
            width: .fixed(80),
            height: .fixed(40),
            visibility: .gone,
            child: fill(#a, kBlue),
          ),
          const Barrier(id: #bar, edge: .end, referenced: [#a]),
          Constrained(
            id: #after,
            start: .rightOf(#bar, margin: 8),
            top: .topOf(parent, margin: 16),
            width: .fixed(80),
            height: .fixed(40),
            child: fill(#after, kGreen),
          ),
        ],
        size: const Size(240, 100),
      );
    });

    testWidgets('golden: zero-area parent lays out without throwing', (
      tester,
    ) async {
      await expectLayoutGolden(
        tester,
        'edge_zero_size_parent',
        [
          Constrained(
            id: #a,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            width: .matchConstraint,
            height: .fixed(20),
            child: fill(#a, kBlue),
          ),
        ],
        size: Size.zero,
      );
    });
  });
}
