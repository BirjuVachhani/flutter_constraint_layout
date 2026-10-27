// Upstream's Direct pass (androidx.constraintlayout.core.widgets.analyzer
// .Direct, lines 58-862), one test per rule, grouped by the part of the pass
// that applies it, plus the cycle guard, the port's one divergence.
//
// Every value is the pinned Java oracle's (VOpDriver v2, core path with the
// echo measurer unless a test says view path, run with -Ddirect -Dprobe
// -Dtranscript at levels 257 and 0, -XX:hashCode=2). Each probe keeps the
// op list the oracle replayed (FORMATS.md 4), and the oracle's fields:
//
// * J257 and J0: the frames at levels 257 and 0, as replayCore and
//   replayView report them;
// * D257: Direct's state (FORMATS.md 8.4), taken after Direct and the
//   post-Direct measures of pass 0, before the solver: per child, the
//   resolved flags, the final value of each anchor or `_`, the raw size, the
//   baseline, the measure request and the solving-pass flags;
// * T257: the measure requests of the measure (FORMATS.md 8.5), whose source
//   is `M` for measureChildren, `P` for a measure Direct makes with a new
//   Measure, `D` for Direct's last pass (Direct.sMeasure) and `R` for the
//   re-measure passes.
//
// Some probes are repros of android_repro_test.dart. A tag such as (M8: 121)
// or (gap 74) names one by its mechanism, repro id or gap there, with
// Android's value in it.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:constraint_engine/src/analyzer/direct.dart';
import 'package:constraint_engine/src/jfloat.dart' show parseFloat32;
import 'package:test/test.dart';

import 'support/echo_measurer.dart';
import 'support/op_replay.dart';

/// One op list and what the Java oracle reports for it.
class _Probe {
  const _Probe(this.ops, {required this.j257, String? j0, this.d257})
    : j0 = j0 ?? j257;

  /// The op list, as the oracle replayed it.
  final String ops;

  /// Java's frames at level 257 (with Direct).
  final String j257;

  /// Java's frames at level 0 (no Direct): [j257] unless given.
  final String j0;

  /// Java's D257 field, without its `D257 ` prefix, or null when not
  /// checked.
  final String? d257;
}

/// Checks [p]'s frames on the core path at levels 257 and 0, and its Direct
/// state when the probe has one.
void _expectProbe(_Probe p) {
  expect(replayCore(p.ops).geometry, equals(p.j257), reason: 'J257 frames');
  expect(
    replayCore(p.ops, level: 0).geometry,
    equals(p.j0),
    reason: 'J0 frames: no Direct at level 0',
  );
  final d257 = p.d257;
  if (d257 != null) {
    expect(_directState(p.ops), equals(d257), reason: 'D257');
  }
}

// ---------------------------------------------------------------------------
// The probes (op lists and Java values)
// ---------------------------------------------------------------------------

const _onesided = _Probe(
  'R 400 300;w a 50 10;add a;w b 30 10;add b;w c 20 10;add c;w d 20 10;'
  'add d;c a L root L 10;c b L a R 5;c c R root R 7;c d R a L 4;'
  'c a T root T 0;c b T root T 0;c c T root T 0;c d T root T 0',
  j257:
      'root 400 x 300 | a: (10, 0) 50 x 10 | b: (65, 0) 30 x 10 | '
      'c: (373, 0) 20 x 10 | d: (-13, 0) 20 x 10',
  d257:
      'a:hv:10,0,60,10,_:50x10:0-:-HV b:hv:65,0,95,10,_:30x10:0-:-HV '
      'c:hv:373,0,393,10,_:20x10:0-:-HV d:hv:-14,0,6,10,_:20x10:0-:-HV',
);

const _otherLinked = _Probe(
  'R 400 300;w u 0 10;add u;hb u P;w a 50 10;add a;c a L root L 10;'
  'c a R u L 0;c a T root T 0;c u T root T 0',
  j257: 'root 400 x 300 | u: (0, 0) 400 x 10 | a: (-19, 0) 50 x 10',
  d257: 'u:-v:_,0,_,10,_:0x10:0-:--V a:-v:_,0,_,10,_:50x10:0-:--V',
);

const _glSecond = _Probe(
  'R 400 300;g gl;go gl 1;gb gl 50;add gl;w x 30 0;add x;hb x W;vb x M;'
  'c x L gl L 10;c x T root T 0;c x B root B 0',
  j257: 'root 400 x 300 | gl: (50, 0) 0 x 300 | x: (60, 0) 30 x 300',
  d257: 'gl:g1:50 x:hv:60,0,90,300,_:30x300:0-:-HV',
);

const _glControl = _Probe(
  'R 400 300;w x 30 0;add x;hb x W;vb x M;c x L root L 60;c x T root T 0;'
  'c x B root B 0',
  j257: 'root 400 x 300 | x: (60, 0) 30 x 300',
  d257: 'x:-v:_,0,_,300,_:30x300:0-:--V',
);

const _glSecondGone = _Probe(
  'R 400 300;g gl;go gl 1;gb gl 50;add gl;v gl 8;w x 30 0;add x;hb x W;'
  'vb x M;c x L gl L 10;c x T root T 0;c x B root B 0',
  j257: 'root 400 x 300 | gl: gone, 0 x 0 | x: (60, 0) 30 x 300',
  d257: 'gl:g1:50 x:-v:_,0,_,300,_:30x300:0-:--V',
);

const _vCrossed = _Probe(
  'R 400 300;w t0 20 90;add t0;c t0 T root T 200;c t0 B root B 200;'
  'c t0 L root L 0',
  j257: 'root 400 x 300 | t0: (0, 0) 20 x 0',
  j0: 'root 400 x 300 | t0: (0, 105) 20 x 90',
  d257: 't0:hv:0,195,20,105,_:20x-90:0-:-HV',
);

const _baseline121 = _Probe(
  'R 314 844;w card 130 370;add card;w icon 10 50;add icon;'
  'w caption 200 10;add caption;w title 30 20;add title;w value 0 40;'
  'add value;w btn0 60 30;add btn0;hbl value 1;hbl title 1;'
  'c card T root T 0;c icon T card T 0;c caption T icon B 0;'
  'c title T caption B 0;hb value M;v value 8;c value S title S 0;'
  'c btn0 T value B 0;bl title 21',
  j257:
      'root 314 x 844 | card: (0, 0) 130 x 370 | icon: (0, 0) 10 x 50 | '
      'caption: (0, 50) 200 x 10 | title: (0, 60) 30 x 20 | '
      'value: gone, 0 x 0 | btn0: (0, 121) 60 x 30',
  j0:
      'root 314 x 844 | card: (0, 0) 130 x 370 | icon: (0, 0) 10 x 50 | '
      'caption: (0, 50) 200 x 10 | title: (0, 60) 30 x 20 | '
      'value: gone, 0 x 0 | btn0: (0, 81) 60 x 30',
  d257:
      'card:-v:_,0,_,370,_:130x370:0-:--V icon:-v:_,0,_,50,_:10x50:0-:--V '
      'caption:-v:_,50,_,60,_:200x10:0-:--V '
      'title:-v:_,60,_,80,81:30x20:21+:--V '
      'value:-v:_,81,_,121,81:0x40:0+:--V '
      'btn0:-v:_,121,_,151,_:60x30:0-:--V',
);

const _bias07 = _Probe(
  'R 100 50;w a 55 10;add a;hx a 0.7;c a L root L 0;c a R root R 0;'
  'c a T root T 0',
  j257: 'root 100 x 50 | a: (32, 0) 55 x 10',
  d257: 'a:hv:32,0,87,10,_:55x10:0-:-HV',
);

const _noFit = _Probe(
  'R 100 50;w a 111 10;add a;c a L root L 0;c a R root R 0;c a T root T 0',
  j257: 'root 100 x 50 | a: (-4, 0) 111 x 10',
  j0: 'root 100 x 50 | a: (-5, 0) 111 x 10',
  d257: 'a:hv:-5,0,106,10,_:111x10:0-:-HV',
);

const _coincident = _Probe(
  'R 398 976;w w0 30 60;add w0;w t0 90 40;add t0;c w0 R root R 0;'
  'c t0 L w0 R 0;c t0 R root R 16',
  j257: 'root 398 x 976 | w0: (368, 0) 30 x 60 | t0: (353, 0) 90 x 40',
  j0: 'root 398 x 976 | w0: (368, 0) 30 x 60 | t0: (345, 0) 90 x 40',
  d257: 'w0:h-:368,_,398,_,_:30x60:0-:-H- t0:h-:353,_,443,_,_:90x40:0-:-H-',
);

const _crossed = _Probe(
  'R 400 300;w t0 90 20;add t0;c t0 L root L 300;c t0 R root R 300;'
  'c t0 T root T 0',
  j257: 'root 400 x 300 | t0: (0, 0) 0 x 20',
  j0: 'root 400 x 300 | t0: (155, 0) 90 x 20',
  d257: 't0:hv:355,0,265,20,_:-90x20:0-:-HV',
);

const _spread = _Probe(
  'R 400 300;w a 0 10;add a;hb a M;c a L root L 10;c a R root R 20;'
  'c a T root T 0',
  j257: 'root 400 x 300 | a: (10, 0) 370 x 10',
  d257: 'a:hv:10,0,380,10,_:370x10:0-:-HV',
);

const _spreadMax = _Probe(
  'R 400 300;w a 0 10;add a;hb a M;hm a 0 0 100 1.0;hx a 0.3;'
  'c a L root L 10;c a R root R 20;c a T root T 0',
  j257: 'root 400 x 300 | a: (91, 0) 100 x 10',
  d257: 'a:hv:91,0,191,10,_:100x10:0-:-HV',
);

const _spreadMin = _Probe(
  'R 100 50;w a 0 10;add a;hb a M;hm a 0 110 0 1.0;c a L root L 0;'
  'c a R root R 0;c a T root T 0',
  j257: 'root 100 x 50 | a: (-4, 0) 109 x 10',
  d257: 'a:hv:-4,0,106,10,_:110x10:0-:-HV',
);

const _spreadCrossed = _Probe(
  'R 100 50;w a 0 10;add a;hb a M;c a L root L 60;c a R root R 60;'
  'c a T root T 0',
  j257: 'root 100 x 50 | a: (0, 0) 0 x 10',
  d257: 'a:--:_,_,_,_,_:0x10:0-:---',
);

const _gap74 = _Probe(
  'R 316 447;w nav 40 40;add nav;w title 89 20;add title;w sub 210 10;'
  'add sub;c nav L root L 0;hb title M;hm title 1 0 0 1.0;'
  'c title L nav R 0;c title R root R 0;c sub L title L 0;'
  'c sub R title R 0',
  j257:
      'root 316 x 447 | nav: (0, 0) 40 x 40 | title: (134, 0) 89 x 20 | '
      'sub: (74, 0) 210 x 10',
  j0:
      'root 316 x 447 | nav: (0, 0) 40 x 40 | title: (134, 0) 89 x 20 | '
      'sub: (73, 0) 210 x 10',
  d257:
      'nav:h-:0,_,40,_,_:40x40:0-:-H- title:h-:134,_,223,_,_:89x20:0-:-H- '
      'sub:h-:74,_,284,_,_:210x10:0-:-H-',
);

const _ratioLastPass = _Probe(
  'R 512 699;w image 190 46;add image;hb image M;ra image 1.7777778 -1',
  j257: 'root 512 x 699 | image: (0, 0) 81 x 46',
  d257: 'image:--:_,_,_,_,_:81x46:0-:-HV',
);

const _gap266 = _Probe(
  'R 243 1234;w card 500 250;add card;w image 60 150;add image;'
  'c card L root L 0;hb image M;ra image 1.7777778 -1;c image L card L 0',
  j257: 'root 243 x 1234 | card: (0, 0) 500 x 250 | image: (0, 0) 266 x 150',
  d257:
      'card:h-:0,_,500,_,_:500x250:0-:-H- '
      'image:h-:0,_,266,_,_:266x150:0-:-H-',
);

const _order = _Probe(
  'R 400 300;w a 30 10;add a;w b 30 10;add b;w c 30 10;add c;hb a M;'
  'hb b M;hb c M;c c L root L 0;c a L root L 0;c b L root L 0;'
  'c a T root T 0;c b T root T 0;c c T root T 0',
  j257:
      'root 400 x 300 | a: (0, 0) 30 x 10 | b: (0, 0) 30 x 10 | '
      'c: (0, 0) 30 x 10',
  d257:
      'a:hv:0,0,30,10,_:30x10:0-:-HV b:hv:0,0,30,10,_:30x10:0-:-HV '
      'c:hv:0,0,30,10,_:30x10:0-:-HV',
);

const _barrier427 = _Probe(
  'R 411 397;b tr0;add tr0;w ch0 20 10;add ch0;bm tr0 16;ref tr0 ch0;'
  'v ch0 8;c ch0 R root R 0',
  j257: 'root 411 x 397 | tr0: (427, 0) 0 x 0 | ch0: gone, 0 x 0',
  j0: 'root 411 x 397 | tr0: (411, 0) 0 x 0 | ch0: gone, 0 x 0',
  d257: 'tr0:b0:hv:427,_,427,_ ch0:h-:411,_,411,_,_:0x0:0-:-H-',
);

const _barrierRecheck = _Probe(
  'R 300 200;b b1;add b1;w w0 40 20;add w0;b b2;add b2;w k 10 10;add k;'
  'bt b1 1;bt b2 1;ref b2 w0;ref b1 b2;c w0 L root L 30;c w0 T root T 0;'
  'c k L b1 R 5;c k T root T 0',
  j257:
      'root 300 x 200 | b1: (70, 0) 0 x 0 | w0: (30, 0) 40 x 20 | '
      'b2: (70, 0) 0 x 0 | k: (75, 0) 10 x 10',
  d257:
      'b1:b1:--:_,_,_,_ w0:hv:30,0,70,20,_:40x20:0-:-HV b2:b1:hv:70,_,70,_ '
      'k:-v:_,0,_,10,_:10x10:0-:--V',
);

const _gapA = _Probe(
  'R 894 827;w w1 60 70;b b0;add b0;b b1;add b1;w w4 20 36;add w4;b b2;'
  'add b2;b top;add top;w t0 33 49;v w1 8;bg b0 0;ref b0 w1;bt b1 1;'
  'ref b1 b0;bt b2 1;ref b2 w4;ref top b1;ref top b2;c t0 L top R 10;'
  'c t0 R root R 5',
  j257:
      'root 894 x 827 | b0: (0, 0) 0 x 0 | b1: (0, 0) 0 x 0 | '
      'w4: (0, 0) 20 x 36 | b2: (20, 0) 0 x 0 | top: (0, 0) 0 x 0',
  j0:
      'root 894 x 827 | b0: (0, 0) 0 x 0 | b1: (20, 0) 0 x 0 | '
      'w4: (0, 0) 20 x 36 | b2: (20, 0) 0 x 0 | top: (20, 0) 0 x 0',
  d257:
      'b0:b0:hv:0,_,0,_ b1:b1:hv:0,_,0,_ w4:--:_,_,_,_,_:20x36:0-:--- '
      'b2:b1:--:_,_,_,_ top:b0:--:_,_,_,_',
);

const _goneCollapse = _Probe(
  'R 671 771;w w0 20 80;add w0;w t0 100 50;add t0;v w0 8;'
  'c w0 R root R 0;c t0 L w0 R 5;c t0 R root R 0',
  j257: 'root 671 x 771 | w0: gone, 0 x 0 | t0: (621, 0) 100 x 50',
  j0: 'root 671 x 771 | w0: gone, 0 x 0 | t0: (624, 0) 100 x 50',
  d257: 'w0:h-:671,_,671,_,_:0x0:0-:-H- t0:h-:621,_,721,_,_:100x50:0-:-H-',
);

const _goneCenter = _Probe(
  'R 400 300;w g 50 10;add g;v g 8;hx g 0.25;c g L root L 100;'
  'c g R root R 0;c g T root T 0;w k 20 10;add k;c k L g R 30;gm k L 12;'
  'c k T root T 0',
  j257: 'root 400 x 300 | g: gone, 0 x 0 | k: (112, 0) 20 x 10',
  d257: 'g:hv:100,0,100,0,_:0x0:0-:-HV k:hv:112,0,132,10,_:20x10:0-:-HV',
);

const _goneSpread = _Probe(
  'R 400 300;w g 0 10;add g;hb g M;hm g 2 0 0 0.5;v g 8;c g L root L 10;'
  'c g R root R 20;c g T root T 0;w k 20 10;add k;c k L g L 5;'
  'c k T root T 0',
  j257: 'root 400 x 300 | g: gone, 0 x 0 | k: (205, 0) 20 x 10',
  d257: 'g:hv:200,0,200,0,_:0x0:0-:-HV k:hv:205,0,225,10,_:20x10:0-:-HV',
);

// Java T257 of [_order]: c, a and b were connected to the container's left
// in that order.
const _orderT257 =
    'P:c:0:WF:30,10:e:30,10,0,00 P:a:0:WF:30,10:e:30,10,0,00 '
    'P:b:0:WF:30,10:e:30,10,0,00 R:a:1:MF:30,10:e:30,10,0,00 '
    'R:b:1:MF:30,10:e:30,10,0,00 R:c:1:MF:30,10:e:30,10,0,00';

// A-ext:99001562 of corpus A (FORMATS.md 3): a cycle of stale dependents.
const _staleCycleOps =
    'R 604 660;g g0;go g0 1;ge g0 186;add g0;g g1;go g1 0;gp g1 0.5;add g1;'
    'w w0 156 64;w w1 88 68;w w2 18 76;b b0;bt b0 0;bm b0 6;bg b0 1;add b0;'
    'add w0;add w1;add w2;c w1 T g1 T 34;c w1 B w2 T 0;c w2 T w1 B 0;'
    'c w2 B root B 0;vc w1 2;hb w0 M;c w0 T root T 0;vb w0 W;'
    'c w1 L b0 R 40;gm w1 T 0;c w2 L w1 L 18;gm w2 L 14;vx w2 1.0;'
    'c w2 T g1 B 40;v w2 8';

// Java J0 of A-ext:99001562 (J257 is `!SO`).
const _staleCycleJ0 =
    'root 604 x 660 | g0: (418, 0) 0 x 660 | g1: (0, 330) 604 x 0 | '
    'b0: (604, 0) 0 x 0 | w0: (0, 0) 156 x 64 | w1: (644, 478) 88 x 68 | '
    'w2: gone, 0 x 0';

// Each widget's baseline is linked to the other's, one link stale: every
// round moves both baselines by 3.
const _baselineCycleOps =
    'R 400 300;w A 50 20;add A;w B 50 20;add B;w C 50 20;add C;hbl A 1;'
    'hbl B 1;hbl C 1;bl A 10;bl B 10;bl C 10;c A L root L 0;'
    'c B L root L 100;c C L root L 200;c C T root T 0;c A S B S 3;'
    'c A S C S 0;c A T root T 0;c B S A S 3';

// Java J0 of the baseline cycle (J257 is `!SO | ... A: (0, 144276) ...`).
const _baselineCycleJ0 =
    'root 400 x 300 | A: (0, 0) 50 x 20 | B: (100, 3) 50 x 20 | '
    'C: (200, 0) 50 x 20';

void main() {
  group('horizontal solving pass', () {
    test('a one-sided link places the widget next to its target, and the '
        'walk goes on from it', () {
      // a: x1 = 0 + 10 from the container's left; b: x1 = a's right + 5,
      // reached from a's own pass; c: x2 = 400 - 7 from the container's
      // right; d's right on a's left: x2 = 10 - 4, x1 = x2 - 20 = -14, read
      // back as (int) (-14 + 0.5f) = -13 with the fixed width kept.
      _expectProbe(_onesided);
    });

    test('the one-sided rules need the other side unlinked, not merely '
        'unresolved', () {
      // a's right targets u, which Direct never resolves (a match-parent
      // axis): a waits for both targets and goes to the solver.
      _expectProbe(_otherLinked);
    });

    test('a widget that cannot be measured yet is skipped; only a '
        "guideline's pass runs again in the last pass", () {
      // x's height is a two-link spread, so its first horizontal visit
      // bails out. The vertical phase measures it. Linked to a guideline,
      // whose pass is never marked done, x is placed by the guideline's
      // second run; linked to the container, it is left to the solver.
      _expectProbe(_glSecond);
      _expectProbe(_glControl);
    });
  });

  group('vertical solving pass', () {
    test('crossed vertical margins subtract the offset, unlike the '
        'horizontal twin', () {
      // s1 = 200 > s2 = 100: distance = 200 - 100 - 90 = 10, d1 = 5,
      // y1 = s1 - d1 = 195 and y2 = y1 - 90: a negative height, which zeroes
      // the frame on read-back.
      _expectProbe(_vCrossed);
    });

    test("a baseline link resolves the widget from its target's baseline "
        'and its stored height (M8: 121)', () {
      // The gone value has a baseline of 0 at 81: setFinalBaseline gives it
      // top 81 and bottom 81 + 40, its stored height, not getHeight() (0
      // when gone); btn0 below it lands at 121, where the solver alone puts
      // it at 81.
      _expectProbe(_baseline121);
    });
  });

  group('centering', () {
    test('the offset is (int) (0.5f + bias * distance) in float: 0.7 over '
        '45 gives 32', () {
      // 0.7f * 45 is 31.5f exactly (0.7f rounds up), so 32; a double
      // product gives 31.
      _expectProbe(_bias07);
    });

    test('a widget that does not fit truncates (int) (bias * distance): '
        '-11 gives -5', () {
      // Direct places a at -5; the solver reads the pinned -5 back as -4.
      _expectProbe(_noFit);
    });

    test('targets at the same position center the widget on it, without '
        'margins (M3: 353)', () {
      // start == end == 398: bias 0.5 and the margin of 16 dropped, so
      // d1 = (int) (0.5f * -90) = -45.
      _expectProbe(_coincident);
    });

    test('crossed margins give a negative width, which zeroes the frame '
        '(M3: 0 x 20)', () {
      // s1 = 300 > s2 = 100: x1 = s1 + d1 = 355 and x2 = x1 - 90.
      _expectProbe(_crossed);
    });
  });

  group('spread match constraints', () {
    test('a spread axis stretches between its targets, within its max and '
        'at its bias', () {
      _expectProbe(_spread);
      // width min(100, 370), distance 270: (int) (0.5f + 0.3f * 270) = 81.
      _expectProbe(_spreadMax);
    });

    test('a min wider than the space offsets by (int) (0.5f + bias * '
        'distance), truncated: -4', () {
      // distance 100 - 110 = -10: (int) (0.5f + 0.5f * -10) = -4, not -5.
      _expectProbe(_spreadMin);
    });

    test('crossed margins leave a spread axis to the solver', () {
      _expectProbe(_spreadCrossed);
    });
  });

  group('canMeasure', () {
    test('a wrap-default match constraint is measured once both targets '
        'are final and leave room for it (gap 74)', () {
      // title (89 wide) fits between nav's right (40) and the container's
      // right (316), so Direct centers it and then centers sub, 210 wide,
      // on it: (int) (0.5f * -121) = -60 puts sub at 74, the solver at 73.
      _expectProbe(_gap74);
    });

    test('a ratio widget with one fixed axis can be measured', () {
      // image's width is a ratio of its fixed height, 46: the last pass
      // measures it at (int) (1.7777778f * 46) = 81.
      _expectProbe(_ratioLastPass);
    });
  });

  group('barriers', () {
    test('a barrier resolves once every reference is, gone references '
        'included (M7: 427)', () {
      // The gone ch0 collapses onto the container's right, 411, and the
      // barrier adds its margin of 16.
      _expectProbe(_barrier427);
    });

    test('a barrier that references a later barrier is resolved by the '
        "re-check in its addToSolver, not by Direct", () {
      _expectProbe(_barrierRecheck);
    });

    test('barriers over barriers resolve in widget order', () {
      // The barrier layout that pass_structure_test.dart and
      // fresh_state_test.dart check at level 0, here at 257 as well. t0 is
      // linked but never added to the container: Direct still measures it
      // from the container's right (`P:t0`).
      _expectProbe(_gapA);
      expect(
        _transcript(_gapA.ops),
        equals(
          'M:w4:0:FF:20,36:e:20,36,0,00 P:t0:0:FF:33,49:e:33,49,0,00',
        ),
      );
    });
  });

  group('last pass', () {
    test('a gone guideline gets no last pass, so its second run is lost', () {
      // The core path with the guideline gone, as the view path makes every
      // guideline: x stays unresolved horizontally (D257 x:-v).
      _expectProbe(_glSecondGone);
      // The view path (Java view path, `direct:glsecondview`).
      const ops =
          'R 400 300;g gl;go gl 1;gb gl 50;add gl;w x 0 0;add x;hb x W;'
          'vb x M;c x L gl L 10;c x T root T 0;c x B root B 0;'
          'ct x text 30 20 -1;cspec E 400 E 300';
      const frames = 'root 400 x 300 | gl: (50, 0) 0 x 0 | x: (60, 0) 30 x 300';
      expect(replayView(ops).geometry, equals(frames));
      expect(replayView(ops, level: 0).geometry, equals(frames));
    });
  });

  group('measure requests', () {
    test('a solving pass measures with a new Measure, the last pass with '
        'Direct.sMeasure', () {
      expect(
        _transcript(_gap266.ops),
        equals(
          'M:card:0:FF:500,250:e:500,250,0,00 '
          'P:image:0:FF:266,150:e:266,150,0,00 '
          'R:image:1:FF:266,150:e:266,150,0,00',
        ),
      );
      _expectProbe(_gap266);
      expect(
        _transcript(_ratioLastPass.ops),
        equals(
          'D:image:0:FF:81,46:e:81,46,0,00 R:image:1:FF:81,46:e:81,46,0,00',
        ),
      );
      expect(
        _transcript(_glControl.ops),
        equals(
          'P:x:0:WF:30,300:e:30,300,0,00 R:x:1:WM:30,300:e:30,300,0,00',
        ),
      );
      expect(
        _transcript(_spreadMin.ops),
        equals(
          'P:a:0:FF:110,10:e:110,10,0,00 R:a:1:MF:109,10:e:110,10,0,00 '
          'R:a:2:MF:109,10:e:110,10,0,00',
        ),
        reason: 'three passes: the re-measure finds the readback 1 short',
      );
    });

    test('dependents are visited in the order they were connected', () {
      // c, a and b were connected to the container's left in that order.
      expect(_transcript(_order.ops), equals(_orderT257));
      _expectProbe(_order);
    });
  });

  group('gone widgets', () {
    test('a gone widget collapses onto its target', () {
      // w0 is a point at the container's right (671); t0, between w0's
      // right and the container's right, centers on 671 (M3c: 621).
      _expectProbe(_goneCollapse);
    });

    test('a gone widget between two targets is a point at its bias, and a '
        'widget linked to it takes its gone margin', () {
      // g's margins count 0: (int) (0.5f + 0.25f * 400) = 100. k is at
      // 100 + 12, the gone margin of its link, not 30.
      _expectProbe(_goneCenter);
    });

    test('a gone match-constraint axis spreads whatever its default', () {
      // g's percent default would not resolve if it were visible.
      _expectProbe(_goneSpread);
    });
  });

  group('exceptions', () {
    test('a stale dependent whose own target was reset throws, as Java '
        'throws a NullPointerException', () {
      // b's left was moved from a's left to the container's, then reset:
      // a's left still lists it, and centering b reads its null target.
      const ops =
          'R 400 300;w a 50 10;add a;w b 20 10;add b;c a L root L 0;'
          'c a T root T 0;c b L a L 0;c b R root R 0;c b L root L 0;x b L;'
          'c b T root T 0';
      // Java J257: `!EXC:java.lang.NullPointerException: ... because
      // "<parameter3>.mLeft.mTarget" is null | root 400 x 300 | a: (0, 0)
      // 50 x 10 | b: (0, 0) 20 x 10`.
      final r = replayCore(ops);
      expect(r.status, startsWith('EXC:'));
      expect(
        r.geometry,
        endsWith(' | root 400 x 300 | a: (0, 0) 50 x 10 | b: (0, 0) 20 x 10'),
      );
      final root = _build(ops)
        ..setMeasurer(const EchoMeasurer())
        ..setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
      expect(
        () => root.measure(
          Optimizer.OPTIMIZATION_STANDARD,
          BasicMeasure.EXACTLY,
          400,
          BasicMeasure.EXACTLY,
          300,
          0,
          0,
          0,
          0,
        ),
        throwsA(isA<TypeError>()),
      );
      expect(
        replayCore(ops, level: 0).geometry,
        equals('root 400 x 300 | a: (0, 0) 50 x 10 | b: (380, 0) 20 x 10'),
      );
    });
  });

  group('cycle guard (the port only)', () {
    test('a re-entry with no change trips the guard, where Android '
        'overflows its stack (A-ext:99001562)', () {
      // w2's top was moved from w1's bottom to g1, which leaves it among
      // w1's bottom's dependents. The vertical passes run g1, w2, w1, w2
      // (re-entered after w1 resolved: it proceeds), then w1 again with no
      // change: Java's StackOverflowError, here the guard.
      final trips = Direct.guardTrips;
      final state = _directState(_staleCycleOps);
      expect(Direct.guardTrips, equals(trips + 1));
      // Direct is abandoned: no axis, guideline or barrier is left
      // resolved, and no anchor keeps a final value. The sizes are the
      // measures' (w0, which Direct never reached, by the post-Direct
      // measures) and those Direct's setFinal calls wrote.
      expect(
        state,
        equals(
          'g0:g1:_ g1:g0:_ b0:b0:--:_,_,_,_ '
          'w0:--:_,_,_,_,_:156x64:0-:--- w1:--:_,_,_,_,_:88x68:0-:--- '
          'w2:--:_,_,_,_,_:0x0:0-:---',
        ),
      );
      // The layout completes: the solver lays every widget out, as at
      // level 0 (Java J257: `!SO`).
      final r = replayCore(_staleCycleOps);
      expect(Direct.guardTrips, equals(trips + 2));
      expect(r.status, equals('ok'));
      expect(r.geometry, equals(_staleCycleJ0));
      expect(replayCore(_staleCycleOps, level: 0).geometry, _staleCycleJ0);
      expect(Direct.guardTrips, equals(trips + 2), reason: 'no Direct at 0');
    });

    test('a cycle that keeps changing the state trips the depth bound', () {
      // A's baseline gives B's (+3), whose stale dependent gives A's back:
      // each round moves both, so no re-entry repeats a state, and Java
      // recurses until its stack overflows (A at y 144276). The guard stops
      // at 4 * (3 + 1) + 64 nested passes.
      final trips = Direct.guardTrips;
      final r = replayCore(_baselineCycleOps);
      expect(Direct.guardTrips, equals(trips + 1));
      expect(r.status, equals('ok'));
      expect(r.geometry, equals(_baselineCycleJ0));
      expect(
        replayCore(_baselineCycleOps, level: 0).geometry,
        equals(_baselineCycleJ0),
      );
    });

    test('layouts without a cycle never trip it', () {
      final trips = Direct.guardTrips;
      for (final p in [
        _onesided,
        _glSecond,
        _baseline121,
        _gap74,
        _barrierRecheck,
        _gapA,
        _goneCenter,
      ]) {
        replayCore(p.ops);
      }
      expect(Direct.guardTrips, equals(trips));
    });
  });

  group('re-entrancy', () {
    test('a measurer may lay out another container inside a solving '
        'pass', () {
      // While Direct measures a (a `P` request), the measurer lays out the
      // 0.7 bias probe in a container of its own, whose Direct runs inside
      // this one. Neither disturbs the other.
      String? nested;
      final measurer = _Recording(
        onMeasure: (widget, source) {
          if (widget.getDebugName() == 'a' && source == 'P') {
            nested = replayCore(_bias07.ops).geometry;
          }
        },
      );
      final trips = Direct.guardTrips;
      final root = _measure(_order.ops, measurer);
      expect(nested, equals(_bias07.j257));
      expect(measurer.entries.join(' '), equals(_orderT257));
      expect(_geometry(root), equals(_order.j257));
      expect(Direct.guardTrips, equals(trips));
    });
  });
}

// ---------------------------------------------------------------------------
// Direct's state (D257) and the measure requests (T257)
// ---------------------------------------------------------------------------

/// Direct's state for [ops] at the oracle's dump point: after
/// Direct.solvingPass and the post-Direct measures of pass 0, before the
/// solver, in the format of FORMATS.md 8.4.
///
/// It starts the measure as OpDriver's core path does (level 257, the echo
/// measurer or [measurer]): measureChildren, then pass 0, whose layout() runs
/// Direct and the post-Direct measures before anything else.
String _directState(String ops, {Measurer measurer = const EchoMeasurer()}) {
  final root = _build(ops)
    ..setMeasurer(measurer)
    ..setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD);
  root.mBasicMeasureSolver.measureChildren(root);
  root.updateHierarchy();
  root.setPass(0);
  Direct.solvingPass(root, root.getMeasurer());
  _postDirectMeasures(root);
  return _dump(root);
}

/// The measures layout() makes after Direct in pass 0 (upstream CWC
/// 737-755): every child still waiting for a measure, other than helpers
/// and match constraint on both axes, is measured with a new Measure.
void _postDirectMeasures(ConstraintWidgetContainer root) {
  for (final child in root.mChildren) {
    if (child.isMeasureRequested() &&
        child is! Guideline &&
        child is! Barrier &&
        child is! VirtualLayout &&
        !child.isInVirtualLayout()) {
      final skip =
          child.getHorizontalDimensionBehaviour() ==
              DimensionBehaviour.matchConstraint &&
          child.mMatchConstraintDefaultWidth !=
              ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
          child.getVerticalDimensionBehaviour() ==
              DimensionBehaviour.matchConstraint &&
          child.mMatchConstraintDefaultHeight !=
              ConstraintWidget.MATCH_CONSTRAINT_WRAP;
      if (!skip) {
        ConstraintWidgetContainer.measureWidget(
          0,
          child,
          root.getMeasurer(),
          Measure(),
          Measure.SELF_DIMENSIONS,
        );
      }
    }
  }
}

String _fv(ConstraintAnchor a) =>
    a.hasFinalValue() ? '${a.getFinalValue()}' : '_';

/// The oracle's D field (DirectProbe.dumpDirect, FORMATS.md 8.4).
String _dump(ConstraintWidgetContainer root) => [
  for (final w in root.getChildren())
    switch (w) {
      final Guideline g =>
        '${g.getDebugName()}:g${g.getOrientation()}:'
            '${_fv(g.getGuidelineAnchor())}',
      final Barrier b =>
        '${b.getDebugName()}:b${b.getBarrierType()}:'
            '${b.isResolvedHorizontally() ? 'h' : '-'}'
            '${b.isResolvedVertically() ? 'v' : '-'}:'
            '${_fv(b.mLeft)},${_fv(b.mTop)},${_fv(b.mRight)},${_fv(b.mBottom)}',
      _ =>
        '${w.getDebugName()}:'
            '${w.isResolvedHorizontally() ? 'h' : '-'}'
            '${w.isResolvedVertically() ? 'v' : '-'}:'
            '${_fv(w.mLeft)},${_fv(w.mTop)},${_fv(w.mRight)},${_fv(w.mBottom)},'
            '${_fv(w.mBaseline)}:${w.mWidth}x${w.mHeight}:'
            '${w.getBaselineDistance()}${w.hasBaseline() ? '+' : '-'}:'
            '${w.isMeasureRequested() ? 'm' : '-'}'
            '${w.isHorizontalSolvingPassDone() ? 'H' : '-'}'
            '${w.isVerticalSolvingPassDone() ? 'V' : '-'}',
    },
].join(' ');

/// One core-path measure of [ops] at level 257 with [measurer], as
/// OpDriver measures (the container is fixed in every probe here).
ConstraintWidgetContainer _measure(String ops, _Recording measurer) {
  final root = _build(ops);
  measurer.container = root;
  root
    ..setMeasurer(measurer)
    ..setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD)
    ..measure(
      Optimizer.OPTIMIZATION_STANDARD,
      BasicMeasure.EXACTLY,
      root.getWidth(),
      BasicMeasure.EXACTLY,
      root.getHeight(),
      0,
      0,
      0,
      0,
    );
  return root;
}

/// The measure requests of one core-path measure of [ops] at level 257, in
/// the format of the oracle's T field (FORMATS.md 8.5).
String _transcript(String ops) {
  final measurer = _Recording();
  _measure(ops, measurer);
  return measurer.entries.join(' ');
}

/// OpDriver's core geometry of [root] (FORMATS.md 2).
String _geometry(ConstraintWidgetContainer root) => [
  'root ${root.getWidth()} x ${root.getHeight()}',
  for (final w in root.getChildren())
    w.getVisibility() == ConstraintWidget.GONE && w is! Barrier
        ? '${w.getDebugName()}: gone, ${w.getWidth()} x ${w.getHeight()}'
        : '${w.getDebugName()}: (${w.getX()}, ${w.getY()}) '
              '${w.getWidth()} x ${w.getHeight()}',
].join(' | ');

String _behaviour(DimensionBehaviour? b) => switch (b) {
  DimensionBehaviour.fixed => 'F',
  DimensionBehaviour.wrapContent => 'W',
  DimensionBehaviour.matchConstraint => 'M',
  DimensionBehaviour.matchParent => 'P',
  null => '?',
};

/// The echo measurer, recording each request as DirectProbe does: its
/// source told by the identity of its Measure, the request, and the answer.
class _Recording implements Measurer {
  _Recording({this.onMeasure});

  /// Called before each request is answered, with its source.
  final void Function(ConstraintWidget widget, String source)? onMeasure;

  final List<String> entries = [];

  /// The container measured, which tells the requests of its passes.
  ConstraintWidgetContainer? container;

  static const _echo = EchoMeasurer();

  @override
  void measure(ConstraintWidget widget, Measure m) {
    final source = _sourceOf(widget, m);
    onMeasure?.call(widget, source);
    final request =
        '$source:${widget.getDebugName()}:${m.measureStrategy}:'
        '${_behaviour(m.horizontalBehavior)}${_behaviour(m.verticalBehavior)}:'
        '${m.horizontalDimension},${m.verticalDimension}';
    _echo.measure(widget, m);
    entries.add(
      '$request:e:${m.measuredWidth},${m.measuredHeight},'
      '${m.measuredBaseline},${m.measuredHasBaseline ? 1 : 0}'
      '${m.measuredNeedsSolverPass ? 1 : 0}',
    );
  }

  String _sourceOf(ConstraintWidget widget, Measure m) {
    if (identical(m, Direct.sMeasure)) {
      return 'D';
    }
    final container = this.container;
    if (container == null) {
      return 'X';
    }
    if (identical(m, container.mBasicMeasureSolver.mMeasure)) {
      return m.measureStrategy == Measure.SELF_DIMENSIONS ? 'M' : 'R';
    }
    // Inside pass 0 before its solver loop: Direct or the post-Direct
    // measures.
    if (container.mPass == 0 && container.mCountSolve == 0) {
      return 'P';
    }
    return 'X';
  }

  @override
  void didMeasures() {}
}

// ---------------------------------------------------------------------------
// The op lists (the subset of FORMATS.md 4 these probes use)
// ---------------------------------------------------------------------------

/// Builds the layout [ops] describes, as the oracle's op interpreter does:
/// the container is `root`, of the leading `R` op's size.
ConstraintWidgetContainer _build(String ops) {
  final list = ops.split(';');
  final head = list.first.split(' ');
  final root = ConstraintWidgetContainer.rect(
    0,
    0,
    int.parse(head[1]),
    int.parse(head[2]),
  )..setDebugName('root');
  final by = <String, ConstraintWidget>{'root': root};
  ConstraintWidget n(String name) => by[name]!;
  for (final op in list.skip(1)) {
    final t = op.split(' ');
    switch (t[0]) {
      case 'w':
        by[t[1]] = ConstraintWidget.sizeNamed(
          t[1],
          int.parse(t[2]),
          int.parse(t[3]),
        );
      case 'g':
        by[t[1]] = Guideline()..setDebugName(t[1]);
      case 'b':
        by[t[1]] = Barrier.named(t[1]);
      case 'add':
        root.add(n(t[1]));
      case 'go':
        (n(t[1]) as Guideline).setOrientation(int.parse(t[2]));
      case 'gb':
        (n(t[1]) as Guideline).setGuideBegin(int.parse(t[2]));
      case 'ge':
        (n(t[1]) as Guideline).setGuideEnd(int.parse(t[2]));
      case 'gp':
        (n(t[1]) as Guideline).setGuidePercent(parseFloat32(t[2]));
      case 'bt':
        (n(t[1]) as Barrier).setBarrierType(int.parse(t[2]));
      case 'bm':
        (n(t[1]) as Barrier).setMargin(int.parse(t[2]));
      case 'bg':
        (n(t[1]) as Barrier).setAllowsGoneWidget(t[2] == '1');
      case 'ref':
        (n(t[1]) as HelperWidget).add(n(t[2]));
      case 'c':
        n(
          t[1],
        ).connect(_anchor(t[2]), n(t[3]), _anchor(t[4]), int.parse(t[5]));
      case 'x':
        n(t[1]).getAnchor(_anchor(t[2]))!.reset();
      case 'hb':
        n(t[1]).setHorizontalDimensionBehaviour(_behaviourOf(t[2]));
      case 'vb':
        n(t[1]).setVerticalDimensionBehaviour(_behaviourOf(t[2]));
      case 'hm':
        n(t[1]).setHorizontalMatchStyle(
          int.parse(t[2]),
          int.parse(t[3]),
          int.parse(t[4]),
          parseFloat32(t[5]),
        );
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
      case 'hbl':
        n(t[1]).setHasBaseline(t[2] == '1');
      case 'ra':
        n(t[1]).setDimensionRatio(parseFloat32(t[2]), int.parse(t[3]));
      case 'vc':
        n(t[1]).setVerticalChainStyle(int.parse(t[2]));
      default:
        throw ArgumentError('op not supported by this test: $op');
    }
  }
  return root;
}

ConstraintAnchorType _anchor(String s) => switch (s) {
  'L' => ConstraintAnchorType.left,
  'R' => ConstraintAnchorType.right,
  'T' => ConstraintAnchorType.top,
  'B' => ConstraintAnchorType.bottom,
  'S' => ConstraintAnchorType.baseline,
  _ => throw ArgumentError('anchor $s'),
};

DimensionBehaviour _behaviourOf(String s) => switch (s) {
  'F' => DimensionBehaviour.fixed,
  'W' => DimensionBehaviour.wrapContent,
  'M' => DimensionBehaviour.matchConstraint,
  'P' => DimensionBehaviour.matchParent,
  _ => throw ArgumentError('behaviour $s'),
};
