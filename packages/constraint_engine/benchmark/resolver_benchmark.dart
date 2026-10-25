// Resolver performance benchmark for the pure-Dart dependency-graph engine.
//
// Measures the time to resolve simple / intermediate / complex layouts, and
// translates that into a frame-budget view (120fps = 8.333ms, 60fps = 16.667ms).
//
// Two cost profiles are measured per tier, mapping to the caching tiers the
// Flutter adapter uses:
//   cold       build the widget model + connections, then layout()  (what a
//              structural change costs: child list changed, ids renamed)
//   resolve    persistent model, layout() each iteration            (steady
//              state when something changed: the model is reused, the graph
//              is rebuilt and re-resolved)
//
// A measures-only profile (cached graph, re-measure only) is intentionally
// absent: resetting run state destroys the graph's edges along with the
// apply-time seeding, so the graph must be rebuilt whenever measures are
// redone. The layer above the engine caches instead by skipping layout()
// entirely when nothing changed.
//
// Run (AOT, closest to a Flutter release build):
//   dart compile exe benchmark/resolver_benchmark.dart -o /tmp/bench && /tmp/bench AOT
// Or JIT (closer to Flutter debug/profile):
//   dart run benchmark/resolver_benchmark.dart

import 'package:constraint_engine/constraint_engine.dart';

/// Builds a representative "screen": [rows] stacked rows, each a horizontal
/// spread chain of [cols] fixed-size items. Each row is anchored below the
/// previous one, producing a deep vertical dependency chain. Root is fixed on
/// both axes so the whole thing resolves in the graph (no phase-2 fallback).
///
/// With [solverRouted] the middle widget of every row becomes matchConstraint
/// with a 2:1 dimension ratio. A chain with a ratio-sized member is one of the
/// cases the graph declines, so the entire layout runs through the Cassowary
/// solver fallback (including the graph attempt + state restore that precede
/// it, which is the true cost of a solver-routed frame).
ConstraintWidgetContainer buildScreen(int rows, int cols,
    {bool solverRouted = false}) {
  final root = ConstraintWidgetContainer.rect(0, 0, 1080, 20000);

  ConstraintWidget? prevRowHead;
  for (var r = 0; r < rows; r++) {
    final rowWidgets = <ConstraintWidget>[];
    for (var c = 0; c < cols; c++) {
      final w = ConstraintWidget.size(80, 40);
      if (solverRouted && c == cols ~/ 2) {
        w.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
        w.setDimensionRatioString('2:1');
      }
      root.add(w);
      rowWidgets.add(w);
    }

    // Horizontal spread chain across the row.
    for (var c = 0; c < cols; c++) {
      final w = rowWidgets[c];
      // left anchor
      if (c == 0) {
        w.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 16);
      } else {
        w.connect(ConstraintAnchorType.left, rowWidgets[c - 1],
            ConstraintAnchorType.right, 8);
      }
      // right anchor
      if (c == cols - 1) {
        w.connect(
            ConstraintAnchorType.right, root, ConstraintAnchorType.right, 16);
      } else {
        w.connect(ConstraintAnchorType.right, rowWidgets[c + 1],
            ConstraintAnchorType.left, 8);
      }
    }

    // Vertical stacking: the row head anchors below the previous head; the rest
    // of the row aligns to the head's top.
    final head = rowWidgets[0];
    if (prevRowHead == null) {
      head.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 16);
    } else {
      head.connect(
          ConstraintAnchorType.top, prevRowHead, ConstraintAnchorType.bottom, 12);
    }
    for (var c = 1; c < cols; c++) {
      rowWidgets[c]
          .connect(ConstraintAnchorType.top, head, ConstraintAnchorType.top, 0);
    }
    prevRowHead = head;
  }

  return root;
}

class Stats {
  Stats(List<int> samplesMicros) : _n = samplesMicros.length {
    final sorted = [...samplesMicros]..sort();
    min = sorted.first.toDouble();
    max = sorted.last.toDouble();
    p50 = _pct(sorted, 0.50);
    p90 = _pct(sorted, 0.90);
    p99 = _pct(sorted, 0.99);
    var sum = 0;
    for (final s in samplesMicros) {
      sum += s;
    }
    mean = sum / _n;
  }

  final int _n;
  late final double min;
  late final double max;
  late final double mean;
  late final double p50;
  late final double p90;
  late final double p99;

  static double _pct(List<int> sorted, double p) {
    final idx = ((sorted.length - 1) * p).round();
    return sorted[idx].toDouble();
  }
}

/// Times [op] for [iters] iterations after [warmup] warmup iterations. [op]
/// returns an int folded into a checksum so the work cannot be optimized away.
(Stats, int) measure(int warmup, int iters, int Function() op) {
  var checksum = 0;
  for (var i = 0; i < warmup; i++) {
    checksum ^= op();
  }
  final samples = List<int>.filled(iters, 0);
  final sw = Stopwatch();
  for (var i = 0; i < iters; i++) {
    sw
      ..reset()
      ..start();
    checksum ^= op();
    sw.stop();
    samples[i] = sw.elapsedMicroseconds;
  }
  return (Stats(samples), checksum);
}

/// Folds resolved geometry into an int so a run isn't elided.
int _checksum(ConstraintWidgetContainer root) {
  var acc = 0;
  for (final w in root.getChildren()) {
    acc = (acc + w.getLeft() + w.getTop() + w.getWidth() + w.getBottom()) & 0x7fffffff;
  }
  return acc;
}

String _ms(double micros) => (micros / 1000).toStringAsFixed(3);

void main(List<String> args) {
  const frame120 = 8333.0; // microseconds
  const frame60 = 16667.0; // microseconds
  final buildLabel = args.isNotEmpty ? args.first : 'JIT (dart run)';

  final tiers = <(String, int, int, int, int)>[
    // name, rows, cols, warmup, iters
    ('Simple', 3, 3, 500, 5000),
    ('Intermediate', 8, 6, 300, 3000),
    ('Complex', 20, 12, 200, 2000),
    ('Heavy', 40, 15, 100, 800),
    ('Extreme', 50, 24, 60, 400),
  ];

  print('ConstraintLayout resolver benchmark');
  print('Build: $buildLabel\n');
  print('Frame budgets: 120fps = 8.333ms, 60fps = 16.667ms (whole frame; '
      'layout is only part of it)\n');

  for (final solverRouted in [false, true]) {
    final engineLabel = solverRouted
        ? 'CASSOWARY SOLVER (graph declines, full solver fallback)'
        : 'DEPENDENCY GRAPH (no fallback)';
    print('======== $engineLabel ========\n');

    for (final (name, rows, cols, tierWarmup, tierIters) in tiers) {
      // Solver passes are one to three orders of magnitude slower than graph
      // passes, so scale the sample counts down to keep the run bounded.
      final warmup = solverRouted ? (tierWarmup ~/ 10).clamp(5, 100) : tierWarmup;
      final iters = solverRouted ? (tierIters ~/ 10).clamp(20, 1000) : tierIters;
      final probeRoot = buildScreen(rows, cols, solverRouted: solverRouted);
      final widgetCount = probeRoot.getChildren().length;

      // Verify the routing is what the label claims before timing anything:
      // a solver pass creates the LinearSystem's variables, while a pure
      // graph pass never touches it. (The row count is no probe: a solve
      // whose equations all resolve directly ends with no rows.)
      probeRoot.layout();
      final solverRan = probeRoot.mSystem.getNumVariables() > 0;
      final solverRows = probeRoot.mSystem.mNumRows;
      if (solverRouted && !solverRan) {
        throw StateError('$name: expected solver fallback, graph resolved it');
      }
      if (!solverRouted && solverRan) {
        throw StateError('$name: expected pure graph, solver ran');
      }

      // cold: full model build + resolve every iteration.
      final (cold, _) = measure(warmup, iters, () {
        final root = buildScreen(rows, cols, solverRouted: solverRouted);
        root.layout();
        return _checksum(root);
      });

      // resolve: persistent model, re-resolved each layout().
      final persistent = buildScreen(rows, cols, solverRouted: solverRouted);
      final (resolve, _) = measure(warmup, iters, () {
        persistent.layout();
        return _checksum(persistent);
      });

      print('== $name  ($rows rows x $cols cols = $widgetCount widgets'
          '${solverRouted ? ', $solverRows solver rows' : ''}) ==');
      print('  profile     p50        p90        p99        mean       min    '
          '    max        %120fps   maxfps');
      _row('cold', cold, frame120);
      _row('resolve', resolve, frame120);
      print('  budget: cold p50 uses '
          '${(cold.p50 / frame120 * 100).toStringAsFixed(1)}% of a 120fps frame, '
          '${(cold.p50 / frame60 * 100).toStringAsFixed(1)}% of a 60fps frame');
      print('  model reuse win: cold->resolve p50 '
          '${_ms(cold.p50)}ms -> ${_ms(resolve.p50)}ms '
          '(${(cold.p50 / (resolve.p50 == 0 ? 1 : resolve.p50)).toStringAsFixed(1)}x)\n');
    }
  }
}

void _row(String label, Stats s, double frame120) {
  final maxFps = s.p50 == 0 ? double.infinity : 1000000 / s.p50;
  print('  ${label.padRight(11)}'
      '${_ms(s.p50).padRight(11)}'
      '${_ms(s.p90).padRight(11)}'
      '${_ms(s.p99).padRight(11)}'
      '${_ms(s.mean).padRight(11)}'
      '${_ms(s.min).padRight(11)}'
      '${_ms(s.max).padRight(11)}'
      '${(s.p50 / frame120 * 100).toStringAsFixed(1).padRight(10)}'
      '${maxFps.toStringAsFixed(0)}');
}
