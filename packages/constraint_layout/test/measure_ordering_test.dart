import 'package:constraint_layout/constraint_layout.dart';
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
            child: height == null ? SingleChildScrollView(child: layout) : layout,
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

  for (final bounded in [true, false]) {
    final label = bounded ? 'bounded height' : 'unbounded height';

    testWidgets('matchConstraint width + wrapContent height measures wrapping '
        'text at the resolved width ($label)', (tester) async {
      // Container 340 wide, text inset 20 each side -> resolved width 300.
      const containerWidth = 340.0;
      const margin = 20.0;
      const resolvedWidth = containerWidth - 2 * margin;

      final oracle =
          await oracleSize(tester, const Text(longText, style: style), resolvedWidth);

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

      expect(tester.getSize(find.byKey(const Key('t'))), oracle,
          reason: 'child must be measured at its resolved width, not width 0');
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

      final oracle =
          await oracleSize(tester, const Text(longText, style: style), columnWidth);

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
      expect(tester.getTopLeft(find.byKey(const Key('follower'))).dy, oracle.height);
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
            Barrier(id: #bar, edge: .bottom, referenced: [#ca, #cb], margin: margin),
          ],
        ),
        width: containerWidth,
        height: bounded ? 800 : null,
      );

      final ha = tester.getSize(find.byKey(const ValueKey(#sa))).height;
      final hb = tester.getSize(find.byKey(const ValueKey(#sb))).height;
      expect(ha, hb, reason: 'both surfaces stretch to the shared barrier');
      expect(ha, greaterThan(60), reason: 'measured at real width, not width 0');
    });
  }
}
