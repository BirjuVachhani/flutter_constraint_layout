// The T-family layout model and its emitter (FORMATS.md 4.4).
//
// A T layout is a child list, as a screen declares it, emitted as engine ops
// in the order Android's setChildrenConstraints and the Flutter adapter make
// their calls (fspec.dart's emitSpecs, extended):
//
// - every child is created and added in child order; a regular widget is
//   created at 0 on each non-fixed axis and gets a `ct` op (its content);
// - both ends of every baseline link are flagged hasBaseline;
// - each child is configured in child order: guidelines (orientation, then
//   percent, begin or end, mirrored for a vertical line in RTL), barriers
//   (type, gone rule, margin, references), flows (their config, members and
//   applyRtl, then their own widget config) and widgets (behaviours, match
//   styles, bias, ratio, chain styles, weights, visibility, then either a
//   circle link or the start/end (else left/right), top, bottom and baseline
//   links, each followed by its gone margin);
// - then the container (prepareOps), the layout view's own ops (cspec, cpad,
//   cmin, cmax) and `adeps`, Android's dependents state.
//
// Android's semantics where the adapter of dc0dc6a differs: an RTL bias flip
// and an RTL guideline percent are binary32 (fsub(1f, x)), a ratio is the
// binary32 quotient of its two parts, and a start/end barrier keeps the sign
// of its margin in RTL, where that adapter negated it.
import 'dart:typed_data';

import 'content.dart';

final Float32List _f32 = Float32List(1);

/// [x] rounded to binary32.
double f32(double x) {
  _f32[0] = x;
  return _f32[0];
}

/// A float op argument: Dart's shortest double string, which Java's
/// Float.parseFloat reads back to the same binary32 value when [x] is one.
String fs(double x) => x.toString();

class Lk {
  const Lk(this.target, this.edge, [this.margin = 0, this.gone = 0]);

  /// 'parent' or a child id.
  final String target;

  /// start, end, left, right, top, bottom, baseline.
  final String edge;
  final int margin;
  final int gone;
}

/// A dimension: fixed (F), wrap (W), match constraint (M: spread, constrained
/// wrap or percent) or match parent (P), with the match min and max (which
/// Android's view layer sets on every behaviour).
class D {
  const D.fixed(this.px, {this.min = 0, this.max = 0})
    : b = 'F',
      pct = null,
      cwrap = false;
  const D.wrap({this.min = 0, this.max = 0})
    : b = 'W',
      px = 0,
      pct = null,
      cwrap = false;
  const D.match({this.min = 0, this.max = 0, this.pct})
    : b = 'M',
      px = 0,
      cwrap = false;
  const D.cwrap({this.min = 0, this.max = 0})
    : b = 'M',
      px = 0,
      pct = null,
      cwrap = true;
  const D.parent({this.min = 0, this.max = 0})
    : b = 'P',
      px = 0,
      pct = null,
      cwrap = false;

  final String b;
  final int px;
  final int min;
  final int max;
  final double? pct;
  final bool cwrap;

  bool get fixed => b == 'F';

  /// The match style op fields: style min max pct.
  String styleArgs() {
    final style = pct != null ? 2 : (cwrap ? 1 : 0);
    return '$style $min $max ${fs(pct ?? 1.0)}';
  }

  String get key => '$b$px/$min/$max/$pct/$cwrap';
}

enum K { widget, barrier, guideline, flow }

class FlowCfg {
  int orientation = 0;
  int wrapMode = 0;
  int hStyle = 0, vStyle = 0;
  double hBias = 0.5, vBias = 0.5;
  int hAlign = 2, vAlign = 2;
  int hGap = 0, vGap = 0;
  int maxElements = -1;
  int padL = 0, padT = 0, padR = 0, padB = 0;
}

class S {
  S.widget(this.id, this.width, this.height, this.content) : kind = K.widget;
  S.barrier(
    this.id,
    this.edge,
    this.refs, {
    this.margin = 0,
    this.allowsGone = true,
  }) : kind = K.barrier,
       width = const D.wrap(),
       height = const D.wrap(),
       content = null;
  S.guideline(this.id, this.horizontalLine, {this.gBegin, this.gEnd, this.gPct})
    : kind = K.guideline,
      width = const D.wrap(),
      height = const D.wrap(),
      content = null;
  S.flow(this.id, this.flow, this.refs, this.width, this.height)
    : kind = K.flow,
      content = null;

  final String id;
  final K kind;

  // Widget and flow.
  D width;
  D height;
  Content? content;
  Lk? start, end, left, right, top, bottom, baseline;
  ({String target, double angle, int radius})? circle;
  double hBias = 0.5;
  double vBias = 0.5;

  /// The ratio as its two parts (the view layer's "W:H" string).
  (double, double)? ratio;
  int ratioSide = -1;
  int hChain = 0;
  int vChain = 0;
  double? hWeight;
  double? vWeight;
  int vis = 0;

  // Barrier.
  String edge = 'bottom';
  List<String> refs = const [];
  int margin = 0;
  bool allowsGone = true;

  // Guideline. horizontalLine: Guideline.horizontal (0).
  bool horizontalLine = false;
  int? gBegin;
  int? gEnd;
  double? gPct;

  // Flow.
  FlowCfg? flow;

  bool get isRegular => kind == K.widget;

  /// Every field the adapter re-applies in place (content excluded).
  String configKey() {
    String l(Lk? k) =>
        k == null ? '-' : '${k.target}.${k.edge}.${k.margin}.${k.gone}';
    return [
      width.key,
      height.key,
      l(start),
      l(end),
      l(left),
      l(right),
      l(top),
      l(bottom),
      l(baseline),
      circle,
      hBias,
      vBias,
      ratio,
      ratioSide,
      hChain,
      vChain,
      hWeight,
      vWeight,
      vis,
    ].join('|');
  }

  S clone() {
    final S c;
    switch (kind) {
      case K.widget:
        c = S.widget(id, width, height, content);
      case K.barrier:
        c = S.barrier(
          id,
          edge,
          [...refs],
          margin: margin,
          allowsGone: allowsGone,
        );
      case K.guideline:
        c = S.guideline(
          id,
          horizontalLine,
          gBegin: gBegin,
          gEnd: gEnd,
          gPct: gPct,
        );
      case K.flow:
        c = S.flow(id, flow, [...refs], width, height);
    }
    c
      ..start = start
      ..end = end
      ..left = left
      ..right = right
      ..top = top
      ..bottom = bottom
      ..baseline = baseline
      ..circle = circle
      ..hBias = hBias
      ..vBias = vBias
      ..ratio = ratio
      ..ratioSide = ratioSide
      ..hChain = hChain
      ..vChain = vChain
      ..hWeight = hWeight
      ..vWeight = vWeight
      ..vis = vis;
    return c;
  }
}

/// A T layout: the container and its child list.
class TL {
  TL(this.w, this.h, {this.ltr = true, this.wrapW = false, this.wrapH = false});

  int w;
  int h;
  bool ltr;
  bool wrapW;
  bool wrapH;
  final List<S> specs = [];

  /// The layout view's own ops: cspec, cpad, cmin, cmax.
  final List<String> viewOps = [];

  /// The container ops (prepareOps) for a core path: [w] x [h], an axis it
  /// wraps at 0 (or at its AT_MOST size, set by [containerOps]).
  List<String>? containerOps;

  S add(S s) {
    specs.add(s);
    return s;
  }

  TL clone() {
    final c = TL(w, h, ltr: ltr, wrapW: wrapW, wrapH: wrapH);
    c.specs.addAll(specs.map((s) => s.clone()));
    c.viewOps.addAll(viewOps);
    c.containerOps = containerOps;
    return c;
  }
}

/// The widgets that need a real baseline: both ends of every baseline link
/// (a link to the parent's baseline has no sibling end).
Set<String> needsBaselineOf(List<S> specs) {
  final ids = {for (final s in specs) s.id};
  final out = <String>{};
  for (final s in specs) {
    final b = s.baseline;
    if (s.kind == K.widget && b != null && s.circle == null) {
      out.add(s.id);
      if (ids.contains(b.target)) out.add(b.target);
    }
  }
  return out;
}

/// The default content of a regular widget without one: a box at its fixed
/// size.
Content contentFor(S s) =>
    s.content ?? Content(ContentKind.box, s.width.px, s.height.px, -1);

/// `_prepareContainer` (fspec prepareOps), unless [TL.containerOps] is set.
List<String> prepare(TL l) =>
    l.containerOps ??
    [
      l.ltr ? 'ltr' : 'rtl',
      l.wrapW ? 'wrapw' : 'fixw',
      l.wrapH ? 'wraph' : 'fixh',
      'cw ${l.wrapW ? 0 : l.w}',
      'ch ${l.wrapH ? 0 : l.h}',
    ];

/// The config ops of one child (the second loop).
List<String> configOps(S s, {required bool ltr}) {
  final ops = <String>[];
  String hAnchor(String edge) => switch (edge) {
    'left' => 'L',
    'right' => 'R',
    'start' => ltr ? 'L' : 'R',
    'end' => ltr ? 'R' : 'L',
    _ => throw ArgumentError('h edge $edge'),
  };
  String vAnchor(String edge) => switch (edge) {
    'top' => 'T',
    'bottom' => 'B',
    'baseline' => 'S',
    _ => throw ArgumentError('v edge $edge'),
  };
  String target(String t) => t == 'parent' ? 'root' : t;
  switch (s.kind) {
    case K.guideline:
      ops.add('go ${s.id} ${s.horizontalLine ? 0 : 1}');
      final mirror = !ltr && !s.horizontalLine;
      if (s.gPct != null) {
        final p = mirror ? f32(1 - f32(s.gPct!)) : s.gPct!;
        ops.add('gp ${s.id} ${fs(p)}');
      } else if (s.gBegin != null) {
        ops.add(mirror ? 'ge ${s.id} ${s.gBegin}' : 'gb ${s.id} ${s.gBegin}');
      } else if (s.gEnd != null) {
        ops.add(mirror ? 'gb ${s.id} ${s.gEnd}' : 'ge ${s.id} ${s.gEnd}');
      }
      return ops;
    case K.barrier:
      final type = switch (s.edge) {
        'left' => 0,
        'right' => 1,
        'top' => 2,
        'bottom' => 3,
        'start' => ltr ? 0 : 1,
        'end' => ltr ? 1 : 0,
        _ => throw ArgumentError('edge ${s.edge}'),
      };
      ops.add('bt ${s.id} $type');
      ops.add('bg ${s.id} ${s.allowsGone ? 1 : 0}');
      if (s.margin != 0) ops.add('bm ${s.id} ${s.margin}');
      for (final r in s.refs) {
        ops.add('ref ${s.id} $r');
      }
      return ops;
    case K.flow:
      final f = s.flow!;
      ops.addAll([
        'fo ${s.id} ${f.orientation}',
        'fwm ${s.id} ${f.wrapMode}',
        'fhs ${s.id} ${f.hStyle}',
        'fvs ${s.id} ${f.vStyle}',
        'fhb ${s.id} ${fs(f.hBias)}',
        'fvb ${s.id} ${fs(f.vBias)}',
        'fha ${s.id} ${f.hAlign}',
        'fva ${s.id} ${f.vAlign}',
        'fhg ${s.id} ${f.hGap}',
        'fvg ${s.id} ${f.vGap}',
        if (f.maxElements != -1) 'fme ${s.id} ${f.maxElements}',
        'fpad ${s.id} ${f.padL} ${f.padT} ${f.padR} ${f.padB}',
      ]);
      for (final r in s.refs) {
        ops.add('ref ${s.id} $r');
      }
      ops.add('frtl ${s.id} ${ltr ? 0 : 1}');
    case K.widget:
      break;
  }
  // A widget, or a flow's own widget config.
  final wd = s.width, ht = s.height;
  ops.add('hb ${s.id} ${wd.b}');
  ops.add('vb ${s.id} ${ht.b}');
  if (wd.b == 'M' || wd.min != 0 || wd.max != 0) {
    ops.add('hm ${s.id} ${wd.styleArgs()}');
  }
  if (ht.b == 'M' || ht.min != 0 || ht.max != 0) {
    ops.add('vm ${s.id} ${ht.styleArgs()}');
  }
  final directional = s.start != null || s.end != null;
  final hb = !ltr && directional ? f32(1 - f32(s.hBias)) : s.hBias;
  if (hb != 0.5) ops.add('hx ${s.id} ${fs(hb)}');
  if (s.vBias != 0.5) ops.add('vx ${s.id} ${fs(s.vBias)}');
  final ra = s.ratio;
  if (ra != null) {
    ops.add('ra ${s.id} ${fs(f32(f32(ra.$1) / f32(ra.$2)))} ${s.ratioSide}');
  }
  if (s.hChain != 0) ops.add('hc ${s.id} ${s.hChain}');
  if (s.vChain != 0) ops.add('vc ${s.id} ${s.vChain}');
  if (s.hWeight != null) ops.add('hw ${s.id} ${fs(s.hWeight!)}');
  if (s.vWeight != null) ops.add('vw ${s.id} ${fs(s.vWeight!)}');
  if (s.vis != 0) ops.add('v ${s.id} ${s.vis}');
  final c = s.circle;
  if (c != null) {
    ops.add('cc ${s.id} ${target(c.target)} ${fs(c.angle)} ${c.radius}');
    return ops;
  }
  void link(String from, Lk? l, bool horizontal) {
    if (l == null) return;
    final fa = horizontal ? hAnchor(from) : vAnchor(from);
    final ta = horizontal ? hAnchor(l.edge) : vAnchor(l.edge);
    ops.add('c ${s.id} $fa ${target(l.target)} $ta ${l.margin}');
    if (l.gone != 0) ops.add('gm ${s.id} $fa ${l.gone}');
  }

  if (directional) {
    link('start', s.start, true);
    link('end', s.end, true);
  } else {
    link('left', s.left, true);
    link('right', s.right, true);
  }
  link('top', s.top, false);
  link('bottom', s.bottom, false);
  link('baseline', s.baseline, false);
  return ops;
}

/// The fresh op list of [l] (see the file comment).
///
/// [orientFirst] (the T2 corpus, Phase 1): every guideline is oriented when it
/// is created (`g`, then `go`, then `add`), as Android does in `onViewAdded`
/// before any constraint and as the adapter does when it creates the widget
/// (constraint_layout.dart, `Guideline()..setOrientation(...)`), so a sibling
/// configured before the guideline links to the edge it names. Without it (T,
/// Phase 0) a core Guideline stays horizontal until its config `go`, and a
/// link from an earlier sibling into its left or right edge is dropped. The
/// config loop keeps its `go` either way (a no-op on an oriented guideline,
/// as the adapter's `_applyHelperConfig` re-applies it).
List<String> emitT(TL l, {bool orientFirst = false}) {
  final ops = <String>['R ${l.w} ${l.h}'];
  if (!l.ltr) ops.add('rtl');
  if (l.wrapW) ops.add('wrapw');
  if (l.wrapH) ops.add('wraph');
  for (final s in l.specs) {
    switch (s.kind) {
      case K.widget:
        ops.add(
          'w ${s.id} ${s.width.fixed ? s.width.px : 0} '
          '${s.height.fixed ? s.height.px : 0}',
        );
        ops.add(contentFor(s).toOp(s.id));
      case K.barrier:
        ops.add('b ${s.id}');
      case K.guideline:
        ops.add('g ${s.id}');
        if (orientFirst) ops.add('go ${s.id} ${s.horizontalLine ? 0 : 1}');
      case K.flow:
        ops.add('fl ${s.id}');
    }
    ops.add('add ${s.id}');
  }
  for (final id in needsBaselineOf(l.specs)) {
    ops.add('hbl $id 1');
  }
  for (final s in l.specs) {
    ops.addAll(configOps(s, ltr: l.ltr));
  }
  ops.addAll(prepare(l));
  ops.addAll(l.viewOps);
  ops.add('adeps');
  return ops;
}

/// The ops that take a container built from [prev] to [next] the way the
/// adapter's in-place path does (fspec emitInPlace, content version): the
/// derived baseline flags, `_applyWidgetConfig` on each changed regular
/// child in child order, the normalization before the engine pass (a
/// non-fixed axis at 0, position 0, baseline distance 0, the flags), the
/// changed content, the container, the view ops and `adeps`. Helpers do not
/// change between [prev] and [next].
List<String> emitInPlaceT(TL prev, TL next) {
  final ops = <String>[];
  final before = {for (final s in prev.specs) s.id: s};
  final needs = needsBaselineOf(next.specs);
  for (final id in needs) {
    ops.add('hbl $id 1');
  }
  for (final s in next.specs) {
    if (!s.isRegular) continue;
    final old = before[s.id];
    if (old != null && old.configKey() == s.configKey()) continue;
    ops.addAll([
      'ipr ${s.id}',
      'ra ${s.id} 0.0 -1',
      'hm ${s.id} 0 0 0 1.0',
      'vm ${s.id} 0 0 0 1.0',
      'sx ${s.id} 0',
      'sy ${s.id} 0',
      'hx ${s.id} 0.5',
      'vx ${s.id} 0.5',
      'hc ${s.id} 0',
      'vc ${s.id} 0',
      'hw ${s.id} -1.0',
      'vw ${s.id} -1.0',
      'v ${s.id} 0',
      'sw ${s.id} ${s.width.fixed ? s.width.px : 0}',
      'sh ${s.id} ${s.height.fixed ? s.height.px : 0}',
    ]);
    ops.addAll(configOps(s, ltr: next.ltr));
  }
  for (final s in next.specs) {
    if (!s.isRegular) continue;
    ops.addAll([
      'sw ${s.id} ${s.width.fixed ? s.width.px : 0}',
      'sh ${s.id} ${s.height.fixed ? s.height.px : 0}',
      'sx ${s.id} 0',
      'sy ${s.id} 0',
      'bl ${s.id} 0',
      'hbl ${s.id} ${needs.contains(s.id) ? 1 : 0}',
    ]);
    final old = before[s.id];
    final c = contentFor(s);
    if (old == null || contentFor(old) != c) ops.add(c.toOp(s.id));
  }
  ops.addAll(prepare(next));
  ops.addAll(next.viewOps);
  ops.add('adeps');
  return ops;
}
