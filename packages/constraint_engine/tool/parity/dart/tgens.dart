// T: the 15 targeted families of FORMATS.md 4.4, which says what each one
// stresses. Each family returns a T layout (temit.dart), emitted with content
// in the adapter's call order and the adeps state. T-inplace emits an
// in-place sequence and T-fresh the fresh build of the same sequence's final
// state.
//
// T2 (Phase 1, FORMATS.md 16): the same families, seeds and layouts, emitted
// with every guideline oriented at creation (emitT orientFirst), as Android
// and the adapter orient it; T2-fresh is the fresh build of each corrected
// T2-inplace sequence's final state. T stays as Phase 0 left it.
import 'dart:math';

import 'content.dart';
import 'temit.dart';

typedef TGen = List<String>? Function(int seed);

const int tFirstSeed = 500000000;

/// The Phase 0 seed count of a T or T2 generator ([gen] `T-<family>` or
/// `T2-<family>`).
int tCount(String gen) =>
    switch (gen.startsWith('T2-') ? 'T-${gen.substring(3)}' : gen) {
      'T-pctmin' || 'T-chain' || 'T-wrap' || 'T-inplace' || 'T-fresh' => 50000,
      _ => 20000,
    };

class Rnd {
  Rnd(int seed) : r = Random(seed);
  final Random r;
  int i(int n) => r.nextInt(n);
  int range(int a, int b) => a + r.nextInt(b - a + 1);
  bool p(double x) => r.nextDouble() < x;
  T pick<T>(List<T> xs) => xs[r.nextInt(xs.length)];
  int margin() =>
      pick(const [0, 0, 0, 4, 8, 8, 12, 16, 16, 24, 3, 5, 7, 10, 1, 2]);
  double bias() => pick(const [
    0.5,
    0.5,
    0.0,
    1.0,
    0.3,
    0.7,
    0.25,
    0.75,
    0.2,
    0.8,
    0.1,
    0.9,
    0.33,
    0.67,
    0.4,
    0.6,
    0.35,
    0.45,
    0.55,
    0.65,
    0.15,
    0.85,
    0.37,
    0.63,
  ]);
  double oddBias() => pick(const [
    0.3,
    0.7,
    0.33,
    0.67,
    0.35,
    0.65,
    0.45,
    0.55,
    0.15,
    0.85,
    0.37,
    0.63,
    0.1,
    0.9,
    0.123,
    0.789,
    0.333,
    0.666,
    0.05,
    0.95,
    0.31,
    0.69,
    0.41,
  ]);
  double pct() => pick(const [
    0.5,
    0.25,
    0.3,
    0.33,
    0.4,
    0.6,
    0.7,
    0.75,
    0.2,
    0.8,
    0.35,
    0.45,
    0.55,
    0.65,
    0.15,
    0.85,
    0.1,
    0.9,
    0.66,
    0.375,
    0.125,
    0.3333,
    0.6667,
    0.29,
  ]);
  int textH() => pick(const [14, 16, 17, 18, 19, 20, 21, 22, 24, 28, 15, 13]);
  int textW() => range(18, 300);
  int bl(int h) => max(1, (h * pick(const [0.75, 0.8, 0.7, 0.78])).round());
  int screenW() => p(0.5)
      ? pick(const [
          320,
          360,
          375,
          390,
          393,
          411,
          412,
          414,
          428,
          430,
          600,
          768,
          800,
          1024,
        ])
      : range(200, 1200);
  int screenH() => p(0.5)
      ? pick(const [
          568,
          640,
          667,
          736,
          812,
          844,
          851,
          896,
          915,
          932,
          1024,
          1280,
        ])
      : range(200, 1400);
}

// ---------------------------------------------------------------------------
// Building blocks.
// ---------------------------------------------------------------------------

/// A wrap x wrap text: [w] wide on one line, [h] per line, with a baseline.
S text(Rnd r, String id, {int? w, int? h}) {
  final hh = h ?? r.textH();
  return S.widget(
    id,
    const D.wrap(),
    const D.wrap(),
    Content(ContentKind.text, w ?? r.textW(), hh, r.bl(hh)),
  );
}

/// A fixed box with a box content of the same size and no baseline.
S box(String id, int w, int h, {int baseline = -1}) => S.widget(
  id,
  D.fixed(w),
  D.fixed(h),
  Content(ContentKind.box, w, h, baseline),
);

/// A wrap x wrap box (an image with an intrinsic size).
S wbox(String id, int w, int h) => S.widget(
  id,
  const D.wrap(),
  const D.wrap(),
  Content(ContentKind.box, w, h, -1),
);

/// A Group helper: a plain wrap x wrap widget measured 0 x 0, unlinked.
S group(String id) => S.widget(
  id,
  const D.wrap(),
  const D.wrap(),
  const Content(ContentKind.box, 0, 0, -1),
);

/// A random regular widget: text, box, wrap box or a match-constraint text.
S anyWidget(Rnd r, String id) {
  switch (r.i(6)) {
    case 0:
    case 1:
      return text(r, id);
    case 2:
      return box(id, r.range(8, 120), r.range(8, 90));
    case 3:
      return wbox(id, r.range(8, 160), r.range(8, 120));
    case 4:
      final s = text(r, id, w: r.range(40, 600));
      s.width = const D.match();
      return s;
    default:
      final s = text(r, id);
      s.width = r.p(0.5) ? const D.cwrap() : const D.parent();
      return s;
  }
}

/// A child order a developer might use (fgens order()).
List<S> order(Rnd r, List<S> specs) {
  if (r.p(0.65)) return specs;
  final out = [...specs];
  if (r.p(0.3)) {
    out.shuffle(r.r);
    return out;
  }
  final helpers = out.where((s) => s.kind != K.widget).toList();
  final widgets = out.where((s) => s.kind == K.widget).toList();
  return r.p(0.5) ? [...helpers, ...widgets] : [...widgets, ...helpers];
}

/// A container: a phone or tablet size, sometimes RTL, sometimes wrapping.
TL container(
  Rnd r, {
  double rtl = 0.25,
  double wrapW = 0.0,
  double wrapH = 0.0,
}) => TL(
  r.screenW(),
  r.screenH(),
  ltr: !r.p(rtl),
  wrapW: r.p(wrapW),
  wrapH: r.p(wrapH),
);

/// Links [s] horizontally between two targets, start/end or left/right.
void hBetween(Rnd r, S s, Lk a, Lk b, {double directional = 0.5}) {
  if (r.p(directional)) {
    s.start = Lk(
      a.target,
      a.edge == 'left' ? 'start' : (a.edge == 'right' ? 'end' : a.edge),
      a.margin,
      a.gone,
    );
    s.end = Lk(
      b.target,
      b.edge == 'left' ? 'start' : (b.edge == 'right' ? 'end' : b.edge),
      b.margin,
      b.gone,
    );
  } else {
    s.left = a;
    s.right = b;
  }
}

/// A vertical stack of [n] random widgets under the parent's top, each
/// linked to the parent's start (sometimes end) edge: context that makes a
/// layout look like a screen around the targeted part.
List<S> filler(Rnd r, String prefix, int n) {
  final out = <S>[];
  String? above;
  for (var k = 0; k < n; k++) {
    final s = anyWidget(r, '$prefix$k');
    s.top = above == null
        ? Lk('parent', 'top', r.margin())
        : Lk(above, 'bottom', r.margin());
    if (s.width.b == 'M' || s.width.b == 'P' || r.p(0.3)) {
      hBetween(
        r,
        s,
        Lk('parent', 'left', r.margin()),
        Lk('parent', 'right', r.margin()),
      );
    } else {
      s.left = Lk('parent', 'left', r.margin());
    }
    if (r.p(0.08)) s.vis = 8;
    out.add(s);
    above = s.id;
  }
  return out;
}

// ---------------------------------------------------------------------------
// T-pctmin: percent sizes with a min above, at or below f x parent.
// ---------------------------------------------------------------------------
TL tPctMin(Rnd r) {
  final l = container(r, wrapW: 0.1, wrapH: 0.15);
  final anchors = <String>[];
  if (r.p(0.5)) {
    final a = box('aL', r.range(10, 80), r.range(10, 60));
    a.left = Lk('parent', 'left', r.margin());
    a.top = Lk('parent', 'top', r.margin());
    if (r.p(0.15)) a.vis = 8;
    l.add(a);
    anchors.add('aL');
  }
  if (r.p(0.5)) {
    final a = box('aR', r.range(10, 80), r.range(10, 60));
    a.right = Lk('parent', 'right', r.margin());
    a.bottom = Lk('parent', 'bottom', r.margin());
    if (r.p(0.15)) a.vis = 8;
    l.add(a);
    anchors.add('aR');
  }
  final n = r.range(1, 4);
  for (var k = 0; k < n; k++) {
    final s = text(r, 'p$k', w: r.range(10, 500));
    final both = r.p(0.2);
    final horizontal = both || r.p(0.6);
    D pctDim(int parent) {
      final f = r.pct();
      final fp = f * parent;
      final mode = r.i(10);
      int mn;
      if (mode < 5) {
        mn = fp.ceil() + r.range(1, 200);
      } else if (mode < 7) {
        mn = fp.round();
      } else if (mode < 9) {
        mn = max(1, fp.floor() - r.range(1, 100));
      } else {
        mn = 0;
      }
      final mx = r.p(0.3) ? max(1, mn + r.range(-60, 200)) : 0;
      return D.match(pct: f, min: mn, max: mx);
    }

    if (horizontal) {
      s.width = pctDim(l.w);
      final left = anchors.isNotEmpty && r.p(0.3)
          ? Lk(r.pick(anchors), 'right', r.margin())
          : Lk('parent', 'left', r.margin());
      final right = anchors.isNotEmpty && r.p(0.3)
          ? Lk(r.pick(anchors), 'left', r.margin())
          : Lk('parent', 'right', r.margin());
      if (r.p(0.65)) {
        hBetween(r, s, left, right);
        s.hBias = r.p(0.5) ? r.bias() : 0.5;
      } else if (r.p(0.5)) {
        s.left = left;
      } else {
        s.right = right;
      }
    } else {
      s.left = Lk('parent', 'left', r.margin());
    }
    if (!horizontal || both) {
      s.height = pctDim(l.h);
      if (r.p(0.65)) {
        s.top = Lk('parent', 'top', r.margin());
        s.bottom = Lk('parent', 'bottom', r.margin());
        s.vBias = r.p(0.5) ? r.bias() : 0.5;
      } else if (r.p(0.5)) {
        s.top = Lk('parent', 'top', r.margin());
      } else {
        s.bottom = Lk('parent', 'bottom', r.margin());
      }
    } else {
      s.top = k == 0
          ? Lk('parent', 'top', r.margin())
          : Lk('p${k - 1}', 'bottom', r.margin());
    }
    if (r.p(0.1)) s.vis = 8;
    l.add(s);
  }
  if (r.p(0.4)) {
    final f = text(r, 'below');
    f.top = Lk('p${n - 1}', 'bottom', r.margin());
    f.left = Lk('p${n - 1}', 'left');
    l.add(f);
  }
  l.specs.setAll(0, order(Rnd(r.i(1 << 30)), [...l.specs]));
  return l;
}

// ---------------------------------------------------------------------------
// T-crossed: crossed and coincident links, gone targets collapsing.
// ---------------------------------------------------------------------------
TL tCrossed(Rnd r) {
  final l = container(r, wrapW: 0.05, wrapH: 0.1);
  final horizontal = r.p(0.6);
  final size = horizontal ? l.w : l.h;
  final aSize = r.range(10, max(11, size ~/ 3));
  final bSize = r.range(10, max(11, size ~/ 3));
  final a = box(
    'a',
    horizontal ? aSize : r.range(10, 60),
    horizontal ? r.range(10, 60) : aSize,
  );
  final b = box(
    'b',
    horizontal ? bSize : r.range(10, 60),
    horizontal ? r.range(10, 60) : bSize,
  );
  final aM = r.range(0, size ~/ 2), bM = r.range(0, size ~/ 2);
  if (horizontal) {
    a.left = Lk('parent', 'left', aM);
    b.right = Lk('parent', 'right', bM);
    a.top = Lk('parent', 'top', r.margin());
    b.top = Lk('parent', 'top', r.margin());
  } else {
    a.top = Lk('parent', 'top', aM);
    b.bottom = Lk('parent', 'bottom', bM);
    a.left = Lk('parent', 'left', r.margin());
    b.left = Lk('parent', 'left', r.margin());
  }
  if (r.p(0.15)) a.vis = 8;
  if (r.p(0.15)) b.vis = 8;
  l.add(a);
  l.add(b);
  final gapAvail = size - (aM + aSize) - (bM + bSize);
  // The victims' margins: crossed (start past end), coincident or plain.
  final mode = r.i(10);
  int m1, m2;
  if (mode < 5) {
    m1 = r.range(0, 200) + max(0, gapAvail ~/ 2);
    m2 = max(0, gapAvail - m1) + r.range(1, 200);
  } else if (mode < 7) {
    m1 = r.range(0, max(0, gapAvail));
    m2 = gapAvail - m1;
  } else {
    m1 = r.margin();
    m2 = r.margin();
  }
  final n = r.range(1, 3);
  String prevStart = 'a', prevEnd = 'b';
  for (var k = 0; k < n; k++) {
    late S v;
    switch (r.i(3)) {
      case 0:
        v = box('v$k', r.range(5, 120), r.range(5, 80));
      case 1:
        v = text(r, 'v$k');
      default:
        v = text(r, 'v$k');
        if (horizontal) {
          v.width = const D.match();
        } else {
          v.height = const D.match();
        }
    }
    if (horizontal) {
      final sEdge = k == 0 ? 'right' : 'left';
      final eEdge = k == 0 ? 'left' : 'right';
      hBetween(
        r,
        v,
        Lk(prevStart, sEdge, k == 0 ? m1 : r.margin()),
        Lk(prevEnd, eEdge, k == 0 ? m2 : r.margin()),
      );
      v.hBias = r.p(0.4) ? r.bias() : 0.5;
      v.top = Lk('parent', 'top', r.range(0, 200));
    } else {
      v.top = Lk(
        prevStart,
        k == 0 ? 'bottom' : 'top',
        k == 0 ? m1 : r.margin(),
      );
      v.bottom = Lk(
        prevEnd,
        k == 0 ? 'top' : 'bottom',
        k == 0 ? m2 : r.margin(),
      );
      v.vBias = r.p(0.4) ? r.bias() : 0.5;
      v.left = Lk('parent', 'left', r.range(0, 200));
    }
    if (r.p(0.1)) v.vis = 8;
    l.add(v);
    prevStart = 'v$k';
    prevEnd = 'v$k';
  }
  // Something hanging off the last victim, and parent links with margins
  // summing past the container.
  if (r.p(0.5)) {
    final d = text(r, 'dep');
    d.left = Lk('v${n - 1}', r.p(0.5) ? 'left' : 'right', r.margin());
    d.top = Lk('v${n - 1}', 'bottom', r.margin());
    l.add(d);
  }
  if (r.p(0.4)) {
    final o = box('over', r.range(10, 100), r.range(10, 60));
    final m = r.range(size ~/ 2, size);
    if (horizontal) {
      o.left = Lk('parent', 'left', m);
      o.right = Lk('parent', 'right', m);
      o.bottom = Lk('parent', 'bottom', r.margin());
    } else {
      o.top = Lk('parent', 'top', m);
      o.bottom = Lk('parent', 'bottom', m);
      o.right = Lk('parent', 'right', r.margin());
    }
    l.add(o);
  }
  l.specs.addAll(filler(r, 'f', r.range(0, 2)));
  return l;
}

// ---------------------------------------------------------------------------
// T-negedge: exact negative edges, chained, readback.
// ---------------------------------------------------------------------------
TL tNegEdge(Rnd r) {
  final l = container(r, wrapW: 0.05, wrapH: 0.1);
  final t = box('t', r.range(10, 120), r.range(10, 60));
  t.left = Lk('parent', 'left', r.range(0, 20));
  t.top = Lk('parent', 'top', r.range(0, 20));
  l.add(t);
  final n = r.range(2, 5);
  var prev = 't';
  for (var k = 0; k < n; k++) {
    final S v = r.p(0.5)
        ? box('n$k', r.range(5, 200), r.range(5, 150))
        : (r.p(0.5)
              ? text(r, 'n$k')
              : wbox('n$k', r.range(5, 200), r.range(5, 150)));
    switch (r.i(5)) {
      case 0:
        // Bottom-aligned with a shorter widget at the top.
        v.bottom = Lk(prev, 'bottom', r.range(-10, 4));
        v.left = Lk(prev, 'right', r.range(-40, 8));
      case 1:
        // Right edge on a widget's left edge near x = 0.
        v.right = Lk(prev, 'left', r.range(-8, 16));
        v.top = Lk(prev, 'top', r.range(-20, 8));
      case 2:
        // Negative margins to the parent.
        v.left = Lk('parent', 'left', -r.range(1, 120));
        v.top = Lk('parent', 'top', -r.range(1, 120));
      case 3:
        // Centered in the parent but larger than it.
        final big = box('n$k', l.w + r.range(1, 301), r.range(5, 60));
        l.add(
          big
            ..left = Lk('parent', 'left', r.margin())
            ..right = Lk('parent', 'right', r.margin())
            ..hBias = r.p(0.5) ? r.bias() : 0.5
            ..top = Lk(prev, 'bottom', r.margin()),
        );
        prev = 'n$k';
        continue;
      default:
        // Centered on a widget it overhangs on both sides.
        v.left = Lk(prev, 'left', 0);
        v.right = Lk(prev, 'right', 0);
        v.top = Lk(prev, 'top', 0);
        v.bottom = Lk(prev, 'bottom', 0);
        v.vBias = r.p(0.5) ? r.bias() : 0.5;
    }
    if (r.p(0.05)) v.vis = 8;
    l.add(v);
    prev = 'n$k';
  }
  l.specs.addAll(filler(r, 'f', r.range(0, 2)));
  return l;
}

// ---------------------------------------------------------------------------
// T-oddbias: odd biases in Direct and in the solver, RTL flips.
// ---------------------------------------------------------------------------
TL tOddBias(Rnd r) {
  final l = container(r, rtl: 0.5, wrapW: 0.05, wrapH: 0.1);
  final n = r.range(1, 4);
  // A percent widget (the solver resolves it) for some widgets to center on.
  if (r.p(0.4)) {
    final p = text(r, 'pw', w: r.range(20, 200));
    p.width = D.match(pct: r.pct());
    p.left = Lk('parent', 'left', r.margin());
    p.right = Lk('parent', 'right', r.margin());
    p.hBias = r.oddBias();
    p.top = Lk('parent', 'top', r.margin());
    l.add(p);
  }
  if (r.p(0.3)) {
    l.add(S.guideline('gv', false, gPct: r.pct()));
  }
  final ids = l.specs
      .where((s) => s.kind == K.widget)
      .map((s) => s.id)
      .toList();
  for (var k = 0; k < n; k++) {
    final S v = r.p(0.5)
        ? box('o$k', r.range(5, 300) | 1, r.range(5, 200) | (r.p(0.5) ? 1 : 0))
        : text(r, 'o$k');
    Lk start = Lk('parent', 'left', r.margin() | (r.p(0.5) ? 1 : 0));
    Lk end = Lk('parent', 'right', r.margin());
    if (ids.isNotEmpty && r.p(0.4)) {
      final t = r.pick(ids);
      start = Lk(t, r.p(0.5) ? 'left' : 'right', r.margin());
    }
    if (l.specs.any((s) => s.id == 'gv') && r.p(0.3)) {
      end = Lk('gv', 'left', r.margin());
    }
    hBetween(r, v, start, end, directional: 0.7);
    v.hBias = r.oddBias();
    v.top = Lk('parent', 'top', r.range(0, 300));
    if (r.p(0.5)) {
      v.bottom = Lk('parent', 'bottom', r.margin());
      v.vBias = r.oddBias();
    }
    if (r.p(0.1)) v.vis = 8;
    l.add(v);
    ids.add(v.id);
  }
  return l;
}

// ---------------------------------------------------------------------------
// T-ratio: ratios on one or both match-constraint axes.
// ---------------------------------------------------------------------------
const _ratios = <(double, double)>[
  (16, 9),
  (4, 3),
  (3, 2),
  (1, 1),
  (9, 16),
  (2.35, 1),
  (21, 9),
  (5, 4),
  (7, 3),
  (1.618, 1),
  (3, 4),
  (2, 3),
  (1, 2),
  (2, 1),
  (1.7777778, 1),
  (0.5625, 1),
  (13, 7),
  (1, 3),
];

TL tRatio(Rnd r) {
  final l = container(r, rtl: 0.2, wrapW: 0.05, wrapH: 0.15);
  final n = r.range(1, 3);
  String? above;
  for (var k = 0; k < n; k++) {
    final s = wbox('r$k', r.range(10, 400), r.range(10, 300));
    s.ratio = r.pick(_ratios);
    s.ratioSide = r.p(0.8) ? -1 : r.pick(const [0, 1]);
    switch (r.i(4)) {
      case 0:
        s.width = const D.match();
      case 1:
        s.height = const D.match();
      case 2:
        s.width = const D.match();
        s.height = const D.match();
      default:
        s.width = const D.match();
        s.height = D.fixed(r.range(10, 200));
        s.content = Content(ContentKind.box, r.range(10, 300), s.height.px, -1);
    }
    if (r.p(0.15)) {
      s.width = D.match(
        min: r.range(0, 100),
        max: r.p(0.5) ? r.range(50, 400) : 0,
      );
    }
    final twoH = r.p(0.7), twoV = r.p(0.5);
    if (twoH) {
      hBetween(
        r,
        s,
        Lk('parent', 'left', r.margin()),
        Lk('parent', 'right', r.margin()),
      );
      s.hBias = r.p(0.3) ? r.bias() : 0.5;
    } else {
      s.left = Lk('parent', 'left', r.margin());
    }
    s.top = above == null
        ? Lk('parent', 'top', r.margin())
        : Lk(above, 'bottom', r.margin());
    if (twoV) s.bottom = Lk('parent', 'bottom', r.margin());
    if (r.p(0.08)) s.vis = 8;
    l.add(s);
    above = s.id;
  }
  // A ratio member inside a chain.
  if (r.p(0.25)) {
    final a = text(r, 'ca');
    final b = wbox('cb', r.range(10, 200), r.range(10, 120));
    b.width = const D.match();
    b.ratio = r.pick(_ratios);
    a.left = Lk('parent', 'left', r.margin());
    a.right = Lk('cb', 'left', r.margin());
    b.left = Lk('ca', 'right', r.margin());
    b.right = Lk('parent', 'right', r.margin());
    a.hChain = r.i(3);
    a.bottom = Lk('parent', 'bottom', r.margin());
    b.bottom = Lk('parent', 'bottom', r.margin());
    l.add(a);
    l.add(b);
  }
  return l;
}

// ---------------------------------------------------------------------------
// T-pct: percent sizes and percent guidelines near .5.
// ---------------------------------------------------------------------------
TL tPct(Rnd r) {
  final f = r.pct();
  // A parent size that puts f x size at or near a half.
  int halfSize(double f, int lo, int hi) {
    for (var t = 0; t < 20; t++) {
      final s = r.range(lo, hi);
      final v = f * s;
      if ((v - v.floor() - 0.5).abs() < 0.02) return s;
    }
    return r.range(lo, hi);
  }

  final l = TL(
    halfSize(f, 200, 1200),
    halfSize(f, 200, 1400),
    ltr: !r.p(0.3),
    wrapW: false,
    wrapH: r.p(0.1),
  );
  final gs = <String>[];
  for (var k = 0; k < r.range(0, 3); k++) {
    final g = S.guideline('g$k', r.p(0.3), gPct: r.p(0.6) ? f : r.pct());
    l.add(g);
    gs.add(g.id);
  }
  final n = r.range(1, 4);
  for (var k = 0; k < n; k++) {
    final s = text(r, 'q$k', w: r.range(10, 400));
    if (r.p(0.6)) s.width = D.match(pct: r.p(0.5) ? f : r.pct());
    if (r.p(0.3)) s.height = D.match(pct: r.pct());
    final vertical = gs
        .where((g) => !l.specs.firstWhere((x) => x.id == g).horizontalLine)
        .toList();
    final horizontalG = gs
        .where((g) => l.specs.firstWhere((x) => x.id == g).horizontalLine)
        .toList();
    Lk hs = vertical.isNotEmpty && r.p(0.5)
        ? Lk(r.pick(vertical), 'left', r.margin())
        : Lk('parent', 'left', r.margin());
    Lk he = vertical.isNotEmpty && r.p(0.5)
        ? Lk(r.pick(vertical), 'right', r.margin())
        : Lk('parent', 'right', r.margin());
    if (r.p(0.7)) {
      hBetween(r, s, hs, he);
      s.hBias = r.p(0.4) ? r.bias() : 0.5;
    } else {
      s.left = hs;
    }
    final vs = horizontalG.isNotEmpty && r.p(0.5)
        ? Lk(r.pick(horizontalG), 'top', r.margin())
        : Lk('parent', 'top', r.margin());
    s.top = vs;
    if (s.height.b == 'M' || r.p(0.3)) {
      s.bottom = Lk('parent', 'bottom', r.margin());
      s.vBias = r.p(0.4) ? r.bias() : 0.5;
    }
    l.add(s);
  }
  return l;
}

// ---------------------------------------------------------------------------
// T-measure: measure strategies.
// ---------------------------------------------------------------------------
TL tMeasure(Rnd r) {
  final l = container(r, rtl: 0.2, wrapW: 0.1, wrapH: 0.3);
  final n = r.range(2, 6);
  String? above;
  var forceSolver = false;
  for (var k = 0; k < n; k++) {
    final id = 'm$k';
    late S s;
    switch (r.i(8)) {
      case 0:
        // Match parent x wrap text that wraps at the parent width.
        s = text(
          r,
          id,
          w: r.range(100, 2500),
          h: r.pick(const [16, 18, 20, 24]),
        );
        s.width = const D.parent();
        if (r.p(0.4)) s.left = Lk('parent', 'left', r.margin());
        if (r.p(0.4)) s.right = Lk('parent', 'right', r.margin());
      case 1:
        // Match x match, a dangling axis or two links.
        s = S.widget(
          id,
          const D.match(),
          const D.match(),
          r.p(0.5)
              ? Content(ContentKind.box, r.range(10, 400), r.range(10, 200), -1)
              : Content(
                  ContentKind.text,
                  r.range(10, 800),
                  r.textH(),
                  r.bl(18),
                ),
        );
        s.left = Lk('parent', 'left', r.margin());
        if (r.p(0.5)) s.right = Lk('parent', 'right', r.margin());
      case 2:
        // A fixed baseline pair (plus a constrained wrap text to reach
        // the solver).
        final hh = r.range(16, 60);
        s = box(id, r.range(20, 200), hh, baseline: r.range(1, hh));
        final p = box('${id}b', r.range(20, 200), r.range(10, 40));
        p.content = Content(
          ContentKind.box,
          p.width.px,
          p.height.px,
          r.range(1, p.height.px),
        );
        p.left = Lk(id, 'right', r.margin());
        p.baseline = Lk(id, 'baseline', r.p(0.8) ? 0 : r.range(-4, 8));
        s.left = Lk('parent', 'left', r.margin());
        l.add(
          s
            ..top = above == null
                ? Lk('parent', 'top', r.range(0, 100))
                : Lk(above, 'bottom', r.margin()),
        );
        l.add(p);
        forceSolver = forceSolver || r.p(0.5);
        above = id;
        continue;
      case 3:
        // Two-link match constraint x wrap text.
        s = text(r, id, w: r.range(50, 1500));
        s.width = const D.match();
        hBetween(
          r,
          s,
          Lk('parent', 'left', r.margin()),
          Lk('parent', 'right', r.margin()),
        );
      case 4:
        // Match x match text, both spread: skipped by measureChildren; its
        // baseline alone can trigger pass 1.
        s = S.widget(
          id,
          const D.match(),
          const D.match(),
          Content(ContentKind.text, r.range(10, 600), r.textH(), r.bl(18)),
        );
        hBetween(
          r,
          s,
          Lk('parent', 'left', r.margin()),
          Lk('parent', 'right', r.margin()),
        );
        s.bottom = Lk('parent', 'bottom', r.margin());
      case 5:
        // Constrained wrap text between links narrower than the text.
        s = text(r, id, w: r.range(50, 1200));
        s.width = D.cwrap(
          max: r.p(0.3) ? r.range(40, 300) : 0,
          min: r.p(0.2) ? r.range(10, 80) : 0,
        );
        hBetween(
          r,
          s,
          Lk('parent', 'left', r.margin()),
          Lk('parent', 'right', r.range(0, 300)),
        );
      case 6:
        // A min/max clamp and the second measure at the clamped size.
        s = text(r, id, w: r.range(50, 1200));
        s.width = D.match(min: r.range(0, 200), max: r.range(20, 300));
        if (r.p(0.5)) {
          s.height = D.match(
            min: r.range(0, 40),
            max: r.p(0.5) ? r.range(10, 60) : 0,
          );
          s.bottom = Lk('parent', 'bottom', r.margin());
        }
        hBetween(
          r,
          s,
          Lk('parent', 'left', r.margin()),
          Lk('parent', 'right', r.margin()),
        );
      default:
        // A wrap text wider than its links (it overflows them).
        s = text(r, id, w: r.range(200, 1500));
        hBetween(
          r,
          s,
          Lk('parent', 'left', r.range(0, 200)),
          Lk('parent', 'right', r.range(0, 200)),
        );
        s.hBias = r.p(0.4) ? r.bias() : 0.5;
    }
    s.top = above == null
        ? Lk('parent', 'top', r.range(0, 100))
        : Lk(above, 'bottom', r.margin());
    if (r.p(0.06)) s.vis = 8;
    l.add(s);
    above = id;
  }
  if (forceSolver) {
    final c = text(r, 'cw', w: r.range(50, 400));
    c.width = const D.cwrap();
    c.left = Lk('parent', 'left', r.margin());
    c.right = Lk('parent', 'right', r.margin());
    c.bottom = Lk('parent', 'bottom', r.margin());
    l.add(c);
  }
  return l;
}

// ---------------------------------------------------------------------------
// T-gone: gone widgets with baselines, gone margins, gone match parent
// and match x match, barriers over gone widgets.
// ---------------------------------------------------------------------------
TL tGone(Rnd r) {
  final l = container(r, rtl: 0.2, wrapW: 0.05, wrapH: 0.2);
  final n = r.range(3, 7);
  final ids = <String>[];
  String? above;
  for (var k = 0; k < n; k++) {
    final id = 'g$k';
    late S s;
    switch (r.i(5)) {
      case 0:
        s = text(r, id);
      case 1:
        s = box(id, r.range(10, 200), r.range(10, 120));
      case 2:
        s = text(r, id)..width = const D.parent();
      case 3:
        s = S.widget(
          id,
          const D.match(),
          const D.match(),
          Content(ContentKind.text, r.range(10, 400), r.textH(), r.bl(18)),
        );
        s.right = Lk('parent', 'right', r.margin());
        s.bottom = Lk('parent', 'bottom', r.margin());
      default:
        s = wbox(id, r.range(10, 200), r.range(10, 120));
    }
    s.left ??= ids.isNotEmpty && r.p(0.4)
        ? Lk(r.pick(ids), 'right', r.margin(), r.p(0.5) ? r.range(1, 32) : 0)
        : Lk('parent', 'left', r.margin());
    if (ids.isNotEmpty && r.p(0.35) && s.content!.baseline > 0) {
      final t = r.pick(ids);
      final ts = l.specs.firstWhere((x) => x.id == t);
      if ((ts.content?.baseline ?? -1) > 0) {
        s.baseline = Lk(t, 'baseline', r.p(0.7) ? 0 : r.range(-6, 12));
      }
    }
    if (s.baseline == null) {
      s.top = above == null
          ? Lk('parent', 'top', r.margin())
          : Lk(above, 'bottom', r.margin(), r.p(0.5) ? r.range(1, 40) : 0);
    }
    if (r.p(0.4)) s.vis = 8;
    l.add(s);
    ids.add(id);
    above = id;
  }
  if (r.p(0.6)) {
    final refs = <String>{
      for (var k = 0; k < r.range(1, 3); k++) r.pick(ids),
    }.toList();
    l.add(
      S.barrier(
        'bar',
        r.pick(const ['bottom', 'end', 'top', 'start']),
        refs,
        margin: r.p(0.5) ? r.range(-8, 16) : 0,
        allowsGone: r.p(0.5),
      ),
    );
    final d = text(r, 'afterBar');
    final b = l.specs.last;
    if (b.edge == 'bottom' || b.edge == 'top') {
      d.top = Lk('bar', b.edge, r.margin());
      d.left = Lk('parent', 'left', r.margin());
    } else {
      d.start = Lk('bar', b.edge, r.margin());
      d.top = Lk('parent', 'top', r.margin());
    }
    l.add(d);
  }
  final tail = text(r, 'tail');
  tail.top = Lk(above!, 'bottom', r.margin(), r.p(0.5) ? r.range(1, 40) : 0);
  tail.left = Lk('parent', 'left', r.margin());
  l.add(tail);
  return l;
}

// ---------------------------------------------------------------------------
// T-circle: circle constraints.
// ---------------------------------------------------------------------------
TL tCircle(Rnd r) {
  final l = container(r, rtl: 0.15, wrapW: 0.05, wrapH: 0.1);
  final hub = r.p(0.5)
      ? box('hub', r.range(10, 160), r.range(10, 160))
      : text(r, 'hub');
  hub.left = Lk('parent', 'left', r.margin());
  hub.right = Lk('parent', 'right', r.margin());
  hub.top = Lk('parent', 'top', r.range(0, 400));
  if (r.p(0.5)) {
    hub.bottom = Lk('parent', 'bottom', r.margin());
    hub.vBias = r.bias();
  }
  hub.hBias = r.bias();
  l.add(hub);
  final ids = ['hub'];
  final n = r.range(1, 4);
  for (var k = 0; k < n; k++) {
    final s = r.p(0.5)
        ? box('c$k', r.range(4, 80), r.range(4, 80))
        : text(r, 'c$k');
    final angle = r.p(0.5)
        ? r.pick(const [
            0.0,
            30.0,
            45.0,
            60.0,
            90.0,
            120.0,
            135.0,
            180.0,
            225.0,
            270.0,
            300.0,
            315.0,
            360.0,
          ])
        : (r.r.nextDouble() * 720 - 180).toDouble();
    s.circle = (
      target: r.pick(ids),
      angle: r.p(0.5) ? angle.roundToDouble() : f32(angle),
      radius: r.range(0, 300),
    );
    if (r.p(0.1)) s.vis = 8;
    l.add(s);
    ids.add(s.id);
  }
  if (r.p(0.5)) {
    final d = text(r, 'label');
    d.top = Lk(r.pick(ids.sublist(1)), 'bottom', r.margin());
    d.left = Lk(r.pick(ids.sublist(1)), 'left', r.margin());
    l.add(d);
  }
  return l;
}

// ---------------------------------------------------------------------------
// T-virtual: one Flow (no Grid), members others link to.
// ---------------------------------------------------------------------------
TL tVirtual(Rnd r) {
  final l = container(r, rtl: 0.3, wrapW: 0.1, wrapH: 0.25);
  final k = r.range(2, 8);
  final members = <String>[];
  for (var j = 0; j < k; j++) {
    final s = r.p(0.6)
        ? text(r, 'm$j')
        : (r.p(0.5)
              ? box('m$j', r.range(10, 160), r.range(10, 100))
              : wbox('m$j', r.range(10, 200), r.range(10, 120)));
    if (r.p(0.1)) s.width = const D.match();
    if (r.p(0.1)) s.vis = 8;
    members.add(s.id);
    l.add(s);
  }
  final cfg = FlowCfg()
    ..orientation = r.p(0.7) ? 0 : 1
    ..wrapMode = r.pick(const [0, 1, 1, 2, 2, 3])
    ..hStyle = r.i(3)
    ..vStyle = r.i(3)
    ..hBias = r.p(0.5) ? 0.5 : r.bias()
    ..vBias = r.p(0.5) ? 0.5 : r.bias()
    ..hAlign = r.i(4)
    ..vAlign = r.i(4)
    ..hGap = r.pick(const [0, 0, 4, 8, 12, 16, 5])
    ..vGap = r.pick(const [0, 0, 4, 8, 12, 16, 3])
    ..maxElements = r.p(0.3) ? r.range(1, 4) : -1;
  if (r.p(0.3)) {
    cfg
      ..padL = r.range(0, 16)
      ..padT = r.range(0, 16)
      ..padR = r.range(0, 16)
      ..padB = r.range(0, 16);
  }
  final D fw = switch (r.i(4)) {
    0 => const D.wrap(),
    1 => const D.match(),
    2 => const D.parent(),
    _ => D.fixed(r.range(60, max(61, l.w))),
  };
  final D fh = r.p(0.7)
      ? const D.wrap()
      : (r.p(0.5) ? const D.match() : D.fixed(r.range(40, 400)));
  final f = S.flow('flow', cfg, members, fw, fh);
  hBetween(
    r,
    f,
    Lk('parent', 'left', r.margin()),
    Lk('parent', 'right', r.margin()),
  );
  f.top = Lk('parent', 'top', r.range(0, 120));
  if (fh.b == 'M' || r.p(0.2)) f.bottom = Lk('parent', 'bottom', r.margin());
  // The flow before or after its members in child order.
  if (r.p(0.5)) {
    l.specs.insert(0, f);
  } else {
    l.add(f);
  }
  if (r.p(0.6)) {
    final b = text(r, 'below');
    b.top = Lk('flow', 'bottom', r.margin());
    b.left = Lk('parent', 'left', r.margin());
    l.add(b);
  }
  if (r.p(0.5)) {
    final badge = box('badge', r.range(6, 20), r.range(6, 20));
    final m = r.pick(members);
    badge.right = Lk(m, 'right', r.range(-6, 0));
    badge.top = Lk(m, 'top', r.range(-6, 0));
    l.add(badge);
  }
  return l;
}

// ---------------------------------------------------------------------------
// T-depsorder: earlier children linked into the top or bottom of a
// baseline-linked widget.
// ---------------------------------------------------------------------------
TL tDepsOrder(Rnd r) {
  final l = container(r, rtl: 0.2, wrapW: 0.05, wrapH: 0.2);
  final y = text(r, 'y');
  y.left = Lk('parent', 'left', r.margin());
  y.top = Lk('parent', 'top', r.range(0, 300));
  final x = r.p(0.7)
      ? text(r, 'x')
      : box('x', r.range(10, 160), r.range(16, 60), baseline: r.range(4, 14));
  x.left = Lk('y', 'right', r.margin());
  // x's own top and bottom links are dropped by its baseline link.
  if (r.p(0.4)) x.top = Lk('parent', 'top', r.margin());
  x.baseline = Lk('y', 'baseline', r.p(0.7) ? 0 : r.range(-6, 10));
  if (r.p(0.15)) x.vis = 8;
  final early = <S>[];
  final late = <S>[];
  for (var k = 0; k < r.range(1, 4); k++) {
    final s = anyWidget(r, 'e$k');
    s.top = Lk('x', r.p(0.5) ? 'bottom' : 'top', r.margin());
    if (r.p(0.3)) s.bottom = Lk('x', 'bottom', r.margin());
    s.left = Lk('parent', 'left', r.margin());
    if (s.width.b == 'M' || s.width.b == 'P') {
      s.right = Lk('parent', 'right', r.margin());
    }
    early.add(s);
  }
  for (var k = 0; k < r.range(0, 2); k++) {
    final s = anyWidget(r, 'l$k');
    s.top = Lk('x', r.p(0.5) ? 'bottom' : 'top', r.margin());
    s.right = Lk('parent', 'right', r.margin());
    if (s.width.b == 'M' || s.width.b == 'P') {
      s.left = Lk('parent', 'left', r.margin());
    }
    late.add(s);
  }
  // Earlier children come before x in child order; y anywhere.
  final out = <S>[...early];
  if (r.p(0.5)) {
    out.insert(r.i(out.length + 1), y);
    out.add(x);
  } else {
    out.add(x);
    out.add(y);
  }
  out.addAll(late);
  l.specs.addAll(out);
  return l;
}

// ---------------------------------------------------------------------------
// T-atmost: AT_MOST and UNSPECIFIED specs, padding, container min and max,
// match min and max on any behaviour.
// ---------------------------------------------------------------------------
TL tAtMost(Rnd r) {
  final l = container(r, rtl: 0.2);
  String mode() => r.pick(const ['E', 'A', 'A', 'U']);
  final wm = mode(), hm = mode();
  final ws = r.range(100, 1200), hs = r.range(100, 1400);
  l.w = ws;
  l.h = hs;
  l.wrapW = wm != 'E';
  l.wrapH = hm != 'E';
  l.viewOps.add('cspec $wm ${wm == 'U' ? 0 : ws} $hm ${hm == 'U' ? 0 : hs}');
  // The container a core path sees: AT_MOST as a wrap axis at its size.
  l.containerOps = [
    l.ltr ? 'ltr' : 'rtl',
    l.wrapW ? 'wrapw' : 'fixw',
    l.wrapH ? 'wraph' : 'fixh',
    'cw ${wm == 'U' ? 0 : ws}',
    'ch ${hm == 'U' ? 0 : hs}',
  ];
  if (r.p(0.5)) {
    l.viewOps.add(
      'cpad ${r.range(0, 24)} ${r.range(0, 24)} ${r.range(0, 24)} ${r.range(0, 24)}',
    );
  }
  if (r.p(0.4)) {
    l.viewOps.add(
      'cmin ${r.p(0.6) ? r.range(0, ws + 200) : 0} ${r.p(0.6) ? r.range(0, hs + 200) : 0}',
    );
  }
  if (r.p(0.3)) {
    l.viewOps.add(
      'cmax ${r.p(0.6) ? r.range(50, ws + 200) : 0x7fffffff} ${r.p(0.6) ? r.range(50, hs + 200) : 0x7fffffff}',
    );
  }
  final n = r.range(2, 6);
  String? above;
  for (var k = 0; k < n; k++) {
    final s = anyWidget(r, 'w$k');
    if (r.p(0.3)) {
      // Match min and max on any behaviour (the view layer sets them on all).
      final mn = r.p(0.5) ? r.range(0, 200) : 0;
      final mx = r.p(0.6) ? r.range(10, 400) : 0;
      final w = s.width;
      s.width = switch (w.b) {
        'F' => D.fixed(w.px, min: mn, max: mx),
        'W' => D.wrap(min: mn, max: mx),
        'P' => D.parent(min: mn, max: mx),
        _ =>
          w.cwrap
              ? D.cwrap(min: mn, max: mx)
              : D.match(min: mn, max: mx, pct: w.pct),
      };
    }
    s.top = above == null
        ? Lk('parent', 'top', r.margin())
        : Lk(above, 'bottom', r.margin());
    if (k == n - 1 && r.p(0.5)) s.bottom = Lk('parent', 'bottom', r.margin());
    if (s.width.b == 'M' || s.width.b == 'P' || r.p(0.4)) {
      hBetween(
        r,
        s,
        Lk('parent', 'left', r.margin()),
        Lk('parent', 'right', r.margin()),
      );
      s.hBias = r.p(0.3) ? r.bias() : 0.5;
    } else {
      s.left = Lk('parent', 'left', r.margin());
    }
    if (r.p(0.06)) s.vis = 8;
    l.add(s);
    above = s.id;
  }
  return l;
}

// ---------------------------------------------------------------------------
// T-chain: chains, weights, styles, gone members, RTL, margins, .5
// splits.
// ---------------------------------------------------------------------------
TL tChain(Rnd r) {
  final l = container(r, rtl: 0.3, wrapW: 0.05, wrapH: 0.1);
  final chains = r.range(1, 3);
  String? above;
  for (var c = 0; c < chains; c++) {
    final horizontal = r.p(0.7);
    final k = r.range(2, 6);
    final ids = [for (var j = 0; j < k; j++) 'c${c}_$j'];
    final weighted = r.p(0.4);
    final style = r.pick(const [0, 0, 1, 2]);
    for (var j = 0; j < k; j++) {
      late S s;
      switch (r.i(5)) {
        case 0:
          s = box(ids[j], r.range(10, 160), r.range(10, 80));
        case 1:
          s = text(r, ids[j]);
        case 2:
          s = text(r, ids[j], w: r.range(10, 300));
          if (horizontal) {
            s.width = r.p(0.8) ? const D.match() : D.match(pct: r.pct());
          } else {
            s.height = const D.match();
          }
        case 3:
          s = text(r, ids[j]);
          if (horizontal) {
            s.width = r.p(0.5)
                ? const D.cwrap()
                : D.match(
                    min: r.range(0, 60),
                    max: r.p(0.5) ? r.range(40, 200) : 0,
                  );
          } else {
            s.height = const D.cwrap();
          }
        default:
          s = wbox(ids[j], r.range(10, 160), r.range(10, 100));
      }
      if (weighted) {
        final w = r.pick(const [1.0, 1.0, 2.0, 0.5, 1.5, 3.0, 0.33, 0.7, 1.3]);
        if (horizontal) {
          s.width = const D.match();
          s.hWeight = w;
        } else {
          s.height = const D.match();
          s.vWeight = w;
        }
      }
      final prev = j == 0 ? null : ids[j - 1];
      final next = j == k - 1 ? null : ids[j + 1];
      final gone = r.p(0.12);
      if (horizontal) {
        final a = prev == null
            ? Lk('parent', 'left', r.margin())
            : Lk(prev, 'right', r.margin(), r.p(0.3) ? r.range(1, 20) : 0);
        final b = next == null
            ? Lk('parent', 'right', r.margin())
            : Lk(next, 'left', r.margin());
        if (l.ltr ? r.p(0.3) : r.p(0.8)) {
          s.start = Lk(
            a.target,
            a.edge == 'left' ? 'start' : 'end',
            a.margin,
            a.gone,
          );
          s.end = Lk(
            b.target,
            b.edge == 'right' ? 'end' : 'start',
            b.margin,
            b.gone,
          );
        } else {
          s.left = a;
          s.right = b;
        }
        s.top = above == null
            ? Lk('parent', 'top', r.margin())
            : Lk(above, 'bottom', r.margin());
        if (j == 0) {
          s.hChain = style;
          if (style == 2 || r.p(0.2)) s.hBias = r.bias();
        }
      } else {
        s.top = prev == null
            ? Lk('parent', 'top', r.margin())
            : Lk(prev, 'bottom', r.margin(), r.p(0.3) ? r.range(1, 20) : 0);
        s.bottom = next == null
            ? Lk('parent', 'bottom', r.margin())
            : Lk(next, 'top', r.margin());
        s.left = Lk('parent', 'left', r.range(0, 300));
        if (j == 0) {
          s.vChain = style;
          if (style == 2 || r.p(0.2)) s.vBias = r.bias();
        }
      }
      if (gone) s.vis = 8;
      l.add(s);
    }
    if (horizontal) above = ids[r.i(k)];
  }
  return l;
}

// ---------------------------------------------------------------------------
// T-wrap: wrap containers with barriers, guidelines and Groups.
// ---------------------------------------------------------------------------
TL tWrap(Rnd r) {
  final both = r.p(0.3);
  final wrapH = both || r.p(0.7);
  final l = container(r, rtl: 0.25);
  l.wrapH = wrapH;
  l.wrapW = both || !wrapH;
  final n = r.range(2, 7);
  final ids = <String>[];
  String? above;
  final guides = <S>[];
  for (var k = 0; k < r.range(0, 2); k++) {
    final horizontalLine = r.p(0.4);
    final g = switch (r.i(3)) {
      0 => S.guideline('gl$k', horizontalLine, gBegin: r.range(0, 120)),
      1 => S.guideline('gl$k', horizontalLine, gEnd: r.range(0, 120)),
      _ => S.guideline('gl$k', horizontalLine, gPct: r.pct()),
    };
    guides.add(g);
  }
  for (var k = 0; k < n; k++) {
    final s = anyWidget(r, 'w$k');
    final vg = guides.where((g) => !g.horizontalLine).toList();
    final hg = guides.where((g) => g.horizontalLine).toList();
    if (vg.isNotEmpty && r.p(0.3)) {
      s.start = Lk(r.pick(vg).id, 'start', r.margin());
    } else if (ids.isNotEmpty && r.p(0.3)) {
      s.left = Lk(r.pick(ids), 'right', r.margin());
    } else {
      s.left = Lk('parent', 'left', r.margin());
    }
    if (s.width.b == 'M' || s.width.b == 'P' || r.p(0.15)) {
      if (s.start != null) {
        s.end = Lk('parent', 'end', r.margin());
      } else {
        s.right = Lk('parent', 'right', r.margin());
      }
    }
    if (hg.isNotEmpty && r.p(0.25)) {
      s.top = Lk(r.pick(hg).id, 'bottom', r.margin());
    } else {
      s.top = above == null
          ? Lk('parent', 'top', r.margin())
          : Lk(above, 'bottom', r.margin());
    }
    if (r.p(0.12)) s.bottom = Lk('parent', 'bottom', r.margin());
    if (r.p(0.08)) s.vis = 8;
    l.add(s);
    ids.add(s.id);
    above = s.id;
  }
  l.specs.addAll(guides);
  if (r.p(0.6)) {
    final refs = <String>{
      for (var k = 0; k < r.range(1, 3); k++) r.pick(ids),
    }.toList();
    final edge = r.pick(const ['bottom', 'end', 'right', 'top']);
    l.add(
      S.barrier(
        'bar',
        edge,
        refs,
        margin: r.p(0.4) ? r.range(-4, 16) : 0,
        allowsGone: r.p(0.6),
      ),
    );
    final d = text(r, 'tail');
    if (edge == 'bottom' || edge == 'top') {
      d.top = Lk('bar', edge, r.margin());
      d.left = Lk('parent', 'left', r.margin());
    } else {
      d.start = Lk('bar', edge == 'right' ? 'right' : 'end', r.margin());
      d.top = Lk('parent', 'top', r.margin());
    }
    l.add(d);
  }
  if (r.p(0.3)) {
    // A Group: its members' visibility follows it; the group widget is a
    // plain 0 x 0 widget in child order.
    final g = group('grp');
    final members = <String>{
      for (var k = 0; k < r.range(1, 3); k++) r.pick(ids),
    };
    final vis = r.pick(const [0, 4, 8]);
    for (final m in members) {
      l.specs.firstWhere((s) => s.id == m).vis = vis;
    }
    g.vis = vis;
    l.specs.insert(r.i(l.specs.length + 1), g);
  }
  return l;
}

// ---------------------------------------------------------------------------
// T-inplace and T-fresh: in-place sequences and the fresh final state.
// ---------------------------------------------------------------------------

/// The families whose layouts start an in-place sequence (helpers stay
/// unchanged across the steps; no flow, no circle, no view ops).
const _inPlaceBases = <TL Function(Rnd)>[
  tMeasure,
  tGone,
  tDepsOrder,
  tChain,
  tWrap,
  tOddBias,
  tPctMin,
  tCrossed,
  tNegEdge,
  tRatio,
  tPct,
];

/// Whether [l]'s vertical links (top, bottom, baseline) reach [to] from
/// [from].
bool _reachesV(TL l, String from, String to) {
  final byId = {for (final s in l.specs) s.id: s};
  final seen = <String>{};
  bool walk(String id) {
    if (id == to) return true;
    if (!seen.add(id)) return false;
    final s = byId[id];
    if (s == null) return false;
    for (final k in [s.top, s.bottom, s.baseline]) {
      if (k != null && k.target != 'parent' && walk(k.target)) return true;
    }
    return false;
  }

  return walk(from);
}

/// One in-place change to [l]'s regular widgets. A change that would close
/// a vertical cycle is skipped.
void _mutate(Rnd r, TL l) {
  final regular = l.specs.where((s) => s.isRegular).toList();
  if (regular.isEmpty) return;
  final s = r.pick(regular);
  final others = regular.where((x) => x.id != s.id).map((x) => x.id).toList();
  switch (r.i(8)) {
    case 0:
      s.vis = r.pick(const [0, 0, 4, 8]);
    case 1:
      final c = s.content;
      if (c != null && c.kind == ContentKind.text) {
        s.content = Content(
          ContentKind.text,
          max(1, c.w + r.range(-120, 400)),
          c.h,
          c.baseline,
        );
      } else if (c != null) {
        s.content = Content(
          c.kind,
          max(0, c.w + r.range(-40, 80)),
          max(0, c.h + r.range(-20, 40)),
          c.baseline,
        );
      }
    case 2:
      s.width = switch (r.i(4)) {
        0 => const D.wrap(),
        1 => D.fixed(r.range(10, 300)),
        2 => const D.match(),
        _ => const D.cwrap(),
      };
      if (s.width.b == 'M' && s.left == null && s.start == null) {
        s.left = Lk('parent', 'left', r.margin());
      }
    case 3:
      if (others.isNotEmpty && (s.content?.baseline ?? -1) > 0) {
        final t = r.pick(others);
        final ts = l.specs.firstWhere((x) => x.id == t);
        if ((ts.content?.baseline ?? -1) > 0 && !_reachesV(l, t, s.id)) {
          s.baseline = r.p(0.7) ? Lk(t, 'baseline', 0) : null;
        }
      }
    case 4:
      final t = others.isNotEmpty && r.p(0.6) ? r.pick(others) : null;
      if (t != null && _reachesV(l, t, s.id)) return;
      s.top = t != null
          ? Lk(t, r.p(0.5) ? 'bottom' : 'top', r.margin())
          : Lk('parent', 'top', r.margin());
      if (r.p(0.3)) s.baseline = null;
    case 5:
      s.hBias = r.bias();
      s.vBias = r.p(0.3) ? r.bias() : s.vBias;
    case 6:
      final m = r.margin();
      if (s.left != null) {
        s.left = Lk(s.left!.target, s.left!.edge, m, s.left!.gone);
      } else if (s.start != null) {
        s.start = Lk(s.start!.target, s.start!.edge, m, s.start!.gone);
      }
    default:
      s.height = r.p(0.5) ? const D.wrap() : D.fixed(r.range(8, 120));
  }
}

/// The steps of one in-place sequence: a base layout and 1 to 3 changed
/// versions of it.
List<TL> inPlaceSteps(int seed) {
  final r = Rnd(seed);
  final base = r.pick(_inPlaceBases)(r);
  final steps = [base];
  for (var k = 0; k < r.range(1, 3); k++) {
    final next = steps.last.clone();
    for (var m = 0; m < r.range(1, 3); m++) {
      _mutate(r, next);
    }
    steps.add(next);
  }
  return steps;
}

/// T-inplace: the fresh build of the first step, then each change in place,
/// with a measure pass (`L`) between steps; the final measure is implicit.
/// [orientFirst]: T2-inplace (guidelines oriented at creation, emitT).
List<String> tInPlace(int seed, {bool orientFirst = false}) {
  final steps = inPlaceSteps(seed);
  final ops = [...emitT(steps.first, orientFirst: orientFirst)];
  for (var k = 1; k < steps.length; k++) {
    ops.add('L');
    ops.addAll(emitInPlaceT(steps[k - 1], steps[k]));
  }
  return ops;
}

/// T-fresh: the fresh build of the last step of the same sequence.
/// [orientFirst]: T2-fresh, the fresh build of T2-inplace's final state.
List<String> tFresh(int seed, {bool orientFirst = false}) =>
    emitT(inPlaceSteps(seed).last, orientFirst: orientFirst);

TGen _fresh(TL Function(Rnd) family, {bool orientFirst = false}) =>
    (seed) => emitT(family(Rnd(seed)), orientFirst: orientFirst);

/// The families by name (`<name>` of `T-<name>` and `T2-<name>`), in the
/// Phase 0 order; T-inplace and T-fresh are added by the maps below.
final Map<String, TL Function(Rnd)> _families = {
  'pctmin': tPctMin,
  'crossed': tCrossed,
  'negedge': tNegEdge,
  'oddbias': tOddBias,
  'ratio': tRatio,
  'pct': tPct,
  'measure': tMeasure,
  'gone': tGone,
  'circle': tCircle,
  'virtual': tVirtual,
  'depsorder': tDepsOrder,
  'atmost': tAtMost,
  'chain': tChain,
  'wrap': tWrap,
};

/// T (Phase 0, unchanged): guidelines oriented in their config, in child order.
final Map<String, TGen> tGenerators = {
  for (final e in _families.entries) 'T-${e.key}': _fresh(e.value),
  'T-inplace': tInPlace,
  'T-fresh': tFresh,
};

/// T2 (Phase 1): T with every guideline oriented at creation.
final Map<String, TGen> t2Generators = {
  for (final e in _families.entries)
    'T2-${e.key}': _fresh(e.value, orientFirst: true),
  'T2-inplace': (seed) => tInPlace(seed, orientFirst: true),
  'T2-fresh': (seed) => tFresh(seed, orientFirst: true),
};
