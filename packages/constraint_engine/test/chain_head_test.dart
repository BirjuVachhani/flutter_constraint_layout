// Copyright (C) 2018 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.ChainHeadTest (upstream
// pinned in UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ChainHeadTest', () {
    test('basicHorizontalChainHeadTest', () {
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

      var chainHead = ChainHead(a, ConstraintWidget.HORIZONTAL, false);
      chainHead.define();

      expect(chainHead.getHead(), a);
      expect(chainHead.getFirst(), a);
      expect(chainHead.getFirstVisibleWidget(), a);
      expect(chainHead.getLast(), c);
      expect(chainHead.getLastVisibleWidget(), c);

      a.setVisibility(ConstraintWidget.GONE);

      chainHead = ChainHead(a, ConstraintWidget.HORIZONTAL, false);
      chainHead.define();

      expect(chainHead.getHead(), a);
      expect(chainHead.getFirst(), a);
      expect(chainHead.getFirstVisibleWidget(), b);

      chainHead = ChainHead(a, ConstraintWidget.HORIZONTAL, true);
      chainHead.define();

      expect(chainHead.getHead(), c);
      expect(chainHead.getFirst(), a);
      expect(chainHead.getFirstVisibleWidget(), b);
    });

    test('basicVerticalChainHeadTest', () {
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
      a.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);

      var chainHead = ChainHead(a, ConstraintWidget.VERTICAL, false);
      chainHead.define();

      expect(chainHead.getHead(), a);
      expect(chainHead.getFirst(), a);
      expect(chainHead.getFirstVisibleWidget(), a);
      expect(chainHead.getLast(), c);
      expect(chainHead.getLastVisibleWidget(), c);

      a.setVisibility(ConstraintWidget.GONE);

      chainHead = ChainHead(a, ConstraintWidget.VERTICAL, false);
      chainHead.define();

      expect(chainHead.getHead(), a);
      expect(chainHead.getFirst(), a);
      expect(chainHead.getFirstVisibleWidget(), b);

      chainHead = ChainHead(a, ConstraintWidget.VERTICAL, true);
      chainHead.define();

      expect(chainHead.getHead(), a);
      expect(chainHead.getFirst(), a);
      expect(chainHead.getFirstVisibleWidget(), b);
    });

    test('basicMatchConstraintTest', () {
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
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalWeight(1);
      b.setHorizontalWeight(2);
      c.setHorizontalWeight(3);

      var chainHead = ChainHead(a, ConstraintWidget.HORIZONTAL, false);
      chainHead.define();

      expect(chainHead.getFirstMatchConstraintWidget(), a);
      expect(chainHead.getLastMatchConstraintWidget(), c);
      expect(chainHead.getTotalWeight(), 6.0);

      c.setVisibility(ConstraintWidget.GONE);

      chainHead = ChainHead(a, ConstraintWidget.HORIZONTAL, false);
      chainHead.define();

      expect(chainHead.getFirstMatchConstraintWidget(), a);
      expect(chainHead.getLastMatchConstraintWidget(), b);
      expect(chainHead.getTotalWeight(), 3.0);
    });

    test('chainOptimizerValuesTest', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(50, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(200, 20);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');

      root.add(a);
      root.add(b);
      root.add(c);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 5);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, 5);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 1);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left, 1);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, 10);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 10);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      var chainHead = ChainHead(a, ConstraintWidget.HORIZONTAL, false);
      chainHead.define();

      expect(chainHead.mVisibleWidgets, 3);
      expect(chainHead.mTotalSize, 367); // Takes all but first and last margins.
      expect(chainHead.mTotalMargins, 32);
      expect(chainHead.mWidgetsMatchCount, 0);
      expect(chainHead.mOptimizable, isTrue);

      b.setVisibility(ConstraintWidget.GONE);

      chainHead = ChainHead(a, ConstraintWidget.HORIZONTAL, false);
      chainHead.define();

      expect(chainHead.mVisibleWidgets, 2);
      expect(chainHead.mTotalSize, 265);
      expect(chainHead.mTotalMargins, 30);
      expect(chainHead.mWidgetsMatchCount, 0);
      expect(chainHead.mOptimizable, isTrue);

      a.setVisibility(ConstraintWidget.GONE);
      b.setVisibility(ConstraintWidget.VISIBLE);
      c.setVisibility(ConstraintWidget.GONE);

      chainHead = ChainHead(a, ConstraintWidget.HORIZONTAL, false);
      chainHead.define();

      expect(chainHead.mVisibleWidgets, 1);
      expect(chainHead.mTotalSize, 100);
      expect(chainHead.mTotalMargins, 2);
      expect(chainHead.mWidgetsMatchCount, 0);
      expect(chainHead.mOptimizable, isTrue);

      a.setVisibility(ConstraintWidget.VISIBLE);
      b.setVisibility(ConstraintWidget.VISIBLE);
      c.setVisibility(ConstraintWidget.VISIBLE);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.mMatchConstraintDefaultWidth = ConstraintWidget.MATCH_CONSTRAINT_PERCENT;

      chainHead = ChainHead(a, ConstraintWidget.HORIZONTAL, false);
      chainHead.define();

      expect(chainHead.mVisibleWidgets, 3);
      expect(chainHead.mTotalSize, 317);
      expect(chainHead.mTotalMargins, 32);
      expect(chainHead.mWidgetsMatchCount, 1);
      expect(chainHead.mOptimizable, isFalse);
    });
  });
}
