// Resolver performance benchmark for the pure-Dart engine.
//
// It times Android's pipeline (BasicMeasure.solverMeasure) on screens of
// stacked rows of fixed-size items, in three sections:
//   standard, chains    OPTIMIZATION_STANDARD (257), Android's default, on
//                       rows that are spread chains: the Direct pass, then
//                       the solver, which sizes and places every chain;
//   standard, one-way   257 on rows linked one way (each item to the one
//                       before it, no chain): the Direct pass resolves the
//                       whole layout, as it does most real layouts, and the
//                       solver only takes its values;
//   graph               OPTIMIZATION_STANDARD | OPTIMIZATION_GRAPH (321) on
//                       the one-way rows: the dependency graph resolves the
//                       layout and no solve runs.
//
// Measures the time to resolve simple / intermediate / complex layouts, and
// translates that into a frame-budget view (120fps = 8.333ms, 60fps = 16.667ms).
//
// Three cost profiles are measured per tier:
//   cold       build the widget model + connections, then measure()  (what a
//              structural change costs: child list changed, ids renamed)
//   resolve    persistent model, updateHierarchy() then measure() each
//              iteration (steady state when something changed: the model is
//              reused, the graph is rebuilt)
//   view       persistent model, measured each iteration through ViewHost,
//              Android's onMeasure and the entry the Flutter adapter runs:
//              resolve plus the per-measure work of the view layer (every
//              child's measure state reset, the dependents rebuilt, the
//              children measured through a ViewMeasurer). Its frames are
//              checked against resolve's before timing.
//
// Run (AOT, closest to a Flutter release build):
//   dart compile exe benchmark/resolver_benchmark.dart -o /tmp/bench && /tmp/bench AOT
// Or JIT (closer to Flutter debug/profile):
//   dart run benchmark/resolver_benchmark.dart

import 'package:constraint_engine/constraint_engine.dart';

/// Reports the proposed size of every widget: the fixed sizes the benchmark
/// gives them, and the solved size of a match-constraint axis.
class _EchoMeasurer implements Measurer {
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    measure.measuredWidth = measure.horizontalDimension;
    measure.measuredHeight = measure.verticalDimension;
    measure.measuredHasBaseline = false;
    measure.measuredBaseline = 0;
    widget.setMeasureRequested(false);
  }

  @override
  void didMeasures() {}
}

/// The child views of a [ViewHost]: each measures to its spec's size under
/// EXACTLY (every item here is fixed) and to 0 otherwise, with no baseline.
class _FixedViews extends ViewMeasurer {
  @override
  ({int width, int height, int baseline}) measureContent(
    ConstraintWidget widget,
    int widthSpec,
    int heightSpec,
  ) => (width: _size(widthSpec), height: _size(heightSpec), baseline: -1);

  static int _size(int spec) => MeasureSpec.getMode(spec) == MeasureSpec.EXACTLY
      ? MeasureSpec.getSize(spec)
      : 0;
}

/// Builds a representative "screen": [rows] stacked rows of [cols]
/// fixed-size items. Each row is anchored below the previous one, producing
/// a deep vertical dependency chain. Root is fixed on both axes.
///
/// With [chains] each row is a horizontal spread chain; otherwise each item
/// is linked to the one before it only, so the layout has no chain and the
/// dependency graph can resolve it at the OPTIMIZATION_GRAPH levels.
ConstraintWidgetContainer buildScreen(
  int rows,
  int cols, {
  bool chains = true,
  Measurer? measurer,
}) {
  final root = ConstraintWidgetContainer.rect(0, 0, 1080, 20000);
  root.setMeasurer(measurer ?? _EchoMeasurer());

  ConstraintWidget? prevRowHead;
  for (var r = 0; r < rows; r++) {
    final rowWidgets = <ConstraintWidget>[];
    for (var c = 0; c < cols; c++) {
      final w = ConstraintWidget.size(80, 40);
      root.add(w);
      rowWidgets.add(w);
    }

    // Horizontal links across the row: a spread chain, or one way.
    for (var c = 0; c < cols; c++) {
      final w = rowWidgets[c];
      // left anchor
      if (c == 0) {
        w.connect(
          ConstraintAnchorType.left,
          root,
          ConstraintAnchorType.left,
          16,
        );
      } else {
        w.connect(
          ConstraintAnchorType.left,
          rowWidgets[c - 1],
          ConstraintAnchorType.right,
          8,
        );
      }
      if (!chains) {
        continue;
      }
      // right anchor
      if (c == cols - 1) {
        w.connect(
          ConstraintAnchorType.right,
          root,
          ConstraintAnchorType.right,
          16,
        );
      } else {
        w.connect(
          ConstraintAnchorType.right,
          rowWidgets[c + 1],
          ConstraintAnchorType.left,
          8,
        );
      }
    }

    // Vertical stacking: the row head anchors below the previous head; the rest
    // of the row aligns to the head's top.
    final head = rowWidgets[0];
    if (prevRowHead == null) {
      head.connect(
        ConstraintAnchorType.top,
        root,
        ConstraintAnchorType.top,
        16,
      );
    } else {
      head.connect(
        ConstraintAnchorType.top,
        prevRowHead,
        ConstraintAnchorType.bottom,
        12,
      );
    }
    for (var c = 1; c < cols; c++) {
      rowWidgets[c].connect(
        ConstraintAnchorType.top,
        head,
        ConstraintAnchorType.top,
        0,
      );
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

/// Measures [root] at [level] with exact specs at its size, as
/// ConstraintLayout's onMeasure does for a fixed-size layout.
void measureAt(ConstraintWidgetContainer root, int level) {
  root.setOptimizationLevel(level);
  root.measure(
    level,
    BasicMeasure.EXACTLY,
    root.getWidth(),
    BasicMeasure.EXACTLY,
    root.getHeight(),
    0,
    0,
    0,
    0,
  );
}

/// Measures [host]'s layout at [level] with exact specs of the screen's size,
/// as a parent gives a fixed-size ConstraintLayout view.
void measureViewAt(ViewHost host, int level) {
  host
    ..optimizationLevel = level
    ..measure(
      MeasureSpec.makeMeasureSpec(1080, MeasureSpec.EXACTLY),
      MeasureSpec.makeMeasureSpec(20000, MeasureSpec.EXACTLY),
    );
}

/// Folds resolved geometry into an int so a run isn't elided.
int _checksum(ConstraintWidgetContainer root) {
  var acc = 0;
  for (final w in root.getChildren()) {
    acc =
        (acc + w.getLeft() + w.getTop() + w.getWidth() + w.getBottom()) &
        0x7fffffff;
  }
  return acc;
}

/// Every child's frame, `x, y, width, height` in child order.
List<int> _frames(ConstraintWidgetContainer root) => [
  for (final w in root.getChildren()) ...[
    w.getX(),
    w.getY(),
    w.getWidth(),
    w.getHeight(),
  ],
];

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
  print(
    'Frame budgets: 120fps = 8.333ms, 60fps = 16.667ms (whole frame; '
    'layout is only part of it)\n',
  );

  // (label, level, chains, whether the solver runs)
  final sections = <(String, int, bool, bool)>[
    (
      'GRAPH LEVEL (321): the dependency graph alone; one-way rows',
      Optimizer.OPTIMIZATION_STANDARD | Optimizer.OPTIMIZATION_GRAPH,
      false,
      false,
    ),
    (
      'STANDARD LEVEL (257): Direct, then the solver; spread-chain rows',
      Optimizer.OPTIMIZATION_STANDARD,
      true,
      true,
    ),
    (
      'STANDARD LEVEL (257), ONE-WAY ROWS: Direct resolves, the solver takes '
          'its values',
      Optimizer.OPTIMIZATION_STANDARD,
      false,
      true,
    ),
  ];

  for (final (engineLabel, level, chains, solverRouted) in sections) {
    print('======== $engineLabel ========\n');

    for (final (name, rows, cols, tierWarmup, tierIters) in tiers) {
      // Solver passes on chains are one to three orders of magnitude slower
      // than graph passes, so scale the sample counts down to keep the run
      // bounded.
      final warmup = chains ? (tierWarmup ~/ 10).clamp(5, 100) : tierWarmup;
      final iters = chains ? (tierIters ~/ 10).clamp(20, 1000) : tierIters;
      final probeRoot = buildScreen(rows, cols, chains: chains);
      final widgetCount = probeRoot.getChildren().length;

      // Verify the routing is what the label claims before timing anything:
      // a solver pass creates the LinearSystem's variables, while a layout
      // the graph resolves never touches it. (The row count is no probe: a
      // solve whose equations all resolve directly ends with no rows.)
      measureAt(probeRoot, level);
      final solverRan = probeRoot.mSystem.getNumVariables() > 0;
      final solverRows = probeRoot.mSystem.mNumRows;
      if (solverRouted && !solverRan) {
        throw StateError('$name: expected the solver, the graph resolved it');
      }
      if (!solverRouted && solverRan) {
        throw StateError('$name: expected the graph alone, the solver ran');
      }

      // cold: full model build + measure every iteration.
      final (cold, _) = measure(warmup, iters, () {
        final root = buildScreen(rows, cols, chains: chains);
        measureAt(root, level);
        return _checksum(root);
      });

      // resolve: persistent model, measured again each iteration.
      final persistent = buildScreen(rows, cols, chains: chains);
      final (resolve, _) = measure(warmup, iters, () {
        persistent.updateHierarchy();
        measureAt(persistent, level);
        return _checksum(persistent);
      });

      // view: persistent model, measured again through ViewHost. Both paths
      // must place every widget at the same frame.
      final viewRoot = buildScreen(rows, cols, chains: chains);
      final host = ViewHost(viewRoot, _FixedViews());
      measureViewAt(host, level);
      final reference = buildScreen(rows, cols, chains: chains);
      measureAt(reference, level);
      final viewFrames = _frames(viewRoot);
      final frames = _frames(reference);
      for (var i = 0; i < frames.length; i++) {
        if (viewFrames[i] != frames[i]) {
          throw StateError('$name: ViewHost placed a widget elsewhere');
        }
      }
      final (view, _) = measure(warmup, iters, () {
        measureViewAt(host, level);
        return _checksum(viewRoot);
      });

      print(
        '== $name  ($rows rows x $cols cols = $widgetCount widgets'
        '${solverRouted ? ', $solverRows solver rows' : ''}) ==',
      );
      print(
        '  profile     p50        p90        p99        mean       min    '
        '    max        %120fps   maxfps',
      );
      _row('cold', cold, frame120);
      _row('resolve', resolve, frame120);
      _row('view', view, frame120);
      print(
        '  budget: cold p50 uses '
        '${(cold.p50 / frame120 * 100).toStringAsFixed(1)}% of a 120fps frame, '
        '${(cold.p50 / frame60 * 100).toStringAsFixed(1)}% of a 60fps frame',
      );
      print(
        '  model reuse win: cold->resolve p50 '
        '${_ms(cold.p50)}ms -> ${_ms(resolve.p50)}ms '
        '(${(cold.p50 / (resolve.p50 == 0 ? 1 : resolve.p50)).toStringAsFixed(1)}x)\n',
      );
    }
  }
}

void _row(String label, Stats s, double frame120) {
  final maxFps = s.p50 == 0 ? double.infinity : 1000000 / s.p50;
  print(
    '  ${label.padRight(11)}'
    '${_ms(s.p50).padRight(11)}'
    '${_ms(s.p90).padRight(11)}'
    '${_ms(s.p99).padRight(11)}'
    '${_ms(s.mean).padRight(11)}'
    '${_ms(s.min).padRight(11)}'
    '${_ms(s.max).padRight(11)}'
    '${(s.p50 / frame120 * 100).toStringAsFixed(1).padRight(10)}'
    '${maxFps.toStringAsFixed(0)}',
  );
}
