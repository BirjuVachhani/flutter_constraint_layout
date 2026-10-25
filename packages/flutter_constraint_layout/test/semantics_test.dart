// Semantics follow visibility: a child that is invisible or gone, by its own
// visibility or a ConstraintGroup's, is neither painted nor hit-tested, so a
// screen reader must neither announce nor activate it. Android likewise
// leaves views that are not VISIBLE out of the accessibility tree.

import 'package:flutter/material.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a hidden button can be neither found nor activated by a '
      'screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    final taps = <String>[];
    for (final viaGroup in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConstraintLayout(
              children: [
                Constrained(
                  id: #pay,
                  start: .startOf(parent),
                  top: .topOf(parent),
                  visibility: viaGroup ? .visible : .invisible,
                  child: ElevatedButton(
                    onPressed: () => taps.add('pay'),
                    child: const Text('Pay'),
                  ),
                ),
                ConstraintGroup(
                  id: #g,
                  referenced: viaGroup ? const [#pay] : const [],
                  visibility: viaGroup ? .invisible : .visible,
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        find.semantics.byLabel('Pay'),
        findsNothing,
        reason: viaGroup ? 'an invisible group' : 'an invisible child',
      );
    }
    expect(taps, isEmpty);
    handle.dispose();
  });

  testWidgets('a merging ancestor leaves hidden children out of its label, '
      'and follows a group toggled in place', (tester) async {
    final handle = tester.ensureSemantics();
    Widget app(ConstraintVisibility group) => MaterialApp(
      home: Scaffold(
        body: MergeSemantics(
          child: ConstraintLayout(
            children: [
              Constrained(
                id: #shown,
                start: .startOf(parent),
                top: .topOf(parent),
                child: const Text('Shown'),
              ),
              Constrained(
                id: #invisible,
                start: .startOf(parent),
                top: .topOf(parent, margin: 30),
                visibility: .invisible,
                child: const Text('Invisible'),
              ),
              Constrained(
                id: #gone,
                start: .startOf(parent),
                top: .topOf(parent, margin: 60),
                visibility: .gone,
                child: const Text('Gone'),
              ),
              Constrained(
                id: #member,
                start: .startOf(parent),
                top: .topOf(parent, margin: 90),
                child: const Text('Member'),
              ),
              ConstraintGroup(
                id: #g,
                referenced: const [#member],
                visibility: group,
              ),
            ],
          ),
        ),
      ),
    );
    for (final (group, label) in [
      (ConstraintVisibility.visible, 'Shown\nMember'),
      (ConstraintVisibility.invisible, 'Shown'),
      (ConstraintVisibility.gone, 'Shown'),
      (ConstraintVisibility.visible, 'Shown\nMember'),
    ]) {
      await tester.pumpWidget(app(group));
      expect(
        tester.getSemantics(find.byType(ConstraintLayout)).label,
        label,
        reason: 'a ${group.name} group',
      );
    }
    handle.dispose();
  });
}
