import 'dart:math' as math;

import 'package:constraint_engine/constraint_engine.dart';
import 'package:flutter/foundation.dart' show kDebugMode, listEquals;
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

part 'render/engine_model.dart';
part 'render/measurers.dart';

/// Refers to the [ConstraintLayout] container itself when used as an anchor
/// target, for example `top: .topOf(parent)`.
const Symbol parent = #parent;

/// Whether every replay also runs the full pipeline and checks that it gives
/// the same result (`--dart-define=cl.verifyReplay=true`): a replayed layout
/// ([RenderConstraintLayout.debugReplayMismatches]), a replayed dry query
/// ([RenderConstraintLayout.debugDryReplayMismatches]), and a child baseline
/// a debug build answers again without asking the child
/// ([RenderConstraintLayout.debugReusedBaselineMismatches]).
const bool _verifyReplay = bool.fromEnvironment('cl.verifyReplay');

/// Android's ConstraintLayout optimization flags
/// (`app:layout_optimizationLevel`, `ConstraintLayout.setOptimizationLevel`),
/// combined with `|`.
///
/// The values are Android's, which are also the engine's [Optimizer]
/// constants. The default, [standard], is Android's default: [direct] and
/// [cacheMeasures]. The dependency graph ([graph], [graphWrap]) is an
/// opt-in, as on Android, and runs exactly where Android runs it.
///
/// Some flags are accepted for parity only. Android reads [barrier],
/// [chains], [dimensions], [ratio] and [groups] nowhere, and the passes of
/// [dependencyOrdering] and [grouping] are not ported, so these change
/// nothing.
///
/// ```dart
/// ConstraintLayout(
///   optimizationLevel: OptimizationLevel.standard | OptimizationLevel.graph,
///   children: [
///     // ...
///   ],
/// )
/// ```
extension type const OptimizationLevel._(int value) implements Object {
  /// No optimization (`OPTIMIZATION_NONE`, 0): the solver resolves every
  /// layout and the children's measures are never answered from a cache.
  static const OptimizationLevel none = OptimizationLevel._(
    Optimizer.OPTIMIZATION_NONE,
  );

  /// Direct resolution (`OPTIMIZATION_DIRECT`, 1): in the first measure
  /// pass, everything that follows directly from the links is resolved
  /// before the solver runs, and the children it sizes are measured then.
  static const OptimizationLevel direct = OptimizationLevel._(
    Optimizer.OPTIMIZATION_DIRECT,
  );

  /// `OPTIMIZATION_BARRIER` (2). Android reads it nowhere; it changes
  /// nothing.
  static const OptimizationLevel barrier = OptimizationLevel._(
    Optimizer.OPTIMIZATION_BARRIER,
  );

  /// `OPTIMIZATION_CHAIN` (4). Android reads it nowhere; it changes
  /// nothing.
  static const OptimizationLevel chains = OptimizationLevel._(
    Optimizer.OPTIMIZATION_CHAIN,
  );

  /// `OPTIMIZATION_DIMENSIONS` (8). Android reads it nowhere; it changes
  /// nothing.
  static const OptimizationLevel dimensions = OptimizationLevel._(
    Optimizer.OPTIMIZATION_DIMENSIONS,
  );

  /// `OPTIMIZATION_RATIO` (16). Android reads it nowhere; it changes
  /// nothing.
  static const OptimizationLevel ratio = OptimizationLevel._(
    Optimizer.OPTIMIZATION_RATIO,
  );

  /// `OPTIMIZATION_GROUPS` (32). Android reads it nowhere; it changes
  /// nothing.
  static const OptimizationLevel groups = OptimizationLevel._(
    Optimizer.OPTIMIZATION_GROUPS,
  );

  /// The dependency graph (`OPTIMIZATION_GRAPH`, 64), an opt-in: when no
  /// child is in a chain or is a flow or a grid, and both of the layout's
  /// axes are bounded, the graph resolves the layout first, and the solver
  /// runs only for what it leaves unresolved, as on Android.
  static const OptimizationLevel graph = OptimizationLevel._(
    Optimizer.OPTIMIZATION_GRAPH,
  );

  /// The dependency graph whatever the layout's constraints
  /// (`OPTIMIZATION_GRAPH_WRAP`, 128), an opt-in: as [graph], and also when
  /// an axis is unbounded, where the graph resolves only the bounded axes
  /// and the solver runs as well, as on Android.
  static const OptimizationLevel graphWrap = OptimizationLevel._(
    Optimizer.OPTIMIZATION_GRAPH_WRAP,
  );

  /// Measure caching (`OPTIMIZATION_CACHE_MEASURES`, 256): a child already
  /// measured at its current size under an equivalent request keeps that
  /// size without being measured again.
  static const OptimizationLevel cacheMeasures = OptimizationLevel._(
    Optimizer.OPTIMIZATION_CACHE_MEASURES,
  );

  /// `OPTIMIZATION_DEPENDENCY_ORDERING` (512). Not ported; it changes
  /// nothing.
  static const OptimizationLevel dependencyOrdering = OptimizationLevel._(
    Optimizer.OPTIMIZATION_DEPENDENCY_ORDERING,
  );

  /// `OPTIMIZATION_GROUPING` (1024). Not ported; it changes nothing.
  static const OptimizationLevel grouping = OptimizationLevel._(
    Optimizer.OPTIMIZATION_GROUPING,
  );

  /// Android's default (`OPTIMIZATION_STANDARD`, 257): [direct] and
  /// [cacheMeasures].
  static const OptimizationLevel standard = OptimizationLevel._(
    Optimizer.OPTIMIZATION_STANDARD,
  );

  /// Both levels' flags.
  OptimizationLevel operator |(OptimizationLevel other) =>
      OptimizationLevel._(value | other.value);
}

/// A layout that positions its children using constraint anchors, inspired by
/// Android's ConstraintLayout.
///
/// Wrap each child in a `Constrained` to describe how it is positioned and
/// sized relative to [parent] or to sibling ids. The layout measures and
/// places its children as Android's ConstraintLayout does, with the pure-Dart
/// port of its engine in `package:constraint_engine`.
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
    this.optimizationLevel = OptimizationLevel.standard,
    this.debugShowChains = false,
    this.debugShowBlueprint = false,
    this.debugChainColor,
    this.debugBlueprintLabelStyle = DebugLabelStyle.both,
    super.children,
  });

  /// Resolves `start`/`end` links. Defaults to the ambient [Directionality].
  final TextDirection? textDirection;

  /// Android's optimization flags for this layout: [OptimizationLevel.standard]
  /// (Android's default) unless set. The dependency graph is an opt-in
  /// ([OptimizationLevel.graph]).
  final OptimizationLevel optimizationLevel;

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
      optimizationLevel: optimizationLevel,
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
      ..optimizationLevel = optimizationLevel
      ..debugShowChains = debugShowChains
      ..debugShowBlueprint = debugShowBlueprint
      ..debugChainColor = debugChainColor
      ..debugBlueprintLabelStyle = debugBlueprintLabelStyle;
  }
}

/// The render object backing [ConstraintLayout].
///
/// ## Layout
///
/// The render object keeps a persistent engine model: a container standing
/// for the layout, holding one engine widget per child in child order. It
/// keeps the model in sync incrementally. Child list changes (insert, remove,
/// move), id renames, and text-direction changes rebuild it; every other
/// configuration change is applied to the affected engine widgets in place,
/// and a `ConstraintGroup`'s visibility reaches each child it references the
/// way a change of the child's own visibility would.
///
/// Each layout then does what Android's ConstraintLayout view does, at the
/// layout's [optimizationLevel]:
///
///  * It measures the layout under the measure specs Android's parent would
///    give it: a bounded axis is EXACTLY its maximum (rounded to a whole
///    pixel), so the layout fills it, and an unbounded axis is UNSPECIFIED,
///    so the layout wraps its children there, with the incoming minimum as
///    the layout's minimum size. Every child is measured as Android's view
///    measurer measures it: laid out under the box constraints its measure
///    spec stands for (EXACTLY is tight, AT_MOST is loose, UNSPECIFIED is
///    unbounded), its size rounded up to whole pixels, and its baseline read.
///  * It places every child at its integer frame. A child whose last layout
///    during the measure already has exactly the frame's size keeps that
///    layout; any other child is laid out again, tight at its frame.
///  * Its size is the measured size, constrained by the incoming constraints.
///
/// ## Replaying a layout
///
/// Android measures the whole layout again whenever it is asked to. Here a
/// layout that repeats one of the two layouts before it is replayed instead:
/// when the configuration and the incoming constraints are those of the last
/// layout, and that layout gave the same result as the one before it, every
/// child is asked again for each measure the last layout asked of it, and
/// when every answer is the same, the children are placed where the last
/// layout placed them without running the engine. A replay therefore saves
/// the engine's work, not the children's layouts. With
/// `--dart-define=cl.verifyReplay=true` a replayed layout also runs in full
/// and reports any difference (see [debugReplayMismatches]).
///
/// Every measure reads the child's baseline. In a debug build, where each
/// read costs a timeline event even when Flutter has the value cached, a
/// child that has not needed layout since the layout last read its baseline
/// under the same constraints answers that read again without being asked:
/// the value Flutter's cache holds (see [debugReusedBaselines]).
///
/// ## Dry layout, intrinsic sizes, and baseline
///
/// [getDryLayout] returns the size [performLayout] gives the layout under the
/// same constraints. On a bounded axis that is the maximum, whatever the
/// children. On an unbounded axis it comes from a measure of a throwaway
/// model of the children, which measures each child with its own
/// [RenderBox.getDryLayout] and [RenderBox.getDryBaseline] instead of laying
/// it out. That model is new, so the query gives the size of a first layout
/// of the configuration. A later layout keeps what Android's keeps from the
/// layout before it, so where Android's second layout differs from its first
/// the laid-out size can differ from the dry one, as Android's own second
/// measure differs from its first: on some degenerate flows at the default
/// level, and more often without [OptimizationLevel.direct], where a barrier
/// that resolves without the solver (every widget it references gone and not
/// counted) stays at 0 from its second layout on, and at the graph levels. A
/// dry query lays out no child and leaves the persistent model untouched,
/// and costs about as much as a layout that has to run the engine.
/// A query that repeats the last one that ran the engine (the same
/// configuration and constraints) is replayed as a layout is: every child is
/// asked again for each measure that query asked of it, and when every answer
/// is the same, the query gives that query's result without running the
/// engine (also checked by `--dart-define=cl.verifyReplay=true`).
///
/// The intrinsic sizes are defined by that dry layout:
///
///  * [getMaxIntrinsicWidth] for a height is the width of the dry layout with
///    an unbounded width and, when the height is finite, that height as a
///    tight constraint: the width the layout wraps its children to.
///    [getMaxIntrinsicHeight] is the same on the other axis.
///  * [getMinIntrinsicWidth] runs the same measure, but measures each child
///    that sizes to its content horizontally at no more than the child's own
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
/// gone children, and helpers (guidelines, barriers, groups, flows, and
/// grids), do not count, and without a child that has a baseline the layout
/// has none. Android's ConstraintLayout reports no baseline of its own.
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
    OptimizationLevel optimizationLevel = OptimizationLevel.standard,
    bool debugShowChains = false,
    bool debugShowBlueprint = false,
    Color? debugChainColor,
    DebugLabelStyle debugBlueprintLabelStyle = DebugLabelStyle.both,
  })
    // ignore: prefer_initializing_formals
    : _textDirection = textDirection,
       // ignore: prefer_initializing_formals
       _optimizationLevel = optimizationLevel,
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

  OptimizationLevel _optimizationLevel;

  /// Android's optimization flags the layout is measured with.
  OptimizationLevel get optimizationLevel => _optimizationLevel;
  set optimizationLevel(OptimizationLevel value) {
    if (_optimizationLevel == value) return;
    _optimizationLevel = value;
    // The model does not change, but the next layout must not replay one
    // measured at the old level.
    _configEpoch++;
    markNeedsLayout();
  }

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

  // The persistent engine model, kept in sync with the children across
  // layouts, with its measurer and the host that measures it. All three are
  // non-null whenever _needsModelRebuild is false.
  _EngineModel? _model;
  _FlutterMeasurer? _measurer;
  ViewHost? _host;
  bool _needsModelRebuild = true;

  /// Advances whenever the configuration the engine measures changes: a
  /// model build, an in-place apply, and an optimization level change. Part
  /// of a layout's replay key.
  int _configEpoch = 0;

  /// The last full run of the engine, the one a replay repeats.
  _ReplayRun? _lastRun;

  /// Number of [performLayout] executions. Test instrumentation.
  @visibleForTesting
  int debugLayoutPasses = 0;

  /// Number of full engine-model rebuilds. Test instrumentation.
  @visibleForTesting
  int debugModelBuilds = 0;

  /// Number of layouts whose result came from a measure of the engine.
  /// Test instrumentation.
  @visibleForTesting
  int debugEnginePasses = 0;

  /// Number of layouts whose result came from a replay of the last layout,
  /// without running the engine. Test instrumentation.
  ///
  /// With `--dart-define=cl.verifyReplay=true` a replayed layout also runs
  /// the engine, and counts in [debugEnginePasses] too.
  @visibleForTesting
  int debugReplayPasses = 0;

  /// Number of replayed layouts whose full run, with
  /// `--dart-define=cl.verifyReplay=true`, gave a different result. Each one
  /// is also reported as an error, and the layout takes the full run's
  /// result. It must stay 0. Test instrumentation.
  @visibleForTesting
  int debugReplayMismatches = 0;

  /// Number of children whose config was re-applied to the persistent model
  /// in place. Test instrumentation.
  @visibleForTesting
  int debugConfigApplies = 0;

  /// Number of dry queries (a dry layout, an intrinsic size or a dry
  /// baseline whose measure Flutter had not cached) that measured a new
  /// throwaway model with the engine. Test instrumentation.
  ///
  /// With `--dart-define=cl.verifyReplay=true` a replayed query also runs
  /// the engine, and counts here too.
  @visibleForTesting
  int debugDryEnginePasses = 0;

  /// Number of dry queries answered by a replay of the last one that ran the
  /// engine, without running it (see [_DryRun]). Test instrumentation.
  @visibleForTesting
  int debugDryReplayPasses = 0;

  /// Number of replayed dry queries whose full run, with
  /// `--dart-define=cl.verifyReplay=true`, gave a different result. Each one
  /// is also reported as an error, and the query takes the full run's
  /// result. It must stay 0. Test instrumentation.
  @visibleForTesting
  int debugDryReplayMismatches = 0;

  /// Number of child baselines a layout answered again in a debug build
  /// without asking the child, as Flutter's cache would answer (see
  /// [_FlutterMeasurer.childBaseline]). Test instrumentation.
  @visibleForTesting
  int debugReusedBaselines = 0;

  /// Number of reused child baselines whose dual run, with
  /// `--dart-define=cl.verifyReplay=true`, asked the child and got another
  /// value. Each one is also reported as an error, and the measure takes the
  /// child's answer. It must stay 0. Test instrumentation.
  @visibleForTesting
  int debugReusedBaselineMismatches = 0;

  /// Whether a model build gives its measurer a request transcript
  /// ([ViewMeasurer.transcript]), which then holds the measure requests of
  /// the last layout that ran the engine, in the parity oracle's format.
  /// Test instrumentation: set it before the layout is built, and reset it
  /// afterwards.
  @visibleForTesting
  static bool debugRecordTranscripts = false;

  /// The persistent engine container: the layout's engine widget, whose
  /// children are the children's engine widgets in child order. Null before
  /// the first layout and after a layout without children. Test
  /// instrumentation.
  @visibleForTesting
  ConstraintWidgetContainer? get debugEngineContainer => _model?.container;

  /// The host that measures the persistent model, whose
  /// [ViewHost.measurer] is the children's measurer. Test instrumentation.
  @visibleForTesting
  ViewHost? get debugViewHost => _host;

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

  // A structural change also drops the kept dry queries, which reference the
  // children: a query cannot replay them before the next build anyway.
  @override
  void insert(RenderBox child, {RenderBox? after}) {
    _needsModelRebuild = true;
    _forgetDryRuns();
    super.insert(child, after: after);
  }

  @override
  void remove(RenderBox child) {
    _needsModelRebuild = true;
    _forgetDryRuns();
    super.remove(child);
  }

  @override
  void removeAll() {
    _needsModelRebuild = true;
    _forgetDryRuns();
    super.removeAll();
  }

  @override
  void move(RenderBox child, {RenderBox? after}) {
    _needsModelRebuild = true;
    _forgetDryRuns();
    super.move(child, after: after);
  }

  @override
  void detach() {
    // A detached layout keeps no throwaway model alive.
    _forgetDryRuns();
    super.detach();
  }

  void _discardModel() {
    _model = null;
    _measurer = null;
    _host = null;
    _lastRun = null;
    _forgetDryRuns();
    _needsModelRebuild = true;
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    debugLayoutPasses++;

    if (childCount == 0) {
      _discardModel();
      size = _sizeWithoutEngine(constraints);
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

    if (_needsModelRebuild) {
      _buildModel(constraints);
      debugModelBuilds++;
    } else if (anyConfigDirty) {
      _applyConfigInPlace(_model!);
    }
    final model = _model!;
    final measurer = _measurer!;

    final last = _lastRun;
    if (last != null &&
        last.confirmed &&
        last.epoch == _configEpoch &&
        last.constraints == constraints &&
        _replays(measurer, last)) {
      debugReplayPasses++;
      if (!_verifyReplay) {
        _place(model, measurer, last.frames);
        size = constraints.constrain(last.measuredSize);
        return;
      }
      final run = _runEngine(model, measurer, constraints);
      final same = run.repeats(last);
      if (!same) {
        debugReplayMismatches++;
        _reportReplayMismatch(last, run);
      }
      run.confirmed = same;
      _lastRun = run;
      return;
    }

    final run = _runEngine(model, measurer, constraints);
    // A run is replayed only once the run after it gave the same result: see
    // _ReplayRun.confirmed.
    run.confirmed = last != null && run.repeats(last);
    _lastRun = run;
  }

  /// Applies the configuration of every child marked dirty to its engine
  /// widget in [model], in place.
  void _applyConfigInPlace(_EngineModel model) {
    // Set until every change is applied. Applying one can throw (an unknown
    // id, in a debug build) after resetting its widget, and as in
    // _buildModel, the half-applied model must not stay behind looking
    // clean: the next layout rebuilds and reports the problem again.
    _needsModelRebuild = true;
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
    _configEpoch++;
  }

  /// Measures the persistent [model] with the engine under [constraints],
  /// recording the run, then places the children and sizes the layout.
  _ReplayRun _runEngine(
    _EngineModel model,
    _FlutterMeasurer measurer,
    BoxConstraints constraints,
  ) {
    // A run that throws leaves the engine and the children's measure state
    // partly updated, which a replay of an earlier run would not repeat.
    _lastRun = null;
    final host = _host!;
    _syncModelForMeasure(model);
    final specs = _hostSpecsFor(constraints);
    host
      ..setRtl(!_ltr)
      ..optimizationLevel = _optimizationLevel.value
      ..minWidth = specs.minWidth
      ..minHeight = specs.minHeight;
    measurer.beginPass(record: true);
    host.measure(specs.widthSpec, specs.heightSpec);
    debugEnginePasses++;
    final transcript = measurer.recording!;
    measurer.recording = null;

    final run = _ReplayRun(
      epoch: _configEpoch,
      constraints: constraints,
      transcript: transcript,
      frames: _framesOf(model),
      measuredWidth: host.getMeasuredWidth(),
      measuredHeight: host.getMeasuredHeight(),
    );
    _place(model, measurer, run.frames);
    size = constraints.constrain(run.measuredSize);
    return run;
  }

  /// Whether every child answers each content measure of [run] as it did
  /// in [run], asked again in the same order.
  ///
  /// The engine's run is a function of the configuration, the specs, these
  /// answers, and the state the run before it left; [run] being confirmed
  /// makes that state the one a full run would leave. So when every answer
  /// is the same, a full run would repeat [run] exactly.
  bool _replays(_FlutterMeasurer measurer, _ReplayRun run) {
    measurer.beginPass(record: false);
    for (final request in run.transcript.contents) {
      final answer = measurer._measureContent(
        request.widget,
        request.content,
        request.widthSpec,
        request.heightSpec,
      );
      if (answer.width != request.width ||
          answer.height != request.height ||
          answer.baseline != request.baseline) {
        return false;
      }
    }
    return true;
  }

  /// The frame of every child of [model] as the engine left it: `x, y,
  /// width, height` per child, in child order.
  static List<int> _framesOf(_EngineModel model) {
    final widgets = model.widgets;
    final frames = List<int>.filled(widgets.length * 4, 0);
    for (var i = 0; i < widgets.length; i++) {
      final w = widgets[i];
      frames[4 * i] = w.getX();
      frames[4 * i + 1] = w.getY();
      frames[4 * i + 2] = w.getWidth();
      frames[4 * i + 3] = w.getHeight();
    }
    return frames;
  }

  /// Places every child of [model] at its frame in [frames] (CL 2001-2070).
  ///
  /// A child whose last layout by [measurer] in this pass has exactly the
  /// frame's size keeps that layout, under the constraints it was measured
  /// with; every other child is laid out tight at its frame. Gone children,
  /// helpers and groups are placed too, at 0 x 0. A box cannot be smaller
  /// than 0, so a negative engine size places the child at 0 on that axis
  /// (Android's setFrame already zeroes the frame of a child whose solved
  /// edges cross).
  ///
  /// A child keeps its offset object when the frame's position equals it
  /// (offsets are values, read by value).
  static void _place(
    _EngineModel model,
    _FlutterMeasurer measurer,
    List<int> frames,
  ) {
    for (var i = 0; i < model.children.length; i++) {
      final width = math.max(0, frames[4 * i + 2]).toDouble();
      final height = math.max(0, frames[4 * i + 3]).toDouble();
      final content = model.contentAt[i];
      if (!measurer._laidOutAt(content, width, height)) {
        measurer.placeChild(
          model.children[i],
          content,
          BoxConstraints.tight(Size(width, height)),
        );
      }
      final pd = model.childData[i];
      final x = frames[4 * i].toDouble();
      final y = frames[4 * i + 1].toDouble();
      if (pd.offset.dx != x || pd.offset.dy != y) {
        pd.offset = Offset(x, y);
      }
    }
  }

  void _reportReplayMismatch(_ReplayRun replayed, _ReplayRun full) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary(
            'A replayed ConstraintLayout layout differs from its full run.',
          ),
          ErrorDescription(
            'The replay placed the children at ${replayed.frames} in a '
            '${replayed.measuredSize} layout, after '
            '${replayed.transcript.requests.length} measure requests and '
            '${replayed.transcript.contents.length} content measures. The '
            'full run placed them at ${full.frames} in a '
            '${full.measuredSize} layout, after '
            '${full.transcript.requests.length} measure requests and '
            '${full.transcript.contents.length} content measures.',
          ),
          ErrorHint('The layout takes the full run\'s result.'),
        ]),
        library: 'flutter_constraint_layout',
        context: ErrorDescription('while verifying a replayed layout'),
        informationCollector: () => <DiagnosticsNode>[
          describeForError('The ConstraintLayout was'),
        ],
      ),
    );
  }

  void _reportDryReplayMismatch(_DryRun replayed, _DryRun? full) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary(
            'A replayed ConstraintLayout dry query differs from its full run.',
          ),
          ErrorDescription(
            'The replay measured the layout at ${replayed.measuredSize}, '
            'after ${replayed.transcript.contents.length} content measures. '
            '${full == null ? 'The full run threw.' : 'The full run '
                      'measured it at ${full.measuredSize}, after '
                      '${full.transcript.contents.length} content measures.'}',
          ),
          ErrorHint('The query takes the full run\'s result.'),
        ]),
        library: 'flutter_constraint_layout',
        context: ErrorDescription('while verifying a replayed dry query'),
        informationCollector: () => <DiagnosticsNode>[
          describeForError('The ConstraintLayout was'),
        ],
      ),
    );
  }

  /// The size the layout takes under [constraints] when the engine does not
  /// need to run: what Android's layout view measures without a child, and
  /// with children when both axes are bounded. A bounded axis is its spec
  /// size (the maximum, rounded); an unbounded axis is its minimum, which
  /// the engine's container would only exceed to fit children.
  static Size _sizeWithoutEngine(BoxConstraints constraints) {
    final specs = _hostSpecsFor(constraints);
    double extent(int spec, int min) =>
        ((MeasureSpec.getMode(spec) == MeasureSpec.EXACTLY
                    ? MeasureSpec.getSize(spec)
                    : math.max(0, min)) &
                MeasureSpec.MEASURED_SIZE_MASK)
            .toDouble();
    return constraints.constrain(
      Size(
        extent(specs.widthSpec, specs.minWidth),
        extent(specs.heightSpec, specs.minHeight),
      ),
    );
  }

  @override
  @protected
  Size computeDryLayout(covariant BoxConstraints constraints) {
    // With both axes bounded, both specs are EXACTLY, and the measured size
    // is exactly the spec sizes whatever the children: no engine run.
    if (childCount == 0 ||
        (constraints.hasBoundedWidth && constraints.hasBoundedHeight)) {
      return _sizeWithoutEngine(constraints);
    }
    final resolved = _resolveDry(constraints);
    if (resolved == null) return constraints.smallest;
    return constraints.constrain(_measuredSizeOf(resolved.host));
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
    final (:model, :measurer, host: _) = resolved;
    var result = BaselineOffset.noBaseline;
    for (var i = 0; i < model.children.length; i++) {
      if (!_contributesBaseline(model, model.childData[i])) continue;
      final w = model.widgets[i];
      // The constraints the child ends up with after the placement of
      // performLayout, where its baseline is read.
      final frame = Size(
        math.max(0, w.getWidth()).toDouble(),
        math.max(0, w.getHeight()).toDouble(),
      );
      final measured = measurer.laidOutOf(w);
      final placed = measured != null && measured.size == frame
          ? measured.constraints
          : BoxConstraints.tight(frame);
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
    final size = constraints.constrain(_measuredSizeOf(resolved.host));
    return switch (axis) {
      Axis.horizontal => size.width,
      Axis.vertical => size.height,
    };
  }

  /// The size [host] measured its layout at.
  static Size _measuredSizeOf(ViewHost host) => Size(
    host.getMeasuredWidth().toDouble(),
    host.getMeasuredHeight().toDouble(),
  );

  /// Measures a throwaway engine model of the children under [constraints],
  /// as [performLayout] measures the persistent one, but with a measurer that
  /// sizes each child with its dry layout instead of laying it out.
  ///
  /// With [minimumAxis], each child that sizes to its content along that axis
  /// measures at no more than its own minimum intrinsic size there.
  ///
  /// Returns null, after reporting the error, if measuring the model throws.
  /// A dry query must not throw: Flutter clears the flag that marks a dry
  /// layout or dry baseline in progress only when the computation returns,
  /// so an exception would leave this render object failing assertions in
  /// every later layout. For the same reason the throwaway model skips
  /// unknown ids, which the layout pass reports.
  ///
  /// A query that repeats the last one of its kind that ran the engine
  /// ([_dryRuns]: the same configuration, constraints and [minimumAxis]) is
  /// replayed when every child answers each of its content measures as
  /// before: see [_DryRun].
  ({_EngineModel model, _DryMeasurer measurer, ViewHost host})? _resolveDry(
    BoxConstraints constraints, {
    Axis? minimumAxis,
  }) {
    final slot = _drySlotOf(minimumAxis);
    final settled = _configSettled();
    final last = _dryRuns[slot];
    assert(
      last == null || last.minimumAxis == minimumAxis,
      'each slot of _dryRuns keeps the queries of one minimum-intrinsic axis, '
      'which the replay needs: the axis decides how every child is measured',
    );
    if (settled &&
        last != null &&
        last.epoch == _configEpoch &&
        last.constraints == constraints &&
        _dryReplays(last)) {
      debugDryReplayPasses++;
      if (!_verifyReplay) return last.resolved;
      final full = _runDry(constraints, minimumAxis);
      if (full == null || !full.sameResultAs(last)) {
        debugDryReplayMismatches++;
        _reportDryReplayMismatch(last, full);
        _dryRuns[slot] = full != null && full.measurer._failed.isEmpty
            ? full
            : null;
        return full?.resolved;
      }
      return last.resolved;
    }
    final run = _runDry(constraints, minimumAxis);
    if (run == null) return null;
    // A query in which a child failed reported it; it is not kept, so the
    // next query asks and reports again, as every query does.
    if (settled && run.measurer._failed.isEmpty) {
      _dryRuns[slot] = run;
    }
    return run.resolved;
  }

  /// The last dry query of each kind that ran the engine, kept for a replay
  /// by [_resolveDry]: at [_drySlotOf] its minimum-intrinsic axis, as a
  /// minimum intrinsic size asks two kinds (see [computeMinIntrinsicWidth]).
  /// Each holds a throwaway model, so a layout that is asked keeps up to
  /// three besides its own.
  final List<_DryRun?> _dryRuns = List<_DryRun?>.filled(3, null);

  /// The index in [_dryRuns] of a query with [minimumAxis].
  static int _drySlotOf(Axis? minimumAxis) => switch (minimumAxis) {
    null => 0,
    Axis.horizontal => 1,
    Axis.vertical => 2,
  };

  /// Drops every kept dry query ([_dryRuns]).
  void _forgetDryRuns() => _dryRuns.fillRange(0, _dryRuns.length, null);

  /// Whether every configuration change has reached the persistent model, so
  /// that [_configEpoch] names the configuration a model built now has: no
  /// rebuild pending, the model's children are the children in order, and no
  /// child's parent data holds a change the next layout would apply. (A query
  /// before that layout reads the change; see [_resolveDry].)
  bool _configSettled() {
    final model = _model;
    if (_needsModelRebuild || model == null) return false;
    final modelChildren = model.children;
    var i = 0;
    RenderBox? child = firstChild;
    while (child != null) {
      final pd = child.parentData! as ConstraintParentData;
      if (i >= modelChildren.length ||
          !identical(modelChildren[i], child) ||
          pd.configDirty ||
          pd.structuralDirty) {
        return false;
      }
      child = pd.nextSibling;
      i++;
    }
    return i == modelChildren.length;
  }

  /// Whether every child answers each content measure of the dry query [run]
  /// as it did in [run], asked again in the same order through [run]'s
  /// measurer (which notes each child's latest dry layout again, as the run
  /// left it when every answer is the same). A child that throws ends the
  /// replay without a report: the full query that follows asks it and
  /// reports, as it always does.
  bool _dryReplays(_DryRun run) {
    final measurer = run.measurer
      ..beginPass(record: false)
      .._probing = true
      .._probeFailed = false;
    try {
      for (final request in run.transcript.contents) {
        final answer = measurer._measureContent(
          request.widget,
          request.content,
          request.widthSpec,
          request.heightSpec,
        );
        if (measurer._probeFailed ||
            answer.width != request.width ||
            answer.height != request.height ||
            answer.baseline != request.baseline) {
          return false;
        }
      }
      return true;
    } finally {
      measurer._probing = false;
    }
  }

  /// Measures a new throwaway model under [constraints] (see [_resolveDry]),
  /// recording its content measures for a replay. Returns null, after
  /// reporting the error, if measuring the model throws.
  _DryRun? _runDry(BoxConstraints constraints, Axis? minimumAxis) {
    try {
      // A new model: what Android's first layout of the configuration
      // measures. The persistent one also carries what its last measure left
      // (see the class doc).
      final model = _createModel(constraints, reportsUnknownIds: false);
      final measurer = _DryMeasurer(this, model, minimumAxis: minimumAxis);
      final host = ViewHost(model.container, measurer);
      final specs = _hostSpecsFor(constraints);
      host
        ..setRtl(!_ltr)
        ..optimizationLevel = _optimizationLevel.value
        ..minWidth = specs.minWidth
        ..minHeight = specs.minHeight;
      measurer.beginPass(record: true, requests: false);
      host.measure(specs.widthSpec, specs.heightSpec);
      debugDryEnginePasses++;
      final transcript = measurer.recording!;
      measurer.recording = null;
      return _DryRun(
        epoch: _configEpoch,
        constraints: constraints,
        minimumAxis: minimumAxis,
        model: model,
        measurer: measurer,
        host: host,
        transcript: transcript,
      );
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

  /// Rebuilds the persistent engine model from scratch, with a new measurer
  /// and host.
  void _buildModel(BoxConstraints constraints) {
    // Dropped before the build: applying config can throw (an unresolvable
    // link id reports through an assert), and a half-built or stale model
    // must not stay behind. _needsModelRebuild is only cleared once the build
    // succeeded, so every later layout rebuilds and re-reports the real
    // problem instead of resolving a model that looks clean.
    _model = null;
    _measurer = null;
    _host = null;
    _lastRun = null;
    _forgetDryRuns();
    final model = _createModel(constraints, reportsUnknownIds: true);
    _publishGroupOverrides(model);
    for (final pd in model.childData) {
      pd.configDirty = false;
      pd.structuralDirty = false;
    }
    final measurer = _FlutterMeasurer(this, model);
    // Installs the measurer on the container before anything measures: a
    // flow keeps the measurer it first finds there.
    final host = ViewHost(model.container, measurer);
    if (debugRecordTranscripts) {
      measurer.transcript = StringBuffer();
    }
    _model = model;
    _measurer = measurer;
    _host = host;
    _needsModelRebuild = false;
    _configEpoch++;
  }

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

/// One full run of the engine on the persistent model: its keys, its
/// transcript, the frames it gave the children, and the layout's measured
/// size.
///
/// A run is a function of the configuration (fixed by [epoch]), the specs
/// (fixed by [constraints]), the children's answers to its content measures,
/// and the state the run before it left: the children's last measured sizes
/// and baselines, which the measure strategies and the measure cache read,
/// a flow's state from its last measure, and what the engine keeps of a
/// widget from one measure to the next, as Android's `reset()` keeps it (a
/// barrier's resolved flag, the dependency graph's runs and nodes). A run
/// rewrites each of these from its own requests and answers, or leaves it as
/// it was. So when a run repeats the run before it (the same keys,
/// transcript, frames and size), it also left the state that run left, and a
/// later run with the same keys and the same answers repeats it exactly: it
/// is [confirmed]. The first run after a build is never confirmed, because
/// Android's own second layout of a layout can differ from its first.
final class _ReplayRun {
  _ReplayRun({
    required this.epoch,
    required this.constraints,
    required this.transcript,
    required this.frames,
    required this.measuredWidth,
    required this.measuredHeight,
  });

  /// The configuration epoch the run measured.
  final int epoch;

  /// The incoming constraints the run measured under.
  final BoxConstraints constraints;

  /// Every measure request of the run and every content measure.
  final _ReplayTranscript transcript;

  /// `x, y, width, height` of every child, in child order, as the engine
  /// left them.
  final List<int> frames;

  /// The layout's measured width.
  final int measuredWidth;

  /// The layout's measured height.
  final int measuredHeight;

  /// Whether the run repeated the run before it, so that a layout with the
  /// same keys whose children answer the same may replay it.
  bool confirmed = false;

  /// The layout's measured size.
  Size get measuredSize =>
      Size(measuredWidth.toDouble(), measuredHeight.toDouble());

  /// Whether this run has the keys of [other] and gave the same result.
  bool repeats(_ReplayRun other) =>
      epoch == other.epoch &&
      constraints == other.constraints &&
      measuredWidth == other.measuredWidth &&
      measuredHeight == other.measuredHeight &&
      listEquals(frames, other.frames) &&
      transcript.sameAs(other.transcript);
}

/// A dry query that ran the engine, kept for a replay: its keys, the
/// throwaway model it measured with its measurer and host, and its content
/// measures.
///
/// Exact (a replay justified by determinism, with the dual run of
/// `--dart-define=cl.verifyReplay=true`): a dry query measures a new model,
/// built from the configuration, with a new measurer and host, so nothing
/// carries over from an earlier measure, and the engine's run is a function
/// of the configuration (fixed by [epoch] once [RenderConstraintLayout.
/// _configSettled]), the constraints, [minimumAxis] and the children's
/// answers to its content measures, each of which is a function of the
/// request and of what the measurer reads from the child: its dry layout and
/// dry baseline, its minimum intrinsic size for [minimumAxis], and whether
/// its last layout found a baseline. Asking every child again for each
/// content measure of the run, in order, through the same measurer, reads
/// all of these as a new run would, so when every answer is the same a new
/// run would make the same requests and get the same answers, and give the
/// same model, frames and size. The replay returns them without measuring a
/// new model.
final class _DryRun {
  _DryRun({
    required this.epoch,
    required this.constraints,
    required this.minimumAxis,
    required this.model,
    required this.measurer,
    required this.host,
    required this.transcript,
  });

  /// The configuration epoch the query's model was built at.
  final int epoch;

  /// The query's constraints.
  final BoxConstraints constraints;

  /// The query's minimum-intrinsic axis, if any.
  final Axis? minimumAxis;

  /// The throwaway model the query measured.
  final _EngineModel model;

  /// The query's measurer.
  final _DryMeasurer measurer;

  /// The query's host.
  final ViewHost host;

  /// The query's content measures (its measure requests are not kept).
  final _ReplayTranscript transcript;

  /// What [RenderConstraintLayout._resolveDry] returns for the query.
  ({_EngineModel model, _DryMeasurer measurer, ViewHost host}) get resolved =>
      (model: model, measurer: measurer, host: host);

  /// The measured size of the layout.
  Size get measuredSize => Size(
    host.getMeasuredWidth().toDouble(),
    host.getMeasuredHeight().toDouble(),
  );

  /// Whether [other], a query with the same keys on another model, gave the
  /// same result: the same measured size, the same frame for each widget of
  /// the container (by index), the same latest dry layout of each child, and
  /// the same content measures (each widget by its index in its container).
  bool sameResultAs(_DryRun other) {
    if (host.getMeasuredWidth() != other.host.getMeasuredWidth() ||
        host.getMeasuredHeight() != other.host.getMeasuredHeight()) {
      return false;
    }
    final a = model.container.mChildren;
    final b = other.model.container.mChildren;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final wa = a[i];
      final wb = b[i];
      if (wa.getX() != wb.getX() ||
          wa.getY() != wb.getY() ||
          wa.getWidth() != wb.getWidth() ||
          wa.getHeight() != wb.getHeight() ||
          measurer.laidOutOf(wa) != other.measurer.laidOutOf(wb)) {
        return false;
      }
    }
    final ca = transcript.contents;
    final cb = other.transcript.contents;
    if (ca.length != cb.length) return false;
    final indexA = <ConstraintWidget, int>{
      for (var i = 0; i < a.length; i++) a[i]: i,
    };
    final indexB = <ConstraintWidget, int>{
      for (var i = 0; i < b.length; i++) b[i]: i,
    };
    for (var i = 0; i < ca.length; i++) {
      final x = ca[i];
      final y = cb[i];
      if (indexA[x.widget] != indexB[y.widget] ||
          x.widthSpec != y.widthSpec ||
          x.heightSpec != y.heightSpec ||
          x.width != y.width ||
          x.height != y.height ||
          x.baseline != y.baseline) {
        return false;
      }
    }
    return true;
  }
}
