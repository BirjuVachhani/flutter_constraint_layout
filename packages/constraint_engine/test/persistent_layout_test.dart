// A layout laid out again in the same container after a change, against
// Android's live views and against a freshly built one with the final
// configuration. ViewHost, Android's onMeasure and the Flutter adapter's
// entry, takes Android's dirty path before each measure: every child's
// measure state reset as ConstraintWidget.reset() resets it, which keeps the
// resolved flags and the dependency graph's runs and nodes. So a layout laid
// out again carries what Android's does: at the levels without
// OPTIMIZATION_DIRECT a barrier's resolved flag, and at the OPTIMIZATION_GRAPH
// levels what the last graph left in its runs and nodes (a gone widget's
// behaviour, a node's margin dependency, a run's type).
//
// Each scenario is an op list on the view path (test/support/op_replay.dart):
// the first configuration, measured (`L`), then the change; the fresh build
// is the final configuration alone. The in-place frames are Android's own:
// the RoboOracle (the ConstraintLayout 2.2.1 view layer under Robolectric
// 4.16, FORMATS.md 10) applies the same op list to live views with
// -Drobo.inplace=1 (every state's LayoutParams set again, so every measure
// takes the dirty path) at each level of [_levels], and gives the fresh
// build's frames wherever a scenario names no others. The fresh builds'
// frames are also checked against the pinned oracle (VOpDriver v2, view
// path, -XX:hashCode=2) at OPTIMIZATION_STANDARD (257) and at
// OPTIMIZATION_STANDARD | OPTIMIZATION_GRAPH (321). Java's own in-place
// re-measure is not the reference: VOpDriver measures again without the
// dirty hierarchy.

import 'package:test/test.dart';

import 'support/op_replay.dart';

/// The levels every in-place sequence is checked at: none, standard,
/// CACHE_MEASURES alone, and the dependency-graph levels with and without the
/// wrap computation.
const _levels = [0, 257, 256, 64, 321, 192, 449];

/// A representative screen: a pinned corner widget, a centered widget with
/// [bias], a match-constraint fill along the bottom, and a widget stacked
/// below the pinned one.
String _screen(
  int width,
  int height, {
  int margin = 10,
  String bias = '0.5',
  bool goneFill = false,
}) => [
  'R $width $height',
  'w pinned 100 40',
  'ct pinned box 100 40 -1',
  'add pinned',
  'c pinned L root L $margin',
  'c pinned T root T $margin',
  'w centered 80 30',
  'ct centered box 80 30 -1',
  'add centered',
  'c centered L root L 0',
  'c centered R root R 0',
  'c centered T root T 0',
  'c centered B root B 0',
  'hx centered $bias',
  'w fill 0 24',
  'ct fill box 0 24 -1',
  'add fill',
  'hb fill M',
  'c fill L root L 16',
  'c fill R root R 16',
  'c fill B root B 8',
  if (goneFill) 'v fill 8',
  'w below 60 60',
  'ct below box 60 60 -1',
  'add below',
  'c below L pinned L 0',
  'c below T pinned B 12',
].join(';');

/// A horizontal spread chain of three widgets over a widget anchored to a
/// horizontal guideline at 75 percent.
String _chainAndGuideline(int width, int height) => [
  'R $width $height',
  for (final n in ['a', 'b', 'c']) ...[
    'w $n 60 20',
    'ct $n box 60 20 -1',
    'add $n',
  ],
  'c a L root L 4',
  'c a R b L 0',
  'c b L a R 0',
  'c b R c L 0',
  'c c L b R 0',
  'c c R root R 4',
  'c a T root T 10',
  'c b T root T 10',
  'c c T root T 10',
  'g guide',
  'go guide 0',
  'gp guide 0.75',
  'add guide',
  'w anchored 120 30',
  'ct anchored box 120 30 -1',
  'add anchored',
  'c anchored L root L 20',
  'c anchored T guide T 0',
].join(';');

/// A match-parent column centered horizontally, with `b` linked below it.
String _matchParentColumn({required bool gone}) => [
  'R 800 600',
  'w a 80 0',
  'ct a box 80 0 -1',
  'add a',
  'vb a P',
  'c a L root L 0',
  'c a R root R 0',
  'c a T root T 0',
  'c a B root B 0',
  if (gone) 'v a 8',
  'w b 50 50',
  'ct b box 50 50 -1',
  'add b',
  'c b L root L 0',
  'c b T a B 0',
].join(';');

/// A match-constraint width over a wrapped height, linked to the top and,
/// with [centered], to the bottom too.
String _centered({required bool centered}) => [
  'R 400 300',
  'w t 100 20',
  'ct t box 100 20 -1',
  'add t',
  'hb t M',
  'vb t W',
  'c t L root L 10',
  'c t R root R 10',
  'c t T root T 0',
  if (centered) 'c t B root B 0',
].join(';');

/// `v` on the baseline of `t`, a match-constraint fill with a baseline of
/// 17, which is [gone].
String _baselineSibling({required bool gone}) => [
  'R 400 300',
  'w t 100 22',
  'ct t box 100 22 17',
  'add t',
  'w v 60 20',
  'ct v box 60 20 15',
  'add v',
  'hbl t 1',
  'hbl v 1',
  'hb t M',
  'c t L root L 40',
  'c t R root R 140',
  'c t T root T 30',
  if (gone) 'v t 8',
  'c v R root R 8',
  'c v S t S 0',
].join(';');

/// A fresh build's op list: [config], then the dependents Android's view
/// layer registers (the oracle's `adeps`).
String _fresh(String config) => '$config;adeps';

/// [config] measured, then [changes] applied in place, each but the last
/// followed by a measure (the replay measures once more at the end). An
/// empty change measures again without one.
String _inPlace(String config, List<String> changes) => [
  config,
  'adeps',
  for (final change in changes) ...[
    'L',
    if (change.isNotEmpty) change,
    'adeps',
  ],
].join(';');

/// Android's NullPointerException in the graph ("Cannot read field
/// \"resolved\""), which the port throws as a failed null check: the
/// [_expectAndroid] value for a level at which the live views throw.
const _throws = 'EXC';

/// Checks that [inPlace] lays out as Android's live views lay it out at every
/// level of [_levels]: as [fresh] does, but at the levels [android] names,
/// which give the live views' frames there (or [_throws]); and that [fresh]
/// gives Java's frames: [j257] at OPTIMIZATION_STANDARD, [j321] (the same
/// when null) at 321, and [j449], when given, at 449.
void _expectAndroid(
  String inPlace,
  String fresh, {
  required String j257,
  String? j321,
  String? j449,
  Map<int, String> android = const {},
}) {
  for (final level in _levels) {
    final a = replayView(inPlace, level: level);
    final b = replayView(fresh, level: level);
    expect(b.status, 'ok', reason: 'fresh, level $level');
    final live = android[level];
    if (live == _throws) {
      expect(
        a.status,
        startsWith('EXC:Null check operator'),
        reason: 'in place, level $level',
      );
      continue;
    }
    expect(a.status, 'ok', reason: 'in place, level $level');
    expect(a.geometry, live ?? b.geometry, reason: 'in place, level $level');
  }
  expect(replayView(fresh).geometry, j257, reason: 'Java J257');
  expect(
    replayView(fresh, level: 321).geometry,
    j321 ?? j257,
    reason: 'Java J321',
  );
  if (j449 != null) {
    expect(replayView(fresh, level: 449).geometry, j449, reason: 'Java J449');
  }
}

void main() {
  group('a container laid out again', () {
    test('measured again without a change', () {
      final screen = _screen(800, 600);
      _expectAndroid(
        _inPlace(screen, ['', '']),
        _fresh(screen),
        j257:
            'root 800 x 600 | pinned: (10, 10) 100 x 40 | '
            'centered: (360, 285) 80 x 30 | fill: (16, 568) 768 x 24 | '
            'below: (10, 62) 60 x 60',
      );
    });

    test('after a resize', () {
      final screen = _screen(800, 600);
      final sizes = [(1000, 700), (640, 480), (800, 600)];
      final expected = [
        'root 1000 x 700 | pinned: (10, 10) 100 x 40 | '
            'centered: (460, 335) 80 x 30 | fill: (16, 668) 968 x 24 | '
            'below: (10, 62) 60 x 60',
        'root 640 x 480 | pinned: (10, 10) 100 x 40 | '
            'centered: (280, 225) 80 x 30 | fill: (16, 448) 608 x 24 | '
            'below: (10, 62) 60 x 60',
        'root 800 x 600 | pinned: (10, 10) 100 x 40 | '
            'centered: (360, 285) 80 x 30 | fill: (16, 568) 768 x 24 | '
            'below: (10, 62) 60 x 60',
      ];
      for (var i = 0; i < sizes.length; i++) {
        final steps = [
          for (final (w, h) in sizes.take(i + 1)) 'cspec E $w E $h',
        ];
        final (w, h) = sizes[i];
        _expectAndroid(
          _inPlace(screen, steps),
          _fresh(_screen(w, h)),
          j257: expected[i],
        );
      }
    });

    test('a chain and a percent guideline after a resize', () {
      final layout = _chainAndGuideline(800, 600);
      final sizes = [(500, 400), (1024, 768), (800, 600)];
      final expected = [
        'root 500 x 400 | a: (82, 10) 60 x 20 | b: (220, 10) 60 x 20 | '
            'c: (358, 10) 60 x 20 | guide: (0, 300) 0 x 0 | '
            'anchored: (20, 300) 120 x 30',
        'root 1024 x 768 | a: (213, 10) 60 x 20 | b: (482, 10) 60 x 20 | '
            'c: (751, 10) 60 x 20 | guide: (0, 576) 0 x 0 | '
            'anchored: (20, 576) 120 x 30',
        'root 800 x 600 | a: (157, 10) 60 x 20 | b: (370, 10) 60 x 20 | '
            'c: (583, 10) 60 x 20 | guide: (0, 450) 0 x 0 | '
            'anchored: (20, 450) 120 x 30',
      ];
      for (var i = 0; i < sizes.length; i++) {
        final steps = [
          for (final (w, h) in sizes.take(i + 1)) 'cspec E $w E $h',
        ];
        final (w, h) = sizes[i];
        _expectAndroid(
          _inPlace(layout, steps),
          _fresh(_chainAndGuideline(w, h)),
          j257: expected[i],
        );
      }
    });

    test('after a margin change', () {
      _expectAndroid(
        _inPlace(_screen(800, 600), [
          'c pinned L root L 42;c pinned T root T 42',
        ]),
        _fresh(_screen(800, 600, margin: 42)),
        j257:
            'root 800 x 600 | pinned: (42, 42) 100 x 40 | '
            'centered: (360, 285) 80 x 30 | fill: (16, 568) 768 x 24 | '
            'below: (42, 94) 60 x 60',
      );
    });

    test('after a bias change', () {
      _expectAndroid(
        _inPlace(_screen(800, 600), ['hx centered 0.25']),
        _fresh(_screen(800, 600, bias: '0.25')),
        j257:
            'root 800 x 600 | pinned: (10, 10) 100 x 40 | '
            'centered: (180, 285) 80 x 30 | fill: (16, 568) 768 x 24 | '
            'below: (10, 62) 60 x 60',
      );
    });

    test('after a widget turns gone, and visible again', () {
      _expectAndroid(
        _inPlace(_screen(800, 600), ['v fill 8']),
        _fresh(_screen(800, 600, goneFill: true)),
        j257:
            'root 800 x 600 | pinned: (10, 10) 100 x 40 | '
            'centered: (360, 285) 80 x 30 | fill: gone, 0 x 0 | '
            'below: (10, 62) 60 x 60',
      );
      _expectAndroid(
        _inPlace(_screen(800, 600), ['v fill 8', 'v fill 0;sh fill 24']),
        _fresh(_screen(800, 600)),
        j257:
            'root 800 x 600 | pinned: (10, 10) 100 x 40 | '
            'centered: (360, 285) 80 x 30 | fill: (16, 568) 768 x 24 | '
            'below: (10, 62) 60 x 60',
      );
    });

    // A gone widget skips DependencyGraph.basicMeasureWidgets, so its runs
    // keep the behaviour of the last graph (upstream's reset() leaves
    // mDimensionBehavior and matchConstraintsType): at the GRAPH levels the
    // gone column is still anchored as matchParent, to the container's
    // edges, and `b` sits at 600 where a fresh build puts it at 300.
    test('after a match-parent widget turns gone', () {
      const kept = 'root 800 x 600 | a: gone, 0 x 0 | b: (0, 600) 50 x 50';
      _expectAndroid(
        _inPlace(_matchParentColumn(gone: false), ['v a 8;sh a 0']),
        _fresh(_matchParentColumn(gone: true)),
        j257: 'root 800 x 600 | a: gone, 0 x 0 | b: (0, 300) 50 x 50',
        android: {64: kept, 321: kept, 192: kept, 449: kept},
      );
    });

    // Upstream's run reset() leaves the run type, and apply() sets it only
    // for a widget linked on both sides: at the GRAPH levels `t`'s vertical
    // run still updates as centered and reads the bottom link it no longer
    // has. The live views throw a NullPointerException in the graph at the
    // second measure, and so does the port.
    test('after a centered widget loses a link', () {
      _expectAndroid(
        _inPlace(_centered(centered: true), ['x t B']),
        _fresh(_centered(centered: false)),
        j257: 'root 400 x 300 | t: (10, 0) 380 x 20',
        android: {64: _throws, 321: _throws, 192: _throws, 449: _throws},
      );
    });

    // Upstream's DependencyNode.clear() leaves a node's margin dependency, so
    // at the GRAPH levels `v`'s top keeps computing its margin from `t`'s
    // last baseline: y = 2, where a fresh build gives -15 at the GRAPH levels
    // (Java J321, the graph places `v`) and -14 at 257 (the solver does).
    test('after the target of a baseline link turns gone', () {
      const kept = 'root 400 x 300 | t: gone, 0 x 0 | v: (332, 2) 60 x 20';
      _expectAndroid(
        _inPlace(_baselineSibling(gone: false), ['v t 8']),
        _fresh(_baselineSibling(gone: true)),
        j257: 'root 400 x 300 | t: gone, 0 x 0 | v: (332, -14) 60 x 20',
        j321: 'root 400 x 300 | t: gone, 0 x 0 | v: (332, -15) 60 x 20',
        android: {64: kept, 321: kept, 192: kept, 449: kept},
      );
    });

    // At the GRAPH_WRAP levels with an unbounded height, the graph is wired
    // before DependencyGraph.basicMeasureWidgets turns r1's spread height
    // into a ratio one (as upstream's does). Android sets the match styles
    // from the layout params again on every measure; without
    // ConstraintWidget.resetMeasureState's restore of the configured mode,
    // the second measure wired the ratio from the start: r1 339 px tall.
    test('a ratio widget measured again at the GRAPH_WRAP levels', () {
      final layout = [
        'R 320 1164',
        'wraph',
        'w r0 0 70',
        'ct r0 box 214 70 -1',
        'add r0',
        'w r1 0 0',
        'ct r1 box 254 33 -1',
        'add r1',
        'hb r0 M',
        'vb r0 F',
        'hm r0 0 0 0 1.0',
        'ra r0 0.5 -1',
        'c r0 L root L 8',
        'c r0 R root R 10',
        'c r0 T root T 3',
        'hb r1 W',
        'vb r1 M',
        'vm r1 0 0 0 1.0',
        'ra r1 0.75 1',
        'c r1 L root L 10',
        'c r1 T r0 B 12',
      ].join(';');
      _expectAndroid(
        _inPlace(layout, ['']),
        _fresh(layout),
        j257: 'root 320 x 275 | r0: (142, 3) 35 x 70 | r1: (10, 85) 254 x 190',
        j449: 'root 320 x 276 | r0: (142, 3) 35 x 70 | r1: (10, 85) 254 x 191',
      );
    });

    test('a barrier that counts no reference', () {
      // A right barrier whose only reference is gone, without
      // allowsGoneWidget, sits at its margin, -8, which the solver reports
      // as -7. allSolved resolves it in the first measure and sets its flag,
      // which only the Direct pass clears: without OPTIMIZATION_DIRECT every
      // later measure leaves it at the 0 reset() gave it (setFinalHorizontal
      // returns at once), and `t` follows it.
      const kept =
          'root 300 x 200 | bar: (0, 0) 0 x 0 | v: gone, 0 x 0 | '
          't: (0, 10) 288 x 20';
      final layout = [
        'R 300 200',
        'rtl',
        'b bar',
        'bt bar 1',
        'bg bar 0',
        'bm bar -8',
        'add bar',
        'w v 40 20',
        'ct v box 40 20 -1',
        'add v',
        'w t 100 20',
        'ct t box 100 20 -1',
        'add t',
        'ref bar v',
        'v v 8',
        'c v L root L 16',
        'hb t M',
        'c t L bar R 0',
        'c t R root R 12',
        'c t T root T 10',
      ].join(';');
      _expectAndroid(
        _inPlace(layout, ['', '', '']),
        _fresh(layout),
        j257:
            'root 300 x 200 | bar: (-7, 0) 0 x 0 | v: gone, 0 x 0 | '
            't: (-7, 10) 295 x 20',
        android: {0: kept, 256: kept, 64: kept, 192: kept},
      );
    });

    test('a wrap-content root keeps its size', () {
      final layout = [
        'R 800 0',
        'wraph',
        'w a 100 40',
        'ct a box 100 40 -1',
        'add a',
        'c a L root L 10',
        'c a T root T 10',
        'w b 100 40',
        'ct b box 100 40 -1',
        'add b',
        'c b L a L 0',
        'c b T a B 6',
      ].join(';');
      _expectAndroid(
        _inPlace(layout, ['', '']),
        _fresh(layout),
        j257: 'root 800 x 96 | a: (10, 10) 100 x 40 | b: (10, 56) 100 x 40',
      );
    });
  });
}
