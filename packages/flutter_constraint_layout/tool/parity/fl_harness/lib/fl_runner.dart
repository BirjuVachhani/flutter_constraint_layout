// The FL runner (FORMATS.md section 11): lays out corpus lines as real
// ConstraintLayout trees through flutter_test and writes section 1 lines
// (id, features, path, status, geometry, ops) for vcompare.
//
// Modes (dart-defines):
//   FL_DRY=true      also writes <out>.dry: `id \t equal|DIFF \t dry \t real`,
//                    the RenderConstraintLayout's getDryLayout under the same
//                    constraints against its laid-out size.
//   FL_INPLACE=true  for a line with `L` ops (T-inplace), pumps every state
//                    (the op list cut before each `L`, then all of it) into the
//                    same ConstraintLayout, so the adapter updates its model in
//                    place, and writes the final geometry; also writes
//                    <out>.fresh with a fresh build of the final state.
//   FL_REPLAY=true   (Phase 4) lays every layout out again four times in the
//                    same ConstraintLayout (markNeedsLayout), so the second
//                    layout confirms the first and the later ones replay it;
//                    run_fl.sh passes --dart-define=cl.verifyReplay=true with
//                    it, so every replay also runs in full and is checked.
//                    Writes <out>.replay (`id \t same|DIFF \t replays N \t
//                    mismatches M \t engine E \t second same|DIFF`, then the
//                    four later geometries when any differs from the first)
//                    and <out>.second (section 1 lines of the second layout,
//                    path fl-<tag>-second, for the comparison with Android's
//                    dirty second layout, FORMATS.md 19).
//   FL_TRANSCRIPT=true  (Phase 4) records the measure-request transcript of
//                    each layout's last engine run and writes <out>.T
//                    (`id \t T257 <entries>`, `T257 -` for none), the side
//                    file format of FORMATS.md 17.2 for tcompare.py.
//   FL_LEVEL=<n>     Android's optimization level of every ConstraintLayout
//                    (default 257, the adapter's default): each bit as its
//                    OptimizationLevel flag. The transcript lines then read
//                    `T<n>`.
// The runner is test support: it reads the layout's test instrumentation.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ftree.dart';

class FlRunConfig {
  const FlRunConfig({
    required this.input,
    required this.output,
    this.tag = 'today',
    this.shard = 0,
    this.shards = 1,
    this.limit = -1,
    this.dry = false,
    this.inplace = false,
    this.replay = false,
    this.transcript = false,
    this.level = 257,
  });

  final String input;
  final String output;
  final String tag;
  final int shard;
  final int shards;
  final int limit;
  final bool dry;
  final bool inplace;
  final bool replay;
  final bool transcript;

  /// Android's optimization level of every layout (FL_LEVEL).
  final int level;

  static FlRunConfig fromEnvironment() => const FlRunConfig(
    input: String.fromEnvironment('FL_IN'),
    output: String.fromEnvironment('FL_OUT'),
    tag: String.fromEnvironment('FL_TAG', defaultValue: 'today'),
    shard: int.fromEnvironment('FL_SHARD'),
    shards: int.fromEnvironment('FL_SHARDS', defaultValue: 1),
    limit: int.fromEnvironment('FL_LIMIT', defaultValue: -1),
    dry: bool.fromEnvironment('FL_DRY'),
    inplace: bool.fromEnvironment('FL_INPLACE'),
    replay: bool.fromEnvironment('FL_REPLAY'),
    transcript: bool.fromEnvironment('FL_TRANSCRIPT'),
    level: int.fromEnvironment('FL_LEVEL', defaultValue: 257),
  );

  FlRunConfig forShard(int k, int n) => FlRunConfig(
    input: input,
    output: '$output.$k',
    tag: tag,
    shard: k,
    shards: n,
    limit: limit,
    dry: dry,
    inplace: inplace,
    replay: replay,
    transcript: transcript,
    level: level,
  );
}

String _oneLine(Object e) =>
    e.toString().split('\n').first.replaceAll('\t', ' ').trim();

String _size(Size s) {
  String n(double v) =>
      v.isFinite && v == v.roundToDouble() ? '${v.toInt()}' : '$v';
  return '${n(s.width)} x ${n(s.height)}';
}

/// One pumped layout: (status, geometry, render object or null).
Future<(String, String, RenderConstraintLayout?)> _pump(
  WidgetTester tester,
  FLayout layout,
  Key key,
  OptimizationLevel level,
) async {
  var status = 'ok';
  try {
    await tester.pumpWidget(
      buildTree(layout, key: key, optimizationLevel: level),
      phase: EnginePhase.layout,
    );
    final error = tester.takeException();
    if (error != null) status = 'EXC:${_oneLine(error)}';
    final ro = tester.renderObject<RenderConstraintLayout>(
      find.byType(ConstraintLayout),
    );
    var geometry = geometryOf(ro, layout);
    if (status != 'ok') geometry = '!$status | $geometry';
    return (status, geometry, ro);
  } catch (e) {
    final pending = tester.takeException();
    return ('EXC:${_oneLine(pending ?? e)}', '-', null);
  }
}

/// Runs [config]'s shard; returns (laid out, unmapped, errors).
Future<(int, int, int)> runFl(WidgetTester tester, FlRunConfig config) async {
  final lines = File(config.input).readAsLinesSync();
  final out = File(config.output).openSync(mode: FileMode.write);
  final dryOut = config.dry
      ? File('${config.output}.dry').openSync(mode: FileMode.write)
      : null;
  final freshOut = config.inplace
      ? File('${config.output}.fresh').openSync(mode: FileMode.write)
      : null;
  final replayOut = config.replay
      ? File('${config.output}.replay').openSync(mode: FileMode.write)
      : null;
  final secondOut = config.replay
      ? File('${config.output}.second').openSync(mode: FileMode.write)
      : null;
  final transcriptOut = config.transcript
      ? File('${config.output}.T').openSync(mode: FileMode.write)
      : null;
  RenderConstraintLayout.debugRecordTranscripts = config.transcript;
  final buf = StringBuffer(), dryBuf = StringBuffer(), freshBuf = StringBuffer();
  final replayBuf = StringBuffer(), secondBuf = StringBuffer();
  final transcriptBuf = StringBuffer();
  var laidOut = 0, unmapped = 0, errors = 0, index = -1;
  final path = 'fl-${config.tag}';
  final level = optimizationLevelOf(config.level);
  for (final line in lines) {
    if (line.isEmpty) continue;
    index++;
    if (index % config.shards != config.shard) continue;
    if (config.limit >= 0 && laidOut + unmapped + errors >= config.limit) break;
    final List<FLayout> states;
    if (config.inplace && line.contains(';L;')) {
      states = mapInplaceStates(line);
    } else {
      states = [mapCorpusLine(line)];
    }
    final last = states.last;
    final bad = states.where((s) => s.unmapped != null).firstOrNull;
    if (bad != null) {
      unmapped++;
      buf.write('${last.id}\t${last.features}\t$path\tUNMAPPED:${bad.unmapped}\t-\t${last.ops}\n');
      continue;
    }
    // Every state of a sequence goes into the same ConstraintLayout (same
    // key), so the adapter applies the changes in place.
    final key = ValueKey<String>('seq$index');
    var status = 'ok', geometry = '-';
    RenderConstraintLayout? ro;
    for (final s in states) {
      (status, geometry, ro) = await _pump(tester, s, key, level);
      if (ro == null) break;
    }
    if (ro == null) {
      errors++;
    } else {
      laidOut++;
    }
    final ops = line.substring(line.lastIndexOf('\t') + 1);
    buf.write('${last.id}\t${last.features}\t$path\t$status\t$geometry\t$ops\n');
    if (dryOut != null && ro != null) {
      final dry = ro.getDryLayout(constraintsOf(last));
      final same = dry == ro.size;
      dryBuf.write('${last.id}\t${same ? 'equal' : 'DIFF'}\t${_size(dry)}\t${_size(ro.size)}\n');
    }
    if (transcriptOut != null && ro != null) {
      final t = ro.debugViewHost?.measurer.transcript?.toString() ?? '';
      transcriptBuf.write(
        '${last.id}\tT${config.level} ${t.isEmpty ? '-' : t}\n',
      );
    }
    if (replayOut != null && secondOut != null && ro != null) {
      // Laid out again four times in the same container: the second layout
      // confirms the first (or differs from it, as Android's own second
      // layout can), the third confirms the second, and the fourth and
      // fifth replay it.
      final geometries = <String>[];
      for (var k = 0; k < 4; k++) {
        ro.markNeedsLayout();
        await tester.pump(null, EnginePhase.layout);
        final error = tester.takeException();
        final g = geometryOf(ro, last);
        geometries.add(error == null ? g : '!EXC:${_oneLine(error)} | $g');
      }
      final second = geometries.first;
      final same = geometries.every((g) => g == geometry);
      final secondSame = second == geometry;
      replayBuf.write(
        '${last.id}\t${same ? 'same' : 'DIFF'}\treplays ${ro.debugReplayPasses}'
        '\tmismatches ${ro.debugReplayMismatches}\tengine ${ro.debugEnginePasses}'
        '\tsecond ${secondSame ? 'same' : 'DIFF'}'
        '${same ? '' : '\t$geometry\t${geometries.join('\t')}'}\n',
      );
      final secondStatus = second.startsWith('!')
          ? second.substring(1, second.indexOf(' | '))
          : status;
      secondBuf.write(
        '${last.id}\t${last.features}\t$path-second\t$secondStatus\t$second\t$ops\n',
      );
    }
    if (freshOut != null) {
      final (fs, fg, _) = await _pump(
        tester,
        last,
        ValueKey<String>('fresh$index'),
        level,
      );
      freshBuf.write('${last.id}\t${last.features}\t$path-fresh\t$fs\t$fg\t$ops\n');
    }
    if (buf.length > 1 << 20) {
      out.writeStringSync(buf.toString());
      buf.clear();
    }
  }
  out
    ..writeStringSync(buf.toString())
    ..closeSync();
  dryOut
    ?..writeStringSync(dryBuf.toString())
    ..closeSync();
  freshOut
    ?..writeStringSync(freshBuf.toString())
    ..closeSync();
  replayOut
    ?..writeStringSync(replayBuf.toString())
    ..closeSync();
  secondOut
    ?..writeStringSync(secondBuf.toString())
    ..closeSync();
  transcriptOut
    ?..writeStringSync(transcriptBuf.toString())
    ..closeSync();
  RenderConstraintLayout.debugRecordTranscripts = false;
  return (laidOut, unmapped, errors);
}
