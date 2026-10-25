// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.DependencyGraph
// (debug/graphviz output omitted).

import 'dart:typed_data';

import '../barrier.dart';
import '../constraint_anchor.dart';
import '../constraint_widget.dart';
import '../constraint_widget_container.dart';
import '../guideline.dart';
import '../helper.dart';
import '../helper_widget.dart';
import '../solver_variable.dart';
import 'basic_measure.dart';
import 'chain_run.dart';
import 'dependency_node.dart';
import 'direct_resolution.dart';
import 'guideline_reference.dart';
import 'helper_references.dart';
import 'run_group.dart';
import 'vertical_widget_run.dart';
import 'widget_run.dart';

class DependencyGraph {
  static const bool useGroups = true;

  final ConstraintWidgetContainer mWidgetcontainer;
  bool mNeedBuildGraph = true;
  bool mNeedRedoMeasures = true;
  final ConstraintWidgetContainer mContainer;
  final List<WidgetRun> mRuns = [];

  DependencyGraph(ConstraintWidgetContainer container)
    : mWidgetcontainer = container,
      mContainer = container;

  Measurer? mMeasurer;
  final Measure mMeasure = Measure();

  final List<RunGroup> mGroups = [];

  void setMeasurer(Measurer? measurer) {
    mMeasurer = measurer;
  }

  /// The wrap size of [container] along [orientation], or null when a group
  /// of runs depends on itself in a loop (see [RunGroup.computeWrapSize]).
  int? _computeWrap(ConstraintWidgetContainer container, int orientation) {
    final count = mGroups.length;
    var wrapSize = 0;
    for (var i = 0; i < count; i++) {
      final run = mGroups[i];
      final size = run.computeWrapSize(container, orientation);
      if (size == null) {
        return null;
      }
      wrapSize = wrapSize > size ? wrapSize : size;
    }
    return wrapSize;
  }

  void defineTerminalWidgets(
    DimensionBehaviour horizontalBehavior,
    DimensionBehaviour verticalBehavior,
  ) {
    if (mNeedBuildGraph) {
      buildGraph();

      if (useGroups) {
        var hasBarrier = false;
        for (final widget in mWidgetcontainer.mChildren) {
          widget.isTerminalWidget[ConstraintWidget.HORIZONTAL] = true;
          widget.isTerminalWidget[ConstraintWidget.VERTICAL] = true;
          if (widget is Barrier) {
            hasBarrier = true;
          }
        }
        if (!hasBarrier) {
          for (final group in mGroups) {
            group.defineTerminalWidgets(
              horizontalBehavior == DimensionBehaviour.wrapContent,
              verticalBehavior == DimensionBehaviour.wrapContent,
            );
          }
        }
      }
    }
  }

  bool directMeasure(bool optimizeWrap) {
    optimizeWrap = optimizeWrap && useGroups;
    final wrapRequested = optimizeWrap;
    var wrapComputedH = false;
    var wrapComputedV = false;

    if (mNeedBuildGraph || mNeedRedoMeasures) {
      for (final widget in mWidgetcontainer.mChildren) {
        widget.ensureWidgetRuns();
        widget.measured = false;
        widget.mHorizontalRun!.reset();
        widget.mVerticalRun!.reset();
      }
      mWidgetcontainer.ensureWidgetRuns();
      mWidgetcontainer.measured = false;
      mWidgetcontainer.mHorizontalRun!.reset();
      mWidgetcontainer.mVerticalRun!.reset();
      // reset() destroys the graph's edges: it calls DependencyNode.clear(),
      // which empties each node's targets and dependencies, and apply-time
      // seeding (resolved fixed dimensions, baked-in margins) is lost with
      // them. The graph must therefore be rebuilt whenever runs were reset.
      // Upstream tolerates skipping the rebuild because its solver fallback
      // recomputes the layout; this engine resolves through the graph alone,
      // so a measures-only invalidation without a rebuild would leave the
      // graph unresolvable and keep stale geometry.
      mNeedBuildGraph = true;
      mNeedRedoMeasures = false;
    }

    final avoid = _basicMeasureWidgets(mContainer);
    if (avoid) {
      return false;
    }

    mWidgetcontainer.setX(0);
    mWidgetcontainer.setY(0);

    final originalHorizontalDimension = mWidgetcontainer.getDimensionBehaviour(
      ConstraintWidget.HORIZONTAL,
    );
    final originalVerticalDimension = mWidgetcontainer.getDimensionBehaviour(
      ConstraintWidget.VERTICAL,
    );

    if (mNeedBuildGraph) {
      buildGraph();
    }
    // A cyclic chain has no ends to lay its members out from, and the runs
    // of the widgets its walk left out are missing from the graph.
    if (_hasCyclicChain) {
      return false;
    }

    final x1 = mWidgetcontainer.getX();
    final y1 = mWidgetcontainer.getY();

    mWidgetcontainer.mHorizontalRun!.start.resolve(x1);
    mWidgetcontainer.mVerticalRun!.start.resolve(y1);

    measureWidgets();

    if (originalHorizontalDimension == DimensionBehaviour.wrapContent ||
        originalVerticalDimension == DimensionBehaviour.wrapContent) {
      if (optimizeWrap) {
        for (final run in mRuns) {
          if (!run.supportsWrapComputation()) {
            optimizeWrap = false;
            break;
          }
        }
      }

      // A wrap size that loops (null) is left uncomputed, which sends the
      // layout to the solver below. The graph cannot resolve such a loop.
      final wrapWidth =
          optimizeWrap &&
              originalHorizontalDimension == DimensionBehaviour.wrapContent
          ? _computeWrap(mWidgetcontainer, ConstraintWidget.HORIZONTAL)
          : null;
      if (wrapWidth != null) {
        mWidgetcontainer.setHorizontalDimensionBehaviour(
          DimensionBehaviour.fixed,
        );
        mWidgetcontainer.setWidth(wrapWidth);
        mWidgetcontainer.mHorizontalRun!.mDimension.resolve(
          mWidgetcontainer.getWidth(),
        );
        wrapComputedH = true;
      }
      final wrapHeight =
          optimizeWrap &&
              originalVerticalDimension == DimensionBehaviour.wrapContent
          ? _computeWrap(mWidgetcontainer, ConstraintWidget.VERTICAL)
          : null;
      if (wrapHeight != null) {
        mWidgetcontainer.setVerticalDimensionBehaviour(
          DimensionBehaviour.fixed,
        );
        mWidgetcontainer.setHeight(wrapHeight);
        mWidgetcontainer.mVerticalRun!.mDimension.resolve(
          mWidgetcontainer.getHeight(),
        );
        wrapComputedV = true;
      }
    }

    var checkRoot = false;

    if (mWidgetcontainer.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] ==
            DimensionBehaviour.fixed ||
        mWidgetcontainer.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] ==
            DimensionBehaviour.matchParent) {
      final x2 = x1 + mWidgetcontainer.getWidth();
      mWidgetcontainer.mHorizontalRun!.end.resolve(x2);
      mWidgetcontainer.mHorizontalRun!.mDimension.resolve(x2 - x1);
      measureWidgets();
      if (mWidgetcontainer.mListDimensionBehaviors[ConstraintWidget.VERTICAL] ==
              DimensionBehaviour.fixed ||
          mWidgetcontainer.mListDimensionBehaviors[ConstraintWidget.VERTICAL] ==
              DimensionBehaviour.matchParent) {
        final y2 = y1 + mWidgetcontainer.getHeight();
        mWidgetcontainer.mVerticalRun!.end.resolve(y2);
        mWidgetcontainer.mVerticalRun!.mDimension.resolve(y2 - y1);
      }
      measureWidgets();
      checkRoot = true;
    }

    for (final run in mRuns) {
      if (run.mWidget == mWidgetcontainer && !run.mResolved) {
        continue;
      }
      run.applyToWidget();
    }

    var allResolved = true;
    var hasBarrier = false;
    for (final run in mRuns) {
      if (!checkRoot && run.mWidget == mWidgetcontainer) {
        continue;
      }
      final runWidget = run.mWidget;
      if (runWidget is Barrier && run is! HelperReferences) {
        hasBarrier = true;
        // Nothing positions a barrier across its own axis (upstream's
        // HorizontalWidgetRun and VerticalWidgetRun skip helpers, and
        // Barrier.addToSolver leaves that axis unconstrained), so the run
        // stays unresolved. It only matters when another widget is anchored
        // to that axis of the barrier.
        if (run.orientation != runWidget.getOrientation() &&
            !_hasDependentsAcross(runWidget, run.orientation)) {
          continue;
        }
      }
      if (!run.start.resolved) {
        allResolved = false;
        break;
      }
      if (!run.end.resolved && run is! GuidelineReference) {
        allResolved = false;
        break;
      }
      if (!run.mDimension.resolved &&
          run is! ChainRun &&
          run is! GuidelineReference) {
        allResolved = false;
        break;
      }
      // The graph measures MATCH_CONSTRAINT_WRAP widgets at their wrap size
      // without clamping them into the available space between their anchors
      // (the solver applies the min rule, as Android does), and it ignores
      // circular (center) constraints entirely. Route layouts containing
      // either to the solver fallback.
      if (run.mWidget != mWidgetcontainer &&
          run is! GuidelineReference &&
          run is! ChainRun) {
        final w = run.mWidget;
        if (w.mCenter.isConnected()) {
          allResolved = false;
          break;
        }
        final mcDefault = run.orientation == ConstraintWidget.HORIZONTAL
            ? w.mMatchConstraintDefaultWidth
            : w.mMatchConstraintDefaultHeight;
        if (w.mListDimensionBehaviors[run.orientation] ==
                DimensionBehaviour.matchConstraint &&
            mcDefault == ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
          allResolved = false;
          break;
        }
        // A size that resolved after the widget's last measure: the widget
        // would report its measured size instead (see _placesMember).
        final horizontal = run.orientation == ConstraintWidget.HORIZONTAL;
        if (run.mDimension.value !=
                (horizontal ? w.getWidth() : w.getHeight()) &&
            w is! Helper &&
            w.getVisibility() != ConstraintWidget.GONE) {
          allResolved = false;
          break;
        }
        // Android ignores a baseline link from a widget without a baseline,
        // where the graph puts the widget's top on the link's target (see
        // _ignoresBaselineLink). Connecting a baseline resets the widget's
        // top and bottom (ConstraintWidget.connect), so its vertical run is
        // not a chain's, and this loop reaches it.
        if (!horizontal &&
            w.mBaseline.mTarget != null &&
            _ignoresBaselineLink(w)) {
          allResolved = false;
          break;
        }
      }
      // The graph's handling of chains diverges from the solver, and from
      // Android, in four cases: GONE members (collapsed chain positioning),
      // ratio-sized and percent matchConstraint members, and chains along a
      // wrap-content axis of the container (chain sizing must feed the wrap
      // size). ChainRun spreads the space over every match-constraint member
      // whose size is not resolved yet, and a percent size resolves late when
      // the member's other axis is match-constraint too, so the chain gives
      // it a share instead of its percent. Report such chains as unresolved
      // and let the solver fallback produce the layout.
      if (run is ChainRun) {
        var needsSolver = false;
        final chainAxisBehaviour =
            run.orientation == ConstraintWidget.HORIZONTAL
            ? originalHorizontalDimension
            : originalVerticalDimension;
        if (chainAxisBehaviour == DimensionBehaviour.wrapContent) {
          needsSolver = true;
        }
        if (!needsSolver) {
          for (final memberRun in run.mWidgets) {
            final member = memberRun.mWidget;
            if (member.getVisibility() == ConstraintWidget.GONE) {
              needsSolver = true;
              break;
            }
            final memberDefault = run.orientation == ConstraintWidget.HORIZONTAL
                ? member.mMatchConstraintDefaultWidth
                : member.mMatchConstraintDefaultHeight;
            if (member.mListDimensionBehaviors[run.orientation] ==
                    DimensionBehaviour.matchConstraint &&
                (member.mDimensionRatio != 0 ||
                    memberDefault == ConstraintWidget.MATCH_CONSTRAINT_WRAP ||
                    memberDefault ==
                        ConstraintWidget.MATCH_CONSTRAINT_PERCENT)) {
              needsSolver = true;
              break;
            }
            if (!_placesMember(run, memberRun)) {
              needsSolver = true;
              break;
            }
          }
        }
        // In a right-to-left container, upstream's ChainRun lays every chain
        // (vertical ones included) out from its end but applies each member's
        // margins on the left-to-right side, so a chain with margins lands
        // off by them. Android does not run this path by default (its
        // standard optimization level leaves the graph off), so such chains
        // go to the solver, which places them as Android does.
        if (!needsSolver && mWidgetcontainer.isRtl()) {
          for (final memberRun in run.mWidgets) {
            if (memberRun.start.mMargin != 0 || memberRun.end.mMargin != 0) {
              needsSolver = true;
              break;
            }
          }
        }
        if (needsSolver) {
          allResolved = false;
          break;
        }
      }
    }

    // A wrap-content axis whose size the graph was asked to compute but did
    // not (a run that does not support wrap computation, such as a barrier or
    // a guideline, turns the computation off) keeps the container's incoming
    // size, which is not its wrap size. Upstream's solver-first entry never
    // reads it; this engine would, so such a layout goes to the solver.
    if (allResolved &&
        wrapRequested &&
        ((originalHorizontalDimension == DimensionBehaviour.wrapContent &&
                !wrapComputedH) ||
            (originalVerticalDimension == DimensionBehaviour.wrapContent &&
                !wrapComputedV))) {
      allResolved = false;
    }

    // A match-constraint axis the graph sized below the widget's minimum
    // (setMinWidth, setMinHeight): the solver gives it the same size, then
    // ConstraintWidget.setFrame raises it to the minimum and records an
    // override, and the solver solves again with that size fixed, which
    // moves the widget and whatever is linked to it. The graph only raises
    // the reported size, so such a layout goes to the solver.
    if (allResolved && _matchBelowMinimum()) {
      allResolved = false;
    }

    // ConstraintWidget.setWrapBehaviorInParent leaves a widget out of a
    // wrap-content container's size on one axis or both. Only addToSolver
    // reads it (the graph's wrap computation counts every widget), so a
    // layout where it has an effect goes to the solver.
    if (allResolved &&
        _excludesWidgetFromWrap(
          originalHorizontalDimension == DimensionBehaviour.wrapContent,
          originalVerticalDimension == DimensionBehaviour.wrapContent,
        )) {
      allResolved = false;
    }

    // A match-parent child on an axis the container wraps; see
    // _matchesWrappingParent.
    if (allResolved &&
        _matchesWrappingParent(
          originalHorizontalDimension == DimensionBehaviour.wrapContent,
          originalVerticalDimension == DimensionBehaviour.wrapContent,
        )) {
      allResolved = false;
    }

    // The solver positions a barrier through soft constraints, so in some
    // layouts it does not put the barrier where the graph does. Those go to
    // the solver; see _barriersMatchSolver.
    if (allResolved && hasBarrier && !_barriersMatchSolver()) {
      allResolved = false;
    }

    mWidgetcontainer.setHorizontalDimensionBehaviour(
      originalHorizontalDimension!,
    );
    mWidgetcontainer.setVerticalDimensionBehaviour(originalVerticalDimension!);

    return allResolved;
  }

  bool directMeasureSetup(bool optimizeWrap) {
    if (mNeedBuildGraph) {
      for (final widget in mWidgetcontainer.mChildren) {
        widget.ensureWidgetRuns();
        widget.measured = false;
        widget.mHorizontalRun!.mDimension.resolved = false;
        widget.mHorizontalRun!.mResolved = false;
        widget.mHorizontalRun!.reset();
        widget.mVerticalRun!.mDimension.resolved = false;
        widget.mVerticalRun!.mResolved = false;
        widget.mVerticalRun!.reset();
      }
      mWidgetcontainer.ensureWidgetRuns();
      mWidgetcontainer.measured = false;
      mWidgetcontainer.mHorizontalRun!.mDimension.resolved = false;
      mWidgetcontainer.mHorizontalRun!.mResolved = false;
      mWidgetcontainer.mHorizontalRun!.reset();
      mWidgetcontainer.mVerticalRun!.mDimension.resolved = false;
      mWidgetcontainer.mVerticalRun!.mResolved = false;
      mWidgetcontainer.mVerticalRun!.reset();
      buildGraph();
    }

    final avoid = _basicMeasureWidgets(mContainer);
    if (avoid) {
      return false;
    }

    mWidgetcontainer.setX(0);
    mWidgetcontainer.setY(0);
    mWidgetcontainer.mHorizontalRun!.start.resolve(0);
    mWidgetcontainer.mVerticalRun!.start.resolve(0);
    return true;
  }

  bool directMeasureWithOrientation(bool optimizeWrap, int orientation) {
    optimizeWrap = optimizeWrap && useGroups;

    final originalHorizontalDimension = mWidgetcontainer.getDimensionBehaviour(
      ConstraintWidget.HORIZONTAL,
    );
    final originalVerticalDimension = mWidgetcontainer.getDimensionBehaviour(
      ConstraintWidget.VERTICAL,
    );

    final x1 = mWidgetcontainer.getX();
    final y1 = mWidgetcontainer.getY();

    if (optimizeWrap &&
        (originalHorizontalDimension == DimensionBehaviour.wrapContent ||
            originalVerticalDimension == DimensionBehaviour.wrapContent)) {
      for (final run in mRuns) {
        if (run.orientation == orientation && !run.supportsWrapComputation()) {
          optimizeWrap = false;
          break;
        }
      }

      // A wrap size that loops (null) leaves the axis to the solver.
      if (orientation == ConstraintWidget.HORIZONTAL) {
        if (optimizeWrap &&
            originalHorizontalDimension == DimensionBehaviour.wrapContent) {
          final wrapWidth = _computeWrap(
            mWidgetcontainer,
            ConstraintWidget.HORIZONTAL,
          );
          if (wrapWidth == null) {
            return false;
          }
          mWidgetcontainer.setHorizontalDimensionBehaviour(
            DimensionBehaviour.fixed,
          );
          mWidgetcontainer.setWidth(wrapWidth);
          mWidgetcontainer.mHorizontalRun!.mDimension.resolve(
            mWidgetcontainer.getWidth(),
          );
        }
      } else {
        if (optimizeWrap &&
            originalVerticalDimension == DimensionBehaviour.wrapContent) {
          final wrapHeight = _computeWrap(
            mWidgetcontainer,
            ConstraintWidget.VERTICAL,
          );
          if (wrapHeight == null) {
            return false;
          }
          mWidgetcontainer.setVerticalDimensionBehaviour(
            DimensionBehaviour.fixed,
          );
          mWidgetcontainer.setHeight(wrapHeight);
          mWidgetcontainer.mVerticalRun!.mDimension.resolve(
            mWidgetcontainer.getHeight(),
          );
        }
      }
    }

    var checkRoot = false;

    if (orientation == ConstraintWidget.HORIZONTAL) {
      if (mWidgetcontainer.mListDimensionBehaviors[ConstraintWidget
                  .HORIZONTAL] ==
              DimensionBehaviour.fixed ||
          mWidgetcontainer.mListDimensionBehaviors[ConstraintWidget
                  .HORIZONTAL] ==
              DimensionBehaviour.matchParent) {
        final x2 = x1 + mWidgetcontainer.getWidth();
        mWidgetcontainer.mHorizontalRun!.end.resolve(x2);
        mWidgetcontainer.mHorizontalRun!.mDimension.resolve(x2 - x1);
        checkRoot = true;
      }
    } else {
      if (mWidgetcontainer.mListDimensionBehaviors[ConstraintWidget.VERTICAL] ==
              DimensionBehaviour.fixed ||
          mWidgetcontainer.mListDimensionBehaviors[ConstraintWidget.VERTICAL] ==
              DimensionBehaviour.matchParent) {
        final y2 = y1 + mWidgetcontainer.getHeight();
        mWidgetcontainer.mVerticalRun!.end.resolve(y2);
        mWidgetcontainer.mVerticalRun!.mDimension.resolve(y2 - y1);
        checkRoot = true;
      }
    }
    measureWidgets();

    for (final run in mRuns) {
      if (run.orientation != orientation) {
        continue;
      }
      if (run.mWidget == mWidgetcontainer && !run.mResolved) {
        continue;
      }
      run.applyToWidget();
    }

    var allResolved = true;
    for (final run in mRuns) {
      if (run.orientation != orientation) {
        continue;
      }
      if (!checkRoot && run.mWidget == mWidgetcontainer) {
        continue;
      }
      if (!run.start.resolved) {
        allResolved = false;
        break;
      }
      if (!run.end.resolved) {
        allResolved = false;
        break;
      }
      if (run is! ChainRun && !run.mDimension.resolved) {
        allResolved = false;
        break;
      }
    }

    mWidgetcontainer.setHorizontalDimensionBehaviour(
      originalHorizontalDimension!,
    );
    mWidgetcontainer.setVerticalDimensionBehaviour(originalVerticalDimension!);

    return allResolved;
  }

  void _measure(
    ConstraintWidget widget,
    DimensionBehaviour horizontalBehavior,
    int horizontalDimension,
    DimensionBehaviour verticalBehavior,
    int verticalDimension,
  ) {
    mMeasure.horizontalBehavior = horizontalBehavior;
    mMeasure.verticalBehavior = verticalBehavior;
    mMeasure.horizontalDimension = horizontalDimension;
    mMeasure.verticalDimension = verticalDimension;
    mMeasurer!.measure(widget, mMeasure);
    widget.setWidth(mMeasure.measuredWidth);
    widget.setHeight(mMeasure.measuredHeight);
    widget.setHasBaseline(mMeasure.measuredHasBaseline);
    widget.setBaselineDistance(mMeasure.measuredBaseline);
  }

  bool _basicMeasureWidgets(
    ConstraintWidgetContainer constraintWidgetContainer,
  ) {
    for (final widget in constraintWidgetContainer.mChildren) {
      var horizontal =
          widget.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL];
      var vertical = widget.mListDimensionBehaviors[ConstraintWidget.VERTICAL];

      if (widget.getVisibility() == ConstraintWidget.GONE) {
        widget.measured = true;
        // Runs persist across passes on a persistent container, and the
        // behaviour assignments below are skipped for GONE widgets. Restore
        // the pristine defaults a fresh widget's runs would have, or a run
        // behaviour from an earlier visible pass (for example matchParent)
        // leaks into apply() and changes how the gone widget is anchored.
        widget.mHorizontalRun!.mDimensionBehavior = null;
        widget.mHorizontalRun!.matchConstraintsType = 0;
        widget.mVerticalRun!.mDimensionBehavior = null;
        widget.mVerticalRun!.matchConstraintsType = 0;
        continue;
      }

      // Note: upstream uses `< 1`, but `setHorizontalMatchStyle` only treats a
      // percent as PERCENT when `> 0 && < 1`. A WRAP style passes percent 0,
      // which must NOT be reclassified as PERCENT. Aligning the guard keeps the
      // graph engine in agreement with the solver's golden results.
      if (widget.mMatchConstraintPercentWidth > 0 &&
          widget.mMatchConstraintPercentWidth < 1 &&
          horizontal == DimensionBehaviour.matchConstraint) {
        widget.mMatchConstraintDefaultWidth =
            ConstraintWidget.MATCH_CONSTRAINT_PERCENT;
      }
      if (widget.mMatchConstraintPercentHeight > 0 &&
          widget.mMatchConstraintPercentHeight < 1 &&
          vertical == DimensionBehaviour.matchConstraint) {
        widget.mMatchConstraintDefaultHeight =
            ConstraintWidget.MATCH_CONSTRAINT_PERCENT;
      }
      if (widget.getDimensionRatio() > 0) {
        if (horizontal == DimensionBehaviour.matchConstraint &&
            (vertical == DimensionBehaviour.wrapContent ||
                vertical == DimensionBehaviour.fixed)) {
          widget.mMatchConstraintDefaultWidth =
              ConstraintWidget.MATCH_CONSTRAINT_RATIO;
        } else if (vertical == DimensionBehaviour.matchConstraint &&
            (horizontal == DimensionBehaviour.wrapContent ||
                horizontal == DimensionBehaviour.fixed)) {
          widget.mMatchConstraintDefaultHeight =
              ConstraintWidget.MATCH_CONSTRAINT_RATIO;
        } else if (horizontal == DimensionBehaviour.matchConstraint &&
            vertical == DimensionBehaviour.matchConstraint) {
          if (widget.mMatchConstraintDefaultWidth ==
              ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
            widget.mMatchConstraintDefaultWidth =
                ConstraintWidget.MATCH_CONSTRAINT_RATIO;
          }
          if (widget.mMatchConstraintDefaultHeight ==
              ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
            widget.mMatchConstraintDefaultHeight =
                ConstraintWidget.MATCH_CONSTRAINT_RATIO;
          }
        }
      }

      if (horizontal == DimensionBehaviour.matchConstraint &&
          widget.mMatchConstraintDefaultWidth ==
              ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
        if (widget.mLeft.mTarget == null || widget.mRight.mTarget == null) {
          horizontal = DimensionBehaviour.wrapContent;
        }
      }
      if (vertical == DimensionBehaviour.matchConstraint &&
          widget.mMatchConstraintDefaultHeight ==
              ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
        if (widget.mTop.mTarget == null || widget.mBottom.mTarget == null) {
          vertical = DimensionBehaviour.wrapContent;
        }
      }

      widget.mHorizontalRun!.mDimensionBehavior = horizontal;
      widget.mHorizontalRun!.matchConstraintsType =
          widget.mMatchConstraintDefaultWidth;
      widget.mVerticalRun!.mDimensionBehavior = vertical;
      widget.mVerticalRun!.matchConstraintsType =
          widget.mMatchConstraintDefaultHeight;

      if ((horizontal == DimensionBehaviour.matchParent ||
              horizontal == DimensionBehaviour.fixed ||
              horizontal == DimensionBehaviour.wrapContent) &&
          (vertical == DimensionBehaviour.matchParent ||
              vertical == DimensionBehaviour.fixed ||
              vertical == DimensionBehaviour.wrapContent)) {
        var width = widget.getWidth();
        if (horizontal == DimensionBehaviour.matchParent) {
          width =
              constraintWidgetContainer.getWidth() -
              widget.mLeft.mMargin -
              widget.mRight.mMargin;
          horizontal = DimensionBehaviour.fixed;
        }
        var height = widget.getHeight();
        if (vertical == DimensionBehaviour.matchParent) {
          height =
              constraintWidgetContainer.getHeight() -
              widget.mTop.mMargin -
              widget.mBottom.mMargin;
          vertical = DimensionBehaviour.fixed;
        }
        _measure(widget, horizontal, width, vertical, height);
        widget.mHorizontalRun!.mDimension.resolve(widget.getWidth());
        widget.mVerticalRun!.mDimension.resolve(widget.getHeight());
        widget.measured = true;
        continue;
      }

      if (horizontal == DimensionBehaviour.matchConstraint &&
          (vertical == DimensionBehaviour.wrapContent ||
              vertical == DimensionBehaviour.fixed)) {
        if (widget.mMatchConstraintDefaultWidth ==
            ConstraintWidget.MATCH_CONSTRAINT_RATIO) {
          if (vertical == DimensionBehaviour.wrapContent) {
            _measure(
              widget,
              DimensionBehaviour.wrapContent,
              0,
              DimensionBehaviour.wrapContent,
              0,
            );
          }
          final height = widget.getHeight();
          final width = (height * widget.mDimensionRatio + 0.5).toInt();
          _measure(
            widget,
            DimensionBehaviour.fixed,
            width,
            DimensionBehaviour.fixed,
            height,
          );
          widget.mHorizontalRun!.mDimension.resolve(widget.getWidth());
          widget.mVerticalRun!.mDimension.resolve(widget.getHeight());
          widget.measured = true;
          continue;
        } else if (widget.mMatchConstraintDefaultWidth ==
            ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
          _measure(
            widget,
            DimensionBehaviour.wrapContent,
            0,
            vertical,
            widget.getHeight(),
          );
          widget.mHorizontalRun!.mDimension.wrapValue = widget.getWidth();
          continue;
        } else if (widget.mMatchConstraintDefaultWidth ==
            ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
          if (constraintWidgetContainer.mListDimensionBehaviors[ConstraintWidget
                      .HORIZONTAL] ==
                  DimensionBehaviour.fixed ||
              constraintWidgetContainer.mListDimensionBehaviors[ConstraintWidget
                      .HORIZONTAL] ==
                  DimensionBehaviour.matchParent) {
            final percent = widget.mMatchConstraintPercentWidth;
            var width = (0.5 + percent * constraintWidgetContainer.getWidth())
                .toInt();
            // Divergence from upstream: clamp percent by the matchConstraint
            // min/max. Upstream relies on its solver-first entry to apply the
            // bounds; this engine resolves percent in the graph. UPSTREAM.md.
            if (width < widget.mMatchConstraintMinWidth) {
              width = widget.mMatchConstraintMinWidth;
            }
            if (widget.mMatchConstraintMaxWidth > 0 &&
                width > widget.mMatchConstraintMaxWidth) {
              width = widget.mMatchConstraintMaxWidth;
            }
            final height = widget.getHeight();
            _measure(widget, DimensionBehaviour.fixed, width, vertical, height);
            widget.mHorizontalRun!.mDimension.resolve(widget.getWidth());
            widget.mVerticalRun!.mDimension.resolve(widget.getHeight());
            widget.measured = true;
            continue;
          }
        } else {
          if (widget.mListAnchors[ConstraintWidget.ANCHOR_LEFT].mTarget ==
                  null ||
              widget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT].mTarget ==
                  null) {
            _measure(
              widget,
              DimensionBehaviour.wrapContent,
              0,
              vertical,
              widget.getHeight(),
            );
            widget.mHorizontalRun!.mDimension.resolve(widget.getWidth());
            widget.mVerticalRun!.mDimension.resolve(widget.getHeight());
            widget.measured = true;
            continue;
          }
        }
      }
      if (vertical == DimensionBehaviour.matchConstraint &&
          (horizontal == DimensionBehaviour.wrapContent ||
              horizontal == DimensionBehaviour.fixed)) {
        if (widget.mMatchConstraintDefaultHeight ==
            ConstraintWidget.MATCH_CONSTRAINT_RATIO) {
          if (horizontal == DimensionBehaviour.wrapContent) {
            _measure(
              widget,
              DimensionBehaviour.wrapContent,
              0,
              DimensionBehaviour.wrapContent,
              0,
            );
          }
          final width = widget.getWidth();
          var ratio = widget.mDimensionRatio;
          if (widget.getDimensionRatioSide() == ConstraintWidget.UNKNOWN) {
            ratio = 1 / ratio;
          }
          final height = (width * ratio + 0.5).toInt();
          _measure(
            widget,
            DimensionBehaviour.fixed,
            width,
            DimensionBehaviour.fixed,
            height,
          );
          widget.mHorizontalRun!.mDimension.resolve(widget.getWidth());
          widget.mVerticalRun!.mDimension.resolve(widget.getHeight());
          widget.measured = true;
          continue;
        } else if (widget.mMatchConstraintDefaultHeight ==
            ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
          _measure(
            widget,
            horizontal,
            widget.getWidth(),
            DimensionBehaviour.wrapContent,
            0,
          );
          widget.mVerticalRun!.mDimension.wrapValue = widget.getHeight();
          continue;
        } else if (widget.mMatchConstraintDefaultHeight ==
            ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
          if (constraintWidgetContainer.mListDimensionBehaviors[ConstraintWidget
                      .VERTICAL] ==
                  DimensionBehaviour.fixed ||
              constraintWidgetContainer.mListDimensionBehaviors[ConstraintWidget
                      .VERTICAL] ==
                  DimensionBehaviour.matchParent) {
            final percent = widget.mMatchConstraintPercentHeight;
            final width = widget.getWidth();
            var height = (0.5 + percent * constraintWidgetContainer.getHeight())
                .toInt();
            // Divergence from upstream: clamp percent by the matchConstraint
            // min/max. Upstream relies on its solver-first entry to apply the
            // bounds; this engine resolves percent in the graph. UPSTREAM.md.
            if (height < widget.mMatchConstraintMinHeight) {
              height = widget.mMatchConstraintMinHeight;
            }
            if (widget.mMatchConstraintMaxHeight > 0 &&
                height > widget.mMatchConstraintMaxHeight) {
              height = widget.mMatchConstraintMaxHeight;
            }
            _measure(
              widget,
              horizontal,
              width,
              DimensionBehaviour.fixed,
              height,
            );
            widget.mHorizontalRun!.mDimension.resolve(widget.getWidth());
            widget.mVerticalRun!.mDimension.resolve(widget.getHeight());
            widget.measured = true;
            continue;
          }
        } else {
          if (widget.mListAnchors[ConstraintWidget.ANCHOR_TOP].mTarget ==
                  null ||
              widget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM].mTarget ==
                  null) {
            // Divergence from upstream, which repeats the horizontal branch's
            // call here, measure(widget, WRAP_CONTENT, 0, vertical, 0): that
            // measures the width as wrap content, replacing a fixed width
            // with the content's, and asks for the unanchored height at its
            // stored size instead of around its content. Measure the height
            // as wrap content and keep the width as given, mirroring the
            // horizontal case and the MATCH_CONSTRAINT_WRAP case above.
            // Android's default path (the Direct pass, then the solver) does
            // not run this code: BasicMeasure asks the measurer with the
            // widget's own behaviours and its width as given. UPSTREAM.md.
            _measure(
              widget,
              horizontal,
              widget.getWidth(),
              DimensionBehaviour.wrapContent,
              0,
            );
            widget.mHorizontalRun!.mDimension.resolve(widget.getWidth());
            widget.mVerticalRun!.mDimension.resolve(widget.getHeight());
            widget.measured = true;
            continue;
          }
        }
      }
      if (horizontal == DimensionBehaviour.matchConstraint &&
          vertical == DimensionBehaviour.matchConstraint) {
        if (widget.mMatchConstraintDefaultWidth ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP ||
            widget.mMatchConstraintDefaultHeight ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
          _measure(
            widget,
            DimensionBehaviour.wrapContent,
            0,
            DimensionBehaviour.wrapContent,
            0,
          );
          widget.mHorizontalRun!.mDimension.wrapValue = widget.getWidth();
          widget.mVerticalRun!.mDimension.wrapValue = widget.getHeight();
        } else if (widget.mMatchConstraintDefaultHeight ==
                ConstraintWidget.MATCH_CONSTRAINT_PERCENT &&
            widget.mMatchConstraintDefaultWidth ==
                ConstraintWidget.MATCH_CONSTRAINT_PERCENT &&
            constraintWidgetContainer.mListDimensionBehaviors[ConstraintWidget
                    .HORIZONTAL] ==
                DimensionBehaviour.fixed &&
            constraintWidgetContainer.mListDimensionBehaviors[ConstraintWidget
                    .VERTICAL] ==
                DimensionBehaviour.fixed) {
          final horizPercent = widget.mMatchConstraintPercentWidth;
          final vertPercent = widget.mMatchConstraintPercentHeight;
          final width =
              (0.5 + horizPercent * constraintWidgetContainer.getWidth())
                  .toInt();
          final height =
              (0.5 + vertPercent * constraintWidgetContainer.getHeight())
                  .toInt();
          _measure(
            widget,
            DimensionBehaviour.fixed,
            width,
            DimensionBehaviour.fixed,
            height,
          );
          widget.mHorizontalRun!.mDimension.resolve(widget.getWidth());
          widget.mVerticalRun!.mDimension.resolve(widget.getHeight());
          widget.measured = true;
        }
      }
    }
    return false;
  }

  void measureWidgets() {
    for (final widget in mWidgetcontainer.mChildren) {
      if (widget.measured) {
        continue;
      }
      final horiz = widget.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL];
      final vert = widget.mListDimensionBehaviors[ConstraintWidget.VERTICAL];
      final horizMatchConstraintsType = widget.mMatchConstraintDefaultWidth;
      final vertMatchConstraintsType = widget.mMatchConstraintDefaultHeight;

      final horizWrap =
          horiz == DimensionBehaviour.wrapContent ||
          (horiz == DimensionBehaviour.matchConstraint &&
              horizMatchConstraintsType ==
                  ConstraintWidget.MATCH_CONSTRAINT_WRAP);

      final vertWrap =
          vert == DimensionBehaviour.wrapContent ||
          (vert == DimensionBehaviour.matchConstraint &&
              vertMatchConstraintsType ==
                  ConstraintWidget.MATCH_CONSTRAINT_WRAP);

      final horizResolved = widget.mHorizontalRun!.mDimension.resolved;
      final vertResolved = widget.mVerticalRun!.mDimension.resolved;

      if (horizResolved && vertResolved) {
        _measure(
          widget,
          DimensionBehaviour.fixed,
          widget.mHorizontalRun!.mDimension.value,
          DimensionBehaviour.fixed,
          widget.mVerticalRun!.mDimension.value,
        );
        widget.measured = true;
      } else if (horizResolved && vertWrap) {
        _measure(
          widget,
          DimensionBehaviour.fixed,
          widget.mHorizontalRun!.mDimension.value,
          DimensionBehaviour.wrapContent,
          widget.mVerticalRun!.mDimension.value,
        );
        if (vert == DimensionBehaviour.matchConstraint) {
          widget.mVerticalRun!.mDimension.wrapValue = widget.getHeight();
        } else {
          widget.mVerticalRun!.mDimension.resolve(widget.getHeight());
          widget.measured = true;
        }
      } else if (vertResolved && horizWrap) {
        _measure(
          widget,
          DimensionBehaviour.wrapContent,
          widget.mHorizontalRun!.mDimension.value,
          DimensionBehaviour.fixed,
          widget.mVerticalRun!.mDimension.value,
        );
        if (horiz == DimensionBehaviour.matchConstraint) {
          widget.mHorizontalRun!.mDimension.wrapValue = widget.getWidth();
        } else {
          widget.mHorizontalRun!.mDimension.resolve(widget.getWidth());
          widget.measured = true;
        }
      }
      if (widget.measured && widget.mVerticalRun!.mBaselineDimension != null) {
        widget.mVerticalRun!.mBaselineDimension!.resolve(
          widget.getBaselineDistance(),
        );
      }
    }
  }

  void invalidateGraph() {
    mNeedBuildGraph = true;
  }

  void invalidateMeasures() {
    mNeedRedoMeasures = true;
  }

  /// Whether the last [buildGraph] built a [ChainRun.cyclic] chain run.
  bool _hasCyclicChain = false;

  void buildGraph() {
    _buildGraphRuns(mRuns);

    if (useGroups) {
      mGroups.clear();
      RunGroup.index = 0;
      _findGroup(
        mWidgetcontainer.mHorizontalRun!,
        ConstraintWidget.HORIZONTAL,
        mGroups,
      );
      _findGroup(
        mWidgetcontainer.mVerticalRun!,
        ConstraintWidget.VERTICAL,
        mGroups,
      );
    }
    mNeedBuildGraph = false;
  }

  void _buildGraphRuns(List<WidgetRun> runs) {
    runs.clear();
    // Rebuild chain runs from scratch each time so a chain style (or membership)
    // changed since the last layout is picked up. A cached ChainRun keeps a stale
    // mChainStyle, which it also mutates during update().
    for (final widget in mContainer.mChildren) {
      widget.horizontalChainRun = null;
      widget.verticalChainRun = null;
    }
    mContainer.mHorizontalRun!.clear();
    mContainer.mVerticalRun!.clear();
    runs.add(mContainer.mHorizontalRun!);
    runs.add(mContainer.mVerticalRun!);
    Set<ChainRun>? chainRuns;
    for (final widget in mContainer.mChildren) {
      if (widget is Guideline) {
        runs.add(GuidelineReference(widget));
        continue;
      }
      if (widget.isInHorizontalChain()) {
        widget.horizontalChainRun ??= ChainRun(
          widget,
          ConstraintWidget.HORIZONTAL,
        );
        chainRuns ??= <ChainRun>{};
        chainRuns.add(widget.horizontalChainRun!);
      } else {
        runs.add(widget.mHorizontalRun!);
      }
      if (widget.isInVerticalChain()) {
        widget.verticalChainRun ??= ChainRun(widget, ConstraintWidget.VERTICAL);
        chainRuns ??= <ChainRun>{};
        chainRuns.add(widget.verticalChainRun!);
      } else {
        runs.add(widget.mVerticalRun!);
      }
      if (widget is HelperWidget) {
        runs.add(HelperReferences(widget));
      }
    }
    _hasCyclicChain = chainRuns?.any((run) => run.cyclic) ?? false;
    if (chainRuns != null) {
      runs.addAll(chainRuns);
    }
    for (final run in runs) {
      run.clear();
    }
    for (final run in runs) {
      if (run.mWidget == mContainer) {
        continue;
      }
      run.apply();
    }
  }

  void _applyGroup(
    DependencyNode node,
    int orientation,
    int direction,
    DependencyNode? end,
    List<RunGroup> groups,
    RunGroup? group,
  ) {
    final run = node.mRun;
    if (run.mRunGroup != null ||
        run == mWidgetcontainer.mHorizontalRun ||
        run == mWidgetcontainer.mVerticalRun) {
      return;
    }

    if (group == null) {
      group = RunGroup(run, direction);
      groups.add(group);
    }

    run.mRunGroup = group;
    group.add(run);
    for (final dependent in run.start.mDependencies) {
      if (dependent is DependencyNode) {
        _applyGroup(dependent, orientation, RunGroup.start, end, groups, group);
      }
    }
    for (final dependent in run.end.mDependencies) {
      if (dependent is DependencyNode) {
        _applyGroup(dependent, orientation, RunGroup.end, end, groups, group);
      }
    }
    if (orientation == ConstraintWidget.VERTICAL && run is VerticalWidgetRun) {
      for (final dependent in run.baseline.mDependencies) {
        if (dependent is DependencyNode) {
          _applyGroup(
            dependent,
            orientation,
            RunGroup.baseline,
            end,
            groups,
            group,
          );
        }
      }
    }
    for (final target in run.start.mTargets) {
      if (target == end) {
        group.dual = true;
      }
      _applyGroup(target, orientation, RunGroup.start, end, groups, group);
    }
    for (final target in run.end.mTargets) {
      if (target == end) {
        group.dual = true;
      }
      _applyGroup(target, orientation, RunGroup.end, end, groups, group);
    }
    if (orientation == ConstraintWidget.VERTICAL && run is VerticalWidgetRun) {
      for (final target in run.baseline.mTargets) {
        _applyGroup(target, orientation, RunGroup.baseline, end, groups, group);
      }
    }
  }

  void _findGroup(WidgetRun run, int orientation, List<RunGroup> groups) {
    for (final dependent in run.start.mDependencies) {
      if (dependent is DependencyNode) {
        _applyGroup(
          dependent,
          orientation,
          RunGroup.start,
          run.end,
          groups,
          null,
        );
      } else if (dependent is WidgetRun) {
        _applyGroup(
          dependent.start,
          orientation,
          RunGroup.start,
          run.end,
          groups,
          null,
        );
      }
    }
    for (final dependent in run.end.mDependencies) {
      if (dependent is DependencyNode) {
        _applyGroup(
          dependent,
          orientation,
          RunGroup.end,
          run.start,
          groups,
          null,
        );
      } else if (dependent is WidgetRun) {
        _applyGroup(
          dependent.end,
          orientation,
          RunGroup.end,
          run.start,
          groups,
          null,
        );
      }
    }
    if (orientation == ConstraintWidget.VERTICAL) {
      for (final dependent
          in (run as VerticalWidgetRun).baseline.mDependencies) {
        if (dependent is DependencyNode) {
          _applyGroup(
            dependent,
            orientation,
            RunGroup.baseline,
            null,
            groups,
            null,
          );
        }
      }
    }
  }

  /// Whether the graph gave a visible child's match-constraint axis less
  /// than the child's minimum size on that axis.
  bool _matchBelowMinimum() {
    for (final widget in mWidgetcontainer.mChildren) {
      if (widget.getVisibility() == ConstraintWidget.GONE) {
        continue;
      }
      final horizontal = widget.mHorizontalRun!.mDimension;
      if (widget.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] ==
              DimensionBehaviour.matchConstraint &&
          horizontal.resolved &&
          horizontal.value < widget.getMinWidth()) {
        return true;
      }
      final vertical = widget.mVerticalRun!.mDimension;
      if (widget.mListDimensionBehaviors[ConstraintWidget.VERTICAL] ==
              DimensionBehaviour.matchConstraint &&
          vertical.resolved &&
          vertical.value < widget.getMinHeight()) {
        return true;
      }
    }
    return false;
  }

  /// Whether a child does not count toward the container's size on an axis
  /// the container wraps ([wrapHorizontal], [wrapVertical]); see
  /// ConstraintWidget.setWrapBehaviorInParent.
  bool _excludesWidgetFromWrap(bool wrapHorizontal, bool wrapVertical) {
    if (!wrapHorizontal && !wrapVertical) {
      return false;
    }
    for (final widget in mWidgetcontainer.mChildren) {
      switch (widget.getWrapBehaviorInParent()) {
        case ConstraintWidget.WRAP_BEHAVIOR_SKIPPED:
          return true;
        case ConstraintWidget.WRAP_BEHAVIOR_HORIZONTAL_ONLY:
          if (wrapVertical) {
            return true;
          }
        case ConstraintWidget.WRAP_BEHAVIOR_VERTICAL_ONLY:
          if (wrapHorizontal) {
            return true;
          }
      }
    }
    return false;
  }

  /// Whether a child is match-parent on an axis the container wraps
  /// ([wrapHorizontal], [wrapVertical]). _basicMeasureWidgets gives it the
  /// container's incoming size on that axis (0 for an unbounded Flutter
  /// constraint) and the wrap computation grows the container around that,
  /// where Android measures the child and wraps the container around its
  /// measured size.
  bool _matchesWrappingParent(bool wrapHorizontal, bool wrapVertical) {
    if (!wrapHorizontal && !wrapVertical) {
      return false;
    }
    for (final widget in mWidgetcontainer.mChildren) {
      if ((wrapHorizontal &&
              widget.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] ==
                  DimensionBehaviour.matchParent) ||
          (wrapVertical &&
              widget.mListDimensionBehaviors[ConstraintWidget.VERTICAL] ==
                  DimensionBehaviour.matchParent)) {
        return true;
      }
    }
    return false;
  }

  /// Whether [widget], linked by its baseline, is not gone and has no
  /// baseline: a baseline distance of 0 after its measure, as a widget
  /// without text measures. ConstraintWidget.addToSolver applies a baseline
  /// link only to a widget with a baseline distance or a gone one
  /// (mBaselineDistance > 0 || GONE), and Direct.verticalSolvingPass places
  /// a widget by its baseline only when it has one (setFinalBaseline), so
  /// Android leaves such a widget where nothing else links it, where the
  /// graph puts its top on the link's target. The solver ignores the link as
  /// Android does. A link to a top or a bottom connects without a baseline,
  /// and one to a baseline only needs both ends to have one when it connects
  /// (ConstraintAnchor.isValidConnection), which the measure that follows
  /// can undo: the Flutter adapter flags both ends of a baseline link before
  /// it connects them.
  static bool _ignoresBaselineLink(ConstraintWidget widget) =>
      widget.getVisibility() != ConstraintWidget.GONE &&
      widget.getBaselineDistance() <= 0;

  /// Whether a widget is anchored to [barrier] across its own axis: along
  /// [orientation], which is not the barrier's. The solver leaves the
  /// barrier unconstrained there, so the graph cannot place such a widget.
  bool _hasDependentsAcross(Barrier barrier, int orientation) {
    if (orientation == ConstraintWidget.HORIZONTAL) {
      return _hasLiveDependents(barrier.mLeft) ||
          _hasLiveDependents(barrier.mRight);
    }
    return _hasLiveDependents(barrier.mTop) ||
        _hasLiveDependents(barrier.mBottom) ||
        _hasLiveDependents(barrier.mBaseline);
  }

  // ---------------------------------------------------------------------
  // Barrier parity (no upstream counterpart).
  //
  // The graph resolves a barrier to the outermost edge of its references
  // plus its margin, and keeps a barrier layout only where Android
  // (upstream at its default OPTIMIZATION_STANDARD) lays it out the same
  // way. Android runs the Direct pass before the solver (DirectResolution):
  // a barrier whose references that pass placed is placed there too, at the
  // graph's position, and Barrier.addToSolver then holds it at that value.
  // Every other barrier is the solver's, which reaches that position only
  // through soft constraints: Barrier.addToSolver bounds the barrier by every
  // reference (a hard inequality), pulls it towards each reference
  // (STRENGTH_HIGHEST, or STRENGTH_EQUALITY when a widget is centered on the
  // barrier and no reference is a match-constraint widget), and pulls it
  // towards one edge of the container (STRENGTH_HIGHEST: the far edge for a
  // left or top barrier, the near edge for a right or bottom one). Widgets
  // centered on the barrier add their own soft range and bounds checks. The
  // solver minimizes the errors of those constraints strength by strength,
  // so a barrier stays at its bound only when moving it off the bound costs
  // more, at the highest strength where the cost and the saving differ, than
  // it saves.
  //
  // _barrierHolds checks exactly that for every barrier the Direct pass
  // leaves to the solver. Moving a barrier carries along everything rigidly
  // attached to it (a widget with a single link along the axis, a widget
  // whose two links both move, a barrier whose outermost reference moves),
  // so the check gathers that group first, then adds up, per strength, how
  // much each soft constraint touching the group changes for a 1px move.
  // Positions are integers, so that difference is the exact slope of each
  // piecewise-linear error. The rest of the layout has to round as Android
  // does too (see the next section). A layout the checks cannot account for
  // goes to the solver.
  // ---------------------------------------------------------------------

  /// Whether Android would place every barrier, and so every widget, where
  /// the graph did. See the section comment above.
  bool _barriersMatchSolver() {
    final container = mWidgetcontainer;
    // The check reads the container's edges, which the graph has not
    // resolved on an axis that wraps without its wrap computation.
    if (!container.mHorizontalRun!.end.resolved ||
        !container.mVerticalRun!.end.resolved ||
        _linksIntoSkippedWidget()) {
      return false;
    }
    final barriers = <Barrier>[];
    final referencedBy = <ConstraintWidget, List<Barrier>>{};
    for (final child in container.mChildren) {
      // The solver reports a position as (int) (value + 0.5), which turns a
      // negative edge one pixel towards zero, and a frame with a negative
      // size as 0, 0, 0, 0. The graph reports both as computed. Barrier
      // layouts went to the solver before this engine resolved them, so they
      // keep doing so here rather than move by a pixel. (A gone widget's
      // position is not meaningful, but a gone barrier's still is.)
      if ((child is Barrier ||
              child.getVisibility() != ConstraintWidget.GONE) &&
          (_hasNegativeGeometry(child.mHorizontalRun!) ||
              _hasNegativeGeometry(child.mVerticalRun!) ||
              _centeredBelowZero(child, true) ||
              _centeredBelowZero(child, false) ||
              _matchSizeDiffers(child, true) ||
              _matchSizeDiffers(child, false) ||
              _hasSoftMatchSize(child, true) ||
              _hasSoftMatchSize(child, false) ||
              _hasMinimumSize(child))) {
        return false;
      }
      if (child is Barrier) {
        barriers.add(child);
        for (var i = 0; i < child.mWidgetsCount; i++) {
          final reference = child.mWidgets[i]!;
          if (!HelperReferences.counts(child, reference)) {
            continue;
          }
          // Barrier.addToSolver adds a reference's own margin when that
          // reference's anchor on the barrier's side targets the barrier.
          // Such a link is a cycle the graph cannot resolve, unless a
          // match-parent axis ignores it, and then only the solver adds the
          // margin.
          final target = reference.mListAnchors[child.getBarrierType()].mTarget;
          final member = _chainMemberMovedWith(
            reference,
            child.getOrientation() == ConstraintWidget.HORIZONTAL,
          );
          if ((target != null && target.mOwner == child) ||
              (member != null && _pullsChain(child, member))) {
            return false;
          }
          (referencedBy[reference] ??= <Barrier>[]).add(child);
        }
      }
    }
    // The Direct pass is only modelled when a check needs it.
    DirectResolution? direct;
    for (final barrier in barriers) {
      if (_barrierHolds(barrier, referencedBy)) {
        continue;
      }
      direct ??= DirectResolution(mWidgetcontainer);
      final horizontal =
          barrier.getOrientation() == ConstraintWidget.HORIZONTAL;
      if (direct.diverged ||
          direct.start(barrier, horizontal) != _barrierPosition(barrier)) {
        return false;
      }
    }
    return _roundsAsAndroid(direct);
  }

  // ---------------------------------------------------------------------
  // Rounding parity with Android (no upstream counterpart).
  //
  // The graph rounds each position as it resolves it. The solver keeps
  // positions exact and rounds each edge once, at the end
  // (LinearSystem.getObjectVariableValue). The two agree wherever a widget
  // reads whole pixels: offset from one target, filling between two, or
  // centered between two. They can disagree where a widget is centered
  // between targets that the solver holds at a fraction, which come from a
  // percent or ratio size, a chain member's edge, an earlier widget centered
  // on a half pixel, or a barrier over one of those. Android lays a layout
  // out with the Direct pass first, which places what it reaches in whole
  // pixels (DirectResolution). Its arithmetic differs from the graph's in
  // two details, a centering offset worked out in Java floats and the
  // truncated offset of a widget that does not fit, which the model
  // reproduces and _directPlacesElsewhere compares. Only the rest goes
  // through Android's solver, so only there do the fraction checks apply. A
  // chain is always there: the Direct pass never places one.
  // ---------------------------------------------------------------------

  // Fraction flags, per child: the start or end of an axis may sit at a
  // fraction of a pixel in Android's solver.
  static const int _startH = 1;
  static const int _endH = 2;
  static const int _startV = 4;
  static const int _endV = 8;

  /// Whether Android rounds every position of this barrier layout as the
  /// graph does, given [direct] when the Direct pass was already modelled.
  /// See the section comment above.
  bool _roundsAsAndroid(DirectResolution? direct) {
    if (!_hasChainsAsSolver()) {
      return false;
    }
    // Most layouts have nothing the solver could round differently, so the
    // Direct pass is only modelled when a first look, which counts every
    // axis as the solver's, finds something.
    if (!_hasRoundingRisk(null)) {
      return true;
    }
    final model = direct ?? DirectResolution(mWidgetcontainer);
    return !model.diverged && !_hasRoundingRisk(model);
  }

  /// Whether every chain lays its members out as the solver does
  /// (Chain.applyChainConstraints). The graph's ChainRun differs from it
  /// when the members do not fit between the chain's ends (the solver then
  /// gives up the end margins and lets a match-constraint member's size go
  /// below 0), and when a member's percent size is not a whole number of
  /// pixels.
  bool _hasChainsAsSolver() {
    for (final run in mRuns) {
      if (run is! ChainRun || run.mWidgets.isEmpty) {
        continue;
      }
      final horizontal = run.orientation == ConstraintWidget.HORIZONTAL;
      // ChainRun lists the members from the left (or top) one, in either
      // direction; the chain's ends are their outer links.
      final firstWidget = run.mWidgets.first.mWidget;
      final lastWidget = run.mWidgets.last.mWidget;
      final first = horizontal ? firstWidget.mLeft : firstWidget.mTop;
      final last = horizontal ? lastWidget.mRight : lastWidget.mBottom;
      if (first.mTarget == null || last.mTarget == null) {
        return false;
      }
      // The members' sizes and every margin of theirs along the axis.
      var size = 0;
      for (final member in run.mWidgets) {
        final widget = member.mWidget;
        if (widget.getVisibility() == ConstraintWidget.GONE) {
          continue;
        }
        // ChainRun spreads a percent size it rounded first; the solver
        // spreads the exact one.
        if (_hasPercentFraction(widget, horizontal)) {
          return false;
        }
        final begin = horizontal ? widget.mLeft : widget.mTop;
        final end = horizontal ? widget.mRight : widget.mBottom;
        size += member.mDimension.value + begin.getMargin() + end.getMargin();
      }
      if (size > _position(last.mTarget!) - _position(first.mTarget!)) {
        return false;
      }
    }
    return true;
  }

  /// Whether some part of the layout that Android leaves to its solver
  /// (every axis, when [direct] is null) can round differently from the
  /// graph, or the Direct pass places a widget or barrier ([direct]) away
  /// from the graph. Works out which axis edges the solver may hold at a
  /// fraction, to a fixed point, and stops at the first place where that
  /// matters.
  bool _hasRoundingRisk(DirectResolution? direct) {
    final fractions = <ConstraintWidget, int>{};
    var changed = true;
    while (changed) {
      changed = false;
      for (final child in mWidgetcontainer.mChildren) {
        final int bits;
        if (child is Guideline) {
          // Direct places every guideline of a container of known size.
          continue;
        } else if (child is Barrier) {
          final horizontal =
              child.getOrientation() == ConstraintWidget.HORIZONTAL;
          if (direct != null &&
              direct.resolves(child, horizontal) &&
              direct.start(child, horizontal) != _barrierPosition(child)) {
            return true;
          }
          bits = _barrierFraction(child, direct, fractions);
        } else {
          final horizontal = _axisFraction(child, true, direct, fractions);
          final vertical = _axisFraction(child, false, direct, fractions);
          if (horizontal < 0 || vertical < 0) {
            return true;
          }
          bits = horizontal | (vertical << 2);
        }
        if (bits != (fractions[child] ?? 0)) {
          fractions[child] = bits;
          changed = true;
        }
      }
    }
    // A chain whose end the solver holds at a fraction lays its members out
    // from there.
    for (final run in mRuns) {
      if (run is! ChainRun || run.mWidgets.isEmpty) {
        continue;
      }
      final horizontal = run.orientation == ConstraintWidget.HORIZONTAL;
      final firstWidget = run.mWidgets.first.mWidget;
      final lastWidget = run.mWidgets.last.mWidget;
      final first = horizontal ? firstWidget.mLeft : firstWidget.mTop;
      final last = horizontal ? lastWidget.mRight : lastWidget.mBottom;
      if ((first.mTarget != null && _isFraction(first.mTarget!, fractions)) ||
          (last.mTarget != null && _isFraction(last.mTarget!, fractions))) {
        return true;
      }
    }
    return false;
  }

  /// Whether the solver may hold [anchor] at a fraction of a pixel.
  bool _isFraction(
    ConstraintAnchor anchor,
    Map<ConstraintWidget, int> fractions,
  ) {
    final owner = anchor.mOwner;
    if (identical(owner, mWidgetcontainer) || owner is Guideline) {
      return false;
    }
    final bits = fractions[owner] ?? 0;
    return switch (anchor.mType) {
      ConstraintAnchorType.left => bits & _startH != 0,
      ConstraintAnchorType.right => bits & _endH != 0,
      ConstraintAnchorType.top ||
      ConstraintAnchorType.baseline => bits & _startV != 0,
      ConstraintAnchorType.bottom => bits & _endV != 0,
      _ => false,
    };
  }

  /// The fraction flags of [barrier]: those of the outermost edges it
  /// follows, unless the Direct pass places it.
  int _barrierFraction(
    Barrier barrier,
    DirectResolution? direct,
    Map<ConstraintWidget, int> fractions,
  ) {
    final horizontal = barrier.getOrientation() == ConstraintWidget.HORIZONTAL;
    if (direct != null && direct.resolves(barrier, horizontal)) {
      return 0;
    }
    for (var i = 0; i < barrier.mWidgetsCount; i++) {
      final reference = barrier.mWidgets[i]!;
      if (HelperReferences.counts(barrier, reference) &&
          _isFraction(
            reference.mListAnchors[barrier.getBarrierType()],
            fractions,
          )) {
        return horizontal ? _startH | _endH : _startV | _endV;
      }
    }
    return 0;
  }

  /// The fraction flags of [widget] along [horizontal] or the vertical axis
  /// (1 for its start, 2 for its end), or -1 where Android can place the
  /// widget differently from the graph. An axis the Direct pass resolves
  /// ([direct]) holds no fraction, and only the Direct cases below apply to
  /// it. Elsewhere, -1 stands for:
  /// - a ratio size the graph rounds and Android truncates (_ratioDiffers),
  ///   wherever the widget is placed;
  /// - a widget centered between two links that reads a fraction, or whose
  ///   own percent size rounds differently there (or whose ratio on both
  ///   match-constraint axes leaves a size this check does not work out);
  /// - a percent or ratio size with a fraction offset from a fraction, or
  ///   linked only at its end, which the solver rounds from there;
  /// - a widget centered with a negative margin, which the solver leaves
  ///   out of its centering (ArrayRow.createRowCentering);
  /// - a match-parent axis that is gone or linked to a gone widget;
  /// - a baseline link to a gone widget with a baseline distance, whose
  ///   baseline Android's solver puts on its top (_readsGoneBaseline);
  /// - a gone widget whose vertical links cross on a half pixel, until the
  ///   Direct pass is modelled (see _directFloorsCrossed).
  /// - a centering with a bias other than 0, 0.5 and 1 on a half pixel or
  ///   with a negative slack, until the Direct pass is modelled
  ///   (_directMayDiffer).
  /// With [direct], an axis it resolves is -1 only for _directCentersOnPoint,
  /// _directFloorsCrossed and _directPlacesElsewhere.
  int _axisFraction(
    ConstraintWidget widget,
    bool horizontal,
    DirectResolution? direct,
    Map<ConstraintWidget, int> fractions,
  ) {
    // Direct measures a ratio size the way the solver sets it, so this holds
    // whichever of them places the widget.
    if (_ratioDiffers(widget, horizontal)) {
      return -1;
    }
    if (direct == null) {
      // Only the Direct pass can tell these apart, so they call for it.
      if (_crossesGoneVertically(widget, horizontal)) {
        return -1;
      }
    } else if (direct.resolves(widget, horizontal)) {
      return _directCentersOnPoint(widget, horizontal, direct) ||
              _directFloorsCrossed(widget, horizontal, direct) ||
              _directPlacesElsewhere(widget, horizontal, direct)
          ? -1
          : 0;
    }
    if (horizontal
        ? widget.isInHorizontalChain()
        : widget.isInVerticalChain()) {
      // Spread gaps and shared sizes split the space in fractions.
      return 3;
    }
    final orientation = horizontal
        ? ConstraintWidget.HORIZONTAL
        : ConstraintWidget.VERTICAL;
    final behaviour = widget.getDimensionBehaviour(orientation);
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    final beginTarget = begin.mTarget;
    final endTarget = end.mTarget;
    if (behaviour == DimensionBehaviour.matchParent) {
      // Optimizer.checkMatchParent puts a match-parent axis against the
      // container with its raw margins, gone or not; the graph collapses a
      // gone one and takes the gone margin of a link to a gone target.
      if (widget.getVisibility() == ConstraintWidget.GONE ||
          (beginTarget != null &&
              beginTarget.mOwner.getVisibility() == ConstraintWidget.GONE) ||
          (endTarget != null &&
              endTarget.mOwner.getVisibility() == ConstraintWidget.GONE)) {
        return -1;
      }
      return 0;
    }
    if (!horizontal && widget.mBaseline.mTarget != null) {
      if (_readsGoneBaseline(widget, direct)) {
        return -1;
      }
      // The solver puts the bottom the exact percent size below the top.
      return (_isFraction(widget.mBaseline.mTarget!, fractions) ? 3 : 0) |
          (_hasPercentFraction(widget, false) ? 2 : 0);
    }
    final percentFraction = _hasPercentFraction(widget, horizontal);
    // With a ratio on both match-constraint axes the solver keeps the exact
    // quotient on the side it derives, which this check does not work out.
    final ratioFraction =
        behaviour == DimensionBehaviour.matchConstraint &&
        widget.getDimensionRatio() > 0 &&
        widget.getVisibility() != ConstraintWidget.GONE &&
        widget.getDimensionBehaviour(1 - orientation) ==
            DimensionBehaviour.matchConstraint;
    if (beginTarget != null && endTarget != null) {
      final beginFraction = _isFraction(beginTarget, fractions);
      final endFraction = _isFraction(endTarget, fractions);
      if (_fills(widget, horizontal)) {
        return (beginFraction ? 1 : 0) | (endFraction ? 2 : 0);
      }
      if (beginFraction ||
          endFraction ||
          ratioFraction ||
          (percentFraction && !_percentRoundsAsGraph(widget, horizontal)) ||
          _percentOverflows(widget, horizontal) ||
          begin.getMargin() < 0 ||
          end.getMargin() < 0) {
        return -1;
      }
      if (direct == null && _directMayDiffer(widget, horizontal)) {
        return -1;
      }
      if (percentFraction) {
        return 3;
      }
      final offset = _centeringOffset(widget, horizontal);
      return (offset - offset.roundToDouble()).abs() > 1e-6 ? 3 : 0;
    }
    if (beginTarget != null) {
      final fraction = _isFraction(beginTarget, fractions);
      if (fraction && (percentFraction || ratioFraction)) {
        // Two fractions add up to an edge the graph rounded from two whole
        // pixels.
        return -1;
      }
      return (fraction ? 1 : 0) |
          (fraction || percentFraction || ratioFraction ? 2 : 0);
    }
    if (endTarget != null) {
      final fraction = _isFraction(endTarget, fractions);
      if (ratioFraction ||
          (percentFraction &&
              (fraction || !_percentRoundsAsGraph(widget, horizontal)))) {
        return -1;
      }
      return fraction || percentFraction ? 3 : 0;
    }
    return percentFraction || ratioFraction ? 2 : 0;
  }

  /// Whether [widget], whose vertical axis Android leaves to its solver
  /// (every axis, when [direct] is null), is linked by its baseline to a
  /// gone widget with a baseline distance. ConstraintWidget.addToSolver puts
  /// a gone widget's baseline on its top (addEquality(baseline, top,
  /// mBaseline.getMargin()), its distance left out), where the graph adds
  /// the distance (VerticalWidgetRun). Android keeps the distance only when
  /// Direct placed the gone widget and its baseline still lists this link
  /// (setFinalVertical, then addToSolver's mBaseline.hasDependents()); with
  /// a stale link that equality is left out and the baseline is free.
  static bool _readsGoneBaseline(
    ConstraintWidget widget,
    DirectResolution? direct,
  ) {
    final target = widget.mBaseline.mTarget!;
    final owner = target.mOwner;
    if (owner.getVisibility() != ConstraintWidget.GONE ||
        owner.getBaselineDistance() == 0) {
      return false;
    }
    return direct == null ||
        !direct.resolves(owner, false) ||
        !(target.mDependents?.contains(widget.mBaseline) ?? false);
  }

  /// Whether the Direct pass, should it place [widget] along [horizontal]
  /// or the vertical axis, can put it elsewhere than the graph, which only
  /// the model tells (_directPlacesElsewhere). Both center it at
  /// bias x slack, but Direct works in Java floats, (int) (0.5f + bias *
  /// distance), and truncates the offset towards zero when the widget does
  /// not fit, (int) (bias * distance), where the graph rounds
  /// 0.5 + start + slack x bias in doubles (WidgetRun.updateRunCenter). The
  /// two agree for a bias of 0, 0.5 or 1, and otherwise part on a half pixel
  /// (0.7f * 45 is 31.5, 0.7 * 45 is 31.499999999999996) and for a negative
  /// slack (bias 0.4 of -54 is -21.6: Direct -21, the graph -22).
  static bool _directMayDiffer(ConstraintWidget widget, bool horizontal) {
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    final bias = horizontal
        ? widget.getHorizontalBiasPercent()
        : widget.getVerticalBiasPercent();
    if (begin.mTarget == end.mTarget || bias == 0 || bias == 0.5 || bias == 1) {
      return false;
    }
    final offset = _centeringOffset(widget, horizontal);
    return offset < 0 || ((offset - offset.floorToDouble()) - 0.5).abs() < 1e-6;
  }

  /// Whether the Direct pass, which places [widget] along [horizontal] or the
  /// vertical axis, puts it elsewhere than the graph (see _directMayDiffer).
  /// The model works Direct out in Java floats and truncates as Direct does.
  /// A gone widget counts only when something places itself from it: it
  /// does not show, and Direct gives one it places by its baseline its raw
  /// height (setFinalBaseline).
  bool _directPlacesElsewhere(
    ConstraintWidget widget,
    bool horizontal,
    DirectResolution direct,
  ) {
    final run = horizontal ? widget.mHorizontalRun! : widget.mVerticalRun!;
    if (widget.getVisibility() == ConstraintWidget.GONE) {
      return direct.start(widget, horizontal) != run.start.value &&
          _isRead(widget, horizontal);
    }
    return direct.start(widget, horizontal) != run.start.value ||
        direct.end(widget, horizontal) != run.end.value;
  }

  /// Whether the Direct pass centers [widget], linked along [horizontal] or
  /// the vertical axis to two anchors it put at the same position, on that
  /// position while the graph does not, and the solver agrees with Direct.
  /// Direct.solveHorizontalCenterConstraints (and its vertical twin) compare
  /// the two target values and, when they are equal, drop the margins and
  /// center at 0.5. The graph only does that when both links share one
  /// anchor. The solver drops a negative margin from its centering, so with
  /// one it lands where Direct does and the graph does not.
  static bool _directCentersOnPoint(
    ConstraintWidget widget,
    bool horizontal,
    DirectResolution direct,
  ) {
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    final beginTarget = begin.mTarget;
    final endTarget = end.mTarget;
    if (beginTarget == null ||
        endTarget == null ||
        identical(beginTarget, endTarget) ||
        (begin.getMargin() >= 0 && end.getMargin() >= 0)) {
      return false;
    }
    final a = direct.valueOf(beginTarget);
    return a != null && a == direct.valueOf(endTarget);
  }

  /// Whether a gone [widget]'s vertical links cross, by the graph's
  /// positions, with a centering offset on a half pixel, which is where
  /// Direct and the graph can part (see _directFloorsCrossed).
  bool _crossesGoneVertically(ConstraintWidget widget, bool horizontal) {
    if (horizontal ||
        widget.getVisibility() != ConstraintWidget.GONE ||
        widget.mTop.mTarget == null ||
        widget.mBottom.mTarget == null) {
      return false;
    }
    final start = _position(widget.mTop.mTarget!);
    final end = _position(widget.mBottom.mTarget!);
    final offset = (start - end) * widget.getVerticalBiasPercent();
    return start > end &&
        (offset - offset.floorToDouble() - 0.5).abs() < 1e-6 &&
        _isRead(widget, false);
  }

  /// Whether the Direct pass puts a gone [widget] whose vertical links cross
  /// (its top target below its bottom target) elsewhere than the graph,
  /// which only happens on a half pixel.
  /// Direct.solveVerticalCenterConstraints subtracts the rounded offset from
  /// the top target there, which rounds a half pixel up the screen, while the
  /// graph rounds it down; the solver keeps the half pixel exact, so widgets
  /// centered against the gone one round as Android does. A visible widget
  /// whose links cross gets a frame of negative height from Direct (which
  /// Android zeroes) and from neither of the others, and the horizontal twin
  /// adds the offset instead, so those are left as they are.
  bool _directFloorsCrossed(
    ConstraintWidget widget,
    bool horizontal,
    DirectResolution direct,
  ) {
    if (horizontal || widget.getVisibility() != ConstraintWidget.GONE) {
      return false;
    }
    final top = widget.mTop.mTarget;
    final bottom = widget.mBottom.mTarget;
    if (top == null || bottom == null) {
      return false;
    }
    final start = direct.valueOf(top);
    final end = direct.valueOf(bottom);
    return start != null &&
        end != null &&
        start > end &&
        direct.start(widget, false) != widget.mVerticalRun!.start.value &&
        _isRead(widget, false);
  }

  /// Whether something places itself from [widget] along [horizontal] or the
  /// vertical axis: a child linked to it, or a barrier that counts it.
  bool _isRead(ConstraintWidget widget, bool horizontal) {
    for (final anchor in _axisAnchors(widget, horizontal)) {
      if (_hasLiveDependents(anchor)) {
        return true;
      }
    }
    for (final child in mWidgetcontainer.mChildren) {
      if (child is Barrier &&
          (child.getOrientation() == ConstraintWidget.HORIZONTAL) ==
              horizontal) {
        for (var i = 0; i < child.mWidgetsCount; i++) {
          if (identical(child.mWidgets[i], widget) &&
              HelperReferences.counts(child, widget)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Whether [widget]'s ratio sizes its axis along [horizontal] or the
  /// vertical axis differently on the graph than in Android, when the other
  /// axis is not match-constraint: ConstraintWidget.addToSolver (and
  /// ConstraintWidgetContainer.measure, for the Direct pass) truncate the
  /// ratio size, (int) (ratio * other), where the graph rounds it. A
  /// percent axis with a ratio is sized by the percent there, and by the
  /// ratio on the graph.
  static bool _ratioDiffers(ConstraintWidget widget, bool horizontal) {
    final orientation = horizontal
        ? ConstraintWidget.HORIZONTAL
        : ConstraintWidget.VERTICAL;
    if (widget.getDimensionRatio() <= 0 ||
        widget.getVisibility() == ConstraintWidget.GONE ||
        widget.getDimensionBehaviour(orientation) !=
            DimensionBehaviour.matchConstraint) {
      return false;
    }
    final style = horizontal
        ? widget.mMatchConstraintDefaultWidth
        : widget.mMatchConstraintDefaultHeight;
    final percent = horizontal
        ? widget.mMatchConstraintPercentWidth
        : widget.mMatchConstraintPercentHeight;
    // The graph pass may already have turned the percent style into a
    // ratio; the fraction it was set with (setHorizontalMatchStyle turns a
    // spread with one into a percent) still tells.
    if (style == ConstraintWidget.MATCH_CONSTRAINT_PERCENT ||
        (percent > 0 && percent < 1)) {
      return true;
    }
    // The graph pass may already have turned the spread style into a ratio.
    if ((style != ConstraintWidget.MATCH_CONSTRAINT_SPREAD &&
            style != ConstraintWidget.MATCH_CONSTRAINT_RATIO &&
            style != ConstraintWidget.MATCH_CONSTRAINT_RATIO_RESOLVED) ||
        widget.getDimensionBehaviour(1 - orientation) ==
            DimensionBehaviour.matchConstraint) {
      return false;
    }
    final other = horizontal
        ? widget.mVerticalRun!.mDimension.value
        : widget.mHorizontalRun!.mDimension.value;
    // Java's float arithmetic: (int) (ratio * other), or (int) (other /
    // ratio) for a height whose ratio names no side.
    _float[0] = widget.getDimensionRatio();
    final ratio = _float[0];
    _float[0] =
        !horizontal &&
            widget.getDimensionRatioSide() == ConstraintWidget.UNKNOWN
        ? other / ratio
        : ratio * other;
    final size = _float[0].truncate();
    final run = horizontal ? widget.mHorizontalRun! : widget.mVerticalRun!;
    return run.mDimension.value != size;
  }

  static final Float32List _float = Float32List(1);

  /// Whether [widget] has a percent size along [horizontal] or the vertical
  /// axis that is not a whole number of pixels: the solver keeps
  /// percent x the container's size, where the graph rounds it.
  bool _hasPercentFraction(ConstraintWidget widget, bool horizontal) {
    if (widget.getVisibility() == ConstraintWidget.GONE ||
        widget.getDimensionBehaviour(
              horizontal
                  ? ConstraintWidget.HORIZONTAL
                  : ConstraintWidget.VERTICAL,
            ) !=
            DimensionBehaviour.matchConstraint ||
        (horizontal
                ? widget.mMatchConstraintDefaultWidth
                : widget.mMatchConstraintDefaultHeight) !=
            ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
      return false;
    }
    final percent = horizontal
        ? widget.mMatchConstraintPercentWidth
        : widget.mMatchConstraintPercentHeight;
    final size =
        percent *
        (horizontal
            ? mWidgetcontainer.getWidth()
            : mWidgetcontainer.getHeight());
    return (size - size.roundToDouble()).abs() > 1e-6;
  }

  /// Whether [widget], centered between two links along [horizontal] or the
  /// vertical axis, has a percent size wider than the space between them
  /// that the solver squeezes into it. The percent row
  /// (ArrayRow.createRowDimensionRatio), the max (addLowerThan) and the
  /// range checks cannot all hold then, and with a max at or below the
  /// percent size and no min the solver gives up the percent size and keeps
  /// the widget between its targets, where the graph lets it overflow both.
  /// With no max, a larger one, or a min, it overflows as the graph does.
  bool _percentOverflows(ConstraintWidget widget, bool horizontal) {
    if (widget.getVisibility() == ConstraintWidget.GONE ||
        widget.getDimensionBehaviour(
              horizontal
                  ? ConstraintWidget.HORIZONTAL
                  : ConstraintWidget.VERTICAL,
            ) !=
            DimensionBehaviour.matchConstraint ||
        (horizontal
                ? widget.mMatchConstraintDefaultWidth
                : widget.mMatchConstraintDefaultHeight) !=
            ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
      return false;
    }
    final min = horizontal
        ? widget.mMatchConstraintMinWidth
        : widget.mMatchConstraintMinHeight;
    final max = horizontal
        ? widget.mMatchConstraintMaxWidth
        : widget.mMatchConstraintMaxHeight;
    final size =
        (horizontal
            ? widget.mMatchConstraintPercentWidth
            : widget.mMatchConstraintPercentHeight) *
        (horizontal
            ? mWidgetcontainer.getWidth()
            : mWidgetcontainer.getHeight());
    if (min > 0 || max <= 0 || max >= size + 1) {
      return false;
    }
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    final space = begin.mTarget == end.mTarget
        ? 0
        : _position(end.mTarget!) -
              end.getMargin() -
              _position(begin.mTarget!) -
              begin.getMargin();
    final run = horizontal ? widget.mHorizontalRun! : widget.mVerticalRun!;
    return run.mDimension.value > space;
  }

  /// Whether the solver rounds [widget]'s edges along [horizontal] or the
  /// vertical axis where the graph put them, given that the widget has a
  /// percent size with a fraction and reads whole pixels. The solver keeps
  /// the exact size, centers it or offsets it from its end link, and rounds
  /// each edge; the graph rounds the size first.
  bool _percentRoundsAsGraph(ConstraintWidget widget, bool horizontal) {
    final run = horizontal ? widget.mHorizontalRun! : widget.mVerticalRun!;
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    final size =
        (horizontal
            ? widget.mMatchConstraintPercentWidth
            : widget.mMatchConstraintPercentHeight) *
        (horizontal
            ? mWidgetcontainer.getWidth()
            : mWidgetcontainer.getHeight());
    final double start;
    if (begin.mTarget != null) {
      var s1 = _position(begin.mTarget!) + begin.getMargin();
      var s2 = _position(end.mTarget!) - end.getMargin();
      var bias = horizontal
          ? widget.getHorizontalBiasPercent()
          : widget.getVerticalBiasPercent();
      if (begin.mTarget == end.mTarget) {
        s1 = _position(begin.mTarget!);
        s2 = s1;
        bias = 0.5;
      }
      start = s1 + (s2 - s1 - size) * bias;
    } else {
      start = _position(end.mTarget!) - end.getMargin() - size;
    }
    // LinearSystem.getObjectVariableValue's (int) (value + 0.5); negative
    // positions are left to the solver already.
    return (start + 0.5).floor() == run.start.value &&
        (start + size + 0.5).floor() == run.end.value;
  }

  /// Whether [widget]'s match-constraint spread axis fills the space between
  /// its two links with no min or max, which puts its edges on its targets.
  /// With a min or a max the solver centers it instead (with range and
  /// bounds checks, and without a negative margin), even where it fills.
  static bool _fills(ConstraintWidget widget, bool horizontal) {
    final orientation = horizontal
        ? ConstraintWidget.HORIZONTAL
        : ConstraintWidget.VERTICAL;
    if (widget.getVisibility() == ConstraintWidget.GONE ||
        widget.getDimensionBehaviour(orientation) !=
            DimensionBehaviour.matchConstraint ||
        widget.getDimensionRatio() > 0 ||
        (horizontal
                ? widget.mMatchConstraintDefaultWidth
                : widget.mMatchConstraintDefaultHeight) !=
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
      return false;
    }
    if ((horizontal
            ? widget.mMatchConstraintMinWidth + widget.mMatchConstraintMaxWidth
            : widget.mMatchConstraintMinHeight +
                  widget.mMatchConstraintMaxHeight) >
        0) {
      return false;
    }
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    if (begin.mTarget == end.mTarget) {
      return false;
    }
    final space =
        _position(end.mTarget!) -
        end.getMargin() -
        _position(begin.mTarget!) -
        begin.getMargin();
    final run = horizontal ? widget.mHorizontalRun! : widget.mVerticalRun!;
    return run.mDimension.value == space;
  }

  /// The exact offset of [widget]'s start from its begin target (plus
  /// margin) when centered between its two links, as the solver computes it
  /// from the graph's whole-pixel targets.
  static double _centeringOffset(ConstraintWidget widget, bool horizontal) {
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    var s1 = _position(begin.mTarget!) + begin.getMargin();
    var s2 = _position(end.mTarget!) - end.getMargin();
    var bias = horizontal
        ? widget.getHorizontalBiasPercent()
        : widget.getVerticalBiasPercent();
    if (begin.mTarget == end.mTarget) {
      s1 = _position(begin.mTarget!);
      s2 = s1;
      bias = 0.5;
    }
    final size = widget.getVisibility() == ConstraintWidget.GONE
        ? 0
        : (horizontal ? widget.mHorizontalRun! : widget.mVerticalRun!)
              .mDimension
              .value;
    return (s2 - s1 - size) * bias;
  }

  /// The chain member along [horizontal] (the barrier's axis) that
  /// [reference] moves with: the reference itself when it is one, else the
  /// first one its links along that axis lead to, through other widgets and
  /// through the references of a barrier, never through the container or a
  /// guideline. A barrier's pull on the reference reaches that member
  /// through the links (a single link, a fill and a centering all hold at
  /// strengths above the pull), so the member gives way as if the barrier
  /// referenced it: a tab indicator under a chained tab, linked to it, pulls
  /// the chain with it. Null when no chain member moves the reference.
  ConstraintWidget? _chainMemberMovedWith(
    ConstraintWidget reference,
    bool horizontal,
  ) {
    final seen = <ConstraintWidget>{};
    final pending = <ConstraintWidget>[reference];
    while (pending.isNotEmpty) {
      final widget = pending.removeLast();
      if (!seen.add(widget) ||
          identical(widget, mWidgetcontainer) ||
          widget is Guideline) {
        continue;
      }
      if (horizontal
          ? widget.isInHorizontalChain()
          : widget.isInVerticalChain()) {
        return widget;
      }
      if (widget is Barrier) {
        for (var i = 0; i < widget.mWidgetsCount; i++) {
          final inner = widget.mWidgets[i]!;
          if (HelperReferences.counts(widget, inner)) {
            pending.add(inner);
          }
        }
        continue;
      }
      for (final anchor in _axisAnchors(widget, horizontal)) {
        final target = anchor.mTarget;
        if (target != null) {
          pending.add(target.mOwner);
        }
      }
    }
    return null;
  }

  /// Whether [barrier]'s soft pulls can move [reference], a member of a
  /// chain along the barrier's axis, which the graph keeps where the chain
  /// put it. Chain.applyChainConstraints glues a packed chain (or a single
  /// visible member) at STRENGTH_CENTERING, and keeps a spread chain's gaps
  /// equal at STRENGTH_EQUALITY and a spread-inside chain's at
  /// STRENGTH_HIGHEST, which is also the strength of the barrier's pulls
  /// (STRENGTH_EQUALITY with centered dependents, see _referenceStrength).
  /// A match-constraint member's size gives way to them in every style.
  bool _pullsChain(Barrier barrier, ConstraintWidget reference) {
    final horizontal = barrier.getOrientation() == ConstraintWidget.HORIZONTAL;
    if (horizontal
        ? !reference.isInHorizontalChain()
        : !reference.isInVerticalChain()) {
      return false;
    }
    final run = horizontal
        ? reference.horizontalChainRun
        : reference.verticalChainRun;
    if (run == null) {
      return true;
    }
    var visible = 0;
    for (final member in run.mWidgets) {
      final widget = member.mWidget;
      if (widget.getVisibility() == ConstraintWidget.GONE) {
        continue;
      }
      visible++;
      if (widget.getDimensionBehaviour(run.orientation) ==
          DimensionBehaviour.matchConstraint) {
        return true;
      }
    }
    final style = horizontal
        ? run.mWidget.getHorizontalChainStyle()
        : run.mWidget.getVerticalChainStyle();
    if (visible <= 1 || style == ConstraintWidget.CHAIN_PACKED) {
      return false;
    }
    if (style == ConstraintWidget.CHAIN_SPREAD) {
      return _referenceStrength(barrier) >= SolverVariable.STRENGTH_EQUALITY;
    }
    return true;
  }

  /// Whether [chain] placed [member] where its widget will report it. The
  /// graph measures a widget once its sizes are resolved (measureWidgets
  /// runs a fixed number of times), and ChainRun.update places its members
  /// only once every member's size is known; a size that resolves later
  /// leaves the widget at its earlier measure, or a chain's members unplaced,
  /// while every run counts as resolved. updateFromRuns only sizes a chain
  /// member from its edges when ChainRun marked its run resolved (the
  /// spread-inside branch does); any other member keeps its measured size.
  /// directMeasure checks a widget outside a chain for the same stale size.
  /// Upstream's graph has the same gaps, which its solver-first entry never
  /// reports; directMeasure declines such a layout, for the solver.
  static bool _placesMember(ChainRun chain, WidgetRun member) {
    if (!member.start.resolved || !member.end.resolved) {
      return false;
    }
    final widget = member.mWidget;
    if (member.isResolved() ||
        widget.getVisibility() == ConstraintWidget.GONE) {
      return true;
    }
    final span = member.end.value - member.start.value;
    final size = chain.orientation == ConstraintWidget.HORIZONTAL
        ? widget.getWidth()
        : widget.getHeight();
    // A fixed size that the chain's rounded edges leave a pixel short (a
    // member at a negative position, which the solver rounds towards zero)
    // is reported in full, as ConstraintWidget.setFrame reports it on
    // Android.
    return span == size ||
        (span < size &&
            widget.getDimensionBehaviour(chain.orientation) ==
                DimensionBehaviour.fixed);
  }

  /// Whether a child links to a gone widget that the solver leaves out.
  /// ConstraintWidget.addToSolver skips a gone widget that no anchor depends
  /// on and no barrier counts, and an anchor forgets what depends on it when
  /// it is reset (ConstraintAnchor.reset), so a link made before that reads
  /// a variable nothing places. The graph places the gone widget all the
  /// same.
  bool _linksIntoSkippedWidget() {
    var hasCandidate = false;
    for (final child in mWidgetcontainer.mChildren) {
      if (child.getVisibility() == ConstraintWidget.GONE &&
          !child.hasDependencies()) {
        hasCandidate = true;
        break;
      }
    }
    if (!hasCandidate) {
      return false;
    }
    for (final child in mWidgetcontainer.mChildren) {
      for (final anchor in child.mAnchors) {
        final owner = anchor.mTarget?.mOwner;
        if (owner == null ||
            identical(owner, mWidgetcontainer) ||
            owner.getVisibility() != ConstraintWidget.GONE ||
            owner.hasDependencies()) {
          continue;
        }
        var counted = false;
        for (final other in mWidgetcontainer.mChildren) {
          if (other is! Barrier) {
            continue;
          }
          for (var i = 0; i < other.mWidgetsCount; i++) {
            if (identical(other.mWidgets[i], owner) &&
                HelperReferences.counts(other, owner)) {
              counted = true;
            }
          }
        }
        if (!counted) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _hasNegativeGeometry(WidgetRun run) {
    if ((run.start.resolved && run.start.value < 0) ||
        (run.end.resolved && run.end.value < 0)) {
      return true;
    }
    return run.start.resolved &&
        run.end.resolved &&
        run.end.value < run.start.value;
  }

  /// Whether the graph centered [widget] on an axis ([horizontal] or
  /// vertical) between its two links at an unrounded position below -0.5.
  /// Its run rounds the start as (int) (0.5 + position), which truncates
  /// towards zero, so a position in (-1.5, -0.5) resolves to 0 and passes
  /// _hasNegativeGeometry. The solver keeps the unrounded position for
  /// whatever depends on the widget, which then lands a pixel away (and a
  /// size that is not fixed is reported a pixel smaller). This mirrors the
  /// centering in HorizontalWidgetRun.update, VerticalWidgetRun.update and
  /// WidgetRun.updateRunCenter.
  static bool _centeredBelowZero(ConstraintWidget widget, bool horizontal) {
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    if (begin.mTarget == null ||
        end.mTarget == null ||
        (horizontal
            ? widget.isInHorizontalChain()
            : widget.isInVerticalChain())) {
      return false;
    }
    final run = horizontal ? widget.mHorizontalRun! : widget.mVerticalRun!;
    final startTarget = run.getTarget(begin);
    final endTarget = run.getTarget(end);
    if (!run.mDimension.resolved ||
        startTarget == null ||
        endTarget == null ||
        !startTarget.resolved ||
        !endTarget.resolved) {
      return false;
    }
    var startPos = startTarget.value + begin.getMargin();
    var endPos = endTarget.value - end.getMargin();
    var bias = horizontal
        ? widget.getHorizontalBiasPercent()
        : widget.getVerticalBiasPercent();
    if (startTarget == endTarget) {
      startPos = startTarget.value;
      endPos = endTarget.value;
      bias = 0.5;
    }
    final distance = endPos - startPos - run.mDimension.value;
    return startPos + distance * bias < -0.5;
  }

  /// Whether the solver can give [widget]'s match-constraint axis
  /// ([horizontal] or vertical) a size the graph does not model:
  /// - a spread with a min or a max whose two links target one anchor:
  ///   _applyConstraints drops its range and bounds checks there, and
  ///   createRowCentering ignores the margins, so the size is free between
  ///   the min and the max and soft pulls (a barrier's reference equality
  ///   among them) choose it, where the graph clamps the space between the
  ///   links;
  /// - a spread with a min or a max, or a spread linked to a barrier, that
  ///   other widgets are linked to: its bounds checks are soft
  ///   (STRENGTH_EQUALITY, or STRENGTH_HIGHEST with a min or max against a
  ///   barrier), so a widget linked to it that overflows its own space can
  ///   make the solver resize it, even to a negative size;
  /// - a percent size outside its min or max: the solver's percent row and
  ///   the bound are both hard and conflict, where the graph clamps (see the
  ///   percent note in README.md).
  bool _hasSoftMatchSize(ConstraintWidget widget, bool horizontal) {
    final orientation = horizontal
        ? ConstraintWidget.HORIZONTAL
        : ConstraintWidget.VERTICAL;
    if (widget.getDimensionBehaviour(orientation) !=
        DimensionBehaviour.matchConstraint) {
      return false;
    }
    final min = horizontal
        ? widget.mMatchConstraintMinWidth
        : widget.mMatchConstraintMinHeight;
    final max = horizontal
        ? widget.mMatchConstraintMaxWidth
        : widget.mMatchConstraintMaxHeight;
    final bounded = min > 0 || max > 0;
    final style = horizontal
        ? widget.mMatchConstraintDefaultWidth
        : widget.mMatchConstraintDefaultHeight;
    if (style == ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
      if (!bounded) {
        return false;
      }
      final parentRun = horizontal
          ? mWidgetcontainer.mHorizontalRun!
          : mWidgetcontainer.mVerticalRun!;
      if (!parentRun.mDimension.resolved) {
        return true;
      }
      final percent = horizontal
          ? widget.mMatchConstraintPercentWidth
          : widget.mMatchConstraintPercentHeight;
      final size = (0.5 + parentRun.mDimension.value * percent).toInt();
      return (min > 0 && size < min) || (max > 0 && size > max);
    }
    if (style != ConstraintWidget.MATCH_CONSTRAINT_SPREAD ||
        widget.getDimensionRatio() > 0) {
      return false;
    }
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    if (begin.mTarget == null || end.mTarget == null) {
      return false;
    }
    if (bounded && begin.mTarget == end.mTarget) {
      return true;
    }
    if (!bounded &&
        begin.mTarget!.mOwner is! Barrier &&
        end.mTarget!.mOwner is! Barrier) {
      // A plain fill keeps its edges on its targets at STRENGTH_FIXED.
      return false;
    }
    for (final anchor in _axisAnchors(widget, horizontal)) {
      if (_hasLiveDependents(anchor)) {
        return true;
      }
    }
    return false;
  }

  /// Whether [widget] has a minimum size set by setMinWidth or setMinHeight
  /// (not a match-constraint min). The graph applies it last, when it
  /// measures the widget (setWidth, setHeight), even over a match-constraint
  /// max, where the solver caps the size at that max. And where the solver
  /// leaves the size below the minimum (a match-constraint size, or the
  /// inverted frame Direct gives a widget whose links cross), setFrame
  /// raises it and records an override, and Android solves the layout again
  /// without the Direct pass's positions, which ConstraintWidget.addToSolver
  /// has spent, so the graph's integer positions need not be Android's.
  static bool _hasMinimumSize(ConstraintWidget widget) =>
      widget.getMinWidth() > 0 || widget.getMinHeight() > 0;

  /// Whether the graph sized [widget]'s match-constraint axis ([horizontal]
  /// or vertical), linked on both sides, differently from the solver. The
  /// solver fills the space between the links, clamped by the
  /// match-constraint minimum and maximum, and lets a negative space give a
  /// negative size (and so a zeroed frame). The graph's
  /// WidgetRun.getLimitedDimension stops at 0, and bounds that conflict (a
  /// minimum above the maximum) are left to the solver.
  static bool _matchSizeDiffers(ConstraintWidget widget, bool horizontal) {
    final orientation = horizontal
        ? ConstraintWidget.HORIZONTAL
        : ConstraintWidget.VERTICAL;
    if (widget.getDimensionBehaviour(orientation) !=
            DimensionBehaviour.matchConstraint ||
        widget.getDimensionRatio() > 0 ||
        (horizontal
                ? widget.mMatchConstraintDefaultWidth
                : widget.mMatchConstraintDefaultHeight) !=
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD ||
        (horizontal
            ? widget.isInHorizontalChain()
            : widget.isInVerticalChain())) {
      return false;
    }
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    if (begin.mTarget == null || end.mTarget == null) {
      return false;
    }
    final space =
        _position(end.mTarget!) -
        end.getMargin() -
        _position(begin.mTarget!) -
        begin.getMargin();
    final min = horizontal
        ? widget.mMatchConstraintMinWidth
        : widget.mMatchConstraintMinHeight;
    final max = horizontal
        ? widget.mMatchConstraintMaxWidth
        : widget.mMatchConstraintMaxHeight;
    if (max > 0 && min > max) {
      return true;
    }
    // _applyConstraints only bounds the size when the bound is positive.
    var size = space;
    if (min > 0 && size < min) {
      size = min;
    }
    if (max > 0 && size > max) {
      size = max;
    }
    final run = horizontal ? widget.mHorizontalRun! : widget.mVerticalRun!;
    return size < 0 || run.mDimension.value != size;
  }

  /// The position the graph gave [anchor] along its axis.
  static int _position(ConstraintAnchor anchor) {
    final owner = anchor.mOwner;
    switch (anchor.mType) {
      case ConstraintAnchorType.left:
        return owner.mHorizontalRun!.start.value;
      case ConstraintAnchorType.right:
        return owner.mHorizontalRun!.end.value;
      case ConstraintAnchorType.top:
        return owner.mVerticalRun!.start.value;
      case ConstraintAnchorType.bottom:
        return owner.mVerticalRun!.end.value;
      case ConstraintAnchorType.baseline:
        return owner.mVerticalRun!.baseline.value;
      default:
        return 0;
    }
  }

  /// The anchors of [widget] along the axis ([horizontal] or vertical) that
  /// other widgets can be linked to.
  static List<ConstraintAnchor> _axisAnchors(
    ConstraintWidget widget,
    bool horizontal,
  ) => horizontal
      ? [widget.mLeft, widget.mRight]
      : [widget.mTop, widget.mBottom, widget.mBaseline];

  /// The barrier's position along its axis.
  static int _barrierPosition(Barrier barrier) =>
      barrier.getOrientation() == ConstraintWidget.HORIZONTAL
      ? barrier.mHorizontalRun!.start.value
      : barrier.mVerticalRun!.start.value;

  /// The position Barrier.addToSolver binds [barrier] to for [reference]:
  /// the reference's anchor on the barrier's side (its mListAnchors entry,
  /// as upstream reads it) plus the barrier's margin.
  static int _referenceTarget(Barrier barrier, ConstraintWidget reference) =>
      _position(reference.mListAnchors[barrier.getBarrierType()]) +
      barrier.getMargin();

  /// The strength of the reference equalities Barrier.addToSolver writes for
  /// [barrier]: STRENGTH_EQUALITY when a widget is centered on the barrier
  /// and no reference is a match-constraint widget linked on both sides,
  /// STRENGTH_HIGHEST otherwise.
  static int _referenceStrength(Barrier barrier) {
    final type = barrier.getBarrierType();
    final horizontal = type == Barrier.left || type == Barrier.right;
    var hasMatchConstraintWidgets = false;
    for (var i = 0; i < barrier.mWidgetsCount; i++) {
      final widget = barrier.mWidgets[i]!;
      if (!HelperReferences.counts(barrier, widget)) {
        continue;
      }
      if (horizontal &&
          widget.getHorizontalDimensionBehaviour() ==
              DimensionBehaviour.matchConstraint &&
          widget.mLeft.mTarget != null &&
          widget.mRight.mTarget != null) {
        hasMatchConstraintWidgets = true;
        break;
      } else if (!horizontal &&
          widget.getVerticalDimensionBehaviour() ==
              DimensionBehaviour.matchConstraint &&
          widget.mTop.mTarget != null &&
          widget.mBottom.mTarget != null) {
        hasMatchConstraintWidgets = true;
        break;
      }
    }
    final hasCenteredDependents = horizontal
        ? barrier.mLeft.hasCenteredDependents() ||
              barrier.mRight.hasCenteredDependents()
        : barrier.mTop.hasCenteredDependents() ||
              barrier.mBottom.hasCenteredDependents();
    return !hasMatchConstraintWidgets && hasCenteredDependents
        ? SolverVariable.STRENGTH_EQUALITY
        : SolverVariable.STRENGTH_HIGHEST;
  }

  /// Adds the change of an error `|position - target|` to [costs] (when it
  /// grows) or [savings] (when it shrinks) at [strength], for a move of
  /// [position] by [move].
  static void _addAbsolute(
    List<int> costs,
    List<int> savings,
    int strength,
    int position,
    int move,
    int target,
  ) => _addChange(
    costs,
    savings,
    strength,
    (position - target).abs(),
    (position + move - target).abs(),
  );

  /// Whether the solver keeps [barrier] at the bound the graph resolved it
  /// to. See the section comment above.
  bool _barrierHolds(
    Barrier barrier,
    Map<ConstraintWidget, List<Barrier>> referencedBy,
  ) {
    final horizontal = barrier.getOrientation() == ConstraintWidget.HORIZONTAL;
    final type = barrier.getBarrierType();
    // A left or top barrier may sit before its references (it is bounded
    // from above), a right or bottom one after them.
    final away = type == Barrier.right || type == Barrier.bottom ? 1 : -1;

    // The group that moves with the barrier.
    final group = <ConstraintWidget>{barrier};
    final pending = <ConstraintWidget>[barrier];
    while (pending.isNotEmpty) {
      final member = pending.removeLast();
      for (final anchor in _axisAnchors(member, horizontal)) {
        final dependents = anchor.mDependents;
        if (dependents == null) {
          continue;
        }
        for (final dependent in dependents) {
          final widget = dependent.mOwner;
          if (dependent.mTarget != anchor ||
              widget.getParent() != mWidgetcontainer ||
              group.contains(widget)) {
            continue;
          }
          if (_movesWithGroup(widget, horizontal, group)) {
            group.add(widget);
            pending.add(widget);
          }
        }
      }
      for (final other in referencedBy[member] ?? const <Barrier>[]) {
        if (!group.contains(other) &&
            other.getOrientation() == barrier.getOrientation() &&
            _followsGroup(other, group, away)) {
          group.add(other);
          pending.add(other);
        }
      }
    }

    // The change of every soft error a 1px move of the group causes, per
    // strength.
    final costs = List<int>.filled(SolverVariable.STRENGTH_FIXED + 1, 0);
    final savings = List<int>.filled(SolverVariable.STRENGTH_FIXED + 1, 0);
    for (final member in group) {
      if (member is Barrier) {
        final position = _barrierPosition(member);
        final strength = _referenceStrength(member);
        for (var i = 0; i < member.mWidgetsCount; i++) {
          final reference = member.mWidgets[i]!;
          if (HelperReferences.counts(member, reference) &&
              !group.contains(reference)) {
            _addAbsolute(
              costs,
              savings,
              strength,
              position,
              away,
              _referenceTarget(member, reference),
            );
          }
        }
        // The pull towards the container's edge.
        final parent = mWidgetcontainer;
        final edge = switch (member.getBarrierType()) {
          Barrier.left => _position(parent.mRight),
          Barrier.top => _position(parent.mBottom),
          Barrier.right => _position(parent.mLeft),
          _ => _position(parent.mTop),
        };
        _addAbsolute(
          costs,
          savings,
          SolverVariable.STRENGTH_HIGHEST,
          position,
          away,
          edge,
        );
      }
      // A member centered between the group and something else (a follower,
      // see _movesWithGroup) moves with the group, but its space changes.
      if (member is! Barrier &&
          !_addCenteredPull(
            member,
            horizontal,
            group,
            away,
            referencedBy,
            costs,
            savings,
          )) {
        return false;
      }
      for (final anchor in _axisAnchors(member, horizontal)) {
        final dependents = anchor.mDependents;
        if (dependents == null) {
          continue;
        }
        for (final dependent in dependents) {
          final widget = dependent.mOwner;
          if (dependent.mTarget != anchor ||
              widget.getParent() != mWidgetcontainer ||
              group.contains(widget)) {
            continue;
          }
          if (!_addCenteredPull(
            widget,
            horizontal,
            group,
            away,
            referencedBy,
            costs,
            savings,
          )) {
            return false;
          }
        }
      }
      for (final other in referencedBy[member] ?? const <Barrier>[]) {
        if (group.contains(other) ||
            other.getOrientation() != barrier.getOrientation()) {
          continue;
        }
        // A barrier outside the group with a reference inside it stays put,
        // so its reference equality grows or shrinks with the move. A
        // reference at that barrier's bound would carry it along in one
        // direction and not the other: left to the solver.
        final position = _barrierPosition(other);
        final target = _referenceTarget(other, member);
        if (target == position) {
          return false;
        }
        _addAbsolute(
          costs,
          savings,
          _referenceStrength(other),
          target,
          away,
          position,
        );
      }
    }

    // The solver keeps the barrier where it is when, at the highest strength
    // where the move costs and saves different amounts, it costs more. A
    // tie at every strength leaves the choice to the solver's pivoting.
    for (
      var strength = SolverVariable.STRENGTH_FIXED;
      strength > 0;
      strength--
    ) {
      final net = costs[strength] - savings[strength];
      if (net > 0) {
        return true;
      }
      if (net < 0) {
        return false;
      }
    }
    return false;
  }

  /// Whether [widget], linked to a member of [group] along the axis, moves
  /// with the group: its only link along the axis is to the group (and its
  /// size does not depend on its position), or both of its links are.
  static bool _movesWithGroup(
    ConstraintWidget widget,
    bool horizontal,
    Set<ConstraintWidget> group,
  ) {
    if (widget is Helper || _hasUnsupportedLinks(widget, horizontal)) {
      return false;
    }
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    final beginInGroup =
        begin.mTarget != null && group.contains(begin.mTarget!.mOwner);
    final endInGroup =
        end.mTarget != null && group.contains(end.mTarget!.mOwner);
    final behaviour = widget.getDimensionBehaviour(
      horizontal ? ConstraintWidget.HORIZONTAL : ConstraintWidget.VERTICAL,
    );
    // A match-parent axis follows the container, not its links
    // (Optimizer.checkMatchParent).
    if (behaviour == DimensionBehaviour.matchParent) {
      return false;
    }
    if (begin.mTarget != null && end.mTarget != null) {
      if (beginInGroup && endInGroup) {
        return true;
      }
      // A widget of fixed size centered between the group and something else
      // sits at begin + bias * slack, so it moves by (1 - bias) of a move of
      // its begin target and by bias of a move of its end target: all of it
      // when the bias pins it to the group's side.
      final bias = horizontal
          ? widget.getHorizontalBiasPercent()
          : widget.getVerticalBiasPercent();
      return _hasFixedSize(widget, behaviour) &&
          ((beginInGroup && bias == 0) || (endInGroup && bias == 1));
    }
    // A ratio couples the size to the other axis.
    if (behaviour == DimensionBehaviour.matchConstraint &&
        widget.getDimensionRatio() > 0) {
      return false;
    }
    return beginInGroup || endInGroup;
  }

  /// Links the solver treats in ways this check does not model: a chain
  /// along the axis, a baseline link (it replaces the top and bottom links),
  /// and a circular one.
  static bool _hasUnsupportedLinks(ConstraintWidget widget, bool horizontal) {
    if (widget.mCenter.isConnected()) {
      return true;
    }
    if (horizontal) {
      return widget.isInHorizontalChain();
    }
    return widget.isInVerticalChain() || widget.mBaseline.isConnected();
  }

  /// Whether [barrier] has to move with [group] for a move in direction
  /// [away]: a reference at its bound is in the group and the move pushes
  /// into the barrier's bound. Moving the other way, the barrier is free to
  /// stay where it is (it is bounded on one side only), and the solver keeps
  /// it there whenever following would cost more, even when every reference
  /// at its bound moves. The check does not model that choice: such a
  /// barrier stays out of the group, and its reference in the group then
  /// sends the layout to the solver (see _barrierHolds).
  static bool _followsGroup(
    Barrier barrier,
    Set<ConstraintWidget> group,
    int away,
  ) {
    final type = barrier.getBarrierType();
    final pushes = type == Barrier.left || type == Barrier.top
        ? away < 0
        : away > 0;
    if (!pushes) {
      return false;
    }
    final position = _barrierPosition(barrier);
    for (var i = 0; i < barrier.mWidgetsCount; i++) {
      final reference = barrier.mWidgets[i]!;
      if (HelperReferences.counts(barrier, reference) &&
          _referenceTarget(barrier, reference) == position &&
          group.contains(reference)) {
        return true;
      }
    }
    return false;
  }

  /// Whether the solver gives [widget] a size along an axis of [behaviour]
  /// that does not depend on where its links are.
  static bool _hasFixedSize(
    ConstraintWidget widget,
    DimensionBehaviour? behaviour,
  ) =>
      widget.getVisibility() == ConstraintWidget.GONE ||
      behaviour == DimensionBehaviour.fixed ||
      behaviour == DimensionBehaviour.wrapContent;

  /// Adds the soft errors of [widget], centered between the moving [group]
  /// on one side of the axis and something that stays on the other, to
  /// [costs] and [savings]. Returns false for a widget the check does not
  /// model. Does nothing for a widget whose links both move or neither does.
  bool _addCenteredPull(
    ConstraintWidget widget,
    bool horizontal,
    Set<ConstraintWidget> group,
    int away,
    Map<ConstraintWidget, List<Barrier>> referencedBy,
    List<int> costs,
    List<int> savings,
  ) {
    if (widget is Helper || _hasUnsupportedLinks(widget, horizontal)) {
      return false;
    }
    final orientation = horizontal
        ? ConstraintWidget.HORIZONTAL
        : ConstraintWidget.VERTICAL;
    final behaviour = widget.getDimensionBehaviour(orientation);
    if (behaviour == DimensionBehaviour.matchParent) {
      // Placed against the container whatever its links.
      return true;
    }
    final begin = horizontal ? widget.mLeft : widget.mTop;
    final end = horizontal ? widget.mRight : widget.mBottom;
    if (begin.mTarget == null || end.mTarget == null) {
      // A single link to the group makes it a member, which leaves a ratio,
      // the one size this check does not follow.
      return group.contains(widget);
    }
    final beginWidget = begin.mTarget!.mOwner;
    final endWidget = end.mTarget!.mOwner;
    final beginInGroup = group.contains(beginWidget);
    if (beginInGroup == group.contains(endWidget)) {
      return true;
    }

    // How much of a move of the group the widget follows. A member follows
    // it all (_movesWithGroup); a widget of fixed size follows (1 - bias) of
    // a move of its begin target and bias of a move of its end target.
    final bias = horizontal
        ? widget.getHorizontalBiasPercent()
        : widget.getVerticalBiasPercent();
    final fixedSize = _hasFixedSize(widget, behaviour);
    final stays = fixedSize && (beginInGroup ? bias == 1 : bias == 0);
    if (!group.contains(widget) && !stays) {
      // It slides part of the way, and whatever is linked to it along the
      // axis, or bounded by it, would slide with it.
      for (final anchor in _axisAnchors(widget, horizontal)) {
        if (_hasLiveDependents(anchor)) {
          return false;
        }
      }
      for (final other in referencedBy[widget] ?? const <Barrier>[]) {
        if (other.getOrientation() == orientation) {
          return false;
        }
      }
    }
    if (widget.getVisibility() == ConstraintWidget.GONE) {
      // addToSolver only centers a gone widget, with no range or bounds
      // checks, unless an anchor (even a stale one) depends on its end.
      return !end.hasDependents();
    }

    // The size the solver gives the widget in a given space, and the
    // strengths of its range and bounds checks, as _applyConstraints sets
    // them for a container that does not wrap.
    final run = horizontal ? widget.mHorizontalRun! : widget.mVerticalRun!;
    final space =
        _position(end.mTarget!) -
        end.getMargin() -
        _position(begin.mTarget!) -
        begin.getMargin();
    var minSize = 0;
    var maxSize = -1;
    var size = fixedSize ? run.mDimension.value : -1;
    var boundsStrength = SolverVariable.STRENGTH_HIGHEST;
    if (behaviour == DimensionBehaviour.matchConstraint) {
      if (widget.getDimensionRatio() > 0) {
        return false;
      }
      final matchType = horizontal
          ? widget.mMatchConstraintDefaultWidth
          : widget.mMatchConstraintDefaultHeight;
      if (matchType == ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
        final min = horizontal
            ? widget.mMatchConstraintMinWidth
            : widget.mMatchConstraintMinHeight;
        final max = horizontal
            ? widget.mMatchConstraintMaxWidth
            : widget.mMatchConstraintMaxHeight;
        if (min == 0 && max == 0) {
          // Fills the space: its edges sit on their targets wherever the
          // group is.
          return true;
        }
        minSize = min;
        maxSize = max > 0 ? max : -1;
      } else if (matchType == ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
        size = run.mDimension.value;
      } else {
        return false;
      }
      if (beginWidget is Barrier || endWidget is Barrier) {
        boundsStrength = SolverVariable.STRENGTH_HIGHEST;
      } else {
        boundsStrength = SolverVariable.STRENGTH_EQUALITY;
      }
    }

    int sizeIn(int space) {
      if (size >= 0) {
        return size;
      }
      var clamped = space;
      if (minSize > 0 && clamped < minSize) {
        clamped = minSize;
      }
      if (maxSize >= 0 && clamped > maxSize) {
        clamped = maxSize;
      }
      return clamped;
    }

    // The graph must have sized the widget as the solver does.
    if (run.mDimension.value != sizeIn(space)) {
      return false;
    }
    final spaceChange = beginInGroup ? -away : away;
    final slackBefore = space - sizeIn(space);
    final slackAfter = space + spaceChange - sizeIn(space + spaceChange);
    // Bounds checks pull both edges onto their targets: |slack| in all.
    _addChange(
      costs,
      savings,
      boundsStrength,
      slackBefore.abs(),
      slackAfter.abs(),
    );
    // Range checks keep both edges between their targets: the overflow.
    _addChange(
      costs,
      savings,
      SolverVariable.STRENGTH_EQUALITY,
      slackBefore < 0 ? -slackBefore : 0,
      slackAfter < 0 ? -slackAfter : 0,
    );
    return true;
  }

  /// Adds the change of an error from [before] to [after] to [costs] (when
  /// it grows) or [savings] (when it shrinks) at [strength].
  static void _addChange(
    List<int> costs,
    List<int> savings,
    int strength,
    int before,
    int after,
  ) {
    if (after > before) {
      costs[strength] += after - before;
    } else if (after < before) {
      savings[strength] += before - after;
    }
  }

  /// Whether a child of this container is linked to [anchor] (the anchor's
  /// dependents can also hold links that have since been moved elsewhere).
  bool _hasLiveDependents(ConstraintAnchor anchor) {
    final dependents = anchor.mDependents;
    if (dependents == null) {
      return false;
    }
    for (final dependent in dependents) {
      if (dependent.mTarget == anchor &&
          dependent.mOwner.getParent() == mWidgetcontainer) {
        return true;
      }
    }
    return false;
  }
}
