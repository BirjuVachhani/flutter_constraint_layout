// Prints the mapped final state of corpus lines (ftree's model), one child
// per line, for diffing two op lists (a debugging aid).
//   dart run tool/dumpstate.dart <file> <id> [inplace]
import 'dart:io';

import 'package:cl_fl_harness/src/fmodel.dart';

String _l(FLink? l) => l == null ? '-' : '${l.target}.${l.edge}+${l.margin}/g${l.goneMargin}';

void main(List<String> args) {
  final line = File(args[0]).readAsLinesSync().firstWhere((l) => l.startsWith('${args[1]}\t'));
  final layout = args.length > 2 ? mapInplaceStates(line).last : mapCorpusLine(line);
  stdout.writeln('unmapped=${layout.unmapped} rtl=${layout.rtl} ${layout.minW}..${layout.maxW} x ${layout.minH}..${layout.maxH}');
  for (final c in layout.children) {
    stdout.writeln([
      c.name, c.kind.name, '${c.width.kind.name}${c.width.px}/${c.width.min}/${c.width.max}/${c.width.pct}',
      '${c.height.kind.name}${c.height.px}/${c.height.min}/${c.height.max}/${c.height.pct}',
      'L=${_l(c.left)}', 'R=${_l(c.right)}', 'T=${_l(c.top)}', 'B=${_l(c.bottom)}', 'S=${_l(c.baseline)}',
      'bias=${c.hBias},${c.vBias}', 'ratio=${c.ratio}', 'ch=${c.hChain},${c.vChain}', 'w=${c.hWeight},${c.vWeight}',
      'vis=${c.visibility}', '${c.content}',
      if (c.kind == FKind.guideline) 'g=${c.horizontalLine ? 'H' : 'V'} b${c.gBegin} e${c.gEnd} p${c.gPercent}',
      if (c.kind == FKind.barrier) 'bar=${c.barrierType} m${c.barrierMargin} g${c.allowsGone} ${c.refs}',
    ].join(' '));
  }
}
