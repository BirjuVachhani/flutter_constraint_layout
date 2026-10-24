// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.ConstraintWidgetContainer
// (upstream pinned in UPSTREAM.md). Layout resolves via the dependency graph
// (directMeasure) first; when the graph cannot fully resolve (cyclic
// constraints, ratio loops, helper wrap sizing), it falls back to the
// LinearSystem Cassowary-style solver, mirroring upstream's layout() loop.
// The Direct/Grouping optimizer passes are not ported (the dependency graph
// plays that role here).

import 'dart:math' as math;

import 'analyzer/basic_measure.dart';
import 'analyzer/dependency_graph.dart';
import 'barrier.dart';
import 'cache.dart';
import 'chain.dart';
import 'chain_head.dart';
import 'constraint_anchor.dart';
import 'constraint_widget.dart';
import 'guideline.dart';
import 'linear_system.dart';
import 'virtual_layout.dart';
import 'optimizer.dart';
import 'solver_variable.dart';
import 'widget_container.dart';

class ConstraintWidgetContainer extends WidgetContainer {
  static const int _MAX_ITERATIONS = 8;

  /// How many times the fallback path re-measures children whose wrap size
  /// depends on a solver-resolved axis (see [_remeasureSizeDependentChildren]).
  /// Matches the `maxIterations` in BasicMeasure.solverMeasure: one pass to
  /// correct the size at the resolved dimension, one to confirm it settled.
  static const int _maxRemeasurePasses = 2;

  late final DependencyGraph mDependencyGraph = DependencyGraph(this);

  Measurer? mMeasurer;
  int mPaddingLeft = 0;
  int mPaddingTop = 0;
  int mPaddingRight = 0;
  int mPaddingBottom = 0;

  int mOptimizationLevel = Optimizer.OPTIMIZATION_STANDARD;
  bool mIsRtl = false;

  final LinearSystem mSystem = LinearSystem();

  int mHorizontalChainsSize = 0;
  int mVerticalChainsSize = 0;
  List<ChainHead?> mVerticalChainsArray = List.filled(4, null);
  List<ChainHead?> mHorizontalChainsArray = List.filled(4, null);

  bool _widthMeasuredTooSmall = false;
  bool _heightMeasuredTooSmall = false;

  ConstraintAnchor? _verticalWrapMin;
  ConstraintAnchor? _horizontalWrapMin;
  ConstraintAnchor? _verticalWrapMax;
  ConstraintAnchor? _horizontalWrapMax;

  final Set<ConstraintWidget> _widgetsToAdd = <ConstraintWidget>{};

  ConstraintWidgetContainer() : super();
  ConstraintWidgetContainer.rect(int x, int y, int width, int height)
    : super.rect(x, y, width, height);
  ConstraintWidgetContainer.size(int width, int height)
    : super.size(width, height);
  ConstraintWidgetContainer.sizeNamed(String debugName, int width, int height)
    : super.size(width, height) {
    setDebugName(debugName);
  }

  @override
  String? getType() => 'ConstraintLayout';

  void invalidateGraph() => mDependencyGraph.invalidateGraph();
  void invalidateMeasures() => mDependencyGraph.invalidateMeasures();

  bool directMeasure(bool optimizeWrap) =>
      mDependencyGraph.directMeasure(optimizeWrap);

  bool directMeasureSetup(bool optimizeWrap) =>
      mDependencyGraph.directMeasureSetup(optimizeWrap);

  bool directMeasureWithOrientation(bool optimizeWrap, int orientation) =>
      mDependencyGraph.directMeasureWithOrientation(optimizeWrap, orientation);

  int mPass = 0;

  void setPass(int pass) {
    mPass = pass;
  }

  /// Set by BasicMeasure.solverMeasure around its layout() calls: children
  /// are already measured, so the solver fallback must not re-measure.
  bool mSkipFallbackRemeasure = false;

  /// Reused flat buffer (8 slots per child) for the pre-graph state snapshot
  /// taken by layout(); avoids per-pass allocations on the hot path.
  final List<int> _layoutSnapshot = [];

  void updateHierarchy() {
    invalidateGraph();
  }

  void setMeasurer(Measurer? measurer) {
    mMeasurer = measurer;
    mDependencyGraph.setMeasurer(measurer);
  }

  Measurer? getMeasurer() => mMeasurer;

  void setOptimizationLevel(int value) => mOptimizationLevel = value;
  int getOptimizationLevel() => mOptimizationLevel;
  bool optimizeFor(int feature) => (mOptimizationLevel & feature) == feature;

  void setPadding(int left, int top, int right, int bottom) {
    mPaddingLeft = left;
    mPaddingTop = top;
    mPaddingRight = right;
    mPaddingBottom = bottom;
  }

  void setRtl(bool isRtl) => mIsRtl = isRtl;
  bool isRtl() => mIsRtl;

  bool handlesInternalConstraints() => false;

  @override
  void updateFromRuns(bool updateHorizontal, bool updateVertical) {
    super.updateFromRuns(updateHorizontal, updateVertical);
    for (final widget in mChildren) {
      widget.updateFromRuns(updateHorizontal, updateVertical);
    }
  }

  late final BasicMeasure mBasicMeasureSolver = BasicMeasure(this);

  /// The `measure(...)` entry used by the host's onMeasure equivalent, ported
  /// from upstream: delegates to BasicMeasure.solverMeasure.
  void measure(
    int optimizationLevel,
    int widthMode,
    int widthSize,
    int heightMode,
    int heightSize,
    int lastMeasureWidth,
    int lastMeasureHeight,
    int paddingX,
    int paddingY,
  ) {
    mPaddingLeft = paddingX;
    mPaddingTop = paddingY;
    mBasicMeasureSolver.solverMeasure(
      this,
      optimizationLevel,
      paddingX,
      paddingY,
      widthMode,
      widthSize,
      heightMode,
      heightSize,
      lastMeasureWidth,
      lastMeasureHeight,
    );
  }

  /// Resolve the layout using the dependency-graph engine.
  ///
  /// Safe to call repeatedly on a persistent container: widget runs are reset
  /// and the dependency graph is rebuilt from the current model each call.
  /// A cheaper measures-only re-resolve is not possible in this architecture,
  /// because resetting run state destroys the graph's edges along with the
  /// apply-time seeding (see the note in DependencyGraph.directMeasure), so
  /// callers should cache above this layer by skipping layout() entirely when
  /// nothing changed.
  void layout() {
    ensureWidgetRuns();
    for (final widget in mChildren) {
      widget.ensureWidgetRuns();
    }
    mMeasurer ??= _EchoMeasurer();
    mDependencyGraph.setMeasurer(mMeasurer);

    // Capture the incoming dimensions before the graph pass mutates them:
    // they are the "measured" bounds the solver fallback checks against.
    final preW = math.max(0, getWidth());
    final preH = math.max(0, getHeight());

    // Snapshot the widget state the graph pass mutates (measure results, run
    // positions, matchConstraint reclassifications). If the graph cannot
    // fully resolve, this state is restored so the solver fallback sees
    // exactly the input upstream's solver would (upstream never runs a graph
    // pass before the solver).
    final entryW = getWidth();
    final entryH = getHeight();
    final snapshot = _layoutSnapshot;
    final snapshotSize = mChildren.length * 8;
    while (snapshot.length < snapshotSize) {
      snapshot.add(0);
    }
    for (var i = 0; i < mChildren.length; i++) {
      final widget = mChildren[i];
      final base = i * 8;
      snapshot[base] = widget.getWidth();
      snapshot[base + 1] = widget.getHeight();
      snapshot[base + 2] = widget.getX();
      snapshot[base + 3] = widget.getY();
      snapshot[base + 4] = widget.getBaselineDistance();
      snapshot[base + 5] = widget.hasBaseline() ? 1 : 0;
      snapshot[base + 6] = widget.mMatchConstraintDefaultWidth;
      snapshot[base + 7] = widget.mMatchConstraintDefaultHeight;
    }

    invalidateGraph();
    invalidateMeasures();

    final optimizeWrap =
        getHorizontalDimensionBehaviour() == DimensionBehaviour.wrapContent ||
        getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent;

    // Nested containers must be laid out before their frame can participate,
    // which only the solver loop does; the graph treats them as leaves.
    // Virtual layouts (Flow) position their referenced widgets by creating
    // anchors at addToSolver time, which only exists on the solver path.
    var hasNestedContainer = false;
    for (final widget in mChildren) {
      if (widget is ConstraintWidgetContainer || widget is VirtualLayout) {
        hasNestedContainer = true;
        break;
      }
    }

    var allResolved =
        !hasNestedContainer && mDependencyGraph.directMeasure(optimizeWrap);

    // Finalize positions/sizes from the resolved runs and zero out GONE widgets.
    updateFromRuns(true, true);

    // Validate the graph's wrap sizing: the group-based wrap computation can
    // underestimate (for example with widgets centered against siblings) while
    // still reporting success. Any child outside the wrap bounds means the
    // graph result is invalid; the solver fallback computes the correct size.
    if (allResolved) {
      final wrapW =
          getHorizontalDimensionBehaviour() == DimensionBehaviour.wrapContent;
      final wrapH =
          getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent;
      // A wrap size above the container's max (setMaxWidth/setMaxHeight)
      // needs the solver too: upstream caps a wrap-content container at its
      // max in addToSolver, and the graph's wrap computation ignores the max.
      if ((wrapW && getWidth() > getMaxWidth()) ||
          (wrapH && getHeight() > getMaxHeight())) {
        allResolved = false;
      } else if (wrapW || wrapH) {
        for (final widget in mChildren) {
          if (widget.getVisibility() == ConstraintWidget.GONE) {
            continue;
          }
          // Widgets centered between two anchors along a wrap axis need the
          // solver: the graph's group wrap computation does not account for
          // them correctly.
          if (wrapW &&
              widget.mLeft.mTarget != null &&
              widget.mRight.mTarget != null) {
            allResolved = false;
            break;
          }
          if (wrapH &&
              widget.mTop.mTarget != null &&
              widget.mBottom.mTarget != null) {
            allResolved = false;
            break;
          }
          // Margins on anchors targeting the container must fit inside the
          // wrap size as well.
          final rightMargin =
              widget.mRight.mTarget != null &&
                  identical(widget.mRight.mTarget!.mOwner, this)
              ? widget.mRight.getMargin()
              : 0;
          final bottomMargin =
              widget.mBottom.mTarget != null &&
                  identical(widget.mBottom.mTarget!.mOwner, this)
              ? widget.mBottom.getMargin()
              : 0;
          if (wrapW &&
              (widget.getLeft() < 0 ||
                  widget.getRight() + rightMargin > getWidth())) {
            allResolved = false;
            break;
          }
          if (wrapH &&
              (widget.getTop() < 0 ||
                  widget.getBottom() + bottomMargin > getHeight())) {
            allResolved = false;
            break;
          }
        }
      }
    }

    if (!allResolved) {
      // The dependency graph could not fully resolve the layout (cyclic
      // constraints, dual-ratio, helper wrap sizing...): restore the
      // pre-graph widget state and fall back to the Cassowary-style
      // LinearSystem, mirroring upstream's layout() loop.
      setWidth(entryW);
      setHeight(entryH);
      for (var i = 0; i < mChildren.length; i++) {
        final widget = mChildren[i];
        final base = i * 8;
        widget.setWidth(snapshot[base]);
        widget.setHeight(snapshot[base + 1]);
        widget.setX(snapshot[base + 2]);
        widget.setY(snapshot[base + 3]);
        widget.setBaselineDistance(snapshot[base + 4]);
        widget.setHasBaseline(snapshot[base + 5] == 1);
        widget.mMatchConstraintDefaultWidth = snapshot[base + 6];
        widget.mMatchConstraintDefaultHeight = snapshot[base + 7];
      }
      // Re-measure wrap-sized children through the host measurer (upstream
      // measures in solverMeasure before solving); without this they would
      // enter the solver with their unmeasured (zero) sizes. Only wrap-sized
      // widgets are re-measured so that fixed widgets keep state a partial
      // measurer would not reproduce (for example baselines). Skipped when
      // this layout() was invoked by solverMeasure, which already measured.
      final fallbackMeasurer = mMeasurer;
      if (!mSkipFallbackRemeasure && fallbackMeasurer != null) {
        // Indexed loop over the pre-existing children: a virtual layout's
        // measure pass may append engine-internal widgets (GridCore boxes) to
        // mChildren, which must not invalidate this iteration.
        final childCount = mChildren.length;
        for (var ci = 0; ci < childCount; ci++) {
          final widget = mChildren[ci];
          if (widget is Guideline ||
              widget is Barrier ||
              widget is ConstraintWidgetContainer) {
            continue;
          }
          if (widget.getVisibility() == ConstraintWidget.GONE) {
            continue;
          }
          // Virtual layouts must run their measure pass before the solver:
          // it computes their measured size and prepares the internal chain
          // lists their addToSolver expands. SELF_DIMENSIONS so a
          // matchConstraint axis measures against the available space rather
          // than a not-yet-solved (zero) stored size.
          if (widget is VirtualLayout) {
            mBasicMeasureSolver.measure(
              fallbackMeasurer,
              widget,
              Measure.SELF_DIMENSIONS,
            );
            continue;
          }
          // A matchConstraint axis with a missing opposing anchor behaves as
          // wrap (mirroring the graph's _basicMeasureWidgets fallback): those
          // axes are measured with wrap behaviour so the measurer reports the
          // natural size. WRAP-styled matchConstraint axes are measured with
          // their MC behaviour (partial measurers echo the stored hint).
          final mcMissingW =
              widget.getHorizontalDimensionBehaviour() ==
                  DimensionBehaviour.matchConstraint &&
              (widget.mLeft.mTarget == null || widget.mRight.mTarget == null);
          final mcMissingH =
              widget.getVerticalDimensionBehaviour() ==
                  DimensionBehaviour.matchConstraint &&
              (widget.mTop.mTarget == null || widget.mBottom.mTarget == null);
          final wrapW =
              widget.getHorizontalDimensionBehaviour() ==
                  DimensionBehaviour.wrapContent ||
              mcMissingW ||
              (widget.getHorizontalDimensionBehaviour() ==
                      DimensionBehaviour.matchConstraint &&
                  widget.mMatchConstraintDefaultWidth ==
                      ConstraintWidget.MATCH_CONSTRAINT_WRAP);
          final wrapH =
              widget.getVerticalDimensionBehaviour() ==
                  DimensionBehaviour.wrapContent ||
              mcMissingH ||
              (widget.getVerticalDimensionBehaviour() ==
                      DimensionBehaviour.matchConstraint &&
                  widget.mMatchConstraintDefaultHeight ==
                      ConstraintWidget.MATCH_CONSTRAINT_WRAP);
          if (wrapW || wrapH) {
            final savedW = widget.getHorizontalDimensionBehaviour();
            final savedH = widget.getVerticalDimensionBehaviour();
            if (mcMissingW) {
              widget.setHorizontalDimensionBehaviour(
                DimensionBehaviour.wrapContent,
              );
            }
            if (mcMissingH) {
              widget.setVerticalDimensionBehaviour(
                DimensionBehaviour.wrapContent,
              );
            }
            mBasicMeasureSolver.measure(
              fallbackMeasurer,
              widget,
              Measure.SELF_DIMENSIONS,
            );
            widget.setHorizontalDimensionBehaviour(savedW);
            widget.setVerticalDimensionBehaviour(savedH);
          }
        }
      }
      _solverLayout(preW, preH);

      // Content whose measured size on a wrap axis depends on its resolved size
      // on a matchConstraint axis (wrapping text: height depends on width) was
      // measured above at a not-yet-solved (zero) match size. Now that the
      // solver has resolved the match axis, re-measure those children at the
      // real size and re-solve if it moved anything. Mirrors the multi-pass
      // re-measure loop in BasicMeasure.solverMeasure, which the direct
      // layout() path would otherwise skip.
      if (!mSkipFallbackRemeasure && fallbackMeasurer != null) {
        _remeasureSizeDependentChildren(fallbackMeasurer, preW, preH);
      }
    }
  }

  /// Re-measures children with one solver-resolved (matchConstraint) axis and
  /// one wrapContent axis whose measured size depends on the resolved one (the
  /// canonical case is wrapping text, whose height depends on its width).
  ///
  /// The fallback solver resolves match axes but does not measure them, and the
  /// pre-solve measure ran before those axes were known, so such children carry
  /// a size measured at width/height zero. This re-measures them at the resolved
  /// dimension and re-solves whenever a size actually changed, up to
  /// [_maxRemeasurePasses] times; a pass that changes nothing stops early.
  void _remeasureSizeDependentChildren(Measurer measurer, int preW, int preH) {
    for (var pass = 0; pass < _maxRemeasurePasses; pass++) {
      var changed = false;
      // Indexed loop: measuring a virtual layout can append internal widgets.
      final childCount = mChildren.length;
      for (var ci = 0; ci < childCount; ci++) {
        final widget = mChildren[ci];
        if (widget is Guideline ||
            widget is Barrier ||
            widget is ConstraintWidgetContainer ||
            widget is VirtualLayout) {
          continue;
        }
        if (widget.getVisibility() == ConstraintWidget.GONE) {
          continue;
        }

        // An axis is "solver-resolved" when it is matchConstraint (spread, not
        // the wrap-capped style) with both anchors present, so the solver sets
        // its size directly. A wrapContent axis is instead measured from
        // content, and only that combination can be mis-measured: one axis
        // sized by the solver, the other wrapped around content that depends
        // on it.
        final widthResolved =
            widget.getHorizontalDimensionBehaviour() ==
                DimensionBehaviour.matchConstraint &&
            widget.mMatchConstraintDefaultWidth !=
                ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
            widget.mLeft.mTarget != null &&
            widget.mRight.mTarget != null;
        final heightResolved =
            widget.getVerticalDimensionBehaviour() ==
                DimensionBehaviour.matchConstraint &&
            widget.mMatchConstraintDefaultHeight !=
                ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
            widget.mTop.mTarget != null &&
            widget.mBottom.mTarget != null;
        final widthWrap =
            widget.getHorizontalDimensionBehaviour() ==
            DimensionBehaviour.wrapContent;
        final heightWrap =
            widget.getVerticalDimensionBehaviour() ==
            DimensionBehaviour.wrapContent;

        if (!((widthResolved && heightWrap) || (heightResolved && widthWrap))) {
          continue;
        }

        final preWidth = widget.getWidth();
        final preHeight = widget.getHeight();
        // USE_GIVEN_DIMENSIONS feeds the solver-resolved size back as the fixed
        // dimension so the wrap axis is measured against it.
        mBasicMeasureSolver.measure(
          measurer,
          widget,
          Measure.USE_GIVEN_DIMENSIONS,
        );
        if (widget.getWidth() != preWidth || widget.getHeight() != preHeight) {
          changed = true;
        }
      }
      if (!changed) {
        return;
      }
      _solverLayout(preW, preH);
    }
  }

  bool isWidthMeasuredTooSmall() => _widthMeasuredTooSmall;

  bool isHeightMeasuredTooSmall() => _heightMeasuredTooSmall;

  void addVerticalWrapMinVariable(ConstraintAnchor top) {
    final current = _verticalWrapMin;
    if (current == null || top.getFinalValue() > current.getFinalValue()) {
      _verticalWrapMin = top;
    }
  }

  void addHorizontalWrapMinVariable(ConstraintAnchor left) {
    final current = _horizontalWrapMin;
    if (current == null || left.getFinalValue() > current.getFinalValue()) {
      _horizontalWrapMin = left;
    }
  }

  void addVerticalWrapMaxVariable(ConstraintAnchor bottom) {
    final current = _verticalWrapMax;
    if (current == null || bottom.getFinalValue() > current.getFinalValue()) {
      _verticalWrapMax = bottom;
    }
  }

  void addHorizontalWrapMaxVariable(ConstraintAnchor right) {
    final current = _horizontalWrapMax;
    if (current == null || right.getFinalValue() > current.getFinalValue()) {
      _horizontalWrapMax = right;
    }
  }

  void _addMinWrap(
    ConstraintAnchor constraintAnchor,
    SolverVariable parentMin,
  ) {
    final variable = mSystem.createObjectVariable(constraintAnchor)!;
    const wrapStrength = SolverVariable.STRENGTH_EQUALITY;
    mSystem.addGreaterThan(variable, parentMin, 0, wrapStrength);
  }

  void _addMaxWrap(
    ConstraintAnchor constraintAnchor,
    SolverVariable parentMax,
  ) {
    final variable = mSystem.createObjectVariable(constraintAnchor)!;
    const wrapStrength = SolverVariable.STRENGTH_EQUALITY;
    mSystem.addGreaterThan(parentMax, variable, 0, wrapStrength);
  }

  /// Add this widget and its children to the solver.
  bool addChildrenToSolver(LinearSystem system) {
    final optimize = optimizeFor(Optimizer.OPTIMIZATION_GRAPH);
    addToSolver(system, optimize);
    final count = mChildren.length;

    var hasBarriers = false;
    for (var i = 0; i < count; i++) {
      final widget = mChildren[i];
      widget.setInBarrier(ConstraintWidget.HORIZONTAL, false);
      widget.setInBarrier(ConstraintWidget.VERTICAL, false);
      if (widget is Barrier) {
        hasBarriers = true;
      }
    }

    if (hasBarriers) {
      for (var i = 0; i < count; i++) {
        final widget = mChildren[i];
        if (widget is Barrier) {
          widget.markWidgets();
        }
      }
    }

    _widgetsToAdd.clear();
    for (var i = 0; i < count; i++) {
      final widget = mChildren[i];
      if (widget.addFirst()) {
        if (widget is VirtualLayout) {
          _widgetsToAdd.add(widget);
        } else {
          widget.addToSolver(system, optimize);
        }
      }
    }

    // If we have virtual layouts, we need to add them to the solver in the
    // correct order (in case they reference one another).
    while (_widgetsToAdd.isNotEmpty) {
      final numLayouts = _widgetsToAdd.length;
      VirtualLayout? layout;
      for (final widget in _widgetsToAdd) {
        layout = widget as VirtualLayout;

        // we'll go through the virtual layouts that references others first,
        // to give them a shot at setting their constraints.
        if (layout.containsAny(_widgetsToAdd)) {
          layout.addToSolver(system, optimize);
          _widgetsToAdd.remove(layout);
          break;
        }
      }
      if (numLayouts == _widgetsToAdd.length) {
        // looks we didn't find anymore dependency, let's add everything.
        for (final widget in _widgetsToAdd) {
          widget.addToSolver(system, optimize);
        }
        _widgetsToAdd.clear();
      }
    }

    for (var i = 0; i < count; i++) {
      final widget = mChildren[i];
      if (widget is ConstraintWidgetContainer) {
        final horizontalBehaviour =
            widget.mListDimensionBehaviors[ConstraintWidget.HORIZONTAL];
        final verticalBehaviour =
            widget.mListDimensionBehaviors[ConstraintWidget.VERTICAL];
        if (horizontalBehaviour == DimensionBehaviour.wrapContent) {
          widget.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
        }
        if (verticalBehaviour == DimensionBehaviour.wrapContent) {
          widget.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
        }
        widget.addToSolver(system, optimize);
        if (horizontalBehaviour == DimensionBehaviour.wrapContent) {
          widget.setHorizontalDimensionBehaviour(horizontalBehaviour);
        }
        if (verticalBehaviour == DimensionBehaviour.wrapContent) {
          widget.setVerticalDimensionBehaviour(verticalBehaviour);
        }
      } else {
        Optimizer.checkMatchParent(this, system, widget);
        if (!widget.addFirst()) {
          widget.addToSolver(system, optimize);
        }
      }
    }

    if (mHorizontalChainsSize > 0) {
      Chain.applyChainConstraints(
        this,
        system,
        null,
        ConstraintWidget.HORIZONTAL,
      );
    }
    if (mVerticalChainsSize > 0) {
      Chain.applyChainConstraints(
        this,
        system,
        null,
        ConstraintWidget.VERTICAL,
      );
    }
    return true;
  }

  /// Update the frame of the layout and its children from the solver.
  bool updateChildrenFromSolver(LinearSystem system, List<bool> flags) {
    flags[Optimizer.FLAG_RECOMPUTE_BOUNDS] = false;
    final optimize = optimizeFor(Optimizer.OPTIMIZATION_GRAPH);
    updateFromSolver(system, optimize);
    final count = mChildren.length;
    var hasOverride = false;
    for (var i = 0; i < count; i++) {
      final widget = mChildren[i];
      widget.updateFromSolver(system, optimize);
      if (widget.hasDimensionOverride()) {
        hasOverride = true;
      }
    }
    return hasOverride;
  }

  LinearSystem getSystem() => mSystem;

  /// Reset the chains array. Needs to be called before layout.
  void _resetChains() {
    mHorizontalChainsSize = 0;
    mVerticalChainsSize = 0;
  }

  /// Add the chain that [constraintWidget] is part of; called by
  /// ConstraintWidget.addToSolver().
  void addChain(ConstraintWidget constraintWidget, int type) {
    if (type == ConstraintWidget.HORIZONTAL) {
      _addHorizontalChain(constraintWidget);
    } else if (type == ConstraintWidget.VERTICAL) {
      _addVerticalChain(constraintWidget);
    }
  }

  void _addHorizontalChain(ConstraintWidget widget) {
    if (mHorizontalChainsSize + 1 >= mHorizontalChainsArray.length) {
      mHorizontalChainsArray = [
        ...mHorizontalChainsArray,
        ...List<ChainHead?>.filled(mHorizontalChainsArray.length, null),
      ];
    }
    mHorizontalChainsArray[mHorizontalChainsSize] = ChainHead(
      widget,
      ConstraintWidget.HORIZONTAL,
      isRtl(),
    );
    mHorizontalChainsSize++;
  }

  void _addVerticalChain(ConstraintWidget widget) {
    if (mVerticalChainsSize + 1 >= mVerticalChainsArray.length) {
      mVerticalChainsArray = [
        ...mVerticalChainsArray,
        ...List<ChainHead?>.filled(mVerticalChainsArray.length, null),
      ];
    }
    mVerticalChainsArray[mVerticalChainsSize] = ChainHead(
      widget,
      ConstraintWidget.VERTICAL,
      isRtl(),
    );
    mVerticalChainsSize++;
  }

  /// The Cassowary solver loop, ported from upstream's layout() (minus the
  /// Direct/Grouping optimizer passes, which the dependency graph replaces).
  /// [preW]/[preH] are the container dimensions from before the graph pass.
  void _solverLayout(int preW, int preH) {
    mX = 0;
    mY = 0;
    _widthMeasuredTooSmall = false;
    _heightMeasuredTooSmall = false;
    final count = mChildren.length;

    final originalVerticalDimensionBehaviour =
        mListDimensionBehaviors[ConstraintWidget.VERTICAL];
    final originalHorizontalDimensionBehaviour =
        mListDimensionBehaviors[ConstraintWidget.HORIZONTAL];

    var wrapOverride = false;

    final useGraphOptimizer =
        optimizeFor(Optimizer.OPTIMIZATION_GRAPH) ||
        optimizeFor(Optimizer.OPTIMIZATION_GRAPH_WRAP);
    mSystem.graphOptimizer = false;
    mSystem.newgraphOptimizer = false;
    if (mOptimizationLevel != Optimizer.OPTIMIZATION_NONE &&
        useGraphOptimizer) {
      mSystem.newgraphOptimizer = true;
    }

    var countSolve = 0;
    final hasWrapContent =
        getHorizontalDimensionBehaviour() == DimensionBehaviour.wrapContent ||
        getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent;

    _resetChains();

    // Before we solve our system, call layout() on any child container.
    for (var i = 0; i < count; i++) {
      final widget = mChildren[i];
      if (widget is ConstraintWidgetContainer) {
        widget.layout();
      }
    }
    final optimize = optimizeFor(Optimizer.OPTIMIZATION_GRAPH);

    // Now let's solve our system as usual
    var needsSolving = true;
    while (needsSolving) {
      countSolve++;
      try {
        mSystem.reset();
        _resetChains();
        createObjectVariables(mSystem);
        for (var i = 0; i < count; i++) {
          mChildren[i].createObjectVariables(mSystem);
        }
        needsSolving = addChildrenToSolver(mSystem);
        if (_verticalWrapMin != null) {
          _addMinWrap(_verticalWrapMin!, mSystem.createObjectVariable(mTop)!);
          _verticalWrapMin = null;
        }
        if (_verticalWrapMax != null) {
          _addMaxWrap(
            _verticalWrapMax!,
            mSystem.createObjectVariable(mBottom)!,
          );
          _verticalWrapMax = null;
        }
        if (_horizontalWrapMin != null) {
          _addMinWrap(
            _horizontalWrapMin!,
            mSystem.createObjectVariable(mLeft)!,
          );
          _horizontalWrapMin = null;
        }
        if (_horizontalWrapMax != null) {
          _addMaxWrap(
            _horizontalWrapMax!,
            mSystem.createObjectVariable(mRight)!,
          );
          _horizontalWrapMax = null;
        }
        if (needsSolving) {
          mSystem.minimize();
        }
      } catch (e) {
        // ignore: avoid_print
        print('EXCEPTION : $e');
      }
      if (needsSolving) {
        needsSolving = updateChildrenFromSolver(mSystem, Optimizer.sFlags);
      } else {
        updateFromSolver(mSystem, optimize);
        for (var i = 0; i < count; i++) {
          mChildren[i].updateFromSolver(mSystem, optimize);
        }
        needsSolving = false;
      }

      if (hasWrapContent &&
          countSolve < _MAX_ITERATIONS &&
          Optimizer.sFlags[Optimizer.FLAG_RECOMPUTE_BOUNDS]) {
        // let's get the new bounds
        var maxX = 0;
        var maxY = 0;
        for (var i = 0; i < count; i++) {
          final widget = mChildren[i];
          maxX = math.max(maxX, widget.mX + widget.getWidth());
          maxY = math.max(maxY, widget.mY + widget.getHeight());
        }
        maxX = math.max(mMinWidth, maxX);
        maxY = math.max(mMinHeight, maxY);
        if (originalHorizontalDimensionBehaviour ==
            DimensionBehaviour.wrapContent) {
          if (getWidth() < maxX) {
            setWidth(maxX);
            // force using the solver
            mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] =
                DimensionBehaviour.wrapContent;
            wrapOverride = true;
            needsSolving = true;
          }
        }
        if (originalVerticalDimensionBehaviour ==
            DimensionBehaviour.wrapContent) {
          if (getHeight() < maxY) {
            setHeight(maxY);
            mListDimensionBehaviors[ConstraintWidget.VERTICAL] =
                DimensionBehaviour.wrapContent;
            wrapOverride = true;
            needsSolving = true;
          }
        }
      }

      final width = math.max(mMinWidth, getWidth());
      if (width > getWidth()) {
        setWidth(width);
        mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] =
            DimensionBehaviour.fixed;
        wrapOverride = true;
        needsSolving = true;
      }
      final height = math.max(mMinHeight, getHeight());
      if (height > getHeight()) {
        setHeight(height);
        mListDimensionBehaviors[ConstraintWidget.VERTICAL] =
            DimensionBehaviour.fixed;
        wrapOverride = true;
        needsSolving = true;
      }

      // Upstream also clamps a wrap axis back to preW/preH here ("width/
      // height measured too small"). That relies on the Direct optimizer
      // having pre-sized wrap containers, which is not ported (the dependency
      // graph plays that role but is bypassed on this path), so the clamp
      // would wrongly squash wrap containers whose entry size is smaller than
      // their content. No core test depends on the clamp; it is omitted.

      if (countSolve > _MAX_ITERATIONS) {
        needsSolving = false;
      }
    }

    if (wrapOverride) {
      mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] =
          originalHorizontalDimensionBehaviour;
      mListDimensionBehaviors[ConstraintWidget.VERTICAL] =
          originalVerticalDimensionBehaviour;
    }

    resetSolverVariables(mSystem.getCache());
  }

  /// Reset the solver variables of this container and all its children.
  @override
  void resetSolverVariables(Cache cache) {
    super.resetSolverVariables(cache);
    final count = mChildren.length;
    for (var i = 0; i < count; i++) {
      mChildren[i].resetSolverVariables(cache);
    }
  }
}

/// Default measurer used when a container has no explicit measurer. For leaf
/// widgets whose intrinsic size was provided up-front (the common test setup),
/// a WRAP_CONTENT measure returns the widget's current natural size, while a
/// FIXED/MATCH measure honours the caller-provided hint (which is the computed
/// size for ratio/percent). This makes the graph engine reproduce the same
/// results the upstream solver produces without an explicit measurer.
class _EchoMeasurer implements Measurer {
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    if (measure.horizontalBehavior == DimensionBehaviour.wrapContent) {
      measure.measuredWidth = widget.mWidth;
    } else {
      measure.measuredWidth = measure.horizontalDimension;
    }
    if (measure.verticalBehavior == DimensionBehaviour.wrapContent) {
      measure.measuredHeight = widget.mHeight;
    } else {
      measure.measuredHeight = measure.verticalDimension;
    }
    // Preserve the widget's declared baseline (the measure() step writes these
    // back to the widget, so echoing them keeps baseline constraints working).
    measure.measuredHasBaseline = widget.hasBaseline();
    measure.measuredBaseline = widget.getBaselineDistance();
    widget.setMeasureRequested(false);
  }

  @override
  void didMeasures() {}
}
