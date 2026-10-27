// `.percent(f, min:)` with the min above `f * parent`, at
// OPTIMIZATION_STANDARD (257) and at level 0.
//
// Direct never resolves a percent axis: it is neither measurable nor a
// spread match constraint (Direct.java 815-862, 386-398). The axis goes to
// the float solver, which builds Android's infeasible system, a hard percent
// row against the min's row, and keeps what enforceBFS and optimize leave.
// With two links that fills the space between them; the dependency graph's
// "keep the min, centered" (what the engine's earlier graph-first design
// gave, cited per test as `graph-first`) is not what Android does.
//
// Expected strings are the pinned oracle's, byte for byte (VOpDriver v2,
// -XX:hashCode=2, levels 257,0), and equal at both levels, as Direct takes no
// part: two minimal repros on the core path, ids `pctmin:one` and
// `pctmin:bias`, whose op lists are the ones below, run through
// tool/parity/java/jrun.sh; and layouts of the T2-pctmin family on the view
// path, ids as cited, from T2.java, which tool/parity/gates/java_refs.sh
// writes for the corpus T2.in.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/echo_measurer.dart';
import 'support/op_replay.dart';

/// Replays [ops] at 257 and at level 0 on the core path, or on the view path
/// when [view], and expects Java's geometry, [java], at both levels.
void _expectJava(String ops, String java, {bool view = false}) {
  for (final level in const [257, 0]) {
    final result = view
        ? replayView(ops, level: level)
        : replayCore(ops, level: level);
    expect(result.status, 'ok', reason: 'level $level');
    expect(result.geometry, equals(java), reason: 'Java J$level');
  }
}

void main() {
  group('minimal repros, core path', () {
    // pctmin:one
    test(
      'a min above the percent of the parent, two links: a fills the links, '
      '(0) 400',
      () {
        _expectJava(
          'R 400 300;w a 10 20;add a;hb a M;vb a F;hm a 2 300 0 0.5;'
              'c a L root L 0;c a R root R 0;c a T root T 0',
          'root 400 x 300 | a: (0, 0) 400 x 20',
        );
      },
    );

    // pctmin:bias
    test(
      'with bias 0.3 and margins 10 and 20: a fills the links, (10) 370',
      () {
        _expectJava(
          'R 400 300;w a 10 20;add a;hb a M;vb a F;hm a 2 300 0 0.5;'
              'hx a 0.3;c a L root L 10;c a R root R 20;c a T root T 0',
          'root 400 x 300 | a: (10, 0) 370 x 20',
        );
      },
    );
  });

  test(
    'Direct leaves the percent axis to the solver: after measure(257) its '
    'anchors hold no final value, while the fixed axis has Direct\'s',
    () {
      // pctmin:one built with the engine API. Java's D257 dump (taken after
      // Direct and the post-Direct measures) is `a:-v:_,0,_,20,_:300x20`.
      final root = ConstraintWidgetContainer.rect(0, 0, 400, 300)
        ..setDebugName('root');
      final a = ConstraintWidget.sizeNamed('a', 10, 20);
      root.add(a);
      a
        ..setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint)
        ..setVerticalDimensionBehaviour(DimensionBehaviour.fixed)
        ..setHorizontalMatchStyle(
          ConstraintWidget.MATCH_CONSTRAINT_PERCENT,
          300,
          0,
          0.5,
        )
        ..connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left)
        ..connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right)
        ..connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      root
        ..setMeasurer(const EchoMeasurer())
        ..setOptimizationLevel(Optimizer.OPTIMIZATION_STANDARD)
        ..measure(
          Optimizer.OPTIMIZATION_STANDARD,
          BasicMeasure.EXACTLY,
          400,
          BasicMeasure.EXACTLY,
          300,
          0,
          0,
          0,
          0,
        );
      expect(a.mLeft.hasFinalValue(), isFalse);
      expect(a.mRight.hasFinalValue(), isFalse);
      expect(a.mTop.hasFinalValue(), isTrue);
      expect(a.mTop.getFinalValue(), 0);
      expect(a.mBottom.getFinalValue(), 20);
      expect(
        [a.getX(), a.getY(), a.getWidth(), a.getHeight()],
        [0, 0, 400, 20],
      );
    },
  );

  group('the T2-pctmin family, view path', () {
    // T2-pctmin:500004599; graph-first: p0 (92, 0) 225 x 14
    test(
      'two links, min 225 above 0.2 of 411: p0 fills (0) 408 wide',
      () {
        _expectJava(
          'R 411 667;w p0 0 0;ct p0 text 62 14 11;add p0;hb p0 M;vb p0 W;'
              'hm p0 2 225 0 0.2;c p0 L root L 0;c p0 R root R 3;'
              'c p0 T root T 0;ltr;fixw;fixh;cw 411;ch 667;adeps',
          'root 411 x 667 | p0: (0, 0) 408 x 14',
          view: true,
        );
      },
    );

    // T2-pctmin:500003673; graph-first: p0 (193, 0) 423 x 20
    test(
      'two links and a margin, min 423 above 0.5 of 800: p0 fills (8) 792 wide',
      () {
        _expectJava(
          'R 800 844;w p0 0 0;ct p0 text 147 20 16;add p0;hb p0 M;vb p0 W;'
              'hm p0 2 423 0 0.5;c p0 L root L 8;c p0 R root R 0;'
              'c p0 T root T 0;ltr;fixw;fixh;cw 800;ch 844;adeps',
          'root 800 x 844 | p0: (8, 0) 792 x 20',
          view: true,
        );
      },
    );

    // T2-pctmin:500012784; graph-first: p0 (0, 198) 393 x 269
    test(
      'a percent height, min 269 above 0.3 of 663: p0 fills (1) 662 high',
      () {
        _expectJava(
          'R 393 663;w p0 0 0;ct p0 text 449 15 11;add p0;hb p0 W;vb p0 M;'
              'vm p0 2 269 0 0.3;c p0 L root L 0;c p0 T root T 1;'
              'c p0 B root B 0;ltr;fixw;fixh;cw 393;ch 663;adeps',
          'root 393 x 663 | p0: (0, 1) 393 x 662',
          view: true,
        );
      },
    );

    // T2-pctmin:500010541; graph-first: p0 (130, 0) 165 x 21
    test(
      'a min below the percent: the percent holds, 0.4 of 412 is 164.8, '
      'centered at 129.6, and the edges read back as (130) 164 wide',
      () {
        _expectJava(
          'R 412 736;w p0 0 0;ct p0 text 40 21 15;add p0;hb p0 M;vb p0 W;'
              'hm p0 2 99 0 0.4;c p0 L root L 12;c p0 R root R 0;'
              'c p0 T root T 0;ltr;fixw;fixh;cw 412;ch 736;adeps',
          'root 412 x 736 | p0: (130, 0) 164 x 21',
          view: true,
        );
      },
    );

    // T2-pctmin:500029978; graph-first: p0 (-73, 7) 448 x 20
    test(
      'one link, min 448 above 0.8 of 375: p0 keeps the min from its right '
      'edge, the negative left edge reads back one pixel in, (-72) 447 wide',
      () {
        _expectJava(
          'R 375 916;w p0 0 0;ct p0 text 60 20 14;add p0;hb p0 M;vb p0 W;'
              'hm p0 2 448 559 0.8;c p0 R root R 0;c p0 T root T 7;ltr;fixw;'
              'fixh;cw 375;ch 916;adeps',
          'root 375 x 916 | p0: (-72, 7) 447 x 20',
          view: true,
        );
      },
    );

    // T2-pctmin:500035214; graph-first: p0 (-48, 1) 454 x 28
    test(
      'one link to a gone widget, min 454 above 0.8 of 411: (-47) 453 wide',
      () {
        _expectJava(
          'R 411 1016;w aR 61 48;ct aR box 61 48 -1;add aR;w p0 0 0;'
              'ct p0 text 77 28 22;add p0;hb aR F;vb aR F;v aR 8;'
              'c aR R root R 1;c aR B root B 5;hb p0 M;vb p0 W;'
              'hm p0 2 454 0 0.8;c p0 R aR L 5;c p0 T root T 1;ltr;fixw;fixh;'
              'cw 411;ch 1016;adeps',
          'root 411 x 1016 | aR: gone, 0 x 0 | p0: (-47, 1) 453 x 28',
          view: true,
        );
      },
    );

    // T2-pctmin:500015399; graph-first: root 247 wide, below 250 wide
    test(
      'a wrap-content parent in RTL, percent on both axes: the root wraps to '
      '246',
      () {
        _expectJava(
          'R 412 1024;rtl;wrapw;w aL 12 24;ct aL box 12 24 -1;add aL;'
              'w p0 0 0;ct p0 text 370 15 12;add p0;w below 0 0;'
              'ct below text 251 14 11;add below;hb aL F;vb aL F;'
              'c aL L root L 0;c aL T root T 5;hb p0 M;vb p0 M;'
              'hm p0 2 1 0 0.15;vm p0 2 577 0 0.45;c p0 R aL L 7;'
              'c p0 L aL R 24;c p0 B root B 0;hb below W;vb below W;'
              'c below L p0 L 0;c below T p0 B 10;rtl;wrapw;fixh;cw 0;ch 1024;'
              'adeps',
          'root 246 x 1024 | aL: (0, 5) 12 x 24 | p0: (-3, 447) 36 x 577 | '
              'below: (-3, 1034) 249 x 14',
          view: true,
        );
      },
    );

    // T2-pctmin:500024184; graph-first: p0 (-67, 7) 489 x 21
    test(
      'RTL, one link, a min of 529 above a max of 489: the max wins, 489 from '
      'the right edge, and the negative left edge reads back as (-66) 488 wide',
      () {
        _expectJava(
          'R 430 751;rtl;w p0 0 0;ct p0 text 90 21 16;add p0;hb p0 M;'
              'vb p0 W;hm p0 2 529 489 0.8;c p0 R root R 8;c p0 T root T 7;rtl;'
              'fixw;fixh;cw 430;ch 751;adeps',
          'root 430 x 751 | p0: (-66, 7) 488 x 21',
          view: true,
        );
      },
    );
  });
}
