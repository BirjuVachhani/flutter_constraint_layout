// verify-final: a declarative child list (as a Flutter screen declares its
// ConstraintLayout children), emitted as engine ops in the order and the
// state the Flutter adapter (constraint_layout.dart) produces them:
// - every child is created and added in child order;
// - the widgets that need a real baseline (both ends of every baseline
//   link, _computeDerivedState) are flagged hasBaseline before any link;
// - each child is configured in child order: behaviours, match styles
//   (spread, constrained wrap, percent, with min and max), bias (mirrored in
//   RTL for a start/end-linked child), ratio, chain styles, weights,
//   visibility, then its horizontal links (start/end, else left/right), top,
//   bottom and baseline, each followed by its gone margin;
// - barriers map start/end to right/left in RTL and negate a directional
//   margin there; vertical guidelines mirror in RTL;
// - then the state performLayout normalizes before the engine pass, with an
//   echo measurer in mind: a gone child's non-fixed size is 0 (nothing
//   measures it), and a child's baseline is what the measurer reports: its
//   text baseline when it needs one and has text, none otherwise, and a gone
//   child that needs one keeps the hasBaseline flag with a distance of 0.

class Link {
  const Link(this.target, this.edge, [this.margin = 0, this.gone = 0]);

  /// 'parent' or a child id.
  final String target;

  /// start, end, left, right, top, bottom, baseline.
  final String edge;
  final int margin;
  final int gone;
}

/// A dimension: fixed (F), wrap (W), match constraint (M: spread, constrained
/// wrap or percent, with min and max) or match parent (P).
class Dim {
  const Dim.fixed(this.px)
    : b = 'F',
      min = 0,
      max = 0,
      pct = null,
      cwrap = false;
  const Dim.wrap()
    : b = 'W',
      px = 0,
      min = 0,
      max = 0,
      pct = null,
      cwrap = false;
  const Dim.match({this.min = 0, this.max = 0, this.pct})
    : b = 'M',
      px = 0,
      cwrap = false;
  const Dim.cwrap({this.min = 0, this.max = 0})
    : b = 'M',
      px = 0,
      pct = null,
      cwrap = true;
  const Dim.parent()
    : b = 'P',
      px = 0,
      min = 0,
      max = 0,
      pct = null,
      cwrap = false;

  final String b;
  final int px;
  final int min;
  final int max;
  final double? pct;
  final bool cwrap;

  bool get fixed => b == 'F';
}

enum Kind { widget, barrier, guideline }

class Spec {
  Spec.widget(this.id, this.iw, this.ih, {this.baselineDist = 0})
    : kind = Kind.widget;
  Spec.barrier(
    this.id,
    this.edge,
    this.refs, {
    this.margin = 0,
    this.allowsGone = true,
  }) : kind = Kind.barrier,
       iw = 0,
       ih = 0,
       baselineDist = 0;
  Spec.guideline(
    this.id,
    this.horizontalLine, {
    this.gBegin,
    this.gEnd,
    this.gPct,
  }) : kind = Kind.guideline,
       iw = 0,
       ih = 0,
       baselineDist = 0;

  final String id;
  final Kind kind;

  // Widget: content size and text baseline (0: no text).
  int iw;
  int ih;
  int baselineDist;
  Dim? width;
  Dim? height;
  Link? start, end, left, right, top, bottom, baseline;
  double hBias = 0.5;
  double vBias = 0.5;
  double? ratio;
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

  // Guideline. horizontalLine: a horizontal line (Guideline.horizontal, 0).
  bool horizontalLine = false;
  int? gBegin;
  int? gEnd;
  double? gPct;
}

/// Whether a guideline is oriented when it is created, as proposal 6 makes
/// the adapter do, rather than with its config in child order.
var orientGuidelinesFirst = false;

/// Emits [specs] as ops for a container of [w] x [h] (see the file comment).
List<String> emitSpecs(
  int w,
  int h,
  List<Spec> specs, {
  bool ltr = true,
  bool wrapW = false,
  bool wrapH = false,
}) {
  final ops = <String>['R $w $h'];
  if (!ltr) ops.add('rtl');
  if (wrapW) ops.add('wrapw');
  if (wrapH) ops.add('wraph');
  final byId = {for (final s in specs) s.id: s};
  // Both ends of every baseline link, as _computeDerivedState collects them
  // (a link to the parent's baseline has no sibling end).
  final needsBaseline = <String>{};
  for (final s in specs) {
    final b = s.baseline;
    if (s.kind == Kind.widget && b != null) {
      needsBaseline.add(s.id);
      if (byId.containsKey(b.target)) needsBaseline.add(b.target);
    }
  }
  for (final s in specs) {
    switch (s.kind) {
      case Kind.widget:
        final gone = s.vis == 8;
        final wd = s.width ?? const Dim.wrap();
        final ht = s.height ?? const Dim.wrap();
        final cw = wd.fixed ? wd.px : (gone ? 0 : s.iw);
        final ch = ht.fixed ? ht.px : (gone ? 0 : s.ih);
        ops.add('w ${s.id} $cw $ch');
      case Kind.barrier:
        ops.add('b ${s.id}');
      case Kind.guideline:
        ops.add('g ${s.id}');
        // Proposal 6: the adapter orients a guideline when it creates it.
        if (orientGuidelinesFirst) {
          ops.add('go ${s.id} ${s.horizontalLine ? 0 : 1}');
        }
    }
    ops.add('add ${s.id}');
  }
  for (final id in needsBaseline) {
    ops.add('hbl $id 1');
  }
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
  for (final s in specs) {
    switch (s.kind) {
      case Kind.guideline:
        // Guideline.horizontal is 0 (a horizontal line), vertical is 1.
        ops.add('go ${s.id} ${s.horizontalLine ? 0 : 1}');
        final mirror = !ltr && !s.horizontalLine;
        if (s.gPct != null) {
          ops.add('gp ${s.id} ${mirror ? 1 - s.gPct! : s.gPct!}');
        } else if (s.gBegin != null) {
          ops.add(mirror ? 'ge ${s.id} ${s.gBegin}' : 'gb ${s.id} ${s.gBegin}');
        } else if (s.gEnd != null) {
          ops.add(mirror ? 'gb ${s.id} ${s.gEnd}' : 'ge ${s.id} ${s.gEnd}');
        }
      case Kind.barrier:
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
        final directional = s.edge == 'start' || s.edge == 'end';
        final m = !ltr && directional ? -s.margin : s.margin;
        if (m != 0) ops.add('bm ${s.id} $m');
        for (final r in s.refs) {
          ops.add('ref ${s.id} $r');
        }
      case Kind.widget:
        final wd = s.width ?? const Dim.wrap();
        final ht = s.height ?? const Dim.wrap();
        ops.add('hb ${s.id} ${wd.b}');
        ops.add('vb ${s.id} ${ht.b}');
        if (wd.b == 'M') {
          final style = wd.pct != null ? 2 : (wd.cwrap ? 1 : 0);
          ops.add('hm ${s.id} $style ${wd.min} ${wd.max} ${wd.pct ?? 1.0}');
        }
        if (ht.b == 'M') {
          final style = ht.pct != null ? 2 : (ht.cwrap ? 1 : 0);
          ops.add('vm ${s.id} $style ${ht.min} ${ht.max} ${ht.pct ?? 1.0}');
        }
        final directional = s.start != null || s.end != null;
        final hb = !ltr && directional ? 1 - s.hBias : s.hBias;
        if (hb != 0.5) ops.add('hx ${s.id} $hb');
        if (s.vBias != 0.5) ops.add('vx ${s.id} ${s.vBias}');
        if (s.ratio != null) ops.add('ra ${s.id} ${s.ratio!} -1');
        if (s.hChain != 0) ops.add('hc ${s.id} ${s.hChain}');
        if (s.vChain != 0) ops.add('vc ${s.id} ${s.vChain}');
        if (s.hWeight != null) ops.add('hw ${s.id} ${s.hWeight!}');
        if (s.vWeight != null) ops.add('vw ${s.id} ${s.vWeight!}');
        if (s.vis != 0) ops.add('v ${s.id} ${s.vis}');
        void link(String from, Link? l, bool horizontal) {
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
    }
  }
  // performLayout's normalization (distance 0, flagged when it needs a
  // baseline), with the text baseline the measurer will report already in
  // place for the echo measurer. A widget without text keeps the flag until
  // a measure reports its distance of 0, which clears it; a gone one is
  // never measured by the engine.
  for (final s in specs) {
    if (s.kind != Kind.widget) continue;
    if (needsBaseline.contains(s.id) && s.vis != 8 && s.baselineDist > 0) {
      ops.add('bl ${s.id} ${s.baselineDist}');
    }
  }
  return ops;
}

/// A copy of [s] that can be changed without changing [s].
Spec cloneSpec(Spec s) {
  final Spec c;
  switch (s.kind) {
    case Kind.widget:
      c = Spec.widget(s.id, s.iw, s.ih, baselineDist: s.baselineDist);
    case Kind.barrier:
      c = Spec.barrier(
        s.id,
        s.edge,
        [...s.refs],
        margin: s.margin,
        allowsGone: s.allowsGone,
      );
    case Kind.guideline:
      c = Spec.guideline(
        s.id,
        s.horizontalLine,
        gBegin: s.gBegin,
        gEnd: s.gEnd,
        gPct: s.gPct,
      );
  }
  c
    ..width = s.width
    ..height = s.height
    ..start = s.start
    ..end = s.end
    ..left = s.left
    ..right = s.right
    ..top = s.top
    ..bottom = s.bottom
    ..baseline = s.baseline
    ..hBias = s.hBias
    ..vBias = s.vBias
    ..ratio = s.ratio
    ..hChain = s.hChain
    ..vChain = s.vChain
    ..hWeight = s.hWeight
    ..vWeight = s.vWeight
    ..vis = s.vis;
  return c;
}

String _dimKey(Dim? d) =>
    d == null ? 'W' : '${d.b}${d.px}/${d.min}/${d.max}/${d.pct}/${d.cwrap}';
String _linkKey(Link? l) =>
    l == null ? '-' : '${l.target}.${l.edge}.${l.margin}.${l.gone}';

/// Every field of a regular child that the adapter re-applies in place
/// (its content size and baseline are the measurer's, not config).
String configKey(Spec s) => [
  _dimKey(s.width),
  _dimKey(s.height),
  _linkKey(s.start),
  _linkKey(s.end),
  _linkKey(s.left),
  _linkKey(s.right),
  _linkKey(s.top),
  _linkKey(s.bottom),
  _linkKey(s.baseline),
  s.hBias,
  s.vBias,
  s.ratio,
  s.hChain,
  s.vChain,
  s.hWeight,
  s.vWeight,
  s.vis,
].join('|');

/// The ops that take a container built from [prev] (same ids, same child
/// order, same helpers) to [next] the way the Flutter adapter's in-place
/// path does (performLayout with configDirty children): the derived state,
/// _applyWidgetConfig on each changed regular child in child order, the
/// normalization before the engine pass (with the echo measurer's content
/// sizes and baselines put in place), and _prepareContainer. The container
/// is [w] x [h], an axis it wraps at 0 as an unbounded constraint gives it.
List<String> emitInPlace(
  List<Spec> prev,
  List<Spec> next, {
  required int w,
  required int h,
  bool ltr = true,
  bool wrapW = false,
  bool wrapH = false,
  String fix = '',
}) {
  final ops = <String>[];
  final before = {for (final s in prev) s.id: s};
  final byId = {for (final s in next) s.id: s};
  final needsBaseline = <String>{};
  for (final s in next) {
    final b = s.baseline;
    if (s.kind == Kind.widget && b != null) {
      needsBaseline.add(s.id);
      if (byId.containsKey(b.target)) needsBaseline.add(b.target);
    }
  }
  // _computeDerivedState seeds the flag of every widget that needs one.
  for (final id in needsBaseline) {
    ops.add('hbl $id 1');
  }
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
  for (final s in next) {
    if (s.kind != Kind.widget) continue;
    final old = before[s.id];
    if (old != null && configKey(old) == configKey(s)) continue;
    // _applyWidgetConfig.
    ops.addAll([
      'ipr ${s.id}',
      'ra ${s.id} 0.0 -1',
      'hm ${s.id} 0 0 0 1.0',
      'vm ${s.id} 0 0 0 1.0',
      'sx ${s.id} 0',
      'sy ${s.id} 0',
    ]);
    final wd = s.width ?? const Dim.wrap();
    final ht = s.height ?? const Dim.wrap();
    ops.add('hb ${s.id} ${wd.b}');
    ops.add('vb ${s.id} ${ht.b}');
    ops.add('sw ${s.id} ${wd.fixed ? wd.px : 0}');
    ops.add('sh ${s.id} ${ht.fixed ? ht.px : 0}');
    if (wd.b == 'M') {
      final style = wd.pct != null ? 2 : (wd.cwrap ? 1 : 0);
      ops.add('hm ${s.id} $style ${wd.min} ${wd.max} ${wd.pct ?? 1.0}');
    }
    if (ht.b == 'M') {
      final style = ht.pct != null ? 2 : (ht.cwrap ? 1 : 0);
      ops.add('vm ${s.id} $style ${ht.min} ${ht.max} ${ht.pct ?? 1.0}');
    }
    final directional = s.start != null || s.end != null;
    ops.add('hx ${s.id} ${!ltr && directional ? 1 - s.hBias : s.hBias}');
    ops.add('vx ${s.id} ${s.vBias}');
    if (s.ratio != null) ops.add('ra ${s.id} ${s.ratio!} -1');
    ops.add('hc ${s.id} ${s.hChain}');
    ops.add('vc ${s.id} ${s.vChain}');
    ops.add('hw ${s.id} ${s.hWeight ?? -1.0}');
    ops.add('vw ${s.id} ${s.vWeight ?? -1.0}');
    ops.add('v ${s.id} ${s.vis}');
    void link(String from, Link? l, bool horizontal) {
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
    if (fix == 'iprest') ops.add('iprest ${s.id}');
  }
  if (fix == 'rereg') ops.add('rereg');
  ops.addAll(normalizeOps(next, needsBaseline));
  ops.addAll(prepareOps(w, h, ltr: ltr, wrapW: wrapW, wrapH: wrapH));
  return ops;
}

/// performLayout's normalization of every regular child before an engine
/// pass, followed by what the echo measurer needs to report the child's
/// content: its content size on a non-fixed axis (a gone child keeps 0,
/// nothing measures it) and its text baseline when it needs one.
List<String> normalizeOps(List<Spec> specs, Set<String> needsBaseline) {
  final ops = <String>[];
  for (final s in specs) {
    if (s.kind != Kind.widget) continue;
    final wd = s.width ?? const Dim.wrap();
    final ht = s.height ?? const Dim.wrap();
    final gone = s.vis == 8;
    ops.add('sw ${s.id} ${wd.fixed ? wd.px : (gone ? 0 : s.iw)}');
    ops.add('sh ${s.id} ${ht.fixed ? ht.px : (gone ? 0 : s.ih)}');
    ops.add('sx ${s.id} 0');
    ops.add('sy ${s.id} 0');
    ops.add('bl ${s.id} 0');
    final needs = needsBaseline.contains(s.id);
    ops.add('hbl ${s.id} ${needs ? 1 : 0}');
    if (needs && !gone && s.baselineDist > 0) {
      ops.add('bl ${s.id} ${s.baselineDist}');
    }
  }
  return ops;
}

/// _prepareContainer for a [w] x [h] constraint, an axis it wraps unbounded.
List<String> prepareOps(
  int w,
  int h, {
  bool ltr = true,
  bool wrapW = false,
  bool wrapH = false,
}) => [
  ltr ? 'ltr' : 'rtl',
  wrapW ? 'wrapw' : 'fixw',
  wrapH ? 'wraph' : 'fixh',
  'cw ${wrapW ? 0 : w}',
  'ch ${wrapH ? 0 : h}',
];

/// The baseline-needing widgets of [specs] (see emitSpecs).
Set<String> needsBaselineOf(List<Spec> specs) {
  final byId = {for (final s in specs) s.id: s};
  final out = <String>{};
  for (final s in specs) {
    final b = s.baseline;
    if (s.kind == Kind.widget && b != null) {
      out.add(s.id);
      if (byId.containsKey(b.target)) out.add(b.target);
    }
  }
  return out;
}
