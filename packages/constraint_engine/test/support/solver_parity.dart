// Graph and solver parity: lays the same layout out on
// ConstraintWidgetContainer.layout's graph-first path and on its solver
// fallback, and lists every difference in the resulting geometry.
//
// Neither path is Android's. Android's default, OPTIMIZATION_STANDARD, runs
// upstream's Direct pass before its solver, and this engine has no Direct
// pass, so its solver fallback lays a layout out as upstream does at
// OPTIMIZATION_NONE. Outside barrier layouts the graph declines only the
// cases UPSTREAM.md lists, and a layout it keeps can come out differently
// from the solver: where Direct places a widget as the graph does (a widget
// centered on a half pixel), or where the graph rounds a fraction of a pixel
// earlier than both (see the engine README). A test that expects no
// differences checks layouts where the two agree. A barrier layout is held
// to Android instead (see [StandardContainer]).

import 'package:constraint_engine/constraint_engine.dart';
// The forced fallback below swaps the container's dependency graph, and the
// Android emulation models the Direct pass; the package exports neither.
import 'package:constraint_engine/src/analyzer/dependency_graph.dart';
import 'package:constraint_engine/src/analyzer/direct_resolution.dart';

/// A container that counts the solver passes of its layouts.
class SolveCountingContainer extends ConstraintWidgetContainer {
  SolveCountingContainer(int width, int height)
    : super.rect(0, 0, width, height);

  /// How many times the solver has solved this container's layout.
  int solves = 0;

  @override
  bool addChildrenToSolver(LinearSystem system) {
    solves++;
    return super.addChildrenToSolver(system);
  }
}

/// A container whose dependency graph resolves the layout as usual and then
/// declines it, so [layout] always takes its solver fallback, exactly as for
/// a layout the graph cannot resolve.
class ForcedSolverContainer extends SolveCountingContainer {
  ForcedSolverContainer(super.width, super.height);

  late final DependencyGraph _graph = _DecliningGraph(this);

  @override
  DependencyGraph get mDependencyGraph => _graph;
}

class _DecliningGraph extends DependencyGraph {
  _DecliningGraph(super.container);

  @override
  bool directMeasure(bool optimizeWrap) {
    super.directMeasure(optimizeWrap);
    return false;
  }
}

/// A container laid out the way Android lays a ConstraintLayout out by
/// default (OPTIMIZATION_STANDARD): the Direct pass places what it can
/// first, and the solver holds those positions while it places the rest.
/// The engine has no Direct pass; this applies [DirectResolution]'s model of
/// it before the first solve of each layout, through the same final values
/// upstream's Direct pass sets (ConstraintWidget.setFinalHorizontal and
/// setFinalVertical, a guideline's anchor, Barrier.mResolved), which
/// ConstraintWidget.addToSolver, Guideline.addToSolver and
/// Barrier.addToSolver then hold. It matches upstream's compiled core at
/// OPTIMIZATION_STANDARD on the fuzzed barrier layouts but for float
/// rounding in a few weighted chains, and exactly on the generators of
/// barrier_parity_test.dart.
class StandardContainer extends ForcedSolverContainer {
  StandardContainer(super.width, super.height);

  bool _applied = false;

  @override
  void layout() {
    _applied = false;
    super.layout();
  }

  @override
  bool addChildrenToSolver(LinearSystem system) {
    // Upstream runs the Direct pass in the first solve of a layout only.
    if (!_applied) {
      _applied = true;
      _applyDirectPass();
    }
    return super.addChildrenToSolver(system);
  }

  void _applyDirectPass() {
    // ConstraintWidget.resetFinalResolution.
    for (final child in mChildren) {
      child.mResolvedHorizontal = false;
      child.mResolvedVertical = false;
      for (final anchor in child.mAnchors) {
        anchor.resetFinalResolution();
      }
    }
    final direct = DirectResolution(this);
    if (direct.diverged) {
      return;
    }
    for (final child in mChildren) {
      for (final horizontal in const [true, false]) {
        final start = direct.start(child, horizontal);
        final end = direct.end(child, horizontal);
        if (start == null || end == null) {
          continue;
        }
        if (child is Guideline) {
          child.mAnchor.setFinalValue(start);
          child.mResolved = true;
        } else if (horizontal) {
          child.setFinalHorizontal(start, end);
        } else {
          child.setFinalVertical(start, end);
        }
        if (child is Barrier) {
          child.mResolved = true;
        }
      }
    }
  }
}

/// The outcome of one layout pass on both paths.
class ParityPass {
  ParityPass(
    this.graphResolved,
    this.differences, {
    this.android = const [],
    this.solverMatchesAndroid = false,
  });

  /// Whether the graph-first container resolved the pass without the solver.
  final bool graphResolved;

  /// Every geometry difference between the two paths, empty at parity.
  final List<String> differences;

  /// With `android: true`, every geometry difference between the graph-first
  /// container and Android ([StandardContainer]), empty at parity.
  final List<String> android;

  /// With `android: true`, whether the solver fallback lays the pass out as
  /// Android does.
  final bool solverMatchesAndroid;

  @override
  String toString() =>
      'graphResolved: $graphResolved, differences: $differences'
      '${android.isEmpty ? '' : ', android: $android'}';
}

/// Builds a layout into [root] the same way every time it is called.
typedef LayoutBuilder = void Function(ConstraintWidgetContainer root);

/// Builds the layout with [build] into a graph-first and a forced-solver
/// container of [width] x [height], lays both out, then applies each of
/// [changes] to both and lays them out again. Returns one [ParityPass] per
/// layout pass. [measurer] makes a measurer for each container. With
/// [android], each pass is also laid out as Android does
/// ([StandardContainer]) and compared with both.
List<ParityPass> layoutBothWays(
  LayoutBuilder build, {
  int width = 800,
  int height = 600,
  List<LayoutBuilder> changes = const [],
  Measurer Function()? measurer,
  bool android = false,
}) {
  final graph = SolveCountingContainer(width, height)..setDebugName('root');
  final solver = ForcedSolverContainer(width, height)..setDebugName('root');
  final standard = android
      ? (StandardContainer(width, height)..setDebugName('root'))
      : null;
  build(graph);
  build(solver);
  if (standard != null) {
    build(standard);
  }
  if (measurer != null) {
    graph.setMeasurer(measurer());
    solver.setMeasurer(measurer());
    standard?.setMeasurer(measurer());
  }
  final passes = <ParityPass>[];
  for (var i = 0; i <= changes.length; i++) {
    if (i > 0) {
      changes[i - 1](graph);
      changes[i - 1](solver);
      if (standard != null) {
        changes[i - 1](standard);
      }
    }
    final solvesBefore = graph.solves;
    graph.layout();
    solver.layout();
    standard?.layout();
    passes.add(
      ParityPass(
        graph.solves == solvesBefore,
        _differences(graph, solver),
        android: standard == null
            ? const []
            : _differences(graph, standard, other: 'android'),
        solverMatchesAndroid:
            standard != null && _differences(solver, standard).isEmpty,
      ),
    );
  }
  return passes;
}

/// The geometry of [root] and of each of its children, one line each. A gone
/// widget is listed by size only: nothing places it, and the solver leaves
/// one that nothing references at 0, 0 where the graph keeps the point it
/// collapsed to. A gone barrier still has a position.
List<String> geometryOf(ConstraintWidgetContainer root) => [
  'root ${root.getWidth()} x ${root.getHeight()}',
  for (final (i, w) in root.getChildren().indexed)
    w.getVisibility() == ConstraintWidget.GONE && w is! Barrier
        ? '${w.getDebugName() ?? '#$i'}: gone, '
              '${w.getWidth()} x ${w.getHeight()}'
        : '${w.getDebugName() ?? '#$i'}: (${w.getX()}, ${w.getY()}) '
              '${w.getWidth()} x ${w.getHeight()}',
];

List<String> _differences(
  ConstraintWidgetContainer graph,
  ConstraintWidgetContainer solver, {
  String other = 'solver',
}) {
  final a = geometryOf(graph);
  final b = geometryOf(solver);
  return [
    for (var i = 0; i < a.length; i++)
      if (a[i] != b[i]) 'graph ${a[i]}, $other ${b[i]}',
  ];
}
