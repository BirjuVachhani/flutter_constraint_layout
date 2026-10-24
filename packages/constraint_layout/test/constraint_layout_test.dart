import 'package:constraint_layout/constraint_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps [layout] in an 800x600 box at the top-left so child offsets read as
/// absolute coordinates within the ConstraintLayout.
Future<void> _pump(WidgetTester tester, ConstraintLayout layout) {
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 800, height: 600, child: layout),
      ),
    ),
  );
}

void main() {
  testWidgets('pins a fixed box to the top-start corner with margins', (
    tester,
  ) async {
    await _pump(
      tester,
      ConstraintLayout(
        children: [
          Constrained(
            id: #box,
            top: .topOf(parent, margin: 24),
            start: .startOf(parent, margin: 32),
            width: .fixed(120),
            height: .fixed(120),
            child: const SizedBox(key: Key('box')),
          ),
        ],
      ),
    );

    expect(tester.getTopLeft(find.byKey(const Key('box'))), const Offset(32, 24));
    expect(tester.getSize(find.byKey(const Key('box'))), const Size(120, 120));
  });

  testWidgets('centers a box between parent start and end (default bias)', (
    tester,
  ) async {
    await _pump(
      tester,
      ConstraintLayout(
        children: [
          Constrained(
            id: #c,
            top: .topOf(parent),
            start: .startOf(parent),
            end: .endOf(parent),
            width: .fixed(100),
            height: .fixed(50),
            child: const SizedBox(key: Key('c')),
          ),
        ],
      ),
    );

    // Centered horizontally: (800 - 100) / 2 = 350.
    expect(tester.getTopLeft(find.byKey(const Key('c'))), const Offset(350, 0));
  });

  testWidgets('horizontalBias shifts the box toward the end', (tester) async {
    await _pump(
      tester,
      ConstraintLayout(
        children: [
          Constrained(
            id: #c,
            top: .topOf(parent),
            start: .startOf(parent),
            end: .endOf(parent),
            horizontalBias: 0.25,
            width: .fixed(100),
            height: .fixed(50),
            child: const SizedBox(key: Key('c')),
          ),
        ],
      ),
    );

    // slack = 800 - 100 = 700; left = 700 * 0.25 = 175.
    expect(tester.getTopLeft(find.byKey(const Key('c'))), const Offset(175, 0));
  });

  testWidgets('positions a widget relative to a sibling', (tester) async {
    await _pump(
      tester,
      ConstraintLayout(
        children: [
          Constrained(
            id: #header,
            top: .topOf(parent),
            start: .startOf(parent),
            width: .fixed(200),
            height: .fixed(60),
            child: const SizedBox(key: Key('header')),
          ),
          Constrained(
            id: #body,
            top: .bottomOf(#header, margin: 16),
            start: .startOf(#header),
            width: .fixed(200),
            height: .fixed(40),
            child: const SizedBox(key: Key('body')),
          ),
        ],
      ),
    );

    expect(tester.getTopLeft(find.byKey(const Key('body'))), const Offset(0, 76));
  });

  testWidgets('matchConstraint fills between opposing anchors', (tester) async {
    await _pump(
      tester,
      ConstraintLayout(
        children: [
          Constrained(
            id: #fill,
            top: .topOf(parent),
            start: .startOf(parent, margin: 20),
            end: .endOf(parent, margin: 20),
            width: .matchConstraint,
            height: .fixed(50),
            child: const SizedBox(key: Key('fill')),
          ),
        ],
      ),
    );

    expect(tester.getTopLeft(find.byKey(const Key('fill'))), const Offset(20, 0));
    expect(tester.getSize(find.byKey(const Key('fill'))).width, 760);
  });

  testWidgets('gone collapses the child to zero size', (tester) async {
    await _pump(
      tester,
      ConstraintLayout(
        children: [
          Constrained(
            id: #box,
            top: .topOf(parent),
            start: .startOf(parent),
            width: .fixed(120),
            height: .fixed(120),
            visibility: .gone,
            child: const SizedBox(key: Key('box')),
          ),
        ],
      ),
    );

    expect(tester.getSize(find.byKey(const Key('box'))), Size.zero);
  });

  testWidgets('wrap-content child takes its intrinsic size', (tester) async {
    await _pump(
      tester,
      ConstraintLayout(
        children: [
          Constrained(
            id: #chip,
            top: .topOf(parent),
            start: .startOf(parent),
            child: const SizedBox(key: Key('chip'), width: 88, height: 33),
          ),
        ],
      ),
    );

    expect(tester.getSize(find.byKey(const Key('chip'))), const Size(88, 33));
    expect(tester.getTopLeft(find.byKey(const Key('chip'))), Offset.zero);
  });
}
