// Where the solver puts the members of a chain that is not packed against
// one end, through measure() on the core path (test/support/op_replay.dart:
// the echo measurer, then measure() at the level).
//
// The solver places every member edge at its exact position and reports it
// as (int) (value + 0.5) (LinearSystem.getObjectVariableValue): two
// match-constraint members of a 375 px layout are 188 and 187 px wide, and a
// spread chain's gaps add up to the container. Direct never places a chain
// member, and BasicMeasure never builds the dependency graph for a layout
// with a chain, so every optimization level gives these frames. The expected
// strings are the pinned oracle's (VOpDriver v2, core path, -XX:hashCode=2):
// the same at levels 257, 0, 64, 321, 192 and 449.

import 'package:test/test.dart';

import 'support/op_replay.dart';

/// The op list of a horizontal chain of [widths.length] members (`a`, `b`,
/// and so on) across a [width] x 600 container: fixed members of [widths],
/// or match-constraint ones with [match], weighted with [weights], in
/// [style], with [outer] margins against the container and [inner] margins
/// between the members, in a right-to-left container with [rtl].
String chain({
  required int width,
  required List<int> widths,
  bool match = false,
  List<String>? weights,
  int style = 0,
  int outer = 0,
  int inner = 0,
  bool rtl = false,
}) {
  final names = [
    for (var i = 0; i < widths.length; i++) String.fromCharCode(0x61 + i),
  ];
  return [
    'R $width 600',
    if (rtl) 'rtl',
    for (final (i, n) in names.indexed) ...['w $n ${widths[i]} 40', 'add $n'],
    for (final (i, n) in names.indexed) ...[
      if (match) 'hb $n M',
      if (weights != null) 'hw $n ${weights[i]}',
      'hc $n $style',
      'c $n T root T 0',
      if (i == 0)
        'c $n L root L $outer'
      else ...[
        'c $n L ${names[i - 1]} R 0',
        'c ${names[i - 1]} R $n L $inner',
      ],
    ],
    'c ${names.last} R root R $outer',
  ].join(';');
}

/// Replays [ops] at OPTIMIZATION_STANDARD (Android's default), with and
/// without Direct, and at the dependency-graph levels, and expects Java's
/// frames, [java], at each.
void expectJava(String ops, String java) {
  for (final level in const [257, 0, 64, 321, 192, 449]) {
    final r = replayCore(ops, level: level);
    expect(r.status, 'ok', reason: 'level $level');
    expect(r.geometry, java, reason: 'level $level');
  }
}

void main() {
  group('chain rounding', () {
    for (final rtl in [false, true]) {
      final direction = rtl ? 'right to left' : 'left to right';

      test('two match-constraint members share 375 px, $direction', () {
        expectJava(
          chain(width: 375, widths: [50, 57], match: true, rtl: rtl),
          'root 375 x 600 | a: (0, 0) 188 x 40 | b: (188, 0) 187 x 40',
        );
      });

      test('five fixed members spread across 325 px, $direction', () {
        expectJava(
          chain(width: 325, widths: [50, 57, 64, 71, 78], rtl: rtl),
          'root 325 x 600 | a: (1, 0) 50 x 40 | b: (52, 0) 57 x 40 | '
          'c: (110, 0) 64 x 40 | d: (174, 0) 71 x 40 | e: (246, 0) 78 x 40',
        );
      });

      test('two fixed members packed in 300 px, $direction', () {
        expectJava(
          chain(width: 300, widths: [50, 57], style: 2, rtl: rtl),
          'root 300 x 600 | a: (97, 0) 50 x 40 | b: (147, 0) 57 x 40',
        );
      });
    }

    test('five fixed members spread inside 323 px', () {
      expectJava(
        chain(width: 323, widths: [50, 57, 64, 71, 78], style: 1),
        'root 323 x 600 | a: (0, 0) 50 x 40 | b: (51, 0) 57 x 40 | '
        'c: (109, 0) 64 x 40 | d: (173, 0) 71 x 40 | e: (245, 0) 78 x 40',
      );
    });

    test('five match-constraint members with margins in 301 px', () {
      expectJava(
        chain(
          width: 301,
          widths: [50, 57, 64, 71, 78],
          match: true,
          outer: 16,
          inner: 8,
        ),
        'root 301 x 600 | a: (16, 0) 47 x 40 | b: (71, 0) 48 x 40 | '
        'c: (127, 0) 47 x 40 | d: (182, 0) 48 x 40 | e: (238, 0) 47 x 40',
      );
    });

    test('four match-constraint members weighted 1 to 4 in 375 px', () {
      expectJava(
        chain(
          width: 375,
          widths: [50, 57, 64, 71],
          match: true,
          weights: ['1', '2', '3', '4'],
        ),
        'root 375 x 600 | a: (0, 0) 38 x 40 | b: (38, 0) 75 x 40 | '
        'c: (113, 0) 112 x 40 | d: (225, 0) 150 x 40',
      );
    });
  });
}
