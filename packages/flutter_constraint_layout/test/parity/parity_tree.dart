// The widget trees of the Android parity corpus (see README.md here): a
// corpus entry's `tree` as a real ConstraintLayout of ContentModelBox
// children, and the laid-out frames in the oracle's geometry format.
import 'package:flutter/rendering.dart';
// The adapter's ConstraintFlow is the flow; Flutter's Flow is not used.
import 'package:flutter/widgets.dart' hide Flow;
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

import 'content_model_box.dart';

Symbol _symbol(String name) => name == 'parent' ? parent : Symbol(name);

Dimension _dimension(Object? json) {
  double? bound(Object? v) => v == 0 ? null : (v! as num).toDouble();
  return switch (json) {
    'wrap' => Dimension.wrapContent,
    'parent' => Dimension.matchParent,
    ['fixed', final num px] => Dimension.fixed(px.toDouble()),
    ['spread', final min, final max] =>
      min == 0 && max == 0
          ? Dimension.matchConstraint
          : Dimension.spread(min: bound(min), max: bound(max)),
    ['cwrap', final min, final max] => Dimension.constrainedWrap(
      min: bound(min),
      max: bound(max),
    ),
    ['percent', final num percent, final min, final max] => Dimension.percent(
      percent.toDouble(),
      min: bound(min),
      max: bound(max),
    ),
    _ => throw ArgumentError('dimension $json'),
  };
}

HorizontalLink? _horizontal(Object? json) {
  if (json == null) return null;
  final [target, edge, margin, gone] = json as List<Object?>;
  final t = _symbol(target! as String);
  final m = (margin! as num).toDouble(), g = (gone! as num).toDouble();
  return switch (edge) {
    'left' => HorizontalLink.leftOf(t, margin: m, goneMargin: g),
    'right' => HorizontalLink.rightOf(t, margin: m, goneMargin: g),
    _ => throw ArgumentError('horizontal edge $edge'),
  };
}

VerticalLink? _vertical(Object? json) {
  if (json == null) return null;
  final [target, edge, margin, gone] = json as List<Object?>;
  final t = _symbol(target! as String);
  final m = (margin! as num).toDouble(), g = (gone! as num).toDouble();
  return switch (edge) {
    'top' => VerticalLink.topOf(t, margin: m, goneMargin: g),
    'bottom' => VerticalLink.bottomOf(t, margin: m, goneMargin: g),
    'baseline' => VerticalLink.baselineOf(t, margin: m, goneMargin: g),
    _ => throw ArgumentError('vertical edge $edge'),
  };
}

ChainStyle? _chainStyle(Object? style) => switch (style) {
  null || 0 => null,
  1 => ChainStyle.spreadInside,
  2 => ChainStyle.packed,
  _ => throw ArgumentError('chain style $style'),
};

ConstraintVisibility _visibility(Object? v) => switch (v) {
  null || 0 => ConstraintVisibility.visible,
  4 => ConstraintVisibility.invisible,
  8 => ConstraintVisibility.gone,
  _ => throw ArgumentError('visibility $v'),
};

double? _double(Object? v) => (v as num?)?.toDouble();

double _bias(Object? v) => _double(v) ?? 0.5;

List<Symbol> _refs(Object? refs) => [
  for (final r in refs! as List<Object?>) _symbol(r! as String),
];

/// The children of [tree] (an entry's `tree`) as ConstraintLayout children.
List<Widget> buildChildren(Map<String, Object?> tree) => [
  for (final json
      in (tree['children']! as List<Object?>).cast<Map<String, Object?>>())
    _child(json),
];

Widget _child(Map<String, Object?> c) {
  final id = _symbol(c['id']! as String);
  switch (c['kind']) {
    case 'guideline':
      final begin = _double(c['begin']);
      final end = _double(c['end']);
      final percent = _double(c['percent']);
      return c['orientation'] == 'horizontal'
          ? Guideline.horizontal(
              id: id,
              begin: begin,
              end: end,
              percent: percent,
            )
          : Guideline.vertical(
              id: id,
              begin: begin,
              end: end,
              percent: percent,
            );
    case 'barrier':
      return Barrier(
        id: id,
        edge: switch (c['edge']) {
          'left' => BarrierEdge.left,
          'right' => BarrierEdge.right,
          'top' => BarrierEdge.top,
          _ => BarrierEdge.bottom,
        },
        referenced: _refs(c['refs']),
        margin: (c['margin']! as num).toDouble(),
        allowsGone: c['allowsGone'] as bool? ?? true,
      );
    case 'flow':
      final f = c['flow']! as Map<String, Object?>;
      ChainStyle? style(Object? s) =>
          s == null ? null : (_chainStyle(s) ?? ChainStyle.spread);
      return ConstraintFlow(
        id: id,
        referenced: _refs(c['refs']),
        orientation: f['orientation'] == 0 ? Axis.horizontal : Axis.vertical,
        left: _horizontal(c['left']),
        right: _horizontal(c['right']),
        top: _vertical(c['top']),
        bottom: _vertical(c['bottom']),
        horizontalBias: _bias(c['hBias']),
        verticalBias: _bias(c['vBias']),
        width: _dimension(c['width']),
        height: _dimension(c['height']),
        wrap: switch (f['wrap']) {
          0 => FlowWrap.none,
          1 => FlowWrap.chain,
          _ => FlowWrap.aligned,
        },
        horizontalGap: _double(f['hGap']) ?? 0,
        verticalGap: _double(f['vGap']) ?? 0,
        horizontalChainStyle: style(f['hStyle']),
        verticalChainStyle: style(f['vStyle']),
        contentHorizontalBias: _bias(f['hBias']),
        contentVerticalBias: _bias(f['vBias']),
        horizontalAlign: switch (f['hAlign']) {
          0 => FlowHorizontalAlign.start,
          1 => FlowHorizontalAlign.end,
          _ => FlowHorizontalAlign.center,
        },
        verticalAlign: switch (f['vAlign']) {
          0 => FlowVerticalAlign.top,
          1 => FlowVerticalAlign.bottom,
          3 => FlowVerticalAlign.baseline,
          _ => FlowVerticalAlign.center,
        },
        maxElementsWrap: f['maxElements'] as int?,
        padding: _double(f['padding']) ?? 0,
        visibility: _visibility(c['visibility']),
      );
    case 'widget':
      final circle = c['circle'] as List<Object?>?;
      return Constrained(
        id: id,
        left: _horizontal(c['left']),
        right: _horizontal(c['right']),
        top: _vertical(c['top']),
        bottom: _vertical(c['bottom']),
        baseline: _vertical(c['baseline']),
        circle: circle == null
            ? null
            : CircularLink.around(
                _symbol(circle[0]! as String),
                angle: (circle[1]! as num).toDouble(),
                radius: (circle[2]! as num).toDouble(),
              ),
        horizontalBias: _bias(c['hBias']),
        verticalBias: _bias(c['vBias']),
        width: _dimension(c['width']),
        height: _dimension(c['height']),
        aspectRatio: _double(c['ratio']),
        horizontalChainStyle: _chainStyle(c['hChain']),
        verticalChainStyle: _chainStyle(c['vChain']),
        horizontalWeight: _double(c['hWeight']),
        verticalWeight: _double(c['vWeight']),
        visibility: _visibility(c['visibility']),
        child: ContentModelBox(
          content: ContentModel.fromJson(c['content']! as List<Object?>),
        ),
      );
    default:
      throw ArgumentError('child kind ${c['kind']}');
  }
}

/// The layout's incoming constraints, `[minW, maxW, minH, maxH]` with null
/// for an unbounded maximum: tight on the oracle's EXACTLY axes, 0..infinity
/// on its UNSPECIFIED ones.
BoxConstraints constraintsOf(Map<String, Object?> tree) {
  final [minW, maxW, minH, maxH] = tree['constraints']! as List<Object?>;
  return BoxConstraints(
    minWidth: (minW! as num).toDouble(),
    maxWidth: (maxW as num?)?.toDouble() ?? double.infinity,
    minHeight: (minH! as num).toDouble(),
    maxHeight: (maxH as num?)?.toDouble() ?? double.infinity,
  );
}

/// The whole tree for [tree] under its constraints, keyed by [key] so every
/// entry gets a fresh render object.
Widget buildTree(Map<String, Object?> tree, {Key? key}) {
  final c = constraintsOf(tree);
  return Directionality(
    textDirection: tree['rtl'] == true ? TextDirection.rtl : TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: c.minWidth,
        maxWidth: c.maxWidth,
        minHeight: c.minHeight,
        maxHeight: c.maxHeight,
        child: ConstraintLayout(key: key, children: buildChildren(tree)),
      ),
    ),
  );
}

String _number(double v) {
  if (v.isFinite && v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

/// The oracle's geometry string for [ro], laid out from [tree]: the layout's
/// size, then each child in child order with its offset and size, or
/// `gone` and its size for a gone child that is not a barrier (Android's
/// `onLayout` places guidelines and barriers, which are always gone, and
/// skips other gone children).
String geometryOf(RenderConstraintLayout ro, Map<String, Object?> tree) {
  final sb = StringBuffer()
    ..write('root ${_number(ro.size.width)} x ${_number(ro.size.height)}');
  final children = (tree['children']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final boxes = ro.getChildrenAsList();
  if (boxes.length != children.length) {
    throw StateError('child count ${boxes.length} != ${children.length}');
  }
  for (var i = 0; i < boxes.length; i++) {
    final c = children[i];
    final box = boxes[i];
    final offset = (box.parentData! as BoxParentData).offset;
    sb.write(' | ${c['id']}: ');
    if (c['visibility'] == 8 && c['kind'] != 'barrier') {
      sb.write(
        'gone, ${_number(box.size.width)} x ${_number(box.size.height)}',
      );
    } else {
      sb.write(
        '(${_number(offset.dx)}, ${_number(offset.dy)}) '
        '${_number(box.size.width)} x ${_number(box.size.height)}',
      );
    }
  }
  return sb.toString();
}
