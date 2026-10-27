// Copyright (C) 2017 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.CenterWrapTest
// (upstream pinned in UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  group('CenterWrapTest', () {
    test('testRatioCenter', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('Root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(a);
      root.add(b);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDimensionRatio(0.3, ConstraintWidget.VERTICAL);

      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setDimensionRatio(1.0, ConstraintWidget.VERTICAL);
      root.setOptimizationLevel(0);
      root.layout();
    });

    test('testSimpleWrap', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('Root');
      a.setDebugName('A');
      root.add(a);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setOptimizationLevel(0);
      root.layout();
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(root.getWidth(), 100);
      expect(root.getHeight(), 20);
    });

    test('testSimpleWrap2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('Root');
      a.setDebugName('A');
      root.add(a);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setOptimizationLevel(0);
      root.layout();
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(root.getWidth(), 100);
      expect(root.getHeight(), 20);
    });

    test('testWrap', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      root.setDebugName('Root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.add(a);
      root.add(b);
      root.add(c);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setOptimizationLevel(0);
      root.layout();
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(c.getWidth(), 100);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(b.getHeight(), 20);
      expect(c.getHeight(), 20);
    });

    test('testWrapHeight', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final tl = ConstraintWidget.size(100, 20);
      final trl = ConstraintWidget.size(100, 20);
      final tbl = ConstraintWidget.size(100, 20);
      final img = ConstraintWidget.size(100, 100);

      root.setDebugName('root');
      tl.setDebugName('TL');
      trl.setDebugName('TRL');
      tbl.setDebugName('TBL');
      img.setDebugName('IMG');

      // vertical

      tl.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      tl.connect(ConstraintAnchorType.bottom, tbl, ConstraintAnchorType.bottom);
      trl.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      tbl.connect(ConstraintAnchorType.top, trl, ConstraintAnchorType.bottom);

      img.connect(ConstraintAnchorType.top, tbl, ConstraintAnchorType.bottom);
      img.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      root.add(tl);
      root.add(trl);
      root.add(tbl);
      root.add(img);

      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(root.getHeight(), 140);
    });

    test('testComplexLayout', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final img = ConstraintWidget.size(100, 100);

      const margin = 16;

      final button = ConstraintWidget.size(50, 50);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);

      img.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      img.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      img.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      img.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      button.connect(
          ConstraintAnchorType.right, root, ConstraintAnchorType.right, margin);
      button.connect(ConstraintAnchorType.top, img, ConstraintAnchorType.bottom);
      button.connect(
          ConstraintAnchorType.bottom, img, ConstraintAnchorType.bottom);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, margin);
      a.connect(
          ConstraintAnchorType.top, button, ConstraintAnchorType.bottom, margin);

      b.connect(
          ConstraintAnchorType.right, root, ConstraintAnchorType.right, margin);
      b.connect(
          ConstraintAnchorType.top, button, ConstraintAnchorType.bottom, margin);

      c.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, margin);
      c.connect(
          ConstraintAnchorType.right, root, ConstraintAnchorType.right, margin);
      c.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, margin);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      root.add(img);
      root.add(button);
      root.add(a);
      root.add(b);
      root.add(c);

      root.setDebugName('root');
      img.setDebugName('IMG');
      button.setDebugName('BUTTON');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');

      root.layout();
      expect(root.getWidth(), 800);
      expect(root.getHeight(), 600);
      expect(img.getWidth(), root.getWidth());
      expect(button.getWidth(), 50);
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(c.getWidth(), 100);
      expect(img.getHeight(), 100);
      expect(button.getHeight(), 50);
      expect(a.getHeight(), 20);
      expect(b.getHeight(), 20);
      expect(c.getHeight(), 20);
      expect(img.getLeft(), 0);
      expect(img.getRight(), root.getRight());
      expect(button.getLeft(), 734);
      expect(button.getTop(), img.getBottom() - button.getHeight() ~/ 2);
      expect(a.getLeft(), margin);
      expect(a.getTop(), button.getBottom() + margin);
      expect(b.getRight(), root.getRight() - margin);
      expect(b.getTop(), a.getTop());
      expect(c.getLeft(), 350);
      expect(c.getRight(), 450);
      // closeTo mirrors upstream's assertEquals delta (CenterWrapTest.java
      // 243).
      expect(c.getTop(), closeTo(379, 1));

      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      root.setOptimizationLevel(0);
      expect(root.getWidth(), 800);
      expect(root.getHeight(), 197);
      expect(img.getWidth(), root.getWidth());
      expect(button.getWidth(), 50);
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 100);
      expect(c.getWidth(), 100);
      expect(img.getHeight(), 100);
      expect(button.getHeight(), 50);
      expect(a.getHeight(), 20);
      expect(b.getHeight(), 20);
      expect(c.getHeight(), 20);
      expect(img.getLeft(), 0);
      expect(img.getRight(), root.getRight());
      expect(button.getLeft(), 734);
      expect(button.getTop(), img.getBottom() - button.getHeight() ~/ 2);
      expect(a.getLeft(), margin);
      expect(a.getTop(), button.getBottom() + margin);
      expect(b.getRight(), root.getRight() - margin);
      expect(b.getTop(), a.getTop());
      expect(c.getLeft(), 350);
      expect(c.getRight(), 450);
      expect(c.getTop(), a.getBottom() + margin);
    });

    test('testWrapCenter', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 800, 600);
      final textBox = ConstraintWidget.size(100, 50);
      final textBoxGone = ConstraintWidget.size(100, 50);
      final valueBox = ConstraintWidget.size(20, 20);

      root.setDebugName('root');
      textBox.setDebugName('TextBox');
      textBoxGone.setDebugName('TextBoxGone');
      valueBox.setDebugName('ValueBox');

      // vertical

      textBox.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      textBox.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 10);
      textBox.connect(
          ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
      textBox.connect(
          ConstraintAnchorType.right, valueBox, ConstraintAnchorType.left, 10);

      valueBox.connect(
          ConstraintAnchorType.right, root, ConstraintAnchorType.right, 10);
      valueBox.connect(
          ConstraintAnchorType.top, textBox, ConstraintAnchorType.top);
      valueBox.connect(
          ConstraintAnchorType.bottom, textBox, ConstraintAnchorType.bottom);

      textBoxGone
          .setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      textBoxGone.connect(
          ConstraintAnchorType.top, textBox, ConstraintAnchorType.bottom, 10);
      textBoxGone.connect(
          ConstraintAnchorType.left, root, ConstraintAnchorType.left, 10);
      textBoxGone.connect(
          ConstraintAnchorType.right, textBox, ConstraintAnchorType.right);
      textBoxGone.setVisibility(ConstraintWidget.GONE);

      root.add(textBox);
      root.add(valueBox);
      root.add(textBoxGone);

      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(valueBox.getTop(),
          textBox.getTop() + ((textBox.getHeight() - valueBox.getHeight()) ~/ 2));
      expect(root.getHeight(), 60);
    });
  });
}
