// Copyright (C) 2021 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.PriorityTest
// (upstream pinned in UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  group('PriorityTest', () {
    test('testPriorityChainHorizontal', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(400, 20);
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

      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);

      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right);

      b.setHorizontalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
      expect(a.getWidth(), 400);
      expect(b.getWidth(), 100);
      expect(c.getWidth(), 100);
      expect(a.getLeft(), 300);
      expect(b.getLeft(), 400);
      expect(c.getLeft(), 500);

      b.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD);
      root.layout();
      expect(a.getWidth(), 400);
      expect(b.getWidth(), 100);
      expect(c.getWidth(), 100);
      expect(a.getLeft(), 300);
      // closeTo: double-vs-float32 solver rounding, see UPSTREAM.md.
      expect(b.getLeft(), closeTo(367, 1));
      expect(c.getLeft(), closeTo(533, 1));

      b.setHorizontalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      root.layout();
      expect(a.getWidth(), 400);
      expect(b.getWidth(), 100);
      expect(c.getWidth(), 100);
      expect(a.getLeft(), 300);
      expect(b.getLeft(), 300);
      expect(c.getLeft(), 600);
    });

    test('testPriorityChainVertical', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 1000);
      final a = ConstraintWidget.size(400, 400);
      final b = ConstraintWidget.size(100, 100);
      final c = ConstraintWidget.size(100, 100);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.add(a);
      root.add(b);
      root.add(c);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top);

      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);

      b.setVerticalChainStyle(ConstraintWidget.CHAIN_PACKED);
      root.layout();
      expect(a.getHeight(), 400);
      expect(b.getHeight(), 100);
      expect(c.getHeight(), 100);
      expect(a.getTop(), 300);
      expect(b.getTop(), 400);
      expect(c.getTop(), 500);

      b.setVerticalChainStyle(ConstraintWidget.CHAIN_SPREAD);
      root.layout();
      expect(a.getHeight(), 400);
      expect(b.getHeight(), 100);
      expect(c.getHeight(), 100);
      expect(a.getTop(), 300);
      // closeTo: double-vs-float32 solver rounding, see UPSTREAM.md.
      expect(b.getTop(), closeTo(367, 1));
      expect(c.getTop(), closeTo(533, 1));

      b.setVerticalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
      root.layout();
      expect(a.getHeight(), 400);
      expect(b.getHeight(), 100);
      expect(c.getHeight(), 100);
      expect(a.getTop(), 300);
      expect(b.getTop(), 300);
      expect(c.getTop(), 600);
    });
  });
}
