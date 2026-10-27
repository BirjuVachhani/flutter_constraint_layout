// Part of the adapter library: the engine model of a
// RenderConstraintLayout's children, how each child's configuration is
// applied to its engine widget (as Android's view layer applies a child's
// layout params), and the state derived from the whole model.
part of '../constraint_layout.dart';

/// An engine model of a [RenderConstraintLayout]'s children: a container
/// holding one engine widget per child, in child order, each configured from
/// its child's parent data the way Android's `ConstraintLayout` configures
/// the widget of each child view from its layout params
/// (`applyConstraintsFromLayoutParams`).
///
/// The render object keeps one alive across layout passes and measures it
/// through a `ViewHost`; the dry-layout, intrinsic-size, and dry-baseline
/// queries each measure a throwaway one, so they never disturb it.
class _EngineModel {
  _EngineModel(this.container, {required this.reportsUnknownIds});

  /// The root, which stands in for the layout itself.
  final ConstraintWidgetContainer container;

  /// Whether building this model throws, in a debug build, on a reference to
  /// an id that no sibling has. True for the persistent model; a throwaway
  /// one skips the reference, as release builds do. See
  /// [_EngineModelBuilder._reportUnknownId].
  final bool reportsUnknownIds;

  /// The children, in child-list order.
  final List<RenderBox> children = <RenderBox>[];

  /// The parent data of each child, by index in [children].
  final List<ConstraintParentData> childData = <ConstraintParentData>[];

  /// The engine widget of each child, by index in [children]. Every child has
  /// exactly one, a `ConstraintGroup` included, and the container holds them
  /// in this order (its `mChildren`), as Android's layout widget holds one
  /// widget per child view.
  final List<ConstraintWidget> widgets = <ConstraintWidget>[];

  /// Engine widgets by child id, for resolving links and helper references:
  /// the children a link or a reference can target, every kind but a group.
  final Map<Symbol, ConstraintWidget> byId = <Symbol, ConstraintWidget>{};

  /// The index in [children] of each child in [byId].
  final Map<Symbol, int> indexById = <Symbol, int>{};

  /// The ids of the groups, kept apart from [byId]: nothing can link to or
  /// reference a group.
  final Set<Symbol> groupIds = <Symbol>{};

  /// The visibility a `ConstraintGroup` imposes on each child it references,
  /// by the child's parent data. Derived state; see
  /// [_EngineModelBuilder._computeDerivedState].
  final Map<ConstraintParentData, ConstraintVisibility> groupOverrides =
      <ConstraintParentData, ConstraintVisibility>{};

  /// The visibility the child with parent data [pd] is laid out with: that of
  /// the last group that references it, otherwise its own.
  ConstraintVisibility visibilityOf(ConstraintParentData pd) =>
      groupOverrides[pd] ?? pd.visibility;

  /// Each content child (a `Constrained` child, so every child but the
  /// helpers, the virtual layouts and the groups), by engine widget: the
  /// children a measurer lays out, each with its [RenderBox] and what the
  /// model's measurer keeps of it.
  final Map<ConstraintWidget, _ContentChild> contentOf =
      <ConstraintWidget, _ContentChild>{};

  /// The [_ContentChild] of each child, by index in [children]; null for a
  /// helper, a virtual layout or a group.
  final List<_ContentChild?> contentAt = <_ContentChild?>[];

  /// The ids of the children a `ConstraintGrid` that is not gone places.
  /// Derived state; see [_EngineModelBuilder._computeDerivedState].
  final Set<Symbol> gridMembers = <Symbol>{};
}

/// The name of [id] as Android's op lists and the measure-request transcript
/// write it: `x` for `#x` (a `Symbol("x")`), null for a child without an id.
///
/// Kept per symbol object ([_debugNames]): a const id (`#x`) is the same
/// object in every build of the model, and its name, a function of the
/// symbol alone, the same string value.
String? _debugNameOf(Symbol? id) {
  if (id == null) return null;
  return _debugNames[id] ??= _nameOf(id);
}

/// [_debugNameOf]'s names, by symbol object.
final Expando<String> _debugNames = Expando<String>('the names of ids');

String _nameOf(Symbol id) {
  final raw = id.toString();
  const prefix = 'Symbol("';
  const suffix = '")';
  if (raw.startsWith(prefix) && raw.endsWith(suffix)) {
    return raw.substring(prefix.length, raw.length - suffix.length);
  }
  return raw;
}

/// The engine's visibility constant for [visibility].
int _engineVisibility(ConstraintVisibility visibility) => switch (visibility) {
  ConstraintVisibility.visible => ConstraintWidget.VISIBLE,
  ConstraintVisibility.invisible => ConstraintWidget.INVISIBLE,
  ConstraintVisibility.gone => ConstraintWidget.GONE,
};

/// The gone margin of a link: Flutter's 0 is Android's unset gone margin
/// (`GONE_UNSET`, so a gone target keeps the normal margin), anything else
/// rounds to whole logical pixels.
int _goneMarginOf(double goneMargin) =>
    goneMargin == 0 ? ConstraintAnchor.unsetGoneMargin : goneMargin.round();

/// The model side of [RenderConstraintLayout]: builds the engine model of
/// its children, applies each child's configuration to its engine widget,
/// and keeps the state derived from the whole model.
///
/// An extension, so that these members live in this part while reading the
/// render object's state (its children, its text direction, whether its
/// model needs a rebuild) as its own members do.
extension _EngineModelBuilder on RenderConstraintLayout {
  /// Builds an engine model of the current children: one engine widget per
  /// child, added to the container in child order and configured from its
  /// parent data.
  ///
  /// Touches nothing but the new model, so it builds both the persistent
  /// model ([RenderConstraintLayout._buildModel]) and the throwaway ones of
  /// the dry-layout queries ([RenderConstraintLayout._resolveDry]). See
  /// [_EngineModel.reportsUnknownIds]. [constraints] only give the container
  /// a starting size: the host sizes it again at every measure.
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

    // Create every widget and register ids before applying any
    // configuration, so links can target later siblings, as Android maps
    // every child's id to its widget before it applies the first child's
    // layout params (CL 1331-1338).
    for (var i = 0; i < model.children.length; i++) {
      final pd = model.childData[i];
      final w = switch (pd.helperKind) {
        // A ConstraintGroup is a plain widget, as Android's Group view is a
        // ConstraintHelper without a helper widget of its own: the widget
        // of its layout params (see _applyGroupConfig).
        HelperKind.none || HelperKind.group => ConstraintWidget(),
        // Oriented now, before any sibling links to it: a guideline only has
        // the left and right edges that links to a vertical one target once
        // it is vertical, and a sibling earlier in the child list connects
        // before the guideline's own config. Android orients the guideline
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
      };
      // The request transcript names widgets as the oracle's op lists do.
      w.setDebugName(_debugNameOf(pd.id));
      model.widgets.add(w);
      // Every child's widget takes part, in child order: it holds its own
      // solver variables, so it shifts the variable ids of every later
      // widget, as Android's widgets do (a group's included).
      model.container.add(w);
      if (pd.helperKind == HelperKind.none) {
        final content = _ContentChild(model.children[i]);
        model.contentOf[w] = content;
        model.contentAt.add(content);
      } else {
        model.contentAt.add(null);
      }
      final id = pd.id;
      if (id == null) continue;
      if (pd.helperKind == HelperKind.group) {
        model.groupIds.add(id);
      } else {
        model.byId[id] = w;
        model.indexById[id] = i;
      }
    }
    // The group overrides decide the members' visibility, and the grid
    // members their bias, so they come before any configuration.
    _computeDerivedState(model);
    for (var i = 0; i < model.widgets.length; i++) {
      _applyWidgetConfig(model, model.widgets[i], model.childData[i]);
    }
    _reportLinkLoop(model);
    _createGridCells(model);
    return model;
  }

  /// Has every grid of [model] create the box widgets that hold its cells,
  /// before the first measure.
  ///
  /// The engine's grid creates its boxes, and adds them to the container, in
  /// its own measure, and a grid that is a match constraint on both axes is
  /// first measured only after the first solve has sized it. Without this,
  /// the first solve of a new model would run without the cells, and a
  /// layout that wraps its children (an unbounded axis) would lay the grid's
  /// children out at its origin on its first layout and in their cells on
  /// every later one; a dry query, which measures a new model, would then
  /// disagree with the layout. Android's view `Grid` creates its box views
  /// when it is attached, before the layout's first measure, so its cells
  /// take part in every measure. A grid has no Android oracle: it is outside
  /// the parity contract (see "Limitations and differences from Android" in
  /// the README).
  void _createGridCells(_EngineModel model) {
    for (final w in model.widgets) {
      if (w is GridCore) {
        // The specs do not matter: the measure the engine makes later reports
        // the grid's size; this one only builds the cells.
        w.measure(BasicMeasure.UNSPECIFIED, 0, BasicMeasure.UNSPECIFIED, 0);
      }
    }
  }

  /// Applies the configuration of the child with parent data [pd] to its
  /// engine widget [w] of [model], whose ids and container its links resolve
  /// against: Android's `applyConstraintsFromLayoutParams` (CL 1354-1596).
  ///
  /// Also updates a persistent widget in place: it first resets the
  /// configuration a previous apply set, so the widget's configuration ends
  /// as a fresh build of the same configuration leaves it. The measure state
  /// is the host's to reset (`ViewHost` resets every widget's measure state
  /// as Android's `reset()` does, keeping what `reset()` keeps, such as the
  /// resolved flags and the dependency graph's runs, and rebuilds every
  /// anchor's dependents before each measure).
  void _applyWidgetConfig(
    _EngineModel model,
    ConstraintWidget w,
    ConstraintParentData pd,
  ) {
    switch (pd.helperKind) {
      case HelperKind.guideline:
        if (w is Guideline) _applyGuidelineConfig(w, pd);
      case HelperKind.barrier:
        if (w is Barrier) _applyBarrierConfig(model, w, pd);
      case HelperKind.group:
        _applyGroupConfig(model, w, pd);
      case HelperKind.none || HelperKind.flow || HelperKind.grid:
        _applyChildConfig(model, w, pd);
        if (w is Flow) {
          _applyFlowConfig(model, w, pd);
        } else if (w is GridCore) {
          _applyGridConfig(model, w, pd);
        }
    }
  }

  /// The configuration of a `Constrained` child, or of a flow or grid as a
  /// child of the layout: CL 1363 and 1428-1594, in that order.
  void _applyChildConfig(
    _EngineModel model,
    ConstraintWidget w,
    ConstraintParentData pd,
  ) {
    // What Android's reset() restores among the fields set below only when
    // the configuration asks: no link, no circle angle, no ratio, the
    // default biases (a circle child sets none), and the origin.
    w.resetAnchors();
    w.mCircleConstraintAngle = double.nan;
    w.setDimensionRatio(0, ConstraintWidget.UNKNOWN);
    w.setHorizontalBiasPercent(ConstraintWidget.DEFAULT_BIAS);
    w.setVerticalBiasPercent(ConstraintWidget.DEFAULT_BIAS);
    w.setX(0);
    w.setY(0);

    // A group that references this child overrides its own visibility.
    w.setVisibility(_engineVisibility(model.visibilityOf(pd)));

    // A flow and a grid have no baseline link, circle, ratio, weights or
    // chain styles of their own; parent data a Constrained child left behind
    // on the same render object must not leak into them.
    final contentChild = pd.helperKind == HelperKind.none;
    final circle = contentChild ? pd.circle : null;
    if (circle != null) {
      // A circle replaces every other link of the child (CL 1429-1435).
      final target = _resolveTarget(model, circle.target);
      if (target == null) {
        _reportUnknownId(
          model,
          'CircularLink targets ${_describeUnresolved(model, circle.target)}. '
          'Targets must be `parent` or the id of a sibling in the same '
          'ConstraintLayout.',
        );
      } else {
        // The angle as given, in degrees: Android's view layer passes a
        // programmatic angle on unchanged (only its XML parser reduces it
        // modulo 360). The engine keeps it as a binary32 value.
        w.connectCircularConstraint(
          target,
          circle.angle,
          circle.radius.round(),
        );
      }
    } else {
      _connectOwnLinks(model, w, pd, report: true);
      // LayoutParams.resolveLayoutDirection: in a right-to-left layout, a
      // child with a start or end link uses 1 - horizontalBias, computed in
      // float, so its bias counts from its start (right) edge. A child linked
      // only with absolute left/right keeps the bias as given. A widget a
      // grid places counts as start/end-linked: the grid's columns count
      // from the start edge, so its position in its cell does too, and the
      // grid mirrors as a whole.
      final id = pd.id;
      final mirrorBias =
          !_ltr &&
          (pd.start != null ||
              pd.end != null ||
              (id != null && model.gridMembers.contains(id)));
      final horizontalBias = mirrorBias
          ? fsub(1, f32(pd.horizontalBias))
          : pd.horizontalBias;
      // CL 1516-1521: a negative bias is not applied.
      if (horizontalBias >= 0) {
        w.setHorizontalBiasPercent(horizontalBias);
      }
      if (pd.verticalBias >= 0) {
        w.setVerticalBiasPercent(pd.verticalBias);
      }
    }

    _applyDimensions(w, pd);

    final ratio = contentChild ? pd.aspectRatio : null;
    if (ratio != null && ratio > 0) {
      // Exact for every binary32 ratio: the shortest string of a double
      // parses back (as Java's Float.parseFloat) to the nearest float.
      w.setDimensionRatioString(ratio.toString());
    }
    w.setHorizontalWeight(
      (contentChild ? pd.horizontalWeight : null) ??
          ConstraintWidget.UNKNOWN.toDouble(),
    );
    w.setVerticalWeight(
      (contentChild ? pd.verticalWeight : null) ??
          ConstraintWidget.UNKNOWN.toDouble(),
    );
    w.setHorizontalChainStyle(
      _chainStyleOf(contentChild ? pd.horizontalChainStyle : null),
    );
    w.setVerticalChainStyle(
      _chainStyleOf(contentChild ? pd.verticalChainStyle : null),
    );
    // CL 1589-1594 set the match style on every widget, so a dimension that
    // is not a match constraint gets the defaults.
    final width = pd.width;
    final height = pd.height;
    if (width is MatchConstraintDimension) {
      w.setHorizontalMatchStyle(
        _matchStyleOf(width),
        width.min?.round() ?? 0,
        width.max?.round() ?? 0,
        width.percent ?? 1,
      );
    } else {
      w.setHorizontalMatchStyle(
        ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
        0,
        0,
        1,
      );
    }
    if (height is MatchConstraintDimension) {
      w.setVerticalMatchStyle(
        _matchStyleOf(height),
        height.min?.round() ?? 0,
        height.max?.round() ?? 0,
        height.percent ?? 1,
      );
    } else {
      w.setVerticalMatchStyle(
        ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
        0,
        0,
        1,
      );
    }
  }

  /// Connects the links of the child with parent data [pd] to [w], as
  /// Android does (CL 1436-1514): left then right (the start/end pair when
  /// either is set, which disables both absolute links; else left and
  /// right), then top, bottom and baseline, each with `immediateConnect`, a
  /// forced connect without the validity checks of the engine's `connect`.
  ///
  /// [report] reports a target id that resolves to no sibling (see
  /// [_reportUnknownId]); the model sync, which only connects again what the
  /// build already connected, passes false.
  void _connectOwnLinks(
    _EngineModel model,
    ConstraintWidget w,
    ConstraintParentData pd, {
    required bool report,
  }) {
    final (leftLink, rightLink) = _horizontalLinksOf(pd);
    _connectHorizontal(model, w, ConstraintAnchorType.left, leftLink, report);
    _connectHorizontal(model, w, ConstraintAnchorType.right, rightLink, report);
    _connectVertical(model, w, ConstraintAnchorType.top, pd.top, report);
    _connectVertical(model, w, ConstraintAnchorType.bottom, pd.bottom, report);
    if (pd.helperKind == HelperKind.none) {
      _connectBaseline(model, w, pd.baseline, report);
    }
  }

  /// The links of the left and right anchors of the child with parent data
  /// [pd]: the start/end pair resolved for the text direction when either
  /// is set (LayoutParams.resolveLayoutDirection: any start or end link
  /// disables both absolute ones), else the left and right links.
  (HorizontalLink?, HorizontalLink?) _horizontalLinksOf(
    ConstraintParentData pd,
  ) {
    if (pd.start != null || pd.end != null) {
      return _ltr ? (pd.start, pd.end) : (pd.end, pd.start);
    }
    return (pd.left, pd.right);
  }

  void _connectHorizontal(
    _EngineModel model,
    ConstraintWidget w,
    ConstraintAnchorType from,
    HorizontalLink? link,
    bool report,
  ) {
    if (link == null) return;
    final target = _resolveTarget(model, link.target);
    if (target == null) {
      if (report) _reportUnknownLinkTarget(model, link.target);
      return;
    }
    w.immediateConnect(
      from,
      target,
      _hAnchor(link.edge),
      link.margin.round(),
      _goneMarginOf(link.goneMargin),
    );
  }

  void _connectVertical(
    _EngineModel model,
    ConstraintWidget w,
    ConstraintAnchorType from,
    VerticalLink? link,
    bool report,
  ) {
    if (link == null) return;
    final target = _resolveTarget(model, link.target);
    if (target == null) {
      if (report) _reportUnknownLinkTarget(model, link.target);
      return;
    }
    w.immediateConnect(
      from,
      target,
      _vAnchor(link.edge),
      link.margin.round(),
      _goneMarginOf(link.goneMargin),
    );
  }

  /// A baseline link, as `setWidgetBaseline` makes it (CL 1598-1620).
  ///
  /// Only a link to a sibling counts: Android needs the target view to have
  /// ConstraintLayout layout params, which the layout itself has not, so a
  /// baseline link to `parent` is ignored. The link replaces the widget's
  /// top and bottom links, and marks both ends as having a baseline (the
  /// target only for a link to its baseline).
  void _connectBaseline(
    _EngineModel model,
    ConstraintWidget w,
    VerticalLink? link,
    bool report,
  ) {
    if (link == null || link.target == parent) return;
    final target = model.byId[link.target];
    if (target == null) {
      if (report) _reportUnknownLinkTarget(model, link.target);
      return;
    }
    final type = _vAnchor(link.edge);
    if (type == ConstraintAnchorType.baseline) {
      target.setHasBaseline(true);
    }
    w.mBaseline.connect(
      target.getAnchor(type),
      link.margin.round(),
      _goneMarginOf(link.goneMargin),
      true,
    );
    w.setHasBaseline(true);
    w.mTop.reset();
    w.mBottom.reset();
  }

  /// The behaviours and sizes of [w] from [pd]'s dimensions (CL 1531-1581),
  /// and the margins a match-parent axis keeps whether or not its anchors
  /// are linked (CL 1540-1542, 1566-1568).
  void _applyDimensions(ConstraintWidget w, ConstraintParentData pd) {
    final width = pd.width;
    final height = pd.height;
    w.setHorizontalDimensionBehaviour(_behaviourOf(width));
    w.setVerticalDimensionBehaviour(_behaviourOf(height));
    // A FIXED axis keeps its size in whole logical pixels; any other starts
    // at 0, as Android's setWidth(WRAP_CONTENT) clamps to the minimum. A
    // negative fixed size becomes 0 the same way.
    w.setWidth(width is FixedDimension ? width.pixels.round() : 0);
    w.setHeight(height is FixedDimension ? height.pixels.round() : 0);
    _applyMatchParentMargins(w, pd);
  }

  /// The margins of a match-parent axis: the margins of the links on its
  /// two anchors, 0 for an anchor without one. Android sets them from the
  /// view's margins after the links, so they survive the baseline link's
  /// reset of the top and bottom anchors, and the view measurer subtracts
  /// them from the layout's size.
  void _applyMatchParentMargins(ConstraintWidget w, ConstraintParentData pd) {
    if (pd.width is MatchParentDimension) {
      final (leftLink, rightLink) = _horizontalLinksOf(pd);
      w.mLeft.mMargin = leftLink?.margin.round() ?? 0;
      w.mRight.mMargin = rightLink?.margin.round() ?? 0;
    }
    if (pd.height is MatchParentDimension) {
      w.mTop.mMargin = pd.top?.margin.round() ?? 0;
      w.mBottom.mMargin = pd.bottom?.margin.round() ?? 0;
    }
  }

  /// A guideline's position (CL 1374-1390): Android's view Guideline is
  /// always GONE, so its widget is too, and nothing but its position is
  /// configured.
  ///
  /// LayoutParams.resolveLayoutDirection with guidelineUseRtl at its default
  /// (true): in a right-to-left layout a vertical guideline counts from the
  /// right, so its percent becomes 1 - percent, computed in float, and begin
  /// and end trade edges. A horizontal guideline is placed as given.
  void _applyGuidelineConfig(Guideline w, ConstraintParentData pd) {
    w.setOrientation(
      pd.guidelineAxis == Axis.horizontal
          ? Guideline.horizontal
          : Guideline.vertical,
    );
    w.setVisibility(ConstraintWidget.GONE);
    final mirror = !_ltr && pd.guidelineAxis == Axis.vertical;
    final percent = pd.guidelinePercent;
    final begin = pd.guidelineBegin;
    final end = pd.guidelineEnd;
    if (percent != null) {
      w.setGuidePercent(mirror ? fsub(1, f32(percent)) : percent);
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
  }

  /// A barrier's configuration: Android's view Barrier is always GONE, so
  /// its widget is too. `.start` and `.end` resolve to the left or right
  /// edge for the text direction (the view Barrier's resolveRtl,
  /// Barrier.java 159-195), and the margin keeps its sign in both
  /// directions: a positive margin moves every barrier right or down.
  void _applyBarrierConfig(
    _EngineModel model,
    Barrier w,
    ConstraintParentData pd,
  ) {
    w.setVisibility(ConstraintWidget.GONE);
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
    w.removeAllIds();
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

  /// A group's own widget: Android's Group view is a ConstraintHelper whose
  /// widget is the plain widget of its layout params (wrap_content on both
  /// axes, no link, the group's own visibility), measured at 0 x 0 without
  /// a baseline and placed at the origin. Its members get its visibility
  /// through the group overrides (see [_computeDerivedState]).
  ///
  /// Also validates the group's referenced ids, reporting those that
  /// resolve to no sibling as a barrier does.
  void _applyGroupConfig(
    _EngineModel model,
    ConstraintWidget w,
    ConstraintParentData pd,
  ) {
    w.resetAnchors();
    w.setX(0);
    w.setY(0);
    w.setVisibility(_engineVisibility(pd.groupVisibility));
    w.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
    w.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
    w.setWidth(0);
    w.setHeight(0);
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

  /// Applies grid configuration on top of the grid's configuration as a
  /// child. Only called from model builds (grid changes are structural), so
  /// referenced widgets never need clearing.
  ///
  /// Nothing here depends on the text direction: the engine's grid mirrors
  /// its columns itself, following the container's right-to-left flag,
  /// which the host sets before every measure.
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

  /// Applies flow configuration on top of the flow's configuration as a
  /// child, as Android's view Flow configures its core Flow.
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
    w.removeAllIds();
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

  /// Marks the children referenced by a group whose visibility changed as if
  /// their own visibility had changed: a `Constrained` child is updated in
  /// place, while a flow or grid, whose configuration is applied at model
  /// build time, rebuilds the model.
  ///
  /// The group's own flag stays set: its widget's visibility is
  /// configuration too, which the in-place apply updates.
  void _passGroupChangesToMembers(_EngineModel model) {
    for (final pd in model.childData) {
      if (pd.helperKind != HelperKind.group || !pd.configDirty) continue;
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

  /// Brings [model]'s widgets back to their configuration before a measure
  /// of the persistent model: what Android's layout params give back on a
  /// measure of a changed hierarchy and the engine's measure can change.
  ///
  /// 1. Every FIXED size, from the parent data: the host's measure-state
  ///    reset keeps FIXED sizes, and a measure can widen one (`setFrame`).
  /// 2. Every virtual layout's own links, from its parent data: a flow's
  ///    measure can connect its own anchors again (a right-to-left vertical
  ///    flow re-links its left anchor, Flow.java 644-647).
  ///
  /// Everything else a measure changes the host resets before the next one
  /// (the measure state, the dependents, the helpers' visibility, the
  /// members of the virtual layouts), or Android keeps too.
  void _syncModelForMeasure(_EngineModel model) {
    for (var i = 0; i < model.widgets.length; i++) {
      final pd = model.childData[i];
      switch (pd.helperKind) {
        case HelperKind.none || HelperKind.flow || HelperKind.grid:
          final w = model.widgets[i];
          final width = pd.width;
          final height = pd.height;
          if (width is FixedDimension) {
            w.setWidth(width.pixels.round());
          }
          if (height is FixedDimension) {
            w.setHeight(height.pixels.round());
          }
          if (w is VirtualLayout) {
            w.resetAnchors();
            _connectOwnLinks(model, w, pd, report: false);
            _applyMatchParentMargins(w, pd);
          }
        case HelperKind.guideline || HelperKind.barrier || HelperKind.group:
          break;
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

  /// Recomputes state derived from the whole of [model]: the visibility
  /// groups impose on their referenced children, and the children a grid
  /// places.
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
        // Guidelines and barriers have no visibility to set: Android's are
        // always gone.
        if (member.helperKind == HelperKind.none ||
            member.helperKind == HelperKind.flow ||
            member.helperKind == HelperKind.grid) {
          groupOverrides[member] = pd.groupVisibility;
        }
      }
    }

    // The widgets a grid that takes part in the layout places: their
    // horizontal bias counts from the start edge (see _applyChildConfig).
    final gridMembers = model.gridMembers..clear();
    for (final pd in model.childData) {
      if (pd.helperKind != HelperKind.grid) continue;
      if (model.visibilityOf(pd) == ConstraintVisibility.gone) continue;
      gridMembers.addAll(pd.gridReferenced);
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
  /// must not throw (see [RenderConstraintLayout._resolveDry]).
  void _reportUnknownId(_EngineModel model, String message) {
    assert(
      () {
        if (model.reportsUnknownIds) throw FlutterError(message);
        return true;
      }(),
      'an unknown id is reported by the FlutterError thrown above, in debug '
      'builds only, so the closure itself never fails',
    );
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
  ///
  /// It reads the links Android's configuration leaves: a circle replaces
  /// every other link, and a baseline link to a sibling the top and bottom
  /// links.
  void _reportLinkLoop(_EngineModel model) {
    assert(
      () {
        if (!model.reportsUnknownIds) return true;
        final loop = _linkLoop(model);
        if (loop == null) return true;
        String edge(ConstraintAnchor anchor) {
          final index = model.widgets.indexOf(anchor.mOwner);
          final pd = model.childData[index];
          final name = switch (anchor.mType) {
            ConstraintAnchorType.left when pd.start != null || pd.end != null =>
              _ltr ? 'start' : 'end',
            ConstraintAnchorType.right
                when pd.start != null || pd.end != null =>
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
      }(),
      'a link loop is reported by the FlutterError thrown above, in debug '
      'builds only, so the closure itself never fails',
    );
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
}

/// Hands [model]'s group overrides to the children's parent data, where
/// painting, hit testing, semantics, and the debug overlay read them. Only
/// for the persistent model: a dry-layout query must leave parent data
/// alone.
void _publishGroupOverrides(_EngineModel model) {
  for (final pd in model.childData) {
    pd.groupOverride = model.groupOverrides[pd];
  }
}

/// How an error names an [id] that no link or reference can resolve: a
/// group's, which nothing can link to or reference (its widget, a 0 x 0
/// point at the layout's origin as Android's Group view is, only stands in
/// the solve), or an unknown id.
String _describeUnresolved(_EngineModel model, Symbol id) =>
    model.groupIds.contains(id)
    ? '$id, which is a ConstraintGroup. A group only sets the visibility of '
          'the children it references, so nothing can link to or reference it'
    : 'unknown id $id';

/// The links of a loop that [_EngineModelBuilder._reportLinkLoop] reports,
/// or null. It follows the engine's two chain walks along each axis: the
/// dependency graph's, through every edge whose target links straight back
/// to it, and the solver's, from a chain's first child to each next child
/// whose start links to the one before.
List<ConstraintAnchor>? _linkLoop(_EngineModel model) {
  ConstraintAnchor? linkedBack(ConstraintAnchor anchor) {
    final target = anchor.mTarget;
    return target != null && identical(target.mTarget, anchor) ? target : null;
  }

  for (final widget in model.widgets) {
    for (final horizontal in const [true, false]) {
      ConstraintAnchor startOf(ConstraintWidget w) =>
          horizontal ? w.mLeft : w.mTop;
      ConstraintAnchor endOf(ConstraintWidget w) =>
          horizontal ? w.mRight : w.mBottom;
      // The graph's walk: back through linked-back starts, then forward
      // through linked-back ends. The walk's lists are made at its first
      // linked-back edge (most edges are not), holding what they held
      // before at every step.
      for (final forward in const [false, true]) {
        List<ConstraintAnchor>? links;
        Set<ConstraintWidget>? seen;
        var current = widget;
        while (true) {
          final anchor = forward ? endOf(current) : startOf(current);
          final back = linkedBack(anchor);
          if (back == null) break;
          (links ??= <ConstraintAnchor>[]).add(anchor);
          if (!(seen ??= <ConstraintWidget>{widget}).add(back.mOwner)) {
            return links;
          }
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
