// Copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0
//
// No upstream counterpart. A read-only model of which widget axes upstream's
// Direct optimizer (androidx.constraintlayout.core.widgets.analyzer.Direct)
// resolves, for DependencyGraph's barrier check. This port does not run
// Direct.

import 'dart:typed_data';

import '../barrier.dart';
import '../constraint_anchor.dart';
import '../constraint_widget.dart';
import '../constraint_widget_container.dart';
import '../guideline.dart';

/// The widget axes Android's Direct pass resolves, and the values it gives
/// them.
///
/// Android lays a ConstraintLayout out at OPTIMIZATION_STANDARD, which runs
/// Direct.solvingPass before the solver. It resolves, in whole pixels, every
/// widget it reaches from the container and the guidelines along links whose
/// targets it already resolved, then each barrier whose references it
/// resolved, and the solver holds every resolved axis where Direct put it
/// (ConstraintWidget.addToSolver and Barrier.addToSolver add equalities to
/// the final values). Direct's arithmetic is mostly the graph's, but not
/// quite: it works a centering offset out in Java floats, (int) (0.5f +
/// bias * distance), where the graph rounds in doubles, and it truncates the
/// offset of a widget that does not fit, (int) (bias * distance), where the
/// graph rounds it. The model reproduces both, so the barrier check can
/// compare where Direct puts an axis with where the graph does; where they
/// agree, the graph's position is Android's even when this port's solver,
/// which has no Direct pass, rounds it differently. Everything else goes
/// through Android's solver, where the graph has to match this port's solver
/// instead.
///
/// The model mirrors Direct.solvingPass, its horizontal and vertical solving
/// passes and the measure requests BasicMeasure.measureChildren leaves for
/// it, on the state the graph resolved: the container's size and the
/// measured size of every widget. It changes no widget. Where it is unsure
/// it leaves an axis unresolved, which only sends more of a layout through
/// the checks for the solver's part. A match-parent axis is one such case:
/// Direct places it at the size the measurer reported, which the graph does
/// not use.
class DirectResolution {
  /// Models the Direct pass of [container], whose children the graph has
  /// resolved.
  DirectResolution(this._container) {
    _run();
  }

  final ConstraintWidgetContainer _container;

  // Widgets whose measure request Android has answered: those
  // BasicMeasure.measureChildren measures before the Direct pass, and those
  // the pass measures once it can (see _canMeasure).
  final Set<ConstraintWidget> _measured = {};
  final Set<ConstraintWidget> _passedH = {};
  final Set<ConstraintWidget> _passedV = {};
  final Set<ConstraintWidget> _passingH = {};
  final Set<ConstraintWidget> _passingV = {};

  /// Whether the Direct pass would never finish on this layout. Upstream
  /// marks a widget's solving pass done only once it returns, so a widget
  /// that its own dependents lead back to (a stale dependent can close such
  /// a loop) starts its pass again and again until Java's stack overflows.
  /// It also throws on a stale dependent that has lost a target (see
  /// _lostTarget). The model stops there instead and reports it, and
  /// nothing it says about the layout counts then.
  bool diverged = false;
  bool _rootRight = false;
  bool _rootBottom = false;

  // Direct's final values: left and right (or the position, for a guideline
  // or barrier) of every horizontally resolved widget, top and bottom of
  // every vertically resolved one.
  final Map<ConstraintWidget, int> _left = {};
  final Map<ConstraintWidget, int> _right = {};
  final Map<ConstraintWidget, int> _top = {};
  final Map<ConstraintWidget, int> _bottom = {};

  static const _matchConstraint = DimensionBehaviour.matchConstraint;

  static final Float32List _float = Float32List(1);

  /// [value] rounded to a 32-bit float, as Java's float arithmetic rounds
  /// every step. Direct computes its offsets in floats, and a double can
  /// land on the other side of a half pixel (0.7f * 45 is 31.5, 0.7 * 45 is
  /// 31.499999999999996).
  static double _f(double value) {
    _float[0] = value;
    return _float[0];
  }

  /// Java's (int) (0.5f + factor * distance).
  static int _roundedOffset(double factor, int distance) =>
      _f(0.5 + _f(_f(factor) * distance)).truncate();

  /// Java's (int) (factor * distance).
  static int _truncatedOffset(double factor, int distance) =>
      _f(_f(factor) * distance).truncate();

  /// Whether Direct resolves [widget] (a child of the container) along
  /// [horizontal] or the vertical axis.
  bool resolves(ConstraintWidget widget, bool horizontal) =>
      horizontal ? _left.containsKey(widget) : _top.containsKey(widget);

  /// Where Direct puts [widget]'s start along [horizontal] or the vertical
  /// axis, or null when it does not resolve that axis.
  int? start(ConstraintWidget widget, bool horizontal) =>
      horizontal ? _left[widget] : _top[widget];

  /// Where Direct puts [widget]'s end along [horizontal] or the vertical
  /// axis, or null when it does not resolve that axis.
  int? end(ConstraintWidget widget, bool horizontal) =>
      horizontal ? _right[widget] : _bottom[widget];

  /// Direct's final value of [anchor], or null when it has none.
  int? valueOf(ConstraintAnchor anchor) =>
      _isFinal(anchor) ? _value(anchor) : null;

  bool _requested(ConstraintWidget widget) =>
      widget.getVisibility() != ConstraintWidget.GONE &&
      !_measured.contains(widget);

  /// The measured size of [widget] along an axis, as Direct reads it
  /// (getWidth and getHeight are 0 for a gone widget).
  static int _size(ConstraintWidget widget, bool horizontal) {
    if (widget.getVisibility() == ConstraintWidget.GONE) {
      return 0;
    }
    final run = horizontal ? widget.mHorizontalRun! : widget.mVerticalRun!;
    return run.mDimension.value;
  }

  /// Whether Direct has a final value for [anchor].
  bool _isFinal(ConstraintAnchor anchor) {
    final owner = anchor.mOwner;
    if (identical(owner, _container)) {
      return switch (anchor.mType) {
        ConstraintAnchorType.left || ConstraintAnchorType.top => true,
        ConstraintAnchorType.right => _rootRight,
        ConstraintAnchorType.bottom => _rootBottom,
        _ => false,
      };
    }
    if (owner is Guideline) {
      return owner.getOrientation() == Guideline.vertical
          ? _left.containsKey(owner)
          : _top.containsKey(owner);
    }
    return switch (anchor.mType) {
      ConstraintAnchorType.left ||
      ConstraintAnchorType.right => _left.containsKey(owner),
      ConstraintAnchorType.top ||
      ConstraintAnchorType.bottom => _top.containsKey(owner),
      ConstraintAnchorType.baseline =>
        _top.containsKey(owner) && _hasBaseline(owner),
      _ => false,
    };
  }

  /// Whether [widget] has a baseline in the Direct pass.
  /// BasicMeasure.measureChildren measures a gone widget too, unless it
  /// leaves an axis of it to the pass, and BasicMeasure.measure then sets
  /// the distance the measurer reported (setBaselineDistance), which clears
  /// the flag for a distance of 0: Android's measurer answers a gone widget
  /// with a baseline of 0. The engine does not measure a gone widget, so it
  /// keeps the flag it was given (the Flutter adapter flags both ends of a
  /// baseline link). Without a baseline, setFinalBaseline does nothing and
  /// setFinalVertical gives the baseline anchor no final value.
  bool _hasBaseline(ConstraintWidget widget) =>
      widget.hasBaseline() &&
      (widget.getVisibility() != ConstraintWidget.GONE ||
          !_measured.contains(widget) ||
          widget.getBaselineDistance() > 0);

  /// Direct's final value of [anchor]: ConstraintAnchor.getFinalValue, which
  /// is 0 for an anchor without one. Direct reads such an anchor through a
  /// stale dependent (an anchor linked elsewhere since, that its old target
  /// still lists).
  int _value(ConstraintAnchor anchor) {
    final owner = anchor.mOwner;
    if (identical(owner, _container)) {
      return switch (anchor.mType) {
        ConstraintAnchorType.right => _rootRight ? _container.getWidth() : 0,
        ConstraintAnchorType.bottom => _rootBottom ? _container.getHeight() : 0,
        _ => 0,
      };
    }
    if (owner is Guideline) {
      return (owner.getOrientation() == Guideline.vertical
              ? _left[owner]
              : _top[owner]) ??
          0;
    }
    if (!_isFinal(anchor)) {
      return 0;
    }
    return switch (anchor.mType) {
      ConstraintAnchorType.left => _left[owner]!,
      ConstraintAnchorType.right => _right[owner]!,
      ConstraintAnchorType.top => _top[owner]!,
      ConstraintAnchorType.bottom => _bottom[owner]!,
      _ => _top[owner]! + owner.getBaselineDistance(),
    };
  }

  /// ConstraintWidget.hasDanglingDimension.
  static bool _dangling(ConstraintWidget widget, bool horizontal) {
    if (horizontal) {
      final targets =
          (widget.mLeft.mTarget != null ? 1 : 0) +
          (widget.mRight.mTarget != null ? 1 : 0);
      return targets < 2;
    }
    final targets =
        (widget.mTop.mTarget != null ? 1 : 0) +
        (widget.mBottom.mTarget != null ? 1 : 0) +
        (widget.mBaseline.mTarget != null ? 1 : 0);
    return targets < 2;
  }

  /// Direct.canMeasure. Its match-constraint wrap case (with resolved
  /// targets) is left out: the graph sends such layouts to the solver.
  bool _canMeasure(ConstraintWidget widget) {
    bool fixed(bool horizontal) {
      final behaviour = widget.getDimensionBehaviour(
        horizontal ? ConstraintWidget.HORIZONTAL : ConstraintWidget.VERTICAL,
      );
      return behaviour == DimensionBehaviour.fixed ||
          behaviour == DimensionBehaviour.wrapContent ||
          resolves(widget, horizontal) ||
          (behaviour == _matchConstraint &&
              (horizontal
                      ? widget.mMatchConstraintDefaultWidth
                      : widget.mMatchConstraintDefaultHeight) ==
                  ConstraintWidget.MATCH_CONSTRAINT_SPREAD &&
              widget.mDimensionRatio == 0 &&
              _dangling(widget, horizontal));
    }

    final horizontalFixed = fixed(true);
    final verticalFixed = fixed(false);
    if (widget.mDimensionRatio > 0 && (horizontalFixed || verticalFixed)) {
      return true;
    }
    return horizontalFixed && verticalFixed;
  }

  /// The widgets BasicMeasure.measureChildren measures before the Direct
  /// pass (with OPTIMIZATION_DIRECT, it leaves a match-constraint spread
  /// axis and a ratio to the pass).
  void _measureChildren() {
    for (final child in _container.mChildren) {
      if (child is Guideline || child is Barrier) {
        continue;
      }
      final width = child.getHorizontalDimensionBehaviour();
      final height = child.getVerticalDimensionBehaviour();
      final spreadWidth =
          width == _matchConstraint &&
          child.mMatchConstraintDefaultWidth ==
              ConstraintWidget.MATCH_CONSTRAINT_SPREAD;
      final spreadHeight =
          height == _matchConstraint &&
          child.mMatchConstraintDefaultHeight ==
              ConstraintWidget.MATCH_CONSTRAINT_SPREAD;
      var skip =
          width == _matchConstraint &&
          child.mMatchConstraintDefaultWidth !=
              ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
          height == _matchConstraint &&
          child.mMatchConstraintDefaultHeight !=
              ConstraintWidget.MATCH_CONSTRAINT_WRAP;
      if (!skip) {
        // Upstream tests the horizontal chain for both axes.
        if ((spreadWidth && height != _matchConstraint) ||
            (spreadHeight && width != _matchConstraint)) {
          skip = !child.isInHorizontalChain();
        }
        if ((width == _matchConstraint || height == _matchConstraint) &&
            child.mDimensionRatio > 0) {
          skip = true;
        }
      }
      if (!skip) {
        _measured.add(child);
      }
    }
  }

  /// Whether [begin] or [end], the anchors of a dependent the pass centers
  /// or fills, has no target. A stale dependent (an anchor its old target
  /// still lists after it was linked elsewhere and then reset) reaches the
  /// two-link branches that way, and upstream's
  /// solveHorizontalCenterConstraints and solveHorizontalMatchConstraint
  /// (and their vertical twins) read the missing target and throw a
  /// NullPointerException. The model stops there, as for a pass that
  /// overflows Java's stack, and nothing it says about the layout counts.
  bool _lostTarget(ConstraintAnchor begin, ConstraintAnchor end) {
    if (begin.mTarget != null && end.mTarget != null) {
      return false;
    }
    diverged = true;
    return true;
  }

  /// Direct.solveHorizontalCenterConstraints and its vertical twin, which
  /// differ for links that cross: the vertical one subtracts the offset.
  void _center(ConstraintWidget widget, bool horizontal) {
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    if (_lostTarget(begin, end)) {
      return;
    }
    var bias = horizontal
        ? widget.getHorizontalBiasPercent()
        : widget.getVerticalBiasPercent();
    final startTarget = _value(begin.mTarget!);
    final endTarget = _value(end.mTarget!);
    var s1 = startTarget + begin.getMargin();
    var s2 = endTarget - end.getMargin();
    if (startTarget == endTarget) {
      bias = 0.5;
      s1 = startTarget;
      s2 = endTarget;
    }
    final size = _size(widget, horizontal);
    final crossed = s1 > s2;
    final distance = crossed ? s1 - s2 - size : s2 - s1 - size;
    final offset = distance > 0
        ? _roundedOffset(bias, distance)
        : _truncatedOffset(bias, distance);
    var a = s1 + offset;
    var b = a + size;
    if (crossed) {
      a = horizontal ? s1 + offset : s1 - offset;
      b = a - size;
    }
    _set(widget, horizontal, a, b);
  }

  /// Direct.solveHorizontalMatchConstraint and its vertical twin, for a
  /// spread (or gone) match-constraint axis linked on both sides.
  void _solveMatchConstraint(ConstraintWidget widget, bool horizontal) {
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    if (_lostTarget(begin, end)) {
      return;
    }
    final s1 = _value(begin.mTarget!) + begin.getMargin();
    final s2 = _value(end.mTarget!) - end.getMargin();
    if (s2 < s1) {
      return;
    }
    var size = _size(widget, horizontal);
    if (widget.getVisibility() != ConstraintWidget.GONE) {
      final min = horizontal
          ? widget.mMatchConstraintMinWidth
          : widget.mMatchConstraintMinHeight;
      final max = horizontal
          ? widget.mMatchConstraintMaxWidth
          : widget.mMatchConstraintMaxHeight;
      size = s2 - s1;
      if (min > size) {
        size = min;
      }
      if (max > 0 && max < size) {
        size = max;
      }
    }
    final bias = horizontal
        ? widget.getHorizontalBiasPercent()
        : widget.getVerticalBiasPercent();
    final a = s1 + _roundedOffset(bias, s2 - s1 - size);
    _set(widget, horizontal, a, a + size);
  }

  /// ConstraintWidget.setFinalHorizontal and setFinalVertical: the first
  /// resolution wins.
  void _set(ConstraintWidget widget, bool horizontal, int a, int b) {
    if (horizontal) {
      if (!_left.containsKey(widget)) {
        _left[widget] = a;
        _right[widget] = b;
      }
    } else if (!_top.containsKey(widget)) {
      _top[widget] = a;
      _bottom[widget] = b;
    }
  }

  /// Direct.horizontalSolvingPass (with [horizontal]) or
  /// Direct.verticalSolvingPass: resolves what depends on [widget].
  void _pass(ConstraintWidget widget, bool horizontal) {
    final passed = horizontal ? _passedH : _passedV;
    if (passed.contains(widget)) {
      return;
    }
    final passing = horizontal ? _passingH : _passingV;
    if (!passing.add(widget) || diverged) {
      diverged = true;
      return;
    }
    // ConstraintWidgetContainer.measure does not measure a guideline, so its
    // measure request stays, and the last pass comes back to it.
    if (!identical(widget, _container) &&
        widget is! Guideline &&
        _requested(widget) &&
        _canMeasure(widget)) {
      _measured.add(widget);
    }
    final sides = horizontal
        ? [widget.mLeft, widget.mRight]
        : [widget.mTop, widget.mBottom];
    for (final side in sides) {
      if (side == sides[1] && widget is Guideline) {
        break;
      }
      final dependents = side.mDependents;
      if (dependents == null || !_isFinal(side)) {
        continue;
      }
      for (final first in dependents) {
        _resolveDependent(first, side, horizontal);
      }
    }
    if (!horizontal) {
      final baseline = widget.mBaseline;
      final dependents = baseline.mDependents;
      if (dependents != null && _isFinal(baseline)) {
        for (final first in dependents) {
          final dependent = first.mOwner;
          if (dependent.getParent() != _container) {
            continue;
          }
          final canMeasure = _canMeasure(dependent);
          if (_requested(dependent) && canMeasure) {
            _measured.add(dependent);
          }
          if (dependent.getVerticalDimensionBehaviour() != _matchConstraint ||
              canMeasure) {
            if (_requested(dependent)) {
              continue;
            }
            if (first == dependent.mBaseline) {
              // ConstraintWidget.setFinalBaseline does nothing without a
              // baseline, but the pass still runs (and is then spent).
              if (_hasBaseline(dependent)) {
                final y =
                    _value(baseline) +
                    first.getMargin() -
                    dependent.getBaselineDistance();
                _set(dependent, false, y, y + _size(dependent, false));
              }
              _pass(dependent, false);
            }
          }
        }
      }
    }
    passing.remove(widget);
    // Upstream returns from a guideline's pass before it marks the pass done
    // (markHorizontalSolvingPassDone), so the last pass runs it again and
    // reaches the dependents it skipped while they waited for a measure.
    if (widget is! Guideline) {
      passed.add(widget);
    }
  }

  /// One dependent of [side] in Direct's solving passes. Like upstream, it
  /// trusts the anchor that depends on [side] (a stale one included).
  void _resolveDependent(
    ConstraintAnchor first,
    ConstraintAnchor side,
    bool horizontal,
  ) {
    final widget = first.mOwner;
    if (widget.getParent() != _container) {
      return;
    }
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    final canMeasure = _canMeasure(widget);
    if (_requested(widget) && canMeasure) {
      _measured.add(widget);
    }
    final bothConnected =
        (first == begin && end.mTarget != null && _isFinal(end.mTarget!)) ||
        (first == end && begin.mTarget != null && _isFinal(begin.mTarget!));
    final inChain = horizontal
        ? widget.isInHorizontalChain()
        : widget.isInVerticalChain();
    final behaviour = widget.getDimensionBehaviour(
      horizontal ? ConstraintWidget.HORIZONTAL : ConstraintWidget.VERTICAL,
    );
    if (behaviour != _matchConstraint || canMeasure) {
      // Upstream bails out on a widget it could not measure yet.
      if (_requested(widget) || behaviour == DimensionBehaviour.matchParent) {
        return;
      }
      final size = _size(widget, horizontal);
      if (first == begin && end.mTarget == null) {
        final a = _value(side) + begin.getMargin();
        _set(widget, horizontal, a, a + size);
        _pass(widget, horizontal);
      } else if (first == end && begin.mTarget == null) {
        final b = _value(side) - end.getMargin();
        _set(widget, horizontal, b - size, b);
        _pass(widget, horizontal);
      } else if (bothConnected && !inChain) {
        _center(widget, horizontal);
        _pass(widget, horizontal);
      }
      return;
    }
    final min = horizontal
        ? widget.mMatchConstraintMinWidth
        : widget.mMatchConstraintMinHeight;
    final max = horizontal
        ? widget.mMatchConstraintMaxWidth
        : widget.mMatchConstraintMaxHeight;
    final style = horizontal
        ? widget.mMatchConstraintDefaultWidth
        : widget.mMatchConstraintDefaultHeight;
    if (max >= 0 &&
        min >= 0 &&
        (widget.getVisibility() == ConstraintWidget.GONE ||
            (style == ConstraintWidget.MATCH_CONSTRAINT_SPREAD &&
                widget.mDimensionRatio == 0)) &&
        !inChain &&
        !widget.isInVirtualLayout() &&
        bothConnected) {
      _solveMatchConstraint(widget, horizontal);
      if (resolves(widget, horizontal)) {
        _pass(widget, horizontal);
      }
    }
  }

  /// Barrier.allSolved: resolves [barrier] (along its own axis) when Direct
  /// resolved every reference it counts.
  bool _solveBarrier(Barrier barrier) {
    final horizontal = barrier.getOrientation() == ConstraintWidget.HORIZONTAL;
    if (barrier.mWidgetsCount == 0) {
      return false;
    }
    final type = barrier.getBarrierType();
    var position = 0;
    var initialized = false;
    for (var i = 0; i < barrier.mWidgetsCount; i++) {
      final reference = barrier.mWidgets[i]!;
      if (!barrier.getAllowsGoneWidget() && !reference.allowedInBarrier()) {
        continue;
      }
      final int value;
      if (reference is Guideline) {
        final resolved = reference.getOrientation() == Guideline.vertical
            ? _left[reference]
            : _top[reference];
        // Upstream reads a guideline's anchor on the barrier's side, which
        // only one orientation has.
        if (resolved == null ||
            (reference.getOrientation() == Guideline.vertical) != horizontal) {
          return false;
        }
        value = resolved;
      } else {
        final edge = switch (type) {
          Barrier.left => _left[reference],
          Barrier.right => _right[reference],
          Barrier.top => _top[reference],
          _ => _bottom[reference],
        };
        if (edge == null) {
          return false;
        }
        value = edge;
      }
      if (!initialized) {
        position = value;
        initialized = true;
      }
      if (type == Barrier.left || type == Barrier.top) {
        position = value < position ? value : position;
      } else {
        position = value > position ? value : position;
      }
    }
    position += barrier.getMargin();
    _set(barrier, horizontal, position, position);
    return true;
  }

  /// The position Direct.solvingPass gives [guideline], or null when it
  /// needs a container size it does not know.
  static int? _guideline(Guideline guideline, int extent, bool known) {
    if (guideline.getRelativeBegin() != -1) {
      return guideline.getRelativeBegin();
    }
    if (!known) {
      return null;
    }
    if (guideline.getRelativeEnd() != -1) {
      return extent - guideline.getRelativeEnd();
    }
    return _roundedOffset(guideline.getRelativePercent(), extent);
  }

  void _run() {
    _measureChildren();
    final children = _container.mChildren;
    _rootRight =
        _container.getHorizontalDimensionBehaviour() ==
        DimensionBehaviour.fixed;
    _rootBottom =
        _container.getVerticalDimensionBehaviour() == DimensionBehaviour.fixed;
    for (final horizontal in const [true, false]) {
      final orientation = horizontal
          ? Guideline.vertical
          : Guideline.horizontal;
      for (final child in children) {
        if (child is Guideline && child.getOrientation() == orientation) {
          final position = _guideline(
            child,
            horizontal ? _container.getWidth() : _container.getHeight(),
            horizontal ? _rootRight : _rootBottom,
          );
          if (position != null) {
            _set(child, horizontal, position, position);
          }
        }
      }
      for (final child in children) {
        if (child is Guideline && child.getOrientation() == orientation) {
          _pass(child, horizontal);
        }
      }
      _pass(_container, horizontal);
      final barrierOrientation = horizontal
          ? ConstraintWidget.HORIZONTAL
          : ConstraintWidget.VERTICAL;
      for (final child in children) {
        if (child is Barrier &&
            child.getOrientation() == barrierOrientation &&
            _solveBarrier(child)) {
          _pass(child, horizontal);
        }
      }
    }
    // Direct's last pass measures what it now can and runs both passes on
    // it, which only reach widgets linked to an axis it resolved.
    for (final child in children) {
      if (_requested(child) && _canMeasure(child)) {
        _measured.add(child);
        if (child is Guideline) {
          _pass(child, child.getOrientation() == Guideline.vertical);
        } else {
          _pass(child, true);
          _pass(child, false);
        }
      }
    }
  }
}
