// Copyright (C) 2016 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.AdvancedChainTest
// (upstream pinned in UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  group('AdvancedChainTest', () {
    test('testComplexChainWeights', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 800);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 0);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, 0);

      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 0);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 0);

      root.add(a);
      root.add(b);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();

      expect(a.getWidth(), 800);
      expect(b.getWidth(), 800);
      expect(a.getHeight(), 400);
      expect(b.getHeight(), 400);
      expect(a.getTop(), 0);
      expect(b.getTop(), 400);

      a.setDimensionRatioString('16:3');

      root.layout();

      expect(a.getWidth(), 800);
      expect(b.getWidth(), 800);
      expect(a.getHeight(), 150);
      expect(b.getHeight(), 150);
      expect(a.getTop(), 167);
      expect(b.getTop(), 483);

      b.setVerticalWeight(1);

      root.layout();

      expect(a.getWidth(), 800);
      expect(b.getWidth(), 800);
      expect(a.getHeight(), 150);
      expect(b.getHeight(), 650);
      expect(a.getTop(), 0);
      expect(b.getTop(), 150);

      a.setVerticalWeight(1);

      root.layout();

      expect(a.getWidth(), 800);
      expect(b.getWidth(), 800);
      expect(a.getHeight(), 150);
      expect(b.getHeight(), 150);
      expect(a.getTop(), 167);
      expect(b.getTop(), 483);
    });

    test('testTooSmall', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 800);
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

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 100);
      c.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 100);

      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();

      expect(a.getTop(), 390);
      expect(b.getTop(), 380);
      expect(c.getTop(), 400);
    });

    test('testChainWeights', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 800);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, 0);

      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 0);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);

      root.add(a);
      root.add(b);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalWeight(1);
      b.setHorizontalWeight(0);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();

      expect(a.getWidth(), closeTo(800, 1));
      expect(b.getWidth(), closeTo(0, 1));
      expect(a.getLeft(), closeTo(0, 1));
      expect(b.getLeft(), closeTo(800, 1));
    });

    test('testChain3Weights', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 800);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, 0);

      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 0);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left, 0);

      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, 0);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);

      root.add(a);
      root.add(b);
      root.add(c);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      a.setHorizontalWeight(1);
      b.setHorizontalWeight(0);
      c.setHorizontalWeight(1);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();

      expect(a.getWidth(), 400);
      expect(b.getWidth(), 0);
      expect(c.getWidth(), 400);
      expect(a.getLeft(), 0);
      expect(b.getLeft(), 400);
      expect(c.getLeft(), 400);
    });

    test('testChainLastGone', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 800);
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

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);

      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);

      c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);

      d.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      d.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 0);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, 0);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 0);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top, 0);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom, 0);
      c.connect(ConstraintAnchorType.bottom, d, ConstraintAnchorType.top, 0);
      d.connect(ConstraintAnchorType.top, c, ConstraintAnchorType.bottom, 0);
      d.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 0);

      b.setVisibility(ConstraintWidget.GONE);
      d.setVisibility(ConstraintWidget.GONE);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();

      expect(a.getTop(), 253);
      expect(c.getTop(), 527);
    });

    test('testRatioChainGone', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 800);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final ratio = ConstraintWidget.size(100, 20);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      ratio.setDebugName('ratio');

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(ratio);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);

      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);

      c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);

      ratio.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 0);
      ratio.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      ratio.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 0);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, 0);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 0);
      b.connect(ConstraintAnchorType.bottom, ratio, ConstraintAnchorType.bottom, 0);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.top, 0);
      c.connect(ConstraintAnchorType.bottom, ratio, ConstraintAnchorType.bottom, 0);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      ratio.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      ratio.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      ratio.setDimensionRatioString('4:3');

      b.setVisibility(ConstraintWidget.GONE);
      c.setVisibility(ConstraintWidget.GONE);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();

      expect(a.getHeight(), 600);

      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.layout();

      expect(a.getHeight(), 600);
    });

    test('testSimpleHorizontalChainPacked', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 20);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 20);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, 0);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 0);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
      expect(a.getLeft() - root.getLeft(),
          closeTo(root.getRight() - b.getRight(), 1));
      expect(b.getLeft() - a.getRight(), closeTo(0, 1));
    });

    test('testSimpleVerticalTChainPacked', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 20);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 20);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 0);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, 0);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 0);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 0);
      a.setVerticalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
      expect(a.getTop() - root.getTop(),
          closeTo(root.getBottom() - b.getBottom(), 1));
      expect(b.getTop() - a.getBottom(), closeTo(0, 1));
    });

    test('testHorizontalChainStyles', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      root.add(a);
      root.add(b);
      root.add(c);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, 0);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 0);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left, 0);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, 0);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);
      root.layout();
      var gap =
          (root.getWidth() - a.getWidth() - b.getWidth() - c.getWidth()) ~/ 4;
      final size = 100;
      expect(a.getWidth(), size);
      expect(b.getWidth(), size);
      expect(c.getWidth(), size);
      expect(gap, a.getLeft());
      expect(a.getRight() + gap, b.getLeft());
      expect(root.getWidth() - gap - c.getWidth(), c.getLeft());
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      root.layout();
      gap = (root.getWidth() - a.getWidth() - b.getWidth() - c.getWidth()) ~/ 2;
      expect(a.getWidth(), size);
      expect(b.getWidth(), size);
      expect(c.getWidth(), size);
      expect(a.getLeft(), 0);
      expect(a.getRight() + gap, b.getLeft());
      expect(root.getWidth(), c.getRight());
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
      expect(a.getWidth(), size);
      expect(b.getWidth(), size);
      expect(c.getWidth(), size);
      expect(a.getLeft(), gap);
      expect(root.getWidth() - gap, c.getRight());
    });

    test('testVerticalChainStyles', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      root.add(a);
      root.add(b);
      root.add(c);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 0);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, 0);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 0);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top, 0);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom, 0);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 0);
      root.layout();
      var gap =
          (root.getHeight() - a.getHeight() - b.getHeight() - c.getHeight()) ~/ 4;
      final size = 20;
      expect(a.getHeight(), size);
      expect(b.getHeight(), size);
      expect(c.getHeight(), size);
      expect(gap, a.getTop());
      expect(a.getBottom() + gap, b.getTop());
      expect(root.getHeight() - gap - c.getHeight(), c.getTop());
      a.setVerticalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      root.layout();
      gap =
          (root.getHeight() - a.getHeight() - b.getHeight() - c.getHeight()) ~/ 2;
      expect(a.getHeight(), size);
      expect(b.getHeight(), size);
      expect(c.getHeight(), size);
      expect(a.getTop(), 0);
      expect(a.getBottom() + gap, b.getTop());
      expect(root.getHeight(), c.getBottom());
      a.setVerticalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
      expect(a.getHeight(), size);
      expect(b.getHeight(), size);
      expect(c.getHeight(), size);
      expect(a.getTop(), gap);
      expect(root.getHeight() - gap, c.getBottom());
    });

    test('testPacked', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.add(a);
      root.add(b);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, 0);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 0);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);
      final gap = (root.getWidth() - a.getWidth() - b.getWidth()) ~/ 2;
      final size = 100;
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
      root.setOptimizationLevel(0);
      expect(a.getWidth(), size);
      expect(b.getWidth(), size);
      expect(a.getLeft(), gap);
    });
  });
}
