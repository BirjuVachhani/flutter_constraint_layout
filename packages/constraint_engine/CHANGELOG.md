## 1.0.0

Initial release: a pure-Dart port of `androidx.constraintlayout.core`, pinned
to a specific upstream revision. The solver, the widget classes, and the Grid
helper (`GridCore`) are verified at parity with the released core 1.1.1. See
`UPSTREAM.md`.

- The widget model: `ConstraintWidgetContainer` and `ConstraintWidget` with
  anchors, margins and gone-margins, bias, visibility, dimension behaviours
  (fixed, wrap content, match parent, and match constraint in its spread, wrap,
  percent, and ratio modes), min/max bounds, chains, `Guideline`, and
  `Barrier`. When a minimum or a maximum changes a solved size, `layout()`
  solves again with that size fixed, as upstream does.
- The dependency-graph resolver (`DependencyGraph` and its widget runs), which
  is tried first and measures each child once. It resolves barriers too, at
  the outermost edge of their widgets plus their margin, when it can tell that
  Android would lay the whole layout out the same way. A port-only model of
  upstream's `Direct` optimizer, which Android's default optimization level
  runs before its solver, tells it which widgets and barriers Android places
  without its solver, and where; the port does not run `Direct` itself.
- The graph applies a baseline link's margin, as Android's `Direct` pass and
  solver do; upstream's graph drops it. The graph hands a layout to the solver
  when its own measure passes leave a result stale (a size that resolved
  after the widget's last measure, or chain members left unplaced or at their
  measured sizes), and when a widget that is not gone has a baseline link but
  no baseline, a link Android ignores.
- Chains resolved on the graph place their members where the solver, and so
  Android, does: `ChainRun` keeps positions and match-constraint sizes exact
  and rounds each edge as the solver reports it.
- The Cassowary `LinearSystem` solver, used for the layouts the graph declines,
  such as chains with gone, ratio-sized, or percent members, circular
  constraints, virtual layouts, and barrier layouts that Android would lay out
  differently from the graph.
- Two solver safeguards that upstream lacks: `ArrayRow.updateFromSystem`
  gives up after a bounded number of rounds, so a solve whose row definitions
  refer back to each other ends where upstream's spins forever, and
  `PriorityGoalRow` treats goal strengths within its epsilon as a tie, so a
  weighted grid whose fixed-size tiles fill or overflow a row or column keeps
  its weighted geometry where upstream's float solver can collapse it.
- Links that loop back on themselves never hang `layout()`. Where two widgets'
  matching anchors other than the baseline target each other (two tops, for
  example), an anchor is connected to itself, or two widgets are connected
  both ways on both sides, the graph's chain walk (`ChainRun`) stops when it
  goes round the loop and marks the chain `cyclic`, and the graph leaves the
  layout to the solver, which lays it out as upstream's does. The solver's
  own chain walks (`ChainHead` and `Chain`) stop at the first member of a
  chain whose first member's start links one way to its last member, while
  the last member's end links back to the first; upstream's never return
  there. A wrap-content axis along which widgets depend on each other in a
  loop goes to the solver too, instead of overflowing the stack.
- `layout()` does not throw on two degenerate links that throw in upstream's
  graph: a chain member whose percent width resolves late, such as the first
  member of a chain whose last member's end links nowhere, and a baseline link
  from a widget that had no baseline when the graph was built. The graph
  leaves both unresolved and hands the layout to the solver.
- Laying a container out again, after its widgets or links changed, gives
  the result a freshly built container with the same widgets and links
  would, when each changed widget is configured as a new one would be (as
  the Flutter adapter does). Each `layout()` first forgets the final
  positions of the last one, as Android's `Direct` pass does on every
  measure, and a reset run or dependency node comes out as a fresh one,
  where upstream's graph keeps a node's margin dependency and a run's type
  and baseline dimension from the graph it built before. As upstream, a size
  override that the solver loop left pending is applied by the next
  `layout()`.
- Virtual layouts: `Flow` and `GridCore`. `GridCore` follows core 1.1.1:
  `setFlags` takes an int bitmask of `SUB_GRID_BY_COL_ROW` (1) and
  `SPANS_RESPECT_WIDGET_ORDER` (2), where the pinned revision took a list of
  flags; a weight list of the wrong length is padded with 1 or trimmed, and an
  unparsable weight reads as 1; spans and skips are sorted by position; and
  span entries past the last widget are ignored, where upstream throws.
  Unlike upstream, it also mirrors its columns in a right-to-left container
  (see `UPSTREAM.md` for this and its other divergences).
- `GridEngine`, upstream's standalone grid cell-placement class, which
  `GridCore` does not use.
- A `Measurer` interface through which a host measures its children, keeping
  each measured size within the widget's match-constraint min and max, as
  Android's measurer does. The default measurer, which `layout()` installs
  when none is set, keeps that contract too.
- The upstream core test suite, ported in full: all 278 in-scope tests, each
  with its whole upstream body (the one that upstream disables is skipped here
  too), including `LayoutTest`, `ArrayLinkedVariablesTest`, `GridEngineTest`,
  and `ComposeLayoutsTest`, whose `state/` API calls are rebuilt as direct
  widget calls. `UPSTREAM.md` lists the out-of-scope test files and every
  intentional divergence from upstream.
