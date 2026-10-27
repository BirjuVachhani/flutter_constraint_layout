// Copyright (C) 2021 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.BarrierTest
// (upstream pinned in UPSTREAM.md).

import 'dart:math' as math;

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  group('BarrierTest', () {
    test('barrierConstrainedWidth', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(200, 20);
      final barrier = Barrier();
      final guidelineStart = Guideline();
      final guidelineEnd = Guideline();
      guidelineStart.setOrientation(ConstraintWidget.VERTICAL);
      guidelineEnd.setOrientation(ConstraintWidget.VERTICAL);
      guidelineStart.setGuideBegin(30);
      guidelineEnd.setGuideEnd(20);

      root.setDebugName('root');
      guidelineStart.setDebugName('guidelineStart');
      guidelineEnd.setDebugName('guidelineEnd');
      a.setDebugName('A');
      b.setDebugName('B');
      barrier.setDebugName('Barrier');
      barrier.setBarrierType(Barrier.left);

      barrier.add(a);
      barrier.add(b);

      root.add(a);
      root.add(b);
      root.add(guidelineStart);
      root.add(guidelineEnd);
      root.add(barrier);

      a.connect(
          ConstraintAnchorType.left, guidelineStart, ConstraintAnchorType.left);
      a.connect(
          ConstraintAnchorType.right, guidelineEnd, ConstraintAnchorType.right);
      b.connect(
          ConstraintAnchorType.left, guidelineStart, ConstraintAnchorType.left);
      b.connect(
          ConstraintAnchorType.right, guidelineEnd, ConstraintAnchorType.right);
      a.setHorizontalBiasPercent(1);
      b.setHorizontalBiasPercent(1);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(root.getWidth(), 250);
      expect(guidelineStart.getLeft(), 30);
      expect(guidelineEnd.getLeft(), 230);
      expect(a.getLeft(), 130);
      expect(a.getWidth(), 100);
      expect(b.getLeft(), 30);
      expect(b.getWidth(), 200);
      expect(barrier.getLeft(), 30);
    });

    test('barrierImage', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(200, 20);
      final c = ConstraintWidget.size(60, 60);
      final barrier = Barrier();

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      barrier.setDebugName('Barrier');
      barrier.setBarrierType(Barrier.right);

      barrier.add(a);
      barrier.add(b);

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(barrier);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);

      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      a.setVerticalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);

      c.setHorizontalBiasPercent(1);
      c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.left, barrier, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.layout();
      expect(a.getLeft(), 0);
      expect(a.getTop(), 0);
      expect(b.getLeft(), 0);
      expect(b.getTop(), 580);
      expect(c.getLeft(), 740);
      expect(c.getTop(), 270);
      expect(barrier.getLeft(), 200);
    });

    test('barrierTooStrong', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(60, 60);
      final b = ConstraintWidget.size(100, 200);
      final c = ConstraintWidget.size(100, 20);
      final barrier = Barrier();

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      barrier.setDebugName('Barrier');
      barrier.setBarrierType(Barrier.bottom);

      barrier.add(b);

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(barrier);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      b.connect(ConstraintAnchorType.top, c, ConstraintAnchorType.bottom);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchParent);

      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchParent);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();
      expect(a.getLeft(), 740);
      expect(a.getTop(), 0);
      expect(b.getLeft(), 0);
      expect(b.getTop(), 60);
      expect(b.getWidth(), 800);
      expect(b.getHeight(), 200);
      expect(c.getLeft(), 0);
      expect(c.getTop(), 0);
      expect(c.getWidth(), 800);
      expect(c.getHeight(), 60);
      expect(barrier.getBottom(), 260);
    });

    test('barrierMax', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(150, 20);
      final barrier = Barrier();

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      barrier.setDebugName('Barrier');

      barrier.add(a);

      root.add(a);
      root.add(barrier);
      root.add(b);

      barrier.setBarrierType(Barrier.right);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.left, barrier, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.setHorizontalBiasPercent(0);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 150, 1);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();

      expect(a.getLeft(), 0);
      expect(barrier.getLeft(), 100);
      expect(b.getLeft(), 100);
      expect(b.getWidth(), 150);
    });

    test('barrierCenter', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final barrier = Barrier();

      root.setDebugName('root');
      a.setDebugName('A');
      barrier.setDebugName('Barrier');

      barrier.add(a);

      root.add(a);
      root.add(barrier);

      barrier.setBarrierType(Barrier.right);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
      a.connect(ConstraintAnchorType.right, barrier, ConstraintAnchorType.right, 30);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      root.layout();

      expect(a.getLeft(), 10);
      expect(barrier.getLeft(), 140);
    });

    test('barrierCenter2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final barrier = Barrier();

      root.setDebugName('root');
      a.setDebugName('A');
      barrier.setDebugName('Barrier');

      barrier.add(a);

      root.add(a);
      root.add(barrier);

      barrier.setBarrierType(Barrier.left);

      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 10);
      a.connect(ConstraintAnchorType.left, barrier, ConstraintAnchorType.left, 30);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      root.layout();

      expect(a.getRight(), root.getWidth() - 10);
      expect(barrier.getLeft(), a.getLeft() - 30);
    });

    test('barrierCenter3', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final barrier = Barrier();

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      barrier.setDebugName('Barrier');

      barrier.add(a);
      barrier.add(b);

      root.add(a);
      root.add(b);
      root.add(barrier);

      barrier.setBarrierType(Barrier.left);

      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      a.setWidth(100);
      b.setWidth(200);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);
      a.setHorizontalBiasPercent(1);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);
      b.setHorizontalBiasPercent(1);

      root.layout();

      expect(a.getWidth(), 100);
      expect(b.getWidth(), 200);
      expect(barrier.getLeft(), b.getLeft());
    });

    test('barrierCenter4', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(150, 20);
      final b = ConstraintWidget.size(100, 20);
      final barrier = Barrier();

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      barrier.setDebugName('Barrier');

      barrier.add(a);
      barrier.add(b);

      root.add(a);
      root.add(b);
      root.add(barrier);

      barrier.setBarrierType(Barrier.left);

      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.left, barrier, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.left, barrier, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      a.setHorizontalBiasPercent(0);
      b.setHorizontalBiasPercent(0);

      root.layout();

      expect(a.getRight(), root.getWidth());
      expect(barrier.getLeft(), math.min(a.getLeft(), b.getLeft()));
      expect(a.getLeft(), barrier.getLeft());
      expect(b.getLeft(), barrier.getLeft());
    });

    test('barrierCenter5', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(150, 20);
      final c = ConstraintWidget.size(200, 20);
      final barrier = Barrier();

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      barrier.setDebugName('Barrier');

      barrier.add(a);
      barrier.add(b);
      barrier.add(c);

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(barrier);

      barrier.setBarrierType(Barrier.right);

      a.connect(ConstraintAnchorType.right, barrier, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      b.connect(ConstraintAnchorType.right, barrier, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);

      c.connect(ConstraintAnchorType.right, barrier, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);

      a.setHorizontalBiasPercent(0);
      b.setHorizontalBiasPercent(0);
      c.setHorizontalBiasPercent(0);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);
      c.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);

      root.layout();

      expect(barrier.getRight(),
          math.max(math.max(a.getRight(), b.getRight()), c.getRight()));
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 150);
      expect(c.getWidth(), 200);
    });

    test('basic', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(150, 20);
      final barrier = Barrier();

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      barrier.setDebugName('Barrier');

      root.add(a);
      root.add(b);
      root.add(barrier);

      barrier.setBarrierType(Barrier.left);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 50);

      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 20);

      barrier.add(a);
      barrier.add(b);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();

      expect(barrier.getLeft(), b.getLeft());

      barrier.setBarrierType(Barrier.right);
      root.layout();
      expect(barrier.getRight(), b.getRight());

      barrier.setBarrierType(Barrier.left);
      b.setWidth(10);
      root.layout();
      expect(barrier.getLeft(), a.getLeft());
    });

    test('basic2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(150, 20);
      final barrier = Barrier();

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      barrier.setDebugName('Barrier');

      root.add(a);
      root.add(b);
      root.add(barrier);

      barrier.setBarrierType(Barrier.bottom);

      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.top, barrier, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      barrier.add(a);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();

      expect(barrier.getTop(), a.getBottom());
      final actual = barrier.getBottom() +
          (root.getBottom() - barrier.getBottom() - b.getHeight()) / 2.0;
      // closeTo mirrors upstream's assertEquals delta (BarrierTest.java 510).
      expect(b.getTop(), closeTo(actual, 1));
    });

    test('basic3', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(150, 20);
      final barrier = Barrier();

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      barrier.setDebugName('Barrier');

      root.add(a);
      root.add(b);
      root.add(barrier);

      barrier.setBarrierType(Barrier.right);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      b.connect(ConstraintAnchorType.left, barrier, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      barrier.add(a);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(barrier.getRight(), a.getRight());
      expect(root.getWidth(), a.getWidth() + b.getWidth());
    });

    test('basic4', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final barrier = Barrier();

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      barrier.setDebugName('Barrier');

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(barrier);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.setVisibility(ConstraintWidget.GONE);

      c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.top, barrier, ConstraintAnchorType.top);

      barrier.add(a);
      barrier.add(b);

      barrier.setBarrierType(Barrier.bottom);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();

      expect(b.getTop(), a.getBottom());
      expect(barrier.getTop(), b.getBottom());
      expect(c.getTop(), barrier.getTop());
    });

    test('growArray', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(150, 20);
      final c = ConstraintWidget.size(175, 20);
      final d = ConstraintWidget.size(200, 20);
      final e = ConstraintWidget.size(125, 20);
      final barrier = Barrier();

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      e.setDebugName('E');
      barrier.setDebugName('Barrier');

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);
      root.add(e);
      root.add(barrier);

      barrier.setBarrierType(Barrier.left);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 50);

      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 20);

      c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom, 20);

      d.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      d.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      d.connect(ConstraintAnchorType.top, c, ConstraintAnchorType.bottom, 20);

      e.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      e.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      e.connect(ConstraintAnchorType.top, d, ConstraintAnchorType.bottom, 20);

      barrier.add(a);
      barrier.add(b);
      barrier.add(c);
      barrier.add(d);
      barrier.add(e);

      root.layout();

      // closeTo mirrors upstream's assertEquals delta (BarrierTest.java
      // 651-655): Java lays C and E out one pixel right of the integer
      // division (313 and 338).
      expect(a.getLeft(), closeTo((root.getWidth() - a.getWidth()) ~/ 2, 1));
      expect(b.getLeft(), closeTo((root.getWidth() - b.getWidth()) ~/ 2, 1));
      expect(c.getLeft(), closeTo((root.getWidth() - c.getWidth()) ~/ 2, 1));
      expect(d.getLeft(), closeTo((root.getWidth() - d.getWidth()) ~/ 2, 1));
      expect(e.getLeft(), closeTo((root.getWidth() - e.getWidth()) ~/ 2, 1));
      expect(barrier.getLeft(), d.getLeft());
    });

    test('connection', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(150, 20);
      final c = ConstraintWidget.size(100, 20);
      final barrier = Barrier();

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      barrier.setDebugName('Barrier');

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(barrier);

      barrier.setBarrierType(Barrier.left);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 50);

      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 20);

      c.connect(ConstraintAnchorType.left, barrier, ConstraintAnchorType.left, 0);
      barrier.add(a);
      barrier.add(b);

      root.layout();

      expect(barrier.getLeft(), b.getLeft());
      expect(c.getLeft(), barrier.getLeft());
    });

    test('withGuideline', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final barrier = Barrier();
      final guideline = Guideline();

      root.setDebugName('root');
      a.setDebugName('A');
      barrier.setDebugName('Barrier');
      guideline.setDebugName('Guideline');

      guideline.setOrientation(ConstraintWidget.VERTICAL);
      guideline.setGuideBegin(200);
      barrier.setBarrierType(Barrier.right);

      root.add(a);
      root.add(barrier);
      root.add(guideline);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 50);

      barrier.add(a);
      barrier.add(guideline);

      root.layout();

      expect(barrier.getLeft(), guideline.getLeft());
    });

    test('wrapIssue', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final barrier = Barrier();
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      barrier.setDebugName('Barrier');
      barrier.setBarrierType(Barrier.bottom);

      root.add(a);
      root.add(b);
      root.add(barrier);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 0);

      barrier.add(a);

      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      b.connect(ConstraintAnchorType.top, barrier, ConstraintAnchorType.bottom, 0);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 0);

      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(barrier.getTop(), a.getBottom());
      expect(b.getTop(), barrier.getBottom());
      expect(root.getHeight(), a.getHeight() + b.getHeight());

      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);

      root.layout();

      expect(barrier.getTop(), a.getBottom());
      expect(b.getTop(), barrier.getBottom());
      expect(root.getHeight(), a.getHeight() + b.getHeight());
    });
  });
}
