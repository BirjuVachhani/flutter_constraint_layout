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
- `utils/GridCore` changed in core 1.1.0 (and not again in 1.1.1), and the
  port follows the released file, so it is at parity with core 1.1.1 too
  (checked 2026-10-24 by diffing the pinned `GridCore.java` against the 1.1.1
  sources jar). Released `GridCore` stores its flags as an int bitmask
  (`SUB_GRID_BY_COL_ROW = 1`, `SPANS_RESPECT_WIDGET_ORDER = 2`, read live
  through `isSubGridByColRow()` and `isSpansRespectWidgetOrder()`) instead of
  an `int[]` copied into sticky booleans; pads (with 1) or trims a row or
  column weight list whose length does not match the track count, where the
  pinned code ignored the whole list; reads an unparsable weight as 1; and
  sorts the spans and skips by position before placing them. The "core
  1.1.1" groups of `test/grid_modes_test.dart` check each of these against
  the released `GridCore`, compiled from the 1.1.1 sources jar and run on a
  JDK. `utils/GridEngine` is unchanged since the pin.
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
- `utils/GridEngine`, a standalone cell-placement class that `GridCore` does
  not use, with the upstream GridEngineTest suite.

Not ported: `motion/`, `parser/`, `dsl/`, `state/` (the Flutter adapter plays
that role), `Placeholder`, `widgets/Rectangle` (only `motion/` uses it), the
`Direct`/`Grouping` optimizers (the dependency graph plays that role), and
`Metrics` instrumentation.

Known intentional divergences from upstream are documented inline at the
relevant code, and include:

- Dart `double` is used where Java uses 32-bit `float`; a handful of golden
  test values differ by 1 to 2 px from upstream because of this and carry a
  `closeTo` note where adjusted. The precision can also decide which
  solution the solver reaches. In an over-constrained layout, such as a
  weighted chain whose content does not fit a track (a grid tile as tall as
  its weighted row, or taller), two pivot candidates of the priority goal row
  can tie exactly; each precision's rounding noise breaks the tie its own
  way, and the two solutions can be tens of pixels apart. Upstream's float
  solver also reaches a collapsed solution for some of these layouts.
  `PriorityGoalRow` therefore treats goal strengths within its epsilon
  (0.0001) as equal, so the candidate found first keeps the pivot, where
  upstream compares them exactly. Over 640 weighted 2 x 2 grids of
  fixed-size tiles, this reaches the weighted cell geometry every time;
  upstream's float solver missed it 20 times, and the exact comparison in
  double 30 times. Inputs that are not exact in float, such as a bias of
  0.3, can still steer the two engines to different solutions.
- `DependencyGraph.directMeasure` treats a measures-only invalidation as a
  graph invalidation (run reset destroys graph edges; upstream masks this via
  its solver fallback path).
- GONE widgets get their runs' dimension behaviour reset to pristine defaults
  in `_basicMeasureWidgets` (upstream leaves stale state that its solver
  fallback hides).
- `DependencyNode.clear()` also resets the node's margin, margin factor,
  margin dependency, and update delegate (`mMargin`, `mMarginFactor`,
  `mMarginDependency`, `updateDelegate`), so a cleared node is a fresh one;
  upstream's keeps them from the graph the node was last wired into. Every
  node is cleared before the graph is wired again, and `addTarget` gives a
  node a plain margin without dropping a margin dependency that
  `addTargetDimension` gave it in an earlier graph, so `update()` went on
  computing the margin from that stale dimension. This entry and the next two,
  with the `layout()` entry after them, make a container laid out again give
  what a freshly built one gives, when each changed widget is configured as a
  new one would be (as the Flutter adapter does); as upstream, a size override
  the solver loop left pending is applied by the next layout. Android's default level never builds the
  graph, so it never wires one twice; this engine keeps a container across
  layouts (the Flutter adapter keeps one per `ConstraintLayout` and updates a
  changed child in place) and builds the graph again on every `layout()`.
- `VerticalWidgetRun.reset()` drops the run's baseline dimension
  (`mBaselineDimension`), as a fresh run has none; upstream's keeps the one
  from the last graph. `apply()` creates one only while the height is
  unresolved, and the graph never measures a gone widget, so a widget that
  turned gone kept the baseline of its last visible measure. With the stale
  margin dependency of the entry above, a widget on the baseline of a sibling
  that turned gone sat that sibling's last baseline distance below where a
  fresh container, and Android, put it.
- `HorizontalWidgetRun.reset()` and `VerticalWidgetRun.reset()` set the run
  type (`mRunType`) back to none; upstream's keep the type from the last
  graph. `apply()` sets it only for a widget linked on both sides of the
  axis, so a centered widget that had since lost one of those links still
  updated as centered, and `updateRunCenter` read the missing target: a null
  check that threw out of `layout()` here, and a `NullPointerException`
  upstream. The Flutter adapter reached it through an in-place update.
  `test/persistent_layout_test.dart` checks that such a widget lays out as in
  a fresh container.
- `ConstraintWidgetContainer.layout()` starts by calling
  `resetFinalResolution()` on the container and on every child, which forgets
  the final positions that `setFinalHorizontal` and `setFinalVertical` gave
  them (`ConstraintWidget.resetFinalResolution`, ported without the
  solving-pass flags of the `Direct` pass). Upstream's `layout()` resets them
  only through `Direct.solvingPass`, which Android's default level runs in the
  first solve of every measure; this port runs no `Direct` pass, so
  `layout()` resets them on every call. Barriers still get final positions
  here: `Barrier.allSolved` resolves a barrier that counts no reference at its
  margin, through `setFinalHorizontal` or `setFinalVertical`, which then
  ignore every later call until a reset, and `Barrier.addToSolver` holds a
  resolved barrier at its stored position. Without the reset, such a barrier
  started each layout of the same container from the position the previous
  one reported, which the solver rounds a pixel towards 0 when it is
  negative, so it moved 1 px per layout where a fresh container, and Android,
  keep it in place. `test/persistent_layout_test.dart` lays one out four
  times and compares each layout with a fresh container.
- Layout entry differs structurally: upstream's default path
  (`OPTIMIZATION_STANDARD`, Android's default) is the `Direct` optimizer and
  then the solver, with optional graph optimization; this port has no `Direct`
  optimizer, tries the dependency graph first, and falls back to the ported
  solver when the graph cannot faithfully resolve. The graph declines (routes to
  the solver) for: chains with GONE, ratio-sized, or percent members (`ChainRun`
  spreads the space over every match-constraint member whose size is not
  resolved yet, and a percent size resolves late when the member's other axis is
  match-constraint too, so the chain gave it a share instead of its percent),
  chains along a wrap-content axis, chains with margins in a right-to-left
  container (upstream's `ChainRun` lays every chain there, vertical ones
  included, out from its end but applies each member's margins on the
  left-to-right side; Android's default optimization leaves the graph off and
  avoids this), MATCH_CONSTRAINT_WRAP widgets, circular (center) constraints,
  nested containers, widgets centered along a wrap axis, gone ones included
  (with a widget linked to a gone one, the wrap computation can come out larger
  than the solver's), match-parent widgets along a wrap axis
  (`_basicMeasureWidgets` gives them the container's incoming size, 0 for an
  unbounded Flutter constraint, where Android measures them and wraps the
  container around their measured size), wrap results whose children overflow
  the computed bounds, wrap results larger than the container's max size
  (`setMaxWidth`/`setMaxHeight`, which upstream's solver applies to a
  wrap-content container in `addToSolver` and the graph's wrap computation
  ignores), a wrap axis whose size the graph was asked to compute but could not
  (a run without wrap support, such as a barrier's or a guideline's, turns the
  computation off and would leave the container's incoming size in place), a
  widget that `setWrapBehaviorInParent` leaves out of a wrap axis (only
  `addToSolver` reads that setting), and a match-constraint axis the graph
  resolved below the widget's `setMinWidth`/`setMinHeight` (the solver resolves
  the same size, then `setFrame` raises it to the minimum and records an
  override, and the solver solves again with it fixed). A layout pass that
  starts with such an override still pending (the solver loop can stop before
  applying the last one) goes to the solver as well: upstream's next solve
  applies it, and the graph neither applies nor clears it, so it would otherwise
  wait for whichever later pass reaches the solver. It also declines a baseline
  link from a widget without a baseline after its measure (a baseline distance
  of 0, as a widget without text measures): `ConstraintWidget.addToSolver`
  applies a baseline link only when `mBaselineDistance > 0` or the widget is
  gone, and `Direct`'s `setFinalBaseline` does nothing without a baseline, so
  Android ignores the link where the graph would put the widget's top on its
  target. And it declines a result its own measure passes left stale: a size
  that resolved after the graph's last measure of the widget (`measureWidgets`
  runs a fixed number of times), or a chain whose members `ChainRun` left
  unplaced or at their measured sizes (it places members only once every
  member's size is known, and `updateFromRuns` sizes a member from its edges
  only after the spread-inside branch). A fixed member that the chain's rounded
  edges leave a pixel short, at a negative position, keeps its size, as
  `setFrame` keeps it on Android. It also falls back for a chain with no first
  or last member (see the chain-walk entry below) and whenever a run is left
  unresolved, as with a cycle. Barrier layouts stay on the graph only where a
  model of Android, upstream at `OPTIMIZATION_STANDARD`, places every widget
  where the graph does (see the barrier entry below, which also lists the
  differences that remain). Outside barrier layouts the graph is not checked
  against Android's rounding, so a layout it resolves can come out differently
  from the solver, as `README.md` describes under "How resolution works". In
  three cases the graph gives Android's result and the solver does not: a
  widget centered on a widget whose own centered position falls on a half
  pixel, a centered widget with a negative margin, and a widget linked to the
  end of a gone match-parent widget. `Direct` places those widgets in whole
  pixels as the graph does, and this engine's solver fallback, which runs
  without it, gives upstream's `OPTIMIZATION_NONE` result (checked 2026-10-25
  against upstream's Java engine at levels 0, 1, 256, and 257). `Direct`'s
  arithmetic is not quite the graph's, though: it works a centering offset out
  in Java floats, `(int) (0.5f + bias * distance)`, and truncates the offset of
  a widget that does not fit, `(int) (bias * distance)`, where the graph rounds
  in doubles, so a widget it centers can sit a pixel from the graph's position.
  Elsewhere the graph differs from Android: a negative position, which the
  graph keeps (-7) and upstream rounds a pixel towards zero at every level
  (-6), and a frame with a negative size, which upstream reports as 0 x 0 at
  0, 0; a fraction of a pixel that the graph rounds earlier than Android's
  solver (a percent or ratio size, a chain gap, a centered position that
  another widget is centered on), and a ratio size that Android truncates
  (`(int) (ratio * other)`) where the graph rounds; a match-constraint size
  with a min or a max, or between anchors that leave it no room, which the
  solver can set differently; the position of a gone widget that nothing
  references, or of a gone match-parent widget, which does not show; and the
  percent clamp below. A fuzz of layouts without barriers against upstream's
  Java engine at `OPTIMIZATION_STANDARD` (2026-10-25) found no other kind of
  difference where the solver matches Android, apart from half-pixel ties that
  floating-point noise decides. Upstream never lays a chain out on its graph:
  `BasicMeasure.solverMeasure` turns the graph off for any layout with a chain,
  even at `OPTIMIZATION_GRAPH`, while this engine keeps a chain on the graph
  unless one of the chain rules above applies (and places its members as the
  solver does; see the `ChainRun` entry below).
  Pre-graph widget state is snapshotted and restored before the fallback, and
  wrap-sized children are re-measured, so the solver sees the same input
  upstream's would. After the fallback solve, children with a solver-sized
  axis (any matchConstraint axis, including a percent or bounded size with
  only one anchor) and a content-sized other axis (wrapContent or
  MATCH_CONSTRAINT_WRAP) are measured again, with TRY_GIVEN_DIMENSIONS and then
  USE_GIVEN_DIMENSIONS. The layout is solved again when a size or baseline
  changes, or the measurer requests another pass. Changes from virtual layouts
  and ordinary children share that first follow-up solve. Upstream runs that
  loop in `BasicMeasure.solverMeasure`, around `layout()` (which does not
  measure again after solving), for every widget with a matchConstraint axis;
  the port runs it only for those combinations.
- Barriers resolve on the graph. Upstream's `HelperReferences` run only
  resolves its start, which fails `DependencyGraph`'s all-resolved check for
  every barrier layout; upstream's solver-first entry never needed more. Here
  `HelperReferences.update` also resolves the run's end (equal to its start)
  and its dimension (0), and seeds the outermost edge from the first
  reference (upstream seeds min with -1 as "unset" and max with 0, which
  loses a reference at -1 and puts a right or bottom barrier over references
  at negative positions at 0). It counts a reference the way
  `Barrier.addToSolver` does, through `allowedInBarrier` (upstream's graph
  skips a gone barrier inside a barrier that disallows gone widgets, where
  the solver counts it), and `applyToWidget` sets the barrier's other
  coordinate to 0, which the solver gives the axis it leaves unconstrained.
  The barrier's own run across its axis is exempt from the all-resolved check
  unless a widget is linked to that axis. The solver places a barrier through
  soft constraints (a hard bound from each reference, pulls towards its
  references at `STRENGTH_HIGHEST`, or `STRENGTH_EQUALITY` when a widget is
  centered on the barrier and no reference is a two-link match-constraint
  widget, a `STRENGTH_HIGHEST` pull towards one container edge, and the range
  and bounds checks of the widgets centered on it), so it can settle a
  barrier off the outermost edge of its references.
  `DependencyGraph._barriersMatchSolver` keeps a barrier layout on the graph
  only where its model of Android, upstream at `OPTIMIZATION_STANDARD`, places
  every widget as the graph does. That level runs upstream's `Direct`
  optimizer, which this port does not run, before the solver;
  `analyzer/direct_resolution.dart` (port-only) models which axes it places
  and where, and a barrier it places is held there (`Barrier.addToSolver`,
  `USE_RESOLUTION`), so the soft pulls never move it.
  For every other barrier the check gathers what moves rigidly with it, adds
  up per strength how much every soft constraint touching that group changes
  for a 1 px move, and requires the move to cost more than it saves at the
  highest strength where the two differ, declining what it does not model
  (chains, baselines, ratios, and widgets that slide part of the way with a
  barrier while something depends on them). It also declines a negative
  position or size anywhere (the solver reports a position as
  `(int) (value + 0.5)`, a pixel towards zero when negative, and zeroes a
  frame with a negative size), a match-constraint size the solver sets
  differently, a minimum size set through `setMinWidth` or `setMinHeight`
  (the graph applies it over a match-constraint max, and where the solver
  leaves a size below it, `setFrame` raises it and Android solves again
  without `Direct`'s positions), an axis `Direct` places elsewhere than the
  graph (the model works `Direct` out in Java floats and truncates as it
  does), and, in the part `Direct` leaves to the solver, every place where
  that solver rounds or places a widget differently from the graph: fractions
  of a pixel the graph rounds earlier (percent and ratio sizes, chain gaps,
  centered positions that another widget is centered on, a percent height
  placed by its baseline), a baseline link to a gone widget with a baseline
  distance (the solver puts a gone widget's baseline on its top), overflowing
  chains, chains a barrier pulls on (through a reference that is a chain
  member, or that its links along the barrier's axis tie to one), and
  centered widgets with a negative margin. A stale graph result and a
  baseline link from a widget without a baseline go to the solver in every
  layout (see the layout entry above).
  Where upstream's `Direct` would throw (a stale dependent that lost its
  target) or recurse without end, `DirectResolution` stops and the check
  declines. Barrier layouts on the solver keep the results they had before.
  `test/barrier_parity_test.dart` checks the barrier layouts of the engine
  tests and a randomized fuzz against the solver and against Android
  (`StandardContainer` in `test/support/solver_parity.dart` applies the
  modelled `Direct` pass before the solver), and `test/barrier_gate_test.dart`
  pins each decline to upstream's results at `OPTIMIZATION_STANDARD`. Two
  kinds of difference from Android remain in the barrier layouts the graph
  keeps: a position exactly on a half pixel, which floating-point noise can
  round either way, and degenerate layouts that the solver lays out as the
  graph does and Android does not, such as one with a widget whose links
  cross, where declining would not give Android's result.
- `GuidelineReference.applyToWidget` sets the guideline's frame as
  `Guideline.updateFromSolver` does on the solver path (a line across the
  whole container, 0 thick); upstream's only sets the position.
- Upstream's "width/height measured too small" clamp in the solver loop is
  omitted: it relies on the unported Direct optimizer pre-sizing wrap
  containers, and would wrongly squash wrap containers whose entry size is
  smaller than their content.
- `RunGroup.computeWrapSize` returns null, and `DependencyGraph` leaves the
  wrap-content axis to the solver, when its traversals reach a node they are
  already inside: runs that depend on each other in a loop, such as a widget
  centered between the container's left and a sibling's right while the
  sibling's left is linked to the widget's right. Upstream's traversals
  recurse round such a loop until the stack overflows, but upstream computes
  a wrap size on the graph only with `OPTIMIZATION_GRAPH_WRAP`, which
  Android's default leaves off, and its solver lays these layouts out. The
  graph never resolves such a loop, so in a container of a fixed size the
  layout already went to the solver. `test/wrap_loop_test.dart` checks three
  such layouts against upstream's Java engine at `OPTIMIZATION_STANDARD`.
- `_basicMeasureWidgets` passes the widget's real dimension (not 0) as the
  fixed-axis measure hint for MATCH_CONSTRAINT_WRAP measures, so the measure
  pass cannot destroy fixed sizes the solver later needs.
- `_basicMeasureWidgets` measures a spread-style matchConstraint height that
  has a single anchor with the widget's own horizontal behaviour and width
  and a wrap-content height. Upstream repeats the width case's call there,
  `measure(widget, WRAP_CONTENT, 0, vertical, 0)`, which measures the width
  as wrap content (replacing a fixed width with the content's) and asks for
  the height at its stored size instead of around its content. Android's
  default optimization level leaves the graph off, and its solver path gets
  this right: upstream's Java engine, measuring through a port of the view
  layer's `ConstraintLayout.Measurer`, gives a fixed 100 px width over 500 px
  of text-like content w=100 h=100 at `OPTIMIZATION_STANDARD` but w=500 h=20
  with `OPTIMIZATION_GRAPH` (checked 2026-10-24).
- `VerticalWidgetRun` links a widget's baseline to its target with the
  link's margin (`mBaseline.getMargin()`, the gone margin when the target is
  gone). Upstream's graph links it with no margin, while
  `Direct.verticalSolvingPass` (`setFinalBaseline(baselineValue +
  first.getMargin())`) and `ConstraintWidget.addToSolver`
  (`addEquality(baseline, baselineTarget, mBaseline.getMargin())`) both add
  it, so Android's default path puts the widget where this graph now does
  (checked 2026-10-25 against upstream's Java engine at
  `OPTIMIZATION_STANDARD` and `OPTIMIZATION_NONE`). In Flutter this is
  `baseline: .baselineOf(#id, margin: n)`.
- `VerticalWidgetRun.apply` leaves the baseline link of a widget the graph
  has not measured unwired when the widget had no baseline as the graph was
  built (no `mBaselineDimension`); upstream reads it unconditionally and
  throws a `NullPointerException`, on the solver fallback too, since that
  builds the graph first. The widget's top stays unresolved and the layout
  goes to the solver, which ignores the link as Android does. Only the engine
  API reaches this: the Flutter adapter flags both ends of a baseline link
  before it connects them.
- `HorizontalWidgetRun.update` returns before centering when an edge has no
  target, as `VerticalWidgetRun.update` does upstream. Upstream's horizontal
  twin centers unconditionally and throws an `IndexOutOfBoundsException` for
  a chain member (its `ChainRun` owns its edges, which get no targets) whose
  percent width resolves through this update, such as the first member of a
  chain whose last member's end links nowhere. The edges stay unresolved and
  the graph declines. The Flutter adapter reached it: a `.percent()` width
  and a `.matchConstraint` height on a child whose `right` links to a sibling
  that links back with nothing on its own `right`.
- `WidgetRun.getLimitedDimension` applies the max to the value the min
  produced. Upstream applies it to the unbounded dimension
  (`Math.min(max, dimension)`), which drops the min whenever a max is set, so
  a spread size whose min exceeds the space between its anchors resolved to
  that space on the graph while the solver keeps the min (upstream's Java
  engine at `OPTIMIZATION_STANDARD`: w=300 for a min of 300 and a max of 400
  between anchors 200 apart).
- `ChainRun.update` keeps member positions and match-constraint sizes exact
  and resolves each member edge the way the solver reports a position,
  `(int) (value + 0.5)` (`LinearSystem.getObjectVariableValue`), so a
  match-constraint member's size is the distance between its rounded edges.
  Upstream rounds each gap (a spread or spread-inside gap down, a packed
  chain's offset half up) and each match-constraint size (half up) first, and
  adds the rounded values up: two match-constraint members of a 375 px
  container came out 188 px each and overflowed it by 1 px, five fixed
  members of a spread chain could end 4 px short of the solver's positions,
  and in right-to-left text the error fell on the other end. Upstream's own
  graph, run directly, still gives those values, but Android never sees them:
  `BasicMeasure.solverMeasure` never runs the graph on a chain, and chains are
  the same at `OPTIMIZATION_STANDARD` as at `OPTIMIZATION_NONE` (the Direct
  optimizer does not place them). Over 42,000 horizontal chains (2 to 5
  fixed, match-constraint or mixed members, the three styles, with and
  without weights and margins, both directions, widths 300 to 420 px and
  1000 to 1081 px) the graph now gives upstream's Java engine's result at
  `OPTIMIZATION_STANDARD` in 99.8 percent of the layouts it resolves (54
  percent before), and over their 21,000 vertical counterparts in 99.7
  percent. The rest have an edge exactly on a half pixel, which Android's
  32-bit floats can round either way (this engine's 64-bit solver rounds
  2,411 of the 42,000 differently from Android too). `ChainRun` snaps a sum
  within a millionth of a pixel of a half to the half before rounding, as
  the exact positions it adds up are fractions with small denominators.
  `test/chain_rounding_test.dart` checks representative chains against
  upstream's Java engine.
- `addToSolver`'s center-point rows are guarded on a non-NaN circle angle
  (upstream would emit NaN rows for plain center connects, a path none of its
  tests exercise).
- `NestedLayout.testNestedLayout` stays skipped: it is disabled upstream too
  (its `@Test` is commented out) and expects a stale coordinate convention.
- Percent-sized matchConstraint dimensions are clamped by the matchConstraint
  min/max at their graph resolve sites (`_basicMeasureWidgets` and the
  widget-run percent cases). Upstream leaves these resolves unclamped and
  relies on its solver-first entry to apply the bounds; this engine resolves
  percent in the graph, so the clamp happens at the resolve site. One case
  still resolves differently on the two paths: a percent size anchored on
  both sides whose min is above the percent keeps the min, centered between
  its anchors, on the graph, while the solver fills the space between the
  anchors (upstream's Java engine at `OPTIMIZATION_STANDARD`, measuring
  through a port of the view layer's `ConstraintLayout.Measurer`: w=780 for a
  percent of 0.1 and a min of 200 between anchors 780 apart, checked
  2026-10-24).
- Virtual layouts always route to the solver (added to the graph decline
  rules): their addToSolver pass is what creates the member constraints.
  Before the solver runs, layout()'s fallback measures virtual layouts with
  `SELF_DIMENSIONS` so a matchConstraint axis measures against the available
  space instead of a not-yet-solved zero size. After the first solve it
  measures those with a matchConstraint axis again with
  `TRY_GIVEN_DIMENSIONS`, at the size the solver resolved, and re-solves, so a
  `Flow` narrower than the container wraps its rows within its own bounds.
  Upstream reaches the same state through solverMeasure, which runs both
  measures around its first solve.
- `GridCore.measure` reports incoming EXACTLY sizes as its measured size.
  Upstream leaves the measured size untouched because its Compose host only
  sizes grids through the solver; a fixed-size grid measured through a host
  measurer would otherwise collapse to 0.
- `WidgetContainer.remove()`, which `add()` also calls for a widget that
  already has a parent, only clears the widget's parent. Upstream's also
  resets the widget (`ConstraintWidget.reset()`, not ported), which clears its
  connections, size, and every other attribute. `GridCore.measure()` adds its
  box widgets to the container again on every measure, as upstream's does,
  and this engine measures virtual layouts again in layout()'s solver
  fallback, so a reset would wipe the boxes' setup: with upstream's
  `remove()`, the weighted grids in `grid_modes_test.dart` lose their
  weights. Upstream's own grid collapses, every cell to 0 x 0, when the same
  container is measured a second time (checked on the pinned commit; released
  core 1.1.1 has the same code). `LayoutTest` adds one widget twice, so its
  port shows the difference.
- `GridCore` mirrors its columns in a right-to-left container
  (`ConstraintWidgetContainer.isRtl()`, read on every solve, as `Flow` reads
  it). Upstream's `GridCore` leaves this as `@TODO handle RTL`, and Android's
  view-based `Grid` reads a `grid_useRtl` attribute that it never applies.
  The box chain still runs left to right; `connectWidget` puts logical column
  `c` (with a span of `s` columns) on boxes `columns - c - s` to
  `columns - 1 - c`, and `setBoxWidgetHorizontalChains` gives box `i` the
  weight of column `columns - 1 - i`. Cell positions in spans and skips and
  the column weights still count from the first (now rightmost) column, and
  the result is the mirror image of the left-to-right grid within the grid's
  bounds: `x_rtl = gridLeft + gridRight - (x_ltr + width)`, for members
  that fill or are centered in their cells. A member's own horizontal bias
  stays absolute, as every engine widget's does; the Flutter adapter
  measures it from the start edge for the widgets a grid places, as it does
  for start/end-linked children, so a biased member mirrors too. The solver's
  fractional solution mirrors exactly; a column edge that lands exactly on a
  half pixel rounds the same way in both directions, so it can sit 1 px off
  the mirror.
- `GridCore` places its widgets from scratch on every solve: `addToSolver`
  first resets the cells, the handled spans, and the
  `SPANS_RESPECT_WIDGET_ORDER` span cursor (through `setupGrid`'s update
  path, which upstream never calls) and applies the skips and spans again.
  Upstream arranges the widgets on top of the cells the previous solve took,
  and a layout can solve several times (the `measure` then `layout()` of
  `grid_modes_test.dart` solves four times), as does every later layout of
  the same grid, so in a grid with free cells each solve moved the widgets
  on into them. On upstream's Java engine, a 3 x 3 grid of four widgets
  spanning `0:1x2` and skipping `4:1x1` ends with the last three widgets in
  the bottom row instead of in cells 2, 3, and 5.
- `GridCore.addToSolver` adds nothing beyond the grid's own constraints when
  the grid built no box widgets: it has no widgets, so a derived track count
  is 0, or it was never measured. Upstream dereferences the missing boxes,
  and the exception, which its `ConstraintWidgetContainer.layout` catches and
  prints, abandons the whole solve, so an empty grid (a grid fed from an
  empty list) left every other widget in the layout unplaced.
- `GridCore` ignores the span entries past its last widget. Upstream gives
  span entry `i` to widget `i` and dereferences a missing widget, so a spans
  string with more entries than the grid has widgets (a grid fed from a list
  that is empty, or shorter than the spans expect) throws from `measure()`,
  which no layout code catches, and the whole layout fails.
- `GridCore` reads the numbers in its span and skip strings with Dart's
  `int.parse`, which ignores surrounding whitespace where Java's
  `Integer.parseInt` rejects it. The span sort released in core 1.1.0 parses
  each position without trimming it, so upstream ignores the whole spans or
  skips string when it has a space after a comma (`'0:2x1, 4:1x2'`); this
  port sorts and places it, as both did before the sort. The sort keeps
  entries at the same position in their listed order, as Java's stable sort
  does. Weights are read with `double.tryParse`, which, unlike Java's
  `Float.parseFloat`, rejects a trailing `f` or `d` and hexadecimal floats;
  such an entry counts as unparsable and reads as 1.
- `GridCore` and `GridEngine` handle some more input differently from
  upstream, where upstream throws or leaves widgets unplaced:
  `GridCore.measure` derives the missing track count from the current number
  of widgets (upstream derives it only in the constructor and in
  `setRows`/`setColumns`, so a grid configured before its widgets are added
  keeps 0 tracks and throws from `measure()`); `GridCore` tracks the widgets
  whose span it placed by identity, where upstream tracks their `stringId`
  and, with the core default of null, skips every other widget once one span
  is placed; `setRows` and `setColumns` ignore a negative count, which
  upstream stores and then fails on (`NegativeArraySizeException`); a
  negative cell position in spans or skips wraps to the end of its row or
  column (Dart's `%` is never negative), where upstream throws
  `ArrayIndexOutOfBoundsException`; and `int.parse` reads a hexadecimal
  position such as `0x1`, which `Integer.parseInt` rejects, so upstream's
  `GridCore` ignores that whole list and its `GridEngine` throws.
- Chain walks stop when they go round a loop. A widget's neighbour in a chain
  is the owner of an anchor that its own anchor targets and that targets it
  straight back, whatever the sides of the two anchors, so two widgets whose
  matching anchors link to each other (two tops, for example), an anchor
  linked to itself (a widget whose left links to its own left), or two
  widgets linked both ways on both sides form a chain with no first or last
  member. Upstream's `ChainRun` walks such a loop forever (and, walking
  forward, grows its member list until memory runs out), but upstream never
  builds one: `BasicMeasure.solverMeasure` keeps the graph off for any layout
  with a chain member, and its solver lays these layouts out, so they finish
  on Android. This engine builds the graph first, so `ChainRun` stops after
  more steps than its container has children and marks itself `cyclic`, and
  `DependencyGraph.directMeasure` declines a layout with a cyclic chain: the
  solver then lays it out as upstream's does. The solver's own walks,
  `ChainHead.defineChainProperties` and `Chain.applyChainConstraints`, never
  end either, upstream's included, for a chain whose first member's start
  links one way to its last member, while the last member's end links back to
  the first (a widget whose start and end both link to a second one that
  links back, or a widget whose start and end both link to its own end);
  they stop at the first member here. Of these loops, that is the only one
  Android never finishes laying out. Checked 2026-10-25 against upstream's
  Java engine at `OPTIMIZATION_STANDARD` and `OPTIMIZATION_GRAPH` on every
  set of links among the edges of two widgets (both axes, with baselines,
  gone widgets and wrap-content containers) and among the horizontal edges
  of three: upstream finishes wherever only the graph's walk loops, and
  never returns wherever the solver's walk loops. `test/link_loop_test.dart`
  covers both.
- `ArrayRow.updateFromSystem` gives up after a bounded number of rounds.
  Upstream substitutes the definitions of the row's defined, final, and
  synonym variables until none is left, which takes at most one round per
  variable of the system unless those definitions refer back to each other.
  Some layouts leave definitions that do: a cyclic barrier layout with a
  match-constraint widget below its `setMinWidth` or `setMinHeight`, solved
  again after `setFrame` records the override, and a few degenerate layouts
  that combine links to a widget's own anchors with match-constraint sizes in
  a wrap-content container. Upstream's Java engine hangs on the barrier
  layout of `test/frame_override_test.dart` at `OPTIMIZATION_NONE` and
  `OPTIMIZATION_STANDARD`, and on 9 of the 10 degenerate layouts that a
  random sweep of 400,000 found, in this loop or in its chain walk. Here the
  loop throws a `StateError` once it has taken more rounds than the system
  has rows and variables, and the catch around each solve in
  `ConstraintWidgetContainer.layout()`, which upstream's `layout()` has too
  and which prints the error, ends that solve with the values it had
  reached. Run over 240,000 layouts from the generators of
  `test/barrier_parity_test.dart`, the bound never fired.

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
| `ArrayLinkedVariablesTest` | `array_linked_variables_test.dart` | 1 |
| `BarrierTest` | `barrier_test.dart` | 17 |
| `BasicTest` | `basic_test.dart` | 21 |
| `CenterWrapTest` | `center_wrap_test.dart` | 7 |
| `ChainTest` | `chain_test.dart` | 38 |
| `ChainWrapContentTest` | `chain_wrap_content_test.dart` | 7 |
| `CircleTest` | `circle_test.dart` | 1 |
| `ComposeLayoutsTest` | `compose_layouts_test.dart` | 1 |
| `EquationVariableTest` | `equation_variable_test.dart` | 6 |
| `FlowTest` | `flow_test.dart` | 3 |
| `GuidelineTest` | `guideline_test.dart` | 2 |
| `LayoutTest` | `layout_test.dart` | 1 |
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
| `utils/GridEngineTest` | `grid_engine_test.dart` | 10 |
| `widgets/ChainHeadTest` | `chain_head_test.dart` | 4 |

That is 278 tests: every active upstream test in those files, plus
`NestedLayout.testNestedLayout`, which is disabled upstream and skipped here.
`GridEngineTest` is ported from AOSP's `androidx-constraintlayout-release`
branch, where it sits in the `utils` package; its tests are the same as at the
pinned commit.

Every one of them runs its full upstream body, including the passes in which
`WidgetsPositioningTest` adds its widgets to the solver in every possible
order and solves them directly (`runTestOnWidgets`). Two ports also check
more than upstream does, and mark those checks as not upstream's. Their
expected values come from upstream's Java engine at the pinned commit, run on
the same input:

- `LayoutTest.testPositions` only prints how long one layout of a screen of
  buttons took, and the solver's table sizes. Its port checks every frame.
  The layout adds one widget twice, and upstream's `WidgetContainer.remove()`
  resets that widget on the second add where this engine's does not (see the
  divergences above), so the expected frames are upstream's for the widget
  moved without the reset.
- `ArrayLinkedVariablesTest.testNestedLayout` adds and removes variables in a
  row and prints it after each step; its only assertion is `assertTrue(true)`.
  Its port checks the row at each of those prints, and the final row.

`ComposeLayoutsTest` builds its layout through the Compose-facing `state/` API
(`State`, `ConstraintReference`, `Dimension`), which is not ported. Its port
makes the widget calls that `State.apply()` makes, in the same order, and keeps
upstream's assertions. Run on upstream's Java engine, that translation matches
the `State` version call for call. The test file's header explains the
mapping.

`WidgetsPositioningTest` also has two methods whose `@Test` is commented out
upstream (`testAddingWidgets` and `testWidgetStrengthPositioning`); they are
not ported. The test support classes `Amount`, `EquationVariable`, and
`LinearEquation` are ported under `test/support/`. The remaining upstream
helpers (`ArrayBackedVariables`, `HistogramCounter`, `OptimizedGoal`,
`OriginalGoal`, and `widgets/BasicSolverVariableValues`) are used by no test
and are not ported.

The other test files are the engine's own, not derived from upstream:
`anchor_api_test.dart`, `barrier_gate_test.dart`, `barrier_modes_test.dart`,
`barrier_parity_test.dart`, `chain_rounding_test.dart`, `flow_modes_test.dart`,
`flow_wrap_test.dart`, `frame_override_test.dart`, `graph_parity_test.dart`,
`grid_modes_test.dart`, `link_loop_test.dart`, `max_dimension_test.dart`,
`measure_ordering_test.dart`, `persistent_layout_test.dart`, `smoke_test.dart`,
`wrap_behavior_test.dart`, `wrap_bias_test.dart`, and `wrap_loop_test.dart`. No
upstream core test sets a max width or height, a widget minimum on a
match-constraint axis, or a wrap behavior, lays out a bias of exactly 1 along a
wrap-content axis or links that loop back on themselves, or runs a chain or a
barrier layout through the dependency graph (upstream never lays either out on
its graph). So the expected values in `max_dimension_test.dart`,
`frame_override_test.dart`, `wrap_behavior_test.dart`, `wrap_bias_test.dart`,
`link_loop_test.dart`, `wrap_loop_test.dart`, `chain_rounding_test.dart`,
`graph_parity_test.dart`, and `barrier_gate_test.dart` were taken from
upstream's Java engine at the pinned commit, run on the same layouts; where
upstream never returns, as for a chain whose first member's start links one
way to its last member while the last member's end links back to the first,
the test checks that the layout finishes. `barrier_parity_test.dart`
compares the graph path with the solver path
(`test/support/solver_parity.dart`) instead, and
`persistent_layout_test.dart` compares a container laid out again after a
change with a freshly built one.

Not ported, as out of scope:

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
