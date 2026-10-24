// Flutter-level layout benchmark for ConstraintLayout.
//
// Measures the real `RenderConstraintLayout.performLayout` cost inside
// Flutter's layout pipeline, against the persistent-model cache. Three slices
// per tier:
//
//   fast     markNeedsLayout on the container only, nothing changed. The
//            all-fixed grid takes the engine-skipping fast path: resolved
//            geometry is reused and children short-circuit.
//   resolve  the incoming constraints alternate between two sizes, so every
//            flush is a real engine pass on the persistent model (graph
//            rebuild + resolve + placement); children stay clean.
//   full     resize plus every child marked dirty: engine pass + child
//            layouts. The upper bound for a frame.
//
// IMPORTANT: `flutter test` runs in DEBUG mode (JIT, asserts on), so absolute
// numbers are inflated versus a release/AOT build. Use these for the ratios;
// the AOT pure-resolver benchmark (packages/constraint_engine/benchmark) is
// the release truth for the resolver slice.
//
// Run:  flutter test benchmark/flutter_layout_benchmark.dart

import 'package:constraint_layout/constraint_layout.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Symbol _cell(int r, int c) => Symbol('r${r}c$c');

/// Builds a grid of [rows] x [cols] fixed 80x40 cells: each row is a horizontal
/// spread chain, each row stacked below the previous. Same topology as the pure-
/// engine benchmark so the resolver work is directly comparable.
///
/// With [solverRouted] the middle cell of every row is matchConstraint with a
/// 2:1 aspect ratio; a chain with a ratio-sized member routes the whole layout
/// through the Cassowary solver fallback instead of the dependency graph.
ConstraintLayout buildGrid(int rows, int cols, {bool solverRouted = false}) {
  final children = <Widget>[];
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final ratioCell = solverRouted && c == cols ~/ 2;
      final HorizontalLink left = c == 0
          ? HorizontalLink.leftOf(parent, margin: 16)
          : HorizontalLink.rightOf(_cell(r, c - 1), margin: 8);
      final HorizontalLink right = c == cols - 1
          ? HorizontalLink.rightOf(parent, margin: 16)
          : HorizontalLink.leftOf(_cell(r, c + 1), margin: 8);
      final VerticalLink top;
      if (c == 0) {
        top = r == 0
            ? const VerticalLink.topOf(parent, margin: 16)
            : VerticalLink.bottomOf(_cell(r - 1, 0), margin: 12);
      } else {
        top = VerticalLink.topOf(_cell(r, 0));
      }
      children.add(
        Constrained(
          id: _cell(r, c),
          left: left,
          right: right,
          top: top,
          width: ratioCell ? .matchConstraint : .fixed(80),
          height: .fixed(40),
          aspectRatio: ratioCell ? 2.0 : null,
          child: const SizedBox(),
        ),
      );
    }
  }
  return ConstraintLayout(children: children);
}

class _Stats {
  _Stats(List<int> micros) {
    final sorted = [...micros]..sort();
    min = sorted.first / 1000;
    p50 = sorted[((sorted.length - 1) * 0.50).round()] / 1000;
    p90 = sorted[((sorted.length - 1) * 0.90).round()] / 1000;
    p99 = sorted[((sorted.length - 1) * 0.99).round()] / 1000;
    var sum = 0;
    for (final s in micros) {
      sum += s;
    }
    mean = sum / micros.length / 1000;
  }
  late final double min, mean, p50, p90, p99;
}

_Stats _measure(int warmup, int iters, void Function() op) {
  for (var i = 0; i < warmup; i++) {
    op();
  }
  final samples = List<int>.filled(iters, 0);
  final sw = Stopwatch();
  for (var i = 0; i < iters; i++) {
    sw
      ..reset()
      ..start();
    op();
    sw.stop();
    samples[i] = sw.elapsedMicroseconds;
  }
  return _Stats(samples);
}

String _f(double ms) => ms.toStringAsFixed(3);

void main() {
  const frame120 = 8.333; // ms
  const frame60 = 16.667; // ms

  final tiers = <(String, int, int, int, int)>[
    // name, rows, cols, warmup, iters
    ('Simple', 3, 3, 50, 800),
    ('Intermediate', 8, 6, 50, 500),
    ('Complex', 20, 12, 40, 200),
    ('Heavy', 40, 15, 20, 80),
  ];

  testWidgets('ConstraintLayout Flutter-level layout benchmark', (
    tester,
  ) async {
    // ignore: avoid_print
    print('\nConstraintLayout Flutter-level layout benchmark (DEBUG build)');
    // ignore: avoid_print
    print('Frame budgets: 120fps = 8.333ms, 60fps = 16.667ms\n');

    // Global JIT warmup so the first measured tier isn't penalized.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 800, height: 600, child: buildGrid(20, 12)),
        ),
      ),
    );
    final warm = tester.renderObject<RenderConstraintLayout>(
      find.byType(ConstraintLayout),
    );
    for (var i = 0; i < 400; i++) {
      warm.markNeedsLayout();
      warm.owner!.flushLayout();
    }

    for (final solverRouted in [false, true]) {
      // ignore: avoid_print
      print(
        solverRouted
            ? '======== CASSOWARY SOLVER (ratio chain member, graph declines) ========\n'
            : '======== DEPENDENCY GRAPH ========\n',
      );

      for (final (name, rows, cols, tierWarmup, tierIters) in tiers) {
        // Solver passes are far slower than graph passes (and this is a DEBUG
        // build); scale the sample counts down to keep the run bounded.
        final warmup = solverRouted ? (tierWarmup ~/ 5).clamp(3, 20) : tierWarmup;
        final iters = solverRouted ? (tierIters ~/ 5).clamp(15, 200) : tierIters;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                key: const Key('root-sizer'),
                width: 800,
                height: 600,
                child: buildGrid(rows, cols, solverRouted: solverRouted),
              ),
            ),
          ),
        );

        final ro = tester.renderObject<RenderConstraintLayout>(
          find.byType(ConstraintLayout),
        );
        final sizer = tester.renderObject<RenderConstrainedBox>(
          find.byKey(const Key('root-sizer')),
        );
        final owner = ro.owner!;
        final children = ro.getChildrenAsList();
        final count = children.length;

        // fast: nothing changed; the all-fixed grid skips the engine.
        final fast = _measure(warmup, iters, () {
          ro.markNeedsLayout();
          owner.flushLayout();
        });

        // resolve: alternate the root size so every flush is an engine pass.
        var flip = false;
        final resolve = _measure(warmup, iters, () {
          flip = !flip;
          sizer.additionalConstraints = BoxConstraints.tightFor(
            width: 800,
            height: flip ? 599 : 600,
          );
          owner.flushLayout();
        });

        // full: engine pass + every child re-runs performLayout.
        final full = _measure(warmup, iters, () {
          flip = !flip;
          sizer.additionalConstraints = BoxConstraints.tightFor(
            width: 800,
            height: flip ? 599 : 600,
          );
          for (final child in children) {
            child.markNeedsLayout();
          }
          owner.flushLayout();
        });

        // ignore: invalid_use_of_visible_for_testing_member
        final enginePasses = ro.debugEnginePasses;
        // ignore: invalid_use_of_visible_for_testing_member
        final fastPasses = ro.debugFastPasses;
        // ignore: invalid_use_of_visible_for_testing_member
        final modelBuilds = ro.debugModelBuilds;

        // ignore: avoid_print
        print('== $name  ($rows x $cols = $count widgets) ==');
        // ignore: avoid_print
        print(
          '  slice           p50        p90        p99        mean       min'
          '        %120fps  %60fps',
        );
        _print('fast (no change)', fast, frame120, frame60);
        _print('resolve (resize)', resolve, frame120, frame60);
        _print('full (all dirty)', full, frame120, frame60);
        // Verify the routing matches the label: the LinearSystem holds rows
        // only after a solver pass.
        // ignore: invalid_use_of_visible_for_testing_member
        final solverRows = ro.debugEngineContainer!.mSystem.mNumRows;
        if (solverRouted && solverRows == 0) {
          fail('$name: expected solver fallback, graph resolved it');
        }
        if (!solverRouted && solverRows != 0) {
          fail('$name: expected pure graph, solver ran');
        }

        // ignore: avoid_print
        print(
          '  cache paths taken so far: '
          '$fastPasses fast, $enginePasses engine, $modelBuilds model builds'
          '${solverRouted ? ', $solverRows solver rows' : ''}\n',
        );
      }
    }

    // Settle so the harness tears down with a clean tree.
    await tester.pump();
  });
}

void _print(String label, _Stats s, double frame120, double frame60) {
  // ignore: avoid_print
  print(
    '  ${label.padRight(16)}'
    '${_f(s.p50).padRight(11)}'
    '${_f(s.p90).padRight(11)}'
    '${_f(s.p99).padRight(11)}'
    '${_f(s.mean).padRight(11)}'
    '${_f(s.min).padRight(11)}'
    '${(s.p50 / frame120 * 100).toStringAsFixed(1).padRight(9)}'
    '${(s.p50 / frame60 * 100).toStringAsFixed(1)}',
  );
}
