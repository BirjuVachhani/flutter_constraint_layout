# ConstraintLayout for Flutter

A Flutter port of Android's ConstraintLayout: position and size children with
constraints instead of nesting. The layout engine is a faithful Dart port of
`androidx.constraintlayout.core` (both the dependency-graph resolver and the
Cassowary `LinearSystem` solver), driven by a persistent, incrementally
invalidated model so steady-state layouts cost a fraction of a millisecond.

## Features

- **Anchors and links**: constrain any edge (`left`, `right`, `start`, `end`,
  `top`, `bottom`, `baseline`) to a sibling or the parent, with margins and
  gone-margins.
- **Dimensions**: `fixed`, `wrapContent`, `matchParent`, `matchConstraint`,
  plus `percent`, min/max bounds (`spread`), and constrained wrap
  (`constrainedWrap`).
- **Chains**: `spread`, `spreadInside`, and `packed` styles, with weighted
  members.
- **Bias and aspect ratio**: position between anchors, derive one dimension
  from the other.
- **Helpers**: `Guideline` (begin/end/percent), `Barrier` (tracks the furthest
  edge of referenced widgets).
- **Virtual layouts**: `ConstraintFlow` (wrapping chains, the ConstraintLayout
  answer to Wrap) and `ConstraintGrid` (rows/columns with spans, skips, and
  weights).
- **Circular positioning**: place a widget at an angle and radius around
  another.
- **Visibility**: `visible`, `invisible` (keeps its space), and `gone`
  (collapses, activates gone-margins).

## Usage

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #avatar,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      width: .fixed(56),
      height: .fixed(56),
      child: const CircleAvatar(),
    ),
    Constrained(
      id: #name,
      start: .endOf(#avatar, margin: 12),
      end: .endOf(parent, margin: 16),
      top: .topOf(#avatar),
      width: .matchConstraint,
      child: const Text('Ada Lovelace'),
    ),
    Barrier(id: #headerEnd, edge: .bottom, referenced: const [#avatar, #name]),
    Constrained(
      id: #bio,
      start: .startOf(parent, margin: 16),
      end: .endOf(parent, margin: 16),
      top: .bottomOf(#headerEnd, margin: 12),
      width: .matchConstraint,
      child: const Text('Enchantress of numbers.'),
    ),
  ],
)
```

Children are identified by `Symbol` ids and reference each other through
type-safe links; `parent` refers to the layout itself. See the `playground/`
app for runnable scenarios.

## Debug visualization

Two flags on `ConstraintLayout` replicate Android Studio's design surface, so
you can see the constraint graph the engine is solving:

```dart
ConstraintLayout(
  debugShowChains: true,        // overlay on top of the real children
  // or
  debugShowBlueprint: true,     // blueprint: boxes + labels instead of children
  debugChainColor: Colors.pink, // optional: tint the whole overlay
  debugBlueprintLabelStyle: DebugLabelStyle.both,
  children: [...],
)
```

- **`debugShowChains`** paints the overlay over the normally painted children:
  constraint connections as curved arrows, opposing constraints as zigzag
  springs (the far leg of a biased pair is dashed), chains as interlocking
  chain links, margin values with end ticks, plus guidelines and barriers.
- **`debugShowBlueprint`** does not paint the children at all. Instead it
  draws the Android Studio blueprint surface: a dark teal background with a
  translucent framed box per child, labels, and the same constraint drawing.
  Children are still laid out and hit-testable. When both flags are set,
  blueprint wins.
- **`debugChainColor`** tints every overlay line (constraints, chains,
  springs, guidelines, barriers, frames); anchors and labels derive shades
  from it. When null, the authentic Android Studio palette is used.
- **`debugBlueprintLabelStyle`** picks the text inside blueprint boxes:

  | Value | Draws |
  |---|---|
  | `id` | the child's `Symbol` id, e.g. `avatar` |
  | `label` | the child widget's runtimeType, e.g. `Text` |
  | `both` | id with the runtimeType below it (default) |
  | `none` | no text |

The rendering replicates the Android Studio design-surface specs (connection
classification, spring and chain-link geometry, the blueprint palette) lifted
from the layout-editor source; see `docs/DEBUG_VISUALIZATION.md` for the full
spec. The playground app has app-bar toggles for both modes on every scenario.

By default the overlays only render in debug builds: both flags are honored
when `kDebugMode` is true and are inert no-ops in profile and release. To force
them on outside debug (for a hosted showcase, a screenshot build, or a release
diagnostic), set the global switch before the overlay is painted:

```dart
ConstraintLayout.allowDebugFlags = true; // defaults to kDebugMode
```

It defaults to `kDebugMode`. Enabling it keeps the debug-overlay rendering code
in the release binary, so leave it at the default unless you actually need the
overlays in a non-debug build.

## How the engine works

ConstraintLayout does not position children by nesting boxes; it solves for
each child's location and size from the constraints you declare. This package
does that with a two-strategy engine, both parts ported from
`androidx.constraintlayout.core`.

### Two resolution strategies

**Dependency graph (the primary path).** Most layouts are deterministic: once
the parent's size and a widget's anchors and dimension are known, its position
follows by propagation. The graph models each measurable quantity (a left edge,
a width, a baseline) as a node that depends on others, resolves them in
dependency order, and measures each child exactly once. There is no iteration
and no search, so it is fast and its cost scales close to linearly with the
widget count. This is the path almost every real screen takes.

**Cassowary solver (the fallback).** Some arrangements are not a simple
propagation but a genuine system of simultaneous equations and inequalities
that must be solved together: a chain whose members share out leftover space by
weight, a widget centered between two moving anchors, an aspect-ratio member
inside a chain. For those, the engine falls back to a linear constraint solver.

### The Cassowary solver

The fallback is a faithful port of Android's `LinearSystem`, which implements
the **Cassowary** linear-arithmetic constraint algorithm (Badros, Borning &
Stuckey; the same algorithm family behind Apple's Auto Layout). In short, it:

- expresses the layout as a system of linear **equations** (one anchor equals
  another anchor plus a margin) and **inequalities** (an edge must stay inside
  the parent),
- introduces a **slack variable** for each inequality so it can be handled as
  an equation,
- carries the constraints that cannot all be satisfied as **error variables**
  weighted by a **strength** (from `STRENGTH_LOW` up to `STRENGTH_FIXED`), so a
  required constraint always outranks an optional one, and
- **minimizes** the weighted sum of those errors with an incremental simplex
  method: it pivots a tableau toward the objective and reuses the previous
  solution between passes.

Two clarifications, because the name gets used loosely:

- It is Cassowary *by algorithm*, but it is Google's own implementation tuned
  for layout, not the reference Cassowary code and not the same codebase as
  kiwi, cassowary.js, or Auto Layout. Upstream's source never actually names it
  "Cassowary"; `LinearSystem` only calls itself a solver for "a system of linear
  equations." The name used here describes its heritage.
- In this package the solver is strictly the fallback. The graph runs first,
  and the solver runs only for the sub-layouts the graph declines (below).

### When the solver runs

The graph resolves what it can resolve faithfully and **declines** (routing the
whole layout to the solver) for the cases it cannot: chains with `gone` or
ratio-sized members, chains along a `wrapContent` axis, constrained-wrap
(`MATCH_CONSTRAINT_WRAP`) widgets, circular (center-at-angle) constraints,
nested containers, widgets centered along a wrap axis, wrap results whose
children overflow the computed bounds, and virtual layouts (`ConstraintFlow`
and `ConstraintGrid`, whose member constraints are created during the solver
pass). Before handing off, the engine snapshots and restores the pre-graph
widget state and re-measures wrap-sized children, so the solver sees the same
input Android's solver-first path would, and the two produce matching results.

### Persistent model and caching

The engine model (widgets, anchors, the graph) is built once and kept alive
across frames, then invalidated in tiers so a steady-state frame does as little
work as possible:

- **fast**: nothing affecting layout changed, so the engine is skipped entirely
  and the previous geometry is reused. This is what carries scrolling and
  animation over a static constraint graph.
- **in-place**: a property changed that the existing model can absorb (a margin,
  a bias, a dimension), so the model is updated in place and re-resolved without
  being rebuilt.
- **rebuild**: the child set or a helper changed structurally, so the model is
  rebuilt from scratch.

Before every engine pass the adapter zeroes each non-fixed stored size, so a
reused model resolves identically to a freshly built one and no state leaks
between frames. The benchmarks under `benchmark/` and
`packages/constraint_engine/benchmark/` measure these tiers: the graph path
resolves a 1200-widget screen in well under a millisecond, while the solver
path is heavier and scales super-linearly, which is exactly why it is reserved
for the layouts that need it.

## How it relates to Android ConstraintLayout

The engine (`packages/constraint_engine`) is a line-faithful port of
`constraintlayout-core`, pinned to a specific upstream revision and verified
at parity with the released core 1.1.1 (see
`packages/constraint_engine/UPSTREAM.md` for the pin and every intentional
divergence). The upstream core test suite is ported and green.

The one structural departure is the entry path: Android runs the Cassowary
solver by default with an optional graph optimization, whereas this port tries
the dependency graph first and falls back to the solver (see
[How the engine works](#how-the-engine-works)). Both classes of layout resolve
to the same result Android produces.

### Non-goals

These upstream areas are intentionally not ported:

- **MotionLayout** (`motion/`): animation is a different feature in Flutter;
  a constraint-animation story would be Flutter-idiomatic, not a port.
- **JSON constraint sets** (`parser/`, `dsl/`, `state/`): the widget API and
  the Flutter adapter replace them.
- **`Placeholder`**: niche; use conditional ids instead.
- **The `Direct`/`Grouping` optimizers**: performance shortcuts in front of
  upstream's solver; the graph-first architecture fills that role here.

## Status

Pre-release. The package name will change before publishing (the pub.dev name
`constraint_layout` is taken).
