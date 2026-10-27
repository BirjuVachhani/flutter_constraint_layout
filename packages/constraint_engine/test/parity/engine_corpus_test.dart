// Copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0
//
// No upstream counterpart. The engine's parity corpus: about 2,000 layouts,
// each an op list with the status and geometry the pinned Java oracle
// (upstream's core at the pin, driven by VOpDriver) computed for it. Every
// entry is replayed through test/support/op_replay.dart on its path and must
// give Java's strings exactly: every child's frame, the container's size, and
// whether the solver loop printed a caught exception. See README.md in this
// directory for how the layouts were chosen and how to regenerate both sides.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/op_replay.dart';

/// One corpus entry: the layout's id in the parity corpora, the path that
/// replays it (`core257`, `view257`, `core0` or `view0`), its op list, and
/// Java's status and geometry on that path.
typedef _Entry = ({
  String id,
  String path,
  String ops,
  String status,
  String geometry,
});

List<_Entry> _load() {
  final file = File('test/parity/engine_corpus.json');
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

  test('the corpus holds every path', () {
    final paths = {for (final e in entries) e.path};
    expect(
      paths,
      containsAll(<String>['core257', 'view257', 'core0', 'view0']),
    );
    expect(entries.length, greaterThan(1900));
  });

  for (final path in const ['core257', 'view257', 'core0', 'view0']) {
    test('$path: every layout gives Java\'s status and frames', () {
      final level = path.endsWith('257') ? 257 : 0;
      final core = path.startsWith('core');
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
