// Copyright (C) 2016 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.VisibilityTest
// (upstream pinned in UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  group('VisibilityTest', () {
    test('testGoneSingleConnection', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');

      const margin = 175;
      const goneMargin = 42;
      root.add(a);
      root.add(b);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, margin);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, margin);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, margin);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, margin);

      root.layout();
      expect(root.getWidth(), 800);
      expect(root.getHeight(), 600);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 20);
      expect(a.getLeft(), root.getLeft() + margin);
      expect(a.getTop(), root.getTop() + margin);
      expect(b.getLeft(), a.getRight() + margin);
      expect(b.getTop(), a.getBottom() + margin);

      a.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(root.getWidth(), 800);
      expect(root.getHeight(), 600);
      expect(a.getWidth(), 0);
      expect(a.getHeight(), 0);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 20);
      expect(a.getLeft(), root.getLeft());
      expect(a.getTop(), root.getTop());
      expect(b.getLeft(), a.getRight() + margin);
      expect(b.getTop(), a.getBottom() + margin);

      b.setGoneMargin(ConstraintAnchorType.left, goneMargin);
      b.setGoneMargin(ConstraintAnchorType.top, goneMargin);

      root.layout();
      expect(root.getWidth(), 800);
      expect(root.getHeight(), 600);
      expect(a.getWidth(), 0);
      expect(a.getHeight(), 0);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 20);
      expect(a.getLeft(), root.getLeft());
      expect(a.getTop(), root.getTop());
      expect(b.getLeft(), a.getRight() + goneMargin);
      expect(b.getTop(), a.getBottom() + goneMargin);
    });

    test('testGoneDualConnection', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final guideline = Guideline();
      guideline.setGuidePercent(0.5);
      guideline.setOrientation(ConstraintWidget.HORIZONTAL);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');

      root.add(a);
      root.add(b);
      root.add(guideline);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, guideline, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      root.layout();
      expect(root.getWidth(), 800);
      expect(root.getHeight(), 600);
      expect(a.getLeft(), root.getLeft());
      expect(a.getRight(), root.getRight());
      expect(b.getLeft(), root.getLeft());
      expect(b.getRight(), root.getRight());
      expect(guideline.getTop(), root.getHeight() ~/ 2);
      expect(a.getTop(), root.getTop());
      expect(a.getBottom(), guideline.getTop());
      expect(b.getTop(), a.getBottom());
      expect(b.getBottom(), root.getBottom());

      a.setVisibility(ConstraintWidget.GONE);
      root.layout();
      expect(root.getWidth(), 800);
      expect(root.getHeight(), 600);
      expect(a.getWidth(), 0);
      expect(a.getHeight(), 0);
      expect(a.getLeft(), 400);
      expect(a.getRight(), 400);
      expect(b.getLeft(), root.getLeft());
      expect(b.getRight(), root.getRight());
      expect(guideline.getTop(), root.getHeight() ~/ 2);
      expect(a.getTop(), 150);
      expect(a.getBottom(), 150);
      expect(b.getTop(), 150);
      expect(b.getBottom(), root.getBottom());
    });
  });
}
