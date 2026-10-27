// rbench: the baseline suite's (BL's) screen benchmark on the pipeline's
// entries. The same screens (BL's buildScreen with
// 80 x 40 cells in spread-chain rows, the same with a 2:1 ratio cell per row,
// and BL's buildFlatScreen with 60 x 40 cells linked one way), the same tiers,
// warm-ups, iteration counts and p50 (the lower median). The retired paths
// (G graph-first layout(), S forced solver, E the DirectResolution model, Sx,
// Ex, Dm) are replaced by the pipeline's entries:
//
//   M257  ConstraintWidgetContainer.measure at OPTIMIZATION_STANDARD (257),
//         Android's default: Direct, then the solver (the oracle's core257
//         path, measured with VOpDriver's Echo as BL's JTimer measures Java)
//   M0    the same at level 0: the solver alone (BL's Sx)
//   M321  the same at 321 (STANDARD | GRAPH): the dependency graph first when
//         Android's rules let it run (no chain), else as 257
//   V257  ViewHost.measure at 257 with the oracle's view measurer (content
//         `none`: a View's getDefaultSize), the adapter's engine entry
//
// "resolve" re-measures one persistent container (JTimer's persistent
// container: measure() with the specs of the first measure, nothing else);
// "cold" builds the screen and measures it once. Every path checks that the
// first measure's frames equal M257's (the paths lay out the same screen).
//
// Build and run (AOT, against the tree under test):
//   dart compile exe --packages=<tree>/.dart_tool/package_config.json \
//     tool/parity/bench/rbench6.dart -o <bin>/rbench6.exe
//   <bin>/rbench6.exe [kind ...]   (kinds: chains chains+ratio flat)
import 'package:constraint_engine/constraint_engine.dart';

import '../dart/vpaths_future.dart' show ContentViewMeasurer, EchoMeasurer;

const int kWidth = 1080;
const int kHeight = 20000;

ConstraintWidgetContainer _root() =>
    ConstraintWidgetContainer.rect(0, 0, kWidth, kHeight)..setDebugName('root');

/// BL's buildScreen: [rows] rows of [cols] 80 x 40 cells, each row a spread
/// chain, each row head below the previous one. With [ratio] the middle cell
/// of every row is match constraint with a 2:1 ratio (BL's solver tier).
ConstraintWidgetContainer buildScreen(
  int rows,
  int cols, {
  bool ratio = false,
}) {
  final root = _root();
  ConstraintWidget? prevRowHead;
  for (var r = 0; r < rows; r++) {
    final rowWidgets = <ConstraintWidget>[];
    for (var c = 0; c < cols; c++) {
      final w = ConstraintWidget.size(80, 40)..setDebugName('r${r}c$c');
      if (ratio && c == cols ~/ 2) {
        w.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
        w.setDimensionRatioString('2:1');
      }
      root.add(w);
      rowWidgets.add(w);
    }
    for (var c = 0; c < cols; c++) {
      final w = rowWidgets[c];
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

/// BL's buildFlatScreen: the same rows without chains, 60 x 40 cells, each
/// placed after the one before it from the left (no right link).
ConstraintWidgetContainer buildFlatScreen(int rows, int cols) {
  final root = _root();
  ConstraintWidget? prevRowHead;
  for (var r = 0; r < rows; r++) {
    final rowWidgets = <ConstraintWidget>[];
    for (var c = 0; c < cols; c++) {
      final w = ConstraintWidget.size(60, 40)..setDebugName('r${r}c$c');
      root.add(w);
      rowWidgets.add(w);
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
    }
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

ConstraintWidgetContainer build(String kind, int rows, int cols) =>
    switch (kind) {
      'chains' => buildScreen(rows, cols),
      'chains+ratio' => buildScreen(rows, cols, ratio: true),
      'flat' => buildFlatScreen(rows, cols),
      _ => throw ArgumentError('kind $kind'),
    };

/// A path: prepares [root] once and returns its measure.
typedef Prepare = void Function() Function(ConstraintWidgetContainer root);

/// The core path at [level]: VOpDriver's Echo, exact specs at the root size.
Prepare core(int level) => (root) {
  root
    ..setMeasurer(const EchoMeasurer())
    ..setOptimizationLevel(level);
  final w = root.getWidth(), h = root.getHeight();
  return () => root.measure(
    level,
    BasicMeasure.EXACTLY,
    w,
    BasicMeasure.EXACTLY,
    h,
    0,
    0,
    0,
    0,
  );
};

/// The view path at [level]: ViewHost with the oracle's view measurer.
Prepare view(int level) => (root) {
  final host = ViewHost(root, ContentViewMeasurer())..optimizationLevel = level;
  final ws = MeasureSpec.makeMeasureSpec(root.getWidth(), MeasureSpec.EXACTLY);
  final hs = MeasureSpec.makeMeasureSpec(root.getHeight(), MeasureSpec.EXACTLY);
  return () => host.measure(ws, hs);
};

final paths = <String, Prepare>{
  'M257': core(Optimizer.OPTIMIZATION_STANDARD),
  'M0': core(Optimizer.OPTIMIZATION_NONE),
  'M321': core(Optimizer.OPTIMIZATION_STANDARD | Optimizer.OPTIMIZATION_GRAPH),
  'V257': view(Optimizer.OPTIMIZATION_STANDARD),
};

/// BL's p50: [warmup] calls, then [iters] timed calls; the lower median in
/// microseconds.
int p50(int warmup, int iters, void Function() op) {
  for (var i = 0; i < warmup; i++) {
    op();
  }
  final s = List<int>.filled(iters, 0);
  final sw = Stopwatch();
  for (var i = 0; i < iters; i++) {
    sw
      ..reset()
      ..start();
    op();
    sw.stop();
    s[i] = sw.elapsedMicroseconds;
  }
  s.sort();
  return s[(iters - 1) ~/ 2];
}

String frames(ConstraintWidgetContainer root) {
  final sb = StringBuffer();
  for (final w in root.getChildren()) {
    sb.write('${w.getX()},${w.getY()},${w.getWidth()},${w.getHeight()};');
  }
  return sb.toString();
}

String ms(int micros) => (micros / 1000).toStringAsFixed(3);

void main(List<String> args) {
  final kinds = args.isEmpty ? ['chains', 'chains+ratio', 'flat'] : args;
  final tiers = <(String, int, int, int, int)>[
    ('Simple', 3, 3, 300, 2000),
    ('Intermediate', 8, 6, 100, 600),
    ('Complex', 20, 12, 30, 150),
    ('Heavy', 40, 15, 10, 40),
  ];
  for (final kind in kinds) {
    print('== $kind');
    for (final (name, rows, cols, warmup, iters) in tiers) {
      final line = StringBuffer('  ${name.padRight(13)}');
      String? reference;
      for (final MapEntry(key: label, value: prepare) in paths.entries) {
        final probe = build(kind, rows, cols);
        prepare(probe)();
        final f = frames(probe);
        reference ??= f;
        final vars = probe.mSystem.getNumVariables();
        final persistent = build(kind, rows, cols);
        final resolve = p50(warmup, iters, prepare(persistent));
        final cold = p50(
          warmup ~/ 2 + 1,
          iters ~/ 2 + 1,
          () => prepare(build(kind, rows, cols))(),
        );
        line.write(
          '$label: resolve ${ms(resolve)} ms, cold ${ms(cold)} ms'
          '${f == reference ? '' : ' (FRAMES DIFFER FROM M257)'}'
          '${vars == 0 ? ' (no solve)' : ''};  ',
        );
      }
      print(line);
    }
  }
}
