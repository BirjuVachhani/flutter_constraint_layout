// The pass structure of ConstraintWidgetContainer.measure (upstream's
// BasicMeasure.solverMeasure) and layout() (ConstraintWidgetContainer.java
// 667-1007), at level 0, without upstream's Direct pass, unless a test says
// otherwise: the passes, their iterations, and the state that one pass or
// iteration leaves for the next.
//
// measure() measures the children, runs layout() (pass 0), measures the
// match-constraint children again and runs layout() again when that changed
// something (passes 1 and 2), each pass from the container size measure()
// started with. layout() iterates its solver loop while a frame records an
// override, and once for the "measured too small" clamp, at most 9 times.
//
// The observations are what Java's DirectProbe records on the pinned oracle
// (VOpDriver v2, core path, echo measurer, -Dprobe -Dtranscript, levels
// 257,0 and 64,128): the passes and their iterations (its P field:
// `passes=3 it=1,1,1`) and every measure request (its T field, FORMATS.md
// 8.5: `src:name:strategy:HV:w,h:e:mw,mh,mb,hasB nsp`). Each test cites the
// oracle's op list and its J0 line (Java J257, where Direct runs, differs
// only where a test says so).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/echo_measurer.dart';

String _behaviour(DimensionBehaviour? b) => switch (b) {
  DimensionBehaviour.fixed => 'F',
  DimensionBehaviour.wrapContent => 'W',
  DimensionBehaviour.matchConstraint => 'M',
  DimensionBehaviour.matchParent => 'P',
  null => '?',
};

/// A container that records what Java's DirectProbe records: the pass of
/// each layout() with the container size it starts from, and the iterations
/// of each pass (from [ConstraintWidgetContainer.mCountSolve]).
class _ProbeContainer extends ConstraintWidgetContainer {
  _ProbeContainer(int width, int height) : super.rect(0, 0, width, height) {
    setDebugName('root');
  }

  /// One entry per layout(): `pass:width x height`.
  final List<String> passes = [];

  /// Iterations per layout(), in pass order.
  final List<int> iterations = [];

  @override
  void layout() {
    passes.add('$mPass:${getWidth()} x ${getHeight()}');
    iterations.add(0);
    super.layout();
  }

  @override
  bool addChildrenToSolver(LinearSystem system) {
    // mCountSolve is the solver loop's iteration, counted from 1.
    iterations[iterations.length - 1] = mCountSolve;
    return super.addChildrenToSolver(system);
  }

  /// The P field's `passes=N it=a,b,c`.
  String get probe => 'passes=${passes.length} it=${iterations.join(',')}';
}

/// The echo measurer ([EchoMeasurer], VOpDriver's core-path `Echo`) with
/// DirectProbe's transcript of every request: `M` for measureChildren and
/// `R` for the re-measure passes (BasicMeasure's own Measure, by identity
/// and strategy), `X` for any other Measure.
class _Transcript implements Measurer {
  _Transcript(this.container);

  final ConstraintWidgetContainer container;
  final List<String> entries = [];
  static const _echo = EchoMeasurer();

  @override
  void measure(ConstraintWidget widget, Measure m) {
    final String source;
    if (identical(m, container.mBasicMeasureSolver.mMeasure)) {
      source = m.measureStrategy == Measure.SELF_DIMENSIONS ? 'M' : 'R';
    } else {
      source = 'X';
    }
    final request =
        '$source:${widget.getDebugName()}:${m.measureStrategy}:'
        '${_behaviour(m.horizontalBehavior)}${_behaviour(m.verticalBehavior)}:'
        '${m.horizontalDimension},${m.verticalDimension}';
    _echo.measure(widget, m);
    entries.add(
      '$request:e:${m.measuredWidth},${m.measuredHeight},'
      '${m.measuredBaseline},${m.measuredHasBaseline ? 1 : 0}'
      '${m.measuredNeedsSolverPass ? 1 : 0}',
    );
  }

  @override
  void didMeasures() {}

  /// The T field: the entries joined by one space.
  String get transcript => entries.join(' ');
}

/// OpDriver's core-path measure: the container's own behaviours give the
/// modes (wrap content AT_MOST, otherwise EXACTLY) at its current size.
void _measure(ConstraintWidgetContainer root, int level) {
  root.setOptimizationLevel(level);
  final wrapW =
      root.getHorizontalDimensionBehaviour() == DimensionBehaviour.wrapContent;
  final wrapH =
      root.getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent;
  root.measure(
    level,
    wrapW ? BasicMeasure.AT_MOST : BasicMeasure.EXACTLY,
    root.getWidth(),
    wrapH ? BasicMeasure.AT_MOST : BasicMeasure.EXACTLY,
    root.getHeight(),
    0,
    0,
    0,
    0,
  );
}

String _frame(ConstraintWidget w) =>
    '${w.getDebugName()}: (${w.getX()}, ${w.getY()}) '
    '${w.getWidth()} x ${w.getHeight()}';

/// The passes layout, which needs BasicMeasure's passes 1 and 2:
/// `R 732 420;w w0 64 90;w w1 116 80;w w2 136 94;add w2;add w1;add w0;
/// c w1 L w0 L 18;c w1 R root L 14;hb w1 M;hm w1 0 42 212 1.0;
/// c w2 R root L 0;hb w2 W`.
(_ProbeContainer, _Transcript, List<ConstraintWidget>) _passesLayout() {
  final root = _ProbeContainer(732, 420);
  final transcript = _Transcript(root);
  root.setMeasurer(transcript);
  final w0 = ConstraintWidget.sizeNamed('w0', 64, 90);
  final w1 = ConstraintWidget.sizeNamed('w1', 116, 80);
  final w2 = ConstraintWidget.sizeNamed('w2', 136, 94);
  root.addAll([w2, w1, w0]);
  w1.connect(.left, w0, .left, 18);
  w1.connect(.right, root, .left, 14);
  w1.setHorizontalDimensionBehaviour(.matchConstraint);
  w1.setHorizontalMatchStyle(
    ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
    42,
    212,
    1,
  );
  w2.connect(.right, root, .left, 0);
  w2.setHorizontalDimensionBehaviour(.wrapContent);
  return (root, transcript, [w2, w1, w0]);
}

void main() {
  group('measure(): the passes', () {
    test('a layout without a match-constraint child takes one pass of one '
        'iteration', () {
      // Java J0: a: (10, 20) 100 x 40, P0 `passes=1 it=1`, T0
      // `M:a:0:FF:100,40:e:100,40,0,00` (VOpDriver core: R 400 300;
      // w a 100 40;add a;c a L root L 10;c a T root T 20).
      final root = _ProbeContainer(400, 300);
      final transcript = _Transcript(root);
      root.setMeasurer(transcript);
      final a = ConstraintWidget.sizeNamed('a', 100, 40);
      root.add(a);
      a.connect(.left, root, .left, 10);
      a.connect(.top, root, .top, 20);

      _measure(root, Optimizer.OPTIMIZATION_NONE);

      expect(root.probe, 'passes=1 it=1');
      expect(transcript.transcript, 'M:a:0:FF:100,40:e:100,40,0,00');
      expect(_frame(a), 'a: (10, 20) 100 x 40');
    });

    test('a re-measure that changes a size runs passes 1 and 2, each from '
        'the size measure() started with', () {
      final (root, transcript, widgets) = _passesLayout();

      _measure(root, Optimizer.OPTIMIZATION_NONE);

      // Java J0 (VOpDriver core, the passes layout's op list):
      // root 732 x 420 | w2: (-133, 0) 133 x 94 | w1: (-18, 0) 41 x 80 |
      // w0: (0, 0) 64 x 90; P0 passes=3 it=1,1,1; T0 below.
      expect(root.probe, 'passes=3 it=1,1,1');
      expect(root.passes, ['0:732 x 420', '1:732 x 420', '2:732 x 420']);
      expect(
        transcript.transcript,
        'M:w2:0:WF:136,94:e:136,94,0,00 M:w1:0:MF:116,80:e:116,80,0,00 '
        'M:w0:0:FF:64,90:e:64,90,0,00 R:w1:1:MF:41,80:e:42,80,0,00 '
        'R:w1:2:MF:41,80:e:42,80,0,00',
      );
      expect(widgets.map(_frame), [
        'w2: (-133, 0) 133 x 94',
        'w1: (-18, 0) 41 x 80',
        'w0: (0, 0) 64 x 90',
      ]);
    });

    test('measureChildren and the re-measure passes reuse BasicMeasure\'s one '
        'Measure, which keeps the outputs of the previous request', () {
      final (root, _, _) = _passesLayout();
      final seen = <Measure>{};
      final baselines = <int>[];
      root.setMeasurer(
        _Spy((widget, m) {
          seen.add(m);
          baselines.add(m.measuredBaseline);
          m.measuredWidth = m.horizontalDimension;
          m.measuredHeight = m.verticalDimension;
          m.measuredBaseline = widget.getWidth();
          m.measuredHasBaseline = false;
        }),
      );

      _measure(root, Optimizer.OPTIMIZATION_NONE);

      expect(seen, hasLength(1));
      expect(identical(seen.single, root.mBasicMeasureSolver.mMeasure), isTrue);
      // Each request starts with the baseline the previous one wrote: the
      // first is a new Measure's 0.
      expect(baselines.first, 0);
      expect(baselines.sublist(1), isNot(contains(0)));
    });

    test('a wrap-content axis restarts every pass from the size measure() '
        'started with', () {
      // The passes layout in a container that wraps its width from 0: each
      // pass starts at 0, whatever the pass before it solved. Java J0
      // (`R 0 420;wrapw;` and the passes layout's other ops): root
      // 64 x 420, the frames of the passes layout, P0 `passes=3 it=1,1,1`.
      final (root, _, widgets) = _passesLayout();
      root.setHorizontalDimensionBehaviour(.wrapContent);
      root.setWidth(0);

      _measure(root, Optimizer.OPTIMIZATION_NONE);

      expect(root.passes, ['0:0 x 420', '1:0 x 420', '2:0 x 420']);
      expect(root.probe, 'passes=3 it=1,1,1');
      expect([root.getWidth(), root.getHeight()], [64, 420]);
      expect(widgets.map(_frame), [
        'w2: (-133, 0) 133 x 94',
        'w1: (-18, 0) 41 x 80',
        'w0: (0, 0) 64 x 90',
      ]);
    });

    test('without children, measure() needs no measurer and runs no pass', () {
      final root = _ProbeContainer(400, 300);

      _measure(root, Optimizer.OPTIMIZATION_NONE);

      expect(root.passes, isEmpty);
      expect([root.getWidth(), root.getHeight()], [400, 300]);
    });

    test('with a child and no measurer, measure() throws a StateError that '
        'names setMeasurer', () {
      final root = _ProbeContainer(400, 300);
      root.add(ConstraintWidget.sizeNamed('a', 10, 10));

      expect(
        () => _measure(root, Optimizer.OPTIMIZATION_NONE),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('setMeasurer'),
          ),
        ),
      );
      expect(root.passes, isEmpty);
    });

    test('a ratio axis the first solve resolved is measured fixed by the '
        're-measure pass', () {
      // Java J0: Q: (0, 0) 100 x 56, P0 `passes=1 it=1`, T0
      // `M:Q:0:FM:100,0:e:100,0,0,00 R:Q:1:FF:100,56:e:100,56,0,00`
      // (VOpDriver core: R 400 800;w Q 100 0;add Q;hb Q F;vb Q M;
      // ra Q 1.7777778 -1;c Q L root L 0;c Q T root T 0). At J257 Direct
      // measures it first (`P:Q:0:FF:100,56`).
      final root = _ProbeContainer(400, 800);
      final transcript = _Transcript(root);
      root.setMeasurer(transcript);
      final q = ConstraintWidget.sizeNamed('Q', 100, 0);
      root.add(q);
      q.setHorizontalDimensionBehaviour(.fixed);
      q.setVerticalDimensionBehaviour(.matchConstraint);
      q.setDimensionRatio(1.7777778, ConstraintWidget.UNKNOWN);
      q.connect(.left, root, .left);
      q.connect(.top, root, .top);

      _measure(root, Optimizer.OPTIMIZATION_NONE);

      expect(
        transcript.transcript,
        'M:Q:0:FM:100,0:e:100,0,0,00 R:Q:1:FF:100,56:e:100,56,0,00',
      );
      expect(root.probe, 'passes=1 it=1');
      expect(_frame(q), 'Q: (0, 0) 100 x 56');
    });
  });

  group('measure(): which children are measured first', () {
    // At OPTIMIZATION_DIRECT, measureChildren leaves the children upstream's
    // Direct pass may size to it: a spread match-constraint axis against a
    // non-match-constraint one, and a ratio. A VirtualLayout is measured
    // whatever its axes. Match constraint on both axes is never measured
    // first. Java's M entries, T0 `M:s M:r M:f` and T257 `M:f`, for
    // `R 600 400;w s 0 30;add s;hb s M;c s L root L 0;c s R root R 0;
    // c s T root T 0;w r 50 0;add r;vb r M;ra r 2.0 -1;c r L root L 0;
    // c r T root T 0;w mm 0 0;add mm;hb mm M;vb mm M;c mm L root L 0;
    // c mm R root R 0;c mm T root T 0;c mm B root B 0;w f 40 20;add f;
    // c f L root L 0;c f T root T 0`.
    (_ProbeContainer, _Transcript) build() {
      final root = _ProbeContainer(600, 400);
      final transcript = _Transcript(root);
      root.setMeasurer(transcript);
      final s = ConstraintWidget.sizeNamed('s', 0, 30);
      root.add(s);
      s.setHorizontalDimensionBehaviour(.matchConstraint);
      s.connect(.left, root, .left);
      s.connect(.right, root, .right);
      s.connect(.top, root, .top);
      final r = ConstraintWidget.sizeNamed('r', 50, 0);
      root.add(r);
      r.setVerticalDimensionBehaviour(.matchConstraint);
      r.setDimensionRatio(2, ConstraintWidget.UNKNOWN);
      r.connect(.left, root, .left);
      r.connect(.top, root, .top);
      final mm = ConstraintWidget.sizeNamed('mm', 0, 0);
      root.add(mm);
      mm.setHorizontalDimensionBehaviour(.matchConstraint);
      mm.setVerticalDimensionBehaviour(.matchConstraint);
      mm.connect(.left, root, .left);
      mm.connect(.right, root, .right);
      mm.connect(.top, root, .top);
      mm.connect(.bottom, root, .bottom);
      final f = ConstraintWidget.sizeNamed('f', 40, 20);
      root.add(f);
      f.connect(.left, root, .left);
      f.connect(.top, root, .top);
      return (root, transcript);
    }

    List<String> measuredFirst(int level) {
      final (root, transcript) = build();
      _measure(root, level);
      return [
        for (final e in transcript.entries)
          if (e.startsWith('M:')) e.split(':')[1],
      ];
    }

    test('level 0 measures every child but the match x match one', () {
      expect(measuredFirst(Optimizer.OPTIMIZATION_NONE), ['s', 'r', 'f']);
    });

    test('OPTIMIZATION_STANDARD leaves the spread and the ratio child to '
        'Direct', () {
      expect(measuredFirst(Optimizer.OPTIMIZATION_STANDARD), ['f']);
    });
  });

  group('layout(): the iterations of one pass', () {
    test('the "measured too small" clamp holds a wrap-content width at the '
        'size the pass started from', () {
      // Java J0 (VOpDriver core: R 427 578;wrapw;w w0 155 40;add w0;
      // hb w0 M;hm w0 2 144 0 0.25): root 427 x 578, w0: (0, 0) 144 x 40;
      // P0 `passes=1 it=2 ... ts=10`; T0
      // `M:w0:0:MF:155,40:e:155,40,0,00 R:w0:1:MF:144,40:e:144,40,0,00`.
      // J257 is the same.
      final root = _ProbeContainer(427, 578);
      final transcript = _Transcript(root);
      root.setMeasurer(transcript);
      root.setHorizontalDimensionBehaviour(.wrapContent);
      final w0 = ConstraintWidget.sizeNamed('w0', 155, 40);
      root.add(w0);
      w0.setHorizontalDimensionBehaviour(.matchConstraint);
      w0.setHorizontalMatchStyle(
        ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
        144,
        0,
        0.25,
      );

      _measure(root, Optimizer.OPTIMIZATION_NONE);

      expect(root.probe, 'passes=1 it=2');
      expect(
        transcript.transcript,
        'M:w0:0:MF:155,40:e:155,40,0,00 R:w0:1:MF:144,40:e:144,40,0,00',
      );
      expect([root.getWidth(), root.getHeight()], [427, 578]);
      expect(_frame(w0), 'w0: (0, 0) 144 x 40');
      expect(root.isWidthMeasuredTooSmall(), isTrue);
      expect(root.isHeightMeasuredTooSmall(), isFalse);
      // layout() restores the behaviour the clamp overrode.
      expect(
        root.getHorizontalDimensionBehaviour(),
        DimensionBehaviour.wrapContent,
      );
    });

    test('a wrap-content axis that starts at 0 is never clamped', () {
      // Java J0: root 165 x 578, w0: (10, 0) 155 x 40, P0 `passes=1 it=1
      // ... ts=00` (VOpDriver core: R 0 578;wrapw;w w0 155 40;add w0;
      // c w0 L root L 10).
      final root = _ProbeContainer(0, 578);
      root.setMeasurer(_Transcript(root));
      root.setHorizontalDimensionBehaviour(.wrapContent);
      final w0 = ConstraintWidget.sizeNamed('w0', 155, 40);
      root.add(w0);
      w0.connect(.left, root, .left, 10);

      _measure(root, Optimizer.OPTIMIZATION_NONE);

      expect(root.probe, 'passes=1 it=1');
      expect(root.getWidth(), 165);
      expect(root.isWidthMeasuredTooSmall(), isFalse);
    });

    test('a size override solves again, at most 9 times, and one left '
        'pending is applied by the next measure', () {
      // A fill centered at its 150 px minimum in a 100 px container starts
      // at -25, which the solver reads back as -24, so its width reads 149
      // and every iteration records an override until the ninth. Java J0
      // (VOpDriver core: R 100 100;w a 0 20;add a;hb a M;mw a 150;
      // c a L root L 0;c a R root R 0;c a T root T 0): a: (-24, 0) 150 x 20,
      // P0 `passes=1 it=9`; with `;L;cw 400` appended: a: (125, 0) 150 x 20,
      // P0 `passes=1 it=1`. (J257 differs: Direct resolves the fill, at
      // (0, 0) 150 x 20 and then (0, 0) 400 x 20.)
      final root = _ProbeContainer(100, 100);
      root.setMeasurer(_Transcript(root));
      final a = ConstraintWidget.sizeNamed('a', 0, 20);
      root.add(a);
      a.setHorizontalDimensionBehaviour(.matchConstraint);
      a.setMinWidth(150);
      a.connect(.left, root, .left);
      a.connect(.right, root, .right);
      a.connect(.top, root, .top);

      _measure(root, Optimizer.OPTIMIZATION_NONE);

      expect(root.iterations, [9]);
      expect(_frame(a), 'a: (-24, 0) 150 x 20');
      expect(a.hasDimensionOverride(), isTrue);

      root.setWidth(400);
      _measure(root, Optimizer.OPTIMIZATION_NONE);

      expect(root.iterations, [9, 1]);
      expect(_frame(a), 'a: (125, 0) 150 x 20');
      expect(a.hasDimensionOverride(), isFalse);
    });

    test('mCountSolve is -1 outside layout(), 0 before its loop, then the '
        'iteration', () {
      final root = _ProbeContainer(200, 100);
      final nested = _NestedProbe(root);
      root.add(nested);
      expect(root.mCountSolve, -1);

      root.layout();

      // A nested container is laid out before the parent's loop.
      expect(nested.parentCountSolve, [0]);
      expect(root.iterations, [1]);
      expect(root.mCountSolve, -1);
    });

    test('a barrier keeps the final value it gave itself from one measure '
        'to the next', () {
      // A right barrier whose only reference is gone, without
      // allowsGoneWidget, counts no reference: Barrier.allSolved resolves it
      // at its margin, -8, and the solver reads it back as -7. Without
      // Direct nothing clears that resolution (setFinalHorizontal keeps the
      // first one), so the next solve pins the barrier at the x the last
      // readback left, -7, which reads back as -6, and so on. Java J0
      // (VOpDriver core: R 300 200;rtl;b b;add b;bt b 1;bg b 0;bm b -8;
      // w v 40 20;add v;w t 100 20;add t;ref b v;v v 8;c v L root L 16;
      // hb t M;c t L b R 0;c t R root R 12;c t T root T 10, then with one,
      // two and three L ops appended): b at -7, -6, -5 and -4. J257 stays
      // at -7: Direct forgets the resolution on every measure.
      final root = _ProbeContainer(300, 200);
      root.setRtl(true);
      final b = Barrier.named('b')
        ..setBarrierType(Barrier.right)
        ..setAllowsGoneWidget(false)
        ..setMargin(-8);
      root.add(b);
      final v = ConstraintWidget.sizeNamed('v', 40, 20);
      root.add(v);
      final t = ConstraintWidget.sizeNamed('t', 100, 20);
      root.add(t);
      b.add(v);
      v.setVisibility(ConstraintWidget.GONE);
      v.connect(.left, root, .left, 16);
      t.setHorizontalDimensionBehaviour(.matchConstraint);
      t.connect(.left, b, .right);
      t.connect(.right, root, .right, 12);
      t.connect(.top, root, .top, 10);

      root.setMeasurer(_Transcript(root));
      final frames = <String>[];
      for (var i = 0; i < 4; i++) {
        _measure(root, Optimizer.OPTIMIZATION_NONE);
        frames.add('${_frame(b)} | ${_frame(t)}');
      }

      expect(frames, [
        'b: (-7, 0) 0 x 0 | t: (-7, 10) 295 x 20',
        'b: (-6, 0) 0 x 0 | t: (-6, 10) 294 x 20',
        'b: (-5, 0) 0 x 0 | t: (-5, 10) 293 x 20',
        'b: (-4, 0) 0 x 0 | t: (-4, 10) 292 x 20',
      ]);
    });

    test('a barrier that references a barrier reads the mResolved that '
        'barrier\'s addToSolver cleared', () {
      // b1 references b0, which resolves itself (Barrier.allSolved) and
      // clears its mResolved in addToSolver, before b1 asks whether it is
      // resolved: upstream's Barrier.isResolvedHorizontally returns mResolved
      // (Barrier.java 91-98), so b1 is not, and the solver places it. Java J0
      // (VOpDriver core: R 894 827;w w1 60 70;b b0;add b0;b b1;add b1;
      // w w4 20 36;add w4;b b2;add b2;b top;add top;w t0 33 49;v w1 8;
      // bg b0 0;ref b0 w1;bt b1 1;ref b1 b0;bt b2 1;ref b2 w4;ref top b1;
      // ref top b2;c t0 L top R 10;c t0 R root R 5): the frames below, with
      // b1 and top at 20; P0 `passes=1 it=1`. Needs the port's Barrier to
      // override isResolvedHorizontally and isResolvedVertically as upstream
      // does.
      final root = _ProbeContainer(894, 827);
      final transcript = _Transcript(root);
      root.setMeasurer(transcript);
      final w1 = ConstraintWidget.sizeNamed('w1', 60, 70);
      final b0 = Barrier.named('b0');
      root.add(b0);
      final b1 = Barrier.named('b1');
      root.add(b1);
      final w4 = ConstraintWidget.sizeNamed('w4', 20, 36);
      root.add(w4);
      final b2 = Barrier.named('b2');
      root.add(b2);
      final top = Barrier.named('top');
      root.add(top);
      final t0 = ConstraintWidget.sizeNamed('t0', 33, 49);
      w1.setVisibility(ConstraintWidget.GONE);
      b0.setAllowsGoneWidget(false);
      b0.add(w1);
      b1.setBarrierType(Barrier.right);
      b1.add(b0);
      b2.setBarrierType(Barrier.right);
      b2.add(w4);
      top.add(b1);
      top.add(b2);
      t0.connect(.left, top, .right, 10);
      t0.connect(.right, root, .right, 5);

      _measure(root, Optimizer.OPTIMIZATION_NONE);

      expect(root.getChildren().map(_frame), [
        'b0: (0, 0) 0 x 0',
        'b1: (20, 0) 0 x 0',
        'w4: (0, 0) 20 x 36',
        'b2: (20, 0) 0 x 0',
        'top: (20, 0) 0 x 0',
      ]);
      expect(root.probe, 'passes=1 it=1');
      expect(transcript.transcript, 'M:w4:0:FF:20,36:e:20,36,0,00');
    });
  });

  group('the dependency graph runs only at the GRAPH levels', () {
    // BasicMeasure.solverMeasure runs the graph at OPTIMIZATION_GRAPH (or
    // GRAPH_WRAP) when no child is in a chain or is a VirtualLayout and both
    // modes are EXACTLY; when the graph resolves both axes, the solver never
    // runs. Elsewhere layout() solves, and no widget run is ever created.
    // Java (VOpDriver core, levels 64 and 128: R 400 300;w a 100 40;
    // w b 60 40;add a;add b;c a L root L 10;c a T root T 10;c b L a R 10;
    // c b T a T 0): `passes=0` and the graph's own requests, T64
    // `X:a:0:FF:100,40:e:100,40,0,00 X:b:0:FF:60,40:e:60,40,0,00`; with
    // `;c a R b L 0;c b R root R 0` (a chain) or `;fl f;add f;
    // c f L root L 0;c f T root T 0` (a Flow), `passes=1 it=1`.
    _ProbeContainer build({bool chain = false, bool flow = false}) {
      final root = _ProbeContainer(400, 300);
      root.setMeasurer(_Transcript(root));
      final a = ConstraintWidget.sizeNamed('a', 100, 40);
      final b = ConstraintWidget.sizeNamed('b', 60, 40);
      root.addAll([a, b]);
      a.connect(.left, root, .left, 10);
      a.connect(.top, root, .top, 10);
      b.connect(.left, a, .right, 10);
      b.connect(.top, a, .top);
      if (chain) {
        a.connect(.right, b, .left);
        b.connect(.right, root, .right);
      }
      if (flow) {
        final f = Flow()..setDebugName('f');
        root.add(f);
        f.connect(.left, root, .left);
        f.connect(.top, root, .top);
      }
      return root;
    }

    for (final level in [
      Optimizer.OPTIMIZATION_GRAPH,
      Optimizer.OPTIMIZATION_GRAPH_WRAP,
    ]) {
      test('level $level with EXACTLY modes resolves on the graph', () {
        final root = build();
        _measure(root, level);
        expect(root.passes, isEmpty);
        expect(
          (root.getMeasurer()! as _Transcript).transcript,
          'X:a:0:FF:100,40:e:100,40,0,00 X:b:0:FF:60,40:e:60,40,0,00',
        );
        expect(root.getChildren().map(_frame), [
          'a: (10, 10) 100 x 40',
          'b: (120, 10) 60 x 40',
        ]);
        expect(root.getChildren().first.mHorizontalRun, isNotNull);
      });
    }

    test('a chain keeps the graph off', () {
      final root = build(chain: true);
      _measure(root, Optimizer.OPTIMIZATION_GRAPH);
      expect(root.probe, 'passes=1 it=1');
      expect(root.getChildren().map(_frame), [
        'a: (83, 10) 100 x 40',
        'b: (267, 10) 60 x 40',
      ]);
    });

    test('a VirtualLayout keeps the graph off', () {
      final root = build(flow: true);
      _measure(root, Optimizer.OPTIMIZATION_GRAPH);
      expect(root.probe, 'passes=1 it=1');
    });

    test('level 0 never runs the graph', () {
      final root = build();
      _measure(root, Optimizer.OPTIMIZATION_NONE);
      expect(root.passes, ['0:400 x 300']);
      expect(root.getChildren().first.mHorizontalRun, isNull);
    });
  });
}

/// A measurer that runs [onMeasure].
class _Spy implements Measurer {
  _Spy(this.onMeasure);

  final void Function(ConstraintWidget widget, Measure measure) onMeasure;

  @override
  void measure(ConstraintWidget widget, Measure measure) =>
      onMeasure(widget, measure);

  @override
  void didMeasures() {}
}

/// A nested container that records its parent's mCountSolve when laid out.
class _NestedProbe extends ConstraintWidgetContainer {
  _NestedProbe(this.parent) : super.rect(0, 0, 10, 10);

  final ConstraintWidgetContainer parent;
  final List<int> parentCountSolve = [];

  @override
  void layout() {
    parentCountSolve.add(parent.mCountSolve);
    super.layout();
  }
}
