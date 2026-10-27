// ftree's model (FORMATS.md section 11): a corpus line (section 1) becomes a
// description of a real ConstraintLayout widget tree, in pure Dart, so the
// ftree CLI can check mappability without Flutter and the FL runner can
// build the widgets from it.
//
// The op list is replayed on engine widgets (the repo's constraint_engine),
// the way the oracles replay it, and each child's final state is read back:
//
// - links become absolute left/right/top/bottom/baseline links (never
//   start/end, so the adapter uses the bias as given), a center link with a
//   circle angle becomes a CircularLink;
// - behaviours and match styles become a Dimension;
// - a vertical guideline of an RTL layout gets the un-mirrored value, since
//   the adapter mirrors it again;
// - barriers keep absolute edges (the adapter negates only start/end
//   margins);
// - `ct` gives the ContentModelBox content.
//
// Anything the Flutter API cannot say yields [FLayout.unmapped].
import 'package:constraint_engine/constraint_engine.dart';

import 'content.dart';

enum FDimKind { fixed, wrap, parent, spread, cwrap, percent }

class FDim {
  const FDim(this.kind, {this.px = 0, this.min = 0, this.max = 0, this.pct = 1});
  final FDimKind kind;
  final int px;
  final int min;
  final int max;
  final double pct;
}

class FLink {
  const FLink(this.target, this.edge, this.margin, this.goneMargin);

  /// 'parent' or a sibling name.
  final String target;

  /// left, right, top, bottom, baseline (the target's edge).
  final String edge;
  final int margin;

  /// 0 when unset (the Flutter API's convention).
  final int goneMargin;
}

class FCircle {
  const FCircle(this.target, this.angle, this.radius);
  final String target;
  final double angle;
  final int radius;
}

enum FKind { widget, guideline, barrier, flow }

class FChild {
  FChild(this.name, this.kind);
  final String name;
  final FKind kind;

  // widget and flow
  FDim width = const FDim(FDimKind.wrap);
  FDim height = const FDim(FDimKind.wrap);
  FLink? left, right, top, bottom, baseline;
  FCircle? circle;
  double hBias = 0.5;
  double vBias = 0.5;
  double? ratio;
  int hChain = 0;
  int vChain = 0;
  double? hWeight;
  double? vWeight;
  int visibility = 0; // 0 visible, 4 invisible, 8 gone
  ContentModel content = ContentModel.bare;

  // guideline: a horizontal line (orientation 0) or a vertical one (1)
  bool horizontalLine = false;
  double? gBegin, gEnd, gPercent;

  // barrier
  int barrierType = 0; // 0 left, 1 right, 2 top, 3 bottom
  int barrierMargin = 0;
  bool allowsGone = true;
  List<String> refs = const [];

  // flow (the adapter's ConstraintFlow fields)
  int flowOrientation = 0;
  int flowWrap = 0; // 0 none, 1 chain, 2 aligned
  int? flowHStyle;
  int? flowVStyle;
  double flowHBias = 0.5;
  double flowVBias = 0.5;
  int flowHAlign = 2; // core HORIZONTAL_ALIGN_CENTER
  int flowVAlign = 2; // core VERTICAL_ALIGN_CENTER
  int flowHGap = 0;
  int flowVGap = 0;
  int? flowMaxElements;
  int flowPadding = 0;
}

class FLayout {
  FLayout(this.id, this.features, this.ops);
  final String id;
  final String features;

  /// The op list as in the corpus line (the last field).
  final String ops;
  bool rtl = false;
  double minW = 0, maxW = double.infinity, minH = 0, maxH = double.infinity;
  final List<FChild> children = [];
  String? unmapped;
}

class _Unmapped implements Exception {
  _Unmapped(this.reason);
  final String reason;
}

ConstraintAnchorType _anc(String s) => switch (s) {
  'L' => ConstraintAnchorType.left,
  'R' => ConstraintAnchorType.right,
  'T' => ConstraintAnchorType.top,
  'B' => ConstraintAnchorType.bottom,
  'S' => ConstraintAnchorType.baseline,
  'C' => ConstraintAnchorType.center,
  'CX' => ConstraintAnchorType.centerX,
  'CY' => ConstraintAnchorType.centerY,
  _ => throw ArgumentError('anchor $s'),
};

DimensionBehaviour _beh(String s) => switch (s) {
  'F' => DimensionBehaviour.fixed,
  'W' => DimensionBehaviour.wrapContent,
  'M' => DimensionBehaviour.matchConstraint,
  'P' => DimensionBehaviour.matchParent,
  _ => throw ArgumentError('behaviour $s'),
};

/// The final engine state of an op list, plus what the engine does not keep.
class _Replay {
  _Replay({this.inplace = false});

  /// In-place mode (T-inplace states): `ipr` resets the widget's anchors as
  /// the adapter's in-place re-apply does, and `L`/`iprest` are no-ops (the
  /// caller cuts the op list at each `L`).
  final bool inplace;
  late ConstraintWidgetContainer root;
  final byName = <String, ConstraintWidget>{};
  final content = <String, ContentModel>{};
  final flowCalls = <String, Map<String, List<String>>>{};
  final flowRtl = <String, bool>{};
  List<String>? cspec;
  bool anyContent = false;
  String? unmapped;

  void unmap(String reason) => unmapped ??= reason;

  ConstraintWidget n(String name) =>
      byName[name] ?? (throw ArgumentError('unknown widget $name'));

  void apply(List<String> t) {
    switch (t[0]) {
      case 'R':
        root = ConstraintWidgetContainer.rect(
          0,
          0,
          int.parse(t[1]),
          int.parse(t[2]),
        )..setDebugName('root');
        byName['root'] = root;
      case 'rtl':
        root.setRtl(true);
      case 'ltr':
        root.setRtl(false);
      case 'wrapw':
        root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      case 'wraph':
        root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      case 'fixw':
        root.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      case 'fixh':
        root.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      case 'cw':
        root.setWidth(int.parse(t[1]));
      case 'ch':
        root.setHeight(int.parse(t[1]));
      case 'w':
        byName[t[1]] = ConstraintWidget.sizeNamed(
          t[1],
          int.parse(t[2]),
          int.parse(t[3]),
        );
      case 'b':
        byName[t[1]] = Barrier.named(t[1]);
      case 'g':
        byName[t[1]] = Guideline()..setDebugName(t[1]);
      case 'fl':
        byName[t[1]] = Flow()..setDebugName(t[1]);
        flowCalls[t[1]] = <String, List<String>>{};
      case 'add':
        root.add(n(t[1]));
      case 'rm':
        unmap('op:rm');
      case 'bt':
        (n(t[1]) as Barrier).setBarrierType(int.parse(t[2]));
      case 'bm':
        (n(t[1]) as Barrier).setMargin(int.parse(t[2]));
      case 'bg':
        (n(t[1]) as Barrier).setAllowsGoneWidget(t[2] == '1');
      case 'ref':
        (n(t[1]) as HelperWidget).add(n(t[2]));
      case 'go':
        (n(t[1]) as Guideline).setOrientation(int.parse(t[2]));
      case 'gb':
        (n(t[1]) as Guideline).setGuideBegin(int.parse(t[2]));
      case 'ge':
        (n(t[1]) as Guideline).setGuideEnd(int.parse(t[2]));
      case 'gp':
        (n(t[1]) as Guideline).setGuidePercent(double.parse(t[2]));
      case 'c':
        n(t[1]).connect(_anc(t[2]), n(t[3]), _anc(t[4]), int.parse(t[5]));
      case 'ic' || 'sbl':
        // The view layer's own link calls: no Flutter API makes them.
        unmap('op:${t[0]}');
      case 'x':
        n(t[1]).getAnchor(_anc(t[2]))!.reset();
      case 'hb':
        n(t[1]).setHorizontalDimensionBehaviour(_beh(t[2]));
      case 'vb':
        n(t[1]).setVerticalDimensionBehaviour(_beh(t[2]));
      case 'hm':
        n(t[1]).setHorizontalMatchStyle(
          int.parse(t[2]),
          int.parse(t[3]),
          int.parse(t[4]),
          double.parse(t[5]),
        );
      case 'vm':
        n(t[1]).setVerticalMatchStyle(
          int.parse(t[2]),
          int.parse(t[3]),
          int.parse(t[4]),
          double.parse(t[5]),
        );
      case 'mw' || 'mh':
        unmap('childmin');
      case 'hx':
        n(t[1]).setHorizontalBiasPercent(double.parse(t[2]));
      case 'vx':
        n(t[1]).setVerticalBiasPercent(double.parse(t[2]));
      case 'gm':
        n(t[1]).setGoneMargin(_anc(t[2]), int.parse(t[3]));
      case 'v':
        n(t[1]).setVisibility(int.parse(t[2]));
      case 'hbl':
        // A baseline connect only validates between widgets that have a
        // baseline, so the flag must be replayed for the links to exist.
        n(t[1]).setHasBaseline(t[2] == '1');
      case 'bl':
        n(t[1]).setBaselineDistance(int.parse(t[2]));
      case 'sx' || 'sy' || 'rereg' || 'adeps':
        // Positions and dependents: the adapter derives its own.
        break;
      case 'sw':
        n(t[1]).setWidth(int.parse(t[2]));
      case 'sh':
        n(t[1]).setHeight(int.parse(t[2]));
      case 'hc':
        n(t[1]).setHorizontalChainStyle(int.parse(t[2]));
      case 'vc':
        n(t[1]).setVerticalChainStyle(int.parse(t[2]));
      case 'hw':
        n(t[1]).setHorizontalWeight(double.parse(t[2]));
      case 'vw':
        n(t[1]).setVerticalWeight(double.parse(t[2]));
      case 'ra':
        n(t[1]).setDimensionRatio(double.parse(t[2]), int.parse(t[3]));
      case 'rs' || 'wb':
        unmap('op:${t[0]}');
      case 'ipr':
        if (inplace) {
          n(t[1]).resetAnchors();
        } else {
          unmap('inplace');
        }
      case 'iprest' || 'L':
        if (!inplace) unmap('inplace');
      case 'ct':
        content[t[1]] = ContentModel.parseOp(t);
        anyContent = true;
      case 'cc':
        n(t[1]).connectCircularConstraint(
          n(t[2]),
          double.parse(t[3]),
          int.parse(t[4]),
        );
      case 'fo' || 'fwm' || 'fhs' || 'fvs' || 'fhb' || 'fvb' || 'fha' ||
          'fva' || 'fhg' || 'fvg' || 'fme' || 'fpad':
        final calls = flowCalls[t[1]];
        if (calls == null) throw ArgumentError('not a flow ${t[1]}');
        calls[t[0]] = t.sublist(2);
      case 'frtl':
        flowRtl[t[1]] = t[2] == '1';
      case 'fset':
        unmap('flowset:${t[2]}');
      case 'cspec':
        cspec = t.sublist(1);
      case 'cpad' || 'cmin' || 'cmax':
        unmap(t[0]);
      default:
        unmap('op:${t[0]}');
    }
  }
}

String _edgeName(ConstraintAnchorType t) => switch (t) {
  ConstraintAnchorType.left => 'left',
  ConstraintAnchorType.right => 'right',
  ConstraintAnchorType.top => 'top',
  ConstraintAnchorType.bottom => 'bottom',
  ConstraintAnchorType.baseline => 'baseline',
  _ => throw _Unmapped('link'),
};

FLink? _link(_Replay r, ConstraintAnchor a, Set<String> names) {
  final target = a.mTarget;
  if (target == null) return null;
  final owner = target.mOwner;
  final String name;
  if (identical(owner, r.root)) {
    name = 'parent';
  } else {
    name = owner.getDebugName()!;
    if (!names.contains(name)) throw _Unmapped('dangling');
  }
  final gone = a.mGoneMargin;
  if (gone == 0) throw _Unmapped('gone0');
  return FLink(
    name,
    _edgeName(target.mType),
    a.mMargin,
    gone == ConstraintAnchor.unsetGoneMargin ? 0 : gone,
  );
}

FDim _dim(ConstraintWidget w, bool h) {
  final b = h
      ? w.getHorizontalDimensionBehaviour()
      : w.getVerticalDimensionBehaviour();
  final mn = h ? w.mMatchConstraintMinWidth : w.mMatchConstraintMinHeight;
  final mx = h ? w.mMatchConstraintMaxWidth : w.mMatchConstraintMaxHeight;
  final pct = h
      ? w.mMatchConstraintPercentWidth
      : w.mMatchConstraintPercentHeight;
  final style = h
      ? w.mMatchConstraintDefaultWidth
      : w.mMatchConstraintDefaultHeight;
  if (b != DimensionBehaviour.matchConstraint &&
      (style != ConstraintWidget.MATCH_CONSTRAINT_SPREAD || pct != 1)) {
    // The adapter leaves a fresh widget's match style on other behaviours.
    throw _Unmapped('mcstyle-nonmc');
  }
  switch (b) {
    case DimensionBehaviour.fixed:
      // A Flutter min/max lives on a match-constraint Dimension only.
      if (mn != 0 || mx != 0) throw _Unmapped('minmax-nonmc');
      final px = h ? w.mWidth : w.mHeight;
      if (px < 0) throw _Unmapped('fixedneg');
      return FDim(FDimKind.fixed, px: px);
    case DimensionBehaviour.wrapContent:
      if (mn != 0 || mx != 0) throw _Unmapped('minmax-nonmc');
      return const FDim(FDimKind.wrap);
    case DimensionBehaviour.matchParent:
      if (mn != 0 || mx != 0) throw _Unmapped('minmax-nonmc');
      return const FDim(FDimKind.parent);
    case DimensionBehaviour.matchConstraint:
      if (mn < 0 || mx < 0) throw _Unmapped('minmax-wrap');
      return switch (style) {
        ConstraintWidget.MATCH_CONSTRAINT_SPREAD => FDim(
          FDimKind.spread,
          min: mn,
          max: mx,
        ),
        ConstraintWidget.MATCH_CONSTRAINT_WRAP => FDim(
          FDimKind.cwrap,
          min: mn,
          max: mx,
        ),
        ConstraintWidget.MATCH_CONSTRAINT_PERCENT => FDim(
          FDimKind.percent,
          min: mn,
          max: mx,
          pct: pct,
        ),
        _ => throw _Unmapped('mcstyle$style'),
      };
  }
}

/// Maps one corpus line (FORMATS.md section 1) to an FLayout.
FLayout mapCorpusLine(String line) {
  final fields = line.split('\t');
  final layout = FLayout(fields.first, fields.length > 1 ? fields[1] : '-', fields.last);
  try {
    _map(layout);
  } on _Unmapped catch (e) {
    layout.unmapped = e.reason;
  } catch (e) {
    layout.unmapped = 'error:${e.toString().split('\n').first}';
  }
  return layout;
}

/// The states of an in-place sequence (a T-inplace line): the op list cut
/// before each `L`, then the whole list. Every state carries the line's id;
/// any unmapped state makes the sequence unmapped (reported on the last).
List<FLayout> mapInplaceStates(String line) {
  final fields = line.split('\t');
  final ops = fields.last.split(';');
  final cuts = <int>[
    for (var i = 0; i < ops.length; i++)
      if (ops[i].trim() == 'L') i,
    ops.length,
  ];
  final states = <FLayout>[];
  for (final cut in cuts) {
    final layout = FLayout(
      fields.first,
      fields.length > 1 ? fields[1] : '-',
      ops.sublist(0, cut).join(';'),
    );
    try {
      _map(layout, inplace: true);
    } on _Unmapped catch (e) {
      layout.unmapped = e.reason;
    } catch (e) {
      layout.unmapped = 'error:${e.toString().split('\n').first}';
    }
    states.add(layout);
  }
  return states;
}

void _map(FLayout layout, {bool inplace = false}) {
  final r = _Replay(inplace: inplace);
  for (final op in layout.ops.split(';')) {
    final s = op.trim();
    if (s.isEmpty) continue;
    r.apply(s.split(' '));
  }
  if (r.unmapped != null) throw _Unmapped(r.unmapped!);
  if (!r.anyContent) throw _Unmapped('nocontent');
  final root = r.root;
  layout.rtl = root.isRtl();
  for (final e in r.flowRtl.entries) {
    if (e.value != layout.rtl) throw _Unmapped('flowrtl');
  }
  final wrapW =
      root.getHorizontalDimensionBehaviour() == DimensionBehaviour.wrapContent;
  final wrapH =
      root.getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent;
  final cspec = r.cspec;
  if (cspec != null) {
    final want = [
      wrapW ? 'U' : 'E',
      wrapW ? '0' : '${root.mWidth}',
      wrapH ? 'U' : 'E',
      wrapH ? '0' : '${root.mHeight}',
    ];
    if (cspec.join(' ') != want.join(' ')) throw _Unmapped('cspec');
  }
  if (wrapW) {
    layout.minW = 0;
    layout.maxW = double.infinity;
  } else {
    layout.minW = layout.maxW = root.mWidth.toDouble();
  }
  if (wrapH) {
    layout.minH = 0;
    layout.maxH = double.infinity;
  } else {
    layout.minH = layout.maxH = root.mHeight.toDouble();
  }
  final kids = root.getChildren();
  final names = <String>{};
  for (final w in kids) {
    final name = w.getDebugName()!;
    if (name == 'parent' || !names.add(name)) throw _Unmapped('name');
  }
  for (final w in kids) {
    final name = w.getDebugName()!;
    if (w is Guideline) {
      final c = FChild(name, FKind.guideline)
        ..horizontalLine = w.getOrientation() == Guideline.horizontal;
      for (final a in w.mAnchors) {
        if (a.mTarget != null) throw _Unmapped('helperlink');
      }
      final mirror = layout.rtl && !c.horizontalLine;
      final pct = w.getRelativePercent();
      final begin = w.getRelativeBegin();
      final end = w.getRelativeEnd();
      if (pct != -1) {
        if (mirror) {
          // The adapter sets 1 - percent; it must give back the op's value.
          final given = 1 - pct;
          if (1 - given != pct) throw _Unmapped('rtlpct');
          c.gPercent = given;
        } else {
          c.gPercent = pct;
        }
      } else if (begin != -1) {
        // The adapter mirrors end to begin in RTL.
        if (mirror) {
          c.gEnd = begin.toDouble();
        } else {
          c.gBegin = begin.toDouble();
        }
      } else if (end != -1) {
        if (mirror) {
          c.gBegin = end.toDouble();
        } else {
          c.gEnd = end.toDouble();
        }
      } else {
        throw _Unmapped('guideline');
      }
      if (w.getVisibility() != ConstraintWidget.VISIBLE) {
        throw _Unmapped('guidelinevis');
      }
      layout.children.add(c);
      continue;
    }
    if (w is Barrier) {
      for (final a in w.mAnchors) {
        if (a.mTarget != null) throw _Unmapped('helperlink');
      }
      if (w.getVisibility() != ConstraintWidget.VISIBLE) {
        throw _Unmapped('barriervis');
      }
      final c = FChild(name, FKind.barrier)
        ..barrierType = w.getBarrierType()
        ..barrierMargin = w.getMargin()
        ..allowsGone = w.getAllowsGoneWidget()
        ..refs = [
          for (var i = 0; i < w.mWidgetsCount; i++)
            w.mWidgets[i]!.getDebugName()!,
        ];
      for (final ref in c.refs) {
        if (!names.contains(ref)) throw _Unmapped('ref');
      }
      layout.children.add(c);
      continue;
    }
    final isFlow = w is Flow;
    if (!isFlow && w.runtimeType != ConstraintWidget) {
      throw _Unmapped('widget:${w.runtimeType}');
    }
    final c = FChild(name, isFlow ? FKind.flow : FKind.widget);
    c.width = _dim(w, true);
    c.height = _dim(w, false);
    if (w.mCenter.mTarget != null) {
      final t = w.mCenter.mTarget!;
      if (t.mType != ConstraintAnchorType.center ||
          w.mCircleConstraintAngle.isNaN) {
        throw _Unmapped('center');
      }
      final owner = t.mOwner;
      final target = identical(owner, root) ? 'parent' : owner.getDebugName()!;
      c.circle = FCircle(target, w.mCircleConstraintAngle, w.mCenter.mMargin);
    }
    if (w.getAnchor(ConstraintAnchorType.centerX)!.mTarget != null ||
        w.getAnchor(ConstraintAnchorType.centerY)!.mTarget != null) {
      throw _Unmapped('center');
    }
    c.left = _link(r, w.mLeft, names);
    c.right = _link(r, w.mRight, names);
    c.top = _link(r, w.mTop, names);
    c.bottom = _link(r, w.mBottom, names);
    c.baseline = _link(r, w.mBaseline, names);
    for (final (l, from) in [
      (c.left, 'left'),
      (c.right, 'right'),
      (c.top, 'top'),
      (c.bottom, 'bottom'),
      (c.baseline, 'baseline'),
    ]) {
      if (l == null) continue;
      final ok = switch (from) {
        'left' || 'right' => l.edge == 'left' || l.edge == 'right',
        'top' || 'bottom' => l.edge == 'top' || l.edge == 'bottom',
        _ => l.edge == 'top' || l.edge == 'bottom' || l.edge == 'baseline',
      };
      if (!ok) throw _Unmapped('link');
    }
    c.hBias = w.getHorizontalBiasPercent();
    c.vBias = w.getVerticalBiasPercent();
    final ratio = w.getDimensionRatio();
    if (ratio > 0) {
      if (w.getDimensionRatioSide() != ConstraintWidget.UNKNOWN) {
        throw _Unmapped('ratioside');
      }
      // The adapter passes ratio.toString(), which parses back exactly.
      c.ratio = ratio;
    } else if (ratio < 0) {
      throw _Unmapped('negratio');
    }
    c.hChain = w.getHorizontalChainStyle();
    c.vChain = w.getVerticalChainStyle();
    if (c.hChain < 0 || c.hChain > 2 || c.vChain < 0 || c.vChain > 2) {
      throw _Unmapped('chainstyle');
    }
    final hw = w.mWeight[0], vw = w.mWeight[1];
    c.hWeight = hw == ConstraintWidget.UNKNOWN ? null : hw;
    c.vWeight = vw == ConstraintWidget.UNKNOWN ? null : vw;
    c.visibility = w.getVisibility();
    if (isFlow) {
      // ConstraintFlow has no baseline link, circle, ratio, weight or chain
      // style of its own (its chain styles are the flow's internal ones).
      if (c.baseline != null ||
          c.circle != null ||
          c.ratio != null ||
          c.hWeight != null ||
          c.vWeight != null ||
          c.hChain != 0 ||
          c.vChain != 0) {
        throw _Unmapped('flowwidget');
      }
      _mapFlow(c, w, r.flowCalls[name]!, names);
    } else {
      c.content = r.content[name] ?? ContentModel.bare;
    }
    layout.children.add(c);
  }
}

void _mapFlow(
  FChild c,
  Flow w,
  Map<String, List<String>> calls,
  Set<String> names,
) {
  c.refs = [
    for (var i = 0; i < w.mWidgetsCount; i++) w.mWidgets[i]!.getDebugName()!,
  ];
  for (final ref in c.refs) {
    if (!names.contains(ref)) throw _Unmapped('ref');
  }
  int i(String op, int fallback) {
    final v = calls[op];
    return v == null ? fallback : int.parse(v[0]);
  }

  double d(String op, double fallback) {
    final v = calls[op];
    return v == null ? fallback : double.parse(v[0]);
  }

  c.flowOrientation = i('fo', 0);
  c.flowWrap = i('fwm', 0);
  if (c.flowWrap > 2) throw _Unmapped('flowwrap');
  // Core Flow turns an unset style into CHAIN_SPREAD when it measures, and
  // the adapter sets CHAIN_SPREAD for null: the same.
  final hs = i('fhs', -1), vs = i('fvs', -1);
  if (hs > 2 || vs > 2) throw _Unmapped('flowstyle');
  c.flowHStyle = hs < 0 ? null : hs;
  c.flowVStyle = vs < 0 ? null : vs;
  c.flowHBias = d('fhb', 0.5);
  c.flowVBias = d('fvb', 0.5);
  c.flowHAlign = i('fha', 2);
  c.flowVAlign = i('fva', 2);
  if (c.flowHAlign > 2 || c.flowVAlign > 3) throw _Unmapped('flowalign');
  c.flowHGap = i('fhg', 0);
  c.flowVGap = i('fvg', 0);
  final me = calls['fme'];
  c.flowMaxElements = me == null || int.parse(me[0]) == -1
      ? null
      : int.parse(me[0]);
  final pad = calls['fpad'];
  if (pad != null) {
    final p = pad.map(int.parse).toList();
    if (p.any((v) => v != p[0])) throw _Unmapped('flowpad');
    c.flowPadding = p[0];
  }
}
