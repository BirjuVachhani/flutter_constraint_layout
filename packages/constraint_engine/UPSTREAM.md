# Upstream provenance

This package is a Dart port of `androidx.constraintlayout.core` (the
platform-independent layout engine behind Android ConstraintLayout).

Pinned upstream revision the port represents:

- Repository: https://github.com/androidx/constraintlayout
- Commit: `9cd4b5a4079a14175f91dc897abd83270799364a` (main, 2023-10-24)
- Library versions at that commit (`constraintlayout/gradle.properties`):
  - `constraintlayout.core` **1.1.0-alpha04**
  - `constraintlayout` 2.2.0-alpha04
- Local mirror used for porting: a clone at `inspo/constraintlayout` in the
  repository root. It is git-ignored and local only, not part of the
  repository.

That commit is the final commit of the GitHub repository; ConstraintLayout
development moved to the AOSP androidx monorepo
(https://android.googlesource.com/platform/frameworks/support, under
`constraintlayout/`), which is where the 2.2.x / core 1.1.x releases ship
from.

Parity with released versions (first verified 2026-07-24 against the AOSP
`androidx-constraintlayout-release` branch, versioned core 1.1.2-dev, which
includes everything in core 1.1.1 / constraintlayout 2.2.1; rechecked
2026-10-24 against the source jars of the released `constraintlayout-core`
1.1.0 and 1.1.1 on Google Maven, which constraintlayout 2.2.0 and 2.2.1
depend on):

- Within the solver classes, `widgets/`, and `widgets/analyzer/`, the only
  source change since the pinned commit is `LinearSystem.sPoolSize` becoming
  an instance field (change I8952e, b/376718273), present from core 1.1.0
  onward. That fix is applied in this port (`_poolSize` in
  `linear_system.dart`), so this scope is at parity with core 1.1.1.
- `utils/GridCore`, the one other ported file, is not at parity yet: core
  1.1.0 changed it after the pin, and this port still follows the pinned
  commit. Released `GridCore` stores its flags as an int bitmask
  (`SUB_GRID_BY_COL_ROW = 1`, `SPANS_RESPECT_WIDGET_ORDER = 2`) instead of an
  `int[]`; pads (with 1) or trims a row or column weight list whose length
  does not match the track count, where the pinned code ignores the whole
  list; reads an unparsable weight as 1; and sorts spans by position before
  placing them.
- Every other post-pin core change is in code this port does not include
  (`motion/`, `parser/`, `state/`). Between 1.1.0 and 1.1.1 the only core
  change is in `state/Dimension`.

Scope ported from `core/src/main/java/androidx/constraintlayout/core/`:

- `widgets/` and `widgets/analyzer/`: widget model + the dependency-graph
  resolver (phase 1).
- The `LinearSystem` Cassowary-style solver and its supporting classes
  (phase 2): `SolverVariable`, `ArrayRow`, `ArrayLinkedVariables`,
  `SolverVariableValues`, `GoalRow`, `PriorityGoalRow`, `Cache`, `Pools`.
- Virtual layouts (phase 3): `VirtualLayout`, `Flow` (with the upstream
  FlowTest suite), and `utils/GridCore`.

Not ported: `motion/`, `parser/`, `dsl/`, `state/` (the Flutter adapter plays
that role), `utils/GridEngine` (a standalone cell-placement class that
`GridCore` does not use), `Placeholder`, the `Direct`/`Grouping` optimizers
(the dependency graph plays that role), and `Metrics` instrumentation.

Known intentional divergences from upstream are documented inline at the
relevant code, and include:

- Dart `double` is used where Java uses 32-bit `float`; a handful of golden
  test values differ by 1 to 2 px from upstream because of this and carry a
  `closeTo` note where adjusted.
- `DependencyGraph.directMeasure` treats a measures-only invalidation as a
  graph invalidation (run reset destroys graph edges; upstream masks this via
  its solver fallback path).
- GONE widgets get their runs' dimension behaviour reset to pristine defaults
  in `_basicMeasureWidgets` (upstream leaves stale state that its solver
  fallback hides).
- Layout entry differs structurally: upstream's default path is the solver
  with optional graph optimization; this port tries the dependency graph
  first and falls back to the ported solver when the graph cannot faithfully
  resolve. The graph declines (routes to the solver) for: chains with GONE or
  ratio-sized members, chains along a wrap-content axis, MATCH_CONSTRAINT_WRAP
  widgets, circular (center) constraints, nested containers, widgets centered
  along a wrap axis, wrap results whose children overflow the computed
  bounds, and wrap results larger than the container's max size
  (`setMaxWidth`/`setMaxHeight`, which upstream's solver applies to a
  wrap-content container in `addToSolver` and the graph's wrap computation
  ignores). It also falls back whenever a run is left unresolved. As in
  upstream, that is always the case for a layout that contains a barrier: the
  barrier's `HelperReferences` run only ever resolves its start, never its end
  or dimension. Pre-graph widget state is snapshotted and restored before the
  fallback, and wrap-sized children are re-measured, so the solver sees the
  same input upstream's would. After the fallback solve, children with a
  solver-sized axis (a matchConstraint axis with both anchors, or a
  MATCH_CONSTRAINT_WRAP axis, which the solver caps) and a content-sized
  other axis (wrapContent or MATCH_CONSTRAINT_WRAP) are measured again, with
  TRY_GIVEN_DIMENSIONS and then USE_GIVEN_DIMENSIONS, and the layout is solved
  again when a size changed. Upstream runs that loop in
  `BasicMeasure.solverMeasure`, around `layout()` (which does not measure
  again after solving), for every widget with a matchConstraint axis; the
  port runs it only for those combinations.
- Upstream's "width/height measured too small" clamp in the solver loop is
  omitted: it relies on the unported Direct optimizer pre-sizing wrap
  containers, and would wrongly squash wrap containers whose entry size is
  smaller than their content.
- `_basicMeasureWidgets` passes the widget's real dimension (not 0) as the
  fixed-axis measure hint for MATCH_CONSTRAINT_WRAP measures, so the measure
  pass cannot destroy fixed sizes the solver later needs.
- `addToSolver`'s center-point rows are guarded on a non-NaN circle angle
  (upstream would emit NaN rows for plain center connects, a path none of its
  tests exercise).
- `NestedLayout.testNestedLayout` stays skipped: it is disabled upstream too
  (its `@Test` is commented out) and expects a stale coordinate convention.
- Percent-sized matchConstraint dimensions are clamped by the matchConstraint
  min/max at their graph resolve sites (`_basicMeasureWidgets` and the
  widget-run percent cases). Upstream leaves these resolves unclamped and
  relies on its solver-first entry to apply the bounds; this engine resolves
  percent in the graph, so the clamp happens at the resolve site.
- Virtual layouts always route to the solver (added to the graph decline
  rules): their addToSolver pass is what creates the member constraints.
  Before the solver runs, layout()'s fallback measures virtual layouts with
  `SELF_DIMENSIONS` so a matchConstraint axis measures against the available
  space instead of a not-yet-solved zero size (upstream reaches the same
  state through its solverMeasure loop).
- `GridCore.measure` reports incoming EXACTLY sizes as its measured size.
  Upstream leaves the measured size untouched because its Compose host only
  sizes grids through the solver; a fixed-size grid measured through a host
  measurer would otherwise collapse to 0.

When updating the port, bump the commit above and re-run the full golden test
suite (`dart test`).

## Ported upstream tests

The upstream core unit tests
(`constraintlayout/core/src/test/java/androidx/constraintlayout/core/` at the
pinned commit) are ported under `test/`. Each Dart file keeps the upstream
class name as its `group` and every test method's name, so a failure maps
straight back to its Java original. `test/PORTING_GUIDE.md` describes the
conversion.

| Upstream test class | Dart file | Tests |
| --- | --- | --- |
| `AdvancedChainTest` | `advanced_chain_test.dart` | 11 |
| `AmountTest` | `amount_test.dart` | 6 |
| `BarrierTest` | `barrier_test.dart` | 17 |
| `BasicTest` | `basic_test.dart` | 21 |
| `CenterWrapTest` | `center_wrap_test.dart` | 7 |
| `ChainTest` | `chain_test.dart` | 38 |
| `ChainWrapContentTest` | `chain_wrap_content_test.dart` | 7 |
| `CircleTest` | `circle_test.dart` | 1 |
| `EquationVariableTest` | `equation_variable_test.dart` | 6 |
| `FlowTest` | `flow_test.dart` | 3 |
| `GuidelineTest` | `guideline_test.dart` | 2 |
| `LinearEquationTest` | `linear_equation_test.dart` | 15 |
| `LinearSystemTest` | `linear_system_test.dart` | 9 |
| `MatchConstraintTest` | `match_constraint_test.dart` | 4 |
| `NestedLayout` | `nested_layout_test.dart` | 1, skipped (see above) |
| `OptimizationsTest` | `optimizations_test.dart` | 37 |
| `PriorityTest` | `priority_test.dart` | 2 |
| `RatioTest` | `ratio_test.dart` | 34 |
| `SolverVariableValuesTest` | `solver_variable_values_test.dart` | 7 |
| `VisibilityTest` | `visibility_test.dart` | 2 |
| `WidgetsPositioningTest` | `widgets_positioning_test.dart` | 15 |
| `WrapTest` | `wrap_test.dart` | 16 |
| `widgets/ChainHeadTest` | `chain_head_test.dart` | 4 |

That is 265 tests: every active upstream test in those files, plus
`NestedLayout.testNestedLayout`, which is disabled upstream and skipped here.

Three of those tests are ported only in part, without the solver runs upstream
makes. In `WidgetsPositioningTest`, `testBaselinePositioning` keeps its
`layout()` assertion but drops the repeat of it after solving the widgets in
every order (`runTestOnWidgets`), `testWidgetPositionMove` asserts its widths
without solving at all, and `testWidgetInfeasiblePosition`, whose assertions
are commented out upstream, connects its widgets without solving. The full
upstream bodies pass against this engine (checked 2026-10-24).

`WidgetsPositioningTest` also has two methods whose `@Test` is commented out
upstream (`testAddingWidgets` and `testWidgetStrengthPositioning`); they are
not ported. The test support classes `Amount`, `EquationVariable`, and
`LinearEquation` are ported under `test/support/`. The remaining upstream
helpers (`ArrayBackedVariables`, `HistogramCounter`, `OptimizedGoal`,
`OriginalGoal`, and `widgets/BasicSolverVariableValues`) are used by no test
and are not ported.

The other test files are the engine's own, not derived from upstream:
`anchor_api_test.dart`, `barrier_modes_test.dart`, `flow_modes_test.dart`,
`grid_modes_test.dart`, `max_dimension_test.dart`,
`measure_ordering_test.dart`, `persistent_layout_test.dart`, and
`smoke_test.dart`. No upstream core test sets a max width or height, so the
expected values in `max_dimension_test.dart` were taken from upstream's Java
engine at the pinned commit, run on the same layouts.

Not ported, although in scope:

| Upstream test class | Tests | Why |
| --- | --- | --- |
| `utils/GridEngineTest` | 10 | It tests `utils/GridEngine`, a standalone cell-placement class that upstream's `GridCore` does not use and that is not ported. The ported `GridCore`'s placement rules (derived rows and columns, spans, skips, and weights) are covered instead by the engine's own `grid_modes_test.dart`. |
| `LayoutTest` | 1 | `testPositions` asserts nothing: it times one layout of a screen of buttons and prints the solver's state. |
| `ArrayLinkedVariablesTest` | 1 | Its one test adds and removes variables in a row and prints it, and its only assertion is `assertTrue(true)`. `ArrayLinkedVariables` is the default row storage of `ArrayRow`, so every test that reaches the solver exercises it. |
| `ComposeLayoutsTest` | 1 | It builds its layout through the Compose-facing `state/` API (`State`, `ConstraintReference`, `Dimension`), which is not ported. Porting it means re-expressing that layout with direct widget calls. |

Out of scope:

| Upstream test | Why |
| --- | --- |
| `RandomLayoutTest` | It needs the Scout auto-constrainer (`scout/`, `Scout.inferConstraints`) and `java.awt.Rectangle`. |
| `PerformanceTest` | A performance probe: one layout of three widgets, printed, with no assertions. |
| `XmlBasedTest` | It runs over Android XML layout fixtures in upstream's `src/test/resources/`, parsed with SAX. |
| `motion/` (14 files) | MotionLayout, which is not ported. |
| `parser/` (`CLParserTest`, `CLParserBenchmarkTest`) and `cl/ConstraintSetParserTest` | The JSON5 parser and the ConstraintSet parser built on it (`parser/` and `state/`), which are not ported. |
| `dsl/DslTest` | The `dsl/` package, which is not ported. |
| `scout/` | Not tests: the Scout auto-constrainer that `RandomLayoutTest` uses. |

## Licensing

Every ported file, under `lib/src/` and among the tests ported from
upstream's core test suite (including their `test/support/` classes), keeps
its upstream copyright line
(`Copyright (C) <year> The Android Open Source Project`), adds
`Modifications copyright (C) 2026 Birju Vachhani`, and carries
`SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause`. See `LICENSE` for both
license texts.
