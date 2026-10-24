// Copyright (C) 2017 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.Barrier (upstream pinned
// in UPSTREAM.md).

import 'dart:math' as math;

import 'constraint_anchor.dart';
import 'constraint_widget.dart';
import 'guideline.dart';
import 'helper_widget.dart';
import 'linear_system.dart';
import 'solver_variable.dart';

class Barrier extends HelperWidget {
  static const int left = 0;
  static const int right = 1;
  static const int top = 2;
  static const int bottom = 3;

  int mBarrierType = left;
  bool mAllowsGoneWidget = true;
  int mMargin = 0;
  bool mResolved = false;

  Barrier() : super();

  Barrier.named(String debugName) : super() {
    setDebugName(debugName);
  }

  @override
  bool allowedInBarrier() => true;

  int getBarrierType() => mBarrierType;
  void setBarrierType(int barrierType) => mBarrierType = barrierType;

  void setAllowsGoneWidget(bool allowsGoneWidget) =>
      mAllowsGoneWidget = allowsGoneWidget;
  bool getAllowsGoneWidget() => mAllowsGoneWidget;

  void setMargin(int margin) => mMargin = margin;
  int getMargin() => mMargin;

  int getOrientation() {
    switch (mBarrierType) {
      case left:
      case right:
        return ConstraintWidget.HORIZONTAL;
      case top:
      case bottom:
        return ConstraintWidget.VERTICAL;
    }
    return ConstraintWidget.UNKNOWN;
  }

  void markWidgets() {
    for (var i = 0; i < mWidgetsCount; i++) {
      final widget = mWidgets[i]!;
      if (!mAllowsGoneWidget && !widget.allowedInBarrier()) {
        continue;
      }
      if (mBarrierType == left || mBarrierType == right) {
        widget.setInBarrier(ConstraintWidget.HORIZONTAL, true);
      } else if (mBarrierType == top || mBarrierType == bottom) {
        widget.setInBarrier(ConstraintWidget.VERTICAL, true);
      }
    }
  }

  static const bool _USE_RESOLUTION = true;
  static const bool _USE_RELAX_GONE = false;

  bool allSolved() {
    if (!_USE_RESOLUTION) {
      return false;
    }
    var hasAllWidgetsResolved = true;
    for (var i = 0; i < mWidgetsCount; i++) {
      final widget = mWidgets[i]!;
      if (!mAllowsGoneWidget && !widget.allowedInBarrier()) {
        continue;
      }
      if ((mBarrierType == left || mBarrierType == right) &&
          !widget.isResolvedHorizontally()) {
        hasAllWidgetsResolved = false;
      } else if ((mBarrierType == top || mBarrierType == bottom) &&
          !widget.isResolvedVertically()) {
        hasAllWidgetsResolved = false;
      }
    }

    if (hasAllWidgetsResolved && mWidgetsCount > 0) {
      // we're done!
      var barrierPosition = 0;
      var initialized = false;
      for (var i = 0; i < mWidgetsCount; i++) {
        final widget = mWidgets[i]!;
        if (!mAllowsGoneWidget && !widget.allowedInBarrier()) {
          continue;
        }
        if (!initialized) {
          if (mBarrierType == left) {
            barrierPosition =
                widget.getAnchor(ConstraintAnchorType.left)!.getFinalValue();
          } else if (mBarrierType == right) {
            barrierPosition =
                widget.getAnchor(ConstraintAnchorType.right)!.getFinalValue();
          } else if (mBarrierType == top) {
            barrierPosition =
                widget.getAnchor(ConstraintAnchorType.top)!.getFinalValue();
          } else if (mBarrierType == bottom) {
            barrierPosition =
                widget.getAnchor(ConstraintAnchorType.bottom)!.getFinalValue();
          }
          initialized = true;
        }
        if (mBarrierType == left) {
          barrierPosition = math.min(barrierPosition,
              widget.getAnchor(ConstraintAnchorType.left)!.getFinalValue());
        } else if (mBarrierType == right) {
          barrierPosition = math.max(barrierPosition,
              widget.getAnchor(ConstraintAnchorType.right)!.getFinalValue());
        } else if (mBarrierType == top) {
          barrierPosition = math.min(barrierPosition,
              widget.getAnchor(ConstraintAnchorType.top)!.getFinalValue());
        } else if (mBarrierType == bottom) {
          barrierPosition = math.max(barrierPosition,
              widget.getAnchor(ConstraintAnchorType.bottom)!.getFinalValue());
        }
      }
      barrierPosition += mMargin;
      if (mBarrierType == left || mBarrierType == right) {
        setFinalHorizontal(barrierPosition, barrierPosition);
      } else {
        setFinalVertical(barrierPosition, barrierPosition);
      }
      mResolved = true;
      return true;
    }
    return false;
  }

  @override
  void addToSolver(LinearSystem system, bool optimize) {
    ConstraintAnchor position;
    mListAnchors[ConstraintWidget.ANCHOR_LEFT] = mLeft;
    mListAnchors[ConstraintWidget.ANCHOR_TOP] = mTop;
    mListAnchors[ConstraintWidget.ANCHOR_RIGHT] = mRight;
    mListAnchors[ConstraintWidget.ANCHOR_BOTTOM] = mBottom;
    for (var i = 0; i < mListAnchors.length; i++) {
      mListAnchors[i].mSolverVariable = system.createObjectVariable(mListAnchors[i]);
    }
    if (mBarrierType >= 0 && mBarrierType < 4) {
      position = mListAnchors[mBarrierType];
    } else {
      return;
    }

    if (_USE_RESOLUTION) {
      if (!mResolved) {
        allSolved();
      }
      if (mResolved) {
        mResolved = false;
        if (mBarrierType == left || mBarrierType == right) {
          system.addEqualityConstant(mLeft.mSolverVariable!, mX);
          system.addEqualityConstant(mRight.mSolverVariable!, mX);
        } else if (mBarrierType == top || mBarrierType == bottom) {
          system.addEqualityConstant(mTop.mSolverVariable!, mY);
          system.addEqualityConstant(mBottom.mSolverVariable!, mY);
        }
        return;
      }
    }

    // We have to handle the case where some of the elements referenced in the
    // barrier are set as match_constraint; we have to take it in account to
    // set the strength of the barrier.
    var hasMatchConstraintWidgets = false;
    for (var i = 0; i < mWidgetsCount; i++) {
      final widget = mWidgets[i]!;
      if (!mAllowsGoneWidget && !widget.allowedInBarrier()) {
        continue;
      }
      if ((mBarrierType == left || mBarrierType == right) &&
          (widget.getHorizontalDimensionBehaviour() ==
              DimensionBehaviour.matchConstraint) &&
          widget.mLeft.mTarget != null &&
          widget.mRight.mTarget != null) {
        hasMatchConstraintWidgets = true;
        break;
      } else if ((mBarrierType == top || mBarrierType == bottom) &&
          (widget.getVerticalDimensionBehaviour() ==
              DimensionBehaviour.matchConstraint) &&
          widget.mTop.mTarget != null &&
          widget.mBottom.mTarget != null) {
        hasMatchConstraintWidgets = true;
        break;
      }
    }

    final hasHorizontalCenteredDependents =
        mLeft.hasCenteredDependents() || mRight.hasCenteredDependents();
    final hasVerticalCenteredDependents =
        mTop.hasCenteredDependents() || mBottom.hasCenteredDependents();
    final applyEqualityOnReferences = !hasMatchConstraintWidgets &&
        ((mBarrierType == left && hasHorizontalCenteredDependents) ||
            (mBarrierType == top && hasVerticalCenteredDependents) ||
            (mBarrierType == right && hasHorizontalCenteredDependents) ||
            (mBarrierType == bottom && hasVerticalCenteredDependents));

    var equalityOnReferencesStrength = SolverVariable.STRENGTH_EQUALITY;
    if (!applyEqualityOnReferences) {
      equalityOnReferencesStrength = SolverVariable.STRENGTH_HIGHEST;
    }
    for (var i = 0; i < mWidgetsCount; i++) {
      final widget = mWidgets[i]!;
      if (!mAllowsGoneWidget && !widget.allowedInBarrier()) {
        continue;
      }
      final target =
          system.createObjectVariable(widget.mListAnchors[mBarrierType])!;
      widget.mListAnchors[mBarrierType].mSolverVariable = target;
      var margin = 0;
      if (widget.mListAnchors[mBarrierType].mTarget != null &&
          identical(widget.mListAnchors[mBarrierType].mTarget!.mOwner, this)) {
        margin += widget.mListAnchors[mBarrierType].mMargin;
      }
      if (mBarrierType == left || mBarrierType == top) {
        system.addLowerBarrier(position.mSolverVariable!, target,
            mMargin - margin, hasMatchConstraintWidgets);
      } else {
        system.addGreaterBarrier(position.mSolverVariable!, target,
            mMargin + margin, hasMatchConstraintWidgets);
      }
      if (_USE_RELAX_GONE) {
        if (widget.getVisibility() != ConstraintWidget.GONE ||
            widget is Guideline ||
            widget is Barrier) {
          system.addEquality(position.mSolverVariable!, target, mMargin + margin,
              equalityOnReferencesStrength);
        }
      } else {
        system.addEquality(position.mSolverVariable!, target, mMargin + margin,
            equalityOnReferencesStrength);
      }
    }

    const barrierParentStrength = SolverVariable.STRENGTH_HIGHEST;
    const barrierParentStrengthOpposite = SolverVariable.STRENGTH_NONE;

    if (mBarrierType == left) {
      system.addEquality(mRight.mSolverVariable!, mLeft.mSolverVariable!, 0,
          SolverVariable.STRENGTH_FIXED);
      system.addEquality(mLeft.mSolverVariable!, mParent!.mRight.mSolverVariable!,
          0, barrierParentStrength);
      system.addEquality(mLeft.mSolverVariable!, mParent!.mLeft.mSolverVariable!,
          0, barrierParentStrengthOpposite);
    } else if (mBarrierType == right) {
      system.addEquality(mLeft.mSolverVariable!, mRight.mSolverVariable!, 0,
          SolverVariable.STRENGTH_FIXED);
      system.addEquality(mLeft.mSolverVariable!, mParent!.mLeft.mSolverVariable!,
          0, barrierParentStrength);
      system.addEquality(mLeft.mSolverVariable!, mParent!.mRight.mSolverVariable!,
          0, barrierParentStrengthOpposite);
    } else if (mBarrierType == top) {
      system.addEquality(mBottom.mSolverVariable!, mTop.mSolverVariable!, 0,
          SolverVariable.STRENGTH_FIXED);
      system.addEquality(mTop.mSolverVariable!, mParent!.mBottom.mSolverVariable!,
          0, barrierParentStrength);
      system.addEquality(mTop.mSolverVariable!, mParent!.mTop.mSolverVariable!,
          0, barrierParentStrengthOpposite);
    } else if (mBarrierType == bottom) {
      system.addEquality(mTop.mSolverVariable!, mBottom.mSolverVariable!, 0,
          SolverVariable.STRENGTH_FIXED);
      system.addEquality(mTop.mSolverVariable!, mParent!.mTop.mSolverVariable!,
          0, barrierParentStrength);
      system.addEquality(mTop.mSolverVariable!, mParent!.mBottom.mSolverVariable!,
          0, barrierParentStrengthOpposite);
    }
  }

  @override
  String toString() {
    final b = StringBuffer('[Barrier] ${getDebugName()} {');
    for (var i = 0; i < mWidgetsCount; i++) {
      if (i > 0) {
        b.write(', ');
      }
      b.write(mWidgets[i]!.getDebugName());
    }
    b.write('}');
    return b.toString();
  }
}
