// Regression tests for a Flow whose size the solver resolves (a
// matchConstraint axis). Such a flow is first measured before the solver
// knows its size, so it has to be measured again at the solved size (as
// upstream's BasicMeasure.solverMeasure does) to arrange its rows against its
// own bounds rather than the whole container's. The layouts run through
// ConstraintWidgetContainer.measure at level 0, as upstream's FlowTest does;
// layout() measures nothing.
//
// Java J0 and J257 (VOpDriver v2, view path: the same scenes as op lists,
// box chips and a text) give the frames asserted here. The horizontal
// WRAP_CHAIN scene one pixel too narrow is `R 331 400;w c0 91 35;
// w c1 66 35;w c2 66 35;w c3 61 35;add c0;add c1;add c2;add c3;fl f;fo f 0;
// fwm f 1;fhg f 8;fvg f 8;fhs f 2;fvs f 2;fhb f 0;fvb f 0;fpad f 0 0 0 0;
// frtl f 0;ref f c0;ref f c1;ref f c2;ref f c3;hb f M;vb f W;
// c f L root L 12;c f R root R 12;c f T root T 12;add f;ct c0 box 91 35 -1;
// ...;cspec E 331 E 400`: c3: (12, 55) 61 x 35, f: (12, 12) 307 x 78,
// passes=2. The other scenes change the width, the wrap mode, the padding
// or the orientation; the shared-solve scene adds `ct t text 900 20 -1`.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

/// Measures the way Android's view-side measurer and the Flutter adapter do: a
/// virtual layout's matchConstraint axis is measured AT_MOST the container's
/// size until the solver has resolved it (SELF_DIMENSIONS), then EXACTLY the
/// resolved size (TRY_GIVEN_DIMENSIONS and USE_GIVEN_DIMENSIONS). Plain
/// widgets keep their own size.
class _HostMeasurer implements Measurer {
  _HostMeasurer({this.text = const {}});

  /// Content length of the text-like widgets, keyed by debug name: one unit
  /// per pixel along a 20 px line, wrapped at the measured width.
  final Map<String, int> text;

  @override
  void measure(ConstraintWidget widget, Measure measure) {
    if (widget is VirtualLayout) {
      final parent = widget.getParent()!;
      final given =
          measure.measureStrategy == Measure.TRY_GIVEN_DIMENSIONS ||
          measure.measureStrategy == Measure.USE_GIVEN_DIMENSIONS;
      bool exact(DimensionBehaviour? behaviour) =>
          behaviour == DimensionBehaviour.fixed ||
          (behaviour == DimensionBehaviour.matchConstraint && given);
      final exactWidth = exact(measure.horizontalBehavior);
      final exactHeight = exact(measure.verticalBehavior);
      widget.measure(
        exactWidth ? BasicMeasure.EXACTLY : BasicMeasure.AT_MOST,
        exactWidth ? measure.horizontalDimension : parent.getWidth(),
        exactHeight ? BasicMeasure.EXACTLY : BasicMeasure.AT_MOST,
        exactHeight ? measure.verticalDimension : parent.getHeight(),
      );
      measure.measuredWidth = widget.getMeasuredWidth();
      measure.measuredHeight = widget.getMeasuredHeight();
    } else if (text[widget.getDebugName()] case final length?) {
      final width = measure.horizontalBehavior == DimensionBehaviour.wrapContent
          ? length
          : measure.horizontalDimension;
      final lines =
          (length + (width <= 0 ? 1 : width) - 1) ~/ (width <= 0 ? 1 : width);
      measure.measuredWidth = width;
      measure.measuredHeight =
          measure.verticalBehavior == DimensionBehaviour.wrapContent
          ? lines * 20
          : measure.verticalDimension;
    } else {
      measure.measuredWidth = measure.horizontalDimension;
      measure.measuredHeight = measure.verticalDimension;
    }
    measure.measuredHasBaseline = false;
    measure.measuredBaseline = 0;
    widget.setMeasureRequested(false);
  }

  @override
  void didMeasures() {}
}

/// Main-axis sizes of the first four chips of the website's flow example
/// ('constraint', 'layout', 'wraps', 'when'). One line holding all four needs
/// 91 + 66 + 66 + 61 + 3 * 8 = 308.
const _chipSizes = [91, 66, 66, 61];
const _lineSize = 308;
const _chipCrossSize = 35;
const _margin = 12;
const _gap = 8;

/// A container whose main axis is [mainSize] long, holding the chips and a
/// flow that is matchConstraint along that axis between the container's
/// edges, inset by [_margin] from each, and packed against its start.
(ConstraintWidgetContainer, Flow, List<ConstraintWidget>) _scene(
  int mainSize, {
  int orientation = ConstraintWidget.HORIZONTAL,
  int wrapMode = Flow.WRAP_CHAIN,
  int padding = 0,
}) {
  final horizontal = orientation == ConstraintWidget.HORIZONTAL;
  final root = horizontal
      ? ConstraintWidgetContainer.rect(0, 0, mainSize, 400)
      : ConstraintWidgetContainer.rect(0, 0, 400, mainSize);
  root.setMeasurer(_HostMeasurer());
  final chips = [
    for (final size in _chipSizes)
      horizontal
          ? ConstraintWidget.size(size, _chipCrossSize)
          : ConstraintWidget.size(_chipCrossSize, size),
  ];
  root.addAll(chips);

  final flow = Flow();
  flow.setOrientation(orientation);
  flow.setWrapMode(wrapMode);
  flow.setHorizontalGap(_gap);
  flow.setVerticalGap(_gap);
  flow.setHorizontalStyle(ConstraintWidget.CHAIN_PACKED);
  flow.setVerticalStyle(ConstraintWidget.CHAIN_PACKED);
  flow.setHorizontalBias(0);
  flow.setVerticalBias(0);
  flow.setPadding(padding);
  // Resolves the start/end padding to left/right, as the host does (Android's
  // ConstraintHelper.resolveRtl).
  flow.applyRtl(false);
  for (final chip in chips) {
    flow.add(chip);
  }
  if (horizontal) {
    flow.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
    flow.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
    flow.connectAnchors(flow.mLeft, root.mLeft, _margin);
    flow.connectAnchors(flow.mRight, root.mRight, _margin);
    flow.connectAnchors(flow.mTop, root.mTop, _margin);
  } else {
    flow.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
    flow.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
    flow.connectAnchors(flow.mTop, root.mTop, _margin);
    flow.connectAnchors(flow.mBottom, root.mBottom, _margin);
    flow.connectAnchors(flow.mLeft, root.mLeft, _margin);
  }
  root.add(flow);
  return (root, flow, chips);
}

/// Measures and lays out [root] at level 0 (upstream's measure entry).
void _measure(ConstraintWidgetContainer root) {
  root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
  root.measure(
    Optimizer.OPTIMIZATION_NONE,
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

void main() {
  group('Flow wraps against its solved size', () {
    for (final (name, wrapMode) in [
      ('WRAP_CHAIN', Flow.WRAP_CHAIN),
      ('WRAP_ALIGNED', Flow.WRAP_ALIGNED),
    ]) {
      test('$name keeps a row that exactly fills the flow on one line', () {
        final (root, flow, chips) = _scene(
          _lineSize + 2 * _margin,
          wrapMode: wrapMode,
        );
        _measure(root);

        expect(flow.getWidth(), _lineSize);
        for (final chip in chips) {
          expect(chip.getTop(), _margin);
        }
        expect(chips.first.getLeft(), flow.getLeft());
        expect(chips.last.getRight(), flow.getRight());
      });

      test('$name wraps a row one pixel wider than the flow', () {
        final (root, flow, chips) = _scene(
          _lineSize + 2 * _margin - 1,
          wrapMode: wrapMode,
        );
        _measure(root);

        expect(flow.getWidth(), _lineSize - 1);
        expect(chips[2].getTop(), _margin);
        expect(chips.last.getTop(), chips.first.getBottom() + _gap);
        for (final chip in chips) {
          expect(chip.getLeft(), greaterThanOrEqualTo(flow.getLeft()));
          expect(chip.getRight(), lessThanOrEqualTo(flow.getRight()));
        }
      });
    }

    test('padding narrows the space a row wraps in', () {
      const padding = 10;
      final (fitRoot, _, fitChips) = _scene(
        _lineSize + 2 * (_margin + padding),
        padding: padding,
      );
      _measure(fitRoot);
      expect(fitChips.last.getTop(), fitChips.first.getTop());

      final (wrapRoot, wrapFlow, wrapChips) = _scene(
        _lineSize + 2 * (_margin + padding) - 1,
        padding: padding,
      );
      _measure(wrapRoot);
      expect(wrapChips.last.getTop(), wrapChips.first.getBottom() + _gap);
      expect(wrapChips.last.getLeft(), wrapFlow.getLeft() + padding);
    });

    test('a vertical flow wraps a column one pixel taller than the flow', () {
      final (fitRoot, fitFlow, fitChips) = _scene(
        _lineSize + 2 * _margin,
        orientation: ConstraintWidget.VERTICAL,
      );
      _measure(fitRoot);
      expect(fitFlow.getHeight(), _lineSize);
      for (final chip in fitChips) {
        expect(chip.getLeft(), _margin);
      }
      expect(fitChips.last.getBottom(), fitFlow.getBottom());

      final (wrapRoot, wrapFlow, wrapChips) = _scene(
        _lineSize + 2 * _margin - 1,
        orientation: ConstraintWidget.VERTICAL,
      );
      _measure(wrapRoot);
      expect(wrapFlow.getHeight(), _lineSize - 1);
      expect(wrapChips.last.getLeft(), wrapChips.first.getRight() + _gap);
      expect(wrapChips.last.getTop(), wrapFlow.getTop());
      for (final chip in wrapChips) {
        expect(chip.getBottom(), lessThanOrEqualTo(wrapFlow.getBottom()));
      }
    });

    test('the upstream measure() entry places every chip and the flow', () {
      // Java J0 and J257 (the scene one pixel too narrow in the header).
      final (measured, _, _) = _scene(_lineSize + 2 * _margin - 1);
      _measure(measured);

      expect(
        [
          for (final w in measured.getChildren())
            [w.getLeft(), w.getTop(), w.getWidth(), w.getHeight()],
        ],
        [
          [12, 12, 91, 35],
          [111, 12, 66, 35],
          [185, 12, 66, 35],
          [12, 55, 61, 35],
          [12, 12, 307, 78],
        ],
      );
    });

    test('a re-measured flow and a re-measured text share one solve, as in '
        'upstream solverMeasure', () {
      // The flow wraps its fifth chip once measured at its solved width, and
      // the text below it measured its height at width 0 before the first
      // solve, so both need a solver pass after it. Upstream's solverMeasure
      // applies both with one solve (its VirtualLayout step only sets
      // needSolverPass for the first pass of the re-measure loop), so it
      // solves twice in all; checked against upstream's Java engine, run with
      // the same measurer at OPTIMIZATION_NONE and OPTIMIZATION_STANDARD.
      final root = _CountingContainer(390, 800);
      root.setMeasurer(_HostMeasurer(text: {'t': 900}));
      final chips = [
        for (var i = 0; i < 5; i++) ConstraintWidget.size(70, 30),
      ];
      root.addAll(chips);
      final flow = Flow();
      flow.setOrientation(ConstraintWidget.HORIZONTAL);
      flow.setWrapMode(Flow.WRAP_CHAIN);
      flow.setHorizontalGap(10);
      flow.setVerticalGap(10);
      flow.applyRtl(false);
      for (final chip in chips) {
        flow.add(chip);
      }
      flow.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      flow.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      flow.connectAnchors(flow.mLeft, root.mLeft, 12);
      flow.connectAnchors(flow.mRight, root.mRight, 12);
      flow.connectAnchors(flow.mTop, root.mTop, 12);
      root.add(flow);
      final text = ConstraintWidget()..setDebugName('t');
      root.add(text);
      text.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      text.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      text.connect(
        ConstraintAnchorType.left,
        root,
        ConstraintAnchorType.left,
        16,
      );
      text.connect(
        ConstraintAnchorType.right,
        root,
        ConstraintAnchorType.right,
        16,
      );
      text.connect(
        ConstraintAnchorType.top,
        flow,
        ConstraintAnchorType.bottom,
        8,
      );

      _measure(root);

      expect(flow.getHeight(), 70, reason: 'two rows of 30 and a gap of 10');
      expect(chips.last.getTop(), chips.first.getBottom() + 10);
      expect(text.getTop(), flow.getBottom() + 8);
      expect(text.getWidth(), 358);
      expect(text.getHeight(), 60, reason: 'ceil(900/358)=3 lines at 20px');
      expect(root.solves, 2);
    });
  });
}

/// Counts solver passes: the solver loop adds the children to the solver
/// once per pass.
class _CountingContainer extends ConstraintWidgetContainer {
  _CountingContainer(int width, int height) : super.rect(0, 0, width, height);

  int solves = 0;

  @override
  bool addChildrenToSolver(LinearSystem system) {
    solves++;
    return super.addChildrenToSolver(system);
  }
}
