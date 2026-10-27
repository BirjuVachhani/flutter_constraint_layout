// gclass: classifies the differences between the port and the Java oracle at
// a GRAPH level (64, 321, or a GRAPH_WRAP variant) by mechanism (FORMATS.md
// 20; moved here from the Phase 3 gate's scratch copy in Phase 5a). The
// tagging is the baseline suite's (BL's) bclass.dart, unchanged in
// substance: for each difference it finds the source widgets (they differ on
// an axis while nothing they depend on along that axis does) and tags them by
// their configuration on that axis. It adds the route:
// whether each side's result equals Java's solver result at the level (J0 at
// 64, J257 at 321 and on the view path; the port equals Java there on every
// corpus), which tells a graph answer from a fall back to the solver.
//
//   gclass <in.tsv> <out.tsv>
// in.tsv (gclass_in.py writes it): id, ops, X (the port at the level), J
// (Java at the level), JS (Java's solver at the level), geometry strings with
// their `!status | ` prefix. Prints the counts per route and per mechanism;
// out.tsv holds, per layout, id, generator, route, mechanisms, source axes and
// tags. A view-path op list is replayed on core widgets for the tags (its
// layout-view ops only set the container view's state).
import 'dart:io';

import 'package:constraint_engine/constraint_engine.dart';

import 'ops.dart';

typedef Frame = ({bool gone, int x, int y, int w, int h});

String body(String g) {
  if (!g.startsWith('!')) return g;
  final i = g.indexOf(' | ');
  return i < 0 ? '' : g.substring(i + 3);
}

Map<String, Frame> parseGeom(String g) {
  final m = <String, Frame>{};
  if (g.isEmpty) return m;
  for (final part in g.split(' | ')) {
    if (part.startsWith('root ')) {
      final t = part.substring(5).split(' x ');
      m['root'] = (
        gone: false,
        x: 0,
        y: 0,
        w: int.parse(t[0]),
        h: int.parse(t[1]),
      );
      continue;
    }
    final i = part.indexOf(': ');
    if (i < 0) continue;
    final name = part.substring(0, i);
    final rest = part.substring(i + 2);
    if (rest.startsWith('gone, ')) {
      final t = rest.substring(6).split(' x ');
      m[name] = (
        gone: true,
        x: 0,
        y: 0,
        w: int.parse(t[0]),
        h: int.parse(t[1]),
      );
      continue;
    }
    final close = rest.indexOf(')');
    final xy = rest.substring(1, close).split(', ');
    final wh = rest.substring(close + 2).split(' x ');
    m[name] = (
      gone: false,
      x: int.parse(xy[0]),
      y: int.parse(xy[1]),
      w: int.parse(wh[0]),
      h: int.parse(wh[1]),
    );
  }
  return m;
}

bool axisDiffers(Frame? a, Frame? b, bool h) {
  if (a == null || b == null) return a != b;
  if (a.gone != b.gone) return true;
  return h ? (a.x != b.x || a.w != b.w) : (a.y != b.y || a.h != b.h);
}

String nameOf(ConstraintWidget w) =>
    w is ConstraintWidgetContainer && w.getParent() == null
    ? 'root'
    : w.getDebugName()!;

List<ConstraintWidget> depsOf(ConstraintWidget w, bool h) {
  final out = <ConstraintWidget>[];
  if (w is Barrier) {
    final bh = w.getOrientation() == ConstraintWidget.HORIZONTAL;
    if (bh == h) {
      for (var i = 0; i < w.mWidgetsCount; i++) {
        out.add(w.mWidgets[i]!);
      }
    }
    return out;
  }
  final anchors = h ? [w.mLeft, w.mRight] : [w.mTop, w.mBottom, w.mBaseline];
  for (final a in anchors) {
    final t = a.mTarget;
    if (t != null) out.add(t.mOwner);
  }
  return out;
}

int? edgeIn(Map<String, Frame> g, ConstraintAnchor? a) {
  if (a == null) return null;
  final f = g[nameOf(a.mOwner)];
  if (f == null || f.gone) return null;
  return switch (a.mType) {
    ConstraintAnchorType.left => f.x,
    ConstraintAnchorType.right => f.x + f.w,
    ConstraintAnchorType.top => f.y,
    ConstraintAnchorType.bottom => f.y + f.h,
    _ => null,
  };
}

Set<String> tagsOf(
  ConstraintWidgetContainer root,
  ConstraintWidget w,
  bool h,
  Frame? x,
  Frame? j,
  Map<String, Frame> jg,
) {
  final t = <String>{};
  t.add(h ? 'H' : 'V');
  if (root.isRtl() && h) t.add('rtl');
  final wrap = h
      ? root.getHorizontalDimensionBehaviour() == DimensionBehaviour.wrapContent
      : root.getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent;
  if (wrap) t.add('wrap');
  if (w is Barrier) {
    t.add('barrier');
    return t;
  }
  if (w is Guideline) {
    t.add('guideline');
    return t;
  }
  if (w.getVisibility() == ConstraintWidget.GONE) t.add('gone');
  if (h ? w.isInHorizontalChain() : w.isInVerticalChain()) t.add('chain');
  if (w.getDimensionRatio() > 0) t.add('ratio');
  final b = h
      ? w.getHorizontalDimensionBehaviour()
      : w.getVerticalDimensionBehaviour();
  if (b == DimensionBehaviour.matchConstraint) {
    final d = h
        ? w.mMatchConstraintDefaultWidth
        : w.mMatchConstraintDefaultHeight;
    final mn = h ? w.mMatchConstraintMinWidth : w.mMatchConstraintMinHeight;
    final mx = h ? w.mMatchConstraintMaxWidth : w.mMatchConstraintMaxHeight;
    if (d == ConstraintWidget.MATCH_CONSTRAINT_PERCENT) {
      t.add('pct');
      if (mn > 0) t.add('pctMin');
    } else if (d == ConstraintWidget.MATCH_CONSTRAINT_WRAP) {
      t.add('mcWrap');
    } else {
      t.add('mc');
    }
    if (mn > 0 || mx > 0) t.add('mcBound');
  } else if (b == DimensionBehaviour.matchParent) {
    t.add('matchParent');
  } else if (b == DimensionBehaviour.wrapContent) {
    t.add('wrapContent');
  }
  if (w.getMinWidth() > 0 && h || w.getMinHeight() > 0 && !h) t.add('minSize');
  final begin = h ? w.mLeft : w.mTop;
  final end = h ? w.mRight : w.mBottom;
  if (!h && w.mBaseline.mTarget != null) t.add('baseline');
  if (begin.mTarget != null && end.mTarget != null) {
    t.add('centered');
    if (w.getVisibility() != ConstraintWidget.GONE) {
      final e1 = edgeIn(jg, begin.mTarget);
      final e2 = edgeIn(jg, end.mTarget);
      if (e1 != null && e2 != null) {
        final s1 = e1 + begin.getMargin();
        final s2 = e2 - end.getMargin();
        final size = x == null ? 0 : (h ? x.w : x.h);
        if (s1 > s2) {
          t.add('crossed');
        } else if (size > s2 - s1 && b != DimensionBehaviour.matchConstraint) {
          t.add('nofit');
        }
      }
    }
    final bias = h ? w.getHorizontalBiasPercent() : w.getVerticalBiasPercent();
    if (bias == 0.5) {
      t.add('bias.5');
    } else if (bias == 0 || bias == 1) {
      t.add('bias01');
    } else {
      t.add('oddBias');
    }
  } else if (begin.mTarget == null &&
      end.mTarget == null &&
      !(!h && w.mBaseline.mTarget != null)) {
    t.add('unanchored');
  }
  for (final d in depsOf(w, h)) {
    if (d.getVisibility() == ConstraintWidget.GONE) t.add('goneTarget');
    if (d is Barrier) t.add('onBarrier');
    if (d is Guideline) t.add('onGuideline');
  }
  for (final f in [x, j]) {
    if (f == null || f.gone) continue;
    final s = h ? f.x : f.y;
    final e = s + (h ? f.w : f.h);
    if (s < 0 || e < 0) t.add('neg');
  }
  if (x != null && j != null && !x.gone && !j.gone) {
    final jz = h ? j.w == 0 : j.h == 0;
    final xz = h ? x.w == 0 : x.h == 0;
    if (j.x == 0 && j.y == 0 && jz && !xz) t.add('collapsedJ');
    if (x.x == 0 && x.y == 0 && xz && !jz) t.add('collapsedX');
  }
  if (x != null && j != null) {
    final sx = h ? x.w : x.h;
    final sj = h ? j.w : j.h;
    t.add(sx != sj ? 'sizeDiff' : 'posOnly');
    final d = h ? (x.x - j.x) : (x.y - j.y);
    if (d.abs() == 1 || (sx - sj).abs() == 1) t.add('1px');
  }
  return t;
}

String mechanism(Set<String> t) {
  if (t.contains('crossed') ||
      t.contains('collapsedJ') ||
      t.contains('collapsedX')) {
    return 'crossed links (negative size)';
  }
  if (t.contains('barrier')) return 'barrier position';
  if (t.contains('guideline')) return 'guideline';
  if (t.contains('chain')) return 'chain';
  if (t.contains('pctMin')) return 'percent with min';
  if (t.contains('ratio')) return 'ratio';
  if (t.contains('pct')) return 'percent';
  if (t.contains('neg')) return 'negative position';
  if (t.contains('minSize')) return 'min size';
  if (t.contains('goneTarget')) return 'link into gone widget';
  if (t.contains('gone')) return 'gone widget';
  if (t.contains('baseline')) return 'baseline';
  if ((t.contains('mc') || t.contains('mcWrap')) && t.contains('sizeDiff')) {
    return 'match-constraint size';
  }
  if (t.contains('nofit')) return 'centered, does not fit';
  if (t.contains('centered') && t.contains('oddBias')) {
    return 'odd bias centering';
  }
  if (t.contains('centered') && t.contains('bias.5')) {
    return 'half-pixel centering';
  }
  if (t.contains('centered') && t.contains('bias01')) {
    return 'bias 0/1 centering';
  }
  if (t.contains('wrap')) return 'wrap size';
  if (t.contains('unanchored')) return 'unanchored';
  return 'other';
}

void main(List<String> args) {
  final out = File(args[1]).openSync(mode: FileMode.write);
  final perRoute = <String, int>{};
  final present = <String, Map<String, int>>{};
  final sole = <String, Map<String, int>>{};
  for (final line in File(args[0]).readAsLinesSync()) {
    final p = line.split('\t');
    final id = p[0];
    final opl = p[1].split(';');
    final xs = body(p[2]), js = body(p[3]);
    final xSolver = p[2] == p[4];
    final jSolver = p[3] == p[4];
    final route = xSolver
        ? 'port=solver, Java graph'
        : (jSolver ? 'port graph, Java=solver' : 'both graph');
    final (w0, h0) = rootSize(opl);
    final root = ConstraintWidgetContainer.rect(0, 0, w0, h0)
      ..setDebugName('root');
    applyOps(root, opl, layoutPass: () {});
    final byName = {for (final c in root.getChildren()) nameOf(c): c};
    final xg = parseGeom(xs);
    final jg = parseGeom(js);
    final sources = <String>[];
    final mechs = <String>{};
    var rootSize0 = false;
    if (axisDiffers(xg['root'], jg['root'], true) ||
        axisDiffers(xg['root'], jg['root'], false)) {
      rootSize0 = true;
    }
    final allTags = <String>{};
    for (final e in byName.entries) {
      final w = e.value;
      for (final h in const [true, false]) {
        if (!axisDiffers(xg[e.key], jg[e.key], h)) continue;
        var source = true;
        for (final d in depsOf(w, h)) {
          final dn = nameOf(d);
          if (dn == 'root') {
            if (axisDiffers(xg['root'], jg['root'], h)) source = false;
            continue;
          }
          if (axisDiffers(xg[dn], jg[dn], h)) source = false;
        }
        if (!source && (h ? w.isInHorizontalChain() : w.isInVerticalChain())) {
          source = true;
          for (final d in depsOf(w, h)) {
            final inChain = h ? d.isInHorizontalChain() : d.isInVerticalChain();
            if (inChain) continue;
            final dn = nameOf(d);
            if (dn == 'root') continue;
            if (axisDiffers(xg[dn], jg[dn], h)) source = false;
          }
        }
        if (!source) continue;
        final t = tagsOf(root, w, h, xg[e.key], jg[e.key], jg);
        allTags.addAll(t);
        sources.add('${e.key}${h ? 'H' : 'V'}');
        mechs.add(mechanism(t));
      }
    }
    if (sources.isEmpty) {
      mechs.add(rootSize0 ? 'wrap size' : 'cycle/unknown');
    }
    perRoute[route] = (perRoute[route] ?? 0) + 1;
    for (final r in [route, 'all']) {
      final pr = present.putIfAbsent(r, () => {});
      for (final m in mechs) {
        pr[m] = (pr[m] ?? 0) + 1;
      }
      if (mechs.length == 1) {
        final so = sole.putIfAbsent(r, () => {});
        so[mechs.first] = (so[mechs.first] ?? 0) + 1;
      }
    }
    final gen = id.substring(0, id.lastIndexOf(':'));
    out.writeStringSync(
      '$id\t$gen\t$route\t${(mechs.toList()..sort()).join('+')}\t'
      '${sources.join(',')}\t${(allTags.toList()..sort()).join(',')}\n',
    );
  }
  out.closeSync();
  print('routes: $perRoute');
  for (final r in [...perRoute.keys, 'all']) {
    print('== $r (mechanism present in / sole mechanism of)');
    final pr = present[r] ?? {};
    final keys = pr.keys.toList()..sort((a, b) => pr[b]!.compareTo(pr[a]!));
    for (final m in keys) {
      print(
        '   ${m.padRight(32)} ${'${pr[m]}'.padLeft(7)} '
        '${'${(sole[r] ?? {})[m] ?? 0}'.padLeft(7)}',
      );
    }
  }
}
