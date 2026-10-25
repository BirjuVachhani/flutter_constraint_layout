// Regression tests for re-layout of a persistent container: the caching mode
// used by the Flutter adapter, which keeps the widget model alive across
// layout passes instead of rebuilding it. Every scenario compares the
// persistent container's geometry against a freshly built container with the
// same configuration, which is the correctness oracle.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

/// Geometry of every child plus the container itself, for exact comparison.
List<List<int>> geometryOf(ConstraintWidgetContainer root) => [
      [root.getWidth(), root.getHeight()],
      for (final w in root.getChildren())
        [w.getLeft(), w.getTop(), w.getWidth(), w.getHeight()],
    ];

/// A representative screen: pinned corner widget, centered widget with bias,
/// a matchConstraint fill, and a widget stacked below the pinned one.
ConstraintWidgetContainer buildScreen(int width, int height,
    {int margin = 10, double bias = 0.5, bool goneFill = false}) {
  final root = ConstraintWidgetContainer.rect(0, 0, width, height);

  final pinned = ConstraintWidget.size(100, 40);
  root.add(pinned);
  pinned.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, margin);
  pinned.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, margin);

  final centered = ConstraintWidget.size(80, 30);
  root.add(centered);
  centered.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
  centered.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
  centered.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
  centered.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
  centered.setHorizontalBiasPercent(bias);

  final fill = ConstraintWidget.size(0, 24);
  root.add(fill);
  fill.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
  fill.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 16);
  fill.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 16);
  fill.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 8);
  if (goneFill) {
    fill.setVisibility(ConstraintWidget.GONE);
  }

  final below = ConstraintWidget.size(60, 60);
  root.add(below);
  below.connect(ConstraintAnchorType.left, pinned, ConstraintAnchorType.left);
  below.connect(ConstraintAnchorType.top, pinned, ConstraintAnchorType.bottom, 12);

  return root;
}

/// A horizontal spread chain of three widgets stacked over a percent
/// guideline-anchored widget.
ConstraintWidgetContainer buildChainAndGuideline(int width, int height) {
  final root = ConstraintWidgetContainer.rect(0, 0, width, height);

  final a = ConstraintWidget.size(60, 20);
  final b = ConstraintWidget.size(60, 20);
  final c = ConstraintWidget.size(60, 20);
  root.add(a);
  root.add(b);
  root.add(c);
  a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 4);
  a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
  b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
  b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
  c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
  c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 4);
  for (final w in [a, b, c]) {
    w.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 10);
  }

  final guideline = Guideline();
  guideline.setOrientation(Guideline.horizontal);
  guideline.setGuidePercent(0.75);
  root.add(guideline);

  final anchored = ConstraintWidget.size(120, 30);
  root.add(anchored);
  anchored.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 20);
  anchored.connect(ConstraintAnchorType.top, guideline, ConstraintAnchorType.top);

  return root;
}

void main() {
  group('persistent container re-layout', () {
    test('repeated layout() is stable', () {
      final root = buildScreen(800, 600);
      root.layout();
      final first = geometryOf(root);
      root.layout();
      root.layout();
      expect(geometryOf(root), first);
    });

    test('re-layout after resize matches a fresh container', () {
      final root = buildScreen(800, 600);
      root.layout();
      for (final (w, h) in [(1000, 700), (640, 480), (800, 600)]) {
        root.setWidth(w);
        root.setHeight(h);
        root.layout();
        final fresh = buildScreen(w, h)..layout();
        expect(geometryOf(root), geometryOf(fresh),
            reason: 'resize to ${w}x$h diverged from fresh layout');
      }
    });

    test('chain and guideline re-layout after resize matches fresh', () {
      final root = buildChainAndGuideline(800, 600);
      root.layout();
      for (final (w, h) in [(500, 400), (1024, 768), (800, 600)]) {
        root.setWidth(w);
        root.setHeight(h);
        root.layout();
        final fresh = buildChainAndGuideline(w, h)..layout();
        expect(geometryOf(root), geometryOf(fresh),
            reason: 'resize to ${w}x$h diverged from fresh layout');
      }
    });

    test('measures-only invalidation still resolves after resize', () {
      // Regression for the reset-implies-rebuild fix: run resets destroy the
      // graph's edges, so a measures-only invalidation must trigger a graph
      // rebuild or geometry silently stays stale.
      final root = buildChainAndGuideline(800, 600);
      root.layout();
      root.setWidth(500);
      root.setHeight(400);
      root.invalidateMeasures();
      root.directMeasure(false);
      root.updateFromRuns(true, true);
      final fresh = buildChainAndGuideline(500, 400)..layout();
      expect(geometryOf(root), geometryOf(fresh));
    });

    test('margin mutation on a persistent model matches fresh', () {
      final root = buildScreen(800, 600);
      root.layout();
      final pinned = root.getChildren()[0];
      pinned.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 42);
      pinned.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 42);
      root.layout();
      final fresh = buildScreen(800, 600, margin: 42)..layout();
      expect(geometryOf(root), geometryOf(fresh));
    });

    test('bias mutation on a persistent model matches fresh', () {
      final root = buildScreen(800, 600);
      root.layout();
      root.getChildren()[1].setHorizontalBiasPercent(0.25);
      root.layout();
      final fresh = buildScreen(800, 600, bias: 0.25)..layout();
      expect(geometryOf(root), geometryOf(fresh));
    });

    test('visibility toggle on a persistent model matches fresh', () {
      final root = buildScreen(800, 600);
      root.layout();
      final fill = root.getChildren()[2];
      fill.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(geometryOf(root),
          geometryOf(buildScreen(800, 600, goneFill: true)..layout()));
      // Caller contract (upstream parity): updateFromRuns zeroes a GONE
      // widget's stored dimensions, so making it visible again requires
      // re-applying its configured size, exactly as Android re-applies
      // LayoutParams after a visibility change.
      fill.setVisibility(ConstraintWidget.VISIBLE);
      fill.setHeight(24);
      root.layout();
      expect(geometryOf(root), geometryOf(buildScreen(800, 600)..layout()));
    });

    test('gone toggle on a matchParent widget matches fresh', () {
      // Regression: runs persist across passes and basicMeasure skips the
      // run-behaviour assignment for GONE widgets, so a matchParent behaviour
      // from an earlier visible pass leaked into apply() and pinned the gone
      // widget to the parent edges instead of centering it.
      ConstraintWidgetContainer build({required bool gone}) {
        final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
        final a = ConstraintWidget.size(80, 0);
        root.add(a);
        a.setVerticalDimensionBehaviour(DimensionBehaviour.matchParent);
        a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
        a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
        a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
        a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
        if (gone) {
          a.setVisibility(ConstraintWidget.GONE);
        }
        return root;
      }

      final root = build(gone: false);
      root.layout();
      final a = root.getChildren()[0];
      a.setVisibility(ConstraintWidget.GONE);
      a.setHeight(0);
      root.layout();
      expect(geometryOf(root), geometryOf(build(gone: true)..layout()));
    });

    test('a centered widget that loses a link lays out again', () {
      // A match-constraint width is measured after the graph is built, so
      // the vertical run is set up as centered; then the bottom link goes.
      ConstraintWidgetContainer build({required bool centered}) {
        final root = ConstraintWidgetContainer.rect(0, 0, 400, 300);
        final t = ConstraintWidget.size(100, 20);
        root.add(t);
        t.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
        t.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
        t.connect(
          ConstraintAnchorType.left,
          root,
          ConstraintAnchorType.left,
          10,
        );
        t.connect(
          ConstraintAnchorType.right,
          root,
          ConstraintAnchorType.right,
          10,
        );
        t.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
        if (centered) {
          t.connect(
            ConstraintAnchorType.bottom,
            root,
            ConstraintAnchorType.bottom,
          );
        }
        return root;
      }

      final root = build(centered: true);
      root.layout();
      expect(geometryOf(root)[1], [10, 140, 380, 20]);
      root.getChildren().single.getAnchor(ConstraintAnchorType.bottom)!.reset();
      root.layout();
      expect(geometryOf(root), geometryOf(build(centered: false)..layout()));
      expect(geometryOf(root)[1], [10, 0, 380, 20]);
    });

    test('a widget on the baseline of a sibling that turns gone lays out '
        'again as a fresh container does', () {
      // t fills between two anchors, so the graph wires its baseline through
      // its baseline dimension (17 from its measure). When t turns gone the
      // graph no longer measures it, and its baseline node must not keep
      // computing its margin from that earlier dimension.
      ConstraintWidgetContainer build({required bool gone}) {
        final root = ConstraintWidgetContainer.rect(0, 0, 400, 300);
        final t = ConstraintWidget.size(100, 22);
        root.add(t);
        final v = ConstraintWidget.size(60, 20);
        root.add(v);
        t.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
        t.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 40);
        t.connect(
          ConstraintAnchorType.right,
          root,
          ConstraintAnchorType.right,
          140,
        );
        t.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 30);
        t.setBaselineDistance(gone ? 0 : 17);
        // The Flutter adapter flags both ends of a baseline link, measured
        // baseline or not.
        t.setHasBaseline(true);
        if (gone) t.setVisibility(ConstraintWidget.GONE);
        v.setBaselineDistance(15);
        v.connect(
          ConstraintAnchorType.right,
          root,
          ConstraintAnchorType.right,
          8,
        );
        v.connect(
          ConstraintAnchorType.baseline,
          t,
          ConstraintAnchorType.baseline,
        );
        return root;
      }

      final root = build(gone: false);
      root.layout();
      expect(geometryOf(root)[2], [332, 32, 60, 20]);
      final t = root.getChildren()[0];
      // What the Flutter adapter does when a child turns gone in place: the
      // widget keeps its baseline flag but no longer has a measured baseline.
      t.setVisibility(ConstraintWidget.GONE);
      t.setBaselineDistance(0);
      t.setHasBaseline(true);
      root.layout();
      expect(geometryOf(root), geometryOf(build(gone: true)..layout()));
    });

    test('a barrier that counts no reference stays put', () {
      // A right barrier whose only reference is gone, without
      // allowsGoneWidget, holds no reference: Barrier.allSolved puts it at
      // its margin, -8, which the solver reports as -7. Android (Direct
      // resets it on every measure) and a fresh container keep it there.
      ConstraintWidgetContainer build() {
        final root = ConstraintWidgetContainer.rect(0, 0, 300, 200);
        root.setRtl(true);
        final b = Barrier()
          ..setBarrierType(Barrier.right)
          ..setAllowsGoneWidget(false)
          ..setMargin(-8);
        root.add(b);
        final v = ConstraintWidget.size(40, 20);
        root.add(v);
        final t = ConstraintWidget.size(100, 20);
        root.add(t);
        b.add(v);
        v.setVisibility(ConstraintWidget.GONE);
        v.connect(
          ConstraintAnchorType.left,
          root,
          ConstraintAnchorType.left,
          16,
        );
        t.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
        t.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
        t.connect(
          ConstraintAnchorType.right,
          root,
          ConstraintAnchorType.right,
          12,
        );
        t.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 10);
        return root;
      }

      final root = build();
      final fresh = geometryOf(build()..layout());
      expect(fresh[3], [-7, 10, 295, 20]);
      for (var i = 0; i < 4; i++) {
        root.layout();
        expect(geometryOf(root), fresh, reason: 'layout ${i + 1}');
      }
    });

    test('wrap-content root re-layout keeps its size', () {
      ConstraintWidgetContainer build() {
        final root = ConstraintWidgetContainer.rect(0, 0, 800, 0);
        final a = ConstraintWidget.size(100, 40);
        root.add(a);
        a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
        a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 10);
        final b = ConstraintWidget.size(100, 40);
        root.add(b);
        b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left);
        b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 6);
        root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
        return root;
      }

      final root = build();
      root.layout();
      final first = geometryOf(root);
      expect(root.getHeight(), greaterThan(0));
      root.layout();
      root.layout();
      expect(geometryOf(root), first,
          reason: 're-layout of a wrap-content root must not collapse');
    });
  });
}
