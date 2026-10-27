// The adapter's Android parity corpus: 1,600 layouts of the parity corpus
// FL, each a real ConstraintLayout widget tree with the frames Android's
// ConstraintLayout gives the same layout. Every tree is laid out through the
// adapter and must give Android's geometry string exactly: the layout's size
// and every child's offset and size, guidelines and barriers included (they
// are gone widgets at 0 x 0, as Android's view helpers are).
//
// The reference is the pinned parity oracle (VOpDriver at
// OPTIMIZATION_STANDARD, the view path); nothing here is computed by the
// adapter. See README.md in this directory for the trees, how the layouts
// were chosen and how to regenerate both sides.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import 'parity_tree.dart';

/// One corpus entry: the layout's id in FL, its op list, the widget tree
/// that expresses it, and Java's geometry.
typedef _Entry = ({
  String id,
  String ops,
  Map<String, Object?> tree,
  String geometry,
});

List<_Entry> _load() {
  final file = File('test/parity/android_corpus.json');
  final data = jsonDecode(file.readAsStringSync()) as List<Object?>;
  return [
    for (final e in data.cast<Map<String, Object?>>())
      (
        id: e['id']! as String,
        ops: e['ops']! as String,
        tree: e['tree']! as Map<String, Object?>,
        geometry: e['geometry']! as String,
      ),
  ];
}

String _generatorOf(String id) => id.substring(0, id.indexOf(':'));

void main() {
  final entries = _load();
  final generators = {for (final e in entries) _generatorOf(e.id)}.toList()
    ..sort();

  test('the corpus holds every generator of FL', () {
    expect(generators, hasLength(20));
    expect(entries.length, greaterThanOrEqualTo(1500));
    expect({for (final e in entries) e.id}, hasLength(entries.length));
  });

  for (final generator in generators) {
    testWidgets('$generator: every frame is Android\'s', (tester) async {
      final mine = [
        for (final e in entries)
          if (_generatorOf(e.id) == generator) e,
      ];
      final differ = <String>[];
      for (var i = 0; i < mine.length; i++) {
        final e = mine[i];
        // A fresh render object for every layout, as the oracle builds one.
        await tester.pumpWidget(
          buildTree(e.tree, key: ValueKey<int>(i)),
          phase: EnginePhase.layout,
        );
        final error = tester.takeException();
        final ro = tester.renderObject<RenderConstraintLayout>(
          find.byType(ConstraintLayout),
        );
        final geometry = error == null
            ? geometryOf(ro, e.tree)
            : 'EXC: ${error.toString().split('\n').first}';
        if (geometry != e.geometry) {
          differ.add('${e.id}\n  adapter: $geometry\n  android: ${e.geometry}');
        }
      }
      expect(
        differ,
        isEmpty,
        reason:
            '${differ.length} of ${mine.length} $generator layouts differ '
            'from Android:\n${differ.join('\n')}',
      );
    });
  }
}
