// rebuildViewDependents gives every anchor the dependents Android's view
// layer leaves after ConstraintLayout.setChildrenConstraints (CL 1249-1351,
// 1354-1620), whatever order and history the engine-side links were made
// with. The dependents decide what Direct visits and in which order, and
// already at level 0 they decide whether a gone widget enters the solver and
// how strongly a barrier holds its references.
//
// The expected states come from Java: DepsProbe
// (tool/parity/java/probes/DepsProbe.java) emulates setChildrenConstraints,
// applyConstraintsFromLayoutParams and setWidgetBaseline step by step on the
// pinned core classes ($CL_CORE, from tool/parity/java/build_core.sh), run
// with -XX:hashCode=2 so each HashSet iterates in insertion order, and
// prints the state in the format of [_state]. The oracle's own model of that
// state is the `adeps` op (tool/parity/dart/ops.dart, Java
// VfAccess.androidDeps), compared below on random layouts.
//
// Only src libraries are imported, so the file needs no change when the
// package's library starts to export the view layer.

import 'dart:math' as math;

import 'package:constraint_engine/src/barrier.dart';
import 'package:constraint_engine/src/constraint_anchor.dart';
import 'package:constraint_engine/src/constraint_widget.dart';
import 'package:constraint_engine/src/constraint_widget_container.dart';
import 'package:constraint_engine/src/flow.dart';
import 'package:constraint_engine/src/guideline.dart';
import 'package:constraint_engine/src/view/measure_spec.dart';
import 'package:constraint_engine/src/view/view_dependents.dart';
import 'package:constraint_engine/src/view/view_host.dart';
import 'package:constraint_engine/src/view/view_measurer.dart';
import 'package:test/test.dart';

const _left = ConstraintAnchorType.left;
const _top = ConstraintAnchorType.top;
const _right = ConstraintAnchorType.right;
const _bottom = ConstraintAnchorType.bottom;
const _baseline = ConstraintAnchorType.baseline;
const _unset = ConstraintAnchor.unsetGoneMargin;

String _letter(ConstraintAnchorType t) => switch (t) {
  ConstraintAnchorType.left => 'L',
  ConstraintAnchorType.top => 'T',
  ConstraintAnchorType.right => 'R',
  ConstraintAnchorType.bottom => 'B',
  ConstraintAnchorType.baseline => 'S',
  ConstraintAnchorType.center => 'C',
  ConstraintAnchorType.centerX => 'CX',
  ConstraintAnchorType.centerY => 'CY',
  ConstraintAnchorType.none => 'N',
};

String _name(ConstraintAnchor a) =>
    '${a.mOwner.getDebugName()}.${_letter(a.mType)}';

/// DepsProbe's dump: the dependents of every anchor of the container and of
/// each child ([ConstraintWidget.getAnchors] order), then every link (or
/// margin) of each child, then the children that have a baseline.
String _state(ConstraintWidgetContainer root) {
  final b = StringBuffer();
  for (final w in [root, ...root.getChildren()]) {
    for (final a in w.getAnchors()) {
      final d = a.mDependents;
      if (d == null) continue;
      b.write(' ${_name(a)}=[${d.map(_name).join(',')}]');
    }
  }
  b.write(' | links');
  for (final w in root.getChildren()) {
    for (final a in w.getAnchors()) {
      final target = a.mTarget;
      if (target == null && a.mMargin == 0) continue;
      b.write(' ${_name(a)}->${target == null ? '-' : _name(target)}');
      b.write('/${a.mMargin}');
    }
  }
  b.write(' | hb');
  for (final w in root.getChildren()) {
    if (w.hasBaseline()) b.write(' ${w.getDebugName()}');
  }
  return b.toString();
}

ConstraintWidgetContainer _root() =>
    ConstraintWidgetContainer.sizeNamed('root', 400, 800);

ConstraintWidget _fixed(String name, int width, int height) =>
    ConstraintWidget.sizeNamed(name, width, height);

/// A view-layer link (immediateConnect: no validity check, no side effect
/// on the widget's other anchors).
void _link(
  ConstraintWidget from,
  ConstraintAnchorType fromType,
  ConstraintWidget to,
  ConstraintAnchorType toType,
  int margin, [
  int goneMargin = _unset,
]) => from.immediateConnect(fromType, to, toType, margin, goneMargin);

/// The oracle's `adeps` op (ops.dart; VfAccess.androidDeps): every live link
/// registered, in child order and mAnchors order, except a link from a child
/// configured before X into X's top or bottom when X has a baseline link.
void _adeps(ConstraintWidgetContainer root) {
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
          (target.mType == _top || target.mType == _bottom) &&
          index[c]! < xi) {
        continue;
      }
      (target.mDependents ??= <ConstraintAnchor>{}).add(a);
    }
  }
}

/// A child view's content for ViewHost (FORMATS.md 6.1, `box W H`): its
/// natural size, given EXACTLY, capped AT_MOST.
class _BoxMeasurer extends ViewMeasurer {
  final Map<ConstraintWidget, (int, int)> sizes = {};

  @override
  ({int width, int height, int baseline}) measureContent(
    ConstraintWidget widget,
    int widthSpec,
    int heightSpec,
  ) {
    final (w, h) = sizes[widget] ?? (0, 0);
    int resolve(int n, int spec) {
      final mode = MeasureSpec.getMode(spec);
      final size = MeasureSpec.getSize(spec);
      if (mode == MeasureSpec.EXACTLY) return size;
      if (mode == MeasureSpec.AT_MOST) return n < size ? n : size;
      return n;
    }

    return (
      width: resolve(w, widthSpec),
      height: resolve(h, heightSpec),
      baseline: -1,
    );
  }
}

void main() {
  group('the state Android leaves (Java DepsProbe)', () {
    test('a baseline link drops the earlier children linked into the '
        "widget's top and bottom, and keeps the later ones", () {
      // CL 1617-1618: setWidgetBaseline resets X's top and bottom after
      // connecting X's baseline. That drops X's own top and bottom links and
      // what E and F (configured before X) registered there; L, configured
      // after X, registers normally.
      final root = _root();
      final e = _fixed('E', 40, 10);
      final f = _fixed('F', 20, 10);
      final x = _fixed('X', 60, 30);
      final b = _fixed('B', 80, 40);
      final l = _fixed('L', 30, 10);
      for (final c in [e, f, x, b, l]) {
        root.add(c);
      }
      // Linked in another order than the view layer's, with history: X keeps
      // its own top and bottom links (setWidgetBaseline would reset them),
      // and E's bottom is moved from X's bottom to X's top, which leaves a
      // stale entry in X's bottom.
      _link(l, _left, x, _left, 0);
      _link(l, _top, x, _bottom, 8);
      _link(b, _left, root, _left, 100);
      _link(b, _top, root, _top, 50);
      _link(x, _baseline, b, _baseline, 0);
      _link(x, _left, root, _left, 20);
      _link(x, _top, root, _top, 30);
      _link(x, _bottom, root, _bottom, 0);
      _link(e, _bottom, x, _bottom, 4);
      _link(e, _bottom, x, _top, 4);
      _link(e, _left, root, _left, 0);
      _link(f, _left, root, _left, 5);
      _link(f, _top, x, _bottom, 2);
      expect(x.mBottom.mDependents, contains(e.mBottom), reason: 'stale');

      rebuildViewDependents(root);

      // DepsProbe "depsorder".
      expect(
        _state(root),
        ' root.L=[E.L,F.L,X.L,B.L] root.T=[B.T] X.L=[L.L] X.B=[L.T] '
        'B.S=[X.S] | links E.L->root.L/0 E.B->X.T/4 F.L->root.L/5 '
        'F.T->X.B/2 X.L->root.L/20 X.S->B.S/0 B.L->root.L/100 '
        'B.T->root.T/50 L.L->X.L/0 L.T->X.B/8 | hb X B',
      );
    });

    test('dependents iterate in child order, then in mAnchors order', () {
      // Q centers on P's right edge (left and right into one target); W
      // links into the same anchors after Q. The engine-side links are made
      // in the opposite order.
      final root = _root();
      final p = _fixed('P', 100, 20);
      final q = _fixed('Q', 50, 20);
      final w = _fixed('W', 30, 20);
      for (final c in [p, q, w]) {
        root.add(c);
      }
      _link(w, _bottom, p, _bottom, 0);
      _link(w, _top, p, _bottom, 0);
      _link(w, _left, p, _right, 3);
      _link(q, _right, p, _right, 0);
      _link(q, _left, p, _right, 0);
      _link(q, _top, p, _bottom, 5);
      _link(p, _top, root, _top, 10);
      _link(p, _left, root, _left, 10);

      rebuildViewDependents(root);

      // DepsProbe "order".
      expect(
        _state(root),
        ' root.L=[P.L] root.T=[P.T] P.R=[Q.L,Q.R,W.L] P.B=[Q.T,W.T,W.B] '
        '| links P.L->root.L/10 P.T->root.T/10 Q.L->P.R/0 Q.T->P.B/5 '
        'Q.R->P.R/0 W.L->P.R/3 W.T->P.B/0 W.B->P.B/0 | hb',
      );
    });

    const matchParentState =
        ' root.L=[B2.L] root.T=[B2.T] B2.R=[M.L] B2.S=[M.S] | links '
        'B2.L->root.L/0 B2.T->root.T/20 M.L->B2.R/4 M.T->-/7 M.B->-/9 '
        'M.S->B2.S/0 | hb B2 M';

    ConstraintWidgetContainer matchParentLayout({required bool linked}) {
      final root = _root();
      final b2 = _fixed('B2', 50, 40);
      final m = _fixed('M', 30, 0)
        ..setVerticalDimensionBehaviour(DimensionBehaviour.matchParent);
      root
        ..add(b2)
        ..add(m);
      _link(b2, _left, root, _left, 0);
      _link(b2, _top, root, _top, 20);
      _link(m, _left, b2, _right, 4);
      if (linked) {
        _link(m, _top, root, _top, 7);
        _link(m, _bottom, root, _bottom, 9);
      } else {
        m.mTop.mMargin = 7;
        m.mBottom.mMargin = 9;
      }
      _link(m, _baseline, b2, _baseline, 0);
      return root;
    }

    test('a match-parent height keeps its margins through the baseline '
        'reset, linked or not', () {
      // CL 1566-1568 set a match-parent axis's margins after
      // setWidgetBaseline reset the top and bottom, and the view measurer
      // and checkMatchParent read them unlinked.
      for (final linked in [true, false]) {
        final root = matchParentLayout(linked: linked);
        rebuildViewDependents(root);
        // DepsProbe "matchparent".
        expect(_state(root), matchParentState, reason: 'linked: $linked');
      }
    });

    test('a baseline link to a top seeds only the linked widget', () {
      final root = _root();
      final z = _fixed('Z', 50, 20);
      final y = _fixed('Y', 50, 20);
      root
        ..add(z)
        ..add(y);
      _link(z, _left, root, _left, 0);
      _link(z, _top, root, _top, 0);
      _link(y, _left, z, _right, 0);
      _link(y, _baseline, z, _top, 3);

      rebuildViewDependents(root);

      // DepsProbe "basetotop": CL 1606-1616 seeds the target only for a
      // baseline-to-baseline link.
      expect(
        _state(root),
        ' root.L=[Z.L] root.T=[Z.T] Z.T=[Y.S] Z.R=[Y.L] | links '
        'Z.L->root.L/0 Z.T->root.T/0 Y.L->Z.R/0 Y.S->Z.T/3 | hb Y',
      );
    });

    test('guidelines, barriers and circles register like any link', () {
      final root = _root();
      final g = Guideline()
        ..setOrientation(Guideline.vertical)
        ..setGuideBegin(50)
        ..setDebugName('G');
      final a = _fixed('A', 40, 40);
      final c = _fixed('C', 10, 10);
      final bar = Barrier.named('bar')
        ..setBarrierType(Barrier.right)
        ..add(a)
        ..add(c);
      final k = _fixed('K', 20, 20);
      for (final w in [g, a, c, bar, k]) {
        root.add(w);
      }
      _link(k, _top, root, _top, 0);
      _link(k, _left, bar, _right, 5, 7);
      c.connectCircularConstraint(a, 45, 30);
      _link(a, _top, root, _top, 0);
      _link(a, _left, g, _left, 0);

      rebuildViewDependents(root);

      // DepsProbe "helpers".
      expect(
        _state(root),
        ' root.T=[A.T,K.T] G.L=[A.L] A.C=[C.C] bar.R=[K.L] | links '
        'A.L->G.L/0 A.T->root.T/0 C.C->A.C/30 K.L->bar.R/5 K.T->root.T/0 '
        '| hb',
      );
    });

    test('the links a Flow made in its last solve are dropped', () {
      final root = _root();
      final flow = Flow()..setDebugName('FL');
      final m0 = _fixed('m0', 30, 20);
      final m1 = _fixed('m1', 40, 20);
      final below = _fixed('below', 50, 10);
      flow
        ..add(m0)
        ..add(m1)
        ..setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent)
        ..setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      for (final w in [flow, m0, m1, below]) {
        root.add(w);
      }
      _link(flow, _left, root, _left, 7);
      _link(flow, _top, root, _top, 4);
      _link(below, _left, root, _left, 5);
      _link(below, _top, flow, _bottom, 2);
      final measurer = _BoxMeasurer()
        ..sizes[m0] = (30, 20)
        ..sizes[m1] = (40, 20)
        ..sizes[below] = (50, 10);
      ViewHost(root, measurer)
        ..optimizationLevel = 0
        ..measure(
          MeasureSpec.makeMeasureSpec(400, MeasureSpec.EXACTLY),
          MeasureSpec.makeMeasureSpec(800, MeasureSpec.EXACTLY),
        );
      expect(
        [
          for (final m in [m0, m1]) ...m.mAnchors,
        ].any((a) => a.isConnected()),
        isTrue,
        reason: 'the solve connects the members',
      );

      rebuildViewDependents(root);

      // DepsProbe "flow": the members carry no links of their own.
      expect(
        _state(root),
        ' root.L=[FL.L,below.L] root.T=[FL.T] FL.B=[below.T] | links '
        'FL.L->root.L/7 FL.T->root.T/4 below.L->root.L/5 below.T->FL.B/2 '
        '| hb',
      );
    });
  });

  group('rebuildViewDependents', () {
    test('drops stale dependents and keeps every live link', () {
      final root = _root();
      final a = _fixed('a', 10, 10);
      final b = _fixed('b', 10, 10);
      final c = _fixed('c', 10, 10);
      for (final w in [a, b, c]) {
        root.add(w);
      }
      c.connect(_left, a, _right, 4);
      c.connect(_left, b, _right, 6); // a's right keeps c's left: stale
      expect(a.mRight.mDependents, contains(c.mLeft));
      rebuildViewDependents(root);
      expect(a.mRight.mDependents, isNull);
      expect(b.mRight.mDependents, [c.mLeft]);
      expect(c.mLeft.mTarget, same(b.mRight));
      expect(c.mLeft.mMargin, 6);
    });

    test('is idempotent', () {
      final root = _idempotenceLayout();
      rebuildViewDependents(root);
      final once = _state(root);
      rebuildViewDependents(root);
      expect(_state(root), once);
    });

    test('a baseline link to the container or outside it seeds nothing', () {
      final root = _root();
      final x = _fixed('X', 10, 10);
      final y = _fixed('Y', 10, 10);
      final outside = _fixed('O', 10, 10);
      root
        ..add(x)
        ..add(y);
      _link(x, _baseline, root, _top, 2);
      _link(x, _top, root, _top, 5);
      _link(y, _baseline, outside, _baseline, 0);

      rebuildViewDependents(root);

      // X's baseline link still resets X's top and bottom, as the oracle's
      // adeps treats any baseline link; only a link to a child seeds.
      expect(x.mTop.mTarget, isNull);
      expect(root.mTop.mDependents, [x.mBaseline]);
      expect(outside.mBaseline.mDependents, [y.mBaseline]);
      expect(x.hasBaseline(), isFalse);
      expect(y.hasBaseline(), isFalse);
      expect(outside.hasBaseline(), isFalse);
    });

    test('resets the members of every virtual layout, and only theirs', () {
      final root = _root();
      final flow = Flow()..setDebugName('FL');
      final m = _fixed('m', 10, 10);
      final other = _fixed('o', 10, 10);
      flow.add(m);
      for (final w in [flow, m, other]) {
        root.add(w);
      }
      _link(m, _left, root, _left, 3);
      _link(m, _top, other, _bottom, 0);
      _link(other, _left, m, _right, 1);
      rebuildViewDependents(root);
      expect(m.mLeft.mTarget, isNull);
      expect(m.mTop.mTarget, isNull);
      expect(m.mRight.mDependents, [other.mLeft]);
      expect(other.mLeft.mTarget, same(m.mRight));
    });
  });

  group("equality with the oracle's adeps op", () {
    // The op lists of the view corpora are built with the core connect,
    // which already resets a widget's top and bottom when its baseline
    // connects; on R, VR2 and T2 (1,109,654 layouts) rebuildViewDependents
    // and adeps leave the same dependents, links and margins (checked once,
    // over the corpora of tool/parity/gates/corpora.sh). Here the same
    // comparison on random layouts made with the core API, re-links and
    // resets included.
    String dependentsOnly(ConstraintWidgetContainer root) {
      final s = _state(root);
      return s.substring(0, s.indexOf(' | hb'));
    }

    const types = [
      ConstraintAnchorType.left,
      ConstraintAnchorType.top,
      ConstraintAnchorType.right,
      ConstraintAnchorType.bottom,
      ConstraintAnchorType.baseline,
      ConstraintAnchorType.center,
      ConstraintAnchorType.centerX,
      ConstraintAnchorType.centerY,
    ];
    // A centerX or centerY connect links the sides anchor by anchor,
    // without the reset of the baseline that connecting a top or bottom
    // does, so it can leave a widget with a baseline link and its own top
    // and bottom links. adeps keeps those (the corpora never build one);
    // Android's setWidgetBaseline drops them, as rebuildViewDependents
    // does. The links start from the other six types here.
    const fromTypes = 6;

    ConstraintWidgetContainer build(int seed) {
      final r = math.Random(seed);
      final root = _root();
      final count = 2 + r.nextInt(7);
      final widgets = <ConstraintWidget>[];
      for (var i = 0; i < count; i++) {
        final kind = r.nextInt(10);
        final ConstraintWidget w;
        if (kind == 0) {
          w = Guideline()
            ..setOrientation(r.nextInt(2))
            ..setGuideBegin(r.nextInt(50))
            ..setDebugName('g$i');
        } else if (kind == 1) {
          w = Barrier.named('b$i')..setBarrierType(r.nextInt(4));
        } else {
          w = _fixed('w$i', 10 + r.nextInt(40), 10 + r.nextInt(40));
        }
        widgets.add(w);
        root.add(w);
      }
      final linkable = [
        for (final w in widgets)
          if (w is! Guideline) w,
      ];
      if (linkable.isEmpty) {
        return root;
      }
      for (final w in widgets) {
        if (w is Barrier) {
          for (final o in widgets) {
            if (o != w && r.nextBool()) w.add(o);
          }
        }
      }
      final steps = count * (3 + r.nextInt(4));
      for (var s = 0; s < steps; s++) {
        final roll = r.nextInt(20);
        final from = linkable[r.nextInt(linkable.length)];
        if (roll == 0) {
          from.getAnchor(types[r.nextInt(types.length)])?.reset();
        } else if (roll == 1) {
          from.setHasBaseline(true);
        } else if (roll == 2) {
          from.setGoneMargin(types[r.nextInt(5)], r.nextInt(9));
        } else {
          final targets = [root, ...widgets];
          final to = targets[r.nextInt(targets.length)];
          from.connect(
            types[r.nextInt(fromTypes)],
            to,
            types[r.nextInt(types.length)],
            r.nextInt(20),
          );
        }
      }
      return root;
    }

    test('on 3,000 random layouts', () {
      for (var seed = 0; seed < 3000; seed++) {
        final viaAdeps = build(seed);
        _adeps(viaAdeps);
        final viaRebuild = build(seed);
        rebuildViewDependents(viaRebuild);
        expect(
          dependentsOnly(viaRebuild),
          dependentsOnly(viaAdeps),
          reason: 'seed $seed',
        );
      }
    });
  });
}

/// A match-parent widget with a baseline link and its own top link, and a
/// later child linked into its bottom.
ConstraintWidgetContainer _idempotenceLayout() {
  final root = _root();
  final b2 = _fixed('B2', 50, 40);
  final m = _fixed('M', 30, 0)
    ..setVerticalDimensionBehaviour(DimensionBehaviour.matchParent);
  final later = _fixed('later', 10, 10);
  root
    ..add(b2)
    ..add(m)
    ..add(later);
  _link(b2, _left, root, _left, 0);
  _link(m, _top, root, _top, 7);
  _link(m, _baseline, b2, _baseline, 0);
  _link(later, _top, m, _bottom, 3);
  return root;
}
