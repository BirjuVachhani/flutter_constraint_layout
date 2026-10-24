// Copyright (C) 2017 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.CircleTest (upstream pinned in
// UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  group('CircleTest', () {
    test('basic', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 600);
      final a = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);

      final widgets = <ConstraintWidget>[];
      for (var i = 0; i < 12; i++) {
        final w = ConstraintWidget.size(10, 10);
        w.setDebugName('w${i + 1}');
        widgets.add(w);
        root.add(w);
      }

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      for (var i = 0; i < 12; i++) {
        widgets[i].connectCircularConstraint(a, 30.0 * (i + 1), 50);
      }

      root.layout();

      const expected = [
        [520, 252],
        [538, 270],
        [545, 295],
        [538, 320],
        [520, 338],
        [495, 345],
        [470, 338],
        [452, 320],
        [445, 295],
        [452, 270],
        [470, 252],
        [495, 245],
      ];
      for (var i = 0; i < 12; i++) {
        expect(widgets[i].getLeft(), expected[i][0], reason: 'w${i + 1} left');
        expect(widgets[i].getTop(), expected[i][1], reason: 'w${i + 1} top');
      }
    });
  });
}
