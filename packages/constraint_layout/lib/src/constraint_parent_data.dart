import 'package:flutter/rendering.dart';

import 'dimension.dart';
import 'link.dart';
import 'types.dart';

/// Per-child layout data attached by `Constrained`, `Guideline`, or `Barrier`
/// and consumed by `RenderConstraintLayout`.
///
/// Holds the full constraint configuration copied from the parent-data widget,
/// plus the linked-list pointers and resolved [offset] provided by
/// [ContainerBoxParentData].
class ConstraintParentData extends ContainerBoxParentData<RenderBox> {
  /// The id assigned to this child.
  Symbol? id;

  /// What kind of engine object this child maps to. Guideline and barrier
  /// children use the `guideline*` / `barrier*` fields and ignore the rest.
  HelperKind helperKind = HelperKind.none;

  /// This widget's left edge, positioned against a target edge. Absolute.
  HorizontalLink? left;

  /// This widget's right edge, positioned against a target edge. Absolute.
  HorizontalLink? right;

  /// This widget's start edge, positioned against a target edge. RTL-aware.
  HorizontalLink? start;

  /// This widget's end edge, positioned against a target edge. RTL-aware.
  HorizontalLink? end;

  /// This widget's top edge, positioned against a target edge.
  VerticalLink? top;

  /// This widget's bottom edge, positioned against a target edge.
  VerticalLink? bottom;

  /// This widget's text baseline, positioned against a target edge.
  VerticalLink? baseline;

  /// Centers this widget on a circle around a target's center.
  CircularLink? circle;

  /// Horizontal position between opposing links: 0.0 = start, 1.0 = end.
  double horizontalBias = 0.5;

  /// Vertical position between opposing links: 0.0 = top, 1.0 = bottom.
  double verticalBias = 0.5;

  /// How the width is determined.
  Dimension width = Dimension.wrapContent;

  /// How the height is determined.
  Dimension height = Dimension.wrapContent;

  /// Enforced `width / height` ratio, or null.
  double? aspectRatio;

  /// Chain style applied when this child heads a horizontal chain.
  ChainStyle? horizontalChainStyle;

  /// Chain style applied when this child heads a vertical chain.
  ChainStyle? verticalChainStyle;

  /// Relative share of leftover space in a weighted horizontal chain.
  double? horizontalWeight;

  /// Relative share of leftover space in a weighted vertical chain.
  double? verticalWeight;

  /// Paint order override; higher paints on top. Null means child order.
  int? zIndex;

  /// Whether this child is laid out and drawn.
  ConstraintVisibility visibility = ConstraintVisibility.visible;

  /// Guideline: the axis of the line itself (a vertical guideline positions
  /// widgets horizontally).
  Axis guidelineAxis = Axis.vertical;

  /// Guideline: distance from the left/top edge, or null.
  double? guidelineBegin;

  /// Guideline: distance from the right/bottom edge, or null.
  double? guidelineEnd;

  /// Guideline: fraction of the parent size from the left/top edge, or null.
  double? guidelinePercent;

  /// Barrier: which edge of the referenced widgets to track.
  BarrierEdge barrierEdge = BarrierEdge.end;

  /// Barrier: ids of the widgets whose edges the barrier tracks.
  List<Symbol> barrierReferenced = const <Symbol>[];

  /// Barrier: offset in logical pixels added past the tracked edge.
  double barrierMargin = 0;

  /// Barrier: whether gone widgets still contribute their (collapsed)
  /// position to the barrier.
  bool barrierAllowsGone = true;

  /// Flow: ids of the widgets this flow arranges.
  List<Symbol> flowReferenced = const <Symbol>[];

  /// Flow: the main axis widgets are laid out along.
  Axis flowOrientation = Axis.horizontal;

  /// Flow: wrap behaviour when the main axis overflows.
  FlowWrap flowWrap = FlowWrap.none;

  /// Flow: gap between widgets on the horizontal axis.
  double flowHorizontalGap = 0;

  /// Flow: gap between widgets on the vertical axis.
  double flowVerticalGap = 0;

  /// Flow: chain style along the horizontal axis, or null for spread.
  ChainStyle? flowHorizontalStyle;

  /// Flow: chain style along the vertical axis, or null for spread.
  ChainStyle? flowVerticalStyle;

  /// Flow: bias of the horizontal chains.
  double flowHorizontalBias = 0.5;

  /// Flow: bias of the vertical chains.
  double flowVerticalBias = 0.5;

  /// Flow: cross-axis alignment of widgets within a row.
  FlowVerticalAlign flowVerticalAlign = FlowVerticalAlign.center;

  /// Flow: cross-axis alignment of widgets within a column.
  FlowHorizontalAlign flowHorizontalAlign = FlowHorizontalAlign.center;

  /// Flow: maximum number of widgets per chain before wrapping, or null.
  int? flowMaxElementsWrap;

  /// Flow: padding inside the flow's bounds, applied on all sides.
  double flowPadding = 0;

  /// Grid: ids of the widgets this grid arranges, in order.
  List<Symbol> gridReferenced = const <Symbol>[];

  /// Grid: number of rows, or null to derive from [gridColumns] and count.
  int? gridRows;

  /// Grid: number of columns, or null to derive from [gridRows] and count.
  int? gridColumns;

  /// Grid: the axis along which widgets fill the cells.
  Axis gridOrientation = Axis.horizontal;

  /// Grid: gap between columns in logical pixels.
  double gridHorizontalGap = 0;

  /// Grid: gap between rows in logical pixels.
  double gridVerticalGap = 0;

  /// Grid: relative row heights, or null for equal rows.
  List<double>? gridRowWeights;

  /// Grid: relative column widths, or null for equal columns.
  List<double>? gridColumnWeights;

  /// Grid: spans in Android's `index:RxC` format, or null.
  String? gridSpans;

  /// Grid: skipped cells in Android's `index:RxC` format, or null.
  String? gridSkips;

  /// Set by the parent-data widget when a layout-affecting field changed;
  /// cleared by `RenderConstraintLayout` once the change is applied to its
  /// persistent engine model.
  bool configDirty = false;

  /// Set when [id], [helperKind], or any guideline/barrier field changed. An
  /// id rename can re-point links on any sibling, and helper configuration is
  /// applied at model-build time, so these force a full engine-model rebuild
  /// rather than an in-place update of this child alone.
  bool structuralDirty = false;
}
