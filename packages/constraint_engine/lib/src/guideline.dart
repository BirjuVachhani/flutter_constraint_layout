// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.Guideline (upstream
// pinned in UPSTREAM.md).

import 'constraint_anchor.dart';
import 'constraint_widget.dart';
import 'constraint_widget_container.dart';
import 'linear_system.dart';
import 'solver_variable.dart';

class Guideline extends ConstraintWidget {
  static const int horizontal = 0;
  static const int vertical = 1;

  static const int relativePercent = 0;
  static const int relativeBegin = 1;
  static const int relativeEnd = 2;
  static const int relativeUnknown = -1;

  double mRelativePercent = -1;
  int mRelativeBegin = -1;
  int mRelativeEnd = -1;
  bool mGuidelineUseRtl = true;

  late ConstraintAnchor mAnchor = mTop;
  int mOrientation = horizontal;
  int mMinimumPosition = 0;
  bool mResolved = false;

  Guideline() : super() {
    mAnchors.clear();
    mAnchors.add(mAnchor);
    for (var i = 0; i < mListAnchors.length; i++) {
      mListAnchors[i] = mAnchor;
    }
  }

  @override
  bool allowedInBarrier() => true;

  int getRelativeBehaviour() {
    if (mRelativePercent != -1) {
      return relativePercent;
    }
    if (mRelativeBegin != -1) {
      return relativeBegin;
    }
    if (mRelativeEnd != -1) {
      return relativeEnd;
    }
    return relativeUnknown;
  }

  void setOrientation(int orientation) {
    if (mOrientation == orientation) {
      return;
    }
    mOrientation = orientation;
    mAnchors.clear();
    if (mOrientation == vertical) {
      mAnchor = mLeft;
    } else {
      mAnchor = mTop;
    }
    mAnchors.add(mAnchor);
    for (var i = 0; i < mListAnchors.length; i++) {
      mListAnchors[i] = mAnchor;
    }
  }

  ConstraintAnchor getGuidelineAnchor() => mAnchor;

  @override
  String? getType() => 'Guideline';

  int getOrientation() => mOrientation;

  void setMinimumPosition(int minimum) => mMinimumPosition = minimum;
  int getMinimumPosition() => mMinimumPosition;

  @override
  ConstraintAnchor? getAnchor(ConstraintAnchorType anchorType) {
    switch (anchorType) {
      case ConstraintAnchorType.left:
      case ConstraintAnchorType.right:
        if (mOrientation == vertical) {
          return mAnchor;
        }
        return null;
      case ConstraintAnchorType.top:
      case ConstraintAnchorType.bottom:
        if (mOrientation == horizontal) {
          return mAnchor;
        }
        return null;
      default:
        return null;
    }
  }

  void setGuidePercent(double value) {
    if (value > -1) {
      mRelativePercent = value;
      mRelativeBegin = -1;
      mRelativeEnd = -1;
    }
  }

  void setGuidePercentInt(int value) => setGuidePercent(value / 100.0);

  void setGuideBegin(int value) {
    if (value > -1) {
      mRelativePercent = -1;
      mRelativeBegin = value;
      mRelativeEnd = -1;
    }
  }

  void setGuideEnd(int value) {
    if (value > -1) {
      mRelativePercent = -1;
      mRelativeBegin = -1;
      mRelativeEnd = value;
    }
  }

  double getRelativePercent() => mRelativePercent;
  int getRelativeBegin() => mRelativeBegin;
  int getRelativeEnd() => mRelativeEnd;

  bool isPercent() =>
      mRelativePercent != -1 && mRelativeBegin == -1 && mRelativeEnd == -1;

  @override
  void addToSolver(LinearSystem system, bool optimize) {
    final parent = getParent() as ConstraintWidgetContainer?;
    if (parent == null) {
      return;
    }
    var begin = parent.getAnchor(ConstraintAnchorType.left)!;
    var end = parent.getAnchor(ConstraintAnchorType.right)!;
    var parentWrapContent = mParent != null &&
        mParent!.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] ==
            DimensionBehaviour.wrapContent;
    if (mOrientation == horizontal) {
      begin = parent.getAnchor(ConstraintAnchorType.top)!;
      end = parent.getAnchor(ConstraintAnchorType.bottom)!;
      parentWrapContent = mParent != null &&
          mParent!.mListDimensionBehaviors[ConstraintWidget.VERTICAL] ==
              DimensionBehaviour.wrapContent;
    }
    if (mResolved && mAnchor.hasFinalValue()) {
      final guide = system.createObjectVariable(mAnchor)!;
      system.addEqualityConstant(guide, mAnchor.getFinalValue());
      if (mRelativeBegin != -1) {
        if (parentWrapContent) {
          system.addGreaterThan(system.createObjectVariable(end)!, guide, 0,
              SolverVariable.STRENGTH_EQUALITY);
        }
      } else if (mRelativeEnd != -1) {
        if (parentWrapContent) {
          final parentRight = system.createObjectVariable(end)!;
          system.addGreaterThan(guide, system.createObjectVariable(begin)!, 0,
              SolverVariable.STRENGTH_EQUALITY);
          system.addGreaterThan(parentRight, guide, 0,
              SolverVariable.STRENGTH_EQUALITY);
        }
      }
      mResolved = false;
      return;
    }
    if (mRelativeBegin != -1) {
      final guide = system.createObjectVariable(mAnchor)!;
      final parentLeft = system.createObjectVariable(begin)!;
      system.addEquality(guide, parentLeft, mRelativeBegin,
          SolverVariable.STRENGTH_FIXED);
      if (parentWrapContent) {
        system.addGreaterThan(system.createObjectVariable(end)!, guide, 0,
            SolverVariable.STRENGTH_EQUALITY);
      }
    } else if (mRelativeEnd != -1) {
      final guide = system.createObjectVariable(mAnchor)!;
      final parentRight = system.createObjectVariable(end)!;
      system.addEquality(guide, parentRight, -mRelativeEnd,
          SolverVariable.STRENGTH_FIXED);
      if (parentWrapContent) {
        system.addGreaterThan(guide, system.createObjectVariable(begin)!, 0,
            SolverVariable.STRENGTH_EQUALITY);
        system.addGreaterThan(parentRight, guide, 0,
            SolverVariable.STRENGTH_EQUALITY);
      }
    } else if (mRelativePercent != -1) {
      final guide = system.createObjectVariable(mAnchor)!;
      final parentRight = system.createObjectVariable(end)!;
      system.addConstraint(LinearSystem.createRowDimensionPercent(
          system, guide, parentRight, mRelativePercent));
    }
  }

  @override
  void updateFromSolver(LinearSystem system, bool optimize) {
    if (getParent() == null) {
      return;
    }
    final value = system.getObjectVariableValue(mAnchor);
    if (mOrientation == vertical) {
      setX(value);
      setY(0);
      setHeight(getParent()!.getHeight());
      setWidth(0);
    } else {
      setX(0);
      setY(value);
      setWidth(getParent()!.getWidth());
      setHeight(0);
    }
  }
}
