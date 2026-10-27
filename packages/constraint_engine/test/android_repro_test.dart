// Android's pixels, at OPTIMIZATION_STANDARD (257), the level Android runs,
// and at level 0, on minimal repros of the ways the engine's earlier
// graph-first design differed from Android, found when the baseline suite
// (tool/parity/FORMATS.md) checked it: the mechanisms M1 to M10 (the groups
// below), the gaps 266 and 74 of its DirectResolution model, since deleted,
// and "float can widen a FIXED widget".
//
// Each repro is an op list replayed on OpDriver's core path
// (support/op_replay.dart: the echo measurer, then measure() at the level).
// Every expected string is the pinned oracle's, byte for byte (VOpDriver v2,
// core path, -XX:hashCode=2, levels 257,0: the op lists below, under the id
// each test cites, run through tool/parity/java/jrun.sh). Level 0 runs no
// Direct pass, so where J257 and J0 differ, Direct is the cause.

import 'package:test/test.dart';

import 'support/op_replay.dart';

/// Replays [ops] at 257 and at level 0 on the core path and expects Java's
/// geometry at each: [j257], and [j0] (the same as [j257] when null).
void _expectJava(String ops, String j257, [String? j0]) {
  final standard = replayCore(ops);
  expect(standard.status, 'ok');
  expect(standard.geometry, equals(j257), reason: 'Java J257');
  final none = replayCore(ops, level: 0);
  expect(none.status, 'ok');
  expect(none.geometry, equals(j0 ?? j257), reason: 'Java J0');
}

void main() {
  group(
    'M1 negative edge: every edge reads back as (int) (v + 0.5f), so an exact '
    'negative edge n comes out as n + 1',
    () {
      // repro:M1a
      test(
        'a FIXED widget keeps its size and moves: ic0 at y -29, not -30',
        () {
          _expectJava(
            'R 397 1278;w ic0 50 50;add ic0;w t0 80 20;add t0;'
                'c ic0 B t0 B 0',
            'root 397 x 1278 | ic0: (0, -29) 50 x 50 | t0: (0, 0) 80 x 20',
          );
        },
      );

      // repro:M1b
      test(
        'any other size loses the pixel: fld0 at -269, 269 wide',
        () {
          _expectJava(
            'R 360 574;w lbl0 220 20;add lbl0;w fld0 190 40;add fld0;'
                'hb fld0 M;hm fld0 2 0 0 0.75;c fld0 R lbl0 L 0',
            'root 360 x 574 | lbl0: (0, 0) 220 x 20 | '
                'fld0: (-269, 0) 269 x 40',
          );
        },
      );

      // repro:M1c
      test(
        'with Direct the truncations stack: Direct centers ic0 at y -14, the '
        'readback gives -13',
        () {
          _expectJava(
            'R 397 1278;w ic0 50 50;add ic0;w t0 80 21;add t0;'
                'c ic0 T t0 T 0;c ic0 B t0 B 0;c t0 T root T 0',
            'root 397 x 1278 | ic0: (0, -13) 50 x 50 | t0: (0, 0) 80 x 21',
            'root 397 x 1278 | ic0: (0, -14) 50 x 50 | t0: (0, 0) 80 x 21',
          );
        },
      );
    },
  );

  group(
    'M2 fractional sizes: a percent or ratio size stays fractional, and a '
    'ratio truncates',
    () {
      // repro:M2a
      test(
        'a percent width keeps its fraction until each edge rounds: title 716 '
        'wide (153.6 to 870.4)',
        () {
          _expectJava(
            'R 1024 983;w title 240 20;add title;hb title M;'
                'hm title 2 0 0 0.7;c title L root L 0;c title R root R 0',
            'root 1024 x 983 | title: (154, 0) 716 x 20',
          );
        },
      );

      // repro:M2b
      test(
        'a ratio width truncates: image 81 x 46 (Direct\'s last pass measures '
        'it)',
        () {
          _expectJava(
            'R 512 699;w image 190 46;add image;hb image M;'
                'ra image 1.7777778 -1',
            'root 512 x 699 | image: (0, 0) 81 x 46',
          );
        },
      );
    },
  );

  group(
    'M3 crossed or coincident links (Direct)',
    () {
      // direct:coincident
      test(
        'targets at one position drop the margins and the bias: t0 at 353 (J0 '
        '345)',
        () {
          _expectJava(
            'R 398 976;w w0 30 60;add w0;w t0 90 40;add t0;c w0 R root R 0;'
                'c t0 L w0 R 0;c t0 R root R 16',
            'root 398 x 976 | w0: (368, 0) 30 x 60 | t0: (353, 0) 90 x 40',
            'root 398 x 976 | w0: (368, 0) 30 x 60 | t0: (345, 0) 90 x 40',
          );
        },
      );

      // direct:crossed
      test(
        'crossed targets give a negative width, which the readback turns into '
        '0 x 20 at 0 (J0 (155, 0) 90 x 20)',
        () {
          _expectJava(
            'R 400 300;w t0 90 20;add t0;c t0 L root L 300;'
                'c t0 R root R 300;c t0 T root T 0',
            'root 400 x 300 | t0: (0, 0) 0 x 20',
            'root 400 x 300 | t0: (155, 0) 90 x 20',
          );
        },
      );

      // repro:M3c
      test(
        'a gone target collapses onto its own target: t0 at 621 (J0 624)',
        () {
          _expectJava(
            'R 671 771;w w0 20 80;add w0;w t0 100 50;add t0;v w0 8;'
                'c w0 R root R 0;c t0 L w0 R 5;c t0 R root R 0',
            'root 671 x 771 | w0: gone, 0 x 0 | t0: (621, 0) 100 x 50',
            'root 671 x 771 | w0: gone, 0 x 0 | t0: (624, 0) 100 x 50',
          );
        },
      );
    },
  );

  group(
    'M4 centered, does not fit (Direct)',
    () {
      // repro:M4
      test(
        'the offset (int) (bias * distance) truncates toward zero: ic0 at y 7 '
        '(J0 6)',
        () {
          _expectJava(
            'R 963 1277;w ic0 30 30;add ic0;w t0 170 24;add t0;vx ic0 0.3;'
                'c ic0 T t0 T 0;c ic0 B t0 B 0;c t0 T root T 8',
            'root 963 x 1277 | ic0: (0, 7) 30 x 30 | t0: (0, 8) 170 x 24',
            'root 963 x 1277 | ic0: (0, 6) 30 x 30 | t0: (0, 8) 170 x 24',
          );
        },
      );
    },
  );

  group(
    'M5 half-pixel cascades',
    () {
      // repro:M5a
      test(
        'Direct rounds the parent first: sub at 271 (J0 270)',
        () {
          _expectJava(
            'R 600 909;w title 75 20;add title;w sub 60 10;add sub;'
                'c title L root L 0;c title R root R 0;c sub L title L 0;'
                'c sub R title R 0',
            'root 600 x 909 | title: (263, 0) 75 x 20 | '
                'sub: (271, 0) 60 x 10',
            'root 600 x 909 | title: (263, 0) 75 x 20 | '
                'sub: (270, 0) 60 x 10',
          );
        },
      );

      // repro:M5b
      test(
        'a percent parent stays with the solver, which keeps the half: sub at '
        '105',
        () {
          _expectJava(
            'R 390 594;w title 100 20;add title;w sub 180 10;add sub;'
                'hb title M;hm title 2 0 0 0.7;c title L root L 0;'
                'c title R root R 0;c sub L title L 0;c sub R title R 0',
            'root 390 x 594 | title: (59, 0) 273 x 20 | '
                'sub: (105, 0) 180 x 10',
          );
        },
      );
    },
  );

  group(
    'M6 odd bias, float',
    () {
      // repro:M6a
      test(
        'Direct\'s (int) (0.5f + 0.35f * 650): 0.35f * 650 is 227.5f, so title '
        'is at 244 (J0 (243) 99 wide)',
        () {
          _expectJava(
            'R 812 404;w nav 24 40;add nav;w title 98 20;add title;'
                'c nav R root R 8;hx title 0.35;c title R nav L 16;'
                'c title L root L 16',
            'root 812 x 404 | nav: (780, 0) 24 x 40 | '
                'title: (244, 0) 98 x 20',
            'root 812 x 404 | nav: (780, 0) 24 x 40 | '
                'title: (243, 0) 99 x 20',
          );
        },
      );

      // repro:M6b
      test(
        'the solver centers in float: w0 at 258',
        () {
          _expectJava(
            'R 892 668;w w0 110 30;add w0;hx w0 0.3;c w0 L root L 34;'
                'c w0 R root R 3',
            'root 892 x 668 | w0: (258, 0) 110 x 30',
          );
        },
      );
    },
  );

  group(
    'M7 barrier position',
    () {
      // direct:barrier427
      test(
        'a barrier over a gone reference, resolved by Barrier.allSolved: tr0 '
        'at 427 (J0 411)',
        () {
          _expectJava(
            'R 411 397;b tr0;add tr0;w ch0 20 10;add ch0;bm tr0 16;'
                'ref tr0 ch0;v ch0 8;c ch0 R root R 0',
            'root 411 x 397 | tr0: (427, 0) 0 x 0 | ch0: gone, 0 x 0',
            'root 411 x 397 | tr0: (411, 0) 0 x 0 | ch0: gone, 0 x 0',
          );
        },
      );
    },
  );

  group(
    'M8 gone widget with a baseline link (Direct)',
    () {
      // direct:baseline121
      test(
        'setFinalBaseline places a gone widget with its raw height: btn0 at y '
        '121 (J0 81)',
        () {
          _expectJava(
            'R 314 844;w card 130 370;add card;w icon 10 50;add icon;'
                'w caption 200 10;add caption;w title 30 20;add title;'
                'w value 0 40;add value;w btn0 60 30;add btn0;hbl value 1;'
                'hbl title 1;c card T root T 0;c icon T card T 0;'
                'c caption T icon B 0;c title T caption B 0;hb value M;'
                'v value 8;c value S title S 0;c btn0 T value B 0;bl title 21',
            'root 314 x 844 | card: (0, 0) 130 x 370 | '
                'icon: (0, 0) 10 x 50 | caption: (0, 50) 200 x 10 | '
                'title: (0, 60) 30 x 20 | value: gone, 0 x 0 | '
                'btn0: (0, 121) 60 x 30',
            'root 314 x 844 | card: (0, 0) 130 x 370 | '
                'icon: (0, 0) 10 x 50 | caption: (0, 50) 200 x 10 | '
                'title: (0, 60) 30 x 20 | value: gone, 0 x 0 | '
                'btn0: (0, 81) 60 x 30',
          );
        },
      );
    },
  );

  group(
    'M9 chains, float',
    () {
      // repro:M9
      test(
        'an equal spread whose split lands on .5 breaks ties in float: widths '
        '244, 243, 244, 243',
        () {
          _expectJava(
            'R 974 490;w tab0 250 20;add tab0;w tab1 90 20;add tab1;'
                'w tab2 120 20;add tab2;w tab3 170 20;add tab3;hb tab0 M;'
                'c tab0 L root L 0;c tab0 R tab1 L 0;hb tab1 M;'
                'c tab1 L tab0 R 0;c tab1 R tab2 L 0;hb tab2 M;'
                'c tab2 L tab1 R 0;c tab2 R tab3 L 0;hb tab3 M;'
                'c tab3 L tab2 R 0;c tab3 R root R 0',
            'root 974 x 490 | tab0: (0, 0) 244 x 20 | '
                'tab1: (244, 0) 243 x 20 | tab2: (487, 0) 244 x 20 | '
                'tab3: (731, 0) 243 x 20',
          );
        },
      );
    },
  );

  group(
    'M10 percent guideline, float',
    () {
      // repro:M10
      test(
        '0.65f * 390 is 253.49999 in float: col at 253',
        () {
          _expectJava(
            'R 390 1114;g col;add col;go col 1;gp col 0.65',
            'root 390 x 1114 | col: (253, 0) 0 x 1114',
          );
        },
      );
    },
  );

  group(
    'float can widen a FIXED widget',
    () {
      // repro:widen
      test(
        'setFrame restores only a size that came out smaller: sub (210, 0) 51 '
        'x 10',
        () {
          _expectJava(
            'R 471 481;w title 60 20;add title;w sub 50 10;add sub;'
                'hb title M;hm title 2 0 0 0.45;c title L root L 0;'
                'c title R root R 0;c sub L title L 0;c sub R title R 0',
            'root 471 x 481 | title: (130, 0) 211 x 20 | '
                'sub: (210, 0) 51 x 10',
          );
        },
      );
    },
  );

  group(
    'gaps of the earlier DirectResolution model (since deleted)',
    () {
      // repro:gap266
      test(
        'a ratio on a one-link axis: image 266 wide',
        () {
          _expectJava(
            'R 243 1234;w card 500 250;add card;w image 60 150;add image;'
                'c card L root L 0;hb image M;ra image 1.7777778 -1;'
                'c image L card L 0',
            'root 243 x 1234 | card: (0, 0) 500 x 250 | '
                'image: (0, 0) 266 x 150',
          );
        },
      );

      // repro:gap74
      test(
        'Direct resolves a parent with a constrained-wrap width: sub at 74 (J0 '
        '73)',
        () {
          _expectJava(
            'R 316 447;w nav 40 40;add nav;w title 89 20;add title;'
                'w sub 210 10;add sub;c nav L root L 0;hb title M;'
                'hm title 1 0 0 1.0;c title L nav R 0;c title R root R 0;'
                'c sub L title L 0;c sub R title R 0',
            'root 316 x 447 | nav: (0, 0) 40 x 40 | '
                'title: (134, 0) 89 x 20 | sub: (74, 0) 210 x 10',
            'root 316 x 447 | nav: (0, 0) 40 x 40 | '
                'title: (134, 0) 89 x 20 | sub: (73, 0) 210 x 10',
          );
        },
      );
    },
  );
}
