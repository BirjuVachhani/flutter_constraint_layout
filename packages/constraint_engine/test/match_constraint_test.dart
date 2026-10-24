// Copyright (C) 2016 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.MatchConstraintTest
// (upstream pinned in UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  group('MatchConstraintTest', () {
    test('testSimpleMinMatch', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 150, 200, 1);
      root.add(a);
      root.add(b);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(a.getWidth(), 150);
      expect(b.getWidth(), 100);
      expect(root.getWidth(), 150);
      b.setWidth(200);
      root.setWidth(0);
      root.layout();
      expect(a.getWidth(), 200);
      expect(b.getWidth(), 200);
      expect(root.getWidth(), 200);
      b.setWidth(300);
      root.setWidth(0);
      root.layout();
      expect(a.getWidth(), 200);
      expect(b.getWidth(), 300);
      expect(root.getWidth(), 300);
    });

    test('testMinMaxMatch', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final guidelineA = Guideline();
      guidelineA.setOrientation(Guideline.vertical);
      guidelineA.setGuideBegin(100);
      final guidelineB = Guideline();
      guidelineB.setOrientation(Guideline.vertical);
      guidelineB.setGuideEnd(100);
      root.add(guidelineA);
      root.add(guidelineB);
      final a = ConstraintWidget.size(100, 20);
      a.connect(ConstraintAnchorType.left, guidelineA, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, guidelineB, ConstraintAnchorType.right);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 150, 200, 1);
      root.add(a);
      root.setDebugName('root');
      guidelineA.setDebugName('guideline A');
      guidelineB.setDebugName('guideline B');
      a.setDebugName('A');
      root.layout();
      expect(root.getWidth(), 800);
      expect(a.getWidth(), 200);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      a.setWidth(100);
      root.layout();
      expect(root.getWidth(), 350);
      expect(a.getWidth(), 150);

      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 150, 200, 1);
      root.layout();
      expect(root.getWidth(), 350);
      expect(a.getWidth(), 150);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      root.setWidth(800);
      root.layout();
      expect(root.getWidth(), 800);
      expect(a.getWidth(), 150); // because it's wrap
      a.setWidth(250);
      root.layout();
      expect(root.getWidth(), 800);
      expect(a.getWidth(), 200);

      a.setWidth(700);
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 150, 0, 1);
      root.layout();
      expect(root.getWidth(), 800);
      expect(a.getWidth(), 600);
      a.setWidth(700);
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 150, 0, 1);
      root.layout();
      expect(root.getWidth(), 800);
      expect(a.getWidth(), 600);

      a.setWidth(700);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setWidth(0);
      root.layout();
      expect(root.getWidth(), 900);
      expect(a.getWidth(), 700);
      a.setWidth(700);
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 150, 0, 1);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(root.getWidth(), 350);
      expect(a.getWidth(), 150);
    });

    test('testSimpleHorizontalMatch', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 0);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 0);
      c.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 0);
      c.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left, 0);

      root.add(a);
      root.add(b);
      root.add(c);

      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(c.getWidth(), 100);
      expect(c.getLeft() >= a.getRight(), isTrue);
      expect(c.getRight() <= b.getLeft(), isTrue);
      expect(c.getLeft() - a.getRight(), b.getLeft() - c.getRight());

      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(c.getWidth(), 600);
      expect(c.getLeft() >= a.getRight(), isTrue);
      expect(c.getRight() <= b.getLeft(), isTrue);
      expect(c.getLeft() - a.getRight(), b.getLeft() - c.getRight());

      c.setWidth(144);
      c.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(c.getWidth(), 144);
      expect(c.getLeft() >= a.getRight(), isTrue);
      expect(c.getRight() <= b.getLeft(), isTrue);
      expect(c.getLeft() - a.getRight(), b.getLeft() - c.getRight());

      c.setWidth(1000);
      c.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(c.getWidth(), 600);
      expect(c.getLeft() >= a.getRight(), isTrue);
      expect(c.getRight() <= b.getLeft(), isTrue);
      expect(c.getLeft() - a.getRight(), b.getLeft() - c.getRight());
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
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);
      root.layout();
      // Java asserts nothing here beyond not crashing.
    });
  });
}
