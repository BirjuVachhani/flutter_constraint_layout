// Adapter benchmark "list" (FORMATS.md section 12): the first layout of
// 50 list items, each its own ConstraintLayout.
//
// A row: an avatar (fixed 40 x 40, centered vertically), a title and a
// subtitle (constrained wrap between the avatar and the trailing value), a
// trailing value on the title's baseline, a chevron (fixed 24 x 24) and a
// divider (match constraint, 1 high). The rows sit in a Column under an
// unbounded height, so every ConstraintLayout wraps its height, as rows of a
// scrolling list do. Each pass builds 50 fresh rows (a new key), and only the
// layout flush of that first frame is timed. Every child sits under a
// counting proxy.
//
// Run (debug JIT):
//   cd $CL_FL   (the harness that setup.sh set up)
//   flutter test --concurrency=2 test/bench_list_test.dart \
//     --dart-define=BENCH_OUT=<file>   (default bench_list.txt in $CL_FL)
import 'package:cl_fl_harness/bench_support.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

const int kRows = 50;
const String kOut = String.fromEnvironment(
  'BENCH_OUT',
  defaultValue: 'bench_list.txt',
);

const TextStyle _title = TextStyle(fontSize: 16, height: 1.25);
const TextStyle _sub = TextStyle(fontSize: 14, height: 1.3);

Widget _counted(LayoutTally t, Widget child) =>
    CountingProxy(tally: t, child: child);

Widget buildRow(LayoutTally tally, int i) => ConstraintLayout(
  children: [
    Constrained(
      id: #avatar,
      start: const HorizontalLink.startOf(parent, margin: 16),
      top: const VerticalLink.topOf(parent, margin: 12),
      bottom: const VerticalLink.bottomOf(parent, margin: 12),
      width: const Dimension.fixed(40),
      height: const Dimension.fixed(40),
      child: _counted(tally, const SizedBox.expand()),
    ),
    Constrained(
      id: #title,
      start: const HorizontalLink.endOf(#avatar, margin: 12),
      end: const HorizontalLink.startOf(#value, margin: 8),
      top: const VerticalLink.topOf(parent, margin: 12),
      width: const Dimension.constrainedWrap(),
      horizontalBias: 0,
      child: _counted(
        tally,
        Text('Item $i: ${'a list title ' * (1 + i % 3)}', style: _title, maxLines: 1),
      ),
    ),
    Constrained(
      id: #subtitle,
      start: const HorizontalLink.startOf(#title),
      end: const HorizontalLink.startOf(#chevron, margin: 8),
      top: const VerticalLink.bottomOf(#title, margin: 2),
      bottom: const VerticalLink.bottomOf(parent, margin: 12),
      width: const Dimension.constrainedWrap(),
      horizontalBias: 0,
      verticalBias: 0,
      child: _counted(
        tally,
        Text('Subtitle for item $i ${'with more words ' * (i % 4)}', style: _sub),
      ),
    ),
    Constrained(
      id: #value,
      end: const HorizontalLink.startOf(#chevron, margin: 8),
      baseline: const VerticalLink.baselineOf(#title),
      child: _counted(tally, Text('${i * 7} min', style: _sub)),
    ),
    Constrained(
      id: #chevron,
      end: const HorizontalLink.endOf(parent, margin: 16),
      top: const VerticalLink.topOf(parent),
      bottom: const VerticalLink.bottomOf(parent),
      width: const Dimension.fixed(24),
      height: const Dimension.fixed(24),
      child: _counted(tally, const SizedBox.expand()),
    ),
    Constrained(
      id: #divider,
      start: const HorizontalLink.startOf(#title),
      end: const HorizontalLink.endOf(parent),
      bottom: const VerticalLink.bottomOf(parent),
      width: Dimension.matchConstraint,
      height: const Dimension.fixed(1),
      child: _counted(tally, const SizedBox.expand()),
    ),
  ],
);

Widget buildList(LayoutTally tally, int generation) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: 412,
      maxWidth: 412,
      maxHeight: double.infinity,
      child: Column(
        key: ValueKey<int>(generation),
        mainAxisSize: MainAxisSize.min,
        children: [for (var i = 0; i < kRows; i++) buildRow(tally, i)],
      ),
    ),
  ),
);

void main() {
  testWidgets('bench list: first layout of $kRows items', (tester) async {
    final tally = LayoutTally();
    final owner = tester.binding.rootPipelineOwner;
    const warmup = 8, iters = 60;
    final micros = <int>[];
    var clPasses = 0, engine = 0, calls = 0, runs = 0;
    final sw = Stopwatch();
    for (var i = 0; i < warmup + iters; i++) {
      await tester.pumpWidget(buildList(tally, i), phase: EnginePhase.build);
      tally.reset();
      sw
        ..reset()
        ..start();
      owner.flushLayout();
      sw.stop();
      final layouts = tester
          .renderObjectList<RenderConstraintLayout>(find.byType(ConstraintLayout))
          .toList();
      if (layouts.length != kRows) {
        throw StateError('expected $kRows rows, found ${layouts.length}');
      }
      if (i >= warmup) {
        micros.add(sw.elapsedMicroseconds);
        for (final ro in layouts) {
          clPasses += ro.debugLayoutPasses;
          engine += ro.debugEnginePasses;
        }
        calls += tally.calls;
        runs += tally.runs;
      }
      await tester.pump();
    }
    BenchStats('list', micros, {
      'rows': kRows,
      'childrenPerRow': 6,
      'clLayouts/pass': clPasses / iters,
      'enginePasses/pass': engine / iters,
      'childLayoutCalls/pass': calls / iters,
      'childLayoutRuns/pass': runs / iters,
      'childLayoutRuns/row': runs / iters / kRows,
    }).report(kOut, [
      'list: $kRows rows, each a ConstraintLayout of 6 children (avatar, title,',
      'subtitle, baseline-aligned value, chevron, divider), 412 wide in a',
      'Column under an unbounded height; time = owner.flushLayout() of the',
      'first frame in ms (debug JIT, flutter test), warmup $warmup, passes $iters.',
    ]);
  });
}
