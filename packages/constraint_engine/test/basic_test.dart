// Copyright (C) 2021 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.BasicTest
// (upstream pinned in UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

class _Measurer implements Measurer {
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    final horizontalBehavior = measure.horizontalBehavior;
    final verticalBehavior = measure.verticalBehavior;
    final horizontalDimension = measure.horizontalDimension;
    final verticalDimension = measure.verticalDimension;

    if (horizontalBehavior == DimensionBehaviour.fixed) {
      measure.measuredWidth = horizontalDimension;
    } else if (horizontalBehavior == DimensionBehaviour.matchConstraint) {
      measure.measuredWidth = horizontalDimension;
    }
    if (verticalBehavior == DimensionBehaviour.fixed) {
      measure.measuredHeight = verticalDimension;
    }
    widget.setMeasureRequested(false);
  }

  @override
  void didMeasures() {}
}

final _Measurer sMeasurer = _Measurer();

void applyChain(int direction, List<ConstraintWidget> widgets) {
  var previous = widgets[0];
  for (var i = 1; i < widgets.length; i++) {
    final widget = widgets[i];
    if (direction == ConstraintWidget.HORIZONTAL) {
      widget.connect(
          ConstraintAnchorType.left, previous, ConstraintAnchorType.right);
      previous.connect(
          ConstraintAnchorType.right, widget, ConstraintAnchorType.left);
    } else {
      widget.connect(
          ConstraintAnchorType.top, previous, ConstraintAnchorType.bottom);
      previous.connect(
          ConstraintAnchorType.bottom, widget, ConstraintAnchorType.top);
    }
    previous = widget;
  }
}

void main() {
  group('BasicTest', () {
    test('testWrapPercent', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      final a = ConstraintWidget.size(100, 30);
      root.setDebugName('root');
      a.setDebugName('A');

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalMatchStyle(
          ConstraintWidget.MATCH_CONSTRAINT_PERCENT, BasicMeasure.WRAP_CONTENT, 0, 0.5);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);

      root.add(a);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.layout();

      expect(a.getWidth(), 100);
      expect(root.getWidth(), a.getWidth() * 2);
    });

    test('testMiddleSplit', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(400, 30);
      final b = ConstraintWidget.size(400, 60);
      final guideline = Guideline();
      final divider = ConstraintWidget.size(100, 30);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      guideline.setDebugName('guideline');
      divider.setDebugName('divider');

      root.add(a);
      root.add(b);
      root.add(guideline);
      root.add(divider);

      guideline.setOrientation(Guideline.vertical);
      guideline.setGuidePercent(0.5);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, guideline, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, guideline, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      divider.setWidth(1);
      divider.setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      divider.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      divider.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.updateHierarchy();
      root.measure(Optimizer.OPTIMIZATION_NONE, BasicMeasure.EXACTLY, 600,
          BasicMeasure.EXACTLY, 800, 0, 0, 0, 0);

      expect(a.getWidth(), 300);
      expect(b.getWidth(), 300);
      expect(a.getLeft(), 0);
      expect(b.getLeft(), 300);
      expect(divider.getHeight(), 60);
      expect(root.getWidth(), 600);
      expect(root.getHeight(), 60);
    });

    test('testSimpleConstraint', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);

      root.setDebugName('root');
      a.setDebugName('A');

      root.add(a);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 8);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 8);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GRAPH);
      root.measure(Optimizer.OPTIMIZATION_GRAPH, 0, 0, 0, 0, 0, 0, 0, 0);
    });

    test('testSimpleWrapConstraint9', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);

      root.setDebugName('root');
      a.setDebugName('A');

      root.add(a);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      const margin = 8;
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, margin);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, margin);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, margin);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, margin);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GRAPH_WRAP);
      root.measure(Optimizer.OPTIMIZATION_GRAPH_WRAP, 0, 0, 0, 0, 0, 0, 0, 0);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.measure(Optimizer.OPTIMIZATION_GRAPH_WRAP, 0, 0, 0, 0, 0, 0, 0, 0);

      expect(root.getWidth(), 116);
      expect(root.getHeight(), 46);
    });

    test('testSimpleWrapConstraint10', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);

      root.setDebugName('root');
      a.setDebugName('A');

      root.add(a);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      const margin = 8;
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, margin);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, margin);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, margin);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, margin);

      root.measure(Optimizer.OPTIMIZATION_NONE, 0, 0, 0, 0, 0, 0, 0, 0);
      root.layout();

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.measure(Optimizer.OPTIMIZATION_GRAPH, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.EXACTLY, 800, 0, 0, 0, 0);

      expect(root.getWidth(), 116);
      expect(root.getHeight(), 800);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 385);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 30);
    });

    test('testSimpleWrapConstraint11', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(10, 30);
      final b = ConstraintWidget.size(800, 30);
      final c = ConstraintWidget.size(10, 30);
      final d = ConstraintWidget.size(800, 30);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);

      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 0);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      c.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      d.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      d.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      d.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);

      root.layout();

      expect(a.getLeft(), 0);
      expect(a.getWidth(), 10);
      expect(c.getWidth(), 10);
      expect(b.getLeft(), a.getRight());
      expect(b.getWidth(), root.getWidth() - a.getWidth() - c.getWidth());
      expect(c.getLeft(), root.getWidth() - c.getWidth());
      expect(d.getWidth(), 800);
      expect(d.getLeft(), -99);
    });

    test('testSimpleWrapConstraint', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);
      final b = ConstraintWidget.size(100, 60);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');

      root.add(a);
      root.add(b);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 8);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 8);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 8);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right, 8);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.measure(Optimizer.OPTIMIZATION_STANDARD, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);

      expect(root.getWidth(), 216);
      expect(root.getHeight(), 68);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 8);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 30);
      expect(b.getLeft(), 116);
      expect(b.getTop(), 0);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 60);

      root.measure(Optimizer.OPTIMIZATION_GRAPH, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);
      expect(root.getWidth(), 216);
      expect(root.getHeight(), 68);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 8);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 30);
      expect(b.getLeft(), 116);
      expect(b.getTop(), 0);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 60);
    });

    test('testSimpleWrapConstraint2', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);
      final b = ConstraintWidget.size(120, 60);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');

      root.add(a);
      root.add(b);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 8);
      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 8);
      b.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 8);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 8);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 8);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.measure(Optimizer.OPTIMIZATION_STANDARD, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);

      expect(root.getWidth(), 128);
      expect(root.getHeight(), 114);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 8);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 30);
      expect(b.getLeft(), 8);
      expect(b.getTop(), 46);
      expect(b.getWidth(), 120);
      expect(b.getHeight(), 60);

      root.measure(Optimizer.OPTIMIZATION_GRAPH, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);
      expect(root.getWidth(), 128);
      expect(root.getHeight(), 114);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 8);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 30);
      expect(b.getLeft(), 8);
      expect(b.getTop(), 46);
      expect(b.getWidth(), 120);
      expect(b.getHeight(), 60);
    });

    test('testSimpleWrapConstraint3', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);

      root.setDebugName('root');
      a.setDebugName('A');

      root.add(a);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 8);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom, 8);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 8);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 8);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.measure(Optimizer.OPTIMIZATION_STANDARD, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);

      expect(root.getWidth(), 116);
      expect(root.getHeight(), 46);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 8);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 30);

      root.measure(Optimizer.OPTIMIZATION_GRAPH, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);
      expect(root.getWidth(), 116);
      expect(root.getHeight(), 46);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 8);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 30);
    });

    test('testSimpleWrapConstraint4', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);
      final b = ConstraintWidget.size(100, 30);
      final c = ConstraintWidget.size(100, 30);
      final d = ConstraintWidget.size(100, 30);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      d.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      d.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 8);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 8);

      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 8);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 8);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 8);

      c.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, 8);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, 8);

      d.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top, 8);
      d.connect(ConstraintAnchorType.left, c, ConstraintAnchorType.right, 8);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.measure(Optimizer.OPTIMIZATION_STANDARD, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);

      expect(root.getWidth(), 532);
      expect(root.getHeight(), 76);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 8);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 30);
      expect(b.getLeft(), 216);
      expect(b.getTop(), 46);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 30);
      expect(c.getLeft(), 324);
      expect(c.getTop(), 8);
      expect(c.getWidth(), 100);
      expect(c.getHeight(), 30);
      expect(d.getLeft(), 432);
      // closeTo mirrors upstream's assertEquals delta (BasicTest.java): Java
      // computes -29 here.
      expect(d.getTop(), closeTo(-28, 2));
      expect(d.getWidth(), 100);
      expect(d.getHeight(), 30);

      root.measure(Optimizer.OPTIMIZATION_GRAPH, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);
      expect(root.getWidth(), 532);
      expect(root.getHeight(), 76);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 8);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 30);
      expect(b.getLeft(), 216);
      expect(b.getTop(), 46);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 30);
      expect(c.getLeft(), 324);
      expect(c.getTop(), 8);
      expect(c.getWidth(), 100);
      expect(c.getHeight(), 30);
      expect(d.getLeft(), 432);
      // closeTo mirrors upstream's assertEquals delta (BasicTest.java): Java
      // computes -29 here.
      expect(d.getTop(), closeTo(-28, 2));
      expect(d.getWidth(), 100);
      expect(d.getHeight(), 30);
    });

    test('testSimpleWrapConstraint5', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);
      final b = ConstraintWidget.size(100, 30);
      final c = ConstraintWidget.size(100, 30);
      final d = ConstraintWidget.size(100, 30);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      d.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      d.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 8);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 8);

      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 8);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 8);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 8);
      b.setHorizontalBiasPercent(0.2);

      c.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, 8);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, 8);

      d.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top, 8);
      d.connect(ConstraintAnchorType.left, c, ConstraintAnchorType.right, 8);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.measure(Optimizer.OPTIMIZATION_STANDARD, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);

      expect(root.getWidth(), 376);
      expect(root.getHeight(), 76);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 8);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 30);
      expect(b.getLeft(), 60);
      expect(b.getTop(), 46);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 30);
      expect(c.getLeft(), 168);
      expect(c.getTop(), 8);
      expect(c.getWidth(), 100);
      expect(c.getHeight(), 30);
      expect(d.getLeft(), 276);
      // closeTo mirrors upstream's assertEquals delta (BasicTest.java): Java
      // computes -29 here.
      expect(d.getTop(), closeTo(-28, 2));
      expect(d.getWidth(), 100);
      expect(d.getHeight(), 30);

      root.measure(Optimizer.OPTIMIZATION_GRAPH, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);
      expect(root.getWidth(), 376);
      expect(root.getHeight(), 76);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 8);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 30);
      expect(b.getLeft(), 60);
      expect(b.getTop(), 46);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 30);
      expect(c.getLeft(), 168);
      expect(c.getTop(), 8);
      expect(c.getWidth(), 100);
      expect(c.getHeight(), 30);
      expect(d.getLeft(), 276);
      // closeTo mirrors upstream's assertEquals delta (BasicTest.java): Java
      // computes -29 here.
      expect(d.getTop(), closeTo(-28, 2));
      expect(d.getWidth(), 100);
      expect(d.getHeight(), 30);
    });

    test('testSimpleWrapConstraint6', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);
      final b = ConstraintWidget.size(100, 30);
      final c = ConstraintWidget.size(100, 30);
      final d = ConstraintWidget.size(100, 30);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      d.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      d.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 8);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 8);

      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom, 8);
      b.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 33);
      b.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 16);
      b.setHorizontalBiasPercent(0.15);

      c.connect(ConstraintAnchorType.bottom, b, ConstraintAnchorType.top, 8);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right, 12);

      d.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.top, 8);
      d.connect(ConstraintAnchorType.left, c, ConstraintAnchorType.right, 8);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.measure(Optimizer.OPTIMIZATION_STANDARD, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);

      expect(root.getWidth(), 389);
      expect(root.getHeight(), 76);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 8);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 30);
      expect(b.getLeft(), 69);
      expect(b.getTop(), 46);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 30);
      expect(c.getLeft(), 181);
      expect(c.getTop(), 8);
      expect(c.getWidth(), 100);
      expect(c.getHeight(), 30);
      expect(d.getLeft(), 289);
      // closeTo mirrors upstream's assertEquals delta (BasicTest.java): Java
      // computes -29 here.
      expect(d.getTop(), closeTo(-28, 2));
      expect(d.getWidth(), 100);
      expect(d.getHeight(), 30);

      root.measure(Optimizer.OPTIMIZATION_GRAPH, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);
      expect(root.getWidth(), 389);
      expect(root.getHeight(), 76);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 8);
      expect(a.getWidth(), 100);
      expect(a.getHeight(), 30);
      expect(b.getLeft(), 69);
      expect(b.getTop(), 46);
      expect(b.getWidth(), 100);
      expect(b.getHeight(), 30);
      expect(c.getLeft(), 181);
      expect(c.getTop(), 8);
      expect(c.getWidth(), 100);
      expect(c.getHeight(), 30);
      expect(d.getLeft(), 289);
      // closeTo mirrors upstream's assertEquals delta (BasicTest.java): Java
      // computes -29 here.
      expect(d.getTop(), closeTo(-28, 2));
      expect(d.getWidth(), 100);
      expect(d.getHeight(), 30);
    });

    test('testSimpleWrapConstraint7', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);

      root.setDebugName('root');
      a.setDebugName('A');

      root.add(a);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 8);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 8);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right, 8);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.measure(Optimizer.OPTIMIZATION_STANDARD, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);

      expect(root.getWidth(), 16);
      expect(root.getHeight(), 38);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 8);
      expect(a.getWidth(), 0);
      expect(a.getHeight(), 30);

      root.measure(Optimizer.OPTIMIZATION_GRAPH, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);
      expect(root.getWidth(), 16);
      expect(root.getHeight(), 38);
      expect(a.getLeft(), 8);
      expect(a.getTop(), 8);
      expect(a.getWidth(), 0);
      expect(a.getHeight(), 30);
    });

    test('testSimpleWrapConstraint8', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);
      final b = ConstraintWidget.size(10, 30);
      final c = ConstraintWidget.size(10, 30);
      final d = ConstraintWidget.size(100, 30);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      d.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      d.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      applyChain(ConstraintWidget.HORIZONTAL, [a, b, c, d]);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      d.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.measure(Optimizer.OPTIMIZATION_STANDARD, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);

      expect(root.getWidth(), 110);
      expect(root.getHeight(), 30);

      root.measure(Optimizer.OPTIMIZATION_GRAPH, BasicMeasure.WRAP_CONTENT, 0,
          BasicMeasure.WRAP_CONTENT, 0, 0, 0, 0, 0);
      expect(root.getWidth(), 110);
      expect(root.getHeight(), 30);
    });

    test('testSimpleCircleConstraint', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);
      final b = ConstraintWidget.size(100, 30);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');

      root.add(a);
      root.add(b);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top, 8);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left, 8);
      b.connectCircularConstraint(a, 30, 50);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GRAPH);
      root.measure(Optimizer.OPTIMIZATION_GRAPH, BasicMeasure.EXACTLY, 600,
          BasicMeasure.EXACTLY, 800, 0, 0, 0, 0);
      // Upstream prints A and B here without asserting.
    });

    test('testRatioChainConstraint', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);
      final b = ConstraintWidget.size(0, 30);
      final c = ConstraintWidget.size(0, 30);
      final d = ConstraintWidget.size(100, 30);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      d.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);

      b.setDimensionRatioString('w,1:1');

      a.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      b.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      c.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      d.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);

      applyChain(ConstraintWidget.HORIZONTAL, [a, b, c, d]);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      d.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_GRAPH);
      root.measure(Optimizer.OPTIMIZATION_GRAPH, BasicMeasure.EXACTLY, 600,
          BasicMeasure.EXACTLY, 800, 0, 0, 0, 0);
    });

    test('testCycleConstraints', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);
      final b = ConstraintWidget.size(40, 20);
      final c = ConstraintWidget.size(40, 20);
      final d = ConstraintWidget.size(30, 30);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);

      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.bottom);
      b.connect(ConstraintAnchorType.left, c, ConstraintAnchorType.left);

      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      c.connect(ConstraintAnchorType.left, d, ConstraintAnchorType.right);

      d.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.top);
      d.connect(ConstraintAnchorType.bottom, c, ConstraintAnchorType.bottom);
      d.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);

      root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      root.measure(Optimizer.OPTIMIZATION_NONE, BasicMeasure.EXACTLY, 600,
          BasicMeasure.EXACTLY, 800, 0, 0, 0, 0);

      expect(a.getTop(), 0);
      expect(b.getTop(), 30);
      expect(c.getTop(), 50);
      expect(d.getTop(), 35);
    });

    test('testGoneChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);
      final b = ConstraintWidget.size(100, 30);
      final c = ConstraintWidget.size(100, 30);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');

      root.add(a);
      root.add(b);
      root.add(c);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVisibility(ConstraintWidget.GONE);
      c.setVisibility(ConstraintWidget.GONE);

      root.measure(Optimizer.OPTIMIZATION_NONE, BasicMeasure.EXACTLY, 600,
          BasicMeasure.EXACTLY, 800, 0, 0, 0, 0);

      expect(b.getWidth(), root.getWidth());
    });

    test('testGoneChainWithCenterWidget', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);
      final b = ConstraintWidget.size(100, 30);
      final c = ConstraintWidget.size(100, 30);
      final d = ConstraintWidget.size(100, 30);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');

      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);

      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      a.setVisibility(ConstraintWidget.GONE);
      c.setVisibility(ConstraintWidget.GONE);
      d.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.left);
      d.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.right);
      d.setVisibility(ConstraintWidget.GONE);

      root.measure(Optimizer.OPTIMIZATION_NONE, BasicMeasure.EXACTLY, 600,
          BasicMeasure.EXACTLY, 800, 0, 0, 0, 0);

      expect(b.getWidth(), root.getWidth());
    });

    test('testBarrier', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 600, 800);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(100, 30);
      final b = ConstraintWidget.size(100, 30);
      final c = ConstraintWidget.size(100, 30);
      final d = ConstraintWidget.size(100, 30);
      final barrier1 = Barrier();
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      d.setDebugName('D');
      barrier1.setDebugName('barrier1');
      root.add(a);
      root.add(b);
      root.add(c);
      root.add(d);
      root.add(barrier1);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      barrier1.add(a);
      barrier1.setBarrierType(Barrier.bottom);

      b.connect(ConstraintAnchorType.top, barrier1, ConstraintAnchorType.bottom);

      c.connect(ConstraintAnchorType.top, b, ConstraintAnchorType.bottom);
      d.connect(ConstraintAnchorType.top, c, ConstraintAnchorType.bottom);
      d.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      root.measure(Optimizer.OPTIMIZATION_NONE, BasicMeasure.EXACTLY, 600,
          BasicMeasure.EXACTLY, 800, 0, 0, 0, 0);

      expect(a.getTop(), 0);
      expect(b.getTop(), a.getBottom());
      expect(barrier1.getTop(), a.getBottom());
      expect(c.getTop(), b.getBottom());
      expect(d.getTop(), 430);
    });

    test('testDirectCentering', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 192, 168);
      root.setMeasurer(sMeasurer);
      final a = ConstraintWidget.size(43, 43);
      final b = ConstraintWidget.size(59, 59);
      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      root.add(b);
      root.add(a);

      b.connect(ConstraintAnchorType.top, a, ConstraintAnchorType.top);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.right, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.bottom, a, ConstraintAnchorType.bottom);

      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
      root.measure(Optimizer.OPTIMIZATION_NONE, BasicMeasure.EXACTLY, 100,
          BasicMeasure.EXACTLY, 100, 0, 0, 0, 0);

      expect(a.getTop(), 63);
      expect(a.getLeft(), 75);
      expect(b.getTop(), 55);
      expect(b.getLeft(), 67);

      root.setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      root.measure(Optimizer.OPTIMIZATION_STANDARD, BasicMeasure.EXACTLY, 100,
          BasicMeasure.EXACTLY, 100, 0, 0, 0, 0);

      expect(a.getTop(), 63);
      expect(a.getLeft(), 75);
      expect(b.getTop(), 55);
      expect(b.getLeft(), 67);
    });
  });
}
