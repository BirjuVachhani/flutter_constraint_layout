// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.OptimizationsTest
// (upstream pinned in UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

// Ported from androidx.constraintlayout.core.OptimizationsTest.
//
// Notes on the mechanical translation:
// - `Metrics metrics = new Metrics(); root.fillMetrics(metrics);` and the
//   `System.out.println(metrics)` calls are diagnostic-only scaffolding (the
//   metrics object is never asserted). The graph engine has no Metrics/solver,
//   so these lines are dropped exactly like the other println/nanoTime lines.
//   No test in this file references genuine solver-only APIs (getSystem,
//   addToSolver, updateFromSolver, connectCircularConstraint, ...), so none are
//   skipped for the solver.
// - Java integer division `/` becomes `~/`; `(int) doubleExpr` becomes
//   `.toInt()`; float literals `0.2f`/`0.3f` become `0.2`/`0.3`.

class _Measurer implements Measurer {
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    final horizontalBehavior = measure.horizontalBehavior;
    final verticalBehavior = measure.verticalBehavior;
    final horizontalDimension = measure.horizontalDimension;
    final verticalDimension = measure.verticalDimension;

    if (horizontalBehavior == DimensionBehaviour.fixed) {
      measure.measuredWidth = horizontalDimension;
    } else if (horizontalBehavior == DimensionBehaviour.matchConstraint) {
      measure.measuredWidth = horizontalDimension;
    }
    if (verticalBehavior == DimensionBehaviour.fixed) {
      measure.measuredHeight = verticalDimension;
      measure.measuredBaseline = 8;
    } else {
      measure.measuredHeight = verticalDimension;
      measure.measuredBaseline = 8;
    }
    widget.setMeasureRequested(false);
  }

  @override
  void didMeasures() {}
}

final _Measurer sMeasurer = _Measurer();

void chainConnect(
  ConstraintAnchorType start,
  ConstraintWidget startTarget,
  ConstraintAnchorType end,
  ConstraintWidget endTarget,
  List<ConstraintWidget> widgets,
) {
  widgets[0].connect(start, startTarget, start);
  ConstraintWidget? previousWidget;
  for (var i = 0; i < widgets.length; i++) {
    if (previousWidget != null) {
      widgets[i].connect(start, previousWidget, end);
    }
    if (i < widgets.length - 1) {
      widgets[i].connect(end, widgets[i + 1], start);
    }
    previousWidget = widgets[i];
  }
  if (previousWidget != null) {
    previousWidget.connect(end, endTarget, end);
  }
}

void main() {
  group('OptimizationsTest', () {
    test('testGoneMatchConstraint', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      final a = ConstraintWidget.sizeNamed('A', 0, 10);
      final b = ConstraintWidget.sizeNamed('B', 10, 10);
      root.setDebugName('root');

      root.add(a);
      root.add(b);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 8);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 8);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 8);
      a.connect(
          ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 8);
      a.setVerticalBiasPercent(0.2);
      a.setHorizontalBiasPercent(0.2);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.layout();

      expect(a.getLeft(), 8);
      expect(a.getTop(), 163);
      expect(a.getRight(), 592);
      expect(a.getBottom(), 173);

      a.setVisibility(ConstraintWidget.GONE);
      root.layout();

      expect(a.getLeft(), 120);
      expect(a.getTop(), 160);
      expect(a.getRight(), 120);
      expect(a.getBottom(), 160);
    });

    test('test3EltsChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.add(a);
      root.add(b);
      root.add(c);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 40);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 30);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      root.layout();
      expect(a.getLeft(), 40);
      expect(b.getLeft(), 255);
      expect(c.getLeft(), 470);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.layout();
      expect(a.getLeft(), 40);
      // The closeTo calls in this test mirror upstream's assertEquals delta
      // (OptimizationsTest.java 117-151); upstream asserts C's left exactly.
      expect(b.getLeft(), closeTo(217, 1));
      expect(c.getLeft(), 393);
      expect(a.getWidth(), closeTo(177, 1));
      expect(b.getWidth(), closeTo(176, 1));
      expect(c.getWidth(), closeTo(177, 1));

      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, 7);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 3);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left, 7);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, 3);

      root.layout();

      expect(a.getLeft(), 40);
      expect(b.getLeft(), 220);
      expect(c.getLeft(), closeTo(400, 1));
      expect(a.getWidth(), closeTo(170, 1));
      expect(b.getWidth(), closeTo(170, 1));
      expect(c.getWidth(), closeTo(170, 1));

      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);

      a.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getLeft(), 0);
      expect(b.getLeft(), 3);
      expect(c.getLeft(), closeTo(292, 1));
      expect(a.getWidth(), 0);
      expect(b.getWidth(), closeTo(279, 1));
      expect(c.getWidth(), closeTo(278, 1));
    });

    test('testBasicChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.layout();
      expect(a.getLeft(), 133);
      // closeTo mirrors upstream's assertEquals delta (OptimizationsTest.java
      // 180 and 191).
      expect(b.getLeft(), closeTo(367, 1));

      final c = ConstraintWidget.size(100, 20);
      c.setDebugName('C');
      root.add(c);
      c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      root.layout();
      expect(a.getLeft(), 133);
      expect(b.getLeft(), closeTo(367, 1));
      expect(c.getLeft(), b.getRight());

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 40);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, 100);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);

      root.layout();
      expect(a.getLeft(), 170);
      expect(b.getLeft(), 370);

      a.setHorizontalBiasPercent(0);
      root.layout();
      expect(a.getLeft(), 40);
      expect(b.getLeft(), 240);

      a.setHorizontalBiasPercent(0.5);
      a.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getLeft(), 250);
      expect(b.getLeft(), 250);
    });

    test('testBasicChain2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      final c = ConstraintWidget.size(100, 20);
      c.setDebugName('C');
      root.add(c);
      c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 40);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, 100);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);

      a.setHorizontalBiasPercent(0.5);
      a.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getLeft(), 250);
      expect(b.getLeft(), 250);
    });

    test('testBasicRatio', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('1:1');
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.layout();
      expect(a.getHeight(), a.getWidth());
      expect(b.getTop(), (a.getHeight() - b.getHeight()) ~/ 2);
    });

    test('testBasicBaseline', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      a.setBaselineDistance(8);
      b.setBaselineDistance(8);
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.baseline, a, ConstraintAnchorType.baseline);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.layout();
      expect(a.getTop(), 290);
      expect(b.getTop(), a.getTop());
    });

    test('testBasicMatchConstraints', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.layout();
      expect(a.getLeft(), 0);
      expect(a.getTop(), 0);
      expect(a.getRight(), root.getWidth());
      expect(a.getBottom(), root.getHeight());
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 10);
      a.connect(
          ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 20);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 30);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 40);
      root.layout();
      expect(a.getLeft(), 30);
      expect(a.getTop(), 10);
      expect(a.getRight(), root.getWidth() - 40);
      expect(a.getBottom(), root.getHeight() - 20);
    });

    test('testBasicCenteringPositioning', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      root.add(a);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.layout();
      expect(a.getLeft(), (root.getWidth() - a.getWidth()) ~/ 2);
      expect(a.getTop(), (root.getHeight() - a.getHeight()) ~/ 2);
      a.setHorizontalBiasPercent(0.3);
      a.setVerticalBiasPercent(0.3);
      root.layout();
      expect(a.getLeft(), ((root.getWidth() - a.getWidth()) * 0.3).toInt());
      expect(a.getTop(), ((root.getHeight() - a.getHeight()) * 0.3).toInt());
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 30);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 50);
      a.connect(
          ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 20);
      root.layout();
      expect(
          a.getLeft(), ((root.getWidth() - a.getWidth() - 40) * 0.3).toInt() + 10);
      expect(a.getTop(),
          ((root.getHeight() - a.getHeight() - 70) * 0.3).toInt() + 50);
    });

    test('testBasicVerticalPositioning', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 31);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 27);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 27);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 104);
      root.add(a);
      root.add(b);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);

      a.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getLeft(), 0);
      expect(a.getTop(), 0);
      expect(b.getLeft(), 27);
      expect(b.getTop(), 104);
    });

    test('testBasicVerticalGuidelinePositioning', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final guidelineA = Guideline();
      guidelineA.setOrientation(Guideline.horizontal);
      guidelineA.setGuideEnd(67);
      root.setDebugName('root');
      a.setDebugName('A');
      guidelineA.setDebugName('guideline');
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 31);
      a.connect(
          ConstraintAnchorType.bottom, guidelineA, ConstraintAnchorType.top, 12);
      root.add(a);
      root.add(guidelineA);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.layout();
      expect(a.getTop(), 266);
      expect(guidelineA.getTop(), 533);
    });

    test('testSimpleCenterPositioning', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      const margin = 13;
      const marginR = 27;
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, margin);
      a.connect(
          ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, -margin);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, margin);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right,
          -marginR);
      root.add(a);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.layout();
      // closeTo mirrors upstream's assertEquals delta (OptimizationsTest.java
      // 476-477).
      expect(a.getLeft(), closeTo(270, 1));
      expect(a.getTop(), closeTo(303, 1));
    });

    test('testSimpleGuideline', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final guidelineA = Guideline();
      final a = ConstraintWidget.size(100, 20);
      guidelineA.setOrientation(Guideline.vertical);
      guidelineA.setGuideBegin(100);
      root.setDebugName('root');
      a.setDebugName('A');
      guidelineA.setDebugName('guidelineA');
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 32);
      a.connect(ConstraintAnchorType.left, guidelineA, ConstraintAnchorType.left, 2);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 7);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.add(guidelineA);
      root.add(a);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.layout();
      expect(a.getLeft(), 102);
      expect(a.getTop(), 32);
      expect(a.getWidth(), 491);
      expect(a.getHeight(), 20);
      expect(guidelineA.getLeft(), 100);
      root.setWidth(700);
      root.layout();
      expect(a.getLeft(), 102);
      expect(a.getTop(), 32);
      expect(a.getWidth(), 591);
      expect(a.getHeight(), 20);
      expect(guidelineA.getLeft(), 100);
    });

    test('testSimple', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 20);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 10);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 20);
      c.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 30);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom, 20);
      root.add(a);
      root.add(b);
      root.add(c);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);

      root.layout();

      expect(a.getLeft(), 10);
      expect(a.getTop(), 20);
      expect(b.getLeft(), 120);
      expect(b.getTop(), 60);
      expect(c.getLeft(), 140);
      expect(c.getTop(), 100);
    });

    test('testGuideline', () {
      void testVerticalGuideline(int directResolution) {
        final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
        root.setOptimizationLevel(directResolution);
        final a = ConstraintWidget.size(100, 20);
        final guideline = Guideline();
        guideline.setOrientation(Guideline.vertical);
        root.setDebugName('root');
        a.setDebugName('A');
        guideline.setDebugName('guideline');
        root.add(a);
        root.add(guideline);
        a.connect(ConstraintAnchorType.left, guideline, ConstraintAnchorType.left, 16);
        guideline.setGuideBegin(100);
        root.layout();
        expect(guideline.getLeft(), 100);
        expect(a.getLeft(), 116);
        expect(a.getWidth(), 100);
        expect(a.getHeight(), 20);
        expect(a.getTop(), 0);
        guideline.setGuidePercent(0.5);
        root.layout();
        expect(guideline.getLeft(), root.getWidth() ~/ 2);
        expect(a.getLeft(), 316);
        expect(a.getWidth(), 100);
        expect(a.getHeight(), 20);
        expect(a.getTop(), 0);
        guideline.setGuideEnd(100);
        root.layout();
        expect(guideline.getLeft(), 500);
        expect(a.getLeft(), 516);
        expect(a.getWidth(), 100);
        expect(a.getHeight(), 20);
        expect(a.getTop(), 0);
      }

      void testHorizontalGuideline(int directResolution) {
        final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
        root.setOptimizationLevel(directResolution);
        final a = ConstraintWidget.size(100, 20);
        final guideline = Guideline();
        guideline.setOrientation(Guideline.horizontal);
        root.setDebugName('root');
        a.setDebugName('A');
        guideline.setDebugName('guideline');
        root.add(a);
        root.add(guideline);
        a.connect(ConstraintAnchorType.top, guideline, ConstraintAnchorType.top, 16);
        guideline.setGuideBegin(100);
        root.layout();
        expect(guideline.getTop(), 100);
        expect(a.getTop(), 116);
        expect(a.getWidth(), 100);
        expect(a.getHeight(), 20);
        expect(a.getLeft(), 0);
        guideline.setGuidePercent(0.5);
        root.layout();
        expect(guideline.getTop(), root.getHeight() ~/ 2);
        expect(a.getTop(), 316);
        expect(a.getWidth(), 100);
        expect(a.getHeight(), 20);
        expect(a.getLeft(), 0);
        guideline.setGuideEnd(100);
        root.layout();
        expect(guideline.getTop(), 500);
        expect(a.getTop(), 516);
        expect(a.getWidth(), 100);
        expect(a.getHeight(), 20);
        expect(a.getLeft(), 0);
      }

      testVerticalGuideline(Optimizer.OPTIMIZATION_NONE);
      testVerticalGuideline(Optimizer.OPTIMIZATION_STANDARD);
      testHorizontalGuideline(Optimizer.OPTIMIZATION_NONE);
      testHorizontalGuideline(Optimizer.OPTIMIZATION_STANDARD);
    });

    test('testBasicCentering', () {
      void testBasicCentering(int directResolution) {
        final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
        root.setOptimizationLevel(directResolution);
        final a = ConstraintWidget.size(100, 20);
        root.setDebugName('root');
        a.setDebugName('A');
        root.add(a);
        a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
        a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 10);
        a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 10);
        a.connect(
            ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 10);
        root.layout();
        expect(a.getLeft(), 250);
        expect(a.getTop(), 290);
      }

      testBasicCentering(Optimizer.OPTIMIZATION_NONE);
      testBasicCentering(Optimizer.OPTIMIZATION_STANDARD);
    });

    test('testPercent', () {
      void testPercent(int directResolution) {
        final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
        root.setOptimizationLevel(directResolution);
        final a = ConstraintWidget.size(100, 20);
        root.setDebugName('root');
        a.setDebugName('A');
        root.add(a);
        a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
        a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 10);
        a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
        a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
        a.setHorizontalMatchStyle(
            ConstraintWidget.MATCH_CONSTRAINT_PERCENT, 0, 0, 0.5);
        a.setVerticalMatchStyle(
            ConstraintWidget.MATCH_CONSTRAINT_PERCENT, 0, 0, 0.5);
        root.layout();
        expect(a.getLeft(), 10);
        expect(a.getTop(), 10);
        expect(a.getWidth(), 300);
        expect(a.getHeight(), 300);
      }

      testPercent(Optimizer.OPTIMIZATION_NONE);
      testPercent(Optimizer.OPTIMIZATION_STANDARD);
    });

    test('testDependency', () {
      void testDependency(int directResolution) {
        final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
        root.setOptimizationLevel(directResolution);
        final a = ConstraintWidget.size(100, 20);
        final b = ConstraintWidget.size(100, 20);
        final c = ConstraintWidget.size(100, 20);
        root.setDebugName('root');
        a.setDebugName('A');
        b.setDebugName('B');
        c.setDebugName('C');
        root.add(a);
        root.add(b);
        root.add(c);
        a.setBaselineDistance(8);
        b.setBaselineDistance(8);
        c.setBaselineDistance(8);
        a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
        a.connect(ConstraintAnchorType.baseline, b, ConstraintAnchorType.baseline);
        b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 16);
        b.connect(ConstraintAnchorType.baseline, c, ConstraintAnchorType.baseline);
        c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, 48);
        c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 32);
        root.layout();
        expect(a.getLeft(), 10);
        expect(a.getTop(), 32);
        expect(b.getLeft(), 126);
        expect(b.getTop(), 32);
        expect(c.getLeft(), 274);
        expect(c.getTop(), 32);
      }

      testDependency(Optimizer.OPTIMIZATION_NONE);
      testDependency(Optimizer.OPTIMIZATION_STANDARD);
    });

    test('testDependency2', () {
      void testDependency2(int directResolution) {
        final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
        root.setOptimizationLevel(directResolution);
        final a = ConstraintWidget.size(100, 20);
        final b = ConstraintWidget.size(100, 20);
        final c = ConstraintWidget.size(100, 20);
        a.setDebugName('A');
        b.setDebugName('B');
        c.setDebugName('C');
        root.add(a);
        root.add(b);
        root.add(c);
        a.setBaselineDistance(8);
        b.setBaselineDistance(8);
        c.setBaselineDistance(8);
        a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
        a.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.left);
        b.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.top);
        b.connect(ConstraintAnchorType.left, c, ConstraintAnchorType.left);
        c.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
        c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 12);
        root.layout();
        expect(a.getLeft(), 12);
        expect(a.getTop(), 580);
        expect(b.getLeft(), 12);
        expect(b.getTop(), 560);
        expect(c.getLeft(), 12);
        expect(c.getTop(), 540);
      }

      testDependency2(Optimizer.OPTIMIZATION_NONE);
      testDependency2(Optimizer.OPTIMIZATION_STANDARD);
    });

    test('testDependency3', () {
      void testDependency3(int directResolution) {
        final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
        root.setOptimizationLevel(directResolution);
        final a = ConstraintWidget.size(100, 20);
        final b = ConstraintWidget.size(100, 20);
        final c = ConstraintWidget.size(100, 20);
        root.setDebugName('root');
        a.setDebugName('A');
        b.setDebugName('B');
        c.setDebugName('C');
        root.add(a);
        root.add(b);
        root.add(c);
        a.setBaselineDistance(8);
        b.setBaselineDistance(8);
        c.setBaselineDistance(8);
        a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
        a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 20);
        b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 30);
        b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 60);
        b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 10);
        c.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
        c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, 20);
        root.layout();
        expect(a.getLeft(), 10);
        expect(a.getTop(), 20);
        expect(b.getLeft(), 260);
        expect(b.getTop(), 520);
        expect(c.getLeft(), 380);
        expect(c.getTop(), 500);
      }

      testDependency3(Optimizer.OPTIMIZATION_NONE);
      testDependency3(Optimizer.OPTIMIZATION_STANDARD);
    });

    test('testDependency4', () {
      void testDependency4(int directResolution) {
        final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
        root.setOptimizationLevel(directResolution);
        final a = ConstraintWidget.size(100, 20);
        final b = ConstraintWidget.size(100, 20);
        root.setDebugName('root');
        a.setDebugName('A');
        b.setDebugName('B');
        root.add(a);
        root.add(b);
        a.setBaselineDistance(8);
        b.setBaselineDistance(8);
        a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
        a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 20);
        a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 10);
        a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 20);
        b.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right, 30);
        b.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom, 60);
        root.layout();
        expect(a.getLeft(), 250);
        expect(a.getTop(), 290);
        expect(b.getLeft(), 220);
        expect(b.getTop(), 230);
      }

      testDependency4(Optimizer.OPTIMIZATION_NONE);
      testDependency4(Optimizer.OPTIMIZATION_STANDARD);
    });

    test('testDependency5', () {
      void testDependency5(int directResolution) {
        final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
        root.setOptimizationLevel(directResolution);
        final a = ConstraintWidget.size(100, 20);
        final b = ConstraintWidget.size(100, 20);
        final c = ConstraintWidget.size(100, 20);
        final d = ConstraintWidget.size(100, 20);
        root.setDebugName('root');
        a.setDebugName('A');
        b.setDebugName('B');
        c.setDebugName('C');
        d.setDebugName('D');
        root.add(a);
        root.add(b);
        root.add(c);
        root.add(d);
        a.setBaselineDistance(8);
        b.setBaselineDistance(8);
        c.setBaselineDistance(8);
        d.setBaselineDistance(8);
        a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
        a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 10);
        a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 20);
        a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
        b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
        b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
        b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
        b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 10);
        c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
        c.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.right, 20);
        d.connect(ConstraintAnchorType.top, c, ConstraintAnchorType.bottom);
        d.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.right, 20);
        root.layout();
        expect(a.getLeft(), 250);
        expect(a.getTop(), 197);
        expect(b.getLeft(), 250);
        expect(b.getTop(), 393);
        expect(c.getLeft(), 230);
        expect(c.getTop(), 413);
        expect(d.getLeft(), 210);
        expect(d.getTop(), 433);
      }

      testDependency5(Optimizer.OPTIMIZATION_NONE);
      testDependency5(Optimizer.OPTIMIZATION_STANDARD);
    });

    test('testUnconstrainedDependency', () {
      void testUnconstrainedDependency(int directResolution) {
        final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
        root.setOptimizationLevel(directResolution);
        final a = ConstraintWidget.size(100, 20);
        final b = ConstraintWidget.size(100, 20);
        final c = ConstraintWidget.size(100, 20);
        root.setDebugName('root');
        a.setDebugName('A');
        b.setDebugName('B');
        c.setDebugName('C');
        root.add(a);
        root.add(b);
        root.add(c);
        a.setBaselineDistance(8);
        b.setBaselineDistance(8);
        c.setBaselineDistance(8);
        a.setFrame(142, 96, 242, 130);
        b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 10);
        b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top, 100);
        c.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.left);
        c.connect(ConstraintAnchorType.baseline, a, ConstraintAnchorType.baseline);
        root.layout();
        expect(a.getLeft(), 142);
        expect(a.getTop(), 96);
        expect(a.getWidth(), 100);
        expect(a.getHeight(), 34);
        expect(b.getLeft(), 252);
        expect(b.getTop(), 196);
        expect(c.getLeft(), 42);
        expect(c.getTop(), 96);
      }

      testUnconstrainedDependency(Optimizer.OPTIMIZATION_NONE);
      testUnconstrainedDependency(Optimizer.OPTIMIZATION_STANDARD);
    });

    test('testFullLayout', () {
      void testFullLayout(int directResolution) {
        final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
        root.setOptimizationLevel(directResolution);
        final a = ConstraintWidget.size(100, 20);
        final b = ConstraintWidget.size(100, 20);
        final c = ConstraintWidget.size(100, 20);
        final d = ConstraintWidget.size(100, 20);
        final e = ConstraintWidget.size(100, 20);
        final f = ConstraintWidget.size(100, 20);
        final g = ConstraintWidget.size(100, 20);
        a.setDebugName('A');
        b.setDebugName('B');
        c.setDebugName('C');
        d.setDebugName('D');
        e.setDebugName('E');
        f.setDebugName('F');
        g.setDebugName('G');
        root.add(g);
        root.add(a);
        root.add(b);
        root.add(e);
        root.add(c);
        root.add(d);
        root.add(f);
        a.setBaselineDistance(8);
        b.setBaselineDistance(8);
        c.setBaselineDistance(8);
        d.setBaselineDistance(8);
        e.setBaselineDistance(8);
        f.setBaselineDistance(8);
        g.setBaselineDistance(8);
        a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 20);
        a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
        a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
        b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 40);
        b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 16);
        c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, 16);
        c.connect(ConstraintAnchorType.baseline, b, ConstraintAnchorType.baseline);
        d.connect(ConstraintAnchorType.top, c, ConstraintAnchorType.bottom);
        d.connect(ConstraintAnchorType.left, c, ConstraintAnchorType.left);
        e.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.right);
        e.connect(ConstraintAnchorType.baseline, d, ConstraintAnchorType.baseline);
        f.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
        f.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
        g.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 16);
        g.connect(ConstraintAnchorType.baseline, f, ConstraintAnchorType.baseline);
        root.layout();

        expect(a.getLeft(), 250);
        expect(a.getTop(), 20);
        expect(b.getLeft(), 16);
        expect(b.getTop(), 80);
        expect(c.getLeft(), 132);
        expect(c.getTop(), 80);
        expect(d.getLeft(), 132);
        expect(d.getTop(), 100);
        expect(e.getLeft(), 16);
        expect(e.getTop(), 100);
        expect(f.getLeft(), 500);
        expect(f.getTop(), 580);
        expect(g.getLeft(), 16);
        expect(g.getTop(), 580);
      }

      testFullLayout(Optimizer.OPTIMIZATION_NONE);
      testFullLayout(Optimizer.OPTIMIZATION_STANDARD);
    });

    test('testComplexLayout', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GROUPING);
      final a = ConstraintWidget.size(100, 100);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final d = ConstraintWidget.size(30, 30);
      final e = ConstraintWidget.size(30, 30);
      final f = ConstraintWidget.size(30, 30);
      final g = ConstraintWidget.size(100, 20);
      final h = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      e.setDebugName('E');
      f.setDebugName('F');
      g.setDebugName('G');
      h.setDebugName('H');
      root.add(g);
      root.add(a);
      root.add(b);
      root.add(e);
      root.add(c);
      root.add(d);
      root.add(f);
      root.add(h);
      b.setBaselineDistance(8);
      c.setBaselineDistance(8);
      d.setBaselineDistance(8);
      e.setBaselineDistance(8);
      f.setBaselineDistance(8);
      g.setBaselineDistance(8);
      h.setBaselineDistance(8);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 16);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 16);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 16);

      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 16);

      c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 16);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      d.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);
      d.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 16);

      e.connect(ConstraintAnchorType.bottom, d, ConstraintAnchorType.bottom);
      e.connect(ConstraintAnchorType.left, d, ConstraintAnchorType.right, 16);

      f.connect(ConstraintAnchorType.bottom, e, ConstraintAnchorType.bottom);
      f.connect(ConstraintAnchorType.left, e, ConstraintAnchorType.right, 16);

      g.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      g.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 16);
      g.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      h.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 16);
      h.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 16);

      root.setMeasurer(sMeasurer);
      root.layout();

      expect(a.getLeft(), 16);
      expect(a.getTop(), 250);

      expect(b.getLeft(), 132);
      expect(b.getTop(), 250);

      expect(c.getLeft(), 132);
      expect(c.getTop(), 290);

      expect(d.getLeft(), 132);
      expect(d.getTop(), 320);

      expect(e.getLeft(), 178);
      expect(e.getTop(), 320);

      expect(f.getLeft(), 224);
      expect(f.getTop(), 320);

      expect(g.getLeft(), 484);
      expect(g.getTop(), 290);

      expect(h.getLeft(), 484);
      expect(h.getTop(), 564);
    });

    test('testComplexLayoutWrap', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_DIRECT);
      final a = ConstraintWidget.size(100, 100);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final d = ConstraintWidget.size(30, 30);
      final e = ConstraintWidget.size(30, 30);
      final f = ConstraintWidget.size(30, 30);
      final g = ConstraintWidget.size(100, 20);
      final h = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      e.setDebugName('E');
      f.setDebugName('F');
      g.setDebugName('G');
      h.setDebugName('H');
      root.add(g);
      root.add(a);
      root.add(b);
      root.add(e);
      root.add(c);
      root.add(d);
      root.add(f);
      root.add(h);
      b.setBaselineDistance(8);
      c.setBaselineDistance(8);
      d.setBaselineDistance(8);
      e.setBaselineDistance(8);
      f.setBaselineDistance(8);
      g.setBaselineDistance(8);
      h.setBaselineDistance(8);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 16);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 16);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 16);

      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 16);

      c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 16);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      d.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);
      d.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 16);

      e.connect(ConstraintAnchorType.bottom, d, ConstraintAnchorType.bottom);
      e.connect(ConstraintAnchorType.left, d, ConstraintAnchorType.right, 16);

      f.connect(ConstraintAnchorType.bottom, e, ConstraintAnchorType.bottom);
      f.connect(ConstraintAnchorType.left, e, ConstraintAnchorType.right, 16);

      g.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      g.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 16);
      g.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      h.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 16);
      h.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 16);

      root.setMeasurer(sMeasurer);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(a.getLeft(), 16);
      expect(a.getTop(), 16);

      expect(b.getLeft(), 132);
      expect(b.getTop(), 16);

      expect(c.getLeft(), 132);
      expect(c.getTop(), 56);

      expect(d.getLeft(), 132);
      expect(d.getTop(), 86);

      expect(e.getLeft(), 178);
      expect(e.getTop(), 86);

      expect(f.getLeft(), 224);
      expect(f.getTop(), 86);

      expect(g.getLeft(), 484);
      expect(g.getTop(), 56);

      expect(h.getLeft(), 484);
      expect(h.getTop(), 96);
    });

    test('testChainLayoutWrap', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GROUPING);
      final a = ConstraintWidget.size(100, 100);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.add(a);
      root.add(b);
      root.add(c);
      a.setBaselineDistance(28);
      b.setBaselineDistance(8);
      c.setBaselineDistance(8);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 16);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 16);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 16);

      b.connect(ConstraintAnchorType.baseline, a, ConstraintAnchorType.baseline);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);

      c.connect(ConstraintAnchorType.baseline, b, ConstraintAnchorType.baseline);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 16);

      root.setMeasurer(sMeasurer);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(a.getLeft(), 16);
      expect(a.getTop(), 250);

      expect(b.getLeft(), 116);
      expect(b.getTop(), 270);

      expect(c.getLeft(), 216);
      expect(c.getTop(), 270);
    });

    test('testChainLayoutWrap2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GROUPING);
      final a = ConstraintWidget.size(100, 100);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final d = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);
      a.setBaselineDistance(28);
      b.setBaselineDistance(8);
      c.setBaselineDistance(8);
      d.setBaselineDistance(8);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 16);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 16);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 16);

      b.connect(ConstraintAnchorType.baseline, a, ConstraintAnchorType.baseline);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);

      c.connect(ConstraintAnchorType.baseline, b, ConstraintAnchorType.baseline);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, d, ConstraintAnchorType.left, 16);

      d.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      d.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      root.setMeasurer(sMeasurer);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(a.getLeft(), 16);
      expect(a.getTop(), 250);

      expect(b.getLeft(), 116);
      expect(b.getTop(), 270);

      expect(c.getLeft(), 216);
      expect(c.getTop(), 270);

      expect(d.getLeft(), 332);
      expect(d.getTop(), 580);
    });

    test('testChainLayoutWrapGuideline', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GROUPING);
      final a = ConstraintWidget.size(100, 20);
      final guideline = Guideline();
      guideline.setOrientation(Guideline.vertical);
      guideline.setGuideEnd(100);
      root.setDebugName('root');
      a.setDebugName('A');
      guideline.setDebugName('guideline');
      root.add(a);
      root.add(guideline);
      a.setBaselineDistance(28);

      a.connect(ConstraintAnchorType.left, guideline, ConstraintAnchorType.left, 16);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 16);

      root.setMeasurer(sMeasurer);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(a.getLeft(), 516);
      expect(a.getTop(), 0);

      expect(guideline.getLeft(), 500);
    });

    test('testChainLayoutWrapGuidelineChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GROUPING);
      final a = ConstraintWidget.size(20, 20);
      final b = ConstraintWidget.size(20, 20);
      final c = ConstraintWidget.size(20, 20);
      final d = ConstraintWidget.size(20, 20);
      final a2 = ConstraintWidget.size(20, 20);
      final b2 = ConstraintWidget.size(20, 20);
      final c2 = ConstraintWidget.size(20, 20);
      final d2 = ConstraintWidget.size(20, 20);
      final guidelineStart = Guideline();
      final guidelineEnd = Guideline();
      guidelineStart.setOrientation(Guideline.vertical);
      guidelineEnd.setOrientation(Guideline.vertical);
      guidelineStart.setGuideBegin(30);
      guidelineEnd.setGuideEnd(30);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      a2.setDebugName('A2');
      b2.setDebugName('B2');
      c2.setDebugName('C2');
      d2.setDebugName('D2');
      guidelineStart.setDebugName('guidelineStart');
      guidelineEnd.setDebugName('guidelineEnd');
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);
      root.add(a2);
      root.add(b2);
      root.add(c2);
      root.add(d2);
      root.add(guidelineStart);
      root.add(guidelineEnd);

      c.setVisibility(ConstraintWidget.GONE);
      chainConnect(ConstraintAnchorType.left, guidelineStart,
          ConstraintAnchorType.right, guidelineEnd, [a, b, c, d]);
      chainConnect(ConstraintAnchorType.left, root, ConstraintAnchorType.right,
          root, [a2, b2, c2, d2]);

      root.setMeasurer(sMeasurer);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(a.getLeft(), 30);
      expect(b.getLeft(), 50);
      expect(c.getLeft(), 70);
      expect(d.getLeft(), 70);
      expect(guidelineStart.getLeft(), 30);
      expect(guidelineEnd.getLeft(), 90);
      expect(a2.getLeft(), 8);
      expect(b2.getLeft(), 36);
      expect(c2.getLeft(), 64);
      expect(d2.getLeft(), 92);
    });

    test('testChainLayoutWrapGuidelineChainVertical', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GROUPING);
      final a = ConstraintWidget.size(20, 20);
      final b = ConstraintWidget.size(20, 20);
      final c = ConstraintWidget.size(20, 20);
      final d = ConstraintWidget.size(20, 20);
      final a2 = ConstraintWidget.size(20, 20);
      final b2 = ConstraintWidget.size(20, 20);
      final c2 = ConstraintWidget.size(20, 20);
      final d2 = ConstraintWidget.size(20, 20);
      final guidelineStart = Guideline();
      final guidelineEnd = Guideline();
      guidelineStart.setOrientation(Guideline.horizontal);
      guidelineEnd.setOrientation(Guideline.horizontal);
      guidelineStart.setGuideBegin(30);
      guidelineEnd.setGuideEnd(30);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      a2.setDebugName('A2');
      b2.setDebugName('B2');
      c2.setDebugName('C2');
      d2.setDebugName('D2');
      guidelineStart.setDebugName('guidelineStart');
      guidelineEnd.setDebugName('guidelineEnd');
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);
      root.add(a2);
      root.add(b2);
      root.add(c2);
      root.add(d2);
      root.add(guidelineStart);
      root.add(guidelineEnd);

      c.setVisibility(ConstraintWidget.GONE);
      chainConnect(ConstraintAnchorType.top, guidelineStart,
          ConstraintAnchorType.bottom, guidelineEnd, [a, b, c, d]);
      chainConnect(ConstraintAnchorType.top, root, ConstraintAnchorType.bottom,
          root, [a2, b2, c2, d2]);

      root.setMeasurer(sMeasurer);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(a.getTop(), 30);
      expect(b.getTop(), 50);
      expect(c.getTop(), 70);
      expect(d.getTop(), 70);
      expect(guidelineStart.getTop(), 30);
      expect(guidelineEnd.getTop(), 90);
      expect(a2.getTop(), 8);
      expect(b2.getTop(), 36);
      expect(c2.getTop(), 64);
      expect(d2.getTop(), 92);

      expect(a.getLeft(), 0);
      expect(b.getLeft(), 0);
      expect(c.getLeft(), 0);
      expect(d.getLeft(), 0);
      expect(a2.getLeft(), 0);
      expect(b2.getLeft(), 0);
      expect(c2.getLeft(), 0);
      expect(d2.getLeft(), 0);
    });

    test('testChainLayoutWrapRatioChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GROUPING);
      final a = ConstraintWidget.size(20, 20);
      final b = ConstraintWidget.size(20, 20);
      final c = ConstraintWidget.size(20, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.add(a);
      root.add(b);
      root.add(c);

      chainConnect(ConstraintAnchorType.top, root, ConstraintAnchorType.bottom,
          root, [a, b, c]);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setVerticalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setDimensionRatioString('1:1');

      root.setMeasurer(sMeasurer);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      root.setHeight(600);
      root.layout();

      expect(a.getTop(), 0);
      expect(b.getTop(), 290);
      expect(c.getTop(), 580);
      expect(a.getLeft(), 0);
      expect(b.getLeft(), 0);
      expect(c.getLeft(), 0);
      expect(b.getWidth(), 20);
      expect(b.getHeight(), b.getWidth());
    });

    test('testLayoutWrapBarrier', () {
      final root = ConstraintWidgetContainer.sizeNamed('root', 600, 600);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GROUPING);
      final a = ConstraintWidget.sizeNamed('A', 20, 20);
      final b = ConstraintWidget.sizeNamed('B', 20, 20);
      final c = ConstraintWidget.sizeNamed('C', 20, 20);
      final barrier = Barrier.named('Barrier');
      barrier.setBarrierType(Barrier.bottom);
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(barrier);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.setVisibility(ConstraintWidget.GONE);
      c.connect(ConstraintAnchorType.top, barrier, ConstraintAnchorType.top);
      barrier.add(a);
      barrier.add(b);

      root.setMeasurer(sMeasurer);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(a.getLeft(), 0);
      expect(a.getTop(), 0);
      expect(b.getLeft(), 0);
      expect(b.getTop(), 20);
      expect(c.getLeft(), 0);
      expect(c.getTop(), 20);
      expect(barrier.getTop(), 20);
      expect(root.getHeight(), 40);
    });

    test('testLayoutWrapGuidelinesMatch', () {
      final root = ConstraintWidgetContainer.sizeNamed('root', 600, 600);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GROUPING);
      final a = ConstraintWidget.sizeNamed('A', 20, 20);

      final left = Guideline();
      left.setOrientation(Guideline.vertical);
      left.setGuideBegin(30);
      left.setDebugName('L');

      final right = Guideline();
      right.setOrientation(Guideline.vertical);
      right.setGuideEnd(30);
      right.setDebugName('R');

      final top = Guideline();
      top.setOrientation(Guideline.horizontal);
      top.setGuideBegin(30);
      top.setDebugName('T');

      final bottom = Guideline();
      bottom.setOrientation(Guideline.horizontal);
      bottom.setGuideEnd(30);
      bottom.setDebugName('B');

      root.add(a);
      root.add(left);
      root.add(right);
      root.add(top);
      root.add(bottom);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.connect(ConstraintAnchorType.left, left, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, right, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, top, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, bottom, ConstraintAnchorType.bottom);

      root.setMeasurer(sMeasurer);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getHeight(), 60);
      expect(a.getLeft(), 30);
      expect(a.getTop(), 30);
      expect(a.getWidth(), 540);
      expect(a.getHeight(), 0);
    });

    test('testLayoutWrapMatch', () {
      final root = ConstraintWidgetContainer.sizeNamed('root', 600, 600);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GROUPING);
      final a = ConstraintWidget.sizeNamed('A', 50, 20);
      final b = ConstraintWidget.sizeNamed('B', 50, 30);
      final c = ConstraintWidget.sizeNamed('C', 50, 20);

      root.add(a);
      root.add(b);
      root.add(c);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.setMeasurer(sMeasurer);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(b.getTop(), 20);
      expect(b.getBottom(), 50);
      expect(b.getLeft(), 50);
      expect(b.getRight(), 550);
      expect(root.getHeight(), 70);
    });

    test('testLayoutWrapBarrier2', () {
      final root = ConstraintWidgetContainer.sizeNamed('root', 600, 600);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GROUPING);
      final a = ConstraintWidget.sizeNamed('A', 50, 20);
      final b = ConstraintWidget.sizeNamed('B', 50, 30);
      final c = ConstraintWidget.sizeNamed('C', 50, 20);

      final guideline = Guideline();
      guideline.setDebugName('end');
      guideline.setGuideEnd(40);
      guideline.setOrientation(ConstraintWidget.VERTICAL);

      final barrier = Barrier();
      barrier.setBarrierType(Barrier.left);
      barrier.setDebugName('barrier');
      barrier.add(b);
      barrier.add(c);

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(barrier);
      root.add(guideline);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, barrier, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, guideline, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      root.setMeasurer(sMeasurer);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getWidth(), 140);
    });

    test('testLayoutWrapBarrier3', () {
      final root = ConstraintWidgetContainer.sizeNamed('root', 600, 600);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GROUPING);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      final a = ConstraintWidget.sizeNamed('A', 50, 20);
      final b = ConstraintWidget.sizeNamed('B', 50, 30);
      final c = ConstraintWidget.sizeNamed('C', 50, 20);

      final guideline = Guideline();
      guideline.setDebugName('end');
      guideline.setGuideEnd(40);
      guideline.setOrientation(ConstraintWidget.VERTICAL);

      final barrier = Barrier();
      barrier.setBarrierType(Barrier.left);
      barrier.setDebugName('barrier');
      barrier.add(b);
      barrier.add(c);

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(barrier);
      root.add(guideline);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, barrier, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, guideline, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      root.setMeasurer(sMeasurer);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getWidth(), 140);
    });

    test('testSimpleGuideline2', () {
      final root = ConstraintWidgetContainer.sizeNamed('root', 600, 600);
      final guidelineStart = Guideline();
      guidelineStart.setDebugName('start');
      guidelineStart.setGuidePercent(0.1);
      guidelineStart.setOrientation(ConstraintWidget.VERTICAL);

      final guidelineEnd = Guideline();
      guidelineEnd.setDebugName('end');
      guidelineEnd.setGuideEnd(40);
      guidelineEnd.setOrientation(ConstraintWidget.VERTICAL);

      final a = ConstraintWidget.sizeNamed('A', 50, 20);
      root.add(a);
      root.add(guidelineStart);
      root.add(guidelineEnd);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.connect(ConstraintAnchorType.left, guidelineStart, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, guidelineEnd, ConstraintAnchorType.right);

      root.setMeasurer(sMeasurer);
      root.layout();
      // Original test has no assertions; it only prints the resolved geometry.
    });
  });
}
