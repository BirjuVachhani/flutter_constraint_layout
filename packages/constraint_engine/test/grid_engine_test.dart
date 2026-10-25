// Copyright (C) 2022 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.utils.GridEngineTest, as on
// AOSP's androidx-constraintlayout-release branch. The test bodies are the
// same as at the commit pinned in UPSTREAM.md, where the class sat in the
// androidx.constraintlayout.core package.
//
// Upstream's two- and three-argument constructors are the named constructors
// GridEngine.sized and GridEngine.sizedWithWidgets.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  group('GridEngineTest', () {
    test('testNoArgument', () {
      final engine = GridEngine();
      engine.setRows(3);
      engine.setColumns(3);
      engine.setNumWidgets(5);
      engine.setup();

      expect(engine.leftOfWidget(0), 0);
      expect(engine.topOfWidget(0), 0);
      expect(engine.rightOfWidget(0), 0);
      expect(engine.bottomOfWidget(0), 0);

      expect(engine.leftOfWidget(1), 1);
      expect(engine.topOfWidget(1), 0);
      expect(engine.rightOfWidget(1), 1);
      expect(engine.bottomOfWidget(1), 0);

      expect(engine.leftOfWidget(2), 2);
      expect(engine.topOfWidget(2), 0);
      expect(engine.rightOfWidget(2), 2);
      expect(engine.bottomOfWidget(2), 0);

      expect(engine.leftOfWidget(3), 0);
      expect(engine.topOfWidget(3), 1);
      expect(engine.rightOfWidget(3), 0);
      expect(engine.bottomOfWidget(3), 1);

      expect(engine.leftOfWidget(4), 1);
      expect(engine.topOfWidget(4), 1);
      expect(engine.rightOfWidget(4), 1);
      expect(engine.bottomOfWidget(4), 1);
    });

    test('testSimpleEngineHorizontal', () {
      final engine = GridEngine.sizedWithWidgets(3, 3, 5);

      expect(engine.leftOfWidget(0), 0);
      expect(engine.topOfWidget(0), 0);
      expect(engine.rightOfWidget(0), 0);
      expect(engine.bottomOfWidget(0), 0);

      expect(engine.leftOfWidget(1), 1);
      expect(engine.topOfWidget(1), 0);
      expect(engine.rightOfWidget(1), 1);
      expect(engine.bottomOfWidget(1), 0);

      expect(engine.leftOfWidget(2), 2);
      expect(engine.topOfWidget(2), 0);
      expect(engine.rightOfWidget(2), 2);
      expect(engine.bottomOfWidget(2), 0);

      expect(engine.leftOfWidget(3), 0);
      expect(engine.topOfWidget(3), 1);
      expect(engine.rightOfWidget(3), 0);
      expect(engine.bottomOfWidget(3), 1);

      expect(engine.leftOfWidget(4), 1);
      expect(engine.topOfWidget(4), 1);
      expect(engine.rightOfWidget(4), 1);
      expect(engine.bottomOfWidget(4), 1);
    });

    test('testSimpleEngineVertical', () {
      // Grid engine with 3 rows, 3 columns, and 5 widgets
      final engine = GridEngine.sizedWithWidgets(3, 3, 5);
      // Set the orientation to Vertical
      engine.setOrientation(1);
      engine.setup();

      expect(engine.leftOfWidget(0), 0);
      expect(engine.topOfWidget(0), 0);
      expect(engine.rightOfWidget(0), 0);
      expect(engine.bottomOfWidget(0), 0);

      expect(engine.leftOfWidget(1), 0);
      expect(engine.topOfWidget(1), 1);
      expect(engine.rightOfWidget(1), 0);
      expect(engine.bottomOfWidget(1), 1);

      expect(engine.leftOfWidget(2), 0);
      expect(engine.topOfWidget(2), 2);
      expect(engine.rightOfWidget(2), 0);
      expect(engine.bottomOfWidget(2), 2);

      expect(engine.leftOfWidget(3), 1);
      expect(engine.topOfWidget(3), 0);
      expect(engine.rightOfWidget(3), 1);
      expect(engine.bottomOfWidget(3), 0);

      expect(engine.leftOfWidget(4), 1);
      expect(engine.topOfWidget(4), 1);
      expect(engine.rightOfWidget(4), 1);
      expect(engine.bottomOfWidget(4), 1);
    });

    test('testSpansSkipsHorizontal', () {
      final engine = GridEngine.sizedWithWidgets(4, 4, 5);
      engine.setSkips('0:2x2,6:1x1');
      engine.setSpans('12:1x3');
      engine.setup();

      expect(engine.leftOfWidget(0), 0);
      expect(engine.topOfWidget(0), 3);
      expect(engine.rightOfWidget(0), 2);
      expect(engine.bottomOfWidget(0), 3);

      expect(engine.leftOfWidget(1), 2);
      expect(engine.topOfWidget(1), 0);
      expect(engine.rightOfWidget(1), 2);
      expect(engine.bottomOfWidget(1), 0);

      expect(engine.leftOfWidget(2), 3);
      expect(engine.topOfWidget(2), 0);
      expect(engine.rightOfWidget(2), 3);
      expect(engine.bottomOfWidget(2), 0);

      expect(engine.leftOfWidget(3), 3);
      expect(engine.topOfWidget(3), 1);
      expect(engine.rightOfWidget(3), 3);
      expect(engine.bottomOfWidget(3), 1);

      expect(engine.leftOfWidget(4), 0);
      expect(engine.topOfWidget(4), 2);
      expect(engine.rightOfWidget(4), 0);
      expect(engine.bottomOfWidget(4), 2);
    });

    test('testSpansSkipsVertical', () {
      final engine = GridEngine.sizedWithWidgets(4, 4, 5);
      engine.setOrientation(1);
      engine.setSkips('0:2x2,6:2x1');
      engine.setSpans('12:3x1');
      engine.setup();

      expect(engine.leftOfWidget(0), 3);
      expect(engine.topOfWidget(0), 0);
      expect(engine.rightOfWidget(0), 3);
      expect(engine.bottomOfWidget(0), 2);

      expect(engine.leftOfWidget(1), 0);
      expect(engine.topOfWidget(1), 2);
      expect(engine.rightOfWidget(1), 0);
      expect(engine.bottomOfWidget(1), 2);

      expect(engine.leftOfWidget(2), 0);
      expect(engine.topOfWidget(2), 3);
      expect(engine.rightOfWidget(2), 0);
      expect(engine.bottomOfWidget(2), 3);

      expect(engine.leftOfWidget(3), 2);
      expect(engine.topOfWidget(3), 0);
      expect(engine.rightOfWidget(3), 2);
      expect(engine.bottomOfWidget(3), 0);

      expect(engine.leftOfWidget(4), 2);
      expect(engine.topOfWidget(4), 1);
      expect(engine.rightOfWidget(4), 2);
      expect(engine.bottomOfWidget(4), 1);
    });

    test('testSetRows', () {
      final engine = GridEngine.sizedWithWidgets(4, 4, 5);
      engine.setRows(3);
      engine.setup();

      expect(engine.leftOfWidget(0), 0);
      expect(engine.topOfWidget(0), 0);
      expect(engine.rightOfWidget(0), 0);
      expect(engine.bottomOfWidget(0), 0);

      expect(engine.leftOfWidget(1), 1);
      expect(engine.topOfWidget(1), 0);
      expect(engine.rightOfWidget(1), 1);
      expect(engine.bottomOfWidget(1), 0);

      expect(engine.leftOfWidget(2), 2);
      expect(engine.topOfWidget(2), 0);
      expect(engine.rightOfWidget(2), 2);
      expect(engine.bottomOfWidget(2), 0);

      expect(engine.leftOfWidget(3), 3);
      expect(engine.topOfWidget(3), 0);
      expect(engine.rightOfWidget(3), 3);
      expect(engine.bottomOfWidget(3), 0);

      expect(engine.leftOfWidget(4), 0);
      expect(engine.topOfWidget(4), 1);
      expect(engine.rightOfWidget(4), 0);
      expect(engine.bottomOfWidget(4), 1);
    });

    test('testSetColumns', () {
      final engine = GridEngine.sizedWithWidgets(4, 4, 5);
      engine.setColumns(3);
      engine.setup();

      expect(engine.leftOfWidget(0), 0);
      expect(engine.topOfWidget(0), 0);
      expect(engine.rightOfWidget(0), 0);
      expect(engine.bottomOfWidget(0), 0);

      expect(engine.leftOfWidget(1), 1);
      expect(engine.topOfWidget(1), 0);
      expect(engine.rightOfWidget(1), 1);
      expect(engine.bottomOfWidget(1), 0);

      expect(engine.leftOfWidget(2), 2);
      expect(engine.topOfWidget(2), 0);
      expect(engine.rightOfWidget(2), 2);
      expect(engine.bottomOfWidget(2), 0);

      expect(engine.leftOfWidget(3), 0);
      expect(engine.topOfWidget(3), 1);
      expect(engine.rightOfWidget(3), 0);
      expect(engine.bottomOfWidget(3), 1);

      expect(engine.leftOfWidget(4), 1);
      expect(engine.topOfWidget(4), 1);
      expect(engine.rightOfWidget(4), 1);
      expect(engine.bottomOfWidget(4), 1);
    });

    test('testSetNumWidgets', () {
      final engine = GridEngine.sized(3, 3);
      engine.setNumWidgets(5);
      engine.setup();

      expect(engine.leftOfWidget(0), 0);
      expect(engine.topOfWidget(0), 0);
      expect(engine.rightOfWidget(0), 0);
      expect(engine.bottomOfWidget(0), 0);

      expect(engine.leftOfWidget(1), 1);
      expect(engine.topOfWidget(1), 0);
      expect(engine.rightOfWidget(1), 1);
      expect(engine.bottomOfWidget(1), 0);

      expect(engine.leftOfWidget(2), 2);
      expect(engine.topOfWidget(2), 0);
      expect(engine.rightOfWidget(2), 2);
      expect(engine.bottomOfWidget(2), 0);

      expect(engine.leftOfWidget(3), 0);
      expect(engine.topOfWidget(3), 1);
      expect(engine.rightOfWidget(3), 0);
      expect(engine.bottomOfWidget(3), 1);

      expect(engine.leftOfWidget(4), 1);
      expect(engine.topOfWidget(4), 1);
      expect(engine.rightOfWidget(4), 1);
      expect(engine.bottomOfWidget(4), 1);
    });

    test('testToggleSkips', () {
      final engine = GridEngine.sizedWithWidgets(4, 4, 5);
      engine.setSkips('0:2x2,6:1x1');
      engine.setup();

      expect(engine.leftOfWidget(0), 2);
      expect(engine.topOfWidget(0), 0);
      expect(engine.rightOfWidget(0), 2);
      expect(engine.bottomOfWidget(0), 0);

      expect(engine.leftOfWidget(1), 3);
      expect(engine.topOfWidget(1), 0);
      expect(engine.rightOfWidget(1), 3);
      expect(engine.bottomOfWidget(1), 0);

      expect(engine.leftOfWidget(2), 3);
      expect(engine.topOfWidget(2), 1);
      expect(engine.rightOfWidget(2), 3);
      expect(engine.bottomOfWidget(2), 1);

      expect(engine.leftOfWidget(3), 0);
      expect(engine.topOfWidget(3), 2);
      expect(engine.rightOfWidget(3), 0);
      expect(engine.bottomOfWidget(3), 2);

      expect(engine.leftOfWidget(4), 1);
      expect(engine.topOfWidget(4), 2);
      expect(engine.rightOfWidget(4), 1);
      expect(engine.bottomOfWidget(4), 2);

      engine.setSkips('');
      engine.setup();

      expect(engine.leftOfWidget(0), 0);
      expect(engine.topOfWidget(0), 0);
      expect(engine.rightOfWidget(0), 0);
      expect(engine.bottomOfWidget(0), 0);

      expect(engine.leftOfWidget(1), 1);
      expect(engine.topOfWidget(1), 0);
      expect(engine.rightOfWidget(1), 1);
      expect(engine.bottomOfWidget(1), 0);

      expect(engine.leftOfWidget(2), 2);
      expect(engine.topOfWidget(2), 0);
      expect(engine.rightOfWidget(2), 2);
      expect(engine.bottomOfWidget(2), 0);

      expect(engine.leftOfWidget(3), 3);
      expect(engine.topOfWidget(3), 0);
      expect(engine.rightOfWidget(3), 3);
      expect(engine.bottomOfWidget(3), 0);

      expect(engine.leftOfWidget(4), 0);
      expect(engine.topOfWidget(4), 1);
      expect(engine.rightOfWidget(4), 0);
      expect(engine.bottomOfWidget(4), 1);
    });

    test('testToggleSpans', () {
      final engine = GridEngine.sizedWithWidgets(4, 4, 5);
      engine.setSpans('0:2x2,3:2x1');
      engine.setup();

      expect(engine.leftOfWidget(0), 0);
      expect(engine.topOfWidget(0), 0);
      expect(engine.rightOfWidget(0), 1);
      expect(engine.bottomOfWidget(0), 1);

      expect(engine.leftOfWidget(1), 3);
      expect(engine.topOfWidget(1), 0);
      expect(engine.rightOfWidget(1), 3);
      expect(engine.bottomOfWidget(1), 1);

      expect(engine.leftOfWidget(2), 2);
      expect(engine.topOfWidget(2), 0);
      expect(engine.rightOfWidget(2), 2);
      expect(engine.bottomOfWidget(2), 0);

      expect(engine.leftOfWidget(3), 2);
      expect(engine.topOfWidget(3), 1);
      expect(engine.rightOfWidget(3), 2);
      expect(engine.bottomOfWidget(3), 1);

      expect(engine.leftOfWidget(4), 0);
      expect(engine.topOfWidget(4), 2);
      expect(engine.rightOfWidget(4), 0);
      expect(engine.bottomOfWidget(4), 2);

      engine.setSpans('');
      engine.setup();

      expect(engine.leftOfWidget(0), 0);
      expect(engine.topOfWidget(0), 0);
      expect(engine.rightOfWidget(0), 0);
      expect(engine.bottomOfWidget(0), 0);

      expect(engine.leftOfWidget(1), 1);
      expect(engine.topOfWidget(1), 0);
      expect(engine.rightOfWidget(1), 1);
      expect(engine.bottomOfWidget(1), 0);

      expect(engine.leftOfWidget(2), 2);
      expect(engine.topOfWidget(2), 0);
      expect(engine.rightOfWidget(2), 2);
      expect(engine.bottomOfWidget(2), 0);

      expect(engine.leftOfWidget(3), 3);
      expect(engine.topOfWidget(3), 0);
      expect(engine.rightOfWidget(3), 3);
      expect(engine.bottomOfWidget(3), 0);

      expect(engine.leftOfWidget(4), 0);
      expect(engine.topOfWidget(4), 1);
      expect(engine.rightOfWidget(4), 0);
      expect(engine.bottomOfWidget(4), 1);
    });
  });
}
