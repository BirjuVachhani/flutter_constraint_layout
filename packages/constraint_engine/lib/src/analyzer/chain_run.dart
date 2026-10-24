// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.ChainRun

import '../constraint_widget.dart';
import '../constraint_widget_container.dart';
import 'dependency.dart';
import 'widget_run.dart';

class ChainRun extends WidgetRun {
  final List<WidgetRun> mWidgets = [];
  int mChainStyle = 0;

  ChainRun(ConstraintWidget widget, int orientation) : super(widget) {
    this.orientation = orientation;
    _build();
  }

  @override
  String toString() {
    final log = StringBuffer('ChainRun ');
    log.write(orientation == ConstraintWidget.HORIZONTAL
        ? 'horizontal : '
        : 'vertical : ');
    for (final run in mWidgets) {
      log.write('<$run> ');
    }
    return log.toString();
  }

  @override
  bool supportsWrapComputation() {
    final count = mWidgets.length;
    for (var i = 0; i < count; i++) {
      if (!mWidgets[i].supportsWrapComputation()) {
        return false;
      }
    }
    return true;
  }

  @override
  int getWrapDimension() {
    final count = mWidgets.length;
    var wrapDimension = 0;
    for (var i = 0; i < count; i++) {
      final run = mWidgets[i];
      wrapDimension += run.start.mMargin;
      wrapDimension += run.getWrapDimension();
      wrapDimension += run.end.mMargin;
    }
    return wrapDimension;
  }

  void _build() {
    var current = mWidget;
    var previous = current.getPreviousChainMember(orientation);
    while (previous != null) {
      current = previous;
      previous = current.getPreviousChainMember(orientation);
    }
    mWidget = current; // first element of the chain
    mWidgets.add(current.getRun(orientation)!);
    var next = current.getNextChainMember(orientation);
    while (next != null) {
      current = next;
      mWidgets.add(current.getRun(orientation)!);
      next = current.getNextChainMember(orientation);
    }
    for (final run in mWidgets) {
      if (orientation == ConstraintWidget.HORIZONTAL) {
        run.mWidget.horizontalChainRun = this;
      } else if (orientation == ConstraintWidget.VERTICAL) {
        run.mWidget.verticalChainRun = this;
      }
    }
    final isInRtl = (orientation == ConstraintWidget.HORIZONTAL) &&
        (mWidget.getParent() as ConstraintWidgetContainer).isRtl();
    if (isInRtl && mWidgets.length > 1) {
      mWidget = mWidgets[mWidgets.length - 1].mWidget;
    }
    mChainStyle = orientation == ConstraintWidget.HORIZONTAL
        ? mWidget.getHorizontalChainStyle()
        : mWidget.getVerticalChainStyle();
  }

  @override
  void clear() {
    mRunGroup = null;
    for (final run in mWidgets) {
      run.clear();
    }
  }

  @override
  void reset() {
    start.resolved = false;
    end.resolved = false;
  }

  @override
  void update(Dependency dependency) {
    if (!(start.resolved && end.resolved)) {
      return;
    }

    final parent = mWidget.getParent();
    var isInRtl = false;
    if (parent is ConstraintWidgetContainer) {
      isInRtl = parent.isRtl();
    }
    final distance = end.value - start.value;
    var size = 0;
    var numMatchConstraints = 0;
    double weights = 0;
    var numVisibleWidgets = 0;
    final count = mWidgets.length;

    var firstVisibleWidget = -1;
    for (var i = 0; i < count; i++) {
      final run = mWidgets[i];
      if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
        continue;
      }
      firstVisibleWidget = i;
      break;
    }
    var lastVisibleWidget = -1;
    for (var i = count - 1; i >= 0; i--) {
      final run = mWidgets[i];
      if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
        continue;
      }
      lastVisibleWidget = i;
      break;
    }
    for (var j = 0; j < 2; j++) {
      for (var i = 0; i < count; i++) {
        final run = mWidgets[i];
        if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
          continue;
        }
        numVisibleWidgets++;
        if (i > 0 && i >= firstVisibleWidget) {
          size += run.start.mMargin;
        }
        var dimension = run.mDimension.value;
        var treatAsFixed =
            run.mDimensionBehavior != DimensionBehaviour.matchConstraint;
        if (treatAsFixed) {
          if (orientation == ConstraintWidget.HORIZONTAL &&
              !run.mWidget.mHorizontalRun!.mDimension.resolved) {
            return;
          }
          if (orientation == ConstraintWidget.VERTICAL &&
              !run.mWidget.mVerticalRun!.mDimension.resolved) {
            return;
          }
        } else if (run.matchConstraintsType ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
            j == 0) {
          treatAsFixed = true;
          dimension = run.mDimension.wrapValue;
          numMatchConstraints++;
        } else if (run.mDimension.resolved) {
          treatAsFixed = true;
        }
        if (!treatAsFixed) {
          numMatchConstraints++;
          final weight = run.mWidget.mWeight[orientation];
          if (weight >= 0) {
            weights += weight;
          }
        } else {
          size += dimension;
        }
        if (i < count - 1 && i < lastVisibleWidget) {
          size += -run.end.mMargin;
        }
      }
      if (size < distance || numMatchConstraints == 0) {
        break;
      }
      numVisibleWidgets = 0;
      numMatchConstraints = 0;
      size = 0;
      weights = 0;
    }

    var position = start.value;
    if (isInRtl) {
      position = end.value;
    }
    if (size > distance) {
      if (isInRtl) {
        position += (0.5 + (size - distance) / 2).toInt();
      } else {
        position -= (0.5 + (size - distance) / 2).toInt();
      }
    }
    var matchConstraintsDimension = 0;
    if (numMatchConstraints > 0) {
      matchConstraintsDimension =
          (0.5 + (distance - size) / numMatchConstraints).toInt();

      var appliedLimits = 0;
      for (var i = 0; i < count; i++) {
        final run = mWidgets[i];
        if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
          continue;
        }
        if (run.mDimensionBehavior == DimensionBehaviour.matchConstraint &&
            !run.mDimension.resolved) {
          var dimension = matchConstraintsDimension;
          if (weights > 0) {
            final weight = run.mWidget.mWeight[orientation];
            dimension = (0.5 + weight * (distance - size) / weights).toInt();
          }
          int max;
          int min;
          var value = dimension;
          if (orientation == ConstraintWidget.HORIZONTAL) {
            max = run.mWidget.mMatchConstraintMaxWidth;
            min = run.mWidget.mMatchConstraintMinWidth;
          } else {
            max = run.mWidget.mMatchConstraintMaxHeight;
            min = run.mWidget.mMatchConstraintMinHeight;
          }
          if (run.matchConstraintsType == ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
            value = value < run.mDimension.wrapValue ? value : run.mDimension.wrapValue;
          }
          value = min > value ? min : value;
          if (max > 0) {
            value = max < value ? max : value;
          }
          if (value != dimension) {
            appliedLimits++;
            dimension = value;
          }
          run.mDimension.resolve(dimension);
        }
      }
      if (appliedLimits > 0) {
        numMatchConstraints -= appliedLimits;
        size = 0;
        for (var i = 0; i < count; i++) {
          final run = mWidgets[i];
          if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
            continue;
          }
          if (i > 0 && i >= firstVisibleWidget) {
            size += run.start.mMargin;
          }
          size += run.mDimension.value;
          if (i < count - 1 && i < lastVisibleWidget) {
            size += -run.end.mMargin;
          }
        }
      }
      if (mChainStyle == ConstraintWidget.CHAIN_PACKED && appliedLimits == 0) {
        mChainStyle = ConstraintWidget.CHAIN_SPREAD;
      }
    }

    if (size > distance) {
      mChainStyle = ConstraintWidget.CHAIN_PACKED;
    }

    if (numVisibleWidgets > 0 &&
        numMatchConstraints == 0 &&
        firstVisibleWidget == lastVisibleWidget) {
      mChainStyle = ConstraintWidget.CHAIN_PACKED;
    }

    if (mChainStyle == ConstraintWidget.CHAIN_SPREAD_INSIDE) {
      var gap = 0;
      if (numVisibleWidgets > 1) {
        gap = (distance - size) ~/ (numVisibleWidgets - 1);
      } else if (numVisibleWidgets == 1) {
        gap = (distance - size) ~/ 2;
      }
      if (numMatchConstraints > 0) {
        gap = 0;
      }
      for (var i = 0; i < count; i++) {
        var indexValue = i;
        if (isInRtl) {
          indexValue = count - (i + 1);
        }
        final run = mWidgets[indexValue];
        if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
          run.start.resolve(position);
          run.end.resolve(position);
          continue;
        }
        if (i > 0) {
          if (isInRtl) {
            position -= gap;
          } else {
            position += gap;
          }
        }
        if (i > 0 && i >= firstVisibleWidget) {
          if (isInRtl) {
            position -= run.start.mMargin;
          } else {
            position += run.start.mMargin;
          }
        }

        if (isInRtl) {
          run.end.resolve(position);
        } else {
          run.start.resolve(position);
        }

        var dimension = run.mDimension.value;
        if (run.mDimensionBehavior == DimensionBehaviour.matchConstraint &&
            run.matchConstraintsType == ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
          dimension = run.mDimension.wrapValue;
        }
        if (isInRtl) {
          position -= dimension;
        } else {
          position += dimension;
        }

        if (isInRtl) {
          run.start.resolve(position);
        } else {
          run.end.resolve(position);
        }
        run.mResolved = true;
        if (i < count - 1 && i < lastVisibleWidget) {
          if (isInRtl) {
            position -= -run.end.mMargin;
          } else {
            position += -run.end.mMargin;
          }
        }
      }
    } else if (mChainStyle == ConstraintWidget.CHAIN_SPREAD) {
      var gap = (distance - size) ~/ (numVisibleWidgets + 1);
      if (numMatchConstraints > 0) {
        gap = 0;
      }
      for (var i = 0; i < count; i++) {
        var indexValue = i;
        if (isInRtl) {
          indexValue = count - (i + 1);
        }
        final run = mWidgets[indexValue];
        if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
          run.start.resolve(position);
          run.end.resolve(position);
          continue;
        }
        if (isInRtl) {
          position -= gap;
        } else {
          position += gap;
        }
        if (i > 0 && i >= firstVisibleWidget) {
          if (isInRtl) {
            position -= run.start.mMargin;
          } else {
            position += run.start.mMargin;
          }
        }

        if (isInRtl) {
          run.end.resolve(position);
        } else {
          run.start.resolve(position);
        }

        var dimension = run.mDimension.value;
        if (run.mDimensionBehavior == DimensionBehaviour.matchConstraint &&
            run.matchConstraintsType == ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
          dimension = dimension < run.mDimension.wrapValue
              ? dimension
              : run.mDimension.wrapValue;
        }

        if (isInRtl) {
          position -= dimension;
        } else {
          position += dimension;
        }

        if (isInRtl) {
          run.start.resolve(position);
        } else {
          run.end.resolve(position);
        }
        if (i < count - 1 && i < lastVisibleWidget) {
          if (isInRtl) {
            position -= -run.end.mMargin;
          } else {
            position += -run.end.mMargin;
          }
        }
      }
    } else if (mChainStyle == ConstraintWidget.CHAIN_PACKED) {
      var bias = (orientation == ConstraintWidget.HORIZONTAL)
          ? mWidget.getHorizontalBiasPercent()
          : mWidget.getVerticalBiasPercent();
      if (isInRtl) {
        bias = 1 - bias;
      }
      var gap = (0.5 + (distance - size) * bias).toInt();
      if (gap < 0 || numMatchConstraints > 0) {
        gap = 0;
      }
      if (isInRtl) {
        position -= gap;
      } else {
        position += gap;
      }
      for (var i = 0; i < count; i++) {
        var indexValue = i;
        if (isInRtl) {
          indexValue = count - (i + 1);
        }
        final run = mWidgets[indexValue];
        if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
          run.start.resolve(position);
          run.end.resolve(position);
          continue;
        }
        if (i > 0 && i >= firstVisibleWidget) {
          if (isInRtl) {
            position -= run.start.mMargin;
          } else {
            position += run.start.mMargin;
          }
        }
        if (isInRtl) {
          run.end.resolve(position);
        } else {
          run.start.resolve(position);
        }

        var dimension = run.mDimension.value;
        if (run.mDimensionBehavior == DimensionBehaviour.matchConstraint &&
            run.matchConstraintsType == ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
          dimension = run.mDimension.wrapValue;
        }
        if (isInRtl) {
          position -= dimension;
        } else {
          position += dimension;
        }

        if (isInRtl) {
          run.start.resolve(position);
        } else {
          run.end.resolve(position);
        }
        if (i < count - 1 && i < lastVisibleWidget) {
          if (isInRtl) {
            position -= -run.end.mMargin;
          } else {
            position += -run.end.mMargin;
          }
        }
      }
    }
  }

  @override
  void applyToWidget() {
    for (var i = 0; i < mWidgets.length; i++) {
      mWidgets[i].applyToWidget();
    }
  }

  ConstraintWidget? _getFirstVisibleWidget() {
    for (var i = 0; i < mWidgets.length; i++) {
      final run = mWidgets[i];
      if (run.mWidget.getVisibility() != ConstraintWidget.GONE) {
        return run.mWidget;
      }
    }
    return null;
  }

  ConstraintWidget? _getLastVisibleWidget() {
    for (var i = mWidgets.length - 1; i >= 0; i--) {
      final run = mWidgets[i];
      if (run.mWidget.getVisibility() != ConstraintWidget.GONE) {
        return run.mWidget;
      }
    }
    return null;
  }

  @override
  void apply() {
    for (final run in mWidgets) {
      run.apply();
    }
    final count = mWidgets.length;
    if (count < 1) {
      return;
    }

    final firstWidget = mWidgets[0].mWidget;
    final lastWidget = mWidgets[count - 1].mWidget;

    if (orientation == ConstraintWidget.HORIZONTAL) {
      final startAnchor = firstWidget.mLeft;
      final endAnchor = lastWidget.mRight;
      final startTarget =
          getTargetOriented(startAnchor, ConstraintWidget.HORIZONTAL);
      var startMargin = startAnchor.getMargin();
      final firstVisibleWidget = _getFirstVisibleWidget();
      if (firstVisibleWidget != null) {
        startMargin = firstVisibleWidget.mLeft.getMargin();
      }
      if (startTarget != null) {
        addTarget(start, startTarget, startMargin);
      }
      final endTarget = getTargetOriented(endAnchor, ConstraintWidget.HORIZONTAL);
      var endMargin = endAnchor.getMargin();
      final lastVisibleWidget = _getLastVisibleWidget();
      if (lastVisibleWidget != null) {
        endMargin = lastVisibleWidget.mRight.getMargin();
      }
      if (endTarget != null) {
        addTarget(end, endTarget, -endMargin);
      }
    } else {
      final startAnchor = firstWidget.mTop;
      final endAnchor = lastWidget.mBottom;
      final startTarget = getTargetOriented(startAnchor, ConstraintWidget.VERTICAL);
      var startMargin = startAnchor.getMargin();
      final firstVisibleWidget = _getFirstVisibleWidget();
      if (firstVisibleWidget != null) {
        startMargin = firstVisibleWidget.mTop.getMargin();
      }
      if (startTarget != null) {
        addTarget(start, startTarget, startMargin);
      }
      final endTarget = getTargetOriented(endAnchor, ConstraintWidget.VERTICAL);
      var endMargin = endAnchor.getMargin();
      final lastVisibleWidget = _getLastVisibleWidget();
      if (lastVisibleWidget != null) {
        endMargin = lastVisibleWidget.mBottom.getMargin();
      }
      if (endTarget != null) {
        addTarget(end, endTarget, -endMargin);
      }
    }
    start.updateDelegate = this;
    end.updateDelegate = this;
  }
}
