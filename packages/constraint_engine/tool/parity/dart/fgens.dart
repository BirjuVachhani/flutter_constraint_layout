// verify-final's realistic Flutter screens. Each generator returns the op
// list (see ops.dart) of one layout, built as a child list the way a
// Flutter screen declares it and emitted in the adapter's call order and
// state (fspec.dart). With barriers: false, the same screen links each part
// to the widget above it instead of a barrier (gone margins included), as
// a screen without barriers would.
//
//   flist      list rows: icon, title, subtitle, a baseline-aligned value,
//              a chevron, dividers, gone rows and gone items
//   frtl       right-to-left forms: start/end and absolute links, a label
//              barrier or a mirrored guideline, required marks on the label
//              baseline, error texts that come and go, button rows
//   fsettings  settings screens: sections, icons, titles with summaries,
//              switches centered on the text block, values on the title
//              baseline, sliders, dividers
//   fchat      chat bubbles: incoming and outgoing, avatars and names that
//              go for consecutive messages, wrapping bubbles hugging one
//              side, timestamps, read marks, reactions on a negative margin
//   ftoolbar   toolbars with centered titles: navigation, actions, a title
//              centered on the bar or between the barriers, subtitles,
//              badges, tabs with an indicator
import 'dart:math';

import 'fspec.dart';

typedef Gen = List<String> Function(int seed);

/// One screen: the container and its child list, before emission.
class Screen {
  Screen(
    this.w,
    this.h,
    this.specs, {
    this.ltr = true,
    this.wrapW = false,
    this.wrapH = false,
  });
  int w;
  int h;
  List<Spec> specs;
  bool ltr;
  bool wrapW;
  bool wrapH;

  List<String> emit() =>
      emitSpecs(w, h, specs, ltr: ltr, wrapW: wrapW, wrapH: wrapH);
}

final Map<String, Screen Function(int seed)> fscreens = {
  'flist': (s) => screenList(s, barriers: true),
  'frtl': (s) => screenRtlForm(s, barriers: true),
  'fsettings': (s) => screenSettings(s, barriers: true),
  'fchat': (s) => screenChat(s, barriers: true),
  'ftoolbar': (s) => screenToolbar(s, barriers: true),
  'nlist': (s) => screenList(s, barriers: false),
  'nrtl': (s) => screenRtlForm(s, barriers: false),
  'nsettings': (s) => screenSettings(s, barriers: false),
  'nchat': (s) => screenChat(s, barriers: false),
  'ntoolbar': (s) => screenToolbar(s, barriers: false),
};

final Map<String, Gen> fgenerators = {
  'flist': (s) => genList(s, barriers: true),
  'frtl': (s) => genRtlForm(s, barriers: true),
  'fsettings': (s) => genSettings(s, barriers: true),
  'fchat': (s) => genChat(s, barriers: true),
  'ftoolbar': (s) => genToolbar(s, barriers: true),
  'nlist': (s) => genList(s, barriers: false),
  'nrtl': (s) => genRtlForm(s, barriers: false),
  'nsettings': (s) => genSettings(s, barriers: false),
  'nchat': (s) => genChat(s, barriers: false),
  'ntoolbar': (s) => genToolbar(s, barriers: false),
};

class R {
  R(int seed) : r = Random(seed);
  final Random r;
  int i(int n) => r.nextInt(n);
  int range(int a, int b) => a + r.nextInt(b - a + 1);
  bool p(double x) => r.nextDouble() < x;
  T pick<T>(List<T> xs) => xs[r.nextInt(xs.length)];
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
  // Phone and tablet widths, and odd ones from fractional device pixels.
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
      : range(240, 1200);
  int textH() => pick(const [14, 16, 17, 18, 19, 20, 21, 22, 24, 28, 15, 13]);
  int textW() => range(18, 260);
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

/// A box (icon, image, switch): fixed, or wrap content, without a baseline.
Spec box(String id, int w, int h, {bool wrap = false}) {
  final s = Spec.widget(id, w, h);
  s.width = wrap ? const Dim.wrap() : Dim.fixed(w);
  s.height = wrap ? const Dim.wrap() : Dim.fixed(h);
  return s;
}

/// A child order a developer might use: the realistic order most of the
/// time, sometimes helpers first or last, rarely shuffled.
List<Spec> order(R r, List<Spec> specs) {
  if (r.p(0.65)) return specs;
  final out = [...specs];
  if (r.p(0.3)) {
    out.shuffle(r.r);
    return out;
  }
  final helpers = out.where((s) => s.kind != Kind.widget).toList();
  final widgets = out.where((s) => s.kind == Kind.widget).toList();
  return r.p(0.5) ? [...helpers, ...widgets] : [...widgets, ...helpers];
}

Link topOf(String? above, int gap, [int gone = 0]) => above == null
    ? Link('parent', 'top', gap)
    : Link(above, 'bottom', gap, gone);

// ---------------------------------------------------------------------------
// flist
// ---------------------------------------------------------------------------
List<String> genList(int seed, {required bool barriers}) =>
    screenList(seed, barriers: barriers).emit();

Screen screenList(int seed, {required bool barriers}) {
  final r = R(seed);
  final w = r.screenW();
  final h = r.range(300, 1600);
  final ltr = r.p(0.7);
  final specs = <Spec>[];
  final pad = r.pick(const [16, 12, 24, 8, 20, 16]);
  String? above;
  if (r.p(0.35)) {
    final hdr = text(r, 'hdr', h: r.pick(const [20, 22, 24, 28]));
    hdr.start = Link('parent', 'start', pad);
    hdr.top = Link('parent', 'top', r.pick(const [8, 16, 24]));
    specs.add(hdr);
    above = 'hdr';
  }
  final rows = r.range(1, 7);
  final iconSize = r.pick(const [24, 32, 40, 48, 56, 36]);
  final trailing = r.pick(const ['value', 'chevron', 'both', 'none', 'both']);
  for (var i = 0; i < rows; i++) {
    final rowGone = r.p(0.08);
    final gap = r.pick(const [8, 12, 16, 0, 4]);
    final rowRefs = <String>[];
    final hasIcon = r.p(0.8);
    final ic = box('ic$i', iconSize, iconSize);
    if (hasIcon) {
      ic.start = Link('parent', 'start', pad);
      if (r.p(0.5)) {
        ic.top = topOf(above, gap);
      }
      if (r.p(0.15)) ic.vis = 8;
      specs.add(ic);
      rowRefs.add(ic.id);
    }
    final t = text(r, 't$i', h: r.pick(const [16, 17, 18, 20, 21, 22, 24]));
    t.start = hasIcon
        ? Link(
            ic.id,
            'end',
            r.pick(const [12, 16, 16, 8]),
            r.pick(const [0, 0, 16, 12]),
          )
        : Link('parent', 'start', pad);
    t.top = topOf(above, gap + r.pick(const [0, 0, 4]));
    final hasSub = r.p(0.6);
    final s = text(r, 's$i', h: r.pick(const [14, 16, 32, 48, 15]));
    if (hasSub) {
      s.start = Link(t.id, 'start');
      s.top = Link(t.id, 'bottom', r.pick(const [0, 2, 4]));
      if (r.p(0.5)) {
        s.width = const Dim.match();
        s.end = Link(t.id, 'end');
      }
      if (r.p(0.3)) s.vis = 8;
    }
    if (hasIcon && ic.top == null) {
      // The icon centered on the text block (or on the title alone).
      ic.top = Link(t.id, 'top');
      ic.bottom = hasSub && r.p(0.6)
          ? Link(s.id, 'bottom')
          : Link(t.id, 'bottom');
      if (r.p(0.15)) ic.vBias = r.pick(const [0.0, 0.3, 1.0]);
    }
    // Trailing items.
    Spec? val;
    Spec? chev;
    if (trailing == 'chevron' || trailing == 'both') {
      chev = box(
        'ch$i',
        r.pick(const [24, 20, 16]),
        r.pick(const [24, 20, 16]),
      );
      chev.end = Link('parent', 'end', pad);
      chev.top = Link(t.id, 'top');
      chev.bottom = r.p(0.7) || !hasSub
          ? Link(t.id, 'bottom')
          : Link(s.id, 'bottom');
      if (r.p(0.25)) chev.vis = 8;
    }
    if (trailing == 'value' || trailing == 'both') {
      val = text(
        r,
        'val$i',
        w: r.range(16, 120),
        h: r.pick(const [14, 16, 17, 18, 20]),
      );
      val.end = chev != null
          ? Link(
              chev.id,
              'start',
              r.pick(const [4, 8]),
              r.pick(const [0, 16, 8]),
            )
          : Link('parent', 'end', pad);
      switch (r.i(3)) {
        case 0 || 1:
          val.baseline = Link(
            t.id,
            'baseline',
            r.p(0.1) ? r.pick(const [2, -2]) : 0,
          );
        default:
          val.top = Link(t.id, 'top');
          val.bottom = Link(t.id, 'bottom');
      }
      if (r.p(0.2)) val.vis = 8;
    }
    final trailRefs = [?val?.id, ?chev?.id];
    String? trailStart;
    if (trailRefs.isNotEmpty) {
      if (barriers) {
        final tb = Spec.barrier(
          'tr$i',
          'start',
          trailRefs,
          margin: r.pick(const [8, 8, 12, 16, 0]),
          allowsGone: r.p(0.7),
        );
        specs.add(tb);
        trailStart = tb.id;
      } else {
        trailStart = trailRefs.first;
      }
    }
    // Title end.
    if (r.p(0.75)) {
      t.end = trailStart != null
          ? (barriers
                ? Link(trailStart, 'start')
                : Link(trailStart, 'start', 8, pad))
          : Link('parent', 'end', pad);
      if (r.p(0.7)) {
        t.width = const Dim.match();
      } else {
        t.hBias = r.pick(const [0.0, 0.0, 0.0, 0.5]);
      }
    }
    specs.add(t);
    rowRefs.add(t.id);
    if (hasSub) {
      specs.add(s);
      rowRefs.add(s.id);
    }
    if (val != null) {
      specs.add(val);
      rowRefs.add(val.id);
    }
    if (chev != null) {
      specs.add(chev);
      if (r.p(0.3)) rowRefs.add(chev.id);
    }
    if (rowGone) {
      for (final sp in specs) {
        if (rowRefs.contains(sp.id) || sp.id == chev?.id) sp.vis = 8;
      }
    }
    String next;
    if (barriers) {
      final rb = Spec.barrier(
        'rb$i',
        'bottom',
        rowRefs,
        margin: r.pick(const [8, 12, 16, 0, 4]),
        allowsGone: r.p(0.75),
      );
      specs.add(rb);
      next = rb.id;
    } else {
      next = hasSub && r.p(0.6) ? s.id : (hasIcon && r.p(0.5) ? ic.id : t.id);
    }
    if (r.p(0.45)) {
      final dv = box('dv$i', 100, 1);
      dv.width = const Dim.match();
      dv.start = r.p(0.6) ? Link(t.id, 'start') : Link('parent', 'start');
      dv.end = Link('parent', 'end');
      dv.top = Link(
        next,
        'bottom',
        barriers ? 0 : r.pick(const [8, 12]),
        barriers ? 0 : 8,
      );
      if (rowGone && r.p(0.5)) dv.vis = 8;
      specs.add(dv);
      next = dv.id;
    }
    above = next;
  }
  if (r.p(0.3)) {
    // A "load more" button centered under the list.
    final more = box(
      'more',
      r.pick(const [96, 120, 88]),
      r.pick(const [36, 40]),
      wrap: r.p(0.5),
    );
    more.start = Link('parent', 'start');
    more.end = Link('parent', 'end');
    more.top = topOf(above, r.pick(const [8, 16]));
    if (r.p(0.2)) more.hBias = r.bias();
    if (r.p(0.15)) more.vis = 8;
    specs.add(more);
  }
  return Screen(
    w,
    h,
    order(r, specs),
    ltr: ltr,
    wrapH: r.p(0.12),
    wrapW: r.p(0.02),
  );
}

// ---------------------------------------------------------------------------
// frtl
// ---------------------------------------------------------------------------
List<String> genRtlForm(int seed, {required bool barriers}) =>
    screenRtlForm(seed, barriers: barriers).emit();

Screen screenRtlForm(int seed, {required bool barriers}) {
  final r = R(seed);
  final w = r.screenW();
  final h = r.range(380, 1400);
  final ltr = r.p(0.1); // mostly right to left
  final specs = <Spec>[];
  final edgeM = r.pick(const [16, 24, 12, 20, 15]);
  final absolute = r.p(0.25); // some children use absolute left/right links
  String? above;
  if (r.p(0.7)) {
    final title = text(r, 'title', h: r.pick(const [22, 24, 28, 27]));
    title.start = Link('parent', 'start', edgeM);
    title.top = Link('parent', 'top', r.pick(const [16, 24, 12]));
    specs.add(title);
    above = 'title';
    if (r.p(0.5)) {
      final close = box(
        'close',
        r.pick(const [24, 32, 40, 48]),
        r.pick(const [24, 32, 40, 48]),
      );
      if (absolute) {
        close.left = Link('parent', 'left', r.pick(const [8, 12, 16]));
      } else {
        close.end = Link('parent', 'end', r.pick(const [8, 12, 16]));
      }
      close.top = Link('title', 'top');
      close.bottom = Link('title', 'bottom');
      specs.add(close);
      if (barriers) {
        specs.add(
          Spec.barrier('head', 'bottom', [
            'title',
            'close',
          ], margin: r.pick(const [8, 16, 24, 0])),
        );
        above = 'head';
      }
    }
  }
  final useGuide = r.p(0.35);
  if (useGuide) {
    final g = Spec.guideline(
      'col',
      false,
      gPct: r.p(0.6)
          ? r.pick(const [0.3, 0.33, 0.35, 0.4, 0.25, 0.375, 0.45])
          : null,
      gBegin: r.range(80, 180),
    );
    specs.add(g);
  }
  final rows = r.range(1, 6);
  final labels = <String>[];
  final fields = <String>[];
  final rowGap = r.pick(const [8, 12, 16, 20, 10]);
  for (var i = 0; i < rows; i++) {
    final label = text(r, 'lbl$i');
    final field = Spec.widget(
      'fld$i',
      r.range(40, 280),
      r.pick(const [40, 48, 56, 36, 44]),
      baselineDist: r.p(0.7) ? r.range(14, 30) : 0,
    );
    labels.add(label.id);
    fields.add(field.id);
    label.start = Link('parent', 'start', edgeM);
    if (useGuide && r.p(0.4)) {
      label.end = Link('col', 'start', r.pick(const [8, 12]));
      label.hBias = r.pick(const [1.0, 0.0, 0.5]);
    }
    final col = useGuide ? 'col' : (barriers ? 'lblEnd' : null);
    // Field horizontally.
    final fieldStart = col != null
        ? Link(
            col,
            useGuide ? 'end' : 'end',
            useGuide ? 0 : r.pick(const [0, 8, 16]),
          )
        : Link(label.id, 'end', r.pick(const [12, 16]));
    switch (r.i(6)) {
      case 0 || 1 || 2:
        field.width = Dim.match(max: r.p(0.15) ? r.range(120, 400) : 0);
        field.start = fieldStart;
        field.end = Link('parent', 'end', edgeM);
        if (field.width!.max > 0) field.hBias = r.bias();
      case 3:
        field.width = Dim.fixed(field.iw);
        field.start = fieldStart;
      case 4:
        field.width = const Dim.wrap();
        field.start = fieldStart;
        field.end = Link('parent', 'end', edgeM);
        field.hBias = r.bias();
      default:
        field.width = Dim.match(pct: r.pct());
        field.start = fieldStart;
        if (r.p(0.5)) field.end = Link('parent', 'end', edgeM);
        field.hBias = r.bias();
    }
    field.height = Dim.fixed(field.ih);
    field.top = topOf(
      above,
      i == 0 ? r.pick(const [16, 24]) : rowGap,
      barriers ? 0 : rowGap,
    );
    switch (r.i(3)) {
      case 0 when field.baselineDist > 0:
        label.baseline = Link(field.id, 'baseline');
      case 1:
        label.top = Link(field.id, 'top');
        label.bottom = Link(field.id, 'bottom');
        if (r.p(0.2)) label.vBias = r.pick(const [0.3, 0.0, 1.0]);
      default:
        label.top = Link(field.id, 'top', r.pick(const [0, 4, 8]));
    }
    specs.addAll([label, field]);
    final rowRefs = [label.id, field.id];
    if (r.p(0.3)) {
      // A required mark on the label's baseline.
      final req = text(r, 'req$i', w: r.range(6, 10), h: label.ih);
      req.start = Link(label.id, 'end', 2);
      req.baseline = Link(label.id, 'baseline');
      specs.add(req);
    }
    if (r.p(0.35)) {
      // A trailing icon inside the field (clear, visibility toggle).
      final ti = box('fic$i', 24, 24);
      if (absolute && r.p(0.5)) {
        ti.left = Link(field.id, 'left', 8);
      } else {
        ti.end = Link(field.id, 'end', 8);
      }
      ti.top = Link(field.id, 'top');
      ti.bottom = Link(field.id, 'bottom');
      if (r.p(0.4)) ti.vis = 8;
      specs.add(ti);
    }
    String next = field.id;
    if (r.p(0.45)) {
      final err = text(r, 'err$i', h: r.pick(const [12, 14, 16, 32]));
      err.start = Link(field.id, 'start', r.pick(const [0, 4, 12]));
      err.top = Link(field.id, 'bottom', r.pick(const [2, 4]));
      if (r.p(0.4)) {
        err.width = const Dim.match();
        err.end = Link(field.id, 'end');
      }
      if (r.p(0.6)) err.vis = 8;
      specs.add(err);
      rowRefs.add(err.id);
      if (!barriers) next = err.id;
    }
    if (barriers && r.p(0.8)) {
      final rb = Spec.barrier(
        'rb$i',
        'bottom',
        rowRefs,
        margin: r.pick(const [0, 0, 4, 8]),
        allowsGone: r.p(0.8),
      );
      specs.add(rb);
      above = rb.id;
    } else {
      above = next;
    }
  }
  if (!useGuide && barriers) {
    specs.add(
      Spec.barrier(
        'lblEnd',
        'end',
        labels,
        margin: r.pick(const [0, 8, 12, 16, 4]),
        allowsGone: r.p(0.6),
      ),
    );
  }
  if (r.p(0.3)) {
    // A check box row.
    final cb = box('cb', 24, 24);
    cb.start = Link('parent', 'start', edgeM);
    cb.top = topOf(above, 16);
    final cbt = text(r, 'cbt');
    cbt.start = Link('cb', 'end', 8);
    cbt.top = Link('cb', 'top');
    cbt.bottom = Link('cb', 'bottom');
    if (r.p(0.5)) {
      cbt.width = const Dim.match();
      cbt.end = Link('parent', 'end', edgeM);
    }
    specs.addAll([cb, cbt]);
    above = 'cb';
  }
  final bgap = r.pick(const [16, 24, 32]);
  switch (r.i(4)) {
    case 0:
      final ok = box(
        'ok',
        r.pick(const [88, 96, 120]),
        r.pick(const [36, 40, 48]),
        wrap: r.p(0.4),
      );
      if (absolute) {
        ok.left = Link('parent', 'left', edgeM);
      } else {
        ok.end = Link('parent', 'end', edgeM);
      }
      ok.top = topOf(above, bgap);
      specs.add(ok);
    case 1:
      final ok = box('ok', 100, r.pick(const [40, 48]));
      ok.width = r.p(0.5)
          ? const Dim.match()
          : Dim.match(pct: r.pick(const [0.5, 0.6, 0.8, 0.9]));
      ok.start = Link('parent', 'start', edgeM);
      ok.end = Link('parent', 'end', edgeM);
      ok.top = topOf(above, bgap);
      specs.add(ok);
    case 2:
      final cancel = box(
        'cancel',
        r.pick(const [80, 88, 75]),
        36,
        wrap: r.p(0.5),
      );
      final ok = box('ok', r.pick(const [64, 88, 96, 77]), 36, wrap: r.p(0.5));
      cancel.start = Link('parent', 'start', edgeM);
      cancel.end = Link('ok', 'start', r.pick(const [0, 8]));
      ok.start = Link('cancel', 'end', r.pick(const [0, 8]));
      ok.end = Link('parent', 'end', edgeM);
      cancel.hChain = r.pick(const [0, 1, 2]);
      if (cancel.hChain == 2) cancel.hBias = r.pick(const [1.0, 0.5, 0.0, 0.7]);
      cancel.top = topOf(above, bgap);
      ok.top = Link('cancel', 'top');
      if (r.p(0.15)) cancel.vis = 8;
      specs.addAll([cancel, ok]);
    default:
      final ok = box('ok', r.pick(const [88, 96]), 36);
      final cancel = box('cancel', r.pick(const [80, 88]), 36);
      ok.end = Link('parent', 'end', edgeM);
      ok.top = topOf(above, bgap);
      cancel.end = Link('ok', 'start', 8, r.pick(const [0, 0, 16]));
      cancel.baseline = null;
      cancel.top = Link('ok', 'top');
      if (r.p(0.3)) ok.vis = 8;
      specs.addAll([ok, cancel]);
  }
  return Screen(w, h, order(r, specs), ltr: ltr, wrapH: r.p(0.1));
}

// ---------------------------------------------------------------------------
// fsettings
// ---------------------------------------------------------------------------
List<String> genSettings(int seed, {required bool barriers}) =>
    screenSettings(seed, barriers: barriers).emit();

Screen screenSettings(int seed, {required bool barriers}) {
  final r = R(seed);
  final w = r.screenW();
  final h = r.range(400, 1800);
  final ltr = r.p(0.7);
  final specs = <Spec>[];
  final pad = r.pick(const [16, 16, 24, 12, 20]);
  String? above;
  final sections = r.range(1, 3);
  var n = 0;
  for (var sct = 0; sct < sections; sct++) {
    final hd = text(r, 'hd$sct', h: r.pick(const [14, 16, 18]));
    hd.start = Link('parent', 'start', pad);
    hd.top = topOf(
      above,
      sct == 0 ? r.pick(const [8, 16]) : r.pick(const [24, 32, 16]),
      barriers ? 0 : 16,
    );
    specs.add(hd);
    above = hd.id;
    final rows = r.range(1, 4);
    final withIcons = r.p(0.6);
    for (var k = 0; k < rows; k++, n++) {
      final gap = r.pick(const [12, 16, 8, 20]);
      final refs = <String>[];
      final ic = box(
        'ic$n',
        r.pick(const [24, 24, 40, 32]),
        r.pick(const [24, 24, 40, 32]),
      );
      if (withIcons) {
        ic.start = Link('parent', 'start', pad);
        if (r.p(0.2)) ic.vis = 8;
        specs.add(ic);
        refs.add(ic.id);
      }
      final t = text(r, 't$n', h: r.pick(const [16, 18, 20, 21, 17]));
      t.start = withIcons
          ? Link(ic.id, 'end', r.pick(const [16, 32, 24]), r.pick([0, 0, pad]))
          : Link('parent', 'start', pad);
      t.top = topOf(above, gap, barriers ? 0 : gap);
      final hasSum = r.p(0.6);
      final sm = text(r, 'sm$n', h: r.pick(const [14, 16, 32, 48, 17]));
      if (hasSum) {
        sm.start = Link(t.id, 'start');
        sm.top = Link(t.id, 'bottom', r.pick(const [2, 4, 0]));
        sm.width = const Dim.match();
        if (r.p(0.35)) sm.vis = 8;
      }
      if (withIcons) {
        ic.top = Link(t.id, 'top');
        ic.bottom = hasSum ? Link(sm.id, 'bottom') : Link(t.id, 'bottom');
      }
      // Trailing control.
      Spec? ctl;
      switch (r.i(5)) {
        case 0 || 1:
          ctl = box(
            'sw$n',
            r.pick(const [52, 36, 51, 44]),
            r.pick(const [32, 20, 31, 24]),
          );
          ctl.top = Link(t.id, 'top');
          ctl.bottom = hasSum ? Link(sm.id, 'bottom') : Link(t.id, 'bottom');
          if (r.p(0.15)) ctl.vBias = r.pick(const [0.0, 0.3]);
        case 2:
          ctl = text(r, 'vl$n', w: r.range(20, 120), h: t.ih);
          ctl.baseline = Link(t.id, 'baseline');
        case 3:
          ctl = box('chv$n', 24, 24);
          ctl.top = Link(t.id, 'top');
          ctl.bottom = Link(t.id, 'bottom');
        default:
          ctl = null;
      }
      if (ctl != null) {
        ctl.end = Link('parent', 'end', pad);
        if (r.p(0.08)) ctl.vis = 4;
        if (r.p(0.08)) ctl.vis = 8;
      }
      String? trail;
      if (ctl != null) {
        if (barriers && r.p(0.6)) {
          final tb = Spec.barrier('tr$n', 'start', [
            ctl.id,
          ], margin: r.pick(const [16, 8, 12]));
          specs.add(tb);
          trail = tb.id;
        } else {
          trail = ctl.id;
        }
      }
      t.width = const Dim.match();
      t.end = trail != null
          ? Link(
              trail,
              'start',
              trail.startsWith('tr') ? 0 : 16,
              trail.startsWith('tr') ? 0 : pad,
            )
          : Link('parent', 'end', pad);
      if (hasSum) sm.end = Link(t.id, 'end');
      specs.add(t);
      refs.add(t.id);
      if (hasSum) {
        specs.add(sm);
        refs.add(sm.id);
      }
      if (ctl != null) {
        specs.add(ctl);
        refs.add(ctl.id);
      }
      String next = hasSum ? sm.id : t.id;
      if (r.p(0.2)) {
        // A slider row under the title.
        final sl = box('sl$n', 200, r.pick(const [32, 40, 24]));
        sl.width = const Dim.match();
        sl.start = Link(t.id, 'start', r.pick(const [0, -16, -8]));
        sl.end = Link('parent', 'end', pad);
        sl.top = Link(next, 'bottom', r.pick(const [4, 8]));
        specs.add(sl);
        refs.add(sl.id);
        next = sl.id;
      }
      if (barriers) {
        final rb = Spec.barrier(
          'rb$n',
          'bottom',
          refs,
          margin: r.pick(const [12, 16, 8, 0]),
          allowsGone: r.p(0.7),
        );
        specs.add(rb);
        next = rb.id;
      }
      if (r.p(0.4)) {
        final dv = box('dv$n', 100, 1);
        dv.width = const Dim.match();
        dv.start = r.p(0.5) ? Link(t.id, 'start') : Link('parent', 'start');
        dv.end = Link('parent', 'end');
        dv.top = Link(next, 'bottom', barriers ? 0 : 12);
        specs.add(dv);
        next = dv.id;
      }
      above = next;
    }
  }
  if (r.p(0.25)) {
    // A footer note centered under the sections.
    final ft = text(r, 'foot', h: r.pick(const [14, 16, 32]));
    ft.start = Link('parent', 'start', pad);
    ft.end = Link('parent', 'end', pad);
    ft.top = topOf(above, 24);
    if (r.p(0.4)) ft.width = Dim.match(max: r.p(0.5) ? r.range(200, 400) : 0);
    specs.add(ft);
  }
  return Screen(w, h, order(r, specs), ltr: ltr, wrapH: r.p(0.2));
}

// ---------------------------------------------------------------------------
// fchat
// ---------------------------------------------------------------------------
List<String> genChat(int seed, {required bool barriers}) =>
    screenChat(seed, barriers: barriers).emit();

Screen screenChat(int seed, {required bool barriers}) {
  final r = R(seed);
  final w = r.screenW();
  final h = r.range(400, 2000);
  final ltr = r.p(0.75);
  final specs = <Spec>[];
  String? above;
  final msgs = r.range(2, 9);
  final avatarSize = r.pick(const [32, 36, 40, 28]);
  final side = r.pick(const [48, 56, 64, 72, 80]);
  var lastIncoming = false;
  for (var k = 0; k < msgs; k++) {
    if (r.p(0.2)) {
      // A date header centered on the screen.
      final dh = text(r, 'dt$k', h: r.pick(const [14, 16, 12]));
      dh.start = Link('parent', 'start');
      dh.end = Link('parent', 'end');
      dh.top = topOf(above, 12, barriers ? 0 : 12);
      if (r.p(0.15)) dh.hBias = r.pick(const [0.3, 0.45]);
      specs.add(dh);
      above = dh.id;
    }
    final incoming = r.p(0.55);
    final consecutive = incoming && lastIncoming && r.p(0.6);
    lastIncoming = incoming;
    final refs = <String>[];
    final lines = r.range(1, 4);
    final bubble = Spec.widget(
      'bb$k',
      r.range(40, 520),
      16 + lines * r.pick(const [18, 20, 19]),
      baselineDist: r.range(14, 24),
    );
    switch (r.i(5)) {
      case 0:
        bubble.width = Dim.cwrap(max: r.p(0.3) ? r.range(160, 320) : 0);
      case 1:
        bubble.width = Dim.match(max: r.range(160, 360));
      default:
        bubble.width = const Dim.wrap();
    }
    bubble.height = const Dim.wrap();
    final gapTop = r.pick(const [2, 4, 8, 12]);
    if (incoming) {
      final av = box('av$k', avatarSize, avatarSize);
      av.start = Link('parent', 'start', 8);
      if (r.p(0.7)) {
        av.bottom = Link(bubble.id, 'bottom');
      } else {
        av.top = Link(bubble.id, 'top');
      }
      if (consecutive) av.vis = 8;
      final nm = text(r, 'nm$k', h: r.pick(const [12, 13, 14]));
      nm.start = Link(bubble.id, 'start', 12);
      nm.top = topOf(above, gapTop, barriers ? 0 : gapTop);
      if (consecutive || r.p(0.2)) nm.vis = 8;
      bubble.start = Link(av.id, 'end', 8, 8 + avatarSize + 8 - 8);
      bubble.end = Link('parent', 'end', side);
      bubble.top = Link(nm.id, 'bottom', 2, r.pick(const [0, 4, 2]));
      bubble.hBias = 0;
      specs.addAll([nm, bubble, av]);
      refs.addAll([av.id, bubble.id]);
    } else {
      bubble.end = Link('parent', 'end', 8);
      bubble.start = Link('parent', 'start', side);
      bubble.top = topOf(above, gapTop, barriers ? 0 : gapTop);
      bubble.hBias = 1;
      specs.add(bubble);
      refs.add(bubble.id);
    }
    String last = bubble.id;
    if (r.p(0.7)) {
      final tm = text(
        r,
        'tm$k',
        w: r.range(28, 60),
        h: r.pick(const [11, 12, 13]),
      );
      tm.top = Link(bubble.id, 'bottom', 2);
      if (incoming) {
        tm.start = Link(bubble.id, 'start', r.pick(const [0, 4]));
      } else {
        tm.end = Link(bubble.id, 'end', r.pick(const [0, 4, 20]));
      }
      if (r.p(0.25)) tm.vis = 8;
      specs.add(tm);
      refs.add(tm.id);
      last = tm.id;
      if (!incoming && r.p(0.6)) {
        // A read mark after the time, centered on it.
        final st = box('st$k', 16, r.pick(const [16, 12, 11]));
        st.start = Link(tm.id, 'end', 4);
        st.top = Link(tm.id, 'top');
        st.bottom = Link(tm.id, 'bottom');
        if (r.p(0.2)) st.vis = 8;
        specs.add(st);
        if (r.p(0.5)) {
          tm.end = Link(bubble.id, 'end', 20);
        }
      }
    }
    if (r.p(0.25)) {
      // Reactions overlapping the bubble's bottom edge.
      final rx = box('rx$k', r.range(24, 64), 20, wrap: r.p(0.4));
      rx.top = Link(bubble.id, 'bottom', -8);
      if (incoming) {
        rx.start = Link(bubble.id, 'start', 8);
      } else {
        rx.end = Link(bubble.id, 'end', 8);
      }
      if (r.p(0.4)) rx.vis = 8;
      specs.add(rx);
      refs.add(rx.id);
    }
    if (barriers) {
      final mb = Spec.barrier(
        'mb$k',
        'bottom',
        refs,
        margin: r.pick(const [0, 4, 8, 0]),
        allowsGone: r.p(0.8),
      );
      specs.add(mb);
      above = mb.id;
    } else {
      above = last;
    }
  }
  if (r.p(0.4)) {
    final ty = box(
      'typing',
      r.pick(const [40, 48, 56]),
      r.pick(const [20, 24]),
    );
    ty.start = Link('parent', 'start', 16);
    ty.top = topOf(above, 8, barriers ? 0 : 8);
    if (r.p(0.6)) ty.vis = 8;
    specs.add(ty);
  }
  if (r.p(0.5)) {
    // The composer at the bottom.
    final send = box('send', 40, 40);
    send.end = Link('parent', 'end', 8);
    final input = Spec.widget(
      'input',
      200,
      r.pick(const [40, 48, 56]),
      baselineDist: 26,
    );
    input.width = const Dim.match();
    input.height = const Dim.wrap();
    input.start = Link('parent', 'start', 8);
    input.end = Link('send', 'start', 8);
    input.bottom = Link('parent', 'bottom', 8);
    send.top = Link('input', 'top');
    send.bottom = Link('input', 'bottom');
    specs.addAll([input, send]);
  }
  return Screen(w, h, order(r, specs), ltr: ltr, wrapH: r.p(0.15));
}

// ---------------------------------------------------------------------------
// ftoolbar
// ---------------------------------------------------------------------------
List<String> genToolbar(int seed, {required bool barriers}) =>
    screenToolbar(seed, barriers: barriers).emit();

Screen screenToolbar(int seed, {required bool barriers}) {
  final r = R(seed);
  final w = r.screenW();
  final h = r.range(56, 1000);
  final ltr = r.p(0.6);
  final specs = <Spec>[];
  final barH = r.pick(const [56, 64, 48, 72, 57, 55, 60]);
  final bar = Spec.widget('bar', w, barH);
  bar.width = const Dim.match();
  bar.height = Dim.fixed(barH);
  bar.start = Link('parent', 'start');
  bar.end = Link('parent', 'end');
  bar.top = Link('parent', 'top');
  specs.add(bar);
  final hasNav = r.p(0.8);
  final nav = box(
    'nav',
    r.pick(const [24, 48, 40]),
    r.pick(const [24, 48, 40]),
  );
  if (hasNav) {
    nav.start = Link('parent', 'start', r.pick(const [4, 16, 8]));
    nav.top = Link('bar', 'top');
    nav.bottom = Link('bar', 'bottom');
    if (r.p(0.25)) nav.vis = 8;
    specs.add(nav);
  }
  final nAct = r.range(0, 3);
  final acts = <String>[];
  for (var k = 0; k < nAct; k++) {
    final s = r.pick(const [24, 40, 48, 32]);
    final a = box('a$k', s, s);
    a.end = k == 0
        ? Link('parent', 'end', r.pick(const [4, 8, 16]))
        : Link(
            'a${k - 1}',
            'start',
            r.pick(const [0, 4, 8]),
            r.pick(const [0, 0, 8]),
          );
    a.top = Link('bar', 'top');
    a.bottom = Link('bar', 'bottom');
    if (r.p(0.2)) a.vis = 8;
    specs.add(a);
    acts.add(a.id);
  }
  if (barriers) {
    if (hasNav) {
      specs.add(
        Spec.barrier(
          'navEnd',
          'end',
          ['nav'],
          margin: r.pick(const [0, 8, 16, 12]),
          allowsGone: r.p(0.5),
        ),
      );
    }
    if (acts.isNotEmpty) {
      specs.add(
        Spec.barrier(
          'actStart',
          'start',
          acts,
          margin: r.pick(const [0, 8, 16]),
          allowsGone: r.p(0.5),
        ),
      );
    }
  }
  final startAnchor = hasNav
      ? (barriers ? Link('navEnd', 'end') : Link('nav', 'end', 16, 16))
      : Link('parent', 'start', 16);
  final endAnchor = acts.isNotEmpty
      ? (barriers
            ? Link('actStart', 'start')
            : Link(acts.last, 'start', 16, 16))
      : Link('parent', 'end', 16);
  final title = text(r, 'title', h: r.pick(const [20, 22, 24, 21, 23]));
  switch (r.i(6)) {
    case 0:
      // Centered on the bar, whatever is at its sides.
      title.start = Link('parent', 'start');
      title.end = Link('parent', 'end');
    case 1:
      // Centered between the navigation and the actions.
      title.start = startAnchor;
      title.end = endAnchor;
    case 2:
      // At the start, filling up to the actions.
      title.start = startAnchor;
      title.end = endAnchor;
      if (r.p(0.6)) {
        title.width = const Dim.match();
      } else {
        title.hBias = 0;
      }
    case 3:
      // Centered on the bar at a fraction of its width.
      title.start = Link('parent', 'start');
      title.end = Link('parent', 'end');
      title.width = Dim.match(pct: r.pick(const [0.5, 0.6, 0.7, 0.55, 0.45]));
    case 4:
      // Centered on the bar, capped by its sides.
      title.start = startAnchor;
      title.end = endAnchor;
      title.width = Dim.cwrap();
    default:
      title.start = startAnchor;
      title.end = endAnchor;
      title.hBias = r.bias();
  }
  final hasSub = r.p(0.35);
  if (hasSub) {
    final sub = text(r, 'sub', h: r.pick(const [14, 16, 13]));
    sub.start = Link('title', 'start');
    if (r.p(0.5)) sub.end = Link('title', 'end');
    if (r.p(0.6)) {
      title.top = Link('bar', 'top');
      title.bottom = Link('sub', 'top');
      sub.top = Link('title', 'bottom');
      sub.bottom = Link('bar', 'bottom');
      title.vChain = 2;
    } else {
      title.top = Link('bar', 'top', r.pick(const [6, 8, 10]));
      sub.top = Link('title', 'bottom');
    }
    if (r.p(0.3)) sub.vis = 8;
    specs.addAll([title, sub]);
  } else {
    title.top = Link('bar', 'top');
    title.bottom = Link('bar', 'bottom');
    specs.add(title);
  }
  if (acts.isNotEmpty && r.p(0.4)) {
    // A badge on the first action's top end corner.
    final bd = box(
      'badge',
      r.pick(const [8, 16, 18, 20, 15]),
      r.pick(const [8, 16, 18, 15]),
    );
    bd.start = Link('a0', 'end');
    bd.end = Link('a0', 'end');
    bd.top = Link('a0', 'top');
    bd.bottom = Link('a0', 'top');
    if (r.p(0.4)) bd.vis = 8;
    specs.add(bd);
  }
  var above = 'bar';
  if (barriers) {
    specs.add(
      Spec.barrier('barBottom', 'bottom', [
        'bar',
        'title',
        if (hasSub) 'sub',
        ...acts,
      ], margin: r.pick(const [0, 0, 8])),
    );
    above = 'barBottom';
  }
  if (r.p(0.5)) {
    // Tabs in a chain under the bar, and an indicator under one of them.
    final nt = r.range(2, 4);
    final style = r.pick(const [0, 0, 1, 2]);
    final weighted = r.p(0.5);
    for (var k = 0; k < nt; k++) {
      final tb = text(r, 'tab$k', h: r.pick(const [20, 24, 48]));
      if (weighted) {
        tb.width = const Dim.match();
        if (r.p(0.3)) tb.hWeight = r.pick(const [1.0, 2.0]);
      }
      tb.start = k == 0 ? Link('parent', 'start') : Link('tab${k - 1}', 'end');
      tb.end = k == nt - 1
          ? Link('parent', 'end')
          : Link('tab${k + 1}', 'start');
      tb.top = Link(above, 'bottom');
      if (k == 0) tb.hChain = style;
      specs.add(tb);
    }
    final sel = r.i(nt);
    final ind = box('ind', 40, r.pick(const [2, 3, 4]));
    ind.width = const Dim.match();
    ind.start = Link('tab$sel', 'start');
    ind.end = Link('tab$sel', 'end');
    ind.top = Link('tab$sel', 'bottom');
    specs.add(ind);
    above = 'ind';
  }
  if (r.p(0.4)) {
    final search = Spec.widget(
      'search',
      200,
      r.pick(const [40, 48]),
      baselineDist: 28,
    );
    search.width = const Dim.match();
    search.height = Dim.fixed(search.ih);
    search.start = Link('parent', 'start', 16);
    search.end = Link('parent', 'end', 16);
    search.top = Link(above, 'bottom', 8);
    specs.add(search);
  }
  return Screen(w, h, order(r, specs), ltr: ltr, wrapH: r.p(0.05));
}
