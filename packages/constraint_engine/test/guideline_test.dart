// Copyright (C) 2021 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.GuidelineTest
// (upstream pinned in UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  group('GuidelineTest', () {
    test('testWrapGuideline', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final guidelineRight = Guideline();
      guidelineRight.setOrientation(Guideline.vertical);
      final guidelineBottom = Guideline();
      guidelineBottom.setOrientation(Guideline.horizontal);
      guidelineRight.setGuidePercent(0.64);
      guidelineBottom.setGuideEnd(60);
      root.setDebugName('Root');
      a.setDebugName('A');
      guidelineRight.setDebugName('GuidelineRight');
      guidelineBottom.setDebugName('GuidelineBottom');
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, guidelineRight, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.bottom, guidelineBottom, ConstraintAnchorType.top);
      root.add(a);
      root.add(guidelineRight);
      root.add(guidelineBottom);
      root.layout();
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(root.getHeight(), 80);
    });

    test('testWrapGuideline2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final guideline = Guideline();
      guideline.setOrientation(Guideline.vertical);
      guideline.setGuideBegin(60);
      root.setDebugName('Root');
      a.setDebugName('A');
      guideline.setDebugName('Guideline');
      a.connect(ConstraintAnchorType.left, guideline, ConstraintAnchorType.left, 5);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 5);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      root.add(a);
      root.add(guideline);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(root.getWidth(), 70);
    });
  });
}
