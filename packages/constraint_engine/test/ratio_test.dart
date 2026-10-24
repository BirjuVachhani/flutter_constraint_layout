// Copyright (C) 2016 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.RatioTest
// (upstream pinned in UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  group('RatioTest', () {
    test('testWrapRatio', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 700, 1920);
      final a = ConstraintWidget.size(231, 126);
      final b = ConstraintWidget.size(231, 126);
      final c = ConstraintWidget.size(231, 126);

      root.setDebugName('root');
      root.add(a);
      root.add(b);
      root.add(c);

      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('1:1');
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
      a.setHorizontalBiasPercent(0.3);
      a.setVerticalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);

      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left, 171);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);

      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(a.getLeft() >= 0, true);
      expect(a.getWidth(), a.getHeight());
      expect(a.getWidth(), 402);
      expect(root.getWidth(), 402);
      expect(root.getHeight(), 654);
      expect(a.getLeft(), 0);
      expect(b.getTop(), 402);
      expect(b.getLeft(), 171);
      expect(c.getTop(), 528);
      expect(c.getLeft(), 171);
    });

    test('testGuidelineRatioChainWrap', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 700, 1920);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final guideline = Guideline();
      guideline.setOrientation(Guideline.horizontal);
      guideline.setGuideBegin(100);

      root.setDebugName('root');
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(guideline);

      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('1:1');
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, guideline, ConstraintAnchorType.top);

      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setDimensionRatioString('1:1');
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);

      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setDimensionRatioString('1:1');
      c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      root.setHeight(0);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getHeight(), 1500);

      expect(a.getWidth(), 100);
      expect(a.getHeight(), 100);

      expect(b.getWidth(), 700);
      expect(b.getHeight(), 700);

      expect(c.getWidth(), 700);
      expect(c.getHeight(), 700);

      expect(a.getTop(), 0);
      expect(b.getTop(), a.getBottom());
      expect(c.getTop(), b.getBottom());

      expect(a.getLeft(), 300);
      expect(b.getLeft(), 0);
      expect(c.getLeft(), 0);

      root.setWidth(0);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getWidth(), 100);
      expect(root.getHeight(), 300);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 100);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 100);
      expect(c.getWidth(), 100);
      expect(c.getHeight(), 100);
    });

    test('testComplexRatioChainWrap', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 700, 1920);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final d = ConstraintWidget.size(100, 40);
      final x = ConstraintWidget.size(100, 20);
      final y = ConstraintWidget.size(100, 20);
      final z = ConstraintWidget.size(100, 40);

      root.setDebugName('root');
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);
      root.add(x);
      root.add(y);
      root.add(z);

      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      x.setDebugName('X');
      y.setDebugName('Y');
      z.setDebugName('Z');

      x.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      x.connect(ConstraintAnchorType.bottom, y, ConstraintAnchorType.top);
      x.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      x.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      x.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      x.setHeight(40);

      y.connect(ConstraintAnchorType.top, x, ConstraintAnchorType.bottom);
      y.connect(ConstraintAnchorType.bottom, z, ConstraintAnchorType.top);
      y.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      y.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      y.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      y.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      y.setDimensionRatioString('1:1');

      z.connect(ConstraintAnchorType.top, y, ConstraintAnchorType.bottom);
      z.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      z.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      z.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      z.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      z.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      z.setDimensionRatioString('1:1');

      root.setWidth(700);
      root.setHeight(0);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getWidth(), 700);
      expect(root.getHeight(), 1440);

      expect(x.getLeft(), 0);
      expect(x.getTop(), 0);
      expect(x.getWidth(), 700);
      expect(x.getHeight(), 40);

      expect(y.getLeft(), 0);
      expect(y.getTop(), 40);
      expect(y.getWidth(), 700);
      expect(y.getHeight(), 700);

      expect(z.getLeft(), 0);
      expect(z.getTop(), 740);
      expect(z.getWidth(), 700);
      expect(z.getHeight(), 700);

      a.connect(ConstraintAnchorType.top, x, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.left, x, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('1:1');

      b.connect(ConstraintAnchorType.top, x, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setDimensionRatioString('1:1');

      c.connect(ConstraintAnchorType.top, x, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, d, ConstraintAnchorType.left);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setDimensionRatioString('1:1');

      d.connect(ConstraintAnchorType.top, x, ConstraintAnchorType.top);
      d.connect(ConstraintAnchorType.left, c, ConstraintAnchorType.right);
      d.connect(ConstraintAnchorType.right, x, ConstraintAnchorType.right);
      d.connect(ConstraintAnchorType.bottom, x, ConstraintAnchorType.bottom);
      d.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      d.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      d.setDimensionRatioString('1:1');

      root.setHeight(0);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getWidth(), 700);
      expect(root.getHeight(), 1440);

      expect(x.getLeft(), 0);
      expect(x.getTop(), 0);
      expect(x.getWidth(), 700);
      expect(x.getHeight(), 40);

      expect(y.getLeft(), 0);
      expect(y.getTop(), 40);
      expect(y.getWidth(), 700);
      expect(y.getHeight(), 700);

      expect(z.getLeft(), 0);
      expect(z.getTop(), 740);
      expect(z.getWidth(), 700);
      expect(z.getHeight(), 700);
    });

    test('testRatioChainWrap', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 1000);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final d = ConstraintWidget.size(100, 40);
      root.setDebugName('root');
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      d.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      d.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      d.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      d.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      d.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      a.connect(ConstraintAnchorType.left, d, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, d, ConstraintAnchorType.top);
      a.setDimensionRatioString('1:1');

      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.top, d, ConstraintAnchorType.top);
      b.setDimensionRatioString('1:1');

      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, d, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.top, d, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.bottom, d, ConstraintAnchorType.bottom);
      c.setDimensionRatioString('1:1');

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getWidth(), 120);
      expect(d.getWidth(), 120);
      expect(a.getWidth(), 40);
      expect(a.getHeight(), 40);
      expect(b.getWidth(), 40);
      expect(b.getHeight(), 40);
      expect(c.getWidth(), 40);
      expect(c.getHeight(), 40);
    });

    test('testRatioChainWrap2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 1536);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final d = ConstraintWidget.size(100, 40);
      final e = ConstraintWidget.size(100, 40);
      final f = ConstraintWidget.size(100, 40);
      root.setDebugName('root');
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);
      root.add(e);
      root.add(f);
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      e.setDebugName('E');
      f.setDebugName('F');

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      d.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      d.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      e.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      e.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      f.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      f.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      d.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      d.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      d.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      d.connect(ConstraintAnchorType.bottom, e, ConstraintAnchorType.top);

      a.connect(ConstraintAnchorType.left, d, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, d, ConstraintAnchorType.top);
      a.setDimensionRatioString('1:1');

      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.top, d, ConstraintAnchorType.top);
      b.setDimensionRatioString('1:1');

      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, d, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.top, d, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.bottom, d, ConstraintAnchorType.bottom);
      c.setDimensionRatioString('1:1');

      e.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      e.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      e.connect(ConstraintAnchorType.top, d, ConstraintAnchorType.bottom);
      e.connect(ConstraintAnchorType.bottom, f, ConstraintAnchorType.top);
      e.setDimensionRatioString('1:1');

      f.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      f.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      f.connect(ConstraintAnchorType.top, e, ConstraintAnchorType.bottom);
      f.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      f.setDimensionRatioString('1:1');

      root.layout();

      root.setWidth(0);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(d.getWidth(), root.getWidth());
      expect(a.getWidth(), d.getHeight());
      expect(a.getHeight(), d.getHeight());
      expect(b.getWidth(), d.getHeight());
      expect(b.getHeight(), d.getHeight());
      expect(c.getWidth(), d.getHeight());
      expect(c.getHeight(), d.getHeight());
    });

    test('testRatioMax', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 1000);
      final a = ConstraintWidget.size(100, 100);
      root.setDebugName('root');
      root.add(a);
      a.setDebugName('A');

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_RATIO, 0, 150, 0);
      a.setDimensionRatioString('W,16:9');

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();

      expect(a.getWidth(), 267);
      expect(a.getHeight(), 150);
      expect(a.getTop(), 425);
    });

    test('testRatioMax2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 1000);
      final a = ConstraintWidget.size(100, 100);
      root.setDebugName('root');
      root.add(a);
      a.setDebugName('A');

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_RATIO, 0, 150, 0);
      a.setDimensionRatioString('16:9');

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();

      expect(a.getWidth(), closeTo(267, 1));
      expect(a.getHeight(), 150);
      expect(a.getTop(), 425);
    });

    test('testRatioSingleTarget', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 1000);
      final a = ConstraintWidget.size(100, 100);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      root.add(a);
      root.add(b);
      a.setDebugName('A');
      b.setDebugName('B');

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setDimensionRatioString('2:3');
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left, 50);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();

      expect(b.getHeight(), 150);
      expect(b.getTop(), a.getBottom() - b.getHeight() ~/ 2);
    });

    test('testSimpleWrapRatio', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 1000);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      root.add(a);
      a.setDebugName('A');

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      a.setDimensionRatioString('1:1');
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getWidth(), 1000);
      expect(root.getHeight(), 1000);
      expect(a.getWidth(), 1000);
      expect(a.getHeight(), 1000);
    });

    test('testSimpleWrapRatio2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 1000);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      root.add(a);
      a.setDebugName('A');

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      a.setDimensionRatioString('1:1');
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getWidth(), 1000);
      expect(root.getHeight(), 1000);
      expect(a.getWidth(), 1000);
      expect(a.getHeight(), 1000);
    });

    test('testNestedRatio', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 1000);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);

      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      a.setDimensionRatioString('1:1');
      b.setDimensionRatioString('1:1');

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getWidth(), 500);
      expect(a.getWidth(), 500);
      expect(b.getWidth(), 500);
      expect(root.getHeight(), 1000);
      expect(a.getHeight(), 500);
      expect(b.getHeight(), 500);
    });

    test('testNestedRatio2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 700, 1200);
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
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);

      c.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);

      d.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left);
      d.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right);
      d.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      d.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalBiasPercent(0);

      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setVerticalBiasPercent(0.5);

      d.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      d.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      d.setVerticalBiasPercent(1);

      a.setDimensionRatioString('1:1');
      b.setDimensionRatioString('4:1');
      c.setDimensionRatioString('4:1');
      d.setDimensionRatioString('4:1');

      root.layout();

      expect(a.getWidth(), 700);
      expect(a.getHeight(), 700);
      expect(b.getWidth(), a.getWidth());
      expect(b.getHeight(), b.getWidth() ~/ 4);
      expect(b.getTop(), a.getTop());
      expect(c.getWidth(), a.getWidth());
      expect(c.getHeight(), c.getWidth() ~/ 4);
      expect(c.getTop(), closeTo((root.getHeight() - c.getHeight()) ~/ 2, 1));
      expect(d.getWidth(), a.getWidth());
      expect(d.getHeight(), d.getWidth() ~/ 4);
      expect(d.getTop(), a.getBottom() - d.getHeight());

      root.setWidth(300);
      root.layout();

      expect(a.getWidth(), root.getWidth());
      expect(a.getHeight(), root.getWidth());
      expect(b.getWidth(), a.getWidth());
      expect(b.getHeight(), b.getWidth() ~/ 4);
      expect(b.getTop(), a.getTop());
      expect(c.getWidth(), a.getWidth());
      expect(c.getHeight(), c.getWidth() ~/ 4);
      expect(c.getTop(), closeTo((root.getHeight() - c.getHeight()) ~/ 2, 1));
      expect(d.getWidth(), a.getWidth());
      expect(d.getHeight(), d.getWidth() ~/ 4);
      expect(d.getTop(), a.getBottom() - d.getHeight());

      root.setWidth(0);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getWidth() > 0, isTrue);
      expect(a.getWidth(), root.getWidth());
      expect(a.getHeight(), root.getWidth());
      expect(b.getWidth(), a.getWidth());
      expect(b.getHeight(), b.getWidth() ~/ 4);
      expect(b.getTop(), a.getTop());
      expect(c.getWidth(), a.getWidth());
      expect(c.getHeight(), c.getWidth() ~/ 4);
      expect(c.getTop(), closeTo((root.getHeight() - c.getHeight()) ~/ 2, 1));
      expect(d.getWidth(), a.getWidth());
      expect(d.getHeight(), d.getWidth() ~/ 4);
      expect(d.getTop(), a.getBottom() - d.getHeight());

      root.setWidth(700);
      root.setHeight(0);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(root.getHeight() > 0, isTrue);
      expect(a.getWidth(), root.getWidth());
      expect(a.getHeight(), root.getWidth());
      expect(b.getWidth(), a.getWidth());
      expect(b.getHeight(), b.getWidth() ~/ 4);
      expect(b.getTop(), a.getTop());
      expect(c.getWidth(), a.getWidth());
      expect(c.getHeight(), closeTo(c.getWidth() ~/ 4, 1));
      expect(c.getTop(), closeTo((root.getHeight() - c.getHeight()) ~/ 2, 1));
      expect(d.getWidth(), a.getWidth());
      expect(d.getHeight(), d.getWidth() ~/ 4);
      expect(d.getTop(), a.getBottom() - d.getHeight());
    });

    test('testNestedRatio3', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1080, 1536);
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

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('1:1');

      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setDimensionRatioString('3.5:1');

      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setDimensionRatioString('5:2');

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);
      b.setVerticalBiasPercent(0.9);

      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.bottom);
      c.setVerticalBiasPercent(0.9);

      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(a.getWidth() / a.getHeight(), closeTo(1, 0.1));
      expect(b.getWidth() / b.getHeight(), closeTo(3.5, 0.1));
      expect(c.getWidth() / c.getHeight(), closeTo(2.5, 0.1));
    });

    test('testNestedRatio4', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(264, 144);
      final b = ConstraintWidget.size(264, 144);

      final verticalGuideline = Guideline();
      verticalGuideline.setGuidePercent(0.34);
      verticalGuideline.setOrientation(Guideline.vertical);

      final horizontalGuideline = Guideline();
      horizontalGuideline.setGuidePercent(0.66);
      horizontalGuideline.setOrientation(Guideline.horizontal);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      horizontalGuideline.setDebugName('hGuideline');
      verticalGuideline.setDebugName('vGuideline');

      root.add(a);
      root.add(b);
      root.add(verticalGuideline);
      root.add(horizontalGuideline);

      a.setWidth(200);
      a.setHeight(200);
      a.connect(
          ConstraintAnchorType.bottom, horizontalGuideline, ConstraintAnchorType.bottom);
      a.connect(
          ConstraintAnchorType.left, verticalGuideline, ConstraintAnchorType.left);
      a.connect(
          ConstraintAnchorType.right, verticalGuideline, ConstraintAnchorType.right);
      a.connect(
          ConstraintAnchorType.top, horizontalGuideline, ConstraintAnchorType.top);

      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      b.setDimensionRatioString('H,1:1');
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_PERCENT, 0, 0, 0.3);
      b.connect(
          ConstraintAnchorType.bottom, horizontalGuideline, ConstraintAnchorType.bottom);
      b.connect(
          ConstraintAnchorType.left, verticalGuideline, ConstraintAnchorType.left);
      b.connect(
          ConstraintAnchorType.right, verticalGuideline, ConstraintAnchorType.right);
      b.connect(
          ConstraintAnchorType.top, horizontalGuideline, ConstraintAnchorType.top);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(verticalGuideline.getLeft(), closeTo(0.34 * root.getWidth(), 1));
      expect(horizontalGuideline.getTop(), closeTo(0.66 * root.getHeight(), 1));
      expect(a.getLeft() >= 0, isTrue);
      expect(b.getLeft() >= 0, isTrue);
      expect(a.getLeft(), verticalGuideline.getLeft() - a.getWidth() ~/ 2);
      expect(a.getTop(), horizontalGuideline.getTop() - a.getHeight() ~/ 2);

      expect(b.getLeft(), verticalGuideline.getLeft() - b.getWidth() ~/ 2);
      expect(b.getTop(), horizontalGuideline.getTop() - b.getHeight() ~/ 2);
    });

    test('testBasicCenter', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();
      expect(a.getLeft(), 450);
      expect(a.getTop(), 290);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.layout();
      expect(a.getLeft(), 450);
      expect(a.getTop(), 290);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
    });

    test('testBasicCenter2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_RATIO, 0, 150, 0);
      a.setDimensionRatioString('W,16:9');
      root.layout();
      expect(a.getLeft(), 0);
      expect(a.getWidth() / a.getHeight(), closeTo(16 / 9, 0.1));
      expect(a.getHeight(), 150);
      expect(a.getTop(), closeTo((root.getHeight() - a.getHeight()) / 2, 0));
    });

    test('testBasicRatio', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 1000);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.setVerticalBiasPercent(0);
      a.setHorizontalBiasPercent(0);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('1:1');
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();
      expect(a.getLeft(), 0);
      expect(a.getTop(), 0);
      expect(a.getWidth(), 600);
      expect(a.getHeight(), 600);
      a.setVerticalBiasPercent(1);
      root.layout();
      expect(a.getLeft(), 0);
      expect(a.getTop(), 400);
      expect(a.getWidth(), 600);
      expect(a.getHeight(), 600);

      a.setVerticalBiasPercent(0);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.layout();
      expect(a.getLeft(), 0);
      expect(a.getTop(), 0);
      expect(a.getWidth(), 600);
      expect(a.getHeight(), 600);
    });

    test('testBasicRatio2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('1:1');
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();
      expect(a.getLeft(), 450);
      expect(a.getTop(), 250);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 100);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.layout();
      expect(a.getLeft(), 450);
      expect(a.getTop(), 250);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 100);
    });

    test('testSimpleRatio', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 200, 600);
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
      a.setDimensionRatioString('3:2');
      root.layout();
      expect(a.getWidth() / a.getHeight(), closeTo(3 / 2, 0.1));
      expect(a.getTop() >= 0, isTrue);
      expect(a.getLeft() >= 0, isTrue);
      expect(a.getTop(), root.getHeight() - a.getBottom());
      expect(a.getLeft(), root.getRight() - a.getRight());
      a.setDimensionRatioString('1:2');
      root.layout();
      expect(a.getWidth() / a.getHeight(), closeTo(1 / 2, 0.1));
      expect(a.getTop() >= 0, isTrue);
      expect(a.getLeft() >= 0, isTrue);
      expect(a.getTop(), root.getHeight() - a.getBottom());
      expect(a.getLeft(), root.getRight() - a.getRight());
    });

    test('testRatioGuideline', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 400, 600);
      final a = ConstraintWidget.size(100, 20);
      final guideline = Guideline();
      guideline.setOrientation(ConstraintWidget.VERTICAL);
      guideline.setGuideBegin(200);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);
      root.add(guideline);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, guideline, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('3:2');
      root.layout();
      expect(a.getWidth() ~/ a.getHeight(), 3 ~/ 2);
      expect(a.getTop() >= 0, isTrue);
      expect(a.getLeft() >= 0, isTrue);
      expect(a.getTop(), root.getHeight() - a.getBottom());
      expect(a.getLeft(), guideline.getLeft() - a.getRight());
      a.setDimensionRatioString('1:2');
      root.layout();
      expect(a.getWidth() ~/ a.getHeight(), 1 ~/ 2);
      expect(a.getTop() >= 0, isTrue);
      expect(a.getLeft() >= 0, isTrue);
      expect(a.getTop(), root.getHeight() - a.getBottom());
      expect(a.getLeft(), guideline.getLeft() - a.getRight());
    });

    test('testRatioWithMinimum', () {
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
      a.setDimensionRatioString('16:9');
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.setWidth(0);
      root.setHeight(0);
      root.layout();
      expect(root.getWidth(), 0);
      expect(root.getHeight(), 0);
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 100, 0, 0);
      root.setWidth(0);
      root.setHeight(0);
      root.layout();
      expect(root.getWidth(), 100);
      expect(root.getHeight(), 56);
      a.setVerticalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 100, 0, 0);
      root.setWidth(0);
      root.setHeight(0);
      root.layout();
      expect(root.getWidth(), 178);
      expect(root.getHeight(), 100);
    });

    test('testRatioWithPercent', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 1000);
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
      a.setDimensionRatioString('1:1');
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_PERCENT, 0, 0, 0.7);
      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.layout();
      final w = (0.7 * root.getWidth()).toInt();
      expect(a.getWidth(), w);
      expect(a.getHeight(), w);
      expect(a.getLeft(), (root.getWidth() - w) ~/ 2);
      expect(a.getTop(), (root.getHeight() - w) ~/ 2);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.layout();
      expect(a.getWidth(), w);
      expect(a.getHeight(), w);
      expect(a.getLeft(), (root.getWidth() - w) ~/ 2);
      expect(a.getTop(), (root.getHeight() - w) ~/ 2);
    });

    test('testRatio', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('16:9');
      root.layout();
      expect(a.getWidth(), 1067);
      expect(a.getHeight(), 600);
    });

    test('testRatio2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1080, 1920);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalBiasPercent(0.9);
      a.setDimensionRatioString('3.5:1');

      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalBiasPercent(0.5);
      b.setVerticalBiasPercent(0.9);
      b.setDimensionRatioString('4:2');

      root.layout();
      expect(a.getWidth() / a.getHeight(), closeTo(3.5, 0.1));
      expect(b.getWidth() / b.getHeight(), closeTo(2, 0.1));
      expect(a.getWidth(), closeTo(1080, 1));
      expect(a.getHeight(), closeTo(309, 1));
      expect(b.getWidth(), closeTo(618, 1));
      expect(b.getHeight(), closeTo(309, 1));
      expect(a.getLeft(), 0);
      expect(a.getTop(), 1450);
      expect(b.getLeft(), 231);
      expect(b.getTop(), a.getTop());
    });

    test('testRatio3', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1080, 1920);
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
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalBiasPercent(0.5);
      a.setDimensionRatioString('1:1');

      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalBiasPercent(0.5);
      b.setVerticalBiasPercent(0.9);
      b.setDimensionRatioString('3.5:1');

      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.bottom);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalBiasPercent(0.5);
      c.setVerticalBiasPercent(0.9);
      c.setDimensionRatioString('5:2');

      root.layout();
      expect(a.getWidth() / a.getHeight(), closeTo(1.0, 0.1));
      expect(b.getWidth() / b.getHeight(), closeTo(3.5, 0.1));
      expect(c.getWidth() / c.getHeight(), closeTo(2.5, 0.1));
      expect(a.getWidth(), closeTo(1080, 1));
      expect(a.getHeight(), closeTo(1080, 1));
      expect(b.getWidth(), closeTo(1080, 1));
      expect(b.getHeight(), closeTo(309, 1));
      expect(c.getWidth(), closeTo(772, 1));
      expect(c.getHeight(), closeTo(309, 1));
      expect(a.getLeft(), 0);
      expect(a.getTop(), 420);
      expect(b.getTop(), 1114);
      expect(c.getLeft(), 154);
      expect(c.getTop(), b.getTop());
    });

    test('testDanglingRatio', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('1:1');
      a.setWidth(100);
      a.setHeight(20);
      a.setDimensionRatioString('W,1:1');
      root.layout();
      expect(a.getWidth(), 1000);
      expect(a.getHeight(), 1000);
    });

    test('testDanglingRatio2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(300, 200);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);
      b.setDebugName('B');
      root.add(b);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 20);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 100);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 15);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setDimensionRatioString('1:1');
      root.layout();
      expect(b.getLeft(), 335);
      expect(b.getTop(), 100);
      expect(b.getWidth(), 200);
      expect(b.getHeight(), 200);
    });

    test('testDanglingRatio3', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(300, 200);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);
      b.setDebugName('B');
      root.add(b);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 20);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 100);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('h,1:1');
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 15);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setDimensionRatioString('w,1:1');
      root.layout();
      expect(a.getLeft(), 20);
      expect(a.getTop(), 100);
      expect(a.getWidth(), 300);
      expect(a.getHeight(), 300);
      expect(b.getLeft(), 335);
      expect(b.getTop(), 100);
      expect(b.getWidth(), 300);
      expect(b.getHeight(), 300);
    });

    test('testChainRatio', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(300, 20);
      final c = ConstraintWidget.size(300, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.add(a);
      root.add(b);
      root.add(c);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('1:1');
      root.layout();
      expect(a.getLeft(), 0);
      expect(a.getTop(), 100);
      expect(a.getWidth(), 400);
      expect(a.getHeight(), 400);

      expect(b.getLeft(), 400);
      expect(b.getTop(), 0);
      expect(b.getWidth(), 300);
      expect(b.getHeight(), 20);

      expect(c.getLeft(), 700);
      expect(c.getTop(), 0);
      expect(c.getWidth(), 300);
      expect(c.getHeight(), 20);
    });

    test('testChainRatio2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 1000);
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
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('1:1');
      root.layout();
      expect(a.getLeft(), 0);
      expect(a.getTop(), 300);
      expect(a.getWidth(), 400);
      expect(a.getHeight(), 400);

      expect(b.getLeft(), 400);
      expect(b.getTop(), 0);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 20);

      expect(c.getLeft(), 500);
      expect(c.getTop(), 0);
      expect(c.getWidth(), 100);
      expect(c.getHeight(), 20);
    });

    test('testChainRatio3', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 1000);
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
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('1:1');
      root.layout();
      expect(a.getLeft(), 0);
      expect(a.getTop(), 90);
      expect(a.getWidth(), 600);
      expect(a.getHeight(), 600);

      expect(b.getLeft(), 0);
      expect(b.getTop(), 780);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 20);

      expect(c.getLeft(), 0);
      expect(c.getTop(), 890);
      expect(c.getWidth(), 100);
      expect(c.getHeight(), 20);
    });

    test('testChainRatio4', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setDimensionRatioString('4:3');
      root.layout();
      expect(a.getLeft(), 0);
      expect(a.getTop(), closeTo(113, 1));
      expect(a.getWidth(), 500);
      expect(a.getHeight(), 375);

      expect(b.getLeft(), 500);
      expect(b.getTop(), closeTo(113, 1));
      expect(b.getWidth(), 500);
      expect(b.getHeight(), 375);
    });

    test('testChainRatio5', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 700, 1200);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(b);
      root.add(a);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatioString('1:1');
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_RATIO, 60, 0, 0);

      root.layout();

      expect(a.getLeft(), 0);
      expect(a.getTop(), 300);
      expect(a.getWidth(), 600);
      expect(a.getHeight(), 600);

      expect(b.getLeft(), 600);
      expect(b.getTop(), 590);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 20);

      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);

      root.layout();

      expect(a.getLeft(), 0);
      expect(a.getTop(), 300);
      expect(a.getWidth(), 600);
      expect(a.getHeight(), 600);

      expect(b.getLeft(), 600);
      expect(b.getTop(), 590);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 20);

      root.setWidth(1080);
      root.setHeight(1536);
      a.setWidth(180);
      a.setHeight(180);
      b.setWidth(900);
      b.setHeight(106);
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_RATIO, 180, 0, 0);
      root.layout();
    });

    test('testChainRatio6', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(264, 144);
      final b = ConstraintWidget.size(264, 144);
      final c = ConstraintWidget.size(264, 144);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.add(a);
      root.add(b);
      root.add(c);
      a.setVerticalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      b.setHorizontalBiasPercent(0.501);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setDimensionRatioString('1:1');
      a.setBaselineDistance(88);
      c.setBaselineDistance(88);
      root.setWidth(1080);
      root.setHeight(2220);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(a.getWidth(), b.getWidth());
      expect(b.getWidth(), b.getHeight());
      expect(root.getWidth(), c.getWidth());
      expect(root.getHeight(), a.getHeight() + b.getHeight() + c.getHeight());
    });
  });
}
