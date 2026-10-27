// Shared pieces of the adapter benchmarks (FORMATS.md section 12): a counting
// proxy around each ConstraintLayout child, a counter registry, and the
// statistics and report line.
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Totals over every [CountingProxy] that reports to it.
class LayoutTally {
  int calls = 0;
  int runs = 0;

  void reset() {
    calls = 0;
    runs = 0;
  }
}

/// Wraps a ConstraintLayout child and counts the layouts the layout asks of
/// it: every `layout()` call, and every `performLayout` that call runs (a
/// call under unchanged constraints on a clean child runs nothing). It adds
/// no constraints of its own and forwards baselines and dry layouts, so the
/// adapter sees the wrapped child's answers.
class CountingProxy extends SingleChildRenderObjectWidget {
  const CountingProxy({super.key, required this.tally, super.child});

  final LayoutTally tally;

  @override
  RenderCountingProxy createRenderObject(BuildContext context) =>
      RenderCountingProxy(tally);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCountingProxy renderObject,
  ) {
    renderObject.tally = tally;
  }
}

class RenderCountingProxy extends RenderProxyBox {
  RenderCountingProxy(this.tally);

  LayoutTally tally;

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    tally.calls++;
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  @override
  void performLayout() {
    tally.runs++;
    super.performLayout();
  }
}

class BenchStats {
  BenchStats(this.name, List<int> micros, this.extra) {
    final sorted = [...micros]..sort();
    n = sorted.length;
    p50 = sorted[((n - 1) * 0.50).round()] / 1000;
    p90 = sorted[((n - 1) * 0.90).round()] / 1000;
    min = sorted.first / 1000;
    var sum = 0;
    for (final m in micros) {
      sum += m;
    }
    mean = sum / n / 1000;
  }

  final String name;
  late final int n;
  late final double p50, p90, min, mean;

  /// Per-pass counts (name -> value), printed after the times.
  final Map<String, num> extra;

  String line() {
    String f(num v) => v is int ? '$v' : v.toStringAsFixed(3);
    final counts = extra.entries.map((e) => '${e.key}=${f(e.value)}').join(' ');
    return 'BENCH $name passes=$n p50=${f(p50)} p90=${f(p90)} '
        'min=${f(min)} mean=${f(mean)} $counts';
  }

  /// Prints the line and writes it (with [notes]) to [path].
  void report(String path, List<String> notes) {
    final text = [line(), ...notes].join('\n');
    // ignore: avoid_print
    print(text);
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('$text\n');
  }
}
