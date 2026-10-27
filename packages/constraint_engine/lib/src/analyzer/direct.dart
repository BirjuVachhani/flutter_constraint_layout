// Copyright (C) 2020 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.Direct
// (upstream pinned in UPSTREAM.md), lines 58-862. solveChain is not ported:
// it is dead at the pin (Chain.USE_CHAIN_OPTIMIZATION is false). The DEBUG
// code (its prints, ls, sHcount, sVcount and the timer) is omitted, and with
// it the level and isRtl parameters, which only that code reads.

import 'dart:math' as math;

import '../barrier.dart';
import '../constraint_anchor.dart';
import '../constraint_widget.dart';
import '../constraint_widget_container.dart';
import '../guideline.dart';
import '../jfloat.dart';
import 'basic_measure.dart';

/// Direct resolution engine (upstream D 33-41).
///
/// It walks the graph of dependencies and infers final positions. This
/// allows the engine to skip the linear solver in many situations, as well
/// as intermediate measure passes. Widgets are solved independently in
/// horizontal and vertical: an axis whose position and size Direct can work
/// out in whole pixels gets final values ([ConstraintWidget.setFinalHorizontal]
/// and the like), which [ConstraintWidget.addToSolver] then holds as
/// constants. Any widget not fully resolved is computed later by the linear
/// solver.
///
/// [ConstraintWidgetContainer.layout] runs [solvingPass] in the first pass of
/// a measure (pass 0) at [Optimizer.OPTIMIZATION_DIRECT], which
/// [Optimizer.OPTIMIZATION_STANDARD], the default level, includes.
///
/// The walk starts from the container, its guidelines and its barriers, and
/// follows each anchor with a final value to the anchors connected to it
/// ([ConstraintAnchor.getDependents]), in the order they were connected (an
/// insertion-ordered set; Android's is a hash set, whose order is not
/// defined). A widget is measured, through
/// [ConstraintWidgetContainer.measureWidget], as soon as both of its sizes
/// can be known. It is then placed from a target with a final value: next to
/// a single target, centered between two with its bias, or, for a spread
/// match-constraint axis, stretched between them. The arithmetic is Java's:
/// one binary32 rounding per float operation, in Java's order, and `(int)`
/// casts that truncate toward zero, so `(int) (0.5f + 0.7f * 45)` is 32.
///
/// Like upstream, Direct catches nothing. Where upstream dereferences null
/// (a stale dependent whose own target is gone, or a barrier that reads a
/// referenced guideline's anchor of the other orientation), the port throws
/// too, out of [ConstraintWidgetContainer.layout] and
/// [ConstraintWidgetContainer.measure].
///
/// **The one divergence from upstream: a cycle guard.** Upstream recurses
/// without a bound. When a widget's solving pass is reached again from its
/// own recursion, a cycle that only stale dependents form (connecting an
/// anchor to a new target leaves it among the old target's dependents, as
/// upstream does), Android repeats the same calls until its stack overflows.
/// The port stops such a walk instead:
///
/// * Each [solvingPass] call counts the changes it makes: a `setFinal` call
///   that resolves an axis, a [ConstraintWidget.setFinalBaseline] that moves
///   the axis or its final values, and a measure that changes the widget's
///   measure request, size or baseline.
/// * Each solving pass on the stack records that count when it starts to
///   walk its dependents, after its own measure.
/// * Entering a widget's pass on an axis whose pass is already on the stack,
///   with no change since that record, fires the guard: the inner call would
///   start from the state of the outer one and repeat it forever.
/// * So does a pass that would nest deeper than `4 * (children + 1) + 64`,
///   which only a cycle that keeps changing the state reaches: without a
///   cycle the nesting is at most `children + 1`.
///
/// When the guard fires, Direct is abandoned for this measure: the final
/// resolution of the container and of every child is reset
/// ([ConstraintWidget.resetFinalResolution]), each [Guideline] and [Barrier]
/// child loses its resolved flag, [guardTrips] grows by one, and
/// [solvingPass] returns normally, so the solver lays every widget out. The
/// measures Direct made, and the positions and sizes its `setFinal` calls
/// wrote, stay.
abstract final class Direct {
  // D 45: Direct never places a match-parent axis by itself.
  static const bool _APPLY_MATCH_PARENT = false;

  /// The [Measure] the last pass of [solvingPass] reuses for every child it
  /// measures (upstream's static `sMeasure`, D 46): one per isolate, shared
  /// by the solving passes of nested containers, as on Android. The other
  /// measures Direct makes each use a new [Measure].
  ///
  /// Public (upstream: private, read by the parity oracle through
  /// reflection) so that a measurer can tell a request of Direct's last pass
  /// by identity.
  static final Measure sMeasure = Measure();

  // D 47: a widget's solving pass on an axis runs once per Direct pass,
  // except a guideline's, which is never marked done.
  static const bool _EARLY_TERMINATION = true;

  /// Port only: how many times the cycle guard abandoned a solving pass (see
  /// [Direct]). Never reset; tools and tests read differences.
  static int guardTrips = 0;

  /// Walk the dependency graph of [layout] and solve it (D 58-275).
  ///
  /// [measurer] measures the widgets; when it is null nothing is measured,
  /// and only the axes that need no measure resolve.
  ///
  /// Re-entrant: a measurer may lay out a nested container, whose own
  /// solving pass then runs inside this one.
  static void solvingPass(
    ConstraintWidgetContainer layout,
    Measurer? measurer,
  ) {
    final horizontal = layout.getHorizontalDimensionBehaviour();
    final vertical = layout.getVerticalDimensionBehaviour();
    layout.resetFinalResolution();
    final children = layout.getChildren();
    final count = children.length;
    for (var i = 0; i < count; i++) {
      final child = children[i];
      child.resetFinalResolution();
    }
    final pass = _SolvingPass(measurer, 4 * (count + 1) + 64);
    try {
      pass.solve(layout, children, count, horizontal, vertical);
    } on _GuardTrip catch (trip) {
      if (!identical(trip.pass, pass)) {
        rethrow;
      }
      guardTrips++;
      layout.resetFinalResolution();
      for (var i = 0; i < count; i++) {
        final child = children[i];
        child.resetFinalResolution();
        if (child is Guideline) {
          child.mResolved = false;
        } else if (child is Barrier) {
          child.mResolved = false;
        }
      }
    }
  }
}

/// The sentinel the cycle guard throws to unwind to [Direct.solvingPass],
/// which catches only its own ([pass]).
final class _GuardTrip implements Exception {
  _GuardTrip(this.pass);

  /// The solving pass whose guard fired.
  final _SolvingPass pass;

  @override
  String toString() => 'Direct: cycle guard';
}

/// The state of one [Direct.solvingPass] call, and upstream's private static
/// methods as instance methods: the measurer, and the cycle guard's state
/// (see [Direct]), which must not be static because the solving passes of
/// nested containers run inside each other.
final class _SolvingPass {
  _SolvingPass(this.measurer, this._maxDepth);

  /// The measurer of [Direct.solvingPass], or null to measure nothing.
  final Measurer? measurer;

  /// The deepest nesting of solving passes the guard allows.
  final int _maxDepth;

  /// The changes this call made that a solving pass can observe.
  int _changes = 0;

  /// The solving passes on the stack.
  int _depth = 0;

  /// For each widget whose horizontal solving pass is on the stack, the
  /// [_changes] its innermost such pass recorded.
  final _OnStack _horizontalOnStack = _OnStack();

  /// The same for the vertical solving passes.
  final _OnStack _verticalOnStack = _OnStack();

  /// The body of [Direct.solvingPass] after the reset of every final
  /// resolution (D 81-268).
  void solve(
    ConstraintWidgetContainer layout,
    List<ConstraintWidget> children,
    int count,
    DimensionBehaviour horizontal,
    DimensionBehaviour vertical,
  ) {
    // First, let's solve the horizontal dependencies, as it's a lot more
    // common to have a container with a fixed horizontal dimension (e.g.
    // match_parent) than the opposite.

    // If we know our size, we can fully set the entire dimension, but if not
    // we can still solve what we can starting from the left.
    if (horizontal == DimensionBehaviour.fixed) {
      _setFinalHorizontal(layout, 0, layout.getWidth());
    } else {
      layout.setFinalLeft(0);
    }

    // Then let's first try to solve the guidelines of this axis, as they only
    // depend on the container (upstream's comment says horizontal; these are
    // the vertical guidelines, which constrain x).
    var hasGuideline = false;
    var hasBarrier = false;
    for (var i = 0; i < count; i++) {
      final child = children[i];
      if (child is Guideline) {
        final guideline = child;
        if (guideline.getOrientation() == Guideline.vertical) {
          if (guideline.getRelativeBegin() != -1) {
            guideline.setFinalValue(guideline.getRelativeBegin());
          } else if (guideline.getRelativeEnd() != -1 &&
              layout.isResolvedHorizontally()) {
            guideline.setFinalValue(
              layout.getWidth() - guideline.getRelativeEnd(),
            );
          } else if (layout.isResolvedHorizontally()) {
            // (int) (0.5f + relativePercent * layout.getWidth()), in float
            final position = jint(
              fadd(
                0.5,
                fmul(guideline.getRelativePercent(), fi(layout.getWidth())),
              ),
            );
            guideline.setFinalValue(position);
          }
          hasGuideline = true;
        }
      } else if (child is Barrier) {
        final barrier = child;
        if (barrier.getOrientation() == ConstraintWidget.HORIZONTAL) {
          hasBarrier = true;
        }
      }
    }
    if (hasGuideline) {
      for (var i = 0; i < count; i++) {
        final child = children[i];
        if (child is Guideline) {
          final guideline = child;
          if (guideline.getOrientation() == Guideline.vertical) {
            _horizontalSolvingPass(guideline);
          }
        }
      }
    }

    // Now let's resolve what we can in the dependencies of the container
    _horizontalSolvingPass(layout);

    // Finally, let's go through barriers, as they depends on widgets that
    // may have been solved.
    if (hasBarrier) {
      for (var i = 0; i < count; i++) {
        final child = children[i];
        if (child is Barrier) {
          final barrier = child;
          if (barrier.getOrientation() == ConstraintWidget.HORIZONTAL) {
            _solveBarrier(barrier, ConstraintWidget.HORIZONTAL);
          }
        }
      }
    }

    // Now we are done with the horizontal axis, let's see what we can do
    // vertically
    if (vertical == DimensionBehaviour.fixed) {
      _setFinalVertical(layout, 0, layout.getHeight());
    } else {
      layout.setFinalTop(0);
    }

    // Same thing as above: let's start with guidelines...
    hasGuideline = false;
    hasBarrier = false;
    for (var i = 0; i < count; i++) {
      final child = children[i];
      if (child is Guideline) {
        final guideline = child;
        if (guideline.getOrientation() == Guideline.horizontal) {
          if (guideline.getRelativeBegin() != -1) {
            guideline.setFinalValue(guideline.getRelativeBegin());
          } else if (guideline.getRelativeEnd() != -1 &&
              layout.isResolvedVertically()) {
            guideline.setFinalValue(
              layout.getHeight() - guideline.getRelativeEnd(),
            );
          } else if (layout.isResolvedVertically()) {
            // (int) (0.5f + relativePercent * layout.getHeight()), in float
            final position = jint(
              fadd(
                0.5,
                fmul(guideline.getRelativePercent(), fi(layout.getHeight())),
              ),
            );
            guideline.setFinalValue(position);
          }
          hasGuideline = true;
        }
      } else if (child is Barrier) {
        final barrier = child;
        if (barrier.getOrientation() == ConstraintWidget.VERTICAL) {
          hasBarrier = true;
        }
      }
    }
    if (hasGuideline) {
      for (var i = 0; i < count; i++) {
        final child = children[i];
        if (child is Guideline) {
          final guideline = child;
          if (guideline.getOrientation() == Guideline.horizontal) {
            _verticalSolvingPass(guideline);
          }
        }
      }
    }

    // ...then solve the vertical dependencies...
    _verticalSolvingPass(layout);

    // ...then deal with any barriers left.
    if (hasBarrier) {
      for (var i = 0; i < count; i++) {
        final child = children[i];
        if (child is Barrier) {
          final barrier = child;
          if (barrier.getOrientation() == ConstraintWidget.VERTICAL) {
            _solveBarrier(barrier, ConstraintWidget.VERTICAL);
          }
        }
      }
    }

    // We can do a last pass to see any widget that could still be measured
    for (var i = 0; i < count; i++) {
      final child = children[i];
      if (child.isMeasureRequested() && _canMeasure(child)) {
        _measure(child, Direct.sMeasure);
        if (child is Guideline) {
          if (child.getOrientation() == Guideline.horizontal) {
            _verticalSolvingPass(child);
          } else {
            _horizontalSolvingPass(child);
          }
        } else {
          _horizontalSolvingPass(child);
          _verticalSolvingPass(child);
        }
      }
    }
  }

  /// Ask the barrier if it's resolved, and if so do a solving pass along
  /// [orientation] (D 280-292).
  void _solveBarrier(Barrier barrier, int orientation) {
    if (barrier.allSolved()) {
      if (orientation == ConstraintWidget.HORIZONTAL) {
        _horizontalSolvingPass(barrier);
      } else {
        _verticalSolvingPass(barrier);
      }
    }
  }

  /// Does an horizontal solving pass for [layout]: walks through the
  /// widget's horizontal dependencies and, where they can be resolved
  /// directly, does so (D 315-459).
  void _horizontalSolvingPass(ConstraintWidget layout) {
    if (Direct._EARLY_TERMINATION && layout.isHorizontalSolvingPassDone()) {
      return;
    }
    final outer = _enter(_horizontalOnStack, layout);

    if (layout is! ConstraintWidgetContainer &&
        layout.isMeasureRequested() &&
        _canMeasure(layout)) {
      final measure = Measure();
      _measure(layout, measure);
    }
    _horizontalOnStack[layout] = _changes;

    final left = layout.getAnchor(ConstraintAnchorType.left)!;
    final right = layout.getAnchor(ConstraintAnchorType.right)!;
    final l = left.getFinalValue();
    final r = right.getFinalValue();

    final leftDependents = left.getDependents();
    if (leftDependents != null && left.hasFinalValue()) {
      for (final first in leftDependents) {
        final widget = first.mOwner;
        final canMeasure = _canMeasure(widget);
        if (widget.isMeasureRequested() && canMeasure) {
          final measure = Measure();
          _measure(widget, measure);
        }

        final bothConnected =
            (identical(first, widget.mLeft) &&
                widget.mRight.mTarget != null &&
                widget.mRight.mTarget!.hasFinalValue()) ||
            (identical(first, widget.mRight) &&
                widget.mLeft.mTarget != null &&
                widget.mLeft.mTarget!.hasFinalValue());
        if (widget.getHorizontalDimensionBehaviour() !=
                DimensionBehaviour.matchConstraint ||
            canMeasure) {
          if (widget.isMeasureRequested()) {
            // Widget needs to be measured
            continue;
          }
          if (identical(first, widget.mLeft) && widget.mRight.mTarget == null) {
            final x1 = l + widget.mLeft.getMargin();
            final x2 = x1 + widget.getWidth();
            _setFinalHorizontal(widget, x1, x2);
            _horizontalSolvingPass(widget);
          } else if (identical(first, widget.mRight) &&
              widget.mLeft.mTarget == null) {
            final x2 = l - widget.mRight.getMargin();
            final x1 = x2 - widget.getWidth();
            _setFinalHorizontal(widget, x1, x2);
            _horizontalSolvingPass(widget);
          } else if (bothConnected && !widget.isInHorizontalChain()) {
            _solveHorizontalCenterConstraints(widget);
          } else if (Direct._APPLY_MATCH_PARENT &&
              widget.getHorizontalDimensionBehaviour() ==
                  DimensionBehaviour.matchParent) {
            _setFinalHorizontal(widget, 0, widget.getWidth());
            _horizontalSolvingPass(widget);
          }
        } else if (widget.getHorizontalDimensionBehaviour() ==
                DimensionBehaviour.matchConstraint &&
            widget.mMatchConstraintMaxWidth >= 0 &&
            widget.mMatchConstraintMinWidth >= 0 &&
            (widget.getVisibility() == ConstraintWidget.GONE ||
                ((widget.mMatchConstraintDefaultWidth ==
                        ConstraintWidget.MATCH_CONSTRAINT_SPREAD) &&
                    widget.getDimensionRatio() == 0)) &&
            !widget.isInHorizontalChain() &&
            !widget.isInVirtualLayout()) {
          if (bothConnected && !widget.isInHorizontalChain()) {
            _solveHorizontalMatchConstraint(layout, widget);
          }
        }
      }
    }
    if (layout is Guideline) {
      // A guideline's left and right anchors are its one anchor, which the
      // loop above walked. Its pass is never marked done, so the last pass
      // runs it again.
      _leave(_horizontalOnStack, layout, outer);
      return;
    }
    final rightDependents = right.getDependents();
    if (rightDependents != null && right.hasFinalValue()) {
      for (final first in rightDependents) {
        final widget = first.mOwner;
        final canMeasure = _canMeasure(widget);
        if (widget.isMeasureRequested() && canMeasure) {
          final measure = Measure();
          _measure(widget, measure);
        }

        final bothConnected =
            (identical(first, widget.mLeft) &&
                widget.mRight.mTarget != null &&
                widget.mRight.mTarget!.hasFinalValue()) ||
            (identical(first, widget.mRight) &&
                widget.mLeft.mTarget != null &&
                widget.mLeft.mTarget!.hasFinalValue());
        if (widget.getHorizontalDimensionBehaviour() !=
                DimensionBehaviour.matchConstraint ||
            canMeasure) {
          if (widget.isMeasureRequested()) {
            // Widget needs to be measured
            continue;
          }
          if (identical(first, widget.mLeft) && widget.mRight.mTarget == null) {
            final x1 = r + widget.mLeft.getMargin();
            final x2 = x1 + widget.getWidth();
            _setFinalHorizontal(widget, x1, x2);
            _horizontalSolvingPass(widget);
          } else if (identical(first, widget.mRight) &&
              widget.mLeft.mTarget == null) {
            final x2 = r - widget.mRight.getMargin();
            final x1 = x2 - widget.getWidth();
            _setFinalHorizontal(widget, x1, x2);
            _horizontalSolvingPass(widget);
          } else if (bothConnected && !widget.isInHorizontalChain()) {
            _solveHorizontalCenterConstraints(widget);
          }
        } else if (widget.getHorizontalDimensionBehaviour() ==
                DimensionBehaviour.matchConstraint &&
            widget.mMatchConstraintMaxWidth >= 0 &&
            widget.mMatchConstraintMinWidth >= 0 &&
            (widget.getVisibility() == ConstraintWidget.GONE ||
                ((widget.mMatchConstraintDefaultWidth ==
                        ConstraintWidget.MATCH_CONSTRAINT_SPREAD) &&
                    widget.getDimensionRatio() == 0)) &&
            !widget.isInHorizontalChain() &&
            !widget.isInVirtualLayout()) {
          if (bothConnected && !widget.isInHorizontalChain()) {
            _solveHorizontalMatchConstraint(layout, widget);
          }
        }
      }
    }
    layout.markHorizontalSolvingPassDone();
    _leave(_horizontalOnStack, layout, outer);
  }

  /// Does a vertical solving pass for [layout]: walks through the widget's
  /// vertical dependencies, baseline included, and, where they can be
  /// resolved directly, does so (D 468-641).
  void _verticalSolvingPass(ConstraintWidget layout) {
    if (Direct._EARLY_TERMINATION && layout.isVerticalSolvingPassDone()) {
      return;
    }
    final outer = _enter(_verticalOnStack, layout);

    if (layout is! ConstraintWidgetContainer &&
        layout.isMeasureRequested() &&
        _canMeasure(layout)) {
      final measure = Measure();
      _measure(layout, measure);
    }
    _verticalOnStack[layout] = _changes;

    final top = layout.getAnchor(ConstraintAnchorType.top)!;
    final bottom = layout.getAnchor(ConstraintAnchorType.bottom)!;
    final t = top.getFinalValue();
    final b = bottom.getFinalValue();

    final topDependents = top.getDependents();
    if (topDependents != null && top.hasFinalValue()) {
      for (final first in topDependents) {
        final widget = first.mOwner;
        final canMeasure = _canMeasure(widget);
        if (widget.isMeasureRequested() && canMeasure) {
          final measure = Measure();
          _measure(widget, measure);
        }

        final bothConnected =
            (identical(first, widget.mTop) &&
                widget.mBottom.mTarget != null &&
                widget.mBottom.mTarget!.hasFinalValue()) ||
            (identical(first, widget.mBottom) &&
                widget.mTop.mTarget != null &&
                widget.mTop.mTarget!.hasFinalValue());
        if (widget.getVerticalDimensionBehaviour() !=
                DimensionBehaviour.matchConstraint ||
            canMeasure) {
          if (widget.isMeasureRequested()) {
            // Widget needs to be measured
            continue;
          }
          if (identical(first, widget.mTop) && widget.mBottom.mTarget == null) {
            final y1 = t + widget.mTop.getMargin();
            final y2 = y1 + widget.getHeight();
            _setFinalVertical(widget, y1, y2);
            _verticalSolvingPass(widget);
          } else if (identical(first, widget.mBottom) &&
              widget.mTop.mTarget == null) {
            final y2 = t - widget.mBottom.getMargin();
            final y1 = y2 - widget.getHeight();
            _setFinalVertical(widget, y1, y2);
            _verticalSolvingPass(widget);
          } else if (bothConnected && !widget.isInVerticalChain()) {
            _solveVerticalCenterConstraints(widget);
          } else if (Direct._APPLY_MATCH_PARENT &&
              widget.getVerticalDimensionBehaviour() ==
                  DimensionBehaviour.matchParent) {
            _setFinalVertical(widget, 0, widget.getHeight());
            _verticalSolvingPass(widget);
          }
        } else if (widget.getVerticalDimensionBehaviour() ==
                DimensionBehaviour.matchConstraint &&
            widget.mMatchConstraintMaxHeight >= 0 &&
            widget.mMatchConstraintMinHeight >= 0 &&
            (widget.getVisibility() == ConstraintWidget.GONE ||
                ((widget.mMatchConstraintDefaultHeight ==
                        ConstraintWidget.MATCH_CONSTRAINT_SPREAD) &&
                    widget.getDimensionRatio() == 0)) &&
            !widget.isInVerticalChain() &&
            !widget.isInVirtualLayout()) {
          if (bothConnected && !widget.isInVerticalChain()) {
            _solveVerticalMatchConstraint(layout, widget);
          }
        }
      }
    }
    if (layout is Guideline) {
      // A guideline's top and bottom anchors are its one anchor, which the
      // loop above walked, and it has no baseline. Its pass is never marked
      // done.
      _leave(_verticalOnStack, layout, outer);
      return;
    }
    final bottomDependents = bottom.getDependents();
    if (bottomDependents != null && bottom.hasFinalValue()) {
      for (final first in bottomDependents) {
        final widget = first.mOwner;
        final canMeasure = _canMeasure(widget);
        if (widget.isMeasureRequested() && canMeasure) {
          final measure = Measure();
          _measure(widget, measure);
        }

        final bothConnected =
            (identical(first, widget.mTop) &&
                widget.mBottom.mTarget != null &&
                widget.mBottom.mTarget!.hasFinalValue()) ||
            (identical(first, widget.mBottom) &&
                widget.mTop.mTarget != null &&
                widget.mTop.mTarget!.hasFinalValue());
        if (widget.getVerticalDimensionBehaviour() !=
                DimensionBehaviour.matchConstraint ||
            canMeasure) {
          if (widget.isMeasureRequested()) {
            // Widget needs to be measured
            continue;
          }
          if (identical(first, widget.mTop) && widget.mBottom.mTarget == null) {
            final y1 = b + widget.mTop.getMargin();
            final y2 = y1 + widget.getHeight();
            _setFinalVertical(widget, y1, y2);
            _verticalSolvingPass(widget);
          } else if (identical(first, widget.mBottom) &&
              widget.mTop.mTarget == null) {
            final y2 = b - widget.mBottom.getMargin();
            final y1 = y2 - widget.getHeight();
            _setFinalVertical(widget, y1, y2);
            _verticalSolvingPass(widget);
          } else if (bothConnected && !widget.isInVerticalChain()) {
            _solveVerticalCenterConstraints(widget);
          }
        } else if (widget.getVerticalDimensionBehaviour() ==
                DimensionBehaviour.matchConstraint &&
            widget.mMatchConstraintMaxHeight >= 0 &&
            widget.mMatchConstraintMinHeight >= 0 &&
            (widget.getVisibility() == ConstraintWidget.GONE ||
                ((widget.mMatchConstraintDefaultHeight ==
                        ConstraintWidget.MATCH_CONSTRAINT_SPREAD) &&
                    widget.getDimensionRatio() == 0)) &&
            !widget.isInVerticalChain() &&
            !widget.isInVirtualLayout()) {
          if (bothConnected && !widget.isInVerticalChain()) {
            _solveVerticalMatchConstraint(layout, widget);
          }
        }
      }
    }

    final baseline = layout.getAnchor(ConstraintAnchorType.baseline)!;
    final baselineDependents = baseline.getDependents();
    if (baselineDependents != null && baseline.hasFinalValue()) {
      final baselineValue = baseline.getFinalValue();
      for (final first in baselineDependents) {
        final widget = first.mOwner;
        final canMeasure = _canMeasure(widget);
        if (widget.isMeasureRequested() && canMeasure) {
          final measure = Measure();
          _measure(widget, measure);
        }
        if (widget.getVerticalDimensionBehaviour() !=
                DimensionBehaviour.matchConstraint ||
            canMeasure) {
          if (widget.isMeasureRequested()) {
            // Widget needs to be measured
            continue;
          }
          if (identical(first, widget.mBaseline)) {
            _setFinalBaseline(widget, baselineValue + first.getMargin());
            _verticalSolvingPass(widget);
          }
        }
      }
    }
    layout.markVerticalSolvingPassDone();
    _leave(_verticalOnStack, layout, outer);
  }

  /// Solve horizontal centering constraints (D 646-682).
  void _solveHorizontalCenterConstraints(ConstraintWidget widget) {
    // Upstream's TODO: handle match constraints here or before calling this.
    var bias = widget.getHorizontalBiasPercent();
    final start = widget.mLeft.mTarget!.getFinalValue();
    final end = widget.mRight.mTarget!.getFinalValue();
    var s1 = start + widget.mLeft.getMargin();
    var s2 = end - widget.mRight.getMargin();
    if (start == end) {
      bias = 0.5;
      s1 = start;
      s2 = end;
    }
    final width = widget.getWidth();
    var distance = s2 - s1 - width;
    if (s1 > s2) {
      distance = s1 - s2 - width;
    }
    final int d1;
    if (distance > 0) {
      // (int) (0.5f + bias * distance)
      d1 = jint(fadd(0.5, fmul(bias, fi(distance))));
    } else {
      // (int) (bias * distance)
      d1 = jint(fmul(bias, fi(distance)));
    }
    var x1 = s1 + d1;
    var x2 = x1 + width;
    if (s1 > s2) {
      x1 = s1 + d1;
      x2 = x1 - width;
    }
    _setFinalHorizontal(widget, x1, x2);
    _horizontalSolvingPass(widget);
  }

  /// Solve vertical centering constraints (D 687-722). Unlike the
  /// horizontal twin, crossed margins subtract the offset.
  void _solveVerticalCenterConstraints(ConstraintWidget widget) {
    // Upstream's TODO: handle match constraints here or before calling this.
    var bias = widget.getVerticalBiasPercent();
    final start = widget.mTop.mTarget!.getFinalValue();
    final end = widget.mBottom.mTarget!.getFinalValue();
    var s1 = start + widget.mTop.getMargin();
    var s2 = end - widget.mBottom.getMargin();
    if (start == end) {
      bias = 0.5;
      s1 = start;
      s2 = end;
    }
    final height = widget.getHeight();
    var distance = s2 - s1 - height;
    if (s1 > s2) {
      distance = s1 - s2 - height;
    }
    final int d1;
    if (distance > 0) {
      // (int) (0.5f + bias * distance)
      d1 = jint(fadd(0.5, fmul(bias, fi(distance))));
    } else {
      // (int) (bias * distance)
      d1 = jint(fmul(bias, fi(distance)));
    }
    var y1 = s1 + d1;
    var y2 = y1 + height;
    if (s1 > s2) {
      y1 = s1 - d1;
      y2 = y1 - height;
    }
    _setFinalVertical(widget, y1, y2);
    _verticalSolvingPass(widget);
  }

  /// Solve horizontal match constraints (D 727-765): [widget], a dependent
  /// of [layout], spreads between its two targets.
  void _solveHorizontalMatchConstraint(
    ConstraintWidget layout,
    ConstraintWidget widget,
  ) {
    final bias = widget.getHorizontalBiasPercent();
    final s1 = widget.mLeft.mTarget!.getFinalValue() + widget.mLeft.getMargin();
    final s2 =
        widget.mRight.mTarget!.getFinalValue() - widget.mRight.getMargin();
    if (s2 >= s1) {
      var width = widget.getWidth();
      if (widget.getVisibility() != ConstraintWidget.GONE) {
        if (widget.mMatchConstraintDefaultWidth ==
            ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
          // Unreachable: the caller requires MATCH_CONSTRAINT_SPREAD unless
          // the widget is gone. Ported as written.
          final int parentWidth;
          if (layout is ConstraintWidgetContainer) {
            parentWidth = layout.getWidth();
          } else {
            parentWidth = layout.getParent()!.getWidth();
          }
          // (int) (0.5f * widget.getHorizontalBiasPercent() * parentWidth)
          width = jint(
            fmul(
              fmul(0.5, widget.getHorizontalBiasPercent()),
              fi(parentWidth),
            ),
          );
        } else if (widget.mMatchConstraintDefaultWidth ==
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
          width = s2 - s1;
        }
        width = math.max(widget.mMatchConstraintMinWidth, width);
        if (widget.mMatchConstraintMaxWidth > 0) {
          width = math.min(widget.mMatchConstraintMaxWidth, width);
        }
      }
      final distance = s2 - s1 - width;
      // (int) (0.5f + bias * distance), also when distance is negative
      final d1 = jint(fadd(0.5, fmul(bias, fi(distance))));
      final x1 = s1 + d1;
      final x2 = x1 + width;
      _setFinalHorizontal(widget, x1, x2);
      _horizontalSolvingPass(widget);
    }
  }

  /// Solve vertical match constraints (D 770-807): [widget], a dependent of
  /// [layout], spreads between its two targets.
  void _solveVerticalMatchConstraint(
    ConstraintWidget layout,
    ConstraintWidget widget,
  ) {
    final bias = widget.getVerticalBiasPercent();
    final s1 = widget.mTop.mTarget!.getFinalValue() + widget.mTop.getMargin();
    final s2 =
        widget.mBottom.mTarget!.getFinalValue() - widget.mBottom.getMargin();
    if (s2 >= s1) {
      var height = widget.getHeight();
      if (widget.getVisibility() != ConstraintWidget.GONE) {
        if (widget.mMatchConstraintDefaultHeight ==
            ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
          // Unreachable: the caller requires MATCH_CONSTRAINT_SPREAD unless
          // the widget is gone. Ported as written.
          final int parentHeight;
          if (layout is ConstraintWidgetContainer) {
            parentHeight = layout.getHeight();
          } else {
            parentHeight = layout.getParent()!.getHeight();
          }
          // (int) (0.5f * bias * parentHeight)
          height = jint(fmul(fmul(0.5, bias), fi(parentHeight)));
        } else if (widget.mMatchConstraintDefaultHeight ==
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
          height = s2 - s1;
        }
        height = math.max(widget.mMatchConstraintMinHeight, height);
        if (widget.mMatchConstraintMaxHeight > 0) {
          height = math.min(widget.mMatchConstraintMaxHeight, height);
        }
      }
      final distance = s2 - s1 - height;
      // (int) (0.5f + bias * distance), also when distance is negative
      final d1 = jint(fadd(0.5, fmul(bias, fi(distance))));
      final y1 = s1 + d1;
      final y2 = y1 + height;
      _setFinalVertical(widget, y1, y2);
      _verticalSolvingPass(widget);
    }
  }

  /// Returns true if the dimensions of [layout] are computable directly:
  /// both dimensions are knowable by a single measure pass (D 815-862).
  bool _canMeasure(ConstraintWidget layout) {
    final horizontalBehaviour = layout.getHorizontalDimensionBehaviour();
    final verticalBehaviour = layout.getVerticalDimensionBehaviour();
    // Java's cast: a parent that is not a container throws, as upstream's
    // ClassCastException does.
    final parent = layout.getParent() != null
        ? layout.getParent()! as ConstraintWidgetContainer
        : null;
    final isParentHorizontalFixed =
        parent != null &&
        parent.getHorizontalDimensionBehaviour() == DimensionBehaviour.fixed;
    final isParentVerticalFixed =
        parent != null &&
        parent.getVerticalDimensionBehaviour() == DimensionBehaviour.fixed;
    final isHorizontalFixed =
        horizontalBehaviour == DimensionBehaviour.fixed ||
        layout.isResolvedHorizontally() ||
        (Direct._APPLY_MATCH_PARENT &&
            horizontalBehaviour == DimensionBehaviour.matchParent &&
            isParentHorizontalFixed) ||
        horizontalBehaviour == DimensionBehaviour.wrapContent ||
        (horizontalBehaviour == DimensionBehaviour.matchConstraint &&
            layout.mMatchConstraintDefaultWidth ==
                ConstraintWidget.MATCH_CONSTRAINT_SPREAD &&
            layout.mDimensionRatio == 0 &&
            layout.hasDanglingDimension(ConstraintWidget.HORIZONTAL)) ||
        (horizontalBehaviour == DimensionBehaviour.matchConstraint &&
            layout.mMatchConstraintDefaultWidth ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
            layout.hasResolvedTargets(
              ConstraintWidget.HORIZONTAL,
              layout.getWidth(),
            ));
    final isVerticalFixed =
        verticalBehaviour == DimensionBehaviour.fixed ||
        layout.isResolvedVertically() ||
        (Direct._APPLY_MATCH_PARENT &&
            verticalBehaviour == DimensionBehaviour.matchParent &&
            isParentVerticalFixed) ||
        verticalBehaviour == DimensionBehaviour.wrapContent ||
        (verticalBehaviour == DimensionBehaviour.matchConstraint &&
            layout.mMatchConstraintDefaultHeight ==
                ConstraintWidget.MATCH_CONSTRAINT_SPREAD &&
            layout.mDimensionRatio == 0 &&
            layout.hasDanglingDimension(ConstraintWidget.VERTICAL)) ||
        (verticalBehaviour == DimensionBehaviour.matchConstraint &&
            layout.mMatchConstraintDefaultHeight ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
            layout.hasResolvedTargets(
              ConstraintWidget.VERTICAL,
              layout.getHeight(),
            ));
    if (layout.mDimensionRatio > 0 && (isHorizontalFixed || isVerticalFixed)) {
      return true;
    }
    return isHorizontalFixed && isVerticalFixed;
  }

  // -------------------------------------------------------------------------
  // Port only: the calls that change state, counted for the cycle guard.
  // -------------------------------------------------------------------------

  /// `ConstraintWidgetContainer.measure(level, widget, measurer, measure,
  /// SELF_DIMENSIONS)`, counting a change of [widget]'s measure request,
  /// size or baseline.
  void _measure(ConstraintWidget widget, Measure measure) {
    final measureRequested = widget.mMeasureRequested;
    final width = widget.mWidth;
    final height = widget.mHeight;
    final baselineDistance = widget.mBaselineDistance;
    final hasBaseline = widget.mHasBaseline;
    // The level argument is upstream's debug indentation, read by nothing.
    ConstraintWidgetContainer.measureWidget(
      0,
      widget,
      measurer,
      measure,
      Measure.SELF_DIMENSIONS,
    );
    if (widget.mMeasureRequested != measureRequested ||
        widget.mWidth != width ||
        widget.mHeight != height ||
        widget.mBaselineDistance != baselineDistance ||
        widget.mHasBaseline != hasBaseline) {
      _changes++;
    }
  }

  /// [ConstraintWidget.setFinalHorizontal], counting the call when it
  /// resolves the axis (it does nothing on a resolved one).
  void _setFinalHorizontal(ConstraintWidget widget, int x1, int x2) {
    if (!widget.mResolvedHorizontal) {
      _changes++;
    }
    widget.setFinalHorizontal(x1, x2);
  }

  /// [ConstraintWidget.setFinalVertical], counting the call when it resolves
  /// the axis (it does nothing on a resolved one).
  void _setFinalVertical(ConstraintWidget widget, int y1, int y2) {
    if (!widget.mResolvedVertical) {
      _changes++;
    }
    widget.setFinalVertical(y1, y2);
  }

  /// [ConstraintWidget.setFinalBaseline], counting the call when it moves the
  /// widget or changes its resolved flag or a final value of its top, bottom
  /// or baseline anchor (it applies even on a resolved axis).
  void _setFinalBaseline(ConstraintWidget widget, int baselineValue) {
    final y = widget.mY;
    final resolvedVertical = widget.mResolvedVertical;
    final top = widget.mTop;
    final bottom = widget.mBottom;
    final baseline = widget.mBaseline;
    final topFinal = top.hasFinalValue();
    final topValue = top.getFinalValue();
    final bottomFinal = bottom.hasFinalValue();
    final bottomValue = bottom.getFinalValue();
    final baselineFinal = baseline.hasFinalValue();
    final baselineValueBefore = baseline.getFinalValue();
    widget.setFinalBaseline(baselineValue);
    if (widget.mY != y ||
        widget.mResolvedVertical != resolvedVertical ||
        top.hasFinalValue() != topFinal ||
        top.getFinalValue() != topValue ||
        bottom.hasFinalValue() != bottomFinal ||
        bottom.getFinalValue() != bottomValue ||
        baseline.hasFinalValue() != baselineFinal ||
        baseline.getFinalValue() != baselineValueBefore) {
      _changes++;
    }
  }

  // -------------------------------------------------------------------------
  // Port only: the cycle guard (see Direct).
  // -------------------------------------------------------------------------

  /// Enter a solving pass of [widget] on the axis of [onStack], after its
  /// early-termination check: fire the guard on a re-entry with no change
  /// since the record of the pass on the stack, or past the depth bound.
  /// Returns the record to restore when the pass leaves, or null.
  int? _enter(_OnStack onStack, ConstraintWidget widget) {
    final outer = onStack[widget];
    if (outer == _changes || _depth >= _maxDepth) {
      throw _GuardTrip(this);
    }
    _depth++;
    return outer;
  }

  /// Leave the solving pass of [widget] on the axis of [onStack], restoring
  /// the record [outer] of the pass it re-entered, if any.
  void _leave(_OnStack onStack, ConstraintWidget widget, int? outer) {
    _depth--;
    if (outer == null) {
      onStack.remove(widget);
    } else {
      onStack[widget] = outer;
    }
  }
}

/// The guard's record of the solving passes on the stack along one axis: an
/// identity map from a widget to the [_SolvingPass._changes] its innermost
/// pass recorded.
///
/// Port only, for speed: it replaces a `HashMap.identity()`, which allocates
/// an entry object for every insertion, with open addressing (linear
/// probing on [identityHashCode], at most half full) and deletion by
/// backward shift, which allocates nothing once grown. Exact: lookups,
/// insertions and removals have the map's semantics (keys compared with
/// [identical]), so every guard decision is the same; nothing iterates the
/// table, so the order of its slots is never observed.
final class _OnStack {
  List<ConstraintWidget?> _keys = List<ConstraintWidget?>.filled(16, null);
  List<int> _values = List<int>.filled(16, 0);
  int _mask = 15;
  int _size = 0;

  /// The record of [widget], or null when its pass is not on the stack.
  int? operator [](ConstraintWidget widget) {
    final keys = _keys;
    final mask = _mask;
    var i = identityHashCode(widget) & mask;
    while (true) {
      final key = keys[i];
      if (key == null) {
        return null;
      }
      if (identical(key, widget)) {
        return _values[i];
      }
      i = (i + 1) & mask;
    }
  }

  /// Record [value] for [widget], replacing its record if it has one.
  void operator []=(ConstraintWidget widget, int value) {
    final keys = _keys;
    final mask = _mask;
    var i = identityHashCode(widget) & mask;
    while (true) {
      final key = keys[i];
      if (key == null) {
        keys[i] = widget;
        _values[i] = value;
        _size++;
        if (2 * _size > mask + 1) {
          _grow();
        }
        return;
      }
      if (identical(key, widget)) {
        _values[i] = value;
        return;
      }
      i = (i + 1) & mask;
    }
  }

  /// Drop the record of [widget], if it has one.
  void remove(ConstraintWidget widget) {
    final keys = _keys;
    final values = _values;
    final mask = _mask;
    var i = identityHashCode(widget) & mask;
    while (true) {
      final key = keys[i];
      if (key == null) {
        return;
      }
      if (identical(key, widget)) {
        break;
      }
      i = (i + 1) & mask;
    }
    // Backward shift: move up every later entry of the probe run whose home
    // slot is not in the cyclic range (i, j], so that no lookup meets the
    // hole before its key.
    var j = i;
    while (true) {
      j = (j + 1) & mask;
      final key = keys[j];
      if (key == null) {
        break;
      }
      final home = identityHashCode(key) & mask;
      final inRange = i <= j
          ? (i < home && home <= j)
          : (i < home || home <= j);
      if (!inRange) {
        keys[i] = key;
        values[i] = values[j];
        i = j;
      }
    }
    keys[i] = null;
    _size--;
  }

  void _grow() {
    final oldKeys = _keys;
    final oldValues = _values;
    final capacity = oldKeys.length * 2;
    final keys = List<ConstraintWidget?>.filled(capacity, null);
    final values = List<int>.filled(capacity, 0);
    final mask = capacity - 1;
    for (var k = 0; k < oldKeys.length; k++) {
      final key = oldKeys[k];
      if (key == null) {
        continue;
      }
      var i = identityHashCode(key) & mask;
      while (keys[i] != null) {
        i = (i + 1) & mask;
      }
      keys[i] = key;
      values[i] = oldValues[k];
    }
    _keys = keys;
    _values = values;
    _mask = mask;
  }
}
