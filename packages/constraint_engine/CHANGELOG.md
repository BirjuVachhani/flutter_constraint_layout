## 1.0.0

Initial release: a pure-Dart port of `androidx.constraintlayout.core`, pinned
to a specific upstream revision. The solver and widget classes are verified at
parity with the released core 1.1.1; the Grid helper (`GridCore`) still follows
the pinned revision. See `UPSTREAM.md`.

- The widget model: `ConstraintWidgetContainer` and `ConstraintWidget` with
  anchors, margins and gone-margins, bias, visibility, dimension behaviours
  (fixed, wrap content, match parent, and match constraint in its spread, wrap,
  percent, and ratio modes), min/max bounds, chains, `Guideline`, and
  `Barrier`.
- The dependency-graph resolver (`DependencyGraph` and its widget runs), which
  is tried first and measures each child once.
- The Cassowary `LinearSystem` solver, used for the layouts the graph declines,
  such as layouts with a barrier, chains with gone or ratio-sized members,
  circular constraints, and virtual layouts.
- Virtual layouts: `Flow` and `GridCore`.
- A `Measurer` interface through which a host measures its children.
- The upstream core test suite, ported. `UPSTREAM.md` lists the few files and
  solver passes that are not, and every intentional divergence from upstream.
