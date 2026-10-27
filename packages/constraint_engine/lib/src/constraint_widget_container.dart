// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.ConstraintWidgetContainer
// (upstream pinned in UPSTREAM.md). layout() is upstream's pass: in the first
// measure pass at OPTIMIZATION_DIRECT it runs the Direct pass
// (analyzer/direct.dart) and measures what Direct left unmeasured, then it
// solves. measure() is upstream's entry through BasicMeasure.solverMeasure,
// which runs the dependency graph first at the OPTIMIZATION_GRAPH levels.
// The Grouping and dependency-ordering passes are not ported.

import 'dart:math' as math;

import 'analyzer/basic_measure.dart';
import 'analyzer/dependency_graph.dart';
import 'analyzer/direct.dart';
import 'barrier.dart';
import 'cache.dart';
import 'chain.dart';
import 'chain_head.dart';
import 'constraint_anchor.dart';
import 'constraint_widget.dart';
import 'debug/solver_trace.dart';
import 'guideline.dart';
import 'jfloat.dart';
import 'linear_system.dart';
import 'virtual_layout.dart';
import 'optimizer.dart';
import 'solver_variable.dart';
import 'widget_container.dart';

/// A container of [ConstraintWidget]s that can lay out its children.
///
/// The container is the root of a layout, and a widget like any other, so
/// its children connect to its anchors. Add children with [add], connect
/// them, set a [Measurer] ([setMeasurer]), then call [measure] to measure
/// the children and resolve every child's position and size, as Android's
/// ConstraintLayout does. [layout] is one pass on its own: the Direct pass
/// when the level has [Optimizer.OPTIMIZATION_DIRECT] and the pass is the
/// first ([setPass]), then the solver, with the sizes the children have by
/// then. A container with a [DimensionBehaviour.wrapContent] axis sizes
/// itself around its children.
class ConstraintWidgetContainer extends WidgetContainer {
  static const int _MAX_ITERATIONS = 8;

  /// The dependency graph, which [BasicMeasure.solverMeasure] runs at the
  /// [Optimizer.OPTIMIZATION_GRAPH] and [Optimizer.OPTIMIZATION_GRAPH_WRAP]
  /// levels.
  late final DependencyGraph mDependencyGraph = DependencyGraph(this);

  /// The measurer set by [setMeasurer], or null.
  Measurer? mMeasurer;

  /// The left padding; see [setPadding].
  int mPaddingLeft = 0;

  /// The top padding; see [setPadding].
  int mPaddingTop = 0;

  /// The right padding; see [setPadding].
  int mPaddingRight = 0;

  /// The bottom padding; see [setPadding].
  int mPaddingBottom = 0;

  /// The optimization level; see [setOptimizationLevel].
  int mOptimizationLevel = Optimizer.OPTIMIZATION_STANDARD;

  /// Whether the layout is right-to-left; see [setRtl].
  bool mIsRtl = false;

  /// The solver that [layout] builds and minimizes.
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

  /// Creates an empty container at (0, 0) with a size of 0 x 0.
  ConstraintWidgetContainer() : super();

  /// Creates an empty container at ([x], [y]) with the given [width] and
  /// [height].
  ConstraintWidgetContainer.rect(int x, int y, int width, int height)
    : super.rect(x, y, width, height);

  /// Creates an empty container at (0, 0) with the given [width] and
  /// [height].
  ConstraintWidgetContainer.size(int width, int height)
    : super.size(width, height);

  /// Creates an empty container at (0, 0) with the given [width] and
  /// [height], named [debugName] for debugging.
  ConstraintWidgetContainer.sizeNamed(String debugName, int width, int height)
    : super.size(width, height) {
    setDebugName(debugName);
  }

  /// The type name of a container: `ConstraintLayout`.
  @override
  String? getType() => 'ConstraintLayout';

  /// Invalidate the graph of constraints, so that the next dependency-graph
  /// pass rebuilds it.
  void invalidateGraph() => mDependencyGraph.invalidateGraph();

  /// Invalidate the widgets' measures, so that the next dependency-graph pass
  /// measures them again.
  void invalidateMeasures() => mDependencyGraph.invalidateMeasures();

  /// Resolve the layout through the dependency graph alone, and return
  /// whether every widget resolved ([BasicMeasure.solverMeasure] solves the
  /// layout when not). [optimizeWrap] lets the graph compute wrap-content
  /// sizes itself.
  bool directMeasure(bool optimizeWrap) =>
      mDependencyGraph.directMeasure(optimizeWrap);

  /// Prepare a dependency-graph pass that resolves one axis at a time:
  /// rebuild the graph if it was invalidated and measure the children.
  /// Follow it with [directMeasureWithOrientation] for each axis, as
  /// [BasicMeasure.solverMeasure] does.
  bool directMeasureSetup(bool optimizeWrap) =>
      mDependencyGraph.directMeasureSetup(optimizeWrap);

  /// Resolve [orientation] ([ConstraintWidget.HORIZONTAL] or
  /// [ConstraintWidget.VERTICAL]) through the dependency graph after
  /// [directMeasureSetup], and return whether every run along that axis
  /// resolved.
  bool directMeasureWithOrientation(bool optimizeWrap, int orientation) =>
      mDependencyGraph.directMeasureWithOrientation(optimizeWrap, orientation);

  /// The index of the current measure pass; see [setPass]. [layout] runs the
  /// Direct pass only in pass 0.
  int mPass = 0;

  /// Keep track of the number of measure passes; [BasicMeasure] sets it
  /// before each solve.
  void setPass(int pass) {
    mPass = pass;
  }

  /// Where [layout] is, for tools that observe a measure (port only; the
  /// state Java's DirectProbe reads): -1 outside [layout], 0 inside it before
  /// its solver loop, then the loop's iteration (1 to 9) from the start of
  /// each iteration.
  int mCountSolve = -1;

  /// Record which children have a match-constraint axis and invalidate the
  /// dependency graph, after the children or their constraints changed
  /// ([BasicMeasure.updateHierarchy]). [measure] does it again itself.
  void updateHierarchy() {
    mBasicMeasureSolver.updateHierarchy(this);
  }

  /// Set the [Measurer] that measures the children's content, which [measure]
  /// requires. [layout] measures through it only in its Direct pass (the
  /// first pass at [Optimizer.OPTIMIZATION_DIRECT]); without one, that pass
  /// resolves only what needs no measure, as upstream's does. There is no
  /// default measurer, as upstream has none.
  void setMeasurer(Measurer? measurer) {
    mMeasurer = measurer;
    mDependencyGraph.setMeasurer(measurer);
  }

  /// The measurer set by [setMeasurer], or null.
  Measurer? getMeasurer() => mMeasurer;

  /// Set the optimization level: a mask of [Optimizer] flags,
  /// [Optimizer.OPTIMIZATION_STANDARD] by default. [layout] reads it; see
  /// [Optimizer] for where each flag applies.
  void setOptimizationLevel(int value) => mOptimizationLevel = value;

  /// Returns the current optimization level; see [setOptimizationLevel].
  int getOptimizationLevel() => mOptimizationLevel;

  /// Returns true if every flag of [feature] is set in the optimization
  /// level.
  bool optimizeFor(int feature) => (mOptimizationLevel & feature) == feature;

  /// Set the padding of this container.
  ///
  /// The left and top paddings offset the positions that
  /// [ConstraintWidget.getX] and [ConstraintWidget.getY] report for the
  /// children. The container's size is not reduced by any padding, and the
  /// right and bottom paddings are only stored.
  void setPadding(int left, int top, int right, int bottom) {
    mPaddingLeft = left;
    mPaddingTop = top;
    mPaddingRight = right;
    mPaddingBottom = bottom;
  }

  /// Set whether the layout is right-to-left, which affects chains (the
  /// rightmost widget heads a horizontal chain) and [Flow]. Anchors are not
  /// mirrored: left stays left.
  void setRtl(bool isRtl) => mIsRtl = isRtl;

  /// Returns true if the layout is right-to-left; see [setRtl].
  bool isRtl() => mIsRtl;

  /// Indicates if the container lays out its content on its own: false for
  /// a [ConstraintWidgetContainer].
  bool handlesInternalConstraints() => false;

  /// Copy the positions and sizes the dependency graph resolved into this
  /// container and then into each child; see
  /// [ConstraintWidget.updateFromRuns].
  @override
  void updateFromRuns(bool updateHorizontal, bool updateVertical) {
    super.updateFromRuns(updateHorizontal, updateVertical);
    for (final widget in mChildren) {
      widget.updateFromRuns(updateHorizontal, updateVertical);
    }
  }

  /// The measure passes behind [measure].
  late final BasicMeasure mBasicMeasureSolver = BasicMeasure(this);

  /// Measure the layout (upstream's measure, CWC 114-122): the entry
  /// Android's onMeasure uses. Sets the left and top padding to [paddingX]
  /// and [paddingY], then runs [BasicMeasure.solverMeasure]: it measures the
  /// children through the [Measurer] ([setMeasurer]; required as soon as the
  /// container has a child), runs [layout], and measures again, with up to
  /// two more [layout] passes, the children whose size depends on the result.
  ///
  /// The container's own dimension behaviours and size are the input: set
  /// them first. Every pass starts from the size the container has when
  /// [measure] is called. The modes and sizes ([BasicMeasure.EXACTLY] and
  /// the like) only take effect when [optimizationLevel] includes
  /// [Optimizer.OPTIMIZATION_GRAPH] or [Optimizer.OPTIMIZATION_GRAPH_WRAP],
  /// where the dependency graph may resolve the layout without the solver.
  /// [layout] runs at [getOptimizationLevel]; pass the same value as
  /// [optimizationLevel]. [lastMeasureWidth] and [lastMeasureHeight] are
  /// not read.
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

  /// Measure [widget] through [measurer] into [measure] with
  /// [measureStrategy], and copy the result onto [widget]: upstream's static
  /// `ConstraintWidgetContainer.measure(int, ConstraintWidget,
  /// BasicMeasure.Measurer, BasicMeasure.Measure, int)` (CWC 521-659),
  /// renamed because Dart has no overloads. Upstream's Direct pass and the
  /// measures that follow it measure through it.
  ///
  /// Unlike [BasicMeasure.measure], it converts the request first:
  ///
  /// * a spread match-constraint axis with fewer than two links
  ///   ([ConstraintWidget.hasDanglingDimension]) and no ratio is measured as
  ///   wrap content, or fixed at the widget's size when the other axis is
  ///   spread match constraint too;
  /// * an axis already resolved ([ConstraintWidget.isResolvedHorizontally],
  ///   [ConstraintWidget.isResolvedVertically]) is measured fixed at the
  ///   widget's size;
  /// * a match-constraint ratio axis whose other axis is not match
  ///   constraint is measured fixed at the ratio of the other axis (measured
  ///   first when it is not fixed), truncated as Java's `(int)` cast of the
  ///   float product or quotient truncates.
  ///
  /// [level] is upstream's debug indentation and is not read. Returns
  /// [Measure.measuredNeedsSolverPass]. Returns false without measuring when
  /// [measurer] is null; for a gone widget, a [Guideline] or a [Barrier] it
  /// reports 0 x 0 in [measure] and returns false, leaving [widget] and the
  /// other fields of [measure] unchanged.
  static bool measureWidget(
    int level,
    ConstraintWidget widget,
    Measurer? measurer,
    Measure measure,
    int measureStrategy,
  ) {
    if (measurer == null) {
      return false;
    }
    if (widget.getVisibility() == ConstraintWidget.GONE ||
        widget is Guideline ||
        widget is Barrier) {
      measure.measuredWidth = 0;
      measure.measuredHeight = 0;
      return false;
    }

    measure.horizontalBehavior = widget.getHorizontalDimensionBehaviour();
    measure.verticalBehavior = widget.getVerticalDimensionBehaviour();
    measure.horizontalDimension = widget.getWidth();
    measure.verticalDimension = widget.getHeight();
    measure.measuredNeedsSolverPass = false;
    measure.measureStrategy = measureStrategy;

    var horizontalMatchConstraints =
        measure.horizontalBehavior == DimensionBehaviour.matchConstraint;
    var verticalMatchConstraints =
        measure.verticalBehavior == DimensionBehaviour.matchConstraint;

    final horizontalUseRatio =
        horizontalMatchConstraints && widget.mDimensionRatio > 0;
    final verticalUseRatio =
        verticalMatchConstraints && widget.mDimensionRatio > 0;

    if (horizontalMatchConstraints &&
        widget.hasDanglingDimension(ConstraintWidget.HORIZONTAL) &&
        widget.mMatchConstraintDefaultWidth ==
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD &&
        !horizontalUseRatio) {
      horizontalMatchConstraints = false;
      measure.horizontalBehavior = DimensionBehaviour.wrapContent;
      if (verticalMatchConstraints &&
          widget.mMatchConstraintDefaultHeight ==
              ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
        // if match x match, size would be zero.
        measure.horizontalBehavior = DimensionBehaviour.fixed;
      }
    }

    if (verticalMatchConstraints &&
        widget.hasDanglingDimension(ConstraintWidget.VERTICAL) &&
        widget.mMatchConstraintDefaultHeight ==
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD &&
        !verticalUseRatio) {
      verticalMatchConstraints = false;
      measure.verticalBehavior = DimensionBehaviour.wrapContent;
      if (horizontalMatchConstraints &&
          widget.mMatchConstraintDefaultWidth ==
              ConstraintWidget.MATCH_CONSTRAINT_SPREAD) {
        // if match x match, size would be zero.
        measure.verticalBehavior = DimensionBehaviour.fixed;
      }
    }

    if (widget.isResolvedHorizontally()) {
      horizontalMatchConstraints = false;
      measure.horizontalBehavior = DimensionBehaviour.fixed;
    }
    if (widget.isResolvedVertically()) {
      verticalMatchConstraints = false;
      measure.verticalBehavior = DimensionBehaviour.fixed;
    }

    if (horizontalUseRatio) {
      if (widget.mResolvedMatchConstraintDefault[ConstraintWidget.HORIZONTAL] ==
          ConstraintWidget.MATCH_CONSTRAINT_RATIO_RESOLVED) {
        measure.horizontalBehavior = DimensionBehaviour.fixed;
      } else if (!verticalMatchConstraints) {
        // let's measure here
        int measuredHeight;
        if (measure.verticalBehavior == DimensionBehaviour.fixed) {
          measuredHeight = measure.verticalDimension;
        } else {
          measure.horizontalBehavior = DimensionBehaviour.wrapContent;
          measurer.measure(widget, measure);
          measuredHeight = measure.measuredHeight;
        }
        measure.horizontalBehavior = DimensionBehaviour.fixed;
        // regardless of which side we are using for the ratio,
        // getDimensionRatio() already made sure that it's expressed in WxH
        // format, so we can simply go and multiply: (int) (ratio * height),
        // in float.
        measure.horizontalDimension = jint(
          fmul(widget.getDimensionRatio(), fi(measuredHeight)),
        );
      }
    }
    if (verticalUseRatio) {
      if (widget.mResolvedMatchConstraintDefault[ConstraintWidget.VERTICAL] ==
          ConstraintWidget.MATCH_CONSTRAINT_RATIO_RESOLVED) {
        measure.verticalBehavior = DimensionBehaviour.fixed;
      } else if (!horizontalMatchConstraints) {
        // let's measure here
        int measuredWidth;
        if (measure.horizontalBehavior == DimensionBehaviour.fixed) {
          measuredWidth = measure.horizontalDimension;
        } else {
          measure.verticalBehavior = DimensionBehaviour.wrapContent;
          measurer.measure(widget, measure);
          measuredWidth = measure.measuredWidth;
        }
        measure.verticalBehavior = DimensionBehaviour.fixed;
        if (widget.getDimensionRatioSide() == -1) {
          // regardless of which side we are using for the ratio,
          // getDimensionRatio() already made sure that it's expressed in WxH
          // format, so we can simply go and divide: (int) (width / ratio).
          measure.verticalDimension = jint(
            fdiv(fi(measuredWidth), widget.getDimensionRatio()),
          );
        } else {
          // getDimensionRatio() already got reverted, so we can simply
          // multiply: (int) (ratio * width).
          measure.verticalDimension = jint(
            fmul(widget.getDimensionRatio(), fi(measuredWidth)),
          );
        }
      }
    }

    measurer.measure(widget, measure);
    widget.setWidth(measure.measuredWidth);
    widget.setHeight(measure.measuredHeight);
    widget.setHasBaseline(measure.measuredHasBaseline);
    widget.setBaselineDistance(measure.measuredBaseline);
    measure.measureStrategy = Measure.SELF_DIMENSIONS;
    return measure.measuredNeedsSolverPass;
  }

  /// One pass over the layout at [getOptimizationLevel]: upstream's layout()
  /// (CWC 667-1007).
  ///
  /// In the first measure pass ([mPass] 0, see [setPass]) at
  /// [Optimizer.OPTIMIZATION_DIRECT], it starts with upstream's Direct pass
  /// (analyzer/direct.dart): from the container's edges, the guidelines and
  /// the barriers, it gives final positions to every axis it can place
  /// directly and measures, through the [Measurer] ([setMeasurer]), each
  /// widget whose size it can know. Then it measures every child that still
  /// has a measure request, unless both of its axes are match constraints
  /// that are not wrap (guidelines, barriers, virtual layouts and their
  /// members excepted). The solver then pins what Direct resolved. Without a
  /// measurer nothing is measured, and Direct resolves only what needs no
  /// measure.
  ///
  /// Each iteration builds the system from the container and its children
  /// ([addChildrenToSolver]), minimizes it, and reads every frame back
  /// ([updateChildrenFromSolver]). The loop runs again, at most 9 times in
  /// all, while a frame records a size override ([ConstraintWidget.setFrame]),
  /// while the container's own min size raises its size, and once when a
  /// wrap-content axis of the container comes out larger than the size the
  /// pass started from: the axis is then held at that size, and
  /// [isWidthMeasuredTooSmall] or [isHeightMeasuredTooSmall] reports it.
  /// An exception thrown while the system is built or minimized is printed
  /// (`EXCEPTION : ...`) and the frames are read from what was solved, as
  /// upstream does.
  ///
  /// Outside the Direct pass it measures nothing: the children enter the
  /// solver with the sizes they have. [measure] measures them first and runs
  /// this pass up to three times, as Android's onMeasure does, the first one
  /// as pass 0. [measure] leaves [mPass] at its last pass, so a later call of
  /// this method on its own runs no Direct pass until [setPass] sets 0.
  ///
  /// As upstream, state carries from one call to the next: the final values
  /// the anchors hold (only a Direct pass resets them; a barrier also gives
  /// itself some in any pass), a size override the previous solve left
  /// pending, and the container's size.
  void layout() {
    if (kSolverTrace && getParent() == null) SolverTrace.pass(mPass);
    mCountSolve = 0;
    try {
      _solverPass();
    } finally {
      // The port's counter reads -1 outside layout(), even when an error
      // escapes the pass.
      mCountSolve = -1;
    }
  }

  /// The body of [layout] after its first two statements (CWC 675-1006).
  void _solverPass() {
    mX = 0;
    mY = 0;

    _widthMeasuredTooSmall = false;
    _heightMeasuredTooSmall = false;
    final count = mChildren.length;

    final preW = math.max(0, getWidth());
    final preH = math.max(0, getHeight());
    final originalVerticalDimensionBehaviour =
        mListDimensionBehaviors[ConstraintWidget.VERTICAL];
    final originalHorizontalDimensionBehaviour =
        mListDimensionBehaviors[ConstraintWidget.HORIZONTAL];

    var wrapOverride = false;

    // CWC 706-764: the Direct pass, in the first measure pass only, then a
    // measure of every child Direct left with a measure request.
    if (mPass == 0 &&
        Optimizer.enabled(mOptimizationLevel, Optimizer.OPTIMIZATION_DIRECT)) {
      Direct.solvingPass(this, getMeasurer());
      for (var i = 0; i < count; i++) {
        final child = mChildren[i];
        if (child.isMeasureRequested() &&
            child is! Guideline &&
            child is! Barrier &&
            child is! VirtualLayout &&
            !child.isInVirtualLayout()) {
          final widthBehavior = child.getDimensionBehaviour(
            ConstraintWidget.HORIZONTAL,
          );
          final heightBehavior = child.getDimensionBehaviour(
            ConstraintWidget.VERTICAL,
          );
          final skip =
              widthBehavior == DimensionBehaviour.matchConstraint &&
              child.mMatchConstraintDefaultWidth !=
                  ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
              heightBehavior == DimensionBehaviour.matchConstraint &&
              child.mMatchConstraintDefaultHeight !=
                  ConstraintWidget.MATCH_CONSTRAINT_WRAP;
          if (!skip) {
            // A new Measure per child (CWC 750), unlike Direct's last pass.
            final measure = Measure();
            measureWidget(
              0,
              child,
              mMeasurer,
              measure,
              Measure.SELF_DIMENSIONS,
            );
          }
        }
      }
    }

    // CWC 766-800: Grouping.simpleSolvingPass, at OPTIMIZATION_GROUPING, is
    // not ported.

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

    // Reset the chains before iterating on our children
    _resetChains();

    // Before we solve our system, we should call layout() on any of our
    // children that is a container (upstream: any WidgetContainer; only a
    // ConstraintWidgetContainer has layout() in this port).
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
      mCountSolve = countSolve;
      try {
        // The parity tools' Direct dump: the root's state after the Direct
        // block, at pass 0's first reset (the oracle's DirectProbe point).
        if (kSolverTrace &&
            getParent() == null &&
            mPass == 0 &&
            countSolve == 1 &&
            optimizeFor(Optimizer.OPTIMIZATION_DIRECT)) {
          SolverTrace.directDump(this);
        }
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
          if (kSolverTrace && getParent() == null) {
            SolverTrace.minimizeCall(mPass, countSolve);
          }
          mSystem.minimize();
        }
      } catch (e) {
        // Java catches Exception here. The Dart errors that stand for Java's
        // NullPointerException and ArrayIndexOutOfBoundsException must be
        // caught too, so this catches everything.
        if (kSolverTrace) SolverTrace.caught(e);
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

      // Upstream reads FLAG_RECOMPUTE_BOUNDS here, which
      // updateChildrenFromSolver always clears, so this block never runs.
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
            // force using the solver
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

      // "Measured too small": a wrap-content axis that came out larger than
      // the size the pass started from is held at that size, once per pass
      // (wrapOverride is never cleared in the loop).
      if (!wrapOverride) {
        if (mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] ==
                DimensionBehaviour.wrapContent &&
            preW > 0) {
          if (getWidth() > preW) {
            _widthMeasuredTooSmall = true;
            wrapOverride = true;
            mListDimensionBehaviors[ConstraintWidget.HORIZONTAL] =
                DimensionBehaviour.fixed;
            setWidth(preW);
            needsSolving = true;
          }
        }
        if (mListDimensionBehaviors[ConstraintWidget.VERTICAL] ==
                DimensionBehaviour.wrapContent &&
            preH > 0) {
          if (getHeight() > preH) {
            _heightMeasuredTooSmall = true;
            wrapOverride = true;
            mListDimensionBehaviors[ConstraintWidget.VERTICAL] =
                DimensionBehaviour.fixed;
            setHeight(preH);
            needsSolving = true;
          }
        }
      }

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

  /// Return true if the width given is too small for the content laid out:
  /// the last [layout] held its wrap-content width at the size it started
  /// from (the "measured too small" clamp).
  bool isWidthMeasuredTooSmall() => _widthMeasuredTooSmall;

  /// Return true if the height given is too small for the content laid out:
  /// the last [layout] held its wrap-content height at the size it started
  /// from (the "measured too small" clamp).
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

  /// The [LinearSystem] that [layout] solves.
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
