// Copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0
//
// No upstream counterpart. The op-list replayer of the parity tooling, for
// tests: a layout is the exact sequence of engine calls that built it, joined
// by ';' ("R 400 300;w a 50 20;add a;c a L root L 10;..."), and the Java
// oracle (VOpDriver, upstream's core at the pin with a Java port of the view
// layer) replays the same list. A test that replays an op list here and
// compares the geometry string with the oracle's therefore compares the port
// with Android, widget for widget and pixel for pixel.
//
// Ported from the parity harness (tool/parity/dart): the op interpreter of
// ops.dart, the geometry and `guarded` of vpaths.dart, the spec form of
// content.dart's ContentMeasurer, and runCore and runView of
// vpaths_future.dart (tool/parity/FORMATS.md 1, 2, 4, 6.1, 8.2, 8.6 and
// 17.1). The op grammar:
//
//   R W H | rtl | ltr | wrapw | wraph | fixw | fixh | cw V | ch V
//   w N W H | b N | g N | fl N | add N | rm N
//   bt N TYPE | bm N MARGIN | bg N 0|1 | ref N CHILD
//   go N ORIENT | gb N V | ge N V | gp N PCT
//   c SRC A DST A MARGIN | x SRC A | cc N TARGET ANGLE RADIUS
//   hb N F|W|M|P | vb N .. | hm N DEF MIN MAX PCT | vm N ..
//   mw N V | mh N V | hx N BIAS | vx N BIAS | gm N A V | v N VIS | bl N V
//   hc N STYLE | vc N STYLE | hw N W | vw N W | ra N RATIO SIDE
//   hbl N 0|1 | sw N V | sh N V | sx N V | sy N V | ipr N | iprest N
//   rereg | adeps | L
//   fo fwm fhs fvs fhb fvb fha fva fhg fvg fme N V | fpad N L T R B
//   frtl N 0|1 | ct N KIND W H BL | cspec WM WS HM HS | cpad L T R B
//   cmin W H | cmax W H
//
// Anchors are L R T B S C CX CY. Floats are read as Java's Float.parseFloat
// reads them (jfloat.dart's parseFloat32). `L` is one measure of the path
// being run; every list ends with an implicit final measure, after which the
// frames are read.

import 'dart:async';

import 'package:constraint_engine/constraint_engine.dart';
import 'package:constraint_engine/src/jfloat.dart' show parseFloat32;

import 'echo_measurer.dart';

/// A replay's result, as vfuzz writes it (FORMATS 1 and 2): status `ok`,
/// `ok-printed` or `EXC:<message>`; geometry with the `!<status> | ` prefix
/// when the status is not `ok`.
typedef OpReplay = ({String status, String geometry});

/// OpDriver's core path (FORMATS 17.1 at [level]): the echo measurer,
/// `measure(level, ...)` for every `L` op and at the end, OpDriver's core
/// geometry rule.
///
/// The container is `ConstraintWidgetContainer.rect(0, 0, W, H)` named
/// `root`. Each measure sets the [EchoMeasurer] and the level, then calls
/// `measure(level, wrap ? AT_MOST : EXACTLY, width, ..., 0, 0, 0, 0)` with
/// the wrap flags and the size read from the container at that moment, as
/// OpDriver does. Content ops (`ct`) and the layout view's ops (`cspec`,
/// `cpad`, `cmin`, `cmax`) are recorded but not read: the oracle's
/// `-Dpath=core` ignores them too.
OpReplay replayCore(String ops, {int level = 257}) {
  final list = ops.split(';');
  final (w, h) = _rootSize(list);
  final root = ConstraintWidgetContainer.rect(0, 0, w, h)..setDebugName('root');
  const measurer = EchoMeasurer();
  void pass() {
    final wrapW =
        root.getHorizontalDimensionBehaviour() ==
        DimensionBehaviour.wrapContent;
    final wrapH =
        root.getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent;
    root.setMeasurer(measurer);
    root.setOptimizationLevel(level);
    root.measure(
      level,
      wrapW ? BasicMeasure.AT_MOST : BasicMeasure.EXACTLY,
      root.getWidth(),
      wrapH ? BasicMeasure.AT_MOST : BasicMeasure.EXACTLY,
      root.getHeight(),
      0,
      0,
      0,
      0,
    );
  }

  final status = _replay(root, list, pass);
  final g = _geometry(root);
  return (status: status, geometry: status == 'ok' ? g : '!$status | $g');
}

/// VOpDriver's view path (FORMATS 8.6 and 17.1 at [level]): one ViewHost
/// and the content measurer, the view geometry rule and the layout view's
/// measured size.
///
/// One [ViewHost] per replay, at [level], measures with a [ViewMeasurer]
/// whose content hook answers from the `ct` ops (a widget without one is a
/// bare `View`). Before every measure the host takes the padding, min and max
/// the `cpad`, `cmin` and `cmax` ops set so far; the specs are `cspec`'s, else
/// EXACTLY at the container's size on a FIXED axis and UNSPECIFIED(0) on a
/// WRAP axis, read from the container at that measure. Geometry follows the
/// view rule: the root is the layout view's measured size, a child's
/// position includes the padding, and guidelines and helpers print their
/// frame even though the host makes them GONE.
OpReplay replayView(String ops, {int level = 257}) {
  final list = ops.split(';');
  final (w, h) = _rootSize(list);
  final root = ConstraintWidgetContainer.rect(0, 0, w, h)..setDebugName('root');
  final host = ViewHost(root, _ContentViewMeasurer())
    ..optimizationLevel = level;
  void pass() {
    final v = _viewOf(root);
    host
      ..paddingLeft = v.padLeft
      ..paddingTop = v.padTop
      ..paddingRight = v.padRight
      ..paddingBottom = v.padBottom
      ..minWidth = v.minWidth
      ..minHeight = v.minHeight
      ..maxWidth = v.maxWidth
      ..maxHeight = v.maxHeight;
    final spec = v.spec;
    final int widthSpec, heightSpec;
    if (spec != null) {
      widthSpec = MeasureSpec.makeMeasureSpec(spec.wSize, spec.wMode);
      heightSpec = MeasureSpec.makeMeasureSpec(spec.hSize, spec.hMode);
    } else {
      widthSpec =
          root.getHorizontalDimensionBehaviour() ==
              DimensionBehaviour.wrapContent
          ? MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
          : MeasureSpec.makeMeasureSpec(root.getWidth(), MeasureSpec.EXACTLY);
      heightSpec =
          root.getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent
          ? MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
          : MeasureSpec.makeMeasureSpec(root.getHeight(), MeasureSpec.EXACTLY);
    }
    host.measure(widthSpec, heightSpec);
  }

  final status = _replay(root, list, pass);
  final g = _geometry(
    root,
    viewRule: true,
    rootW: host.getMeasuredWidth(),
    rootH: host.getMeasuredHeight(),
  );
  return (status: status, geometry: status == 'ok' ? g : '!$status | $g');
}

// ---------------------------------------------------------------------------
// Replay and status (vpaths_future.dart _replay and _status, vpaths.dart
// guarded)
// ---------------------------------------------------------------------------

/// Replays [ops] into [root] (each `L` op runs [pass]), then runs the final
/// [pass], and returns the status. As in VOpDriver, only the final measure's
/// printed exceptions make the status `ok-printed` (each `L` op's output is
/// captured and dropped there), while a throw anywhere makes it `EXC:...`.
String _replay(
  ConstraintWidgetContainer root,
  List<String> ops,
  void Function() pass,
) {
  final (_, thrownByOps) = _guarded(() {
    _applyOps(root, ops, pass);
  });
  if (thrownByOps != null) {
    return 'EXC:${_oneLine(thrownByOps)}';
  }
  final (printed, thrown) = _guarded(pass);
  if (thrown != null) {
    return 'EXC:${_oneLine(thrown)}';
  }
  return printed ? 'ok-printed' : 'ok';
}

/// Runs [body], returning whether it printed (the solver loop prints the
/// exceptions it catches) and what it threw.
(bool, Object?) _guarded(void Function() body) {
  var printed = false;
  Object? thrown;
  runZoned(
    () {
      try {
        body();
      } catch (e) {
        thrown = e;
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        printed = true;
      },
    ),
  );
  return (printed, thrown);
}

String _oneLine(Object e) =>
    e.toString().replaceAll('\t', ' ').replaceAll('\n', ' ');

// ---------------------------------------------------------------------------
// Geometry (vpaths.dart geometry; OpDriver's measureAndReport)
// ---------------------------------------------------------------------------

/// OpDriver's geometry of [root]: `root W x H`, then per child in
/// `mChildren` order ` | name: (x, y) w x h`, or ` | name: gone, w x h` for
/// a GONE child, except a barrier (the core rule) or, with [viewRule], any
/// guideline or helper, which the view layer's onLayout places anyway. The
/// root is reported as [rootW] x [rootH] when given.
String _geometry(
  ConstraintWidgetContainer root, {
  int? rootW,
  int? rootH,
  bool viewRule = false,
}) {
  final sb = StringBuffer()
    ..write('root ${rootW ?? root.getWidth()} x ${rootH ?? root.getHeight()}');
  for (final (i, w) in root.getChildren().indexed) {
    final name = w.getDebugName() ?? '#$i';
    final placed = viewRule
        ? (w is Guideline || w is HelperWidget)
        : w is Barrier;
    if (w.getVisibility() == ConstraintWidget.GONE && !placed) {
      sb.write(' | $name: gone, ${w.getWidth()} x ${w.getHeight()}');
    } else {
      sb.write(
        ' | $name: (${w.getX()}, ${w.getY()}) '
        '${w.getWidth()} x ${w.getHeight()}',
      );
    }
  }
  return sb.toString();
}

// ---------------------------------------------------------------------------
// The layout view's state and the content model (ops.dart ContainerView,
// content.dart's spec form)
// ---------------------------------------------------------------------------

/// The layout view's own state that the view path reads: the specs
/// onMeasure receives (`cspec`), its padding (`cpad`), and its min and max
/// sizes (`cmin`, `cmax`).
final class _ContainerView {
  ({int wMode, int wSize, int hMode, int hSize})? spec;
  int padLeft = 0, padTop = 0, padRight = 0, padBottom = 0;
  int minWidth = 0, minHeight = 0;
  int maxWidth = 0x7fffffff, maxHeight = 0x7fffffff;
}

final Expando<_ContainerView> _views = Expando<_ContainerView>('view');

_ContainerView _viewOf(ConstraintWidgetContainer root) =>
    _views[root] ??= _ContainerView();

enum _ContentKind { box, text, none }

/// What a child view's onMeasure answers (FORMATS.md 6.1), from its `ct`
/// op: `box W H` has the natural size W x H; `text W H` is W wide on one
/// line and H per line, so at width w it takes `H * ceil(W / w)` (`H * 50`
/// when w <= 0); `none` is a bare View (`View.getDefaultSize(0, spec)`).
/// `BL` is what `getBaseline()` returns, -1 for none.
final class _Content {
  const _Content(this.kind, this.w, this.h, this.baseline);

  factory _Content.parseOp(List<String> t) {
    if (t.length != 6 || t[0] != 'ct') {
      throw ArgumentError('ct op: ${t.join(' ')}');
    }
    final kind = switch (t[2]) {
      'box' => _ContentKind.box,
      'text' => _ContentKind.text,
      'none' => _ContentKind.none,
      _ => throw ArgumentError('content kind ${t[2]}'),
    };
    return _Content(kind, int.parse(t[3]), int.parse(t[4]), int.parse(t[5]));
  }

  static const bare = _Content(_ContentKind.none, 0, 0, -1);

  final _ContentKind kind;
  final int w;
  final int h;
  final int baseline;

  /// The height a text takes at [width], with Java's 32-bit int arithmetic.
  int _textHeightAt(int width) {
    if (width <= 0) return (h * 50).toSigned(32);
    return (h * ((w + width - 1) ~/ width)).toSigned(32);
  }

  /// EXACTLY(s) gives s, AT_MOST(s) gives min(n, s), UNSPECIFIED gives n.
  static int _resolve(int n, int mode, int size) {
    if (mode == MeasureSpec.EXACTLY) return size;
    if (mode == MeasureSpec.AT_MOST) return n < size ? n : size;
    return n;
  }

  /// View.getDefaultSize(0, spec): EXACTLY and AT_MOST give the spec size,
  /// UNSPECIFIED gives 0.
  static int _defaultSize(int mode, int size) =>
      mode == MeasureSpec.UNSPECIFIED ? 0 : size;

  ({int width, int height, int baseline}) measure(
    int widthSpec,
    int heightSpec,
  ) {
    final wMode = MeasureSpec.getMode(widthSpec);
    final wSize = MeasureSpec.getSize(widthSpec);
    final hMode = MeasureSpec.getMode(heightSpec);
    final hSize = MeasureSpec.getSize(heightSpec);
    switch (kind) {
      case _ContentKind.box:
        return (
          width: _resolve(w, wMode, wSize),
          height: _resolve(h, hMode, hSize),
          baseline: baseline,
        );
      case _ContentKind.text:
        final width = _resolve(w, wMode, wSize);
        return (
          width: width,
          height: _resolve(_textHeightAt(width), hMode, hSize),
          baseline: baseline,
        );
      case _ContentKind.none:
        return (
          width: _defaultSize(wMode, wSize),
          height: _defaultSize(hMode, hSize),
          baseline: -1,
        );
    }
  }
}

final Expando<_Content> _contents = Expando<_Content>('content');

/// The view measurer of the view path: every child view's onMeasure answers
/// from its `ct` op.
final class _ContentViewMeasurer extends ViewMeasurer {
  @override
  ({int width, int height, int baseline}) measureContent(
    ConstraintWidget widget,
    int widthSpec,
    int heightSpec,
  ) => (_contents[widget] ?? _Content.bare).measure(widthSpec, heightSpec);
}

// ---------------------------------------------------------------------------
// The op interpreter (ops.dart applyOpsWith)
// ---------------------------------------------------------------------------

(int, int) _rootSize(List<String> ops) {
  final t = ops.first.split(' ');
  if (t[0] != 'R') throw ArgumentError('ops must start with R');
  return (int.parse(t[1]), int.parse(t[2]));
}

int _specMode(String m) => switch (m) {
  'E' => MeasureSpec.EXACTLY,
  'A' => MeasureSpec.AT_MOST,
  'U' => MeasureSpec.UNSPECIFIED,
  _ => throw ArgumentError('spec mode $m'),
};

ConstraintAnchorType _anchor(String s) => switch (s) {
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

DimensionBehaviour _behaviour(String s) => switch (s) {
  'F' => DimensionBehaviour.fixed,
  'W' => DimensionBehaviour.wrapContent,
  'M' => DimensionBehaviour.matchConstraint,
  'P' => DimensionBehaviour.matchParent,
  _ => throw ArgumentError('behaviour $s'),
};

/// The dependents an `ipr` op saved, for a later `iprest`.
final Expando<List<Set<ConstraintAnchor>?>> _savedDependents =
    Expando<List<Set<ConstraintAnchor>?>>('saved dependents');

/// Replays [ops] (the `R` op included, which does nothing here) into
/// [root]; an `L` op runs [layoutPass].
void _applyOps(
  ConstraintWidgetContainer root,
  List<String> ops,
  void Function() layoutPass,
) {
  final by = <String, ConstraintWidget>{'root': root};
  ConstraintWidget n(String name) =>
      by[name] ?? (throw ArgumentError('unknown $name'));
  for (final op in ops) {
    final t = op.split(' ');
    switch (t[0]) {
      case 'R':
        break;
      case 'rtl':
        root.setRtl(true);
      case 'ltr':
        root.setRtl(false);
      case 'wrapw':
        root.setHorizontalDimensionBehaviour(DimensionBehaviour.wrapContent);
      case 'wraph':
        root.setVerticalDimensionBehaviour(DimensionBehaviour.wrapContent);
      case 'fixw':
        root.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
      case 'fixh':
        root.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
      case 'cw':
        root.setWidth(int.parse(t[1]));
      case 'ch':
        root.setHeight(int.parse(t[1]));
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
      case 'fl':
        by[t[1]] = Flow()..setDebugName(t[1]);
      case 'add':
        root.add(n(t[1]));
      case 'rm':
        root.remove(n(t[1]));
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
        (n(t[1]) as Guideline).setGuidePercent(parseFloat32(t[2]));
      case 'c':
        n(t[1]).connect(_anchor(t[2]), n(t[3]), _anchor(t[4]), int.parse(t[5]));
      case 'x':
        n(t[1]).getAnchor(_anchor(t[2]))!.reset();
      case 'cc':
        n(t[1]).connectCircularConstraint(
          n(t[2]),
          parseFloat32(t[3]),
          int.parse(t[4]),
        );
      case 'hb':
        n(t[1]).setHorizontalDimensionBehaviour(_behaviour(t[2]));
      case 'vb':
        n(t[1]).setVerticalDimensionBehaviour(_behaviour(t[2]));
      case 'hm':
        n(t[1]).setHorizontalMatchStyle(
          int.parse(t[2]),
          int.parse(t[3]),
          int.parse(t[4]),
          parseFloat32(t[5]),
        );
      case 'vm':
        n(t[1]).setVerticalMatchStyle(
          int.parse(t[2]),
          int.parse(t[3]),
          int.parse(t[4]),
          parseFloat32(t[5]),
        );
      case 'mw':
        n(t[1]).setMinWidth(int.parse(t[2]));
      case 'mh':
        n(t[1]).setMinHeight(int.parse(t[2]));
      case 'hx':
        n(t[1]).setHorizontalBiasPercent(parseFloat32(t[2]));
      case 'vx':
        n(t[1]).setVerticalBiasPercent(parseFloat32(t[2]));
      case 'gm':
        n(t[1]).setGoneMargin(_anchor(t[2]), int.parse(t[3]));
      case 'v':
        n(t[1]).setVisibility(int.parse(t[2]));
      case 'bl':
        n(t[1]).setBaselineDistance(int.parse(t[2]));
      case 'hc':
        n(t[1]).setHorizontalChainStyle(int.parse(t[2]));
      case 'vc':
        n(t[1]).setVerticalChainStyle(int.parse(t[2]));
      case 'hw':
        n(t[1]).setHorizontalWeight(parseFloat32(t[2]));
      case 'vw':
        n(t[1]).setVerticalWeight(parseFloat32(t[2]));
      case 'ra':
        n(t[1]).setDimensionRatio(parseFloat32(t[2]), int.parse(t[3]));
      case 'hbl':
        n(t[1]).setHasBaseline(t[2] == '1');
      case 'sw':
        n(t[1]).setWidth(int.parse(t[2]));
      case 'sh':
        n(t[1]).setHeight(int.parse(t[2]));
      case 'sx':
        n(t[1]).setX(int.parse(t[2]));
      case 'sy':
        n(t[1]).setY(int.parse(t[2]));
      case 'ipr':
        // An in-place anchor reset: every anchor reset, the incoming
        // dependents kept.
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
        // After the connects, the incoming dependents the last `ipr` saved
        // that still target the anchor.
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
        // Every live link registered with its target.
        for (final c in root.getChildren()) {
          for (final a in c.mAnchors) {
            final target = a.mTarget;
            if (target != null) {
              (target.mDependents ??= <ConstraintAnchor>{}).add(a);
            }
          }
        }
      case 'adeps':
        // The dependents Android's view layer leaves
        // (ConstraintLayout.setChildrenConstraints): every live link is
        // registered with its target, except a link from a child configured
        // before X into X's top or bottom when X has a baseline link
        // (setWidgetBaseline resets X's top and bottom, dropping them).
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
        layoutPass();
      case 'ct':
        _contents[n(t[1])] = _Content.parseOp(t);
      case 'fo':
        (n(t[1]) as Flow).setOrientation(int.parse(t[2]));
      case 'fwm':
        (n(t[1]) as Flow).setWrapMode(int.parse(t[2]));
      case 'fhs':
        (n(t[1]) as Flow).setHorizontalStyle(int.parse(t[2]));
      case 'fvs':
        (n(t[1]) as Flow).setVerticalStyle(int.parse(t[2]));
      case 'fhb':
        (n(t[1]) as Flow).setHorizontalBias(parseFloat32(t[2]));
      case 'fvb':
        (n(t[1]) as Flow).setVerticalBias(parseFloat32(t[2]));
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
        _viewOf(root).spec = (
          wMode: _specMode(t[1]),
          wSize: int.parse(t[2]),
          hMode: _specMode(t[3]),
          hSize: int.parse(t[4]),
        );
      case 'cpad':
        _viewOf(root)
          ..padLeft = int.parse(t[1])
          ..padTop = int.parse(t[2])
          ..padRight = int.parse(t[3])
          ..padBottom = int.parse(t[4]);
      case 'cmin':
        _viewOf(root)
          ..minWidth = int.parse(t[1])
          ..minHeight = int.parse(t[2]);
      case 'cmax':
        _viewOf(root)
          ..maxWidth = int.parse(t[1])
          ..maxHeight = int.parse(t[2]);
      default:
        throw ArgumentError('op $op');
    }
  }
}
