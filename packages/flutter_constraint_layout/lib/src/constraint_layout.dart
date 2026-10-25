import 'dart:math' as math;

import 'package:constraint_engine/constraint_engine.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/rendering.dart';
// The engine also declares a class named Flow (the virtual layout).
import 'package:flutter/widgets.dart' hide Flow;

import 'constraint_parent_data.dart';
import 'debug/debug_extractor.dart';
import 'debug/debug_painter.dart';
import 'debug/debug_palette.dart';
import 'debug/debug_scene.dart';
import 'dimension.dart';
import 'link.dart';
import 'types.dart';

/// Refers to the [ConstraintLayout] container itself when used as an anchor
/// target, for example `top: .topOf(parent)`.
const Symbol parent = #parent;

/// A layout that positions its children using constraint anchors, inspired by
/// Android's ConstraintLayout.
///
/// Wrap each child in a `Constrained` to describe how it is positioned and
/// sized relative to [parent] or to sibling ids. Positions are resolved by the
/// pure-Dart dependency-graph engine in `package:constraint_engine`.
class ConstraintLayout extends MultiChildRenderObjectWidget {
  /// Whether [debugShowChains] and [debugShowBlueprint] are honored at all.
  ///
  /// Defaults to [kDebugMode], so the design-surface and blueprint overlays are
  /// active in debug builds and inert in profile and release. Set it to true
  /// (e.g. in `main`) to force the overlays on in a release build, for a demo,
  /// a design review, or this package's own docs site:
  ///
  /// ```dart
  /// ConstraintLayout.allowDebugFlags = true;
  /// ```
  ///
  /// Note: enabling this keeps the debug-overlay rendering code in the release
  /// binary. Leave it at the default if you want that code tree-shaken away.
  static bool allowDebugFlags = kDebugMode;

  /// Creates a constraint layout.
  ///
  /// [textDirection] resolves `start`/`end` edges to left/right. When omitted,
  /// the ambient [Directionality] is used, falling back to [TextDirection.ltr].
  const ConstraintLayout({
    super.key,
    this.textDirection,
    this.debugShowChains = false,
    this.debugShowBlueprint = false,
    this.debugChainColor,
    this.debugBlueprintLabelStyle = DebugLabelStyle.both,
    super.children,
  });

  /// Resolves `start`/`end` links. Defaults to the ambient [Directionality].
  final TextDirection? textDirection;

  /// Paints an Android Studio design-surface overlay on top of the children:
  /// constraint connections, chain links, springs, margin values, anchors,
  /// guidelines, and barriers.
  ///
  /// Honored in debug builds, and in profile/release only when
  /// [allowDebugFlags] is set; otherwise a no-op.
  final bool debugShowChains;

  /// Replaces the children with Android Studio blueprint mode: a dark surface
  /// with a framed translucent box per child, labels, and the same
  /// constraint/chain drawing as [debugShowChains]. Children are still laid
  /// out and hit-testable, just not painted.
  ///
  /// Takes precedence over [debugShowChains] when both are set. Honored in
  /// debug builds, and in profile/release only when [allowDebugFlags] is set;
  /// otherwise a no-op.
  final bool debugShowBlueprint;

  /// Tints every overlay line (constraints, chains, springs, guidelines,
  /// barriers, frames); anchors and labels derive shades from it. When null,
  /// the authentic Android Studio palette is used.
  final Color? debugChainColor;

  /// What text [debugShowBlueprint] draws inside each widget box.
  final DebugLabelStyle debugBlueprintLabelStyle;

  TextDirection _resolveDirection(BuildContext context) =>
      textDirection ?? Directionality.maybeOf(context) ?? TextDirection.ltr;

  @override
  RenderConstraintLayout createRenderObject(BuildContext context) {
    return RenderConstraintLayout(
      textDirection: _resolveDirection(context),
      debugShowChains: debugShowChains,
      debugShowBlueprint: debugShowBlueprint,
      debugChainColor: debugChainColor,
      debugBlueprintLabelStyle: debugBlueprintLabelStyle,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderConstraintLayout renderObject,
  ) {
    renderObject
      ..textDirection = _resolveDirection(context)
      ..debugShowChains = debugShowChains
      ..debugShowBlueprint = debugShowBlueprint
      ..debugChainColor = debugChainColor
      ..debugBlueprintLabelStyle = debugBlueprintLabelStyle;
  }
}

/// The render object backing [ConstraintLayout].
///
/// Keeps a persistent engine model (one `ConstraintWidget` per child plus the
/// container) alive across layout passes and keeps it in sync incrementally:
///
///  * Child list changes (insert/remove/move), id renames, and text-direction
///    changes rebuild the model.
///  * Other `Constrained` config changes are applied to the affected engine
///    widgets in place. A `ConstraintGroup`'s visibility reaches each child
///    it references the way a change of the child's own visibility would.
///  * When nothing layout-affecting changed and no child's size can depend on
///    its content, a re-layout under identical constraints skips the engine
///    entirely and reuses the resolved geometry.
///
/// Every engine pass resolves through `container.layout()`, the same code path
/// a freshly built model uses, so incremental updates cannot drift from a
/// from-scratch layout.
///
/// ## Dry layout, intrinsic sizes, and baseline
///
/// [getDryLayout] returns the size [performLayout] gives the layout under the
/// same constraints. On a bounded axis that is the maximum, whatever the
/// children. On an unbounded axis it comes from an engine pass over a
/// throwaway model of the children, which measures each child with its own
/// [RenderBox.getDryLayout] (and [RenderBox.getDryBaseline] for baseline
/// links) instead of laying it out. So a dry query lays out no child and
/// leaves the persistent model untouched, and costs about as much as a layout
/// that has to run the engine.
///
/// The intrinsic sizes are defined by that dry layout:
///
///  * [getMaxIntrinsicWidth] for a height is the width of the dry layout with
///    an unbounded width and, when the height is finite, that height as a
///    tight constraint: the width the layout wraps its children to.
///    [getMaxIntrinsicHeight] is the same on the other axis.
///  * [getMinIntrinsicWidth] runs the same pass, but measures each child that
///    sizes to its content horizontally at no more than the child's own
///    minimum intrinsic width, so wrapping text counts its longest word rather
///    than its whole line. It is never more than the maximum.
///    [getMinIntrinsicHeight] is the same on the other axis.
///
/// A child that cannot compute a dry layout (a `LayoutBuilder`, for one)
/// throws when asked in a debug build. The layout reports that error and
/// measures the child at the smallest size its constraints allow, so the
/// query still returns a size. A child with tight constraints is never asked:
/// its size is already known.
///
/// The layout's baseline is the highest (smallest) baseline among its visible
/// children, measured from the layout's top, as a [Stack]'s is. Invisible and
/// gone children, and helpers (guidelines, barriers, flows, and grids), do not
/// count, and without a child that has a baseline the layout has none.
/// Android's ConstraintLayout reports no baseline of its own.
class RenderConstraintLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, ConstraintParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, ConstraintParentData> {
  /// Creates the render object with the given [textDirection].
  //
  // The fields are private and the parameters are public, so initializing
  // formals cannot be used here.
  RenderConstraintLayout({
    required TextDirection textDirection,
    bool debugShowChains = false,
    bool debugShowBlueprint = false,
    Color? debugChainColor,
    DebugLabelStyle debugBlueprintLabelStyle = DebugLabelStyle.both,
  })
    // ignore: prefer_initializing_formals
    : _textDirection = textDirection,
       // ignore: prefer_initializing_formals
       _debugShowChains = debugShowChains,
       // ignore: prefer_initializing_formals
       _debugShowBlueprint = debugShowBlueprint,
       // ignore: prefer_initializing_formals
       _debugChainColor = debugChainColor,
       _debugLabelStyle = debugBlueprintLabelStyle;

  TextDirection _textDirection;

  /// The direction used to resolve `start`/`end` edges.
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    // start/end resolution is baked into the engine connections, and the
    // mirrored horizontal bias and vertical guideline positions of a
    // right-to-left layout into the engine widgets.
    _needsModelRebuild = true;
    markNeedsLayout();
  }

  bool get _ltr => _textDirection != TextDirection.rtl;

  // Debug-overlay configuration. Paint-only: the setters never touch the
  // layout or the persistent engine model, and the overlay itself is gated by
  // ConstraintLayout.allowDebugFlags (see paint), so these are inert unless
  // that flag is set (which it is by default only in debug builds).
  bool _debugShowChains;
  bool _debugShowBlueprint;
  Color? _debugChainColor;
  DebugLabelStyle _debugLabelStyle;

  /// Whether the design-surface overlay is painted over the children.
  set debugShowChains(bool value) {
    if (_debugShowChains == value) return;
    _debugShowChains = value;
    markNeedsPaint();
  }

  /// Whether blueprint mode replaces the children's painting.
  set debugShowBlueprint(bool value) {
    if (_debugShowBlueprint == value) return;
    _debugShowBlueprint = value;
    markNeedsPaint();
  }

  /// The overlay tint; null means the authentic Android Studio palette.
  set debugChainColor(Color? value) {
    if (_debugChainColor == value) return;
    _debugChainColor = value;
    markNeedsPaint();
  }

  /// What text blueprint mode draws inside each widget box.
  set debugBlueprintLabelStyle(DebugLabelStyle value) {
    if (_debugLabelStyle == value) return;
    _debugLabelStyle = value;
    markNeedsPaint();
  }

  // Persistent engine model, kept in sync with the children across layouts.
  // Non-null whenever _needsModelRebuild is false.
  _EngineModel? _model;
  _FlutterMeasurer? _measurer;
  bool _needsModelRebuild = true;
  BoxConstraints? _lastConstraints;

  /// Number of [performLayout] executions. Test instrumentation.
  @visibleForTesting
  int debugLayoutPasses = 0;

  /// Number of full engine-model rebuilds. Test instrumentation.
  @visibleForTesting
  int debugModelBuilds = 0;

  /// Number of layouts that resolved through the engine. Test instrumentation.
  @visibleForTesting
  int debugEnginePasses = 0;

  /// Number of layouts that reused resolved geometry without running the
  /// engine. Test instrumentation.
  @visibleForTesting
  int debugFastPasses = 0;

  /// Number of children whose config was re-applied to the persistent model
  /// in place. Test instrumentation.
  @visibleForTesting
  int debugConfigApplies = 0;

  /// The persistent engine container, for probing which engine resolved the
  /// last layout: on a freshly built model, `mSystem.getNumVariables()` is
  /// non-zero only if that layout ran the solver. The row count is no proof,
  /// because a solve can end with no rows, and `mSystem` keeps its state until
  /// the next solve, so a later layout of the same model on the graph still
  /// shows the earlier solve. Test instrumentation.
  @visibleForTesting
  ConstraintWidgetContainer? get debugEngineContainer => _model?.container;

  /// Builds the debug-overlay scene from the current engine state.
  ///
  /// Exposed for tests; also used by [paint] when a debug flag is set. Only
  /// valid after a layout pass.
  @visibleForTesting
  DebugScene debugDescribeScene() {
    final model = _model!;
    return buildDebugScene(
      container: model.container,
      widgets: model.widgets,
      parentData: model.childData,
      children: model.children,
    );
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ConstraintParentData) {
      child.parentData = ConstraintParentData();
    }
  }

  @override
  void insert(RenderBox child, {RenderBox? after}) {
    _needsModelRebuild = true;
    super.insert(child, after: after);
  }

  @override
  void remove(RenderBox child) {
    _needsModelRebuild = true;
    super.remove(child);
  }

  @override
  void removeAll() {
    _needsModelRebuild = true;
    super.removeAll();
  }

  @override
  void move(RenderBox child, {RenderBox? after}) {
    _needsModelRebuild = true;
    super.move(child, after: after);
  }

  void _discardModel() {
    _model = null;
    _measurer = null;
    _needsModelRebuild = true;
    _lastConstraints = null;
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    debugLayoutPasses++;

    if (childCount == 0) {
      _discardModel();
      size = constraints.smallest;
      return;
    }

    // Sweep the child list for per-child dirt. insert/remove/move already set
    // _needsModelRebuild; verifying list identity here is defence in depth so
    // a missed structural signal degrades to a rebuild, never to stale layout.
    var anyConfigDirty = false;
    var anyGroupDirty = false;
    if (!_needsModelRebuild) {
      final modelChildren = _model!.children;
      var i = 0;
      RenderBox? child = firstChild;
      while (child != null) {
        final pd = child.parentData! as ConstraintParentData;
        if (i >= modelChildren.length ||
            !identical(modelChildren[i], child) ||
            pd.structuralDirty) {
          _needsModelRebuild = true;
          break;
        }
        if (pd.configDirty) {
          anyConfigDirty = true;
          if (pd.helperKind == HelperKind.group) {
            anyGroupDirty = true;
          }
        }
        child = pd.nextSibling;
        i++;
      }
      if (!_needsModelRebuild && i != modelChildren.length) {
        _needsModelRebuild = true;
      }
    }
    if (!_needsModelRebuild && anyGroupDirty) {
      _passGroupChangesToMembers(_model!);
    }

    // Fast path: nothing layout-affecting changed, the incoming constraints
    // are identical, and no child's size or position can depend on its
    // content (no wrap/underconstrained-match dimensions, no baselines).
    // The resolved geometry is then still exact; skip the engine and re-place.
    // Children are still laid out so an independently dirty child re-layouts
    // within its unchanged tight size.
    if (!_needsModelRebuild &&
        !anyConfigDirty &&
        _lastConstraints == constraints &&
        !_model!.hasContentDependentChild &&
        _model!.needsBaseline.isEmpty) {
      debugFastPasses++;
      final model = _model!;
      for (var i = 0; i < model.children.length; i++) {
        final w = model.widgets[i];
        model.children[i].layout(BoxConstraints.tight(_placedSize(w)));
        model.childData[i].offset = Offset(
          w.getX().toDouble(),
          w.getY().toDouble(),
        );
      }
      size = _resolvedSize(model.container, constraints);
      return;
    }

    if (_needsModelRebuild) {
      _buildModel(constraints);
      debugModelBuilds++;
    } else if (anyConfigDirty) {
      final model = _model!;
      // Set until every change is applied. Applying one can throw (an
      // unknown id, in a debug build) after resetting its widget, and as in
      // _buildModel, the half-applied model must not stay behind looking
      // clean: the next layout rebuilds and reports the problem again.
      _needsModelRebuild = true;
      // Derived state must be recomputed before connects are re-applied:
      // baseline connects only validate when both endpoints are already
      // marked baseline-capable (see _computeDerivedState).
      _computeDerivedState(model);
      _publishGroupOverrides(model);
      for (var i = 0; i < model.children.length; i++) {
        final pd = model.childData[i];
        if (!pd.configDirty) continue;
        pd.configDirty = false;
        _applyWidgetConfig(model, model.widgets[i], pd);
        debugConfigApplies++;
      }
      _reportLinkLoop(model);
      _needsModelRebuild = false;
    }
    final model = _model!;

    // Normalize stored sizes before every engine pass: a fresh widget enters
    // the engine with 0 on any non-fixed axis, but a persistent widget can
    // carry a size written by a previous pass (notably the solver fallback's
    // wrap re-measure of underconstrained matchConstraint children). The
    // graph feeds stored sizes back as measure hints, so a leaked size would
    // change the result relative to a freshly built model. Positions are
    // reset to a fresh widget's (0, 0) for the same reason: a position the
    // previous pass resolved is the engine's input on an axis nothing
    // anchors, such as a widget a flow places, and where a layout has more
    // than one solution (a match-constraint flow between the edges of a
    // wrapping axis) it decides which one the solver lands on.
    for (var i = 0; i < model.widgets.length; i++) {
      final pd = model.childData[i];
      if (pd.helperKind != HelperKind.none) continue;
      final w = model.widgets[i];
      if (pd.width is! FixedDimension) w.setWidth(0);
      if (pd.height is! FixedDimension) w.setHeight(0);
      w.setX(0);
      w.setY(0);
      // The baseline too, to a fresh widget's: distance 0, flagged only for
      // the endpoints of baseline links (as _computeDerivedState seeds them).
      // The graph does not measure a gone widget, so a baseline target that
      // turned gone in place would otherwise keep the baseline of its last
      // measure, and a widget baseline-linked to it would sit where a fresh
      // model (and Android, which resets every widget on a hierarchy change
      // and measures a gone view with baseline 0) does not put it.
      w.setBaselineDistance(0);
      w.setHasBaseline(model.needsBaseline.contains(w));
    }

    final container = model.container;
    _prepareContainer(container, constraints);

    // Resolve the graph, measuring intrinsic child sizes through
    // RenderBox.layout.
    final measurer = _measurer!;
    measurer.beginPass(constraints);
    debugEnginePasses++;
    container.layout();

    // Place and size each child from the resolved coordinates.
    for (var i = 0; i < model.children.length; i++) {
      final w = model.widgets[i];
      final rb = model.children[i];
      final relayout = _placementConstraints(w, measurer.laidOut[w]);
      if (relayout != null) {
        rb.layout(relayout);
      }
      // A capped child can need tight constraints on both axes. Flutter then
      // makes it a relayout boundary, even though its next content change can
      // change the size this container resolves for it. A baseline query
      // establishes a layout dependency across that boundary (including when
      // there is no real baseline), so the change still re-runs the engine.
      // Fixed-size children keep their independent relayout boundaries.
      if (rb.constraints.isTight && _isContentDependent(model.childData[i])) {
        rb.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true);
      }
      model.childData[i].offset = Offset(
        w.getX().toDouble(),
        w.getY().toDouble(),
      );
    }

    _lastConstraints = constraints;
    size = _resolvedSize(container, constraints);
  }

  /// Sets [container] up as the root of an engine pass under [constraints].
  ///
  /// The root mirrors the incoming constraints: a bounded axis is fixed at its
  /// maximum (the layout fills the space it is given, even when the
  /// constraints are loose), and an unbounded axis wraps the children.
  void _prepareContainer(
    ConstraintWidgetContainer container,
    BoxConstraints constraints,
  ) {
    final boundedW = constraints.hasBoundedWidth;
    final boundedH = constraints.hasBoundedHeight;
    container.setRtl(!_ltr);
    container.setHorizontalDimensionBehaviour(
      boundedW ? DimensionBehaviour.fixed : DimensionBehaviour.wrapContent,
    );
    container.setVerticalDimensionBehaviour(
      boundedH ? DimensionBehaviour.fixed : DimensionBehaviour.wrapContent,
    );
    container.setWidth(boundedW ? constraints.maxWidth.round() : 0);
    container.setHeight(boundedH ? constraints.maxHeight.round() : 0);
  }

  /// The layout's size once an engine pass prepared by [_prepareContainer]
  /// has resolved [container].
  static Size _resolvedSize(
    ConstraintWidgetContainer container,
    BoxConstraints constraints,
  ) => constraints.constrain(
    Size(container.getWidth().toDouble(), container.getHeight().toDouble()),
  );

  /// The constraints that place the child of [w] at the size the engine
  /// resolved for it, or null when its latest [measured] layout from the
  /// engine pass already has (effectively) that size.
  ///
  /// That layout is then kept instead of forcing a tight one: the measure
  /// pass uses loose constraints on wrap axes, which leaves the child a
  /// non-boundary so a later content change propagates back here and
  /// triggers re-resolution.
  static BoxConstraints? _placementConstraints(
    ConstraintWidget w,
    _MeasuredLayout? measured,
  ) {
    final placed = _placedSize(w);
    if (measured != null &&
        (measured.size.width - placed.width).abs() < 1 &&
        (measured.size.height - placed.height).abs() < 1) {
      return null;
    }
    return BoxConstraints.tight(placed);
  }

  /// The size a child is placed at: the size the engine resolved for its
  /// widget [w], except that a negative size (margins that add up to more
  /// than the space between two anchors) places it at a size of 0.
  static Size _placedSize(ConstraintWidget w) => Size(
    math.max(0, w.getWidth()).toDouble(),
    math.max(0, w.getHeight()).toDouble(),
  );

  @override
  @protected
  Size computeDryLayout(covariant BoxConstraints constraints) {
    if (childCount == 0) return constraints.smallest;
    // A bounded axis is fixed at its maximum whatever the children (see
    // _prepareContainer), so only an unbounded axis needs an engine pass.
    if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
      return constraints.constrain(
        Size(
          constraints.maxWidth.round().toDouble(),
          constraints.maxHeight.round().toDouble(),
        ),
      );
    }
    final resolved = _resolveDry(constraints);
    if (resolved == null) return constraints.smallest;
    return _resolvedSize(resolved.model.container, constraints);
  }

  @override
  @protected
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    if (childCount == 0) return null;
    final resolved = _resolveDry(constraints);
    if (resolved == null) return null;
    final (:model, :measurer) = resolved;
    var result = BaselineOffset.noBaseline;
    for (var i = 0; i < model.children.length; i++) {
      if (!_contributesBaseline(model, model.childData[i])) continue;
      final w = model.widgets[i];
      // The constraints the child ends up with after the placement pass of
      // performLayout, where its baseline is read.
      final measured = measurer.laidOut[w];
      final placed =
          _placementConstraints(w, measured) ?? measured!.constraints;
      final childBaseline = measurer.dryBaseline(
        model.children[i],
        placed,
        baseline,
      );
      result = result.minOf(
        BaselineOffset(childBaseline) + w.getY().toDouble(),
      );
    }
    return result.offset;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    // Without a model the last pass placed no child: there were none, or (in
    // a debug build) an unknown id abandoned the pass before any was laid
    // out.
    final model = _model;
    if (model == null) return null;
    var result = BaselineOffset.noBaseline;
    for (var i = 0; i < model.children.length; i++) {
      final pd = model.childData[i];
      if (!_contributesBaseline(model, pd)) continue;
      result = result.minOf(
        BaselineOffset(
              model.children[i].getDistanceToActualBaseline(baseline),
            ) +
            pd.offset.dy,
      );
    }
    return result.offset;
  }

  /// Whether the child with parent data [pd] takes part in the baseline of a
  /// layout resolved as [model]: a visible content child, not an invisible or
  /// gone one (by its own visibility or its group's), and not a helper.
  static bool _contributesBaseline(
    _EngineModel model,
    ConstraintParentData pd,
  ) =>
      pd.helperKind == HelperKind.none &&
      model.visibilityOf(pd) == ConstraintVisibility.visible;

  @override
  double computeMinIntrinsicWidth(double height) => math.min(
    _minimumIntrinsicExtent(Axis.horizontal, height),
    computeMaxIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      computeDryLayout(_intrinsicConstraints(Axis.horizontal, height)).width;

  @override
  double computeMinIntrinsicHeight(double width) => math.min(
    _minimumIntrinsicExtent(Axis.vertical, width),
    computeMaxIntrinsicHeight(width),
  );

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeDryLayout(_intrinsicConstraints(Axis.vertical, width)).height;

  /// The constraints of an intrinsic query along [axis]: unbounded on [axis],
  /// so the layout wraps its children there, and tight at [crossExtent] on the
  /// other axis when that is finite.
  static BoxConstraints _intrinsicConstraints(Axis axis, double crossExtent) {
    if (!crossExtent.isFinite) return const BoxConstraints();
    return switch (axis) {
      Axis.horizontal => BoxConstraints.tightFor(height: crossExtent),
      Axis.vertical => BoxConstraints.tightFor(width: crossExtent),
    };
  }

  /// The layout's extent along [axis] under [_intrinsicConstraints] when each
  /// child that sizes to its content along [axis] measures at no more than its
  /// own minimum intrinsic size there.
  double _minimumIntrinsicExtent(Axis axis, double crossExtent) {
    if (childCount == 0) return 0;
    final constraints = _intrinsicConstraints(axis, crossExtent);
    final resolved = _resolveDry(constraints, minimumAxis: axis);
    if (resolved == null) return 0;
    final size = _resolvedSize(resolved.model.container, constraints);
    return switch (axis) {
      Axis.horizontal => size.width,
      Axis.vertical => size.height,
    };
  }

  /// Resolves a throwaway engine model of the children under [constraints],
  /// as [performLayout] resolves the persistent one, but with a measurer that
  /// sizes each child with its dry layout instead of laying it out.
  ///
  /// With [minimumAxis], each child that sizes to its content along that axis
  /// measures at no more than its own minimum intrinsic size there.
  ///
  /// Returns null, after reporting the error, if resolving the model throws.
  /// A dry query must not throw: Flutter clears the flag that marks a dry
  /// layout or dry baseline in progress only when the computation returns,
  /// so an exception would leave this render object failing assertions in
  /// every later layout. For the same reason the throwaway model skips
  /// unknown ids, which the layout pass reports.
  ({_EngineModel model, _DryMeasurer measurer})? _resolveDry(
    BoxConstraints constraints, {
    Axis? minimumAxis,
  }) {
    try {
      // A fresh model needs none of the normalization performLayout gives
      // the persistent one: its widgets enter the engine as a rebuilt
      // model's do.
      final model = _createModel(constraints, reportsUnknownIds: false);
      final measurer = _DryMeasurer(
        this,
        model.renderOf,
        model.needsBaseline,
        minimumAxis: minimumAxis,
      );
      final container = model.container..setMeasurer(measurer);
      _prepareContainer(container, constraints);
      measurer.beginPass(constraints);
      container.layout();
      return (model: model, measurer: measurer);
    } catch (exception, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'flutter_constraint_layout',
          context: ErrorDescription(
            'while resolving a ConstraintLayout for a dry layout, intrinsic '
            'size, or dry baseline',
          ),
          informationCollector: () => <DiagnosticsNode>[
            describeForError('The ConstraintLayout was'),
          ],
        ),
      );
      return null;
    }
  }

  /// Rebuilds the persistent engine model from scratch.
  void _buildModel(BoxConstraints constraints) {
    // Dropped before the build: applying config can throw (an unresolvable
    // link id reports through an assert), and a half-built or stale model
    // must not stay behind. _needsModelRebuild is only cleared once the build
    // succeeded, so every later layout rebuilds and re-reports the real
    // problem instead of resolving a model that looks clean.
    _model = null;
    _measurer = null;
    final model = _createModel(constraints, reportsUnknownIds: true);
    _publishGroupOverrides(model);
    for (final pd in model.childData) {
      pd.configDirty = false;
      pd.structuralDirty = false;
    }
    final measurer = _FlutterMeasurer(model.renderOf, model.needsBaseline);
    model.container.setMeasurer(measurer);
    _model = model;
    _measurer = measurer;
    _needsModelRebuild = false;
  }

  /// Builds an engine model of the current children: one `ConstraintWidget`
  /// per child, configured from its parent data.
  ///
  /// Touches nothing but the new model, so it builds both the persistent
  /// model ([_buildModel]) and the throwaway ones of the dry-layout queries
  /// ([_resolveDry]). See [_EngineModel.reportsUnknownIds].
  _EngineModel _createModel(
    BoxConstraints constraints, {
    required bool reportsUnknownIds,
  }) {
    final model = _EngineModel(
      ConstraintWidgetContainer.rect(
        0,
        0,
        constraints.hasBoundedWidth ? constraints.maxWidth.round() : 0,
        constraints.hasBoundedHeight ? constraints.maxHeight.round() : 0,
      ),
      reportsUnknownIds: reportsUnknownIds,
    );

    RenderBox? child = firstChild;
    while (child != null) {
      final pd = child.parentData! as ConstraintParentData;
      model.children.add(child);
      model.childData.add(pd);
      child = pd.nextSibling;
    }

    // Create every widget and register ids before applying config, so links
    // can target later siblings. Helper children map to their dedicated
    // engine types.
    for (var i = 0; i < model.children.length; i++) {
      final pd = model.childData[i];
      final w = switch (pd.helperKind) {
        HelperKind.none => ConstraintWidget(),
        // Oriented now, before any sibling links to it: a guideline only has
        // the left and right edges that links to a vertical one target once
        // it is vertical, and a sibling earlier in the child list connects
        // before the guideline's own config. Android sets the orientation
        // when it validates the guideline's layout params, before any
        // constraint, so the child order does not matter there either.
        HelperKind.guideline =>
          Guideline()..setOrientation(
            pd.guidelineAxis == Axis.horizontal
                ? Guideline.horizontal
                : Guideline.vertical,
          ),
        HelperKind.barrier => Barrier(),
        HelperKind.flow => Flow(),
        HelperKind.grid => GridCore(),
        // Only keeps the model lists index-aligned (and the group's child
        // placed at 0 x 0 at the origin): it is never added to the container.
        HelperKind.group => ConstraintWidget(),
      };
      model.widgets.add(w);
      if (pd.helperKind == HelperKind.none) {
        model.renderOf[w] = model.children[i];
      }
      final id = pd.id;
      if (pd.helperKind == HelperKind.group) {
        if (id != null) {
          model.groupIds.add(id);
        }
        continue;
      }
      if (id != null) {
        model.byId[id] = w;
        model.indexById[id] = i;
      }
      model.container.add(w);
    }
    // Derived state (and its baseline seeding) must precede the connects.
    _computeDerivedState(model);
    for (var i = 0; i < model.widgets.length; i++) {
      _applyWidgetConfig(model, model.widgets[i], model.childData[i]);
    }
    _reportLinkLoop(model);
    return model;
  }

  /// Applies the full `Constrained` config from [pd] to engine widget [w] of
  /// [model], whose ids and container its links resolve against.
  ///
  /// Also used to update a persistent widget in place, so it first resets any
  /// state a previous configuration (or the engine's GONE zeroing in
  /// updateFromRuns) may have left behind; after the reset, re-applying is
  /// equivalent to configuring a fresh widget.
  void _applyWidgetConfig(
    _EngineModel model,
    ConstraintWidget w,
    ConstraintParentData pd,
  ) {
    if (pd.helperKind == HelperKind.guideline ||
        pd.helperKind == HelperKind.barrier) {
      _applyHelperConfig(model, w, pd);
      return;
    }
    if (pd.helperKind == HelperKind.group) {
      _applyGroupConfig(model, pd);
      return;
    }
    // Flows fall through: they are positioned and sized like a regular child
    // (links, dimensions, bias, visibility) and get their flow configuration
    // applied on top at the end.

    // resetAnchors() clears each anchor's incoming-dependents set, but
    // siblings still targeting this widget keep their connections; the
    // solver's GONE handling gates on hasDependencies(), so the incoming
    // bookkeeping must survive an in-place re-apply.
    final savedDependents = [
      for (final anchor in w.mAnchors) anchor.mDependents,
    ];
    w.resetAnchors();
    for (var i = 0; i < w.mAnchors.length; i++) {
      w.mAnchors[i].mDependents = savedDependents[i];
    }
    w.setDimensionRatio(0, ConstraintWidget.UNKNOWN);
    // Match styles carry min/max/percent; reset to pristine spread defaults.
    w.setHorizontalMatchStyle(
      ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
      0,
      0,
      1,
    );
    w.setVerticalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 0, 1);
    // A circular constraint is an anchor connect plus this angle; the connect
    // is cleared by resetAnchors, the angle must be cleared here.
    w.mCircleConstraintAngle = double.nan;
    // The stored position is the engine's input for an unanchored axis, so a
    // value resolved under a removed link must not survive the re-apply.
    w.setX(0);
    w.setY(0);

    w.setHorizontalDimensionBehaviour(_behaviourOf(pd.width));
    w.setVerticalDimensionBehaviour(_behaviourOf(pd.height));
    // Non-fixed axes reset the stored size to 0, matching a fresh widget.
    // Visible widgets get measured every pass either way, but a GONE widget
    // skips measurement and the engine then reads the stored size during
    // graph building, so a stale value would shift its resolved position.
    final width = pd.width;
    w.setWidth(width is FixedDimension ? width.pixels.round() : 0);
    final height = pd.height;
    w.setHeight(height is FixedDimension ? height.pixels.round() : 0);
    if (width is MatchConstraintDimension) {
      w.setHorizontalMatchStyle(
        _matchStyleOf(width),
        width.min?.round() ?? 0,
        width.max?.round() ?? 0,
        width.percent ?? 1,
      );
    }
    if (height is MatchConstraintDimension) {
      w.setVerticalMatchStyle(
        _matchStyleOf(height),
        height.min?.round() ?? 0,
        height.max?.round() ?? 0,
        height.percent ?? 1,
      );
    }
    // Resolved as Android's LayoutParams.resolveLayoutDirection does: in a
    // right-to-left layout, a child with any start/end link uses
    // 1 - horizontalBias, so its bias counts from its start (right) edge. A
    // child linked only with absolute left/right keeps the bias as given.
    // A widget a grid places counts as start/end-linked: the grid's columns
    // count from the start edge, so its position in its cell does too, and
    // the grid mirrors as a whole.
    final id = pd.id;
    final mirrorBias =
        !_ltr &&
        (pd.start != null ||
            pd.end != null ||
            (id != null && model.gridMembers.contains(id)));
    w.setHorizontalBiasPercent(
      mirrorBias ? 1 - pd.horizontalBias : pd.horizontalBias,
    );
    w.setVerticalBiasPercent(pd.verticalBias);
    final ratio = pd.aspectRatio;
    if (ratio != null && ratio > 0) {
      w.setDimensionRatioString(ratio.toString());
    }
    w.setHorizontalChainStyle(_chainStyleOf(pd.horizontalChainStyle));
    w.setVerticalChainStyle(_chainStyleOf(pd.verticalChainStyle));
    w.setHorizontalWeight(
      pd.horizontalWeight ?? ConstraintWidget.UNKNOWN.toDouble(),
    );
    w.setVerticalWeight(
      pd.verticalWeight ?? ConstraintWidget.UNKNOWN.toDouble(),
    );
    // A group that references this child overrides its own visibility.
    w.setVisibility(switch (model.visibilityOf(pd)) {
      ConstraintVisibility.visible => ConstraintWidget.VISIBLE,
      ConstraintVisibility.invisible => ConstraintWidget.INVISIBLE,
      ConstraintVisibility.gone => ConstraintWidget.GONE,
    });

    // Android resolves start/end as a pair: when either is set, all absolute
    // left/right links are ignored, not just the link on the same side.
    if (pd.start != null || pd.end != null) {
      _connectH(model, w, HorizontalEdge.start, pd.start);
      _connectH(model, w, HorizontalEdge.end, pd.end);
    } else {
      _connectH(model, w, HorizontalEdge.left, pd.left);
      _connectH(model, w, HorizontalEdge.right, pd.right);
    }
    _connectV(model, w, VerticalEdge.top, pd.top);
    _connectV(model, w, VerticalEdge.bottom, pd.bottom);
    _connectV(model, w, VerticalEdge.baseline, pd.baseline);

    final circle = pd.circle;
    if (circle != null) {
      final target = _resolveTarget(model, circle.target);
      if (target == null) {
        _reportUnknownId(
          model,
          'CircularLink targets ${_describeUnresolved(model, circle.target)}. '
          'Targets must be `parent` or the id of a sibling in the same '
          'ConstraintLayout.',
        );
      } else {
        w.connectCircularConstraint(
          target,
          circle.angle,
          circle.radius.round(),
        );
      }
    }

    if (w is Flow) {
      _applyFlowConfig(model, w, pd);
    } else if (w is GridCore) {
      _applyGridConfig(model, w, pd);
    }

    // The connects above reset anchors of this widget again: a top or bottom
    // link resets its baseline, and a baseline link its top and bottom, which
    // drops the incoming links restored after resetAnchors. Android applies
    // these links without resetting anything, so whatever still points at
    // one of this widget's anchors is registered with it again. Without this
    // a widget whose baseline another one links to lost that link whenever
    // it was re-applied in place (or configured after the widget linking to
    // it), and the layout differed from a fresh build.
    for (var i = 0; i < w.mAnchors.length; i++) {
      final saved = savedDependents[i];
      final anchor = w.mAnchors[i];
      if (saved == null || identical(saved, anchor.mDependents)) continue;
      for (final dependent in saved) {
        if (identical(dependent.mTarget, anchor)) {
          (anchor.mDependents ??= <ConstraintAnchor>{}).add(dependent);
        }
      }
    }
  }

  /// Applies grid configuration on top of the regular widget config. Only
  /// called from model builds (grid changes are structural), so referenced
  /// widgets never need clearing.
  ///
  /// Nothing here depends on the text direction: the engine's grid mirrors
  /// its columns itself, following the container's `setRtl` from
  /// [_prepareContainer].
  void _applyGridConfig(
    _EngineModel model,
    GridCore w,
    ConstraintParentData pd,
  ) {
    w.setRows(pd.gridRows ?? 0);
    w.setColumns(pd.gridColumns ?? 0);
    w.setOrientation(
      pd.gridOrientation == Axis.horizontal
          ? GridCore.HORIZONTAL
          : GridCore.VERTICAL,
    );
    w.setHorizontalGaps(pd.gridHorizontalGap);
    w.setVerticalGaps(pd.gridVerticalGap);
    final rowWeights = pd.gridRowWeights;
    if (rowWeights != null) {
      w.setRowWeights(rowWeights.join(','));
    }
    final columnWeights = pd.gridColumnWeights;
    if (columnWeights != null) {
      w.setColumnWeights(columnWeights.join(','));
    }
    final spans = pd.gridSpans;
    if (spans != null) {
      w.setSpans(spans);
    }
    final skips = pd.gridSkips;
    if (skips != null) {
      w.setSkips(skips);
    }
    for (final id in pd.gridReferenced) {
      final target = model.byId[id];
      if (target == null) {
        _reportUnknownId(
          model,
          'ConstraintGrid references ${_describeUnresolved(model, id)}. '
          'Referenced ids must belong to siblings in the same '
          'ConstraintLayout.',
        );
        continue;
      }
      w.add(target);
    }
  }

  /// Applies flow configuration on top of the regular widget config. Only
  /// called from model builds (flow changes are structural), so referenced
  /// widgets never need clearing.
  void _applyFlowConfig(_EngineModel model, Flow w, ConstraintParentData pd) {
    w.setOrientation(
      pd.flowOrientation == Axis.horizontal
          ? ConstraintWidget.HORIZONTAL
          : ConstraintWidget.VERTICAL,
    );
    w.setWrapMode(switch (pd.flowWrap) {
      FlowWrap.none => Flow.WRAP_NONE,
      FlowWrap.chain => Flow.WRAP_CHAIN,
      FlowWrap.aligned => Flow.WRAP_ALIGNED,
    });
    w.setHorizontalGap(pd.flowHorizontalGap.round());
    w.setVerticalGap(pd.flowVerticalGap.round());
    w.setHorizontalStyle(_chainStyleOf(pd.flowHorizontalStyle));
    w.setVerticalStyle(_chainStyleOf(pd.flowVerticalStyle));
    w.setHorizontalBias(pd.flowHorizontalBias);
    w.setVerticalBias(pd.flowVerticalBias);
    w.setHorizontalAlign(switch (pd.flowHorizontalAlign) {
      FlowHorizontalAlign.start => Flow.HORIZONTAL_ALIGN_START,
      FlowHorizontalAlign.end => Flow.HORIZONTAL_ALIGN_END,
      FlowHorizontalAlign.center => Flow.HORIZONTAL_ALIGN_CENTER,
    });
    w.setVerticalAlign(switch (pd.flowVerticalAlign) {
      FlowVerticalAlign.top => Flow.VERTICAL_ALIGN_TOP,
      FlowVerticalAlign.bottom => Flow.VERTICAL_ALIGN_BOTTOM,
      FlowVerticalAlign.center => Flow.VERTICAL_ALIGN_CENTER,
      FlowVerticalAlign.baseline => Flow.VERTICAL_ALIGN_BASELINE,
    });
    w.setMaxElementsWrap(pd.flowMaxElementsWrap ?? ConstraintWidget.UNKNOWN);
    w.setPadding(pd.flowPadding.round());
    // setPadding sets the horizontal sides as start/end, which become the
    // left/right padding the flow wraps and places with only once resolved
    // for the text direction (as Android's ConstraintHelper.resolveRtl does).
    w.applyRtl(!_ltr);
    for (final id in pd.flowReferenced) {
      final target = model.byId[id];
      if (target == null) {
        _reportUnknownId(
          model,
          'ConstraintFlow references ${_describeUnresolved(model, id)}. '
          'Referenced ids must belong to siblings in the same '
          'ConstraintLayout.',
        );
        continue;
      }
      w.add(target);
    }
  }

  /// Applies guideline/barrier configuration to the dedicated engine widget.
  /// Only called from model builds: helper config changes are structural, so
  /// [w] is always freshly constructed and needs no reset.
  void _applyHelperConfig(
    _EngineModel model,
    ConstraintWidget w,
    ConstraintParentData pd,
  ) {
    if (w is Guideline) {
      w.setOrientation(
        pd.guidelineAxis == Axis.horizontal
            ? Guideline.horizontal
            : Guideline.vertical,
      );
      // Resolved as Android's LayoutParams.resolveLayoutDirection does with
      // guidelineUseRtl at its default (true): in a right-to-left layout a
      // vertical guideline counts from the right, so percent becomes
      // 1 - percent and begin and end trade edges. Horizontal guidelines are
      // unaffected.
      final mirror = !_ltr && pd.guidelineAxis == Axis.vertical;
      final percent = pd.guidelinePercent;
      final begin = pd.guidelineBegin;
      final end = pd.guidelineEnd;
      if (percent != null) {
        w.setGuidePercent(mirror ? 1 - percent : percent);
      } else if (begin != null) {
        if (mirror) {
          w.setGuideEnd(begin.round());
        } else {
          w.setGuideBegin(begin.round());
        }
      } else if (end != null) {
        if (mirror) {
          w.setGuideBegin(end.round());
        } else {
          w.setGuideEnd(end.round());
        }
      }
    } else if (w is Barrier) {
      w.setBarrierType(switch (pd.barrierEdge) {
        BarrierEdge.left => Barrier.left,
        BarrierEdge.right => Barrier.right,
        BarrierEdge.top => Barrier.top,
        BarrierEdge.bottom => Barrier.bottom,
        BarrierEdge.start => _ltr ? Barrier.left : Barrier.right,
        BarrierEdge.end => _ltr ? Barrier.right : Barrier.left,
      });
      w.setAllowsGoneWidget(pd.barrierAllowsGone);
      // Deliberate difference from Android, whose view-layer Barrier resolves
      // start and end to left and right but keeps the margin's sign, so a
      // positive margin moves every barrier right. Here a right-to-left
      // layout is the exact mirror of its left-to-right twin: a start or end
      // barrier tracks the mirrored edge, so it takes the mirrored margin
      // too. Absolute left/right barriers and top/bottom barriers keep it.
      final margin = pd.barrierMargin.round();
      final directional =
          pd.barrierEdge == BarrierEdge.start ||
          pd.barrierEdge == BarrierEdge.end;
      w.setMargin(!_ltr && directional ? -margin : margin);
      for (final id in pd.barrierReferenced) {
        final target = model.byId[id];
        if (target == null) {
          _reportUnknownId(
            model,
            'Barrier references ${_describeUnresolved(model, id)}. '
            'Referenced ids must belong to siblings in the same '
            'ConstraintLayout.',
          );
          continue;
        }
        w.add(target);
      }
    }
  }

  /// Validates a group's referenced ids, reporting those that resolve to no
  /// sibling as Barrier does. A group puts nothing into the engine: its
  /// visibility reaches the referenced children through
  /// [_EngineModel.groupOverrides], set in [_computeDerivedState].
  void _applyGroupConfig(_EngineModel model, ConstraintParentData pd) {
    for (final id in pd.groupReferenced) {
      if (model.indexById.containsKey(id)) continue;
      _reportUnknownId(
        model,
        'ConstraintGroup references ${_describeUnresolved(model, id)}. '
        'Referenced ids must belong to siblings in the same '
        'ConstraintLayout.',
      );
    }
  }

  /// Marks the children referenced by a group whose visibility changed as if
  /// their own visibility had changed: a `Constrained` child is updated in
  /// place, while a flow or grid, whose configuration is applied at model
  /// build time, rebuilds the model. The group's own flag is cleared, since
  /// it has no engine configuration to apply.
  void _passGroupChangesToMembers(_EngineModel model) {
    for (final pd in model.childData) {
      if (pd.helperKind != HelperKind.group || !pd.configDirty) continue;
      pd.configDirty = false;
      for (final id in pd.groupReferenced) {
        final index = model.indexById[id];
        if (index == null) continue;
        final member = model.childData[index];
        switch (member.helperKind) {
          case HelperKind.none:
            member.configDirty = true;
          case HelperKind.flow || HelperKind.grid:
            _needsModelRebuild = true;
          case HelperKind.guideline || HelperKind.barrier || HelperKind.group:
            break;
        }
      }
    }
  }

  /// Hands [model]'s group overrides to the children's parent data, where
  /// painting, hit testing, semantics, and the debug overlay read them. Only
  /// for the persistent model: a dry-layout query must leave parent data
  /// alone.
  static void _publishGroupOverrides(_EngineModel model) {
    for (final pd in model.childData) {
      pd.groupOverride = model.groupOverrides[pd];
    }
  }

  /// How an error names an [id] that resolves to no sibling that takes part
  /// in the layout: as a group, which nothing can link to or reference, or as
  /// an unknown id.
  static String _describeUnresolved(_EngineModel model, Symbol id) =>
      model.groupIds.contains(id)
      ? '$id, which is a ConstraintGroup. A group has no position or size, '
            'so nothing can link to or reference it'
      : 'unknown id $id';

  int _matchStyleOf(MatchConstraintDimension d) {
    if (d.wrap) return ConstraintWidget.MATCH_CONSTRAINT_WRAP;
    if (d.percent != null) return ConstraintWidget.MATCH_CONSTRAINT_PERCENT;
    return ConstraintWidget.MATCH_CONSTRAINT_SPREAD;
  }

  int _chainStyleOf(ChainStyle? style) => switch (style) {
    null || ChainStyle.spread => ConstraintWidget.CHAIN_SPREAD,
    ChainStyle.spreadInside => ConstraintWidget.CHAIN_SPREAD_INSIDE,
    ChainStyle.packed => ConstraintWidget.CHAIN_PACKED,
  };

  /// Recomputes state derived from the whole of [model]: the visibility
  /// groups impose on their referenced children, which widgets need a real
  /// baseline measured, and whether any child's geometry can depend on its
  /// content (which disables the engine-skipping fast path).
  ///
  /// Writes only to [model]: the persistent model's group overrides reach
  /// the parent data through [_publishGroupOverrides].
  void _computeDerivedState(_EngineModel model) {
    // As Android's Group, each group sets its visibility on every child it
    // references, in child order, so the last group to reference a child
    // wins. The overrides are rebuilt from scratch, so a child that no group
    // references any more is laid out with its own visibility again.
    // Unresolvable ids are skipped here and reported by _applyGroupConfig.
    final groupOverrides = model.groupOverrides..clear();
    for (final pd in model.childData) {
      if (pd.helperKind != HelperKind.group) continue;
      for (final id in pd.groupReferenced) {
        final index = model.indexById[id];
        if (index == null) continue;
        final member = model.childData[index];
        // Guidelines and barriers have no visibility to set.
        if (member.helperKind == HelperKind.none ||
            member.helperKind == HelperKind.flow ||
            member.helperKind == HelperKind.grid) {
          groupOverrides[member] = pd.groupVisibility;
        }
      }
    }

    // The widgets a grid that takes part in the layout places: their
    // horizontal bias counts from the start edge (see _applyWidgetConfig).
    final gridMembers = model.gridMembers..clear();
    for (final pd in model.childData) {
      if (pd.helperKind != HelperKind.grid) continue;
      if (model.visibilityOf(pd) == ConstraintVisibility.gone) continue;
      gridMembers.addAll(pd.gridReferenced);
    }

    // Cleared and refilled in place: the model's measurer holds this set.
    final needsBaseline = model.needsBaseline..clear();
    var contentDependent = false;
    for (var i = 0; i < model.childData.length; i++) {
      final pd = model.childData[i];
      final link = pd.baseline;
      if (link != null) {
        needsBaseline.add(model.widgets[i]);
        final target = link.target == parent ? null : model.byId[link.target];
        if (target != null) {
          needsBaseline.add(target);
        }
      }
      // A baseline-aligned flow needs real baselines for every widget it
      // arranges.
      if (pd.helperKind == HelperKind.flow &&
          pd.flowVerticalAlign == FlowVerticalAlign.baseline) {
        for (final id in pd.flowReferenced) {
          final target = model.byId[id];
          if (target != null) {
            needsBaseline.add(target);
          }
        }
      }
      contentDependent = contentDependent || _isContentDependent(pd);
    }
    model.hasContentDependentChild = contentDependent;

    // Baseline connects only validate when both endpoints already report a
    // baseline (upstream parity: Android sets hasBaseline from the view while
    // applying LayoutParams, before connecting). Seed the participants now;
    // the next measure pass overwrites the flag with the real value.
    for (final w in needsBaseline) {
      w.setHasBaseline(true);
    }
  }

  /// Whether this child's resolved size can depend on its content: a wrap
  /// dimension, a constrained-wrap match dimension, or a matchConstraint
  /// dimension the engine measures as wrap because an opposing anchor is
  /// missing. Helper children (guidelines, barriers) have no content.
  bool _isContentDependent(ConstraintParentData pd) {
    if (pd.helperKind != HelperKind.none) return false;
    final directional = pd.start != null || pd.end != null;
    final hasLeft = directional
        ? (_ltr ? pd.start : pd.end) != null
        : pd.left != null;
    final hasRight = directional
        ? (_ltr ? pd.end : pd.start) != null
        : pd.right != null;
    final hasTop = pd.top != null;
    final hasBottom = pd.bottom != null;

    bool depends(Dimension d, bool hasA, bool hasB) => switch (d) {
      WrapContentDimension() => true,
      MatchConstraintDimension(:final wrap) => wrap || !(hasA && hasB),
      _ => false,
    };

    return depends(pd.width, hasLeft, hasRight) ||
        depends(pd.height, hasTop, hasBottom);
  }

  void _connectH(
    _EngineModel model,
    ConstraintWidget w,
    HorizontalEdge sourceEdge,
    HorizontalLink? link,
  ) {
    if (link == null) return;
    final target = _resolveTarget(model, link.target);
    if (target == null) {
      _reportUnknownLinkTarget(model, link.target);
      return;
    }
    final from = _hAnchor(sourceEdge);
    w.connect(from, target, _hAnchor(link.edge), link.margin.round());
    if (link.goneMargin != 0) {
      w.setGoneMargin(from, link.goneMargin.round());
    }
  }

  void _connectV(
    _EngineModel model,
    ConstraintWidget w,
    VerticalEdge sourceEdge,
    VerticalLink? link,
  ) {
    if (link == null) return;
    final target = _resolveTarget(model, link.target);
    if (target == null) {
      _reportUnknownLinkTarget(model, link.target);
      return;
    }
    final from = _vAnchor(sourceEdge);
    w.connect(from, target, _vAnchor(link.edge), link.margin.round());
    if (link.goneMargin != 0) {
      w.setGoneMargin(from, link.goneMargin.round());
    }
  }

  ConstraintWidget? _resolveTarget(_EngineModel model, Symbol target) {
    if (target == parent) return model.container;
    return model.byId[target];
  }

  void _reportUnknownLinkTarget(_EngineModel model, Symbol target) =>
      _reportUnknownId(
        model,
        'Constrained link targets ${_describeUnresolved(model, target)}. '
        'Targets must be `parent` or the id of a sibling Constrained in the '
        'same ConstraintLayout.',
      );

  /// Reports a reference to an id that no sibling has, described by
  /// [message].
  ///
  /// In a debug build the persistent model's build throws it, abandoning the
  /// layout pass so the mistake cannot go unnoticed; release builds skip the
  /// reference. A throwaway model (see [_EngineModel.reportsUnknownIds])
  /// skips it in every build: the layout pass reports it, and a dry query
  /// must not throw (see [_resolveDry]).
  void _reportUnknownId(_EngineModel model, String message) {
    assert(() {
      if (model.reportsUnknownIds) throw FlutterError(message);
      return true;
    }());
  }

  /// Reports, like an unknown id (see [_reportUnknownId]), links that loop
  /// back on themselves: two children whose same edges link to each other
  /// (both tops, or both ends), an edge linked to itself, two children linked
  /// both ways on both sides, or a chain whose first child's start links one
  /// way to its last child while the last child's end links back to the
  /// first child. No child of such a loop has a position to start from.
  /// Android's ConstraintLayout never finishes laying out a layout with the
  /// last kind. It lays out the others, at the layout's left or top edge in
  /// either text direction when nothing else anchors the loop, and the engine
  /// lays out every kind, the others as Android does. Baseline links are not
  /// followed, so two baselines linked to each other are not reported.
  void _reportLinkLoop(_EngineModel model) {
    assert(() {
      if (!model.reportsUnknownIds) return true;
      final loop = _linkLoop(model);
      if (loop == null) return true;
      String edge(ConstraintAnchor anchor) {
        final index = model.widgets.indexOf(anchor.mOwner);
        final pd = model.childData[index];
        final name = switch (anchor.mType) {
          ConstraintAnchorType.left when pd.start != null || pd.end != null =>
            _ltr ? 'start' : 'end',
          ConstraintAnchorType.right when pd.start != null || pd.end != null =>
            _ltr ? 'end' : 'start',
          final type => type.name,
        };
        return '${pd.id} $name';
      }

      final links = [
        for (final anchor in loop)
          '${edge(anchor)} to ${edge(anchor.mTarget!)}',
      ];
      throw FlutterError(
        'Constrained links loop back on themselves: ${links.join(', ')}. '
        'None of these children has a position to start from. Link one of '
        'these edges to `parent` or to a child outside the loop instead.',
      );
    }());
  }

  /// The links of a loop that [_reportLinkLoop] reports, or null. It follows
  /// the engine's two chain walks along each axis: the dependency graph's,
  /// through every edge whose target links straight back to it, and the
  /// solver's, from a chain's first child to each next child whose start
  /// links to the one before.
  static List<ConstraintAnchor>? _linkLoop(_EngineModel model) {
    ConstraintAnchor? linkedBack(ConstraintAnchor anchor) {
      final target = anchor.mTarget;
      return target != null && identical(target.mTarget, anchor)
          ? target
          : null;
    }

    for (final widget in model.widgets) {
      for (final horizontal in const [true, false]) {
        ConstraintAnchor startOf(ConstraintWidget w) =>
            horizontal ? w.mLeft : w.mTop;
        ConstraintAnchor endOf(ConstraintWidget w) =>
            horizontal ? w.mRight : w.mBottom;
        // The graph's walk: back through linked-back starts, then forward
        // through linked-back ends.
        for (final forward in const [false, true]) {
          final links = <ConstraintAnchor>[];
          final seen = <ConstraintWidget>{widget};
          var current = widget;
          while (true) {
            final anchor = forward ? endOf(current) : startOf(current);
            final back = linkedBack(anchor);
            if (back == null) break;
            links.add(anchor);
            if (!seen.add(back.mOwner)) return links;
            current = back.mOwner;
          }
        }
        // The solver's walk, from a chain's first child.
        final start = startOf(widget).mTarget;
        if (start == null ||
            identical(start.mTarget, startOf(widget)) ||
            linkedBack(endOf(widget)) == null) {
          continue;
        }
        final links = <ConstraintAnchor>[];
        var current = widget;
        while (true) {
          final end = endOf(current);
          final next = end.mTarget?.mOwner;
          if (next == null ||
              !identical(startOf(next).mTarget?.mOwner, current)) {
            break;
          }
          links.add(end);
          if (identical(next, widget)) return links;
          if (links.length > model.widgets.length) break;
          current = next;
        }
      }
    }
    return null;
  }

  ConstraintAnchorType _hAnchor(HorizontalEdge edge) => switch (edge) {
    HorizontalEdge.left => ConstraintAnchorType.left,
    HorizontalEdge.right => ConstraintAnchorType.right,
    HorizontalEdge.start =>
      _ltr ? ConstraintAnchorType.left : ConstraintAnchorType.right,
    HorizontalEdge.end =>
      _ltr ? ConstraintAnchorType.right : ConstraintAnchorType.left,
  };

  ConstraintAnchorType _vAnchor(VerticalEdge edge) => switch (edge) {
    VerticalEdge.top => ConstraintAnchorType.top,
    VerticalEdge.bottom => ConstraintAnchorType.bottom,
    VerticalEdge.baseline => ConstraintAnchorType.baseline,
  };

  DimensionBehaviour _behaviourOf(Dimension d) => switch (d) {
    WrapContentDimension() => DimensionBehaviour.wrapContent,
    MatchParentDimension() => DimensionBehaviour.matchParent,
    MatchConstraintDimension() => DimensionBehaviour.matchConstraint,
    FixedDimension() => DimensionBehaviour.fixed,
  };

  /// Children in paint order: ascending [ConstraintParentData.zIndex], with
  /// document order as the default key and as the tiebreaker.
  List<RenderBox> _paintOrder() {
    final list = <RenderBox>[];
    final order = <RenderBox, int>{};
    var i = 0;
    RenderBox? child = firstChild;
    while (child != null) {
      list.add(child);
      order[child] = i++;
      child = (child.parentData! as ConstraintParentData).nextSibling;
    }
    list.sort((a, b) {
      final za = (a.parentData! as ConstraintParentData).zIndex ?? order[a]!;
      final zb = (b.parentData! as ConstraintParentData).zIndex ?? order[b]!;
      final cmp = za.compareTo(zb);
      return cmp != 0 ? cmp : order[a]!.compareTo(order[b]!);
    });
    return list;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // The debug overlays are honored only when ConstraintLayout.allowDebugFlags
    // is set (true by default in debug builds, false in profile/release unless
    // the app opts in). When it is off both flags read as false here, so this
    // stays a normal child paint.
    final debugEnabled = ConstraintLayout.allowDebugFlags;
    final showBlueprint = debugEnabled && _debugShowBlueprint;
    final showChains = debugEnabled && _debugShowChains;

    // Blueprint mode replaces the children's painting. Skipping paintChild is
    // safe with descendant RepaintBoundary widgets: their layers simply are not
    // composited.
    if (!showBlueprint) {
      for (final child in _paintOrder()) {
        final pd = child.parentData! as ConstraintParentData;
        if (pd.effectiveVisibility != ConstraintVisibility.visible) continue;
        context.paintChild(child, pd.offset + offset);
      }
    }
    // The design-surface / blueprint overlay. context.canvas is read here,
    // after the paintChild calls, because the getter re-acquires the canvas.
    if ((showBlueprint || showChains) && _model != null) {
      final tint = _debugChainColor;
      final palette = tint != null
          ? DebugPalette.tinted(tint, blueprint: showBlueprint)
          : showBlueprint
          ? const DebugPalette.blueprint()
          : const DebugPalette.design();
      paintDebugScene(
        context.canvas,
        offset,
        size,
        debugDescribeScene(),
        palette,
        blueprint: showBlueprint,
        labelStyle: _debugLabelStyle,
      );
    }
  }

  /// Only visible children take part in semantics. Invisible and gone ones
  /// (by their own visibility or a group's) are neither painted nor
  /// hit-tested, so a screen reader must not announce or activate them
  /// either; Android likewise leaves views that are not VISIBLE out of the
  /// accessibility tree. No extra invalidation is needed: every visibility
  /// change, a child's own or a group's, re-runs [performLayout], and
  /// [RenderObject.layout] marks the semantics dirty after it.
  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    RenderBox? child = firstChild;
    while (child != null) {
      final pd = child.parentData! as ConstraintParentData;
      if (pd.effectiveVisibility == ConstraintVisibility.visible) {
        visitor(child);
      }
      child = pd.nextSibling;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in _paintOrder().reversed) {
      final pd = child.parentData! as ConstraintParentData;
      if (pd.effectiveVisibility != ConstraintVisibility.visible) continue;
      final hit = result.addWithPaintOffset(
        offset: pd.offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }
}

/// An engine model of a [RenderConstraintLayout]'s children: a container
/// holding one engine widget per child, configured from the child's parent
/// data.
///
/// The render object keeps one alive across layout passes; the dry-layout,
/// intrinsic-size, and dry-baseline queries each resolve a throwaway one, so
/// they never disturb it.
class _EngineModel {
  _EngineModel(this.container, {required this.reportsUnknownIds});

  /// The root, which stands in for the layout itself.
  final ConstraintWidgetContainer container;

  /// Whether building this model throws, in a debug build, on a reference to
  /// an id that no sibling has. True for the persistent model; a throwaway
  /// one skips the reference, as release builds do. See
  /// [RenderConstraintLayout._reportUnknownId].
  final bool reportsUnknownIds;

  /// The children, in child-list order.
  final List<RenderBox> children = <RenderBox>[];

  /// The parent data of each child, by index in [children].
  final List<ConstraintParentData> childData = <ConstraintParentData>[];

  /// The engine widget of each child, by index in [children].
  final List<ConstraintWidget> widgets = <ConstraintWidget>[];

  /// Engine widgets by child id, for resolving links and helper references:
  /// the children that take part in the layout, every kind but a group.
  final Map<Symbol, ConstraintWidget> byId = <Symbol, ConstraintWidget>{};

  /// The index in [children] of each child in [byId].
  final Map<Symbol, int> indexById = <Symbol, int>{};

  /// The ids of the groups, kept apart from [byId]: nothing can link to or
  /// reference a group.
  final Set<Symbol> groupIds = <Symbol>{};

  /// The visibility a `ConstraintGroup` imposes on each child it references,
  /// by the child's parent data. Derived state; see
  /// [RenderConstraintLayout._computeDerivedState].
  final Map<ConstraintParentData, ConstraintVisibility> groupOverrides =
      <ConstraintParentData, ConstraintVisibility>{};

  /// The visibility the child with parent data [pd] is laid out with: that of
  /// the last group that references it, otherwise its own.
  ConstraintVisibility visibilityOf(ConstraintParentData pd) =>
      groupOverrides[pd] ?? pd.visibility;

  /// The RenderBox of each content child (every child but the helpers), by
  /// engine widget: the children a measurer measures.
  final Map<ConstraintWidget, RenderBox> renderOf =
      <ConstraintWidget, RenderBox>{};

  /// Widgets whose real baseline must be measured; see
  /// [_FlutterMeasurer._needsBaseline].
  final Set<ConstraintWidget> needsBaseline = <ConstraintWidget>{};

  /// The ids of the children a `ConstraintGrid` that is not gone places.
  /// Derived state; see [RenderConstraintLayout._computeDerivedState].
  final Set<Symbol> gridMembers = <Symbol>{};

  /// Whether any child's geometry can depend on its content, which rules out
  /// the layout's engine-skipping fast path.
  bool hasContentDependentChild = false;
}

/// The latest layout a measurer gave a child during an engine pass: its
/// constraints, and the size the child took under them (or, for a
/// [_DryMeasurer], would take).
typedef _MeasuredLayout = ({BoxConstraints constraints, Size size});

/// Bridges the engine's intrinsic-measurement seam to Flutter: measures a child
/// by laying out its [RenderBox]. Follows the same contract as the engine's
/// default measurer (wrap axes report the child's natural size; fixed/match/
/// match-parent axes echo the size the graph resolved), except that a
/// WRAP-styled match axis measured again after a solve is measured at the size
/// the solver capped it to, and that, as in Android's view measurer, every
/// measured size is kept within the widget's match-constraint min and max.
///
/// [_DryMeasurer] measures the same way without laying anything out.
class _FlutterMeasurer implements Measurer {
  _FlutterMeasurer(this._renderOf, this._needsBaseline);

  final Map<ConstraintWidget, RenderBox> _renderOf;

  /// Widgets whose real baseline must be measured: those with a baseline link
  /// and the targets of baseline links. Baselines are only queried for these
  /// because querying a child's baseline makes Flutter propagate that child's
  /// future layout dirtiness to this container, which would stop fixed-size
  /// children from acting as relayout boundaries.
  final Set<ConstraintWidget> _needsBaseline;

  BoxConstraints _rootConstraints = const BoxConstraints();

  /// Widgets whose RenderBox was laid out through this measurer during the
  /// current engine pass, with the latest such layout. Placement uses this to
  /// keep the measure-pass layout when it already matches the resolved size.
  final Map<ConstraintWidget, _MeasuredLayout> laidOut =
      <ConstraintWidget, _MeasuredLayout>{};

  void beginPass(BoxConstraints rootConstraints) {
    _rootConstraints = rootConstraints;
    laidOut.clear();
  }

  /// Lays [child] out under [constraints] and returns its size.
  Size layoutChild(RenderBox child, BoxConstraints constraints) {
    child.layout(constraints, parentUsesSize: true);
    return child.size;
  }

  /// The alphabetic baseline of [child], which [layoutChild] last laid out
  /// under [constraints], or null if it has none.
  double? baselineOf(RenderBox child, BoxConstraints constraints) =>
      child.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true);

  /// The constraints [child] is measured under, from the [constraints] that
  /// size it to its content on each axis where [wrapWidth] or [wrapHeight] is
  /// set. Unchanged here; [_DryMeasurer] lowers them for the minimum
  /// intrinsic sizes.
  BoxConstraints limitContent(
    RenderBox child,
    BoxConstraints constraints, {
    required bool wrapWidth,
    required bool wrapHeight,
  }) => constraints;

  @override
  void measure(ConstraintWidget widget, Measure measure) {
    // Virtual layouts (Flow) are measured through their own measure pass,
    // which internally measures the referenced widgets back through this
    // measurer. Mirrors Android's view-side measurer.
    if (widget is VirtualLayout) {
      var widthMode = BasicMeasure.UNSPECIFIED;
      var heightMode = BasicMeasure.UNSPECIFIED;
      var widthSize = 0;
      var heightSize = 0;
      // matchConstraint axes measure against the available space first
      // (SELF_DIMENSIONS) and against the solver-assigned size on later
      // strategies, mirroring Android's view measurer.
      final givenStrategy =
          measure.measureStrategy == Measure.TRY_GIVEN_DIMENSIONS ||
          measure.measureStrategy == Measure.USE_GIVEN_DIMENSIONS;
      if (widget.getHorizontalDimensionBehaviour() ==
          DimensionBehaviour.matchParent) {
        widthSize = widget.getParent()?.getWidth() ?? 0;
        widthMode = BasicMeasure.EXACTLY;
      } else if (measure.horizontalBehavior == DimensionBehaviour.fixed) {
        widthSize = measure.horizontalDimension;
        widthMode = BasicMeasure.EXACTLY;
      } else if (measure.horizontalBehavior ==
              DimensionBehaviour.matchConstraint &&
          givenStrategy) {
        widthSize = measure.horizontalDimension;
        widthMode = BasicMeasure.EXACTLY;
      } else if (_rootConstraints.hasBoundedWidth) {
        widthSize = _rootConstraints.maxWidth.round();
        widthMode = BasicMeasure.AT_MOST;
      }
      if (widget.getVerticalDimensionBehaviour() ==
          DimensionBehaviour.matchParent) {
        heightSize = widget.getParent()?.getHeight() ?? 0;
        heightMode = BasicMeasure.EXACTLY;
      } else if (measure.verticalBehavior == DimensionBehaviour.fixed) {
        heightSize = measure.verticalDimension;
        heightMode = BasicMeasure.EXACTLY;
      } else if (measure.verticalBehavior ==
              DimensionBehaviour.matchConstraint &&
          givenStrategy) {
        heightSize = measure.verticalDimension;
        heightMode = BasicMeasure.EXACTLY;
      } else if (_rootConstraints.hasBoundedHeight) {
        heightSize = _rootConstraints.maxHeight.round();
        heightMode = BasicMeasure.AT_MOST;
      }
      widget.measure(widthMode, widthSize, heightMode, heightSize);
      measure.measuredWidth = widget.getMeasuredWidth();
      measure.measuredHeight = widget.getMeasuredHeight();
      measure.measuredHasBaseline = false;
      measure.measuredBaseline = 0;
      widget.setMeasureRequested(false);
      return;
    }

    final child = _renderOf[widget];
    // The Measure object is reused across widgets, so every output field must
    // be written on every call or a previous widget's values leak through.
    if (child == null) {
      // Helper widgets (guidelines, barriers) have no RenderBox to measure.
      measure.measuredWidth = measure.horizontalDimension;
      measure.measuredHeight = measure.verticalDimension;
      measure.measuredHasBaseline = false;
      measure.measuredBaseline = 0;
      widget.setMeasureRequested(false);
      return;
    }

    // A WRAP-styled matchConstraint axis sizes to content capped by the
    // constraints, so its content is measured like wrapContent and the engine
    // then applies the cap. The re-measures that follow a solve measure it at
    // the size the solver gave it instead, so content that reflows (wrapping
    // text) sizes its other axis at the capped size. Android's view measurer
    // does the same.
    final wrapW =
        measure.horizontalBehavior == DimensionBehaviour.wrapContent ||
        (measure.horizontalBehavior == DimensionBehaviour.matchConstraint &&
            widget.mMatchConstraintDefaultWidth ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
            !_measuresAtGivenSize(widget, measure, horizontal: true));
    final wrapH =
        measure.verticalBehavior == DimensionBehaviour.wrapContent ||
        (measure.verticalBehavior == DimensionBehaviour.matchConstraint &&
            widget.mMatchConstraintDefaultHeight ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
            !_measuresAtGivenSize(widget, measure, horizontal: false));

    // A size the solver resolved can be negative, when margins add up to more
    // than the space between two anchors; a box cannot be smaller than 0.
    final double minW, maxW, minH, maxH;
    if (wrapW) {
      minW = 0;
      maxW = _rootConstraints.maxWidth;
    } else {
      minW = maxW = math.max(0, measure.horizontalDimension).toDouble();
    }
    if (wrapH) {
      minH = 0;
      maxH = _rootConstraints.maxHeight;
    } else {
      minH = maxH = math.max(0, measure.verticalDimension).toDouble();
    }
    final constraints = limitContent(
      child,
      BoxConstraints(
        minWidth: minW,
        maxWidth: maxW,
        minHeight: minH,
        maxHeight: maxH,
      ),
      wrapWidth: wrapW,
      wrapHeight: wrapH,
    );

    // A re-measure that only pins the child to the size it already took in
    // this pass would lay it out again for the same result, and the tight
    // layout would make it a relayout boundary, cutting its later content
    // changes off from this container. Skip it, as Android's measure cache
    // skips a similar measure spec.
    final last = laidOut[widget];
    final givenStrategy =
        measure.measureStrategy == Measure.TRY_GIVEN_DIMENSIONS ||
        measure.measureStrategy == Measure.USE_GIVEN_DIMENSIONS;
    if (!givenStrategy ||
        last == null ||
        !_isSimilarLayout(last.constraints, last.size, constraints)) {
      laidOut[widget] = (
        constraints: constraints,
        size: layoutChild(child, constraints),
      );
    }
    var measured = laidOut[widget]!;

    var measuredWidth = wrapW
        ? measured.size.width.round()
        : measure.horizontalDimension;
    var measuredHeight = wrapH
        ? measured.size.height.round()
        : measure.verticalDimension;

    // Android's view measurer (ConstraintLayout.Measurer.measure) keeps every
    // measured size within the widget's match-constraint min and max, and
    // when that changes a size, measures the child again at it so its other
    // axis can follow, as wrapping text grows taller at a capped width. The
    // graph relies on it for a match-constraint axis with a single link,
    // which it measures as wrap content and resolves at the measured size;
    // the solver applies the same bounds itself, so with the clamp here both
    // paths agree. Only match-constraint dimensions carry a min or max.
    final width = _limit(
      measuredWidth,
      widget.mMatchConstraintMinWidth,
      widget.mMatchConstraintMaxWidth,
    );
    final height = _limit(
      measuredHeight,
      widget.mMatchConstraintMinHeight,
      widget.mMatchConstraintMaxHeight,
    );
    if (width != measuredWidth || height != measuredHeight) {
      final clampW = width != measuredWidth;
      final clampH = height != measuredHeight;
      // Limited again from the unlowered bounds, since a minimum intrinsic
      // size on the axis the clamp leaves alone depends on the clamped size
      // (wrapping text grows taller at a capped width). The identity for
      // _FlutterMeasurer, so a real layout is unchanged.
      final clamped = limitContent(
        child,
        BoxConstraints(
          minWidth: clampW ? width.toDouble() : minW,
          maxWidth: clampW ? width.toDouble() : maxW,
          minHeight: clampH ? height.toDouble() : minH,
          maxHeight: clampH ? height.toDouble() : maxH,
        ),
        wrapWidth: wrapW && !clampW,
        wrapHeight: wrapH && !clampH,
      );
      measured = (constraints: clamped, size: layoutChild(child, clamped));
      laidOut[widget] = measured;
      measuredWidth = clampW
          ? width
          : wrapW
          ? measured.size.width.round()
          : measure.horizontalDimension;
      measuredHeight = clampH
          ? height
          : wrapH
          ? measured.size.height.round()
          : measure.verticalDimension;
    }
    measure.measuredWidth = measuredWidth;
    measure.measuredHeight = measuredHeight;

    measure.measuredHasBaseline = false;
    measure.measuredBaseline = 0;
    if (_needsBaseline.contains(widget)) {
      final baseline = baselineOf(child, measured.constraints);
      if (baseline != null) {
        measure.measuredHasBaseline = true;
        measure.measuredBaseline = baseline.round();
      }
    }

    widget.setMeasureRequested(false);
  }

  /// Whether a re-measure sizes a WRAP-styled matchConstraint axis at the size
  /// the solver gave it rather than around its content.
  ///
  /// Mirrors Android's view measurer: always on USE_GIVEN_DIMENSIONS, and on
  /// TRY_GIVEN_DIMENSIONS once the other axis is stable (the child's size on
  /// it, from its layout earlier in this pass, is the one the solver kept) or
  /// this axis is already resolved. While the other axis is still settling,
  /// the content is measured again so that both sizes can follow it.
  bool _measuresAtGivenSize(
    ConstraintWidget widget,
    Measure measure, {
    required bool horizontal,
  }) {
    if (measure.measureStrategy == Measure.USE_GIVEN_DIMENSIONS) return true;
    if (measure.measureStrategy != Measure.TRY_GIVEN_DIMENSIONS) return false;
    // The child's size is only known once this measurer has laid it out in
    // this pass.
    final measured = laidOut[widget];
    final otherDimensionStable =
        measured != null &&
        (horizontal
            ? measured.size.height.round() == widget.getHeight()
            : measured.size.width.round() == widget.getWidth());
    return otherDimensionStable ||
        (horizontal
            ? widget.isResolvedHorizontally()
            : widget.isResolvedVertically());
  }

  /// [size] raised to [min] and then lowered to [max], each only when it is
  /// positive: the order and the zero-means-unset convention of Android's
  /// measurer, so a [max] below [min] wins.
  static int _limit(int size, int min, int max) {
    var limited = size;
    if (min > 0 && limited < min) limited = min;
    if (max > 0 && limited > max) limited = max;
    return limited;
  }

  /// Whether laying a child out under [next] repeats its layout under [last],
  /// in which it took [size]: on each axis [next] either equals [last] or pins
  /// the child to the size it already has. Android's `isSimilarSpec`, for box
  /// constraints.
  static bool _isSimilarLayout(
    BoxConstraints last,
    Size size,
    BoxConstraints next,
  ) {
    bool similar(
      double lastMin,
      double lastMax,
      double min,
      double max,
      double extent,
    ) =>
        (min == lastMin && max == lastMax) ||
        (min == max && max == extent.roundToDouble());
    return similar(
          last.minWidth,
          last.maxWidth,
          next.minWidth,
          next.maxWidth,
          size.width,
        ) &&
        similar(
          last.minHeight,
          last.maxHeight,
          next.minHeight,
          next.maxHeight,
          size.height,
        );
  }

  @override
  void didMeasures() {}
}

/// Measures children for the dry-layout queries: the dry layout, the
/// intrinsic sizes, and the dry baseline of a [RenderConstraintLayout].
///
/// Sizes each child with [RenderBox.getDryLayout] and reads its baseline with
/// [RenderBox.getDryBaseline] instead of laying it out, so a query changes no
/// child. A child under tight constraints is not asked for its size, which
/// the constraints already fix.
///
/// A child that cannot answer (in a debug build, a `LayoutBuilder` throws,
/// since it cannot compute a dry layout) has its error reported once per
/// query, and then measures at the smallest size its constraints allow and
/// without a baseline, so the query still returns a result.
class _DryMeasurer extends _FlutterMeasurer {
  _DryMeasurer(
    this._layout,
    super.renderOf,
    super.needsBaseline, {
    this.minimumAxis,
  });

  /// The layout whose query this measures for, named in error reports.
  final RenderConstraintLayout _layout;

  /// When set, each child that sizes to its content along this axis measures
  /// at no more than its own minimum intrinsic size along it.
  final Axis? minimumAxis;

  /// Children whose dry measurement threw during this query.
  final Set<RenderBox> _failed = <RenderBox>{};

  @override
  Size layoutChild(RenderBox child, BoxConstraints constraints) {
    if (constraints.isTight) return constraints.smallest;
    final size =
        _ask(child, () => child.getDryLayout(constraints)) ??
        constraints.smallest;
    // A child that expands to fill an unbounded axis could not be laid out
    // under these constraints at all. A query (for an intrinsic size, say)
    // measures it collapsed on that axis instead, which is also the intrinsic
    // size an expanding box reports.
    return Size(
      size.width.isFinite ? size.width : constraints.minWidth,
      size.height.isFinite ? size.height : constraints.minHeight,
    );
  }

  @override
  double? baselineOf(RenderBox child, BoxConstraints constraints) =>
      dryBaseline(child, constraints, TextBaseline.alphabetic);

  /// The [baseline] of [child] under [constraints], or null if it has none.
  double? dryBaseline(
    RenderBox child,
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => _ask(child, () => child.getDryBaseline(constraints, baseline));

  @override
  BoxConstraints limitContent(
    RenderBox child,
    BoxConstraints constraints, {
    required bool wrapWidth,
    required bool wrapHeight,
  }) {
    if (minimumAxis == Axis.horizontal && wrapWidth) {
      final minimum = _ask(
        child,
        () => child.getMinIntrinsicWidth(constraints.maxHeight),
      );
      if (minimum != null && minimum < constraints.maxWidth) {
        return constraints.copyWith(
          maxWidth: math.max(constraints.minWidth, minimum),
        );
      }
    } else if (minimumAxis == Axis.vertical && wrapHeight) {
      final minimum = _ask(
        child,
        () => child.getMinIntrinsicHeight(constraints.maxWidth),
      );
      if (minimum != null && minimum < constraints.maxHeight) {
        return constraints.copyWith(
          maxHeight: math.max(constraints.minHeight, minimum),
        );
      }
    }
    return constraints;
  }

  /// Runs [query] against [child] and returns its result, or null if it
  /// throws or the child already threw during this query.
  ///
  /// What it throws is reported rather than rethrown, so that one child that
  /// cannot be measured without a layout does not fail the whole query.
  T? _ask<T extends Object>(RenderBox child, T? Function() query) {
    if (_failed.contains(child)) return null;
    try {
      return query();
    } catch (exception, stack) {
      _failed.add(child);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'flutter_constraint_layout',
          context: ErrorDescription(
            'while measuring a child of a ConstraintLayout for a dry layout, '
            'intrinsic size, or dry baseline',
          ),
          informationCollector: () => <DiagnosticsNode>[
            _layout.describeForError('The ConstraintLayout was'),
            child.describeForError('The child was'),
            ErrorHint(
              'The ConstraintLayout measured the child at the smallest size '
              'its constraints allow, so the size it computed may be wrong. '
              'Flutter does not recover a render object whose dry layout '
              'threw, so such a child can report more errors when it is next '
              'laid out. A child with a fixed size is never asked for its '
              'size: give it one, or use a widget that supports dry layout.',
            ),
          ],
        ),
      );
      return null;
    }
  }
}
