import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the measure ordering for content whose size on one axis depends on
/// its resolved size on the other (the classic case: wrapping text, whose
/// height depends on its width).
///
/// The trap: a `matchConstraint` width is resolved by the solver, not measured,
/// so a `wrapContent` height must be measured *after* that width is known. If it
/// is measured first (at width 0) the text wraps one word per line and the child
/// comes out absurdly tall. This slipped through once because every existing
/// widget test ran under a *bounded* container height and used width-independent
/// children; the bug only fires under an unbounded height. So each case here is
/// run under BOTH a bounded and an unbounded container height, and every
/// expectation is an *oracle*: the same child laid out directly at the width the
/// ConstraintLayout is expected to give it. No hand-computed pixels.
///
/// A `constrainedWrap` size sets the same trap from the other side: it is
/// measured around its content and only then capped by the solver, so the other
/// axis must be measured *again* at the capped size. Otherwise the child keeps
/// the height its text took at the uncapped width, and the text is clipped.
///
/// The measures themselves are Android's view measurer's (the request
/// transcripts of these layouts are checked against VOpDriver in
/// measurer_spec_test.dart). A measured size is rounded up to whole pixels
/// (see "Whole pixels" in the README), and every child is placed at its
/// whole-pixel frame, so the oracles here use a font size whose text metrics
/// are whole pixels, and the last group checks the rounding with one whose
/// metrics are not.
void main() {
  const style = TextStyle(fontSize: 14);
  const longText =
      'A much longer description that will certainly wrap onto several lines '
      'within a narrow column, so its height depends on the resolved width.';

  /// Pumps [layout] as the child of a box that is [width] wide and either
  /// [height] tall (bounded) or unbounded (wrapped in a scroll view).
  Future<void> pump(
    WidgetTester tester,
    Widget layout, {
    required double width,
    double? height,
  }) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: height,
            child: height == null
                ? SingleChildScrollView(child: layout)
                : layout,
          ),
        ),
      ),
    );
  }

  /// Ground truth: the natural size of [child] laid out at exactly [width].
  Future<Size> oracleSize(
    WidgetTester tester,
    Widget child,
    double width,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: KeyedSubtree(key: const Key('oracle'), child: child),
          ),
        ),
      ),
    );
    return tester.getSize(find.byKey(const Key('oracle')));
  }

  /// Ground truth: the natural size of [child] under loose constraints.
  Future<Size> naturalSize(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: KeyedSubtree(key: const Key('oracle'), child: child),
        ),
      ),
    );
    return tester.getSize(find.byKey(const Key('oracle')));
  }

  for (final bounded in [true, false]) {
    final label = bounded ? 'bounded height' : 'unbounded height';

    testWidgets('matchConstraint width + wrapContent height measures wrapping '
        'text at the resolved width ($label)', (tester) async {
      // Container 340 wide, text inset 20 each side -> resolved width 300.
      const containerWidth = 340.0;
      const margin = 20.0;
      const resolvedWidth = containerWidth - 2 * margin;

      final oracle = await oracleSize(
        tester,
        const Text(longText, style: style),
        resolvedWidth,
      );

      await pump(
        tester,
        ConstraintLayout(
          children: [
            Constrained(
              id: #t,
              top: .topOf(parent),
              left: .leftOf(parent, margin: margin),
              right: .rightOf(parent, margin: margin),
              width: .matchConstraint,
              height: .wrapContent,
              child: const Text(longText, key: Key('t'), style: style),
            ),
          ],
        ),
        width: containerWidth,
        height: bounded ? 600 : null,
      );

      expect(
        tester.getSize(find.byKey(const Key('t'))),
        oracle,
        reason: 'child must be measured at its resolved width, not width 0',
      );
    });

    testWidgets('a bottom Barrier settles on the true wrapped height of the '
        'tallest match-width child ($label)', (tester) async {
      // Two match-width columns split by a center guideline; the taller text
      // drives a shared barrier that a follower box hangs from. If either text
      // is measured at width 0, the barrier lands far below its real position.
      const containerWidth = 640.0;
      const margin = 16.0;
      // Column inner width: half the container, less the outer/center margins.
      const columnWidth = containerWidth / 2 - margin - margin;

      final oracle = await oracleSize(
        tester,
        const Text(longText, style: style),
        columnWidth,
      );

      await pump(
        tester,
        ConstraintLayout(
          children: [
            Guideline.vertical(id: #mid, percent: 0.5),
            Constrained(
              id: #a,
              top: .topOf(parent),
              left: .leftOf(parent, margin: margin),
              right: .leftOf(#mid, margin: margin),
              width: .matchConstraint,
              height: .wrapContent,
              child: const Text(longText, key: Key('a'), style: style),
            ),
            Constrained(
              id: #b,
              top: .topOf(parent),
              left: .rightOf(#mid, margin: margin),
              right: .rightOf(parent, margin: margin),
              width: .matchConstraint,
              height: .wrapContent,
              child: const Text('Short.', key: Key('b'), style: style),
            ),
            Barrier(id: #bar, edge: .bottom, referenced: [#a, #b]),
            Constrained(
              id: #follower,
              top: .bottomOf(#bar),
              left: .leftOf(parent),
              width: .fixed(10),
              height: .fixed(10),
              child: const SizedBox(key: Key('follower')),
            ),
          ],
        ),
        width: containerWidth,
        height: bounded ? 600 : null,
      );

      // The tall column defines the barrier; the follower sits right below it.
      expect(tester.getSize(find.byKey(const Key('a'))).height, oracle.height);
      expect(
        tester.getTopLeft(find.byKey(const Key('follower'))).dy,
        oracle.height,
      );
    });

    testWidgets('stretch-to-barrier cards in a row share the tallest height '
        '($label)', (tester) async {
      // The features-grid pattern: per card a wrapContent-height content box
      // drives a shared bottom barrier, and a match-height surface stretches
      // down to it. Both surfaces must end up the same (tallest) height.
      const containerWidth = 640.0;
      const margin = 16.0;

      await pump(
        tester,
        ConstraintLayout(
          children: [
            Guideline.vertical(id: #mid, percent: 0.5),
            for (final (id, sid, text, side) in [
              (#ca, #sa, longText, 'left'),
              (#cb, #sb, 'Short.', 'right'),
            ]) ...[
              Constrained(
                id: sid,
                top: .topOf(parent),
                bottom: .bottomOf(#bar),
                left: side == 'left' ? .leftOf(parent) : .rightOf(#mid),
                right: side == 'left' ? .leftOf(#mid) : .rightOf(parent),
                width: .matchConstraint,
                height: .matchConstraint,
                child: SizedBox(key: ValueKey(sid)),
              ),
              Constrained(
                id: id,
                top: .topOf(parent, margin: margin),
                left: side == 'left'
                    ? .leftOf(parent, margin: margin)
                    : .rightOf(#mid, margin: margin),
                right: side == 'left'
                    ? .leftOf(#mid, margin: margin)
                    : .rightOf(parent, margin: margin),
                width: .matchConstraint,
                height: .wrapContent,
                child: Text(text, style: style),
              ),
            ],
            Barrier(
              id: #bar,
              edge: .bottom,
              referenced: [#ca, #cb],
              margin: margin,
            ),
          ],
        ),
        width: containerWidth,
        height: bounded ? 800 : null,
      );

      final ha = tester.getSize(find.byKey(const ValueKey(#sa))).height;
      final hb = tester.getSize(find.byKey(const ValueKey(#sb))).height;
      expect(ha, hb, reason: 'both surfaces stretch to the shared barrier');
      expect(
        ha,
        greaterThan(60),
        reason: 'measured at real width, not width 0',
      );
    });

    testWidgets('constrainedWrap width + wrapContent height measures wrapping '
        'text again at the capped width ($label)', (tester) async {
      // Measured on its own, the text wraps across the container's full 340;
      // the links cap it at 340 - 60 - 60 = 220, where it needs more lines.
      const containerWidth = 340.0;
      const margin = 60.0;
      const cappedWidth = containerWidth - 2 * margin;

      final uncapped = await oracleSize(
        tester,
        const Text(longText, style: style),
        containerWidth,
      );
      final oracle = await oracleSize(
        tester,
        const Text(longText, style: style),
        cappedWidth,
      );
      expect(
        oracle.height,
        greaterThan(uncapped.height),
        reason: 'precondition: the text needs more lines when capped',
      );

      await pump(
        tester,
        ConstraintLayout(
          children: [
            Constrained(
              id: #t,
              top: .topOf(parent),
              left: .leftOf(parent, margin: margin),
              right: .rightOf(parent, margin: margin),
              width: .constrainedWrap(),
              height: .wrapContent,
              child: const Text(longText, key: Key('t'), style: style),
            ),
          ],
        ),
        width: containerWidth,
        height: bounded ? 600 : null,
      );

      expect(
        tester.getSize(find.byKey(const Key('t'))),
        oracle,
        reason:
            'the height must follow the capped width, not stay at the '
            'height the text took before the cap',
      );
    });

    testWidgets('constrainedWrap(min:, max:) measures text at its bounded '
        'width, with one link or two ($label)', (tester) async {
      // Short text is widened to the min; the long text is capped at the max
      // well inside the links, and wraps there.
      const containerWidth = 340.0;
      const margin = 20.0;
      const min = 120.0;
      const max = 200.0;

      final shortOracle = await oracleSize(
        tester,
        const Text('Short.', style: style),
        min,
      );
      final longOracle = await oracleSize(
        tester,
        const Text(longText, style: style),
        max,
      );
      final uncapped = await oracleSize(
        tester,
        const Text(longText, style: style),
        containerWidth,
      );
      expect(
        longOracle.height,
        greaterThan(uncapped.height),
        reason: 'precondition: the text needs more lines at the max',
      );

      await pump(
        tester,
        ConstraintLayout(
          children: [
            Constrained(
              id: #short,
              top: .topOf(parent),
              left: .leftOf(parent, margin: margin),
              right: .rightOf(parent, margin: margin),
              width: .constrainedWrap(min: min, max: max),
              child: const Text('Short.', key: Key('short'), style: style),
            ),
            Constrained(
              id: #two,
              top: .bottomOf(#short),
              left: .leftOf(parent, margin: margin),
              right: .rightOf(parent, margin: margin),
              width: .constrainedWrap(min: min, max: max),
              child: const Text(longText, key: Key('two'), style: style),
            ),
            Constrained(
              id: #one,
              top: .bottomOf(#two),
              left: .leftOf(parent, margin: margin),
              width: .constrainedWrap(min: min, max: max),
              child: const Text(longText, key: Key('one'), style: style),
            ),
          ],
        ),
        width: containerWidth,
        height: bounded ? 2000 : null,
      );

      expect(tester.getSize(find.byKey(const Key('short'))), shortOracle);
      expect(
        tester.getSize(find.byKey(const Key('two'))),
        longOracle,
        reason: 'two links: the height must follow the max width',
      );
      expect(
        tester.getSize(find.byKey(const Key('one'))),
        longOracle,
        reason: 'one link: the height must follow the max width',
      );
    });

    testWidgets('constrainedWrap leaves single-line text at the size it takes '
        'on its own ($label)', (tester) async {
      // Text that fits keeps its natural size (it is not spread between the
      // links), and a one-line caption that does not fit is capped and
      // ellipsized, staying one line tall.
      const containerWidth = 340.0;
      const margin = 20.0;
      const cappedWidth = containerWidth - 2 * margin;
      const caption = Text(
        longText,
        key: Key('caption'),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

      final natural = await naturalSize(
        tester,
        const Text('Short.', style: style),
      );
      final captionOracle = await oracleSize(tester, caption, cappedWidth);

      await pump(
        tester,
        ConstraintLayout(
          children: [
            Constrained(
              id: #short,
              top: .topOf(parent),
              left: .leftOf(parent, margin: margin),
              right: .rightOf(parent, margin: margin),
              width: .constrainedWrap(),
              child: const Text('Short.', key: Key('short'), style: style),
            ),
            Constrained(
              id: #caption,
              top: .bottomOf(#short),
              left: .leftOf(parent, margin: margin),
              right: .rightOf(parent, margin: margin),
              width: .constrainedWrap(),
              child: caption,
            ),
          ],
        ),
        width: containerWidth,
        height: bounded ? 600 : null,
      );

      expect(tester.getSize(find.byKey(const Key('short'))), natural);
      expect(
        tester.getTopLeft(find.byKey(const Key('short'))).dx,
        margin + (cappedWidth - natural.width) / 2,
        reason: 'centered between the links at its own width',
      );
      expect(tester.getSize(find.byKey(const Key('caption'))), captionOracle);
    });
  }

  testWidgets('constrainedWrap height + wrapContent width measures turned text '
      'again at the capped height', (tester) async {
    // A quarter turn swaps the axes: the box's width is the wrapped text's
    // height, so capping the box's height must widen it.
    const containerHeight = 340.0;
    const margin = 60.0;
    const cappedHeight = containerHeight - 2 * margin;

    final uncapped = await oracleSize(
      tester,
      const Text(longText, style: style),
      containerHeight,
    );
    final oracle = await oracleSize(
      tester,
      const Text(longText, style: style),
      cappedHeight,
    );
    expect(
      oracle.height,
      greaterThan(uncapped.height),
      reason: 'precondition: the text needs more lines when capped',
    );

    await pump(
      tester,
      ConstraintLayout(
        children: [
          Constrained(
            id: #t,
            left: .leftOf(parent),
            top: .topOf(parent, margin: margin),
            bottom: .bottomOf(parent, margin: margin),
            width: .wrapContent,
            height: .constrainedWrap(),
            child: const RotatedBox(
              key: Key('t'),
              quarterTurns: 1,
              child: Text(longText, style: style),
            ),
          ),
        ],
      ),
      width: 600,
      height: containerHeight,
    );

    expect(
      tester.getSize(find.byKey(const Key('t'))),
      Size(oracle.height, oracle.width),
      reason: 'the width must follow the capped height',
    );
  });

  testWidgets('constrainedWrap on both axes measures wrapping text again at '
      'the capped width', (tester) async {
    const containerWidth = 340.0;
    const margin = 60.0;
    const cappedWidth = containerWidth - 2 * margin;

    final uncapped = await oracleSize(
      tester,
      const Text(longText, style: style),
      containerWidth,
    );
    final oracle = await oracleSize(
      tester,
      const Text(longText, style: style),
      cappedWidth,
    );
    expect(
      oracle.height,
      greaterThan(uncapped.height),
      reason: 'precondition: the text needs more lines when capped',
    );

    await pump(
      tester,
      ConstraintLayout(
        children: [
          Constrained(
            id: #t,
            top: .topOf(parent, margin: margin),
            bottom: .bottomOf(parent, margin: margin),
            left: .leftOf(parent, margin: margin),
            right: .rightOf(parent, margin: margin),
            width: .constrainedWrap(),
            height: .constrainedWrap(),
            child: const Text(longText, key: Key('t'), style: style),
          ),
        ],
      ),
      width: containerWidth,
      height: 600,
    );

    expect(tester.getSize(find.byKey(const Key('t'))), oracle);
  });

  group('fractional text metrics round up to whole pixels', () {
    // At a font size of 14.3 a glyph is 14.3 wide, so a line of text is not a
    // whole number of pixels wide: its measured width rounds up to the whole
    // pixel, as max(0, (v - 0.001).ceil()), and the text is laid out again,
    // tight at that frame. (The test font's line heights are whole pixels.)
    const fractional = TextStyle(fontSize: 14.3);
    double whole(double v) => (v - 0.001).ceilToDouble();

    /// Ground truth: [child] laid out under a maximum width of [maxWidth].
    Future<Size> wrappedSize(
      WidgetTester tester,
      Widget child,
      double maxWidth,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: KeyedSubtree(key: const Key('oracle'), child: child),
            ),
          ),
        ),
      );
      return tester.getSize(find.byKey(const Key('oracle')));
    }

    for (final bounded in [true, false]) {
      final label = bounded ? 'bounded height' : 'unbounded height';

      testWidgets('a short text at its own size ($label)', (tester) async {
        final natural = await naturalSize(
          tester,
          const Text('Short.', style: fractional),
        );
        expect(
          natural.width,
          isNot(natural.width.roundToDouble()),
          reason: 'precondition: the natural width is fractional',
        );

        await pump(
          tester,
          ConstraintLayout(
            children: [
              Constrained(
                id: #short,
                top: .topOf(parent),
                left: .leftOf(parent),
                child: const Text(
                  'Short.',
                  key: Key('short'),
                  style: fractional,
                ),
              ),
              Constrained(
                id: #next,
                top: .topOf(parent),
                left: .rightOf(#short),
                width: .fixed(10),
                height: .fixed(10),
                child: const SizedBox(key: Key('next')),
              ),
            ],
          ),
          width: 340,
          height: bounded ? 600 : null,
        );

        expect(
          tester.getSize(find.byKey(const Key('short'))),
          Size(whole(natural.width), whole(natural.height)),
        );
        expect(
          tester.getTopLeft(find.byKey(const Key('next'))).dx,
          whole(natural.width),
          reason: 'its neighbour starts at the rounded-up right edge',
        );
      });

      testWidgets('wrapping text at the width it wraps to ($label)', (
        tester,
      ) async {
        // A wrapContent text is measured under the layout's width (Android's
        // AT_MOST), wraps there, and is as wide as its widest line.
        const containerWidth = 340.0;
        final oracle = await wrappedSize(
          tester,
          const Text(
            longText,
            style: fractional,
            textWidthBasis: TextWidthBasis.longestLine,
          ),
          containerWidth,
        );
        expect(
          oracle.width,
          isNot(oracle.width.roundToDouble()),
          reason: 'precondition: the widest line is a fractional width',
        );

        await pump(
          tester,
          ConstraintLayout(
            children: [
              Constrained(
                id: #t,
                top: .topOf(parent),
                left: .leftOf(parent),
                child: const Text(
                  longText,
                  key: Key('t'),
                  style: fractional,
                  textWidthBasis: TextWidthBasis.longestLine,
                ),
              ),
            ],
          ),
          width: containerWidth,
          height: bounded ? 600 : null,
        );

        expect(
          tester.getSize(find.byKey(const Key('t'))),
          Size(whole(oracle.width), whole(oracle.height)),
          reason: 'laid out again at the rounded-up width, it wraps the same',
        );
        if (!bounded) {
          expect(
            tester.getSize(find.byType(ConstraintLayout)).height,
            whole(oracle.height),
          );
        }
      });
    }
  });

  testWidgets('matchConstraint width + constrainedWrap height sizes the height '
      'to the text wrapped at the resolved width', (tester) async {
    const containerWidth = 340.0;
    const margin = 20.0;
    const resolvedWidth = containerWidth - 2 * margin;

    final oracle = await oracleSize(
      tester,
      const Text(longText, style: style),
      resolvedWidth,
    );

    await pump(
      tester,
      ConstraintLayout(
        children: [
          Constrained(
            id: #t,
            top: .topOf(parent, margin: margin),
            bottom: .bottomOf(parent, margin: margin),
            left: .leftOf(parent, margin: margin),
            right: .rightOf(parent, margin: margin),
            width: .matchConstraint,
            height: .constrainedWrap(),
            child: const Text(longText, key: Key('t'), style: style),
          ),
        ],
      ),
      width: containerWidth,
      height: 600,
    );

    expect(
      tester.getSize(find.byKey(const Key('t'))),
      oracle,
      reason: 'the text needs its wrapped height, not the whole span',
    );
  });
}
