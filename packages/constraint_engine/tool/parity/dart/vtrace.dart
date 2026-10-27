// vtrace: the Dart side of solver trace parity (FORMATS.md 7, 7b and 16).
//
//   vtrace <corpus.txt> <out.trace> --path <path> [--level 257]
//          [--measurer auto|echo|today] [--max N]
//
// Compile with the trace on (lib/src/debug/solver_trace.dart is behind
// const bool.fromEnvironment('cl.trace')):
//   dart compile exe -Dcl.trace=true \
//     --packages=<repo or copy>/.dart_tool/package_config.json \
//     tool/parity/dart/vtrace.dart -o <out>/vtrace.exe
//
// For each corpus line (id in the first field, ops in the last; `#` lines
// skipped, as VOpDriver skips them) it writes `T <id> <level> 0`, runs the
// layout on the path with the engine's trace sink writing every other event,
// and writes `E`, exactly as VOpDriver -Dtrace does, so tracediff.py can
// compare the two. --level is only the label of the T line: the path decides
// what runs (core<level> or view<level>, FORMATS.md 5 and 20; core0's Java
// reference is TraceJava at level 0 with -Dpath=core, core257's at 257). The
// core paths measure with the echo measurer, which matches VOpDriver's core
// path (-Dpath=core) on op lists that carry content. --measurer is accepted
// and ignored, as by vfuzz.
//
// Compiled without -Dcl.trace=true the trace holds only the driver's T and E
// lines, and vtrace says so on stderr.
import 'dart:io';

import 'package:constraint_engine/src/debug/solver_trace.dart';

import 'vpaths.dart';

/// Connects the engine's solver trace to [emit] (one event line per call).
/// Returns false when compiled without -Dcl.trace=true.
bool installTraceSink(void Function(String line) emit) {
  if (!kSolverTrace) {
    return false; // Compiled without -Dcl.trace=true.
  }
  SolverTrace.sink = emit;
  return true;
}

String _arg(List<String> args, String flag, String fallback) {
  final i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'usage: vtrace <corpus.txt> <out.trace> --path <path> [--level 257] '
      '[--measurer auto|echo|today] [--max N]',
    );
    exit(2);
  }
  final pathName = _arg(args, '--path', 'core257');
  final level = _arg(args, '--level', '257');
  final measurer = _arg(args, '--measurer', 'auto');
  final maxN = int.parse(_arg(args, '--max', '-1'));
  final path = pathNamed(pathName, measurer: measurer);
  if (path == null) {
    stderr.writeln(
      'vtrace: unknown path $pathName (core<level> or view<level>)',
    );
    exit(64);
  }
  final out = File(args[1]).openSync(mode: FileMode.write);
  final buf = StringBuffer();
  void emit(String line) => buf.writeln(line);
  if (!installTraceSink(emit)) {
    stderr.writeln(
      'vtrace: compiled without -Dcl.trace=true; writing T and E lines only',
    );
  }
  var n = 0;
  for (final line in File(args[0]).readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#')) continue;
    if (maxN >= 0 && n >= maxN) break;
    final p = line.split('\t');
    final ops = p.last.split(';');
    emit('T ${p.first} $level 0');
    path(ops);
    emit('E');
    n++;
    if (buf.length > 1 << 20) {
      out.writeStringSync(buf.toString());
      buf.clear();
    }
  }
  out.writeStringSync(buf.toString());
  out.closeSync();
  stdout.writeln('vtrace: $n layouts traced on $pathName');
}
