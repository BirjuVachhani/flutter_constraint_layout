// Copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0
//
// No upstream counterpart. The engine's parity corpus at the dependency-graph
// optimization levels: 560 layouts, each an op list with the status and
// geometry the pinned Java oracle (upstream's core at the pin, driven by
// VOpDriver) computed for it at OPTIMIZATION_GRAPH (64),
// OPTIMIZATION_STANDARD | OPTIMIZATION_GRAPH (321), and the
// OPTIMIZATION_GRAPH_WRAP levels 192 and 449, on the core path or the view
// path. At those levels BasicMeasure runs upstream's DependencyGraph before,
// or instead of, the solver, and the solver reads what the graph resolved.
// The layouts are ones on which the engine before its graph was reconciled
// with upstream's (every port-only decline and rounding change reverted)
// differed from Java, picked to cover every generator and every kind of
// difference; select_graph_corpus.py in this directory chooses them and
// documents the Java runs. Every entry is replayed through
// test/support/op_replay.dart at its level and must give Java's strings
// exactly.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/op_replay.dart';

/// One corpus entry: the layout's id in the parity corpora, the path that
/// replays it (`core<level>` or `view<level>`), its op list, and Java's
/// status and geometry on that path.
typedef _Entry = ({
  String id,
  String path,
  String ops,
  String status,
  String geometry,
});

List<_Entry> _load() {
  final file = File('test/parity/graph_corpus.json');
  final data = jsonDecode(file.readAsStringSync()) as List<Object?>;
  return [
    for (final e in data.cast<Map<String, Object?>>())
      (
        id: e['id']! as String,
        path: e['path']! as String,
        ops: e['ops']! as String,
        status: e['status']! as String,
        geometry: e['geometry']! as String,
      ),
  ];
}

void main() {
  final entries = _load();
  const paths = [
    'core64',
    'core321',
    'core192',
    'core449',
    'view321',
    'view192',
    'view449',
  ];

  test('the corpus holds every path', () {
    expect({for (final e in entries) e.path}, containsAll(paths));
    expect(entries.length, greaterThan(500));
  });

  for (final path in paths) {
    test('$path: every layout gives Java\'s status and frames', () {
      final core = path.startsWith('core');
      final level = int.parse(path.substring(4));
      final own = entries.where((e) => e.path == path).toList();
      expect(own, isNotEmpty);
      final mismatches = <String>[];
      for (final e in own) {
        final r = core
            ? replayCore(e.ops, level: level)
            : replayView(e.ops, level: level);
        if (r.status != e.status || r.geometry != e.geometry) {
          mismatches.add(
            '${e.id}\n'
            '  Java: ${e.status} | ${e.geometry}\n'
            '  Dart: ${r.status} | ${r.geometry}',
          );
        }
      }
      expect(
        mismatches,
        isEmpty,
        reason:
            '${mismatches.length} of ${own.length} $path layouts differ from '
            'Java; the first ones:\n${mismatches.take(5).join('\n')}',
      );
    });
  }
}
