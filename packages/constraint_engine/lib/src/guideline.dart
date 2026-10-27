// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.Guideline (upstream
// pinned in UPSTREAM.md).

import 'constraint_anchor.dart';
import 'constraint_widget.dart';
import 'constraint_widget_container.dart';
import 'jfloat.dart';
import 'linear_system.dart';
import 'solver_variable.dart';

/// A horizontal or vertical line that other widgets constrain to.
///
/// A guideline sits at a fixed distance from its parent's left or top edge
/// ([setGuideBegin]), from its right or bottom edge ([setGuideEnd]), or at a
/// fraction of the parent's size ([setGuidePercent]). It takes no space; add
/// it to the container like any other widget.
class Guideline extends ConstraintWidget {
  /// Orientation of a horizontal guideline: a horizontal line that widgets
  /// constrain their top and bottom anchors to.
  static const int horizontal = 0;

  /// Orientation of a vertical guideline: a vertical line that widgets
  /// constrain their left and right anchors to.
  static const int vertical = 1;

  /// Relative behaviour of a guideline placed at a fraction of the parent's
  /// size; see [getRelativeBehaviour].
  static const int relativePercent = 0;

  /// Relative behaviour of a guideline placed at a distance from the
  /// parent's left or top edge.
  static const int relativeBegin = 1;

  /// Relative behaviour of a guideline placed at a distance from the
  /// parent's right or bottom edge.
  static const int relativeEnd = 2;

  /// Relative behaviour of a guideline with no position set.
  static const int relativeUnknown = -1;

  /// The fraction set by [setGuidePercent], or -1 when unset.
  double mRelativePercent = -1;

  /// The distance set by [setGuideBegin], or -1 when unset.
  int mRelativeBegin = -1;

  /// The distance set by [setGuideEnd], or -1 when unset.
  int mRelativeEnd = -1;
  bool mGuidelineUseRtl = true;

  /// The guideline's single anchor: [mTop] for a horizontal guideline,
  /// [mLeft] for a vertical one.
  late ConstraintAnchor mAnchor = mTop;

  /// The orientation, [horizontal] (the default) or [vertical].
  int mOrientation = horizontal;
  int mMinimumPosition = 0;

  /// Whether [setFinalValue] resolved the guideline's position for the next
  /// solve. [addToSolver] holds the position and clears it. Like Android's,
  /// [resetMeasureState] keeps it: `reset()` (CW 557-621) does not touch it.
  bool mResolved = false;

  /// Creates a horizontal guideline with no position set.
  Guideline() : super() {
    mAnchors.clear();
    mAnchors.add(mAnchor);
    for (var i = 0; i < mListAnchors.length; i++) {
      mListAnchors[i] = mAnchor;
    }
  }

  /// Always true: a [Barrier] uses a guideline whatever its visibility.
  @override
  bool allowedInBarrier() => true;

  /// How the guideline is positioned: [relativePercent], [relativeBegin],
  /// [relativeEnd], or [relativeUnknown] when no position is set.
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

  /// Set the orientation, [horizontal] or [vertical], which also selects the
  /// guideline's anchor ([mAnchor]).
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

  /// The guideline's single anchor ([mAnchor]).
  ConstraintAnchor getGuidelineAnchor() => mAnchor;

  /// The type name of a guideline: `Guideline`.
  @override
  String? getType() => 'Guideline';

  /// Get the orientation: [horizontal] or [vertical].
  int getOrientation() => mOrientation;

  /// Set the minimum position. Kept from upstream; the engine does not read
  /// it.
  void setMinimumPosition(int minimum) => mMinimumPosition = minimum;

  /// Get the minimum position set by [setMinimumPosition].
  int getMinimumPosition() => mMinimumPosition;

  /// The guideline's anchor for [ConstraintAnchorType.left] or
  /// [ConstraintAnchorType.right] when it is vertical, and for
  /// [ConstraintAnchorType.top] or [ConstraintAnchorType.bottom] when it is
  /// horizontal; null for any other type.
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

  /// Position the guideline at the fraction [value] (0 to 1) of the parent's
  /// width for a vertical guideline, or of its height for a horizontal one.
  /// Values of -1 or less are ignored. The fraction is kept as the binary32
  /// value upstream's float holds.
  void setGuidePercent(double value) {
    // Upstream's parameter is a float: the binary32 value is both the one
    // compared and the one stored.
    final percent = f32(value);
    if (percent > -1) {
      mRelativePercent = percent;
      mRelativeBegin = -1;
      mRelativeEnd = -1;
    }
  }

  /// Same as [setGuidePercent], with [value] as a percentage (0 to 100):
  /// upstream's `value / 100f`, a float quotient.
  void setGuidePercentInt(int value) => setGuidePercent(fdiv(fi(value), 100));

  /// Position the guideline [value] from the parent's left edge for a
  /// vertical guideline, or from its top edge for a horizontal one. Negative
  /// values are ignored.
  void setGuideBegin(int value) {
    if (value > -1) {
      mRelativePercent = -1;
      mRelativeBegin = value;
      mRelativeEnd = -1;
    }
  }

  /// Position the guideline [value] from the parent's right edge for a
  /// vertical guideline, or from its bottom edge for a horizontal one.
  /// Negative values are ignored.
  void setGuideEnd(int value) {
    if (value > -1) {
      mRelativePercent = -1;
      mRelativeBegin = -1;
      mRelativeEnd = value;
    }
  }

  /// The fraction set by [setGuidePercent], or -1 when the guideline is not
  /// positioned by percent.
  double getRelativePercent() => mRelativePercent;

  /// The distance set by [setGuideBegin], or -1 when the guideline is not
  /// positioned from the begin edge.
  int getRelativeBegin() => mRelativeBegin;

  /// The distance set by [setGuideEnd], or -1 when the guideline is not
  /// positioned from the end edge.
  int getRelativeEnd() => mRelativeEnd;

  /// Whether the guideline is positioned by percent ([setGuidePercent]).
  bool isPercent() =>
      mRelativePercent != -1 && mRelativeBegin == -1 && mRelativeEnd == -1;

  /// Resolve the guideline at [position]: a final value on its anchor, and
  /// [mResolved] (upstream GL 213-219). The next [addToSolver] holds the
  /// guideline there and clears [mResolved]. Upstream's Direct pass calls
  /// it.
  void setFinalValue(int position) {
    mAnchor.setFinalValue(position);
    mResolved = true;
  }

  /// Whether [setFinalValue] resolved the guideline and no solve has
  /// consumed it yet: [mResolved] (upstream GL 223-225), whatever the axis.
  @override
  bool isResolvedHorizontally() => mResolved;

  /// Same as [isResolvedHorizontally] (upstream GL 228-230).
  @override
  bool isResolvedVertically() => mResolved;

  /// [ConstraintWidget.resetMeasureState], then the size set to 0 x 0, as
  /// Android's `reset()` sets it: a guideline's size is never configuration
  /// (Android's view layer sets none, and [updateFromSolver] writes it from
  /// the parent's). [mResolved] is kept, as `reset()` keeps it.
  @override
  void resetMeasureState() {
    super.resetMeasureState();
    mWidth = 0;
    mHeight = 0;
  }

  @override
  void addToSolver(LinearSystem system, bool optimize) {
    final parent = getParent() as ConstraintWidgetContainer?;
    if (parent == null) {
      return;
    }
    var begin = parent.getAnchor(ConstraintAnchorType.left)!;
    var end = parent.getAnchor(ConstraintAnchorType.right)!;
    var parentWrapContent =
        mParent != null &&
        mParent!.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] ==
            DimensionBehaviour.wrapContent;
    if (mOrientation == horizontal) {
      begin = parent.getAnchor(ConstraintAnchorType.top)!;
      end = parent.getAnchor(ConstraintAnchorType.bottom)!;
      parentWrapContent =
          mParent != null &&
          mParent!.mListDimensionBehaviors[ConstraintWidget.VERTICAL] ==
              DimensionBehaviour.wrapContent;
    }
    if (mResolved && mAnchor.hasFinalValue()) {
      final guide = system.createObjectVariable(mAnchor)!;
      system.addEqualityConstant(guide, mAnchor.getFinalValue());
      if (mRelativeBegin != -1) {
        if (parentWrapContent) {
          system.addGreaterThan(
            system.createObjectVariable(end)!,
            guide,
            0,
            SolverVariable.STRENGTH_EQUALITY,
          );
        }
      } else if (mRelativeEnd != -1) {
        if (parentWrapContent) {
          final parentRight = system.createObjectVariable(end)!;
          system.addGreaterThan(
            guide,
            system.createObjectVariable(begin)!,
            0,
            SolverVariable.STRENGTH_EQUALITY,
          );
          system.addGreaterThan(
            parentRight,
            guide,
            0,
            SolverVariable.STRENGTH_EQUALITY,
          );
        }
      }
      mResolved = false;
      return;
    }
    if (mRelativeBegin != -1) {
      final guide = system.createObjectVariable(mAnchor)!;
      final parentLeft = system.createObjectVariable(begin)!;
      system.addEquality(
        guide,
        parentLeft,
        mRelativeBegin,
        SolverVariable.STRENGTH_FIXED,
      );
      if (parentWrapContent) {
        system.addGreaterThan(
          system.createObjectVariable(end)!,
          guide,
          0,
          SolverVariable.STRENGTH_EQUALITY,
        );
      }
    } else if (mRelativeEnd != -1) {
      final guide = system.createObjectVariable(mAnchor)!;
      final parentRight = system.createObjectVariable(end)!;
      system.addEquality(
        guide,
        parentRight,
        -mRelativeEnd,
        SolverVariable.STRENGTH_FIXED,
      );
      if (parentWrapContent) {
        system.addGreaterThan(
          guide,
          system.createObjectVariable(begin)!,
          0,
          SolverVariable.STRENGTH_EQUALITY,
        );
        system.addGreaterThan(
          parentRight,
          guide,
          0,
          SolverVariable.STRENGTH_EQUALITY,
        );
      }
    } else if (mRelativePercent != -1) {
      final guide = system.createObjectVariable(mAnchor)!;
      final parentRight = system.createObjectVariable(end)!;
      system.addConstraint(
        LinearSystem.createRowDimensionPercent(
          system,
          guide,
          parentRight,
          mRelativePercent,
        ),
      );
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
