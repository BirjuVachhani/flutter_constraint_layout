// A declarative child list, emitted as engine ops in the order the Flutter
// adapter (constraint_layout.dart) makes its engine calls: every child is
// created and added in child order, then each child is configured in child
// order (behaviours, match styles, bias (mirrored for start/end links in
// RTL), ratio, chain styles, weights, visibility, then its horizontal links
// (start/end or left/right), top, bottom and baseline, each followed by its
// gone margin). Barriers map start/end to right/left in RTL and negate a
// directional margin there; vertical guidelines mirror in RTL.

class Link {
  const Link(this.target, this.edge, [this.margin = 0, this.gone = 0]);

  /// 'parent' or a child id.
  final String target;

  /// start, end, left, right, top, bottom, baseline.
  final String edge;
  final int margin;
  final int gone;
}

/// A dimension: fixed (F), wrap (W), match constraint (M) or match parent (P).
class Dim {
  const Dim.fixed(this.px) : b = 'F', min = 0, max = 0, pct = null;
  const Dim.wrap() : b = 'W', px = 0, min = 0, max = 0, pct = null;
  const Dim.match({this.min = 0, this.max = 0, this.pct}) : b = 'M', px = 0;
  const Dim.parent() : b = 'P', px = 0, min = 0, max = 0, pct = null;

  final String b;
  final int px;
  final int min;
  final int max;
  final double? pct;
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

  // Widget.
  final int iw;
  final int ih;
  final int baselineDist;
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

String _f(double v) {
  final s = v.toString();
  return s;
}

/// Emits [specs] as ops for a container of [w] x [h].
List<String> emit(
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
  for (final s in specs) {
    switch (s.kind) {
      case Kind.widget:
        ops.add('w ${s.id} ${s.iw} ${s.ih}');
        if (s.baselineDist > 0) ops.add('bl ${s.id} ${s.baselineDist}');
      case Kind.barrier:
        ops.add('b ${s.id}');
      case Kind.guideline:
        ops.add('g ${s.id}');
    }
    ops.add('add ${s.id}');
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
          ops.add('gp ${s.id} ${_f(mirror ? 1 - s.gPct! : s.gPct!)}');
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
          final style = wd.pct != null ? 2 : 0;
          ops.add('hm ${s.id} $style ${wd.min} ${wd.max} ${_f(wd.pct ?? 1)}');
        }
        if (ht.b == 'M') {
          final style = ht.pct != null ? 2 : 0;
          ops.add('vm ${s.id} $style ${ht.min} ${ht.max} ${_f(ht.pct ?? 1)}');
        }
        final directional = s.start != null || s.end != null;
        final hb = !ltr && directional ? 1 - s.hBias : s.hBias;
        if (hb != 0.5) ops.add('hx ${s.id} ${_f(hb)}');
        if (s.vBias != 0.5) ops.add('vx ${s.id} ${_f(s.vBias)}');
        if (s.ratio != null) ops.add('ra ${s.id} ${_f(s.ratio!)} -1');
        if (s.hChain != 0) ops.add('hc ${s.id} ${s.hChain}');
        if (s.vChain != 0) ops.add('vc ${s.id} ${s.vChain}');
        if (s.hWeight != null) ops.add('hw ${s.id} ${_f(s.hWeight!)}');
        if (s.vWeight != null) ops.add('vw ${s.id} ${_f(s.vWeight!)}');
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
  return ops;
}
