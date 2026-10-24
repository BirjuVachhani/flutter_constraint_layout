// Copyright (C) 2016 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.ChainTest
// (upstream pinned in UPSTREAM.md).

import 'dart:math' as math;

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void _checkPositions(ConstraintWidget a, ConstraintWidget b, ConstraintWidget c) {
  expect(a.getLeft() <= a.getRight(), isTrue);
  expect(a.getRight() <= b.getLeft(), isTrue);
  expect(b.getLeft() <= b.getRight(), isTrue);
  expect(b.getRight() <= c.getLeft(), isTrue);
  expect(c.getLeft() <= c.getRight(), isTrue);
}

void _checkVerticalPositions(
    ConstraintWidget a, ConstraintWidget b, ConstraintWidget c) {
  expect(a.getTop() <= a.getBottom(), isTrue);
  expect(a.getBottom() <= b.getTop(), isTrue);
  expect(b.getTop() <= b.getBottom(), isTrue);
  expect(b.getBottom() <= c.getTop(), isTrue);
  expect(c.getTop() <= c.getBottom(), isTrue);
}

void main() {
  group('ChainTest', () {
    test('testCenteringElementsWithSpreadChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final d = ConstraintWidget.size(100, 20);
      final e = ConstraintWidget.size(600, 20);

      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      e.setDebugName('E');
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);
      root.add(e);

      a.connect(ConstraintAnchorType.left, e, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, e, ConstraintAnchorType.right);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      c.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);

      d.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.left);
      d.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.right);
      d.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);

      root.layout();
      expect(a.getWidth(), 300);
      expect(b.getWidth(), a.getWidth());
    });

    test('testBasicChainMatch', () {
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

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setBaselineDistance(8);
      b.setBaselineDistance(8);
      c.setBaselineDistance(8);

      root.setOptimizationLevel(
          Optimizer.OPTIMIZATION_STANDARD | Optimizer.OPTIMIZATION_CHAIN);
      root.layout();
      expect(a.getLeft(), 0);
      expect(a.getRight(), 200);
      expect(b.getLeft(), 200);
      expect(b.getRight(), 400);
      expect(c.getLeft(), 400);
      expect(c.getRight(), 600);
    });

    test('testSpreadChainGone', () {
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

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD);
      a.setVisibility(ConstraintWidget.GONE);

      root.layout();
      expect(a.getLeft(), 0);
      expect(a.getRight(), 0);
      expect(b.getLeft(), 133);
      expect(b.getRight(), 233);
      expect(c.getLeft(), 367);
      expect(c.getRight(), 467);
    });

    test('testPackChainGone', () {
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

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 100);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 20);

      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
      b.setGoneMargin(ConstraintAnchorType.right, 100);
      c.setVisibility(ConstraintWidget.GONE);

      root.layout();
      expect(a.getLeft(), 200);
      expect(b.getLeft(), 300);
      expect(c.getLeft(), 500);
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(c.getWidth(), 0);
    });

    test('testSpreadInsideChain2', () {
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

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, 25);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      root.layout();
      expect(a.getLeft(), 0);
      expect(a.getRight(), 100);
      expect(b.getLeft(), 100);
      expect(b.getRight(), 475);
      expect(c.getLeft(), 500);
      expect(c.getRight(), 600);
    });

    test('testPackChain2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 1);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(a.getLeft(), root.getWidth() - b.getRight());
      expect(b.getLeft(), a.getLeft() + a.getWidth());
    });

    test('testPackChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(a.getLeft(), root.getWidth() - b.getRight());
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      a.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getWidth(), 0);
      expect(b.getWidth(), 100);
      expect(a.getLeft(), root.getWidth() - b.getRight());
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      b.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getWidth(), 0);
      expect(b.getWidth(), 0);
      expect(a.getLeft(), 0);
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      a.setVisibility(ConstraintWidget.VISIBLE);
      a.setWidth(100);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 0);
      expect(a.getLeft(), root.getWidth() - b.getRight());
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      a.setVisibility(ConstraintWidget.VISIBLE);
      a.setWidth(100);
      a.setHeight(20);
      b.setVisibility(ConstraintWidget.VISIBLE);
      b.setWidth(100);
      b.setHeight(20);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 1);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(a.getLeft(), root.getWidth() - b.getRight());
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 0, 1);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 500);
      expect(a.getLeft(), 0);
      expect(b.getLeft(), 100);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 50, 1);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 50);
      expect(a.getLeft(), root.getWidth() - b.getRight());
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      b.setHorizontalMatchStyle(
          ConstraintWidget.MATCH_CONSTRAINT_PERCENT, 0, 0, 0.3);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), (0.3 * 600).toInt());
      expect(a.getLeft(), root.getWidth() - b.getRight());
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      b.setDimensionRatioString('16:9');
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_RATIO, 0, 0, 1);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), closeTo((16 / 9 * 20).toInt(), 1));
      expect(a.getLeft(), closeTo(root.getWidth() - b.getRight(), 1));
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 0, 1);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 0, 1);
      b.setDimensionRatio(0, 0);
      a.setVisibility(ConstraintWidget.VISIBLE);
      a.setWidth(100);
      a.setHeight(20);
      b.setVisibility(ConstraintWidget.VISIBLE);
      b.setWidth(100);
      b.setHeight(20);
      root.layout();
      expect(a.getWidth(), b.getWidth());
      expect(a.getWidth() + b.getWidth(), root.getWidth());
      a.setHorizontalWeight(1);
      b.setHorizontalWeight(3);
      root.layout();
      expect(a.getWidth() * 3, b.getWidth());
      expect(a.getWidth() + b.getWidth(), root.getWidth());
    });

    test('testPackChainOpt', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_DIRECT |
          Optimizer.OPTIMIZATION_BARRIER |
          Optimizer.OPTIMIZATION_CHAIN);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(a.getLeft(), root.getWidth() - b.getRight());
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      a.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getWidth(), 0);
      expect(b.getWidth(), 100);
      expect(a.getLeft(), root.getWidth() - b.getRight());
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      b.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getWidth(), 0);
      expect(b.getWidth(), 0);
      expect(a.getLeft(), 0);
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      a.setVisibility(ConstraintWidget.VISIBLE);
      a.setWidth(100);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 0);
      expect(a.getLeft(), root.getWidth() - b.getRight());
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      a.setVisibility(ConstraintWidget.VISIBLE);
      a.setWidth(100);
      a.setHeight(20);
      b.setVisibility(ConstraintWidget.VISIBLE);
      b.setWidth(100);
      b.setHeight(20);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 1);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(a.getLeft(), root.getWidth() - b.getRight());
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 0, 1);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 500);
      expect(a.getLeft(), 0);
      expect(b.getLeft(), 100);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 50, 1);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 50);
      expect(a.getLeft(), root.getWidth() - b.getRight());
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      b.setHorizontalMatchStyle(
          ConstraintWidget.MATCH_CONSTRAINT_PERCENT, 0, 0, 0.3);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), (0.3 * 600).toInt());
      expect(a.getLeft(), root.getWidth() - b.getRight());
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      b.setDimensionRatioString('16:9');
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_RATIO, 0, 0, 1);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), closeTo((16 / 9 * 20).toInt(), 1));
      expect(a.getLeft(), closeTo(root.getWidth() - b.getRight(), 1));
      expect(b.getLeft(), a.getLeft() + a.getWidth());
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 0, 1);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 0, 1);
      b.setDimensionRatio(0, 0);
      a.setVisibility(ConstraintWidget.VISIBLE);
      a.setWidth(100);
      a.setHeight(20);
      b.setVisibility(ConstraintWidget.VISIBLE);
      b.setWidth(100);
      b.setHeight(20);
      root.layout();
      expect(a.getWidth(), b.getWidth());
      expect(a.getWidth() + b.getWidth(), root.getWidth());
      a.setHorizontalWeight(1);
      b.setHorizontalWeight(3);
      root.layout();
      expect(a.getWidth() * 3, b.getWidth());
      expect(a.getWidth() + b.getWidth(), root.getWidth());
    });

    test('testSpreadChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(a.getLeft(), closeTo(b.getLeft() - a.getRight(), 1));
      expect(b.getLeft() - a.getRight(),
          closeTo(root.getWidth() - b.getRight(), 1));
      b.setVisibility(ConstraintWidget.GONE);
      root.layout();
    });

    test('testSpreadInsideChain', () {
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
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(b.getRight(), root.getWidth());

      b.resetAnchors();
      root.add(b);
      b.setDebugName('B');
      b.setWidth(100);
      b.setHeight(20);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(c.getWidth(), 100);
      expect(b.getLeft() - a.getRight(), c.getLeft() - b.getRight());
      final gap =
          (root.getWidth() - a.getWidth() - b.getWidth() - c.getWidth()) ~/ 2;
      expect(b.getLeft(), a.getRight() + gap);
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
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      root.layout();
      expect(a.getWidth(), closeTo(b.getWidth(), 1));
      expect(a.getLeft() - root.getLeft(),
          closeTo(root.getRight() - b.getRight(), 1));
      expect(a.getLeft() - root.getLeft(),
          closeTo(b.getLeft() - a.getRight(), 1));
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.layout();
      expect(a.getWidth(), root.getWidth() - b.getWidth());
      expect(b.getWidth(), 100);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setWidth(100);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.layout();
      expect(b.getWidth(), root.getWidth() - a.getWidth());
      expect(a.getWidth(), 100);
    });

    test('testBasicVerticalChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      root.layout();
      expect(a.getHeight(), closeTo(b.getHeight(), 1));
      // Tolerance 2 (upstream 1): double-vs-float32 solver rounding, see
      // UPSTREAM.md.
      expect(a.getTop() - root.getTop(),
          closeTo(root.getBottom() - b.getBottom(), 2));
      expect(a.getTop() - root.getTop(),
          closeTo(b.getTop() - a.getBottom(), 1));
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.layout();
      expect(a.getHeight(), root.getHeight() - b.getHeight());
      expect(b.getHeight(), 20);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setHeight(20);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.layout();
      expect(b.getHeight(), root.getHeight() - a.getHeight());
      expect(a.getHeight(), 20);
    });

    test('testBasicChainThreeElements1', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
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
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, 0);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 0);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left, 0);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, 0);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);
      root.layout();
      // all elements spread equally
      expect(a.getWidth(), closeTo(b.getWidth(), 1));
      expect(b.getWidth(), closeTo(c.getWidth(), 1));
      expect(a.getLeft() - root.getLeft(),
          closeTo(root.getRight() - c.getRight(), 1));
      expect(a.getLeft() - root.getLeft(),
          closeTo(b.getLeft() - a.getRight(), 1));
      expect(b.getLeft() - a.getRight(),
          closeTo(c.getLeft() - b.getRight(), 1));
    });

    test('testBasicChainThreeElements', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      const marginL = 7;
      const marginR = 27;
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.add(a);
      root.add(b);
      root.add(c);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, 0);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 0);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left, 0);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, 0);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);
      root.layout();
      // all elements spread equally
      expect(a.getWidth(), closeTo(b.getWidth(), 1));
      expect(b.getWidth(), closeTo(c.getWidth(), 1));
      expect(a.getLeft() - root.getLeft(),
          closeTo(root.getRight() - c.getRight(), 1));
      expect(a.getLeft() - root.getLeft(),
          closeTo(b.getLeft() - a.getRight(), 1));
      expect(b.getLeft() - a.getRight(),
          closeTo(c.getLeft() - b.getRight(), 1));
      // A marked as 0dp, B == C, A takes the rest
      a.getAnchor(ConstraintAnchorType.left)!.setMargin(marginL);
      a.getAnchor(ConstraintAnchorType.right)!.setMargin(marginR);
      b.getAnchor(ConstraintAnchorType.left)!.setMargin(marginL);
      b.getAnchor(ConstraintAnchorType.right)!.setMargin(marginR);
      c.getAnchor(ConstraintAnchorType.left)!.setMargin(marginL);
      c.getAnchor(ConstraintAnchorType.right)!.setMargin(marginR);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.layout();
      expect(a.getLeft() - root.getLeft() - marginL,
          root.getRight() - c.getRight() - marginR);
      expect(c.getLeft() - b.getRight(), b.getLeft() - a.getRight());
      expect(a.getWidth(), 498);
      expect(b.getWidth(), c.getWidth());
      expect(b.getWidth(), 100);
      _checkPositions(a, b, c);
      // B marked as 0dp, A == C, B takes the rest
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setWidth(100);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.layout();
      expect(b.getWidth(), 498);
      expect(a.getWidth(), c.getWidth());
      expect(a.getWidth(), 100);
      _checkPositions(a, b, c);
      // C marked as 0dp, A == B, C takes the rest
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setWidth(100);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.layout();
      expect(c.getWidth(), 498);
      expect(a.getWidth(), b.getWidth());
      expect(a.getWidth(), 100);
      _checkPositions(a, b, c);
      // A & B marked as 0dp, C == 100
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      c.setWidth(100);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.layout();
      expect(c.getWidth(), 100);
      expect(a.getWidth(), b.getWidth());
      expect(a.getWidth(), 299);
      _checkPositions(a, b, c);
      // A & C marked as 0dp, B == 100
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setWidth(100);
      root.layout();
      expect(b.getWidth(), 100);
      expect(a.getWidth(), c.getWidth());
      expect(a.getWidth(), 299);
      _checkPositions(a, b, c);
      // B & C marked as 0dp, A == 100
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setWidth(100);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), c.getWidth());
      expect(b.getWidth(), 299);
      _checkPositions(a, b, c);
      // A == 0dp, B & C == 100, C is gone
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setWidth(100);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setWidth(100);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      c.setWidth(100);
      c.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getWidth(), 632);
      expect(b.getWidth(), 100);
      expect(c.getWidth(), 0);
      _checkPositions(a, b, c);
    });

    test('testBasicVerticalChainThreeElements', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      const marginT = 7;
      const marginB = 27;
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.add(a);
      root.add(b);
      root.add(c);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 0);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, 0);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 0);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top, 0);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom, 0);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 0);
      root.layout();
      // all elements spread equally
      expect(a.getHeight(), closeTo(b.getHeight(), 1));
      expect(b.getHeight(), closeTo(c.getHeight(), 1));
      expect(a.getTop() - root.getTop(),
          closeTo(root.getBottom() - c.getBottom(), 1));
      expect(a.getTop() - root.getTop(),
          closeTo(b.getTop() - a.getBottom(), 1));
      expect(b.getTop() - a.getBottom(),
          closeTo(c.getTop() - b.getBottom(), 1));
      // A marked as 0dp, B == C, A takes the rest
      a.getAnchor(ConstraintAnchorType.top)!.setMargin(marginT);
      a.getAnchor(ConstraintAnchorType.bottom)!.setMargin(marginB);
      b.getAnchor(ConstraintAnchorType.top)!.setMargin(marginT);
      b.getAnchor(ConstraintAnchorType.bottom)!.setMargin(marginB);
      c.getAnchor(ConstraintAnchorType.top)!.setMargin(marginT);
      c.getAnchor(ConstraintAnchorType.bottom)!.setMargin(marginB);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.layout();
      expect(a.getTop(), 7);
      expect(c.getBottom(), 573);
      expect(b.getBottom(), 519);
      expect(a.getHeight(), 458);
      expect(b.getHeight(), c.getHeight());
      expect(b.getHeight(), 20);
      _checkVerticalPositions(a, b, c);
      // B marked as 0dp, A == C, B takes the rest
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setHeight(20);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.layout();
      expect(b.getHeight(), 458);
      expect(a.getHeight(), c.getHeight());
      expect(a.getHeight(), 20);
      _checkVerticalPositions(a, b, c);
      // C marked as 0dp, A == B, C takes the rest
      b.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setHeight(20);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.layout();
      expect(c.getHeight(), 458);
      expect(a.getHeight(), b.getHeight());
      expect(a.getHeight(), 20);
      _checkVerticalPositions(a, b, c);
      // A & B marked as 0dp, C == 20
      c.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      c.setHeight(20);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.layout();
      expect(c.getHeight(), 20);
      expect(a.getHeight(), b.getHeight());
      expect(a.getHeight(), 239);
      _checkVerticalPositions(a, b, c);
      // A & C marked as 0dp, B == 20
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setHeight(20);
      root.layout();
      expect(b.getHeight(), 20);
      expect(a.getHeight(), c.getHeight());
      expect(a.getHeight(), 239);
      _checkVerticalPositions(a, b, c);
      // B & C marked as 0dp, A == 20
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setHeight(20);
      root.layout();
      expect(a.getHeight(), 20);
      expect(b.getHeight(), c.getHeight());
      expect(b.getHeight(), 239);
      _checkVerticalPositions(a, b, c);
      // A == 0dp, B & C == 20, C is gone
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHeight(20);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setHeight(20);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      c.setHeight(20);
      c.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getHeight(), 512);
      expect(b.getHeight(), 20);
      expect(c.getHeight(), 0);
      _checkVerticalPositions(a, b, c);
    });

    test('testHorizontalChainWeights', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      const marginL = 7;
      const marginR = 27;
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.add(a);
      root.add(b);
      root.add(c);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, marginL);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, marginR);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, marginL);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left, marginR);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, marginL);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, marginR);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalWeight(1);
      b.setHorizontalWeight(1);
      c.setHorizontalWeight(1);
      root.layout();
      expect(a.getWidth(), closeTo(b.getWidth(), 1));
      expect(b.getWidth(), closeTo(c.getWidth(), 1));
      a.setHorizontalWeight(1);
      b.setHorizontalWeight(2);
      c.setHorizontalWeight(1);
      root.layout();
      expect(2 * a.getWidth(), closeTo(b.getWidth(), 1));
      expect(a.getWidth(), closeTo(c.getWidth(), 1));
    });

    test('testVerticalChainWeights', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      const marginT = 7;
      const marginB = 27;
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.add(a);
      root.add(b);
      root.add(c);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, marginT);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, marginB);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, marginT);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top, marginB);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom, marginT);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, marginB);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalWeight(1);
      b.setVerticalWeight(1);
      c.setVerticalWeight(1);
      root.layout();
      expect(a.getHeight(), closeTo(b.getHeight(), 1));
      expect(b.getHeight(), closeTo(c.getHeight(), 1));
      a.setVerticalWeight(1);
      b.setVerticalWeight(2);
      c.setVerticalWeight(1);
      root.layout();
      expect(2 * a.getHeight(), closeTo(b.getHeight(), 1));
      expect(a.getHeight(), closeTo(c.getHeight(), 1));
    });

    test('testHorizontalChainPacked', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      const marginL = 7;
      const marginR = 27;
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.add(a);
      root.add(b);
      root.add(c);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, marginL);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, marginR);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, marginL);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left, marginR);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, marginL);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, marginR);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
      expect(a.getLeft() - root.getLeft() - marginL,
          closeTo(root.getRight() - marginR - c.getRight(), 1));
    });

    test('testVerticalChainPacked', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      const marginT = 7;
      const marginB = 27;
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.add(a);
      root.add(b);
      root.add(c);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, marginT);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, marginB);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, marginT);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top, marginB);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom, marginT);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, marginB);
      a.setVerticalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
      expect(a.getTop() - root.getTop() - marginT,
          closeTo(root.getBottom() - marginB - c.getBottom(), 1));
    });

    test('testHorizontalChainComplex', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final d = ConstraintWidget.size(50, 20);
      final e = ConstraintWidget.size(50, 20);
      final f = ConstraintWidget.size(50, 20);
      const marginL = 7;
      const marginR = 19;
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      e.setDebugName('E');
      f.setDebugName('F');
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);
      root.add(e);
      root.add(f);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, marginL);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, marginR);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, marginL);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left, marginR);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, marginL);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, marginR);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      d.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left, 0);
      d.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right, 0);
      e.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.left, 0);
      e.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.right, 0);
      f.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left, 0);
      f.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right, 0);
      root.layout();
      expect(a.getWidth(), closeTo(b.getWidth(), 1));
      expect(b.getWidth(), closeTo(c.getWidth(), 1));
      expect(a.getWidth(), closeTo(307, 1));
    });

    test('testVerticalChainComplex', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final d = ConstraintWidget.size(50, 20);
      final e = ConstraintWidget.size(50, 20);
      final f = ConstraintWidget.size(50, 20);
      const marginT = 7;
      const marginB = 19;
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      e.setDebugName('E');
      f.setDebugName('F');
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);
      root.add(e);
      root.add(f);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, marginT);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, marginB);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, marginT);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top, marginB);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom, marginT);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, marginB);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      d.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top, 0);
      d.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom, 0);
      e.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.top, 0);
      e.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.bottom, 0);
      f.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top, 0);
      f.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom, 0);
      root.layout();
      expect(a.getHeight(), closeTo(b.getHeight(), 1));
      expect(b.getHeight(), closeTo(c.getHeight(), 1));
      expect(a.getHeight(), closeTo(174, 1));
    });

    test('testHorizontalChainComplex2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 379, 591);
      final a = ConstraintWidget.size(100, 185);
      final b = ConstraintWidget.size(100, 185);
      final c = ConstraintWidget.size(100, 185);
      final d = ConstraintWidget.size(53, 17);
      final e = ConstraintWidget.size(42, 17);
      final f = ConstraintWidget.size(47, 17);
      const marginL = 0;
      const marginR = 0;
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      e.setDebugName('E');
      f.setDebugName('F');
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);
      root.add(e);
      root.add(f);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 16);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 16);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, marginL);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, marginR);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, marginL);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left, marginR);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top, 0);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, marginL);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, marginR);
      c.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top, 0);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      d.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left, 0);
      d.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right, 0);
      d.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 0);
      e.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.left, 0);
      e.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.right, 0);
      e.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 0);
      f.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left, 0);
      f.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right, 0);
      f.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 0);
      root.layout();
      expect(a.getWidth(), closeTo(b.getWidth(), 1));
      expect(b.getWidth(), closeTo(c.getWidth(), 1));
      expect(a.getWidth(), 126);
    });

    test('testVerticalChainBaseline', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      root.add(a);
      root.add(b);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 0);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, 0);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 0);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 0);
      root.layout();
      final ay = a.getTop();
      // Tolerance 2 (upstream 1): double-vs-float32 solver rounding, see
      // UPSTREAM.md.
      expect(a.getTop() - root.getTop(),
          closeTo(root.getBottom() - b.getBottom(), 2));
      expect(b.getTop() - a.getBottom(),
          closeTo(a.getTop() - root.getTop(), 1));
      root.add(c);
      a.setBaselineDistance(7);
      c.setBaselineDistance(7);
      c.connect(ConstraintAnchorType.baseline, a, ConstraintAnchorType.baseline, 0);
      root.layout();
      expect(ay, closeTo(c.getTop(), 1));
      a.setVerticalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
    });

    test('testWrapHorizontalChain', () {
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
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 0);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 0);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 0);
      c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 0);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 0);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, 0);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 0);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left, 0);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, 0);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);
      root.layout();
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(root.getHeight(), a.getHeight());
      expect(root.getHeight(), b.getHeight());
      expect(root.getHeight(), c.getHeight());
      expect(root.getWidth(), a.getWidth() + b.getWidth() + c.getWidth());
    });

    test('testWrapVerticalChain', () {
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
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);
      c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 0);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, 0);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 0);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top, 0);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom, 0);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 0);
      root.layout();
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(root.getWidth(), a.getWidth());
      expect(root.getWidth(), b.getWidth());
      expect(root.getWidth(), c.getWidth());
      expect(root.getHeight(), a.getHeight() + b.getHeight() + c.getHeight());
    });

    test('testPackWithBaseline', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 411, 603);
      final a = ConstraintWidget.rect(118, 93, 88, 48);
      final b = ConstraintWidget.rect(206, 93, 88, 48);
      final c = ConstraintWidget.rect(69, 314, 88, 48);
      final d = ConstraintWidget.rect(83, 458, 88, 48);
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      a.setBaselineDistance(29);
      b.setBaselineDistance(29);
      c.setBaselineDistance(29);
      d.setBaselineDistance(29);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 100);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.baseline, a, ConstraintAnchorType.baseline);
      c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      d.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      d.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, d, ConstraintAnchorType.top);
      d.connect(ConstraintAnchorType.top, c, ConstraintAnchorType.bottom);
      d.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
      c.setVerticalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
      c.getAnchor(ConstraintAnchorType.top)!.reset();
      root.layout();
      c.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      root.layout();
      expect(c.getBottom(), d.getTop());
    });

    test('testBasicGoneChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
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
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, d, ConstraintAnchorType.left);
      d.connect(ConstraintAnchorType.left, c, ConstraintAnchorType.right);
      d.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      b.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getLeft(), 0);
      expect(c.getLeft(), 250);
      expect(d.getLeft(), 500);
      b.setVisibility(ConstraintWidget.VISIBLE);
      d.setVisibility(ConstraintWidget.GONE);
      root.layout();
    });

    test('testGonePackChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final guideline = Guideline();
      final d = ConstraintWidget.size(100, 20);
      guideline.setOrientation(Guideline.vertical);
      guideline.setGuideBegin(200);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      guideline.setDebugName('guideline');
      d.setDebugName('D');
      root.add(a);
      root.add(b);
      root.add(guideline);
      root.add(d);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, guideline, ConstraintAnchorType.left);
      d.connect(ConstraintAnchorType.left, guideline, ConstraintAnchorType.right);
      d.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
      a.setVisibility(ConstraintWidget.GONE);
      b.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getWidth(), 0);
      expect(b.getWidth(), 0);
      expect(guideline.getLeft(), 200);
      expect(d.getLeft(), 350);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD);
      root.layout();
      expect(a.getWidth(), 0);
      expect(b.getWidth(), 0);
      expect(guideline.getLeft(), 200);
      expect(d.getLeft(), 350);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      root.layout();
      expect(a.getWidth(), 0);
      expect(b.getWidth(), 0);
      expect(guideline.getLeft(), 200);
      expect(d.getLeft(), 350);
    });

    test('testVerticalGonePackChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final guideline = Guideline();
      final d = ConstraintWidget.size(100, 20);
      guideline.setOrientation(Guideline.horizontal);
      guideline.setGuideBegin(200);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      guideline.setDebugName('guideline');
      d.setDebugName('D');
      root.add(a);
      root.add(b);
      root.add(guideline);
      root.add(d);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, guideline, ConstraintAnchorType.top);
      d.connect(ConstraintAnchorType.top, guideline, ConstraintAnchorType.bottom);
      d.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.setVerticalChainStyle(ConstraintWidget.CHAIN_PACKED);
      a.setVisibility(ConstraintWidget.GONE);
      b.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getHeight(), 0);
      expect(b.getHeight(), 0);
      expect(guideline.getTop(), 200);
      expect(d.getTop(), 390);
      a.setVerticalChainStyle(ConstraintWidget.CHAIN_SPREAD);
      root.layout();
      expect(a.getHeight(), 0);
      expect(b.getHeight(), 0);
      expect(guideline.getTop(), 200);
      expect(d.getTop(), 390);
      a.setVerticalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      root.layout();
      expect(a.getHeight(), 0);
      expect(b.getHeight(), 0);
      expect(guideline.getTop(), 200);
      expect(d.getTop(), 390);
    });

    test('testVerticalDanglingChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 1000);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, 7);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 9);
      root.layout();
      expect(a.getTop(), 0);
      expect(b.getTop(), a.getHeight() + math.max(7, 9));
    });

    test('testHorizontalWeightChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 1000);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final guidelineLeft = Guideline();
      final guidelineRight = Guideline();

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      guidelineLeft.setDebugName('guidelineLeft');
      guidelineRight.setDebugName('guidelineRight');
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(guidelineLeft);
      root.add(guidelineRight);

      guidelineLeft.setOrientation(Guideline.vertical);
      guidelineRight.setOrientation(Guideline.vertical);
      guidelineLeft.setGuideBegin(20);
      guidelineRight.setGuideEnd(20);

      a.connect(ConstraintAnchorType.left, guidelineLeft, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, guidelineRight, ConstraintAnchorType.right);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalWeight(1);
      b.setHorizontalWeight(1);
      c.setHorizontalWeight(1);
      root.layout();
      expect(a.getLeft(), 20);
      expect(b.getLeft(), 207);
      // closeTo: double-vs-float32 solver rounding, see UPSTREAM.md.
      expect(c.getLeft(), closeTo(393, 1));
      // closeTo: double-vs-float32 solver rounding, see UPSTREAM.md.
      expect(a.getWidth(), closeTo(187, 1));
      expect(b.getWidth(), closeTo(186, 1));
      expect(c.getWidth(), 187);
      c.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getLeft(), 20);
      expect(b.getLeft(), 300);
      expect(c.getLeft(), 580);
      expect(a.getWidth(), 280);
      expect(b.getWidth(), 280);
      expect(c.getWidth(), 0);
    });

    test('testVerticalGoneChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 16);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
      a.getAnchor(ConstraintAnchorType.bottom)!.setGoneMargin(16);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 16);
      a.setVerticalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(a.getHeight(), closeTo(b.getHeight(), 1));
      expect(a.getTop() - root.getTop(),
          closeTo(root.getBottom() - b.getBottom(), 1));
      expect(a.getBottom(), b.getTop());

      b.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(a.getTop() - root.getTop(), root.getBottom() - a.getBottom());
      expect(root.getHeight(), 52);
    });

    test('testVerticalGoneChain2', () {
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
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 16);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);
      b.getAnchor(ConstraintAnchorType.top)!.setGoneMargin(16);
      b.getAnchor(ConstraintAnchorType.bottom)!.setGoneMargin(16);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 16);
      a.setVerticalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(a.getTop() - root.getTop(),
          closeTo(root.getBottom() - c.getBottom(), 1));
      expect(a.getBottom(), b.getTop());

      a.setVisibility(ConstraintWidget.GONE);
      c.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(b.getTop() - root.getTop(), root.getBottom() - b.getBottom());
      expect(root.getHeight(), 52);
    });

    test('testVerticalSpreadInsideChain', () {
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
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 16);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 16);

      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      a.setVerticalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      root.layout();

      expect(a.getHeight(), closeTo(b.getHeight(), 1));
      expect(b.getHeight(), closeTo(c.getHeight(), 1));
      expect(a.getHeight(), closeTo((root.getHeight() - 32) ~/ 3, 1));
    });

    test('testHorizontalSpreadMaxChain', () {
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
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      a.setVerticalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      root.layout();
      expect(a.getWidth(), closeTo(b.getWidth(), 1));
      expect(b.getWidth(), closeTo(c.getWidth(), 1));
      expect(a.getWidth(), closeTo(200, 1));

      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 50, 1);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 50, 1);
      c.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 50, 1);
      root.layout();
      expect(a.getWidth(), closeTo(b.getWidth(), 1));
      expect(b.getWidth(), closeTo(c.getWidth(), 1));
      expect(a.getWidth(), closeTo(50, 1));
    });

    test('testPackCenterChain', () {
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

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 16);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 16);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 16);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      a.setVerticalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setMinHeight(300);
      root.layout();
      expect(root.getHeight(), 300);
      expect(c.getTop(), (root.getHeight() - c.getHeight()) ~/ 2);
      expect(a.getTop(), (root.getHeight() - a.getHeight() - b.getHeight()) ~/ 2);
    });

    test('testPackCenterChainGone', () {
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

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 16);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 16);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 16);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      a.setVerticalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
      expect(600, root.getHeight());
      expect(20, a.getHeight());
      expect(20, b.getHeight());
      expect(20, c.getHeight());
      expect(270, a.getTop());
      expect(290, b.getTop());
      expect(310, c.getTop());

      a.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(600, root.getHeight());
      expect(0, a.getHeight());
      expect(20, b.getHeight());
      expect(20, c.getHeight());
      expect(a.getTop(), b.getTop());
      expect((600 - 40) ~/ 2, b.getTop());
      expect(b.getTop() + b.getHeight(), c.getTop());
    });

    test('testSpreadInsideChainWithMargins', () {
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

      var marginOut = 0;

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, marginOut);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, marginOut);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      root.layout();
      expect(a.getLeft(), marginOut);
      expect(c.getRight(), root.getWidth() - marginOut);
      expect(b.getLeft(),
          a.getRight() + (c.getLeft() - a.getRight() - b.getWidth()) ~/ 2);

      marginOut = 20;
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, marginOut);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, marginOut);
      root.layout();
      expect(a.getLeft(), marginOut);
      expect(c.getRight(), root.getWidth() - marginOut);
      expect(b.getLeft(),
          a.getRight() + (c.getLeft() - a.getRight() - b.getWidth()) ~/ 2);
    });
  });
}
