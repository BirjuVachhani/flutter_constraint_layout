// Links that loop back on themselves.
//
// Two children whose tops link to each other, an edge linked to itself, or
// two children linked both ways on both sides used to freeze the app: the
// engine's chain walk went round the loop forever. Android lays these out. A
// chain whose first child's start links one way to its last child, while the
// last child's end links back to the first child, froze the app too, and
// Android never finishes laying it out. The engine now lays every kind out,
// the others as Android does. No child of such a loop has a position to start
// from, so, like an unknown id, a debug build reports the links. Baseline
// links are not followed, so two baselines linked to each other are not
// reported.

import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [children] in a 375 x 100 layout and returns every error the
/// layout reported.
Future<List<String>> layoutErrors(
  WidgetTester tester,
  List<Widget> children, {
  TextDirection direction = TextDirection.ltr,
}) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  try {
    await tester.pumpWidget(
      Directionality(
        textDirection: direction,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 375,
            height: 100,
            child: ConstraintLayout(children: children),
          ),
        ),
      ),
    );
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

/// Matches reported errors where one reports the loop of [links].
Matcher reportsLoop(String links) => predicate<List<String>>(
  (errors) => errors.any(
    (e) => e.contains('Constrained links loop back on themselves: $links.'),
  ),
  'reports the loop $links',
);

Widget box(
  Symbol id, {
  HorizontalLink? start,
  HorizontalLink? end,
  VerticalLink? top,
}) => Constrained(
  id: id,
  start: start,
  end: end,
  top: top,
  width: .fixed(100),
  height: .fixed(40),
  child: const SizedBox(),
);

void main() {
  group('links that loop back on themselves are reported', () {
    testWidgets('two tops linked to each other', (tester) async {
      final errors = await layoutErrors(tester, [
        box(#a, top: .topOf(#b), start: .startOf(parent)),
        box(#b, top: .topOf(#a), start: .endOf(#a)),
      ]);
      expect(
        errors,
        reportsLoop(
          'Symbol("a") top to Symbol("b") top, '
          'Symbol("b") top to Symbol("a") top',
        ),
      );
    });

    testWidgets('an end linked to itself, right to left', (tester) async {
      final errors = await layoutErrors(tester, [
        box(#a, end: .endOf(#a)),
      ], direction: TextDirection.rtl);
      expect(errors, reportsLoop('Symbol("a") end to Symbol("a") end'));
    });

    testWidgets(
      'a chain whose first child\'s start links one way to its last child, '
      'while the last child\'s end links back to the first child',
      (tester) async {
        final errors = await layoutErrors(tester, [
          box(#h, start: .startOf(#a), end: .startOf(#a)),
          box(#a, start: .endOf(#h), end: .startOf(#h)),
        ]);
        expect(
          errors,
          reportsLoop(
            'Symbol("h") end to Symbol("a") start, '
            'Symbol("a") end to Symbol("h") start',
          ),
        );
      },
    );

    testWidgets('a chain is not a loop', (tester) async {
      final errors = await layoutErrors(tester, [
        box(#a, start: .startOf(parent), end: .startOf(#b)),
        box(#b, start: .endOf(#a), end: .endOf(parent)),
      ]);
      expect(errors, isEmpty);
    });
  });
}
