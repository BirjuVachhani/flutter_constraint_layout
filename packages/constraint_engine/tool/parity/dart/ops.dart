// Op lists: one layout as the exact sequence of engine calls that built it.
// The Dart harness and the Java oracle (java/src/VOpDriver.java) replay the
// same list, so both sides see the same anchors, dependents (stale ones
// included) and connect side effects.
//
// Ops ("op arg arg"), joined by ';':
//   R W H | rtl | wrapw | wraph
//   w N W H | b N | g N | add N
//   bt N TYPE | bm N MARGIN | bg N 0|1 | ref N CHILD
//   go N ORIENT | gb N V | ge N V | gp N PCT
//   c SRC A DST A MARGIN | x SRC A
//   hb N F|W|M|P | vb N ... | hm N DEF MIN MAX PCT | vm N ...
//   mw N V | mh N V | hx N BIAS | vx N BIAS | gm N A V | v N VIS
//   bl N V | hc N STYLE | vc N STYLE | hw N W | vw N W | ra N RATIO SIDE
//   verify-final: hbl N 0|1 | sw/sh/sx/sy N V | ipr N (adapter in-place
//   anchor reset) | L (a layout pass) | cw V | ch V | fixw | fixh | ltr | rm N
//   p0 (FORMATS.md 4.2): ct N KIND W H BL (content) | cc N T ANGLE RADIUS
//   (circle) | fl N (Flow) | ref N M (any helper) | fo fwm fhs fvs fhb fvb
//   fha fva fhg fvg fme N V | fpad N L T R B | frtl N 0|1 | cspec WM WS HM HS
//   | cpad L T R B | cmin W H | cmax W H
//
// Copied from the baseline suite's (BL's) ops.dart into the parity harness,
// with the ops of FORMATS.md 4.2.
//
// Float arguments (gp, hm, vm, hx, vx, hw, vw, ra, the cc angle, fhb, fvb) are
// read as VOpDriver reads them, with Java's Float.parseFloat (jfloat.dart
// parseFloat32: the decimal rounded once to binary32), since Phase 1 made the
// engine store binary32: double.parse and a second rounding to binary32 can
// land one ulp from Java's value. Compiled with -Dcl.doubleparse=true they
// are read with double.parse, as in Phase 0: that build reproduces Phase 0's
// outputs of today's engine and its corpora (respec reads the parsed floats
// back).
import 'package:constraint_engine/constraint_engine.dart';
import 'package:constraint_engine/src/jfloat.dart' show parseFloat32;

import 'content.dart';

/// Phase 0's float parse (`double.parse`), when compiled with
/// `-Dcl.doubleparse=true`.
const bool kDoubleParse = bool.fromEnvironment('cl.doubleparse');

/// A float op argument as the Java oracle reads it (`Float.parseFloat`), or as
/// Phase 0 read it with [kDoubleParse].
double pf(String s) => kDoubleParse ? double.parse(s) : parseFloat32(s);

/// The layout view's own state that a view path reads (FORMATS.md 4.2):
/// the specs onMeasure receives, padding, and android:min/max sizes.
class ContainerView {
  /// `cspec`: null until set; then (mode, size) per axis with BasicMeasure's
  /// modes.
  ({int wMode, int wSize, int hMode, int hSize})? spec;
  int padLeft = 0, padTop = 0, padRight = 0, padBottom = 0;
  int minWidth = 0, minHeight = 0;
  int maxWidth = 0x7fffffff, maxHeight = 0x7fffffff;

  /// The widgets the adapter queries a baseline for (the last `hbl` op of
  /// each was 1), in op order.
  final Set<ConstraintWidget> needsBaseline = <ConstraintWidget>{};

  bool get hasPadding =>
      padLeft != 0 || padTop != 0 || padRight != 0 || padBottom != 0;
  bool get hasMin => minWidth != 0 || minHeight != 0;
  bool get hasMax => maxWidth != 0x7fffffff || maxHeight != 0x7fffffff;
}

final Expando<ContainerView> _viewOf = Expando<ContainerView>('view');

/// The view state of [root], created on first use.
ContainerView viewOf(ConstraintWidgetContainer root) =>
    _viewOf[root] ??= ContainerView();

int specModeOf(String m) => switch (m) {
  'E' => BasicMeasure.EXACTLY,
  'A' => BasicMeasure.AT_MOST,
  'U' => BasicMeasure.UNSPECIFIED,
  _ => throw ArgumentError('spec mode $m'),
};

ConstraintAnchorType anc(String s) => switch (s) {
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

String ancName(ConstraintAnchorType t) => switch (t) {
  ConstraintAnchorType.left => 'L',
  ConstraintAnchorType.right => 'R',
  ConstraintAnchorType.top => 'T',
  ConstraintAnchorType.bottom => 'B',
  ConstraintAnchorType.baseline => 'S',
  ConstraintAnchorType.center => 'C',
  ConstraintAnchorType.centerX => 'CX',
  ConstraintAnchorType.centerY => 'CY',
  _ => throw ArgumentError('anchor $t'),
};

DimensionBehaviour beh(String s) => switch (s) {
  'F' => DimensionBehaviour.fixed,
  'W' => DimensionBehaviour.wrapContent,
  'M' => DimensionBehaviour.matchConstraint,
  'P' => DimensionBehaviour.matchParent,
  _ => throw ArgumentError('behaviour $s'),
};

String behName(DimensionBehaviour b) => switch (b) {
  DimensionBehaviour.fixed => 'F',
  DimensionBehaviour.wrapContent => 'W',
  DimensionBehaviour.matchConstraint => 'M',
  DimensionBehaviour.matchParent => 'P',
};

final _savedDependents = Expando<List<Set<ConstraintAnchor>?>>();

/// The root size of [ops] (its leading R op).
(int, int) rootSize(List<String> ops) {
  final t = ops.first.split(' ');
  if (t[0] != 'R') throw ArgumentError('ops must start with R');
  return (int.parse(t[1]), int.parse(t[2]));
}

/// Replays [ops] (after the R op) into [root].
void applyOps(
  ConstraintWidgetContainer root,
  List<String> ops, {
  void Function()? layoutPass,
}) => applyOpsWith(
  root,
  ops,
  <String, ConstraintWidget>{'root': root},
  layoutPass: layoutPass,
);

/// [applyOps] with a name table [by] that persists across calls. An `L` op
/// runs [layoutPass] when given (the path's measure), else `root.layout()`.
void applyOpsWith(
  ConstraintWidgetContainer root,
  List<String> ops,
  Map<String, ConstraintWidget> by, {
  void Function()? layoutPass,
}) {
  ConstraintWidget n(String name) =>
      by[name] ?? (throw ArgumentError('unknown $name'));
  for (final op in ops) {
    final t = op.split(' ');
    switch (t[0]) {
      case 'R':
        break;
      case 'rtl':
        root.setRtl(true);
      case 'wrapw':
        root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      case 'wraph':
        root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      case 'w':
        by[t[1]] = ConstraintWidget.sizeNamed(
          t[1],
          int.parse(t[2]),
          int.parse(t[3]),
        );
      case 'b':
        by[t[1]] = Barrier.named(t[1]);
      case 'g':
        by[t[1]] = Guideline()..setDebugName(t[1]);
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
        (n(t[1]) as Guideline).setGuidePercent(pf(t[2]));
      case 'c':
        n(t[1]).connect(anc(t[2]), n(t[3]), anc(t[4]), int.parse(t[5]));
      case 'x':
        n(t[1]).getAnchor(anc(t[2]))!.reset();
      case 'hb':
        n(t[1]).setHorizontalDimensionBehaviour(beh(t[2]));
      case 'vb':
        n(t[1]).setVerticalDimensionBehaviour(beh(t[2]));
      case 'hm':
        n(t[1]).setHorizontalMatchStyle(
          int.parse(t[2]),
          int.parse(t[3]),
          int.parse(t[4]),
          pf(t[5]),
        );
      case 'vm':
        n(t[1]).setVerticalMatchStyle(
          int.parse(t[2]),
          int.parse(t[3]),
          int.parse(t[4]),
          pf(t[5]),
        );
      case 'mw':
        n(t[1]).setMinWidth(int.parse(t[2]));
      case 'mh':
        n(t[1]).setMinHeight(int.parse(t[2]));
      case 'hx':
        n(t[1]).setHorizontalBiasPercent(pf(t[2]));
      case 'vx':
        n(t[1]).setVerticalBiasPercent(pf(t[2]));
      case 'gm':
        n(t[1]).setGoneMargin(anc(t[2]), int.parse(t[3]));
      case 'v':
        n(t[1]).setVisibility(int.parse(t[2]));
      case 'bl':
        n(t[1]).setBaselineDistance(int.parse(t[2]));
      case 'hc':
        n(t[1]).setHorizontalChainStyle(int.parse(t[2]));
      case 'vc':
        n(t[1]).setVerticalChainStyle(int.parse(t[2]));
      case 'hw':
        n(t[1]).setHorizontalWeight(pf(t[2]));
      case 'vw':
        n(t[1]).setVerticalWeight(pf(t[2]));
      case 'ra':
        n(t[1]).setDimensionRatio(pf(t[2]), int.parse(t[3]));
      // verify-final additions (VOpDriver.java mirrors them).
      case 'hbl':
        final w = n(t[1]);
        w.setHasBaseline(t[2] == '1');
        final needs = viewOf(root).needsBaseline;
        t[2] == '1' ? needs.add(w) : needs.remove(w);
      case 'sw':
        n(t[1]).setWidth(int.parse(t[2]));
      case 'sh':
        n(t[1]).setHeight(int.parse(t[2]));
      case 'sx':
        n(t[1]).setX(int.parse(t[2]));
      case 'sy':
        n(t[1]).setY(int.parse(t[2]));
      case 'ipr':
        // The adapter's in-place reset (_applyWidgetConfig): every anchor
        // reset, the incoming dependents kept.
        final w = n(t[1]);
        final saved = [for (final a in w.mAnchors) a.mDependents];
        _savedDependents[w] = [
          for (final d in saved) d == null ? null : {...d},
        ];
        w.resetAnchors();
        for (var i = 0; i < w.mAnchors.length; i++) {
          w.mAnchors[i].mDependents = saved[i];
        }
      case 'iprest':
        // A candidate adapter fix: after the connects, the incoming
        // dependents saved by the last 'ipr' that still target the anchor.
        final w = n(t[1]);
        final saved = _savedDependents[w];
        if (saved != null) {
          for (var i = 0; i < w.mAnchors.length; i++) {
            final anchor = w.mAnchors[i];
            for (final d in saved[i] ?? const <ConstraintAnchor>{}) {
              if (identical(d.mTarget, anchor)) {
                (anchor.mDependents ??= <ConstraintAnchor>{}).add(d);
              }
            }
          }
        }
      case 'rereg':
        // A candidate adapter fix: every link registered with its target.
        for (final c in root.getChildren()) {
          for (final a in c.mAnchors) {
            final target = a.mTarget;
            if (target != null) {
              (target.mDependents ??= <ConstraintAnchor>{}).add(a);
            }
          }
        }
      case 'adeps':
        // baseline: the dependents Android's view layer leaves
        // (ConstraintLayout.setChildrenConstraints): every live link is
        // registered with its target, except a link from a child configured
        // before X into X's top or bottom when X has a baseline link
        // (setWidgetBaseline resets X's top and bottom, dropping them).
        // immediateConnect resets nothing, so X's baseline keeps all of its.
        final kids = root.getChildren();
        final index = <ConstraintWidget, int>{
          for (var i = 0; i < kids.length; i++) kids[i]: i,
        };
        for (final a in root.mAnchors) {
          a.mDependents = null;
        }
        for (final c in kids) {
          for (final a in c.mAnchors) {
            a.mDependents = null;
          }
        }
        for (final c in kids) {
          for (final a in c.mAnchors) {
            final target = a.mTarget;
            if (target == null) continue;
            final x = target.mOwner;
            final xi = index[x];
            if (xi != null &&
                x.mBaseline.mTarget != null &&
                (target.mType == ConstraintAnchorType.top ||
                    target.mType == ConstraintAnchorType.bottom) &&
                index[c]! < xi) {
              continue;
            }
            (target.mDependents ??= <ConstraintAnchor>{}).add(a);
          }
        }
      case 'L':
        layoutPass != null ? layoutPass() : root.layout();
      case 'cw':
        root.setWidth(int.parse(t[1]));
      case 'ch':
        root.setHeight(int.parse(t[1]));
      case 'fixw':
        root.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      case 'fixh':
        root.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      case 'ltr':
        root.setRtl(false);
      case 'rm':
        root.remove(n(t[1]));
      // p0 additions (FORMATS.md 4.2; VOpDriver.java mirrors them).
      case 'ct':
        setContent(n(t[1]), Content.parseOp(t));
      case 'cc':
        n(t[1]).connectCircularConstraint(
          n(t[2]),
          pf(t[3]),
          int.parse(t[4]),
        );
      case 'fl':
        by[t[1]] = Flow()..setDebugName(t[1]);
      case 'fo':
        (n(t[1]) as Flow).setOrientation(int.parse(t[2]));
      case 'fwm':
        (n(t[1]) as Flow).setWrapMode(int.parse(t[2]));
      case 'fhs':
        (n(t[1]) as Flow).setHorizontalStyle(int.parse(t[2]));
      case 'fvs':
        (n(t[1]) as Flow).setVerticalStyle(int.parse(t[2]));
      case 'fhb':
        (n(t[1]) as Flow).setHorizontalBias(pf(t[2]));
      case 'fvb':
        (n(t[1]) as Flow).setVerticalBias(pf(t[2]));
      case 'fha':
        (n(t[1]) as Flow).setHorizontalAlign(int.parse(t[2]));
      case 'fva':
        (n(t[1]) as Flow).setVerticalAlign(int.parse(t[2]));
      case 'fhg':
        (n(t[1]) as Flow).setHorizontalGap(int.parse(t[2]));
      case 'fvg':
        (n(t[1]) as Flow).setVerticalGap(int.parse(t[2]));
      case 'fme':
        (n(t[1]) as Flow).setMaxElementsWrap(int.parse(t[2]));
      case 'fpad':
        (n(t[1]) as Flow)
          ..setPaddingLeft(int.parse(t[2]))
          ..setPaddingTop(int.parse(t[3]))
          ..setPaddingRight(int.parse(t[4]))
          ..setPaddingBottom(int.parse(t[5]));
      case 'frtl':
        (n(t[1]) as VirtualLayout).applyRtl(t[2] == '1');
      case 'cspec':
        viewOf(root).spec = (
          wMode: specModeOf(t[1]),
          wSize: int.parse(t[2]),
          hMode: specModeOf(t[3]),
          hSize: int.parse(t[4]),
        );
      case 'cpad':
        viewOf(root)
          ..padLeft = int.parse(t[1])
          ..padTop = int.parse(t[2])
          ..padRight = int.parse(t[3])
          ..padBottom = int.parse(t[4]);
      case 'cmin':
        viewOf(root)
          ..minWidth = int.parse(t[1])
          ..minHeight = int.parse(t[2]);
      case 'cmax':
        viewOf(root)
          ..maxWidth = int.parse(t[1])
          ..maxHeight = int.parse(t[2]);
      default:
        throw ArgumentError('op $op');
    }
  }
}

/// Records engine calls as ops while applying them to real widgets, so a
/// generator can read back the state it built (orientation, connections).
class Rec {
  Rec(this.width, this.height)
    : root = ConstraintWidgetContainer.rect(0, 0, width, height) {
    ops.add('R $width $height');
    _names[root] = 'root';
  }

  final int width;
  final int height;
  final ConstraintWidgetContainer root;
  final ops = <String>[];
  final _names = <ConstraintWidget, String>{};

  String name(ConstraintWidget w) =>
      _names[w] ?? (throw StateError('unnamed widget'));

  void rtl() {
    root.setRtl(true);
    ops.add('rtl');
  }

  void wrapW() {
    root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
    ops.add('wrapw');
  }

  void wrapH() {
    root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
    ops.add('wraph');
  }

  ConstraintWidget widget(String n, int w, int h, {bool add = false}) {
    final x = ConstraintWidget.sizeNamed(n, w, h);
    _names[x] = n;
    ops.add('w $n $w $h');
    if (add) this.add(x);
    return x;
  }

  Barrier barrier(
    String n, {
    int type = 0,
    int margin = 0,
    bool allowsGone = true,
    bool add = false,
  }) {
    final b = Barrier.named(n);
    _names[b] = n;
    ops.add('b $n');
    barrierType(b, type);
    if (margin != 0) barrierMargin(b, margin);
    barrierGone(b, allowsGone);
    if (add) this.add(b);
    return b;
  }

  void barrierType(Barrier b, int type) {
    b.setBarrierType(type);
    ops.add('bt ${name(b)} $type');
  }

  void barrierMargin(Barrier b, int m) {
    b.setMargin(m);
    ops.add('bm ${name(b)} $m');
  }

  void barrierGone(Barrier b, bool allows) {
    b.setAllowsGoneWidget(allows);
    ops.add('bg ${name(b)} ${allows ? 1 : 0}');
  }

  void ref(Barrier b, ConstraintWidget c) {
    b.add(c);
    ops.add('ref ${name(b)} ${name(c)}');
  }

  Guideline guideline(String n, int orientation, {bool add = false}) {
    final g = Guideline()..setDebugName(n);
    _names[g] = n;
    ops.add('g $n');
    g.setOrientation(orientation);
    ops.add('go $n $orientation');
    if (add) this.add(g);
    return g;
  }

  void guideBegin(Guideline g, int v) {
    g.setGuideBegin(v);
    ops.add('gb ${name(g)} $v');
  }

  void guideEnd(Guideline g, int v) {
    g.setGuideEnd(v);
    ops.add('ge ${name(g)} $v');
  }

  void guidePercent(Guideline g, double p) {
    g.setGuidePercent(p);
    ops.add('gp ${name(g)} $p');
  }

  void add(ConstraintWidget c) {
    root.add(c);
    ops.add('add ${name(c)}');
  }

  void connect(
    ConstraintWidget src,
    ConstraintAnchorType a,
    ConstraintWidget dst,
    ConstraintAnchorType b, [
    int margin = 0,
  ]) {
    src.connect(a, dst, b, margin);
    ops.add('c ${name(src)} ${ancName(a)} ${name(dst)} ${ancName(b)} $margin');
  }

  void reset(ConstraintWidget w, ConstraintAnchorType a) {
    w.getAnchor(a)!.reset();
    ops.add('x ${name(w)} ${ancName(a)}');
  }

  void behaviour(ConstraintWidget w, bool h, DimensionBehaviour b) {
    h
        ? w.setHorizontalDimensionBehaviour(b)
        : w.setVerticalDimensionBehaviour(b);
    ops.add('${h ? 'h' : 'v'}b ${name(w)} ${behName(b)}');
  }

  void matchStyle(
    ConstraintWidget w,
    bool h,
    int style,
    int min,
    int max,
    double pct,
  ) {
    h
        ? w.setHorizontalMatchStyle(style, min, max, pct)
        : w.setVerticalMatchStyle(style, min, max, pct);
    ops.add('${h ? 'h' : 'v'}m ${name(w)} $style $min $max $pct');
  }

  void minSize(ConstraintWidget w, bool h, int v) {
    h ? w.setMinWidth(v) : w.setMinHeight(v);
    ops.add('${h ? 'mw' : 'mh'} ${name(w)} $v');
  }

  void bias(ConstraintWidget w, bool h, double v) {
    h ? w.setHorizontalBiasPercent(v) : w.setVerticalBiasPercent(v);
    ops.add('${h ? 'h' : 'v'}x ${name(w)} $v');
  }

  void goneMargin(ConstraintWidget w, ConstraintAnchorType a, int v) {
    w.setGoneMargin(a, v);
    ops.add('gm ${name(w)} ${ancName(a)} $v');
  }

  void visibility(ConstraintWidget w, int v) {
    w.setVisibility(v);
    ops.add('v ${name(w)} $v');
  }

  void baseline(ConstraintWidget w, int v) {
    w.setBaselineDistance(v);
    ops.add('bl ${name(w)} $v');
  }

  void chainStyle(ConstraintWidget w, bool h, int s) {
    h ? w.setHorizontalChainStyle(s) : w.setVerticalChainStyle(s);
    ops.add('${h ? 'h' : 'v'}c ${name(w)} $s');
  }

  void weight(ConstraintWidget w, bool h, double v) {
    h ? w.setHorizontalWeight(v) : w.setVerticalWeight(v);
    ops.add('${h ? 'h' : 'v'}w ${name(w)} $v');
  }

  void ratio(ConstraintWidget w, double r, int side) {
    w.setDimensionRatio(r, side);
    ops.add('ra ${name(w)} $r $side');
  }
}
