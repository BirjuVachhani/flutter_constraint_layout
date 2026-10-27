// ftree CLI (FORMATS.md section 11): selects the FL corpus.
//
//   ftree select <perGen> <out FL.txt> <corpus.txt>...
//       keeps, per generator (the id before ':'), the first <perGen> lines
//       whose op list maps to the Flutter API; writes FL.txt (section 1
//       lines, unchanged), FL.txt.unmapped (id \t reason) and a summary to
//       stdout and FL.txt.sum.
//   ftree check <corpus.txt>...
//       counts mappable lines and unmapped reasons per generator.
//   Both take --gens a,b,c to keep only those generators.
import 'dart:convert';
import 'dart:io';

import 'package:cl_fl_harness/src/fmodel.dart';

Future<void> main(List<String> argv) async {
  var args = argv;
  if (args.isEmpty) {
    stderr.writeln('usage: ftree select <perGen> <out> <corpus>... | ftree check <corpus>...');
    exit(2);
  }
  // --gens a,b,c keeps only those generators.
  final gi = args.indexOf('--gens');
  Set<String>? only;
  if (gi >= 0) {
    only = args[gi + 1].split(',').toSet();
    args = [...args.sublist(0, gi), ...args.sublist(gi + 2)];
  }
  final select = args[0] == 'select';
  final perGen = select ? int.parse(args[1]) : -1;
  final outPath = select ? args[2] : null;
  final inputs = args.sublist(select ? 3 : 1);
  final kept = <String, int>{};
  final seen = <String, int>{};
  final reasons = <String, Map<String, int>>{};
  final out = outPath == null ? null : File(outPath).openSync(mode: FileMode.write);
  final unmapped = outPath == null
      ? null
      : File('$outPath.unmapped').openSync(mode: FileMode.write);
  final buf = StringBuffer(), ubuf = StringBuffer();
  for (final path in inputs) {
    // Streamed: the full corpora are hundreds of megabytes.
    final lines = File(path)
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final id = line.substring(0, line.indexOf('\t'));
      final gen = id.substring(0, id.lastIndexOf(':'));
      if (only != null && !only.contains(gen)) continue;
      if (select && (kept[gen] ?? 0) >= perGen) continue;
      seen[gen] = (seen[gen] ?? 0) + 1;
      final layout = mapCorpusLine(line);
      final reason = layout.unmapped;
      if (reason != null) {
        final r = reasons.putIfAbsent(gen, () => <String, int>{});
        r[reason] = (r[reason] ?? 0) + 1;
        ubuf.write('$id\t$reason\n');
        continue;
      }
      kept[gen] = (kept[gen] ?? 0) + 1;
      buf.write('$line\n');
      if (buf.length > 1 << 20) {
        out?.writeStringSync(buf.toString());
        buf.clear();
      }
    }
  }
  out?.writeStringSync(buf.toString());
  out?.closeSync();
  unmapped?.writeStringSync(ubuf.toString());
  unmapped?.closeSync();
  final summary = StringBuffer();
  for (final gen in seen.keys) {
    final r = reasons[gen] ?? const <String, int>{};
    final top = (r.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(6)
        .map((e) => '${e.key} ${e.value}')
        .join(', ');
    summary.writeln(
      '$gen: read ${seen[gen]}, mapped ${kept[gen] ?? 0}, unmapped '
      '${r.values.fold(0, (a, b) => a + b)}${top.isEmpty ? '' : ' ($top)'}',
    );
  }
  stdout.write(summary);
  if (outPath != null) File('$outPath.sum').writeAsStringSync(summary.toString());
}
