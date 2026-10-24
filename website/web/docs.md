# flutter_constraint_layout

> A faithful port of Android ConstraintLayout to Flutter, in pure Dart. Every child is a direct child of one `ConstraintLayout`, and each child declares where its own edges go (pinned to the parent or to a sibling by id) and how it is sized. The widget tree stays flat instead of nesting rows, columns, and stacks, and the same layout runs on iOS, Android, web, macOS, Windows, and Linux.

This file is the flutter_constraint_layout docs page in a single Markdown file, meant to be fed to an LLM or read offline. It mirrors the live docs at https://constraints.birju.dev/docs (the docs page is the source of truth). It is a guided tour of the features, not the full reference: the package README is the full guide, covering every option plus z-order, sizing inside scroll views and intrinsic sizing, the debug overlay, unknown and duplicate ids, common mistakes, performance, and the limitations and differences from Android.

- Package: https://pub.dev/packages/flutter_constraint_layout
- Full guide (package README): https://github.com/BirjuVachhani/constraint_layout/blob/main/packages/flutter_constraint_layout/README.md
- Source: https://github.com/BirjuVachhani/constraint_layout

## Introduction

ConstraintLayout is a layout for Flutter, ported from Android, that positions and sizes children by the **constraints you declare** instead of by nesting boxes. Every child is a direct child of one `ConstraintLayout`, and each says where its own edges go: pinned to the parent, or to a sibling.

If you have built Flutter UIs you know the other way: a `Row` inside a `Column` inside a `Stack` inside a `Padding`, several levels deep, just to place a handful of widgets. ConstraintLayout keeps the tree **flat**. Relationships that would otherwise need wrapper widgets ("put this after that", "line these up", "let this one fill the rest") become properties on the child itself.

### The mental model

- **Anchor, not nest.** A child links its edges (`start`, `top`, and so on) to the parent or a sibling. `top: .bottomOf(#header)` reads as "my top goes at the header's bottom".
- **Ids, not order.** Children are identified by a `Symbol` id (like `#header`) and refer to each other by id, so the order of the list does not decide position.
- **Solve, not stack.** One engine resolves every edge and size from the constraints in a single pass. See **How the engine works**.

The rest of these docs walk the features one at a time, each with a live example you can read beside the layout it produces. Everything is behind a single import. These docs are a guided tour; the package README on pub.dev is the full guide and also covers z-order, sizing inside scroll views, the debug overlay, common mistakes, and the limitations.

## Features

Most of Android's ConstraintLayout is here, behind a single import and a Flutter-native API. MotionLayout, `ConstraintSet`, and the `Group`, `Layer`, and `Placeholder` helpers are not ported. At a glance, this is what you get:

### Positioning

- **Anchors and links.** Pin any edge (`start`, `end`, `top`, `bottom`, the absolute `left` / `right`, or the text `baseline`) to the parent or a sibling, with per-link `margin` and `goneMargin`.
- **Centering and bias.** Opposing anchors center a child; `horizontalBias` / `verticalBias` slide it along the axis, proportional as the parent resizes.
- **Circular positioning.** Place a child at an angle and radius around another, for dials, clock faces, and radial menus.

### Sizing

- **Dimensions beyond wrap and fill.** `.matchConstraint` fills the span between two anchors, `.percent` takes a fraction of the parent, and `.spread` / `.constrainedWrap` bound a fill or a wrap.
- **Aspect ratio.** Fix one axis and derive the other to hold a `width / height` ratio, ideal for 16 : 9 or square media.

### Chains and helpers

- **Chains with weights.** Widgets linked to each other share an axis like flexbox: `.spread`, `.spreadInside`, or `.packed`, splitting leftover space by per-child weight.
- **Guidelines.** An invisible line at a fixed offset or a percent of the parent that many siblings can share.
- **Barriers.** A line that tracks the furthest edge of a group, so content always clears the tallest or widest member.
- **Visibility.** Every child is `visible`, `invisible` (holds its space), or `gone` (collapses, switching links to `goneMargin`).

### Virtual layouts

- **Flow and Grid.** `ConstraintFlow` and `ConstraintGrid` arrange referenced children without wrapping them, so those children stay direct siblings other constraints can still target.

### Under it all

- **A two-strategy engine.** A fast dependency graph for the common case, a Cassowary solver for the genuinely simultaneous one.
- **Pure Dart, every platform.** RTL-aware anchors, no native code, and a resolver verified at parity with androidx core 1.1.1.

Each of these has its own section below, with a live example you can read beside the layout it produces.

## Installation

> Requires Dart 3.12 or newer and Flutter 3.44 or newer. The API is designed around Dart dot shorthands such as `.startOf(parent)`, which every example in these docs uses.

Add the package with the Flutter CLI:

```shellscript
flutter pub add flutter_constraint_layout
```

Or add it to your `pubspec.yaml` directly:

**`pubspec.yaml`**

```yaml
dependencies:
  flutter_constraint_layout: ^1.0.0
```

Then import it. That one import brings in every widget, dimension, link, and helper you will see in these docs:

```dart
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
```

## Quick start

Here is a complete `ConstraintLayout` with one child, pinned 16 logical pixels from the parent's top-start corner.

> Every example uses `DemoBox`, a plain colored box with a label, in place of real content, so the focus stays on the constraints. Swap it for any widget of your own.

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #box,
      // My start edge, 16 from the parent's start edge.
      start: .startOf(parent, margin: 16),
      // My top edge, 16 from the parent's top edge.
      top: .topOf(parent, margin: 16),
      child: DemoBox('A'),
    ),
  ],
)
```

Read each link as **"my edge, at the target's edge"**: `start: .startOf(parent, margin: 16)` puts this child's start edge 16 past the parent's start edge. Point it at a sibling id instead of `parent` to pin to a sibling. That single idea, an edge linked to an edge, is the whole foundation.

## Anchors & links

A **link** ties one of this widget's edges to an edge of a target. The parameter names your edge; the constructor names the target's edge. Horizontal edges come in absolute (`left`, `right`) and RTL-aware (`start`, `end`) pairs; vertical edges are `top`, `bottom`, and the text `baseline`.

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #a,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      child: DemoBox('A'),
    ),
    Constrained(
      id: #b,
      // Chain off a sibling: B's start sits at A's end.
      start: .endOf(#a, margin: 12),
      top: .topOf(#a),
      child: DemoBox('B'),
    ),
  ],
)
```

In the example, B links to A rather than to the parent: `start: .endOf(#a)` places B just after A and `top: .topOf(#a)` lines their tops up. Move A and B follows.

### The links

| Your edge | Kind | Constructors (the target's edge) |
| --- | --- | --- |
| `left` / `right` | Absolute horizontal edges | `.leftOf` `.rightOf` `.startOf` `.endOf` |
| `start` / `end` | RTL-aware horizontal edges | `.startOf` `.endOf` `.leftOf` `.rightOf` |
| `top` / `bottom` | Vertical edges | `.topOf` `.bottomOf` |
| `baseline` | Text baseline | `.baselineOf` `.topOf` `.bottomOf` |
| `circle` | Center, on a circle around the target's center | `.around` (see **Circular positioning**) |

Every link constructor except `.around` takes a `margin`, and a `goneMargin` used instead when the target is `gone` (see **Visibility**). A `top` or `bottom` link to `.baselineOf` is ignored; align baselines through `baseline`.

> Build each id the same way everywhere it appears. For ids made in a loop with `Symbol('item$i')`, refer to them through the same call, for example a helper `Symbol item(int i) => Symbol('item$i');`, never through a literal such as `#item0` or a `const Symbol('item0')`. Release and profile WebAssembly builds, and builds compiled with `--obfuscate`, rename symbol literals, so there `#item0` is not equal to `Symbol('item0')` and a link that mixes the two forms is silently skipped. Debug builds treat them as equal, so the mistake does not show up while you develop.

### Right-to-left

`start` and `end` follow the text direction: the layout's `textDirection`, otherwise the ambient `Directionality`. A layout written with them mirrors in right-to-left text, and, following Android's rules, so do these:

- The horizontal bias of a child with a `start` or `end` link: it becomes `1 - horizontalBias`, so it is measured from the start, a packed chain's bias included. A child linked only with `left` and `right` keeps its bias measured from the left.
- Vertical guidelines: `begin` and `percent` are measured from the right and `end` from the left. Horizontal guidelines do not change.
- `ConstraintFlow`: its rows start at the right edge, and `contentHorizontalBias` is measured from the start.

Two things do not mirror: a barrier's `margin` always moves it right or down, and `ConstraintGrid` fills its cells from the left.

## Centering & bias

Give a widget **both** opposing anchors on an axis (start and end, or top and bottom) and it centers between them. Add `horizontalBias` or `verticalBias` to slide it along that axis: 0 hugs the left or top, 1 hugs the right or bottom, and the default 0.5 is dead center. In right-to-left text the horizontal bias of a child linked with `start` or `end` mirrors, as on Android, so 0 hugs the right (see **Anchors & links**).

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #box,
      // Both horizontal and both vertical anchors: centered by default...
      start: .startOf(parent),
      end: .endOf(parent),
      top: .topOf(parent),
      bottom: .bottomOf(parent),
      // ...then biased off-center: 25% across, 70% down.
      horizontalBias: 0.25,
      verticalBias: 0.7,
      child: DemoBox('A'),
    ),
  ],
)
```

Bias is how you place something "a third of the way down" or "near the end" without hardcoding pixels: it stays proportional as the parent resizes.

## Dimensions

A child's `width` and `height` are each a `Dimension`. Beyond the familiar wrap-to-content and fill-the-parent, ConstraintLayout adds sizes that only make sense with constraints: fill the space **between two anchors**, or take a **percent** of the parent.

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #bar,
      start: .startOf(parent, margin: 16),
      end: .endOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      width: .matchConstraint, // fill the space between the anchors
      height: .fixed(44),
      child: DemoBox('matchConstraint'),
    ),
    Constrained(
      id: #half,
      start: .startOf(parent, margin: 16),
      end: .endOf(parent, margin: 16),
      top: .bottomOf(#bar, margin: 12),
      width: .percent(0.5),    // half the parent's width
      horizontalBias: 0,       // ...pinned to the start
      height: .fixed(44),
      child: DemoBox('percent 0.5'),
    ),
  ],
)
```

### The dimensions

| Dimension | Sizes to |
| --- | --- |
| `.wrapContent` | The child's own content (the default). |
| `.matchParent` | The parent's full size. Link targets are ignored, but their margins still inset it. |
| `.matchConstraint` | The space between the two opposing anchors. |
| `.fixed(n)` | Exactly n logical pixels. |
| `.percent(f)` | A fraction f of the parent on this axis. |
| `.spread(min: a, max: b)` | Like matchConstraint, but bounded. |
| `.constrainedWrap(...)` | Content, capped by the constraints. |

> `.matchConstraint` and `.spread` need **both** edges on the axis anchored, because they size to the space those edges define. `.percent` sizes to the parent instead, so one link is enough.

## Aspect ratio

Set `aspectRatio` and the engine derives one dimension from the other to hold a `width / height` ratio. Fix one axis, make the other `matchConstraint`, and it is computed for you, ideal for media that must stay 16 : 9 or square.

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #media,
      start: .startOf(parent),
      end: .endOf(parent),
      top: .topOf(parent),
      bottom: .bottomOf(parent),
      width: .fixed(200),
      height: .matchConstraint, // derived from the width...
      aspectRatio: 16 / 9,      // ...to keep width / height = 16 / 9
      child: DemoBox('16 : 9'),
    ),
  ],
)
```

## Chains

When two or more widgets link to **each other** in a line (first to second, second back to first, and so on) they form a **chain**: a group that shares its space as a unit, much like flexbox's justify-content. The two outer edges anchor to something outside the chain.

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #a,
      start: .startOf(parent),
      end: .startOf(#b),
      top: .topOf(parent),
      bottom: .bottomOf(parent),
      horizontalChainStyle: .spread, // set on the head
      child: DemoBox('A'),
    ),
    Constrained(
      id: #b,
      start: .endOf(#a),
      end: .startOf(#c),
      top: .topOf(#a),
      child: DemoBox('B'),
    ),
    Constrained(
      id: #c,
      start: .endOf(#b),
      end: .endOf(parent),
      top: .topOf(#a),
      child: DemoBox('C'),
    ),
  ],
)
```

### Chain styles

Set the style on the chain's **head** (the first member) with `horizontalChainStyle` or `verticalChainStyle`:

- **`.spread`** (default): equal gaps everywhere, including the ends.
- **`.spreadInside`**: the ends sit flush against the outer anchors, with equal gaps between members.
- **`.packed`**: members are packed together and the head's bias moves the packed group along the axis.

Give members a `matchConstraint` size along the axis plus a `horizontalWeight` or `verticalWeight` to split the leftover space by ratio, exactly like `Expanded`'s flex.

## Guidelines

A `Guideline` is an invisible line at a fixed offset or a **percent** of the parent that siblings anchor to. It is ideal for a shared column edge: everything linked to it moves together when the guideline moves.

```dart
ConstraintLayout(
  children: [
    // A vertical line at 40% of the width.
    Guideline.vertical(id: #split, percent: 0.4),
    Constrained(
      id: #label,
      end: .leftOf(#split, margin: 8),
      top: .topOf(parent, margin: 16),
      child: DemoBox('label'),
    ),
    Constrained(
      id: #value,
      start: .rightOf(#split, margin: 8),
      top: .topOf(#label),
      child: DemoBox('value'),
    ),
  ],
)
```

Use `Guideline.vertical` for a vertical line (siblings link their horizontal edges to it) and `Guideline.horizontal` for a horizontal one. Position it with exactly one of `begin`, `end`, or `percent`.

## Barriers

A `Barrier` is a line that tracks the **furthest** edge of a set of widgets. Anchor a form's value column to a barrier over its labels and the column always clears the longest label, no matter which one grows.

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #a,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      width: .fixed(70),
      child: DemoBox('A'),
    ),
    Constrained(
      id: #b,
      start: .startOf(parent, margin: 16),
      top: .bottomOf(#a, margin: 12),
      width: .fixed(130),
      child: DemoBox('B is wider'),
    ),
    // Sits at the rightmost end of A and B.
    Barrier(id: #barrier, edge: .end, referenced: [#a, #b], margin: 12),
    Constrained(
      id: #c,
      start: .startOf(#barrier),
      top: .topOf(#a),
      bottom: .bottomOf(#b),
      height: .matchConstraint,
      child: DemoBox('C'),
    ),
  ],
)
```

Pick the `edge` to track (`start`, `end`, `top`, `bottom`, and the absolute `left` / `right`) and list the widgets in `referenced`. A barrier has no size and draws nothing; it only reports a position. A layout that contains one is resolved by the Cassowary solver rather than the faster dependency graph (see **How the engine works**).

## Circular positioning

The `circle` link places a widget at an **angle and radius** around another widget's center, for radial menus, clock faces, or anything arranged on a dial. 0 degrees points straight up and angles increase clockwise.

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #hub,
      start: .startOf(parent),
      end: .endOf(parent),
      top: .topOf(parent),
      bottom: .bottomOf(parent),
      child: DemoBox('hub'),
    ),
    Constrained(
      id: #a,
      circle: .around(#hub, angle: 0, radius: 72),
      child: DemoBox('0°'),
    ),
    Constrained(
      id: #b,
      circle: .around(#hub, angle: 120, radius: 72),
      child: DemoBox('120°'),
    ),
    Constrained(
      id: #c,
      circle: .around(#hub, angle: 240, radius: 72),
      child: DemoBox('240°'),
    ),
  ],
)
```

## Visibility

Every child has a `visibility`, mirroring Android's three states:

- **`.visible`** (default): laid out and drawn.
- **`.invisible`**: laid out and holds its space, but is not drawn, siblings still anchor to it exactly as if it were there.
- **`.gone`**: collapses to a zero-size point and is skipped entirely, and links targeting it switch from `margin` to `goneMargin`.

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #a,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      child: DemoBox('A'),
    ),
    Constrained(
      id: #b,
      start: .endOf(#a, margin: 12),
      top: .topOf(#a),
      visibility: .gone, // collapses to a zero-size point
      child: DemoBox('B'),
    ),
    Constrained(
      id: #c,
      // 12 past B normally; 40 past its collapsed point when B is gone.
      start: .endOf(#b, margin: 12, goneMargin: 40),
      top: .topOf(#a),
      child: DemoBox('C'),
    ),
  ],
)
```

`gone` removes a widget and reflows around it in one step, and `goneMargin` lets neighbors keep a sensible gap when they do. Because it is only a property, toggling it keeps the child mounted, so its state survives the round trip.

### Try it

The live docs include an interactive version of this example: flip B between the three states and watch C. `invisible` keeps B's space (C does not move), while `gone` collapses it and C slides in on its `goneMargin`.

## Flow

If you have reached for `Wrap` to lay a run of chips or buttons out and let them spill onto the next line, `ConstraintFlow` is the constraint-native version. The difference is that it is **virtual**: it does not wrap the widgets it arranges in a subtree of its own.

### What "virtual" means

A normal layout widget like `Row` or `Wrap` becomes the parent of its children: they live inside it, and nothing outside can point at them. A virtual layout is different. Its children stay **direct siblings** in the one `ConstraintLayout`; the flow only reads their sizes and hands back positions. You list the ones it should arrange by id in `referenced`, and they remain fair game for any other constraint, so a barrier or a chain can still target a widget that a flow is placing.

It lays the referenced widgets out in a chain and wraps to a new run when it runs out of width, just like `Wrap`, but every wrapped run is itself a chain you can style.

```dart
const labels = [
  'constraint', 'layout', 'wraps', 'when', 'it',
  'runs', 'out', 'of', 'room',
];

ConstraintLayout(
  children: [
    for (final (i, label) in labels.indexed)
      Constrained(id: Symbol('c$i'), child: DemoBox(label)),
    ConstraintFlow(
      id: #flow,
      referenced: [for (var i = 0; i < labels.length; i++) Symbol('c$i')],
      start: .startOf(parent, margin: 12),
      end: .endOf(parent, margin: 12),
      top: .topOf(parent, margin: 12),
      width: .matchConstraint,
      wrap: .chain,
      horizontalGap: 8,
      verticalGap: 8,
      horizontalChainStyle: .packed,
      contentHorizontalBias: 0,
    ),
  ],
)
```

### Wrap modes

- **`.none`** (default): a single run that does not wrap (a plain chain).
- **`.chain`**: wraps into as many runs as it needs, filling each run before starting the next and laying each one out as its own chain, the closest match to `Wrap`.
- **`.aligned`**: wraps and also lines the runs up column-for-column, so the result reads as a grid.

Set `horizontalGap` and `verticalGap` for the spacing between items and runs, and `horizontalChainStyle` / `contentHorizontalBias` to control how each run distributes its slack, as a chain's style and bias do. `contentHorizontalBias` is always measured from the start, so it mirrors in right-to-left text.

## Grid

`ConstraintGrid` is to `GridView` what `ConstraintFlow` is to `Wrap`: it places its `referenced` children into a fixed grid of `rows` by `columns` cells, in order. Unlike `GridView` it does not scroll and does not become their parent; it is **virtual**, so the tiles stay siblings in the single layer that other constraints can still target.

Children fill the cells left to right, top to bottom. Give a tile `width: .matchConstraint` and `height: .matchConstraint` to fill its cell, or leave it to wrap its own content and sit within the cell.

```dart
ConstraintLayout(
  children: [
    for (var i = 0; i < 5; i++)
      Constrained(
        id: Symbol('t$i'),
        width: .matchConstraint,
        height: .matchConstraint,
        child: DemoBox('${i + 1}'),
      ),
    ConstraintGrid(
      id: #grid,
      referenced: [for (var i = 0; i < 5; i++) Symbol('t$i')],
      rows: 2,
      columns: 3,
      spans: '0:1x2', // cell 0 spans two columns
      horizontalGap: 8,
      verticalGap: 8,
      start: .startOf(parent, margin: 12),
      end: .endOf(parent, margin: 12),
      top: .topOf(parent, margin: 12),
      bottom: .bottomOf(parent, margin: 12),
    ),
  ],
)
```

### Spans, skips, and weights

- **Spans** let one tile cover several cells: `spans: '0:1x2'` makes the tile at cell 0 span one row and two columns, using Android's `index:RxC` syntax.
- **Skips** leave cells empty so the flow of tiles steps over them, with the same `index:RxC` syntax in `skips`.
- **Weights** (`rowWeights`, `columnWeights`) hand out the grid's space unevenly, so a column can take twice the width of its neighbor.

Anchor the grid itself like any child (here all four edges to the parent), and it sizes and positions the whole set of tiles as a unit.

## A profile card

Here is a small, real layout that uses several features at once: an avatar, a name and handle beside it, a **barrier** under the taller of the header pieces, and a bio spanning the full width below. It is one flat layer, with no `Row`, `Column`, or `Stack` nesting.

**`profile_card.dart`**

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #avatar,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      width: .fixed(56),
      height: .fixed(56),
      child: DemoBox('IMG'),
    ),
    Constrained(
      id: #name,
      start: .endOf(#avatar, margin: 12),
      end: .endOf(parent, margin: 16),
      top: .topOf(#avatar),
      width: .matchConstraint,
      height: .fixed(24),
      child: DemoBox('Ada Lovelace'),
    ),
    Constrained(
      id: #handle,
      start: .startOf(#name),
      top: .bottomOf(#name, margin: 6),
      height: .fixed(20),
      child: DemoBox('@ada'),
    ),
    Barrier(id: #headerEnd, edge: .bottom, referenced: [#avatar, #handle]),
    Constrained(
      id: #bio,
      start: .startOf(parent, margin: 16),
      end: .endOf(parent, margin: 16),
      top: .bottomOf(#headerEnd, margin: 16),
      width: .matchConstraint,
      height: .fixed(48),
      child: DemoBox('Enchantress of numbers'),
    ),
  ],
)
```

Each piece states its own relationships: the name fills the width up to the parent's end (`matchConstraint`), the handle sits under the name, and the bio starts below `#headerEnd` (the barrier), so it always clears both the avatar and the text no matter which is taller.

## How the engine works

ConstraintLayout does not position children by nesting boxes; it **solves** for each child's location and size from the constraints you declared. It does that with a two-strategy engine, both parts faithfully ported from `androidx.constraintlayout.core`.

### Dependency graph (the fast path)

Most layouts are deterministic: once the parent size and a widget's anchors and dimension are known, its position follows by propagation. The graph models each measurable quantity as a node, resolves them in dependency order, and measures each child exactly once, with no iteration and no search. This is the path almost every real screen takes, and its cost scales close to linearly with the widget count.

### Cassowary solver (the fallback)

Some layouts are outside what the graph resolves, and for those the engine falls back to a linear constraint solver, a port of Android's `LinearSystem`, which implements the **Cassowary** algorithm (the same family behind Apple's Auto Layout). A layout takes this path when it contains a barrier, a `circle` link, a `.constrainedWrap` size, a `ConstraintFlow` or `ConstraintGrid`, an `aspectRatio` child whose width and height are both `.matchConstraint`, or a chain with a `gone` or aspect-ratio member. It also takes this path when the layout sizes to its content along an axis that has a chain, a child anchored on both sides, or a child extending outside the layout, and for anything else the graph cannot resolve directly.

### Persistent, incremental model

The engine model is built once and kept alive across frames, then invalidated in tiers so a steady-state frame does as little as possible:

- **fast**: nothing layout-affecting changed, the incoming constraints are the same, and no child's size or position depends on its content: no `.wrapContent` or `.constrainedWrap` size, no `.matchConstraint`, `.spread`, or `.percent` size missing one of its two links, and no baseline alignment. The engine is skipped and the previous geometry reused.
- **in-place**: a link, margin, bias, size, ratio, chain style, weight, or visibility changed, so the model is updated in place and re-resolved without a rebuild. New incoming constraints, and any pass the fast tier does not cover, also re-resolve the existing model.
- **rebuild**: the child set or a helper changed structurally, or the text direction changed, so the model is rebuilt from scratch.

The graph path resolves a 1200-widget screen in well under a millisecond; the solver is heavier and reserved for the layouts that genuinely need it.

## Relation to Android

The engine is a line-faithful port of `constraintlayout-core`, pinned to a specific upstream revision. Its solver and widget classes are verified at parity with the released core 1.1.1 (only the Grid helper still follows the pinned revision), and nearly all of upstream's core test suite is ported and green, so a given layout resolves to the same result Android produces. Right-to-left text follows Android's rules too: the horizontal bias of a child linked with start or end mirrors, and so does the position of a vertical guideline (see **Anchors & links**).

The one structural departure is the entry path: Android runs the Cassowary solver by default with an optional graph optimization, whereas this port tries the dependency graph first and falls back to the solver (see **How the engine works**).
