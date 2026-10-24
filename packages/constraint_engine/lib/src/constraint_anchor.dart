// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.ConstraintAnchor
// (grouping machinery omitted).

import 'cache.dart';
import 'constraint_widget.dart';
import 'guideline.dart';
import 'solver_variable.dart';

/// The type of an anchor (which edge of a widget it represents).
enum ConstraintAnchorType {
  none,
  left,
  top,
  right,
  bottom,
  baseline,
  center,
  centerX,
  centerY,
}

/// Models a constraint relation. Widgets contain anchors, and a constraint
/// between two widgets is made by connecting one anchor to another.
class ConstraintAnchor {
  static const int unsetGoneMargin = -0x80000000; // Integer.MIN_VALUE

  final ConstraintWidget mOwner;
  final ConstraintAnchorType mType;
  ConstraintAnchor? mTarget;
  int mMargin = 0;
  int mGoneMargin = unsetGoneMargin;

  int _finalValue = 0;
  bool _hasFinalValue = false;

  SolverVariable? mSolverVariable;

  /// Anchors currently targeting this anchor.
  Set<ConstraintAnchor>? mDependents;

  ConstraintAnchor(this.mOwner, this.mType);

  Set<ConstraintAnchor>? getDependents() => mDependents;

  bool hasDependents() {
    final dependents = mDependents;
    if (dependents == null) {
      return false;
    }
    return dependents.isNotEmpty;
  }

  bool hasCenteredDependents() {
    final dependents = mDependents;
    if (dependents == null) {
      return false;
    }
    for (final anchor in dependents) {
      final opposite = anchor.getOpposite();
      if (opposite != null && opposite.isConnected()) {
        return true;
      }
    }
    return false;
  }

  /// Return the solver variable for this anchor.
  SolverVariable? getSolverVariable() => mSolverVariable;

  /// Reset (or lazily create) the solver variable.
  void resetSolverVariable(Cache cache) {
    if (mSolverVariable == null) {
      mSolverVariable = SolverVariable.typed(
        SolverVariableType.unrestricted,
        null,
      );
    } else {
      mSolverVariable!.reset();
    }
  }

  void setFinalValue(int finalValue) {
    _finalValue = finalValue;
    _hasFinalValue = true;
  }

  int getFinalValue() => _hasFinalValue ? _finalValue : 0;

  void resetFinalResolution() {
    _hasFinalValue = false;
    _finalValue = 0;
  }

  bool hasFinalValue() => _hasFinalValue;

  ConstraintWidget getOwner() => mOwner;

  ConstraintAnchorType getType() => mType;

  /// The connection's margin, honoring GONE visibility of self and target.
  int getMargin() {
    if (mOwner.getVisibility() == ConstraintWidget.GONE) {
      return 0;
    }
    if (mGoneMargin != unsetGoneMargin &&
        mTarget != null &&
        mTarget!.mOwner.getVisibility() == ConstraintWidget.GONE) {
      return mGoneMargin;
    }
    return mMargin;
  }

  ConstraintAnchor? getTarget() => mTarget;

  void reset() {
    final targetDependents = mTarget?.mDependents;
    if (targetDependents != null) {
      targetDependents.remove(this);
      if (targetDependents.isEmpty) {
        mTarget!.mDependents = null;
      }
    }
    mDependents = null;
    mTarget = null;
    mMargin = 0;
    mGoneMargin = unsetGoneMargin;
    _hasFinalValue = false;
    _finalValue = 0;
  }

  /// Connects this anchor to [toAnchor] with the given [margin]/[goneMargin].
  bool connect(
    ConstraintAnchor? toAnchor,
    int margin, [
    int goneMargin = unsetGoneMargin,
    bool forceConnection = false,
  ]) {
    if (toAnchor == null) {
      reset();
      return true;
    }
    if (!forceConnection && !isValidConnection(toAnchor)) {
      return false;
    }
    mTarget = toAnchor;
    (mTarget!.mDependents ??= <ConstraintAnchor>{}).add(this);
    mMargin = margin;
    mGoneMargin = goneMargin;
    return true;
  }

  bool isConnected() => mTarget != null;

  bool isValidConnection(ConstraintAnchor? anchor) {
    if (anchor == null) {
      return false;
    }
    final target = anchor.getType();
    if (target == mType) {
      if (mType == ConstraintAnchorType.baseline &&
          (!anchor.getOwner().hasBaseline() || !getOwner().hasBaseline())) {
        return false;
      }
      return true;
    }
    switch (mType) {
      case ConstraintAnchorType.center:
        return target != ConstraintAnchorType.baseline &&
            target != ConstraintAnchorType.centerX &&
            target != ConstraintAnchorType.centerY;
      case ConstraintAnchorType.left:
      case ConstraintAnchorType.right:
        var isCompatible =
            target == ConstraintAnchorType.left ||
            target == ConstraintAnchorType.right;
        if (anchor.getOwner() is Guideline) {
          isCompatible = isCompatible || target == ConstraintAnchorType.centerX;
        }
        return isCompatible;
      case ConstraintAnchorType.top:
      case ConstraintAnchorType.bottom:
        var isCompatible =
            target == ConstraintAnchorType.top ||
            target == ConstraintAnchorType.bottom;
        if (anchor.getOwner() is Guideline) {
          isCompatible = isCompatible || target == ConstraintAnchorType.centerY;
        }
        return isCompatible;
      case ConstraintAnchorType.baseline:
        if (target == ConstraintAnchorType.left ||
            target == ConstraintAnchorType.right) {
          return false;
        }
        return true;
      case ConstraintAnchorType.centerX:
      case ConstraintAnchorType.centerY:
      case ConstraintAnchorType.none:
        return false;
    }
  }

  void setMargin(int margin) {
    if (isConnected()) {
      mMargin = margin;
    }
  }

  void setGoneMargin(int margin) {
    if (isConnected()) {
      mGoneMargin = margin;
    }
  }

  bool isVerticalAnchor() {
    switch (mType) {
      case ConstraintAnchorType.left:
      case ConstraintAnchorType.right:
      case ConstraintAnchorType.center:
      case ConstraintAnchorType.centerX:
        return false;
      case ConstraintAnchorType.centerY:
      case ConstraintAnchorType.top:
      case ConstraintAnchorType.bottom:
      case ConstraintAnchorType.baseline:
      case ConstraintAnchorType.none:
        return true;
    }
  }

  /// The opposite anchor on the same axis (left<->right, top<->bottom).
  ConstraintAnchor? getOpposite() {
    switch (mType) {
      case ConstraintAnchorType.left:
        return mOwner.mRight;
      case ConstraintAnchorType.right:
        return mOwner.mLeft;
      case ConstraintAnchorType.top:
        return mOwner.mBottom;
      case ConstraintAnchorType.bottom:
        return mOwner.mTop;
      case ConstraintAnchorType.baseline:
      case ConstraintAnchorType.center:
      case ConstraintAnchorType.centerX:
      case ConstraintAnchorType.centerY:
      case ConstraintAnchorType.none:
        return null;
    }
  }

  @override
  String toString() => '${mOwner.getDebugName()}:${mType.name}';
}
