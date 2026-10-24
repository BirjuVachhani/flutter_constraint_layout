// Copyright (C) 2021 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.FlowTest (upstream pinned in
// UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

/// The upstream FlowTest measurer: virtual layouts are measured through their
/// own measure() pass; plain widgets echo their fixed dimensions.
class _FlowMeasurer implements Measurer {
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    final horizontalBehavior = measure.horizontalBehavior;
    final verticalBehavior = measure.verticalBehavior;
    final horizontalDimension = measure.horizontalDimension;
    final verticalDimension = measure.verticalDimension;

    if (widget is VirtualLayout) {
      final layout = widget;
      var widthMode = BasicMeasure.UNSPECIFIED;
      var heightMode = BasicMeasure.UNSPECIFIED;
      var widthSize = 0;
      var heightSize = 0;
      if (layout.getHorizontalDimensionBehaviour() ==
          DimensionBehaviour.matchParent) {
        widthSize = layout.getParent() != null ? layout.getParent()!.getWidth() : 0;
        widthMode = BasicMeasure.EXACTLY;
      } else if (horizontalBehavior == DimensionBehaviour.fixed) {
        widthSize = horizontalDimension;
        widthMode = BasicMeasure.EXACTLY;
      }
      if (layout.getVerticalDimensionBehaviour() ==
          DimensionBehaviour.matchParent) {
        heightSize =
            layout.getParent() != null ? layout.getParent()!.getHeight() : 0;
        heightMode = BasicMeasure.EXACTLY;
      } else if (verticalBehavior == DimensionBehaviour.fixed) {
        heightSize = verticalDimension;
        heightMode = BasicMeasure.EXACTLY;
      }
      layout.measure(widthMode, widthSize, heightMode, heightSize);
      measure.measuredWidth = layout.getMeasuredWidth();
      measure.measuredHeight = layout.getMeasuredHeight();
    } else {
      if (horizontalBehavior == DimensionBehaviour.fixed) {
        measure.measuredWidth = horizontalDimension;
      }
      if (verticalBehavior == DimensionBehaviour.fixed) {
        measure.measuredHeight = verticalDimension;
      }
    }
  }

  @override
  void didMeasures() {}
}

final Measurer sMeasurer = _FlowMeasurer();

void main() {
  group('FlowTest', () {
    test('testFlowBaseline', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1080, 1536);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(20, 15);
      final flow = Flow();

      root.setMeasurer(sMeasurer);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      flow.setDebugName('Flow');

      flow.setVerticalAlign(Flow.VERTICAL_ALIGN_BASELINE);
      flow.add(a);
      flow.add(b);
      a.setBaselineDistance(15);

      flow.setHeight(30);
      flow.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      flow.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      flow.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      flow.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      flow.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      flow.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      root.add(flow);
      root.add(a);
      root.add(b);

      root.measure(Optimizer.OPTIMIZATION_NONE, 0, 0, 0, 0, 0, 0, 0, 0);
      root.layout();

      expect(flow.getWidth(), 1080);
      expect(flow.getHeight(), 30);
      expect(flow.getTop(), 753);
      expect(a.getLeft(), 320);
      expect(a.getTop(), 758);
      expect(b.getLeft(), 740);
      expect(b.getTop(), 761);
    });

    test('testComplexChain', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 1080, 1536);
      final a = ConstraintWidget.size(100, 20);
      final b = ConstraintWidget.size(100, 20);
      final c = ConstraintWidget.size(100, 20);
      final flow = Flow();

      root.setMeasurer(sMeasurer);

      root.setDebugName('root');
      a.setDebugName('A');
      b.setDebugName('B');
      c.setDebugName('C');
      flow.setDebugName('Flow');

      flow.setWrapMode(Flow.WRAP_CHAIN);
      flow.setMaxElementsWrap(2);

      flow.add(a);
      flow.add(b);
      flow.add(c);

      root.add(flow);
      root.add(a);
      root.add(b);
      root.add(c);

      a.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      b.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);
      c.setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint);

      flow.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      flow.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      flow.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      flow.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);

      flow.setHorizontalDimensionBehaviour(DimensionBehaviour.matchParent);
      flow.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);

      root.measure(Optimizer.OPTIMIZATION_NONE, 0, 0, 0, 0, 0, 0, 0, 0);
      root.layout();

      expect(a.getWidth(), 540);
      expect(b.getWidth(), 540);
      expect(c.getWidth(), 1080);
      expect(flow.getWidth(), root.getWidth());
      expect(
        flow.getHeight(),
        (a.getHeight() > b.getHeight() ? a.getHeight() : b.getHeight()) +
            c.getHeight(),
      );
      expect(flow.getTop(), 748);
    });

    test('testFlowText', () {
      final root = ConstraintWidgetContainer.size(20, 5);
      final a = ConstraintWidget.size(7, 1);
      final b = ConstraintWidget.size(6, 1);
      a.setDebugName('A');
      b.setDebugName('B');
      final flow = Flow();
      flow.setDebugName('flow');
      flow.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      flow.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      flow.setWidth(20);
      flow.setHeight(2);
      flow.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      flow.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      flow.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      flow.connect(ConstraintAnchorType.bottom, root, ConstraintAnchorType.bottom);
      flow.add(a);
      flow.add(b);
      root.add(flow);
      root.add(a);
      root.add(b);
      root.setMeasurer(sMeasurer);
      // Upstream only exercises measure() here (its layout() call is
      // commented out) and asserts nothing beyond not crashing.
      root.measure(Optimizer.OPTIMIZATION_NONE, 0, 0, 0, 0, 0, 0, 0, 0);
    });
  });
}
