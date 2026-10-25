// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.ChainRun

import '../constraint_widget.dart';
import '../constraint_widget_container.dart';
import 'dependency.dart';
import 'widget_run.dart';

class ChainRun extends WidgetRun {
  final List<WidgetRun> mWidgets = [];
  int mChainStyle = 0;

  /// Whether walking the chain went round a loop, so that the chain has no
  /// first or last member. A widget's neighbour in a chain is the owner of
  /// an anchor its own anchor targets and that targets it straight back,
  /// whatever the sides of the two anchors, so two widgets whose tops link to
  /// each other, a widget whose left links to its own left, or two widgets
  /// linked both ways on both sides form such a loop. Upstream's walk never
  /// ends on one, but upstream never builds a chain run for these layouts:
  /// `BasicMeasure.solverMeasure` keeps the graph off for any layout with a
  /// chain member. `DependencyGraph` declines a layout with a cyclic chain,
  /// and the solver lays it out as upstream's does.
  bool cyclic = false;

  ChainRun(ConstraintWidget widget, int orientation) : super(widget) {
    this.orientation = orientation;
    _build();
  }

  @override
  String toString() {
    final log = StringBuffer('ChainRun ');
    log.write(
      orientation == ConstraintWidget.HORIZONTAL
          ? 'horizontal : '
          : 'vertical : ',
    );
    for (final run in mWidgets) {
      log.write('<$run> ');
    }
    return log.toString();
  }

  @override
  bool supportsWrapComputation() {
    final count = mWidgets.length;
    for (var i = 0; i < count; i++) {
      if (!mWidgets[i].supportsWrapComputation()) {
        return false;
      }
    }
    return true;
  }

  @override
  int getWrapDimension() {
    final count = mWidgets.length;
    var wrapDimension = 0;
    for (var i = 0; i < count; i++) {
      final run = mWidgets[i];
      wrapDimension += run.start.mMargin;
      wrapDimension += run.getWrapDimension();
      wrapDimension += run.end.mMargin;
    }
    return wrapDimension;
  }

  void _build() {
    // A chain has at most as many members as its container has children, so
    // a walk that takes more steps than that went round a loop (see
    // [cyclic]).
    final limit =
        (mWidget.getParent()! as ConstraintWidgetContainer).mChildren.length;
    var current = mWidget;
    var steps = 0;
    var previous = current.getPreviousChainMember(orientation);
    while (previous != null) {
      if (++steps > limit) {
        cyclic = true;
        break;
      }
      current = previous;
      previous = current.getPreviousChainMember(orientation);
    }
    mWidget = current; // first element of the chain
    mWidgets.add(current.getRun(orientation)!);
    steps = 0;
    var next = current.getNextChainMember(orientation);
    while (next != null) {
      if (++steps > limit) {
        cyclic = true;
        break;
      }
      current = next;
      mWidgets.add(current.getRun(orientation)!);
      next = current.getNextChainMember(orientation);
    }
    for (final run in mWidgets) {
      if (orientation == ConstraintWidget.HORIZONTAL) {
        run.mWidget.horizontalChainRun = this;
      } else if (orientation == ConstraintWidget.VERTICAL) {
        run.mWidget.verticalChainRun = this;
      }
    }
    final isInRtl =
        (orientation == ConstraintWidget.HORIZONTAL) &&
        (mWidget.getParent() as ConstraintWidgetContainer).isRtl();
    if (isInRtl && mWidgets.length > 1) {
      mWidget = mWidgets[mWidgets.length - 1].mWidget;
    }
    mChainStyle = orientation == ConstraintWidget.HORIZONTAL
        ? mWidget.getHorizontalChainStyle()
        : mWidget.getVerticalChainStyle();
  }

  @override
  void clear() {
    mRunGroup = null;
    for (final run in mWidgets) {
      run.clear();
    }
  }

  @override
  void reset() {
    start.resolved = false;
    end.resolved = false;
  }

  @override
  void update(Dependency dependency) {
    if (!(start.resolved && end.resolved)) {
      return;
    }

    final parent = mWidget.getParent();
    var isInRtl = false;
    if (parent is ConstraintWidgetContainer) {
      isInRtl = parent.isRtl();
    }
    final distance = end.value - start.value;
    var size = 0;
    var numMatchConstraints = 0;
    double weights = 0;
    var numVisibleWidgets = 0;
    final count = mWidgets.length;

    var firstVisibleWidget = -1;
    for (var i = 0; i < count; i++) {
      final run = mWidgets[i];
      if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
        continue;
      }
      firstVisibleWidget = i;
      break;
    }
    var lastVisibleWidget = -1;
    for (var i = count - 1; i >= 0; i--) {
      final run = mWidgets[i];
      if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
        continue;
      }
      lastVisibleWidget = i;
      break;
    }
    for (var j = 0; j < 2; j++) {
      for (var i = 0; i < count; i++) {
        final run = mWidgets[i];
        if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
          continue;
        }
        numVisibleWidgets++;
        if (i > 0 && i >= firstVisibleWidget) {
          size += run.start.mMargin;
        }
        var dimension = run.mDimension.value;
        var treatAsFixed =
            run.mDimensionBehavior != DimensionBehaviour.matchConstraint;
        if (treatAsFixed) {
          if (orientation == ConstraintWidget.HORIZONTAL &&
              !run.mWidget.mHorizontalRun!.mDimension.resolved) {
            return;
          }
          if (orientation == ConstraintWidget.VERTICAL &&
              !run.mWidget.mVerticalRun!.mDimension.resolved) {
            return;
          }
        } else if (run.matchConstraintsType ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
            j == 0) {
          treatAsFixed = true;
          dimension = run.mDimension.wrapValue;
          numMatchConstraints++;
        } else if (run.mDimension.resolved) {
          treatAsFixed = true;
        }
        if (!treatAsFixed) {
          numMatchConstraints++;
          final weight = run.mWidget.mWeight[orientation];
          if (weight >= 0) {
            weights += weight;
          }
        } else {
          size += dimension;
        }
        if (i < count - 1 && i < lastVisibleWidget) {
          size += -run.end.mMargin;
        }
      }
      if (size < distance || numMatchConstraints == 0) {
        break;
      }
      numVisibleWidgets = 0;
      numMatchConstraints = 0;
      size = 0;
      weights = 0;
    }

    // The solver puts every member edge at its exact position and reports
    // each one as (int) (value + 0.5) (LinearSystem.getObjectVariableValue).
    // Upstream's graph rounds each gap, match-constraint size and offset
    // instead and adds the rounded values up, so its edges drift from the
    // solver's: two match-constraint members in 375 px are 188 px each and
    // overflow by 1 px, five fixed members in a spread chain can end 4 px
    // short, and a right-to-left chain rounds the other way. Here positions
    // and match-constraint sizes stay exact until each edge is resolved,
    // with the solver's rounding, and a member's size is the distance between
    // its rounded edges.
    var position = (isInRtl ? end.value : start.value).toDouble();
    if (size > distance) {
      if (isInRtl) {
        position += (size - distance) / 2;
      } else {
        position -= (size - distance) / 2;
      }
    }
    // The exact sizes of the match-constraint members the chain sizes,
    // resolved with their edges (null for every other member).
    List<double?>? matchSizes;
    // The total size of the members and margins once a min or max applied,
    // exact as the sizes it adds up.
    var sizeWithLimits = size.toDouble();
    double matchConstraintsDimension = 0;
    if (numMatchConstraints > 0) {
      matchSizes = List<double?>.filled(count, null);
      matchConstraintsDimension = (distance - size) / numMatchConstraints;

      var appliedLimits = 0;
      for (var i = 0; i < count; i++) {
        final run = mWidgets[i];
        if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
          continue;
        }
        if (run.mDimensionBehavior == DimensionBehaviour.matchConstraint &&
            !run.mDimension.resolved) {
          var dimension = matchConstraintsDimension;
          if (weights > 0) {
            final weight = run.mWidget.mWeight[orientation];
            dimension = weight * (distance - size) / weights;
          }
          int max;
          int min;
          var value = dimension;
          if (orientation == ConstraintWidget.HORIZONTAL) {
            max = run.mWidget.mMatchConstraintMaxWidth;
            min = run.mWidget.mMatchConstraintMinWidth;
          } else {
            max = run.mWidget.mMatchConstraintMaxHeight;
            min = run.mWidget.mMatchConstraintMinHeight;
          }
          if (run.matchConstraintsType ==
              ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
            value = value < run.mDimension.wrapValue
                ? value
                : run.mDimension.wrapValue.toDouble();
          }
          value = min > value ? min.toDouble() : value;
          if (max > 0) {
            value = max < value ? max.toDouble() : value;
          }
          if (value != dimension) {
            appliedLimits++;
            dimension = value;
          }
          matchSizes[i] = dimension;
        }
      }
      if (appliedLimits > 0) {
        numMatchConstraints -= appliedLimits;
        sizeWithLimits = 0;
        for (var i = 0; i < count; i++) {
          final run = mWidgets[i];
          if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
            continue;
          }
          if (i > 0 && i >= firstVisibleWidget) {
            sizeWithLimits += run.start.mMargin;
          }
          sizeWithLimits += matchSizes[i] ?? run.mDimension.value;
          if (i < count - 1 && i < lastVisibleWidget) {
            sizeWithLimits += -run.end.mMargin;
          }
        }
      }
      if (mChainStyle == ConstraintWidget.CHAIN_PACKED && appliedLimits == 0) {
        mChainStyle = ConstraintWidget.CHAIN_SPREAD;
      }
    }

    if (sizeWithLimits > distance) {
      mChainStyle = ConstraintWidget.CHAIN_PACKED;
    }

    if (numVisibleWidgets > 0 &&
        numMatchConstraints == 0 &&
        firstVisibleWidget == lastVisibleWidget) {
      mChainStyle = ConstraintWidget.CHAIN_PACKED;
    }

    if (mChainStyle == ConstraintWidget.CHAIN_SPREAD_INSIDE) {
      double gap = 0;
      if (numVisibleWidgets > 1) {
        gap = (distance - sizeWithLimits) / (numVisibleWidgets - 1);
      } else if (numVisibleWidgets == 1) {
        gap = (distance - sizeWithLimits) / 2;
      }
      if (numMatchConstraints > 0) {
        gap = 0;
      }
      for (var i = 0; i < count; i++) {
        var indexValue = i;
        if (isInRtl) {
          indexValue = count - (i + 1);
        }
        final run = mWidgets[indexValue];
        if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
          run.start.resolve(_round(position));
          run.end.resolve(_round(position));
          continue;
        }
        if (i > 0) {
          if (isInRtl) {
            position -= gap;
          } else {
            position += gap;
          }
        }
        if (i > 0 && i >= firstVisibleWidget) {
          if (isInRtl) {
            position -= run.start.mMargin;
          } else {
            position += run.start.mMargin;
          }
        }

        final edge = position;

        var dimension =
            matchSizes?[indexValue] ?? run.mDimension.value.toDouble();
        if (run.mDimensionBehavior == DimensionBehaviour.matchConstraint &&
            run.matchConstraintsType ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
          dimension = run.mDimension.wrapValue.toDouble();
        }
        if (isInRtl) {
          position -= dimension;
        } else {
          position += dimension;
        }

        _resolveEdges(
          run,
          edge,
          position,
          isInRtl,
          sized: matchSizes?[indexValue] != null,
        );
        run.mResolved = true;
        if (i < count - 1 && i < lastVisibleWidget) {
          if (isInRtl) {
            position -= -run.end.mMargin;
          } else {
            position += -run.end.mMargin;
          }
        }
      }
    } else if (mChainStyle == ConstraintWidget.CHAIN_SPREAD) {
      var gap = (distance - sizeWithLimits) / (numVisibleWidgets + 1);
      if (numMatchConstraints > 0) {
        gap = 0;
      }
      for (var i = 0; i < count; i++) {
        var indexValue = i;
        if (isInRtl) {
          indexValue = count - (i + 1);
        }
        final run = mWidgets[indexValue];
        if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
          run.start.resolve(_round(position));
          run.end.resolve(_round(position));
          continue;
        }
        if (isInRtl) {
          position -= gap;
        } else {
          position += gap;
        }
        if (i > 0 && i >= firstVisibleWidget) {
          if (isInRtl) {
            position -= run.start.mMargin;
          } else {
            position += run.start.mMargin;
          }
        }

        final edge = position;

        var dimension =
            matchSizes?[indexValue] ?? run.mDimension.value.toDouble();
        if (run.mDimensionBehavior == DimensionBehaviour.matchConstraint &&
            run.matchConstraintsType ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
          dimension = dimension < run.mDimension.wrapValue
              ? dimension
              : run.mDimension.wrapValue.toDouble();
        }

        if (isInRtl) {
          position -= dimension;
        } else {
          position += dimension;
        }

        _resolveEdges(
          run,
          edge,
          position,
          isInRtl,
          sized: matchSizes?[indexValue] != null,
        );
        if (i < count - 1 && i < lastVisibleWidget) {
          if (isInRtl) {
            position -= -run.end.mMargin;
          } else {
            position += -run.end.mMargin;
          }
        }
      }
    } else if (mChainStyle == ConstraintWidget.CHAIN_PACKED) {
      var bias = (orientation == ConstraintWidget.HORIZONTAL)
          ? mWidget.getHorizontalBiasPercent()
          : mWidget.getVerticalBiasPercent();
      if (isInRtl) {
        bias = 1 - bias;
      }
      var gap = (distance - sizeWithLimits) * bias;
      if (gap < 0 || numMatchConstraints > 0) {
        gap = 0;
      }
      if (isInRtl) {
        position -= gap;
      } else {
        position += gap;
      }
      for (var i = 0; i < count; i++) {
        var indexValue = i;
        if (isInRtl) {
          indexValue = count - (i + 1);
        }
        final run = mWidgets[indexValue];
        if (run.mWidget.getVisibility() == ConstraintWidget.GONE) {
          run.start.resolve(_round(position));
          run.end.resolve(_round(position));
          continue;
        }
        if (i > 0 && i >= firstVisibleWidget) {
          if (isInRtl) {
            position -= run.start.mMargin;
          } else {
            position += run.start.mMargin;
          }
        }
        final edge = position;

        var dimension =
            matchSizes?[indexValue] ?? run.mDimension.value.toDouble();
        if (run.mDimensionBehavior == DimensionBehaviour.matchConstraint &&
            run.matchConstraintsType ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
          dimension = run.mDimension.wrapValue.toDouble();
        }
        if (isInRtl) {
          position -= dimension;
        } else {
          position += dimension;
        }

        _resolveEdges(
          run,
          edge,
          position,
          isInRtl,
          sized: matchSizes?[indexValue] != null,
        );
        if (i < count - 1 && i < lastVisibleWidget) {
          if (isInRtl) {
            position -= -run.end.mMargin;
          } else {
            position += -run.end.mMargin;
          }
        }
      }
    }
  }

  /// An exact position as the solver reports it: (int) (value + 0.5).
  ///
  /// Adding up exact gaps and sizes can leave a position that is a whole
  /// pixel and a half in theory a few units in the last place off it (three
  /// gaps of 67 / 6 after 107 px come to 140.49999999999997), where the
  /// solver, which places each edge directly, reports the half pixel
  /// rounded. Such sums are snapped to the half pixel first.
  static int _round(double position) {
    var value = position + 0.5;
    final whole = value.roundToDouble();
    if ((value - whole).abs() < 1e-6) {
      value = whole;
    }
    return value.toInt();
  }

  /// Resolves the edges of [run], which the walk passed at the exact
  /// positions [from] and then [to] (end first in a right-to-left container),
  /// and first, when the chain [sized] it, its size: the distance between
  /// them.
  void _resolveEdges(
    WidgetRun run,
    double from,
    double to,
    bool isInRtl, {
    required bool sized,
  }) {
    final first = _round(from);
    final second = _round(to);
    if (sized) {
      run.mDimension.resolve(isInRtl ? first - second : second - first);
    }
    if (isInRtl) {
      run.end.resolve(first);
      run.start.resolve(second);
    } else {
      run.start.resolve(first);
      run.end.resolve(second);
    }
  }

  @override
  void applyToWidget() {
    for (var i = 0; i < mWidgets.length; i++) {
      mWidgets[i].applyToWidget();
    }
  }

  ConstraintWidget? _getFirstVisibleWidget() {
    for (var i = 0; i < mWidgets.length; i++) {
      final run = mWidgets[i];
      if (run.mWidget.getVisibility() != ConstraintWidget.GONE) {
        return run.mWidget;
      }
    }
    return null;
  }

  ConstraintWidget? _getLastVisibleWidget() {
    for (var i = mWidgets.length - 1; i >= 0; i--) {
      final run = mWidgets[i];
      if (run.mWidget.getVisibility() != ConstraintWidget.GONE) {
        return run.mWidget;
      }
    }
    return null;
  }

  @override
  void apply() {
    for (final run in mWidgets) {
      run.apply();
    }
    final count = mWidgets.length;
    if (count < 1) {
      return;
    }

    final firstWidget = mWidgets[0].mWidget;
    final lastWidget = mWidgets[count - 1].mWidget;

    if (orientation == ConstraintWidget.HORIZONTAL) {
      final startAnchor = firstWidget.mLeft;
      final endAnchor = lastWidget.mRight;
      final startTarget = getTargetOriented(
        startAnchor,
        ConstraintWidget.HORIZONTAL,
      );
      var startMargin = startAnchor.getMargin();
      final firstVisibleWidget = _getFirstVisibleWidget();
      if (firstVisibleWidget != null) {
        startMargin = firstVisibleWidget.mLeft.getMargin();
      }
      if (startTarget != null) {
        addTarget(start, startTarget, startMargin);
      }
      final endTarget = getTargetOriented(
        endAnchor,
        ConstraintWidget.HORIZONTAL,
      );
      var endMargin = endAnchor.getMargin();
      final lastVisibleWidget = _getLastVisibleWidget();
      if (lastVisibleWidget != null) {
        endMargin = lastVisibleWidget.mRight.getMargin();
      }
      if (endTarget != null) {
        addTarget(end, endTarget, -endMargin);
      }
    } else {
      final startAnchor = firstWidget.mTop;
      final endAnchor = lastWidget.mBottom;
      final startTarget = getTargetOriented(
        startAnchor,
        ConstraintWidget.VERTICAL,
      );
      var startMargin = startAnchor.getMargin();
      final firstVisibleWidget = _getFirstVisibleWidget();
      if (firstVisibleWidget != null) {
        startMargin = firstVisibleWidget.mTop.getMargin();
      }
      if (startTarget != null) {
        addTarget(start, startTarget, startMargin);
      }
      final endTarget = getTargetOriented(endAnchor, ConstraintWidget.VERTICAL);
      var endMargin = endAnchor.getMargin();
      final lastVisibleWidget = _getLastVisibleWidget();
      if (lastVisibleWidget != null) {
        endMargin = lastVisibleWidget.mBottom.getMargin();
      }
      if (endTarget != null) {
        addTarget(end, endTarget, -endMargin);
      }
    }
    start.updateDelegate = this;
    end.updateDelegate = this;
  }
}
