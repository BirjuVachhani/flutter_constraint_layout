// Measure ordering: content whose size on one axis depends on the size the
// layout gives it on the other, as wrapping text's height depends on its
// width. BasicMeasure.solverMeasure measures the children, solves, and
// measures the match-constraint children again at the size the solve gave
// them (passes 1 and 2), so such content ends up measured at its final size.
//
// The text scenarios are op lists on the view path
// (test/support/op_replay.dart): ViewHost, Android's onMeasure, with each
// child's content answering the measure specs (`ct N text W H`: W wide on
// one line, H per line). The expected strings are the pinned oracle's
// (VOpDriver v2, view path, -XX:hashCode=2); unless a test says otherwise,
// the same at levels 257, 0, 64 and 321.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/op_replay.dart';

/// Replays [ops] at [levels] and expects Java's frames, [java], at each.
void expectJava(
  String ops,
  String java, {
  List<int> levels = const [257, 0, 64, 321],
}) {
  for (final level in levels) {
    final r = replayView(ops, level: level);
    expect(r.status, 'ok', reason: 'level $level');
    expect(r.geometry, java, reason: 'level $level');
  }
}

/// A box whose baseline moves with its width while its height stays at 60.
/// The main widget is initially 500 wide, then capped to 300 by the solver.
class _BaselineMeasurer implements Measurer {
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    final a = widget.getDebugName() == 'a';
    final width =
        a &&
            (measure.horizontalBehavior == DimensionBehaviour.wrapContent ||
                (measure.horizontalBehavior ==
                        DimensionBehaviour.matchConstraint &&
                    measure.measureStrategy == Measure.SELF_DIMENSIONS))
        ? 500
        : measure.horizontalDimension;
    final height = measure.verticalBehavior == DimensionBehaviour.wrapContent
        ? 60
        : measure.verticalDimension;
    final baseline = a ? width ~/ 10 : 10;
    measure.measuredWidth = width;
    measure.measuredHeight = height;
    measure.measuredHasBaseline = true;
    measure.measuredBaseline = baseline;
    measure.measuredNeedsSolverPass =
        width != measure.horizontalDimension ||
        height != measure.verticalDimension ||
        baseline != widget.getBaselineDistance();
    widget.setMeasureRequested(false);
  }

  @override
  void didMeasures() {}
}

void main() {
  group('measure ordering: a wrapped size depends on a resolved one', () {
    test('a match-constraint width resolves before the wrapped height is '
        'measured, in a container of unbounded height', () {
      // 340 - 20 - 20 = 300 wide: 300 of text is one 20 px line, not 300
      // lines measured at width 0.
      expectJava(
        'R 340 0;wraph;w a 0 0;ct a text 300 20 -1;add a;hb a M;vb a W;'
            'c a L root L 20;c a R root R 20;c a T root T 0;adeps',
        'root 340 x 20 | a: (20, 0) 300 x 20',
      );
    });

    test('a bottom barrier settles on the wrapped height of the tallest '
        'match-width child', () {
      // Each column is 330 wide less a 15 px inset on each side: `a` wraps
      // to two lines (40 px), `b` to one.
      expectJava(
        [
          'R 660 0',
          'wraph',
          'g guide',
          'go guide 1',
          'gp guide 0.5',
          'add guide',
          'w a 0 0',
          'ct a text 500 20 -1',
          'add a',
          'w b 0 0',
          'ct b text 100 20 -1',
          'add b',
          'hb a M',
          'vb a W',
          'c a T root T 0',
          'hb b M',
          'vb b W',
          'c b T root T 0',
          'c a L root L 15',
          'c a R guide L 15',
          'c b L guide R 15',
          'c b R root R 15',
          'b barrier',
          'bt barrier 3',
          'ref barrier a',
          'ref barrier b',
          'add barrier',
          'w follower 10 10',
          'ct follower box 10 10 -1',
          'add follower',
          'c follower L root L 0',
          'c follower T barrier T 0',
          'adeps',
        ].join(';'),
        'root 660 x 50 | guide: (330, 0) 0 x 0 | a: (15, 0) 300 x 40 | '
        'b: (345, 0) 300 x 20 | barrier: (0, 40) 0 x 0 | '
        'follower: (0, 40) 10 x 10',
      );
    });
  });

  group('measure ordering: a capped MATCH_CONSTRAINT_WRAP width is measured '
      'again at its capped size', () {
    test('a width capped by its anchors measures the wrapped height at the '
        'capped width', () {
      // 500 of text capped to 300: two 20 px lines.
      expectJava(
        'R 340 600;w a 0 0;ct a text 500 20 -1;add a;hb a M;hm a 1 0 0 1;'
            'vb a W;c a L root L 20;c a R root R 20;c a T root T 0;adeps',
        'root 340 x 600 | a: (20, 0) 300 x 40',
      );
    });

    test('a width capped by its max measures the height at the max, with '
        'one anchor or two', () {
      // Three 20 px lines at 200; centered between two anchors.
      expectJava(
        'R 340 600;w a 0 0;ct a text 500 20 -1;add a;hb a M;hm a 1 0 200 1;'
            'vb a W;c a L root L 20;c a T root T 0;adeps',
        'root 340 x 600 | a: (20, 0) 200 x 60',
      );
      expectJava(
        'R 340 600;w a 0 0;ct a text 500 20 -1;add a;hb a M;hm a 1 0 200 1;'
            'vb a W;c a L root L 20;c a R root R 20;c a T root T 0;adeps',
        'root 340 x 600 | a: (70, 0) 200 x 60',
      );
    });

    test('content that fits keeps the size it measured', () {
      // Not spread: centered at its own 120 in the 300 between the anchors.
      expectJava(
        'R 340 600;w a 0 0;ct a text 120 20 -1;add a;hb a M;hm a 1 100 0 1;'
            'vb a W;c a L root L 20;c a R root R 20;c a T root T 0;adeps',
        'root 340 x 600 | a: (110, 0) 120 x 20',
      );
    });

    test('a change of baseline alone solves again', () {
      // BasicMeasure.solverMeasure solves again when the measurer asks for
      // it or a baseline changed: the width is 300 x 60 before and after
      // its second measure, and only the baseline moves. Java's core with
      // the same measurer gives these frames at levels 257, 0, 64 and 321.
      for (final level in const [257, 0, 64, 321]) {
        final root = ConstraintWidgetContainer.rect(0, 0, 340, 600);
        root.setMeasurer(_BaselineMeasurer());
        final a = ConstraintWidget()..setDebugName('a');
        root.add(a);
        a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
        a.setHorizontalMatchStyle(
          ConstraintWidget.MATCH_CONSTRAINT_WRAP,
          0,
          0,
          1,
        );
        a.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
        a.setHasBaseline(true);
        a.setBaselineDistance(1);
        a.connect(.left, root, .left, 20);
        a.connect(.right, root, .right, 20);
        a.connect(.top, root, .top);
        final b = ConstraintWidget.size(50, 60)..setDebugName('b');
        b.setHasBaseline(true);
        b.setBaselineDistance(10);
        root.add(b);
        b.connect(.left, root, .left);
        b.connect(.baseline, a, .baseline);
        root.setOptimizationLevel(level);
        root.measure(
          level,
          BasicMeasure.EXACTLY,
          340,
          BasicMeasure.EXACTLY,
          600,
          0,
          0,
          0,
          0,
        );

        expect(
          [a.getX(), a.getY(), a.getWidth(), a.getHeight()],
          [20, 0, 300, 60],
          reason: 'level $level',
        );
        expect(a.getBaselineDistance(), 30, reason: 'level $level');
        expect([b.getX(), b.getY()], [0, 20], reason: 'level $level');
      }
    });
  });

  group('measure ordering: a one-link match-constraint width the solver '
      'resizes is measured again', () {
    test('a percent width measures the wrapped height again', () {
      // Half of 340: three 20 px lines.
      expectJava(
        'R 340 600;w a 0 0;ct a text 500 20 -1;add a;hb a M;hm a 2 0 0 0.5;'
            'vb a W;c a L root L 0;c a T root T 0;adeps',
        'root 340 x 600 | a: (0, 0) 170 x 60',
      );
    });

    test('a spread width capped by its max measures the wrapped height '
        'again', () {
      expectJava(
        'R 340 600;w a 0 0;ct a text 500 20 -1;add a;hb a M;hm a 0 0 200 1;'
            'vb a W;c a L root L 0;c a T root T 0;adeps',
        'root 340 x 600 | a: (0, 0) 200 x 60',
      );
    });
  });

  test('a one-link match-constraint height with a fixed width', () {
    // Android's view measurer keeps the 100 px width and wraps the height
    // around the content: five 20 px lines. At the dependency-graph levels
    // upstream's DependencyGraph.basicMeasureWidgets measures such a height
    // with the arguments of the width's case, measuring the width as wrap
    // content and the height as given, and Java gives 500 x 20 there.
    const ops =
        'R 800 600;w a 100 0;ct a text 500 20 -1;add a;hb a F;vb a M;'
        'c a L root L 10;c a T root T 5;adeps';
    expectJava(
      ops,
      'root 800 x 600 | a: (10, 5) 100 x 100',
      levels: const [257, 0],
    );
    expectJava(
      ops,
      'root 800 x 600 | a: (10, 5) 500 x 20',
      levels: const [64, 321, 192, 449],
    );
  });
}
