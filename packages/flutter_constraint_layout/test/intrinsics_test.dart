// Intrinsic sizes, dry layout, and baseline of RenderConstraintLayout.
//
// The layout used to report 0 for every intrinsic size, throw from
// getDryLayout, and have no baseline, so IntrinsicHeight and IntrinsicWidth
// collapsed it, dialogs and menus sized it at their minimum width, and a
// Baseline or a baseline-aligned Row could not line it up. These tests pin
// the contract that replaced that:
//
//  * getDryLayout returns the size layout gives, for every layout the other
//    test suites lay out, under bounded, loose, and unbounded constraints;
//  * the maximum intrinsic sizes are that dry layout with the measured axis
//    unbounded, the minimum ones measure each content-sized child at its own
//    minimum intrinsic size, and both satisfy Flutter's contract;
//  * the baseline is the highest one among the visible children;
//  * none of these queries changes the layout, its children, or the
//    persistent engine model.
//
// Many tests run with debugCheckIntrinsicSizes on, so Flutter itself also
// checks, after every layout of every box, the intrinsic contract, that
// getDryLayout matches the size, and, after painting, that each dry baseline
// matches the real one.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_constraint_layout/src/constraint_parent_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_fixtures.dart';

/// Whether the suite runs with `--dart-define=cl.verifyReplay=true`, under
/// which a replayed layout also runs the engine to check itself.
const verifyReplay = bool.fromEnvironment('cl.verifyReplay');

RenderConstraintLayout layoutOf(WidgetTester tester) =>
    tester.renderObject<RenderConstraintLayout>(
      find.byType(ConstraintLayout).first,
    );

/// Runs [body] with Flutter's intrinsic-size self-checks on.
Future<void> withIntrinsicChecks(Future<void> Function() body) async {
  debugCheckIntrinsicSizes = true;
  try {
    await body();
  } finally {
    debugCheckIntrinsicSizes = false;
  }
}

/// Lays [child] out under exactly [constraints], at the top left.
Widget under(
  BoxConstraints constraints,
  Widget child, {
  TextDirection direction = TextDirection.ltr,
}) => Directionality(
  textDirection: direction,
  child: Align(
    alignment: Alignment.topLeft,
    child: OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: constraints.minWidth,
      maxWidth: constraints.maxWidth,
      minHeight: constraints.minHeight,
      maxHeight: constraints.maxHeight,
      child: child,
    ),
  ),
);

/// Places [child] at the top left, under a [Directionality].
Widget topLeft(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    Directionality(
      textDirection: direction,
      child: Align(alignment: Alignment.topLeft, child: child),
    );

/// The rect of the widget keyed [id], relative to the outermost
/// ConstraintLayout.
Rect rectOf(WidgetTester tester, Symbol id) {
  final box = tester.renderObject<RenderBox>(find.byKey(ValueKey(id)));
  final topLeft = box.localToGlobal(Offset.zero, ancestor: layoutOf(tester));
  return topLeft & box.size;
}

/// [text] laid out in [style], at most [maxWidth] wide: the expected
/// metrics of a Text widget.
TextPainter measureText(String text, TextStyle style, {double? maxWidth}) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth ?? double.infinity);

/// Collects every error reported while [body] runs, keeping them away from
/// the test binding.
Future<List<FlutterErrorDetails>> reportedDuring(
  Future<void> Function() body,
) async {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

/// The README's profile card, without the Card around it.
List<Widget> profileCard(TextTheme textTheme) => [
  Constrained(
    id: #cover,
    start: .startOf(parent),
    end: .endOf(parent),
    top: .topOf(parent),
    width: .matchConstraint,
    height: .matchConstraint,
    aspectRatio: 3,
    child: const ColoredBox(key: ValueKey(#cover), color: Colors.indigo),
  ),
  Constrained(
    id: #avatar,
    start: .startOf(parent, margin: 16),
    top: .bottomOf(#cover),
    bottom: .bottomOf(#cover),
    child: const CircleAvatar(
      key: ValueKey(#avatar),
      radius: 36,
      child: Text('AL'),
    ),
  ),
  Constrained(
    id: #follow,
    end: .endOf(parent, margin: 16),
    top: .bottomOf(#cover, margin: 12),
    child: FilledButton(
      key: const ValueKey(#follow),
      onPressed: () {},
      child: const Text('Follow'),
    ),
  ),
  Constrained(
    id: #name,
    start: .startOf(#avatar),
    end: .startOf(#follow, margin: 12),
    top: .bottomOf(#avatar, margin: 8),
    width: .matchConstraint,
    child: Text(
      'Ada Lovelace',
      key: const ValueKey(#name),
      style: textTheme.titleLarge,
    ),
  ),
  Constrained(
    id: #handle,
    start: .startOf(#name),
    top: .bottomOf(#name),
    child: Text(
      '@ada',
      key: const ValueKey(#handle),
      style: textTheme.bodyMedium,
    ),
  ),
  const Barrier(id: #header, edge: .bottom, referenced: [#handle, #follow]),
  Constrained(
    id: #bio,
    start: .startOf(parent, margin: 16),
    end: .endOf(parent, margin: 16),
    top: .bottomOf(#header, margin: 12),
    bottom: .bottomOf(parent, margin: 16),
    width: .matchConstraint,
    child: const Text(
      'Mathematician and writer. Published the first algorithm intended to '
      'be carried out by a machine.',
      key: ValueKey(#bio),
    ),
  ),
];

/// Three 80 x 40 boxes in a horizontal chain, 16 in from each edge.
List<Widget> chainOfThree({ChainStyle? style}) => [
  for (var i = 0; i < 3; i++)
    Constrained(
      id: Symbol('c$i'),
      start: i == 0
          ? .startOf(parent, margin: 16)
          : .endOf(Symbol('c${i - 1}'), margin: 8),
      end: i == 2 ? .endOf(parent, margin: 16) : .startOf(Symbol('c${i + 1}')),
      top: .topOf(parent, margin: 10),
      width: .fixed(80),
      height: .fixed(40),
      horizontalChainStyle: i == 0 ? style : null,
      child: SizedBox(key: ValueKey(Symbol('c$i'))),
    ),
];

const String words = 'Constraint layouts measure text';
const TextStyle wordStyle = TextStyle(fontSize: 10);

/// Text that sizes to its content, capped at the space between margins of
/// 16 on either side.
List<Widget> cappedText() => [
  Constrained(
    id: #text,
    start: .startOf(parent, margin: 16),
    end: .endOf(parent, margin: 16),
    top: .topOf(parent, margin: 8),
    bottom: .bottomOf(parent, margin: 8),
    width: .constrainedWrap(),
    child: const Text(words, key: ValueKey(#text), style: wordStyle),
  ),
];

/// A single 200 x 30 box pinned to the top left.
Widget fixedRow() => ConstraintLayout(
  children: [
    Constrained(
      id: #row,
      start: .startOf(parent),
      top: .topOf(parent),
      width: .fixed(200),
      height: .fixed(30),
      child: const SizedBox(key: ValueKey(#row)),
    ),
  ],
);

void main() {
  group('IntrinsicHeight and IntrinsicWidth', () {
    testWidgets('IntrinsicHeight sizes the profile card to its content', (
      tester,
    ) async {
      await withIntrinsicChecks(() async {
        Widget app(Widget Function(Widget card) wrap) => MaterialApp(
          home: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: Builder(
                builder: (context) => wrap(
                  ConstraintLayout(
                    children: profileCard(Theme.of(context).textTheme),
                  ),
                ),
              ),
            ),
          ),
        );

        // The card's natural height at 400 wide, as in a list.
        await tester.pumpWidget(
          app(
            (card) => OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 400,
              maxWidth: 400,
              maxHeight: double.infinity,
              child: card,
            ),
          ),
        );
        final natural = tester.getSize(find.byType(ConstraintLayout));
        final placed = {
          for (final id in const [#cover, #avatar, #follow, #name, #bio])
            id: rectOf(tester, id),
        };
        expect(natural.width, 400);
        // The bio ends 16 above the bottom.
        expect(placed[#bio]!.bottom, natural.height - 16);

        await tester.pumpWidget(
          app(
            (card) => SizedBox(width: 400, child: IntrinsicHeight(child: card)),
          ),
        );
        expect(tester.getSize(find.byType(ConstraintLayout)), natural);
        for (final MapEntry(key: id, value: rect) in placed.entries) {
          expect(rectOf(tester, id), rect, reason: '$id');
        }
      });
    });

    testWidgets('IntrinsicWidth wraps a chain', (tester) async {
      await withIntrinsicChecks(() async {
        await tester.pumpWidget(
          topLeft(
            IntrinsicWidth(child: ConstraintLayout(children: chainOfThree())),
          ),
        );
        // 16 + 80 + 8 + 80 + 8 + 80 + 16. A bounded height is taken whole.
        expect(
          tester.getSize(find.byType(ConstraintLayout)),
          const Size(288, 600),
        );
        expect(rectOf(tester, #c0), const Rect.fromLTWH(16, 10, 80, 40));
        expect(rectOf(tester, #c1), const Rect.fromLTWH(104, 10, 80, 40));
        expect(rectOf(tester, #c2), const Rect.fromLTWH(192, 10, 80, 40));
      });
    });

    testWidgets(
      'IntrinsicWidth wraps a right-to-left packed chain at its start',
      (
        tester,
      ) async {
        await withIntrinsicChecks(() async {
          await tester.pumpWidget(
            topLeft(
              IntrinsicWidth(
                child: ConstraintLayout(
                  children: chainOfThree(style: ChainStyle.packed),
                ),
              ),
              direction: TextDirection.rtl,
            ),
          );
          expect(tester.getSize(find.byType(ConstraintLayout)).width, 288);
          // The head is the start-most member: at the right.
          expect(rectOf(tester, #c0).left, 192);
          expect(rectOf(tester, #c2).left, 16);
        });
      },
    );

    testWidgets('IntrinsicHeight wraps text capped by constrainedWrap', (
      tester,
    ) async {
      await withIntrinsicChecks(() async {
        await tester.pumpWidget(
          topLeft(
            SizedBox(
              width: 150,
              child: IntrinsicHeight(
                child: ConstraintLayout(children: cappedText()),
              ),
            ),
          ),
        );
        // The text is capped at 150 - 2 * 16 and wraps there.
        final wrapped = measureText(words, wordStyle, maxWidth: 118);
        expect(wrapped.computeLineMetrics().length, greaterThan(1));
        expect(
          tester.getSize(find.byType(ConstraintLayout)),
          Size(150, wrapped.height + 16),
        );
        expect(rectOf(tester, #text).height, wrapped.height);
      });
    });

    testWidgets(
      'IntrinsicWidth fits text capped by constrainedWrap on one line',
      (
        tester,
      ) async {
        await withIntrinsicChecks(() async {
          await tester.pumpWidget(
            topLeft(
              IntrinsicWidth(child: ConstraintLayout(children: cappedText())),
            ),
          );
          final line = measureText(words, wordStyle);
          expect(
            tester.getSize(find.byType(ConstraintLayout)).width,
            line.width + 32,
          );
          expect(rectOf(tester, #text).size, line.size);
        });
      },
    );

    testWidgets('IntrinsicHeight reaches into a nested ConstraintLayout', (
      tester,
    ) async {
      await withIntrinsicChecks(() async {
        final nested = ConstraintLayout(
          children: [
            Constrained(
              id: #inner,
              start: .startOf(parent),
              end: .endOf(parent),
              top: .topOf(parent, margin: 10),
              bottom: .bottomOf(parent, margin: 10),
              width: .matchConstraint,
              child: ConstraintLayout(children: cappedText()),
            ),
          ],
        );
        // The outer layout's natural height at 150 wide: the inner one wraps
        // its text, which wraps at 150 - 2 * 16.
        await tester.pumpWidget(
          under(const BoxConstraints.tightFor(width: 150), nested),
        );
        final wrapped = measureText(words, wordStyle, maxWidth: 118);
        final natural = tester.getSize(find.byType(ConstraintLayout).first);
        final text = rectOf(tester, #text);
        expect(natural, Size(150, wrapped.height + 36));

        await tester.pumpWidget(
          topLeft(SizedBox(width: 150, child: IntrinsicHeight(child: nested))),
        );
        expect(tester.getSize(find.byType(ConstraintLayout).first), natural);
        expect(rectOf(tester, #text), text);
      });
    });
  });

  group('intrinsic sizes', () {
    Future<RenderConstraintLayout> pumpLaidOut(
      WidgetTester tester,
      List<Widget> children,
    ) async {
      await tester.pumpWidget(
        topLeft(
          SizedBox(
            width: 400,
            height: 300,
            child: ConstraintLayout(children: children),
          ),
        ),
      );
      return layoutOf(tester);
    }

    testWidgets('are the dry layout with the measured axis unbounded', (
      tester,
    ) async {
      final ro = await pumpLaidOut(tester, cappedText());
      for (final extent in [double.infinity, 150.0, 40.0]) {
        final tight = extent.isFinite;
        expect(
          ro.getMaxIntrinsicWidth(extent),
          ro
              .getDryLayout(
                tight
                    ? BoxConstraints.tightFor(height: extent)
                    : const BoxConstraints(),
              )
              .width,
        );
        expect(
          ro.getMaxIntrinsicHeight(extent),
          ro
              .getDryLayout(
                tight
                    ? BoxConstraints.tightFor(width: extent)
                    : const BoxConstraints(),
              )
              .height,
        );
      }
    });

    testWidgets('measure wrapping text at its longest word for the minimum', (
      tester,
    ) async {
      final ro = await pumpLaidOut(tester, cappedText());
      final line = measureText(words, wordStyle);
      expect(ro.getMaxIntrinsicWidth(double.infinity), line.width + 32);
      expect(
        ro.getMinIntrinsicWidth(double.infinity),
        line.minIntrinsicWidth + 32,
      );
      expect(line.minIntrinsicWidth, lessThan(line.width));

      // At 150 wide the text wraps at 118 whichever height is asked for.
      final wrapped = measureText(words, wordStyle, maxWidth: 118);
      expect(ro.getMaxIntrinsicHeight(150), wrapped.height + 16);
      expect(ro.getMinIntrinsicHeight(150), wrapped.height + 16);
    });

    testWidgets('satisfy the intrinsic contract for every fixture', (
      tester,
    ) async {
      for (final fixture in [...featureFixtures, ...goldenFixtures]) {
        await tester.pumpWidget(
          under(
            BoxConstraints.tight(fixture.size),
            ConstraintLayout(children: fixture.children()),
            direction: fixture.direction,
          ),
        );
        final ro = layoutOf(tester);
        for (final extent in [
          double.infinity,
          fixture.size.width,
          fixture.size.height,
          0.0,
        ]) {
          final minW = ro.getMinIntrinsicWidth(extent);
          final maxW = ro.getMaxIntrinsicWidth(extent);
          final minH = ro.getMinIntrinsicHeight(extent);
          final maxH = ro.getMaxIntrinsicHeight(extent);
          final reason = '${fixture.name} at $extent';
          for (final value in [minW, maxW, minH, maxH]) {
            expect(value.isFinite, isTrue, reason: reason);
            expect(value, greaterThanOrEqualTo(0), reason: reason);
          }
          expect(minW, lessThanOrEqualTo(maxW), reason: reason);
          expect(minH, lessThanOrEqualTo(maxH), reason: reason);
        }
      }
    });

    testWidgets('are 0 for an empty layout', (tester) async {
      final ro = await pumpLaidOut(tester, const []);
      expect(ro.getMinIntrinsicWidth(double.infinity), 0);
      expect(ro.getMaxIntrinsicWidth(100), 0);
      expect(ro.getMinIntrinsicHeight(100), 0);
      expect(ro.getMaxIntrinsicHeight(double.infinity), 0);
      // An empty layout fills its bounded axes, as Android's fills an
      // EXACTLY spec. Java J257: root 50 x 0 (VOpDriver view, p4a:empty50,
      // E50 x U0 without a child).
      expect(
        ro.getDryLayout(const BoxConstraints(minWidth: 10, maxWidth: 50)),
        const Size(50, 0),
      );
      expect(
        ro.getDryBaseline(const BoxConstraints(), TextBaseline.alphabetic),
        isNull,
      );
    });

    testWidgets('do not count gone children', (tester) async {
      final ro = await pumpLaidOut(tester, [
        Constrained(
          id: #shown,
          start: .startOf(parent, margin: 10),
          top: .topOf(parent, margin: 10),
          width: .fixed(50),
          height: .fixed(20),
          child: const SizedBox(),
        ),
        Constrained(
          id: #gone,
          start: .endOf(#shown),
          top: .bottomOf(#shown),
          width: .fixed(300),
          height: .fixed(200),
          visibility: .gone,
          child: const SizedBox(),
        ),
      ]);
      expect(ro.getMaxIntrinsicWidth(double.infinity), 60);
      expect(ro.getMaxIntrinsicHeight(double.infinity), 30);
    });

    testWidgets('the minimum height counts text at the width a one-link max '
        'caps it to', (tester) async {
      for (final width in const [
        Dimension.spread(max: 300),
        Dimension.fixed(300),
        Dimension.constrainedWrap(max: 300),
      ]) {
        await tester.pumpWidget(
          under(
            const BoxConstraints(minWidth: 800, maxWidth: 800),
            ConstraintLayout(
              children: [
                Constrained(
                  id: #t,
                  start: .startOf(parent, margin: 10),
                  top: .topOf(parent),
                  width: width,
                  child: const Text(
                    'AAAAAAAAA BBBBBBBBB CCCCCCCCC DDDDDDDDD',
                    style: TextStyle(fontSize: 20),
                  ),
                ),
                Constrained(
                  id: #below,
                  start: .startOf(parent),
                  top: .bottomOf(#t),
                  width: .fixed(10),
                  height: .fixed(10),
                  child: const SizedBox(),
                ),
              ],
            ),
          ),
        );
        final ro = layoutOf(tester);
        // Four 20 px lines at the capped 300 px width, then the 10 px box.
        expect(ro.size, const Size(800, 90), reason: '$width');
        expect(ro.getMaxIntrinsicHeight(800), 90, reason: '$width');
        // It cannot be any shorter at that width.
        expect(ro.getMinIntrinsicHeight(800), 90, reason: '$width');
      }
    });
  });

  group('dialogs and menus', () {
    // Longer than an AlertDialog's minimum content width of 280 - 2 * 24.
    const message = 'Delete this layout from the project?';

    Widget opener(void Function(BuildContext context) open) => MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    );

    Widget messageLayout() => ConstraintLayout(
      children: [
        Constrained(
          id: #message,
          start: .startOf(parent),
          top: .topOf(parent),
          child: const Text(message, key: ValueKey(#message)),
        ),
      ],
    );

    /// Checks that the message fits on one line, and returns that line.
    TextPainter expectOneLine(WidgetTester tester) {
      final text = tester.renderObject<RenderParagraph>(find.text(message));
      final line = measureText(message, text.text.style!);
      expect(text.size, line.size);
      expect(
        tester.getSize(find.byType(ConstraintLayout)).width,
        greaterThanOrEqualTo(line.width),
      );
      return line;
    }

    testWidgets('an AlertDialog is as wide as its ConstraintLayout content', (
      tester,
    ) async {
      await withIntrinsicChecks(() async {
        await tester.pumpWidget(
          opener(
            (context) => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(content: messageLayout()),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final line = expectOneLine(tester);
        expect(tester.getSize(find.byType(ConstraintLayout)).width, line.width);
      });
    });

    testWidgets('a SimpleDialog is as wide as its ConstraintLayout child', (
      tester,
    ) async {
      await withIntrinsicChecks(() async {
        await tester.pumpWidget(
          opener(
            (context) => showDialog<void>(
              context: context,
              builder: (_) => SimpleDialog(children: [messageLayout()]),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expectOneLine(tester);
      });
    });

    testWidgets('a popup menu is as wide as its ConstraintLayout item', (
      tester,
    ) async {
      await withIntrinsicChecks(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: Center(
                child: PopupMenuButton<int>(
                  itemBuilder: (_) => [
                    PopupMenuItem<int>(value: 1, child: fixedRow()),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(PopupMenuButton<int>));
        await tester.pumpAndSettle();
        final layout = tester.getRect(find.byType(ConstraintLayout));
        final row = tester.getRect(find.byKey(const ValueKey(#row)));
        expect(layout.width, greaterThanOrEqualTo(200));
        expect(row.right, lessThanOrEqualTo(layout.right));
      });
    });
  });

  group('baseline', () {
    const titleStyle = TextStyle(fontSize: 20);
    const subtitleStyle = TextStyle(fontSize: 12);

    /// A title 30 down from the top and a subtitle under it.
    List<Widget> titled({
      ConstraintVisibility title = ConstraintVisibility.visible,
    }) => [
      Constrained(
        id: #title,
        start: .startOf(parent),
        top: .topOf(parent, margin: 30),
        visibility: title,
        child: const Text('Title', key: ValueKey(#title), style: titleStyle),
      ),
      Constrained(
        id: #subtitle,
        start: .startOf(parent),
        top: .topOf(parent, margin: 60),
        child: const Text(
          'Subtitle',
          key: ValueKey(#subtitle),
          style: subtitleStyle,
        ),
      ),
    ];

    double baselineOf(TextStyle style) => measureText(
      'A',
      style,
    ).computeDistanceToActualBaseline(TextBaseline.alphabetic);

    testWidgets('a baseline-aligned Row lines the layout up with a Text', (
      tester,
    ) async {
      await withIntrinsicChecks(() async {
        await tester.pumpWidget(
          topLeft(
            UnconstrainedBox(
              alignment: Alignment.topLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  ConstraintLayout(children: titled()),
                  const Text(
                    'Beside',
                    key: ValueKey(#beside),
                    style: TextStyle(fontSize: 40),
                  ),
                ],
              ),
            ),
          ),
        );
        final title = tester.getTopLeft(find.byKey(const ValueKey(#title))).dy;
        final beside = tester
            .getTopLeft(find.byKey(const ValueKey(#beside)))
            .dy;
        expect(
          title + baselineOf(titleStyle),
          beside + baselineOf(const TextStyle(fontSize: 40)),
        );
      });
    });

    testWidgets('Baseline aligns the highest visible baseline', (tester) async {
      await withIntrinsicChecks(() async {
        Future<double> layoutTop(ConstraintVisibility title) async {
          await tester.pumpWidget(
            topLeft(
              Baseline(
                baseline: 150,
                baselineType: TextBaseline.alphabetic,
                child: SizedBox(
                  width: 300,
                  height: 120,
                  child: ConstraintLayout(children: titled(title: title)),
                ),
              ),
            ),
          );
          return tester.getTopLeft(find.byType(ConstraintLayout)).dy;
        }

        expect(await layoutTop(.visible), 150 - 30 - baselineOf(titleStyle));
        // An invisible or gone title does not count: the subtitle's does.
        expect(
          await layoutTop(.invisible),
          150 - 60 - baselineOf(subtitleStyle),
        );
        expect(await layoutTop(.gone), 150 - 60 - baselineOf(subtitleStyle));
      });
    });

    testWidgets('helpers and children without a baseline do not count', (
      tester,
    ) async {
      await withIntrinsicChecks(() async {
        await tester.pumpWidget(
          topLeft(
            Baseline(
              baseline: 150,
              baselineType: TextBaseline.alphabetic,
              child: SizedBox(
                width: 300,
                height: 200,
                child: ConstraintLayout(
                  children: [
                    const Guideline.horizontal(id: #line, begin: 20),
                    Constrained(
                      id: #box,
                      start: .startOf(parent),
                      top: .topOf(parent),
                      width: .fixed(40),
                      height: .fixed(10),
                      child: const ColoredBox(color: Colors.red),
                    ),
                    Constrained(
                      id: #chip,
                      width: .fixed(40),
                      height: .fixed(40),
                      child: const SizedBox(),
                    ),
                    const ConstraintFlow(id: #flow, referenced: [#chip]),
                    const Barrier(
                      id: #below,
                      edge: .bottom,
                      referenced: [#box],
                    ),
                    Constrained(
                      id: #text,
                      start: .startOf(parent),
                      top: .bottomOf(#line, margin: 70),
                      child: const Text('Text', style: titleStyle),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(
          tester.getTopLeft(find.byType(ConstraintLayout)).dy,
          150 - 90 - baselineOf(titleStyle),
        );
      });
    });

    testWidgets('a layout without text has no baseline', (tester) async {
      await tester.pumpWidget(
        topLeft(
          SizedBox(
            width: 100,
            height: 100,
            child: ConstraintLayout(children: chainOfThree()),
          ),
        ),
      );
      final ro = layoutOf(tester);
      expect(
        ro.getDryBaseline(ro.constraints, TextBaseline.alphabetic),
        isNull,
      );
    });

    testWidgets('the dry baseline follows text direction and constraints', (
      tester,
    ) async {
      await withIntrinsicChecks(() async {
        for (final direction in TextDirection.values) {
          await tester.pumpWidget(
            topLeft(
              UnconstrainedBox(
                alignment: Alignment.topLeft,
                child: ConstraintLayout(children: titled()),
              ),
              direction: direction,
            ),
          );
          final ro = layoutOf(tester);
          for (final constraints in [
            const BoxConstraints(),
            const BoxConstraints(maxWidth: 40),
            BoxConstraints.tight(const Size(300, 200)),
          ]) {
            expect(
              ro.getDryBaseline(constraints, TextBaseline.alphabetic),
              30 + baselineOf(titleStyle),
            );
          }
        }
      });
    });

    for (final viaGroup in [false, true]) {
      testWidgets('a baseline target that turns gone in place '
          '(${viaGroup ? 'by a group' : 'by its own visibility'}) lays out, '
          'and reports its baseline, as a fresh layout does', (tester) async {
        const tight = BoxConstraints.tightFor(width: 800, height: 600);
        List<Widget> children({required bool gone}) => [
          Constrained(
            id: #title,
            start: .startOf(parent, margin: 8),
            top: .topOf(parent, margin: 8),
            visibility: !viaGroup && gone ? .gone : .visible,
            child: const Text('Title', style: TextStyle(fontSize: 30)),
          ),
          Constrained(
            id: #label,
            start: .endOf(#title, margin: 8, goneMargin: 4),
            baseline: .baselineOf(#title),
            child: const Text('label', style: TextStyle(fontSize: 12)),
          ),
          ConstraintGroup(
            id: #g,
            referenced: viaGroup ? const [#title] : const [],
            visibility: viaGroup && gone ? .gone : .visible,
          ),
        ];
        List<Rect> rects() => [
          for (final child in layoutOf(tester).getChildrenAsList())
            (child.parentData! as BoxParentData).offset & child.size,
        ];

        await tester.pumpWidget(
          under(tight, ConstraintLayout(children: children(gone: false))),
        );
        final ro = layoutOf(tester);
        final builds = ro.debugModelBuilds;
        await tester.pumpWidget(
          under(tight, ConstraintLayout(children: children(gone: true))),
        );
        expect(ro.debugModelBuilds, builds, reason: 'applied in place');
        final inPlace = rects();

        RenderObject.debugCheckingIntrinsics = true;
        final double? dry;
        final double? real;
        try {
          dry = ro.getDryBaseline(ro.constraints, TextBaseline.alphabetic);
          real = ro.getDistanceToBaseline(
            TextBaseline.alphabetic,
            onlyReal: true,
          );
        } finally {
          RenderObject.debugCheckingIntrinsics = false;
        }
        expect(dry, real, reason: 'dry baseline vs real baseline');

        await tester.pumpWidget(
          under(
            tight,
            ConstraintLayout(key: UniqueKey(), children: children(gone: true)),
          ),
        );
        expect(inPlace, rects(), reason: 'in place vs fresh');
      });
    }
  });

  group('getDryLayout matches the size layout gives', () {
    // Each fixture runs under the constraints its own test gives it and
    // under loose, fractional, and unbounded variants of them. With the
    // intrinsic self-checks on, every pump also checks the intrinsic
    // contract and the dry baselines of every box, nested layouts included.
    List<BoxConstraints> variantsOf(Size size) => [
      BoxConstraints.tight(size),
      BoxConstraints.loose(size),
      BoxConstraints(maxWidth: size.width + 0.4, maxHeight: size.height + 0.6),
      BoxConstraints.tightFor(width: size.width),
      BoxConstraints(maxWidth: size.width),
      BoxConstraints.tightFor(height: size.height),
      const BoxConstraints(),
    ];

    for (final fixture in [...featureFixtures, ...goldenFixtures]) {
      // One persistent layout across the variants, grids included: a grid
      // creates its cells before the first measure of a model (see 'a grid
      // in a wrapping axis is right on its first layout' below), so a dry
      // layout, always the first measure of a new model, agrees with a
      // layout laid out again.
      testWidgets(fixture.name, (tester) async {
        await withIntrinsicChecks(() async {
          for (final constraints in variantsOf(fixture.size)) {
            await tester.pumpWidget(
              under(
                constraints,
                ConstraintLayout(children: fixture.children()),
                direction: fixture.direction,
              ),
            );
            final ro = layoutOf(tester);
            expect(ro.constraints, constraints);
            expect(
              ro.getDryLayout(constraints),
              ro.size,
              reason: '${fixture.name} under $constraints',
            );
          }
        });
      });
    }
  });

  testWidgets(
    'a grid in a wrapping axis is right on its first layout',
    (tester) async {
      Widget cell(Symbol id) => Constrained(
        id: id,
        width: .fixed(10),
        height: .fixed(10),
        child: SizedBox(key: ValueKey(id)),
      );
      await tester.pumpWidget(
        under(
          const BoxConstraints.tightFor(width: 800),
          ConstraintLayout(
            children: [
              cell(#a),
              cell(#b),
              cell(#c),
              cell(#d),
              ConstraintGrid(
                id: #grid,
                referenced: const [#a, #b, #c, #d],
                rows: 2,
                columns: 2,
                start: .startOf(parent),
                end: .endOf(parent),
                top: .topOf(parent),
                bottom: .bottomOf(parent),
              ),
            ],
          ),
        ),
      );
      // Two rows of two cells, on the first layout as on every later one (and
      // as the adapter's earlier graph-first design gave). The engine's grid
      // creates its cells' box widgets in its own measure, and Android's
      // measure skips a widget that is a match constraint (spread) on both
      // axes until the solver has sized it, so without the cells created
      // before the first measure (as Android's view Grid creates its box views
      // when it is attached) the first solve would run without them: every
      // cell at the origin and the layout one cell tall. Grid has no Android
      // oracle: it is outside the parity contract.
      final ro = layoutOf(tester);
      expect(ro.size, const Size(800, 20));
      expect(rectOf(tester, #d), const Rect.fromLTWH(595, 10, 10, 10));
      expect(
        ro.getDryLayout(const BoxConstraints.tightFor(width: 800)),
        ro.size,
      );
      final first = rectOf(tester, #d);
      ro.markNeedsLayout();
      await tester.pump();
      expect(rectOf(tester, #d), first);
      expect(ro.size, const Size(800, 20));
    },
  );

  group('dry queries leave the layout as it was', () {
    ({int layouts, int builds, int engine, int replays, int applies})
    countersOf(RenderConstraintLayout ro) => (
      layouts: ro.debugLayoutPasses,
      builds: ro.debugModelBuilds,
      engine: ro.debugEnginePasses,
      replays: ro.debugReplayPasses,
      applies: ro.debugConfigApplies,
    );

    void queryEverything(RenderConstraintLayout ro) {
      for (final extent in [double.infinity, 120.0]) {
        ro.getMinIntrinsicWidth(extent);
        ro.getMaxIntrinsicWidth(extent);
        ro.getMinIntrinsicHeight(extent);
        ro.getMaxIntrinsicHeight(extent);
      }
      for (final constraints in [
        const BoxConstraints(),
        const BoxConstraints(maxWidth: 200),
        BoxConstraints.tight(const Size(150, 90)),
      ]) {
        ro.getDryLayout(constraints);
        ro.getDryBaseline(constraints, TextBaseline.alphabetic);
        ro.getDryBaseline(constraints, TextBaseline.ideographic);
      }
    }

    List<Rect> childRects(WidgetTester tester, RenderConstraintLayout ro) => [
      for (
        RenderBox? child = ro.firstChild;
        child != null;
        child = ro.childAfter(child)
      )
        child.localToGlobal(Offset.zero, ancestor: ro) & child.size,
    ];

    testWidgets('a layout that replays still replays', (tester) async {
      await tester.pumpWidget(
        topLeft(
          SizedBox(
            width: 400,
            height: 300,
            child: ConstraintLayout(children: chainOfThree()),
          ),
        ),
      );
      final ro = layoutOf(tester);
      // The second identical layout confirms the first one's run, so the
      // third may replay it.
      ro.markNeedsLayout();
      await tester.pump();
      final before = countersOf(ro);
      final container = ro.debugEngineContainer;
      final rects = childRects(tester, ro);

      queryEverything(ro);
      expect(countersOf(ro), before);
      expect(ro.debugEngineContainer, same(container));
      expect(ro.debugNeedsLayout, isFalse);
      expect(childRects(tester, ro), rects);

      // The persistent model and its last run are still the ones the last
      // layout left, so the next layout under the same constraints replays
      // that run (with cl.verifyReplay, it also runs the engine to check).
      ro.markNeedsLayout();
      await tester.pump();
      final after = countersOf(ro);
      expect(after.replays, before.replays + 1);
      expect(after.engine, before.engine + (verifyReplay ? 1 : 0));
      expect(ro.debugReplayMismatches, 0);
      expect(after.builds, before.builds);
      expect(childRects(tester, ro), rects);
    });

    testWidgets('a content-sized layout is not rebuilt or reconfigured', (
      tester,
    ) async {
      await tester.pumpWidget(
        topLeft(
          SizedBox(
            width: 300,
            height: 200,
            child: ConstraintLayout(
              children: [
                ...cappedText(),
                Constrained(
                  id: #label,
                  start: .startOf(parent),
                  baseline: .baselineOf(#text),
                  child: const Text('Label', key: ValueKey(#label)),
                ),
                const Barrier(id: #end, edge: .end, referenced: [#label]),
                Constrained(
                  id: #after,
                  start: .rightOf(#end, margin: 4),
                  top: .topOf(parent),
                  width: .fixed(20),
                  height: .fixed(20),
                  child: const SizedBox(key: ValueKey(#after)),
                ),
              ],
            ),
          ),
        ),
      );
      final ro = layoutOf(tester);
      final before = countersOf(ro);
      final container = ro.debugEngineContainer;
      final rects = childRects(tester, ro);
      final children = <RenderBox>[
        for (
          RenderBox? child = ro.firstChild;
          child != null;
          child = ro.childAfter(child)
        )
          child,
      ];

      queryEverything(ro);
      expect(countersOf(ro), before);
      expect(ro.debugEngineContainer, same(container));
      for (final child in children) {
        expect(child.debugNeedsLayout, isFalse);
        final pd = child.parentData! as ConstraintParentData;
        expect(pd.configDirty, isFalse);
        expect(pd.structuralDirty, isFalse);
      }
      expect(childRects(tester, ro), rects);

      ro.markNeedsLayout();
      await tester.pump();
      final after = countersOf(ro);
      expect(after.builds, before.builds);
      expect(after.applies, before.applies);
      expect(childRects(tester, ro), rects);
    });

    testWidgets('a pending config change is read, not applied', (tester) async {
      await tester.pumpWidget(
        topLeft(
          SizedBox(
            width: 400,
            height: 300,
            child: ConstraintLayout(
              children: [
                Constrained(
                  id: #a,
                  start: .startOf(parent, margin: 10),
                  top: .topOf(parent),
                  width: .fixed(100),
                  height: .fixed(40),
                  child: const SizedBox(key: ValueKey(#a)),
                ),
              ],
            ),
          ),
        ),
      );
      final ro = layoutOf(tester);
      final pd = ro.firstChild!.parentData! as ConstraintParentData;
      // A change the next layout will apply in place, as Constrained does.
      pd
        ..width = const Dimension.fixed(300)
        ..configDirty = true;
      final before = countersOf(ro);

      // The query sees the new width...
      expect(ro.getMaxIntrinsicWidth(double.infinity), 310);
      // ...without consuming the change or touching the live model.
      expect(pd.configDirty, isTrue);
      expect(countersOf(ro), before);
      expect(ro.debugEngineContainer!.mChildren.single.getWidth(), 100);

      ro.markNeedsLayout();
      await tester.pump();
      expect(ro.debugConfigApplies, before.applies + 1);
      expect(rectOf(tester, #a), const Rect.fromLTWH(10, 0, 300, 40));
    });
  });

  // A dry query that repeats the last one that ran the engine (the same
  // configuration, constraints and kind) asks every child again for each
  // measure that query asked of it, and when every answer is the same, gives
  // that query's result without running the engine. Under cl.verifyReplay
  // every replayed query also runs in full and compares.
  group('dry replay', () {
    /// A title (wrapping text, start to end), a box under it, and a value
    /// on the title's baseline: the layout's height comes from the engine.
    List<Widget> titled({String title = 'A title that wraps'}) => [
      Constrained(
        id: #title,
        start: .startOf(parent, margin: 8),
        end: .endOf(parent, margin: 60),
        top: .topOf(parent, margin: 8),
        width: const Dimension.constrainedWrap(),
        horizontalBias: 0,
        child: Text(title, key: const ValueKey(#title)),
      ),
      Constrained(
        id: #value,
        end: .endOf(parent, margin: 8),
        baseline: .baselineOf(#title),
        child: const Text('42', key: ValueKey(#value)),
      ),
      Constrained(
        id: #box,
        start: .startOf(parent, margin: 8),
        top: .bottomOf(#title, margin: 4),
        bottom: .bottomOf(parent, margin: 8),
        width: .fixed(40),
        height: .fixed(30),
        child: const SizedBox(key: ValueKey(#box)),
      ),
    ];

    Widget app(List<Widget> children) => topLeft(
      SizedBox(width: 240, child: ConstraintLayout(children: children)),
    );

    testWidgets('a repeated query replays the last one', (tester) async {
      await tester.pumpWidget(app(titled()));
      final ro = layoutOf(tester);
      final height = ro.getMaxIntrinsicHeight(240);
      expect(ro.debugDryEnginePasses, 1);
      expect(ro.debugDryReplayPasses, 0);

      // The layout's own markNeedsLayout clears Flutter's cache of its
      // intrinsic sizes, without changing anything the query reads.
      for (var i = 1; i <= 3; i++) {
        ro.markNeedsLayout();
        expect(ro.getMaxIntrinsicHeight(240), height);
        expect(ro.debugDryReplayPasses, i);
        expect(ro.debugDryEnginePasses, 1 + (verifyReplay ? i : 0));
      }
      // The minimum asks two kinds of query: one that measures each
      // content-sized child at its minimum intrinsic size, which runs in
      // full the first time, and the maximum's, which replays. Each kind is
      // kept, so the next minimum replays both.
      ro.markNeedsLayout();
      final minimum = ro.getMinIntrinsicHeight(240);
      expect(ro.debugDryReplayPasses, 4);
      ro.markNeedsLayout();
      expect(ro.getMinIntrinsicHeight(240), minimum);
      expect(ro.debugDryReplayPasses, 6);
      expect(ro.debugDryReplayMismatches, 0);
      await tester.pump();

      // A fresh tree answers the same.
      await tester.pumpWidget(app(titled()));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(titled()));
      expect(layoutOf(tester).getMaxIntrinsicHeight(240), height);
    });

    testWidgets('a child whose answer changes runs the query in full', (
      tester,
    ) async {
      await tester.pumpWidget(app(titled()));
      final ro = layoutOf(tester);
      final height = ro.getMaxIntrinsicHeight(240);
      final engine = ro.debugDryEnginePasses;

      // A longer title wraps to more lines: its dry layout differs, so the
      // query runs the engine again, and gives the fresh tree's height.
      const longer = 'A much longer title that wraps over several lines';
      await tester.pumpWidget(app(titled(title: longer)));
      final taller = ro.getMaxIntrinsicHeight(240);
      expect(taller, greaterThan(height));
      expect(ro.debugDryReplayPasses, 0);
      expect(ro.debugDryEnginePasses, engine + 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(titled(title: longer)));
      expect(layoutOf(tester).getMaxIntrinsicHeight(240), taller);
    });

    testWidgets('a pending configuration change is never replayed', (
      tester,
    ) async {
      await tester.pumpWidget(app(titled()));
      final ro = layoutOf(tester);
      final height = ro.getMaxIntrinsicHeight(240);
      final engine = ro.debugDryEnginePasses;

      // A change the next layout will apply in place, as Constrained makes
      // it: the queries before that layout read it, each in full.
      final box = ro.lastChild!.parentData! as ConstraintParentData;
      box
        ..height = const Dimension.fixed(50)
        ..configDirty = true;
      ro.markNeedsLayout();
      expect(ro.getMaxIntrinsicHeight(240), height + 20);
      ro.markNeedsLayout();
      expect(ro.getMaxIntrinsicHeight(240), height + 20);
      expect(ro.debugDryReplayPasses, 0);
      expect(ro.debugDryEnginePasses, engine + 2);

      // Once the layout applied it, a query runs in full and is kept, and
      // the one after it replays.
      await tester.pump();
      ro.markNeedsLayout();
      expect(ro.getMaxIntrinsicHeight(240), height + 20);
      expect(ro.debugDryEnginePasses, engine + 3);
      ro.markNeedsLayout();
      expect(ro.getMaxIntrinsicHeight(240), height + 20);
      expect(ro.debugDryReplayPasses, 1);
      expect(ro.debugDryReplayMismatches, 0);
      await tester.pump();
    });

    testWidgets('IntrinsicHeight replays the query while the answers hold', (
      tester,
    ) async {
      final typed = ValueNotifier<String>('a');
      addTearDown(typed.dispose);
      await tester.pumpWidget(
        topLeft(
          SizedBox(
            width: 240,
            child: IntrinsicHeight(
              child: ConstraintLayout(
                children: [
                  ...titled(),
                  Constrained(
                    id: #field,
                    start: .startOf(parent, margin: 60),
                    end: .endOf(parent, margin: 8),
                    top: .bottomOf(#value, margin: 4),
                    width: .matchConstraint,
                    child: ValueListenableBuilder<String>(
                      valueListenable: typed,
                      builder: (context, value, _) =>
                          Text(value, key: const ValueKey(#field), maxLines: 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final ro = layoutOf(tester);
      final size = ro.size;
      final engine = ro.debugDryEnginePasses;
      // A keystroke relays the field out at the same size: IntrinsicHeight
      // asks the layout again, which replays its last query.
      for (final text in ['ab', 'abc', 'abcd']) {
        typed.value = text;
        await tester.pump();
        expect(ro.size, size);
      }
      expect(ro.debugDryReplayPasses, greaterThanOrEqualTo(2));
      expect(
        ro.debugDryEnginePasses - engine,
        lessThanOrEqualTo(1 + (verifyReplay ? 3 : 0)),
      );
      expect(ro.debugDryReplayMismatches, 0);
    });
  });

  group('children that cannot be measured dry', () {
    Widget builderChild({required bool fixed}) => Constrained(
      id: #builder,
      start: .startOf(parent),
      top: .topOf(parent),
      width: fixed ? .fixed(80) : .wrapContent,
      height: fixed ? .fixed(40) : .wrapContent,
      child: LayoutBuilder(
        builder: (context, constraints) =>
            const SizedBox(width: 80, height: 40),
      ),
    );

    List<Widget> withBuilder({required bool fixed}) => [
      builderChild(fixed: fixed),
      Constrained(
        id: #below,
        start: .startOf(parent),
        top: .topOf(parent, margin: 50),
        width: .fixed(60),
        height: .fixed(30),
        child: const SizedBox(),
      ),
    ];

    testWidgets('a child with a fixed size is never asked', (tester) async {
      await withIntrinsicChecks(() async {
        await tester.pumpWidget(
          topLeft(
            SizedBox(
              width: 300,
              child: IntrinsicHeight(
                child: ConstraintLayout(children: withBuilder(fixed: true)),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(ConstraintLayout)),
          const Size(300, 80),
        );
      });
    });

    testWidgets('a failing child is reported, and the query still answers', (
      tester,
    ) async {
      await tester.pumpWidget(
        topLeft(
          SizedBox(
            width: 300,
            height: 200,
            child: ConstraintLayout(children: withBuilder(fixed: false)),
          ),
        ),
      );
      final ro = layoutOf(tester);

      late double height;
      final errors = await reportedDuring(() async {
        height = ro.getMaxIntrinsicHeight(300);
      });
      // The LayoutBuilder counts as empty: only the box below it remains.
      expect(height, 80);
      expect(errors, hasLength(1));
      final details = errors.single;
      expect(details.library, 'flutter_constraint_layout');
      expect(
        details.exceptionAsString(),
        contains('does not support dry layout'),
      );
      expect(details.toString(), contains('The ConstraintLayout was'));
      expect(details.toString(), contains('The child was'));

      // The query left this layout's own dry-layout bookkeeping intact (a
      // dry layout that threw would fail an assertion on the next one),
      // even though Flutter leaves the LayoutBuilder itself unable to
      // answer again.
      final again = await reportedDuring(() async {
        expect(
          ro.getDryLayout(const BoxConstraints(maxWidth: 300)),
          const Size(300, 80),
        );
      });
      expect(again, hasLength(1));
    });
  });
}
