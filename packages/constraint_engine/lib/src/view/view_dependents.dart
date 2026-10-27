// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.widget.ConstraintLayout
// (setChildrenConstraints, applyConstraintsFromLayoutParams and
// setWidgetBaseline; upstream pinned in UPSTREAM.md): the anchor dependents
// the view layer leaves, rebuilt from the links the widgets already hold.

import '../constraint_anchor.dart';
import '../constraint_widget.dart';
import '../constraint_widget_container.dart';
import '../virtual_layout.dart';

/// Rebuild the anchor state that Android's `setChildrenConstraints` leaves
/// (ConstraintLayout.java 1249-1351 and 1354-1620) from the links the
/// widgets of [container] hold now.
///
/// Android resets every child widget and connects its links again on every
/// measure of a changed hierarchy, so its anchors' dependents (the anchors
/// that target each one) list the live links only, in child order. An
/// engine user that edits the links in place instead leaves stale entries
/// behind (a reconnected anchor stays in its old target's dependents) and
/// keeps the order of its own calls. This function gives the view layer's
/// state, in four steps:
///
/// 1. Members. The anchors of every member of a [VirtualLayout] child are
///    reset ([ConstraintWidget.resetAnchors]), dropping the links a
///    `Flow` made in its previous solve, as Android's `reset()` does.
///    Android then applies the members' layout params again. Links of a
///    member's own are not supported: they are dropped at every measure,
///    the first one included, where Android's layout params would connect
///    them again (and, with `OPTIMIZATION_DIRECT`, its `Direct` pass could
///    place the member by them before the flow links it).
/// 2. Clear. Every dependents set of the container and of the children is
///    dropped.
/// 3. Register. Child by child, in child order, and within a child in
///    [ConstraintWidget.mAnchors] order, every anchor with a target is
///    added to its target's dependents, an insertion-ordered set: the order
///    Android's connections are made in (left before right; top, bottom,
///    baseline), which a Java run with `-XX:hashCode=2` iterates in. Before
///    a child that has a baseline link registers its own anchors, its top
///    and bottom anchors are reset, as `setWidgetBaseline` does after
///    connecting the baseline (CL 1617-1618): that drops the child's own top
///    and bottom links and the dependents that earlier children registered
///    there, while later children register normally. The margins of a
///    match-parent vertical axis are kept: the view layer sets them again
///    right after (CL 1566-1568), and a match-parent axis reads them
///    whether or not the anchor is linked.
/// 4. Seed. A child whose baseline is linked to an anchor of a child (not
///    of the container) gets [ConstraintWidget.setHasBaseline], and so does
///    the target's owner when the target is its baseline
///    (`setWidgetBaseline`, CL 1606-1616).
///
/// The view layer only makes a baseline link to a child (CL 1603-1605); a
/// baseline link to the container is treated as any other baseline link in
/// step 3 and seeds nothing in step 4. The view layer's precedence among
/// links (a circle link replaces the others, CL 1429) is the caller's job:
/// this function registers whatever links the widgets hold. The container's
/// own links, if any, are not registered (it has none in a view layout).
///
/// Calling it twice in a row gives the same state as calling it once.
void rebuildViewDependents(ConstraintWidgetContainer container) {
  final children = container.getChildren();
  final childCount = children.length;

  // 1. Members: Android's reset() of every child drops the links a Flow made
  // in its previous solve (Flow.java 495 and 1361 reset and connect them).
  for (var i = 0; i < childCount; i++) {
    final child = children[i];
    if (child is VirtualLayout) {
      final members = child.mWidgets;
      for (var m = 0; m < child.mWidgetsCount; m++) {
        members[m]?.resetAnchors();
      }
    }
  }

  // 2. Clear. reset() drops the dependents of all eight anchors of every
  // child, and the children's resets empty the container's.
  _clearDependents(container);
  for (var i = 0; i < childCount; i++) {
    _clearDependents(children[i]);
  }

  // 3. Register, in the order applyConstraintsFromLayoutParams connects.
  for (var i = 0; i < childCount; i++) {
    final child = children[i];
    if (child.mBaseline.mTarget != null) {
      final matchParent =
          child.mListDimensionBehaviors[ConstraintWidget.VERTICAL] ==
          DimensionBehaviour.matchParent;
      _resetForBaseline(child.mTop, matchParent);
      _resetForBaseline(child.mBottom, matchParent);
    }
    final anchors = child.mAnchors;
    for (var a = 0; a < anchors.length; a++) {
      final anchor = anchors[a];
      final target = anchor.mTarget;
      if (target != null) {
        (target.mDependents ??= <ConstraintAnchor>{}).add(anchor);
      }
    }
  }

  // 4. Seed hasBaseline as setWidgetBaseline does. The order does not
  // matter: every seed sets the flag to true.
  Set<ConstraintWidget>? childSet;
  for (var i = 0; i < childCount; i++) {
    final child = children[i];
    final target = child.mBaseline.mTarget;
    if (target == null) {
      continue;
    }
    final owner = target.mOwner;
    if (identical(owner, container)) {
      continue;
    }
    childSet ??= Set<ConstraintWidget>.identity()..addAll(children);
    if (!childSet.contains(owner)) {
      continue;
    }
    if (target.mType == ConstraintAnchorType.baseline) {
      owner.setHasBaseline(true);
    }
    child.setHasBaseline(true);
  }
}

/// Drops the dependents of every anchor [widget] owns: all eight, as
/// ConstraintWidget.reset() resets them (a guideline's
/// [ConstraintWidget.mAnchors] holds only the anchor of its orientation).
void _clearDependents(ConstraintWidget widget) {
  widget.mLeft.mDependents = null;
  widget.mTop.mDependents = null;
  widget.mRight.mDependents = null;
  widget.mBottom.mDependents = null;
  widget.mBaseline.mDependents = null;
  widget.mCenterX.mDependents = null;
  widget.mCenterY.mDependents = null;
  widget.mCenter.mDependents = null;
}

/// `setWidgetBaseline`'s reset of a top or bottom anchor (CL 1617-1618):
/// [ConstraintAnchor.reset] drops the anchor's link, its gone margin and
/// final value, and the dependents earlier children registered there. When
/// [keepMargin] (a match-parent vertical axis), the margin survives, as
/// applyConstraintsFromLayoutParams sets it again after the reset
/// (CL 1566-1568).
void _resetForBaseline(ConstraintAnchor anchor, bool keepMargin) {
  final margin = anchor.mMargin;
  anchor.reset();
  if (keepMargin) {
    anchor.mMargin = margin;
  }
}
