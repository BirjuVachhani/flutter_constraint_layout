// Flutter-level layout benchmark for ConstraintLayout.
//
// Measures the real `RenderConstraintLayout.performLayout` cost inside
// Flutter's layout pipeline, against the persistent-model cache.
//
// Grids: rows x cols cells of 80 x 40, each row stacked below the previous
// one, in three shapes:
//
//   FIXED CELLS  each row a horizontal spread chain: the solver sizes and
//                places every row (the engine dominates).
//   RATIO CELLS  the same, with a 2:1 match-constraint cell in every row.
//   FLAT CELLS   each cell linked to the one before it only, no chain: the
//                Direct pass resolves the whole layout, so the time is the
//                adapter's and the measure path's own (most real layouts
//                are like this).
//
// Three slices per tier:
//
//   replay   markNeedsLayout on the container only, nothing changed. The
//            layout replays its last confirmed engine run: every measured
//            child is asked again and the recorded frames are reused. Its
//            constraints are unchanged and it is clean, so Flutter's own
//            layout cache runs no child layout: the benchmark checks 0 runs.
//   resolve  the incoming constraints alternate between two sizes, so every
//            flush is a real engine pass on the persistent model (measure +
//            placement); children are laid out only where their constraints
//            change.
//   full     resize plus every child marked dirty: engine pass + child
//            layouts. The upper bound for a frame.
//
// Scenarios: the adapter on realistic children (text with baselines, wrap
// content, an unbounded height), the trees of the parity harness's form and
// list benchmarks (tool/parity/fl_harness/test/bench_form_test.dart and
// bench_list_test.dart):
//
//   form keystroke  a 40-field form (87 children, labels on their fields'
//                   baselines, a barrier, wrapping error texts); a keystroke
//                   changes one field's text. The layout replays.
//   list first      the first layout of 50 list rows, each its own
//                   ConstraintLayout of 6 children: model builds and first
//                   engine runs.
//   intrinsic form  the form in an IntrinsicHeight: every keystroke also asks
//                   the layout for its maximum intrinsic height, a dry query
//                   that replays its last one while the children's answers
//                   hold.
//
// Each slice also reports the child layouts per pass: calls to a child's
// layout() and the performLayout runs they led to (Android's measure
// sequence measures a child more than once, and placement lays a child out
// again at its frame unless its measure already has that size).
//
// IMPORTANT: `flutter test` runs in DEBUG mode (JIT, asserts on), so absolute
// numbers are inflated versus a release/AOT build, and debug-only work (the
// engine's asserts, Flutter's timeline events for every baseline and dry
// layout query) is part of them. Use these for the ratios; the AOT
// pure-resolver benchmark (packages/constraint_engine/benchmark) is the
// release truth for the resolver slice.
//
// Run:  flutter test benchmark/flutter_layout_benchmark.dart

import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Symbol _cell(int r, int c) => Symbol('r${r}c$c');

/// Counts the layouts the benchmark's children are asked for.
class LayoutCounter {
  int calls = 0;
  int runs = 0;
}

/// A childless box that fills its constraints' smallest size, as a
/// `SizedBox()` does, and counts its layouts.
class _CountedBox extends LeafRenderObjectWidget {
  const _CountedBox(this.counter);

  final LayoutCounter counter;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCountedBox(counter);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCountedBox renderObject,
  ) => renderObject.counter = counter;
}

class _RenderCountedBox extends RenderBox {
  _RenderCountedBox(this.counter);

  LayoutCounter counter;

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    counter.calls++;
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  @override
  void performLayout() {
    counter.runs++;
    size = constraints.smallest;
  }
}

/// Counts the layouts of the child it wraps, adding nothing of its own (it
/// forwards baselines and dry layouts, so the layout sees the child's
/// answers).
class _Counted extends SingleChildRenderObjectWidget {
  const _Counted(this.counter, {required super.child});

  final LayoutCounter counter;

  @override
  _RenderCounted createRenderObject(BuildContext context) =>
      _RenderCounted(counter);

  @override
  void updateRenderObject(BuildContext context, _RenderCounted renderObject) =>
      renderObject.counter = counter;
}

class _RenderCounted extends RenderProxyBox {
  _RenderCounted(this.counter);

  LayoutCounter counter;

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    counter.calls++;
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  @override
  void performLayout() {
    counter.runs++;
    super.performLayout();
  }
}

/// Builds a grid of [rows] x [cols] fixed 80x40 cells, each row stacked below
/// the previous. With [chains] (the default) each row is a horizontal spread
/// chain: the same topology as the pure-engine benchmark's standard tiers, so
/// the resolver work is directly comparable. Without, each cell is linked to
/// the one before it only, so no chain forms and the Direct pass resolves the
/// layout.
///
/// With [withRatio] the middle cell of every row is matchConstraint with a
/// 2:1 aspect ratio, which the solver sizes.
ConstraintLayout buildGrid(
  int rows,
  int cols,
  LayoutCounter counter, {
  bool withRatio = false,
  bool chains = true,
}) {
  final children = <Widget>[];
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final ratioCell = withRatio && c == cols ~/ 2;
      final HorizontalLink left = c == 0
          ? HorizontalLink.leftOf(parent, margin: 16)
          : HorizontalLink.rightOf(_cell(r, c - 1), margin: 8);
      final HorizontalLink? right = !chains
          ? null
          : c == cols - 1
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
          child: _CountedBox(counter),
        ),
      );
    }
  }
  return ConstraintLayout(children: children);
}

// ---------------------------------------------------------------------------
// Scenarios: the trees of the parity harness's form and list benchmarks.
// ---------------------------------------------------------------------------

const TextStyle _fieldStyle = TextStyle(fontSize: 16, height: 1.25);

/// A form of 40 rows, a label on its field's baseline and the field between
/// a barrier at the labels' end and the parent's end, every 10th field with
/// an error text under it, and a button (87 children). [typed] is the text of
/// field 20.
ConstraintLayout buildForm(LayoutCounter counter, ValueNotifier<String> typed) {
  const fields = 40;
  const typedField = 20;
  Widget counted(Widget child) => _Counted(counter, child: child);
  final children = <Widget>[
    Constrained(
      id: #title,
      start: const .startOf(parent, margin: 16),
      top: const .topOf(parent, margin: 16),
      child: counted(
        const Text('Account details', style: TextStyle(fontSize: 22)),
      ),
    ),
  ];
  Symbol above = #title;
  for (var i = 0; i < fields; i++) {
    final label = Symbol('label$i');
    final field = Symbol('field$i');
    children.add(
      Constrained(
        id: label,
        start: const .startOf(parent, margin: 16),
        baseline: .baselineOf(field),
        child: counted(Text('Field label $i', style: _fieldStyle)),
      ),
    );
    final value = i == typedField
        ? ValueListenableBuilder<String>(
            valueListenable: typed,
            builder: (context, v, _) =>
                Text(v, style: _fieldStyle, maxLines: 1),
          )
        : Text('value $i', style: _fieldStyle, maxLines: 1);
    children.add(
      Constrained(
        id: field,
        start: const .endOf(#labelsEnd, margin: 12),
        end: const .endOf(parent, margin: 16),
        top: .bottomOf(above, margin: 12),
        width: .matchConstraint,
        child: counted(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF888888)),
            ),
            child: value,
          ),
        ),
      ),
    );
    if (i % 10 == 9) {
      final error = Symbol('error$i');
      children.add(
        Constrained(
          id: error,
          start: .startOf(field),
          end: const .endOf(parent, margin: 16),
          top: .bottomOf(field, margin: 4),
          width: const .constrainedWrap(),
          child: counted(
            const Text(
              'This field needs a value in the expected format.',
              style: _fieldStyle,
            ),
          ),
        ),
      );
      above = error;
    } else {
      above = field;
    }
  }
  children
    ..add(
      Barrier(
        id: #labelsEnd,
        edge: .end,
        referenced: [for (var i = 0; i < fields; i++) Symbol('label$i')],
      ),
    )
    ..add(
      Constrained(
        id: #submit,
        end: const .endOf(parent, margin: 16),
        top: .bottomOf(above, margin: 24),
        width: .fixed(120),
        height: .fixed(44),
        child: counted(const SizedBox.expand()),
      ),
    );
  return ConstraintLayout(children: children);
}

const TextStyle _titleStyle = TextStyle(fontSize: 16, height: 1.25);
const TextStyle _subtitleStyle = TextStyle(fontSize: 14, height: 1.3);

/// List row [i]: an avatar, a title and a subtitle (constrained wrap), a
/// value on the title's baseline, a chevron and a divider.
ConstraintLayout buildRow(LayoutCounter counter, int i) {
  Widget counted(Widget child) => _Counted(counter, child: child);
  return ConstraintLayout(
    children: [
      Constrained(
        id: #avatar,
        start: const .startOf(parent, margin: 16),
        top: const .topOf(parent, margin: 12),
        bottom: const .bottomOf(parent, margin: 12),
        width: .fixed(40),
        height: .fixed(40),
        child: counted(const SizedBox.expand()),
      ),
      Constrained(
        id: #title,
        start: const .endOf(#avatar, margin: 12),
        end: const .startOf(#value, margin: 8),
        top: const .topOf(parent, margin: 12),
        width: const .constrainedWrap(),
        horizontalBias: 0,
        child: counted(
          Text(
            'Item $i: ${'a list title ' * (1 + i % 3)}',
            style: _titleStyle,
            maxLines: 1,
          ),
        ),
      ),
      Constrained(
        id: #subtitle,
        start: const .startOf(#title),
        end: const .startOf(#chevron, margin: 8),
        top: const .bottomOf(#title, margin: 2),
        bottom: const .bottomOf(parent, margin: 12),
        width: const .constrainedWrap(),
        horizontalBias: 0,
        verticalBias: 0,
        child: counted(
          Text(
            'Subtitle for item $i ${'with more words ' * (i % 4)}',
            style: _subtitleStyle,
          ),
        ),
      ),
      Constrained(
        id: #value,
        end: const .startOf(#chevron, margin: 8),
        baseline: const .baselineOf(#title),
        child: counted(Text('${i * 7} min', style: _subtitleStyle)),
      ),
      Constrained(
        id: #chevron,
        end: const .endOf(parent, margin: 16),
        top: const .topOf(parent),
        bottom: const .bottomOf(parent),
        width: .fixed(24),
        height: .fixed(24),
        child: counted(const SizedBox.expand()),
      ),
      Constrained(
        id: #divider,
        start: const .startOf(#title),
        end: const .endOf(parent),
        bottom: const .bottomOf(parent),
        width: .matchConstraint,
        height: .fixed(1),
        child: counted(const SizedBox.expand()),
      ),
    ],
  );
}

/// [child] 412 wide at the top left, its height unbounded, as a phone-width
/// scrolling page lays it out.
Widget _phoneWidth(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: 412,
      maxWidth: 412,
      maxHeight: double.infinity,
      child: child,
    ),
  ),
);

// ---------------------------------------------------------------------------
// Timing.
// ---------------------------------------------------------------------------

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

/// The child layouts per pass of the samples [_measure] took: calls and
/// performLayout runs.
typedef _ChildLayouts = ({double calls, double runs});

_Stats _measure(
  int warmup,
  int iters,
  LayoutCounter counter,
  void Function() op, {
  required void Function(_ChildLayouts) childLayouts,
}) {
  for (var i = 0; i < warmup; i++) {
    op();
  }
  final samples = List<int>.filled(iters, 0);
  final sw = Stopwatch();
  final calls = counter.calls;
  final runs = counter.runs;
  for (var i = 0; i < iters; i++) {
    sw
      ..reset()
      ..start();
    op();
    sw.stop();
    samples[i] = sw.elapsedMicroseconds;
  }
  childLayouts((
    calls: (counter.calls - calls) / iters,
    runs: (counter.runs - runs) / iters,
  ));
  return _Stats(samples);
}

/// Times the layout flush of [iters] frames after [warmup] ones: [prepare]
/// changes what the frame shows and builds it (without laying it out), the
/// flush is timed, and the rest of the frame follows untimed.
Future<_Stats> _measureFrames(
  WidgetTester tester,
  int warmup,
  int iters,
  LayoutCounter counter,
  Future<void> Function(int frame) prepare, {
  required void Function(_ChildLayouts) childLayouts,
}) async {
  final owner = tester.binding.rootPipelineOwner;
  final samples = <int>[];
  final sw = Stopwatch();
  var calls = 0, runs = 0;
  for (var i = 0; i < warmup + iters; i++) {
    await prepare(i);
    final calls0 = counter.calls, runs0 = counter.runs;
    sw
      ..reset()
      ..start();
    owner.flushLayout();
    sw.stop();
    if (i >= warmup) {
      samples.add(sw.elapsedMicroseconds);
      calls += counter.calls - calls0;
      runs += counter.runs - runs0;
    }
    await tester.pump();
  }
  childLayouts((calls: calls / iters, runs: runs / iters));
  return _Stats(samples);
}

String _f(double ms) => ms.toStringAsFixed(3);

const frame120 = 8.333; // ms
const frame60 = 16.667; // ms

void main() {
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
          child: SizedBox(
            width: 800,
            height: 600,
            child: buildGrid(20, 12, LayoutCounter()),
          ),
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

    for (final (cells, withRatio, chains) in [
      ('FIXED CELLS', false, true),
      ('RATIO CELLS (a 2:1 match-constraint cell per row)', true, true),
      ('FLAT CELLS (rows linked one way, no chain)', false, false),
    ]) {
      // ignore: avoid_print
      print('======== $cells ========\n');

      for (final (name, rows, cols, tierWarmup, tierIters) in tiers) {
        // Ratio cells make every pass solve more; this is a DEBUG build too,
        // so scale the sample counts down to keep the run bounded.
        final warmup = withRatio ? (tierWarmup ~/ 5).clamp(3, 20) : tierWarmup;
        final iters = withRatio ? (tierIters ~/ 5).clamp(15, 200) : tierIters;
        final counter = LayoutCounter();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                key: const Key('root-sizer'),
                width: 800,
                height: 600,
                child: buildGrid(
                  rows,
                  cols,
                  counter,
                  withRatio: withRatio,
                  chains: chains,
                ),
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

        // replay: nothing changed. The first relayout confirms the build's
        // run, so the measured iterations replay it.
        ro.markNeedsLayout();
        owner.flushLayout();
        // ignore: invalid_use_of_visible_for_testing_member
        final replaysBefore = ro.debugReplayPasses;
        late _ChildLayouts replayLayouts;
        final replay = _measure(warmup, iters, counter, () {
          ro.markNeedsLayout();
          owner.flushLayout();
        }, childLayouts: (c) => replayLayouts = c);

        // resolve: alternate the root size so every flush is an engine pass.
        var flip = false;
        late _ChildLayouts resolveLayouts;
        final resolve = _measure(warmup, iters, counter, () {
          flip = !flip;
          sizer.additionalConstraints = BoxConstraints.tightFor(
            width: 800,
            height: flip ? 599 : 600,
          );
          owner.flushLayout();
        }, childLayouts: (c) => resolveLayouts = c);

        // full: engine pass + every child re-runs performLayout.
        late _ChildLayouts fullLayouts;
        final full = _measure(warmup, iters, counter, () {
          flip = !flip;
          sizer.additionalConstraints = BoxConstraints.tightFor(
            width: 800,
            height: flip ? 599 : 600,
          );
          for (final child in children) {
            child.markNeedsLayout();
          }
          owner.flushLayout();
        }, childLayouts: (c) => fullLayouts = c);

        // ignore: invalid_use_of_visible_for_testing_member
        final enginePasses = ro.debugEnginePasses;
        // ignore: invalid_use_of_visible_for_testing_member
        final replayPasses = ro.debugReplayPasses;
        // ignore: invalid_use_of_visible_for_testing_member
        final modelBuilds = ro.debugModelBuilds;

        // ignore: avoid_print
        print('== $name  ($rows x $cols = $count widgets) ==');
        // ignore: avoid_print
        print(
          '  slice           p50        p90        p99        mean       min'
          '        %120fps  %60fps   child layouts/pass (calls, runs)',
        );
        _print('replay', replay, replayLayouts);
        _print('resolve (resize)', resolve, resolveLayouts);
        _print('full (all dirty)', full, fullLayouts);
        // A layout with nothing changed must replay, never run the engine.
        // ignore: invalid_use_of_visible_for_testing_member
        final replays = ro.debugReplayPasses - replaysBefore;
        if (replays < warmup + iters) {
          fail('$name: $replays replays, expected ${warmup + iters}');
        }
        // A replay asks every child again under its unchanged constraints:
        // Flutter's own layout cache must turn each of those layout() calls
        // into no performLayout at all.
        if (replayLayouts.calls < count || replayLayouts.runs != 0) {
          fail(
            '$name: a replay made ${replayLayouts.calls} child layout calls '
            'and ${replayLayouts.runs} runs per pass, expected at least '
            '$count calls and 0 runs',
          );
        }

        // ignore: avoid_print
        print(
          '  paths taken so far: $replayPasses replay, $enginePasses engine, '
          '$modelBuilds model builds\n',
        );
      }
    }

    await _scenarios(tester);

    // Settle so the harness tears down with a clean tree.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

/// The adapter scenarios (see the header).
Future<void> _scenarios(WidgetTester tester) async {
  // ignore: avoid_print
  print(
    '======== SCENARIOS (text children, phone width, height unbounded) '
    '========\n',
  );
  // ignore: avoid_print
  print(
    '  scenario        p50        p90        p99        mean       min'
    '        %120fps  %60fps   child layouts/pass (calls, runs)',
  );
  const word = 'quick brown fox jumps';

  // form keystroke: the layout replays every frame.
  {
    final counter = LayoutCounter();
    final typed = ValueNotifier<String>('a');
    await tester.pumpWidget(_phoneWidth(buildForm(counter, typed)));
    final ro = tester.renderObject<RenderConstraintLayout>(
      find.byType(ConstraintLayout),
    );
    // ignore: invalid_use_of_visible_for_testing_member
    final engine0 = ro.debugEnginePasses, replays0 = ro.debugReplayPasses;
    late _ChildLayouts layouts;
    const warmup = 60, iters = 400;
    final stats = await _measureFrames(tester, warmup, iters, counter, (i) {
      typed.value = word.substring(0, 1 + i % word.length);
      return tester.pump(Duration.zero, EnginePhase.build);
    }, childLayouts: (c) => layouts = c);
    _print('form keystroke', stats, layouts);
    // ignore: avoid_print
    print(
      // ignore: invalid_use_of_visible_for_testing_member
      '    ${ro.childCount} children; per frame ${_per(ro.debugReplayPasses - replays0, warmup + iters)} replay, '
      // ignore: invalid_use_of_visible_for_testing_member
      '${_per(ro.debugEnginePasses - engine0, warmup + iters)} engine',
    );
    typed.dispose();
  }

  // list first: 50 new rows every frame.
  {
    final counter = LayoutCounter();
    const rows = 50;
    Widget list(int generation) => _phoneWidth(
      Column(
        key: ValueKey<int>(generation),
        mainAxisSize: MainAxisSize.min,
        children: [for (var i = 0; i < rows; i++) buildRow(counter, i)],
      ),
    );
    late _ChildLayouts layouts;
    const warmup = 8, iters = 60;
    final stats = await _measureFrames(
      tester,
      warmup,
      iters,
      counter,
      (i) => tester.pumpWidget(list(i), phase: EnginePhase.build),
      childLayouts: (c) => layouts = c,
    );
    _print('list first', stats, layouts);
    // ignore: avoid_print
    print(
      '    $rows rows of 6 children, every one laid out for the first time',
    );
  }

  // intrinsic form: IntrinsicHeight asks for the form's maximum intrinsic
  // height on every keystroke, then lays it out.
  {
    final counter = LayoutCounter();
    final typed = ValueNotifier<String>('a');
    await tester.pumpWidget(
      _phoneWidth(IntrinsicHeight(child: buildForm(counter, typed))),
    );
    final ro = tester.renderObject<RenderConstraintLayout>(
      find.byType(ConstraintLayout),
    );
    // ignore: invalid_use_of_visible_for_testing_member
    final engine0 = ro.debugEnginePasses, replays0 = ro.debugReplayPasses;
    late _ChildLayouts layouts;
    const warmup = 30, iters = 200;
    final stats = await _measureFrames(tester, warmup, iters, counter, (i) {
      typed.value = word.substring(0, 1 + i % word.length);
      return tester.pump(Duration.zero, EnginePhase.build);
    }, childLayouts: (c) => layouts = c);
    _print('intrinsic form', stats, layouts);
    // ignore: avoid_print
    print(
      // ignore: invalid_use_of_visible_for_testing_member
      '    layout per frame ${_per(ro.debugReplayPasses - replays0, warmup + iters)} replay, '
      // ignore: invalid_use_of_visible_for_testing_member
      '${_per(ro.debugEnginePasses - engine0, warmup + iters)} engine\n',
    );
    typed.dispose();
  }
}

String _per(int n, int frames) => (n / frames).toStringAsFixed(2);

void _print(String label, _Stats s, _ChildLayouts layouts) {
  // ignore: avoid_print
  print(
    '  ${label.padRight(16)}'
    '${_f(s.p50).padRight(11)}'
    '${_f(s.p90).padRight(11)}'
    '${_f(s.p99).padRight(11)}'
    '${_f(s.mean).padRight(11)}'
    '${_f(s.min).padRight(11)}'
    '${(s.p50 / frame120 * 100).toStringAsFixed(1).padRight(9)}'
    '${(s.p50 / frame60 * 100).toStringAsFixed(1).padRight(9)}'
    '${layouts.calls.toStringAsFixed(1)}, ${layouts.runs.toStringAsFixed(1)}',
  );
}
