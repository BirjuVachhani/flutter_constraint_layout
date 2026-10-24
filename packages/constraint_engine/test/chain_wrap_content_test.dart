// Copyright (C) 2016 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.ChainWrapContentTest
// (upstream pinned in UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void _testVerticalWrapContentChain(int directResolution) {
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
  root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
  b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
  a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 10);
  a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
  b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
  b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);
  c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
  c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 32);
  root.layout();
  expect(a.getTop(), 10);
  expect(b.getTop(), 30);
  expect(c.getTop(), 30);
  expect(root.getHeight(), 82);
}

void _testHorizontalWrapContentChain(int directResolution) {
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
  b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
  a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
  a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
  b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
  b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
  c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
  c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 32);
  root.layout();
  root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
  root.layout();
  expect(a.getLeft(), 10);
  expect(b.getLeft(), 110);
  expect(c.getLeft(), 110);
  expect(root.getWidth(), 242);
  root.setMinWidth(400);
  root.layout();
  expect(a.getLeft(), 10);
  expect(b.getLeft(), 110);
  expect(c.getLeft(), 268);
  expect(root.getWidth(), 400);
}

void _testVerticalWrapContentChain3Elts(int directResolution) {
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
  root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
  b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
  c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
  a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 10);
  a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
  b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
  b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);
  c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
  c.connect(ConstraintAnchorType.bottom, d, ConstraintAnchorType.top);
  d.connect(ConstraintAnchorType.top, c, ConstraintAnchorType.bottom);
  d.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 32);
  root.layout();
  expect(a.getTop(), 10);
  expect(b.getTop(), 30);
  expect(c.getTop(), 30);
  expect(d.getTop(), 30);
  expect(root.getHeight(), 82);
  root.setMinHeight(300);
  root.layout();
  expect(a.getTop(), 10);
  expect(b.getTop(), 30);
  expect(c.getTop(), 139);
  expect(d.getTop(), 248);
  expect(root.getHeight(), 300);
  root.setHeight(600);
  root.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
  root.layout();
  expect(a.getTop(), 10);
  expect(b.getTop(), 30);
  expect(c.getTop(), 289);
  expect(d.getTop(), 548);
  expect(root.getHeight(), 600);
}

void _testHorizontalWrapContentChain3Elts(int directResolution) {
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
  root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
  b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
  c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
  a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
  a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
  b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
  b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
  c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
  c.connect(ConstraintAnchorType.right, d, ConstraintAnchorType.left);
  d.connect(ConstraintAnchorType.left, c, ConstraintAnchorType.right);
  d.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 32);
  root.layout();
  expect(a.getLeft(), 10);
  expect(b.getLeft(), 110);
  expect(c.getLeft(), 110);
  expect(d.getLeft(), 110);
  expect(root.getWidth(), 242);
  root.setMinWidth(300);
  root.layout();
  expect(a.getLeft(), 10);
  expect(b.getLeft(), 110);
  expect(c.getLeft(), 139);
  expect(d.getLeft(), 168);
  expect(root.getWidth(), 300);
  root.setWidth(600);
  root.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
  root.layout();
  expect(a.getLeft(), 10);
  expect(b.getLeft(), 110);
  expect(c.getLeft(), 289);
  expect(d.getLeft(), 468);
  expect(root.getWidth(), 600);
}

void main() {
  group('ChainWrapContentTest', () {
    test('testVerticalWrapContentChain', () {
      _testVerticalWrapContentChain(Optimizer.OPTIMIZATION_NONE);
      _testVerticalWrapContentChain(Optimizer.OPTIMIZATION_STANDARD);
    });

    test('testHorizontalWrapContentChain', () {
      _testHorizontalWrapContentChain(Optimizer.OPTIMIZATION_NONE);
      _testHorizontalWrapContentChain(Optimizer.OPTIMIZATION_STANDARD);
    });

    test('testVerticalWrapContentChain3Elts', () {
      _testVerticalWrapContentChain3Elts(Optimizer.OPTIMIZATION_NONE);
      _testVerticalWrapContentChain3Elts(Optimizer.OPTIMIZATION_STANDARD);
    });

    test('testHorizontalWrapContentChain3Elts', () {
      _testHorizontalWrapContentChain3Elts(Optimizer.OPTIMIZATION_NONE);
      _testHorizontalWrapContentChain3Elts(Optimizer.OPTIMIZATION_STANDARD);
    });

    test('testHorizontalWrapChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 1000);
      final a = ConstraintWidget.size(20, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(20, 20);
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
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);
      b.setWidth(600);
      root.layout();
      expect(a.getLeft(), 0);
      expect(b.getLeft(), 20);
      expect(c.getLeft(), 580);
      a.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
      b.setWidth(600);
      root.layout();
      expect(a.getLeft(), 0);
      expect(b.getLeft(), 20);
      expect(c.getLeft(), 580); // doesn't expand beyond
      b.setWidth(100);
      root.layout();
      expect(a.getLeft(), 230);
      expect(b.getLeft(), 250);
      expect(c.getLeft(), 350);
      b.setWidth(600);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      root.layout();
      expect(root.getHeight(), 20);
      expect(a.getLeft(), 0);
      expect(b.getLeft(), 20);
      expect(c.getLeft(), 580);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setWidth(600);
      root.setWidth(0);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(root.getHeight(), 20);
      expect(a.getLeft(), 0);
      expect(b.getLeft(), 20);
      expect(c.getLeft(), 620);
    });

    test('testWrapChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1440, 1944);
      final a = ConstraintWidget.size(308, 168);
      final b = ConstraintWidget.size(308, 168);
      final c = ConstraintWidget.size(308, 168);
      final d = ConstraintWidget.size(308, 168);
      final e = ConstraintWidget.size(308, 168);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      e.setDebugName('E');
      root.add(e);
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
      e.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      e.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      e.connect(ConstraintAnchorType.top, c, ConstraintAnchorType.bottom);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(root.getWidth(), 1440);
      expect(root.getHeight(), 336);
    });

    test('testWrapDanglingChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1440, 1944);
      final a = ConstraintWidget.size(308, 168);
      final b = ConstraintWidget.size(308, 168);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(root.getWidth(), 616);
      expect(root.getHeight(), 168);
      expect(a.getLeft(), 0);
      expect(b.getLeft(), 308);
      expect(a.getWidth(), 308);
      expect(b.getWidth(), 308);
    });
  });
}
