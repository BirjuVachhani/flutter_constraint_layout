// Links that loop back on themselves.
//
// A widget is a chain member when one of its anchors targets an anchor that
// targets it straight back, whatever the sides of the two anchors. Two
// widgets whose matching anchors link to each other (two tops, for example),
// an anchor linked to itself, or two widgets linked both ways on both sides
// form a chain with no first or last member. BasicMeasure keeps the
// dependency graph off for any layout with a chain member, at every
// optimization level, so the solver lays these out; the graph's own chain
// walk (ChainRun) stops on such a loop too, for a direct
// DependencyGraph.directMeasure call.
//
// The solver's chain walks (ChainHead.defineChainProperties and
// Chain.applyChainConstraints) never end, upstream's included, for a chain
// whose first member's start links one way to its last member while the last
// member's end links back to the first. Here they stop at the first member;
// those layouts are only checked to finish, the same at every level.
//
// Each layout is an op list replayed on the core path
// (test/support/op_replay.dart: the echo measurer, then measure() at the
// level). The expected strings are the pinned oracle's (VOpDriver v2, core
// path, -XX:hashCode=2), the same at levels 257, 0, 64, 321, 192 and 449;
// Java hangs on the last two. Each layout runs in its own isolate, so a
// regression fails its test instead of hanging the run. The timeout is
// short because some of these loops also grow a list: before the fix, two
// widgets whose rights link to each other took about 1 GB of memory a
// second.

import 'dart:async';
import 'dart:isolate';

import 'package:test/test.dart';

import 'support/op_replay.dart';

/// The levels each layout is laid out at.
const _levels = [257, 0, 64, 321, 192, 449];

/// The status and geometry of [ops] at [level], replayed in an isolate.
/// Fails the test if the layout does not finish.
Future<OpReplay> layoutInIsolate(String ops, int level) async {
  final port = ReceivePort();
  final isolate = await Isolate.spawn(_layout, (port.sendPort, ops, level));
  try {
    return await port.first.timeout(const Duration(seconds: 2)) as OpReplay;
  } on TimeoutException {
    fail('the layout did not finish within 2 seconds at level $level');
  } finally {
    isolate.kill(priority: Isolate.immediate);
    port.close();
  }
}

void _layout((SendPort, String, int) message) {
  final (reply, ops, level) = message;
  reply.send(replayCore(ops, level: level));
}

/// `a` and `b`, 100 x 50 each, in a 375 x 600 container.
const _two = 'R 375 600;w a 100 50;add a;w b 100 50;add b';

/// Lays [ops] out at every level of [_levels] and expects [java].
Future<void> expectJava(String ops, String java) async {
  for (final level in _levels) {
    final r = await layoutInIsolate(ops, level);
    expect(r.status, 'ok', reason: 'level $level');
    expect(r.geometry, java, reason: 'level $level');
  }
}

void main() {
  group('links that loop', () {
    // Upstream lays every one of these out with both widgets unplaced.
    final unplaced = <String, String>{
      'tops linked to each other': '$_two;c a T b T 0;c b T a T 0',
      'bottoms linked to each other': '$_two;c a B b B 0;c b B a B 0',
      'lefts linked to each other': '$_two;c a L b L 0;c b L a L 0',
      'rights linked to each other': '$_two;c a R b R 0;c b R a R 0',
      'two widgets linked both ways on both sides':
          '$_two;c a L b R 0;c a R b L 0;c b L a R 0;c b R a L 0',
    };
    for (final MapEntry(key: name, value: ops) in unplaced.entries) {
      test('$name lay out as upstream does', () async {
        await expectJava(
          ops,
          'root 375 x 600 | a: (0, 0) 100 x 50 | b: (0, 0) 100 x 50',
        );
      });
    }

    for (final (name, ops) in [
      ('a left linked to itself', 'R 375 600;w a 100 50;add a;c a L a L 0'),
      ('a right linked to itself', 'R 375 600;w a 100 50;add a;c a R a R 0'),
    ]) {
      test('$name lays out as upstream does', () async {
        await expectJava(ops, 'root 375 x 600 | a: (0, 0) 100 x 50');
      });
    }

    test('tops linked to each other in a row of widgets', () async {
      // The Flutter adapter's `top: .topOf(#b)` and `top: .topOf(#a)`, with
      // both widgets placed horizontally: `b` 8 to the right of `a`.
      await expectJava(
        '$_two;c a L root L 16;c b L a R 8;c a T b T 0;c b T a T 0',
        'root 375 x 600 | a: (16, 0) 100 x 50 | b: (124, 0) 100 x 50',
      );
    });

    test('rights linked to each other in a right-to-left layout', () async {
      // `b` stacked under `a`.
      await expectJava(
        'R 375 600;rtl;w a 100 50;add a;w b 100 50;add b;'
            'c a R b R 0;c b R a R 0;c a T root T 0;c b T a B 0',
        'root 375 x 600 | a: (0, 0) 100 x 50 | b: (0, 50) 100 x 50',
      );
    });

    // Upstream never returns from these two (Java hangs at every level), so
    // the frames are the port's own: its chain walks stop at the first
    // member.
    for (final (name, ops, frames) in [
      (
        'a chain whose first member\'s start links one way to its last '
            'member, while the last member\'s end links back to the first',
        // `h` heads a chain (its left links one way to `a`, its right both
        // ways), and `a`'s right links back to `h`: the walk returns to `h`.
        'R 375 600;w h 100 50;add h;w a 100 50;add a;'
            'c h L a L 0;c h R a L 0;c a L h R 0;c a R h L 0',
        'root 375 x 600 | h: (100, 0) 100 x 50 | a: (200, 0) 100 x 50',
      ),
      (
        'a widget whose start and end both link to its own end',
        'R 375 600;w x 100 50;add x;c x L x R 0;c x R x R 0',
        'root 375 x 600 | x: (-199, 0) 100 x 50',
      ),
    ]) {
      test('$name: the layout finishes, the same at every level', () async {
        for (final level in _levels) {
          final r = await layoutInIsolate(ops, level);
          expect(r.status, 'ok', reason: 'level $level');
          expect(r.geometry, frames, reason: 'level $level');
        }
      });
    }
  });
}
