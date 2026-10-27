// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.widget.ConstraintLayout.Measurer
// (ConstraintLayout.java, "CL" below, lines 680-1039; upstream pinned in
// UPSTREAM.md): how the view layer of Android's ConstraintLayout measures each
// child for the core engine. The child view's own onMeasure is the one hook
// a host implements, [ViewMeasurer.measureContent]; everything else, from the
// specs to the cache and the answer, is upstream's.

import 'dart:math' as math;

import '../analyzer/basic_measure.dart';
import '../analyzer/direct.dart';
import '../constraint_widget.dart';
import '../constraint_widget_container.dart';
import '../jfloat.dart';
import '../optimizer.dart';
import '../virtual_layout.dart';
import 'measure_spec.dart';

/// ConstraintLayout's view `Measurer` (CL 678-1039): measures every child of
/// a layout as Android's view layer does, through one hook for the child
/// view's own `onMeasure`, [measureContent].
///
/// [measure] builds the child's measure specs from the request (by behaviour
/// and strategy, against the layout's own specs and padding that
/// [captureLayoutInfo] stored), answers from the cache when
/// [Optimizer.OPTIMIZATION_CACHE_MEASURES] allows it, measures the view, keeps
/// the size within the widget's match-constraint min and max (measuring
/// again when that changes a size), and writes the answer with Android's
/// baseline and `measuredNeedsSolverPass` rules. A subclass implements
/// [measureContent] only; it does not override [measure].
///
/// The measurer also keeps each child view's state, as a `View` keeps it
/// from one measure to the next: its last measured size and baseline, which
/// the strategies and the cache read, and `LayoutParams.mNeedsBaseline`.
/// [ViewHost] drives it; see there for the measure sequence.
abstract class ViewMeasurer implements Measurer {
  // captureLayoutInfo state (CL 680-701).

  /// The layout's top padding (`mPaddingTop`).
  int paddingTop = 0;

  /// The layout's bottom padding (`mPaddingBottom`).
  int paddingBottom = 0;

  /// The layout's horizontal padding, left plus right (`mPaddingWidth`).
  int paddingWidth = 0;

  /// The layout's vertical padding, top plus bottom (`mPaddingHeight`).
  int paddingHeight = 0;

  /// The width spec the layout itself is measured with, padding included
  /// (`mLayoutWidthSpec`).
  int layoutWidthSpec = 0;

  /// The height spec the layout itself is measured with, padding included
  /// (`mLayoutHeightSpec`).
  int layoutHeightSpec = 0;

  /// The layout view's optimization level (CL `mOptimizationLevel`), which
  /// [ViewHost.measure] sets. It decides CACHE_MEASURES (CL 844-872) and
  /// whether the ratio branch runs (CL 942-952, without DIRECT only).
  int optimizationLevel = Optimizer.OPTIMIZATION_STANDARD;

  /// Store the layout's own specs and padding (CL 689-701), as
  /// `resolveSystem` does before the engine measures anything.
  void captureLayoutInfo(
    int widthSpec,
    int heightSpec,
    int top,
    int bottom,
    int width,
    int height,
  ) {
    paddingTop = top;
    paddingBottom = bottom;
    paddingWidth = width;
    paddingHeight = height;
    layoutWidthSpec = widthSpec;
    layoutHeightSpec = heightSpec;
  }

  /// THE HOOK: the child view's `onMeasure` under [widthSpec] and
  /// [heightSpec] ([MeasureSpec] values). For the parity contract it is a
  /// pure function of the specs.
  ///
  /// Returns the view's measured width and height and its `getBaseline()`
  /// (-1 for none). The measurer keeps the sizes `& MEASURED_SIZE_MASK`, as
  /// `View.getMeasuredWidth` does. It is never called for a GONE widget (the
  /// GONE short cut answers), for a [VirtualLayout] (whose own
  /// [VirtualLayout.measure] the measurer runs), or for a widget that is
  /// spread match constraint on both axes under
  /// [Measure.SELF_DIMENSIONS] (not measured at all).
  ({int width, int height, int baseline}) measureContent(
    ConstraintWidget widget,
    int widthSpec,
    int heightSpec,
  );

  // ------------------------------------------------------------------------
  // The child views' state
  // ------------------------------------------------------------------------

  final Expando<_ViewState> _views = Expando<_ViewState>('view');

  _ViewState _viewOf(ConstraintWidget widget) =>
      _views[widget] ??= _ViewState();

  /// The child view's last measured width (`View.getMeasuredWidth`): the
  /// last measure's width `& MEASURED_SIZE_MASK`, or 0 before any.
  int measuredWidthOf(ConstraintWidget widget) =>
      (_views[widget]?.measuredWidth ?? 0) & MeasureSpec.MEASURED_SIZE_MASK;

  /// The child view's last measured height (`View.getMeasuredHeight`), or 0
  /// before any measure.
  int measuredHeightOf(ConstraintWidget widget) =>
      (_views[widget]?.measuredHeight ?? 0) & MeasureSpec.MEASURED_SIZE_MASK;

  /// The child view's baseline from its last measure (`View.getBaseline`), or
  /// -1 before any measure.
  int baselineOf(ConstraintWidget widget) => _views[widget]?.baseline ?? -1;

  /// Whether the child's layout params ask for its baseline
  /// (`LayoutParams.mNeedsBaseline`, CL 982).
  bool needsBaselineOf(ConstraintWidget widget) =>
      _views[widget]?.needsBaseline ?? false;

  /// Mark that the child's layout params ask for its baseline, as
  /// `setWidgetBaseline` does (CL 1598-1620). The flag is sticky: layout
  /// params keep it until the view is replaced ([forgetView]).
  void setNeedsBaseline(ConstraintWidget widget) {
    _viewOf(widget).needsBaseline = true;
  }

  /// Drop the state of [widget]'s view, as when a new view replaces it: its
  /// measured size goes back to 0 x 0, its baseline to -1, and its
  /// needs-baseline flag is cleared.
  void forgetView(ConstraintWidget widget) {
    _views[widget] = null;
  }

  // ------------------------------------------------------------------------
  // Request transcript and counters
  // ------------------------------------------------------------------------

  /// The measure-request transcript, or null (the default) to record none.
  ///
  /// While it is set, every completed [measure] call appends one entry,
  /// entries separated by one space:
  /// `<src>:<name>:<strategy>:<HB><VB>:<hdim>,<vdim>:<detail>:<mw>,<mh>,<mb>,<hasB><nsp>`.
  /// The request fields are taken on entry; the answer is what the measurer
  /// left in the [Measure]. `<src>` names the caller (`M` measureChildren,
  /// `R` the re-measure loop, `F` a [VirtualLayout] measuring a member, `D`
  /// Direct's last pass, `P` Direct's solving passes and the post-Direct
  /// measures, `X` any other), `<detail>`
  /// is `g` (GONE), `n` (no parent), `c` (cache hit), `s` (spread on both
  /// axes, not measured) or the specs of each view measure, two joined by
  /// `+`. A [VirtualLayout]'s member requests complete inside its own, so
  /// their entries come first. This is the T field of the parity oracle
  /// (VOpDriver's DirectProbe).
  StringBuffer? transcript;

  /// The number of [measure] calls since [beginMeasure].
  int measureCalls = 0;

  /// The number of CACHE_MEASURES hits since [beginMeasure].
  int cacheHits = 0;

  /// Clear the [transcript] and the counters. [ViewHost.measure] calls it
  /// first, so they describe its last call.
  void beginMeasure() {
    transcript?.clear();
    measureCalls = 0;
    cacheHits = 0;
  }

  /// The container of the widgets this measurer last measured, for the
  /// transcript's source of a widget that has no parent of its own.
  ConstraintWidgetContainer? _container;

  // ------------------------------------------------------------------------
  // Measurer
  // ------------------------------------------------------------------------

  /// Measure [widget] as [measure] requests: CL 709-996.
  ///
  /// Subclasses implement [measureContent] and do not override this.
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    measureCalls++;
    final t = transcript;
    if (t == null) {
      _measure(widget, measure, null);
      return;
    }
    // The request as it arrives. A VirtualLayout measures its members from
    // inside its own request, so these locals are the transcript's stack.
    final src = _sourceOf(widget, measure);
    final strategy = measure.measureStrategy;
    final horizontalBehavior = measure.horizontalBehavior;
    final verticalBehavior = measure.verticalBehavior;
    final horizontalDimension = measure.horizontalDimension;
    final verticalDimension = measure.verticalDimension;
    final detail = StringBuffer();
    _measure(widget, measure, detail);
    if (t.isNotEmpty) {
      t.write(' ');
    }
    t
      ..write(src)
      ..write(':')
      ..write(widget.getDebugName() ?? 'null')
      ..write(':')
      ..write(strategy)
      ..write(':')
      ..write(_behaviourLetter(horizontalBehavior))
      ..write(_behaviourLetter(verticalBehavior))
      ..write(':')
      ..write(horizontalDimension)
      ..write(',')
      ..write(verticalDimension)
      ..write(':')
      ..write(detail)
      ..write(':')
      ..write(measure.measuredWidth)
      ..write(',')
      ..write(measure.measuredHeight)
      ..write(',')
      ..write(measure.measuredBaseline)
      ..write(',')
      ..write(measure.measuredHasBaseline ? '1' : '0')
      ..write(measure.measuredNeedsSolverPass ? '1' : '0');
  }

  /// CL 709-996. [detail] collects the transcript's detail when recording.
  void _measure(
    ConstraintWidget widget,
    Measure measure,
    StringBuffer? detail,
  ) {
    // No Placeholder in the port, so no widget is in one.
    if (widget.getVisibility() == ConstraintWidget.GONE) {
      measure.measuredWidth = 0;
      measure.measuredHeight = 0;
      measure.measuredBaseline = 0;
      detail?.write('g');
      return;
    }
    if (widget.getParent() == null) {
      detail?.write('n');
      return;
    }

    // Java switches on the enum, which throws on null; so does the `!`.
    final horizontalBehavior = measure.horizontalBehavior!;
    final verticalBehavior = measure.verticalBehavior!;

    final horizontalDimension = measure.horizontalDimension;
    final verticalDimension = measure.verticalDimension;

    var horizontalSpec = 0;
    var verticalSpec = 0;

    final heightPadding = paddingTop + paddingBottom;
    final widthPadding = paddingWidth;

    // Port only, for speed: the child view's state is looked up once here.
    // [measuredWidthOf] and [measuredHeightOf] would look up the same
    // object again (it exists from here on, so their `?? 0` never applies),
    // so this method reads them from [child]: the same values.
    final child = _viewOf(widget);
    final strategy = measure.measureStrategy;
    final givenStrategy =
        strategy == Measure.TRY_GIVEN_DIMENSIONS ||
        strategy == Measure.USE_GIVEN_DIMENSIONS;

    switch (horizontalBehavior) {
      case DimensionBehaviour.fixed:
        horizontalSpec = MeasureSpec.makeMeasureSpec(
          horizontalDimension,
          MeasureSpec.EXACTLY,
        );
      case DimensionBehaviour.wrapContent:
        horizontalSpec = MeasureSpec.getChildMeasureSpec(
          layoutWidthSpec,
          widthPadding,
          BasicMeasure.WRAP_CONTENT,
        );
      case DimensionBehaviour.matchParent:
        // The horizontal spec must account for the margins as well as the
        // padding here.
        horizontalSpec = MeasureSpec.getChildMeasureSpec(
          layoutWidthSpec,
          widthPadding + widget.getHorizontalMargin(),
          BasicMeasure.MATCH_PARENT,
        );
      case DimensionBehaviour.matchConstraint:
        horizontalSpec = MeasureSpec.getChildMeasureSpec(
          layoutWidthSpec,
          widthPadding,
          BasicMeasure.WRAP_CONTENT,
        );
        final shouldDoWrap =
            widget.mMatchConstraintDefaultWidth ==
            ConstraintWidget.MATCH_CONSTRAINT_WRAP;
        if (givenStrategy) {
          // The solver gives the new dimension, but a wrap measured before
          // can be wrong if the other side was variable too, so check that
          // the other side is stable.
          final otherDimensionStable =
              (child.measuredHeight & MeasureSpec.MEASURED_SIZE_MASK) ==
              widget.getHeight();
          final useCurrent =
              strategy == Measure.USE_GIVEN_DIMENSIONS ||
              !shouldDoWrap ||
              (shouldDoWrap && otherDimensionStable) ||
              widget.isResolvedHorizontally();
          if (useCurrent) {
            horizontalSpec = MeasureSpec.makeMeasureSpec(
              widget.getWidth(),
              MeasureSpec.EXACTLY,
            );
          }
        }
    }

    switch (verticalBehavior) {
      case DimensionBehaviour.fixed:
        verticalSpec = MeasureSpec.makeMeasureSpec(
          verticalDimension,
          MeasureSpec.EXACTLY,
        );
      case DimensionBehaviour.wrapContent:
        verticalSpec = MeasureSpec.getChildMeasureSpec(
          layoutHeightSpec,
          heightPadding,
          BasicMeasure.WRAP_CONTENT,
        );
      case DimensionBehaviour.matchParent:
        // The vertical spec must account for the margins as well as the
        // padding here.
        verticalSpec = MeasureSpec.getChildMeasureSpec(
          layoutHeightSpec,
          heightPadding + widget.getVerticalMargin(),
          BasicMeasure.MATCH_PARENT,
        );
      case DimensionBehaviour.matchConstraint:
        verticalSpec = MeasureSpec.getChildMeasureSpec(
          layoutHeightSpec,
          heightPadding,
          BasicMeasure.WRAP_CONTENT,
        );
        final shouldDoWrap =
            widget.mMatchConstraintDefaultHeight ==
            ConstraintWidget.MATCH_CONSTRAINT_WRAP;
        if (givenStrategy) {
          final otherDimensionStable =
              (child.measuredWidth & MeasureSpec.MEASURED_SIZE_MASK) ==
              widget.getWidth();
          final useCurrent =
              strategy == Measure.USE_GIVEN_DIMENSIONS ||
              !shouldDoWrap ||
              (shouldDoWrap && otherDimensionStable) ||
              widget.isResolvedVertically();
          if (useCurrent) {
            verticalSpec = MeasureSpec.makeMeasureSpec(
              widget.getHeight(),
              MeasureSpec.EXACTLY,
            );
          }
        }
    }

    // CACHE_MEASURES (CL 844-872).
    final container = widget.getParent();
    if (container is ConstraintWidgetContainer &&
        Optimizer.enabled(
          optimizationLevel,
          Optimizer.OPTIMIZATION_CACHE_MEASURES,
        )) {
      final measuredWidth =
          child.measuredWidth & MeasureSpec.MEASURED_SIZE_MASK;
      final measuredHeight =
          child.measuredHeight & MeasureSpec.MEASURED_SIZE_MASK;
      if (measuredWidth == widget.getWidth() &&
          // The container check replicates legacy behaviour.
          measuredWidth < container.getWidth() &&
          measuredHeight == widget.getHeight() &&
          measuredHeight < container.getHeight() &&
          child.baseline == widget.getBaselineDistance() &&
          !widget.isMeasureRequested()) {
        final similar =
            _isSimilarSpec(
              widget.getLastHorizontalMeasureSpec(),
              horizontalSpec,
              widget.getWidth(),
            ) &&
            _isSimilarSpec(
              widget.getLastVerticalMeasureSpec(),
              verticalSpec,
              widget.getHeight(),
            );
        if (similar) {
          // The solver widget already has the view's size: no re-measure.
          // measuredHasBaseline and measuredNeedsSolverPass stay as the
          // caller left them.
          measure.measuredWidth = widget.getWidth();
          measure.measuredHeight = widget.getHeight();
          measure.measuredBaseline = widget.getBaselineDistance();
          cacheHits++;
          detail?.write('c');
          return;
        }
      }
    }

    final horizontalMatchConstraints =
        horizontalBehavior == DimensionBehaviour.matchConstraint;
    final verticalMatchConstraints =
        verticalBehavior == DimensionBehaviour.matchConstraint;

    final verticalDimensionKnown =
        verticalBehavior == DimensionBehaviour.matchParent ||
        verticalBehavior == DimensionBehaviour.fixed;
    final horizontalDimensionKnown =
        horizontalBehavior == DimensionBehaviour.matchParent ||
        horizontalBehavior == DimensionBehaviour.fixed;
    final horizontalUseRatio =
        horizontalMatchConstraints && widget.mDimensionRatio > 0;
    final verticalUseRatio =
        verticalMatchConstraints && widget.mDimensionRatio > 0;

    var width = 0;
    var height = 0;
    var baseline = 0;

    if (givenStrategy ||
        !(horizontalMatchConstraints &&
            widget.mMatchConstraintDefaultWidth ==
                ConstraintWidget.MATCH_CONSTRAINT_SPREAD &&
            verticalMatchConstraints &&
            widget.mMatchConstraintDefaultHeight ==
                ConstraintWidget.MATCH_CONSTRAINT_SPREAD)) {
      _measureView(widget, child, horizontalSpec, verticalSpec, detail);
      widget.setLastMeasureSpec(horizontalSpec, verticalSpec);

      final w = child.measuredWidth & MeasureSpec.MEASURED_SIZE_MASK;
      final h = child.measuredHeight & MeasureSpec.MEASURED_SIZE_MASK;
      baseline = child.baseline;

      width = w;
      height = h;

      // The match-constraint min and max bound every measure, whatever the
      // behaviour.
      if (widget.mMatchConstraintMinWidth > 0) {
        width = math.max(widget.mMatchConstraintMinWidth, width);
      }
      if (widget.mMatchConstraintMaxWidth > 0) {
        width = math.min(widget.mMatchConstraintMaxWidth, width);
      }
      if (widget.mMatchConstraintMinHeight > 0) {
        height = math.max(widget.mMatchConstraintMinHeight, height);
      }
      if (widget.mMatchConstraintMaxHeight > 0) {
        height = math.min(widget.mMatchConstraintMaxHeight, height);
      }

      final optimizeDirect = Optimizer.enabled(
        optimizationLevel,
        Optimizer.OPTIMIZATION_DIRECT,
      );
      if (!optimizeDirect) {
        if (horizontalUseRatio && verticalDimensionKnown) {
          final ratio = widget.mDimensionRatio;
          // (int) (0.5f + height * ratio)
          width = jint(fadd(0.5, fmul(fi(height), ratio)));
        } else if (verticalUseRatio && horizontalDimensionKnown) {
          final ratio = widget.mDimensionRatio;
          // (int) (0.5f + width / ratio)
          height = jint(fadd(0.5, fdiv(fi(width), ratio)));
        }
      }

      if (w != width || h != height) {
        if (w != width) {
          horizontalSpec = MeasureSpec.makeMeasureSpec(
            width,
            MeasureSpec.EXACTLY,
          );
        }
        if (h != height) {
          verticalSpec = MeasureSpec.makeMeasureSpec(
            height,
            MeasureSpec.EXACTLY,
          );
        }
        _measureView(widget, child, horizontalSpec, verticalSpec, detail);
        widget.setLastMeasureSpec(horizontalSpec, verticalSpec);
        // Not clamped again.
        width = child.measuredWidth & MeasureSpec.MEASURED_SIZE_MASK;
        height = child.measuredHeight & MeasureSpec.MEASURED_SIZE_MASK;
        baseline = child.baseline;
      }
    } else {
      // Spread match constraints on both axes under SELF_DIMENSIONS: the
      // solver sizes the widget, which is not measured (0 x 0).
      detail?.write('s');
    }

    var hasBaseline = baseline != -1;

    measure.measuredNeedsSolverPass =
        width != measure.horizontalDimension ||
        height != measure.verticalDimension;
    if (child.needsBaseline) {
      hasBaseline = true;
    }
    if (hasBaseline &&
        baseline != -1 &&
        widget.getBaselineDistance() != baseline) {
      measure.measuredNeedsSolverPass = true;
    }
    measure.measuredWidth = width;
    measure.measuredHeight = height;
    measure.measuredHasBaseline = hasBaseline;
    measure.measuredBaseline = baseline;
  }

  /// `child.measure(horizontalSpec, verticalSpec)` (CL 904-911, 961): a
  /// [VirtualLayout]'s view runs the layout's own measure (the view Flow's
  /// `onMeasure`, which reports no baseline); any other view measures its
  /// content through [measureContent].
  void _measureView(
    ConstraintWidget widget,
    _ViewState child,
    int horizontalSpec,
    int verticalSpec,
    StringBuffer? detail,
  ) {
    if (detail != null) {
      if (detail.isNotEmpty) {
        detail.write('+');
      }
      detail
        ..write(MeasureSpec.toShortString(horizontalSpec))
        ..write('/')
        ..write(MeasureSpec.toShortString(verticalSpec));
    }
    if (widget is VirtualLayout) {
      widget.measure(
        MeasureSpec.getMode(horizontalSpec),
        MeasureSpec.getSize(horizontalSpec),
        MeasureSpec.getMode(verticalSpec),
        MeasureSpec.getSize(verticalSpec),
      );
      child
        ..measuredWidth = widget.getMeasuredWidth()
        ..measuredHeight = widget.getMeasuredHeight()
        ..baseline = -1;
      return;
    }
    final content = measureContent(widget, horizontalSpec, verticalSpec);
    child
      ..measuredWidth = content.width
      ..measuredHeight = content.height
      ..baseline = content.baseline;
  }

  /// Whether the previous measure spec is equivalent to the new one: the
  /// same spec, or an EXACTLY spec of the widget's size after an AT_MOST or
  /// UNSPECIFIED one (CL 1009-1019).
  static bool _isSimilarSpec(int lastMeasureSpec, int spec, int widgetSize) {
    if (lastMeasureSpec == spec) {
      return true;
    }
    final lastMode = MeasureSpec.getMode(lastMeasureSpec);
    final mode = MeasureSpec.getMode(spec);
    final size = MeasureSpec.getSize(spec);
    return mode == MeasureSpec.EXACTLY &&
        (lastMode == MeasureSpec.AT_MOST ||
            lastMode == MeasureSpec.UNSPECIFIED) &&
        widgetSize == size;
  }

  /// Placeholders' and helpers' `updatePostMeasure` (CL 1022-1038). The port
  /// has none, so this does nothing.
  @override
  void didMeasures() {}

  /// The caller of a [measure] call, from the identity of its [Measure], as
  /// the oracle's DirectProbe tells it, in the same order: Direct's static
  /// [Direct.sMeasure] first (`D`, its last pass), then BasicMeasure's own
  /// Measure, a [VirtualLayout]'s, and a new Measure in pass 0 before the
  /// solver loop (`P`: Direct's solving passes and the post-Direct measures).
  String _sourceOf(ConstraintWidget widget, Measure measure) {
    final parent = widget.getParent();
    if (parent is ConstraintWidgetContainer) {
      _container = parent;
    }
    if (identical(measure, Direct.sMeasure)) {
      return 'D';
    }
    final container = _container;
    if (container == null) {
      return 'X';
    }
    if (identical(measure, container.mBasicMeasureSolver.mMeasure)) {
      // measureChildren always asks for SELF_DIMENSIONS (BM 140), the
      // re-measure loop for TRY_GIVEN or USE_GIVEN (BM 326, 377-381).
      return measure.measureStrategy == Measure.SELF_DIMENSIONS ? 'M' : 'R';
    }
    final children = container.mChildren;
    for (var i = 0; i < children.length; i++) {
      final c = children[i];
      if (c is VirtualLayout && identical(c.mMeasure, measure)) {
        return 'F';
      }
    }
    if (container.mPass == 0 && container.mCountSolve == 0) {
      return 'P';
    }
    return 'X';
  }

  static String _behaviourLetter(DimensionBehaviour? behaviour) =>
      switch (behaviour) {
        DimensionBehaviour.fixed => 'F',
        DimensionBehaviour.wrapContent => 'W',
        DimensionBehaviour.matchConstraint => 'M',
        DimensionBehaviour.matchParent => 'P',
        null => '?',
      };
}

/// The state a child `View` keeps between measures.
final class _ViewState {
  /// `setMeasuredDimension`'s width, as stored (read `& MEASURED_SIZE_MASK`).
  int measuredWidth = 0;

  /// `setMeasuredDimension`'s height, as stored.
  int measuredHeight = 0;

  /// `getBaseline()` after the last measure: -1 for none.
  int baseline = -1;

  /// `LayoutParams.mNeedsBaseline`.
  bool needsBaseline = false;
}
