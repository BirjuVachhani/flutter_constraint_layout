// The view measurer of a ConstraintLayout: how a child's measure specs become
// box constraints, how its answer rounds to whole pixels, the baseline every
// measured child reports, a Group's answer, the error of a child that cannot
// size itself under unbounded constraints, and what the dry queries ask.
//
// Expected frames and request transcripts are Java's: VOpDriver at the pin,
// view path, level 257 (pinned classes, -XX:hashCode=2, -Dprobe
// -Dtranscript). Each test cites its probe: a `p4:` or `p4b:` id names an op
// list of test/parity/probes.in, whose output is test/parity/probes.J257.txt,
// and the C probes (`probe:C1`, `probe:C2`) are op lists of the engine's
// test/view_host_test.dart. Every probe gives the same frames at level 0. A
// probe's content op (`ct N KIND W H BL`, FORMATS 6) is reproduced by
// [_Content] with the same size, so the Flutter tree answers the same
// measures. A Flutter-only rule has no probe, and its test states the rule
// instead, as the adapter's README documents it: sizes rounded up to whole
// pixels ("Whole pixels"), the error of a child that cannot size itself on
// an unbounded axis ("Children on an unbounded axis"), and the dry queries
// ("Intrinsic sizes, dry layout, and baseline").
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => RenderConstraintLayout.debugRecordTranscripts = true);
  tearDown(() => RenderConstraintLayout.debugRecordTranscripts = false);

  group('measure specs become box constraints', () {
    testWidgets('EXACTLY is tight and AT_MOST is 0 up to the size (C2)', (
      tester,
    ) async {
      // Java J257: A (0, 10) 400 x 60 (VOpDriver view, probe:C2: MATCH_PARENT
      // x WRAP text 1000 / 20 under E400 x E800).
      final log = <BoxConstraints>[];
      await _pump(tester, BoxConstraints.tight(const Size(400, 800)), [
        Constrained(
          id: #A,
          top: .topOf(parent, margin: 10),
          width: .matchParent,
          child: _Content.text(1000, 20, log: log),
        ),
      ]);
      expect(_geometry(tester, ['A']), 'root 400 x 800 | A: (0, 10) 400 x 60');
      expect(_transcript(tester), 'M:A:0:PW:0,0:E400/A800:400,60,-1,01');
      expect(
        log.first,
        const BoxConstraints(minWidth: 400, maxWidth: 400, maxHeight: 800),
      );
    });

    testWidgets('UNSPECIFIED is 0 up to infinity (p4:mpunbounded)', (
      tester,
    ) async {
      // Java J257: root 400 x 20, A (0, 0) 120 x 20 (VOpDriver view,
      // p4:mpunbounded: E400 x U0, WRAP x MATCH_PARENT text 120 / 20).
      final log = <BoxConstraints>[];
      await _pump(tester, const BoxConstraints(minWidth: 400, maxWidth: 400), [
        Constrained(
          id: #A,
          left: .leftOf(parent),
          top: .topOf(parent),
          height: .matchParent,
          child: _Content.text(120, 20, log: log),
        ),
      ]);
      expect(_geometry(tester, ['A']), 'root 400 x 20 | A: (0, 0) 120 x 20');
      expect(_transcript(tester), 'M:A:0:WP:0,0:A400/U0:120,20,-1,01');
      expect(log.first, const BoxConstraints(maxWidth: 400));
    });

    testWidgets('a fixed size of 0 is measured EXACTLY(0) (p4:fixed0)', (
      tester,
    ) async {
      // Java J257: a (0, 0) 0 x 20 (VOpDriver view, p4:fixed0: FIXED 0 x 20,
      // content box 50 x 20).
      final log = <BoxConstraints>[];
      await _pump(tester, BoxConstraints.tight(const Size(400, 100)), [
        Constrained(
          id: #a,
          left: .leftOf(parent),
          top: .topOf(parent),
          width: .fixed(0),
          height: .fixed(20),
          child: _Content.box(50, 20, log: log),
        ),
      ]);
      expect(_geometry(tester, ['a']), 'root 400 x 100 | a: (0, 0) 0 x 20');
      expect(_transcript(tester), 'M:a:0:FF:0,20:E0/E20:0,20,-1,00');
      expect(log.first, BoxConstraints.tight(const Size(0, 20)));
    });

    testWidgets(
      'a match-constraint width on an unbounded axis is measured for its '
      'content first (p4:mcunbounded)',
      (tester) async {
        // Java J257: root 0 x 100, A (0, 0) 0 x 100 (VOpDriver view,
        // p4:mcunbounded: U0 x E100, spread MC x WRAP between both parent
        // edges, text 120 / 20). Direct measures it U0/A100, then the
        // re-measure loop twice at E0/A100.
        final log = <BoxConstraints>[];
        await _pump(tester, BoxConstraints.tightFor(height: 100), [
          Constrained(
            id: #A,
            left: .leftOf(parent),
            right: .rightOf(parent),
            top: .topOf(parent),
            width: .matchConstraint,
            child: _Content.text(120, 20, log: log),
          ),
        ]);
        expect(_geometry(tester, ['A']), 'root 0 x 100 | A: (0, 0) 0 x 100');
        expect(
          _transcript(tester),
          'P:A:0:MW:0,0:U0/A100:120,20,-1,01 '
          'R:A:1:MW:0,20:E0/A100:0,100,-1,01 '
          'R:A:2:MW:0,100:E0/A100:0,100,-1,00',
        );
        expect(log.take(3), const [
          BoxConstraints(maxHeight: 100),
          BoxConstraints(maxWidth: 0, maxHeight: 100),
          BoxConstraints(maxWidth: 0, maxHeight: 100),
        ]);
      },
    );
  });

  group('sizes round up to whole pixels', () {
    testWidgets('99.4 answers 100, 99.0005 answers 99, 99.002 answers 100', (
      tester,
    ) async {
      // The answers are Java's box contents: Java J257: a (0, 0) 100 x 20, b
      // (100, 0) 99 x 20, c (199, 0) 100 x 21 (VOpDriver view, p4b:sizes:
      // boxes 100 x 20, 99 x 20 and 100 x 21). The Flutter sizes round to
      // them by the adapter's rule ("Whole pixels" in the README):
      // max(0, (v - 0.001).ceil()).
      await _pump(tester, BoxConstraints.tight(const Size(400, 100)), [
        Constrained(
          id: #a,
          left: .leftOf(parent),
          top: .topOf(parent),
          child: const _Content.box(99.4, 20),
        ),
        Constrained(
          id: #b,
          left: .rightOf(#a),
          top: .topOf(parent),
          child: const _Content.box(99.0005, 20),
        ),
        Constrained(
          id: #c,
          left: .rightOf(#b),
          top: .topOf(parent),
          child: const _Content.box(99.002, 20.4),
        ),
      ]);
      expect(
        _geometry(tester, ['a', 'b', 'c']),
        'root 400 x 100 | a: (0, 0) 100 x 20 | b: (100, 0) 99 x 20 | '
        'c: (199, 0) 100 x 21',
      );
      expect(
        _transcript(tester),
        'M:a:0:WW:0,0:A400/A100:100,20,-1,01 '
        'M:b:0:WW:0,0:A400/A100:99,20,-1,01 '
        'M:c:0:WW:0,0:A400/A100:100,21,-1,01',
      );
    });

    testWidgets('a child is laid out tight at its rounded-up frame', (
      tester,
    ) async {
      // A box 99.4 wide answers 100, so its frame is 100 wide and the child
      // is laid out again, tight at the frame, rather than left at 99.4.
      final log = <BoxConstraints>[];
      await _pump(tester, BoxConstraints.tight(const Size(400, 100)), [
        Constrained(
          id: #a,
          left: .leftOf(parent),
          top: .topOf(parent),
          child: _Content.box(99.4, 20, log: log),
        ),
      ]);
      expect(log, [
        const BoxConstraints(maxWidth: 400, maxHeight: 100),
        BoxConstraints.tight(const Size(100, 20)),
      ]);
      expect(_geometry(tester, ['a']), 'root 400 x 100 | a: (0, 0) 100 x 20');
    });
  });

  group('every measured child reports its baseline', () {
    testWidgets('integral, zero, missing and fractional baselines', (
      tester,
    ) async {
      // Java J257: x 15, y -1 (none), z 0, q 14, with hasBaseline set unless
      // -1 (VOpDriver view, p4b:baselines: boxes 50 x 20 with baselines 15,
      // -1, 0 and 14, no baseline link). q's 13.4 rounds up to 14, as a size
      // does.
      await _pump(tester, BoxConstraints.tight(const Size(400, 100)), [
        Constrained(
          id: #x,
          left: .leftOf(parent),
          top: .topOf(parent),
          child: const _Content.box(50, 20, baseline: 15),
        ),
        Constrained(
          id: #y,
          left: .rightOf(#x),
          top: .topOf(parent),
          child: const _Content.box(50, 20),
        ),
        Constrained(
          id: #z,
          left: .rightOf(#y),
          top: .topOf(parent),
          child: const _Content.box(50, 20, baseline: 0),
        ),
        Constrained(
          id: #q,
          left: .rightOf(#z),
          top: .topOf(parent),
          child: const _Content.box(50, 20, baseline: 13.4),
        ),
      ]);
      expect(
        _geometry(tester, ['x', 'y', 'z', 'q']),
        'root 400 x 100 | x: (0, 0) 50 x 20 | y: (50, 0) 50 x 20 | '
        'z: (100, 0) 50 x 20 | q: (150, 0) 50 x 20',
      );
      expect(
        _transcript(tester),
        'M:x:0:WW:0,0:A400/A100:50,20,15,11 '
        'M:y:0:WW:0,0:A400/A100:50,20,-1,01 '
        'M:z:0:WW:0,0:A400/A100:50,20,0,11 '
        'M:q:0:WW:0,0:A400/A100:50,20,14,11',
      );
    });

    for (final (label, b, c) in const [
      ('integral', 30.0, 15.0),
      ('fractional, rounded up', 29.4, 15.0005),
    ]) {
      testWidgets('a fixed baseline pair, $label baselines (C1)', (
        tester,
      ) async {
        // Java J257: B (0, 100) 100 x 40, C (100, 115) 100 x 20 (VOpDriver
        // view, probe:C1: fixed 100 x 40 and 100 x 20 with baselines 30 and
        // 15, C's baseline linked to B's). 29.4 answers 30 and 15.0005 answers
        // 15, so the fractional pair gives the same frames.
        await _pump(tester, BoxConstraints.tight(const Size(400, 800)), [
          Constrained(
            id: #B,
            left: .leftOf(parent),
            top: .topOf(parent, margin: 100),
            width: .fixed(100),
            height: .fixed(40),
            child: _Content.box(100, 40, baseline: b),
          ),
          Constrained(
            id: #C,
            left: .rightOf(#B),
            baseline: .baselineOf(#B),
            width: .fixed(100),
            height: .fixed(20),
            child: _Content.box(100, 20, baseline: c),
          ),
        ]);
        expect(
          _geometry(tester, ['B', 'C']),
          'root 400 x 800 | B: (0, 100) 100 x 40 | C: (100, 115) 100 x 20',
        );
        expect(
          _transcript(tester),
          'M:B:0:FF:100,40:E100/E40:100,40,30,11 '
          'M:C:0:FF:100,20:E100/E20:100,20,15,11',
        );
      });
    }
  });

  group('a Group answers 0 x 0 without a baseline', () {
    for (final gone in [false, true]) {
      testWidgets(gone ? 'a gone Group (p4:groupgone)' : 'a Group (p4:group)', (
        tester,
      ) async {
        // Java J257: a (10, 10) 100 x 20, G (0, 0) 0 x 0 (or gone), k (115,
        // 10) 30 x 20 (VOpDriver view, p4:group and p4:groupgone: the Group
        // as Android's plain WRAP x WRAP widget, measured 0 x 0 with baseline
        // -1, or GONE).
        await _pump(tester, BoxConstraints.tight(const Size(400, 100)), [
          Constrained(
            id: #a,
            left: .leftOf(parent, margin: 10),
            top: .topOf(parent, margin: 10),
            child: const _Content.box(100, 20),
          ),
          ConstraintGroup(
            id: #G,
            referenced: const [],
            visibility: gone ? .gone : .visible,
          ),
          Constrained(
            id: #k,
            left: .rightOf(#a, margin: 5),
            top: .topOf(parent, margin: 10),
            child: const _Content.box(30, 20),
          ),
        ]);
        expect(
          _geometry(tester, ['a', 'G', 'k'], gone: {if (gone) 'G'}),
          'root 400 x 100 | a: (10, 10) 100 x 20 | '
          '${gone ? 'G: gone, 0 x 0' : 'G: (0, 0) 0 x 0'} | '
          'k: (115, 10) 30 x 20',
        );
        expect(
          _transcript(tester),
          'M:a:0:WW:0,0:A400/A100:100,20,-1,01 '
          '${gone ? 'M:G:0:WW:0,0:g:0,0,0,00' : 'M:G:0:WW:0,0:A400/A100:0,0,-1,00'} '
          'M:k:0:WW:0,0:A400/A100:30,20,-1,01',
        );
      });
    }
  });

  group('a child that cannot size itself on an unbounded axis', () {
    testWidgets('a vertical ListView with a matchParent height fails loudly', (
      tester,
    ) async {
      // The layout is unbounded vertically (a scroll view), so it measures a
      // matchParent height UNSPECIFIED, which is 0 up to infinity, and a
      // vertical viewport cannot take that ("Children on an unbounded axis"
      // in the README).
      final errors = await _collectErrors(
        () => tester.pumpWidget(
          _scrolling(
            Constrained(
              id: #list,
              left: .leftOf(parent),
              top: .topOf(parent),
              width: .fixed(100),
              height: .matchParent,
              child: ListView(children: const [SizedBox(height: 50)]),
            ),
          ),
        ),
      );
      final messages = [for (final e in errors) e.exceptionAsString()];
      final ours = messages.indexWhere(
        (m) => m.startsWith('The ConstraintLayout child #list'),
      );
      expect(ours, isNot(-1), reason: messages.join('\n---\n'));
      // Flutter reports the child's own failure first.
      expect(
        messages.take(ours),
        contains(startsWith('Vertical viewport was given unbounded height.')),
      );
      final error = errors[ours].exception as FlutterError;
      expect(
        error.diagnostics.first.toDescription(),
        'The ConstraintLayout child #list has no finite height after its '
        'layout under unbounded constraints.',
      );
      final text = _describe(error);
      expect(text, contains('The ConstraintLayout is unbounded vertically'));
      expect(text, contains('a vertical scroll view'));
      expect(text, contains('as Android measures a match_parent or'));
      expect(text, contains('Give the child a fixed height'));
      expect(text, contains("bound the ConstraintLayout's height"));
      expect(text, contains('shrinkWrap: true'));
    });

    testWidgets('a shrink-wrapping ListView sizes itself there', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scrolling(
          Constrained(
            id: #list,
            left: .leftOf(parent),
            top: .topOf(parent),
            width: .fixed(100),
            height: .matchParent,
            child: ListView(
              shrinkWrap: true,
              children: const [SizedBox(height: 50), SizedBox(height: 30)],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(ConstraintLayout)),
        const Size(400, 80),
      );
    });

    testWidgets('a child that takes an infinite size fails loudly', (
      tester,
    ) async {
      // An unbounded width measured for a wrapContent child, which takes all
      // the room it is given.
      final errors = await _collectErrors(
        () => tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                height: 100,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstraintLayout(
                    children: [
                      Constrained(
                        id: #wide,
                        left: .leftOf(parent),
                        top: .topOf(parent),
                        child: const _Expanding(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final ours = [
        for (final e in errors)
          if (e.exception case final FlutterError error
              when error.diagnostics.first.toDescription().startsWith(
                'The ConstraintLayout child #wide',
              ))
            error,
      ];
      expect(ours, isNotEmpty, reason: errors.join('\n---\n'));
      expect(
        ours.first.diagnostics.first.toDescription(),
        'The ConstraintLayout child #wide has no finite width after its '
        'layout under unbounded constraints.',
      );
      final text = _describe(ours.first);
      expect(text, contains('The ConstraintLayout is unbounded horizontally'));
      expect(text, contains('it took an infinite width'));
      expect(text, contains('Give the child a fixed width'));
    });

    testWidgets('a child whose own layout fails under bounded constraints '
        'gets an error without the unbounded cause', (tester) async {
      final errors = await _collectErrors(
        () => _pump(tester, BoxConstraints.tight(const Size(400, 100)), [
          Constrained(
            id: #bad,
            left: .leftOf(parent),
            top: .topOf(parent),
            child: const _Failing(),
          ),
        ]),
      );
      final messages = [for (final e in errors) e.exceptionAsString()];
      final ours = messages.indexWhere(
        (m) => m.startsWith('The ConstraintLayout child #bad'),
      );
      expect(ours, isNot(-1), reason: messages.join('\n---\n'));
      expect(
        messages.take(ours),
        contains(contains('a failing layout')),
        reason: "Flutter reports the child's own failure first",
      );
      final error = errors[ours].exception as FlutterError;
      expect(
        error.diagnostics.first.toDescription(),
        'The ConstraintLayout child #bad has no finite size after its layout '
        'under BoxConstraints(0.0<=w<=400.0, 0.0<=h<=100.0).',
      );
      expect(_describe(error), isNot(contains('unbounded')));
    });

    testWidgets('a dry query measures it at its minimum instead', (
      tester,
    ) async {
      // A query must not throw, so the error a layout gives such a child does
      // not apply: the expanding child measures 0 wide on the unbounded axis,
      // as its intrinsic size.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstraintLayout(
              children: [
                Constrained(
                  id: #wide,
                  left: .leftOf(parent),
                  top: .topOf(parent),
                  child: const _Expanding(),
                ),
                Constrained(
                  id: #box,
                  left: .rightOf(#wide),
                  top: .topOf(parent),
                  child: const _Content.box(30, 20),
                ),
              ],
            ),
          ),
        ),
      );
      final ro = tester.renderObject<RenderConstraintLayout>(
        find.byType(ConstraintLayout),
      );
      expect(ro.getMaxIntrinsicWidth(20), 30);
      expect(ro.getDryLayout(const BoxConstraints(maxHeight: 20)).width, 30);
      expect(tester.takeException(), isNull);
    });
  });

  group('the requests of measure-order layouts are Android\'s', () {
    for (final bounded in [true, false]) {
      final label = bounded ? 'bounded height' : 'unbounded height';
      final heightSpec = bounded ? 'A600' : 'U0';
      final constraints = bounded
          ? BoxConstraints.tight(const Size(340, 600))
          : BoxConstraints.tightFor(width: 340);

      testWidgets('match-constraint width, wrapping text ($label)', (
        tester,
      ) async {
        // Java J257: t (20, 0) 300 x 40 in a root 340 x 600 (bounded) or
        // 340 x 40 (VOpDriver view, p4b:order_b and p4b:order_u: MC x WRAP
        // between margins of 20, text 600 / 20, baseline 15). Direct resolves
        // the width, so the first measure is already at 300.
        await _pump(tester, constraints, [
          Constrained(
            id: #t,
            left: .leftOf(parent, margin: 20),
            right: .rightOf(parent, margin: 20),
            top: .topOf(parent),
            width: .matchConstraint,
            child: const _Content.text(600, 20, baseline: 15),
          ),
        ]);
        expect(
          _geometry(tester, ['t']),
          'root 340 x ${bounded ? 600 : 40} | t: (20, 0) 300 x 40',
        );
        expect(
          _transcript(tester),
          'P:t:0:FW:300,0:E300/$heightSpec:300,40,15,11 '
          '${bounded ? 'R:t:1:MW:300,40:c:300,40,15,00' : 'R:t:1:MW:300,40:E300/U0:300,40,15,10'}',
        );
      });

      testWidgets('constrainedWrap width, measured again when capped ($label)', (
        tester,
      ) async {
        // Java J257: t (60, 0) 220 x 60 in a root 340 x 600 (bounded) or
        // 340 x 60 (VOpDriver view, p4b:cwrap_b and p4b:cwrap_u: WRAP-default
        // MC width between margins of 60, text 600 / 20). Measured for its
        // content at A340 (2 lines), capped at 220 and measured again there
        // (3 lines).
        await _pump(tester, constraints, [
          Constrained(
            id: #t,
            left: .leftOf(parent, margin: 60),
            right: .rightOf(parent, margin: 60),
            top: .topOf(parent),
            width: .constrainedWrap(),
            child: const _Content.text(600, 20, baseline: 15),
          ),
        ]);
        expect(
          _geometry(tester, ['t']),
          'root 340 x ${bounded ? 600 : 60} | t: (60, 0) 220 x 60',
        );
        expect(
          _transcript(tester),
          'M:t:0:MW:0,0:A340/$heightSpec:340,40,15,11 '
          'R:t:1:MW:220,40:E220/$heightSpec:220,60,15,11 '
          '${bounded ? 'R:t:2:MW:220,60:c:220,60,15,10' : 'R:t:2:MW:220,60:E220/U0:220,60,15,10'}',
        );
      });

      testWidgets('a bottom barrier under two wrapping columns ($label)', (
        tester,
      ) async {
        // Java J257: a (16, 0) 288 x 80, b (336, 0) 288 x 20, bar (0, 80)
        // 0 x 0, f (0, 80) 10 x 10, root 640 x 600 (bounded) or 640 x 90
        // (VOpDriver view, p4b:barrier_b and p4b:barrier_u: a center
        // guideline, MC columns of text 900 / 20 and 90 / 20, a bottom
        // barrier over both, a follower below it). The guideline and the
        // barrier are GONE helpers, 0 x 0 at their position.
        final bigger = bounded
            ? BoxConstraints.tight(const Size(640, 600))
            : BoxConstraints.tightFor(width: 640);
        await _pump(tester, bigger, [
          const Guideline.vertical(id: #mid, percent: 0.5),
          Constrained(
            id: #a,
            left: .leftOf(parent, margin: 16),
            right: .leftOf(#mid, margin: 16),
            top: .topOf(parent),
            width: .matchConstraint,
            child: const _Content.text(900, 20, baseline: 15),
          ),
          Constrained(
            id: #b,
            left: .rightOf(#mid, margin: 16),
            right: .rightOf(parent, margin: 16),
            top: .topOf(parent),
            width: .matchConstraint,
            child: const _Content.text(90, 20, baseline: 15),
          ),
          const Barrier(id: #bar, edge: .bottom, referenced: [#a, #b]),
          Constrained(
            id: #f,
            top: .bottomOf(#bar),
            left: .leftOf(parent),
            width: .fixed(10),
            height: .fixed(10),
            child: const _Content.box(10, 10),
          ),
        ]);
        expect(
          _geometry(tester, ['mid', 'a', 'b', 'bar', 'f']),
          'root 640 x ${bounded ? 600 : 90} | mid: (320, 0) 0 x 0 | '
          'a: (16, 0) 288 x 80 | b: (336, 0) 288 x 20 | bar: (0, 80) 0 x 0 | '
          'f: (0, 80) 10 x 10',
        );
        final h = bounded ? 'A600' : 'U0';
        expect(
          _transcript(tester),
          'M:f:0:FF:10,10:E10/E10:10,10,-1,00 '
          'P:a:0:FW:288,0:E288/$h:288,80,15,11 '
          'P:b:0:FW:288,0:E288/$h:288,20,15,11 '
          'R:a:1:MW:288,80:c:288,80,15,00 '
          'R:b:1:MW:288,20:c:288,20,15,00',
        );
      });
    }
  });

  group('dry queries', () {
    testWidgets(
      'do not ask a child that cannot compute a dry baseline for one',
      (tester) async {
        // A RotatedBox has no dry baseline: asked for one in a debug build it
        // throws, and Flutter leaves it unusable. Under IntrinsicHeight the
        // layout's intrinsic height is asked before the child is ever laid
        // out, and must not ask it.
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: IntrinsicHeight(
                  child: ConstraintLayout(
                    children: [
                      Constrained(
                        id: #turned,
                        left: .leftOf(parent),
                        top: .topOf(parent),
                        child: const RotatedBox(
                          quarterTurns: 1,
                          child: SizedBox(width: 40, height: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(ConstraintLayout)),
          const Size(300, 40),
        );
        // Laid out again, and asked again: still nothing to report.
        final ro = tester.renderObject<RenderConstraintLayout>(
          find.byType(ConstraintLayout),
        );
        ro.markNeedsLayout();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'once the children are laid out, a dry layout reads the baselines the '
      'layout read and resolves as it does',
      (tester) async {
        // Java J257: root 428 x 423, m0 (0, 59) 0 x 126, m1 (24, 292) 49 x
        // 22, m2 (140, 314) 141 x 108, m3 (0, 423) 416 x 0 (VOpDriver view,
        // FL T-measure:500000097, whose op list this is). The texts' baselines
        // give their widgets baseline variables early in the solver, which
        // decides this degenerate wrap height: without them it resolves 229
        // tall. The layout reads every child's baseline, as Android does, and
        // a dry layout after it reads the baselines the layout found.
        const constraints = BoxConstraints(minWidth: 428, maxWidth: 428);
        await _pump(tester, constraints, [
          Constrained(
            id: #m0,
            left: .leftOf(parent),
            top: .topOf(parent, margin: 59),
            width: .matchConstraint,
            height: .matchConstraint,
            child: const _Content.box(301, 126),
          ),
          Constrained(
            id: #m1,
            left: .leftOf(parent, margin: 24),
            right: .rightOf(parent, margin: 16),
            top: .bottomOf(#m0, margin: 3),
            bottom: .bottomOf(parent, margin: 5),
            width: .spread(min: 108, max: 49),
            height: .spread(min: 36, max: 22),
            child: const _Content.text(892, 16, baseline: 13),
          ),
          Constrained(
            id: #m2,
            left: .leftOf(parent, margin: 2),
            right: .rightOf(parent, margin: 10),
            top: .bottomOf(#m1),
            width: .spread(min: 116, max: 141),
            child: const _Content.text(811, 18, baseline: 14),
          ),
          Constrained(
            id: #m3,
            left: .leftOf(parent),
            right: .rightOf(parent, margin: 12),
            top: .bottomOf(#m2, margin: 1),
            bottom: .bottomOf(parent),
            width: .matchConstraint,
            height: .matchConstraint,
            child: const _Content.text(235, 20, baseline: 14),
          ),
        ]);
        expect(
          _geometry(tester, ['m0', 'm1', 'm2', 'm3']),
          'root 428 x 423 | m0: (0, 59) 0 x 126 | m1: (24, 292) 49 x 22 | '
          'm2: (140, 314) 141 x 108 | m3: (0, 423) 416 x 0',
        );
        final ro = tester.renderObject<RenderConstraintLayout>(
          find.byType(ConstraintLayout),
        );
        expect(ro.getDryLayout(constraints), ro.size);
      },
    );
  });
}

/// Pumps a ConstraintLayout of [children] under [constraints], as the parity
/// harness builds a probe: Directionality, Align top-left, and an OverflowBox
/// that gives the layout exactly [constraints].
Future<void> _pump(
  WidgetTester tester,
  BoxConstraints constraints,
  List<Widget> children,
) => tester.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
        minHeight: constraints.minHeight,
        maxHeight: constraints.maxHeight,
        child: ConstraintLayout(children: children),
      ),
    ),
  ),
);

/// A ConstraintLayout of [child] in a vertical scroll view 400 x 600.
Widget _scrolling(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 400,
      height: 600,
      child: SingleChildScrollView(
        child: ConstraintLayout(children: [child]),
      ),
    ),
  ),
);

/// Runs [body] with every reported Flutter error collected instead of
/// failing the test, and returns them in report order.
Future<List<FlutterErrorDetails>> _collectErrors(
  Future<void> Function() body,
) async {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

/// The text of every part of [error], one part per line, unwrapped.
String _describe(FlutterError error) => [
  for (final part in error.diagnostics) part.toDescription(),
].join('\n');

/// The frames of the laid-out ConstraintLayout in the parity geometry format
/// (FORMATS 2): the root's size, then each child, in child order, under the
/// name in [names], as `(x, y) w x h`, or as `gone, w x h` when [gone] holds
/// its name.
String _geometry(
  WidgetTester tester,
  List<String> names, {
  Set<String> gone = const {},
}) {
  final ro = tester.renderObject<RenderConstraintLayout>(
    find.byType(ConstraintLayout),
  );
  String n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  final children = ro.getChildrenAsList();
  expect(children, hasLength(names.length), reason: 'one name per child');
  final sb = StringBuffer('root ${n(ro.size.width)} x ${n(ro.size.height)}');
  for (var i = 0; i < children.length; i++) {
    final child = children[i];
    final offset = (child.parentData! as BoxParentData).offset;
    final size = '${n(child.size.width)} x ${n(child.size.height)}';
    sb.write(' | ${names[i]}: ');
    sb.write(
      gone.contains(names[i])
          ? 'gone, $size'
          : '(${n(offset.dx)}, ${n(offset.dy)}) $size',
    );
  }
  return sb.toString();
}

/// The request transcript of the layout's last full run (the T field of the
/// parity oracle).
String _transcript(WidgetTester tester) => tester
    .renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout))
    .debugViewHost!
    .measurer
    .transcript
    .toString();

/// A leaf whose size and baseline follow a content op of the parity corpora
/// (FORMATS 6.2), as the harness's ContentModelBox does: a box is [width] x
/// [height]; a text is [width] wide on one line and [height] per line, so at
/// a width w it is `height * ceil(width / w)` tall (`height * 50` at a width
/// of 0). [baseline] is null for none. [log], when given, receives the
/// constraints of every layout the leaf is given.
class _Content extends LeafRenderObjectWidget {
  const _Content.box(this.width, this.height, {this.baseline, this.log})
    : text = false;

  const _Content.text(this.width, this.height, {this.baseline, this.log})
    : text = true;

  final double width;
  final double height;
  final bool text;
  final double? baseline;
  final List<BoxConstraints>? log;

  @override
  _RenderContent createRenderObject(BuildContext context) =>
      _RenderContent(this);

  @override
  void updateRenderObject(BuildContext context, _RenderContent renderObject) {
    renderObject.content = this;
  }
}

class _RenderContent extends RenderBox {
  _RenderContent(this._content);

  _Content _content;

  set content(_Content value) {
    _content = value;
    markNeedsLayout();
  }

  double _heightAt(double width) {
    if (!_content.text) return _content.height;
    if (width <= 0) return _content.height * 50;
    return _content.height * (_content.width / width).ceil();
  }

  Size _sizeFor(BoxConstraints constraints) {
    final width = constraints.constrainWidth(_content.width);
    return Size(width, constraints.constrainHeight(_heightAt(width)));
  }

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    _content.log?.add(constraints as BoxConstraints);
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  @override
  void performLayout() {
    size = _sizeFor(constraints);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _sizeFor(constraints);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _content.baseline;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) => _content.baseline;

  @override
  double computeMinIntrinsicWidth(double height) => _content.width;

  @override
  double computeMaxIntrinsicWidth(double height) => _content.width;

  @override
  double computeMinIntrinsicHeight(double width) => _heightAt(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _heightAt(width);
}

/// A leaf whose layout always throws, so it never has a size.
class _Failing extends LeafRenderObjectWidget {
  const _Failing();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFailing();
}

class _RenderFailing extends RenderBox {
  @override
  void performLayout() {
    throw StateError('a failing layout');
  }
}

/// A leaf that takes all the room its constraints give it, even an infinite
/// extent, and whose dry layout says the same.
class _Expanding extends LeafRenderObjectWidget {
  const _Expanding();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderExpanding();
}

class _RenderExpanding extends RenderBox {
  @override
  void performLayout() {
    size = constraints.biggest;
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.biggest;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) => null;

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;
}
