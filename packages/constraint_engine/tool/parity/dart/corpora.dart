// The Phase 0 corpora R, VR and A as generator functions of a seed
// (FORMATS.md section 3). T lives in tgens.dart.
//
// R reproduces BL's bfuzz pipeline exactly (run_variant.sh with adeps):
//   f: generators   gen(seed), --prep (prepareOps), then adeps
//   c: generators   gen(seed), [--strip], --respec, then adeps
// with the barrier filter (--bar or --nobar) applied after the transforms,
// so the R ids and op lists equal those of BL's own adeps run.
// VR is R's op list with content (FORMATS.md 4.3).
// VR2 (Phase 1, FORMATS.md 16) is VR with every guideline oriented at
// creation (fspec orientGuidelinesFirst), as Android and the adapter orient
// it; R and VR stay byte-identical to Phase 0.
// A is the 18 raw generators of excrun.sh, as excfind replays them.
//
// R, VR and VR2 depend on the engine the generator runs on: respec (the rsc*
// and nbrsc* labels) replays the raw ops and reads back float fields (bias,
// ratio, weight, percent) to print them. They equal Phase 0's (and BL's)
// only with today's engine and Phase 0's parse (vfuzz compiled against
// dc0dc6a with -Dcl.doubleparse=true). With a Phase 1 engine, replay the
// saved corpus files (vfuzz --corpus) instead of regenerating them.
import 'package:constraint_engine/constraint_engine.dart';

import 'fgens.dart' as fg;
import 'fspec.dart' show orientGuidelinesFirst, prepareOps;
import 'gens.dart' as cg;
import 'ops.dart';
import 'respec.dart';
import 'tgens.dart' as tg;
import 'vgens.dart' as vg;

/// A corpus generator: the op list of [seed], or null when the seed is
/// filtered out (R's barrier filter). Throws on a generator error.
typedef CorpusGen = List<String>? Function(int seed);

/// BL's withPrep (bfuzz.dart): the adapter's _prepareContainer appended.
List<String> withPrep(List<String> ops) {
  final (w, h) = rootSize(ops);
  var rtl = false, wrapW = false, wrapH = false;
  for (final o in ops) {
    if (o == 'rtl') rtl = true;
    if (o == 'ltr') rtl = false;
    if (o == 'wrapw') wrapW = true;
    if (o == 'wraph') wrapH = true;
    if (o == 'fixw') wrapW = false;
    if (o == 'fixh') wrapH = false;
  }
  return [...ops, ...prepareOps(w, h, ltr: !rtl, wrapW: wrapW, wrapH: wrapH)];
}

/// engine-final's transform (ffuzz.dart stripBarriers), copied verbatim: a
/// link to a barrier is re-targeted to the same edge of its first widget
/// reference, else dropped.
List<String> stripBarriers(List<String> ops) {
  final barriers = <String>{};
  final refs = <String, List<String>>{};
  final createdAt = <String, int>{};
  final guidelines = <String>{};
  for (var i = 0; i < ops.length; i++) {
    final t = ops[i].split(' ');
    switch (t[0]) {
      case 'b':
        barriers.add(t[1]);
        createdAt[t[1]] = i;
      case 'w':
        createdAt[t[1]] = i;
      case 'g':
        guidelines.add(t[1]);
        createdAt[t[1]] = i;
      case 'ref':
        (refs[t[1]] ??= []).add(t[2]);
    }
  }
  if (barriers.isEmpty) return ops;
  String? widgetOf(String barrier, Set<String> seen) {
    if (!seen.add(barrier)) return null;
    for (final r in refs[barrier] ?? const <String>[]) {
      if (barriers.contains(r)) {
        final w = widgetOf(r, seen);
        if (w != null) return w;
      } else if (!guidelines.contains(r)) {
        return r;
      }
    }
    return null;
  }

  final out = <String>[];
  for (var i = 0; i < ops.length; i++) {
    final t = ops[i].split(' ');
    if (t.length > 1 && barriers.contains(t[1])) continue;
    if (t[0] == 'ref') continue;
    if (t[0] == 'c' && barriers.contains(t[3])) {
      final w = widgetOf(t[3], {});
      if (w == null || w == t[1] || createdAt[w]! > i) continue;
      out.add('c ${t[1]} ${t[2]} $w ${t[4]} ${t[5]}');
      continue;
    }
    out.add(ops[i]);
  }
  return out;
}

bool hasBarrier(List<String> ops) => ops.any((o) => o.startsWith('b '));

/// One R generator: BL's bfuzz with [kind] (c or f), [name], the transforms
/// and the barrier filter, then the adeps state.
CorpusGen _r(
  String kind,
  String name, {
  bool strip = false,
  bool re = false,
  bool prep = false,
  required bool bar,
}) {
  final gen = kind == 'c' ? cg.generators[name]! : fg.fgenerators[name]!;
  return (seed) {
    var ops = gen(seed);
    if (strip) ops = stripBarriers(ops);
    if (re) ops = respec(ops);
    if (prep && !re) ops = withPrep(ops);
    ops = [...ops, 'adeps'];
    if (hasBarrier(ops) != bar) return null;
    return ops;
  };
}

/// R: BL's 16 labels (run_variant.sh).
final Map<String, CorpusGen> rGenerators = {
  'fflist': _r('f', 'flist', prep: true, bar: true),
  'ffrtl': _r('f', 'frtl', prep: true, bar: true),
  'ffsettings': _r('f', 'fsettings', prep: true, bar: true),
  'ffchat': _r('f', 'fchat', prep: true, bar: true),
  'fftoolbar': _r('f', 'ftoolbar', prep: true, bar: true),
  'rscform': _r('c', 'form', re: true, bar: true),
  'rsccards': _r('c', 'cards', re: true, bar: true),
  'rscnest': _r('c', 'nest', re: true, bar: true),
  'fnlist': _r('f', 'nlist', prep: true, bar: false),
  'fnrtl': _r('f', 'nrtl', prep: true, bar: false),
  'fnsettings': _r('f', 'nsettings', prep: true, bar: false),
  'fnchat': _r('f', 'nchat', prep: true, bar: false),
  'fntoolbar': _r('f', 'ntoolbar', prep: true, bar: false),
  'nbrscform': _r('c', 'form', strip: true, re: true, bar: false),
  'nbrsccards': _r('c', 'cards', strip: true, re: true, bar: false),
  'nbrscnest': _r('c', 'nest', strip: true, re: true, bar: false),
};

/// The VR content of a widget whose `w` op gave [cw] x [ch], FIXED on the
/// axes [fixedH] and [fixedV], with text baseline [bl] (-1 for none):
/// FORMATS.md 4.3, step 3.
String vrContentOp(
  String id,
  int cw,
  int ch,
  bool fixedH,
  bool fixedV,
  int bl,
) {
  if (fixedH && fixedV) return 'ct $id box $cw $ch $bl';
  if (cw > 0 && ch > 0) return 'ct $id text $cw $ch $bl';
  if (cw > 0 && ch == 0) return 'ct $id text $cw 20 $bl';
  return 'ct $id box $cw $ch $bl';
}

/// VR: R's op list [ops] with content (FORMATS.md 4.3).
List<String> toVR(List<String> ops) {
  final hb = <String, String>{}, vb = <String, String>{};
  final bl = <String, int>{};
  for (final o in ops) {
    final t = o.split(' ');
    switch (t[0]) {
      case 'hb':
        hb[t[1]] = t[2];
      case 'vb':
        vb[t[1]] = t[2];
      case 'bl':
        bl[t[1]] = int.parse(t[2]);
    }
  }
  final out = <String>[];
  for (final o in ops) {
    final t = o.split(' ');
    switch (t[0]) {
      case 'bl':
        continue;
      case 'sw' || 'sh':
        throw ArgumentError('toVR expects a fresh R layout, found $o');
      case 'w':
        final id = t[1];
        final cw = int.parse(t[2]), ch = int.parse(t[3]);
        final fixedH = (hb[id] ?? 'F') == 'F';
        final fixedV = (vb[id] ?? 'F') == 'F';
        out.add('w $id ${fixedH ? cw : 0} ${fixedV ? ch : 0}');
        final b = (bl[id] ?? 0) > 0 ? bl[id]! : -1;
        out.add(vrContentOp(id, cw, ch, fixedH, fixedV, b));
      default:
        out.add(o);
    }
  }
  return out;
}

/// VR: one generator per R generator.
final Map<String, CorpusGen> vrGenerators = {
  for (final e in rGenerators.entries)
    'VR-${e.key}': (seed) {
      final ops = e.value(seed);
      return ops == null ? null : toVR(ops);
    },
};

/// VR2: one generator per R generator, the R layout emitted with every
/// guideline oriented at creation (`g`, `go`, `add`; the config `go` stays, a
/// no-op as in the adapter), then VR's content transform. Only the labels with
/// guidelines (ffrtl, fnrtl) change; a link from an earlier sibling into a
/// vertical guideline's left or right edge is kept instead of dropped.
final Map<String, CorpusGen> vr2Generators = {
  for (final e in rGenerators.entries)
    'VR2-${e.key}': (seed) {
      final saved = orientGuidelinesFirst;
      orientGuidelinesFirst = true;
      try {
        final ops = e.value(seed);
        return ops == null ? null : toVR(ops);
      } finally {
        orientGuidelinesFirst = saved;
      }
    },
};

/// A: the 18 generators of excrun.sh, raw.
const aConverge = [
  'form',
  'formx',
  'rand',
  'ext',
  'extl',
  'chainy',
  'crossed',
  'cards',
  'nest',
];
const aVerify = [
  'vform',
  'vprofile',
  'vcard',
  'vtoolbar',
  'vgrid',
  'vcenter',
  'vadv',
  'vext',
  'vext2',
];

final Map<String, CorpusGen> aGenerators = {
  for (final n in aConverge) 'A-$n': (seed) => cg.generators[n]!(seed),
  for (final n in aVerify) 'A-$n': (seed) => vg.vgenerators[n]!(seed),
};

/// Every corpus generator, by name.
final Map<String, CorpusGen> corpusGenerators = {
  ...rGenerators,
  ...vrGenerators,
  ...vr2Generators,
  ...tg.tGenerators,
  ...tg.t2Generators,
  ...aGenerators,
};

/// The generator names of a corpus (R, VR, VR2, T, T2 or A).
List<String> corpusNames(String corpus) => switch (corpus) {
  'R' => rGenerators.keys.toList(),
  'VR' => vrGenerators.keys.toList(),
  'VR2' => vr2Generators.keys.toList(),
  'T' => tg.tGenerators.keys.toList(),
  'T2' => tg.t2Generators.keys.toList(),
  'A' => aGenerators.keys.toList(),
  _ => throw ArgumentError('corpus $corpus'),
};

/// The first seed and the count of each generator in the Phase 0 corpora
/// (VR2 and T2 use VR's and T's).
(int, int) defaultSeeds(String gen) {
  if (gen.startsWith('A-')) return (99000000, 20000);
  if (gen.startsWith('T-') || gen.startsWith('T2-')) {
    return (tg.tFirstSeed, tg.tCount(gen));
  }
  return (300100000, 20000);
}

/// Feature tags of a built layout (BL's ffuzz features, plus p0's).
Set<String> features(ConstraintWidgetContainer root, List<String> ops) {
  final f = <String>{};
  if (root.isRtl()) f.add('rtl');
  if (root.getHorizontalDimensionBehaviour() ==
      DimensionBehaviour.wrapContent) {
    f.add('wrapW');
  }
  if (root.getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent) {
    f.add('wrapH');
  }
  for (final w in root.getChildren()) {
    if (w is Barrier) {
      f.add('barrier');
      continue;
    }
    if (w is Guideline) {
      f.add(w.getRelativePercent() != -1 ? 'gpct' : 'guide');
      continue;
    }
    if (w is Flow) f.add('flow');
    if (w.isInHorizontalChain() || w.isInVerticalChain()) f.add('chain');
    if (w.getVisibility() == ConstraintWidget.GONE) f.add('gone');
    if (w.getVisibility() == ConstraintWidget.INVISIBLE) f.add('invisible');
    if (w.mBaseline.isConnected()) {
      f.add('baseline');
      if (w.mBaseline.mMargin != 0) f.add('blMargin');
    }
    if (w.mCenter.isConnected()) f.add('circle');
    if (w.getDimensionRatio() > 0) f.add('ratio');
    if (w.getMinWidth() > 0 || w.getMinHeight() > 0) f.add('minSize');
    for (final h in [true, false]) {
      final b = h
          ? w.getHorizontalDimensionBehaviour()
          : w.getVerticalDimensionBehaviour();
      if (b == DimensionBehaviour.matchParent) f.add('matchParent');
      if (b == DimensionBehaviour.matchConstraint) {
        final d = h
            ? w.mMatchConstraintDefaultWidth
            : w.mMatchConstraintDefaultHeight;
        if (d == ConstraintWidget.MATCH_CONSTRAINT_PERCENT) f.add('pct');
        if (d == ConstraintWidget.MATCH_CONSTRAINT_WRAP) f.add('cwrap');
      }
      final mn = h ? w.mMatchConstraintMinWidth : w.mMatchConstraintMinHeight;
      final mx = h ? w.mMatchConstraintMaxWidth : w.mMatchConstraintMaxHeight;
      if (mn > 0 || mx > 0) f.add('mcBound');
      final bias = h
          ? w.getHorizontalBiasPercent()
          : w.getVerticalBiasPercent();
      final begin = h ? w.mLeft : w.mTop;
      final end = h ? w.mRight : w.mBottom;
      if (begin.isConnected() && end.isConnected()) {
        f.add('centered');
        if (bias != 0 && bias != 1 && bias != 0.5) f.add('oddBias');
      }
      for (final a in [begin, end]) {
        if (a.isConnected() && a.mMargin < 0) f.add('negMargin');
      }
    }
  }
  for (final o in ops) {
    final op = o.split(' ').first;
    switch (op) {
      case 'ct':
        f.add('content');
        if (o.split(' ')[2] == 'text') f.add('text');
      case 'cspec':
        if (o.contains(' A ')) f.add('atmost');
        f.add('cspec');
      case 'cpad':
        f.add('pad');
      case 'cmin':
        f.add('cmin');
      case 'cmax':
        f.add('cmax');
      case 'L':
        f.add('inplace');
    }
  }
  return f;
}
