// Copyright (C) 2016 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.LayoutTest
// (upstream pinned in UPSTREAM.md).
//
// Upstream runs the layout below once, inside a `while (true)` loop that
// returns after its first pass, and only prints the time it took
// (System.nanoTime) and the solver's table sizes
// (getSystem().displaySystemInformation()). It asserts nothing. That
// diagnostic scaffolding is dropped here.
//
// The expectations at the end are not upstream's: they check the frames
// against upstream's Java engine at the pinned commit, run on the same layout.
// One difference has to be accounted for. The layout adds button3 twice, and
// the second add() finds button3 already parented, so it removes it from the
// root first and re-adds it last but one. Upstream's WidgetContainer.remove()
// also resets the widget (ConstraintWidget.reset()), leaving button3 a bare
// 0 x 0 widget with no constraints, so everything stacked on it centers on a
// zero-width target. This engine's remove() does not reset (UPSTREAM.md
// explains why), so button3 keeps its size and constraints. The frames below
// are what upstream computes when the second add() moves button3 without
// resetting it; for every widget they are what this engine computes too.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

void main() {
  group('LayoutTest', () {
    test('testPositions', () {
      final root = ConstraintWidgetContainer.size(1000, 1000);
      root.setDebugName('root');
      final button3 = ConstraintWidget.size(200, 20);
      button3.setDebugName('button3');
      final button4 = ConstraintWidget.size(200, 20);
      button4.setDebugName('button4');
      final button5 = ConstraintWidget.size(200, 20);
      button5.setDebugName('button5');
      final editText = ConstraintWidget.size(200, 20);
      editText.setDebugName('editText');
      final button6 = ConstraintWidget.size(200, 20);
      button6.setDebugName('button6');
      final button7 = ConstraintWidget.size(200, 20);
      button7.setDebugName('button7');
      final button8 = ConstraintWidget.size(200, 20);
      button8.setDebugName('button8');
      final button9 = ConstraintWidget.size(200, 20);
      button9.setDebugName('button9');
      final editText2 = ConstraintWidget.size(200, 20);
      editText2.setDebugName('editText2');
      final toggleButton = ConstraintWidget.size(200, 20);
      toggleButton.setDebugName('toggleButton');
      final toggleButton2 = ConstraintWidget.size(200, 20);
      toggleButton2.setDebugName('toggleButton2');
      final toggleButton3 = ConstraintWidget.size(200, 20);
      toggleButton3.setDebugName('toggleButton3');
      final toggleButton4 = ConstraintWidget.size(200, 20);
      toggleButton4.setDebugName('toggleButton4');
      final textView = ConstraintWidget.size(200, 20);
      textView.setDebugName('textView');
      final textView2 = ConstraintWidget.size(200, 20);
      textView2.setDebugName('textView2');
      final back = ConstraintWidget.size(200, 20);
      back.setDebugName('back');

      button3.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      button3.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      button4.connect(
          ConstraintAnchorType.left, button3, ConstraintAnchorType.left);
      button4.connect(
          ConstraintAnchorType.top, button3, ConstraintAnchorType.bottom);
      button4.connect(
          ConstraintAnchorType.right, button3, ConstraintAnchorType.right);

      button5.connect(
          ConstraintAnchorType.left, button4, ConstraintAnchorType.left);
      button5.connect(
          ConstraintAnchorType.top, button4, ConstraintAnchorType.bottom);
      button5.connect(
          ConstraintAnchorType.right, button4, ConstraintAnchorType.right);

      editText.connect(
          ConstraintAnchorType.left, button5, ConstraintAnchorType.left);
      editText.connect(
          ConstraintAnchorType.top, button5, ConstraintAnchorType.bottom);

      button6.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      button6.connect(
          ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      button7.connect(
          ConstraintAnchorType.left, button6, ConstraintAnchorType.left);
      button7.connect(
          ConstraintAnchorType.top, button6, ConstraintAnchorType.bottom);
      button7.connect(
          ConstraintAnchorType.right, button6, ConstraintAnchorType.right);

      button8.connect(
          ConstraintAnchorType.left, button5, ConstraintAnchorType.left);
      button8.connect(
          ConstraintAnchorType.top, button5, ConstraintAnchorType.bottom);
      button8.connect(
          ConstraintAnchorType.right, button5, ConstraintAnchorType.right);

      button9.connect(
          ConstraintAnchorType.left, toggleButton2, ConstraintAnchorType.left);
      button9.connect(ConstraintAnchorType.right, toggleButton2,
          ConstraintAnchorType.right);
      button9.connect(ConstraintAnchorType.baseline, button8,
          ConstraintAnchorType.baseline);

      editText2.connect(
          ConstraintAnchorType.left, editText, ConstraintAnchorType.left);
      editText2.connect(
          ConstraintAnchorType.top, editText, ConstraintAnchorType.bottom);
      editText2.connect(
          ConstraintAnchorType.right, editText, ConstraintAnchorType.right);

      toggleButton.connect(
          ConstraintAnchorType.left, button8, ConstraintAnchorType.left);
      toggleButton.connect(
          ConstraintAnchorType.top, button8, ConstraintAnchorType.bottom);
      toggleButton.connect(
          ConstraintAnchorType.right, button8, ConstraintAnchorType.right);

      toggleButton2.connect(ConstraintAnchorType.left, toggleButton,
          ConstraintAnchorType.right);
      toggleButton2.connect(
          ConstraintAnchorType.top, button9, ConstraintAnchorType.bottom);

      toggleButton3.connect(ConstraintAnchorType.left, toggleButton2,
          ConstraintAnchorType.right);
      toggleButton3.connect(
          ConstraintAnchorType.top, toggleButton2, ConstraintAnchorType.top);

      toggleButton4.connect(ConstraintAnchorType.left, toggleButton3,
          ConstraintAnchorType.right);
      toggleButton4.connect(ConstraintAnchorType.baseline, toggleButton3,
          ConstraintAnchorType.baseline);

      textView.connect(
          ConstraintAnchorType.left, textView2, ConstraintAnchorType.left);
      textView.connect(
          ConstraintAnchorType.top, textView2, ConstraintAnchorType.bottom);

      textView2.connect(
          ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      textView2.connect(
          ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      back.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      back.connect(
          ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      root.add(button3);
      root.add(button4);
      root.add(button5);
      root.add(editText);
      root.add(button6);
      root.add(button7);
      root.add(button8);
      root.add(button9);
      root.add(editText2);
      root.add(toggleButton);
      root.add(toggleButton2);
      root.add(toggleButton3);
      root.add(toggleButton4);
      root.add(textView);
      root.add(textView2);
      root.add(button3);
      root.add(back);

      root.layout();

      // Not upstream: the child order and frames checked against upstream's
      // Java engine (see the note at the top), as (x, y) width x height.
      expect(root.getChildren(), [
        button4, button5, editText, button6, button7, button8, button9,
        editText2, toggleButton, toggleButton2, toggleButton3, toggleButton4,
        textView, textView2, button3, back,
      ]);
      String frame(ConstraintWidget w) => '${w.getDebugName()}: '
          '(${w.getX()}, ${w.getY()}) ${w.getWidth()} x ${w.getHeight()}';
      expect(root.getChildren().map(frame).toList(), [
        'button4: (0, 20) 200 x 20',
        'button5: (0, 40) 200 x 20',
        'editText: (0, 60) 200 x 20',
        'button6: (800, 0) 200 x 20',
        'button7: (800, 20) 200 x 20',
        'button8: (0, 60) 200 x 20',
        'button9: (200, 0) 200 x 20',
        'editText2: (0, 80) 200 x 20',
        'toggleButton: (0, 80) 200 x 20',
        'toggleButton2: (200, 20) 200 x 20',
        'toggleButton3: (400, 20) 200 x 20',
        'toggleButton4: (600, 0) 200 x 20',
        'textView: (0, 1000) 200 x 20',
        'textView2: (0, 980) 200 x 20',
        'button3: (0, 0) 200 x 20',
        'back: (800, 980) 200 x 20',
      ]);
    });
  });
}
