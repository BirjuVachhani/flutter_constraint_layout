// ftree (FORMATS.md section 11): an FLayout (lib/src/fmodel.dart, read from
// a corpus line) as a real ConstraintLayout widget tree of ContentModelBox
// children, and the frames of the laid-out tree in section 2's geometry
// format.
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

import 'content_model_box.dart';
import 'src/fmodel.dart';

export 'src/fmodel.dart';

Symbol _sym(String name) => name == 'parent' ? parent : Symbol(name);

Dimension _dimension(FDim d) {
  double? opt(int v) => v == 0 ? null : v.toDouble();
  return switch (d.kind) {
    FDimKind.fixed => Dimension.fixed(d.px.toDouble()),
    FDimKind.wrap => Dimension.wrapContent,
    FDimKind.parent => Dimension.matchParent,
    FDimKind.spread =>
      d.min == 0 && d.max == 0
          ? Dimension.matchConstraint
          : Dimension.spread(min: opt(d.min), max: opt(d.max)),
    FDimKind.cwrap => Dimension.constrainedWrap(min: opt(d.min), max: opt(d.max)),
    FDimKind.percent => Dimension.percent(d.pct, min: opt(d.min), max: opt(d.max)),
  };
}

HorizontalLink? _h(FLink? l) {
  if (l == null) return null;
  final t = _sym(l.target);
  final m = l.margin.toDouble(), g = l.goneMargin.toDouble();
  return switch (l.edge) {
    'left' => HorizontalLink.leftOf(t, margin: m, goneMargin: g),
    'right' => HorizontalLink.rightOf(t, margin: m, goneMargin: g),
    _ => throw ArgumentError('horizontal edge ${l.edge}'),
  };
}

VerticalLink? _v(FLink? l) {
  if (l == null) return null;
  final t = _sym(l.target);
  final m = l.margin.toDouble(), g = l.goneMargin.toDouble();
  return switch (l.edge) {
    'top' => VerticalLink.topOf(t, margin: m, goneMargin: g),
    'bottom' => VerticalLink.bottomOf(t, margin: m, goneMargin: g),
    'baseline' => VerticalLink.baselineOf(t, margin: m, goneMargin: g),
    _ => throw ArgumentError('vertical edge ${l.edge}'),
  };
}

ChainStyle? _chain(int? s) => switch (s) {
  null || 0 => null,
  1 => ChainStyle.spreadInside,
  2 => ChainStyle.packed,
  _ => throw ArgumentError('chain style $s'),
};

ConstraintVisibility _vis(int v) => switch (v) {
  0 => ConstraintVisibility.visible,
  4 => ConstraintVisibility.invisible,
  8 => ConstraintVisibility.gone,
  _ => throw ArgumentError('visibility $v'),
};

/// The children of [layout] as ConstraintLayout children. [counters], when
/// given, receives one LayoutCounter per regular child (benchmarks).
List<Widget> buildChildren(FLayout layout, {Map<String, LayoutCounter>? counters}) {
  final out = <Widget>[];
  for (final c in layout.children) {
    final id = _sym(c.name);
    switch (c.kind) {
      case FKind.guideline:
        out.add(
          c.horizontalLine
              ? Guideline.horizontal(
                  id: id,
                  begin: c.gBegin,
                  end: c.gEnd,
                  percent: c.gPercent,
                )
              : Guideline.vertical(
                  id: id,
                  begin: c.gBegin,
                  end: c.gEnd,
                  percent: c.gPercent,
                ),
        );
      case FKind.barrier:
        out.add(
          Barrier(
            id: id,
            edge: switch (c.barrierType) {
              0 => BarrierEdge.left,
              1 => BarrierEdge.right,
              2 => BarrierEdge.top,
              _ => BarrierEdge.bottom,
            },
            referenced: [for (final r in c.refs) _sym(r)],
            margin: c.barrierMargin.toDouble(),
            allowsGone: c.allowsGone,
          ),
        );
      case FKind.flow:
        out.add(
          ConstraintFlow(
            id: id,
            referenced: [for (final r in c.refs) _sym(r)],
            orientation: c.flowOrientation == 0 ? Axis.horizontal : Axis.vertical,
            left: _h(c.left),
            right: _h(c.right),
            top: _v(c.top),
            bottom: _v(c.bottom),
            horizontalBias: c.hBias,
            verticalBias: c.vBias,
            width: _dimension(c.width),
            height: _dimension(c.height),
            wrap: switch (c.flowWrap) {
              0 => FlowWrap.none,
              1 => FlowWrap.chain,
              _ => FlowWrap.aligned,
            },
            horizontalGap: c.flowHGap.toDouble(),
            verticalGap: c.flowVGap.toDouble(),
            horizontalChainStyle: c.flowHStyle == null
                ? null
                : (_chain(c.flowHStyle) ?? ChainStyle.spread),
            verticalChainStyle: c.flowVStyle == null
                ? null
                : (_chain(c.flowVStyle) ?? ChainStyle.spread),
            contentHorizontalBias: c.flowHBias,
            contentVerticalBias: c.flowVBias,
            horizontalAlign: switch (c.flowHAlign) {
              0 => FlowHorizontalAlign.start,
              1 => FlowHorizontalAlign.end,
              _ => FlowHorizontalAlign.center,
            },
            verticalAlign: switch (c.flowVAlign) {
              0 => FlowVerticalAlign.top,
              1 => FlowVerticalAlign.bottom,
              3 => FlowVerticalAlign.baseline,
              _ => FlowVerticalAlign.center,
            },
            maxElementsWrap: c.flowMaxElements,
            padding: c.flowPadding.toDouble(),
            visibility: _vis(c.visibility),
          ),
        );
      case FKind.widget:
        final circle = c.circle;
        out.add(
          Constrained(
            id: id,
            left: _h(c.left),
            right: _h(c.right),
            top: _v(c.top),
            bottom: _v(c.bottom),
            baseline: _v(c.baseline),
            circle: circle == null
                ? null
                : CircularLink.around(
                    _sym(circle.target),
                    angle: circle.angle,
                    radius: circle.radius.toDouble(),
                  ),
            horizontalBias: c.hBias,
            verticalBias: c.vBias,
            width: _dimension(c.width),
            height: _dimension(c.height),
            aspectRatio: c.ratio,
            horizontalChainStyle: _chain(c.hChain),
            verticalChainStyle: _chain(c.vChain),
            horizontalWeight: c.hWeight,
            verticalWeight: c.vWeight,
            visibility: _vis(c.visibility),
            child: ContentModelBox(
              content: c.content,
              counter: counters?[c.name],
            ),
          ),
        );
    }
  }
  return out;
}

/// The layout's incoming constraints: tight on a FIXED axis, 0..infinity on
/// a WRAP axis (FORMATS.md 4.2's U(0)).
BoxConstraints constraintsOf(FLayout layout) => BoxConstraints(
  minWidth: layout.minW,
  maxWidth: layout.maxW,
  minHeight: layout.minH,
  maxHeight: layout.maxH,
);

/// The adapter's flags for Android's optimization level [value] (FL_LEVEL),
/// each bit as its flag: 257 is [OptimizationLevel.standard], 0
/// [OptimizationLevel.none].
OptimizationLevel optimizationLevelOf(int value) {
  const flags = <OptimizationLevel>[
    OptimizationLevel.direct,
    OptimizationLevel.barrier,
    OptimizationLevel.chains,
    OptimizationLevel.dimensions,
    OptimizationLevel.ratio,
    OptimizationLevel.groups,
    OptimizationLevel.graph,
    OptimizationLevel.graphWrap,
    OptimizationLevel.cacheMeasures,
    OptimizationLevel.dependencyOrdering,
    OptimizationLevel.grouping,
  ];
  var level = OptimizationLevel.none;
  for (final flag in flags) {
    if (value & flag.value != 0) level = level | flag;
  }
  return level;
}

/// The whole tree for [layout] under its constraints, keyed by [key] so every
/// layout gets a fresh render object, at [optimizationLevel] (Android's
/// default unless given).
Widget buildTree(
  FLayout layout, {
  Key? key,
  Map<String, LayoutCounter>? counters,
  OptimizationLevel optimizationLevel = OptimizationLevel.standard,
}) =>
    Directionality(
      textDirection: layout.rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: layout.minW,
          maxWidth: layout.maxW,
          minHeight: layout.minH,
          maxHeight: layout.maxH,
          child: ConstraintLayout(
            key: key,
            optimizationLevel: optimizationLevel,
            children: buildChildren(layout, counters: counters),
          ),
        ),
      ),
    );

String _num(double v) {
  if (v.isFinite && v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

/// Section 2's geometry string for a laid-out [ro] built from [layout].
String geometryOf(RenderConstraintLayout ro, FLayout layout) {
  final sb = StringBuffer()
    ..write('root ${_num(ro.size.width)} x ${_num(ro.size.height)}');
  final kids = ro.getChildrenAsList();
  if (kids.length != layout.children.length) {
    throw StateError('child count ${kids.length} != ${layout.children.length}');
  }
  for (var i = 0; i < kids.length; i++) {
    final c = layout.children[i];
    final rb = kids[i];
    final offset = (rb.parentData! as BoxParentData).offset;
    sb.write(' | ${c.name}: ');
    if (c.visibility == 8 && c.kind != FKind.barrier) {
      sb.write('gone, ${_num(rb.size.width)} x ${_num(rb.size.height)}');
    } else {
      sb.write(
        '(${_num(offset.dx)}, ${_num(offset.dy)}) '
        '${_num(rb.size.width)} x ${_num(rb.size.height)}',
      );
    }
  }
  return sb.toString();
}
