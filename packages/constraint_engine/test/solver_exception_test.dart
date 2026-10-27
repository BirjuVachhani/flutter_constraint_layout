// The layouts on which Java's solver loop catches and prints an exception
// at OPTIMIZATION_STANDARD (257): class (i) of the exception gate
// (tool/parity/gates/exc.sh, classes in compare/exc_classify.py). Java
// throws inside the solver at the same operation as the port (the TraceJava
// and Dart solver traces of all of them are identical at 257, the throws
// included), so the port keeps the swallow and the partial-state readback,
// which is Android's behaviour.
//
// They are the corpus A layouts (adversarial: stale links, cycles, gone
// references) that print at 257 on the pinned oracle (VOpDriver v2, core
// path, -XX:hashCode=2, levels 257,0, with -Dprobe: A.java, which
// tool/parity/gates/java_refs.sh writes; op lists from A.in, which
// tool/parity/gates/corpora.sh writes). For each, at both levels: the frames
// and the printed status, byte for byte, through OpDriver's core path
// (support/op_replay.dart); and the exceptions the last measure printed, in
// order, as Java classes (the P field's `excs`): a failed null check is
// Java's NullPointerException (ArrayLinkedVariables.get, line 642) and a
// RangeError its ArrayIndexOutOfBoundsException (index -1,
// ArrayRow.updateFromSystem, line 799), as SolverTrace.javaExceptionClass
// maps them. Three of them print only at 257.
//
// Two more layouts, built by hand ([_centeredDependents]), pin upstream's
// NullPointerException in ConstraintAnchor.hasCenteredDependents
// (ConstraintAnchor.java 68): a baseline linked to the bottom of a barrier
// that Direct did not resolve, which Barrier.addToSolver asks about inside
// the solve. No corpus makes that link.

import 'dart:async';

import 'package:constraint_engine/constraint_engine.dart';
import 'package:constraint_engine/src/debug/solver_trace.dart';
import 'package:constraint_engine/src/jfloat.dart' show parseFloat32;
import 'package:test/test.dart';

import 'support/echo_measurer.dart';
import 'support/op_replay.dart';

const _npe = 'java.lang.NullPointerException';
const _aioobe = 'java.lang.ArrayIndexOutOfBoundsException';

/// One layout and what Java gives for it at a level: the geometry (with its
/// `!ok-printed | ` prefix when the last measure printed) and the classes of
/// the exceptions it printed, in order.
typedef _Java = ({String geometry, List<String> exceptions});

typedef _Repro = ({String id, String ops, _Java j257, _Java j0});

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

/// The layout of [ops], built with the engine calls OpDriver makes for them
/// (the oracle's dart/ops.dart), for the ops these repros use.
ConstraintWidgetContainer _build(String ops) {
  final list = ops.split(';');
  final size = list.first.split(' ');
  final root = ConstraintWidgetContainer.rect(
    0,
    0,
    int.parse(size[1]),
    int.parse(size[2]),
  )..setDebugName('root');
  final byName = <String, ConstraintWidget>{'root': root};
  ConstraintWidget n(String name) => byName[name]!;
  for (final op in list.skip(1)) {
    final t = op.split(' ');
    switch (t[0]) {
      case 'rtl':
        root.setRtl(true);
      case 'w':
        byName[t[1]] = ConstraintWidget.sizeNamed(
          t[1],
          int.parse(t[2]),
          int.parse(t[3]),
        );
      case 'b':
        byName[t[1]] = Barrier.named(t[1]);
      case 'g':
        byName[t[1]] = Guideline()..setDebugName(t[1]);
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
      case 'gp':
        (n(t[1]) as Guideline).setGuidePercent(parseFloat32(t[2]));
      case 'c':
        n(t[1]).connect(_anchor(t[2]), n(t[3]), _anchor(t[4]), int.parse(t[5]));
      case 'x':
        n(t[1]).getAnchor(_anchor(t[2]))!.reset();
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
      case 'ra':
        n(t[1]).setDimensionRatio(parseFloat32(t[2]), int.parse(t[3]));
      default:
        throw ArgumentError('op $op');
    }
  }
  return root;
}

/// Measures [root] as OpDriver's core path does at [level] (the oracle's
/// runCore) and returns what the solver loop printed.
List<String> _measure(ConstraintWidgetContainer root, int level) {
  final printed = <String>[];
  runZoned(
    () {
      final wrapW =
          root.getHorizontalDimensionBehaviour() ==
          DimensionBehaviour.wrapContent;
      final wrapH =
          root.getVerticalDimensionBehaviour() ==
          DimensionBehaviour.wrapContent;
      root
        ..setMeasurer(const EchoMeasurer())
        ..setOptimizationLevel(level)
        ..measure(
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
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
  return printed;
}

/// The Java class SolverTrace.javaExceptionClass gives for the error whose
/// line (`EXCEPTION : <error>`) the solver loop printed: the same rules,
/// read from the error's text, which is all a print carries.
String _javaClassOf(String line) {
  const prefix = 'EXCEPTION : ';
  expect(line, startsWith(prefix));
  final error = line.substring(prefix.length);
  if (error.contains('Null check operator')) {
    return _npe;
  }
  if (error.startsWith('RangeError')) {
    return _aioobe;
  }
  if (error.contains(' is not a subtype of ')) {
    return 'java.lang.ClassCastException';
  }
  return 'dart: $error';
}

/// OpDriver's core geometry of [root] (FORMATS.md 2), without a status.
String _geometry(ConstraintWidgetContainer root) {
  final sb = StringBuffer('root ${root.getWidth()} x ${root.getHeight()}');
  for (final w in root.getChildren()) {
    if (w.getVisibility() == ConstraintWidget.GONE && w is! Barrier) {
      sb.write(
        ' | ${w.getDebugName()}: gone, ${w.getWidth()} x ${w.getHeight()}',
      );
    } else {
      sb.write(
        ' | ${w.getDebugName()}: (${w.getX()}, ${w.getY()}) '
        '${w.getWidth()} x ${w.getHeight()}',
      );
    }
  }
  return sb.toString();
}

Object? _none() => null;

const List<_Repro> _repros = [
  (
    id: 'A-ext:99004672',
    ops:
        'R 746 296;g g0;go g0 1;gp g0 0.3;add g0;g g1;go g1 1;gb g1 62;'
        'add g1;w w0 108 44;w w1 98 10;w w2 104 70;w w3 148 92;w w4 64 20;'
        'w w5 48 40;w w6 124 58;b b0;bt b0 1;bm b0 20;bg b0 0;b b1;bt b1 1;'
        'bg b1 1;b b2;bt b2 2;bg b2 0;add w0;add w4;add w5;add w6;add b2;'
        'add w2;add w3;add b0;add w1;add b1;ref b0 b1;ref b1 b0;ref b1 w2;'
        'ref b2 w0;ref b2 w2;c w0 L g0 R 38;c w0 R b0 L 38;hb w0 W;vb w0 M;'
        'vx w0 0.5;c w1 L w0 R 18;hb w1 W;hx w1 1.0;c w1 T w0 B 24;v w1 8;'
        'c w2 L root L 0;c w2 R b1 R 14;hb w2 M;hm w2 1 0 0 1.0;hx w2 1.0;'
        'c w2 T root T 0;c w2 B w0 B 6;vb w2 M;vm w2 2 136 94 0.25;'
        'gm w2 T 24;c w2 L w6 R 0;v w2 4;c w3 R root R 2;c w3 T b2 T 36;'
        'c w3 B w0 B 24;vx w3 0.0;v w3 4;c w4 L b0 L 0;gm w4 L 6;'
        'c w4 T w3 B 14;vb w4 W;c w5 L b0 R 32;hb w5 M;hm w5 2 0 0 0.2;'
        'c w5 T w1 T 0;c w5 B b2 T 18;gm w5 T 8;v w5 8;c w6 L root L 14;'
        'c w6 R root R 0;hb w6 M;hm w6 0 36 0 1.0;hx w6 0.0;c w6 T b2 T 0;'
        'c w6 B w2 B 38;bl w6 29;bl w3 46;x w6 T;x w6 B;c w6 S w3 S 0',
    j257: (
      geometry:
          '!ok-printed | root 746 x 296 | g0: (224, 0) 0 x 296 | '
          'g1: (62, 0) 0 x 296 | w0: (0, 0) 0 x 44 | w4: (0, 0) 64 x 0 | '
          'w5: gone, 0 x 0 | w6: (0, 0) 0 x 58 | b2: (0, 0) 0 x 0 | '
          'w2: (0, 0) 0 x 0 | w3: (596, 0) 148 x 92 | b0: (0, 0) 0 x 0 | '
          'w1: gone, 0 x 0 | b1: (0, 0) 0 x 0',
      exceptions: [_npe],
    ),
    j0: (
      geometry:
          '!ok-printed | root 746 x 296 | g0: (224, 0) 0 x 296 | '
          'g1: (62, 0) 0 x 296 | w0: (0, 0) 0 x 44 | w4: (0, 0) 64 x 0 | '
          'w5: gone, 0 x 0 | w6: (0, 0) 0 x 58 | b2: (0, 0) 0 x 0 | '
          'w2: (0, 0) 0 x 0 | w3: (596, 0) 148 x 92 | b0: (0, 0) 0 x 0 | '
          'w1: gone, 0 x 0 | b1: (0, 0) 0 x 0',
      exceptions: [_npe],
    ),
  ),
  (
    id: 'A-ext:99005217',
    ops:
        'R 254 248;rtl;w w0 90 26;w w1 142 42;w w2 34 16;w w3 38 44;b b0;'
        'bt b0 2;bm b0 40;bg b0 0;b b1;bt b1 3;bm b1 32;bg b1 1;add w0;'
        'add w1;add b0;add w3;add w2;add b1;ref b1 w0;c w2 L root L 0;'
        'c w2 R w3 L 0;c w3 L w2 R 0;c w3 R root R 2;hc w2 1;'
        'c w0 R w3 L 12;hb w0 M;c w0 T b1 B 10;c w1 L w0 R 34;'
        'c w1 R root R 0;hb w1 M;hm w1 2 26 58 0.2;gm w1 L 2;vb w1 M;'
        'vm w1 2 22 46 0.2;gm w1 T 14;c w2 T w1 B 28;vx w2 0.0;v w2 4;'
        'gm w3 L 12;c w3 T w2 B 16;vb w3 M;vx w3 0.0',
    j257: (
      geometry:
          '!ok-printed | root 254 x 248 | w0: (0, 0) 0 x 26 | '
          'w1: (0, 0) 0 x 46 | b0: (0, 0) 0 x 0 | w3: (0, 0) 38 x 0 | '
          'w2: (0, 0) 34 x 16 | b1: (0, 0) 0 x 0',
      exceptions: [_npe, _aioobe, _npe],
    ),
    j0: (
      geometry:
          '!ok-printed | root 254 x 248 | w0: (0, 0) 0 x 26 | '
          'w1: (0, 0) 0 x 46 | b0: (0, 0) 0 x 0 | w3: (0, 0) 38 x 0 | '
          'w2: (0, 0) 34 x 16 | b1: (0, 0) 0 x 0',
      exceptions: [_npe, _aioobe, _npe],
    ),
  ),
  (
    id: 'A-ext:99011487',
    ops:
        'R 472 270;w w0 78 56;w w1 128 32;w w2 144 98;w w3 130 36;'
        'w w4 42 12;w w5 50 48;b b0;bt b0 1;bm b0 -6;bg b0 0;b b1;bt b1 2;'
        'bm b1 -18;bg b1 0;add w3;add w4;add w2;add w5;add b0;add w1;'
        'add w0;add b1;ref b0 w1;ref b1 w3;ref b1 w1;hb w0 M;gm w0 T 4;'
        'c w1 R root R 0;hx w1 0.5;c w2 L w0 L 14;c w2 T b1 T 24;vb w2 W;'
        'vx w2 1.0;v w2 8;c w3 L b0 R 32;c w3 R w1 R 8;hb w3 M;mw w3 70;'
        'hx w3 1.0;c w3 T b1 T 18;vb w3 M;vx w3 1.0;c w4 L w0 R 0;'
        'c w4 R w3 L 0;hx w4 0.0;c w4 T b1 T 26;vb w4 M;mh w4 28;vx w4 0.5;'
        'gm w4 T 12;c w5 R w0 L 14;c w5 T w0 T 0;vb w5 M;gm w5 T 4',
    j257: (
      geometry:
          '!ok-printed | root 472 x 270 | w3: (394, 0) 70 x 0 | '
          'w4: (0, 8) 42 x 28 | w2: gone, 0 x 0 | w5: (-63, 0) 50 x 0 | '
          'b0: (0, 0) 0 x 0 | w1: (344, 0) 128 x 32 | w0: (0, 0) 0 x 56 | '
          'b1: (0, -17) 0 x 0',
      exceptions: [_npe, _aioobe],
    ),
    j0: (
      geometry:
          '!ok-printed | root 472 x 270 | w3: (394, 0) 70 x 0 | '
          'w4: (0, 8) 42 x 28 | w2: gone, 0 x 0 | w5: (-63, 0) 50 x 0 | '
          'b0: (466, 0) 0 x 0 | w1: (344, 0) 128 x 32 | '
          'w0: (0, 0) 0 x 56 | b1: (0, -17) 0 x 0',
      exceptions: [_npe, _aioobe],
    ),
  ),
  (
    id: 'A-ext:99015494',
    ops:
        'R 614 524;g g0;go g0 1;gp g0 0.1;add g0;w w0 54 108;w w1 140 20;'
        'w w2 26 36;w w3 12 72;w w4 122 92;w w5 16 30;b b0;bt b0 3;'
        'bm b0 -14;bg b0 1;b b1;bt b1 0;bm b1 -12;bg b1 1;b b2;bt b2 0;'
        'bm b2 26;bg b2 0;add b1;add b2;add w1;add w4;add w5;add w2;add w3;'
        'add w0;add b0;ref b0 w2;ref b1 g0;ref b1 w3;ref b2 w3;'
        'c w0 L b1 L 20;hb w0 W;gm w0 L 2;vx w0 0.5;c w1 L w0 R 0;'
        'c w1 R w0 R 16;hb w1 W;c w1 T root B 14;vb w1 M;c w2 L w1 L 18;'
        'c w2 T b0 B 0;vb w2 M;vm w2 1 0 0 1.0;vx w2 0.0;hb w3 W;hx w3 0.0;'
        'c w3 T w0 B 30;vb w3 M;gm w3 T 30;v w3 4;c w4 L root L 18;'
        'c w4 R g0 R 28;hb w4 M;hm w4 0 60 76 1.0;c w4 T b0 T 0;'
        'c w5 L g0 L 20;hb w5 M;c w5 T root T 34;c w5 B root T 0;gm w5 T 10',
    j257: (
      geometry:
          '!ok-printed | root 614 x 524 | g0: (61, 0) 0 x 524 | '
          'b1: (0, 0) 0 x 0 | b2: (0, 0) 0 x 0 | w1: (0, 538) 0 x 20 | '
          'w4: (0, 0) 0 x 92 | w5: (81, -14) 16 x 30 | w2: (0, 0) 26 x 0 | '
          'w3: (0, 0) 12 x 0 | w0: (0, 0) 0 x 108 | b0: (0, 0) 0 x 0',
      exceptions: [_npe],
    ),
    j0: (
      geometry:
          '!ok-printed | root 614 x 524 | g0: (61, 0) 0 x 524 | '
          'b1: (0, 0) 0 x 0 | b2: (0, 0) 0 x 0 | w1: (0, 538) 0 x 20 | '
          'w4: (0, 0) 0 x 92 | w5: (81, -14) 16 x 30 | w2: (0, 0) 26 x 0 | '
          'w3: (0, 0) 12 x 0 | w0: (0, 0) 0 x 108 | b0: (0, 0) 0 x 0',
      exceptions: [_npe],
    ),
  ),
  (
    id: 'A-extl:99006761',
    ops:
        'R 657 619;rtl;g g0;go g0 0;gb g0 122;add g0;g g1;go g1 0;'
        'gb g1 191;add g1;w w0 62 14;w w1 76 76;w w2 69 24;w w3 109 105;'
        'w w4 127 77;w w5 86 42;w w6 26 66;w w7 142 100;b b0;bt b0 2;'
        'bm b0 6;bg b0 0;v b0 8;add w0;add w4;add w2;add w3;add w7;add w6;'
        'add b0;add w5;add w1;ref b0 w5;c w0 T root T 31;vb w0 M;'
        'vm w0 2 0 34 0.5;vx w0 0.0;gm w0 T 30;gm w1 L 22;c w1 T root B 0;'
        'gm w1 T 12;c w1 T w4 B 6;c w2 L w0 R 8;hb w2 M;hx w2 0.0;'
        'c w2 T w0 B 24;gm w2 T 16;c w3 L w1 R 0;c w3 R root L 0;'
        'c w3 T root B 39;c w3 B root T 28;vb w3 M;c w4 L w1 L 0;hb w4 W;'
        'gm w4 L 18;c w4 B b0 T 0;vb w4 M;vx w4 0.0;c w5 L root L 22;'
        'c w5 T b0 B 13;vx w5 0.4;gm w5 T 2;c w6 L root L 9;c w6 R w5 R 25;'
        'hb w6 W;gm w6 L 30;c w6 T w1 B 14;c w6 B b0 B 0;vb w6 P;'
        'gm w6 T 24;c w7 L w5 R 0;hb w7 M;hx w7 0.4;c w7 T b0 T 3;'
        'c w7 B w0 T 36;vb w7 M;mh w7 52;vx w7 0.1;v w7 4',
    j257: (
      geometry:
          '!ok-printed | root 657 x 619 | g0: (0, 122) 657 x 0 | '
          'g1: (0, 191) 657 x 0 | w0: (0, 31) 62 x 34 | '
          'w4: (0, -59) 0 x 0 | w2: (70, 89) 0 x 24 | w3: (0, 0) 109 x 0 | '
          'w7: (108, -56) 0 x 52 | w6: (46, 14) 0 x 605 | '
          'b0: (0, -59) 0 x 0 | w5: (22, -52) 86 x 42 | '
          'w1: (0, -53) 76 x 76',
      exceptions: [_npe, _aioobe],
    ),
    j0: (
      geometry:
          'root 657 x 619 | g0: (0, 122) 657 x 0 | g1: (0, 191) 657 x 0 | '
          'w0: (0, 31) 62 x 34 | w4: (0, -136) 127 x 77 | '
          'w2: (70, 89) 69 x 24 | w3: (0, 0) 109 x 0 | '
          'w7: (108, -56) 0 x 52 | w6: (33, 14) 26 x 605 | '
          'b0: (0, -59) 0 x 0 | w5: (22, -52) 86 x 42 | '
          'w1: (0, -53) 76 x 76',
      exceptions: [],
    ),
  ),
  (
    id: 'A-vadv:99001417',
    ops:
        'R 113 496;rtl;w w0 26 140;w w1 152 165;bl w1 26;w w2 129 101;'
        'bl w2 6;w w3 190 28;bl w3 15;w w4 8 19;bl w4 12;w w5 174 186;'
        'bl w5 31;w w6 28 146;bl w6 5;w w7 165 40;b b0;bt b0 0;add w2;'
        'add w0;add w4;add w3;add w7;add b0;add w1;add w6;add w5;ref b0 w0;'
        'vb w0 M;vm w0 2 0 209 0.6;c w0 L root R 4;c w0 R root R 8;'
        'c w0 T root B -24;c w0 B root T 11;hb w1 M;hm w1 2 0 0 0.8;'
        'vb w1 W;mh w1 17;c w1 L root R 7;c w1 R w0 R 0;hb w2 M;'
        'hm w2 2 0 0 0.1;vb w2 M;vm w2 2 0 0 0.55;hx w2 0.45;'
        'c w2 T w0 B 11;c w2 B root B 0;hb w3 M;hm w3 2 0 0 0.65;vb w3 F;'
        'mh w3 11;ra w3 1.5 -1;vx w3 0.7;c w3 L root L 4;c w3 R w2 L 0;'
        'c w3 S w0 S 0;hb w4 M;hm w4 0 14 0 1.0;vb w4 W;hx w4 0.1;'
        'c w4 S w6 S 0;gm w4 L 33;hb w5 M;hm w5 2 50 0 0.15;mw w5 20;'
        'vb w5 M;vm w5 0 0 99 1.0;c w5 L w3 L 0;c w5 R w4 R 0;'
        'c w5 T w3 T 0;c w5 B w4 T -24;hb w6 F;c w6 L w4 R 11;hb w7 F;'
        'vb w7 P;c w7 L w0 R 24;c w7 R w3 L 16;c w7 T w2 B 11;'
        'c w7 B root T 3',
    j257: (
      geometry:
          '!ok-printed | root 113 x 496 | w2: (0, 112) 11 x 272 | '
          'w0: (0, 0) 26 x 0 | w4: (0, -6) 14 x 0 | w3: (0, 0) 0 x 28 | '
          'w7: (-13, 11) 165 x 482 | b0: (0, 0) 0 x 0 | '
          'w1: (78, 0) 90 x 17 | w6: (25, 0) 28 x 146 | w5: (0, 0) 20 x 0',
      exceptions: [
        _npe,
        _aioobe,
        _npe,
        _aioobe,
        _npe,
        _aioobe,
        _aioobe,
        _npe,
        _aioobe,
        _aioobe,
        _aioobe,
        _aioobe,
        _npe,
        _aioobe,
        _aioobe,
        _aioobe,
        _aioobe,
      ],
    ),
    j0: (
      geometry:
          '!ok-printed | root 113 x 496 | w2: (0, 0) 11 x 0 | '
          'w0: (100, 0) 26 x 0 | w4: (0, 0) 14 x 0 | w3: (0, 0) 0 x 28 | '
          'w7: (0, 11) 165 x 482 | b0: (0, 0) 0 x 0 | w1: (0, 0) 0 x 17 | '
          'w6: (0, 0) 28 x 146 | w5: (0, 0) 20 x 0',
      exceptions: [
        _npe,
        _aioobe,
        _npe,
        _aioobe,
        _npe,
        _aioobe,
        _npe,
        _aioobe,
        _npe,
        _aioobe,
        _npe,
        _aioobe,
        _npe,
        _aioobe,
        _npe,
        _aioobe,
        _npe,
      ],
    ),
  ),
  (
    id: 'A-vext:99003906',
    ops:
        'R 500 965;w w0 124 122;bl w0 65;w w1 169 84;w w2 185 139;'
        'bl w2 112;b b0;w w3 7 9;w w4 157 131;bl w4 19;w w5 187 50;'
        'bl w5 48;add w3;add w4;add w0;add w1;add w5;add b0;add w2;hb w0 W;'
        'vb w0 W;vx w0 0.65;v w0 4;c w0 L root R 0;c w0 R root R 7;'
        'c w0 T root B 0;c w0 B root T 8;hb w1 P;vb w1 M;vm w1 0 16 0 0.4;'
        'v w1 8;hb w2 M;vb w2 F;hm w2 0 0 0 0.2;ra w2 1.5 1;c w2 T w0 B 0;'
        'c w2 B w0 T 16;bt b0 2;ref b0 w0;hb w3 P;vb w3 W;hb w4 M;vb w4 P;'
        'hm w4 0 22 129 0.375;ra w4 1.0 0;c w4 L w2 R 4;c w4 R w3 R 8;'
        'gm w4 L 26;c w4 T w1 B 3;c w4 B b0 B 0;hb w5 P;vb w5 W;'
        'c w5 L w4 R 0;c w5 R w4 L 12;c w5 T root B 7',
    j257: (
      geometry:
          '!ok-printed | root 500 x 965 | w3: (0, 0) 500 x 9 | '
          'w4: (0, 3) 0 x 962 | w0: (0, 0) 0 x 0 | w1: gone, 0 x 0 | '
          'w5: (0, 0) 0 x 0 | b0: (0, 0) 0 x 0 | w2: (0, 0) 0 x 139',
      exceptions: [_npe, _aioobe, _npe],
    ),
    j0: (
      geometry:
          'root 500 x 965 | w3: (0, 0) 500 x 9 | w4: (234, 3) 129 x 962 | '
          'w0: (438, 253) 124 x 122 | w1: gone, 0 x 0 | '
          'w5: (0, 972) 488 x 50 | b0: (0, 253) 0 x 0 | '
          'w2: (0, 237) 100 x 139',
      exceptions: [],
    ),
  ),
  (
    id: 'A-vext:99005987',
    ops:
        'R 253 691;w w0 76 32;bl w0 31;w w1 116 30;w w2 176 41;bl w2 28;'
        'w w3 119 92;bl w3 61;b b0;w w4 48 78;bl w4 47;b b1;add w1;add w0;'
        'add b0;add w4;add w3;add w2;add b1;hb w0 F;vb w0 W;hx w0 0.1;'
        'vx w0 0.67;c w0 CX root CX 0;hb w1 P;vb w1 W;c w1 L root R 8;'
        'c w1 R w0 L 3;c w1 CY root CY 0;hb w2 M;vb w2 W;hm w2 0 44 0 0.7;'
        'ra w2 0.75 -1;hx w2 0.5;vx w2 0.4;c w2 L root L 0;c w2 R root L 7;'
        'hb w3 W;vb w3 W;v w3 4;c w3 L w1 R 8;c w3 R w2 L -5;c w3 T w1 B 0;'
        'c w3 B root T 12;bt b0 0;bm b0 16;ref b0 w3;ref b0 w2;ref b0 w1;'
        'hb w4 P;vb w4 F;c w4 CX w3 CX 0;c w4 T w0 B 12;bt b1 0;ref b1 w4',
    j257: (
      geometry:
          '!ok-printed | root 253 x 691 | w1: (8, 0) 242 x 0 | '
          'w0: (0, 0) 76 x 0 | b0: (0, 0) 0 x 0 | w4: (0, 0) 0 x 78 | '
          'w3: (0, 0) 0 x 0 | w2: (0, 0) 0 x 0 | b1: (0, 0) 0 x 0',
      exceptions: [_npe],
    ),
    j0: (
      geometry:
          '!ok-printed | root 253 x 691 | w1: (8, 331) 242 x 30 | '
          'w0: (18, 0) 76 x 32 | b0: (0, 0) 0 x 0 | w4: (0, 44) 253 x 78 | '
          'w3: (0, 128) 0 x 92 | w2: (0, 0) 0 x 41 | b1: (0, 0) 0 x 0',
      exceptions: [_npe],
    ),
  ),
  (
    id: 'A-vext:99016492',
    ops:
        'R 1168 550;g g0;w w0 187 99;w w1 54 58;w w2 134 56;bl w2 43;'
        'w w3 73 152;w w4 84 41;bl w4 14;b bz;add g0;add w0;add w1;add w2;'
        'add w3;add w4;add bz;go g0 0;gb g0 193;hb w0 W;vb w0 P;hx w0 0.45;'
        'c w0 L root L 7;c w0 R root R 0;gm w0 L 1;c w0 T root T 4;'
        'c w0 B root T 7;hb w1 W;vb w1 F;v w1 8;c w1 L w0 L 16;'
        'c w1 S w0 S 8;hb w2 M;vb w2 P;hm w2 2 36 36 0.375;vx w2 0.67;'
        'c w2 L root R -9;c w2 R root R 0;c w2 S w1 S 0;hb w3 P;vb w3 W;'
        'hx w3 0.3;vx w3 0.67;v w3 4;c w3 T root B 0;hb w4 M;vb w4 F;'
        'hm w4 0 42 0 0.4;ra w4 0.5 0;hx w4 0.5;vx w4 0.25;c w4 L w2 L 0;'
        'c w4 R w1 R 0;c w4 S w1 S 0;bt bz 1;ref bz w0;ref bz w1',
    j257: (
      geometry:
          '!ok-printed | root 1168 x 550 | g0: (0, 193) 1168 x 0 | '
          'w0: (529, 4) 0 x 539 | w1: gone, 0 x 0 | '
          'w2: (1150, 0) 36 x 550 | w3: (0, 550) 1168 x 0 | '
          'w4: (1150, 0) 42 x 41 | bz: (0, 0) 0 x 0',
      exceptions: [_npe, _aioobe],
    ),
    j0: (
      geometry:
          '!ok-printed | root 1168 x 550 | g0: (0, 193) 1168 x 0 | '
          'w0: (0, 4) 0 x 539 | w1: gone, 0 x 0 | w2: (0, 0) 0 x 0 | '
          'w3: (0, 0) 0 x 0 | w4: (0, 0) 0 x 41 | bz: (0, 0) 0 x 0',
      exceptions: [_npe, _aioobe, _npe],
    ),
  ),
  (
    id: 'A-vext2:99003906',
    ops:
        'R 500 965;w w0 124 122;bl w0 65;w w1 169 84;w w2 185 139;'
        'bl w2 112;b b0;w w3 7 9;w w4 157 131;bl w4 19;w w5 187 50;'
        'bl w5 48;add w3;add w4;add w0;add w1;add w5;add b0;add w2;hb w0 W;'
        'vb w0 W;vx w0 0.65;v w0 4;c w0 L root R 0;c w0 R root R 7;'
        'c w0 T root B 0;c w0 B root T 8;hb w1 P;vb w1 M;vm w1 0 16 0 0.4;'
        'v w1 8;hb w2 M;vb w2 F;hm w2 0 0 0 0.2;ra w2 1.5 1;c w2 T w0 B 0;'
        'c w2 B w0 T 16;bt b0 2;ref b0 w0;hb w3 P;vb w3 W;hb w4 M;vb w4 P;'
        'hm w4 0 22 129 0.375;ra w4 1.0 0;c w4 L w2 R 4;c w4 R w3 R 8;'
        'gm w4 L 26;c w4 T w1 B 3;c w4 B b0 B 0;hb w5 P;vb w5 W;'
        'c w5 L w4 R 0;c w5 R w4 L 12;c w5 T root B 7',
    j257: (
      geometry:
          '!ok-printed | root 500 x 965 | w3: (0, 0) 500 x 9 | '
          'w4: (0, 3) 0 x 962 | w0: (0, 0) 0 x 0 | w1: gone, 0 x 0 | '
          'w5: (0, 0) 0 x 0 | b0: (0, 0) 0 x 0 | w2: (0, 0) 0 x 139',
      exceptions: [_npe, _aioobe, _npe],
    ),
    j0: (
      geometry:
          'root 500 x 965 | w3: (0, 0) 500 x 9 | w4: (234, 3) 129 x 962 | '
          'w0: (438, 253) 124 x 122 | w1: gone, 0 x 0 | '
          'w5: (0, 972) 488 x 50 | b0: (0, 253) 0 x 0 | '
          'w2: (0, 237) 100 x 139',
      exceptions: [],
    ),
  ),
  (
    id: 'A-vext2:99005987',
    ops:
        'R 253 691;w w0 76 32;bl w0 31;w w1 116 30;w w2 176 41;bl w2 28;'
        'w w3 119 92;bl w3 61;b b0;w w4 48 78;bl w4 47;b b1;add w1;add w0;'
        'add b0;add w4;add w3;add w2;add b1;hb w0 F;vb w0 W;hx w0 0.1;'
        'vx w0 0.67;c w0 CX root CX 0;hb w1 P;vb w1 W;c w1 L root R 8;'
        'c w1 R w0 L 3;c w1 CY root CY 0;hb w2 M;vb w2 W;hm w2 0 44 0 0.7;'
        'ra w2 0.75 -1;hx w2 0.5;vx w2 0.4;c w2 L root L 0;c w2 R root L 7;'
        'hb w3 W;vb w3 W;v w3 4;c w3 L w1 R 8;c w3 R w2 L -5;c w3 T w1 B 0;'
        'c w3 B root T 12;bt b0 0;bm b0 16;ref b0 w3;ref b0 w2;ref b0 w1;'
        'hb w4 P;vb w4 F;c w4 CX w3 CX 0;c w4 T w0 B 12;bt b1 0;ref b1 w4',
    j257: (
      geometry:
          '!ok-printed | root 253 x 691 | w1: (8, 0) 242 x 0 | '
          'w0: (0, 0) 76 x 0 | b0: (0, 0) 0 x 0 | w4: (0, 0) 0 x 78 | '
          'w3: (0, 0) 0 x 0 | w2: (0, 0) 0 x 0 | b1: (0, 0) 0 x 0',
      exceptions: [_npe],
    ),
    j0: (
      geometry:
          '!ok-printed | root 253 x 691 | w1: (8, 331) 242 x 30 | '
          'w0: (18, 0) 76 x 32 | b0: (0, 0) 0 x 0 | w4: (0, 44) 253 x 78 | '
          'w3: (0, 128) 0 x 92 | w2: (0, 0) 0 x 41 | b1: (0, 0) 0 x 0',
      exceptions: [_npe],
    ),
  ),
];

/// Upstream's NullPointerException in ConstraintAnchor.hasCenteredDependents
/// (ConstraintAnchor.java 68): it reads `getOpposite()` of each dependent in
/// turn until one is connected, and a baseline has none. Barrier.addToSolver
/// asks about the sides of both axes, whatever the barrier's type (the left,
/// then the right only when the left has no centered dependent; the top, then
/// the bottom the same way), so a baseline linked to the bottom of a barrier
/// that Direct did not resolve throws there, inside the solve: the solver
/// loop prints it, and the frames are read back from the abandoned system
/// (here every position as 0, and each FIXED size as set). Each side's
/// dependents hold at most one anchor, so no hash order decides where it
/// throws, and the triple run of tool/parity/java/jbatch3.sh finds neither
/// layout ND.
///
/// Java's values are the pinned oracle's, as for [_repros] (the op lists run
/// through tool/parity/java/jrun.sh, levels 257,0, -Dprobe: one
/// NullPointerException at ConstraintAnchor.hasCenteredDependents per
/// printing measure). The TraceJava and Dart solver traces of both are
/// identical at 257 and at 0, the throw included (class i, `same`, of
/// compare/exc_classify.py).
const List<_Repro> _centeredDependents = [
  (
    // At 257 Direct resolves the barrier (its one reference is placed), so
    // addToSolver takes its resolved branch and never asks; at 0 there is no
    // Direct pass.
    id: 'baseline on a barrier',
    ops:
        'R 400 300;b b0;add b0;bt b0 3;w r 50 20;add r;ref b0 r;'
        'c r T root T 10;w t 60 20;add t;bl t 15;c t S b0 B 0;'
        'c t L root L 0',
    j257: (
      geometry:
          'root 400 x 300 | b0: (0, 30) 0 x 0 | r: (0, 10) 50 x 20 | '
          't: (0, 15) 60 x 20',
      exceptions: [],
    ),
    j0: (
      geometry:
          '!ok-printed | root 400 x 300 | b0: (0, 0) 0 x 0 | '
          'r: (0, 0) 50 x 20 | t: (0, 0) 60 x 20',
      exceptions: [_npe],
    ),
  ),
  (
    // The barrier's reference is in a vertical chain, which Direct leaves to
    // the solver, so the barrier reaches the solver at 257 too.
    id: 'baseline on a barrier over a vertical chain',
    ops:
        'R 400 300;b b0;add b0;bt b0 3;w r 50 20;add r;w r2 50 20;add r2;'
        'ref b0 r;c r T root T 10;c r B r2 T 0;c r2 T r B 0;'
        'c r2 B root B 0;w t 60 20;add t;bl t 15;c t S b0 B 0;'
        'c t L root L 0',
    j257: (
      geometry:
          '!ok-printed | root 400 x 300 | b0: (0, 0) 0 x 0 | '
          'r: (0, 0) 50 x 20 | r2: (0, 0) 50 x 20 | t: (0, 0) 60 x 20',
      exceptions: [_npe],
    ),
    j0: (
      geometry:
          '!ok-printed | root 400 x 300 | b0: (0, 0) 0 x 0 | '
          'r: (0, 0) 50 x 20 | r2: (0, 0) 50 x 20 | t: (0, 0) 60 x 20',
      exceptions: [_npe],
    ),
  ),
];

void main() {
  test(
    'a printed error maps to the Java class SolverTrace.javaExceptionClass '
    'gives the error itself',
    () {
      final errors = <Object>[
        RangeError.index(-1, const <int>[]),
        RangeError.range(-1, 0, 127),
        IndexError.withLength(-1, 128),
      ];
      try {
        _none()!.hashCode;
      } catch (e) {
        errors.add(e);
      }
      expect(errors, hasLength(4));
      for (final error in errors) {
        expect(
          _javaClassOf('EXCEPTION : $error'),
          SolverTrace.javaExceptionClass(error),
          reason: '$error',
        );
      }
    },
  );

  for (final repro in [..._repros, ..._centeredDependents]) {
    group(repro.id, () {
      for (final level in const [257, 0]) {
        final java = level == 257 ? repro.j257 : repro.j0;
        final printed = java.exceptions.isNotEmpty;

        test('level $level: frames and printed status are Java\'s', () {
          final result = replayCore(repro.ops, level: level);
          expect(result.status, printed ? 'ok-printed' : 'ok');
          expect(result.geometry, equals(java.geometry));
        });

        test('level $level: the last measure prints Java\'s exceptions, in '
            'order', () {
          final root = _build(repro.ops);
          final lines = _measure(root, level);
          expect(lines.map(_javaClassOf).toList(), java.exceptions);
          // The local build replays the op list as op_replay does.
          expect(
            printed ? '!ok-printed | ${_geometry(root)}' : _geometry(root),
            equals(java.geometry),
          );
        });
      }
    });
  }
}
