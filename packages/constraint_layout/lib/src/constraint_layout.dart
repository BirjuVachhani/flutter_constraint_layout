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
/// target, for example `topToTop: parent`.
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
///    widgets in place.
///  * When nothing layout-affecting changed and no child's size can depend on
///    its content, a re-layout under identical constraints skips the engine
///    entirely and reuses the resolved geometry.
///
/// Every engine pass resolves through `container.layout()`, the same code path
/// a freshly built model uses, so incremental updates cannot drift from a
/// from-scratch layout.
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
    // start/end resolution is baked into the engine connections.
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
  ConstraintWidgetContainer? _container;
  final List<RenderBox> _modelChildren = <RenderBox>[];
  final List<ConstraintParentData> _modelChildData = <ConstraintParentData>[];
  final List<ConstraintWidget> _modelWidgets = <ConstraintWidget>[];
  final Map<Symbol, ConstraintWidget> _byId = <Symbol, ConstraintWidget>{};
  final Set<ConstraintWidget> _needsBaseline = <ConstraintWidget>{};
  _FlutterMeasurer? _measurer;
  bool _needsModelRebuild = true;
  bool _hasContentDependentChild = false;
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
  /// last layout (`mSystem.mNumRows` is non-zero after a solver pass). Test
  /// instrumentation.
  @visibleForTesting
  ConstraintWidgetContainer? get debugEngineContainer => _container;

  /// Builds the debug-overlay scene from the current engine state.
  ///
  /// Exposed for tests; also used by [paint] when a debug flag is set. Only
  /// valid after a layout pass.
  @visibleForTesting
  DebugScene debugDescribeScene() => buildDebugScene(
        container: _container!,
        widgets: _modelWidgets,
        parentData: _modelChildData,
        children: _modelChildren,
      );

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
    _container = null;
    _measurer = null;
    _modelChildren.clear();
    _modelChildData.clear();
    _modelWidgets.clear();
    _byId.clear();
    _needsBaseline.clear();
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
    if (!_needsModelRebuild) {
      var i = 0;
      RenderBox? child = firstChild;
      while (child != null) {
        final pd = child.parentData! as ConstraintParentData;
        if (i >= _modelChildren.length ||
            !identical(_modelChildren[i], child) ||
            pd.structuralDirty) {
          _needsModelRebuild = true;
          break;
        }
        if (pd.configDirty) {
          anyConfigDirty = true;
        }
        child = pd.nextSibling;
        i++;
      }
      if (!_needsModelRebuild && i != _modelChildren.length) {
        _needsModelRebuild = true;
      }
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
        !_hasContentDependentChild &&
        _needsBaseline.isEmpty) {
      debugFastPasses++;
      for (var i = 0; i < _modelChildren.length; i++) {
        final w = _modelWidgets[i];
        _modelChildren[i].layout(
          BoxConstraints.tight(
            Size(w.getWidth().toDouble(), w.getHeight().toDouble()),
          ),
        );
        _modelChildData[i].offset =
            Offset(w.getX().toDouble(), w.getY().toDouble());
      }
      final container = _container!;
      size = constraints.constrain(
        Size(container.getWidth().toDouble(), container.getHeight().toDouble()),
      );
      return;
    }

    final boundedW = constraints.hasBoundedWidth;
    final boundedH = constraints.hasBoundedHeight;

    if (_needsModelRebuild) {
      _buildModel(constraints, boundedW, boundedH);
      debugModelBuilds++;
    } else if (anyConfigDirty) {
      // Derived state must be recomputed before connects are re-applied:
      // baseline connects only validate when both endpoints are already
      // marked baseline-capable (see _computeDerivedState).
      _computeDerivedState();
      for (var i = 0; i < _modelChildren.length; i++) {
        final pd = _modelChildData[i];
        if (!pd.configDirty) continue;
        pd.configDirty = false;
        _applyWidgetConfig(_modelWidgets[i], pd);
        debugConfigApplies++;
      }
    }

    // Normalize stored sizes before every engine pass: a fresh widget enters
    // the engine with 0 on any non-fixed axis, but a persistent widget can
    // carry a size written by a previous pass (notably the solver fallback's
    // wrap re-measure of underconstrained matchConstraint children). The
    // graph feeds stored sizes back as measure hints, so a leaked size would
    // change the result relative to a freshly built model.
    for (var i = 0; i < _modelWidgets.length; i++) {
      final pd = _modelChildData[i];
      if (pd.helperKind != HelperKind.none) continue;
      final w = _modelWidgets[i];
      if (pd.width is! FixedDimension) w.setWidth(0);
      if (pd.height is! FixedDimension) w.setHeight(0);
    }

    // Root container mirrors the incoming constraints: bounded axes are fixed
    // (the layout fills the space it is given), unbounded axes wrap children.
    final container = _container!;
    container.setRtl(!_ltr);
    container.setHorizontalDimensionBehaviour(
      boundedW ? DimensionBehaviour.fixed : DimensionBehaviour.wrapContent,
    );
    container.setVerticalDimensionBehaviour(
      boundedH ? DimensionBehaviour.fixed : DimensionBehaviour.wrapContent,
    );
    container.setWidth(boundedW ? constraints.maxWidth.round() : 0);
    container.setHeight(boundedH ? constraints.maxHeight.round() : 0);

    // Resolve the graph, measuring intrinsic child sizes through
    // RenderBox.layout.
    final measurer = _measurer!;
    measurer.beginPass(constraints);
    debugEnginePasses++;
    container.layout();

    // Place and size each child from the resolved coordinates.
    for (var i = 0; i < _modelChildren.length; i++) {
      final w = _modelWidgets[i];
      final rb = _modelChildren[i];
      final ew = w.getWidth().toDouble();
      final eh = w.getHeight().toDouble();
      // If the measure pass already laid the child out at (effectively) the
      // resolved size, keep that layout instead of forcing a tight one: the
      // measure pass uses loose constraints on wrap axes, which leaves the
      // child a non-boundary so a later content change propagates back here
      // and triggers re-resolution.
      final keepMeasuredLayout = measurer.laidOut.contains(w) &&
          (rb.size.width - ew).abs() < 1 &&
          (rb.size.height - eh).abs() < 1;
      if (!keepMeasuredLayout) {
        rb.layout(BoxConstraints.tight(Size(ew, eh)));
      }
      _modelChildData[i].offset =
          Offset(w.getX().toDouble(), w.getY().toDouble());
    }

    _lastConstraints = constraints;
    size = constraints.constrain(
      Size(container.getWidth().toDouble(), container.getHeight().toDouble()),
    );
  }

  /// Rebuilds the engine model from scratch: one `ConstraintWidget` per child,
  /// configured from its parent data.
  void _buildModel(BoxConstraints constraints, bool boundedW, bool boundedH) {
    _needsModelRebuild = false;
    _modelChildren.clear();
    _modelChildData.clear();
    _modelWidgets.clear();
    _byId.clear();

    RenderBox? child = firstChild;
    while (child != null) {
      final pd = child.parentData! as ConstraintParentData;
      pd.configDirty = false;
      pd.structuralDirty = false;
      _modelChildren.add(child);
      _modelChildData.add(pd);
      child = pd.nextSibling;
    }

    final container = ConstraintWidgetContainer.rect(
      0,
      0,
      boundedW ? constraints.maxWidth.round() : 0,
      boundedH ? constraints.maxHeight.round() : 0,
    );
    _container = container;

    // Create every widget and register ids before applying config, so links
    // can target later siblings. Helper children map to their dedicated
    // engine types.
    final renderOf = <ConstraintWidget, RenderBox>{};
    for (var i = 0; i < _modelChildren.length; i++) {
      final w = switch (_modelChildData[i].helperKind) {
        HelperKind.none => ConstraintWidget(),
        HelperKind.guideline => Guideline(),
        HelperKind.barrier => Barrier(),
        HelperKind.flow => Flow(),
        HelperKind.grid => GridCore(),
      };
      _modelWidgets.add(w);
      if (_modelChildData[i].helperKind == HelperKind.none) {
        renderOf[w] = _modelChildren[i];
      }
      final id = _modelChildData[i].id;
      if (id != null) {
        _byId[id] = w;
      }
      container.add(w);
    }
    // Derived state (and its baseline seeding) must precede the connects.
    _computeDerivedState();
    for (var i = 0; i < _modelWidgets.length; i++) {
      _applyWidgetConfig(_modelWidgets[i], _modelChildData[i]);
    }

    _measurer = _FlutterMeasurer(renderOf, _needsBaseline);
    container.setMeasurer(_measurer);
  }

  /// Applies the full `Constrained` config from [pd] to engine widget [w].
  ///
  /// Also used to update a persistent widget in place, so it first resets any
  /// state a previous configuration (or the engine's GONE zeroing in
  /// updateFromRuns) may have left behind; after the reset, re-applying is
  /// equivalent to configuring a fresh widget.
  void _applyWidgetConfig(ConstraintWidget w, ConstraintParentData pd) {
    if (pd.helperKind == HelperKind.guideline ||
        pd.helperKind == HelperKind.barrier) {
      _applyHelperConfig(w, pd);
      return;
    }
    // Flows fall through: they are positioned and sized like a regular child
    // (links, dimensions, bias, visibility) and get their flow configuration
    // applied on top at the end.

    // resetAnchors() clears each anchor's incoming-dependents set, but
    // siblings still targeting this widget keep their connections; the
    // solver's GONE handling gates on hasDependencies(), so the incoming
    // bookkeeping must survive an in-place re-apply.
    final savedDependents = [for (final anchor in w.mAnchors) anchor.mDependents];
    w.resetAnchors();
    for (var i = 0; i < w.mAnchors.length; i++) {
      w.mAnchors[i].mDependents = savedDependents[i];
    }
    w.setDimensionRatio(0, ConstraintWidget.UNKNOWN);
    // Match styles carry min/max/percent; reset to pristine spread defaults.
    w.setHorizontalMatchStyle(ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 0, 1);
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
    w.setHorizontalBiasPercent(pd.horizontalBias);
    w.setVerticalBiasPercent(pd.verticalBias);
    final ratio = pd.aspectRatio;
    if (ratio != null && ratio > 0) {
      w.setDimensionRatioString(ratio.toString());
    }
    w.setHorizontalChainStyle(_chainStyleOf(pd.horizontalChainStyle));
    w.setVerticalChainStyle(_chainStyleOf(pd.verticalChainStyle));
    w.setHorizontalWeight(
        pd.horizontalWeight ?? ConstraintWidget.UNKNOWN.toDouble());
    w.setVerticalWeight(
        pd.verticalWeight ?? ConstraintWidget.UNKNOWN.toDouble());
    w.setVisibility(switch (pd.visibility) {
      ConstraintVisibility.visible => ConstraintWidget.VISIBLE,
      ConstraintVisibility.invisible => ConstraintWidget.INVISIBLE,
      ConstraintVisibility.gone => ConstraintWidget.GONE,
    });

    _connectH(w, HorizontalEdge.left, pd.left);
    _connectH(w, HorizontalEdge.right, pd.right);
    _connectH(w, HorizontalEdge.start, pd.start);
    _connectH(w, HorizontalEdge.end, pd.end);
    _connectV(w, VerticalEdge.top, pd.top);
    _connectV(w, VerticalEdge.bottom, pd.bottom);
    _connectV(w, VerticalEdge.baseline, pd.baseline);

    final circle = pd.circle;
    if (circle != null) {
      final target = _resolveTarget(circle.target);
      if (target == null) {
        assert(() {
          throw FlutterError(
            'CircularLink targets unknown id ${circle.target}. Targets must '
            'be `parent` or the id of a sibling in the same ConstraintLayout.',
          );
        }());
      } else {
        w.connectCircularConstraint(target, circle.angle, circle.radius.round());
      }
    }

    if (w is Flow) {
      _applyFlowConfig(w, pd);
    } else if (w is GridCore) {
      _applyGridConfig(w, pd);
    }
  }

  /// Applies grid configuration on top of the regular widget config. Only
  /// called from model builds (grid changes are structural), so referenced
  /// widgets never need clearing.
  void _applyGridConfig(GridCore w, ConstraintParentData pd) {
    w.setRows(pd.gridRows ?? 0);
    w.setColumns(pd.gridColumns ?? 0);
    w.setOrientation(pd.gridOrientation == Axis.horizontal
        ? GridCore.HORIZONTAL
        : GridCore.VERTICAL);
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
      final target = _byId[id];
      if (target == null) {
        assert(() {
          throw FlutterError(
            'ConstraintGrid references unknown id $id. Referenced ids must '
            'belong to siblings in the same ConstraintLayout.',
          );
        }());
        continue;
      }
      w.add(target);
    }
  }

  /// Applies flow configuration on top of the regular widget config. Only
  /// called from model builds (flow changes are structural), so referenced
  /// widgets never need clearing.
  void _applyFlowConfig(Flow w, ConstraintParentData pd) {
    w.setOrientation(pd.flowOrientation == Axis.horizontal
        ? ConstraintWidget.HORIZONTAL
        : ConstraintWidget.VERTICAL);
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
    for (final id in pd.flowReferenced) {
      final target = _byId[id];
      if (target == null) {
        assert(() {
          throw FlutterError(
            'ConstraintFlow references unknown id $id. Referenced ids must '
            'belong to siblings in the same ConstraintLayout.',
          );
        }());
        continue;
      }
      w.add(target);
    }
  }

  /// Applies guideline/barrier configuration to the dedicated engine widget.
  /// Only called from model builds: helper config changes are structural, so
  /// [w] is always freshly constructed and needs no reset.
  void _applyHelperConfig(ConstraintWidget w, ConstraintParentData pd) {
    if (w is Guideline) {
      w.setOrientation(pd.guidelineAxis == Axis.horizontal
          ? Guideline.horizontal
          : Guideline.vertical);
      final percent = pd.guidelinePercent;
      final begin = pd.guidelineBegin;
      final end = pd.guidelineEnd;
      if (percent != null) {
        w.setGuidePercent(percent);
      } else if (begin != null) {
        w.setGuideBegin(begin.round());
      } else if (end != null) {
        w.setGuideEnd(end.round());
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
      w.setMargin(pd.barrierMargin.round());
      for (final id in pd.barrierReferenced) {
        final target = _byId[id];
        if (target == null) {
          assert(() {
            throw FlutterError(
              'Barrier references unknown id $id. Referenced ids must belong '
              'to siblings in the same ConstraintLayout.',
            );
          }());
          continue;
        }
        w.add(target);
      }
    }
  }

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

  /// Recomputes state derived from the whole model: which widgets need a real
  /// baseline measured, and whether any child's geometry can depend on its
  /// content (which disables the engine-skipping fast path).
  void _computeDerivedState() {
    _needsBaseline.clear();
    var contentDependent = false;
    for (var i = 0; i < _modelChildData.length; i++) {
      final pd = _modelChildData[i];
      final link = pd.baseline;
      if (link != null) {
        _needsBaseline.add(_modelWidgets[i]);
        final target = link.target == parent ? null : _byId[link.target];
        if (target != null) {
          _needsBaseline.add(target);
        }
      }
      // A baseline-aligned flow needs real baselines for every widget it
      // arranges.
      if (pd.helperKind == HelperKind.flow &&
          pd.flowVerticalAlign == FlowVerticalAlign.baseline) {
        for (final id in pd.flowReferenced) {
          final target = _byId[id];
          if (target != null) {
            _needsBaseline.add(target);
          }
        }
      }
      contentDependent = contentDependent || _isContentDependent(pd);
    }
    _hasContentDependentChild = contentDependent;

    // Baseline connects only validate when both endpoints already report a
    // baseline (upstream parity: Android sets hasBaseline from the view while
    // applying LayoutParams, before connecting). Seed the participants now;
    // the next measure pass overwrites the flag with the real value.
    for (final w in _needsBaseline) {
      w.setHasBaseline(true);
    }
  }

  /// Whether this child's resolved size can depend on its content: a wrap
  /// dimension, a constrained-wrap match dimension, or a matchConstraint
  /// dimension the engine measures as wrap because an opposing anchor is
  /// missing. Helper children (guidelines, barriers) have no content.
  bool _isContentDependent(ConstraintParentData pd) {
    if (pd.helperKind != HelperKind.none) return false;
    final hasLeft = pd.left != null || (_ltr ? pd.start : pd.end) != null;
    final hasRight = pd.right != null || (_ltr ? pd.end : pd.start) != null;
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

  void _connectH(ConstraintWidget w, HorizontalEdge sourceEdge,
      HorizontalLink? link) {
    if (link == null) return;
    final target = _resolveTarget(link.target);
    if (target == null) {
      assert(() {
        throw FlutterError(
          'Constrained link targets unknown id ${link.target}. Targets must be '
          '`parent` or the id of a sibling Constrained in the same '
          'ConstraintLayout.',
        );
      }());
      return;
    }
    final from = _hAnchor(sourceEdge);
    w.connect(from, target, _hAnchor(link.edge), link.margin.round());
    if (link.goneMargin != 0) {
      w.setGoneMargin(from, link.goneMargin.round());
    }
  }

  void _connectV(ConstraintWidget w, VerticalEdge sourceEdge,
      VerticalLink? link) {
    if (link == null) return;
    final target = _resolveTarget(link.target);
    if (target == null) {
      assert(() {
        throw FlutterError(
          'Constrained link targets unknown id ${link.target}. Targets must be '
          '`parent` or the id of a sibling Constrained in the same '
          'ConstraintLayout.',
        );
      }());
      return;
    }
    final from = _vAnchor(sourceEdge);
    w.connect(from, target, _vAnchor(link.edge), link.margin.round());
    if (link.goneMargin != 0) {
      w.setGoneMargin(from, link.goneMargin.round());
    }
  }

  ConstraintWidget? _resolveTarget(Symbol target) {
    if (target == parent) return _container;
    return _byId[target];
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
        if (pd.visibility != ConstraintVisibility.visible) continue;
        context.paintChild(child, pd.offset + offset);
      }
    }
    // The design-surface / blueprint overlay. context.canvas is read here,
    // after the paintChild calls, because the getter re-acquires the canvas.
    if ((showBlueprint || showChains) && _container != null) {
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

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in _paintOrder().reversed) {
      final pd = child.parentData! as ConstraintParentData;
      if (pd.visibility != ConstraintVisibility.visible) continue;
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

/// Bridges the engine's intrinsic-measurement seam to Flutter: measures a child
/// by laying out its [RenderBox]. Follows the same contract as the engine's
/// default measurer (wrap axes report the child's natural size; fixed/match/
/// match-parent axes echo the size the graph resolved).
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
  /// current engine pass. Placement uses this to keep the measure-pass layout
  /// when it already matches the resolved size.
  final Set<ConstraintWidget> laidOut = <ConstraintWidget>{};

  void beginPass(BoxConstraints rootConstraints) {
    _rootConstraints = rootConstraints;
    laidOut.clear();
  }

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
    // constraints, so its content must be measured like wrapContent; the
    // engine then applies the cap (Android's view measurer does the same).
    final wrapW = measure.horizontalBehavior == DimensionBehaviour.wrapContent ||
        (measure.horizontalBehavior == DimensionBehaviour.matchConstraint &&
            widget.mMatchConstraintDefaultWidth ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP);
    final wrapH = measure.verticalBehavior == DimensionBehaviour.wrapContent ||
        (measure.verticalBehavior == DimensionBehaviour.matchConstraint &&
            widget.mMatchConstraintDefaultHeight ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP);

    final double minW, maxW, minH, maxH;
    if (wrapW) {
      minW = 0;
      maxW = _rootConstraints.maxWidth;
    } else {
      minW = maxW = measure.horizontalDimension.toDouble();
    }
    if (wrapH) {
      minH = 0;
      maxH = _rootConstraints.maxHeight;
    } else {
      minH = maxH = measure.verticalDimension.toDouble();
    }

    child.layout(
      BoxConstraints(
        minWidth: minW,
        maxWidth: maxW,
        minHeight: minH,
        maxHeight: maxH,
      ),
      parentUsesSize: true,
    );
    laidOut.add(widget);

    measure.measuredWidth =
        wrapW ? child.size.width.round() : measure.horizontalDimension;
    measure.measuredHeight =
        wrapH ? child.size.height.round() : measure.verticalDimension;

    measure.measuredHasBaseline = false;
    measure.measuredBaseline = 0;
    if (_needsBaseline.contains(widget)) {
      final baseline =
          child.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true);
      if (baseline != null) {
        measure.measuredHasBaseline = true;
        measure.measuredBaseline = baseline.round();
      }
    }

    widget.setMeasureRequested(false);
  }

  @override
  void didMeasures() {}
}
