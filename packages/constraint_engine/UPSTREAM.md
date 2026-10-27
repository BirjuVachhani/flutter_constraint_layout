# Upstream provenance

This package is a Dart port of Android ConstraintLayout's layout pipeline:
`androidx.constraintlayout.core`, the platform-independent engine, and the
measure pass of the ConstraintLayout view (`ConstraintLayout.java`).

Pinned upstream revision the port represents:

- Repository: https://github.com/androidx/constraintlayout
- Commit: `9cd4b5a4079a14175f91dc897abd83270799364a` (main, 2023-10-24)
- Library versions at that commit (`constraintlayout/gradle.properties`):
  - `constraintlayout.core` **1.1.0-alpha04**
  - `constraintlayout` 2.2.0-alpha04
- Local mirror used for porting: a clone at `inspo/constraintlayout` in the
  repository root. It is git-ignored and local only, not part of the
  repository. The parity tooling (`tool/parity/README.md`) clones the same
  commit and compiles its core.

That commit is the final commit of the GitHub repository; ConstraintLayout
development moved to the AOSP androidx monorepo
(https://android.googlesource.com/platform/frameworks/support, under
`constraintlayout/`), which is where the 2.2.x / core 1.1.x releases ship
from.

Parity with released versions (first verified 2026-07-24 against the AOSP
`androidx-constraintlayout-release` branch, versioned core 1.1.2-dev, which
includes everything in core 1.1.1 / constraintlayout 2.2.1; rechecked
2026-10-24 against the source jars of the released `constraintlayout-core`
1.1.0 and 1.1.1 and `constraintlayout` 2.2.1 on Google Maven):

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
- The released view layer (`constraintlayout` 2.2.1) differs from the pinned
  one only in branches for API levels below 17, in `ConstraintSet` loading
  from XML, in motion classes and in `Grid`: on API 17 and later its measure
  pass is code-identical (`tool/parity/FORMATS.md` 13 lists every file). The
  parity oracle's check on real views runs the released 2.2.1 view layer, and
  gives the same frames with the pinned core and with core 1.1.1.
- Every other post-pin core change is in code this port does not include
  (`motion/`, `parser/`, `state/`). Between 1.1.0 and 1.1.1 the only core
  change is in `state/Dimension`.

Scope ported from `core/src/main/java/androidx/constraintlayout/core/`:

- `widgets/` and `widgets/analyzer/`: the widget model, the dependency graph,
  and the `Direct` pass (`analyzer/direct.dart`; `Direct.solveChain` is left
  out, dead at the pin since `Chain.USE_CHAIN_OPTIMIZATION` is false).
- The `LinearSystem` Cassowary-style solver and its supporting classes:
  `SolverVariable`, `ArrayRow`, `ArrayLinkedVariables`,
  `SolverVariableValues`, `GoalRow`, `PriorityGoalRow`, `Cache`, `Pools`.
- Virtual layouts: `VirtualLayout`, `Flow` (with the upstream FlowTest
  suite), and `utils/GridCore`.
- `utils/GridEngine`, a standalone cell-placement class that `GridCore` does
  not use, with the upstream GridEngineTest suite.

Ported from the view layer (`constraintlayout/src/main/java/androidx/
constraintlayout/widget/ConstraintLayout.java`, "CL" below) into
`lib/src/view/`: `onMeasure`'s dirty path (`ViewHost`), the child `Measurer`
(`ViewMeasurer`, with one hook for the child view's own `onMeasure`), the
anchor state `setChildrenConstraints` leaves (`rebuildViewDependents`), and
Android's `View.MeasureSpec` helpers (`MeasureSpec`).

Comments cite upstream files by a short name and line numbers at the pin:
CL (above) and CH (`ConstraintHelper.java`, beside it in `widget/`); CW,
CWC, BR and GL (`ConstraintWidget.java`, `ConstraintWidgetContainer.java`,
`Barrier.java` and `Guideline.java` in the core's `widgets/`); and BM and D
(`BasicMeasure.java` and `Direct.java` in `widgets/analyzer/`).

Not ported: `motion/`, `parser/`, `dsl/`, `state/` (the Flutter adapter plays
that role), `Placeholder`, `widgets/Rectangle` (only `motion/` uses it), the
`Grouping` pass and `OPTIMIZATION_DEPENDENCY_ORDERING`, the `Metrics`
instrumentation, and the view layer outside the measure pass (layout params
parsing, `ConstraintSet`, the helper views, drawing).

## The parity contract

The engine is checked against upstream's Java engine itself, never against a
model of it. The oracle is upstream's core at the pinned commit, driven by
`VOpDriver`, which replays an op list (the exact sequence of engine calls
that builds a layout) and measures it either on the core path
(`ConstraintWidgetContainer.measure` with an echo measurer) or on the view
path (a Java port of the view layer's `onMeasure` and child measurer over
content views). The view path is itself checked against real Android views:
under Robolectric 4.16 with the released ConstraintLayout 2.2.1 view layer, a
`RoboOracle` lays out VR, T, VR2 and T2 (1.46 million layouts) with 0
differences from `VOpDriver`. It also applies T2's 50,000 in-place sequences
to live views state by state (layout params rewritten in place, so every
measure takes Android's dirty path), and the engine lays every one out as
the live views do, at every optimization level checked (the in-place gate
below). Every Java run uses `-XX:hashCode=2`, which makes the
identity-hash-ordered sets iterate in insertion order (up to ten entries).
The tools, corpora and every command are in `tool/parity/`; the formats in
`tool/parity/FORMATS.md`.

A layout matches when the layout's size and every child's frame are equal,
and, on the adversarial corpus A, whether the solver loop printed a caught
exception. Results at `OPTIMIZATION_STANDARD` (257), Android's default:

| Corpus (path) | Layouts | Compared | Differ | Excluded |
| --- | --- | --- | --- | --- |
| R, realistic screens (core) | 319,827 | 319,827 | 0; Direct's state 0 | none |
| A, adversarial (core), frames and printed status | 360,000 | 359,617 | 0 | ND 154, HANG 8, SOE 110, JEXC 111 |
| T2core, targeted families (core) | 379,995 | 379,995 | 0; Direct's state 0 | none |
| VR2, R with content (view) | 319,827 | 319,827 | 0; Direct's state 0; measure requests 0 | none |
| T2, targeted families (view; in-place sequences against fresh builds, which Android's live views equal at 257) | 470,000 | 469,990 | 0; Direct's state 0; measure requests 0 | ND 10 |
| Solver trace sample, R and T2 (core) | 2,000 | 2,000 | 0 events: every variable, row, subject, pivot, goal update and final value, bit for bit | none |
| FL, real Flutter widget trees through the adapter | 60,000 | 60,000 | 0 (and every dry layout equals the first layout's size) | none |

The measure-request comparisons hold with one rule: the requests of Direct's
block in pass 0 compare as a set, because Java iterates a hash set in
insertion order only up to ten entries and Android's own order there is
random per launch (6,006 VR2 layouts need the rule; none of their frames
differ). On T2, 4,815 in-place layouts differ from their fresh build only in
the hasBaseline flag of a GONE or cache-hit answer, history Java keeps too.

At the dependency-graph levels, against Java at the same level: R and T2core
(core) at 64, 321, 192 and 449, and VR2 and T2 (view) at 321, 192 and 449,
differ on 0 layouts (T2core excludes 168 JEXC at every level). At
`OPTIMIZATION_NONE` (0): R 0 of 319,827, A 0 of 359,993 (HANG 6, JEXC 1),
T2core 0 of 379,995, VR2 0 of 319,827 (and its measure requests), T2 0 of
420,000 (and its measure requests), and the solver trace sample identical.
At these levels T2's in-place sequences are left to the in-place gate: Java's
in-place measure is not Android's dirty one, and Android's live views lay
many of them out unlike their fresh builds.

**The in-place gate** (`tool/parity/gates/inplace_gates.sh`) applies T2's
50,000 in-place sequences (T2-inplace) state by state to Android's live views
(RoboOracle, `-Drobo.inplace=1`: every state's layout params set again on the
same views, so every measure takes the dirty path) and to the engine through
`ViewHost`, at levels 0, 64, 192, 256, 257, 321 and 449:

| Level | Compared | Differ in place | Differ in the dirty second layout | Fresh builds differ | Android throws (engine on the same, at the same state) | Live views in place unlike their fresh build |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 50,000 | 0 | 0 | 0 | 0 | 187 |
| 64 | 49,959 | 0 | 0 | 0 | 41 (15 at an earlier state) | 429 |
| 192 | 49,840 | 0 | 0 | 0 | 160 (72 at an earlier state) | 577 |
| 256 | 50,000 | 0 | 0 | 0 | 0 | 187 |
| 257 | 50,000 | 0 | 0 | 0 | 0 | 0 |
| 321 | 49,959 | 0 | 0 | 0 | 41 (15 at an earlier state) | 239 |
| 449 | 49,840 | 0 | 0 | 0 | 160 (72 at an earlier state) | 386 |

At 257 the live views lay every sequence out as a fresh build; elsewhere they
keep what `reset()` keeps, and so does the engine (see "Android's dirty
measure" below). Both sides run T2-inplace without its in-place `bl N 0` and
`hbl N 0` ops (`compare/keepbl.py`): they model an earlier adapter that
cleared the baseline flags between states, which neither Android nor the
adapter does (the live views never read them; the engine does, and with them
70 sequences at 64 and 321, and 79 at 192 and 449, keep no stale baseline
margin and differ from the live views).

The excluded classes are where Android has no single result, counted on the
oracle's side:

- **ND**: the oracle's result changes with the identity hashes (a triple run
  with other hash settings and repeated builds disagrees). Android's order
  there is random per launch.
- **HANG**: Java never returns (A: 8 at 257, 6 at 0). The engine finishes
  (see the hang guards below).
- **SOE**: Java's `Direct` recurses until its stack overflows (A: 110 at
  257). The engine's guard trips on exactly these 110 layouts, and the solver
  lays them out.
- **JEXC**: Java throws out of `onMeasure`, outside the solver loop's catch
  (A: 111 at 257, a null anchor or target in Direct, and the engine throws on
  each of them too; 1 at 0; T2core: 168 at every GRAPH level, where Java's
  graph reads a baseline dimension a widget never got and the engine's guard
  leaves the link to the solver; T2-inplace on live views: 41 at 64 and 321,
  160 at 192 and 449, a `NullPointerException` in the graph of an in-place
  measure, where the engine throws too, at the same state).

Two more boundaries:

- **A layout measured again in the same container** is compared with
  Android's own dirty second layout (`DirtyTwice`: every child `reset()` and
  configured again, as `setChildrenConstraints` does), not with a fresh
  build. Android's second layout differs from its first at 257 on 28
  degenerate T2 layouts: 27 match-constraint x match-constraint Flows, whose
  `addToSolver` reads the chain list their previous measure left, and one
  chain whose anchors keep solver ids the last iteration did not register
  (T2-chain 500034267). The engine gives Android's second layout on all 28;
  on one more (T2-chain 500040012), Java's second layout never returns. At
  level 0, where a barrier that `allSolved` resolved keeps its flag,
  Android's second layout differs from its first on 6,469 VR2 and 1,239 T2
  layouts (T2-inplace left to the in-place gate), and the engine's second
  layout equals DirtyTwice's on every VR2 and T2 layout but one where Java
  hangs (and at 257 too, compared on every layout). Over FL, the adapter's
  second layout equals Android's on all 60,000 at 257 (3 differ from their
  first, on both sides) and at 0, 64, 192, 256, 321 and 449 (1,091 or 1,092
  differ from their first at the levels without Direct, 3 at the others).
- **Grid layouts** (`GridCore`) are outside the contract: Android's view
  `Grid` is not core `GridCore` (it adds box views of its own), so no corpus
  holds a grid, and `GridCore` keeps divergences of its own (below).

## Where the code differs from upstream

The engine is upstream's code, line for line, in Java's arithmetic. Each
difference below is commented where it is made, and is one of four kinds:

1. how Java maps onto Dart (floats, null dereferences, hash-set order);
2. a guard that ends a walk or a loop where upstream crashes, hangs or
   overflows its stack;
3. the view layer's work before a measure, which `ViewHost` does for a
   caller that keeps its widgets configured: what Android's dirty measure
   resets and sets again, no more;
4. an exact representation change for speed, which changes no float, row,
   variable id or tie, checked by bit-identical runs.

None of them changes a frame on the parity corpora outside the excluded
classes.

### Java's numbers

- **Floats.** Every Java `float` is a Dart `double` that holds a binary32
  value, and every Java float operation is one call that rounds once, in
  Java's evaluation order (`jfloat.dart`: `f32`, `fadd`, `fsub`, `fmul`,
  `fdiv`, `fi`, `jfrem`); every `(int)` cast is `jint` (truncation toward zero,
  NaN to 0, saturating); `Math.toRadians` and `Float.parseFloat` are Java's.
  Inputs (biases, percents, ratios, weights, angles, gaps) are stored as
  binary32 values, and row coefficients live in `Float32List`s, as Java's
  `float[]`. Comparisons are exact; the only epsilons are Java's own, as
  binary32 constants. Tests: `jfloat_test.dart` (2,000 JVM-computed vectors
  per primitive; `tool/parity/jfloat/` generates them and checks 1,000,000),
  `solver_float_test.dart`, the "Java float" groups of `chain_test.dart` and
  `ratio_test.dart`, and the solver trace sample.

### Java null semantics

Java dereferences objects the port types as nullable. Where upstream
dereferences null, the port fails at the same operation: a failed null check
(`!`) or a `RangeError` stands for Java's `NullPointerException` or
`ArrayIndexOutOfBoundsException`, and `ArrayLinkedVariables`,
`SolverVariableValues` and `ArrayRow` take a nullable variable and throw
exactly where Java does, not before (`get` of a missing variable in an empty
row returns 0; `put` and `add` of a missing variable write the head slot of
an empty list, then throw). The solver loop of `layout()` catches every
error, as Java catches `Exception` there, prints it, and reads the frames back
from what was solved. Test: `solver_exception_test.dart` (every exception
repro at 0 and 257: Java's frames, Java's printed status, and Java's
exception classes at the same solver operation), the "Java null semantics"
group of `array_linked_variables_test.dart`, and
`solver_variable_values_test.dart`'s "binary32 values and missing
variables". On the exception repros, every exception the engine catches is
one Java catches at the same operation (11 layouts at 257, 10 at 0), and it
catches none Java does not.

A dereference no corpus reaches is kept the same way.
`ConstraintAnchor.hasCenteredDependents` reads `getOpposite()` of each
dependent in turn until one is connected, as upstream does, and a baseline
or center anchor has none. `Barrier.addToSolver` asks the barrier's top,
then its bottom only when the top has no centered dependent, so a baseline
linked to the top or bottom of a barrier that Direct did not resolve makes
it fail the null check inside the solve, where upstream throws its
`NullPointerException` (ConstraintAnchor.java 68), unless a centered
dependent is read first. The solver loop prints it, and the frames are read
back from the abandoned solve, as on the oracle: a position or size the
solve had not fixed before the throw reads back as 0, except a FIXED size,
which setFrame restores. Test: the two hand-built layouts of
`solver_exception_test.dart`, with Java's frames, printed status and
exception class at 0 and 257 (a baseline on a barrier that Direct resolves
at 257, which prints only at 0, and the same barrier over a vertical chain,
which prints at both levels; the solver traces of both equal TraceJava's,
the throw included), and `anchor_api_test.dart`, which also pins that the
dependents are read in the order they were linked.

Where the mapping differs:

- **A missing measurer**: `measure()` throws a `StateError` with a message
  where upstream throws a `NullPointerException`; both leave `measure()`.
- **The catch around the solve** also catches the Dart errors that stand for
  Java `Error`s, which Java's `catch (Exception)` lets through: a stack
  overflow or an out-of-memory error inside a solve. On the corpora such
  layouts are Java's SOE, HANG or JEXC classes.

### Hash-set order

Android iterates several `HashSet`s in identity-hash order, which differs
from launch to launch. The port iterates insertion-ordered sets instead: each
anchor's dependents (`ConstraintAnchor.mDependents`), the dependency graph's
chain runs, the virtual layouts the container adds to the solver, and
`GridCore`'s placed-span set. The order is deterministic, and it is the order
the oracle's `-XX:hashCode=2` gives up to ten entries. `ViewHost` registers
the dependents in the order Android's `setChildrenConstraints` makes the
links (`rebuildViewDependents`). Where Android's own order changes the result,
the layout is ND on the oracle (A 154, T2 10 at 257) and excluded. Tests:
`dependents_state_test.dart` (the dependents Android's view layer leaves, from
a Java probe, `tool/parity/java/probes/DepsProbe.java`).

### Guards against crashes and hangs

Each acts only where upstream never returns, overflows its stack or throws
out of its measure; elsewhere the walk or loop runs exactly as upstream's.

- **Direct's re-entry guard** (`analyzer/direct.dart`). Upstream's `Direct`
  recurses without a bound. A cycle that only stale dependents form
  (connecting an anchor to a new target leaves it among the old target's
  dependents, as upstream does) makes Android repeat the same calls until its
  stack overflows. The port counts the changes each solving pass makes; when
  a widget's pass on an axis is entered again with no change since that pass
  started walking, or the nesting passes `4 * (children + 1) + 64` (which
  only a cycle that keeps changing the state reaches), the guard abandons
  Direct for this measure: every final resolution it made is reset and the
  solver lays every widget out. `Direct.guardTrips` counts the trips. The
  table that records the passes on the stack is an identity hash table with
  open addressing, an exact replacement for a `HashMap.identity()` (nothing
  iterates it). On corpus A it trips on exactly the 110 layouts where Java
  overflows, and on no other layout of any corpus. Tests: `direct_test.dart`
  ("cycle guard (the port only)": a re-entry with no change, a cycle that
  keeps changing the state, layouts without a cycle never trip it, and a
  nested container's Direct inside a measure);
  `tool/parity/compare/guardcheck.py` on corpus A.
- **The solver's chain walks** (`ChainHead` and `Chain`). For a chain whose
  first member's start links one way to its last member while the last
  member's end links back to the first (a widget whose start and end both
  link to a second one that links back, or a widget whose start and end both
  link to its own end), upstream's `defineChainProperties` and
  `applyChainConstraints` restart the walk forever; the port stops at the
  first member. Java hangs on these layouts at every level. Test:
  `link_loop_test.dart` (each layout in its own isolate, checked to finish
  the same at every level, the others against Java's strings).
- **The graph's chain walk** (`ChainRun`). A widget's neighbour in a chain is
  the owner of an anchor that its own anchor targets and that targets it
  straight back, whatever the sides, so two tops linked to each other, an
  anchor linked to itself, or two widgets linked both ways on both sides form
  a chain with no first or last member. Upstream's walk never ends there (and
  walking forward, grows its member list until memory runs out). The port
  stops after more steps than the container has children, marks the run
  `cyclic`, and `DependencyGraph.directMeasure` declines the layout.
  `measure()` keeps the graph off for any layout with a chain at every level,
  so only a direct `directMeasure` call reaches it. Test:
  `link_loop_test.dart`.
- **The wrap cycle** (`RunGroup.computeWrapSize`). At the
  `OPTIMIZATION_GRAPH_WRAP` levels, runs that depend on each other in a loop
  (a widget centered between the container's left and a sibling's right
  while the sibling's left is linked to the widget's right) make upstream's
  traversals recurse until the stack overflows. The port's traversal stops
  when it reaches a node it is already inside, computes no wrap size, and
  leaves that axis to the solver. Test: `wrap_loop_test.dart` (Java's strings
  at 257 at every level, the graph returning without a wrap size, and a
  direct graph call where Java throws a `StackOverflowError`).
- **`ArrayRow.updateFromSystem` is bounded.** Upstream substitutes the
  definitions of a row's defined, final and synonym variables until none is
  left, which ends within one round per variable unless the definitions refer
  back to each other; some degenerate layouts leave definitions that do (a
  cyclic barrier layout with a match-constraint widget below its minimum,
  solved again after `setFrame` records the override), and upstream spins
  forever. The port throws a `StateError` after `mNumRows + mVariablesID + 1`
  rounds, which the solver loop catches and prints, and the frames are read
  from what was solved. Tests: `frame_override_test.dart` ("a cyclic barrier
  layout below a minimum returns, where upstream never does"), and corpus A's
  HANG layouts (the engine finishes on all 8).
- **The graph's other crash guards**, each where upstream throws out of
  `measure()`:
  - `VerticalWidgetRun.apply` leaves the baseline link of a widget the graph
    has not measured unwired when the widget's run never got a baseline
    dimension (no `mBaselineDimension`: `apply` creates one for a widget with
    a baseline, and the run keeps it from one graph to the next), where
    upstream throws a `NullPointerException`; the widget's top stays
    unresolved and the solver lays it out. This is T2core's JEXC class at the
    GRAPH levels (168 layouts).
  - `HorizontalWidgetRun.update` returns before centering when an edge has no
    target, as `VerticalWidgetRun.update` does upstream; upstream's
    horizontal twin throws an `IndexOutOfBoundsException` for a chain member
    whose percent width resolves through this update. Only a direct
    `directMeasure` call reaches a chain member's run. No test pins it.
  - `DependencyNode.resolve` iterates a copy of its dependencies. Nothing adds
    one while the graph resolves, so this is exact; upstream's iterator would
    throw a `ConcurrentModificationException` if something did.

### Android's dirty measure

Upstream's core keeps state from one measure to the next, and Android's view
layer keeps part of it too: on every measure in which a child requested
layout, `setChildrenConstraints` calls `reset()` on every child widget and
configures it again from its layout params, and `reset()` leaves some state
alone. The engine resets exactly what Android does, and has no reset of its
own; the caller sets again what Android's layout params set and a measure can
change: FIXED sizes and a virtual layout's own links (the adapter does). A
virtual layout member's own links are not supported: `ViewHost` resets every
member's anchors, as `reset()` does, and nothing connects those links again
before the measure, where Android's layout params do (`rebuildViewDependents`;
no corpus layout has such a link).

- **`ViewHost` takes Android's dirty path on every measure.** It applies
  `ConstraintWidget.resetMeasureState` to every child: what `reset()`
  (CW 557-621) clears and the layout params do not set again (every
  anchor's final value, the position, a non-fixed size, the baseline
  distance, what the solver derived, the virtual-layout membership, a
  pending size override), with the match-constraint modes the layout params
  set again (`setHorizontalMatchStyle` and `setVerticalMatchStyle` undo the
  dependency graph's reclassification to percent or ratio, so a direct write
  to `mMatchConstraintDefaultWidth` or `Height` that bypasses them is undone
  by the next measure). It keeps what `reset()` keeps: both resolved flags
  and both solving-pass flags, a guideline's and a barrier's own resolved
  flag, `hasBaseline`, the last measure specs, and the dependency graph's
  runs and nodes. It then makes every guideline and barrier GONE (Android's
  view helpers always are), marks the virtual layouts' members, rebuilds
  the dependents in Android's order, and marks the children a baseline link
  needs the baseline of. Android takes this path only when a child requested
  layout, and otherwise measures again over what the last measure left;
  `ViewHost` takes it every time, as a Flutter layout cannot tell which
  child changed. It also skips the first of Android's two `updateHierarchy`
  calls at levels without the graph, where both of its effects are
  overwritten before anything reads them.
- **What that history changes**, on Android's live views and in the engine
  alike (the in-place gate above):
  - Without `OPTIMIZATION_DIRECT` (levels 0, 64, 192 and 256), a barrier
    that `Barrier.allSolved` resolves keeps its `mResolvedHorizontal` (or
    vertical) flag, which its `addToSolver` never clears, while `reset()`
    zeroes its position; its next `setFinalHorizontal` returns at once, and
    `addToSolver` pins the barrier at 0. With Direct (257, 321 and 449),
    `Direct.solvingPass` clears every flag in the first solver pass of each
    measure, before anything reads them.
  - At the GRAPH levels (64, 192, 321 and 449), the graph is wired again
    from runs and nodes that keep what the last graph left: a gone widget,
    which `basicMeasureWidgets` skips, keeps its run's dimension behaviour
    (a gone match-parent column stays anchored to the container's edges); a
    node keeps its margin dependency (a margin recomputed from a stale
    baseline); a run keeps its type, so a centered widget that lost a link
    updates as centered and reads the missing target, where upstream throws
    a `NullPointerException` and the engine a failed null check, on the same
    sequences and at the same state.
  - At `OPTIMIZATION_STANDARD` neither changes a layout: Android's live
    views lay every in-place sequence of T2 out as a fresh build, and so
    does the engine.
- **R8**, `resetMeasureState`'s restore of the configured match-constraint
  modes, is the one reset beyond `reset()` itself, and it is what Android's
  layout params do. The port reset more before: both resolved flags and
  both solving-pass flags, a guideline's and a barrier's own flag, and R1 to
  R7 in the graph (a rebuild forced after every reset of the runs, a run's
  dimension behaviour, match-constraint type, run type and baseline
  dimension, every chain run, and a node's margin, factor, margin
  dependency and update delegate). Each made a container laid out again
  resolve as a freshly built one, which Android's live views do not; they
  are gone.
- Tests: `view_host_test.dart`, `fresh_state_test.dart` ("resetMeasureState";
  "in place through ViewHost, as on Android": ResetProbe's sequence at seven
  levels with the live views' and Java's frames, and random in-place
  sequences against their fresh builds where Android's equal them),
  `persistent_layout_test.dart` (in-place scenarios against the live views
  at 0, 257, 256, 64, 321, 192 and 449: a gone match-parent widget, a
  centered widget that loses a link, the target of a baseline link that
  turns gone, a barrier that counts no reference, a ratio widget at the
  GRAPH_WRAP levels), `dependents_state_test.dart`; on the corpora, the
  in-place gate, and the second layouts against DirtyTwice at 257 and 0.

### Replay

The engine replays nothing. The Flutter adapter replays a layout: when a
layout repeats the configuration and constraints of the last one, and that
layout gave the same result as the one before it, it asks every child again
for each measure the last layout asked and, when every answer is the same,
places the children where the last layout did, without running the engine. A
measure is a function of the configuration, the specs, the answers and the
state the last measure left, the history Android itself keeps (what `reset()`
keeps, above, a Flow's chain list, a solver variable's id). The two-layout
condition covers it: a run that repeated the run before it, with the same
keys, requests and answers, left the state that run left. Under
`--dart-define=cl.verifyReplay=true` every replay also runs in full and is
compared: over FL, each layout laid out five times, 0 mismatches at every
level checked (177,328 replays at 257; 176,323 to 178,771 at 0, 64, 192, 256,
321 and 449), and the second layout is Android's dirty second layout at each
level (FORMATS.md 21.1). Tests: the adapter's `transcript_replay_test.dart` and
`caching_fuzz_test.dart`.

The adapter's dry layout and intrinsic sizes measure a new model through a
throwaway `ViewHost`, so they give a first layout's size. Where Android's
second layout of a layout differs from its first, the size can too: on FL,
the size changes from the second layout on for 1 layout at 257, 321 and 449,
and 19 at 0, 64, 192 and 256.

### Exact changes for speed

Each of these changes how the engine computes, never what: the same float
operations in the same order, the same rows, variable ids and ties. They were
checked bit for bit: the Dart outputs at 257 on R, A, T2core, VR2, T2, the
trace sample, FL and the second layouts (31 content hashes), and at the GRAPH
levels (14 outputs), are byte-identical before and after.

- **The synonym-scan skip** (`LinearSystem.addEqualityConstant`). Upstream
  fixes `a = value` and then scans every variable of the system for synonyms
  of `a`, which makes n equalities cost O(n^2): upstream's Java engine at 257
  takes 4.0 ms on a flat screen of 600 widgets. The port skips the scan while
  `mSynonymCount` is 0, which is exact: the scan's body runs only for a
  variable with `mIsSynonym` set; only `SolverVariable.setSynonym` sets it,
  counting the call on its system; `reset()` zeroes the count only after
  resetting every registered variable, and a variable registered later is
  fresh or reset first. So while the count is 0 no variable is a synonym, and
  the scan would change no state, no float and no trace event. On the layout
  path the count stays 0: `addSynonym` has no caller in the core, and
  `addEquality`'s own `setSynonym` call sits behind upstream's `DO_NOT_USE`,
  which is false. Debug builds check the invariant with an assert, which runs
  the scan only while some variable in the isolate is a synonym
  (`SolverVariable.debugLiveSynonyms`, kept by `mIsSynonym`'s setter). Test:
  `solver_float_test.dart` ("synonym scan of addEqualityConstant").
- **Solver representation** (`ArrayLinkedVariables`, `ArrayRow`,
  `PriorityGoalRow`, `SolverVariable`, `LinearSystem`, `Cache`): fixed-length
  lists grown as `Arrays.copyOf` grows them; one linked walk instead of
  `getVariable(i)` from the head for each `i`, while the list cannot change;
  early-exit walks while the list is well formed (ids rising strictly, an id
  mask that is a superset); a client-row bit mask per variable; removals
  searched from the back where an entry occurs once; goal occurrences counted
  per variable, so the goal's last occurrence is found first; a reset that
  skips a variable already in its reset state; `LinearSystem.reset` touching
  only the ids in use; and a ratio test that visits only the entering
  variable's client rows, lowest index first on a tie, which falls back to
  upstream's full scan whenever one of its guards fails (a row without a
  subject, a row not handed out by `createRow` in this epoch, an unregistered
  variable stored in a row, a candidate that is not the table's entry for its
  id). Upstream's dead sort branch in `PriorityGoalRow.addToGoal` (it compares
  the element just stored with itself) is left out with its sort array. Test:
  `array_linked_variables_differential_test.dart` runs the list against the
  previous implementation (`test/support/reference_array_linked_variables.dart`)
  on adversarial sequences, comparing results, Java exception classes, lists,
  usage counts and client rows after every step.
- **The view layer**: `ViewMeasurer` looks a child view's state up once per
  measure; `ViewHost` skips the dead first `updateHierarchy` (above).

These add public members, all bookkeeping that the solver keeps consistent:
`SolverVariable.goalOccurrences`, `SolverVariable.debugLiveSynonyms`,
`LinearSystem.mSynonymCount`, `ArrayRow.mClientBit`, `ArrayRow.mRowIndex`,
`ArrayRow.mSystemEpoch` and `Cache.mUnregisteredEntry`; `mIsSynonym` is now a
getter and setter. Code that drives `LinearSystem` directly, as the ported
solver tests do, gets upstream's results: a row stored into `mRows` other
than through the system's own methods makes the ratio test fall back to
upstream's scan, and every write of `mIsSynonym` goes through the setter.

### Grid (outside the contract)

Android's Grid helper is a view (`helper/widget/Grid.java`) that adds box
views to the layout; `GridCore` is the Compose path's helper, which no
Android layout runs. The port keeps `GridCore` working where upstream's
throws, collapses or moves its widgets.

- **The tie epsilon.** Goal strengths compare exactly, as
  upstream's do, except in a solve whose container holds a `GridCore`:
  `GridCore.addToSolver` sets `LinearSystem.goalTieEpsilon`, and
  `PriorityGoalRow` then treats strengths within 0.0001 of each other as a
  tie, so the candidate found first keeps the pivot. In an over-constrained
  grid (a weighted row or column whose fixed-size tiles fill or overflow
  their track), two pivot candidates can tie exactly, and rounding noise
  breaks the tie one way or the other, tens of pixels apart; with the
  tolerance the weighted cell geometry comes out every time (over 640
  weighted 2 x 2 grids). Every solve resets the flag. Tests:
  `solver_float_test.dart` ("a GridCore container keeps the tie tolerance",
  "the container switches the tie mode on for a GridCore") and
  `grid_modes_test.dart` ("row weights 4,1 hold with ... px tall tiles").
- **Right to left.** `GridCore` mirrors its columns in a right-to-left
  container (`ConstraintWidgetContainer.isRtl()`, read on every solve, as
  `Flow` reads it); upstream leaves this as `@TODO handle RTL`. The box
  chain still runs left to right: logical column `c` (span `s`) goes on boxes
  `columns - c - s` to `columns - 1 - c`, and box `i` takes the weight of
  column `columns - 1 - i`, so the result is the mirror image of the
  left-to-right grid within its bounds. Cell positions in spans and skips and
  the column weights still count from the first (now rightmost) column; a
  column edge exactly on a half pixel rounds the same way in both
  directions, so it can sit 1 px off the mirror.
- **Placement from scratch on every solve.** `addToSolver` resets the cells,
  the handled spans and the `SPANS_RESPECT_WIDGET_ORDER` span cursor (through
  `setupGrid`'s update path, which upstream never calls) and places the skips
  and spans again. Upstream arranges the widgets on top of the cells the
  previous solve took, and a measure solves up to three times, so each solve
  moved the widgets on into the cells still free.
- **`measure()` reports the incoming exact sizes** as the grid's measured
  size (upstream leaves it untouched, as its Compose host sizes grids only
  through the solver), and derives a missing track count from the current
  number of widgets on every measure (upstream derives it only in the
  constructor and in `setRows`/`setColumns`, so a grid configured before its
  widgets keeps 0 tracks and throws).
- **No boxes, no constraints.** `addToSolver` adds nothing beyond the grid's
  own constraints when the grid built no box widgets (no widgets, or never
  measured); upstream dereferences the missing boxes and the solve is
  abandoned for the whole layout.
- **Input upstream rejects.** Span entries past the last widget are ignored
  (upstream throws from `measure()`); placed spans are tracked by widget
  identity (upstream tracks `stringId`, null by default, and skips every
  other widget once one span is placed); `setRows` and `setColumns` ignore a
  negative count; a negative cell position cannot be taken, like one past the
  last row or column (Java's truncating `/` and `%` give a negative index, on
  which upstream throws); positions are read with Dart's `int.parse`, which
  accepts surrounding whitespace and a hexadecimal `0x1` where Java's
  `Integer.parseInt` rejects them (upstream then ignores the whole spans or
  skips string, or, in the released span sort, throws on a space after a
  comma); weights are read as `Float.parseFloat` reads them. The span sort
  keeps entries at the same position in their listed order, as Java's stable
  sort does.
- **`WidgetContainer.remove()`** (which `add()` calls for a widget that
  already has a parent) only clears the widget's parent. Upstream's also
  resets the widget (`ConstraintWidget.reset()`, not ported), clearing its
  connections, size and every other attribute. `GridCore.measure()` adds its
  box widgets to the container again on every measure, as upstream's does,
  and a measure measures a virtual layout more than once, so a reset would
  wipe the boxes' setup: upstream's own grid collapses, every cell 0 x 0, the
  second time it is measured. `LayoutTest` adds one widget twice, so its port
  shows the difference.
- **`GridEngine`** handles input the same way where it parses: `int.parse`
  reads a hexadecimal position, and a negative position wraps to the end of
  its row or column (Dart's `%`), where upstream throws.

Tests: `grid_modes_test.dart` (including its "core 1.1.1" groups, checked
against the released `GridCore` on a JDK, and "configuration guards"),
`grid_engine_test.dart`, `layout_test.dart`.

When updating the port, bump the commit above, port the change, and rerun the
engine suite and the parity gates (`tool/parity/README.md`).

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
| `NestedLayout` | `nested_layout_test.dart` | 1, skipped (see below) |
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
`NestedLayout.testNestedLayout`, which is disabled upstream (its `@Test` is
commented out, and it expects a stale coordinate convention) and skipped here.
`GridEngineTest` is ported from AOSP's `androidx-constraintlayout-release`
branch, where it sits in the `utils` package; its tests are the same as at the
pinned commit. Four of these files also hold groups of the port's own, which
the table does not count: the Java float checks of `chain_test.dart` and
`ratio_test.dart`, and the binary32 and Java null semantics checks of
`array_linked_variables_test.dart` and `solver_variable_values_test.dart`.

Every one of them runs its full upstream body, including the passes in which
`WidgetsPositioningTest` adds its widgets to the solver in every possible
order and solves them directly (`runTestOnWidgets`), with upstream's own
assertions; a `closeTo` stands only where upstream's `assertEquals` passes a
delta. Two ports also check more than upstream does, and mark those checks
as not upstream's. Their expected values come from upstream's Java engine at
the pinned commit, run on the same input:

- `LayoutTest.testPositions` only prints how long one layout of a screen of
  buttons took, and the solver's table sizes. Its port checks every frame.
  The layout adds one widget twice, and upstream's `WidgetContainer.remove()`
  resets that widget on the second add where this engine's does not (see
  Grid above), so the expected frames are upstream's for the widget moved
  without the reset.
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

The other test files are the engine's own, not derived from upstream. Where
Android has a result, their expected values are the pinned oracle's
(`VOpDriver`, core or view path, `-XX:hashCode=2`) or a JVM's, at the levels
each file names; the API and Grid tests check the engine's own contract:

- the pipeline: `pass_structure_test.dart` (the passes and measure requests
  of `measure()`), `measure_widget_test.dart` (the static measure Direct
  uses), `direct_test.dart` (Direct's state and the cycle guard),
  `view_host_test.dart`, `dependents_state_test.dart`,
  `fresh_state_test.dart`, `persistent_layout_test.dart`;
- Java's numbers and exceptions: `jfloat_test.dart`, `solver_float_test.dart`,
  `solver_exception_test.dart`, `array_linked_variables_differential_test.dart`;
- Android's results on mechanisms and repros: `android_repro_test.dart`,
  `percent_min_test.dart`, `chain_rounding_test.dart`,
  `frame_override_test.dart`, `link_loop_test.dart`, `wrap_loop_test.dart`,
  `wrap_behavior_test.dart`, `wrap_bias_test.dart`, `max_dimension_test.dart`,
  `measure_ordering_test.dart`, `flow_wrap_test.dart`, `smoke_test.dart`;
- the API and the helpers: `anchor_api_test.dart`, `barrier_modes_test.dart`,
  `flow_modes_test.dart`, `grid_modes_test.dart`;
- the parity corpora: `parity/engine_corpus_test.dart` (2,000 layouts at 257
  and 0, core and view paths) and `parity/graph_corpus_test.dart` (560
  layouts at the GRAPH levels); `test/parity/README.md` describes both.

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
`SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause`. The files with no
upstream counterpart say so in their header. See `LICENSE` for both license
texts.
