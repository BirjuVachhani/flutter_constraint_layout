// Copyright (C) 2021 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.NestedLayout
// (upstream pinned in UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  group('NestedLayout', () {
    test('testNestedLayout',
        skip: 'disabled upstream too (@Test is commented out): the child '
            'coordinate expectations (a.getLeft() == 425) predate the '
            'container-relative position convention', () {
      final root = ConstraintWidgetContainer.rect(20, 20, 1000, 1000);
      final container = ConstraintWidgetContainer.rect(0, 0, 100, 100);
      root.setDebugName('root');
      container.setDebugName('container');
      container.connect(
          ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      container.connect(
          ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      root.add(container);
      root.layout();
      expect(container.getLeft(), 450);
      expect(container.getWidth(), 100);

      final a = ConstraintWidget.rect(0, 0, 100, 20);
      final b = ConstraintWidget.rect(0, 0, 50, 20);
      container.add(a);
      container.add(b);
      container.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      a.connect(ConstraintAnchorType.left, container, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, container, ConstraintAnchorType.right);
      root.layout();
      expect(container.getWidth(), 150);
      expect(container.getLeft(), 425);
      expect(a.getLeft(), 425);
      expect(b.getLeft(), 525);
      expect(a.getWidth(), 100);
      expect(b.getWidth(), 50);
    });
  });
}
