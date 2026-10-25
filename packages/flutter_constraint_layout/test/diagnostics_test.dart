// Diagnostics and render-object surface.
//
// Two things live here. First, the errors: every link and helper reference is
// resolved by id, and a typo'd id is the single most likely authoring mistake.
// The engine cannot do anything sensible with a dangling reference, so the
// adapter throws a FlutterError naming the id rather than silently dropping
// the constraint and leaving the author to wonder why a widget did not move.
// Those throws are assert-guarded, so they are debug-only; these tests pin the
// message and prove the layout does not also corrupt itself on the way out.
//
// Second, the RenderConstraintLayout API that widgets and tests drive
// directly: the direction getter, the debug hooks, and the child-list
// overrides that keep the persistent engine model honest.

import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  List<Widget> children, {
  TextDirection direction = TextDirection.ltr,
  bool showBlueprint = false,
  DebugLabelStyle labelStyle = DebugLabelStyle.both,
}) => Directionality(
  textDirection: direction,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 400,
      height: 300,
      child: ConstraintLayout(
        debugShowBlueprint: showBlueprint,
        debugBlueprintLabelStyle: labelStyle,
        children: children,
      ),
    ),
  ),
);

RenderConstraintLayout roOf(WidgetTester tester) =>
    tester.renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout));

/// Pumps [children] and returns every error the layout reported.
///
/// A layout can run several passes, so one bad id is reported more than once.
/// Intercepting `FlutterError.onError` collects them all and keeps them away
/// from the test binding, which would otherwise fail the test with a
/// "multiple exceptions" summary that hides the messages being asserted on.
Future<List<String>> layoutErrors(
  WidgetTester tester,
  List<Widget> children,
) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  try {
    await tester.pumpWidget(host(children));
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

/// Matches a list of reported errors where at least one mentions [text].
Matcher reportsError(String text) => predicate<List<String>>(
  (errors) => errors.any((e) => e.contains(text)),
  'reports an error containing "$text"',
);

void main() {
  group('unknown ids are reported, not ignored', () {
    testWidgets('a horizontal link to a missing sibling', (tester) async {
      final errors = await layoutErrors(tester, [
        Constrained(
          id: #a,
          start: .endOf(#nope, margin: 8),
          width: .fixed(40),
          height: .fixed(40),
          child: const SizedBox(),
        ),
      ]);
      expect(
        errors,
        reportsError('Constrained link targets unknown id Symbol("nope")'),
      );
    });

    testWidgets('a vertical link to a missing sibling', (tester) async {
      final errors = await layoutErrors(tester, [
        Constrained(
          id: #a,
          top: .bottomOf(#ghost),
          width: .fixed(40),
          height: .fixed(40),
          child: const SizedBox(),
        ),
      ]);
      expect(errors, reportsError('Constrained link targets unknown id Symbol("ghost")'));
    });

    testWidgets('a circular link to a missing hub', (tester) async {
      final errors = await layoutErrors(tester, [
        Constrained(
          id: #a,
          circle: .around(#hub, angle: 45, radius: 50),
          width: .fixed(20),
          height: .fixed(20),
          child: const SizedBox(),
        ),
      ]);
      expect(errors, reportsError('CircularLink targets unknown id Symbol("hub")'));
    });

    testWidgets('a barrier referencing a missing widget', (tester) async {
      final errors = await layoutErrors(tester, [
        Constrained(
          id: #a,
          width: .fixed(40),
          height: .fixed(40),
          child: const SizedBox(),
        ),
        const Barrier(id: #bar, edge: .end, referenced: [#a, #missing]),
      ]);
      expect(errors, reportsError('Barrier references unknown id Symbol("missing")'));
    });

    testWidgets('a flow referencing a missing widget', (tester) async {
      final errors = await layoutErrors(tester, [
        Constrained(
          id: #a,
          width: .fixed(40),
          height: .fixed(40),
          child: const SizedBox(),
        ),
        const ConstraintFlow(
          id: #flow,
          referenced: [#a, #missing],
          start: .startOf(parent),
          top: .topOf(parent),
        ),
      ]);
      expect(errors, reportsError('ConstraintFlow references unknown id Symbol("missing")'));
    });

    testWidgets('a grid referencing a missing widget', (tester) async {
      final errors = await layoutErrors(tester, [
        Constrained(
          id: #a,
          width: .fixed(40),
          height: .fixed(40),
          child: const SizedBox(),
        ),
        const ConstraintGrid(
          id: #grid,
          referenced: [#a, #missing],
          rows: 1,
          columns: 2,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
        ),
      ]);
      expect(errors, reportsError('ConstraintGrid references unknown id Symbol("missing")'));
    });

    testWidgets('a group referencing a missing widget', (tester) async {
      final errors = await layoutErrors(tester, [
        Constrained(
          id: #a,
          width: .fixed(40),
          height: .fixed(40),
          child: const SizedBox(),
        ),
        const ConstraintGroup(id: #group, referenced: [#a, #missing]),
      ]);
      expect(
        errors,
        reportsError('ConstraintGroup references unknown id Symbol("missing")'),
      );
    });

    // A group has no position or size, so it is not a target. The message
    // says what the id is rather than calling it unknown.
    testWidgets('a link to a group', (tester) async {
      final errors = await layoutErrors(tester, [
        Constrained(
          id: #a,
          width: .fixed(40),
          height: .fixed(40),
          child: const SizedBox(),
        ),
        Constrained(
          id: #b,
          top: .bottomOf(#group),
          width: .fixed(40),
          height: .fixed(40),
          child: const SizedBox(),
        ),
        const ConstraintGroup(id: #group, referenced: [#a]),
      ]);
      expect(
        errors,
        reportsError(
          'Constrained link targets Symbol("group"), which is a '
          'ConstraintGroup. A group has no position or size',
        ),
      );
    });

    testWidgets('a barrier or another group referencing a group', (
      tester,
    ) async {
      final barrierErrors = await layoutErrors(tester, [
        Constrained(
          id: #a,
          width: .fixed(40),
          height: .fixed(40),
          child: const SizedBox(),
        ),
        const ConstraintGroup(id: #group, referenced: [#a]),
        const Barrier(id: #bar, edge: .end, referenced: [#a, #group]),
      ]);
      expect(
        barrierErrors,
        reportsError(
          'Barrier references Symbol("group"), which is a ConstraintGroup',
        ),
      );

      final groupErrors = await layoutErrors(tester, [
        Constrained(
          id: #a,
          width: .fixed(40),
          height: .fixed(40),
          child: const SizedBox(),
        ),
        const ConstraintGroup(id: #inner, referenced: [#a]),
        const ConstraintGroup(id: #outer, referenced: [#inner]),
      ]);
      expect(
        groupErrors,
        reportsError(
          'ConstraintGroup references Symbol("inner"), which is a '
          'ConstraintGroup',
        ),
      );
    });

    testWidgets('a bad id aborts the pass, and fixing it recovers', (
      tester,
    ) async {
      // The throw unwinds out of performLayout, so the whole pass is abandoned
      // rather than half-applied: siblings stay unpositioned. That is the
      // debug contract. With asserts compiled out the link is skipped instead
      // and the rest of the layout resolves.
      final errors = await layoutErrors(tester, [
        Constrained(
          id: #good,
          start: .startOf(parent, margin: 20),
          top: .topOf(parent, margin: 20),
          width: .fixed(80),
          height: .fixed(40),
          child: const SizedBox(key: ValueKey(#good)),
        ),
        Constrained(
          id: #bad,
          start: .endOf(#nope),
          width: .fixed(40),
          height: .fixed(40),
          child: const SizedBox(key: ValueKey(#bad)),
        ),
      ]);
      expect(
        errors,
        reportsError('Constrained link targets unknown id Symbol("nope")'),
      );

      // What matters is that the aborted pass leaves no wreckage in the
      // persistent engine model: correcting the id lays out normally, with no
      // rebuild of the widget tree.
      await tester.pumpWidget(
        host([
          Constrained(
            id: #good,
            start: .startOf(parent, margin: 20),
            top: .topOf(parent, margin: 20),
            width: .fixed(80),
            height: .fixed(40),
            child: const SizedBox(key: ValueKey(#good)),
          ),
          Constrained(
            id: #bad,
            start: .endOf(#good, margin: 10),
            top: .topOf(#good),
            width: .fixed(40),
            height: .fixed(40),
            child: const SizedBox(key: ValueKey(#bad)),
          ),
        ]),
      );
      expect(tester.takeException(), isNull);

      final ro = roOf(tester);
      final good = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey(#good)),
      );
      final bad = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey(#bad)),
      );
      expect(good.localToGlobal(Offset.zero, ancestor: ro), const Offset(20, 20));
      expect(bad.localToGlobal(Offset.zero, ancestor: ro), const Offset(110, 20));
    });
  });

  group('render object surface', () {
    testWidgets('exposes the direction it resolves start/end with', (
      tester,
    ) async {
      await tester.pumpWidget(host(const []));
      expect(roOf(tester).textDirection, TextDirection.ltr);

      await tester.pumpWidget(host(const [], direction: TextDirection.rtl));
      expect(roOf(tester).textDirection, TextDirection.rtl);
    });

    testWidgets('exposes the engine container once a layout has run', (
      tester,
    ) async {
      await tester.pumpWidget(
        host([
          Constrained(
            id: #a,
            start: .startOf(parent),
            top: .topOf(parent),
            width: .fixed(40),
            height: .fixed(40),
            child: const SizedBox(),
          ),
        ]),
      );
      final container = roOf(tester).debugEngineContainer;
      expect(container, isNotNull);
      expect(container!.getWidth(), 400);
      expect(container.getHeight(), 300);
    });

    testWidgets('an empty layout discards the model and takes the smallest size',
        (tester) async {
      await tester.pumpWidget(
        host([
          Constrained(
            id: #a,
            start: .startOf(parent),
            top: .topOf(parent),
            width: .fixed(40),
            height: .fixed(40),
            child: const SizedBox(),
          ),
        ]),
      );
      expect(roOf(tester).debugEngineContainer, isNotNull);

      // Dropping to no children must release the model, not keep a stale one
      // that a later re-populate could resolve against.
      await tester.pumpWidget(host(const []));
      final ro = roOf(tester);
      expect(ro.debugEngineContainer, isNull);
      expect(ro.size, const Size(400, 300));

      // Re-populating rebuilds from scratch and lays out correctly.
      await tester.pumpWidget(
        host([
          Constrained(
            id: #b,
            start: .startOf(parent, margin: 12),
            top: .topOf(parent, margin: 12),
            width: .fixed(40),
            height: .fixed(40),
            child: const SizedBox(key: ValueKey(#b)),
          ),
        ]),
      );
      final b = tester.renderObject<RenderBox>(find.byKey(const ValueKey(#b)));
      expect(
        b.localToGlobal(Offset.zero, ancestor: roOf(tester)),
        const Offset(12, 12),
      );
    });

    testWidgets('changing the blueprint label style only repaints', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          [
            Constrained(
              id: #a,
              start: .startOf(parent, margin: 10),
              top: .topOf(parent, margin: 10),
              width: .fixed(60),
              height: .fixed(30),
              child: const SizedBox(),
            ),
          ],
          showBlueprint: true,
        ),
      );
      final ro = roOf(tester);
      final layouts = ro.debugLayoutPasses;

      await tester.pumpWidget(
        host(
          [
            Constrained(
              id: #a,
              start: .startOf(parent, margin: 10),
              top: .topOf(parent, margin: 10),
              width: .fixed(60),
              height: .fixed(30),
              child: const SizedBox(),
            ),
          ],
          showBlueprint: true,
          labelStyle: DebugLabelStyle.none,
        ),
      );
      expect(ro.debugLayoutPasses, layouts, reason: 'label style is paint-only');
      expect(tester.takeException(), isNull);
    });

    test('removeAll drops every child and forces a rebuild', () {
      // Exercised directly: the framework removes children one at a time, so
      // this override is only reachable from code that clears the list in one
      // go. It still has to invalidate the persistent model.
      final ro = RenderConstraintLayout(textDirection: TextDirection.ltr);
      final children = [
        for (var i = 0; i < 3; i++)
          RenderConstrainedBox(
            additionalConstraints: BoxConstraints.tight(const Size(10, 10)),
          ),
      ];
      for (final child in children) {
        ro.add(child);
      }
      expect(ro.childCount, 3);

      ro.removeAll();
      expect(ro.childCount, 0);
      expect(ro.firstChild, isNull);
    });
  });

  testWidgets('an unknown id applied in place is reported again on the next '
      'layout, not left half-applied', (tester) async {
    List<Widget> children(Symbol target) => [
      Constrained(
        id: #a,
        start: .startOf(parent, margin: 10),
        top: .topOf(parent, margin: 10),
        width: .fixed(50),
        height: .fixed(50),
        child: const SizedBox(),
      ),
      Constrained(
        id: #b,
        start: .endOf(target, margin: 5),
        top: .bottomOf(#a, margin: 7),
        width: .fixed(20),
        height: .fixed(20),
        child: const SizedBox(),
      ),
    ];
    List<Rect> rects() => [
      for (final child in roOf(tester).getChildrenAsList())
        (child.parentData! as BoxParentData).offset & child.size,
    ];
    await tester.pumpWidget(host(children(#a)));
    final ro = roOf(tester);
    final good = rects();

    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exceptionAsString());
    try {
      await tester.pumpWidget(host(children(#nope)));
      expect(errors, contains(contains('unknown id Symbol("nope")')));
      errors.clear();
      ro.markNeedsLayout();
      await tester.pump();
      expect(
        errors,
        contains(contains('unknown id Symbol("nope")')),
        reason: 'the next layout reports it again',
      );
      expect(rects(), good, reason: 'no half-applied widget');
    } finally {
      FlutterError.onError = previous;
    }
  });
}
