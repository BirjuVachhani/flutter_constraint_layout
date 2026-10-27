// ConstraintWidgetContainer.measureWidget, the port of upstream's static
// ConstraintWidgetContainer.measure(int, ConstraintWidget, Measurer, Measure,
// int) (ConstraintWidgetContainer.java 521-659): the measure upstream's
// Direct pass and the measures after it make. It converts the request before
// measuring: a dangling spread match-constraint axis, a resolved axis, and a
// ratio axis, whose size it truncates as Java's (int) cast of a float.
//
// Java values: view_host_test.dart's probes probe:C3 and probe:ratio, run
// on the pinned oracle (VOpDriver v2, view path, -Dtranscript) at
// OPTIMIZATION_STANDARD. C3 (`R 400 800;w D 0 0;add D;hb D M;vb D M;
// c D L root L 10;c D T root T 10;ct D box 300 50 -1;cspec E 400 E 800`)
// requests `P:D:0:FW:0,0:E0/A800:0,50,-1,01`, the ratio probe
// (`R 400 800;w Q 100 0;add Q;hb Q F;vb Q M;ra Q 1.7777778 -1;
// c Q L root L 0;c Q T root T 0;ct Q box 100 10 -1;cspec E 400 E 800`)
// `P:Q:0:FF:100,56:E100/E56`. `(int) (0.29f * 100)` is 29 in Java
// (jfloat_test.dart), where double arithmetic gives 28.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

/// One request a [_Recorder] received: what the measure asked for.
typedef _Request = ({
  DimensionBehaviour? horizontal,
  DimensionBehaviour? vertical,
  int width,
  int height,
  int strategy,
});

/// A measurer that records every request and answers as Android's view
/// measurer does for a box of [boxWidth] x [boxHeight] in a layout measured
/// EXACTLY [layoutWidth] x [layoutHeight] without padding (ConstraintLayout
/// 709-996, the fixed and wrap cases): a fixed axis is measured EXACTLY at
/// the requested size, a wrap axis AT_MOST the layout's size. The box takes
/// the exact size, or its own size capped by the at-most size, and reports
/// no baseline (-1). The layout is 400 x 800, as in those two probes.
class _Recorder implements Measurer {
  _Recorder(this.boxWidth, this.boxHeight);

  final int boxWidth;
  final int boxHeight;
  final int layoutWidth = 400;
  final int layoutHeight = 800;
  final List<_Request> requests = [];

  int _resolve(
    DimensionBehaviour? behaviour,
    int dimension,
    int natural,
    int available,
  ) {
    if (behaviour == DimensionBehaviour.wrapContent) {
      return natural < available ? natural : available;
    }
    return dimension;
  }

  @override
  void measure(ConstraintWidget widget, Measure measure) {
    requests.add((
      horizontal: measure.horizontalBehavior,
      vertical: measure.verticalBehavior,
      width: measure.horizontalDimension,
      height: measure.verticalDimension,
      strategy: measure.measureStrategy,
    ));
    final width = _resolve(
      measure.horizontalBehavior,
      measure.horizontalDimension,
      boxWidth,
      layoutWidth,
    );
    final height = _resolve(
      measure.verticalBehavior,
      measure.verticalDimension,
      boxHeight,
      layoutHeight,
    );
    measure.measuredWidth = width;
    measure.measuredHeight = height;
    measure.measuredBaseline = -1;
    measure.measuredHasBaseline = false;
    measure.measuredNeedsSolverPass =
        width != measure.horizontalDimension ||
        height != measure.verticalDimension;
  }

  @override
  void didMeasures() {}
}

_Request _request(
  DimensionBehaviour horizontal,
  DimensionBehaviour vertical,
  int width,
  int height, {
  int strategy = Measure.SELF_DIMENSIONS,
}) => (
  horizontal: horizontal,
  vertical: vertical,
  width: width,
  height: height,
  strategy: strategy,
);

const _fixed = DimensionBehaviour.fixed;
const _wrap = DimensionBehaviour.wrapContent;
const _match = DimensionBehaviour.matchConstraint;

/// [widget] added to a 400 x 800 container named root.
ConstraintWidgetContainer _rootWith(ConstraintWidget widget) {
  final root = ConstraintWidgetContainer.sizeNamed('root', 400, 800);
  root.add(widget);
  return root;
}

void main() {
  group('measureWidget', () {
    test('C3: match x match with one link per axis measures the width fixed '
        'at 0 and the height as wrap content: 0 x 50', () {
      final d = ConstraintWidget.named('D');
      final root = _rootWith(d);
      d.setHorizontalDimensionBehaviour(_match);
      d.setVerticalDimensionBehaviour(_match);
      d.connect(.left, root, .left, 10);
      d.connect(.top, root, .top, 10);
      final recorder = _Recorder(300, 50);
      final m = Measure();

      final needsSolverPass = ConstraintWidgetContainer.measureWidget(
        0,
        d,
        recorder,
        m,
        Measure.SELF_DIMENSIONS,
      );

      // Java J257 (VOpDriver -Dtranscript, the C3 probe):
      // P:D:0:FW:0,0:E0/A800:0,50,-1,01.
      expect(recorder.requests, [_request(_fixed, _wrap, 0, 0)]);
      expect([d.getWidth(), d.getHeight()], [0, 50]);
      expect(needsSolverPass, isTrue);
      expect(m.measureStrategy, Measure.SELF_DIMENSIONS);
      // The widget keeps its behaviours: only the request is converted.
      expect(d.getHorizontalDimensionBehaviour(), _match);
      expect(d.getVerticalDimensionBehaviour(), _match);
    });

    test('a dangling spread height against a fixed width is measured as wrap '
        'content', () {
      final w = ConstraintWidget.sizeNamed('w', 120, 0);
      final root = _rootWith(w);
      w.setVerticalDimensionBehaviour(_match);
      w.connect(.left, root, .left);
      w.connect(.top, root, .top);
      final recorder = _Recorder(300, 50);

      ConstraintWidgetContainer.measureWidget(
        0,
        w,
        recorder,
        Measure(),
        Measure.SELF_DIMENSIONS,
      );

      expect(recorder.requests, [_request(_fixed, _wrap, 120, 0)]);
      expect([w.getWidth(), w.getHeight()], [120, 50]);
    });

    test('a spread width with two links is left match constraint', () {
      final w = ConstraintWidget.sizeNamed('w', 0, 30);
      final root = _rootWith(w);
      w.setHorizontalDimensionBehaviour(_match);
      w.connect(.left, root, .left);
      w.connect(.right, root, .right);
      w.connect(.top, root, .top);
      final recorder = _Recorder(300, 50);

      ConstraintWidgetContainer.measureWidget(
        0,
        w,
        recorder,
        Measure(),
        Measure.SELF_DIMENSIONS,
      );

      expect(recorder.requests, [_request(_match, _fixed, 0, 30)]);
    });

    test('a resolved axis is measured fixed at the widget size', () {
      final w = ConstraintWidget.sizeNamed('w', 0, 0);
      final root = _rootWith(w);
      w.setHorizontalDimensionBehaviour(_match);
      w.setVerticalDimensionBehaviour(_wrap);
      w.connect(.left, root, .left, 10);
      w.connect(.right, root, .right, 10);
      w.connect(.top, root, .top);
      w.setFinalHorizontal(10, 390);
      final recorder = _Recorder(300, 50);

      ConstraintWidgetContainer.measureWidget(
        0,
        w,
        recorder,
        Measure(),
        Measure.SELF_DIMENSIONS,
      );

      expect(recorder.requests, [_request(_fixed, _wrap, 380, 0)]);
      expect([w.getWidth(), w.getHeight()], [380, 50]);
    });

    test('ratio probe: a ratio height under a fixed width of 100 is '
        '(int) (100 / 1.7777778f) = 56', () {
      final q = ConstraintWidget.sizeNamed('Q', 100, 0);
      final root = _rootWith(q);
      q.setVerticalDimensionBehaviour(_match);
      q.setDimensionRatio(1.7777778, ConstraintWidget.UNKNOWN);
      q.connect(.left, root, .left);
      q.connect(.top, root, .top);
      final recorder = _Recorder(100, 10);

      ConstraintWidgetContainer.measureWidget(
        0,
        q,
        recorder,
        Measure(),
        Measure.SELF_DIMENSIONS,
      );

      // Java J257 (the ratio probe): P:Q:0:FF:100,56:E100/E56.
      expect(recorder.requests, [_request(_fixed, _fixed, 100, 56)]);
      expect([q.getWidth(), q.getHeight()], [100, 56]);
    });

    test('a ratio width truncates the float product: (int) (0.29f * 100) is '
        '29, not the 28 of double arithmetic', () {
      final w = ConstraintWidget.sizeNamed('w', 0, 100);
      final root = _rootWith(w);
      w.setHorizontalDimensionBehaviour(_match);
      w.setDimensionRatio(0.29, ConstraintWidget.UNKNOWN);
      w.connect(.left, root, .left);
      w.connect(.top, root, .top);
      final recorder = _Recorder(300, 50);

      ConstraintWidgetContainer.measureWidget(
        0,
        w,
        recorder,
        Measure(),
        Measure.SELF_DIMENSIONS,
      );

      expect(0.29 * 100 ~/ 1, 28, reason: 'what double arithmetic gives');
      expect(recorder.requests, [_request(_fixed, _fixed, 29, 100)]);
      expect(w.getWidth(), 29);
    });

    test('a ratio height with a side multiplies: (int) (0.29f * 100) = 29', () {
      final w = ConstraintWidget.sizeNamed('w', 100, 0);
      final root = _rootWith(w);
      w.setVerticalDimensionBehaviour(_match);
      w.setDimensionRatio(0.29, ConstraintWidget.VERTICAL);
      w.connect(.left, root, .left);
      w.connect(.top, root, .top);
      final recorder = _Recorder(300, 50);

      ConstraintWidgetContainer.measureWidget(
        0,
        w,
        recorder,
        Measure(),
        Measure.SELF_DIMENSIONS,
      );

      expect(recorder.requests, [_request(_fixed, _fixed, 100, 29)]);
    });

    test('a ratio width against a wrap height measures the height first, '
        'then the width fixed at the ratio of it', () {
      final w = ConstraintWidget.named('w');
      final root = _rootWith(w);
      w.setHorizontalDimensionBehaviour(_match);
      w.setVerticalDimensionBehaviour(_wrap);
      w.setDimensionRatio(2, ConstraintWidget.UNKNOWN);
      w.connect(.left, root, .left);
      w.connect(.top, root, .top);
      final recorder = _Recorder(300, 50);

      ConstraintWidgetContainer.measureWidget(
        0,
        w,
        recorder,
        Measure(),
        Measure.SELF_DIMENSIONS,
      );

      expect(recorder.requests, [
        _request(_wrap, _wrap, 0, 0),
        _request(_fixed, _wrap, 100, 0),
      ]);
      expect([w.getWidth(), w.getHeight()], [100, 50]);
    });

    test('a ratio axis the solver resolved is measured fixed', () {
      final w = ConstraintWidget.sizeNamed('w', 80, 40);
      final root = _rootWith(w);
      w.setHorizontalDimensionBehaviour(_match);
      w.setVerticalDimensionBehaviour(_match);
      w.setDimensionRatio(2, ConstraintWidget.UNKNOWN);
      w.connect(.left, root, .left);
      w.connect(.right, root, .right);
      w.connect(.top, root, .top);
      w.connect(.bottom, root, .bottom);
      w.mResolvedMatchConstraintDefault[ConstraintWidget.HORIZONTAL] =
          ConstraintWidget.MATCH_CONSTRAINT_RATIO_RESOLVED;
      final recorder = _Recorder(300, 50);

      ConstraintWidgetContainer.measureWidget(
        0,
        w,
        recorder,
        Measure(),
        Measure.TRY_GIVEN_DIMENSIONS,
      );

      expect(recorder.requests, [
        _request(
          _fixed,
          _match,
          80,
          40,
          strategy: Measure.TRY_GIVEN_DIMENSIONS,
        ),
      ]);
    });

    test('a gone widget, a guideline and a barrier are reported 0 x 0 and '
        'left alone', () {
      final gone = ConstraintWidget.sizeNamed('gone', 50, 60)
        ..setVisibility(ConstraintWidget.GONE);
      final guideline = Guideline()..setOrientation(Guideline.vertical);
      final barrier = Barrier();
      final root = ConstraintWidgetContainer.sizeNamed('root', 400, 800);
      root.addAll([gone, guideline, barrier]);
      final recorder = _Recorder(300, 50);
      for (final widget in [gone, guideline, barrier]) {
        final m = Measure()
          ..measuredWidth = 7
          ..measuredHeight = 8
          ..measuredBaseline = 9
          ..measuredHasBaseline = true
          ..measuredNeedsSolverPass = true
          ..horizontalDimension = 11
          ..measureStrategy = Measure.USE_GIVEN_DIMENSIONS;
        final width = widget.mWidth;
        final height = widget.mHeight;

        expect(
          ConstraintWidgetContainer.measureWidget(
            0,
            widget,
            recorder,
            m,
            Measure.SELF_DIMENSIONS,
          ),
          isFalse,
        );

        expect([m.measuredWidth, m.measuredHeight], [0, 0]);
        // Upstream writes nothing else.
        expect(m.measuredBaseline, 9);
        expect(m.measuredHasBaseline, isTrue);
        expect(m.measuredNeedsSolverPass, isTrue);
        expect(m.horizontalDimension, 11);
        expect(m.measureStrategy, Measure.USE_GIVEN_DIMENSIONS);
        expect([widget.mWidth, widget.mHeight], [width, height]);
      }
      expect(recorder.requests, isEmpty);
    });

    test('without a measurer it measures nothing and returns false', () {
      final w = ConstraintWidget.sizeNamed('w', 50, 60);
      _rootWith(w);
      final m = Measure()..measuredWidth = 7;

      expect(
        ConstraintWidgetContainer.measureWidget(
          0,
          w,
          null,
          m,
          Measure.SELF_DIMENSIONS,
        ),
        isFalse,
      );
      expect(m.measuredWidth, 7);
      expect(m.horizontalBehavior, isNull);
      expect([w.getWidth(), w.getHeight()], [50, 60]);
    });

    test('copies the baseline the measurer reports onto the widget', () {
      final w = ConstraintWidget.sizeNamed('w', 50, 60);
      _rootWith(w);
      final measurer = _BaselineMeasurer(17);

      ConstraintWidgetContainer.measureWidget(
        0,
        w,
        measurer,
        Measure(),
        Measure.SELF_DIMENSIONS,
      );

      expect(w.getBaselineDistance(), 17);
      expect(w.hasBaseline(), isTrue);
    });
  });
}

/// Echoes the requested size and reports [baseline].
class _BaselineMeasurer implements Measurer {
  _BaselineMeasurer(this.baseline);

  final int baseline;

  @override
  void measure(ConstraintWidget widget, Measure measure) {
    measure.measuredWidth = measure.horizontalDimension;
    measure.measuredHeight = measure.verticalDimension;
    measure.measuredBaseline = baseline;
    measure.measuredHasBaseline = true;
  }

  @override
  void didMeasures() {}
}
