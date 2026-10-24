// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.WidgetsPositioningTest
// (upstream pinned in UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

// Upstream drives these tests directly against the LinearSystem, adding the
// widgets in every possible order (permutations) and asserting the same
// solved result each time.
LinearSystem ls = LinearSystem();
const bool optimizeFlag = false;

void runTestOnWidgets(List<ConstraintWidget> widgets, void Function() check) {
  final tail = [for (var i = 0; i < widgets.length; i++) i];
  _addToSolverWithPermutation(widgets, [], tail, check);
}

void _addToSolverWithPermutation(List<ConstraintWidget> widgets, List<int> list,
    List<int> tail, void Function() check) {
  if (tail.isNotEmpty) {
    final n = tail.length;
    for (var i = 0; i < n; i++) {
      list.add(tail[i]);
      final permuted = [...tail]..removeAt(i);
      _addToSolverWithPermutation(widgets, list, permuted, check);
      list.removeLast();
    }
  } else {
    ls.reset();
    for (final index in list) {
      widgets[index].resetSolverVariables(ls.getCache());
    }
    for (final index in list) {
      widgets[index].addToSolver(ls, optimizeFlag);
    }
    ls.minimize();
    for (final widget in widgets) {
      widget.updateFromSolver(ls, optimizeFlag);
    }
    check();
  }
}

void main() {
  group('WidgetsPositioningTest', () {
    setUp(() {
      ls = LinearSystem();
    });
    test('testCentering', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 600);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(20, 100);
      final c = ConstraintWidget.size(100, 20);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 200);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top, 0);
      b.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom, 0);
      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.top, 0);
      c.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.bottom, 0);
      root.add(a);
      root.add(b);
      root.add(c);
      root.layout();
    });

    test('testDimensionRatio', () {
      final a = ConstraintWidget.rect(0, 0, 600, 600);
      final b = ConstraintWidget.size(100, 100);
      const margin = 10;
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left, margin);
      b.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right, margin);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top, margin);
      b.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom, margin);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setDebugName('A');
      b.setDebugName('B');
      const ratio = 0.3;
      final widgets = [a, b];
      // First, let's check vertical ratio
      b.setDimensionRatio(ratio, ConstraintWidget.VERTICAL);
      runTestOnWidgets(widgets, () {
        expect(b.getWidth(), a.getWidth() - 2 * margin);
        expect(b.getHeight(), (ratio * b.getWidth()).toInt());
        expect(b.getTop() - a.getTop(), (a.getHeight() - b.getHeight()) ~/ 2);
        expect(a.getBottom() - b.getBottom(),
            (a.getHeight() - b.getHeight()) ~/ 2);
        expect(b.getTop() - a.getTop(), a.getBottom() - b.getBottom());
      });

      b.setVerticalBiasPercent(1.0);
      runTestOnWidgets(widgets, () {
        expect(b.getWidth(), a.getWidth() - 2 * margin);
        expect(b.getHeight(), (ratio * b.getWidth()).toInt());
        expect(b.getTop(), a.getHeight() - b.getHeight() - margin);
        expect(a.getBottom(), b.getBottom() + margin);
      });

      b.setVerticalBiasPercent(0.0);
      runTestOnWidgets(widgets, () {
        expect(b.getWidth(), a.getWidth() - 2 * margin);
        expect(b.getHeight(), (ratio * b.getWidth()).toInt());
        expect(b.getTop(), a.getTop() + margin);
        expect(b.getBottom(), a.getTop() + b.getHeight() + margin);
      });

      // Then, let's check horizontal ratio
      b.setDimensionRatio(ratio, ConstraintWidget.HORIZONTAL);
      runTestOnWidgets(widgets, () {
        expect(b.getHeight(), a.getHeight() - 2 * margin);
        expect(b.getWidth(), (ratio * b.getHeight()).toInt());
        expect(b.getLeft() - a.getLeft(), (a.getWidth() - b.getWidth()) ~/ 2);
        expect(a.getRight() - b.getRight(), (a.getWidth() - b.getWidth()) ~/ 2);
      });

      b.setHorizontalBiasPercent(1.0);
      runTestOnWidgets(widgets, () {
        expect(b.getHeight(), a.getHeight() - 2 * margin);
        expect(b.getWidth(), (ratio * b.getHeight()).toInt());
        expect(b.getRight(), a.getRight() - margin);
        expect(b.getLeft(), a.getRight() - b.getWidth() - margin);
      });

      b.setHorizontalBiasPercent(0.0);
      runTestOnWidgets(widgets, () {
        expect(b.getHeight(), a.getHeight() - 2 * margin);
        expect(b.getWidth(), (ratio * b.getHeight()).toInt());
        expect(b.getRight(), a.getLeft() + margin + b.getWidth());
        expect(b.getLeft(), a.getLeft() + margin);
      });
    });

    test('testCreateManyVariables', () {
      final rootWidget = ConstraintWidgetContainer.rect(0, 0, 600, 400);
      final previous = ConstraintWidget.rect(0, 0, 100, 20);
      rootWidget.add(previous);
      for (var i = 0; i < 100; i++) {
        final w = ConstraintWidget.rect(0, 0, 100, 20);
        w.connect(
            ConstraintAnchorType.left, previous, ConstraintAnchorType.right, 20);
        w.connect(
            ConstraintAnchorType.right, rootWidget, ConstraintAnchorType.right, 20);
        rootWidget.add(w);
      }
      rootWidget.layout();
    });

    test('testWidgetCenterPositioning', () {
      const x = 20;
      const y = 30;
      final rootWidget = ConstraintWidget.rect(x, y, 600, 400);
      final centeredWidget = ConstraintWidget.size(100, 20);

      centeredWidget.setDebugName('A');
      rootWidget.setDebugName('Root');
      centeredWidget.connect(
          ConstraintAnchorType.centerX, rootWidget, ConstraintAnchorType.centerX);
      centeredWidget.connect(
          ConstraintAnchorType.centerY, rootWidget, ConstraintAnchorType.centerY);

      runTestOnWidgets([centeredWidget, rootWidget], () {
        final left = centeredWidget.getLeft();
        final top = centeredWidget.getTop();
        final right = centeredWidget.getRight();
        final bottom = centeredWidget.getBottom();
        expect(left, x + 250);
        expect(right, x + 350);
        expect(top, y + 190);
        expect(bottom, y + 210);
      });
    });

    test('testBaselinePositioning', () {
      final a = ConstraintWidget.rect(20, 230, 200, 70);
      final b = ConstraintWidget.rect(200, 60, 200, 100);
      a.setDebugName('A');
      b.setDebugName('B');
      a.setBaselineDistance(40);
      b.setBaselineDistance(60);
      b.connect(ConstraintAnchorType.baseline, a, ConstraintAnchorType.baseline);
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 1000);
      root.setDebugName('root');
      root.add(a);
      root.add(b);
      root.layout();
      expect(b.getTop() + b.getBaselineDistance(),
          a.getTop() + a.getBaselineDistance());
    });

    test('testWidgetTopRightPositioning', () {
      // Easy to tweak numbers to test larger systems
      const numLoops = 10;
      const numWidgets = 100;

      for (var j = 0; j < numLoops; j++) {
        final widgets = <ConstraintWidget>[];
        final w = 100 + j;
        final h = 20 + j;
        final first = ConstraintWidget.size(w, h);
        widgets.add(first);
        var previous = first;
        const margin = 20;
        for (var i = 0; i < numWidgets; i++) {
          final widget = ConstraintWidget.size(w, h);
          widget.connect(
              ConstraintAnchorType.left, previous, ConstraintAnchorType.right, margin);
          widget.connect(
              ConstraintAnchorType.top, previous, ConstraintAnchorType.bottom, margin);
          widgets.add(widget);
          previous = widget;
        }
        ls.reset();
        for (final widget in widgets) {
          widget.resetSolverVariables(ls.getCache());
        }
        for (final widget in widgets) {
          widget.addToSolver(ls, optimizeFlag);
        }
        ls.minimize();
        for (var i = 0; i < widgets.length; i++) {
          final widget = widgets[i];
          widget.updateFromSolver(ls, optimizeFlag);
          final left = widget.getLeft();
          final top = widget.getTop();
          final right = widget.getRight();
          final bottom = widget.getBottom();
          expect(left, i * (w + margin));
          expect(right, i * (w + margin) + w);
          expect(top, i * (h + margin));
          expect(bottom, i * (h + margin) + h);
        }
      }
    });

    test('testWrapSimpleWrapContent', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1000, 1000);
      final a = ConstraintWidget.rect(0, 0, 200, 20);

      root.setDebugName('root');
      a.setDebugName('A');

      root.add(a);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.layout();
      expect(root.getWidth(), a.getWidth());
      expect(root.getHeight(), a.getHeight());
      expect(a.getWidth(), 200);
      expect(a.getHeight(), 20);
    });

    test('testMatchConstraint', () {
      final root = ConstraintWidgetContainer.rect(50, 50, 500, 500);
      final a = ConstraintWidget.rect(10, 20, 100, 30);
      final b = ConstraintWidget.rect(150, 200, 100, 30);
      final c = ConstraintWidget.size(50, 50);
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      root.setDebugName('root');
      root.add(a);
      root.add(b);
      root.add(c);

      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top);
      root.layout();
      expect(c.getX(), a.getRight());
      expect(c.getRight(), b.getX());
      expect(c.getY(), a.getBottom());
      expect(c.getBottom(), b.getY());
    });

    test('testWidgetPositionMove', () {
      final a = ConstraintWidget.rect(0, 0, 100, 20);
      final b = ConstraintWidget.rect(0, 30, 200, 20);
      final c = ConstraintWidget.rect(0, 60, 100, 20);
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');

      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      c.setOrigin(200, 0);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.right);

      void check() {
        expect(a.getWidth(), 100);
        expect(b.getWidth(), 200);
        expect(c.getWidth(), 100);
      }

      check();
      c.setOrigin(100, 0);
      check();
      c.setOrigin(50, 0);
      check();
    });

    test('testWrapProblem', () {
      final root = ConstraintWidgetContainer.size(400, 400);
      final a = ConstraintWidget.size(80, 300);
      final b = ConstraintWidget.size(250, 80);
      a.setParent(root);
      b.setParent(root);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      runTestOnWidgets([root, b, a], () {
        expect(a.getWidth(), 80);
        expect(a.getHeight(), 300);
        expect(b.getWidth(), 250);
        expect(b.getHeight(), 80);
        expect(a.getY(), 0);
        expect(b.getY(), 110);
      });
    });

    test('testGuideline', () {
      final root = ConstraintWidgetContainer.size(400, 400);
      final a = ConstraintWidget.size(100, 20);
      final guideline = Guideline();
      root.add(guideline);
      root.add(a);
      guideline.setGuidePercent(0.50);
      guideline.setOrientation(Guideline.vertical);
      root.setDebugName('root');
      a.setDebugName('A');
      guideline.setDebugName('guideline');

      a.connect(ConstraintAnchorType.left, guideline, ConstraintAnchorType.left);
      root.layout();
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(a.getX(), 200);

      guideline.setGuidePercent(0);
      root.layout();
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(a.getX(), 0);

      guideline.setGuideBegin(150);
      root.layout();
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(a.getX(), 150);

      guideline.setGuideEnd(150);
      root.layout();
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(a.getX(), 250);

      guideline.setOrientation(Guideline.horizontal);
      a.resetAnchors();
      a.connect(ConstraintAnchorType.top, guideline, ConstraintAnchorType.top);
      guideline.setGuideBegin(150);
      root.layout();
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(a.getY(), 150);

      a.resetAnchors();
      a.connect(ConstraintAnchorType.top, guideline, ConstraintAnchorType.bottom);
      root.layout();
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(a.getY(), 150);
    });

    test('testGuidelinePosition', () {
      final root = ConstraintWidgetContainer.size(800, 400);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final guideline = Guideline();
      root.add(guideline);
      root.add(a);
      root.add(b);
      guideline.setGuidePercent(0.651);
      guideline.setOrientation(Guideline.vertical);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      guideline.setDebugName('guideline');

      a.connect(ConstraintAnchorType.left, guideline, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, guideline, ConstraintAnchorType.right);
      root.layout();
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(a.getX(), 521);
      expect(b.getRight(), 521);
    });

    test('testWidgetInfeasiblePosition', () {
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);

      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.left);
      // TODO: this fails -- need to figure the best way to fix this.
      // expect(a.getWidth(), 100);
      // expect(b.getWidth(), 100);
    });

    test('testWidgetMultipleDependentPositioning', () {
      final root = ConstraintWidget.size(400, 400);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 10);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 10);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      root.resetSolverVariables(ls.getCache());
      a.resetSolverVariables(ls.getCache());
      b.resetSolverVariables(ls.getCache());

      runTestOnWidgets([root, b, a], () {
        expect(root.getHeight(), 400);
        expect(root.getHeight(), 400);
        expect(a.getHeight(), 20);
        expect(b.getHeight(), 20);
        expect(a.getTop() - root.getTop(), root.getBottom() - a.getBottom());
        expect(b.getTop() - a.getBottom(), root.getBottom() - b.getBottom());
      });
    });

    test('testMinSize', () {
      final root = ConstraintWidgetContainer.size(600, 400);
      final a = ConstraintWidget.size(100, 20);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      root.setDebugName('root');
      a.setDebugName('A');
      root.add(a);
      root.setOptimizationLevel(0);
      root.layout();
      expect(root.getWidth(), 600);
      expect(root.getHeight(), 400);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(a.getLeft() - root.getLeft(), root.getRight() - a.getRight());
      expect(a.getTop() - root.getTop(), root.getBottom() - a.getBottom());
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(root.getHeight(), a.getHeight());
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(a.getLeft() - root.getLeft(), root.getRight() - a.getRight());
      expect(a.getTop() - root.getTop(), root.getBottom() - a.getBottom());
      root.setMinHeight(200);
      root.layout();
      expect(root.getHeight(), 200);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(a.getLeft() - root.getLeft(), root.getRight() - a.getRight());
      expect(a.getTop() - root.getTop(), root.getBottom() - a.getBottom());
      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();
      expect(root.getWidth(), a.getWidth());
      expect(root.getHeight(), 200);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(a.getLeft() - root.getLeft(), root.getRight() - a.getRight());
      expect(a.getTop() - root.getTop(), root.getBottom() - a.getBottom());
      root.setMinWidth(300);
      root.layout();
      expect(root.getWidth(), 300);
      expect(root.getHeight(), 200);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 20);
      expect(a.getLeft() - root.getLeft(), root.getRight() - a.getRight());
      expect(a.getTop() - root.getTop(), root.getBottom() - a.getBottom());
    });
  });
}
