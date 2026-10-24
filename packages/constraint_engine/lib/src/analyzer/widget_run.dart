// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.WidgetRun

import '../constraint_anchor.dart';
import '../constraint_widget.dart';
import 'dependency.dart';
import 'dependency_node.dart';
import 'dimension_dependency.dart';
import 'run_group.dart';

enum RunType { none, start, end, center }

abstract class WidgetRun implements Dependency {
  int matchConstraintsType = 0;
  ConstraintWidget mWidget;
  RunGroup? mRunGroup;
  DimensionBehaviour? mDimensionBehavior;
  late DimensionDependency mDimension;

  int orientation = ConstraintWidget.HORIZONTAL;
  bool mResolved = false;
  late DependencyNode start;
  late DependencyNode end;

  RunType mRunType = RunType.none;

  WidgetRun(this.mWidget) {
    mDimension = DimensionDependency(this);
    start = DependencyNode(this);
    end = DependencyNode(this);
  }

  void clear();
  void apply();
  void applyToWidget();
  void reset();
  bool supportsWrapComputation();

  bool isDimensionResolved() => mDimension.resolved;

  bool isCenterConnection() {
    var connections = 0;
    var count = start.mTargets.length;
    for (var i = 0; i < count; i++) {
      final dependency = start.mTargets[i];
      if (dependency.mRun != this) {
        connections++;
      }
    }
    count = end.mTargets.length;
    for (var i = 0; i < count; i++) {
      final dependency = end.mTargets[i];
      if (dependency.mRun != this) {
        connections++;
      }
    }
    return connections >= 2;
  }

  int wrapSize(int direction) {
    if (mDimension.resolved) {
      var size = mDimension.value;
      if (isCenterConnection()) {
        size += start.mMargin - end.mMargin;
      } else {
        if (direction == RunGroup.start) {
          size += start.mMargin;
        } else {
          size -= end.mMargin;
        }
      }
      return size;
    }
    return 0;
  }

  DependencyNode? getTarget(ConstraintAnchor anchor) {
    if (anchor.mTarget == null) {
      return null;
    }
    DependencyNode? target;
    final targetWidget = anchor.mTarget!.mOwner;
    final targetType = anchor.mTarget!.mType;
    switch (targetType) {
      case ConstraintAnchorType.left:
        target = targetWidget.mHorizontalRun!.start;
        break;
      case ConstraintAnchorType.right:
        target = targetWidget.mHorizontalRun!.end;
        break;
      case ConstraintAnchorType.top:
        target = targetWidget.mVerticalRun!.start;
        break;
      case ConstraintAnchorType.baseline:
        target = targetWidget.mVerticalRun!.baseline;
        break;
      case ConstraintAnchorType.bottom:
        target = targetWidget.mVerticalRun!.end;
        break;
      default:
        break;
    }
    return target;
  }

  DependencyNode? getTargetOriented(ConstraintAnchor anchor, int orientation) {
    if (anchor.mTarget == null) {
      return null;
    }
    DependencyNode? target;
    final targetWidget = anchor.mTarget!.mOwner;
    final WidgetRun run = (orientation == ConstraintWidget.HORIZONTAL)
        ? targetWidget.mHorizontalRun!
        : targetWidget.mVerticalRun!;
    final targetType = anchor.mTarget!.mType;
    switch (targetType) {
      case ConstraintAnchorType.top:
      case ConstraintAnchorType.left:
        target = run.start;
        break;
      case ConstraintAnchorType.bottom:
      case ConstraintAnchorType.right:
        target = run.end;
        break;
      default:
        break;
    }
    return target;
  }

  void updateRunCenter(
    Dependency dependency,
    ConstraintAnchor startAnchor,
    ConstraintAnchor endAnchor,
    int orientation,
  ) {
    final startTarget = getTarget(startAnchor);
    final endTarget = getTarget(endAnchor);

    if (!(startTarget!.resolved && endTarget!.resolved)) {
      return;
    }

    var startPos = startTarget.value + startAnchor.getMargin();
    var endPos = endTarget.value - endAnchor.getMargin();
    final distance = endPos - startPos;

    if (!mDimension.resolved &&
        mDimensionBehavior == DimensionBehaviour.matchConstraint) {
      resolveDimension(orientation, distance);
    }

    if (!mDimension.resolved) {
      return;
    }

    if (mDimension.value == distance) {
      start.resolve(startPos);
      end.resolve(endPos);
      return;
    }

    var bias = orientation == ConstraintWidget.HORIZONTAL
        ? mWidget.getHorizontalBiasPercent()
        : mWidget.getVerticalBiasPercent();

    if (startTarget == endTarget) {
      startPos = startTarget.value;
      endPos = endTarget.value;
      bias = 0.5;
    }

    final availableDistance = endPos - startPos - mDimension.value;
    start.resolve((0.5 + startPos + availableDistance * bias).toInt());
    end.resolve(start.value + mDimension.value);
  }

  void resolveDimension(int orientation, int distance) {
    switch (matchConstraintsType) {
      case ConstraintWidget.MATCH_CONSTRAINT_SPREAD:
        mDimension.resolve(getLimitedDimension(distance, orientation));
        break;
      case ConstraintWidget.MATCH_CONSTRAINT_PERCENT:
        final parent = mWidget.getParent();
        if (parent != null) {
          final WidgetRun run = orientation == ConstraintWidget.HORIZONTAL
              ? parent.mHorizontalRun!
              : parent.mVerticalRun!;
          if (run.mDimension.resolved) {
            final percent = orientation == ConstraintWidget.HORIZONTAL
                ? mWidget.mMatchConstraintPercentWidth
                : mWidget.mMatchConstraintPercentHeight;
            final targetDimensionValue = run.mDimension.value;
            final size = (0.5 + targetDimensionValue * percent).toInt();
            mDimension.resolve(getLimitedDimension(size, orientation));
          }
        }
        break;
      case ConstraintWidget.MATCH_CONSTRAINT_WRAP:
        final wrapValue = getLimitedDimension(
          mDimension.wrapValue,
          orientation,
        );
        mDimension.resolve(wrapValue < distance ? wrapValue : distance);
        break;
      case ConstraintWidget.MATCH_CONSTRAINT_RATIO:
        if (mWidget.mHorizontalRun!.mDimensionBehavior ==
                DimensionBehaviour.matchConstraint &&
            mWidget.mHorizontalRun!.matchConstraintsType ==
                ConstraintWidget.MATCH_CONSTRAINT_RATIO &&
            mWidget.mVerticalRun!.mDimensionBehavior ==
                DimensionBehaviour.matchConstraint &&
            mWidget.mVerticalRun!.matchConstraintsType ==
                ConstraintWidget.MATCH_CONSTRAINT_RATIO) {
          // pof
        } else {
          final WidgetRun run = (orientation == ConstraintWidget.HORIZONTAL)
              ? mWidget.mVerticalRun!
              : mWidget.mHorizontalRun!;
          if (run.mDimension.resolved) {
            final ratio = mWidget.getDimensionRatio();
            int value;
            if (orientation == ConstraintWidget.VERTICAL) {
              value = (0.5 + run.mDimension.value / ratio).toInt();
            } else {
              value = (0.5 + ratio * run.mDimension.value).toInt();
            }
            mDimension.resolve(value);
          }
        }
        break;
      default:
        break;
    }
  }

  void updateRunStart(Dependency dependency) {}

  void updateRunEnd(Dependency dependency) {}

  @override
  void update(Dependency dependency) {}

  int getLimitedDimension(int dimension, int orientation) {
    if (orientation == ConstraintWidget.HORIZONTAL) {
      final max = mWidget.mMatchConstraintMaxWidth;
      final min = mWidget.mMatchConstraintMinWidth;
      var value = min > dimension ? min : dimension;
      if (max > 0) {
        value = max < dimension ? max : dimension;
      }
      if (value != dimension) {
        dimension = value;
      }
    } else {
      final max = mWidget.mMatchConstraintMaxHeight;
      final min = mWidget.mMatchConstraintMinHeight;
      var value = min > dimension ? min : dimension;
      if (max > 0) {
        value = max < dimension ? max : dimension;
      }
      if (value != dimension) {
        dimension = value;
      }
    }
    return dimension;
  }

  void addTarget(DependencyNode node, DependencyNode target, int margin) {
    node.mTargets.add(target);
    node.mMargin = margin;
    target.mDependencies.add(node);
  }

  void addTargetDimension(
    DependencyNode node,
    DependencyNode target,
    int marginFactor,
    DimensionDependency dimensionDependency,
  ) {
    node.mTargets.add(target);
    node.mTargets.add(mDimension);
    node.mMarginFactor = marginFactor;
    node.mMarginDependency = dimensionDependency;
    target.mDependencies.add(node);
    dimensionDependency.mDependencies.add(node);
  }

  int getWrapDimension() {
    if (mDimension.resolved) {
      return mDimension.value;
    }
    // An unresolved MATCH_CONSTRAINT dimension inside a wrapping parent cannot
    // spread, so it collapses to its configured minimum (matches the solver).
    if (mDimensionBehavior == DimensionBehaviour.matchConstraint) {
      return orientation == ConstraintWidget.HORIZONTAL
          ? mWidget.mMatchConstraintMinWidth
          : mWidget.mMatchConstraintMinHeight;
    }
    return 0;
  }

  bool isResolved() => mResolved;
}
