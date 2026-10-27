// baseline: turns a raw op list (converge's Rec order) into the op list the
// Flutter adapter would emit for the same final state. The ops are replayed
// on real engine widgets, the final state of every child is read back as a
// Spec (fspec.dart), and the specs are emitted by emitSpecs in the adapter's
// call order, followed by _prepareContainer (prepareOps): a wrap axis starts
// at 0, as the adapter gives it under an unbounded constraint.
//
// What the adapter cannot express is dropped or refused:
// - a ratio's side (the adapter passes a bare ratio, side UNKNOWN);
// - center anchors (C, CX, CY) and setMinWidth/setMinHeight: refused.
import 'package:constraint_engine/constraint_engine.dart';

import 'fspec.dart';
import 'ops.dart';

class RespecError implements Exception {
  RespecError(this.message);
  final String message;
  @override
  String toString() => 'RespecError: $message';
}

String _edgeOf(ConstraintAnchorType t) => switch (t) {
  ConstraintAnchorType.left => 'left',
  ConstraintAnchorType.right => 'right',
  ConstraintAnchorType.top => 'top',
  ConstraintAnchorType.bottom => 'bottom',
  ConstraintAnchorType.baseline => 'baseline',
  _ => throw RespecError('anchor $t'),
};

Dim _dim(ConstraintWidget w, bool h) {
  final b = h
      ? w.getHorizontalDimensionBehaviour()
      : w.getVerticalDimensionBehaviour();
  switch (b) {
    case DimensionBehaviour.fixed:
      return Dim.fixed(h ? w.mWidth : w.mHeight);
    case DimensionBehaviour.wrapContent:
      return const Dim.wrap();
    case DimensionBehaviour.matchParent:
      return const Dim.parent();
    case DimensionBehaviour.matchConstraint:
      final style = h
          ? w.mMatchConstraintDefaultWidth
          : w.mMatchConstraintDefaultHeight;
      final mn = h ? w.mMatchConstraintMinWidth : w.mMatchConstraintMinHeight;
      final mx = h ? w.mMatchConstraintMaxWidth : w.mMatchConstraintMaxHeight;
      final pct = h
          ? w.mMatchConstraintPercentWidth
          : w.mMatchConstraintPercentHeight;
      if (style == ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
        return Dim.match(min: mn, max: mx, pct: pct);
      }
      if (style == ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
        return Dim.cwrap(min: mn, max: mx);
      }
      return Dim.match(min: mn, max: mx);
  }
}

Link? _link(ConstraintAnchor a) {
  final t = a.mTarget;
  if (t == null) return null;
  final owner = t.mOwner;
  final target = owner is ConstraintWidgetContainer && owner.getParent() == null
      ? 'parent'
      : owner.getDebugName()!;
  final gone = a.mGoneMargin == ConstraintAnchor.unsetGoneMargin
      ? 0
      : a.mGoneMargin;
  return Link(target, _edgeOf(t.mType), a.mMargin, gone);
}

/// The adapter-order op list of the layout [ops] builds.
List<String> respec(List<String> ops) {
  for (final o in ops) {
    final t = o.split(' ');
    if (t[0] == 'mw' || t[0] == 'mh') throw RespecError('min size');
    if (t[0] == 'c' && (t[2].startsWith('C') || t[4].startsWith('C'))) {
      throw RespecError('center anchor');
    }
  }
  final (w0, h0) = rootSize(ops);
  final root = ConstraintWidgetContainer.rect(0, 0, w0, h0)
    ..setDebugName('root');
  applyOps(root, ops);
  final specs = <Spec>[];
  for (final c in root.getChildren()) {
    final id = c.getDebugName()!;
    if (c is Barrier) {
      final edge = switch (c.getBarrierType()) {
        Barrier.left => 'left',
        Barrier.right => 'right',
        Barrier.top => 'top',
        _ => 'bottom',
      };
      specs.add(
        Spec.barrier(
          id,
          edge,
          [
            for (var i = 0; i < c.mWidgetsCount; i++)
              c.mWidgets[i]!.getDebugName()!,
          ],
          margin: c.getMargin(),
          allowsGone: c.getAllowsGoneWidget(),
        ),
      );
      continue;
    }
    if (c is Guideline) {
      final horizontalLine = c.getOrientation() == Guideline.horizontal;
      specs.add(
        Spec.guideline(
          id,
          horizontalLine,
          gPct: c.getRelativePercent() != -1 ? c.getRelativePercent() : null,
          gBegin: c.getRelativePercent() == -1 && c.getRelativeBegin() != -1
              ? c.getRelativeBegin()
              : null,
          gEnd:
              c.getRelativePercent() == -1 &&
                  c.getRelativeBegin() == -1 &&
                  c.getRelativeEnd() != -1
              ? c.getRelativeEnd()
              : null,
        ),
      );
      continue;
    }
    final s = Spec.widget(
      id,
      c.mWidth,
      c.mHeight,
      baselineDist: c.getBaselineDistance(),
    );
    s.width = _dim(c, true);
    s.height = _dim(c, false);
    s.left = _link(c.mLeft);
    s.right = _link(c.mRight);
    s.top = _link(c.mTop);
    s.bottom = _link(c.mBottom);
    s.baseline = _link(c.mBaseline);
    s.hBias = c.getHorizontalBiasPercent();
    s.vBias = c.getVerticalBiasPercent();
    final r = c.getDimensionRatio();
    s.ratio = r > 0 ? r : null;
    s.hChain = c.getHorizontalChainStyle();
    s.vChain = c.getVerticalChainStyle();
    s.hWeight = c.mWeight[0] == -1 ? null : c.mWeight[0];
    s.vWeight = c.mWeight[1] == -1 ? null : c.mWeight[1];
    s.vis = c.getVisibility();
    specs.add(s);
  }
  final ltr = !root.isRtl();
  final wrapW =
      root.getHorizontalDimensionBehaviour() == DimensionBehaviour.wrapContent;
  final wrapH =
      root.getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent;
  return [
    ...emitSpecs(w0, h0, specs, ltr: ltr, wrapW: wrapW, wrapH: wrapH),
    ...prepareOps(w0, h0, ltr: ltr, wrapW: wrapW, wrapH: wrapH),
  ];
}
