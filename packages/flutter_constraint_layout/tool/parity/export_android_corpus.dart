// Writes the Android parity corpus of the adapter,
// test/parity/android_corpus.json: layouts of the parity corpus FL, each
// with the widget tree that expresses it through the Flutter API and the
// frames Android's ConstraintLayout gives it. See test/parity/README.md.
//
//   dart run tool/parity/export_android_corpus.dart <FL.txt> <FL.J257.java> \
//       <out.json> [--seed N] [--per-generator N] [--fixed-zero-flows N]
//
// <FL.txt> holds corpus lines (`id \t features \t path \t status \t
// geometry \t ops`); <FL.J257.java> the oracle's results for them
// (`id \t status \t geometry ...`, VOpDriver at level 257, view path). The
// same inputs and options give the same file.
//
// The Java side of a written file alone:
//
//   dart run tool/parity/export_android_corpus.dart --ops <json> <out.in>
//       writes `id \t ops` lines, the oracle's batch input;
//   dart run tool/parity/export_android_corpus.dart --check <json> <java>
//       compares every entry's geometry with the oracle's result file.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'fl_model.dart';

const _usage =
    'usage: dart run tool/parity/export_android_corpus.dart <FL.txt> '
    '<FL.J257.java> <out.json> [--seed N] [--per-generator N] '
    '[--fixed-zero-flows N]';

void main(List<String> args) {
  if (args.length == 3 && args[0] == '--ops') {
    _writeOps(args[1], args[2]);
    return;
  }
  if (args.length == 3 && args[0] == '--check') {
    _check(args[1], args[2]);
    return;
  }
  final positional = <String>[];
  var seed = 20261026;
  var perGenerator = 80;
  var fixedZeroFlows = 40;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--seed':
        seed = int.parse(args[++i]);
      case '--per-generator':
        perGenerator = int.parse(args[++i]);
      case '--fixed-zero-flows':
        fixedZeroFlows = int.parse(args[++i]);
      default:
        positional.add(args[i]);
    }
  }
  if (positional.length != 3) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  final [corpusPath, javaPath, outPath] = positional;

  // The oracle's status and geometry at 257, by id.
  final java = <String, (String, String)>{};
  for (final line in File(javaPath).readAsLinesSync()) {
    final f = line.split('\t');
    if (f.length < 3) continue;
    java[f[0]] = (f[1], f[2]);
  }

  // Candidates by generator, in corpus order: mapped, and finished by Java.
  final byGenerator = <String, List<_Candidate>>{};
  var unmapped = 0, skipped = 0;
  for (final line in File(corpusPath).readAsLinesSync()) {
    if (line.isEmpty) continue;
    final layout = mapCorpusLine(line);
    if (layout.unmapped != null) {
      unmapped++;
      continue;
    }
    final result = java[layout.id];
    if (result == null || result.$1 != 'ok') {
      skipped++;
      continue;
    }
    final generator = layout.id.split(':').first;
    (byGenerator[generator] ??= []).add(_Candidate(layout, result.$2));
  }

  final random = Random(seed);
  final chosen = <_Candidate>[];
  final generators = byGenerator.keys.toList()..sort();
  for (final generator in generators) {
    chosen.addAll(
      _select(
        byGenerator[generator]!,
        perGenerator,
        generator == 'T-virtual' ? fixedZeroFlows : 0,
        random,
      ),
    );
  }

  final out = StringBuffer('[\n');
  for (var i = 0; i < chosen.length; i++) {
    final c = chosen[i];
    out
      ..write(
        jsonEncode({
          'id': c.layout.id,
          'ops': c.layout.ops,
          'tree': c.layout.toJson(),
          'geometry': c.geometry,
        }),
      )
      ..write(i == chosen.length - 1 ? '\n' : ',\n');
  }
  out.write(']\n');
  File(outPath).writeAsStringSync(out.toString());
  stdout.writeln(
    'wrote ${chosen.length} entries (${generators.length} generators; '
    'unmapped $unmapped, not ok in Java $skipped) to $outPath',
  );
}

class _Candidate {
  _Candidate(this.layout, this.geometry)
    : tags = {
        for (final t in layout.features.split(','))
          if (t.isNotEmpty && t != '-') t,
        if (layout.rtl) 'rtl',
        if (!layout.maxW.isFinite) 'unboundedW',
        if (!layout.maxH.isFinite) 'unboundedH',
        if (layout.hasFixedZeroFlow) 'fixedZeroFlow',
      };

  final FlLayout layout;
  final String geometry;
  final Set<String> tags;
}

/// [budget] layouts of one generator: a greedy cover of its tags (each tag
/// twice), the [fixedZeroFlows] shortest layouts with a `.fixed(0)` flow,
/// then a seeded draw from the shorter half, every step preferring the
/// shorter op list.
List<_Candidate> _select(
  List<_Candidate> candidates,
  int budget,
  int fixedZeroFlows,
  Random random,
) {
  final byLength = [...candidates]
    ..sort((a, b) {
      final c = a.layout.ops.length.compareTo(b.layout.ops.length);
      return c != 0 ? c : a.layout.id.compareTo(b.layout.id);
    });
  final taken = <_Candidate>{};
  final covered = <String, int>{};
  for (final c in byLength) {
    if (taken.length >= budget) break;
    if (c.tags.any((t) => (covered[t] ?? 0) < 2)) {
      taken.add(c);
      for (final t in c.tags) {
        covered[t] = (covered[t] ?? 0) + 1;
      }
    }
  }
  var zero = taken.where((c) => c.layout.hasFixedZeroFlow).length;
  for (final c in byLength) {
    if (zero >= fixedZeroFlows || taken.length >= budget) break;
    if (c.layout.hasFixedZeroFlow && taken.add(c)) zero++;
  }
  final shorter = byLength.sublist(0, (byLength.length + 1) ~/ 2)
    ..shuffle(random);
  for (final c in shorter) {
    if (taken.length >= budget) break;
    taken.add(c);
  }
  // Corpus order, so the file reads like the corpus.
  return [
    for (final c in candidates)
      if (taken.contains(c)) c,
  ];
}

List<Map<String, Object?>> _entries(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List<Object?>)
        .cast<Map<String, Object?>>();

/// Writes the op lists of the corpus file [jsonPath] as the oracle's batch
/// input, `id \t ops` per line.
void _writeOps(String jsonPath, String outPath) {
  final entries = _entries(jsonPath);
  File(outPath).writeAsStringSync(
    entries.map((e) => '${e['id']}\t${e['ops']}\n').join(),
  );
  stdout.writeln('wrote ${entries.length} op lists to $outPath');
}

/// Compares the geometry of every entry of [jsonPath] with the oracle's
/// result file [javaPath] (its first geometry field), and reports the
/// entries that differ or are missing.
void _check(String jsonPath, String javaPath) {
  final java = <String, String>{};
  for (final line in File(javaPath).readAsLinesSync()) {
    final f = line.split('\t');
    if (f.length >= 3 && f[1] == 'ok') java[f[0]] = f[2];
  }
  var differ = 0;
  final entries = _entries(jsonPath);
  for (final e in entries) {
    final geometry = java[e['id']];
    if (geometry != e['geometry']) {
      differ++;
      stdout.writeln('${e['id']}: ${geometry ?? 'missing'}');
    }
  }
  stdout.writeln('${entries.length} entries, $differ differ');
  if (differ > 0) exitCode = 1;
}
