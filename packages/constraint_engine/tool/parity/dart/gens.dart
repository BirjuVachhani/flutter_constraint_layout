// Barrier layout generators for the converge fuzz. Each returns the op list
// of one layout (see ops.dart).
import 'dart:math';

import 'package:constraint_engine/constraint_engine.dart';

import 'ops.dart';

typedef Gen = List<String> Function(int seed);

final Map<String, Gen> generators = {
  'ext': (s) => genExt(s, strict: true),
  'extl': (s) => genExt(s, strict: false),
  'rand': genRand,
  'form': genForm,
  'formx': genFormX,
  'chainy': genChainy,
  'crossed': genCrossed,
  'cards': genCards,
  'nest': genNest,
};

// ---------------------------------------------------------------------------
// ext: the reviewer's extended fuzz (fuzz_ext.dart), on the op recorder.
// strict keeps sizes, margins and container sizes even, and biases 0, 0.5, 1;
// loose allows odd sizes, any bias in tenths and negative widget margins.
// ---------------------------------------------------------------------------
List<String> genExt(int seed, {required bool strict}) {
  final sizeRnd = Random(seed * 7919);
  final width = strict
      ? 200 + 2 * sizeRnd.nextInt(300)
      : 200 + sizeRnd.nextInt(600);
  final height = strict
      ? 200 + 2 * sizeRnd.nextInt(300)
      : 200 + sizeRnd.nextInt(600);
  final rec = Rec(width, height);
  final root = rec.root;
  final rnd = Random(seed);
  int even(int max) => 2 * rnd.nextInt(max ~/ 2 + 1);
  int size(int base, int span) =>
      strict ? base + even(span) : base + rnd.nextInt(span + 1);
  int margin() {
    if (rnd.nextInt(4) == 0) return 0;
    if (!strict && rnd.nextInt(8) == 0) return -rnd.nextInt(20);
    return strict ? even(40) : rnd.nextInt(41);
  }

  double bias() {
    if (strict || rnd.nextBool()) return const [0.0, 0.5, 1.0][rnd.nextInt(3)];
    return (rnd.nextInt(11)) / 10.0;
  }

  if (rnd.nextInt(4) == 0) rec.rtl();
  if (rnd.nextInt(10) == 0) rec.wrapW();
  if (rnd.nextInt(10) == 0) rec.wrapH();

  final vGuides = <Guideline>[];
  final hGuides = <Guideline>[];
  final guideCount = rnd.nextInt(3);
  for (var i = 0; i < guideCount; i++) {
    final vertical = rnd.nextBool();
    final gl = rec.guideline(
      'g$i',
      vertical ? Guideline.vertical : Guideline.horizontal,
    );
    final extent = vertical ? width : height;
    switch (rnd.nextInt(3)) {
      case 0:
        rec.guideBegin(
          gl,
          strict ? even(extent ~/ 2) : rnd.nextInt(extent ~/ 2),
        );
      case 1:
        rec.guideEnd(gl, strict ? even(extent ~/ 2) : rnd.nextInt(extent ~/ 2));
      default:
        rec.guidePercent(gl, const [0.25, 0.5, 0.75, 0.1, 0.3][rnd.nextInt(5)]);
    }
    rec.add(gl);
    (vertical ? vGuides : hGuides).add(gl);
  }

  final n = 1 + rnd.nextInt(8);
  final widgets = [
    for (var i = 0; i < n; i++) rec.widget('w$i', size(10, 150), size(10, 100)),
  ];
  final barrierCount = 1 + rnd.nextInt(3);
  final barriers = <Barrier>[];
  for (var i = 0; i < barrierCount; i++) {
    final b = rec.barrier(
      'b$i',
      type: rnd.nextInt(4),
      margin: rnd.nextInt(5) == 0 ? -even(30) : margin().abs(),
      allowsGone: rnd.nextBool(),
    );
    if (rnd.nextInt(12) == 0) rec.visibility(b, ConstraintWidget.GONE);
    barriers.add(b);
  }
  final order = <ConstraintWidget>[...widgets, ...barriers]..shuffle(rnd);
  for (final c in order) {
    rec.add(c);
  }
  for (final b in barriers) {
    final count = rnd.nextInt(4);
    for (var j = 0; j < count; j++) {
      final roll = rnd.nextInt(10);
      if (roll < 2 && barriers.length > 1) {
        final other = barriers[rnd.nextInt(barriers.length)];
        if (other != b) rec.ref(b, other);
      } else if (roll < 3) {
        final guides = b.getOrientation() == ConstraintWidget.HORIZONTAL
            ? vGuides
            : hGuides;
        if (guides.isNotEmpty) rec.ref(b, guides[rnd.nextInt(guides.length)]);
      } else {
        rec.ref(b, widgets[rnd.nextInt(widgets.length)]);
      }
    }
    if (count == 0 && rnd.nextBool()) {
      rec.ref(b, widgets[rnd.nextInt(widgets.length)]);
    }
  }
  List<Barrier> along(int o) =>
      barriers.where((b) => b.getOrientation() == o).toList();
  final vertical = along(ConstraintWidget.HORIZONTAL);
  final horizontal = along(ConstraintWidget.VERTICAL);

  (ConstraintWidget, ConstraintAnchorType)? pick(int i, bool h) {
    final begin = h ? ConstraintAnchorType.left : ConstraintAnchorType.top;
    final end = h ? ConstraintAnchorType.right : ConstraintAnchorType.bottom;
    final side = rnd.nextBool() ? begin : end;
    final lines = h ? vertical : horizontal;
    final guides = h ? vGuides : hGuides;
    final roll = rnd.nextInt(12);
    if (roll < 3) return (root, side);
    if (roll < 6 && lines.isNotEmpty) {
      return (lines[rnd.nextInt(lines.length)], side);
    }
    if (roll < 8 && guides.isNotEmpty) {
      return (guides[rnd.nextInt(guides.length)], side);
    }
    if (roll < 11 && i > 0) return (widgets[rnd.nextInt(i)], side);
    if (roll == 11) return (widgets[rnd.nextInt(widgets.length)], side);
    return null;
  }

  void link(
    ConstraintWidget w,
    ConstraintAnchorType from,
    (ConstraintWidget, ConstraintAnchorType)? to,
  ) {
    if (to == null || to.$1 == w) return;
    final other = to.$1;
    final h =
        from == ConstraintAnchorType.left || from == ConstraintAnchorType.right;
    for (final a
        in h ? [other.mLeft, other.mRight] : [other.mTop, other.mBottom]) {
      if (a.mTarget != null && a.mTarget!.mOwner == w) return;
    }
    rec.connect(w, from, to.$1, to.$2, margin());
  }

  final chained = <ConstraintWidget, bool>{};
  if (n >= 3 && rnd.nextInt(3) == 0) {
    final h = rnd.nextBool();
    final len = 2 + rnd.nextInt(min(3, n - 1) - 1 + 1);
    final start = n - len;
    final members = widgets.sublist(start, start + len);
    final begin = h ? ConstraintAnchorType.left : ConstraintAnchorType.top;
    final end = h ? ConstraintAnchorType.right : ConstraintAnchorType.bottom;
    (ConstraintWidget, ConstraintAnchorType) endTarget(bool atBegin) {
      final lines = h ? vertical : horizontal;
      final guides = h ? vGuides : hGuides;
      final roll = rnd.nextInt(6);
      if (roll == 0 && lines.isNotEmpty) {
        return (lines[rnd.nextInt(lines.length)], atBegin ? end : begin);
      }
      if (roll == 1 && guides.isNotEmpty) {
        return (guides[rnd.nextInt(guides.length)], begin);
      }
      return (root, atBegin ? begin : end);
    }

    final head = endTarget(true);
    final tail = endTarget(false);
    rec.connect(members.first, begin, head.$1, head.$2, margin().abs());
    for (var k = 0; k + 1 < members.length; k++) {
      rec.connect(members[k], end, members[k + 1], begin, 0);
      rec.connect(members[k + 1], begin, members[k], end, 0);
    }
    rec.connect(members.last, end, tail.$1, tail.$2, margin().abs());
    rec.chainStyle(members.first, h, rnd.nextInt(3));
    for (final m in members) {
      chained[m] = h;
    }
  }

  for (final (i, w) in widgets.indexed) {
    for (final h in [true, false]) {
      final inChain = chained[w] == h;
      final begin = h ? ConstraintAnchorType.left : ConstraintAnchorType.top;
      final end = h ? ConstraintAnchorType.right : ConstraintAnchorType.bottom;
      final kind = rnd.nextInt(12);
      if (!inChain) {
        if (rnd.nextInt(10) < 8) link(w, begin, pick(i, h));
        if (rnd.nextInt(10) < 5) link(w, end, pick(i, h));
      }
      final linkedTwice =
          w.getAnchor(begin)!.isConnected() && w.getAnchor(end)!.isConnected();
      if (kind < 2) {
        rec.behaviour(w, h, DimensionBehaviour.wrapContent);
      } else if (kind < 5) {
        rec.behaviour(w, h, DimensionBehaviour.matchConstraint);
        final s = rnd.nextInt(6);
        if (s == 1 && linkedTwice) {
          final mn = even(60);
          final mx = rnd.nextInt(3) == 0 ? 0 : 40 + even(200);
          rec.matchStyle(
            w,
            h,
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
            mn,
            mx,
            1,
          );
        } else if (s == 2) {
          rec.matchStyle(w, h, ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 1);
        } else if (s == 3) {
          final p = const [0.25, 0.5, 0.2][rnd.nextInt(3)];
          final mn = rnd.nextInt(3) == 0 ? even(200) : 0;
          final mx = rnd.nextInt(3) == 0 ? 20 + even(200) : 0;
          rec.matchStyle(
            w,
            h,
            ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
            mn,
            mx,
            p,
          );
        } else if (s == 4 && rnd.nextInt(3) == 0) {
          rec.minSize(w, h, even(80));
        }
      } else if (kind == 5 && rnd.nextInt(3) == 0) {
        rec.behaviour(w, h, DimensionBehaviour.matchParent);
      }
      if (rnd.nextInt(4) == 0) rec.bias(w, h, bias());
      if (rnd.nextInt(5) == 0) rec.goneMargin(w, begin, even(30));
    }
    if (rnd.nextInt(10) == 0) {
      // Re-link an anchor without resetting it first: the old target keeps a
      // stale dependent, as an in-place update can leave behind.
      final h = rnd.nextBool();
      final a = h
          ? (rnd.nextBool()
                ? ConstraintAnchorType.left
                : ConstraintAnchorType.right)
          : (rnd.nextBool()
                ? ConstraintAnchorType.top
                : ConstraintAnchorType.bottom);
      if (w.getAnchor(a)!.isConnected()) link(w, a, pick(i, h));
    }
    if (!strict && rnd.nextInt(12) == 0) {
      final h = rnd.nextBool();
      final linkedTwice = h
          ? w.mLeft.isConnected() && w.mRight.isConnected()
          : w.mTop.isConnected() && w.mBottom.isConnected();
      if (linkedTwice) {
        rec.behaviour(w, h, DimensionBehaviour.matchConstraint);
        rec.matchStyle(w, h, ConstraintWidget.MATCH_CONSTRAINT_SPREAD, 0, 0, 1);
        rec.ratio(
          w,
          const [0.5, 1.0, 1.5, 1.7777778][rnd.nextInt(4)],
          h ? ConstraintWidget.HORIZONTAL : ConstraintWidget.VERTICAL,
        );
      }
    }
    if (rnd.nextInt(12) == 0 && i > 0) {
      final other = widgets[rnd.nextInt(i)];
      rec.baseline(w, w.getHeight() ~/ 2);
      rec.baseline(other, other.getHeight() ~/ 2);
      rec.reset(w, ConstraintAnchorType.top);
      rec.reset(w, ConstraintAnchorType.bottom);
      rec.connect(
        w,
        ConstraintAnchorType.baseline,
        other,
        ConstraintAnchorType.baseline,
        0,
      );
    }
    switch (rnd.nextInt(10)) {
      case 0:
        rec.visibility(w, ConstraintWidget.GONE);
      case 1:
        rec.visibility(w, ConstraintWidget.INVISIBLE);
    }
  }
  return rec.ops;
}

// ---------------------------------------------------------------------------
// rand: barrier_parity_test.dart's _randomLayout, verbatim on the recorder.
// ---------------------------------------------------------------------------
List<String> genRand(int seed) {
  final size = Random(seed);
  final rec = Rec(200 + 2 * size.nextInt(300), 200 + 2 * size.nextInt(300));
  final root = rec.root;
  final rnd = Random(seed);
  int even(int max) => 2 * rnd.nextInt(max ~/ 2 + 1);
  int margin() => rnd.nextInt(4) == 0 ? 0 : even(40);
  if (rnd.nextInt(6) == 0) rec.wrapW();
  if (rnd.nextInt(6) == 0) rec.wrapH();
  final widgetCount = 1 + rnd.nextInt(7);
  final widgets = <ConstraintWidget>[];
  for (var i = 0; i < widgetCount; i++) {
    widgets.add(rec.widget('w$i', 10 + even(150), 10 + even(100)));
  }
  final barriers = <Barrier>[];
  final barrierCount = 1 + rnd.nextInt(3);
  for (var i = 0; i < barrierCount; i++) {
    final type = rnd.nextInt(4);
    final m = rnd.nextInt(5) == 0 ? -even(30) : margin();
    final allows = rnd.nextBool();
    final gone = rnd.nextInt(12) == 0;
    final b = rec.barrier('b$i', type: type, margin: m, allowsGone: allows);
    if (gone) rec.visibility(b, ConstraintWidget.GONE);
    barriers.add(b);
  }
  for (final child in <ConstraintWidget>[
    ...widgets,
    ...barriers,
  ]..shuffle(rnd)) {
    rec.add(child);
  }
  for (final b in barriers) {
    final count = rnd.nextInt(4);
    for (var j = 0; j < count; j++) {
      if (rnd.nextInt(5) == 0 && barriers.length > 1) {
        final other = barriers[rnd.nextInt(barriers.length)];
        if (other != b) rec.ref(b, other);
      } else {
        rec.ref(b, widgets[rnd.nextInt(widgets.length)]);
      }
    }
    if (count == 0 && rnd.nextBool()) {
      rec.ref(b, widgets[rnd.nextInt(widgets.length)]);
    }
  }
  List<Barrier> along(int o) =>
      barriers.where((b) => b.getOrientation() == o).toList();
  final vertical = along(ConstraintWidget.HORIZONTAL);
  final horizontal = along(ConstraintWidget.VERTICAL);

  (ConstraintWidget, ConstraintAnchorType)? pick(int i, bool h) {
    final begin = h ? ConstraintAnchorType.left : ConstraintAnchorType.top;
    final end = h ? ConstraintAnchorType.right : ConstraintAnchorType.bottom;
    final side = rnd.nextBool() ? begin : end;
    final lines = h ? vertical : horizontal;
    final roll = rnd.nextInt(10);
    if (roll < 3) return (root, side);
    if (roll < 6 && lines.isNotEmpty) {
      return (lines[rnd.nextInt(lines.length)], side);
    }
    if (roll < 9 && i > 0) return (widgets[rnd.nextInt(i)], side);
    if (roll == 9) return (widgets[rnd.nextInt(widgets.length)], side);
    return null;
  }

  void link(
    ConstraintWidget w,
    ConstraintAnchorType from,
    (ConstraintWidget, ConstraintAnchorType)? to,
  ) {
    if (to == null || to.$1 == w) return;
    final other = to.$1;
    final h =
        from == ConstraintAnchorType.left || from == ConstraintAnchorType.right;
    for (final a
        in h ? [other.mLeft, other.mRight] : [other.mTop, other.mBottom]) {
      if (a.mTarget != null && a.mTarget!.mOwner == w) return;
    }
    rec.connect(w, from, to.$1, to.$2, margin());
  }

  for (final (i, w) in widgets.indexed) {
    for (final h in [true, false]) {
      final begin = h ? ConstraintAnchorType.left : ConstraintAnchorType.top;
      final end = h ? ConstraintAnchorType.right : ConstraintAnchorType.bottom;
      final kind = rnd.nextInt(10);
      if (rnd.nextInt(10) < 8) link(w, begin, pick(i, h));
      if (rnd.nextInt(10) < 5) link(w, end, pick(i, h));
      final linkedTwice =
          w.getAnchor(begin)!.isConnected() && w.getAnchor(end)!.isConnected();
      if (kind < 2) {
        rec.behaviour(w, h, DimensionBehaviour.wrapContent);
      } else if (kind < 4) {
        rec.behaviour(w, h, DimensionBehaviour.matchConstraint);
        final s = rnd.nextInt(4);
        if (s == 1 && linkedTwice) {
          final mn = even(60);
          rec.matchStyle(
            w,
            h,
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
            mn,
            rnd.nextInt(3) == 0 ? 0 : 40 + even(200),
            1,
          );
        } else if (s == 2) {
          rec.matchStyle(w, h, ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0, 1);
        }
      }
      if (rnd.nextInt(4) == 0) {
        rec.bias(w, h, const [0.0, 0.5, 1.0][rnd.nextInt(3)]);
      }
      if (rnd.nextInt(5) == 0) rec.goneMargin(w, begin, even(30));
    }
    switch (rnd.nextInt(10)) {
      case 0:
        rec.visibility(w, ConstraintWidget.GONE);
      case 1:
        rec.visibility(w, ConstraintWidget.INVISIBLE);
    }
  }
  return rec.ops;
}

// ---------------------------------------------------------------------------
// form: barrier_parity_test.dart's _formLayout, verbatim on the recorder.
// ---------------------------------------------------------------------------
List<String> genForm(int seed) {
  final size = Random(seed);
  final rec = Rec(320 + 2 * size.nextInt(200), 600 + 2 * size.nextInt(200));
  final root = rec.root;
  final rnd = Random(seed);
  int even(int max) => 2 * rnd.nextInt(max ~/ 2 + 1);
  final avatar = rec.widget(
    'avatar',
    40 + even(40),
    40 + even(40),
    add: true,
  );
  final title = rec.widget('title', 60 + even(160), 20 + even(20), add: true);
  rec.behaviour(title, true, DimensionBehaviour.wrapContent);
  final subtitle = rec.widget(
    'subtitle',
    40 + even(160),
    16 + even(40),
    add: true,
  );
  rec.connect(avatar, .left, root, .left, 16);
  rec.connect(avatar, .top, root, .top, 16);
  rec.connect(title, .left, avatar, .right, 12);
  rec.connect(title, .top, avatar, .top);
  rec.connect(subtitle, .left, title, .left);
  rec.connect(subtitle, .top, title, .bottom, 4);
  if (rnd.nextBool()) rec.visibility(subtitle, ConstraintWidget.GONE);
  final headerMargin = even(16);
  final headerGone = rnd.nextBool();
  final header = rec.barrier(
    'header',
    type: Barrier.bottom,
    margin: headerMargin,
    allowsGone: headerGone,
  );
  for (final r in [avatar, title, subtitle]) {
    rec.ref(header, r);
  }
  rec.add(header);
  final labels = <ConstraintWidget>[];
  final values = <ConstraintWidget>[];
  ConstraintWidget? above;
  final rows = 1 + rnd.nextInt(5);
  for (var i = 0; i < rows; i++) {
    final label = rec.widget('label$i', 30 + even(120), 20, add: true);
    rec.behaviour(label, true, DimensionBehaviour.wrapContent);
    final value = rec.widget(
      'value$i',
      40 + even(120),
      20 + even(20),
      add: true,
    );
    rec.connect(label, .left, root, .left, 16);
    rec.connect(label, .top, above ?? header, .bottom, above == null ? 12 : 8);
    rec.connect(value, .top, label, .top);
    labels.add(label);
    values.add(value);
    above = value.getHeight() > label.getHeight() ? value : label;
    if (rnd.nextInt(8) == 0) rec.visibility(label, ConstraintWidget.GONE);
  }
  final labelEndMargin = even(16);
  final labelEndGone = rnd.nextBool();
  final labelEnd = rec.barrier(
    'labelEnd',
    type: Barrier.right,
    margin: labelEndMargin,
    allowsGone: labelEndGone,
  );
  for (final l in labels) {
    rec.ref(labelEnd, l);
  }
  rec.add(labelEnd);
  final secondColumn = rnd.nextInt(3) == 0;
  for (final value in values) {
    rec.connect(value, .left, labelEnd, .right, 8);
    switch (rnd.nextInt(4)) {
      case 0:
        break;
      case 1:
        rec.behaviour(value, true, DimensionBehaviour.matchConstraint);
        rec.connect(value, .right, root, .right, 16);
      case 2:
        rec.connect(value, .right, root, .right, 16);
        rec.bias(value, true, const [0.0, 0.5, 1.0][rnd.nextInt(3)]);
      default:
        rec.behaviour(value, true, DimensionBehaviour.matchConstraint);
        rec.matchStyle(
          value,
          true,
          ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
          0,
          60 + even(100),
          1,
        );
        rec.connect(value, .right, root, .right, 16);
    }
    if (secondColumn) rec.behaviour(value, true, DimensionBehaviour.fixed);
  }
  if (secondColumn) {
    final withLabelEnd = rnd.nextBool();
    final valueEndMargin = even(12);
    final valueEnd = rec.barrier(
      'valueEnd',
      type: Barrier.right,
      margin: valueEndMargin,
    );
    for (final v in values) {
      rec.ref(valueEnd, v);
    }
    if (withLabelEnd) rec.ref(valueEnd, labelEnd);
    rec.add(valueEnd);
    final unit = rec.widget('unit', 20 + even(40), 20, add: true);
    rec.connect(unit, .left, valueEnd, .right, 4);
    rec.connect(unit, .top, values.first, .top);
  }
  final bottom = rec.barrier('bottom', type: Barrier.bottom);
  for (final x in [...labels, ...values]) {
    rec.ref(bottom, x);
  }
  rec.add(bottom);
  final footer = rec.widget('footer', 100, 40, add: true);
  rec.connect(footer, .top, bottom, .bottom, 16);
  switch (rnd.nextInt(3)) {
    case 0:
      rec.connect(footer, .left, root, .left, 16);
    case 1:
      rec.behaviour(footer, true, DimensionBehaviour.matchConstraint);
      rec.connect(footer, .left, root, .left, 16);
      rec.connect(footer, .right, root, .right, 16);
    default:
      rec.connect(footer, .left, labelEnd, .right);
      rec.connect(footer, .right, root, .right);
  }
  if (rnd.nextBool()) {
    rec.connect(footer, .bottom, root, .bottom, 16);
    rec.bias(footer, false, const [0.0, 0.5, 1.0][rnd.nextInt(3)]);
  }
  return rec.ops;
}

// ---------------------------------------------------------------------------
// formx: realistic screens. Odd sizes, RTL, centered titles and captions,
// percent guidelines and widths, baseline-aligned values, gone fields,
// button chains, nested barriers, negative margins now and then.
// ---------------------------------------------------------------------------
List<String> genFormX(int seed) {
  final rnd = Random(seed);
  final rec = Rec(280 + rnd.nextInt(820), 480 + rnd.nextInt(1000));
  final root = rec.root;
  int odd(int base, int span) => base + rnd.nextInt(span + 1);
  int pick(List<int> xs) => xs[rnd.nextInt(xs.length)];
  double pickD(List<double> xs) => xs[rnd.nextInt(xs.length)];
  bool chance(int n) => rnd.nextInt(n) == 0;
  if (chance(3)) rec.rtl();

  // Header: avatar, title, subtitle, an optional trailing action.
  final avatar = rec.widget('avatar', odd(32, 48), odd(32, 48), add: true);
  rec.connect(avatar, .left, root, .left, pick([0, 8, 12, 16, 24]));
  rec.connect(avatar, .top, root, .top, pick([0, 8, 16, 24]));
  ConstraintWidget? action;
  if (chance(2)) {
    action = rec.widget('action', odd(24, 40), odd(24, 40), add: true);
    rec.connect(action, .right, root, .right, pick([0, 8, 16]));
    rec.connect(action, .top, avatar, .top);
    if (chance(2)) {
      rec.connect(action, .bottom, avatar, .bottom);
    }
  }
  final title = rec.widget('title', odd(40, 200), odd(16, 16), add: true);
  rec.behaviour(title, true, DimensionBehaviour.wrapContent);
  rec.connect(title, .left, avatar, .right, pick([8, 12, 16]));
  switch (rnd.nextInt(3)) {
    case 0:
      rec.connect(title, .top, avatar, .top);
    case 1:
      rec.connect(title, .top, avatar, .top);
      rec.connect(title, .bottom, avatar, .bottom);
    default:
      rec.connect(title, .top, avatar, .top);
      rec.connect(title, .bottom, avatar, .bottom);
      rec.bias(title, false, pickD([0.0, 0.3, 0.5]));
  }
  if (action != null && chance(2)) {
    rec.connect(title, .right, action, .left, 8);
    if (chance(2)) {
      rec.behaviour(title, true, DimensionBehaviour.matchConstraint);
      if (chance(2)) {
        rec.matchStyle(
          title,
          true,
          ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
          0,
          odd(60, 200),
          1,
        );
      }
    } else {
      rec.bias(title, true, pickD([0.0, 0.5]));
    }
  }
  final subtitle = rec.widget('subtitle', odd(30, 180), odd(12, 30), add: true);
  rec.behaviour(subtitle, true, DimensionBehaviour.wrapContent);
  rec.connect(subtitle, .left, title, .left);
  rec.connect(subtitle, .top, title, .bottom, pick([0, 2, 4]));
  if (chance(3)) rec.visibility(subtitle, ConstraintWidget.GONE);
  final header = rec.barrier(
    'header',
    type: Barrier.bottom,
    margin: pick([0, 4, 8, 12, 16]),
    allowsGone: rnd.nextBool(),
  );
  for (final r in [avatar, title, subtitle, ?action]) {
    if (r == action && chance(2)) continue;
    rec.ref(header, r);
  }
  rec.add(header);

  // Optional percent guideline for the label column.
  Guideline? column;
  if (chance(3)) {
    column = rec.guideline('column', Guideline.vertical, add: true);
    if (chance(2)) {
      rec.guidePercent(column, pickD([0.25, 0.3, 0.33, 0.35, 0.4]));
    } else {
      rec.guideBegin(column, odd(60, 120));
    }
  }

  // Rows.
  final labels = <ConstraintWidget>[];
  final values = <ConstraintWidget>[];
  final units = <ConstraintWidget>[];
  ConstraintWidget above = header;
  final rows = 1 + rnd.nextInt(6);
  for (var i = 0; i < rows; i++) {
    final label = rec.widget('label$i', odd(24, 120), odd(14, 10), add: true);
    rec.behaviour(label, true, DimensionBehaviour.wrapContent);
    if (chance(4)) rec.behaviour(label, false, DimensionBehaviour.wrapContent);
    rec.connect(label, .left, root, .left, pick([12, 16, 20]));
    if (column != null && chance(2)) {
      rec.connect(label, .right, column, .left, pick([0, 8]));
      rec.bias(label, true, pickD([0.0, 1.0]));
    }
    rec.connect(label, .top, above, .bottom, pick([4, 8, 12]));
    final value = rec.widget('value$i', odd(30, 160), odd(16, 24), add: true);
    switch (rnd.nextInt(4)) {
      case 0:
        rec.connect(value, .top, label, .top);
      case 1:
        rec.baseline(label, label.getHeight() * 3 ~/ 4);
        rec.baseline(value, value.getHeight() * 3 ~/ 4);
        rec.connect(value, .baseline, label, .baseline);
      case 2:
        rec.connect(value, .top, label, .top);
        rec.connect(value, .bottom, label, .bottom);
      default:
        rec.connect(value, .top, above, .bottom, pick([4, 8]));
    }
    labels.add(label);
    values.add(value);
    if (chance(5)) {
      final unit = rec.widget('unit$i', odd(12, 30), odd(14, 10), add: true);
      rec.behaviour(unit, true, DimensionBehaviour.wrapContent);
      rec.connect(unit, .right, root, .right, pick([12, 16]));
      rec.connect(unit, .top, value, .top);
      if (chance(2)) rec.connect(unit, .bottom, value, .bottom);
      units.add(unit);
    }
    if (chance(8)) rec.visibility(label, ConstraintWidget.GONE);
    if (chance(10)) rec.visibility(value, ConstraintWidget.GONE);
    // The next row goes below a row barrier, or below the taller of the two.
    if (chance(3)) {
      final rowBottom = rec.barrier(
        'row$i',
        type: Barrier.bottom,
        allowsGone: rnd.nextBool(),
      );
      rec.ref(rowBottom, label);
      rec.ref(rowBottom, value);
      rec.add(rowBottom);
      above = rowBottom;
    } else {
      above = value.getHeight() >= label.getHeight() ? value : label;
    }
  }
  final labelEnd = rec.barrier(
    'labelEnd',
    type: Barrier.right,
    margin: pick([0, 0, 8, 12, -4]),
    allowsGone: rnd.nextBool(),
  );
  for (final l in labels) {
    rec.ref(labelEnd, l);
  }
  if (column != null && chance(2)) rec.ref(labelEnd, column);
  rec.add(labelEnd);
  for (final (i, value) in values.indexed) {
    rec.connect(value, .left, labelEnd, .right, pick([0, 8, 12]));
    final unit = units.where((u) => u.getDebugName() == 'unit$i').firstOrNull;
    final endTarget = unit ?? root;
    final endAnchor = unit != null
        ? ConstraintAnchorType.left
        : ConstraintAnchorType.right;
    switch (rnd.nextInt(6)) {
      case 0:
        break;
      case 1:
        rec.behaviour(value, true, DimensionBehaviour.matchConstraint);
        rec.connect(value, .right, endTarget, endAnchor, pick([8, 16]));
      case 2:
        rec.connect(value, .right, endTarget, endAnchor, pick([8, 16]));
        rec.bias(value, true, pickD([0.0, 0.5, 1.0, 0.3]));
      case 3:
        rec.behaviour(value, true, DimensionBehaviour.matchConstraint);
        rec.matchStyle(
          value,
          true,
          ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
          chance(3) ? odd(20, 60) : 0,
          odd(60, 160),
          1,
        );
        rec.connect(value, .right, endTarget, endAnchor, pick([8, 16]));
      case 4:
        rec.behaviour(value, true, DimensionBehaviour.matchConstraint);
        rec.matchStyle(
          value,
          true,
          ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
          0,
          chance(3) ? odd(60, 160) : 0,
          pickD([0.3, 0.4, 0.5, 0.25]),
        );
        if (chance(2)) {
          rec.connect(value, .right, endTarget, endAnchor, pick([8, 16]));
        }
      default:
        rec.behaviour(value, true, DimensionBehaviour.wrapContent);
        rec.connect(value, .right, endTarget, endAnchor, pick([8, 16]));
        rec.bias(value, true, pickD([0.0, 1.0]));
    }
  }

  // Optional second column past the values.
  if (chance(4)) {
    final valueEnd = rec.barrier(
      'valueEnd',
      type: Barrier.right,
      margin: pick([0, 4, 8]),
    );
    for (final v in values) {
      if (v.getHorizontalDimensionBehaviour() !=
          DimensionBehaviour.matchConstraint) {
        rec.ref(valueEnd, v);
      }
    }
    if (chance(2)) rec.ref(valueEnd, labelEnd);
    rec.add(valueEnd);
    final extra = rec.widget('extra', odd(16, 40), odd(16, 20), add: true);
    rec.connect(extra, .left, valueEnd, .right, pick([0, 4, 8]));
    rec.connect(extra, .top, values.first, .top);
    if (chance(2)) {
      rec.connect(extra, .right, root, .right, pick([0, 8]));
      rec.bias(extra, true, pickD([0.0, 0.5]));
    }
  }

  final bottom = rec.barrier(
    'bottom',
    type: Barrier.bottom,
    margin: pick([0, 8, 16]),
    allowsGone: rnd.nextBool(),
  );
  for (final x in [...labels, ...values, ...units]) {
    if (chance(6)) continue;
    rec.ref(bottom, x);
  }
  if (above != header && above is Barrier && chance(2)) rec.ref(bottom, above);
  rec.add(bottom);

  // Footer: a caption centered under the form, then a button bar.
  if (chance(2)) {
    final caption = rec.widget('caption', odd(40, 200), odd(14, 10), add: true);
    rec.behaviour(caption, true, DimensionBehaviour.wrapContent);
    rec.connect(caption, .left, root, .left, pick([0, 16]));
    rec.connect(caption, .right, root, .right, pick([0, 16]));
    rec.connect(caption, .top, bottom, .bottom, pick([0, 8]));
    if (chance(3)) rec.bias(caption, true, pickD([0.0, 0.3]));
  }
  final buttons = 1 + rnd.nextInt(3);
  final bar = <ConstraintWidget>[
    for (var i = 0; i < buttons; i++)
      rec.widget('btn$i', odd(48, 100), odd(32, 16), add: true),
  ];
  final style = rnd.nextInt(3);
  for (final (i, b) in bar.indexed) {
    rec.connect(b, .top, bottom, .bottom, pick([8, 16, 24]));
    if (chance(3)) {
      rec.connect(b, .bottom, root, .bottom, pick([0, 16]));
      rec.bias(b, false, pickD([0.0, 1.0]));
    }
    if (i == 0) {
      rec.connect(b, .left, root, .left, pick([0, 16]));
    } else {
      rec.connect(b, .left, bar[i - 1], .right, 0);
    }
    if (i == buttons - 1) {
      rec.connect(b, .right, root, .right, pick([0, 16]));
    } else {
      rec.connect(b, .right, bar[i + 1], .left, 0);
    }
  }
  if (buttons > 1) {
    rec.chainStyle(bar.first, true, style);
    if (chance(2)) {
      for (final b in bar) {
        rec.behaviour(b, true, DimensionBehaviour.matchConstraint);
        if (chance(3)) rec.weight(b, true, pickD([1.0, 2.0]));
      }
    }
  } else if (chance(2)) {
    rec.bias(bar.first, true, pickD([0.0, 0.5, 1.0]));
  }
  if (chance(6)) rec.visibility(bar.last, ConstraintWidget.GONE);
  return rec.ops;
}

// ---------------------------------------------------------------------------
// chainy: chains, guidelines and barriers wired into each other. Chain ends
// on barriers and guidelines, barriers over chain members, odd sizes,
// percent widths and RTL.
// ---------------------------------------------------------------------------
List<String> genChainy(int seed) {
  final rnd = Random(seed);
  final rec = Rec(240 + rnd.nextInt(700), 240 + rnd.nextInt(700));
  final root = rec.root;
  bool chance(int n) => rnd.nextInt(n) == 0;
  int pick(List<int> xs) => xs[rnd.nextInt(xs.length)];
  if (chance(3)) rec.rtl();
  final guides = <Guideline>[];
  for (var i = 0; i < rnd.nextInt(3); i++) {
    final g = rec.guideline(
      'g$i',
      rnd.nextBool() ? Guideline.vertical : Guideline.horizontal,
      add: true,
    );
    switch (rnd.nextInt(3)) {
      case 0:
        rec.guidePercent(g, const [0.2, 0.25, 0.3, 0.5, 0.7][rnd.nextInt(5)]);
      case 1:
        rec.guideBegin(g, rnd.nextInt(200));
      default:
        rec.guideEnd(g, rnd.nextInt(200));
    }
    guides.add(g);
  }
  final n = 2 + rnd.nextInt(6);
  final widgets = [
    for (var i = 0; i < n; i++)
      rec.widget('w$i', 10 + rnd.nextInt(120), 10 + rnd.nextInt(80)),
  ];
  final barriers = [
    for (var i = 0; i < 1 + rnd.nextInt(3); i++)
      rec.barrier(
        'b$i',
        type: rnd.nextInt(4),
        margin: chance(4) ? 0 : pick([4, 8, 12, -6]),
        allowsGone: rnd.nextBool(),
      ),
  ];
  final order = <ConstraintWidget>[...widgets, ...barriers]..shuffle(rnd);
  for (final c in order) {
    rec.add(c);
  }
  // References first (so the orientation is known for chain ends).
  for (final b in barriers) {
    final k = 1 + rnd.nextInt(3);
    for (var j = 0; j < k; j++) {
      if (chance(6) && barriers.length > 1) {
        final o = barriers[rnd.nextInt(barriers.length)];
        if (o != b) rec.ref(b, o);
      } else {
        rec.ref(b, widgets[rnd.nextInt(widgets.length)]);
      }
    }
  }
  final chained = <ConstraintWidget, bool>{};
  // One or two chains among disjoint members.
  var next = 0;
  for (var c = 0; c < 1 + rnd.nextInt(2) && next + 2 <= n; c++) {
    final len = min(n - next, 2 + rnd.nextInt(3));
    final members = widgets.sublist(next, next + len);
    next += len;
    final h = rnd.nextBool();
    final begin = h ? ConstraintAnchorType.left : ConstraintAnchorType.top;
    final end = h ? ConstraintAnchorType.right : ConstraintAnchorType.bottom;
    final lines = barriers
        .where(
          (b) =>
              b.getOrientation() ==
              (h ? ConstraintWidget.HORIZONTAL : ConstraintWidget.VERTICAL),
        )
        .toList();
    final axisGuides = guides
        .where(
          (g) =>
              g.getOrientation() ==
              (h ? Guideline.vertical : Guideline.horizontal),
        )
        .toList();
    (ConstraintWidget, ConstraintAnchorType) endTarget(bool atBegin) {
      final roll = rnd.nextInt(5);
      if (roll == 0 && lines.isNotEmpty) {
        return (lines[rnd.nextInt(lines.length)], atBegin ? end : begin);
      }
      if (roll == 1 && axisGuides.isNotEmpty) {
        return (axisGuides[rnd.nextInt(axisGuides.length)], begin);
      }
      return (root, atBegin ? begin : end);
    }

    final head = endTarget(true);
    final tail = endTarget(false);
    rec.connect(members.first, begin, head.$1, head.$2, pick([0, 0, 8, 16]));
    for (var k = 0; k + 1 < members.length; k++) {
      rec.connect(members[k], end, members[k + 1], begin, pick([0, 0, 4]));
      rec.connect(members[k + 1], begin, members[k], end, pick([0, 0, 4]));
    }
    rec.connect(members.last, end, tail.$1, tail.$2, pick([0, 0, 8, 16]));
    rec.chainStyle(members.first, h, rnd.nextInt(3));
    final allMatch = chance(2);
    for (final m in members) {
      chained[m] = h;
      if (allMatch || chance(4)) {
        rec.behaviour(m, h, DimensionBehaviour.matchConstraint);
        if (chance(4)) {
          rec.matchStyle(
            m,
            h,
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
            0,
            40 + rnd.nextInt(80),
            1,
          );
        }
        if (chance(3)) rec.weight(m, h, (1 + rnd.nextInt(3)).toDouble());
      } else if (chance(4)) {
        rec.behaviour(m, h, DimensionBehaviour.wrapContent);
      }
    }
    if (chance(4)) rec.bias(members.first, h, pick([0, 3, 5, 10]) / 10);
  }
  // Every widget's other axis (and unchained widgets' both axes).
  for (final (i, w) in widgets.indexed) {
    for (final h in [true, false]) {
      if (chained[w] == h) continue;
      final begin = h ? ConstraintAnchorType.left : ConstraintAnchorType.top;
      final end = h ? ConstraintAnchorType.right : ConstraintAnchorType.bottom;
      final lines = barriers
          .where(
            (b) =>
                b.getOrientation() ==
                (h ? ConstraintWidget.HORIZONTAL : ConstraintWidget.VERTICAL),
          )
          .toList();
      (ConstraintWidget, ConstraintAnchorType) target() {
        final side = rnd.nextBool() ? begin : end;
        final roll = rnd.nextInt(8);
        if (roll < 3) return (root, side);
        if (roll < 5 && lines.isNotEmpty) {
          return (lines[rnd.nextInt(lines.length)], side);
        }
        if (roll < 7 && i > 0) return (widgets[rnd.nextInt(i)], side);
        return (root, side);
      }

      bool ok(ConstraintWidget other) {
        if (other == w) return false;
        for (final a
            in h ? [other.mLeft, other.mRight] : [other.mTop, other.mBottom]) {
          if (a.mTarget != null && a.mTarget!.mOwner == w) return false;
        }
        return true;
      }

      final t1 = target();
      if (ok(t1.$1)) rec.connect(w, begin, t1.$1, t1.$2, pick([0, 8, 16]));
      if (chance(2)) {
        final t2 = target();
        if (ok(t2.$1)) rec.connect(w, end, t2.$1, t2.$2, pick([0, 8, 16]));
      }
      if (chance(4)) rec.bias(w, h, pick([0, 3, 5, 7, 10]) / 10);
      if (chance(6)) {
        rec.behaviour(w, h, DimensionBehaviour.matchConstraint);
        if (chance(2)) {
          rec.matchStyle(
            w,
            h,
            ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
            0,
            0,
            const [0.2, 0.25, 0.3, 0.5][rnd.nextInt(4)],
          );
        }
      }
    }
    if (chance(10)) rec.visibility(w, ConstraintWidget.GONE);
  }
  return rec.ops;
}

// ---------------------------------------------------------------------------
// crossed: widgets centered between links that cross (the begin target after
// the end target), along either axis, gone or visible, with guidelines
// (whole or percent), dependents with one or two links, and a barrier.
// ---------------------------------------------------------------------------
List<String> genCrossed(int seed) {
  final rnd = Random(seed);
  final rec = Rec(200 + rnd.nextInt(700), 200 + rnd.nextInt(700));
  final root = rec.root;
  final h = rnd.nextBool();
  final begin = h ? ConstraintAnchorType.left : ConstraintAnchorType.top;
  final end = h ? ConstraintAnchorType.right : ConstraintAnchorType.bottom;
  final g = rec.guideline(
    'g0',
    h ? Guideline.vertical : Guideline.horizontal,
    add: true,
  );
  if (rnd.nextBool()) {
    rec.guidePercent(g, const [0.25, 0.3, 0.5, 0.7][rnd.nextInt(4)]);
  } else {
    rec.guideBegin(g, 50 + rnd.nextInt(300));
  }
  final w1 = rec.widget(
    'w1',
    10 + rnd.nextInt(100),
    10 + rnd.nextInt(100),
    add: true,
  );
  // Crossed: begin after end.
  rec.connect(
    w1,
    begin,
    rnd.nextBool() ? g : root,
    rnd.nextBool() ? begin : end,
    rnd.nextInt(3) * 8,
  );
  rec.connect(w1, end, root, begin, rnd.nextInt(2) * 8);
  if (rnd.nextInt(3) == 0) {
    rec.bias(w1, h, const [0.0, 0.3, 0.5, 1.0][rnd.nextInt(4)]);
  }
  if (rnd.nextBool()) rec.visibility(w1, ConstraintWidget.GONE);
  final w0 = rec.widget(
    'w0',
    10 + rnd.nextInt(80),
    10 + rnd.nextInt(80),
    add: true,
  );
  rec.connect(w0, begin, w1, rnd.nextBool() ? begin : end, rnd.nextInt(2) * 6);
  if (rnd.nextBool()) {
    rec.connect(w0, end, root, end, 0);
  }
  final b = rec.barrier(
    'b0',
    type: h
        ? (rnd.nextBool() ? Barrier.left : Barrier.right)
        : (rnd.nextBool() ? Barrier.top : Barrier.bottom),
    add: true,
  );
  rec.ref(b, rnd.nextBool() ? w0 : w1);
  final w2 = rec.widget('w2', 20, 20, add: true);
  rec.connect(w2, begin, b, end, 0);
  return rec.ops;
}

// ---------------------------------------------------------------------------
// cards: centered content, the half-pixel cascades of real screens. A card
// centered in the container, an icon centered in it, a caption centered
// under the icon, a badge on the icon's corner, a title row with a barrier,
// and buttons centered under a bottom barrier. Odd sizes everywhere, RTL,
// gone toggles, percent widths now and then.
// ---------------------------------------------------------------------------
List<String> genCards(int seed) {
  final rnd = Random(seed);
  final rec = Rec(240 + rnd.nextInt(860), 320 + rnd.nextInt(1100));
  final root = rec.root;
  bool chance(int n) => rnd.nextInt(n) == 0;
  int odd(int base, int span) => base + rnd.nextInt(span + 1);
  double pickD(List<double> xs) => xs[rnd.nextInt(xs.length)];
  if (chance(3)) rec.rtl();
  final card = rec.widget('card', odd(120, 400), odd(80, 300), add: true);
  rec.connect(card, .left, root, .left, chance(2) ? 0 : odd(0, 24));
  rec.connect(card, .right, root, .right, chance(2) ? 0 : odd(0, 24));
  rec.connect(card, .top, root, .top, odd(0, 40));
  if (chance(2)) {
    rec.connect(card, .bottom, root, .bottom, odd(0, 40));
    if (chance(3)) rec.bias(card, false, pickD([0.3, 0.5, 0.0]));
  }
  if (chance(4)) {
    rec.behaviour(card, true, DimensionBehaviour.matchConstraint);
    if (chance(2)) {
      rec.matchStyle(
        card,
        true,
        ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
        0,
        0,
        pickD([0.8, 0.9, 0.75]),
      );
    }
  }
  if (chance(3)) {
    final image = rec.widget('image', odd(40, 200), odd(30, 120), add: true);
    rec.connect(image, .left, card, .left, odd(0, 8));
    rec.connect(image, .right, card, .right, odd(0, 8));
    rec.connect(image, .top, card, .top, odd(0, 8));
    rec.behaviour(image, true, DimensionBehaviour.matchConstraint);
    if (chance(2)) {
      rec.behaviour(image, false, DimensionBehaviour.matchConstraint);
    }
    rec.ratio(
      image,
      pickD([1.7777778, 1.3333334, 1.0]),
      ConstraintWidget.VERTICAL,
    );
    if (chance(2)) {
      final under = rec.widget('under', odd(20, 100), odd(10, 20), add: true);
      rec.connect(under, .top, image, .bottom, odd(0, 8));
      rec.connect(under, .left, image, .left);
      rec.connect(under, .right, image, .right);
    }
  }
  final icon = rec.widget('icon', odd(16, 64), odd(16, 64), add: true);
  rec.connect(icon, .left, card, .left);
  rec.connect(icon, .right, card, .right);
  rec.connect(icon, .top, card, .top, odd(0, 24));
  if (chance(3)) rec.bias(icon, true, pickD([0.0, 0.3, 1.0]));
  final caption = rec.widget('caption', odd(20, 200), odd(10, 20), add: true);
  rec.behaviour(caption, true, DimensionBehaviour.wrapContent);
  rec.connect(caption, .left, icon, .left);
  rec.connect(caption, .right, icon, .right);
  rec.connect(caption, .top, icon, .bottom, odd(0, 12));
  if (chance(3)) {
    final badge = rec.widget('badge', odd(6, 20), odd(6, 20), add: true);
    rec.connect(badge, .left, icon, .right);
    rec.connect(badge, .right, icon, .right);
    rec.connect(badge, .top, icon, .top);
    rec.connect(badge, .bottom, icon, .top);
  }
  if (chance(5)) rec.visibility(caption, ConstraintWidget.GONE);
  final title = rec.widget('title', odd(30, 200), odd(14, 20), add: true);
  rec.behaviour(title, true, DimensionBehaviour.wrapContent);
  rec.connect(title, .left, card, .left, odd(0, 16));
  rec.connect(title, .top, caption, .bottom, odd(0, 12));
  final value = rec.widget('value', odd(30, 150), odd(14, 30), add: true);
  final titleEnd = rec.barrier(
    'titleEnd',
    type: Barrier.right,
    margin: odd(0, 12),
    allowsGone: rnd.nextBool(),
  );
  rec.ref(titleEnd, title);
  if (chance(2)) rec.ref(titleEnd, caption);
  rec.add(titleEnd);
  rec.connect(value, .left, titleEnd, .right);
  rec.connect(value, .right, card, .right, odd(0, 16));
  if (chance(2)) {
    rec.behaviour(value, true, DimensionBehaviour.matchConstraint);
  } else {
    rec.bias(value, true, pickD([0.0, 0.5, 1.0]));
  }
  if (chance(2)) {
    rec.connect(value, .top, title, .top);
    rec.connect(value, .bottom, title, .bottom);
  } else {
    rec.baseline(title, title.getHeight() * 3 ~/ 4);
    rec.baseline(value, value.getHeight() * 3 ~/ 4);
    rec.connect(value, .baseline, title, .baseline);
  }
  if (chance(6)) rec.visibility(value, ConstraintWidget.GONE);
  final bottom = rec.barrier(
    'bottom',
    type: Barrier.bottom,
    margin: odd(0, 16),
    allowsGone: rnd.nextBool(),
  );
  for (final w in [title, value, caption, icon]) {
    if (!chance(4)) rec.ref(bottom, w);
  }
  rec.add(bottom);
  final n = 1 + rnd.nextInt(2);
  for (var i = 0; i < n; i++) {
    final b = rec.widget('btn$i', odd(40, 100), odd(24, 20), add: true);
    rec.connect(b, .top, bottom, .bottom, odd(0, 16));
    if (n == 1 || chance(2)) {
      rec.connect(b, .left, card, .left);
      rec.connect(b, .right, card, .right);
      if (chance(3)) rec.bias(b, true, pickD([0.0, 1.0, 0.3]));
    } else {
      rec.connect(
        b,
        i == 0 ? .left : .right,
        card,
        i == 0 ? .left : .right,
        odd(0, 16),
      );
    }
  }
  return rec.ops;
}

// ---------------------------------------------------------------------------
// nest: barriers over barriers. Rows and columns of widgets, a barrier per
// group, barriers over those, widgets centered or offset on any of them,
// gone members and allowsGone both ways, odd sizes and margins.
// ---------------------------------------------------------------------------
List<String> genNest(int seed) {
  final rnd = Random(seed);
  final rec = Rec(300 + rnd.nextInt(700), 300 + rnd.nextInt(900));
  final root = rec.root;
  bool chance(int n) => rnd.nextInt(n) == 0;
  int odd(int base, int span) => base + rnd.nextInt(span + 1);
  if (chance(4)) rec.rtl();
  final h = rnd.nextBool();
  final begin = h ? ConstraintAnchorType.left : ConstraintAnchorType.top;
  final end = h ? ConstraintAnchorType.right : ConstraintAnchorType.bottom;
  final across = h ? ConstraintAnchorType.top : ConstraintAnchorType.left;
  final groups = 2 + rnd.nextInt(3);
  final level1 = <Barrier>[];
  var k = 0;
  for (var gi = 0; gi < groups; gi++) {
    final members = <ConstraintWidget>[];
    for (var i = 0; i < 1 + rnd.nextInt(3); i++) {
      final w = rec.widget('w$k', odd(10, 120), odd(10, 80), add: true);
      k++;
      if (level1.isEmpty || chance(3)) {
        rec.connect(w, begin, root, begin, odd(0, 40));
      } else {
        rec.connect(
          w,
          begin,
          level1[rnd.nextInt(level1.length)],
          end,
          odd(0, 12),
        );
      }
      rec.connect(w, across, root, across, odd(0, 400));
      if (chance(3)) {
        rec.connect(w, end, root, end, odd(0, 40));
        rec.bias(w, h, const [0.0, 0.5, 1.0, 0.3][rnd.nextInt(4)]);
      }
      if (chance(6)) rec.behaviour(w, h, DimensionBehaviour.wrapContent);
      if (chance(8)) rec.visibility(w, ConstraintWidget.GONE);
      members.add(w);
    }
    final b = rec.barrier(
      'b$gi',
      type: h ? Barrier.right : Barrier.bottom,
      margin: chance(3) ? 0 : odd(0, 16),
      allowsGone: rnd.nextBool(),
    );
    for (final m in members) {
      rec.ref(b, m);
    }
    if (level1.isNotEmpty && chance(2)) {
      rec.ref(b, level1[rnd.nextInt(level1.length)]);
    }
    rec.add(b);
    level1.add(b);
  }
  final top = rec.barrier(
    'top',
    type: h ? Barrier.right : Barrier.bottom,
    margin: odd(0, 8),
  );
  for (final b in level1) {
    if (!chance(3)) rec.ref(top, b);
  }
  rec.add(top);
  for (var i = 0; i < 1 + rnd.nextInt(3); i++) {
    final w = rec.widget('t$i', odd(10, 100), odd(10, 60), add: true);
    final anchor = chance(2) ? top : level1[rnd.nextInt(level1.length)];
    rec.connect(w, begin, anchor, end, odd(0, 12));
    rec.connect(w, across, root, across, odd(0, 300));
    if (chance(2)) {
      rec.connect(w, end, root, end, odd(0, 20));
      if (chance(2)) rec.bias(w, h, const [0.0, 0.5, 1.0][rnd.nextInt(3)]);
      if (chance(4)) rec.behaviour(w, h, DimensionBehaviour.matchConstraint);
    }
  }
  return rec.ops;
}
