// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.HorizontalWidgetRun

import '../constraint_anchor.dart';
import '../constraint_widget.dart';
import '../helper.dart';
import 'dependency.dart';
import 'dependency_node.dart';
import 'widget_run.dart';

class HorizontalWidgetRun extends WidgetRun {
  static final List<int> sTempDimensions = [0, 0];

  HorizontalWidgetRun(ConstraintWidget widget) : super(widget) {
    start.mType = DependencyNodeType.left;
    end.mType = DependencyNodeType.right;
    orientation = ConstraintWidget.HORIZONTAL;
  }

  @override
  String toString() => 'HorizontalRun ${mWidget.getDebugName()}';

  @override
  void clear() {
    mRunGroup = null;
    start.clear();
    end.clear();
    mDimension.clear();
    mResolved = false;
  }

  @override
  void reset() {
    mResolved = false;
    start.clear();
    start.resolved = false;
    end.clear();
    end.resolved = false;
    mDimension.resolved = false;
  }

  @override
  bool supportsWrapComputation() {
    if (mDimensionBehavior == DimensionBehaviour.matchConstraint) {
      if (mWidget.mMatchConstraintDefaultWidth ==
          ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
        return true;
      }
      return false;
    }
    return true;
  }

  @override
  void apply() {
    if (mWidget.measured) {
      mDimension.resolve(mWidget.getWidth());
    }
    if (!mDimension.resolved) {
      mDimensionBehavior = mWidget.getHorizontalDimensionBehaviour();
      if (mDimensionBehavior != DimensionBehaviour.matchConstraint) {
        if (mDimensionBehavior == DimensionBehaviour.matchParent) {
          final parent = mWidget.getParent();
          if (parent != null &&
              (parent.getHorizontalDimensionBehaviour() ==
                      DimensionBehaviour.fixed ||
                  parent.getHorizontalDimensionBehaviour() ==
                      DimensionBehaviour.matchParent)) {
            final resolvedDimension = parent.getWidth() -
                mWidget.mLeft.getMargin() -
                mWidget.mRight.getMargin();
            addTarget(start, parent.mHorizontalRun!.start, mWidget.mLeft.getMargin());
            addTarget(end, parent.mHorizontalRun!.end, -mWidget.mRight.getMargin());
            mDimension.resolve(resolvedDimension);
            return;
          }
        }
        if (mDimensionBehavior == DimensionBehaviour.fixed) {
          mDimension.resolve(mWidget.getWidth());
        }
      }
    } else {
      if (mDimensionBehavior == DimensionBehaviour.matchParent) {
        final parent = mWidget.getParent();
        if (parent != null &&
            (parent.getHorizontalDimensionBehaviour() ==
                    DimensionBehaviour.fixed ||
                parent.getHorizontalDimensionBehaviour() ==
                    DimensionBehaviour.matchParent)) {
          addTarget(start, parent.mHorizontalRun!.start, mWidget.mLeft.getMargin());
          addTarget(end, parent.mHorizontalRun!.end, -mWidget.mRight.getMargin());
          return;
        }
      }
    }

    if (mDimension.resolved && mWidget.measured) {
      if (mWidget.mListAnchors[ConstraintWidget.ANCHOR_LEFT].mTarget != null &&
          mWidget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT].mTarget != null) {
        // <-s-e->
        if (mWidget.isInHorizontalChain()) {
          start.mMargin =
              mWidget.mListAnchors[ConstraintWidget.ANCHOR_LEFT].getMargin();
          end.mMargin =
              -mWidget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT].getMargin();
        } else {
          final startTarget =
              getTarget(mWidget.mListAnchors[ConstraintWidget.ANCHOR_LEFT]);
          if (startTarget != null) {
            addTarget(start, startTarget,
                mWidget.mListAnchors[ConstraintWidget.ANCHOR_LEFT].getMargin());
          }
          final endTarget =
              getTarget(mWidget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT]);
          if (endTarget != null) {
            addTarget(end, endTarget,
                -mWidget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT].getMargin());
          }
          start.delegateToWidgetRun = true;
          end.delegateToWidgetRun = true;
        }
      } else if (mWidget.mListAnchors[ConstraintWidget.ANCHOR_LEFT].mTarget !=
          null) {
        // <-s-e
        final target =
            getTarget(mWidget.mListAnchors[ConstraintWidget.ANCHOR_LEFT]);
        if (target != null) {
          addTarget(start, target,
              mWidget.mListAnchors[ConstraintWidget.ANCHOR_LEFT].getMargin());
          addTarget(end, start, mDimension.value);
        }
      } else if (mWidget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT].mTarget !=
          null) {
        //   s-e->
        final target =
            getTarget(mWidget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT]);
        if (target != null) {
          addTarget(end, target,
              -mWidget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT].getMargin());
          addTarget(start, end, -mDimension.value);
        }
      } else {
        // no connections
        if (mWidget is! Helper &&
            mWidget.getParent() != null &&
            mWidget.getAnchor(ConstraintAnchorType.center)!.mTarget == null) {
          final left = mWidget.getParent()!.mHorizontalRun!.start;
          addTarget(start, left, mWidget.getX());
          addTarget(end, start, mDimension.value);
        }
      }
    } else {
      if (mDimensionBehavior == DimensionBehaviour.matchConstraint) {
        switch (mWidget.mMatchConstraintDefaultWidth) {
          case ConstraintWidget.MATCH_CONSTRAINT_RATIO:
            if (mWidget.mMatchConstraintDefaultHeight ==
                ConstraintWidget.MATCH_CONSTRAINT_RATIO) {
              start.updateDelegate = this;
              end.updateDelegate = this;
              mWidget.mVerticalRun!.start.updateDelegate = this;
              mWidget.mVerticalRun!.end.updateDelegate = this;
              mDimension.updateDelegate = this;

              if (mWidget.isInVerticalChain()) {
                mDimension.mTargets.add(mWidget.mVerticalRun!.mDimension);
                mWidget.mVerticalRun!.mDimension.mDependencies.add(mDimension);
                mWidget.mVerticalRun!.mDimension.updateDelegate = this;
                mDimension.mTargets.add(mWidget.mVerticalRun!.start);
                mDimension.mTargets.add(mWidget.mVerticalRun!.end);
                mWidget.mVerticalRun!.start.mDependencies.add(mDimension);
                mWidget.mVerticalRun!.end.mDependencies.add(mDimension);
              } else if (mWidget.isInHorizontalChain()) {
                mWidget.mVerticalRun!.mDimension.mTargets.add(mDimension);
                mDimension.mDependencies.add(mWidget.mVerticalRun!.mDimension);
              } else {
                mWidget.mVerticalRun!.mDimension.mTargets.add(mDimension);
              }
              break;
            }
            final targetDimension = mWidget.mVerticalRun!.mDimension;
            mDimension.mTargets.add(targetDimension);
            targetDimension.mDependencies.add(mDimension);
            mWidget.mVerticalRun!.start.mDependencies.add(mDimension);
            mWidget.mVerticalRun!.end.mDependencies.add(mDimension);
            mDimension.delegateToWidgetRun = true;
            mDimension.mDependencies.add(start);
            mDimension.mDependencies.add(end);
            start.mTargets.add(mDimension);
            end.mTargets.add(mDimension);
            break;
          case ConstraintWidget.MATCH_CONSTRAINT_PERCENT:
            final parent = mWidget.getParent();
            if (parent == null) {
              break;
            }
            final targetDimension = parent.mVerticalRun!.mDimension;
            mDimension.mTargets.add(targetDimension);
            targetDimension.mDependencies.add(mDimension);
            mDimension.delegateToWidgetRun = true;
            mDimension.mDependencies.add(start);
            mDimension.mDependencies.add(end);
            break;
          case ConstraintWidget.MATCH_CONSTRAINT_SPREAD:
            // work done in update()
            break;
          default:
            break;
        }
      }
      if (mWidget.mListAnchors[ConstraintWidget.ANCHOR_LEFT].mTarget != null &&
          mWidget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT].mTarget != null) {
        // <-s-d-e->
        if (mWidget.isInHorizontalChain()) {
          start.mMargin =
              mWidget.mListAnchors[ConstraintWidget.ANCHOR_LEFT].getMargin();
          end.mMargin =
              -mWidget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT].getMargin();
        } else {
          final startTarget =
              getTarget(mWidget.mListAnchors[ConstraintWidget.ANCHOR_LEFT]);
          final endTarget =
              getTarget(mWidget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT]);
          if (startTarget != null) {
            startTarget.addDependency(this);
          }
          if (endTarget != null) {
            endTarget.addDependency(this);
          }
          mRunType = RunType.center;
        }
      } else if (mWidget.mListAnchors[ConstraintWidget.ANCHOR_LEFT].mTarget !=
          null) {
        // <-s<-d<-e
        final target =
            getTarget(mWidget.mListAnchors[ConstraintWidget.ANCHOR_LEFT]);
        if (target != null) {
          addTarget(start, target,
              mWidget.mListAnchors[ConstraintWidget.ANCHOR_LEFT].getMargin());
          addTargetDimension(end, start, 1, mDimension);
        }
      } else if (mWidget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT].mTarget !=
          null) {
        //   s->d->e->
        final target =
            getTarget(mWidget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT]);
        if (target != null) {
          addTarget(end, target,
              -mWidget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT].getMargin());
          addTargetDimension(start, end, -1, mDimension);
        }
      } else {
        // no connections
        if (mWidget is! Helper && mWidget.getParent() != null) {
          final left = mWidget.getParent()!.mHorizontalRun!.start;
          addTarget(start, left, mWidget.getX());
          addTargetDimension(end, start, 1, mDimension);
        }
      }
    }
  }

  void computeInsetRatio(List<int> dimensions, int x1, int x2, int y1, int y2,
      double ratio, int side) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    switch (side) {
      case ConstraintWidget.UNKNOWN:
        final candidateX1 = (0.5 + dy * ratio).toInt();
        final candidateY1 = dy;
        final candidateX2 = dx;
        final candidateY2 = (0.5 + dx / ratio).toInt();
        if (candidateX1 <= dx && candidateY1 <= dy) {
          dimensions[ConstraintWidget.HORIZONTAL] = candidateX1;
          dimensions[ConstraintWidget.VERTICAL] = candidateY1;
        } else if (candidateX2 <= dx && candidateY2 <= dy) {
          dimensions[ConstraintWidget.HORIZONTAL] = candidateX2;
          dimensions[ConstraintWidget.VERTICAL] = candidateY2;
        }
        break;
      case ConstraintWidget.HORIZONTAL:
        final horizontalSide = (0.5 + dy * ratio).toInt();
        dimensions[ConstraintWidget.HORIZONTAL] = horizontalSide;
        dimensions[ConstraintWidget.VERTICAL] = dy;
        break;
      case ConstraintWidget.VERTICAL:
        final verticalSide = (0.5 + dx * ratio).toInt();
        dimensions[ConstraintWidget.HORIZONTAL] = dx;
        dimensions[ConstraintWidget.VERTICAL] = verticalSide;
        break;
      default:
        break;
    }
  }

  @override
  void update(Dependency dependency) {
    switch (mRunType) {
      case RunType.start:
        updateRunStart(dependency);
        break;
      case RunType.end:
        updateRunEnd(dependency);
        break;
      case RunType.center:
        updateRunCenter(
            dependency, mWidget.mLeft, mWidget.mRight, ConstraintWidget.HORIZONTAL);
        return;
      default:
        break;
    }

    if (!mDimension.resolved) {
      if (mDimensionBehavior == DimensionBehaviour.matchConstraint) {
        switch (mWidget.mMatchConstraintDefaultWidth) {
          case ConstraintWidget.MATCH_CONSTRAINT_RATIO:
            if (mWidget.mMatchConstraintDefaultHeight ==
                    ConstraintWidget.MATCH_CONSTRAINT_SPREAD ||
                mWidget.mMatchConstraintDefaultHeight ==
                    ConstraintWidget.MATCH_CONSTRAINT_RATIO) {
              final secondStart = mWidget.mVerticalRun!.start;
              final secondEnd = mWidget.mVerticalRun!.end;
              final s1 = mWidget.mLeft.mTarget != null;
              final s2 = mWidget.mTop.mTarget != null;
              final e1 = mWidget.mRight.mTarget != null;
              final e2 = mWidget.mBottom.mTarget != null;

              final definedSide = mWidget.getDimensionRatioSide();

              if (s1 && s2 && e1 && e2) {
                final ratio = mWidget.getDimensionRatio();
                if (secondStart.resolved && secondEnd.resolved) {
                  if (!(start.readyToSolve && end.readyToSolve)) {
                    return;
                  }
                  final x1 = start.mTargets[0].value + start.mMargin;
                  final x2 = end.mTargets[0].value - end.mMargin;
                  final y1 = secondStart.value + secondStart.mMargin;
                  final y2 = secondEnd.value - secondEnd.mMargin;
                  computeInsetRatio(
                      sTempDimensions, x1, x2, y1, y2, ratio, definedSide);
                  mDimension.resolve(sTempDimensions[ConstraintWidget.HORIZONTAL]);
                  mWidget.mVerticalRun!.mDimension
                      .resolve(sTempDimensions[ConstraintWidget.VERTICAL]);
                  return;
                }
                if (start.resolved && end.resolved) {
                  if (!(secondStart.readyToSolve && secondEnd.readyToSolve)) {
                    return;
                  }
                  final x1 = start.value + start.mMargin;
                  final x2 = end.value - end.mMargin;
                  final y1 = secondStart.mTargets[0].value + secondStart.mMargin;
                  final y2 = secondEnd.mTargets[0].value - secondEnd.mMargin;
                  computeInsetRatio(
                      sTempDimensions, x1, x2, y1, y2, ratio, definedSide);
                  mDimension.resolve(sTempDimensions[ConstraintWidget.HORIZONTAL]);
                  mWidget.mVerticalRun!.mDimension
                      .resolve(sTempDimensions[ConstraintWidget.VERTICAL]);
                }
                if (!(start.readyToSolve &&
                    end.readyToSolve &&
                    secondStart.readyToSolve &&
                    secondEnd.readyToSolve)) {
                  return;
                }
                final x1 = start.mTargets[0].value + start.mMargin;
                final x2 = end.mTargets[0].value - end.mMargin;
                final y1 = secondStart.mTargets[0].value + secondStart.mMargin;
                final y2 = secondEnd.mTargets[0].value - secondEnd.mMargin;
                computeInsetRatio(
                    sTempDimensions, x1, x2, y1, y2, ratio, definedSide);
                mDimension.resolve(sTempDimensions[ConstraintWidget.HORIZONTAL]);
                mWidget.mVerticalRun!.mDimension
                    .resolve(sTempDimensions[ConstraintWidget.VERTICAL]);
              } else if (s1 && e1) {
                if (!(start.readyToSolve && end.readyToSolve)) {
                  return;
                }
                final ratio = mWidget.getDimensionRatio();
                final x1 = start.mTargets[0].value + start.mMargin;
                final x2 = end.mTargets[0].value - end.mMargin;

                switch (definedSide) {
                  case ConstraintWidget.UNKNOWN:
                  case ConstraintWidget.HORIZONTAL:
                    final dx = x2 - x1;
                    final ldx = getLimitedDimension(dx, ConstraintWidget.HORIZONTAL);
                    final dy = (0.5 + ldx * ratio).toInt();
                    final ldy = getLimitedDimension(dy, ConstraintWidget.VERTICAL);
                    var fdx = ldx;
                    if (dy != ldy) {
                      fdx = (0.5 + ldy / ratio).toInt();
                    }
                    mDimension.resolve(fdx);
                    mWidget.mVerticalRun!.mDimension.resolve(ldy);
                    break;
                  case ConstraintWidget.VERTICAL:
                    final dx = x2 - x1;
                    final ldx = getLimitedDimension(dx, ConstraintWidget.HORIZONTAL);
                    final dy = (0.5 + ldx / ratio).toInt();
                    final ldy = getLimitedDimension(dy, ConstraintWidget.VERTICAL);
                    var fdx = ldx;
                    if (dy != ldy) {
                      fdx = (0.5 + ldy * ratio).toInt();
                    }
                    mDimension.resolve(fdx);
                    mWidget.mVerticalRun!.mDimension.resolve(ldy);
                    break;
                  default:
                    break;
                }
              } else if (s2 && e2) {
                if (!(secondStart.readyToSolve && secondEnd.readyToSolve)) {
                  return;
                }
                final ratio = mWidget.getDimensionRatio();
                final y1 = secondStart.mTargets[0].value + secondStart.mMargin;
                final y2 = secondEnd.mTargets[0].value - secondEnd.mMargin;

                switch (definedSide) {
                  case ConstraintWidget.UNKNOWN:
                  case ConstraintWidget.VERTICAL:
                    final dy = y2 - y1;
                    final ldy = getLimitedDimension(dy, ConstraintWidget.VERTICAL);
                    final dx = (0.5 + ldy / ratio).toInt();
                    final ldx = getLimitedDimension(dx, ConstraintWidget.HORIZONTAL);
                    var fdy = ldy;
                    if (dx != ldx) {
                      fdy = (0.5 + ldx * ratio).toInt();
                    }
                    mDimension.resolve(ldx);
                    mWidget.mVerticalRun!.mDimension.resolve(fdy);
                    break;
                  case ConstraintWidget.HORIZONTAL:
                    final dy = y2 - y1;
                    final ldy = getLimitedDimension(dy, ConstraintWidget.VERTICAL);
                    final dx = (0.5 + ldy * ratio).toInt();
                    final ldx = getLimitedDimension(dx, ConstraintWidget.HORIZONTAL);
                    var fdy = ldy;
                    if (dx != ldx) {
                      fdy = (0.5 + ldx / ratio).toInt();
                    }
                    mDimension.resolve(ldx);
                    mWidget.mVerticalRun!.mDimension.resolve(fdy);
                    break;
                  default:
                    break;
                }
              }
            } else {
              int size = 0;
              final ratioSide = mWidget.getDimensionRatioSide();
              switch (ratioSide) {
                case ConstraintWidget.HORIZONTAL:
                  size = (0.5 +
                          mWidget.mVerticalRun!.mDimension.value /
                              mWidget.getDimensionRatio())
                      .toInt();
                  break;
                case ConstraintWidget.VERTICAL:
                  size = (0.5 +
                          mWidget.mVerticalRun!.mDimension.value *
                              mWidget.getDimensionRatio())
                      .toInt();
                  break;
                case ConstraintWidget.UNKNOWN:
                  size = (0.5 +
                          mWidget.mVerticalRun!.mDimension.value *
                              mWidget.getDimensionRatio())
                      .toInt();
                  break;
                default:
                  break;
              }
              mDimension.resolve(size);
            }
            break;
          case ConstraintWidget.MATCH_CONSTRAINT_PERCENT:
            final parent = mWidget.getParent();
            if (parent != null) {
              if (parent.mHorizontalRun!.mDimension.resolved) {
                final percent = mWidget.mMatchConstraintPercentWidth;
                final targetDimensionValue = parent.mHorizontalRun!.mDimension.value;
                final size = (0.5 + targetDimensionValue * percent).toInt();
                // Divergence from upstream: percent is clamped by the
                // matchConstraint min/max here. Upstream leaves this resolve
                // unclamped and relies on its solver-first entry to apply the
                // bounds; this engine resolves percent in the graph, so the
                // clamp has to happen at the resolve site. See UPSTREAM.md.
                mDimension.resolve(
                    getLimitedDimension(size, ConstraintWidget.HORIZONTAL));
              }
            }
            break;
          default:
            break;
        }
      }
    }

    if (!(start.readyToSolve && end.readyToSolve)) {
      return;
    }

    if (start.resolved && end.resolved && mDimension.resolved) {
      return;
    }

    if (!mDimension.resolved &&
        mDimensionBehavior == DimensionBehaviour.matchConstraint &&
        mWidget.mMatchConstraintDefaultWidth ==
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD &&
        !mWidget.isInHorizontalChain()) {
      final startTarget = start.mTargets[0];
      final endTarget = end.mTargets[0];
      final startPos = startTarget.value + start.mMargin;
      final endPos = endTarget.value + end.mMargin;
      final distance = endPos - startPos;
      start.resolve(startPos);
      end.resolve(endPos);
      mDimension.resolve(distance);
      return;
    }

    if (!mDimension.resolved &&
        mDimensionBehavior == DimensionBehaviour.matchConstraint &&
        matchConstraintsType == ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
      if (start.mTargets.isNotEmpty && end.mTargets.isNotEmpty) {
        final startTarget = start.mTargets[0];
        final endTarget = end.mTargets[0];
        final startPos = startTarget.value + start.mMargin;
        final endPos = endTarget.value + end.mMargin;
        final availableSpace = endPos - startPos;
        var value = availableSpace < mDimension.wrapValue
            ? availableSpace
            : mDimension.wrapValue;
        final max = mWidget.mMatchConstraintMaxWidth;
        final min = mWidget.mMatchConstraintMinWidth;
        value = min > value ? min : value;
        if (max > 0) {
          value = max < value ? max : value;
        }
        mDimension.resolve(value);
      }
    }

    if (!mDimension.resolved) {
      return;
    }
    // centering
    final startTarget = start.mTargets[0];
    final endTarget = end.mTargets[0];
    var startPos = startTarget.value + start.mMargin;
    var endPos = endTarget.value + end.mMargin;
    var bias = mWidget.getHorizontalBiasPercent();
    if (startTarget == endTarget) {
      startPos = startTarget.value;
      endPos = endTarget.value;
      bias = 0.5;
    }
    final distance = endPos - startPos - mDimension.value;
    start.resolve((0.5 + startPos + distance * bias).toInt());
    end.resolve(start.value + mDimension.value);
  }

  @override
  void applyToWidget() {
    if (start.resolved) {
      mWidget.setX(start.value);
    }
  }
}
