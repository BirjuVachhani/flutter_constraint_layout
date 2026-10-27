// Adapter benchmark "form" (FORMATS.md section 12): a keystroke relayout
// in a 40-field form held by one ConstraintLayout.
//
// Each row is a label (wrap) baseline-aligned to its field (match constraint
// between a barrier at the labels' end and the parent's end, wrap height);
// every 10th field has an error text below it. A keystroke changes the text
// of field 20 through a ValueNotifier, the frame is built, and then only the
// layout flush is timed. Every child sits under a counting proxy, so a pass
// reports how many child layouts the adapter asked for and ran.
//
// Run (debug JIT, like the repo's flutter_layout_benchmark.dart):
//   cd $CL_FL   (the harness that setup.sh set up)
//   flutter test --concurrency=2 test/bench_form_test.dart \
//     --dart-define=BENCH_OUT=<file>   (default bench_form.txt in $CL_FL)
import 'package:cl_fl_harness/bench_support.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

const int kFields = 40;
const int kTyped = 20;
const String kOut = String.fromEnvironment(
  'BENCH_OUT',
  defaultValue: 'bench_form.txt',
);

Symbol _s(String n) => Symbol(n);

const TextStyle _style = TextStyle(fontSize: 16, height: 1.25);

Widget _counted(LayoutTally t, Widget child) =>
    CountingProxy(tally: t, child: child);

/// Per-role tallies: title, label, field, typed (field $kTyped), error, submit.
final Map<String, LayoutTally> roles = {
  for (final r in ['title', 'label', 'field', 'typed', 'error', 'submit']) r: LayoutTally(),
};

Widget buildForm(LayoutTally tally, ValueNotifier<String> typed) {
  final children = <Widget>[
    Constrained(
      id: #title,
      start: const HorizontalLink.startOf(parent, margin: 16),
      top: const VerticalLink.topOf(parent, margin: 16),
      child: _counted(roles['title']!, const Text('Account details', style: TextStyle(fontSize: 22))),
    ),
  ];
  Symbol? above = #title;
  for (var i = 0; i < kFields; i++) {
    final label = _s('label$i'), field = _s('field$i'), error = _s('error$i');
    children.add(
      Constrained(
        id: label,
        start: const HorizontalLink.startOf(parent, margin: 16),
        baseline: VerticalLink.baselineOf(field),
        child: _counted(roles['label']!, Text('Field label $i', style: _style)),
      ),
    );
    final value = i == kTyped
        ? ValueListenableBuilder<String>(
            valueListenable: typed,
            builder: (context, v, _) => Text(v, style: _style, maxLines: 1),
          )
        : Text('value $i', style: _style, maxLines: 1);
    children.add(
      Constrained(
        id: field,
        start: const HorizontalLink.endOf(#labelsEnd, margin: 12),
        end: const HorizontalLink.endOf(parent, margin: 16),
        top: VerticalLink.bottomOf(above!, margin: 12),
        width: Dimension.matchConstraint,
        child: _counted(
          roles[i == kTyped ? 'typed' : 'field']!,
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
      children.add(
        Constrained(
          id: error,
          start: HorizontalLink.startOf(field),
          end: const HorizontalLink.endOf(parent, margin: 16),
          top: VerticalLink.bottomOf(field, margin: 4),
          width: const Dimension.constrainedWrap(),
          child: _counted(
            roles['error']!,
            const Text('This field needs a value in the expected format.', style: _style),
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
        edge: BarrierEdge.end,
        referenced: [for (var i = 0; i < kFields; i++) _s('label$i')],
      ),
    )
    ..add(
      Constrained(
        id: #submit,
        end: const HorizontalLink.endOf(parent, margin: 16),
        top: VerticalLink.bottomOf(above!, margin: 24),
        width: const Dimension.fixed(120),
        height: const Dimension.fixed(44),
        child: _counted(roles['submit']!, const SizedBox.expand()),
      ),
    );
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 412,
        maxWidth: 412,
        maxHeight: double.infinity,
        child: ConstraintLayout(children: children),
      ),
    ),
  );
}

void main() {
  testWidgets('bench form: keystroke relayout, 40 fields', (tester) async {
    final tally = LayoutTally();
    final typed = ValueNotifier<String>('a');
    await tester.pumpWidget(buildForm(tally, typed));
    final ro = tester.renderObject<RenderConstraintLayout>(
      find.byType(ConstraintLayout),
    );
    final owner = tester.binding.rootPipelineOwner;
    const warmup = 60, iters = 400;
    final micros = <int>[];
    var clPasses = 0, engine = 0, fast = 0, calls = 0, runs = 0;
    final roleCalls = <String, int>{}, roleRuns = <String, int>{};
    final sw = Stopwatch();
    const word = 'quick brown fox jumps';
    for (var i = 0; i < warmup + iters; i++) {
      // A keystroke: the typed text grows by one character, and starts over
      // after a word, so the field stays on one line.
      typed.value = word.substring(0, 1 + i % word.length);
      await tester.pump(Duration.zero, EnginePhase.build);
      final l0 = ro.debugLayoutPasses, e0 = ro.debugEnginePasses, f0 = ro.debugReplayPasses;
      for (final t in roles.values) {
        t.reset();
      }
      sw
        ..reset()
        ..start();
      owner.flushLayout();
      sw.stop();
      if (i >= warmup) {
        micros.add(sw.elapsedMicroseconds);
        clPasses += ro.debugLayoutPasses - l0;
        engine += ro.debugEnginePasses - e0;
        fast += ro.debugReplayPasses - f0;
        for (final e in roles.entries) {
          calls += e.value.calls;
          runs += e.value.runs;
          roleCalls[e.key] = (roleCalls[e.key] ?? 0) + e.value.calls;
          roleRuns[e.key] = (roleRuns[e.key] ?? 0) + e.value.runs;
        }
      }
      await tester.pump();
    }
    final children = ro.childCount;
    BenchStats('form', micros, {
      'children': children,
      'clLayouts/pass': clPasses / iters,
      'enginePasses/pass': engine / iters,
      'replayPasses/pass': fast / iters,
      'childLayoutCalls/pass': calls / iters,
      'childLayoutRuns/pass': runs / iters,
    }).report(kOut, [
      'per role, calls/runs per pass: ${[for (final r in roles.keys) '$r ${(roleCalls[r] ?? 0) / iters}/${(roleRuns[r] ?? 0) / iters}'].join(', ')}',
      'form: one ConstraintLayout, $kFields label + field rows, 4 error texts, a',
      'barrier and a button ($children children), 412 wide, height unbounded;',
      'a keystroke changes field $kTyped text; time = owner.flushLayout() in ms',
      '(debug JIT, flutter test), warmup $warmup, passes $iters.',
    ]);
  });
}
