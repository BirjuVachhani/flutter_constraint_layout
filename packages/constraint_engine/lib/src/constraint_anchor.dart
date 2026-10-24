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
  /// No anchor.
  none,

  /// The left edge.
  left,

  /// The top edge.
  top,

  /// The right edge.
  right,

  /// The bottom edge.
  bottom,

  /// The text baseline.
  baseline,

  /// The center point, used for circular positioning (see
  /// [ConstraintWidget.connectCircularConstraint]).
  center,

  /// The horizontal center, midway between the left and right edges.
  centerX,

  /// The vertical center, midway between the top and bottom edges.
  centerY,
}

/// Models a constraint relation. Widgets contain anchors, and a constraint
/// between two widgets is made by connecting one anchor to another. A
/// connected anchor holds its target ([mTarget]).
class ConstraintAnchor {
  /// The [mGoneMargin] value meaning no gone margin is set (Java's
  /// `Integer.MIN_VALUE`).
  static const int unsetGoneMargin = -0x80000000; // Integer.MIN_VALUE

  /// The widget this anchor belongs to.
  final ConstraintWidget mOwner;

  /// Which part of [mOwner] this anchor represents.
  final ConstraintAnchorType mType;

  /// The anchor this one is connected to, or null when it is not connected.
  ConstraintAnchor? mTarget;

  /// The margin to keep from [mTarget]; [getMargin] applies visibility.
  int mMargin = 0;

  /// The margin used instead of [mMargin] when the target's widget is gone,
  /// or [unsetGoneMargin] for none.
  int mGoneMargin = unsetGoneMargin;

  int _finalValue = 0;
  bool _hasFinalValue = false;

  /// The solver variable of this anchor's position, created on demand by the
  /// solver; see [getSolverVariable].
  SolverVariable? mSolverVariable;

  /// Anchors currently targeting this anchor.
  Set<ConstraintAnchor>? mDependents;

  /// Creates an anchor of type [mType] owned by [mOwner]. Widgets create
  /// their own anchors; see [ConstraintWidget.getAnchor].
  ConstraintAnchor(this.mOwner, this.mType);

  /// The anchors connected to this one, or null when there are none.
  Set<ConstraintAnchor>? getDependents() => mDependents;

  /// Whether any anchor is connected to this one.
  bool hasDependents() {
    final dependents = mDependents;
    if (dependents == null) {
      return false;
    }
    return dependents.isNotEmpty;
  }

  /// Whether an anchor connected to this one belongs to a widget that is
  /// also connected on the opposite side of the same axis (so it is centered
  /// between two targets).
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

  /// Record [finalValue] as this anchor's resolved position.
  void setFinalValue(int finalValue) {
    _finalValue = finalValue;
    _hasFinalValue = true;
  }

  /// The resolved position set by [setFinalValue], or 0 when there is none.
  int getFinalValue() => _hasFinalValue ? _finalValue : 0;

  /// Clear the resolved position set by [setFinalValue].
  void resetFinalResolution() {
    _hasFinalValue = false;
    _finalValue = 0;
  }

  /// Whether a resolved position is set; see [setFinalValue].
  bool hasFinalValue() => _hasFinalValue;

  /// Return the anchor's owner: the widget it belongs to.
  ConstraintWidget getOwner() => mOwner;

  /// Return the type of the anchor.
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

  /// Return the connection's target, or null if not connected.
  ConstraintAnchor? getTarget() => mTarget;

  /// Reset the anchor's connection: clear the target, the margin and gone
  /// margin, and the resolved position, and forget the anchors connected to
  /// this one.
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
  ///
  /// A null [toAnchor] resets the anchor. Unless [forceConnection] is true, a
  /// connection that [isValidConnection] rejects is refused, and the method
  /// returns false.
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

  /// Returns the connection status of this anchor: true if it is connected
  /// to another one.
  bool isConnected() => mTarget != null;

  /// Checks if the connection to [anchor] is valid.
  ///
  /// Anchors of the same type can connect, baselines only when both widgets
  /// have a baseline. Otherwise left and right connect to each other (and to
  /// the centerX of a [Guideline]), top and bottom likewise (and to the
  /// centerY of a [Guideline]), a baseline to anything but left or right,
  /// and center to anything but baseline, centerX, or centerY. A null
  /// [anchor] is invalid.
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

  /// Set the margin of the connection, if there is one.
  void setMargin(int margin) {
    if (isConnected()) {
      mMargin = margin;
    }
  }

  /// Set the gone margin of the connection, if there is one: the margin used
  /// when the target's widget is gone.
  void setGoneMargin(int margin) {
    if (isConnected()) {
      mGoneMargin = margin;
    }
  }

  /// Returns true if this anchor is a vertical one: top, bottom, baseline,
  /// or centerY.
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
