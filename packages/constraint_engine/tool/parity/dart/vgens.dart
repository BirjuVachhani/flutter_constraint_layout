// Verifier's own barrier layout generators (verify-converge). Each returns
// the op list (see ops.dart) of one layout. The realistic ones build a child
// list the way a Flutter screen declares it and emit it in the adapter's
// call order (vspec.dart); vadv builds raw engine calls.
import 'dart:math';

import 'vspec.dart';

typedef Gen = List<String> Function(int seed);

final Map<String, Gen> vgenerators = {
  'vform': genVForm,
  'vprofile': genVProfile,
  'vcard': genVCard,
  'vtoolbar': genVToolbar,
  'vgrid': genVGrid,
  'vcenter': genVCenter,
  'vadv': genVAdv,
  'vext': genVExt,
  'vext2': (s) => genVExt(s, baselineEdges: true),
};

class R {
  R(int seed) : r = Random(seed);
  final Random r;
  int i(int n) => r.nextInt(n);
  int range(int a, int b) => a + r.nextInt(b - a + 1);
  bool p(double x) => r.nextDouble() < x;
  T pick<T>(List<T> xs) => xs[r.nextInt(xs.length)];
  int margin() => pick(const [0, 0, 4, 8, 8, 12, 16, 16, 24, 3, 5, 7, 10]);
  double bias() => pick(const [
    0.5,
    0.5,
    0.5,
    0.0,
    1.0,
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
  ]);
  int textH() => pick(const [14, 16, 17, 18, 19, 20, 21, 22, 24, 28, 15, 13]);
  int textW() => range(18, 220);
  int bl(int h) => max(1, (h * pick(const [0.75, 0.8, 0.7, 0.78])).round());
}

/// A text-like widget: wrap content with a baseline.
Spec text(R r, String id, {int? w, int? h}) {
  final hh = h ?? r.textH();
  final s = Spec.widget(id, w ?? r.textW(), hh, baselineDist: r.bl(hh));
  s.width = const Dim.wrap();
  s.height = const Dim.wrap();
  return s;
}

Spec box(String id, int w, int h, {bool wrap = false}) {
  final s = Spec.widget(id, w, h);
  s.width = wrap ? const Dim.wrap() : Dim.fixed(w);
  s.height = wrap ? const Dim.wrap() : Dim.fixed(h);
  return s;
}

/// Shuffles a child list the way a developer might order children (anchors
/// before or after their dependents), keeping the realistic order most of
/// the time.
List<Spec> order(R r, List<Spec> specs) {
  if (r.p(0.6)) return specs;
  final out = [...specs];
  if (r.p(0.5)) {
    out.shuffle(r.r);
    return out;
  }
  // Move the helpers (barriers, guidelines) to the front or the end.
  final helpers = out.where((s) => s.kind != Kind.widget).toList();
  final widgets = out.where((s) => s.kind == Kind.widget).toList();
  return r.p(0.5) ? [...helpers, ...widgets] : [...widgets, ...helpers];
}

// ---------------------------------------------------------------------------
// vform: two-column label/field forms, as a Flutter screen declares them.
// ---------------------------------------------------------------------------
List<String> genVForm(int seed) {
  final r = R(seed);
  final w = r.range(280, 1100);
  final h = r.range(420, 1500);
  final ltr = r.p(0.65);
  final specs = <Spec>[];
  final edgeM = r.pick(const [16, 16, 24, 12, 20, 8, 0, 15]);
  String? above; // anchor above the first row (a widget or barrier id)
  var aboveEdge = 'bottom';

  // Optional header.
  if (r.p(0.6)) {
    final title = text(r, 'title', h: r.pick(const [24, 28, 32, 22, 27]));
    title.start = Link('parent', 'start', edgeM);
    title.top = Link('parent', 'top', r.pick(const [16, 24, 12, 8]));
    specs.add(title);
    final refs = ['title'];
    if (r.p(0.6)) {
      final sub = text(r, 'subtitle');
      sub.start = Link('title', 'start');
      sub.top = Link('title', 'bottom', r.pick(const [2, 4, 6, 0]));
      if (r.p(0.25)) sub.vis = 8;
      if (r.p(0.4)) {
        sub.width = const Dim.match();
        sub.end = Link('parent', 'end', edgeM);
      }
      specs.add(sub);
      refs.add('subtitle');
    }
    if (r.p(0.5)) {
      final close = box(
        'close',
        r.pick(const [24, 32, 40, 48]),
        r.pick(const [24, 32, 40, 48]),
      );
      close.end = Link('parent', 'end', r.pick(const [8, 12, 16]));
      close.top = Link('title', 'top');
      if (r.p(0.5)) close.bottom = Link('title', 'bottom');
      specs.add(close);
      refs.add('close');
      if (title.end == null && r.p(0.5)) {
        title.end = Link('close', 'start', 8);
        title.hBias = r.pick(const [0.0, 0.0, 0.5]);
        if (r.p(0.4)) title.width = const Dim.match();
      }
    }
    final hb = Spec.barrier(
      'header',
      'bottom',
      refs,
      margin: r.pick(const [0, 8, 12, 16, 24]),
      allowsGone: r.p(0.7),
    );
    specs.add(hb);
    above = 'header';
  }

  final split = r.p(0.3); // a percent guideline instead of a label barrier
  final rows = r.range(1, 6);
  final labels = <String>[];
  final fields = <String>[];
  final rowBarriers = <String>[];
  final labelColumn = split ? 'split' : 'labelEnd';
  if (split) {
    final g = Spec.guideline(
      'split',
      false,
      gPct: r.pick(const [0.3, 0.33, 0.35, 0.4, 0.25, 0.375]),
    );
    if (r.p(0.3)) {
      g.gPct = null;
      g.gBegin = r.range(80, 160);
    }
    specs.add(g);
  }
  final rowGap = r.pick(const [8, 12, 16, 10, 6, 20]);
  for (var i = 0; i < rows; i++) {
    final label = text(r, 'label$i');
    final field = Spec.widget(
      'field$i',
      r.range(40, 260),
      r.pick(const [40, 48, 56, 36, 44, 22, 18]),
      baselineDist: r.p(0.7) ? r.range(12, 30) : 0,
    );
    labels.add(label.id);
    fields.add(field.id);
    // Label placement.
    if (split && r.p(0.6)) {
      // Right-aligned labels against the split.
      label.end = Link('split', 'start', r.pick(const [8, 12, 16]));
      if (r.p(0.4)) {
        label.start = Link('parent', 'start', edgeM);
        label.hBias = r.pick(const [1.0, 1.0, 0.5, 0.0]);
      }
    } else {
      label.start = Link('parent', 'start', edgeM);
    }
    final topAnchor = above;
    final gap = i == 0 ? r.pick(const [16, 24, 12, 8]) : rowGap;
    // Field horizontal.
    final fieldStartTarget = split ? 'split' : 'labelEnd';
    final fieldStartEdge = split ? 'end' : 'end';
    switch (r.i(7)) {
      case 0 || 1 || 2:
        field.width = Dim.match(
          min: r.p(0.15) ? r.range(40, 200) : 0,
          max: r.p(0.2) ? r.range(80, 400) : 0,
        );
        field.start = Link(fieldStartTarget, fieldStartEdge, r.margin());
        field.end = Link('parent', 'end', edgeM);
        if (field.width!.min > 0 || field.width!.max > 0) {
          field.hBias = r.bias();
        }
      case 3:
        field.width = Dim.fixed(field.iw);
        field.start = Link(fieldStartTarget, fieldStartEdge, r.margin());
      case 4:
        field.width = Dim.match(
          pct: r.pct(),
          max: r.p(0.2) ? r.range(60, 300) : 0,
        );
        field.start = Link(fieldStartTarget, fieldStartEdge, r.margin());
        if (r.p(0.7)) field.end = Link('parent', 'end', edgeM);
        field.hBias = r.bias();
      case 5:
        field.width = const Dim.wrap();
        field.start = Link(fieldStartTarget, fieldStartEdge, r.margin());
        field.end = Link('parent', 'end', edgeM);
        field.hBias = r.bias();
      default:
        // A swatch sized by a ratio.
        field.width = const Dim.match();
        field.height = Dim.fixed(field.ih);
        field.ratio = r.pick(const [1.0, 1.5, 2.0, 0.75, 1.3333334, 1.7777778]);
        field.start = Link(fieldStartTarget, fieldStartEdge, r.margin());
    }
    field.height ??= Dim.fixed(field.ih);
    // Vertical: one of the usual alignments.
    switch (r.i(5)) {
      case 0:
        // Label on the row's top, field baseline-aligned to it.
        label.top = topAnchor == null
            ? Link('parent', 'top', gap)
            : Link(topAnchor, aboveEdge, gap);
        if (field.baselineDist > 0) {
          field.baseline = Link(label.id, 'baseline');
        } else {
          field.top = Link(label.id, 'top');
        }
      case 1:
        // Field on the row's top, label centered on it.
        field.top = topAnchor == null
            ? Link('parent', 'top', gap)
            : Link(topAnchor, aboveEdge, gap);
        label.top = Link(field.id, 'top');
        label.bottom = Link(field.id, 'bottom');
        label.vBias = r.pick(const [0.5, 0.5, 0.0, 1.0, 0.3]);
      case 2:
        // Field on the row's top, label baseline-aligned to it.
        field.top = topAnchor == null
            ? Link('parent', 'top', gap)
            : Link(topAnchor, aboveEdge, gap);
        if (field.baselineDist > 0) {
          label.baseline = Link(field.id, 'baseline');
        } else {
          label.top = Link(field.id, 'top');
        }
      case 3:
        // Both on the row's top.
        label.top = topAnchor == null
            ? Link('parent', 'top', gap)
            : Link(topAnchor, aboveEdge, gap);
        field.top = topAnchor == null
            ? Link('parent', 'top', gap)
            : Link(topAnchor, aboveEdge, gap);
      default:
        // Label above the field (stacked), field below the label.
        label.top = topAnchor == null
            ? Link('parent', 'top', gap)
            : Link(topAnchor, aboveEdge, gap);
        field.top = Link(label.id, 'bottom', r.pick(const [4, 6, 8, 2]));
    }
    specs.add(label);
    specs.add(field);
    final rowRefs = [label.id, field.id];
    // Helper text under the field.
    if (r.p(0.35)) {
      final helper = text(r, 'help$i', h: r.pick(const [12, 13, 14, 16]));
      helper.start = Link(field.id, 'start', r.pick(const [0, 4, 12]));
      helper.top = Link(field.id, 'bottom', r.pick(const [2, 4, 6]));
      if (r.p(0.3)) {
        helper.width = const Dim.match();
        helper.end = Link(field.id, 'end');
      }
      if (r.p(0.4)) helper.vis = 8;
      specs.add(helper);
      rowRefs.add(helper.id);
    }
    // Gone rows.
    if (r.p(0.12)) {
      label.vis = 8;
      if (r.p(0.6)) field.vis = 8;
    } else if (r.p(0.05)) {
      label.vis = 4;
    }
    // The row's bottom barrier, which the next row hangs from.
    if (r.p(0.75)) {
      final rb = Spec.barrier(
        'row$i',
        'bottom',
        rowRefs,
        margin: r.pick(const [0, 0, 4, 8]),
        allowsGone: r.p(0.8),
      );
      specs.add(rb);
      rowBarriers.add(rb.id);
      above = rb.id;
      aboveEdge = 'bottom';
    } else {
      above = r.p(0.5) ? field.id : label.id;
      aboveEdge = 'bottom';
    }
  }
  if (!split) {
    final le = Spec.barrier(
      'labelEnd',
      'end',
      labels,
      margin: r.pick(const [0, 0, 8, 12, 16, 4]),
      allowsGone: r.p(0.6),
    );
    if (r.p(0.15) && specs.any((s) => s.id == 'title')) {
      le.refs = [...labels, 'title'];
    }
    specs.add(le);
  }
  // A second column (units) behind the fields.
  if (r.p(0.2)) {
    final ve = Spec.barrier('valueEnd', 'end', [
      for (final f in fields) f,
    ], margin: r.pick(const [4, 8]));
    if (r.p(0.4) && !split) ve.refs = [...ve.refs, labelColumn];
    specs.add(ve);
    final unit = text(r, 'unit');
    unit.start = Link('valueEnd', 'end', 4);
    unit.baseline = Link(fields.first, 'baseline');
    if (specs.firstWhere((s) => s.id == fields.first).baselineDist == 0) {
      unit.baseline = null;
      unit.top = Link(fields.first, 'top');
    }
    specs.add(unit);
  }
  // Bottom barrier over everything and buttons.
  final bottomRefs = [...labels, ...fields];
  final bottom = Spec.barrier(
    'bottom',
    'bottom',
    r.p(0.3) && rowBarriers.isNotEmpty
        ? [rowBarriers.last, ...fields]
        : bottomRefs,
    margin: r.pick(const [0, 16, 24]),
  );
  specs.add(bottom);
  final buttons = r.i(5);
  final bgap = r.pick(const [16, 24, 32, 12]);
  switch (buttons) {
    case 0:
      final ok = box(
        'ok',
        r.pick(const [88, 96, 120, 64]),
        r.pick(const [36, 40, 48]),
        wrap: r.p(0.5),
      );
      ok.end = Link('parent', 'end', edgeM);
      ok.top = Link('bottom', 'bottom', bgap);
      specs.add(ok);
    case 1:
      final ok = box('ok', 100, r.pick(const [40, 48, 44]));
      ok.width = const Dim.match();
      ok.start = Link('parent', 'start', edgeM);
      ok.end = Link('parent', 'end', edgeM);
      ok.top = Link('bottom', 'bottom', bgap);
      if (r.p(0.4)) {
        ok.bottom = Link('parent', 'bottom', edgeM);
        ok.vBias = r.pick(const [0.0, 1.0, 0.5, 0.9]);
      }
      specs.add(ok);
    case 2:
      // Packed chain at the end.
      final cancel = box(
        'cancel',
        r.pick(const [80, 88, 72, 75]),
        36,
        wrap: r.p(0.5),
      );
      final ok = box('ok', r.pick(const [64, 88, 96, 77]), 36, wrap: r.p(0.5));
      cancel.start = Link('parent', 'start', edgeM);
      cancel.end = Link('ok', 'start', r.pick(const [0, 8]));
      ok.start = Link('cancel', 'end', r.pick(const [0, 8]));
      ok.end = Link('parent', 'end', edgeM);
      cancel.hChain = 2;
      cancel.hBias = r.pick(const [1.0, 1.0, 0.5, 0.0, 0.7]);
      cancel.top = Link('bottom', 'bottom', bgap);
      ok.top = Link('cancel', 'top');
      if (r.p(0.4)) ok.baseline = null;
      specs.addAll([cancel, ok]);
    case 3:
      // Spread chain of buttons.
      final n = r.range(2, 3);
      final ids = [for (var k = 0; k < n; k++) 'btn$k'];
      final style = r.pick(const [0, 1, 2]);
      for (var k = 0; k < n; k++) {
        final b = box(
          ids[k],
          r.range(48, 120),
          r.pick(const [36, 40]),
          wrap: r.p(0.3),
        );
        if (r.p(0.3)) {
          b.width = const Dim.match();
          if (r.p(0.5)) b.hWeight = r.pick(const [1.0, 2.0, 1.0, 3.0]);
        }
        b.start = k == 0
            ? Link('parent', 'start', edgeM)
            : Link(ids[k - 1], 'end', r.pick(const [0, 8]));
        b.end = k == n - 1
            ? Link('parent', 'end', edgeM)
            : Link(ids[k + 1], 'start', r.pick(const [0, 8]));
        b.top = Link('bottom', 'bottom', bgap);
        if (k == 0) b.hChain = style;
        specs.add(b);
      }
    default:
      final ok = box('ok', r.pick(const [88, 96]), 36);
      final cancel = box('cancel', r.pick(const [80, 88]), 36);
      ok.end = Link('parent', 'end', edgeM);
      ok.top = Link('bottom', 'bottom', bgap);
      cancel.end = Link('ok', 'start', 8);
      cancel.top = Link('ok', 'top');
      if (r.p(0.3)) cancel.vis = 8;
      specs.addAll([ok, cancel]);
  }
  return emit(
    w,
    h,
    order(r, specs),
    ltr: ltr,
    wrapH: r.p(0.03),
    wrapW: r.p(0.02),
  );
}

// ---------------------------------------------------------------------------
// vprofile: a profile header with a cover, an avatar, names, a follow button,
// stats and tabs.
// ---------------------------------------------------------------------------
List<String> genVProfile(int seed) {
  final r = R(seed);
  final w = r.range(300, 1000);
  final h = r.range(500, 1400);
  final ltr = r.p(0.65);
  final specs = <Spec>[];
  final edgeM = r.pick(const [16, 12, 24, 8]);
  final cover = Spec.widget('cover', w, r.range(100, 240));
  cover.width = const Dim.match();
  cover.start = Link('parent', 'start');
  cover.end = Link('parent', 'end');
  cover.top = Link('parent', 'top');
  if (r.p(0.12)) {
    cover.height = const Dim.match();
    cover.ratio = r.pick(const [1.7777778, 2.0, 3.0, 2.5, 1.5]);
  } else {
    cover.height = Dim.fixed(cover.ih);
  }
  final hasCover = r.p(0.8);
  if (hasCover) specs.add(cover);
  final av = r.pick(const [48, 56, 64, 72, 80, 96, 57, 63]);
  final avatar = box('avatar', av, av);
  avatar.start = Link('parent', 'start', edgeM);
  if (hasCover) {
    switch (r.i(3)) {
      case 0:
        avatar.top = Link('cover', 'bottom', -av ~/ 2);
      case 1:
        avatar.top = Link('cover', 'bottom');
        avatar.bottom = Link('cover', 'bottom');
      default:
        avatar.top = Link('cover', 'bottom', r.pick(const [8, 12, 16]));
    }
  } else {
    avatar.top = Link('parent', 'top', edgeM);
  }
  specs.add(avatar);
  final name = text(r, 'name', h: r.pick(const [20, 22, 24, 26]));
  name.start = Link('avatar', 'end', r.pick(const [8, 12, 16]));
  final handle = text(r, 'handle', h: r.pick(const [14, 16]));
  handle.start = Link('name', 'start');
  handle.top = Link('name', 'bottom', r.pick(const [0, 2, 4]));
  if (r.p(0.3)) handle.vis = 8;
  switch (r.i(3)) {
    case 0:
      name.top = hasCover
          ? Link('cover', 'bottom', r.pick(const [4, 8, 12]))
          : Link('avatar', 'top');
    case 1:
      // name + handle as a packed vertical chain centered on the avatar.
      name.top = Link('avatar', 'top');
      name.bottom = Link('handle', 'top');
      handle.top = Link('name', 'bottom');
      handle.bottom = Link('avatar', 'bottom');
      name.vChain = 2;
      name.vBias = r.pick(const [0.5, 0.5, 0.0, 0.4]);
    default:
      name.top = Link('avatar', 'top');
      name.bottom = Link('avatar', 'bottom');
      name.vBias = r.pick(const [0.5, 0.3, 0.0]);
  }
  specs.addAll([name, handle]);
  final follow = box(
    'follow',
    r.pick(const [88, 96, 100, 72]),
    r.pick(const [32, 36, 40]),
    wrap: r.p(0.5),
  );
  follow.end = Link('parent', 'end', edgeM);
  final hasFollow = r.p(0.8);
  if (hasFollow) {
    switch (r.i(3)) {
      case 0:
        follow.top = Link('avatar', 'top');
        follow.bottom = Link('avatar', 'bottom');
      case 1:
        follow.top = hasCover
            ? Link('cover', 'bottom', 12)
            : Link('parent', 'top', 12);
      default:
        follow.baseline = Link('name', 'baseline');
        follow.iw;
    }
    if (follow.baseline != null) {
      // a button has a baseline
      specs.add(
        Spec.widget('follow', follow.iw, follow.ih, baselineDist: 24)
          ..width = follow.width
          ..height = follow.height
          ..end = follow.end
          ..baseline = follow.baseline,
      );
    } else {
      specs.add(follow);
    }
    if (r.p(0.5)) {
      name.end = Link('follow', 'start', 8);
      name.hBias = 0;
      if (r.p(0.5)) name.width = const Dim.match();
    }
  }
  final headRefs = ['avatar', 'name', 'handle', if (hasFollow) 'follow'];
  final head = Spec.barrier(
    'head',
    'bottom',
    headRefs,
    margin: r.pick(const [0, 8, 12, 16]),
    allowsGone: r.p(0.7),
  );
  specs.add(head);
  // Bio.
  final bio = Spec.widget(
    'bio',
    r.range(100, 600),
    r.pick(const [20, 40, 60, 80, 37, 53]),
  );
  bio.width = r.p(0.6) ? const Dim.match() : const Dim.wrap();
  bio.height = const Dim.wrap();
  bio.start = Link('parent', 'start', edgeM);
  if (bio.width!.b == 'M') bio.end = Link('parent', 'end', edgeM);
  bio.top = Link('head', 'bottom', r.pick(const [0, 8, 12]));
  if (r.p(0.2)) bio.vis = 8;
  specs.add(bio);
  // Stats: counters in a chain, labels centered under them.
  final n = r.range(2, 4);
  final style = r.pick(const [0, 1, 2, 0]);
  final statRefs = <String>[];
  for (var k = 0; k < n; k++) {
    final c = text(
      r,
      'count$k',
      w: r.range(16, 60),
      h: r.pick(const [20, 22, 24]),
    );
    final chainM = !ltr || r.p(0.5) ? 0 : edgeM;
    c.start = k == 0
        ? Link('parent', 'start', chainM)
        : Link('count${k - 1}', 'end');
    c.end = k == n - 1
        ? Link('parent', 'end', chainM)
        : Link('count${k + 1}', 'start');
    c.top = Link(
      r.p(0.5) ? 'bio' : 'head',
      'bottom',
      r.pick(const [12, 16, 8]),
    );
    if (k == 0) {
      c.hChain = style;
      if (style == 2) c.hBias = r.bias();
    }
    final l = text(
      r,
      'clabel$k',
      w: r.range(30, 90),
      h: r.pick(const [12, 14]),
    );
    l.start = Link('count$k', 'start');
    if (r.p(0.4)) l.end = Link('count$k', 'end');
    l.top = Link('count$k', 'bottom', 2);
    specs.addAll([c, l]);
    statRefs.addAll([c.id, l.id]);
  }
  final stats = Spec.barrier(
    'stats',
    'bottom',
    statRefs,
    margin: r.pick(const [0, 8, 16]),
  );
  specs.add(stats);
  // Tabs.
  final tabs = r.range(0, 4);
  for (var k = 0; k < tabs; k++) {
    final t = Spec.widget('tab$k', r.range(40, 120), 48);
    t.width = r.p(0.7) ? const Dim.match() : const Dim.wrap();
    t.height = Dim.fixed(48);
    t.start = k == 0 ? Link('parent', 'start') : Link('tab${k - 1}', 'end');
    t.end = k == tabs - 1
        ? Link('parent', 'end')
        : Link('tab${k + 1}', 'start');
    t.top = Link('stats', 'bottom', r.pick(const [0, 8]));
    if (tabs == 1) t.end = null;
    specs.add(t);
  }
  return emit(w, h, order(r, specs), ltr: ltr);
}

// ---------------------------------------------------------------------------
// vcard: a list card with an image, texts, meta column and actions.
// ---------------------------------------------------------------------------
List<String> genVCard(int seed) {
  final r = R(seed);
  final w = r.range(260, 900);
  final h = r.range(120, 700);
  final ltr = r.p(0.65);
  final specs = <Spec>[];
  final pad = r.pick(const [12, 16, 8, 10, 14]);
  final image = Spec.widget('image', r.range(48, 140), r.range(48, 140));
  image.start = Link('parent', 'start', pad);
  image.top = Link('parent', 'top', pad);
  switch (r.i(4)) {
    case 0:
      image.width = Dim.fixed(image.iw);
      image.height = Dim.fixed(image.ih);
    case 1:
      image.width = Dim.fixed(image.iw);
      image.height = const Dim.match();
      image.ratio = r.pick(const [1.0, 1.3333334, 0.75, 1.5]);
    case 2:
      image.width = Dim.match(pct: r.pick(const [0.25, 0.3, 0.33, 0.2, 0.35]));
      image.height = Dim.fixed(image.ih);
    default:
      image.width = Dim.fixed(image.iw);
      image.height = const Dim.match();
      image.bottom = Link('parent', 'bottom', pad);
      image.vBias = 0;
  }
  if (r.p(0.1)) image.vis = 8;
  specs.add(image);
  // Meta column at the end: timestamp and an icon.
  final hasMeta = r.p(0.6);
  if (hasMeta) {
    final time = text(r, 'time', w: r.range(24, 80), h: r.pick(const [12, 14]));
    time.end = Link('parent', 'end', pad);
    time.top = Link('parent', 'top', pad);
    final icon = box(
      'icon',
      r.pick(const [16, 20, 24]),
      r.pick(const [16, 20, 24]),
    );
    icon.end = Link('parent', 'end', pad);
    icon.top = Link('time', 'bottom', 4);
    if (r.p(0.3)) icon.vis = 8;
    specs.addAll([time, icon]);
    specs.add(
      Spec.barrier('metaStart', 'start', [
        'time',
        'icon',
      ], margin: r.pick(const [0, 8, 12])),
    );
  }
  final title = text(r, 'title', h: r.pick(const [18, 20, 22]));
  title.start = Link('image', 'end', r.pick(const [8, 12, 16]));
  title.top = Link('image', 'top');
  if (r.p(0.7)) {
    title.width = const Dim.match();
    title.end = hasMeta
        ? Link('metaStart', 'start')
        : Link('parent', 'end', pad);
  } else if (r.p(0.5)) {
    title.end = hasMeta
        ? Link('metaStart', 'start')
        : Link('parent', 'end', pad);
    title.hBias = r.pick(const [0.0, 0.0, 0.5, 0.3]);
  }
  final sub = text(r, 'sub', h: r.pick(const [14, 16, 32, 48]));
  sub.start = Link('title', 'start');
  sub.top = Link('title', 'bottom', r.pick(const [2, 4]));
  if (r.p(0.5)) {
    sub.width = const Dim.match();
    sub.end = Link('title', 'end');
  }
  if (r.p(0.2)) sub.vis = 8;
  final price = text(r, 'price', h: r.pick(const [20, 24, 18]));
  price.start = Link('title', 'start');
  price.top = Link(
    'sub',
    'bottom',
    r.pick(const [4, 8]),
    r.pick(const [0, 0, 8]),
  );
  final rating = text(r, 'rating', h: r.pick(const [14, 16]));
  rating.start = Link('price', 'end', 8);
  rating.baseline = Link('price', 'baseline');
  if (r.p(0.15)) rating.vis = 8;
  specs.addAll([title, sub, price, rating]);
  final textBottom = Spec.barrier(
    'textBottom',
    'bottom',
    [
      'image',
      'title',
      'sub',
      'price',
      'rating',
      if (hasMeta && r.p(0.3)) 'icon',
    ],
    margin: r.pick(const [0, 8, 12]),
    allowsGone: r.p(0.6),
  );
  specs.add(textBottom);
  // Badge on the image's corner.
  if (r.p(0.4)) {
    final badge = box(
      'badge',
      r.pick(const [16, 18, 20, 24, 15]),
      r.pick(const [16, 18, 20, 15]),
    );
    badge.start = Link('image', 'end');
    badge.end = Link('image', 'end');
    badge.top = Link('image', 'top');
    badge.bottom = Link('image', 'top');
    specs.add(badge);
  }
  // Divider and actions.
  var actionsTop = 'textBottom';
  if (r.p(0.4)) {
    final div = Spec.widget('div', 100, 1);
    div.width = const Dim.match();
    div.height = Dim.fixed(1);
    div.start = Link('parent', 'start', r.pick([0, pad]));
    div.end = Link('parent', 'end');
    div.top = Link('textBottom', 'bottom', 8);
    specs.add(div);
    actionsTop = 'div';
  }
  final na = r.range(0, 3);
  for (var k = 0; k < na; k++) {
    final a = box('act$k', r.range(48, 100), 36, wrap: r.p(0.5));
    a.top = Link(actionsTop, 'bottom', 8);
    if (k == 0) {
      a.end = Link('parent', 'end', pad);
    } else {
      a.end = Link('act${k - 1}', 'start', 8);
    }
    if (r.p(0.2)) a.vis = 8;
    if (r.p(0.3)) {
      a.bottom = Link('parent', 'bottom', pad);
      a.vBias = r.pick(const [0.0, 1.0, 0.5]);
    }
    specs.add(a);
  }
  return emit(w, h, order(r, specs), ltr: ltr);
}

// ---------------------------------------------------------------------------
// vtoolbar: an app bar with leading and trailing actions, a title between
// two barriers, and content below a bottom barrier.
// ---------------------------------------------------------------------------
List<String> genVToolbar(int seed) {
  final r = R(seed);
  final w = r.range(240, 1200);
  final h = r.range(56, 900);
  final ltr = r.p(0.6);
  final specs = <Spec>[];
  final barH = r.pick(const [48, 56, 64, 72, 57]);
  final leads = <String>[];
  final nLead = r.range(0, 2);
  for (var k = 0; k < nLead; k++) {
    final s = r.pick(const [24, 32, 40, 48, 36]);
    final l = box('lead$k', s, s);
    l.start = k == 0
        ? Link('parent', 'start', r.pick(const [4, 8, 16]))
        : Link('lead${k - 1}', 'end', 4);
    l.top = Link('parent', 'top');
    l.bottom = Link('parent', 'top', -barH);
    if (r.p(0.15)) l.vis = 8;
    specs.add(l);
    leads.add(l.id);
  }
  // A bar background as a fixed-height strip, so the content has an edge.
  final bar = Spec.widget('bar', w, barH);
  bar.width = const Dim.match();
  bar.height = Dim.fixed(barH);
  bar.start = Link('parent', 'start');
  bar.end = Link('parent', 'end');
  bar.top = Link('parent', 'top');
  specs.insert(0, bar);
  // Fix the leading icons' vertical centering on the bar.
  for (final s in specs) {
    if (s.id.startsWith('lead')) {
      s.top = Link('bar', 'top');
      s.bottom = Link('bar', 'bottom');
    }
  }
  final nAct = r.range(0, 3);
  final acts = <String>[];
  for (var k = 0; k < nAct; k++) {
    final s = r.pick(const [24, 40, 48, 32]);
    final a = box('act$k', s, s);
    a.end = k == 0
        ? Link('parent', 'end', r.pick(const [4, 8, 16]))
        : Link('act${k - 1}', 'start', r.pick(const [0, 4, 8]));
    a.top = Link('bar', 'top');
    a.bottom = Link('bar', 'bottom');
    if (r.p(0.15)) a.vis = 8;
    specs.add(a);
    acts.add(a.id);
  }
  final leadEnd = Spec.barrier(
    'leadEnd',
    'end',
    leads,
    margin: r.pick(const [0, 8, 16, 12]),
    allowsGone: r.p(0.5),
  );
  final actStart = Spec.barrier(
    'actStart',
    'start',
    acts,
    margin: r.pick(const [0, 8, 16]),
    allowsGone: r.p(0.5),
  );
  specs.addAll([leadEnd, actStart]);
  final title = text(r, 'title', h: r.pick(const [20, 22, 24, 21]));
  switch (r.i(4)) {
    case 0:
      title.start = Link('leadEnd', 'end');
      title.end = Link('actStart', 'start');
      title.hBias = r.pick(const [0.0, 0.5, 0.5, 0.0, 0.3]);
    case 1:
      title.width = const Dim.match();
      title.start = Link('leadEnd', 'end');
      title.end = Link('actStart', 'start');
    case 2:
      title.start = Link('parent', 'start');
      title.end = Link('parent', 'end');
    default:
      title.start = Link('leadEnd', 'end', r.pick(const [0, 16]));
  }
  final hasSub = r.p(0.4);
  if (hasSub) {
    final sub = text(r, 'subtitle', h: r.pick(const [14, 16]));
    sub.start = Link('title', 'start');
    if (r.p(0.4)) sub.end = Link('title', 'end');
    title.top = Link('bar', 'top');
    title.bottom = Link('subtitle', 'top');
    sub.top = Link('title', 'bottom');
    sub.bottom = Link('bar', 'bottom');
    title.vChain = 2;
    if (r.p(0.3)) sub.vis = 8;
    specs.addAll([title, sub]);
  } else {
    title.top = Link('bar', 'top');
    title.bottom = Link('bar', 'bottom');
    specs.add(title);
  }
  final barBottom = Spec.barrier('barBottom', 'bottom', [
    'bar',
    ...leads,
    ...acts,
    'title',
    if (hasSub) 'subtitle',
  ], margin: r.pick(const [0, 0, 8]));
  specs.add(barBottom);
  // Content: a few rows below the bar.
  final rows = r.range(0, 4);
  var prev = 'barBottom';
  for (var k = 0; k < rows; k++) {
    final icon = box('ricon$k', 40, 40);
    icon.start = Link('parent', 'start', 16);
    icon.top = Link(prev, 'bottom', r.pick(const [8, 12, 16]));
    final t = text(r, 'rtext$k');
    t.start = Link('ricon$k', 'end', 16);
    t.top = Link('ricon$k', 'top');
    t.bottom = Link('ricon$k', 'bottom');
    if (r.p(0.5)) {
      t.end = Link('parent', 'end', 16);
      t.hBias = 0;
      if (r.p(0.5)) t.width = const Dim.match();
    }
    final rb = Spec.barrier('rb$k', 'bottom', ['ricon$k', 'rtext$k']);
    specs.addAll([icon, t, rb]);
    prev = 'rb$k';
  }
  return emit(w, h, order(r, specs), ltr: ltr);
}

// ---------------------------------------------------------------------------
// vgrid: a table laid out with column and row barriers, barriers over
// barriers, headers centered over columns.
// ---------------------------------------------------------------------------
List<String> genVGrid(int seed) {
  final r = R(seed);
  final w = r.range(300, 1200);
  final h = r.range(300, 1200);
  final ltr = r.p(0.65);
  final specs = <Spec>[];
  final rows = r.range(1, 4);
  final cols = r.range(1, 4);
  final gap = r.pick(const [4, 8, 12, 16, 0, 5]);
  final cells = List.generate(rows, (_) => List<String>.filled(cols, ''));
  final chainBarriers = r.p(
    0.5,
  ); // column barrier j also references barrier j-1
  for (var i = 0; i < rows; i++) {
    for (var j = 0; j < cols; j++) {
      final id = 'c${i}_$j';
      cells[i][j] = id;
      final c = r.p(0.5)
          ? text(r, id)
          : box(id, r.range(16, 120), r.range(14, 60), wrap: r.p(0.5));
      c.start = j == 0
          ? Link('parent', 'start', gap)
          : Link('col${j - 1}', 'end', gap);
      c.top = i == 0
          ? Link('parent', 'top', gap)
          : Link('row${i - 1}', 'bottom', gap);
      if (r.p(0.1)) c.vis = 8;
      if (r.p(0.15) && j > 0 && c.baselineDist > 0) {
        final first = specs.firstWhere((s) => s.id == cells[i][0]);
        if (first.baselineDist > 0) {
          c.top = null;
          c.baseline = Link(first.id, 'baseline');
        }
      }
      specs.add(c);
    }
  }
  for (var j = 0; j < cols; j++) {
    final refs = [for (var i = 0; i < rows; i++) cells[i][j]];
    if (chainBarriers && j > 0) refs.add('col${j - 1}');
    specs.add(
      Spec.barrier(
        'col$j',
        'end',
        refs,
        margin: r.pick(const [0, 0, 4, 8]),
        allowsGone: r.p(0.6),
      ),
    );
  }
  for (var i = 0; i < rows; i++) {
    final refs = [for (var j = 0; j < cols; j++) cells[i][j]];
    if (r.p(0.4) && i > 0) refs.add('row${i - 1}');
    specs.add(
      Spec.barrier(
        'row$i',
        'bottom',
        refs,
        margin: r.pick(const [0, 0, 4]),
        allowsGone: r.p(0.6),
      ),
    );
  }
  // A footer centered under the table, between the first and last columns.
  if (r.p(0.6)) {
    final f = text(r, 'foot');
    f.start = Link('parent', 'start');
    f.end = Link('col${cols - 1}', 'end');
    f.hBias = r.bias();
    f.top = Link('row${rows - 1}', 'bottom', gap);
    if (r.p(0.3)) {
      f.width = Dim.match(pct: r.pct());
    }
    specs.add(f);
  }
  // A side note vertically centered on the table.
  if (r.p(0.5)) {
    final n = box('note', r.range(20, 80), r.range(20, 80));
    n.start = Link('col${cols - 1}', 'end', gap);
    n.end = Link('parent', 'end', gap);
    n.hBias = r.bias();
    n.top = Link('parent', 'top');
    n.bottom = Link('row${rows - 1}', 'bottom');
    n.vBias = r.bias();
    if (r.p(0.3)) {
      n.height = Dim.match(
        min: r.p(0.5) ? r.range(10, 60) : 0,
        max: r.p(0.5) ? r.range(20, 90) : 0,
      );
    }
    specs.add(n);
  }
  return emit(w, h, order(r, specs), ltr: ltr);
}

// ---------------------------------------------------------------------------
// vcenter: widgets centered between barrier edges, guidelines, the parent
// and each other, with odd sizes, biases, percent sizes, bounds, negative
// margins and gone widgets, and barriers over them.
// ---------------------------------------------------------------------------
List<String> genVCenter(int seed) {
  final r = R(seed);
  final w = r.range(200, 1000);
  final h = r.range(200, 1000);
  final ltr = r.p(0.65);
  final specs = <Spec>[];
  // Seeds: a few anchored widgets.
  final seeds = r.range(1, 3);
  final pool = <String>[]; // widget ids
  for (var k = 0; k < seeds; k++) {
    final s = r.p(0.5)
        ? text(r, 's$k')
        : box('s$k', r.range(10, 150), r.range(10, 150), wrap: r.p(0.3));
    s.start = Link('parent', 'start', r.range(0, 120));
    s.top = Link('parent', 'top', r.range(0, 200));
    if (r.p(0.3)) {
      s.end = Link('parent', 'end', r.range(0, 120));
      s.hBias = r.bias();
    }
    if (r.p(0.2)) s.vis = 8;
    specs.add(s);
    pool.add(s.id);
  }
  final guides = <String>[];
  if (r.p(0.5)) {
    final g = Spec.guideline('gv', false, gPct: r.pct());
    if (r.p(0.3)) {
      g.gPct = null;
      g.gBegin = r.range(20, w ~/ 2);
    }
    specs.add(g);
    guides.add('gv');
  }
  if (r.p(0.4)) {
    final g = Spec.guideline('gh', true, gPct: r.pct());
    specs.add(g);
  }
  final barriers = <String, String>{}; // id -> edge
  void addBarrier(String id) {
    final edge = r.pick(const [
      'start',
      'end',
      'top',
      'bottom',
      'left',
      'right',
      'bottom',
      'end',
    ]);
    final n = r.range(1, min(3, pool.length));
    final refs = <String>{};
    for (var k = 0; k < n; k++) {
      refs.add(r.pick(pool));
    }
    if (barriers.isNotEmpty && r.p(0.3)) {
      // a barrier over a barrier of the same orientation
      final same = barriers.entries
          .where((e) => _horizontal(e.value) == _horizontal(edge))
          .map((e) => e.key)
          .toList();
      if (same.isNotEmpty) refs.add(r.pick(same));
    }
    if (_horizontal(edge) && guides.isNotEmpty && r.p(0.2)) refs.add('gv');
    specs.add(
      Spec.barrier(
        id,
        edge,
        refs.toList(),
        margin: r.pick(const [0, 0, 0, 4, 8, 12, -4, 16, 3]),
        allowsGone: r.p(0.7),
      ),
    );
    barriers[id] = edge;
  }

  addBarrier('b0');
  // Centered widgets, each between two targets read from what exists.
  final count = r.range(2, 6);
  for (var k = 0; k < count; k++) {
    if (k > 0 && r.p(0.35)) addBarrier('b${barriers.length}');
    final id = 'w$k';
    final s = r.p(0.4)
        ? text(r, id)
        : box(id, r.range(5, 160), r.range(5, 160), wrap: r.p(0.3));
    // Horizontal.
    Link hTarget(bool startSide) {
      final opts = <Link>[
        Link('parent', startSide ? 'start' : 'end', r.margin()),
      ];
      for (final e in barriers.entries) {
        if (_horizontal(e.value)) {
          opts.add(Link(e.key, r.pick(const ['start', 'end']), r.margin()));
        }
      }
      for (final p in pool) {
        opts.add(Link(p, r.pick(const ['start', 'end']), r.margin()));
      }
      for (final g in guides) {
        opts.add(Link(g, 'start', r.margin()));
      }
      return r.pick(opts);
    }

    Link vTarget(bool topSide) {
      final opts = <Link>[
        Link('parent', topSide ? 'top' : 'bottom', r.margin()),
      ];
      for (final e in barriers.entries) {
        if (!_horizontal(e.value)) {
          opts.add(Link(e.key, r.pick(const ['top', 'bottom']), r.margin()));
        }
      }
      for (final p in pool) {
        opts.add(Link(p, r.pick(const ['top', 'bottom']), r.margin()));
      }
      if (specs.any((x) => x.id == 'gh')) {
        opts.add(Link('gh', 'top', r.margin()));
      }
      return r.pick(opts);
    }

    Link neg(Link l) =>
        r.p(0.12) ? Link(l.target, l.edge, -r.range(1, 20), l.gone) : l;
    s.start = neg(hTarget(true));
    if (r.p(0.8)) {
      s.end = neg(hTarget(false));
      s.hBias = r.bias();
    }
    s.top = neg(vTarget(true));
    if (r.p(0.7)) {
      s.bottom = neg(vTarget(false));
      s.vBias = r.bias();
    }
    // Sizes.
    if (s.end != null && r.p(0.35)) {
      s.width = switch (r.i(3)) {
        0 => Dim.match(pct: r.pct()),
        1 => Dim.match(
          min: r.p(0.5) ? r.range(5, 100) : 0,
          max: r.p(0.6) ? r.range(10, 200) : 0,
        ),
        _ => const Dim.match(),
      };
    }
    if (s.bottom != null && r.p(0.3)) {
      s.height = switch (r.i(3)) {
        0 => Dim.match(pct: r.pct()),
        1 => Dim.match(
          min: r.p(0.5) ? r.range(5, 100) : 0,
          max: r.p(0.6) ? r.range(10, 200) : 0,
        ),
        _ => const Dim.match(),
      };
    }
    if (r.p(0.08) && s.width?.b != 'M') {
      s.height = const Dim.match();
      s.ratio = r.pick(const [1.0, 1.5, 0.5, 2.0, 1.7777778, 1.3333334]);
    }
    if (r.p(0.15) && s.baselineDist > 0) {
      final texts = specs
          .where((x) => x.kind == Kind.widget && x.baselineDist > 0)
          .toList();
      if (texts.isNotEmpty) {
        s.top = null;
        s.bottom = null;
        s.baseline = Link(
          r.pick(texts).id,
          'baseline',
          r.p(0.2) ? r.range(-5, 10) : 0,
        );
      }
    }
    if (r.p(0.1)) s.vis = 8;
    if (r.p(0.04)) s.vis = 4;
    // gone margins sometimes
    if (r.p(0.1) && s.start != null) {
      s.start = Link(
        s.start!.target,
        s.start!.edge,
        s.start!.margin,
        r.range(1, 30),
      );
    }
    specs.add(s);
    pool.add(id);
  }
  // A last barrier over some centered widgets, and a follower.
  addBarrier('b${barriers.length}');
  final last = barriers.keys.last;
  final f = box('follow', r.range(10, 80), r.range(10, 80));
  if (_horizontal(barriers[last]!)) {
    f.start = Link(last, 'end', r.margin());
    f.top = Link('parent', 'top', r.margin());
    if (r.p(0.4)) {
      f.end = Link('parent', 'end', r.margin());
      f.hBias = r.bias();
    }
  } else {
    f.top = Link(last, 'bottom', r.margin());
    f.start = Link('parent', 'start', r.margin());
    if (r.p(0.4)) {
      f.bottom = Link('parent', 'bottom', r.margin());
      f.vBias = r.bias();
    }
  }
  specs.add(f);
  return emit(w, h, order(r, specs), ltr: ltr);
}

bool _horizontal(String edge) =>
    const {'start', 'end', 'left', 'right'}.contains(edge);

// ---------------------------------------------------------------------------
// vadv: raw engine calls. Random widgets of every behaviour, links in every
// direction (forward, backward, crossed, to barriers and guidelines),
// chains, baselines, barriers over barriers and guidelines, barrier
// margins of both signs, gone and invisible widgets, re-links that leave
// stale dependents, resets, and a shuffled add order.
// ---------------------------------------------------------------------------
List<String> genVAdv(int seed) {
  final r = R(seed);
  final W = r.range(100, 1200);
  final H = r.range(100, 1200);
  final ops = <String>['R $W $H'];
  if (r.p(0.3)) ops.add('rtl');
  if (r.p(0.04)) ops.add('wrapw');
  if (r.p(0.04)) ops.add('wraph');
  final nw = r.range(2, 9);
  final nb = r.range(1, 4);
  final ng = r.range(0, 2);
  final ws = [for (var k = 0; k < nw; k++) 'w$k'];
  final bs = [for (var k = 0; k < nb; k++) 'b$k'];
  final gs = [for (var k = 0; k < ng; k++) 'g$k'];
  final created = <String>[];
  for (final id in ws) {
    ops.add('w $id ${r.range(0, 200)} ${r.range(0, 200)}');
    if (r.p(0.35)) ops.add('bl $id ${r.range(1, 40)}');
    created.add(id);
  }
  final gOrient = <String, int>{};
  for (final id in gs) {
    ops.add('g $id');
    final o = r.i(2);
    gOrient[id] = o;
    ops.add('go $id $o');
    switch (r.i(3)) {
      case 0:
        ops.add('gb $id ${r.range(0, 300)}');
      case 1:
        ops.add('ge $id ${r.range(0, 300)}');
      default:
        ops.add('gp $id ${r.pct()}');
    }
    created.add(id);
  }
  final bType = <String, int>{};
  for (final id in bs) {
    ops.add('b $id');
    final t = r.i(4);
    bType[id] = t;
    ops.add('bt $id $t');
    if (r.p(0.4)) {
      ops.add('bm $id ${r.pick(const [-8, -3, 4, 8, 12, 16, 1, 30])}');
    }
    if (r.p(0.3)) ops.add('bg $id 0');
    created.add(id);
  }
  // Add order.
  final addOrder = [...created];
  if (r.p(0.6)) addOrder.shuffle(r.r);
  for (final id in addOrder) {
    ops.add('add $id');
  }
  // Barrier references.
  final dagRefs = r.p(0.7);
  final rank = <String, int>{for (final b in bs) b: r.range(1, nw)};
  for (final id in bs) {
    final horizontal = bType[id]! < 2;
    final n = r.range(1, 4);
    for (var k = 0; k < n; k++) {
      final pool = dagRefs ? ws.sublist(0, rank[id]!) : ws;
      final c = r.p(0.12) && bs.length > 1
          ? r.pick(bs.where((b) => b != id).toList())
          : (r.p(0.1) && gs.isNotEmpty ? r.pick(gs) : r.pick(pool));
      if (gOrient.containsKey(c) &&
          (gOrient[c] == 1) != horizontal &&
          r.p(0.8)) {
        continue;
      }
      ops.add('ref $id $c');
    }
  }
  // In DAG mode a widget only links to the root, guidelines, earlier
  // widgets and barriers over earlier widgets only.
  final dag = r.p(0.7);
  final barrierRank = <String, int>{};
  for (final b in bs) {
    barrierRank[b] = rank[b]!;
  }
  List<String> earlier(String self) {
    final k = ws.indexOf(self);
    return dag
        ? ws.sublist(0, k < 0 ? 0 : k)
        : ws.where((x) => x != self).toList();
  }

  bool barrierOk(String b, String self) =>
      !dag ||
      !dagRefs ||
      barrierRank[b]! <= (!ws.contains(self) ? nw : ws.indexOf(self));

  String hTarget(String self) {
    final opts = <String>['root', 'root', ...earlier(self)];
    opts.addAll(bs.where((b) => bType[b]! < 2 && barrierOk(b, self)));
    opts.addAll(gs.where((g) => gOrient[g] == 1));
    return r.pick(opts);
  }

  String vTarget(String self) {
    final opts = <String>['root', 'root', ...earlier(self)];
    opts.addAll(bs.where((b) => bType[b]! >= 2 && barrierOk(b, self)));
    opts.addAll(gs.where((g) => gOrient[g] == 0));
    return r.pick(opts);
  }

  int m() => r.p(0.1)
      ? -r.range(1, 30)
      : r.pick(const [0, 0, 0, 4, 8, 16, 3, 7, 11, 24]);
  String side(String t, bool h) {
    if (gOrient.containsKey(t)) return h ? 'L' : 'T';
    return h ? r.pick(const ['L', 'R']) : r.pick(const ['T', 'B']);
  }

  // Chains: link consecutive widgets both ways sometimes.
  final chainH = r.p(0.2);
  final chainV = r.p(0.15);
  for (var k = 0; k < nw; k++) {
    final id = ws[k];
    // Behaviours.
    for (final h in [true, false]) {
      final b = r.pick(const ['F', 'F', 'W', 'W', 'M', 'M', 'P']);
      if (b == 'P' && r.p(0.7)) continue;
      ops.add('${h ? 'h' : 'v'}b $id $b');
      if (b == 'M') {
        final style = r.pick(const [0, 0, 0, 2, 2]);
        final mn = r.p(0.2) ? r.range(1, 120) : 0;
        final mx = r.p(0.2) ? r.range(1, 220) : 0;
        ops.add(
          '${h ? 'h' : 'v'}m $id $style $mn $mx ${style == 2 ? r.pct() : 1.0}',
        );
      }
      if (r.p(0.08)) ops.add('${h ? 'mw' : 'mh'} $id ${r.range(1, 80)}');
    }
    if (r.p(0.08)) {
      ops.add(
        'ra $id ${r.pick(const [1.0, 1.5, 0.5, 2.0, 1.7777778])} ${r.pick(const [-1, -1, 0, 1])}',
      );
    }
    if (r.p(0.4)) ops.add('hx $id ${r.bias()}');
    if (r.p(0.4)) ops.add('vx $id ${r.bias()}');
    if (r.p(0.12)) ops.add('v $id 8');
    if (r.p(0.04)) ops.add('v $id 4');
    // Horizontal links.
    final hl = r.pick(const [0, 1, 1, 2, 2, 2]);
    if (chainH && k > 0 && r.p(0.6)) {
      ops.add('c $id L ${ws[k - 1]} R ${m()}');
      ops.add('c ${ws[k - 1]} R $id L ${m()}');
      if (r.p(0.3)) ops.add('hc ${ws[k - 1]} ${r.i(3)}');
      if (r.p(0.2)) ops.add('hw $id ${r.pick(const [1.0, 2.0, 0.5])}');
    } else {
      if (hl >= 1) {
        final t = hTarget(id);
        ops.add('c $id L $t ${side(t, true)} ${m()}');
      }
      if (hl >= 2 || (hl == 1 && r.p(0.3))) {
        final t = hTarget(id);
        ops.add('c $id R $t ${side(t, true)} ${m()}');
      }
    }
    final vl = r.pick(const [0, 1, 1, 2, 2, 2, 3]);
    if (chainV && k > 0 && r.p(0.6)) {
      ops.add('c $id T ${ws[k - 1]} B ${m()}');
      ops.add('c ${ws[k - 1]} B $id T ${m()}');
      if (r.p(0.3)) ops.add('vc ${ws[k - 1]} ${r.i(3)}');
    } else if (vl == 3) {
      final t = r.pick(ws.where((x) => x != id).toList());
      ops.add('c $id S $t S ${r.p(0.2) ? m() : 0}');
    } else {
      if (vl >= 1) {
        final t = vTarget(id);
        ops.add('c $id T $t ${side(t, false)} ${m()}');
      }
      if (vl >= 2) {
        final t = vTarget(id);
        ops.add('c $id B $t ${side(t, false)} ${m()}');
      }
    }
    if (r.p(0.1)) {
      ops.add('gm $id ${r.pick(const ['L', 'R', 'T', 'B'])} ${r.range(1, 40)}');
    }
  }
  // Re-links (stale dependents) and resets.
  if (r.p(0.15)) {
    final id = r.pick(ws);
    final t = hTarget(id);
    ops.add('c $id L $t ${side(t, true)} ${m()}');
  }
  if (r.p(0.08)) {
    ops.add('x ${r.pick(ws)} ${r.pick(const ['L', 'R', 'T', 'B'])}');
  }
  return ops;
}

// ---------------------------------------------------------------------------
// vext: features the other generators use little: center-x/center-y and
// center links, match-parent widgets, ratios with a side, invisible widgets,
// gone barriers, negative barrier margins, guidelines from the end,
// barriers over guidelines, baseline links with margins and gone margins.
// Links only go to earlier widgets (and barriers over earlier widgets), so
// most layouts resolve.
// ---------------------------------------------------------------------------
List<String> genVExt(int seed, {bool baselineEdges = false}) {
  final r = R(seed);
  final W = r.range(160, 1200);
  final H = r.range(160, 1200);
  final ops = <String>['R $W $H'];
  if (r.p(0.35)) ops.add('rtl');
  final names = <String>[]; // in creation (dependency) order
  final kind = <String, String>{}; // w, bh (barrier horizontal), bv, gh, gv
  final adds = <String>[];
  final cfg = <String>[];
  var nW = 0, nB = 0, nG = 0;
  final count = r.range(3, 9);
  String pickH(String self) {
    final opts = <String>['root:L', 'root:R'];
    for (final n in names) {
      if (n == self) continue;
      final k = kind[n]!;
      if (k == 'w') opts.addAll(['$n:L', '$n:R']);
      if (k == 'bh') opts.addAll(['$n:L', '$n:R']);
      if (k == 'gv') opts.add('$n:L');
    }
    return r.pick(opts);
  }

  String pickV(String self) {
    final opts = <String>['root:T', 'root:B'];
    for (final n in names) {
      if (n == self) continue;
      final k = kind[n]!;
      if (k == 'w') opts.addAll(['$n:T', '$n:B']);
      if (k == 'bv') opts.addAll(['$n:T', '$n:B']);
      if (k == 'gh') opts.add('$n:T');
    }
    return r.pick(opts);
  }

  int m() =>
      r.p(0.08) ? -r.range(1, 12) : r.pick(const [0, 0, 0, 4, 8, 16, 3, 7, 12]);
  for (var i = 0; i < count; i++) {
    final roll = r.i(10);
    if (roll < 2 && names.where((n) => kind[n] == 'w').isNotEmpty) {
      // A barrier over earlier widgets (and maybe a barrier or guideline).
      final id = 'b${nB++}';
      final t = r.i(4);
      final horizontal = t < 2;
      kind[id] = horizontal ? 'bh' : 'bv';
      ops.add('b $id');
      adds.add(id);
      cfg.add('bt $id $t');
      if (r.p(0.4)) {
        cfg.add('bm $id ${r.pick(const [-8, -4, 4, 8, 12, 16, -1, 1])}');
      }
      if (r.p(0.3)) cfg.add('bg $id 0');
      if (r.p(0.1)) cfg.add('v $id 8');
      final pool = names
          .where(
            (n) =>
                kind[n] == 'w' ||
                kind[n] == (horizontal ? 'bh' : 'bv') ||
                kind[n] == (horizontal ? 'gv' : 'gh'),
          )
          .toList();
      final k = r.range(1, min(3, pool.length));
      final refs = <String>{};
      for (var j = 0; j < k; j++) {
        refs.add(r.pick(pool));
      }
      for (final ref in refs) {
        cfg.add('ref $id $ref');
      }
      names.add(id);
      continue;
    }
    if (roll < 3) {
      final id = 'g${nG++}';
      final vertical = r.p(0.6);
      kind[id] = vertical ? 'gv' : 'gh';
      ops.add('g $id');
      adds.add(id);
      cfg.add('go $id ${vertical ? 1 : 0}');
      switch (r.i(3)) {
        case 0:
          cfg.add('gb $id ${r.range(0, (vertical ? W : H) ~/ 2)}');
        case 1:
          cfg.add('ge $id ${r.range(0, (vertical ? W : H) ~/ 2)}');
        default:
          cfg.add('gp $id ${r.pct()}');
      }
      names.add(id);
      continue;
    }
    final id = 'w${nW++}';
    kind[id] = 'w';
    final w = r.range(4, 220), h = r.range(4, 160);
    ops.add('w $id $w $h');
    if (r.p(0.4)) ops.add('bl $id ${r.range(1, h)}');
    adds.add(id);
    final hb = r.pick(const ['F', 'F', 'W', 'W', 'M', 'P']);
    final vb = r.pick(const ['F', 'F', 'W', 'W', 'M', 'P']);
    cfg.add('hb $id $hb');
    cfg.add('vb $id $vb');
    if (hb == 'M') {
      cfg.add(
        'hm $id ${r.pick(const [0, 0, 2])} ${r.p(0.2) ? r.range(1, 60) : 0} ${r.p(0.2) ? r.range(20, 300) : 0} ${r.pct()}',
      );
    }
    if (vb == 'M') {
      cfg.add(
        'vm $id ${r.pick(const [0, 0, 2])} ${r.p(0.2) ? r.range(1, 60) : 0} ${r.p(0.2) ? r.range(20, 300) : 0} ${r.pct()}',
      );
    }
    if ((hb == 'M' || vb == 'M') && r.p(0.25)) {
      cfg.add(
        'ra $id ${r.pick(const [1.0, 1.5, 0.5, 2.0, 1.7777778, 0.75])} ${r.pick(const [-1, 0, 1])}',
      );
    }
    if (r.p(0.4)) cfg.add('hx $id ${r.bias()}');
    if (r.p(0.4)) cfg.add('vx $id ${r.bias()}');
    if (r.p(0.08)) cfg.add('v $id 8');
    if (r.p(0.06)) cfg.add('v $id 4');
    // Horizontal links.
    switch (r.i(6)) {
      case 0:
        break;
      case 1:
        final t = pickH(id).split(':');
        cfg.add('c $id CX ${t[0]} CX 0');
      case 2:
        final t = pickH(id).split(':');
        cfg.add('c $id L ${t[0]} ${t[1]} ${m()}');
      default:
        final a = pickH(id).split(':');
        final b = pickH(id).split(':');
        cfg.add('c $id L ${a[0]} ${a[1]} ${m()}');
        cfg.add('c $id R ${b[0]} ${b[1]} ${m()}');
        if (r.p(0.15)) cfg.add('gm $id L ${r.range(1, 30)}');
    }
    // Vertical links.
    final texts = names.where((n) => kind[n] == 'w').toList();
    switch (r.i(7)) {
      case 0:
        break;
      case 1:
        final t = pickV(id).split(':');
        cfg.add('c $id CY ${t[0]} CY 0');
      case 2:
        final t = pickV(id).split(':');
        cfg.add('c $id T ${t[0]} ${t[1]} ${m()}');
      case 3 when texts.isNotEmpty:
        final edge = baselineEdges ? r.pick(const ['S', 'S', 'T', 'B']) : 'S';
        cfg.add('c $id S ${r.pick(texts)} $edge ${r.p(0.3) ? m() : 0}');
        if (r.p(0.2)) cfg.add('gm $id S ${r.range(1, 20)}');
      default:
        final a = pickV(id).split(':');
        final b = pickV(id).split(':');
        cfg.add('c $id T ${a[0]} ${a[1]} ${m()}');
        cfg.add('c $id B ${b[0]} ${b[1]} ${m()}');
    }
    names.add(id);
  }
  if (!kind.values.any((k) => k == 'bh' || k == 'bv')) {
    // Make it a barrier layout.
    final ws = names.where((n) => kind[n] == 'w').toList();
    ops.add('b bz');
    adds.add('bz');
    cfg.add('bt bz ${r.i(4)}');
    for (final x in ws.take(r.range(1, 2))) {
      cfg.add('ref bz $x');
    }
  }
  if (r.p(0.4)) adds.shuffle(r.r);
  for (final a in adds) {
    ops.add('add $a');
  }
  ops.addAll(cfg);
  return ops;
}
