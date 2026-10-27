// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.VerticalWidgetRun

import '../constraint_anchor.dart';
import '../constraint_widget.dart';
import '../helper.dart';
import '../jfloat.dart';
import 'baseline_dimension_dependency.dart';
import 'dependency.dart';
import 'dependency_node.dart';
import 'dimension_dependency.dart';
import 'widget_run.dart';

class VerticalWidgetRun extends WidgetRun {
  static const bool forceUse = true;
  late DependencyNode baseline;
  DimensionDependency? mBaselineDimension;

  VerticalWidgetRun(ConstraintWidget widget) : super(widget) {
    baseline = DependencyNode(this);
    start.mType = DependencyNodeType.top;
    end.mType = DependencyNodeType.bottom;
    baseline.mType = DependencyNodeType.baseline;
    orientation = ConstraintWidget.VERTICAL;
  }

  @override
  String toString() => 'VerticalRun ${mWidget.getDebugName()}';

  @override
  void clear() {
    mRunGroup = null;
    start.clear();
    end.clear();
    baseline.clear();
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
    baseline.clear();
    baseline.resolved = false;
    mDimension.resolved = false;
  }

  @override
  bool supportsWrapComputation() {
    if (mDimensionBehavior == DimensionBehaviour.matchConstraint) {
      if (mWidget.mMatchConstraintDefaultHeight ==
          ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
        return true;
      }
      return false;
    }
    return true;
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
          dependency,
          mWidget.mTop,
          mWidget.mBottom,
          ConstraintWidget.VERTICAL,
        );
        return;
      default:
        break;
    }
    if (forceUse || dependency == mDimension) {
      if (mDimension.readyToSolve && !mDimension.resolved) {
        if (mDimensionBehavior == DimensionBehaviour.matchConstraint) {
          switch (mWidget.mMatchConstraintDefaultHeight) {
            case ConstraintWidget.MATCH_CONSTRAINT_RATIO:
              if (mWidget.mHorizontalRun!.mDimension.resolved) {
                int size = 0;
                final ratioSide = mWidget.getDimensionRatioSide();
                switch (ratioSide) {
                  case ConstraintWidget.HORIZONTAL:
                    size = jint(
                      fadd(
                        0.5,
                        fmul(
                          fi(mWidget.mHorizontalRun!.mDimension.value),
                          mWidget.getDimensionRatio(),
                        ),
                      ),
                    );
                    break;
                  case ConstraintWidget.VERTICAL:
                    size = jint(
                      fadd(
                        0.5,
                        fdiv(
                          fi(mWidget.mHorizontalRun!.mDimension.value),
                          mWidget.getDimensionRatio(),
                        ),
                      ),
                    );
                    break;
                  case ConstraintWidget.UNKNOWN:
                    size = jint(
                      fadd(
                        0.5,
                        fdiv(
                          fi(mWidget.mHorizontalRun!.mDimension.value),
                          mWidget.getDimensionRatio(),
                        ),
                      ),
                    );
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
                if (parent.mVerticalRun!.mDimension.resolved) {
                  final percent = mWidget.mMatchConstraintPercentHeight;
                  final targetDimensionValue =
                      parent.mVerticalRun!.mDimension.value;
                  // (int) (0.5f + targetDimensionValue * percent), in floats.
                  final size = jint(
                    fadd(0.5, fmul(fi(targetDimensionValue), percent)),
                  );
                  mDimension.resolve(size);
                }
              }
              break;
            default:
              break;
          }
        }
      }
    }
    if (!(start.readyToSolve && end.readyToSolve)) {
      return;
    }
    if (start.resolved && end.resolved && mDimension.resolved) {
      return;
    }

    // Upstream reads the width's match-constraint default here.
    if (!mDimension.resolved &&
        mDimensionBehavior == DimensionBehaviour.matchConstraint &&
        mWidget.mMatchConstraintDefaultWidth ==
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD &&
        !mWidget.isInVerticalChain()) {
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
        if (availableSpace < mDimension.wrapValue) {
          mDimension.resolve(availableSpace);
        } else {
          mDimension.resolve(mDimension.wrapValue);
        }
      }
    }

    if (!mDimension.resolved) {
      return;
    }
    // centering
    if (start.mTargets.isNotEmpty && end.mTargets.isNotEmpty) {
      final startTarget = start.mTargets[0];
      final endTarget = end.mTargets[0];
      var startPos = startTarget.value + start.mMargin;
      var endPos = endTarget.value + end.mMargin;
      var bias = mWidget.getVerticalBiasPercent();
      if (startTarget == endTarget) {
        startPos = startTarget.value;
        endPos = endTarget.value;
        bias = 0.5;
      }
      final distance = endPos - startPos - mDimension.value;
      // (int) (0.5f + startPos + distance * bias), in floats.
      start.resolve(
        jint(fadd(fadd(0.5, fi(startPos)), fmul(fi(distance), bias))),
      );
      end.resolve(start.value + mDimension.value);
    }
  }

  @override
  void apply() {
    if (mWidget.measured) {
      mDimension.resolve(mWidget.getHeight());
    }
    if (!mDimension.resolved) {
      mDimensionBehavior = mWidget.getVerticalDimensionBehaviour();
      if (mWidget.hasBaseline()) {
        mBaselineDimension = BaselineDimensionDependency(this);
      }
      if (mDimensionBehavior != DimensionBehaviour.matchConstraint) {
        if (mDimensionBehavior == DimensionBehaviour.matchParent) {
          final parent = mWidget.getParent();
          if (parent != null &&
              parent.getVerticalDimensionBehaviour() ==
                  DimensionBehaviour.fixed) {
            final resolvedDimension =
                parent.getHeight() -
                mWidget.mTop.getMargin() -
                mWidget.mBottom.getMargin();
            addTarget(
              start,
              parent.mVerticalRun!.start,
              mWidget.mTop.getMargin(),
            );
            addTarget(
              end,
              parent.mVerticalRun!.end,
              -mWidget.mBottom.getMargin(),
            );
            mDimension.resolve(resolvedDimension);
            return;
          }
        }
        if (mDimensionBehavior == DimensionBehaviour.fixed) {
          mDimension.resolve(mWidget.getHeight());
        }
      }
    } else {
      if (mDimensionBehavior == DimensionBehaviour.matchParent) {
        final parent = mWidget.getParent();
        if (parent != null &&
            parent.getVerticalDimensionBehaviour() ==
                DimensionBehaviour.fixed) {
          addTarget(
            start,
            parent.mVerticalRun!.start,
            mWidget.mTop.getMargin(),
          );
          addTarget(
            end,
            parent.mVerticalRun!.end,
            -mWidget.mBottom.getMargin(),
          );
          return;
        }
      }
    }

    if (mDimension.resolved && mWidget.measured) {
      if (mWidget.mListAnchors[ConstraintWidget.ANCHOR_TOP].mTarget != null &&
          mWidget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM].mTarget !=
              null) {
        // <-s-e->
        if (mWidget.isInVerticalChain()) {
          start.mMargin = mWidget.mListAnchors[ConstraintWidget.ANCHOR_TOP]
              .getMargin();
          end.mMargin = -mWidget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM]
              .getMargin();
        } else {
          final startTarget = getTarget(
            mWidget.mListAnchors[ConstraintWidget.ANCHOR_TOP],
          );
          if (startTarget != null) {
            addTarget(
              start,
              startTarget,
              mWidget.mListAnchors[ConstraintWidget.ANCHOR_TOP].getMargin(),
            );
          }
          final endTarget = getTarget(
            mWidget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM],
          );
          if (endTarget != null) {
            addTarget(
              end,
              endTarget,
              -mWidget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM].getMargin(),
            );
          }
          start.delegateToWidgetRun = true;
          end.delegateToWidgetRun = true;
        }
        if (mWidget.hasBaseline()) {
          addTarget(baseline, start, mWidget.getBaselineDistance());
        }
      } else if (mWidget.mListAnchors[ConstraintWidget.ANCHOR_TOP].mTarget !=
          null) {
        // <-s-e
        final target = getTarget(
          mWidget.mListAnchors[ConstraintWidget.ANCHOR_TOP],
        );
        if (target != null) {
          addTarget(
            start,
            target,
            mWidget.mListAnchors[ConstraintWidget.ANCHOR_TOP].getMargin(),
          );
          addTarget(end, start, mDimension.value);
          if (mWidget.hasBaseline()) {
            addTarget(baseline, start, mWidget.getBaselineDistance());
          }
        }
      } else if (mWidget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM].mTarget !=
          null) {
        //   s-e->
        final target = getTarget(
          mWidget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM],
        );
        if (target != null) {
          addTarget(
            end,
            target,
            -mWidget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM].getMargin(),
          );
          addTarget(start, end, -mDimension.value);
        }
        if (mWidget.hasBaseline()) {
          addTarget(baseline, start, mWidget.getBaselineDistance());
        }
      } else if (mWidget
              .mListAnchors[ConstraintWidget.ANCHOR_BASELINE]
              .mTarget !=
          null) {
        final target = getTarget(
          mWidget.mListAnchors[ConstraintWidget.ANCHOR_BASELINE],
        );
        if (target != null) {
          // As upstream, the baseline link's margin is not applied here.
          addTarget(baseline, target, 0);
          addTarget(start, baseline, -mWidget.getBaselineDistance());
          addTarget(end, start, mDimension.value);
        }
      } else {
        // no connections
        if (mWidget is! Helper &&
            mWidget.getParent() != null &&
            mWidget.getAnchor(ConstraintAnchorType.center)!.mTarget == null) {
          final top = mWidget.getParent()!.mVerticalRun!.start;
          addTarget(start, top, mWidget.getY());
          addTarget(end, start, mDimension.value);
          if (mWidget.hasBaseline()) {
            addTarget(baseline, start, mWidget.getBaselineDistance());
          }
        }
      }
    } else {
      if (!mDimension.resolved &&
          mDimensionBehavior == DimensionBehaviour.matchConstraint) {
        switch (mWidget.mMatchConstraintDefaultHeight) {
          case ConstraintWidget.MATCH_CONSTRAINT_RATIO:
            if (!mWidget.isInVerticalChain()) {
              if (mWidget.mMatchConstraintDefaultWidth ==
                  ConstraintWidget.MATCH_CONSTRAINT_RATIO) {
                break;
              }
              final targetDimension = mWidget.mHorizontalRun!.mDimension;
              mDimension.mTargets.add(targetDimension);
              targetDimension.mDependencies.add(mDimension);
              mDimension.delegateToWidgetRun = true;
              mDimension.mDependencies.add(start);
              mDimension.mDependencies.add(end);
            }
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
      } else {
        mDimension.addDependency(this);
      }
      if (mWidget.mListAnchors[ConstraintWidget.ANCHOR_TOP].mTarget != null &&
          mWidget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM].mTarget !=
              null) {
        // <-s-d-e->
        if (mWidget.isInVerticalChain()) {
          start.mMargin = mWidget.mListAnchors[ConstraintWidget.ANCHOR_TOP]
              .getMargin();
          end.mMargin = -mWidget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM]
              .getMargin();
        } else {
          final startTarget = getTarget(
            mWidget.mListAnchors[ConstraintWidget.ANCHOR_TOP],
          );
          final endTarget = getTarget(
            mWidget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM],
          );
          if (startTarget != null) {
            startTarget.addDependency(this);
          }
          if (endTarget != null) {
            endTarget.addDependency(this);
          }
          mRunType = RunType.center;
        }
        if (mWidget.hasBaseline()) {
          addTargetDimension(baseline, start, 1, mBaselineDimension!);
        }
      } else if (mWidget.mListAnchors[ConstraintWidget.ANCHOR_TOP].mTarget !=
          null) {
        // <-s<-d<-e
        final target = getTarget(
          mWidget.mListAnchors[ConstraintWidget.ANCHOR_TOP],
        );
        if (target != null) {
          addTarget(
            start,
            target,
            mWidget.mListAnchors[ConstraintWidget.ANCHOR_TOP].getMargin(),
          );
          addTargetDimension(end, start, 1, mDimension);
          if (mWidget.hasBaseline()) {
            addTargetDimension(baseline, start, 1, mBaselineDimension!);
          }
          if (mDimensionBehavior == DimensionBehaviour.matchConstraint) {
            if (mWidget.getDimensionRatio() > 0) {
              if (mWidget.mHorizontalRun!.mDimensionBehavior ==
                  DimensionBehaviour.matchConstraint) {
                mWidget.mHorizontalRun!.mDimension.mDependencies.add(
                  mDimension,
                );
                mDimension.mTargets.add(mWidget.mHorizontalRun!.mDimension);
                mDimension.updateDelegate = this;
              }
            }
          }
        }
      } else if (mWidget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM].mTarget !=
          null) {
        //   s->d->e->
        final target = getTarget(
          mWidget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM],
        );
        if (target != null) {
          addTarget(
            end,
            target,
            -mWidget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM].getMargin(),
          );
          addTargetDimension(start, end, -1, mDimension);
          if (mWidget.hasBaseline()) {
            addTargetDimension(baseline, start, 1, mBaselineDimension!);
          }
        }
      } else if (mWidget
              .mListAnchors[ConstraintWidget.ANCHOR_BASELINE]
              .mTarget !=
          null) {
        final target = getTarget(
          mWidget.mListAnchors[ConstraintWidget.ANCHOR_BASELINE],
        );
        if (target != null) {
          addTarget(baseline, target, 0);
          // Port-only guard: upstream reads mBaselineDimension here
          // unconditionally and throws a NullPointerException for a widget
          // whose run never got a baseline dimension (apply creates one for a
          // widget with a baseline whose height is not resolved yet, and the
          // run keeps it from one graph to the next; BasicMeasure does not
          // catch the exception). The widget's top and bottom stay unwired,
          // and unresolved.
          if (mBaselineDimension != null) {
            addTargetDimension(start, baseline, -1, mBaselineDimension!);
            addTargetDimension(end, start, 1, mDimension);
          }
        }
      } else {
        // no connections
        if (mWidget is! Helper && mWidget.getParent() != null) {
          final top = mWidget.getParent()!.mVerticalRun!.start;
          addTarget(start, top, mWidget.getY());
          addTargetDimension(end, start, 1, mDimension);
          if (mWidget.hasBaseline()) {
            addTargetDimension(baseline, start, 1, mBaselineDimension!);
          }
          if (mDimensionBehavior == DimensionBehaviour.matchConstraint) {
            if (mWidget.getDimensionRatio() > 0) {
              if (mWidget.mHorizontalRun!.mDimensionBehavior ==
                  DimensionBehaviour.matchConstraint) {
                mWidget.mHorizontalRun!.mDimension.mDependencies.add(
                  mDimension,
                );
                mDimension.mTargets.add(mWidget.mHorizontalRun!.mDimension);
                mDimension.updateDelegate = this;
              }
            }
          }
        }
      }

      if (mDimension.mTargets.isEmpty) {
        mDimension.readyToSolve = true;
      }
    }
  }

  @override
  void applyToWidget() {
    if (start.resolved) {
      mWidget.setY(start.value);
    }
  }
}
