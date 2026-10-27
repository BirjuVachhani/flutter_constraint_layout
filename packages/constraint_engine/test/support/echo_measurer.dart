// Copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0
//
// No upstream counterpart. The echo measurer of the parity tooling: the
// oracle's OpDriver measures with it on the core path (VOpDriver's `Echo`),
// and it is the measurer ConstraintWidgetContainer.layout() used to install
// when none was set. Upstream's layout() has no default measurer, so the
// tests that relied on that default set this one.

import 'package:constraint_engine/constraint_engine.dart';

/// A measurer that answers every request from the widget itself: the
/// widget's stored size on a wrap-content axis and the proposed size on any
/// other, with the baseline it already has.
///
/// On a wrap-content axis the width is the raw [ConstraintWidget.mWidth] field
/// (not [ConstraintWidget.getWidth], which is 0 for a GONE widget), and
/// likewise the height. When the widget's own behaviour on an axis is
/// [DimensionBehaviour.matchConstraint], the size is then raised to the
/// match-constraint min and lowered to the max (each only when positive), as
/// Android's view measurer bounds every measure. The baseline is
/// [ConstraintWidget.hasBaseline] and [ConstraintWidget.getBaselineDistance];
/// the measure clears the widget's measure request.
class EchoMeasurer implements Measurer {
  const EchoMeasurer();

  @override
  void measure(ConstraintWidget widget, Measure measure) {
    var width = measure.horizontalBehavior == DimensionBehaviour.wrapContent
        ? widget.mWidth
        : measure.horizontalDimension;
    var height = measure.verticalBehavior == DimensionBehaviour.wrapContent
        ? widget.mHeight
        : measure.verticalDimension;
    if (widget.getHorizontalDimensionBehaviour() ==
        DimensionBehaviour.matchConstraint) {
      width = _clamp(
        width,
        widget.mMatchConstraintMinWidth,
        widget.mMatchConstraintMaxWidth,
      );
    }
    if (widget.getVerticalDimensionBehaviour() ==
        DimensionBehaviour.matchConstraint) {
      height = _clamp(
        height,
        widget.mMatchConstraintMinHeight,
        widget.mMatchConstraintMaxHeight,
      );
    }
    measure.measuredWidth = width;
    measure.measuredHeight = height;
    measure.measuredHasBaseline = widget.hasBaseline();
    measure.measuredBaseline = widget.getBaselineDistance();
    widget.setMeasureRequested(false);
  }

  @override
  void didMeasures() {}

  /// [size] raised to [min], then lowered to [max], skipping a bound that is
  /// not positive.
  static int _clamp(int size, int min, int max) {
    var value = size;
    if (min > 0 && value < min) {
      value = min;
    }
    if (max > 0 && value > max) {
      value = max;
    }
    return value;
  }
}
