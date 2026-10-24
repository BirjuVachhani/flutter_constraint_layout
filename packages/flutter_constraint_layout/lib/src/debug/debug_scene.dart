import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../types.dart';

/// How a [DebugConnection] is classified, mirroring Android Studio's
/// `DrawConnection` types.
enum DebugConnectionType {
  /// A plain one-sided constraint: curved line with an arrowhead.
  normal,

  /// A [normal] connection whose endpoints are within 4 px of each other:
  /// drawn as a small arrow only.
  adjacent,

  /// One side of an opposing pair (bias): drawn as a zigzag spring.
  spring,

  /// Both opposite anchors connect to the same target widget (centering):
  /// one connection for the pair, with a dashed center line.
  center,

  /// A bidirectional chain link between two chain members.
  chain,

  /// A baseline-to-baseline connection: tall bowed curve plus baseline ticks.
  baseline,

  /// A circular (angle + radius) constraint: dashed center-to-center line.
  circular,
}

/// Which edge of a widget a connection endpoint sits on.
enum DebugEdge { left, right, top, bottom, baseline }

/// One classified constraint connection, in layout-local coordinates.
@immutable
class DebugConnection {
  const DebugConnection({
    required this.type,
    required this.sourcePoint,
    required this.targetPoint,
    required this.sourceEdge,
    required this.targetEdge,
    required this.horizontal,
    this.margin = 0,
    this.targetIsParent = false,
    this.dashed = false,
    this.chainStyle,
    this.centerDashedLine,
    this.circularAngle,
    this.circularRadius,
  });

  final DebugConnectionType type;

  /// Resolved endpoint on the source widget's edge.
  final Offset sourcePoint;

  /// Resolved endpoint on the target's edge.
  final Offset targetPoint;

  final DebugEdge sourceEdge;
  final DebugEdge targetEdge;

  /// Whether the connection runs along the horizontal axis.
  final bool horizontal;

  /// The resolved margin (gone-aware), 0 when none.
  final double margin;

  /// Whether the target is the layout itself.
  final bool targetIsParent;

  /// Rendering hint: the far leg of a biased spring pair, or a circular line.
  final bool dashed;

  /// The chain's style; [DebugConnectionType.chain] only.
  final ChainStyle? chainStyle;

  /// The second leg of a centering pair: the opposite side's (source point,
  /// target point). The painter draws both legs plus a dashed line spanning
  /// [targetPoint] to this leg's target point. [DebugConnectionType.center]
  /// only.
  final (Offset, Offset)? centerDashedLine;

  /// Degrees clockwise, 0 = up; [DebugConnectionType.circular] only.
  final double? circularAngle;

  /// Pixel radius; [DebugConnectionType.circular] only.
  final double? circularRadius;

  @override
  String toString() =>
      'DebugConnection($type, $sourceEdge$sourcePoint -> $targetEdge'
      '$targetPoint${targetIsParent ? ' [parent]' : ''}'
      '${margin != 0 ? ', margin $margin' : ''}'
      '${chainStyle != null ? ', $chainStyle' : ''}'
      '${dashed ? ', dashed' : ''})';
}

/// The solved box of one real (or virtual-layout) child.
@immutable
class DebugWidgetBox {
  const DebugWidgetBox({
    required this.rect,
    this.idLabel,
    this.typeLabel,
    this.invisible = false,
    this.virtual = false,
    this.baselineY,
    this.connectedEdges = const {},
  });

  final Rect rect;

  /// The Symbol id, without the `Symbol("...")` wrapper. Null when the child
  /// has no id.
  final String? idLabel;

  /// The child widget's runtimeType name.
  final String? typeLabel;

  /// `ConstraintVisibility.invisible`: drawn at half opacity in blueprint.
  final bool invisible;

  /// A Flow/Grid virtual layout: dashed frame, no fill, no anchors.
  final bool virtual;

  /// Absolute baseline y, when the baseline participates in a constraint.
  final double? baselineY;

  /// Which side anchors are connected (drawn solid vs hollow).
  final Set<DebugEdge> connectedEdges;

  @override
  String toString() =>
      'DebugWidgetBox($rect${idLabel != null ? ', #$idLabel' : ''}'
      '${typeLabel != null ? ', $typeLabel' : ''}'
      '${invisible ? ', invisible' : ''}${virtual ? ', virtual' : ''})';
}

/// A guideline's resolved line and its position chip.
@immutable
class DebugGuidelineInfo {
  const DebugGuidelineInfo({
    required this.vertical,
    required this.position,
    required this.chipText,
  });

  /// A vertical line ([position] is x) vs a horizontal line ([position] is y).
  final bool vertical;

  final double position;

  /// The chip text, e.g. `25%`, `16`, or `end 24`.
  final String chipText;

  @override
  String toString() =>
      'DebugGuidelineInfo(${vertical ? 'x' : 'y'}=$position, "$chipText")';
}

/// A barrier's resolved line and fade side.
@immutable
class DebugBarrierInfo {
  const DebugBarrierInfo({
    required this.start,
    required this.end,
    required this.fadeDirection,
  });

  final Offset start;
  final Offset end;

  /// Unit vector perpendicular to the line, pointing to the fade side (the
  /// direction the barrier faces).
  final Offset fadeDirection;

  @override
  String toString() => 'DebugBarrierInfo($start -> $end, fade $fadeDirection)';
}

/// Everything the debug painter needs, extracted from the engine after a
/// layout pass. Painter-agnostic pure data.
@immutable
class DebugScene {
  const DebugScene({
    required this.layoutSize,
    required this.boxes,
    required this.connections,
    required this.guidelines,
    required this.barriers,
  });

  final Size layoutSize;
  final List<DebugWidgetBox> boxes;
  final List<DebugConnection> connections;
  final List<DebugGuidelineInfo> guidelines;
  final List<DebugBarrierInfo> barriers;

  @override
  String toString() =>
      'DebugScene($layoutSize, ${boxes.length} boxes, '
      '${connections.length} connections, ${guidelines.length} guidelines, '
      '${barriers.length} barriers)';
}
