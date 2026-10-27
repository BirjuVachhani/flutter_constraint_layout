## 1.0.0

Initial release: a pure-Dart port of Android ConstraintLayout's layout
pipeline, pinned to upstream commit `9cd4b5a` (core 1.1.0-alpha04,
ConstraintLayout 2.2.0-alpha04) and at parity with the released core 1.1.1 and
ConstraintLayout 2.2.1. It lays every layout of the parity corpora out exactly
as Android does, outside the layouts on which Android itself hangs, overflows
its stack, throws out of its measure or depends on hash order. See `README.md`
and `UPSTREAM.md`.

- **Android's pipeline, literally.** `ConstraintWidgetContainer.measure` is
  upstream's `BasicMeasure.solverMeasure`: the dependency graph first at the
  `OPTIMIZATION_GRAPH` levels, then the children's measures, pass 0 with
  upstream's `Direct` pass and the solver loop (at most 9 iterations, the
  minimum and "measured too small" clamps, the catch that prints an exception
  and keeps what was solved), then the re-measures of passes 1 and 2.
  `layout()` is one of those passes on its own.
- **Java's arithmetic.** Every Java float operation is one binary32 rounding
  in Java's evaluation order, every `(int)` cast truncates, and inputs and
  row coefficients are stored as binary32 values (`f32` and `fsub` are
  exported), so a widget lands on Android's pixel.
- **The view layer.** `ViewHost` is the ConstraintLayout view's `onMeasure`
  (the dirty path, padding, minimum and maximum, `resolveMeasuredDimension`),
  `ViewMeasurer` its child measurer with one hook for the child view's own
  measure (`measureContent`), `MeasureSpec` Android's `View.MeasureSpec`, and
  `rebuildViewDependents` the anchor state `setChildrenConstraints` leaves.
  Before each measure `ViewHost` resets every child's measure state as
  Android's dirty-hierarchy path does (`ConstraintWidget.reset()`, then the
  layout params), and no more: a widget keeps what Android's keeps from one
  measure to the next (its resolved flags, a guideline's and a barrier's own
  flag, the dependency graph's runs and nodes), so a layout measured again
  gives what Android's live views give, at every level checked (0, 64, 192,
  256, 257, 321 and 449).
- **Optimization levels as on Android.** `OPTIMIZATION_STANDARD` (Direct and
  the measure cache) is the default. The `OPTIMIZATION_GRAPH` levels are
  opt-in, run upstream's dependency graph by its own rules, and give
  Android's results at the same level.
- **Parity, measured.** Against upstream's Java engine driven through a Java
  port of the view layer (itself matched on real Android views), at Android's
  default level: 0 differences on 319,827 realistic layouts, 359,617
  adversarial ones (frames and printed exceptions) and 379,995 targeted ones
  on the core path, and on 319,827 and 469,990 on the view path; Direct's
  state, the measure requests and a 2,000-layout solver trace are identical
  too. The same corpora differ on 0 layouts at level 0 and at the GRAPH
  levels. T2's 50,000 in-place sequences, applied state by state to
  Android's live views and to the engine, differ on 0 at levels 0, 64, 192,
  256, 257, 321 and 449, second layouts included, the engine throwing where
  the views throw (without the corpus's in-place `bl N 0` and `hbl N 0` ops,
  which model an earlier adapter that cleared the baseline flags between
  states, as neither Android nor the current adapter does; with them 70
  sequences at 64 and 321, and 79 at 192 and 449, differ: see
  `UPSTREAM.md`). Android's own nondeterministic, hanging,
  stack-overflowing and throwing layouts are excluded and counted
  (`UPSTREAM.md`).
- **No default measurer.** `measure()` requires a `Measurer`, as upstream
  does; `layout()` without one measures nothing.
- **Guards where Android crashes or hangs.** Direct's recursion stops on a
  cycle that only stale dependents form (Android overflows its stack); the
  solver's and the graph's chain walks stop on links that loop; a wrap-content
  axis whose runs depend on each other in a loop goes to the solver;
  `ArrayRow.updateFromSystem` gives up after a bounded number of rounds.
  Each acts only where upstream never returns or throws out of its measure.
- **Speed.** Exact representation changes, each checked bit for bit against
  the unoptimized engine: the synonym scan Android pays O(n^2) for is
  skipped where it can change nothing, solver lists are walked once, goal and
  client-row bookkeeping avoids linear searches, and the ratio test visits
  only the entering variable's rows. A realistic screen measures in about
  4 us at the default level (AOT); `README.md` has the benchmark.
- **Widgets.** `ConstraintWidgetContainer` and `ConstraintWidget` with anchors,
  margins and gone margins, bias, visibility, dimension behaviours (fixed,
  wrap content, match parent, and match constraint in its spread, wrap,
  percent, and ratio modes), minimum and maximum bounds, chains, `Guideline`,
  and `Barrier`.
- **Virtual layouts.** `Flow` and `GridCore`. `GridCore` follows core 1.1.1:
  `setFlags` takes an int bitmask of `SUB_GRID_BY_COL_ROW` (1) and
  `SPANS_RESPECT_WIDGET_ORDER` (2), a weight list of the wrong length is
  padded with 1 or trimmed, an unparsable weight reads as 1, and spans and
  skips are sorted by position. Unlike upstream it mirrors its columns in a
  right-to-left container, places its widgets from scratch on every solve,
  and accepts input upstream throws on. Grid layouts are outside the parity
  contract (Android's view `Grid` is not `GridCore`), and a container holding
  a grid keeps a tie tolerance in the solver's goal comparisons.
- `GridEngine`, upstream's standalone grid cell-placement class, which
  `GridCore` does not use.
- **The upstream core test suite, ported in full:** all 278 in-scope tests,
  each with its whole upstream body and upstream's own assertions (the one
  that upstream disables is skipped here too), including `LayoutTest`,
  `ArrayLinkedVariablesTest`, `GridEngineTest`, and `ComposeLayoutsTest`, whose
  `state/` API calls are rebuilt as direct widget calls. `UPSTREAM.md` lists
  the out-of-scope test files and every place where the code differs from
  upstream's.
- **Parity tooling.** `tool/parity/` holds the Java oracle, the corpus
  generators, the comparators and the real-view checks (frames, and the
  in-place gate on live views at any optimization level), with the commands
  that rebuild the oracle at the pin and rerun every gate; `test/parity/` holds
  2,560 corpus layouts with Java's results, replayed by the suite.
