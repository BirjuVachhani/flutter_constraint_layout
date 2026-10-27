// The tree model of the Android parity corpus (test/parity/README.md): a
// line of the parity corpora (an op list, FORMATS.md 1 and 4 of the parity
// oracle) becomes the description of a real ConstraintLayout widget tree,
// written as JSON for test/parity/android_parity_test.dart. Pure Dart: it
// replays the op list on the engine's widgets, as the oracle replays it, and
// reads each child's final configuration back:
//
// - links become absolute left, right, top, bottom and baseline links
//   (never start/end, so a bias is used as given), and a center link with a
//   circle angle becomes a circular link;
// - behaviours and match styles become a dimension;
// - a vertical guideline of a right-to-left layout gets the value that the
//   adapter's mirror (1 - percent in float; begin and end traded) turns back
//   into the op list's;
// - barriers keep absolute edges, whose margin the adapter applies as given;
// - a `ct` op gives the child's content model.
//
// A line the Flutter API cannot express is unmapped, with a reason. This is
// the Phase 0 harness's `ftree` model (FORMATS.md 11), kept with the corpus
// so it can be regenerated.
import 'package:constraint_engine/constraint_engine.dart';

/// A dimension of a widget or a flow, as the adapter's `Dimension` says it.
sealed class FlDim {
  const FlDim();

  Object toJson();
}

final class FlFixed extends FlDim {
  const FlFixed(this.px);
  final int px;
  @override
  Object toJson() => ['fixed', px];
}

final class FlWrap extends FlDim {
  const FlWrap();
  @override
  Object toJson() => 'wrap';
}

final class FlParent extends FlDim {
  const FlParent();
  @override
  Object toJson() => 'parent';
}

/// A match-constraint dimension: `spread`, `cwrap` (constrained wrap) or
/// `percent`, with its min and max (0 for none).
final class FlMatch extends FlDim {
  const FlMatch(this.style, this.min, this.max, [this.percent = 1]);
  final String style;
  final int min;
  final int max;
  final double percent;
  @override
  Object toJson() =>
      style == 'percent' ? [style, percent, min, max] : [style, min, max];
}

/// A link: the target ('parent' or a sibling's name), the target's edge
/// (left, right, top, bottom, baseline), the margin, and the gone margin (0
/// when unset, the Flutter API's convention).
class FlLink {
  const FlLink(this.target, this.edge, this.margin, this.goneMargin);
  final String target;
  final String edge;
  final int margin;
  final int goneMargin;
  Object toJson() => [target, edge, margin, goneMargin];
}

enum FlKind { widget, guideline, barrier, flow }

class FlChild {
  FlChild(this.name, this.kind);
  final String name;
  final FlKind kind;

  // A widget or a flow.
  FlDim width = const FlWrap();
  FlDim height = const FlWrap();
  FlLink? left, right, top, bottom, baseline;
  (String, double, int)? circle;
  double hBias = 0.5;
  double vBias = 0.5;
  double? ratio;
  int hChain = 0;
  int vChain = 0;
  double? hWeight;
  double? vWeight;
  int visibility = 0;

  /// The `ct` op's fields: kind (box, text, none), W, H and the baseline
  /// (-1 for none). A widget without one is a bare view: none 0 0 -1.
  List<Object> content = const ['none', 0, 0, -1];

  // A guideline: a horizontal line (orientation 0) or a vertical one (1).
  bool horizontalLine = false;
  double? gBegin, gEnd, gPercent;

  // A barrier.
  int barrierType = 0;
  int barrierMargin = 0;
  bool allowsGone = true;
  List<String> refs = const [];

  // A flow (the adapter's ConstraintFlow fields).
  int flowOrientation = 0;
  int flowWrap = 0;
  int? flowHStyle;
  int? flowVStyle;
  double flowHBias = 0.5;
  double flowVBias = 0.5;
  int flowHAlign = 2;
  int flowVAlign = 2;
  int flowHGap = 0;
  int flowVGap = 0;
  int? flowMaxElements;
  int flowPadding = 0;

  Map<String, Object?> toJson() {
    final out = <String, Object?>{'id': name, 'kind': kind.name};
    void links() {
      for (final (key, link) in [
        ('left', left),
        ('right', right),
        ('top', top),
        ('bottom', bottom),
        ('baseline', baseline),
      ]) {
        if (link != null) out[key] = link.toJson();
      }
    }

    switch (kind) {
      case FlKind.guideline:
        out['orientation'] = horizontalLine ? 'horizontal' : 'vertical';
        if (gBegin != null) out['begin'] = gBegin;
        if (gEnd != null) out['end'] = gEnd;
        if (gPercent != null) out['percent'] = gPercent;
      case FlKind.barrier:
        out['edge'] = const ['left', 'right', 'top', 'bottom'][barrierType];
        out['margin'] = barrierMargin;
        if (!allowsGone) out['allowsGone'] = false;
        out['refs'] = refs;
      case FlKind.widget || FlKind.flow:
        out['width'] = width.toJson();
        out['height'] = height.toJson();
        links();
        final c = circle;
        if (c != null) out['circle'] = [c.$1, c.$2, c.$3];
        if (hBias != 0.5) out['hBias'] = hBias;
        if (vBias != 0.5) out['vBias'] = vBias;
        if (ratio != null) out['ratio'] = ratio;
        if (hChain != 0) out['hChain'] = hChain;
        if (vChain != 0) out['vChain'] = vChain;
        if (hWeight != null) out['hWeight'] = hWeight;
        if (vWeight != null) out['vWeight'] = vWeight;
        if (visibility != 0) out['visibility'] = visibility;
        if (kind == FlKind.widget) {
          out['content'] = content;
        } else {
          out['refs'] = refs;
          out['flow'] = <String, Object?>{
            'orientation': flowOrientation,
            'wrap': flowWrap,
            'hStyle': ?flowHStyle,
            'vStyle': ?flowVStyle,
            if (flowHBias != 0.5) 'hBias': flowHBias,
            if (flowVBias != 0.5) 'vBias': flowVBias,
            'hAlign': flowHAlign,
            'vAlign': flowVAlign,
            if (flowHGap != 0) 'hGap': flowHGap,
            if (flowVGap != 0) 'vGap': flowVGap,
            'maxElements': ?flowMaxElements,
            if (flowPadding != 0) 'padding': flowPadding,
          };
        }
    }
    return out;
  }
}

class FlLayout {
  FlLayout(this.id, this.features, this.ops);
  final String id;
  final String features;

  /// The op list as in the corpus line (its last field).
  final String ops;
  bool rtl = false;
  double minW = 0, maxW = double.infinity, minH = 0, maxH = double.infinity;
  final List<FlChild> children = [];
  String? unmapped;

  /// Whether a flow of this layout has a `.fixed(0)` axis: FIXED 0, which
  /// Android's layout params cannot say (`0dp` is a match constraint).
  bool get hasFixedZeroFlow => children.any(
    (c) =>
        c.kind == FlKind.flow &&
        ((c.width is FlFixed && (c.width as FlFixed).px == 0) ||
            (c.height is FlFixed && (c.height as FlFixed).px == 0)),
  );

  Map<String, Object?> toJson() => {
    'rtl': rtl,
    'constraints': [
      minW,
      if (maxW.isFinite) maxW else null,
      minH,
      if (maxH.isFinite) maxH else null,
    ],
    'children': [for (final c in children) c.toJson()],
  };
}

class _Unmapped implements Exception {
  _Unmapped(this.reason);
  final String reason;
}

ConstraintAnchorType _anchor(String s) => switch (s) {
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

DimensionBehaviour _behaviour(String s) => switch (s) {
  'F' => DimensionBehaviour.fixed,
  'W' => DimensionBehaviour.wrapContent,
  'M' => DimensionBehaviour.matchConstraint,
  'P' => DimensionBehaviour.matchParent,
  _ => throw ArgumentError('behaviour $s'),
};

/// The final engine state of an op list, plus what the engine does not keep.
class _Replay {
  late ConstraintWidgetContainer root;
  final byName = <String, ConstraintWidget>{};
  final content = <String, List<Object>>{};
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
        n(t[1]).connect(_anchor(t[2]), n(t[3]), _anchor(t[4]), int.parse(t[5]));
      case 'x':
        n(t[1]).getAnchor(_anchor(t[2]))!.reset();
      case 'hb':
        n(t[1]).setHorizontalDimensionBehaviour(_behaviour(t[2]));
      case 'vb':
        n(t[1]).setVerticalDimensionBehaviour(_behaviour(t[2]));
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
      case 'hx':
        n(t[1]).setHorizontalBiasPercent(double.parse(t[2]));
      case 'vx':
        n(t[1]).setVerticalBiasPercent(double.parse(t[2]));
      case 'gm':
        n(t[1]).setGoneMargin(_anchor(t[2]), int.parse(t[3]));
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
      case 'ct':
        content[t[1]] = [
          t[2],
          int.parse(t[3]),
          int.parse(t[4]),
          int.parse(t[5]),
        ];
        anyContent = true;
      case 'cc':
        n(t[1]).connectCircularConstraint(
          n(t[2]),
          double.parse(t[3]),
          int.parse(t[4]),
        );
      case 'fo' ||
          'fwm' ||
          'fhs' ||
          'fvs' ||
          'fhb' ||
          'fvb' ||
          'fha' ||
          'fva' ||
          'fhg' ||
          'fvg' ||
          'fme' ||
          'fpad':
        final calls = flowCalls[t[1]];
        if (calls == null) throw ArgumentError('not a flow ${t[1]}');
        calls[t[0]] = t.sublist(2);
      case 'frtl':
        flowRtl[t[1]] = t[2] == '1';
      case 'cspec':
        cspec = t.sublist(1);
      case 'cpad' || 'cmin' || 'cmax':
        unmap(t[0]);
      case 'mw' || 'mh':
        unmap('childmin');
      case 'ipr' || 'iprest' || 'L':
        unmap('inplace');
      default:
        // rm, ic, sbl, rs, wb, fset and anything else the Flutter API
        // cannot say.
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

FlLink? _link(_Replay r, ConstraintAnchor a, Set<String> names) {
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
  return FlLink(
    name,
    _edgeName(target.mType),
    a.mMargin,
    gone == ConstraintAnchor.unsetGoneMargin ? 0 : gone,
  );
}

FlDim _dim(ConstraintWidget w, bool horizontal) {
  final b = horizontal
      ? w.getHorizontalDimensionBehaviour()
      : w.getVerticalDimensionBehaviour();
  final min = horizontal
      ? w.mMatchConstraintMinWidth
      : w.mMatchConstraintMinHeight;
  final max = horizontal
      ? w.mMatchConstraintMaxWidth
      : w.mMatchConstraintMaxHeight;
  final percent = horizontal
      ? w.mMatchConstraintPercentWidth
      : w.mMatchConstraintPercentHeight;
  final style = horizontal
      ? w.mMatchConstraintDefaultWidth
      : w.mMatchConstraintDefaultHeight;
  if (b != DimensionBehaviour.matchConstraint &&
      (style != ConstraintWidget.MATCH_CONSTRAINT_SPREAD || percent != 1)) {
    // The adapter gives a dimension that is not a match constraint the
    // default match style.
    throw _Unmapped('mcstyle-nonmc');
  }
  switch (b) {
    case DimensionBehaviour.fixed:
      // A Flutter min and max live on a match-constraint dimension only.
      if (min != 0 || max != 0) throw _Unmapped('minmax-nonmc');
      final px = horizontal ? w.mWidth : w.mHeight;
      if (px < 0) throw _Unmapped('fixedneg');
      return FlFixed(px);
    case DimensionBehaviour.wrapContent:
      if (min != 0 || max != 0) throw _Unmapped('minmax-nonmc');
      return const FlWrap();
    case DimensionBehaviour.matchParent:
      if (min != 0 || max != 0) throw _Unmapped('minmax-nonmc');
      return const FlParent();
    case DimensionBehaviour.matchConstraint:
      if (min < 0 || max < 0) throw _Unmapped('minmax-wrap');
      return switch (style) {
        ConstraintWidget.MATCH_CONSTRAINT_SPREAD => FlMatch('spread', min, max),
        ConstraintWidget.MATCH_CONSTRAINT_WRAP => FlMatch('cwrap', min, max),
        ConstraintWidget.MATCH_CONSTRAINT_PERCENT => FlMatch(
          'percent',
          min,
          max,
          percent,
        ),
        _ => throw _Unmapped('mcstyle$style'),
      };
  }
}

/// Maps one corpus line (`id \t features \t ... \t ops`) to an [FlLayout];
/// [FlLayout.unmapped] says why when the Flutter API cannot express it.
FlLayout mapCorpusLine(String line) {
  final fields = line.split('\t');
  final layout = FlLayout(
    fields.first,
    fields.length > 1 ? fields[1] : '-',
    fields.last,
  );
  try {
    _map(layout);
  } on _Unmapped catch (e) {
    layout.unmapped = e.reason;
  } on Object catch (e) {
    layout.unmapped = 'error:${e.toString().split('\n').first}';
  }
  return layout;
}

void _map(FlLayout layout) {
  final r = _Replay();
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
  // The container: tight on a FIXED axis, 0..infinity on a WRAP axis (the
  // U(0) spec).
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
      final c = FlChild(name, FlKind.guideline)
        ..horizontalLine = w.getOrientation() == Guideline.horizontal;
      for (final a in w.mAnchors) {
        if (a.mTarget != null) throw _Unmapped('helperlink');
      }
      final mirror = layout.rtl && !c.horizontalLine;
      final percent = w.getRelativePercent();
      final begin = w.getRelativeBegin();
      final end = w.getRelativeEnd();
      if (percent != -1) {
        if (mirror) {
          // The adapter sets 1 - percent in float; the value given must
          // come back as the op list's.
          final given = 1 - percent;
          if (fsub(1, f32(given)) != percent) throw _Unmapped('rtlpct');
          c.gPercent = given;
        } else {
          c.gPercent = percent;
        }
      } else if (begin != -1) {
        // The adapter mirrors begin to end in right-to-left text.
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
      final c = FlChild(name, FlKind.barrier)
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
    final c = FlChild(name, isFlow ? FlKind.flow : FlKind.widget);
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
      c.circle = (target, w.mCircleConstraintAngle, w.mCenter.mMargin);
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
      c.content = r.content[name] ?? const ['none', 0, 0, -1];
    }
    layout.children.add(c);
  }
}

void _mapFlow(
  FlChild c,
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
  // The core Flow turns an unset style into CHAIN_SPREAD when it measures,
  // and the adapter sets CHAIN_SPREAD for null: the same.
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
