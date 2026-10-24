// Copyright (C) 2021 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.WrapTest
// (upstream pinned in UPSTREAM.md).

import 'dart:math' as math;

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  group('WrapTest', () {
    test('testBasic', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.layout();

      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 100, 0);
      a.setVerticalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 60, 0);
      root.layout();
    });

    test('testBasic2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
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
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 100, 1);
      b.setVerticalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 60, 1);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();
      expect(root.getWidth(), 200);
      expect(root.getHeight(), 40);

      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 20, 100, 1);
      b.setVerticalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 30, 60, 1);
      root.setWidth(0);
      root.setHeight(0);
      root.layout();
      expect(root.getWidth(), 220);
      expect(root.getHeight(), 70);
    });

    test('testRatioWrap', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 100, 600);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('1:1');

      root.setHeight(0);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();
      expect(root.getWidth(), 100);
      expect(root.getHeight(), 100);

      root.setHeight(600);
      root.setWidth(0);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      root.layout();
      expect(root.getWidth(), 600);
      expect(root.getHeight(), 600);

      root.setWidth(100);
      root.setHeight(600);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.layout();
      expect(root.getWidth(), 0);
      expect(root.getHeight(), 0);
    });

    test('testRatioWrap2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setDimensionRatioString('1:1');

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();
      expect(root.getWidth(), 100);
      expect(root.getHeight(), 120);
    });

    test('testRatioWrap3', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 500, 600);
      final a = ConstraintWidget.size(100, 60);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.add(a);
      root.add(b);
      root.add(c);

      a.setBaselineDistance(100);
      b.setBaselineDistance(10);
      c.setBaselineDistance(10);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      a.setVerticalBiasPercent(0);

      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.baseline, a, ConstraintAnchorType.baseline);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);

      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.baseline, b, ConstraintAnchorType.baseline);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('1:1');

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();

      expect(a.getWidth(), 300);
      expect(a.getHeight(), 300);
      expect(b.getLeft(), 300);
      expect(b.getTop(), 90);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 20);
      expect(c.getLeft(), 400);
      expect(c.getTop(), 90);
      expect(c.getWidth(), 100);
      expect(c.getHeight(), 20);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      a.setBaselineDistance(10);

      root.layout();
      expect(root.getWidth(), 220);
      expect(root.getHeight(), 20);
    });

    test('testGoneChainWrap', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 500, 600);
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
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      d.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, d, ConstraintAnchorType.top);
      d.connect(ConstraintAnchorType.top, c, ConstraintAnchorType.bottom);
      d.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      d.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();
      expect(root.getHeight(), 40);

      a.setVerticalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
      expect(root.getHeight(), 40);
    });

    test('testWrap', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 500, 600);
      final a = ConstraintWidget.size(100, 0);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final d = ConstraintWidget.size(100, 40);
      final e = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
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

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      d.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);

      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      d.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);

      e.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      e.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      e.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();
      expect(root.getHeight(), 80);
      expect(e.getTop(), 30);
    });

    test('testWrap2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 500, 600);
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
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      d.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      d.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.connect(ConstraintAnchorType.top, c, ConstraintAnchorType.bottom, 30);
      a.connect(ConstraintAnchorType.bottom, d, ConstraintAnchorType.top, 40);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(c.getTop(), 0);
      expect(a.getTop(), c.getBottom() + 30);
      expect(d.getTop(), a.getBottom() + 40);
      expect(root.getHeight(), 20 + 30 + 20 + 40 + 20);
    });

    test('testWrap3', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 500, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 200);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left, 250);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(root.getWidth(), a.getWidth() + 200);
      expect(a.getLeft(), 0);
      expect(b.getLeft(), 250);
      expect(b.getWidth(), 100);
      expect(b.getRight() > root.getWidth(), isTrue);
    });

    test('testWrap4', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 500, 600);
      final a = ConstraintWidget.size(80, 80);
      final b = ConstraintWidget.size(60, 60);
      final c = ConstraintWidget.size(50, 100);
      final barrier1 = Barrier();
      barrier1.setBarrierType(Barrier.bottom);
      final barrier2 = Barrier();
      barrier2.setBarrierType(Barrier.bottom);

      barrier1.add(a);
      barrier1.add(b);

      barrier2.add(c);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      barrier1.setDebugName('B1');
      barrier2.setDebugName('B2');

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(barrier1);
      root.add(barrier2);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, barrier1, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.bottom, barrier1, ConstraintAnchorType.bottom);

      c.connect(ConstraintAnchorType.top, barrier1, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, barrier2, ConstraintAnchorType.top);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);

      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(a.getTop() >= 0, isTrue);
      expect(b.getTop() >= 0, isTrue);
      expect(c.getTop() >= 0, isTrue);
      expect(root.getHeight(), math.max(a.getHeight(), b.getHeight()) + c.getHeight());
    });

    test('testWrap5', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 500, 600);
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

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 8);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 8);

      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 8);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 8);

      c.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);
      d.setHorizontalBiasPercent(0.557);
      d.setVerticalBiasPercent(0.8);

      d.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      d.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      d.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      d.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);
      d.setHorizontalBiasPercent(0.557);
      d.setVerticalBiasPercent(0.28);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
    });

    test('testWrap6', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 500, 600);
      final a = ConstraintWidget.size(100, 20);
      final guideline = Guideline();
      guideline.setOrientation(ConstraintWidget.VERTICAL);
      guideline.setGuidePercent(0.5);
      root.setDebugName('root');
      a.setDebugName('A');
      guideline.setDebugName('guideline');

      root.add(a);
      root.add(guideline);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 8);
      a.connect(ConstraintAnchorType.left, guideline, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getWidth(), a.getWidth() * 2);
      expect(root.getHeight(), a.getHeight() + 8);
      expect(guideline.getLeft(), closeTo(root.getWidth() / 2, 0));
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
    });

    test('testWrap7', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 500, 600);
      final a = ConstraintWidget.size(100, 20);
      final divider = ConstraintWidget.size(1, 20);
      final guideline = Guideline();
      guideline.setOrientation(ConstraintWidget.VERTICAL);
      guideline.setGuidePercent(0.5);
      root.setDebugName('root');
      a.setDebugName('A');
      divider.setDebugName('divider');
      guideline.setDebugName('guideline');

      root.add(a);
      root.add(divider);
      root.add(guideline);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      a.connect(ConstraintAnchorType.left, guideline, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);

      divider.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      divider.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      divider.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      divider.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      divider.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getWidth(), a.getWidth() * 2);
      expect(root.getHeight(), a.getHeight());
      expect(guideline.getLeft(), closeTo(root.getWidth() / 2, 0));
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
    });

    test('testWrap8', () {
      // check_048
      final root = ConstraintWidgetContainer.rect(0, 0, 1080, 1080);
      final button56 = ConstraintWidget.size(231, 126);
      final button60 = ConstraintWidget.size(231, 126);
      final button63 = ConstraintWidget.size(368, 368);
      final button65 = ConstraintWidget.size(231, 126);

      button56.setDebugName('button56');
      button60.setDebugName('button60');
      button63.setDebugName('button63');
      button65.setDebugName('button65');

      root.add(button56);
      root.add(button60);
      root.add(button63);
      root.add(button65);

      button56.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 42);
      button56.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 42);

      button60.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 42);
      button60.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 79);

      button63.connect(ConstraintAnchorType.left, button56, ConstraintAnchorType.right, 21);
      button63.connect(ConstraintAnchorType.right, button60, ConstraintAnchorType.left, 21);
      button63.connect(ConstraintAnchorType.top, button56, ConstraintAnchorType.bottom, 21);
      button63.connect(ConstraintAnchorType.bottom, button60, ConstraintAnchorType.top, 21);
      button63.setVerticalBiasPercent(0.8);

      button65.connect(ConstraintAnchorType.left, button56, ConstraintAnchorType.right, 21);
      button65.connect(ConstraintAnchorType.right, button60, ConstraintAnchorType.left, 21);
      button65.connect(ConstraintAnchorType.top, button56, ConstraintAnchorType.bottom, 21);
      button65.connect(ConstraintAnchorType.bottom, button60, ConstraintAnchorType.top, 21);
      button65.setVerticalBiasPercent(0.28);

      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getWidth(), 1080);
      expect(root.getHeight(), 783);
      expect(button56.getLeft(), 42);
      expect(button56.getTop(), 42);
      expect(button60.getLeft(), 807);
      expect(button60.getTop(), 578);
      expect(button63.getLeft(), 356);
      expect(button63.getTop(), 189);
      expect(button65.getLeft(), 425);
      expect(button65.getTop(), 257);
    });

    test('testWrap9', () {
      // b/161826272
      final root = ConstraintWidgetContainer.rect(0, 0, 1080, 1080);
      final text = ConstraintWidget.size(270, 30);
      final view = ConstraintWidget.size(10, 10);

      root.setDebugName('root');
      text.setDebugName('text');
      view.setDebugName('view');

      root.add(text);
      root.add(view);

      text.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      text.connect(ConstraintAnchorType.top, view, ConstraintAnchorType.top);

      view.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      view.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      view.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      view.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      view.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      view.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      view.setVerticalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_PERCENT, 0, 0, 0.2);
      view.setDimensionRatioString('1:1');

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.layout();

      expect(view.getWidth(), view.getHeight());
      expect(view.getHeight(), (0.2 * root.getHeight()).toInt());
      expect(root.getWidth(), math.max(text.getWidth(), view.getWidth()));
    });

    test('testBarrierWrap', () {
      // b/165028374

      final root = ConstraintWidgetContainer.rect(0, 0, 1080, 1080);
      final view = ConstraintWidget.size(200, 200);
      final space = ConstraintWidget.size(50, 50);
      final button = ConstraintWidget.size(100, 80);
      final text = ConstraintWidget.size(90, 30);

      final barrier = Barrier();
      barrier.setBarrierType(Barrier.bottom);
      barrier.add(button);
      barrier.add(space);

      root.setDebugName('root');
      view.setDebugName('view');
      space.setDebugName('space');
      button.setDebugName('button');
      text.setDebugName('text');
      barrier.setDebugName('barrier');

      root.add(view);
      root.add(space);
      root.add(button);
      root.add(text);
      root.add(barrier);

      view.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      space.connect(ConstraintAnchorType.top, view, ConstraintAnchorType.bottom);
      button.connect(ConstraintAnchorType.top, view, ConstraintAnchorType.bottom);
      button.connect(ConstraintAnchorType.bottom, text, ConstraintAnchorType.top);
      text.connect(ConstraintAnchorType.top, barrier, ConstraintAnchorType.bottom);
      text.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      button.setVerticalBiasPercent(1.0);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.layout();

      expect(view.getTop(), 0);
      expect(view.getBottom(), 200);
      expect(space.getTop(), 200);
      expect(space.getBottom(), 250);
      expect(button.getTop(), 200);
      expect(button.getBottom(), 280);
      expect(barrier.getTop(), 280);
      expect(text.getTop(), barrier.getTop());
    });
  });
}
