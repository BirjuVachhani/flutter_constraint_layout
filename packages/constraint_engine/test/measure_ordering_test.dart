import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

/// A measurer that models content whose height depends on its width, the way
/// wrapping text does: a widget carries a content "length", and at a given
/// width it wraps to `ceil(length / width)` lines of [lineHeight] each. At
/// width 0 every unit lands on its own line, so a mis-order that measures a
/// wrapContent height before its matchConstraint width is resolved produces a
/// wildly tall result, exactly like real text wrapping at width 0.
class _TextLikeMeasurer implements Measurer {
  _TextLikeMeasurer(this.length);

  /// Content length per widget, keyed by debug name.
  final Map<String, int> length;

  /// Height contributed per wrapped line. Fixed: no test varies it, so it is a
  /// plain field rather than a constructor parameter (which would never be
  /// supplied and trips the `unused_element_parameter` lint).
  final int lineHeight = 20;

  @override
  void measure(ConstraintWidget widget, Measure measure) {
    final len = length[widget.getDebugName()] ?? 0;

    final int width;
    if (measure.horizontalBehavior == DimensionBehaviour.wrapContent) {
      width = len; // natural single-line width
    } else {
      width = measure.horizontalDimension; // fixed or solver-resolved
    }

    final int height;
    if (measure.verticalBehavior == DimensionBehaviour.wrapContent) {
      final w = width <= 0 ? 1 : width; // width 0 => one unit per line
      final lines = (len + w - 1) ~/ w; // ceil(len / w)
      height = (lines <= 0 ? 1 : lines) * lineHeight;
    } else {
      height = measure.verticalDimension;
    }

    measure.measuredWidth = width;
    measure.measuredHeight = height;
    measure.measuredHasBaseline = false;
    measure.measuredBaseline = 0;
    widget.setMeasureRequested(false);
  }

  @override
  void didMeasures() {}
}

/// [_TextLikeMeasurer]'s content on widgets sized MATCH_CONSTRAINT_WRAP along
/// their lines, measured the way a host measurer must measure that style:
/// around the content when measured on its own (SELF_DIMENSIONS), and at the
/// size the solver gave it when re-measured after a solve (TRY_GIVEN_DIMENSIONS
/// and USE_GIVEN_DIMENSIONS), as Android's view measurer does once the other
/// axis is stable. The lines run along the width, or along the height when
/// [vertical] is set (text turned a quarter turn).
class _WrapStyleMeasurer implements Measurer {
  _WrapStyleMeasurer(this.length, {this.vertical = false});

  /// Content length per widget, keyed by debug name.
  final Map<String, int> length;

  /// Whether the lines run along the height instead of the width.
  final bool vertical;

  /// Extent of one line across the line axis.
  final int lineHeight = 20;

  @override
  void measure(ConstraintWidget widget, Measure measure) {
    final len = length[widget.getDebugName()] ?? 0;
    final lineBehavior = vertical
        ? measure.verticalBehavior
        : measure.horizontalBehavior;
    final lineDefault = vertical
        ? widget.mMatchConstraintDefaultHeight
        : widget.mMatchConstraintDefaultWidth;
    final aroundContent =
        lineBehavior == DimensionBehaviour.wrapContent ||
        (lineBehavior == DimensionBehaviour.matchConstraint &&
            lineDefault == ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
            measure.measureStrategy == Measure.SELF_DIMENSIONS);
    final line = aroundContent
        ? len // natural single-line extent
        : (vertical ? measure.verticalDimension : measure.horizontalDimension);

    final int across;
    if ((vertical ? measure.horizontalBehavior : measure.verticalBehavior) ==
        DimensionBehaviour.wrapContent) {
      final l = line <= 0 ? 1 : line;
      final lines = (len + l - 1) ~/ l; // ceil(len / line)
      across = (lines <= 0 ? 1 : lines) * lineHeight;
    } else {
      across = vertical ? measure.horizontalDimension : measure.verticalDimension;
    }

    measure.measuredWidth = vertical ? across : line;
    measure.measuredHeight = vertical ? line : across;
    measure.measuredHasBaseline = false;
    measure.measuredBaseline = 0;
    widget.setMeasureRequested(false);
  }

  @override
  void didMeasures() {}
}

/// A box whose baseline moves with its width while its height stays at 60.
/// The main widget is initially 500 wide, then capped to 300 by the solver.
class _BaselineMeasurer implements Measurer {
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    final a = widget.getDebugName() == 'a';
    final width = a &&
            (measure.horizontalBehavior == DimensionBehaviour.wrapContent ||
                (measure.horizontalBehavior == DimensionBehaviour.matchConstraint &&
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
    measure.measuredNeedsSolverPass = width != measure.horizontalDimension ||
        height != measure.verticalDimension ||
        baseline != widget.getBaselineDistance();
    widget.setMeasureRequested(false);
  }

  @override
  void didMeasures() {}
}

void main() {
  group('measure ordering: wrap size depends on resolved match size', () {
    test('matchConstraint width resolves before the wrapContent height is '
        'measured, under a wrapContent (unbounded) container height', () {
      // Container 340 wide, its own height wrapping to content (the case that
      // pushed the layout onto the solver-fallback path where the bug lived).
      final root = ConstraintWidgetContainer.rect(0, 0, 340, 0);
      root.setDebugName('root');
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setMeasurer(_TextLikeMeasurer({'a': 300}));

      final a = ConstraintWidget();
      a.setDebugName('a');
      root.add(a);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 20);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 20);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      root.layout();

      // Width resolves to 340 - 20 - 20 = 300; at width 300 the length-300
      // content is a single 20px line, NOT 300 lines measured at width 0.
      expect(a.getWidth(), 300);
      expect(a.getHeight(), 20);
      expect(root.getHeight(), 20);
    });

    test('a bottom barrier settles on the true wrapped height of the tallest '
        'match-width child', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 660, 0);
      root.setDebugName('root');
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      // 'a' wraps to 2 lines (40px) at its resolved width, 'b' to 1 (20px).
      root.setMeasurer(_TextLikeMeasurer({'a': 500, 'b': 100}));

      final guide = Guideline();
      guide.setDebugName('guide');
      guide.setOrientation(Guideline.vertical);
      guide.setGuidePercent(0.5);
      root.add(guide);

      final a = ConstraintWidget()..setDebugName('a');
      final b = ConstraintWidget()..setDebugName('b');
      root.add(a);
      root.add(b);
      for (final w in [a, b]) {
        w.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
        w.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
        w.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      }
      // Each column is 330 wide, less a 15px inset on each side -> width 300.
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 15);
      a.connect(ConstraintAnchorType.right, guide, ConstraintAnchorType.left, 15);
      b.connect(ConstraintAnchorType.left, guide, ConstraintAnchorType.right, 15);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 15);

      final barrier = Barrier();
      barrier.setDebugName('barrier');
      barrier.setBarrierType(Barrier.bottom);
      barrier.add(a);
      barrier.add(b);
      root.add(barrier);

      final follower = ConstraintWidget.size(10, 10)..setDebugName('follower');
      root.add(follower);
      follower.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      follower.connect(
          ConstraintAnchorType.top, barrier, ConstraintAnchorType.top);

      root.layout();

      expect(a.getWidth(), 300);
      expect(a.getHeight(), 40, reason: 'ceil(500/300)=2 lines at 20px');
      expect(b.getHeight(), 20);
      // Barrier and the follower below it sit at the tall column's height.
      expect(follower.getTop(), 40);
    });
  });

  group('measure ordering: a capped MATCH_CONSTRAINT_WRAP axis is measured '
      'again at its capped size', () {
    // A MATCH_CONSTRAINT_WRAP axis is measured around its content, and only
    // the solver caps it. Content whose other axis depends on it must then be
    // measured again at the capped size, or it keeps the size it measured at
    // its natural (uncapped) extent.
    ConstraintWidget wrapStyled(
      ConstraintWidgetContainer root, {
      int min = 0,
      int max = 0,
      bool vertical = false,
    }) {
      final a = ConstraintWidget()..setDebugName('a');
      root.add(a);
      if (vertical) {
        a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
        a.setVerticalMatchStyle(
            ConstraintWidget.MATCH_CONSTRAINT_WRAP, min, max, 1);
        a.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      } else {
        a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
        a.setHorizontalMatchStyle(
            ConstraintWidget.MATCH_CONSTRAINT_WRAP, min, max, 1);
        a.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      }
      return a;
    }

    test('a width capped by its anchors re-measures the wrapContent height '
        'at the capped width', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 340, 600);
      root.setMeasurer(_WrapStyleMeasurer({'a': 500}));
      final a = wrapStyled(root);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 20);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 20);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      root.layout();

      // 500 of content capped to 340 - 20 - 20 = 300: two 20px lines, not the
      // single line it measured at its natural width.
      expect(a.getLeft(), 20);
      expect(a.getWidth(), 300);
      expect(a.getHeight(), 40, reason: 'ceil(500/300)=2 lines at 20px');
    });

    test('a width capped by its max re-measures the height at the max, with '
        'one anchor or two', () {
      for (final anchors in [1, 2]) {
        final root = ConstraintWidgetContainer.rect(0, 0, 340, 600);
        root.setMeasurer(_WrapStyleMeasurer({'a': 500}));
        final a = wrapStyled(root, max: 200);
        a.connect(
            ConstraintAnchorType.left, root, ConstraintAnchorType.left, 20);
        if (anchors == 2) {
          a.connect(
              ConstraintAnchorType.right, root, ConstraintAnchorType.right, 20);
        }
        a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

        root.layout();

        expect(a.getWidth(), 200, reason: '$anchors anchor(s)');
        expect(a.getHeight(), 60,
            reason: '$anchors anchor(s): ceil(500/200)=3 lines at 20px');
      }
    });

    test('content that fits keeps the size it measured', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 340, 600);
      root.setMeasurer(_WrapStyleMeasurer({'a': 120}));
      final a = wrapStyled(root, min: 100);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 20);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 20);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      root.layout();

      // Not spread: centered at its own 120 in the 300 between the anchors.
      expect(a.getLeft(), 110);
      expect(a.getWidth(), 120);
      expect(a.getHeight(), 20);
    });

    test('a height capped by its anchors re-measures the wrapContent width '
        'at the capped height', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 340);
      root.setMeasurer(_WrapStyleMeasurer({'a': 500}, vertical: true));
      final a = wrapStyled(root, vertical: true);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 20);
      a.connect(
          ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 20);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);

      root.layout();

      expect(a.getTop(), 20);
      expect(a.getHeight(), 300);
      expect(a.getWidth(), 40, reason: 'ceil(500/300)=2 lines at 20px');
    });

    test('a baseline-only change after capping a width re-solves the '
        'baseline link', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 340, 600);
      root.setMeasurer(_BaselineMeasurer());
      final a = wrapStyled(root);
      a.setHasBaseline(true);
      a.setBaselineDistance(1);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 20);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 20);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      final b = ConstraintWidget.size(50, 60)..setDebugName('b');
      b.setHasBaseline(true);
      b.setBaselineDistance(10);
      root.add(b);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.baseline, a, ConstraintAnchorType.baseline);

      root.layout();

      // Upstream BasicMeasure.solverMeasure checks both the measurer's
      // request for another pass and a changed baseline. The absolute
      // baselines must still align even though the size did not change on
      // re-measure (300 x 60 before and after); checked against Java core at
      // OPTIMIZATION_NONE and OPTIMIZATION_STANDARD.
      expect(a.getWidth(), 300);
      expect(a.getHeight(), 60);
      expect(a.getBaselineDistance(), 30);
      expect(b.getTop(), 20);
      expect(b.getTop() + b.getBaselineDistance(),
          a.getTop() + a.getBaselineDistance());
    });
  });

  group('measure ordering: a one-link matchConstraint axis the solver '
      'resizes is measured again', () {
    // With fewer than two links, the solver still sizes a matchConstraint
    // axis: as a percent of the parent in the percent style, and as its
    // measured size capped by its min/max in the spread style
    // (applyConstraints, numConnections != 2). Upstream's solverMeasure then
    // measures every matchConstraint widget again, so content whose other
    // axis depends on it is measured at the solved size. The expected values
    // match upstream's Java engine run with an equivalent measurer.
    ConstraintWidget oneLinkWidth(
      ConstraintWidgetContainer root,
      int style, {
      int max = 0,
      double percent = 1,
    }) {
      final a = ConstraintWidget()..setDebugName('a');
      root.add(a);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalMatchStyle(style, 0, max, percent);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      // An unrelated circular constraint routes the layout through the
      // solver fallback.
      final g = ConstraintWidget.size(10, 10)..setDebugName('g');
      root.add(g);
      g.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      g.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      final h = ConstraintWidget.size(10, 10)..setDebugName('h');
      root.add(h);
      h.connectCircularConstraint(g, 90, 20);
      return a;
    }

    test('a percent width re-measures the wrapContent height', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 340, 600);
      root.setMeasurer(_TextLikeMeasurer({'a': 500}));
      final a = oneLinkWidth(
        root,
        ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
        percent: 0.5,
      );

      root.layout();

      expect(a.getWidth(), 170);
      expect(a.getHeight(), 60, reason: 'ceil(500/170)=3 lines at 20px');
    });

    test('a spread width capped by its max re-measures the wrapContent '
        'height', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 340, 600);
      root.setMeasurer(_TextLikeMeasurer({'a': 500}));
      final a = oneLinkWidth(
        root,
        ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
        max: 200,
      );

      root.layout();

      expect(a.getWidth(), 200);
      expect(a.getHeight(), 60, reason: 'ceil(500/200)=3 lines at 20px');
    });
  });

  group('measure ordering: a one-link matchConstraint height is measured '
      'around its content on the graph', () {
    // Upstream's DependencyGraph measures a spread height that has a single
    // link with the arguments of the width case (see UPSTREAM.md): the width
    // as wrap content, which replaces a fixed width with the content's, and
    // the height at its stored size. The expected values are Android's:
    // upstream's Java engine at OPTIMIZATION_STANDARD, its solver path, with
    // a port of the view layer's measurer and the same content gives
    // x=10 y=5 w=100 h=100, while its own graph path gives w=500 h=20.
    for (final solver in [false, true]) {
      test('a fixed width is kept and the height wraps the content '
          '(${solver ? 'solver' : 'graph'})', () {
        final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
        root.setMeasurer(_TextLikeMeasurer({'a': 500}));
        final a = ConstraintWidget()..setDebugName('a');
        root.add(a);
        a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
        a.setWidth(100);
        a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
        a.connect(
          ConstraintAnchorType.left,
          root,
          ConstraintAnchorType.left,
          10,
        );
        a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 5);
        if (solver) {
          // An unrelated circular constraint routes the layout through
          // the solver fallback. (A barrier no longer does: the graph
          // resolves barriers that sit on their widgets' outermost edge.)
          final g = ConstraintWidget.size(10, 10)..setDebugName('g');
          root.add(g);
          g.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
          g.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
          final h = ConstraintWidget.size(10, 10)..setDebugName('h');
          root.add(h);
          h.connectCircularConstraint(g, 90, 20);
        }

        root.layout();

        // The solver creates variables; a graph-resolved layout never reaches
        // it. (Its row count is no probe: a pass whose equations all resolve
        // directly ends with no rows.)
        expect(root.mSystem.getNumVariables() > 0, solver);
        expect(
          [a.getX(), a.getY(), a.getWidth(), a.getHeight()],
          [10, 5, 100, 100],
          reason: 'ceil(500/100)=5 lines at 20px',
        );
      });
    }
  });
}
