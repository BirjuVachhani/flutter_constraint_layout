// Where the dependency graph puts the members of a chain that is not packed
// against one end.
//
// The solver places every member edge at its exact position and reports it
// as (int) (value + 0.5). Upstream's ChainRun, which this engine's graph
// ports, rounded each gap and each match-constraint size first and added the
// rounded values up: two match-constraint members of a 375 px layout came
// out 188 px each, overflowing it by 1 px, and five fixed members of a spread
// chain could end 4 px short of where the solver puts them. Upstream never
// runs its graph on a chain (BasicMeasure.solverMeasure turns the graph off
// for any layout with one), so Android always shows the solver's result. The
// expected values are upstream's Java engine at the pinned commit (see
// UPSTREAM.md) at OPTIMIZATION_STANDARD, Android's default; its own graph,
// run directly, gives the old values.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/solver_parity.dart';

/// A horizontal chain of [widths.length] members across a [width] x 600
/// container: fixed members of [widths], or match-constraint ones with
/// [match], in [style], with [outer] margins against the container and
/// [inner] margins between the members, in a right-to-left container with
/// [rtl].
LayoutBuilder chain({
  required int width,
  required List<int> widths,
  bool match = false,
  List<double>? weights,
  int style = ConstraintWidget.CHAIN_SPREAD,
  int outer = 0,
  int inner = 0,
  bool rtl = false,
}) => (root) {
  root.setWidth(width);
  root.setRtl(rtl);
  final members = [
    for (final (i, w) in widths.indexed)
      ConstraintWidget.sizeNamed(String.fromCharCode(0x61 + i), w, 40),
  ];
  root.addAll(members);
  for (final (i, member) in members.indexed) {
    if (match) {
      member.setHorizontalDimensionBehaviour(.matchConstraint);
    }
    if (weights != null) {
      member.setHorizontalWeight(weights[i]);
    }
    member.setHorizontalChainStyle(style);
    member.connect(.top, root, .top);
    if (i == 0) {
      member.connect(.left, root, .left, outer);
    } else {
      member.connect(.left, members[i - 1], .right);
      members[i - 1].connect(.right, member, .left, inner);
    }
  }
  members.last.connect(.right, root, .right, outer);
};

/// Lays [build] out graph first and on the solver; checks that the graph
/// resolved it, as the solver does, and returns each member's
/// `x + width`.
List<String> layOut(LayoutBuilder build) {
  final pass = layoutBothWays(build).single;
  expect(pass.graphResolved, isTrue);
  expect(pass.differences, isEmpty);
  final root = SolveCountingContainer(800, 600);
  build(root);
  root.layout();
  return [for (final w in root.getChildren()) '${w.getX()} + ${w.getWidth()}'];
}

void main() {
  group('chain rounding', () {
    for (final rtl in [false, true]) {
      final direction = rtl ? 'right to left' : 'left to right';

      test('two match-constraint members share 375 px, $direction', () {
        expect(
          layOut(chain(width: 375, widths: [50, 57], match: true, rtl: rtl)),
          ['0 + 188', '188 + 187'],
        );
      });

      test('five fixed members spread across 325 px, $direction', () {
        expect(
          layOut(chain(width: 325, widths: [50, 57, 64, 71, 78], rtl: rtl)),
          ['1 + 50', '52 + 57', '110 + 64', '174 + 71', '246 + 78'],
        );
      });

      test('two fixed members packed in 300 px, $direction', () {
        expect(
          layOut(
            chain(
              width: 300,
              widths: [50, 57],
              style: ConstraintWidget.CHAIN_PACKED,
              rtl: rtl,
            ),
          ),
          ['97 + 50', '147 + 57'],
        );
      });
    }

    test('five fixed members spread inside 323 px', () {
      expect(
        layOut(
          chain(
            width: 323,
            widths: [50, 57, 64, 71, 78],
            style: ConstraintWidget.CHAIN_SPREAD_INSIDE,
          ),
        ),
        ['0 + 50', '51 + 57', '109 + 64', '173 + 71', '245 + 78'],
      );
    });

    test('five match-constraint members with margins in 301 px', () {
      expect(
        layOut(
          chain(
            width: 301,
            widths: [50, 57, 64, 71, 78],
            match: true,
            outer: 16,
            inner: 8,
          ),
        ),
        ['16 + 47', '71 + 48', '127 + 47', '182 + 48', '238 + 47'],
      );
    });

    test('four match-constraint members weighted 1 to 4 in 375 px', () {
      expect(
        layOut(
          chain(
            width: 375,
            widths: [50, 57, 64, 71],
            match: true,
            weights: [1, 2, 3, 4],
          ),
        ),
        ['0 + 38', '38 + 75', '113 + 112', '225 + 150'],
      );
    });
  });
}
