// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.DependencyGraph
// (debug/graphviz output omitted).

import '../barrier.dart';
import '../constraint_widget.dart';
import '../constraint_widget_container.dart';
import '../guideline.dart';
import '../helper_widget.dart';
import 'basic_measure.dart';
import 'chain_run.dart';
import 'dependency_node.dart';
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

  int _computeWrap(ConstraintWidgetContainer container, int orientation) {
    final count = mGroups.length;
    var wrapSize = 0;
    for (var i = 0; i < count; i++) {
      final run = mGroups[i];
      final size = run.computeWrapSize(container, orientation);
      wrapSize = wrapSize > size ? wrapSize : size;
    }
    return wrapSize;
  }

  void defineTerminalWidgets(
      DimensionBehaviour horizontalBehavior, DimensionBehaviour verticalBehavior) {
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
                verticalBehavior == DimensionBehaviour.wrapContent);
          }
        }
      }
    }
  }

  bool directMeasure(bool optimizeWrap) {
    optimizeWrap = optimizeWrap && useGroups;

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

    final originalHorizontalDimension =
        mWidgetcontainer.getDimensionBehaviour(ConstraintWidget.HORIZONTAL);
    final originalVerticalDimension =
        mWidgetcontainer.getDimensionBehaviour(ConstraintWidget.VERTICAL);

    if (mNeedBuildGraph) {
      buildGraph();
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

      if (optimizeWrap &&
          originalHorizontalDimension == DimensionBehaviour.wrapContent) {
        mWidgetcontainer.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
        mWidgetcontainer
            .setWidth(_computeWrap(mWidgetcontainer, ConstraintWidget.HORIZONTAL));
        mWidgetcontainer.mHorizontalRun!.mDimension
            .resolve(mWidgetcontainer.getWidth());
      }
      if (optimizeWrap &&
          originalVerticalDimension == DimensionBehaviour.wrapContent) {
        mWidgetcontainer.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
        mWidgetcontainer
            .setHeight(_computeWrap(mWidgetcontainer, ConstraintWidget.VERTICAL));
        mWidgetcontainer.mVerticalRun!.mDimension
            .resolve(mWidgetcontainer.getHeight());
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
    for (final run in mRuns) {
      if (!checkRoot && run.mWidget == mWidgetcontainer) {
        continue;
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
      // (the solver, upstream's ground truth, applies the min rule), and it
      // ignores circular (center) constraints entirely. Route layouts
      // containing either to the solver fallback.
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
      }
      // The graph's handling of chains diverges from the solver (the upstream
      // ground truth) in three cases: GONE members (collapsed chain
      // positioning), ratio-sized matchConstraint members, and chains along a
      // wrap-content axis of the container (chain sizing must feed the wrap
      // size). Report such chains as unresolved and let the solver fallback
      // produce the layout.
      if (run is ChainRun) {
        var needsSolver = false;
        final chainAxisBehaviour = run.orientation == ConstraintWidget.HORIZONTAL
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
            final memberDefault =
                run.orientation == ConstraintWidget.HORIZONTAL
                    ? member.mMatchConstraintDefaultWidth
                    : member.mMatchConstraintDefaultHeight;
            if (member.mListDimensionBehaviors[run.orientation] ==
                    DimensionBehaviour.matchConstraint &&
                (member.mDimensionRatio != 0 ||
                    memberDefault == ConstraintWidget.MATCH_CONSTRAINT_WRAP)) {
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

    mWidgetcontainer.setHorizontalDimensionBehaviour(originalHorizontalDimension!);
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

    final originalHorizontalDimension =
        mWidgetcontainer.getDimensionBehaviour(ConstraintWidget.HORIZONTAL);
    final originalVerticalDimension =
        mWidgetcontainer.getDimensionBehaviour(ConstraintWidget.VERTICAL);

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

      if (orientation == ConstraintWidget.HORIZONTAL) {
        if (optimizeWrap &&
            originalHorizontalDimension == DimensionBehaviour.wrapContent) {
          mWidgetcontainer.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
          mWidgetcontainer.setWidth(
              _computeWrap(mWidgetcontainer, ConstraintWidget.HORIZONTAL));
          mWidgetcontainer.mHorizontalRun!.mDimension
              .resolve(mWidgetcontainer.getWidth());
        }
      } else {
        if (optimizeWrap &&
            originalVerticalDimension == DimensionBehaviour.wrapContent) {
          mWidgetcontainer.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
          mWidgetcontainer
              .setHeight(_computeWrap(mWidgetcontainer, ConstraintWidget.VERTICAL));
          mWidgetcontainer.mVerticalRun!.mDimension
              .resolve(mWidgetcontainer.getHeight());
        }
      }
    }

    var checkRoot = false;

    if (orientation == ConstraintWidget.HORIZONTAL) {
      if (mWidgetcontainer.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] ==
              DimensionBehaviour.fixed ||
          mWidgetcontainer.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] ==
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

    mWidgetcontainer.setHorizontalDimensionBehaviour(originalHorizontalDimension!);
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

  bool _basicMeasureWidgets(ConstraintWidgetContainer constraintWidgetContainer) {
    for (final widget in constraintWidgetContainer.mChildren) {
      var horizontal = widget.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL];
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
        widget.mMatchConstraintDefaultWidth = ConstraintWidget.MATCH_CONSTRAINT_PERCENT;
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
          widget.mMatchConstraintDefaultWidth = ConstraintWidget.MATCH_CONSTRAINT_RATIO;
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
      widget.mHorizontalRun!.matchConstraintsType = widget.mMatchConstraintDefaultWidth;
      widget.mVerticalRun!.mDimensionBehavior = vertical;
      widget.mVerticalRun!.matchConstraintsType = widget.mMatchConstraintDefaultHeight;

      if ((horizontal == DimensionBehaviour.matchParent ||
              horizontal == DimensionBehaviour.fixed ||
              horizontal == DimensionBehaviour.wrapContent) &&
          (vertical == DimensionBehaviour.matchParent ||
              vertical == DimensionBehaviour.fixed ||
              vertical == DimensionBehaviour.wrapContent)) {
        var width = widget.getWidth();
        if (horizontal == DimensionBehaviour.matchParent) {
          width = constraintWidgetContainer.getWidth() -
              widget.mLeft.mMargin -
              widget.mRight.mMargin;
          horizontal = DimensionBehaviour.fixed;
        }
        var height = widget.getHeight();
        if (vertical == DimensionBehaviour.matchParent) {
          height = constraintWidgetContainer.getHeight() -
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
            _measure(widget, DimensionBehaviour.wrapContent, 0,
                DimensionBehaviour.wrapContent, 0);
          }
          final height = widget.getHeight();
          final width = (height * widget.mDimensionRatio + 0.5).toInt();
          _measure(widget, DimensionBehaviour.fixed, width,
              DimensionBehaviour.fixed, height);
          widget.mHorizontalRun!.mDimension.resolve(widget.getWidth());
          widget.mVerticalRun!.mDimension.resolve(widget.getHeight());
          widget.measured = true;
          continue;
        } else if (widget.mMatchConstraintDefaultWidth ==
            ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
          _measure(widget, DimensionBehaviour.wrapContent, 0, vertical,
              widget.getHeight());
          widget.mHorizontalRun!.mDimension.wrapValue = widget.getWidth();
          continue;
        } else if (widget.mMatchConstraintDefaultWidth ==
            ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
          if (constraintWidgetContainer
                      .mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] ==
                  DimensionBehaviour.fixed ||
              constraintWidgetContainer
                      .mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] ==
                  DimensionBehaviour.matchParent) {
            final percent = widget.mMatchConstraintPercentWidth;
            var width =
                (0.5 + percent * constraintWidgetContainer.getWidth()).toInt();
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
          if (widget.mListAnchors[ConstraintWidget.ANCHOR_LEFT].mTarget == null ||
              widget.mListAnchors[ConstraintWidget.ANCHOR_RIGHT].mTarget == null) {
            _measure(widget, DimensionBehaviour.wrapContent, 0, vertical,
              widget.getHeight());
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
            _measure(widget, DimensionBehaviour.wrapContent, 0,
                DimensionBehaviour.wrapContent, 0);
          }
          final width = widget.getWidth();
          var ratio = widget.mDimensionRatio;
          if (widget.getDimensionRatioSide() == ConstraintWidget.UNKNOWN) {
            ratio = 1 / ratio;
          }
          final height = (width * ratio + 0.5).toInt();
          _measure(widget, DimensionBehaviour.fixed, width,
              DimensionBehaviour.fixed, height);
          widget.mHorizontalRun!.mDimension.resolve(widget.getWidth());
          widget.mVerticalRun!.mDimension.resolve(widget.getHeight());
          widget.measured = true;
          continue;
        } else if (widget.mMatchConstraintDefaultHeight ==
            ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
          _measure(widget, horizontal, widget.getWidth(),
              DimensionBehaviour.wrapContent, 0);
          widget.mVerticalRun!.mDimension.wrapValue = widget.getHeight();
          continue;
        } else if (widget.mMatchConstraintDefaultHeight ==
            ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
          if (constraintWidgetContainer
                      .mListDimensionBehaviors[ConstraintWidget.VERTICAL] ==
                  DimensionBehaviour.fixed ||
              constraintWidgetContainer
                      .mListDimensionBehaviors[ConstraintWidget.VERTICAL] ==
                  DimensionBehaviour.matchParent) {
            final percent = widget.mMatchConstraintPercentHeight;
            final width = widget.getWidth();
            var height =
                (0.5 + percent * constraintWidgetContainer.getHeight()).toInt();
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
            _measure(widget, horizontal, width, DimensionBehaviour.fixed, height);
            widget.mHorizontalRun!.mDimension.resolve(widget.getWidth());
            widget.mVerticalRun!.mDimension.resolve(widget.getHeight());
            widget.measured = true;
            continue;
          }
        } else {
          if (widget.mListAnchors[ConstraintWidget.ANCHOR_TOP].mTarget == null ||
              widget.mListAnchors[ConstraintWidget.ANCHOR_BOTTOM].mTarget == null) {
            _measure(widget, DimensionBehaviour.wrapContent, 0, vertical,
              widget.getHeight());
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
          _measure(widget, DimensionBehaviour.wrapContent, 0,
              DimensionBehaviour.wrapContent, 0);
          widget.mHorizontalRun!.mDimension.wrapValue = widget.getWidth();
          widget.mVerticalRun!.mDimension.wrapValue = widget.getHeight();
        } else if (widget.mMatchConstraintDefaultHeight ==
                ConstraintWidget.MATCH_CONSTRAINT_PERCENT &&
            widget.mMatchConstraintDefaultWidth ==
                ConstraintWidget.MATCH_CONSTRAINT_PERCENT &&
            constraintWidgetContainer
                    .mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] ==
                DimensionBehaviour.fixed &&
            constraintWidgetContainer
                    .mListDimensionBehaviors[ConstraintWidget.VERTICAL] ==
                DimensionBehaviour.fixed) {
          final horizPercent = widget.mMatchConstraintPercentWidth;
          final vertPercent = widget.mMatchConstraintPercentHeight;
          final width =
              (0.5 + horizPercent * constraintWidgetContainer.getWidth()).toInt();
          final height =
              (0.5 + vertPercent * constraintWidgetContainer.getHeight()).toInt();
          _measure(widget, DimensionBehaviour.fixed, width,
              DimensionBehaviour.fixed, height);
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

      final horizWrap = horiz == DimensionBehaviour.wrapContent ||
          (horiz == DimensionBehaviour.matchConstraint &&
              horizMatchConstraintsType == ConstraintWidget.MATCH_CONSTRAINT_WRAP);

      final vertWrap = vert == DimensionBehaviour.wrapContent ||
          (vert == DimensionBehaviour.matchConstraint &&
              vertMatchConstraintsType == ConstraintWidget.MATCH_CONSTRAINT_WRAP);

      final horizResolved = widget.mHorizontalRun!.mDimension.resolved;
      final vertResolved = widget.mVerticalRun!.mDimension.resolved;

      if (horizResolved && vertResolved) {
        _measure(widget, DimensionBehaviour.fixed,
            widget.mHorizontalRun!.mDimension.value, DimensionBehaviour.fixed,
            widget.mVerticalRun!.mDimension.value);
        widget.measured = true;
      } else if (horizResolved && vertWrap) {
        _measure(widget, DimensionBehaviour.fixed,
            widget.mHorizontalRun!.mDimension.value, DimensionBehaviour.wrapContent,
            widget.mVerticalRun!.mDimension.value);
        if (vert == DimensionBehaviour.matchConstraint) {
          widget.mVerticalRun!.mDimension.wrapValue = widget.getHeight();
        } else {
          widget.mVerticalRun!.mDimension.resolve(widget.getHeight());
          widget.measured = true;
        }
      } else if (vertResolved && horizWrap) {
        _measure(widget, DimensionBehaviour.wrapContent,
            widget.mHorizontalRun!.mDimension.value, DimensionBehaviour.fixed,
            widget.mVerticalRun!.mDimension.value);
        if (horiz == DimensionBehaviour.matchConstraint) {
          widget.mHorizontalRun!.mDimension.wrapValue = widget.getWidth();
        } else {
          widget.mHorizontalRun!.mDimension.resolve(widget.getWidth());
          widget.measured = true;
        }
      }
      if (widget.measured && widget.mVerticalRun!.mBaselineDimension != null) {
        widget.mVerticalRun!.mBaselineDimension!
            .resolve(widget.getBaselineDistance());
      }
    }
  }

  void invalidateGraph() {
    mNeedBuildGraph = true;
  }

  void invalidateMeasures() {
    mNeedRedoMeasures = true;
  }

  void buildGraph() {
    _buildGraphRuns(mRuns);

    if (useGroups) {
      mGroups.clear();
      RunGroup.index = 0;
      _findGroup(mWidgetcontainer.mHorizontalRun!, ConstraintWidget.HORIZONTAL, mGroups);
      _findGroup(mWidgetcontainer.mVerticalRun!, ConstraintWidget.VERTICAL, mGroups);
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
        widget.horizontalChainRun ??= ChainRun(widget, ConstraintWidget.HORIZONTAL);
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
              dependent, orientation, RunGroup.baseline, end, groups, group);
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
        _applyGroup(dependent, orientation, RunGroup.start, run.end, groups, null);
      } else if (dependent is WidgetRun) {
        _applyGroup(
            dependent.start, orientation, RunGroup.start, run.end, groups, null);
      }
    }
    for (final dependent in run.end.mDependencies) {
      if (dependent is DependencyNode) {
        _applyGroup(dependent, orientation, RunGroup.end, run.start, groups, null);
      } else if (dependent is WidgetRun) {
        _applyGroup(
            dependent.end, orientation, RunGroup.end, run.start, groups, null);
      }
    }
    if (orientation == ConstraintWidget.VERTICAL) {
      for (final dependent in (run as VerticalWidgetRun).baseline.mDependencies) {
        if (dependent is DependencyNode) {
          _applyGroup(dependent, orientation, RunGroup.baseline, null, groups, null);
        }
      }
    }
  }
}
