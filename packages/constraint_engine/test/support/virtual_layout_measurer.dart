// Copyright (C) 2021 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Adapted from the measurer in androidx.constraintlayout.core.FlowTest
// (upstream pinned in UPSTREAM.md).
//
// The measurer virtual-layout tests need: a Flow or Grid measures itself
// through its own measure() pass, while a plain widget just echoes back the
// dimensions it was handed.
//
// This mirrors the measurer upstream's FlowTest defines inline. It lives here
// so the mode-matrix tests can share one copy.

import 'package:constraint_engine/constraint_engine.dart';

class VirtualLayoutMeasurer implements Measurer {
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    if (widget is VirtualLayout) {
      var widthMode = BasicMeasure.UNSPECIFIED;
      var heightMode = BasicMeasure.UNSPECIFIED;
      var widthSize = 0;
      var heightSize = 0;

      if (widget.getHorizontalDimensionBehaviour() ==
          DimensionBehaviour.matchParent) {
        widthSize = widget.getParent()?.getWidth() ?? 0;
        widthMode = BasicMeasure.EXACTLY;
      } else if (measure.horizontalBehavior == DimensionBehaviour.fixed) {
        widthSize = measure.horizontalDimension;
        widthMode = BasicMeasure.EXACTLY;
      }
      if (widget.getVerticalDimensionBehaviour() ==
          DimensionBehaviour.matchParent) {
        heightSize = widget.getParent()?.getHeight() ?? 0;
        heightMode = BasicMeasure.EXACTLY;
      } else if (measure.verticalBehavior == DimensionBehaviour.fixed) {
        heightSize = measure.verticalDimension;
        heightMode = BasicMeasure.EXACTLY;
      }

      widget.measure(widthMode, widthSize, heightMode, heightSize);
      measure.measuredWidth = widget.getMeasuredWidth();
      measure.measuredHeight = widget.getMeasuredHeight();
      return;
    }

    if (measure.horizontalBehavior == DimensionBehaviour.fixed) {
      measure.measuredWidth = measure.horizontalDimension;
    }
    if (measure.verticalBehavior == DimensionBehaviour.fixed) {
      measure.measuredHeight = measure.verticalDimension;
    }
  }

  @override
  void didMeasures() {}
}

final Measurer virtualLayoutMeasurer = VirtualLayoutMeasurer();
