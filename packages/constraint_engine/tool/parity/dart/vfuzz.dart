// vfuzz: the Phase 0 corpus generator and Dart-side runner (p0-dart).
//
//   vfuzz <gen> <firstSeed> <count> <out.txt> --path <path>
//         [--measurer auto|echo|today] [--progress <file>]
//         [--transcript <side.txt>] [--direct <side.txt>]
//         [--twice|--twice-links]
//   vfuzz --corpus <in.txt> <out.txt> --path <path> [--measurer ...]
//         [--transcript <side.txt>] [--direct <side.txt>]
//         [--twice|--twice-links]
//   vfuzz --list [R|VR|VR2|T|T2|A]
//   vfuzz --seeds <gen>          the Phase 0 first seed and count of <gen>
//
// <gen> is a generator of FORMATS.md section 3 (R, VR-*, VR2-*, T-*, T2-*,
// A-*). <path> is none, core<level> or view<level> with an optimization level
// from 0 to 2047: core0, core257, view0 and view257 (FORMATS.md 5, 17 and 18),
// the GRAPH levels core64, core321 and view321, or any other level (FORMATS.md
// 20). The Phase 0 paths graphfirst and forced are retired (Phase 5a deletes
// the graph-first entry they ran). --measurer is accepted and ignored: a core
// path measures with the echo measurer, a view path with the content model.
//
// --transcript (view paths) also writes the measure-request transcript of
// each layout's last measure to a side file, one line per layout,
// `id \t T<level> <entries>` (`T<level> -` for none): VOpDriver's T field
// (FORMATS.md 8.5 and 17). tcompare.py compares it with VOpDriver's.
//
// --direct (any path; a build with -Dcl.trace=true)
// writes the Direct dump of each layout's last measure to a side file,
// `id \t D<level> <entries>` (`D<level> -` when that measure made none):
// VOpDriver's D field (FORMATS.md 8.4 and 18). dcompare.py compares it.
//
// --twice (view paths) measures every layout a second time in the same
// container after re-applying the FIXED sizes its op list configured, and
// writes the layouts whose status or geometry changed to <out>.twice,
// `id \t class \t first \t second` (FORMATS.md 18; class `vl-links` when the
// first measure changed a VirtualLayout's own links, else `other`).
// --twice-links also puts those links back before the second measure.
// Every path writes <out>.guard, `id \t trips`, for the layouts during
// which Direct's guard fired (Direct.guardTrips grew), and counts them in
// the summary.
//
// --corpus replays a saved corpus file instead of generating: each line's id
// (first field) and op list (last field), in file order, so any vfuzz file,
// VOpDriver input or id subset runs unchanged (FORMATS.md 16). R, VR and VR2
// must be replayed rather than regenerated with a Phase 1 engine (corpora.dart).
//
// Output (FORMATS.md 1), one line per layout:
//   id \t features \t path \t status \t geometry \t ops
// The file is a valid OpDriver/VOpDriver batch input. The summary goes to
// stdout and <out>.sum, generator errors to <out>.err.
import 'dart:convert';
import 'dart:io';

import 'package:constraint_engine/constraint_engine.dart';
import 'package:constraint_engine/src/analyzer/direct.dart' show Direct;

import 'corpora.dart';
import 'ops.dart';
import 'vpaths.dart';
import 'vpaths_future.dart' as future;

/// The lines of the file [path], read in 1 MB blocks: corpus files are ASCII
/// and can be larger than a comfortable in-memory list (R.in is 600 MB).
Iterable<String> readLines(String path) sync* {
  final raf = File(path).openSync();
  final lines = <String>[];
  final bytes = latin1.decoder.startChunkedConversion(
    const LineSplitter().startChunkedConversion(_ListSink(lines)),
  );
  try {
    while (true) {
      final block = raf.readSync(1 << 20);
      if (block.isEmpty) break;
      bytes.add(block);
      yield* lines;
      lines.clear();
    }
    bytes.close();
    yield* lines;
  } finally {
    raf.closeSync();
  }
}

class _ListSink implements Sink<String> {
  _ListSink(this.out);

  final List<String> out;

  @override
  void add(String data) => out.add(data);

  @override
  void close() {}
}

String _arg(List<String> args, String flag, String fallback) {
  final i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}

void main(List<String> args) {
  if (args.isNotEmpty && args[0] == '--list') {
    final names = args.length > 1
        ? corpusNames(args[1])
        : corpusGenerators.keys.toList();
    stdout.writeln(names.join('\n'));
    return;
  }
  if (args.isNotEmpty && args[0] == '--seeds') {
    final (first, count) = defaultSeeds(args[1]);
    stdout.writeln('$first $count');
    return;
  }
  final replay = args.isNotEmpty && args[0] == '--corpus';
  if (args.length < (replay ? 3 : 4)) {
    stderr.writeln(
      'usage: vfuzz <gen> <firstSeed> <count> <out.txt> --path <path> '
      '[--measurer auto|echo|today] [--progress <file>] '
      '[--transcript <side.txt>] [--direct <side.txt>] [--twice|--twice-links]\n'
      '       vfuzz --corpus <in.txt> <out.txt> --path <path> '
      '[--measurer auto|echo|today] [--progress <file>] '
      '[--transcript <side.txt>] [--direct <side.txt>] [--twice|--twice-links]',
    );
    exit(2);
  }
  // The layouts to run: (id, ops) from a generator's seeds, or from a corpus
  // file's lines (--corpus).
  final String genName;
  final Iterable<(String, List<String>? Function())> layouts;
  final int first, count;
  if (replay) {
    genName = args[1];
    first = 0;
    count = -1; // Counted while reading.
    layouts = readLines(args[1])
        .where((l) => l.isNotEmpty && !l.startsWith('#') && l.contains('\t'))
        .map((l) {
          final id = l.substring(0, l.indexOf('\t'));
          final ops = l.substring(l.lastIndexOf('\t') + 1).split(';');
          return (id, () => ops);
        });
  } else {
    genName = args[0];
    final gen = corpusGenerators[genName];
    if (gen == null) {
      stderr.writeln('vfuzz: unknown generator $genName (vfuzz --list)');
      exit(2);
    }
    first = int.parse(args[1]);
    count = int.parse(args[2]);
    layouts = [
      for (var seed = first; seed < first + count; seed++)
        ('$genName:$seed', () => gen(seed)),
    ];
  }
  final outPath = args[replay ? 2 : 3];
  final pathName = _arg(args, '--path', 'none');
  final measurer = _arg(args, '--measurer', 'auto');
  final progressPath = _arg(args, '--progress', '');
  final transcriptPath = _arg(args, '--transcript', '');
  final directPath = _arg(args, '--direct', '');
  final twiceLinks = args.contains('--twice-links');
  final twice = args.contains('--twice') || twiceLinks;
  if (!isPathName(pathName)) {
    stderr.writeln('vfuzz: unknown path $pathName ($pathNames)');
    exit(2);
  }
  LayoutPath? path;
  if (pathName != 'none') {
    path = pathNamed(pathName, measurer: measurer);
    if (path == null) {
      stderr.writeln('vfuzz: path $pathName: ${future.futureReason(pathName)}');
      exit(64);
    }
  }
  final transcriptLevel = future.transcriptLevel(pathName);
  if (transcriptPath.isNotEmpty && transcriptLevel == null) {
    stderr.writeln(
      'vfuzz: --transcript needs a path that records one (view<level>), '
      'not $pathName',
    );
    exit(2);
  }
  final directLevel = future.directLevel(pathName);
  if (directPath.isNotEmpty && directLevel == null) {
    stderr.writeln(
      'vfuzz: --direct needs a path of the upstream pipeline (core<level>, '
      'view<level>), not $pathName',
    );
    exit(2);
  }
  if (directPath.isNotEmpty && !future.canDumpDirect) {
    stderr.writeln(
      'vfuzz: --direct needs a build with -Dcl.trace=true (the engine calls '
      'the Direct dump sink only there)',
    );
    exit(2);
  }
  if (twice && !future.isViewPath(pathName)) {
    stderr.writeln('vfuzz: --twice needs a view path (view<level>)');
    exit(2);
  }
  final side = transcriptPath.isEmpty
      ? null
      : File(transcriptPath).openSync(mode: FileMode.write);
  future.recordTranscript = side != null;
  final sideBuf = StringBuffer();
  final dside = directPath.isEmpty
      ? null
      : File(directPath).openSync(mode: FileMode.write);
  future.recordDirect = dside != null;
  final dsideBuf = StringBuffer();
  future.measureTwice = twice;
  future.twiceRestoreLinks = twiceLinks;
  final twiceBuf = StringBuffer();
  final guardBuf = StringBuffer();
  var twiceN = 0, twiceDiffer = 0, guardLayouts = 0, guardTrips = 0;
  final twiceClasses = <String, int>{};
  final out = File(outPath).openSync(mode: FileMode.write);
  final err = StringBuffer();
  final progress = progressPath.isEmpty ? null : File(progressPath);
  final buf = StringBuffer();
  var emitted = 0, skipped = 0, genErrors = 0, printedN = 0, thrownN = 0;
  var childLayouts = 0;
  final sw = Stopwatch()..start();
  var index = 0;
  for (final (id, make) in layouts) {
    if (progress != null && index % 500 == 0) {
      progress.writeAsStringSync('${first + index}');
    }
    index++;
    List<String>? ops;
    try {
      ops = make();
    } catch (e, st) {
      genErrors++;
      err.writeln(
        'gen-err $id $e ${st.toString().split('\n').take(3).join(' / ')}',
      );
      continue;
    }
    if (ops == null) {
      skipped++;
      continue;
    }
    String feats;
    String status = '-', geom = '-';
    if (path == null) {
      final (w, h) = rootSize(ops);
      final root = ConstraintWidgetContainer.rect(0, 0, w, h)
        ..setDebugName('root');
      try {
        applyOps(root, ops, layoutPass: () {});
      } catch (e) {
        genErrors++;
        err.writeln('ops-err $id $e');
        continue;
      }
      feats = (features(root, ops).toList()..sort()).join(',');
    } else {
      final tripsBefore = Direct.guardTrips;
      final r = path(ops);
      final trips = Direct.guardTrips - tripsBefore;
      if (trips > 0) {
        guardLayouts++;
        guardTrips += trips;
        guardBuf.write('$id\t$trips\n');
      }
      if (twice) {
        final t = future.lastTwice;
        if (t != null) {
          twiceN++;
          if (t) {
            twiceDiffer++;
            final detail = future.lastTwiceDetail!;
            final cls = detail.substring(0, detail.indexOf('\t'));
            twiceClasses[cls] = (twiceClasses[cls] ?? 0) + 1;
            twiceBuf.write('$id\t$detail\n');
          }
        }
      }
      status = r.status;
      geom = r.geometry;
      childLayouts += r.childLayouts;
      if (status == 'ok-printed') printedN++;
      if (status.startsWith('EXC')) thrownN++;
      feats = (features(r.root, ops).toList()..sort()).join(',');
      if (side != null) {
        final t = future.lastTranscript ?? '';
        sideBuf.write('$id\tT$transcriptLevel ${t.isEmpty ? '-' : t}\n');
        if (sideBuf.length > 1 << 20) {
          side.writeStringSync(sideBuf.toString());
          sideBuf.clear();
        }
      }
      if (dside != null) {
        final d = future.lastDirect;
        dsideBuf.write('$id\tD$directLevel ${d ?? '-'}\n');
        if (dsideBuf.length > 1 << 20) {
          dside.writeStringSync(dsideBuf.toString());
          dsideBuf.clear();
        }
      }
    }
    emitted++;
    buf.write(
      '$id\t${feats.isEmpty ? '-' : feats}\t$pathName\t$status\t$geom\t'
      '${ops.join(';')}\n',
    );
    if (buf.length > 1 << 20) {
      out.writeStringSync(buf.toString());
      buf.clear();
    }
  }
  out.writeStringSync(buf.toString());
  out.closeSync();
  if (side != null) {
    side.writeStringSync(sideBuf.toString());
    side.closeSync();
  }
  if (dside != null) {
    dside.writeStringSync(dsideBuf.toString());
    dside.closeSync();
  }
  if (path != null) {
    File('$outPath.guard').writeAsStringSync(guardBuf.toString());
  }
  if (twice) {
    File('$outPath.twice').writeAsStringSync(twiceBuf.toString());
  }
  final range = replay ? '($index lines)' : '$first..${first + count - 1}';
  final summary =
      '$genName $range path $pathName: emitted '
      '$emitted, skipped $skipped, gen errors $genErrors, printed $printedN, '
      'threw $thrownN, child layouts $childLayouts, '
      'guard trips $guardTrips in $guardLayouts layouts'
      '${twice ? ', twice: $twiceN measured again, $twiceDiffer differ $twiceClasses' : ''}, '
      '${sw.elapsedMilliseconds} ms';
  File('$outPath.sum').writeAsStringSync('$summary\n');
  if (err.isNotEmpty) File('$outPath.err').writeAsStringSync(err.toString());
  progress?.writeAsStringSync('DONE');
  stdout.writeln(summary);
}
