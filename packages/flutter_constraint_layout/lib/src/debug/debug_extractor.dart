import 'package:constraint_engine/constraint_engine.dart';
// The engine also declares a class named Flow (the virtual layout).
import 'package:flutter/widgets.dart' hide Flow;

import '../constraint_parent_data.dart';
import '../types.dart';
import 'debug_scene.dart';

/// Builds the debug-overlay scene from the engine state after a layout pass.
///
/// [widgets], [parentData], and [children] are the render object's
/// index-aligned model lists. Inputs are never mutated.
///
/// Chain membership is derived from anchor topology (a connection is a chain
/// link iff the target anchor points back at the source anchor), never from
/// the container's `ChainHead` bookkeeping, which is only populated on the
/// solver fallback path.
DebugScene buildDebugScene({
  required ConstraintWidgetContainer container,
  required List<ConstraintWidget> widgets,
  required List<ConstraintParentData> parentData,
  required List<RenderBox> children,
}) =>
    _SceneExtractor(container, widgets, parentData, children).extract();

class _SceneExtractor {
  _SceneExtractor(this.container, this.widgets, this.parentData, this.children)
      : indexOf = Map<ConstraintWidget, int>.identity() {
    for (var i = 0; i < widgets.length; i++) {
      indexOf[widgets[i]] = i;
    }
  }

  final ConstraintWidgetContainer container;
  final List<ConstraintWidget> widgets;
  final List<ConstraintParentData> parentData;
  final List<RenderBox> children;
  final Map<ConstraintWidget, int> indexOf;

  final boxes = <DebugWidgetBox>[];
  final connections = <DebugConnection>[];
  final guidelines = <DebugGuidelineInfo>[];
  final barriers = <DebugBarrierInfo>[];

  /// Chain pairs already emitted: (lower index, higher index, horizontal).
  final _emittedChains = <(int, int, bool)>{};

  DebugScene extract() {
    for (var i = 0; i < widgets.length; i++) {
      final pd = parentData[i];
      final w = widgets[i];
      switch (pd.helperKind) {
        case HelperKind.none:
          if (w.getVisibility() == ConstraintWidget.GONE) break;
          _addBox(i, virtual: false);
          _addConnections(i);
        case HelperKind.flow || HelperKind.grid:
          _addBox(i, virtual: true);
          _addConnections(i);
        case HelperKind.guideline:
          _addGuideline(i);
        case HelperKind.barrier:
          _addBarrier(w as Barrier);
      }
    }
    return DebugScene(
      layoutSize: Size(
        container.getWidth().toDouble(),
        container.getHeight().toDouble(),
      ),
      boxes: boxes,
      connections: connections,
      guidelines: guidelines,
      barriers: barriers,
    );
  }

  Rect _rectOf(ConstraintWidget w) => Rect.fromLTWH(
        w.getX().toDouble(),
        w.getY().toDouble(),
        w.getWidth().toDouble(),
        w.getHeight().toDouble(),
      );

  // ---------------------------------------------------------------- boxes --

  void _addBox(int i, {required bool virtual}) {
    final w = widgets[i];
    final pd = parentData[i];
    final rect = _rectOf(w);
    final baselineUsed = !virtual &&
        w.hasBaseline() &&
        (w.mBaseline.isConnected() || w.mBaseline.hasDependents());
    boxes.add(DebugWidgetBox(
      rect: rect,
      idLabel: _idLabel(pd.id),
      typeLabel: virtual ? null : _typeLabel(children[i]),
      invisible: pd.visibility == ConstraintVisibility.invisible,
      virtual: virtual,
      baselineY: baselineUsed ? rect.top + w.getBaselineDistance() : null,
      connectedEdges: {
        if (w.mLeft.isConnected()) DebugEdge.left,
        if (w.mRight.isConnected()) DebugEdge.right,
        if (w.mTop.isConnected()) DebugEdge.top,
        if (w.mBottom.isConnected()) DebugEdge.bottom,
        if (w.mBaseline.isConnected()) DebugEdge.baseline,
      },
    ));
  }

  static final _symbolName = RegExp(r'^Symbol\("(.*)"\)$');

  String? _idLabel(Symbol? id) {
    if (id == null) return null;
    final raw = id.toString();
    return _symbolName.firstMatch(raw)?.group(1) ?? raw;
  }

  /// The user-meaningful widget type: the widget sitting directly below the
  /// `Constrained` in the element tree (via [RenderObject.debugCreator]),
  /// falling back to the render object's own type name.
  String _typeLabel(RenderBox child) {
    final creator = child.debugCreator;
    if (creator is DebugCreator) {
      Widget best = creator.element.widget;
      creator.element.visitAncestorElements((element) {
        final widget = element.widget;
        if (widget is ParentDataWidget<ConstraintParentData>) return false;
        best = widget;
        return true;
      });
      return best.runtimeType.toString();
    }
    var name = child.runtimeType.toString();
    if (name.startsWith('Render')) name = name.substring('Render'.length);
    if (name.startsWith('_')) name = name.substring(1);
    return name;
  }

  // ---------------------------------------------------------- connections --

  void _addConnections(int i) {
    final w = widgets[i];
    if (_addCircular(i, w)) {
      // A circular constraint replaces the center-anchor drawing; side
      // anchors (if any) still process below.
    }
    _addAxis(i, w, horizontal: true);
    _addAxis(i, w, horizontal: false);
    _addBaseline(i, w);
  }

  bool _addCircular(int i, ConstraintWidget w) {
    if (!w.mCenter.isConnected() || w.mCircleConstraintAngle.isNaN) {
      return false;
    }
    final target = w.mCenter.getTarget()!.getOwner();
    final sourceRect = _rectOf(w);
    final targetRect =
        identical(target, container) ? _containerRect : _rectOf(target);
    connections.add(DebugConnection(
      type: DebugConnectionType.circular,
      sourcePoint: sourceRect.center,
      targetPoint: targetRect.center,
      sourceEdge: DebugEdge.left,
      targetEdge: DebugEdge.left,
      horizontal: false,
      targetIsParent: identical(target, container),
      dashed: true,
      circularAngle: w.mCircleConstraintAngle,
      circularRadius: w.mCenter.getMargin().toDouble(),
    ));
    return true;
  }

  Rect get _containerRect => Rect.fromLTWH(
        0,
        0,
        container.getWidth().toDouble(),
        container.getHeight().toDouble(),
      );

  void _addAxis(int i, ConstraintWidget w, {required bool horizontal}) {
    final startAnchor = horizontal ? w.mLeft : w.mTop;
    final endAnchor = horizontal ? w.mRight : w.mBottom;
    final startIsChain = _isChainLink(startAnchor);
    final endIsChain = _isChainLink(endAnchor);

    // Center pair: both opposite anchors on the same target widget.
    if (!startIsChain &&
        !endIsChain &&
        startAnchor.isConnected() &&
        endAnchor.isConnected() &&
        identical(startAnchor.getTarget()!.getOwner(),
            endAnchor.getTarget()!.getOwner())) {
      _emitCenter(i, w, startAnchor, endAnchor, horizontal: horizontal);
      return;
    }

    final bothConnected = startAnchor.isConnected() && endAnchor.isConnected();
    final bias =
        horizontal ? parentData[i].horizontalBias : parentData[i].verticalBias;
    final biased = bothConnected && (bias - 0.5).abs() > 0.01;

    for (final (anchor, isChain, isStartSide) in [
      (startAnchor, startIsChain, true),
      (endAnchor, endIsChain, false),
    ]) {
      if (!anchor.isConnected()) continue;
      if (isChain) {
        _emitChain(i, anchor, horizontal: horizontal);
        continue;
      }
      // A spring when the opposite anchor is also connected (bias case); the
      // longer side of a biased pair renders dashed.
      final spring = bothConnected;
      final dashed = biased && (bias < 0.5 ? !isStartSide : isStartSide);
      _emitSingle(
        i,
        w,
        anchor,
        horizontal: horizontal,
        type: spring ? DebugConnectionType.spring : DebugConnectionType.normal,
        dashed: dashed,
      );
    }
  }

  /// A connection is a chain link iff its target anchor points straight back.
  bool _isChainLink(ConstraintAnchor anchor) {
    final target = anchor.getTarget();
    if (target == null) return false;
    if (identical(target.getOwner(), container)) return false;
    return identical(target.getTarget(), anchor);
  }

  void _emitChain(int i, ConstraintAnchor anchor, {required bool horizontal}) {
    final target = anchor.getTarget()!;
    final j = indexOf[target.getOwner()];
    if (j == null) return; // engine-internal widget (grid box); never chains
    final key = (i < j ? i : j, i < j ? j : i, horizontal);
    if (!_emittedChains.add(key)) return;
    final sourcePoint = _anchorPoint(widgets[i], anchor);
    connections.add(DebugConnection(
      type: DebugConnectionType.chain,
      sourcePoint: sourcePoint,
      targetPoint:
          _targetPoint(target, crossAxis: sourcePoint, horizontal: horizontal),
      sourceEdge: _edgeOf(anchor),
      targetEdge: _edgeOf(target),
      horizontal: horizontal,
      chainStyle: _chainStyleOf(widgets[i], horizontal: horizontal),
    ));
  }

  /// Walks to the chain head (source-side-most member) and reads its style.
  ChainStyle _chainStyleOf(ConstraintWidget member, {required bool horizontal}) {
    var head = member;
    for (var guard = 0; guard < widgets.length; guard++) {
      final anchor = horizontal ? head.mLeft : head.mTop;
      if (!_isChainLink(anchor)) break;
      head = anchor.getTarget()!.getOwner();
    }
    final style =
        horizontal ? head.mHorizontalChainStyle : head.mVerticalChainStyle;
    return switch (style) {
      ConstraintWidget.CHAIN_SPREAD_INSIDE => ChainStyle.spreadInside,
      ConstraintWidget.CHAIN_PACKED => ChainStyle.packed,
      _ => ChainStyle.spread,
    };
  }

  void _emitCenter(
    int i,
    ConstraintWidget w,
    ConstraintAnchor startAnchor,
    ConstraintAnchor endAnchor, {
    required bool horizontal,
  }) {
    final startPoint = _anchorPoint(w, startAnchor);
    final endPoint = _anchorPoint(w, endAnchor);
    final startTarget = _targetPoint(startAnchor.getTarget()!,
        crossAxis: startPoint, horizontal: horizontal);
    final endTarget = _targetPoint(endAnchor.getTarget()!,
        crossAxis: endPoint, horizontal: horizontal);
    connections.add(DebugConnection(
      type: DebugConnectionType.center,
      sourcePoint: startPoint,
      targetPoint: startTarget,
      sourceEdge: _edgeOf(startAnchor),
      targetEdge: _edgeOf(startAnchor.getTarget()!),
      horizontal: horizontal,
      margin: startAnchor.getMargin().toDouble(),
      targetIsParent:
          identical(startAnchor.getTarget()!.getOwner(), container),
      // The second leg of the pair: opposite-side source and target points.
      centerDashedLine: (endPoint, endTarget),
    ));
  }

  void _emitSingle(
    int i,
    ConstraintWidget w,
    ConstraintAnchor anchor, {
    required bool horizontal,
    required DebugConnectionType type,
    required bool dashed,
  }) {
    final target = anchor.getTarget()!;
    final sourcePoint = _anchorPoint(w, anchor);
    final targetPoint =
        _targetPoint(target, crossAxis: sourcePoint, horizontal: horizontal);
    var resolved = type;
    if (type == DebugConnectionType.normal &&
        (sourcePoint - targetPoint).distance < 4) {
      resolved = DebugConnectionType.adjacent;
    }
    connections.add(DebugConnection(
      type: resolved,
      sourcePoint: sourcePoint,
      targetPoint: targetPoint,
      sourceEdge: _edgeOf(anchor),
      targetEdge: _edgeOf(target),
      horizontal: horizontal,
      margin: anchor.getMargin().toDouble(),
      targetIsParent: identical(target.getOwner(), container),
      dashed: dashed,
    ));
  }

  void _addBaseline(int i, ConstraintWidget w) {
    if (!w.mBaseline.isConnected()) return;
    final target = w.mBaseline.getTarget()!;
    final targetOwner = target.getOwner();
    final sourceRect = _rectOf(w);
    final targetRect =
        identical(targetOwner, container) ? _containerRect : _rectOf(targetOwner);
    connections.add(DebugConnection(
      type: DebugConnectionType.baseline,
      sourcePoint: Offset(
        sourceRect.center.dx,
        sourceRect.top + w.getBaselineDistance(),
      ),
      targetPoint: Offset(
        targetRect.center.dx,
        targetRect.top + targetOwner.getBaselineDistance(),
      ),
      sourceEdge: DebugEdge.baseline,
      targetEdge: DebugEdge.baseline,
      horizontal: false,
      targetIsParent: identical(targetOwner, container),
    ));
  }

  // ------------------------------------------------------------ geometry --

  DebugEdge _edgeOf(ConstraintAnchor anchor) => switch (anchor.getType()) {
        ConstraintAnchorType.left => DebugEdge.left,
        ConstraintAnchorType.right => DebugEdge.right,
        ConstraintAnchorType.top => DebugEdge.top,
        ConstraintAnchorType.bottom => DebugEdge.bottom,
        ConstraintAnchorType.baseline => DebugEdge.baseline,
        _ => DebugEdge.left,
      };

  /// The midpoint of the anchor's edge on its owner widget.
  Offset _anchorPoint(ConstraintWidget w, ConstraintAnchor anchor) {
    final rect = identical(w, container) ? _containerRect : _rectOf(w);
    return switch (_edgeOf(anchor)) {
      DebugEdge.left => Offset(rect.left, rect.center.dy),
      DebugEdge.right => Offset(rect.right, rect.center.dy),
      DebugEdge.top => Offset(rect.center.dx, rect.top),
      DebugEdge.bottom => Offset(rect.center.dx, rect.bottom),
      DebugEdge.baseline => Offset(rect.center.dx, rect.top),
    };
  }

  /// The point on the target anchor's edge, keeping the source's cross-axis
  /// coordinate clamped into the target edge's span.
  Offset _targetPoint(
    ConstraintAnchor target, {
    required Offset crossAxis,
    required bool horizontal,
  }) {
    final owner = target.getOwner();
    final rect =
        identical(owner, container) ? _containerRect : _rectOf(owner);
    if (horizontal) {
      final x = switch (_edgeOf(target)) {
        DebugEdge.right => rect.right,
        _ => rect.left,
      };
      return Offset(x, crossAxis.dy.clamp(rect.top, rect.bottom));
    }
    final y = switch (_edgeOf(target)) {
      DebugEdge.bottom => rect.bottom,
      _ => rect.top,
    };
    return Offset(crossAxis.dx.clamp(rect.left, rect.right), y);
  }

  // ------------------------------------------------------------- helpers --

  void _addGuideline(int i) {
    final w = widgets[i] as Guideline;
    final pd = parentData[i];
    final vertical = w.getOrientation() == Guideline.vertical;
    final String chipText;
    if (pd.guidelinePercent != null) {
      chipText = '${(pd.guidelinePercent! * 100).round()}%';
    } else if (pd.guidelineBegin != null) {
      chipText = '${pd.guidelineBegin!.round()}';
    } else {
      chipText = 'end ${pd.guidelineEnd?.round() ?? 0}';
    }
    guidelines.add(DebugGuidelineInfo(
      vertical: vertical,
      position: vertical ? w.getX().toDouble() : w.getY().toDouble(),
      chipText: chipText,
    ));
  }

  void _addBarrier(Barrier w) {
    final width = container.getWidth().toDouble();
    final height = container.getHeight().toDouble();
    switch (w.getBarrierType()) {
      case Barrier.left || Barrier.right:
        final x = w.getLeft().toDouble();
        barriers.add(DebugBarrierInfo(
          start: Offset(x, 0),
          end: Offset(x, height),
          fadeDirection: w.getBarrierType() == Barrier.left
              ? const Offset(-1, 0)
              : const Offset(1, 0),
        ));
      default:
        final y = w.getTop().toDouble();
        barriers.add(DebugBarrierInfo(
          start: Offset(0, y),
          end: Offset(width, y),
          fadeDirection: w.getBarrierType() == Barrier.top
              ? const Offset(0, -1)
              : const Offset(0, 1),
        ));
    }
  }
}
