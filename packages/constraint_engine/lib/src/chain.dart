// Copyright (C) 2017 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.Chain (upstream pinned
// in UPSTREAM.md). The USE_CHAIN_OPTIMIZATION direct-solve path (statically
// disabled upstream) and debug output are omitted.

import 'chain_head.dart';
import 'constraint_anchor.dart';
import 'constraint_widget.dart';
import 'constraint_widget_container.dart';
import 'linear_system.dart';
import 'solver_variable.dart';

/// Chain management and constraints creation.
class Chain {
  static const bool USE_CHAIN_OPTIMIZATION = false;

  /// Apply specific rules for dealing with chains of widgets: a chain is a
  /// list of widgets linked together with bi-directional connections.
  static void applyChainConstraints(
    ConstraintWidgetContainer constraintWidgetContainer,
    LinearSystem system,
    List<ConstraintWidget>? widgets,
    int orientation,
  ) {
    int offset;
    int chainsSize;
    List<ChainHead?> chainsArray;
    if (orientation == ConstraintWidget.HORIZONTAL) {
      offset = 0;
      chainsSize = constraintWidgetContainer.mHorizontalChainsSize;
      chainsArray = constraintWidgetContainer.mHorizontalChainsArray;
    } else {
      offset = 2;
      chainsSize = constraintWidgetContainer.mVerticalChainsSize;
      chainsArray = constraintWidgetContainer.mVerticalChainsArray;
    }

    for (var i = 0; i < chainsSize; i++) {
      final first = chainsArray[i]!;
      // we have to make sure we define the ChainHead here, otherwise the
      // values we use may not be correctly initialized (as we initialize them
      // in the ConstraintWidget.addToSolver())
      first.define();
      if (widgets == null || widgets.contains(first.mFirst)) {
        _applyChainConstraints(
          constraintWidgetContainer,
          system,
          orientation,
          offset,
          first,
        );
      }
    }
  }

  static void _applyChainConstraints(
    ConstraintWidgetContainer container,
    LinearSystem system,
    int orientation,
    int offset,
    ChainHead chainHead,
  ) {
    final first = chainHead.mFirst;
    final last = chainHead.mLast;
    final firstVisibleWidget = chainHead.mFirstVisibleWidget;
    var lastVisibleWidget = chainHead.mLastVisibleWidget;
    final head = chainHead.mHead!;

    var widget = first;
    ConstraintWidget? next;
    var done = false;

    var totalWeights = chainHead.mTotalWeight;

    final isWrapContent =
        container.mListDimensionBehaviors[orientation] ==
        DimensionBehaviour.wrapContent;
    var isChainSpread = false;
    var isChainSpreadInside = false;
    var isChainPacked = false;

    if (orientation == ConstraintWidget.HORIZONTAL) {
      isChainSpread =
          head.mHorizontalChainStyle == ConstraintWidget.CHAIN_SPREAD;
      isChainSpreadInside =
          head.mHorizontalChainStyle == ConstraintWidget.CHAIN_SPREAD_INSIDE;
      isChainPacked =
          head.mHorizontalChainStyle == ConstraintWidget.CHAIN_PACKED;
    } else {
      isChainSpread = head.mVerticalChainStyle == ConstraintWidget.CHAIN_SPREAD;
      isChainSpreadInside =
          head.mVerticalChainStyle == ConstraintWidget.CHAIN_SPREAD_INSIDE;
      isChainPacked = head.mVerticalChainStyle == ConstraintWidget.CHAIN_PACKED;
    }

    // This traversal will:
    // - set up some basic ordering constraints
    // - build a linked list of matched constraints widgets
    while (!done) {
      final begin = widget.mListAnchors[offset];

      var strength = SolverVariable.STRENGTH_HIGHEST;
      if (isChainPacked) {
        strength = SolverVariable.STRENGTH_LOW;
      }
      var margin = begin.getMargin();
      final isSpreadOnly =
          widget.mListDimensionBehaviors[orientation] ==
              DimensionBehaviour.matchConstraint &&
          widget.mResolvedMatchConstraintDefault[orientation] ==
              ConstraintWidget.MATCH_CONSTRAINT_SPREAD;

      if (begin.mTarget != null && !identical(widget, first)) {
        margin += begin.mTarget!.getMargin();
      }

      if (isChainPacked &&
          !identical(widget, first) &&
          !identical(widget, firstVisibleWidget)) {
        strength = SolverVariable.STRENGTH_FIXED;
      }

      if (begin.mTarget != null) {
        if (identical(widget, firstVisibleWidget)) {
          system.addGreaterThan(
            begin.mSolverVariable!,
            begin.mTarget!.mSolverVariable!,
            margin,
            SolverVariable.STRENGTH_BARRIER,
          );
        } else {
          system.addGreaterThan(
            begin.mSolverVariable!,
            begin.mTarget!.mSolverVariable!,
            margin,
            SolverVariable.STRENGTH_FIXED,
          );
        }
        if (isSpreadOnly && !isChainPacked) {
          strength = SolverVariable.STRENGTH_EQUALITY;
        }
        if (identical(widget, firstVisibleWidget) &&
            isChainPacked &&
            widget.isInBarrier(orientation)) {
          strength = SolverVariable.STRENGTH_EQUALITY;
        }
        system.addEquality(
          begin.mSolverVariable!,
          begin.mTarget!.mSolverVariable!,
          margin,
          strength,
        );
      }

      if (isWrapContent) {
        if (widget.getVisibility() != ConstraintWidget.GONE &&
            widget.mListDimensionBehaviors[orientation] ==
                DimensionBehaviour.matchConstraint) {
          system.addGreaterThan(
            widget.mListAnchors[offset + 1].mSolverVariable!,
            widget.mListAnchors[offset].mSolverVariable!,
            0,
            SolverVariable.STRENGTH_EQUALITY,
          );
        }
        system.addGreaterThan(
          widget.mListAnchors[offset].mSolverVariable!,
          container.mListAnchors[offset].mSolverVariable!,
          0,
          SolverVariable.STRENGTH_FIXED,
        );
      }

      // go to the next widget
      final nextAnchor = widget.mListAnchors[offset + 1].mTarget;
      if (nextAnchor != null) {
        next = nextAnchor.mOwner;
        if (next.mListAnchors[offset].mTarget == null ||
            !identical(next.mListAnchors[offset].mTarget!.mOwner, widget)) {
          next = null;
        }
      } else {
        next = null;
      }
      if (next != null) {
        widget = next;
      } else {
        done = true;
      }
    }

    // Make sure we have constraints for the last anchors / targets
    if (lastVisibleWidget != null &&
        last.mListAnchors[offset + 1].mTarget != null) {
      final end = lastVisibleWidget.mListAnchors[offset + 1];
      final isSpreadOnly =
          lastVisibleWidget.mListDimensionBehaviors[orientation] ==
              DimensionBehaviour.matchConstraint &&
          lastVisibleWidget.mResolvedMatchConstraintDefault[orientation] ==
              ConstraintWidget.MATCH_CONSTRAINT_SPREAD;
      if (isSpreadOnly &&
          !isChainPacked &&
          identical(end.mTarget!.mOwner, container)) {
        system.addEquality(
          end.mSolverVariable!,
          end.mTarget!.mSolverVariable!,
          -end.getMargin(),
          SolverVariable.STRENGTH_EQUALITY,
        );
      } else if (isChainPacked && identical(end.mTarget!.mOwner, container)) {
        system.addEquality(
          end.mSolverVariable!,
          end.mTarget!.mSolverVariable!,
          -end.getMargin(),
          SolverVariable.STRENGTH_HIGHEST,
        );
      }
      system.addLowerThan(
        end.mSolverVariable!,
        last.mListAnchors[offset + 1].mTarget!.mSolverVariable!,
        -end.getMargin(),
        SolverVariable.STRENGTH_BARRIER,
      );
    }

    // ... and make sure the root end is constrained in wrap content.
    if (isWrapContent) {
      system.addGreaterThan(
        container.mListAnchors[offset + 1].mSolverVariable!,
        last.mListAnchors[offset + 1].mSolverVariable!,
        last.mListAnchors[offset + 1].getMargin(),
        SolverVariable.STRENGTH_FIXED,
      );
    }

    // Now, let's apply the centering / spreading for matched constraints
    final listMatchConstraints = chainHead.mWeightedMatchConstraintsWidgets;
    if (listMatchConstraints != null) {
      final count = listMatchConstraints.length;
      if (count > 1) {
        ConstraintWidget? lastMatch;
        double lastWeight = 0;

        if (chainHead.mHasUndefinedWeights &&
            !chainHead.mHasComplexMatchWeights) {
          totalWeights = chainHead.mWidgetsMatchCount.toDouble();
        }

        for (var i = 0; i < count; i++) {
          final match = listMatchConstraints[i];
          var currentWeight = match.mWeight[orientation];

          if (currentWeight < 0) {
            if (chainHead.mHasComplexMatchWeights) {
              system.addEquality(
                match.mListAnchors[offset + 1].mSolverVariable!,
                match.mListAnchors[offset].mSolverVariable!,
                0,
                SolverVariable.STRENGTH_HIGHEST,
              );
              continue;
            }
            currentWeight = 1;
          }
          if (currentWeight == 0) {
            system.addEquality(
              match.mListAnchors[offset + 1].mSolverVariable!,
              match.mListAnchors[offset].mSolverVariable!,
              0,
              SolverVariable.STRENGTH_FIXED,
            );
            continue;
          }

          if (lastMatch != null) {
            final begin = lastMatch.mListAnchors[offset].mSolverVariable!;
            final end = lastMatch.mListAnchors[offset + 1].mSolverVariable!;
            final nextBegin = match.mListAnchors[offset].mSolverVariable!;
            final nextEnd = match.mListAnchors[offset + 1].mSolverVariable!;
            final row = system.createRow();
            row.createRowEqualMatchDimensions(
              lastWeight,
              totalWeights,
              currentWeight,
              begin,
              end,
              nextBegin,
              nextEnd,
            );
            system.addConstraint(row);
          }

          lastMatch = match;
          lastWeight = currentWeight;
        }
      }
    }

    // Finally, let's apply the specific rules dealing with the different
    // chain types

    if (firstVisibleWidget != null &&
        (identical(firstVisibleWidget, lastVisibleWidget) || isChainPacked)) {
      var begin = first.mListAnchors[offset];
      var end = last.mListAnchors[offset + 1];
      final beginTarget = begin.mTarget?.mSolverVariable;
      final endTarget = end.mTarget?.mSolverVariable;
      begin = firstVisibleWidget.mListAnchors[offset];
      if (lastVisibleWidget != null) {
        end = lastVisibleWidget.mListAnchors[offset + 1];
      }
      if (beginTarget != null && endTarget != null) {
        var bias = 0.5;
        if (orientation == ConstraintWidget.HORIZONTAL) {
          bias = head.mHorizontalBiasPercent;
        } else {
          bias = head.mVerticalBiasPercent;
        }
        final beginMargin = begin.getMargin();
        final endMargin = end.getMargin();
        system.addCentering(
          begin.mSolverVariable!,
          beginTarget,
          beginMargin,
          bias,
          endTarget,
          end.mSolverVariable!,
          endMargin,
          SolverVariable.STRENGTH_CENTERING,
        );
      }
    } else if (isChainSpread && firstVisibleWidget != null) {
      // for chain spread, we need to add equal dimensions
      // in between *visible* widgets
      ConstraintWidget? spreadWidget = firstVisibleWidget;
      var previousVisibleWidget = firstVisibleWidget;
      final applyFixedEquality =
          chainHead.mWidgetsMatchCount > 0 &&
          (chainHead.mWidgetsCount == chainHead.mWidgetsMatchCount);
      while (spreadWidget != null) {
        next = spreadWidget.mNextChainWidget[orientation];
        while (next != null && next.getVisibility() == ConstraintWidget.GONE) {
          next = next.mNextChainWidget[orientation];
        }
        if (next != null || identical(spreadWidget, lastVisibleWidget)) {
          final beginAnchor = spreadWidget.mListAnchors[offset];
          final begin = beginAnchor.mSolverVariable;
          var beginTarget = beginAnchor.mTarget?.mSolverVariable;
          if (!identical(previousVisibleWidget, spreadWidget)) {
            beginTarget =
                previousVisibleWidget.mListAnchors[offset + 1].mSolverVariable;
          } else if (identical(spreadWidget, firstVisibleWidget)) {
            beginTarget = first.mListAnchors[offset].mTarget?.mSolverVariable;
          }

          ConstraintAnchor? beginNextAnchor;
          SolverVariable? beginNext;
          SolverVariable? beginNextTarget;
          var beginMargin = beginAnchor.getMargin();
          var nextMargin = spreadWidget.mListAnchors[offset + 1].getMargin();

          if (next != null) {
            beginNextAnchor = next.mListAnchors[offset];
            beginNext = beginNextAnchor.mSolverVariable;
          } else {
            beginNextAnchor = last.mListAnchors[offset + 1].mTarget;
            if (beginNextAnchor != null) {
              beginNext = beginNextAnchor.mSolverVariable;
            }
          }
          beginNextTarget =
              spreadWidget.mListAnchors[offset + 1].mSolverVariable;

          if (beginNextAnchor != null) {
            nextMargin += beginNextAnchor.getMargin();
          }
          beginMargin += previousVisibleWidget.mListAnchors[offset + 1]
              .getMargin();
          if (begin != null &&
              beginTarget != null &&
              beginNext != null &&
              beginNextTarget != null) {
            var margin1 = beginMargin;
            if (identical(spreadWidget, firstVisibleWidget)) {
              margin1 = firstVisibleWidget.mListAnchors[offset].getMargin();
            }
            var margin2 = nextMargin;
            if (identical(spreadWidget, lastVisibleWidget)) {
              margin2 = lastVisibleWidget!.mListAnchors[offset + 1].getMargin();
            }
            var strength = SolverVariable.STRENGTH_EQUALITY;
            if (applyFixedEquality) {
              strength = SolverVariable.STRENGTH_FIXED;
            }
            system.addCentering(
              begin,
              beginTarget,
              margin1,
              0.5,
              beginNext,
              beginNextTarget,
              margin2,
              strength,
            );
          }
        }
        if (spreadWidget.getVisibility() != ConstraintWidget.GONE) {
          previousVisibleWidget = spreadWidget;
        }
        spreadWidget = next;
      }
    } else if (isChainSpreadInside && firstVisibleWidget != null) {
      // for chain spread inside, we need to add equal dimensions in between
      // *visible* widgets
      ConstraintWidget? insideWidget = firstVisibleWidget;
      var previousVisibleWidget = firstVisibleWidget;
      final applyFixedEquality =
          chainHead.mWidgetsMatchCount > 0 &&
          (chainHead.mWidgetsCount == chainHead.mWidgetsMatchCount);
      while (insideWidget != null) {
        next = insideWidget.mNextChainWidget[orientation];
        while (next != null && next.getVisibility() == ConstraintWidget.GONE) {
          next = next.mNextChainWidget[orientation];
        }
        if (!identical(insideWidget, firstVisibleWidget) &&
            !identical(insideWidget, lastVisibleWidget) &&
            next != null) {
          if (identical(next, lastVisibleWidget)) {
            next = null;
          }
          final beginAnchor = insideWidget.mListAnchors[offset];
          final begin = beginAnchor.mSolverVariable;
          SolverVariable? beginTarget =
              previousVisibleWidget.mListAnchors[offset + 1].mSolverVariable;
          ConstraintAnchor? beginNextAnchor;
          SolverVariable? beginNext;
          SolverVariable? beginNextTarget;
          var beginMargin = beginAnchor.getMargin();
          var nextMargin = insideWidget.mListAnchors[offset + 1].getMargin();

          if (next != null) {
            beginNextAnchor = next.mListAnchors[offset];
            beginNext = beginNextAnchor.mSolverVariable;
            beginNextTarget = beginNextAnchor.mTarget?.mSolverVariable;
          } else {
            beginNextAnchor = lastVisibleWidget!.mListAnchors[offset];
            beginNext = beginNextAnchor.mSolverVariable;
            beginNextTarget =
                insideWidget.mListAnchors[offset + 1].mSolverVariable;
          }

          nextMargin += beginNextAnchor.getMargin();
          beginMargin += previousVisibleWidget.mListAnchors[offset + 1]
              .getMargin();
          var strength = SolverVariable.STRENGTH_HIGHEST;
          if (applyFixedEquality) {
            strength = SolverVariable.STRENGTH_FIXED;
          }
          if (begin != null &&
              beginTarget != null &&
              beginNext != null &&
              beginNextTarget != null) {
            system.addCentering(
              begin,
              beginTarget,
              beginMargin,
              0.5,
              beginNext,
              beginNextTarget,
              nextMargin,
              strength,
            );
          }
        }
        if (insideWidget.getVisibility() != ConstraintWidget.GONE) {
          previousVisibleWidget = insideWidget;
        }
        insideWidget = next;
      }
      final begin = firstVisibleWidget.mListAnchors[offset];
      final beginTarget = first.mListAnchors[offset].mTarget;
      final end = lastVisibleWidget!.mListAnchors[offset + 1];
      final endTarget = last.mListAnchors[offset + 1].mTarget;
      const endPointsStrength = SolverVariable.STRENGTH_EQUALITY;
      if (beginTarget != null) {
        if (!identical(firstVisibleWidget, lastVisibleWidget)) {
          system.addEquality(
            begin.mSolverVariable!,
            beginTarget.mSolverVariable!,
            begin.getMargin(),
            endPointsStrength,
          );
        } else if (endTarget != null) {
          system.addCentering(
            begin.mSolverVariable!,
            beginTarget.mSolverVariable!,
            begin.getMargin(),
            0.5,
            end.mSolverVariable!,
            endTarget.mSolverVariable!,
            end.getMargin(),
            endPointsStrength,
          );
        }
      }
      if (endTarget != null &&
          !identical(firstVisibleWidget, lastVisibleWidget)) {
        system.addEquality(
          end.mSolverVariable!,
          endTarget.mSolverVariable!,
          -end.getMargin(),
          endPointsStrength,
        );
      }
    }

    // final centering, necessary if the chain is larger than
    // the available space...
    if ((isChainSpread || isChainSpreadInside) &&
        firstVisibleWidget != null &&
        !identical(firstVisibleWidget, lastVisibleWidget)) {
      var begin = firstVisibleWidget.mListAnchors[offset];
      lastVisibleWidget ??= firstVisibleWidget;
      var end = lastVisibleWidget.mListAnchors[offset + 1];
      final beginTarget = begin.mTarget?.mSolverVariable;
      var endTarget = end.mTarget?.mSolverVariable;
      if (!identical(last, lastVisibleWidget)) {
        final realEnd = last.mListAnchors[offset + 1];
        endTarget = realEnd.mTarget?.mSolverVariable;
      }
      if (identical(firstVisibleWidget, lastVisibleWidget)) {
        begin = firstVisibleWidget.mListAnchors[offset];
        end = firstVisibleWidget.mListAnchors[offset + 1];
      }
      if (beginTarget != null && endTarget != null) {
        const bias = 0.5;
        final beginMargin = begin.getMargin();
        final endMargin = lastVisibleWidget.mListAnchors[offset + 1]
            .getMargin();
        system.addCentering(
          begin.mSolverVariable!,
          beginTarget,
          beginMargin,
          bias,
          endTarget,
          end.mSolverVariable!,
          endMargin,
          SolverVariable.STRENGTH_EQUALITY,
        );
      }
    }
  }
}
