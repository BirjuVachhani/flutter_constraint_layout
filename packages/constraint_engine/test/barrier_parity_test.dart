// Barriers on the dependency graph.
//
// The graph resolves a barrier to the outermost edge of its widgets plus its
// margin. Android (upstream at OPTIMIZATION_STANDARD) gets there through its
// Direct pass, which places a barrier whose widgets it placed, or else
// through the solver's soft constraints. The graph keeps a barrier layout
// only where, as far as it can tell, Android puts every barrier, and so
// every widget, in the same place, and hands the others to the solver (the
// fuzz group says which differences remain). Every test here lays a layout
// out on both paths (support/solver_parity.dart) and compares every
// widget's geometry, against the solver or against Android
// (StandardContainer); the layouts that should stay on the graph must do
// so.
//
// The first group repeats every barrier layout of the engine's other tests.
// The rest cover what changes a barrier's position on each path, then a
// randomized fuzz over barrier layouts.

import 'dart:math';

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/solver_parity.dart';

/// Every pass resolved on the graph, with the solver's geometry.
void expectGraph(List<ParityPass> passes) {
  for (final pass in passes) {
    expect(pass.differences, isEmpty);
    expect(pass.graphResolved, isTrue, reason: 'expected the graph path');
  }
}

/// Every pass resolved on the graph, with Android's geometry (the passes
/// were laid out with `android: true`).
void expectAndroid(List<ParityPass> passes) {
  for (final pass in passes) {
    expect(pass.android, isEmpty);
    expect(pass.graphResolved, isTrue, reason: 'expected the graph path');
  }
}

/// Every pass went to the solver (so both paths agree by construction).
void expectSolver(List<ParityPass> passes) {
  for (final pass in passes) {
    expect(pass.differences, isEmpty);
    expect(pass.graphResolved, isFalse, reason: 'expected the solver path');
  }
}

ConstraintWidget widget(
  ConstraintWidgetContainer root,
  String name,
  int width,
  int height,
) {
  final w = ConstraintWidget.sizeNamed(name, width, height);
  root.add(w);
  return w;
}

Barrier barrier(
  ConstraintWidgetContainer root,
  String name,
  int type,
  List<ConstraintWidget> references, {
  int margin = 0,
  bool allowsGone = true,
}) {
  final b = Barrier.named(name)
    ..setBarrierType(type)
    ..setMargin(margin)
    ..setAllowsGoneWidget(allowsGone);
  for (final reference in references) {
    b.add(reference);
  }
  root.add(b);
  return b;
}

void main() {
  group('the barrier layouts of the engine tests', () {
    // barrier_test.dart (upstream's BarrierTest).
    test('BarrierTest.barrierConstrainedWidth (wraps its width)', () {
      expectSolver(
        layoutBothWays((root) {
          final a = widget(root, 'A', 100, 20);
          final b = widget(root, 'B', 200, 20);
          final start = Guideline()
            ..setOrientation(Guideline.vertical)
            ..setGuideBegin(30);
          final end = Guideline()
            ..setOrientation(Guideline.vertical)
            ..setGuideEnd(20);
          root.addAll([start, end]);
          barrier(root, 'Barrier', Barrier.left, [a, b]);
          for (final w in [a, b]) {
            w.connect(.left, start, .left);
            w.connect(.right, end, .right);
            w.setHorizontalBiasPercent(1);
          }
          root.setHorizontalDimensionBehaviour(.wrapContent);
        }),
      );
    });

    test('BarrierTest.barrierImage', () {
      expectGraph(
        layoutBothWays((root) {
          final a = widget(root, 'A', 100, 20);
          final b = widget(root, 'B', 200, 20);
          final c = widget(root, 'C', 60, 60);
          final bar = barrier(root, 'Barrier', Barrier.right, [a, b]);
          a.connect(.left, root, .left);
          a.connect(.top, root, .top);
          a.connect(.bottom, b, .top);
          b.connect(.left, root, .left);
          b.connect(.top, a, .bottom);
          b.connect(.bottom, root, .bottom);
          a.setVerticalChainStyle(ConstraintWidget.CHAIN_SPREAD_INSIDE);
          c.setHorizontalBiasPercent(1);
          c.connect(.top, root, .top);
          c.connect(.bottom, root, .bottom);
          c.connect(.left, bar, .right);
          c.connect(.right, root, .right);
        }),
      );
    });

    test('BarrierTest.barrierTooStrong', () {
      expectGraph(
        layoutBothWays((root) {
          final a = widget(root, 'A', 60, 60);
          final b = widget(root, 'B', 100, 200);
          final c = widget(root, 'C', 100, 20);
          barrier(root, 'Barrier', Barrier.bottom, [b]);
          a.connect(.top, root, .top);
          a.connect(.right, root, .right);
          b.connect(.top, c, .bottom);
          b.setHorizontalDimensionBehaviour(.matchParent);
          c.setHorizontalDimensionBehaviour(.matchParent);
          c.setVerticalDimensionBehaviour(.matchConstraint);
          c.connect(.top, root, .top);
          c.connect(.bottom, a, .bottom);
        }),
      );
    });

    test('BarrierTest.barrierMax', () {
      expectGraph(
        layoutBothWays((root) {
          final a = widget(root, 'A', 100, 20);
          final bar = barrier(root, 'Barrier', Barrier.right, [a]);
          final b = widget(root, 'B', 150, 20);
          a.connect(.left, root, .left);
          a.connect(.top, root, .top);
          b.connect(.top, root, .top);
          b.connect(.left, bar, .left);
          b.connect(.right, root, .right);
          b.setHorizontalBiasPercent(0);
          b.setHorizontalDimensionBehaviour(.matchConstraint);
          b.setHorizontalMatchStyle(
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
            0,
            150,
            1,
          );
        }),
      );
    });

    // A widget linked to the barrier that references it is a cycle.
    for (final (name, type) in [
      ('barrierCenter', Barrier.right),
      ('barrierCenter2', Barrier.left),
    ]) {
      test('BarrierTest.$name (a cycle)', () {
        expectSolver(
          layoutBothWays((root) {
            final a = widget(root, 'A', 100, 20);
            final bar = barrier(root, 'Barrier', type, [a]);
            if (type == Barrier.right) {
              a.connect(.left, root, .left, 10);
              a.connect(.right, bar, .right, 30);
            } else {
              a.connect(.right, root, .right, 10);
              a.connect(.left, bar, .left, 30);
            }
            a.connect(.top, root, .top);
          }),
        );
      });
    }

    test('BarrierTest.barrierCenter3 (constrained wrap widths)', () {
      expectSolver(
        layoutBothWays((root) {
          final a = widget(root, 'A', 100, 20);
          final b = widget(root, 'B', 200, 20);
          barrier(root, 'Barrier', Barrier.left, [a, b]);
          for (final w in [a, b]) {
            w.connect(.right, root, .right);
            w.connect(.left, root, .left);
            w.setHorizontalDimensionBehaviour(.matchConstraint);
            w.setHorizontalMatchStyle(
              ConstraintWidget.MATCH_CONSTRAINT_WRAP,
              0,
              0,
              0,
            );
            w.setHorizontalBiasPercent(1);
          }
          a.connect(.top, root, .top);
          b.connect(.top, a, .bottom);
        }),
      );
    });

    test('BarrierTest.barrierCenter4 (a cycle)', () {
      expectSolver(
        layoutBothWays((root) {
          final a = widget(root, 'A', 150, 20);
          final b = widget(root, 'B', 100, 20);
          final bar = barrier(root, 'Barrier', Barrier.left, [a, b]);
          for (final w in [a, b]) {
            w.connect(.right, root, .right);
            w.connect(.left, bar, .left);
            w.setHorizontalBiasPercent(0);
          }
          a.connect(.top, root, .top);
          b.connect(.top, a, .bottom);
        }),
      );
    });

    test('BarrierTest.barrierCenter5 (a cycle)', () {
      expectSolver(
        layoutBothWays((root) {
          final a = widget(root, 'A', 100, 20);
          final b = widget(root, 'B', 150, 20);
          final c = widget(root, 'C', 200, 20);
          final bar = barrier(root, 'Barrier', Barrier.right, [a, b, c]);
          for (final w in [a, b, c]) {
            w.connect(.right, bar, .right);
            w.connect(.left, root, .left);
            w.setHorizontalBiasPercent(0);
            w.setHorizontalDimensionBehaviour(.matchConstraint);
            w.setHorizontalMatchStyle(
              ConstraintWidget.MATCH_CONSTRAINT_WRAP,
              0,
              0,
              0,
            );
          }
          a.connect(.top, root, .top);
          b.connect(.top, a, .bottom);
          c.connect(.top, b, .bottom);
        }),
      );
    });

    test('BarrierTest.basic (type changes between passes)', () {
      expectGraph(
        layoutBothWays(
          (root) {
            final a = widget(root, 'A', 100, 20);
            final b = widget(root, 'B', 150, 20);
            barrier(root, 'Barrier', Barrier.left, [a, b]);
            for (final w in [a, b]) {
              w.connect(.left, root, .left);
              w.connect(.right, root, .right);
            }
            a.connect(.top, root, .top, 50);
            b.connect(.top, a, .bottom, 20);
          },
          changes: [
            (root) => (root.getChildren()[2] as Barrier).setBarrierType(
              Barrier.right,
            ),
            (root) {
              (root.getChildren()[2] as Barrier).setBarrierType(Barrier.left);
              root.getChildren()[1].setWidth(10);
            },
          ],
        ),
      );
    });

    test('BarrierTest.basic2 (a constrained wrap height)', () {
      expectSolver(
        layoutBothWays((root) {
          final a = widget(root, 'A', 100, 20);
          final b = widget(root, 'B', 150, 20);
          final bar = barrier(root, 'Barrier', Barrier.bottom, [a]);
          a.setVerticalDimensionBehaviour(.matchConstraint);
          a.setVerticalMatchStyle(
            ConstraintWidget.MATCH_CONSTRAINT_WRAP,
            0,
            0,
            0,
          );
          a.connect(.left, root, .left);
          a.connect(.top, root, .top);
          b.connect(.left, root, .left);
          b.connect(.top, bar, .bottom);
          b.connect(.bottom, root, .bottom);
        }),
      );
    });

    test('BarrierTest.basic3 (wraps its width)', () {
      expectSolver(
        layoutBothWays((root) {
          final a = widget(root, 'A', 100, 20);
          final b = widget(root, 'B', 150, 20);
          final bar = barrier(root, 'Barrier', Barrier.right, [a]);
          a.connect(.left, root, .left);
          a.connect(.top, root, .top);
          b.connect(.left, bar, .left);
          b.connect(.top, root, .top);
          b.connect(.right, root, .right);
          root.setHorizontalDimensionBehaviour(.wrapContent);
        }),
      );
    });

    test('BarrierTest.basic4 (a gone reference)', () {
      expectGraph(
        layoutBothWays((root) {
          final a = widget(root, 'A', 100, 20);
          final b = widget(root, 'B', 100, 20);
          final c = widget(root, 'C', 100, 20);
          final bar = barrier(root, 'Barrier', Barrier.bottom, [a, b]);
          a.connect(.left, root, .left);
          a.connect(.top, root, .top);
          b.connect(.left, root, .left);
          b.connect(.top, a, .bottom);
          b.setVisibility(ConstraintWidget.GONE);
          c.connect(.left, root, .left);
          c.connect(.top, bar, .top);
        }),
      );
    });

    test('BarrierTest.growArray', () {
      expectGraph(
        layoutBothWays((root) {
          final widgets = [
            for (final (i, w) in [100, 150, 175, 200, 125].indexed)
              widget(root, 'W$i', w, 20),
          ];
          barrier(root, 'Barrier', Barrier.left, widgets);
          for (final (i, w) in widgets.indexed) {
            w.connect(.left, root, .left);
            w.connect(.right, root, .right);
            if (i == 0) {
              w.connect(.top, root, .top, 50);
            } else {
              w.connect(.top, widgets[i - 1], .bottom, 20);
            }
          }
        }),
      );
    });

    test('BarrierTest.connection', () {
      expectGraph(
        layoutBothWays((root) {
          final a = widget(root, 'A', 100, 20);
          final b = widget(root, 'B', 150, 20);
          final c = widget(root, 'C', 100, 20);
          final bar = barrier(root, 'Barrier', Barrier.left, [a, b]);
          for (final w in [a, b]) {
            w.connect(.left, root, .left);
            w.connect(.right, root, .right);
          }
          a.connect(.top, root, .top, 50);
          b.connect(.top, a, .bottom, 20);
          c.connect(.left, bar, .left, 0);
        }),
      );
    });

    test('BarrierTest.withGuideline', () {
      expectGraph(
        layoutBothWays((root) {
          final a = widget(root, 'A', 100, 20);
          final guideline = Guideline()
            ..setOrientation(Guideline.vertical)
            ..setGuideBegin(200);
          root.add(guideline);
          barrier(root, 'Barrier', Barrier.right, [a, guideline]);
          a.connect(.left, root, .left, 10);
          a.connect(.top, root, .top, 50);
        }),
      );
    });

    test('BarrierTest.wrapIssue (wraps its height)', () {
      expectSolver(
        layoutBothWays(
          (root) {
            final a = widget(root, 'A', 100, 20);
            final b = widget(root, 'B', 100, 20);
            final bar = barrier(root, 'Barrier', Barrier.bottom, [a]);
            a.connect(.left, root, .left);
            a.connect(.top, root, .top);
            b.connect(.left, root, .left);
            b.connect(.top, bar, .bottom);
            b.connect(.bottom, root, .bottom);
            root.setVerticalDimensionBehaviour(.wrapContent);
          },
          changes: [
            (root) {
              final a = root.getChildren()[0];
              a.setVerticalDimensionBehaviour(.matchConstraint);
              a.setVerticalMatchStyle(
                ConstraintWidget.MATCH_CONSTRAINT_WRAP,
                0,
                0,
                0,
              );
            },
          ],
        ),
      );
    });

    // basic_test.dart, wrap_test.dart, optimizations_test.dart and
    // measure_ordering_test.dart.
    test('BasicTest.testBarrier', () {
      expectGraph(
        layoutBothWays(width: 600, height: 800, (root) {
          final a = widget(root, 'A', 100, 30);
          final b = widget(root, 'B', 100, 30);
          final c = widget(root, 'C', 100, 30);
          final d = widget(root, 'D', 100, 30);
          final bar = barrier(root, 'barrier1', Barrier.bottom, [a]);
          a.connect(.top, root, .top);
          b.connect(.top, bar, .bottom);
          c.connect(.top, b, .bottom);
          d.connect(.top, c, .bottom);
          d.connect(.bottom, root, .bottom);
        }),
      );
    });

    test('WrapTest.testWrap4 (wraps its height)', () {
      expectSolver(
        layoutBothWays(width: 500, (root) {
          final a = widget(root, 'A', 80, 80);
          final b = widget(root, 'B', 60, 60);
          final c = widget(root, 'C', 50, 100);
          final b1 = barrier(root, 'B1', Barrier.bottom, [a, b]);
          final b2 = barrier(root, 'B2', Barrier.bottom, [c]);
          a.connect(.top, root, .top);
          a.connect(.bottom, b1, .bottom);
          b.connect(.top, root, .top);
          b.connect(.bottom, b1, .bottom);
          c.connect(.top, b1, .bottom);
          c.connect(.bottom, b2, .top);
          a.connect(.left, root, .left);
          b.connect(.left, a, .right);
          root.setVerticalDimensionBehaviour(.wrapContent);
        }),
      );
    });

    test('WrapTest.testBarrierWrap (wraps its height)', () {
      expectSolver(
        layoutBothWays(width: 1080, height: 1080, (root) {
          final view = widget(root, 'view', 200, 200);
          final space = widget(root, 'space', 50, 50);
          final button = widget(root, 'button', 100, 80);
          final text = widget(root, 'text', 90, 30);
          final bar = barrier(root, 'barrier', Barrier.bottom, [button, space]);
          view.connect(.top, root, .top);
          space.connect(.top, view, .bottom);
          button.connect(.top, view, .bottom);
          button.connect(.bottom, text, .top);
          text.connect(.top, bar, .bottom);
          text.connect(.bottom, root, .bottom);
          button.setVerticalBiasPercent(1);
          root.setVerticalDimensionBehaviour(.wrapContent);
        }),
      );
    });

    test('OptimizationsTest.testLayoutWrapBarrier (wraps its height)', () {
      expectSolver(
        layoutBothWays(width: 600, (root) {
          final a = widget(root, 'A', 20, 20);
          final b = widget(root, 'B', 20, 20);
          final c = widget(root, 'C', 20, 20);
          final bar = barrier(root, 'Barrier', Barrier.bottom, [a, b]);
          a.connect(.top, root, .top);
          b.connect(.top, a, .bottom);
          b.setVisibility(ConstraintWidget.GONE);
          c.connect(.top, bar, .top);
          root.setVerticalDimensionBehaviour(.wrapContent);
        }),
      );
    });

    for (final name in ['testLayoutWrapBarrier2', 'testLayoutWrapBarrier3']) {
      test('OptimizationsTest.$name (wraps its width)', () {
        expectSolver(
          layoutBothWays(width: 600, (root) {
            if (name.endsWith('3')) {
              root.setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);
            }
            final a = widget(root, 'A', 50, 20);
            final b = widget(root, 'B', 50, 30);
            final c = widget(root, 'C', 50, 20);
            final end = Guideline()
              ..setGuideEnd(40)
              ..setOrientation(ConstraintWidget.VERTICAL);
            final bar = barrier(root, 'barrier', Barrier.left, [b, c]);
            root.add(end);
            a.connect(.left, root, .left);
            a.connect(.right, bar, .left);
            b.connect(.right, end, .right);
            c.connect(.right, root, .right);
            root.setHorizontalDimensionBehaviour(.wrapContent);
          }),
        );
      });
    }

    test('measure ordering: a bottom barrier over wrapped text (wraps its '
        'height)', () {
      expectSolver(
        layoutBothWays(
          width: 660,
          height: 0,
          measurer: () => _TextMeasurer({'a': 500, 'b': 100}),
          (root) {
            root.setVerticalDimensionBehaviour(.wrapContent);
            final guide = Guideline()
              ..setOrientation(Guideline.vertical)
              ..setGuidePercent(0.5);
            root.add(guide);
            final a = ConstraintWidget.named('a');
            final b = ConstraintWidget.named('b');
            root.addAll([a, b]);
            for (final w in [a, b]) {
              w.setHorizontalDimensionBehaviour(.matchConstraint);
              w.setVerticalDimensionBehaviour(.wrapContent);
              w.connect(.top, root, .top);
            }
            a.connect(.left, root, .left, 15);
            a.connect(.right, guide, .left, 15);
            b.connect(.left, guide, .right, 15);
            b.connect(.right, root, .right, 15);
            final bar = barrier(root, 'barrier', Barrier.bottom, [a, b]);
            final follower = widget(root, 'follower', 10, 10);
            follower.connect(.left, root, .left);
            follower.connect(.top, bar, .top);
          },
        ),
      );
    });

    // barrier_modes_test.dart: a barrier over three staggered widgets, for
    // every type, with and without a margin, a gone member, and a follower.
    for (final type in [
      Barrier.left,
      Barrier.right,
      Barrier.top,
      Barrier.bottom,
    ]) {
      for (final margin in [0, 25]) {
        for (final allowsGone in [true, false]) {
          for (final goneMember in [false, true]) {
            test('barrier modes: type $type, margin $margin, allowsGone '
                '$allowsGone, gone member $goneMember', () {
              expectGraph(
                layoutBothWays(
                  (root) => _staggered(
                    root,
                    type,
                    margin: margin,
                    allowsGone: allowsGone,
                    goneMember: goneMember,
                    follower: true,
                  ),
                ),
              );
            });
          }
        }
      }
    }

    test('barrier modes: a barrier tracking another barrier', () {
      expectGraph(
        layoutBothWays((root) {
          final first = _staggered(root, Barrier.right);
          barrier(root, 'second', Barrier.right, [first], margin: 30);
        }),
      );
    });

    test('barrier modes: the group is re-read on every layout', () {
      expectGraph(
        layoutBothWays(
          (root) => _staggered(root, Barrier.right),
          changes: [(root) => root.getChildren()[1].setWidth(260)],
        ),
      );
    });

    test('barrier modes: an entirely gone group, and no widgets at all', () {
      expectSolver(
        layoutBothWays((root) {
          final b = _staggered(root, Barrier.right, allowsGone: false);
          for (final w in root.getChildren()) {
            if (w != b) {
              w.setVisibility(ConstraintWidget.GONE);
            }
          }
        }),
      );
      expectSolver(
        layoutBothWays((root) => barrier(root, 'empty', Barrier.left, [])),
      );
    });
  });

  group('on the graph, as on the solver', () {
    test('every barrier type, with positive and negative margins', () {
      for (final type in [
        Barrier.left,
        Barrier.right,
        Barrier.top,
        Barrier.bottom,
      ]) {
        for (final margin in [-8, 0, 12]) {
          expectGraph(
            layoutBothWays(
              (root) => _staggered(
                root,
                type,
                margin: margin,
                inset: 40,
                follower: true,
              ),
            ),
          );
        }
      }
    });

    test('gone references, counted or skipped', () {
      for (final allowsGone in [true, false]) {
        expectGraph(
          layoutBothWays((root) {
            final a = widget(root, 'a', 80, 20);
            final b = widget(root, 'b', 160, 20);
            a.connect(.left, root, .left, 16);
            a.connect(.top, root, .top, 16);
            b.connect(.left, a, .right, 40);
            b.connect(.top, a, .bottom, 8);
            b.setVisibility(ConstraintWidget.GONE);
            final end = barrier(
              root,
              'end',
              Barrier.right,
              [a, b],
              allowsGone: allowsGone,
            );
            final value = widget(root, 'value', 50, 20);
            value.connect(.left, end, .right, 8);
            value.connect(.top, root, .top, 16);
          }),
        );
      }
    });

    test('a barrier inside another barrier, gone or not', () {
      for (final allowsGone in [true, false]) {
        for (final goneInner in [false, true]) {
          expectGraph(
            layoutBothWays((root) {
              final a = widget(root, 'a', 80, 20);
              final b = widget(root, 'b', 120, 20);
              a.connect(.left, root, .left, 16);
              a.connect(.top, root, .top, 16);
              b.connect(.left, root, .left, 16);
              b.connect(.top, a, .bottom, 8);
              final inner = barrier(root, 'inner', Barrier.right, [a]);
              if (goneInner) {
                inner.setVisibility(ConstraintWidget.GONE);
              }
              barrier(
                root,
                'outer',
                Barrier.right,
                [inner, b],
                margin: 4,
                allowsGone: allowsGone,
              );
            }),
          );
        }
      }
    });

    test('a chain of barriers through the widgets linked to them', () {
      // labels | end of labels | values | end of values | units
      expectGraph(
        layoutBothWays((root) {
          final labels = [
            for (final (i, w) in [70, 110, 90].indexed)
              widget(root, 'label$i', w, 20),
          ];
          final labelEnd = barrier(
            root,
            'labelEnd',
            Barrier.right,
            labels,
            margin: 8,
          );
          final values = [
            for (final (i, w) in [120, 60, 150].indexed)
              widget(root, 'value$i', w, 20),
          ];
          final valueEnd = barrier(
            root,
            'valueEnd',
            Barrier.right,
            [...values, labelEnd],
            margin: 6,
          );
          for (var i = 0; i < 3; i++) {
            labels[i].connect(.left, root, .left, 16);
            labels[i].connect(.top, root, .top, 16 + 30 * i);
            values[i].connect(.left, labelEnd, .right);
            values[i].connect(.top, labels[i], .top);
            final unit = widget(root, 'unit$i', 30, 20);
            unit.connect(.left, valueEnd, .right);
            unit.connect(.top, labels[i], .top);
          }
          final below = barrier(
            root,
            'below',
            Barrier.bottom,
            [...labels, ...values],
          );
          final footer = widget(root, 'footer', 200, 40);
          footer.connect(.left, labelEnd, .right);
          footer.connect(.top, below, .bottom, 16);
        }),
      );
    });

    test('widgets linked to a barrier: one link, a fill, a capped fill, a '
        'bias', () {
      for (final bias in [0.0, 0.5, 1.0]) {
        expectGraph(
          layoutBothWays((root) {
            final name = widget(root, 'name', 90, 20);
            final email = widget(root, 'email', 140, 20);
            name.connect(.left, root, .left, 16);
            name.connect(.top, root, .top, 16);
            email.connect(.left, root, .left, 16);
            email.connect(.top, name, .bottom, 12);
            final labels = barrier(root, 'labels', Barrier.right, [
              name,
              email,
            ]);
            final single = widget(root, 'single', 100, 20);
            single.connect(.left, labels, .right, 12);
            single.connect(.top, name, .top);
            final fill = widget(root, 'fill', 0, 20);
            fill.setHorizontalDimensionBehaviour(.matchConstraint);
            fill.connect(.left, labels, .right, 12);
            fill.connect(.right, root, .right, 16);
            fill.connect(.top, email, .top);
            final capped = widget(root, 'capped', 0, 20);
            capped.setHorizontalDimensionBehaviour(.matchConstraint);
            capped.setHorizontalMatchStyle(
              ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
              0,
              200,
              1,
            );
            capped.connect(.left, labels, .right, 12);
            capped.connect(.right, root, .right, 16);
            capped.connect(.top, email, .bottom, 12);
            final centered = widget(root, 'centered', 100, 20);
            centered.connect(.left, labels, .right, 12);
            centered.connect(.right, root, .right, 16);
            centered.connect(.top, capped, .bottom, 12);
            centered.setHorizontalBiasPercent(bias);
            centered.setVerticalDimensionBehaviour(.matchConstraint);
            centered.connect(.bottom, root, .bottom, 16);
          }),
        );
      }
    });

    test('barriers over match-constraint widgets', () {
      expectGraph(
        layoutBothWays((root) {
          final guide = Guideline()
            ..setOrientation(Guideline.vertical)
            ..setGuidePercent(0.4);
          root.add(guide);
          final image = widget(root, 'image', 0, 0);
          image.setHorizontalDimensionBehaviour(.matchConstraint);
          image.setVerticalDimensionBehaviour(.matchConstraint);
          image.connect(.left, root, .left, 16);
          image.connect(.right, guide, .left, 16);
          image.connect(.top, root, .top, 16);
          image.connect(.bottom, root, .bottom, 300);
          final caption = widget(root, 'caption', 120, 20);
          caption.connect(.left, root, .left, 16);
          caption.connect(.top, image, .bottom, 8);
          final end = barrier(root, 'end', Barrier.right, [image, caption]);
          final bottom = barrier(root, 'bottom', Barrier.bottom, [
            image,
            caption,
          ]);
          final side = widget(root, 'side', 120, 40);
          side.connect(.left, end, .right, 12);
          side.connect(.top, root, .top, 16);
          final footer = widget(root, 'footer', 0, 40);
          footer.setHorizontalDimensionBehaviour(.matchConstraint);
          footer.connect(.left, root, .left, 16);
          footer.connect(.right, root, .right, 16);
          footer.connect(.top, bottom, .bottom, 16);
        }),
      );
    });
  });

  group('to the solver, which moves the barrier off its bound', () {
    test('a widget that does not fit between the barrier and its other '
        'link', () {
      // The solver widens the space by moving the barrier: the widget's
      // range checks outweigh the barrier's pull towards its one widget.
      expectSolver(
        layoutBothWays(width: 453, height: 241, (root) {
          final w0 = widget(root, 'w0', 133, 17);
          w0.connect(.top, root, .top, 21);
          final b0 = barrier(root, 'b0', Barrier.right, [w0], margin: 15);
          final w1 = widget(root, 'w1', 136, 86);
          w1.connect(.left, w0, .right, 13);
          w1.connect(.right, b0, .right, 17);
          w1.connect(.top, root, .top, 40);
        }),
      );
    });

    test('a barrier at a negative position', () {
      // The solver rounds a position as (int) (value + 0.5), one pixel
      // towards zero for a negative one; barrier layouts keep its result.
      expectSolver(
        layoutBothWays((root) {
          final a = widget(root, 'a', 60, 20);
          a.connect(.left, root, .left);
          a.connect(.top, root, .top);
          final b = barrier(root, 'b', Barrier.left, [a], margin: -7);
          final f = widget(root, 'f', 50, 20);
          f.connect(.left, b, .left);
          f.connect(.top, a, .bottom);
        }),
      );
    });

    test('a widget linked across the barrier', () {
      // The solver never constrains a left barrier's top, so a widget below
      // it lands wherever the rest of its constraints put it.
      expectSolver(
        layoutBothWays((root) {
          final a = widget(root, 'a', 60, 20);
          a.connect(.left, root, .left, 30);
          a.connect(.top, root, .top, 30);
          final b = barrier(root, 'b', Barrier.left, [a]);
          final f = widget(root, 'f', 50, 20);
          f.connect(.left, root, .left);
          f.connect(.top, b, .top, 10);
        }),
      );
    });
  });

  group('on the graph where the Direct pass places the barrier', () {
    // The solver alone would move these barriers off their bound, but
    // Android's Direct pass places them (their widgets are placed first),
    // and Barrier.addToSolver holds a barrier the pass placed: Android lays
    // them out as the graph does. The values are Android's.
    test('a left barrier past the container edge it is pulled towards', () {
      // Barrier.addToSolver pulls a left barrier towards the container's
      // right edge as hard as towards its widget, so past that edge the
      // solver alone settles anywhere between the two (400 here).
      void build(ConstraintWidgetContainer root) {
        final a = widget(root, 'a', 60, 20);
        a.connect(.left, root, .left, 10);
        a.connect(.top, root, .top, 10);
        barrier(root, 'b', Barrier.left, [a], margin: 500);
      }

      expectAndroid(layoutBothWays(width: 400, build, android: true));
      final root = SolveCountingContainer(400, 600);
      build(root);
      root.layout();
      final b = root.getChildren().whereType<Barrier>().single;
      expect(b.getX(), 510);
    });

    test('a slack bounds check that outweighs a match-constraint '
        'reference', () {
      // With a match-constraint reference, the barrier's pull towards its
      // references drops to STRENGTH_HIGHEST, where three widgets centered
      // between the barrier and the container's edge pull harder: the
      // solver alone would move the barrier to 740.
      void build(ConstraintWidgetContainer root) {
        final a = widget(root, 'a', 0, 20);
        a.setHorizontalDimensionBehaviour(.matchConstraint);
        a.connect(.left, root, .left, 16);
        a.connect(.right, root, .right, 500);
        a.connect(.top, root, .top, 16);
        final end = barrier(root, 'end', Barrier.right, [a]);
        for (var i = 0; i < 3; i++) {
          final w = widget(root, 'w$i', 60, 20);
          w.connect(.left, end, .right);
          w.connect(.right, root, .right);
          w.connect(.top, a, .bottom, 30 * i);
        }
      }

      expectAndroid(layoutBothWays(build, android: true));
      final root = SolveCountingContainer(800, 600);
      build(root);
      root.layout();
      final end = root.getChildren().whereType<Barrier>().single;
      expect(end.getX(), 300);
      for (final w in root.getChildren().where(
        (c) => c.getDebugName()?.startsWith('w') ?? false,
      )) {
        expect(w.getX(), 520);
      }
    });
  });

  group('wrap content', () {
    test('a container that wraps its content around a barrier takes the '
        'solver', () {
      // A barrier turns off the graph's wrap computation, so the graph
      // would keep the container's incoming size.
      expectSolver(
        layoutBothWays(width: 1000, height: 500, (root) {
          root.setHorizontalDimensionBehaviour(.wrapContent);
          final a = widget(root, 'a', 60, 20);
          final c = widget(root, 'c', 30, 20);
          a.connect(.left, root, .left, 5);
          a.connect(.top, root, .top);
          final b = barrier(root, 'b', Barrier.right, [a]);
          c.connect(.left, b, .right, 8);
          c.connect(.top, root, .top);
        }),
      );
    });

    test('so does one that wraps its content around a guideline', () {
      final graph = SolveCountingContainer(1000, 500);
      graph.setHorizontalDimensionBehaviour(.wrapContent);
      final guide = Guideline()
        ..setOrientation(Guideline.vertical)
        ..setGuideBegin(10);
      final a = ConstraintWidget.sizeNamed('a', 60, 20);
      graph.addAll([guide, a]);
      a.connect(.left, guide, .left, 5);
      a.connect(.top, graph, .top);
      graph.layout();
      // 10 + 5 + 60, not the incoming 1000.
      expect(graph.getWidth(), 75);
      expect(graph.solves, greaterThan(0));
    });
  });

  group('the graph resolves the barrier itself', () {
    test('at the outermost edge when its widgets lie at negative '
        'positions', () {
      // directMeasure resolves through the graph alone. Upstream seeds the
      // outermost edge with -1 as "unset" (min) and 0 (max), which loses a
      // widget at -1 and puts a right barrier over widgets left of 0 at 0.
      final root = ConstraintWidgetContainer.rect(0, 0, 400, 300);
      root.setMeasurer(_TextMeasurer({}));
      final a = ConstraintWidget.sizeNamed('a', 40, 20);
      final b = ConstraintWidget.sizeNamed('b', 40, 20);
      root.addAll([a, b]);
      a.connect(.right, root, .left, 10);
      b.connect(.right, root, .left, 30);
      a.connect(.top, root, .top);
      b.connect(.top, root, .top);
      final right = Barrier.named('right')..setBarrierType(Barrier.right);
      right.add(a);
      right.add(b);
      final c = ConstraintWidget.sizeNamed('c', 40, 20);
      c.connect(.left, root, .left, -1);
      c.connect(.top, root, .top);
      final left = Barrier.named('left')..setBarrierType(Barrier.left);
      left.add(a);
      left.add(c);
      root.addAll([c, right, left]);
      root.directMeasure(false);
      expect(right.getX(), -10);
      expect(left.getX(), -50);
    });

    test('as a line: its end is its start, its size is 0, and it sits at 0 '
        'across its axis', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 400, 300);
      final a = ConstraintWidget.sizeNamed('a', 40, 20);
      a.connect(.left, root, .left, 30);
      a.connect(.top, root, .top, 70);
      final b = Barrier.named('b')..setBarrierType(Barrier.bottom);
      b.add(a);
      root.addAll([a, b]);
      b.setX(25);
      root.layout();
      expect(b.getY(), 90);
      expect(b.getX(), 0);
      expect(b.getWidth(), 0);
      expect(b.getHeight(), 0);
    });
  });

  group('fuzz', () {
    // Random barrier layouts: up to seven widgets of every size kind and up
    // to three barriers of every type, in random order, linked to the
    // container, to each other, and to the barriers (cycles included), with
    // gone and invisible widgets, gone barriers, barriers inside barriers,
    // negative barrier margins, and containers that wrap their content.
    //
    // A layout the graph keeps must not be one that the solver lays out as
    // Android does while the graph does not: that is what the check
    // guarantees. It can differ from the solver (where Android's Direct pass
    // places a barrier the solver alone would move, or rounds a half pixel
    // as the graph does), and in a few degenerate layouts from both (an
    // overflowing widget whose offset Android truncates, links that cross),
    // where declining would not bring Android's geometry. Nothing here relies
    // on positions being whole pixels.
    void expectNoBetterSolver(ParityPass pass, int i) {
      expect(
        pass.graphResolved &&
            pass.android.isNotEmpty &&
            pass.solverMatchesAndroid,
        isFalse,
        reason: 'layout $i: ${pass.android}',
      );
    }

    for (final seed in [1, 2, 3, 4, 5]) {
      test('random barrier layouts, seed $seed', () {
        var graphResolved = 0;
        var asAndroid = 0;
        for (var i = 0; i < 2000; i++) {
          final layoutSeed = seed * 100000 + i;
          final size = Random(layoutSeed);
          final passes = layoutBothWays(
            width: 200 + 2 * size.nextInt(300),
            height: 200 + 2 * size.nextInt(300),
            (root) => _randomLayout(root, layoutSeed),
            android: true,
          );
          final pass = passes.single;
          expectNoBetterSolver(pass, i);
          if (pass.graphResolved) {
            graphResolved++;
            if (pass.android.isEmpty) {
              asAndroid++;
            }
          }
        }
        // Most random layouts hold a cycle, a conflict, or a container that
        // wraps its content, which the solver resolves; about one in
        // eighteen stays on the graph, and more than four in five of those
        // come out exactly as Android lays them out (the rest differ from
        // Android as the solver does).
        expect(graphResolved, greaterThan(90));
        expect(asAndroid, greaterThan(graphResolved * 4 ~/ 5));
      });

      test('form layouts, seed $seed', () {
        var graphResolved = 0;
        var asAndroid = 0;
        for (var i = 0; i < 400; i++) {
          final layoutSeed = seed * 100000 + i;
          final size = Random(layoutSeed);
          final passes = layoutBothWays(
            width: 320 + 2 * size.nextInt(200),
            height: 600 + 2 * size.nextInt(200),
            (root) => _formLayout(root, layoutSeed),
            android: true,
          );
          final pass = passes.single;
          expectNoBetterSolver(pass, i);
          if (pass.graphResolved) {
            graphResolved++;
            if (pass.android.isEmpty) {
              asAndroid++;
            }
          }
        }
        // Nearly every form stays on the graph, exactly as Android lays it
        // out.
        expect(graphResolved, greaterThan(380));
        expect(asAndroid, graphResolved);
      });
    }
  });
}

/// barrier_modes_test.dart's layout: three widgets of different sizes,
/// staggered from the top-left by [inset], and a barrier over all three. With
/// [goneMember] the widest one is gone; with [follower] a widget is linked
/// past the barrier.
Barrier _staggered(
  ConstraintWidgetContainer root,
  int type, {
  int margin = 0,
  bool allowsGone = true,
  bool goneMember = false,
  bool follower = false,
  int inset = 0,
}) {
  final widgets = <ConstraintWidget>[];
  const sizes = [(60, 20), (140, 40), (100, 80)];
  for (final (i, (w, h)) in sizes.indexed) {
    final child = widget(root, 'w$i', w, h);
    child.connect(.left, root, .left, inset + 10 * i);
    child.connect(.top, root, .top, inset + 15 * i);
    widgets.add(child);
  }
  if (goneMember) {
    widgets[1].setVisibility(ConstraintWidget.GONE);
  }
  final b = barrier(
    root,
    'barrier',
    type,
    widgets,
    margin: margin,
    allowsGone: allowsGone,
  );
  if (follower) {
    final f = widget(root, 'follower', 50, 20);
    if (type == Barrier.left || type == Barrier.right) {
      f.connect(.left, b, .left);
      f.connect(.top, root, .top);
    } else {
      f.connect(.top, b, .bottom);
      f.connect(.left, root, .left);
    }
  }
  return b;
}

/// A random barrier layout; see the fuzz group.
void _randomLayout(ConstraintWidgetContainer root, int seed) {
  final rnd = Random(seed);
  int even(int max) => 2 * rnd.nextInt(max ~/ 2 + 1);
  int margin() => rnd.nextInt(4) == 0 ? 0 : even(40);
  if (rnd.nextInt(6) == 0) {
    root.setHorizontalDimensionBehaviour(.wrapContent);
  }
  if (rnd.nextInt(6) == 0) {
    root.setVerticalDimensionBehaviour(.wrapContent);
  }
  final widgets = [
    for (var i = 0; i < 1 + rnd.nextInt(7); i++)
      ConstraintWidget.sizeNamed('w$i', 10 + even(150), 10 + even(100)),
  ];
  final barriers = [
    for (var i = 0; i < 1 + rnd.nextInt(3); i++)
      Barrier.named('b$i')
        ..setBarrierType(rnd.nextInt(4))
        ..setMargin(rnd.nextInt(5) == 0 ? -even(30) : margin())
        ..setAllowsGoneWidget(rnd.nextBool())
        ..setVisibility(
          rnd.nextInt(12) == 0
              ? ConstraintWidget.GONE
              : ConstraintWidget.VISIBLE,
        ),
  ];
  for (final child in [...widgets, ...barriers]..shuffle(rnd)) {
    root.add(child);
  }
  for (final b in barriers) {
    final count = rnd.nextInt(4);
    for (var j = 0; j < count; j++) {
      if (rnd.nextInt(5) == 0 && barriers.length > 1) {
        final other = barriers[rnd.nextInt(barriers.length)];
        if (other != b) {
          b.add(other);
        }
      } else {
        b.add(widgets[rnd.nextInt(widgets.length)]);
      }
    }
    if (count == 0 && rnd.nextBool()) {
      b.add(widgets[rnd.nextInt(widgets.length)]);
    }
  }
  List<Barrier> along(int orientation) =>
      barriers.where((b) => b.getOrientation() == orientation).toList();
  final vertical = along(ConstraintWidget.HORIZONTAL);
  final horizontal = along(ConstraintWidget.VERTICAL);

  (ConstraintWidget, ConstraintAnchorType)? pick(int i, bool h) {
    final begin = h ? ConstraintAnchorType.left : ConstraintAnchorType.top;
    final end = h ? ConstraintAnchorType.right : ConstraintAnchorType.bottom;
    final side = rnd.nextBool() ? begin : end;
    final lines = h ? vertical : horizontal;
    final roll = rnd.nextInt(10);
    if (roll < 3) return (root, side);
    if (roll < 6 && lines.isNotEmpty) {
      return (lines[rnd.nextInt(lines.length)], side);
    }
    if (roll < 9 && i > 0) return (widgets[rnd.nextInt(i)], side);
    if (roll == 9) return (widgets[rnd.nextInt(widgets.length)], side);
    return null;
  }

  void link(
    ConstraintWidget w,
    ConstraintAnchorType from,
    (ConstraintWidget, ConstraintAnchorType)? to,
  ) {
    if (to == null || to.$1 == w) return;
    // Two widgets linked to each other on one axis would form a chain,
    // possibly a degenerate one (see link_loop_test.dart). This generator
    // leaves chains out: along each axis it links two widgets one way only.
    final other = to.$1;
    final h =
        from == ConstraintAnchorType.left || from == ConstraintAnchorType.right;
    for (final a
        in h ? [other.mLeft, other.mRight] : [other.mTop, other.mBottom]) {
      if (a.mTarget != null && a.mTarget!.mOwner == w) return;
    }
    w.connect(from, to.$1, to.$2, margin());
  }

  for (final (i, w) in widgets.indexed) {
    for (final h in [true, false]) {
      final begin = h ? ConstraintAnchorType.left : ConstraintAnchorType.top;
      final end = h ? ConstraintAnchorType.right : ConstraintAnchorType.bottom;
      final kind = rnd.nextInt(10);
      if (rnd.nextInt(10) < 8) link(w, begin, pick(i, h));
      if (rnd.nextInt(10) < 5) link(w, end, pick(i, h));
      final linkedTwice =
          w.getAnchor(begin)!.isConnected() && w.getAnchor(end)!.isConnected();
      void behave(DimensionBehaviour b) => h
          ? w.setHorizontalDimensionBehaviour(b)
          : w.setVerticalDimensionBehaviour(b);
      void style(int style, int min, int max) => h
          ? w.setHorizontalMatchStyle(style, min, max, 1)
          : w.setVerticalMatchStyle(style, min, max, 1);
      if (kind < 2) {
        behave(.wrapContent);
      } else if (kind < 4) {
        behave(.matchConstraint);
        final s = rnd.nextInt(4);
        if (s == 1 && linkedTwice) {
          final min = even(60);
          style(
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
            min,
            rnd.nextInt(3) == 0 ? 0 : 40 + even(200),
          );
        } else if (s == 2) {
          style(ConstraintWidget.MATCH_CONSTRAINT_WRAP, 0, 0);
        }
      }
      if (rnd.nextInt(4) == 0) {
        final bias = const [0.0, 0.5, 1.0][rnd.nextInt(3)];
        h ? w.setHorizontalBiasPercent(bias) : w.setVerticalBiasPercent(bias);
      }
      if (rnd.nextInt(5) == 0) w.setGoneMargin(begin, even(30));
    }
    switch (rnd.nextInt(10)) {
      case 0:
        w.setVisibility(ConstraintWidget.GONE);
      case 1:
        w.setVisibility(ConstraintWidget.INVISIBLE);
    }
  }
}

/// A form: a header with a bottom barrier over it, rows of a label and a
/// value with an end barrier over the labels (values linked to it by one
/// link, filling, centered with a bias, or capped), sometimes a second column
/// past an end barrier over the values, and a footer below a bottom barrier
/// over the rows.
void _formLayout(ConstraintWidgetContainer root, int seed) {
  final rnd = Random(seed);
  int even(int max) => 2 * rnd.nextInt(max ~/ 2 + 1);
  final avatar = widget(root, 'avatar', 40 + even(40), 40 + even(40));
  final title = widget(root, 'title', 60 + even(160), 20 + even(20))
    ..setHorizontalDimensionBehaviour(.wrapContent);
  final subtitle = widget(root, 'subtitle', 40 + even(160), 16 + even(40));
  avatar.connect(.left, root, .left, 16);
  avatar.connect(.top, root, .top, 16);
  title.connect(.left, avatar, .right, 12);
  title.connect(.top, avatar, .top);
  subtitle.connect(.left, title, .left);
  subtitle.connect(.top, title, .bottom, 4);
  if (rnd.nextBool()) {
    subtitle.setVisibility(ConstraintWidget.GONE);
  }
  final header = barrier(
    root,
    'header',
    Barrier.bottom,
    [avatar, title, subtitle],
    margin: even(16),
    allowsGone: rnd.nextBool(),
  );
  final labels = <ConstraintWidget>[];
  final values = <ConstraintWidget>[];
  ConstraintWidget? above;
  for (var i = 0; i < 1 + rnd.nextInt(5); i++) {
    final label = widget(root, 'label$i', 30 + even(120), 20)
      ..setHorizontalDimensionBehaviour(.wrapContent);
    final value = widget(root, 'value$i', 40 + even(120), 20 + even(20));
    label.connect(.left, root, .left, 16);
    label.connect(.top, above ?? header, .bottom, above == null ? 12 : 8);
    value.connect(.top, label, .top);
    labels.add(label);
    values.add(value);
    above = value.getHeight() > label.getHeight() ? value : label;
    if (rnd.nextInt(8) == 0) {
      label.setVisibility(ConstraintWidget.GONE);
    }
  }
  final labelEnd = barrier(
    root,
    'labelEnd',
    Barrier.right,
    labels,
    margin: even(16),
    allowsGone: rnd.nextBool(),
  );
  final secondColumn = rnd.nextInt(3) == 0;
  for (final value in values) {
    value.connect(.left, labelEnd, .right, 8);
    switch (rnd.nextInt(4)) {
      case 0:
        break;
      case 1:
        value.setHorizontalDimensionBehaviour(.matchConstraint);
        value.connect(.right, root, .right, 16);
      case 2:
        value.connect(.right, root, .right, 16);
        value.setHorizontalBiasPercent(const [0.0, 0.5, 1.0][rnd.nextInt(3)]);
      default:
        value.setHorizontalDimensionBehaviour(.matchConstraint);
        value.setHorizontalMatchStyle(
          ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
          0,
          60 + even(100),
          1,
        );
        value.connect(.right, root, .right, 16);
    }
    if (secondColumn) {
      value.setHorizontalDimensionBehaviour(.fixed);
    }
  }
  if (secondColumn) {
    final valueEnd = barrier(root, 'valueEnd', Barrier.right, [
      ...values,
      if (rnd.nextBool()) labelEnd,
    ], margin: even(12));
    final unit = widget(root, 'unit', 20 + even(40), 20);
    unit.connect(.left, valueEnd, .right, 4);
    unit.connect(.top, values.first, .top);
  }
  final bottom = barrier(root, 'bottom', Barrier.bottom, [
    ...labels,
    ...values,
  ]);
  final footer = widget(root, 'footer', 100, 40);
  footer.connect(.top, bottom, .bottom, 16);
  switch (rnd.nextInt(3)) {
    case 0:
      footer.connect(.left, root, .left, 16);
    case 1:
      footer.setHorizontalDimensionBehaviour(.matchConstraint);
      footer.connect(.left, root, .left, 16);
      footer.connect(.right, root, .right, 16);
    default:
      footer.connect(.left, labelEnd, .right);
      footer.connect(.right, root, .right);
  }
  if (rnd.nextBool()) {
    footer.connect(.bottom, root, .bottom, 16);
    footer.setVerticalBiasPercent(const [0.0, 0.5, 1.0][rnd.nextInt(3)]);
  }
}

/// measure_ordering_test.dart's text-like measurer: content of a given
/// length wraps to ceil(length / width) lines of 20px.
class _TextMeasurer implements Measurer {
  _TextMeasurer(this.length);

  final Map<String, int> length;

  @override
  void measure(ConstraintWidget widget, Measure measure) {
    final len = length[widget.getDebugName()] ?? 0;
    final width = measure.horizontalBehavior == DimensionBehaviour.wrapContent
        ? len
        : measure.horizontalDimension;
    final int height;
    if (measure.verticalBehavior == DimensionBehaviour.wrapContent) {
      final w = width <= 0 ? 1 : width;
      final lines = (len + w - 1) ~/ w;
      height = (lines <= 0 ? 1 : lines) * 20;
    } else {
      height = measure.verticalDimension;
    }
    measure.measuredWidth = width;
    measure.measuredHeight = height;
    measure.measuredHasBaseline = false;
    measure.measuredBaseline = 0;
  }

  @override
  void didMeasures() {}
}
