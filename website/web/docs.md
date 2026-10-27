# flutter_constraint_layout

> A faithful port of Android ConstraintLayout to Flutter, in pure Dart. Every child is a direct child of one `ConstraintLayout`, and each child declares where its own edges go (pinned to the parent or to a sibling by id) and how it is sized. The widget tree stays flat instead of nesting rows, columns, and stacks, and the same layout runs on iOS, Android, web, macOS, Windows, and Linux.

This file is the flutter_constraint_layout docs page in a single Markdown file, meant to be fed to an LLM or read offline. It mirrors the live docs at https://constraints.birju.dev/docs (the docs page is the source of truth). It is a guided tour of the features, not the full reference: the package README is the full guide, covering every option plus z-order, sizing inside scroll views and intrinsic sizing, the debug overlay, unknown and duplicate ids, common mistakes, Android parity, optimization levels, performance, and the limitations and differences from Android.

- Package: https://pub.dev/packages/flutter_constraint_layout
- Full guide (package README): https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/flutter_constraint_layout/README.md
- Source: https://github.com/BirjuVachhani/flutter_constraint_layout

## Introduction

ConstraintLayout is a layout for Flutter, ported from Android, that positions and sizes children by the **constraints you declare** instead of by nesting boxes. Every child is a direct child of one `ConstraintLayout`, and each says where its own edges go: pinned to the parent, or to a sibling.

If you have built Flutter UIs you know the other way: a `Row` inside a `Column` inside a `Stack` inside a `Padding`, several levels deep, just to place a handful of widgets. ConstraintLayout keeps the tree **flat**. Relationships that would otherwise need wrapper widgets ("put this after that", "line these up", "let this one fill the rest") become properties on the child itself.

### The mental model

- **Anchor, not nest.** A child links its edges (`start`, `top`, and so on) to the parent or a sibling. `top: .bottomOf(#header)` reads as "my top goes at the header's bottom".
- **Ids, not order.** Children are identified by a `Symbol` id (like `#header`) and refer to each other by id, so the order of the list does not decide position.
- **Solve, not stack.** Android's own layout engine, ported to Dart, resolves every edge and size from the constraints. See **How the engine works**.

The rest of these docs walk the features one at a time, each with a live example you can read beside the layout it produces. Everything is behind a single import. These docs are a guided tour; the package README on pub.dev is the full guide and also covers z-order, sizing inside scroll views, the debug overlay, common mistakes, Android parity, performance, and the limitations.

## Features

Most of Android's ConstraintLayout is here, behind a single import and a Flutter-native API. MotionLayout, `ConstraintSet`, and the `Layer` and `Placeholder` helpers are not ported. At a glance, this is what you get:

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
- **Barriers.** A line that tracks the furthest edge of a set of widgets, so content always clears the tallest or widest member.
- **Visibility.** Every child is `visible`, `invisible` (holds its space), or `gone` (collapses, switching links to `goneMargin`).
- **Groups.** A `ConstraintGroup` sets the visibility of several children at once, like Android's `Group`.

### Virtual layouts

- **Flow and Grid.** `ConstraintFlow` and `ConstraintGrid` arrange referenced children without wrapping them, so those children stay direct siblings other constraints can still target.

### Under it all

- **Android's pipeline.** The same measure passes, `Direct` pass, and Cassowary solver as Android's ConstraintLayout, in its 32-bit float arithmetic, so a layout gets Android's frames.
- **Pure Dart, every platform.** RTL-aware anchors, no native code, and frames checked against Android's own code on nearly two million layouts.

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

Here is a complete `ConstraintLayout` with one child, pinned 16 logical pixels from the parent's top-start corner. The source is on one side and the layout it renders on the other.

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

Links must not loop back on themselves. Four kinds of loop leave none of their children a position to start from: two children whose matching edges link to each other (two tops, for example), an edge linked to itself, two children linked both ways on both sides, and a chain whose first child's start links one way to its last child while the last child's end links back to the first child. Debug builds report each of them with a `FlutterError`, as they report a link to an unknown id; baseline links are not followed, so two baselines linked to each other are not reported. Profile and release builds still lay the layout out. Android never finishes laying out a layout with the last kind, and lays out the others as this layout does: two children whose tops link to each other, for example, both sit at the top edge.

> Build each id the same way everywhere it appears. For ids made in a loop with `Symbol('item$i')`, refer to them through the same call, for example a helper `Symbol item(int i) => Symbol('item$i');`, never through a literal such as `#item0` or a `const Symbol('item0')`. Release and profile WebAssembly builds, and builds compiled with `--obfuscate`, rename symbol literals, so there `#item0` is not equal to `Symbol('item0')` and a link that mixes the two forms is silently skipped. Debug builds treat them as equal, so the mistake does not show up while you develop.

### Right-to-left

`start` and `end` follow the text direction: the layout's `textDirection`, otherwise the ambient `Directionality`. A layout written with them mirrors in right-to-left text, and, following Android's rules, so do these:

- The horizontal bias of a child with a `start` or `end` link: it becomes `1 - horizontalBias`, so it is measured from the start, a packed chain's bias included. A child linked only with `left` and `right` keeps its bias measured from the left.
- Vertical guidelines: `begin` and `percent` are measured from the right and `end` from the left. Horizontal guidelines do not change.
- `ConstraintFlow`: its rows start at the right edge, and `contentHorizontalBias` is measured from the start.

`ConstraintGrid` mirrors too, which Android's grid helpers leave unimplemented: its first column is the rightmost, so the cells fill from the right. Cell numbers in `spans` and `skips`, and the entries of `columnWeights`, still count from the first column, and a tile's `horizontalBias` is measured from the start edge of its cell.

A barrier's own `margin` does not mirror: as on Android, a positive value moves every barrier right or down, a `.start` or `.end` one included. For a gap that mirrors, put it on the links that target the barrier.

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

*Opposing anchors on an axis center the child; bias slides it along (0 = start/top, 1 = end/bottom).*

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

*matchConstraint fills the gap between two anchors, so it needs both; percent takes a fraction of the parent, so one link is enough.*

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

> `.matchConstraint` and `.spread` need **both** edges on the axis anchored to fill the space between them. With only one link the child sizes to its own content instead, which `.spread` keeps between its `min` and `max` (the other dimension follows, so text wraps at a capped width). `.percent` sizes to the parent, so one link is enough.

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

*One axis is fixed; the matchConstraint axis is derived to hold the ratio. Here height follows a 200px width at 16 : 9.*

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

*Three boxes linked start-to-end form a chain. The style set on the head (A) governs the whole group; try spreadInside or packed.*

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

*A guideline is an invisible line at a fixed offset or a percent of the parent. Everything anchored to it moves together when it moves.*

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

*A barrier tracks the furthest edge of the widgets it references, so C clears whichever of A or B is wider, even as their content changes.*

Pick the `edge` to track (`start`, `end`, `top`, `bottom`, and the absolute `left` / `right`) and list the widgets in `referenced`. A barrier has no size and draws nothing; it only reports a position. Its own `margin` moves it, and keeps its sign as on Android: a positive value moves every barrier right or down, whatever its edge and the text direction. For a gap that mirrors in right-to-left text, put the margin on the links that target the barrier instead.

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

*Place a widget at an angle and radius around another. 0° points straight up and angles run clockwise.*

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

*A gone widget collapses to a point and links targeting it switch to their goneMargin, so C closes the gap B left behind.*

`gone` removes a widget and reflows around it in one step, and `goneMargin` lets neighbors keep a sensible gap when they do. Because it is only a property, toggling it keeps the child mounted, so its state survives the round trip. Invisible and gone children are also left out of the semantics tree, so screen readers neither announce nor activate them, as on Android. To set the visibility of several children at once, use a group (below).

### Try it

Flip B between the three states and watch C: `invisible` keeps B's space (C does not move), while `gone` collapses it and C slides in on its `goneMargin`.

### Groups

A `ConstraintGroup` sets the visibility of several children at once, like Android's `Group`. Its `visibility` replaces the `visibility` of every child listed in `referenced`, so one value from your state shows or hides a whole section of the layout:

```dart
bool expanded = false; // from your State

ConstraintLayout(
  children: [
    Constrained(
      id: #name,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      child: DemoBox('Ada Lovelace'),
    ),
    Constrained(
      id: #email,
      start: .startOf(#name),
      top: .bottomOf(#name, margin: 8),
      child: DemoBox('ada@example.com'),
    ),
    Constrained(
      id: #phone,
      start: .startOf(#name),
      top: .bottomOf(#email, margin: 8),
      child: DemoBox('+44 20 7946 0000'),
    ),
    // Both detail rows take the group's visibility, whatever their own.
    ConstraintGroup(
      id: #details,
      referenced: [#email, #phone],
      visibility: expanded ? .visible : .gone,
    ),
  ],
)
```

*With expanded set to false, the group makes both detail rows gone at once, so only the name shows. Set it to true and both rows come back.*

- **The group wins.** A referenced child takes the group's visibility for layout, painting, hit testing, and semantics, whatever its own `visibility` says. When several groups reference the same child, the one that comes last in `children` wins.
- **A group only sets visibility.** Like Android's `Group`, it is a child of the layout with a widget of its own, laid out at 0 x 0 at the layout's origin, but it never moves or sizes anything. No link can target it, and no barrier, flow, grid, or other group can reference it. It can reference `Constrained` children, flows, and grids; guidelines and barriers have no visibility, so it leaves them as they are.
- **Changing its `visibility` costs what changing the children's would.** Each referenced child is updated exactly as if its own `visibility` had changed.

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

*ConstraintFlow lays its referenced siblings out in a chain and wraps to new rows when it runs out of width, the constraint-based answer to Wrap.*

### Wrap modes

- **`.none`** (default): a single run that does not wrap (a plain chain).
- **`.chain`**: wraps into as many runs as it needs, filling each run before starting the next and laying each one out as its own chain, the closest match to `Wrap`.
- **`.aligned`**: wraps and also lines the runs up column-for-column, so the result reads as a grid.

Set `horizontalGap` and `verticalGap` for the spacing between items and runs, and `horizontalChainStyle` / `contentHorizontalBias` to control how each run distributes its slack, as a chain's style and bias do. `contentHorizontalBias` is always measured from the start, so it mirrors in right-to-left text.

## Grid

`ConstraintGrid` is to `GridView` what `ConstraintFlow` is to `Wrap`: it places its `referenced` children into a fixed grid of `rows` by `columns` cells, in order. Unlike `GridView` it does not scroll and does not become their parent; it is **virtual**, so the tiles stay siblings in the single layer that other constraints can still target.

Children fill the cells row by row from the start edge: left to right, or right to left in right-to-left text. Give a tile `width: .matchConstraint` and `height: .matchConstraint` to fill its cell, or leave it to wrap its own content and sit within the cell.

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

*ConstraintGrid places its referenced siblings into rows and columns. Spans use Android's index:RxC syntax, so cell 0 spans two columns.*

### Spans, skips, and weights

- **Spans** let one tile cover several cells: `spans: '0:1x2'` makes the tile at cell 0 span one row and two columns, using Android's `index:RxC` syntax. The entries are sorted by cell index and go to the tiles in order: the lowest index to the first tile, the next to the second. Entries beyond the last tile are ignored.
- **Skips** leave cells empty so the flow of tiles steps over them, with the same `index:RxC` syntax in `skips`.
- **Weights** (`rowWeights`, `columnWeights`) hand out the grid's space unevenly, so a column can take twice the width of its neighbor. A list shorter than the number of rows or columns is padded with weights of 1, and a longer one is trimmed.

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

*Avatar, name, and handle across the top; a barrier below the taller of them; the bio spans the full width beneath. One flat layer, no nesting.*

Each piece states its own relationships: the name fills the width up to the parent's end (`matchConstraint`), the handle sits under the name, and the bio starts below `#headerEnd` (the barrier), so it always clears both the avatar and the text no matter which is taller.

## How the engine works

ConstraintLayout does not position children by nesting boxes; it **solves** for each child's location and size from the constraints you declared. It does that with Android's own layout pipeline, ported line by line from `androidx.constraintlayout` to pure Dart.

### Android's pipeline

Each layout pass measures the layout the way Android's `ConstraintLayout` measures itself. Every child is measured as Android's view measurer measures a child view: laid out under the constraints of the measure spec Android would give it, with its size rounded up to whole pixels and its baseline read. In the first measure pass, the **`Direct`** pass places everything that follows directly from the links, such as a widget linked to edges already placed, a centered widget at its bias, a guideline, or a barrier once all of its widgets are placed. The **Cassowary solver** settles the rest, such as chains, aspect ratios, and percent sizes: a port of Android's `LinearSystem`, the algorithm family behind Apple's Auto Layout. Children whose size the solver decided are measured again at that size, and the layout is solved again when an answer changed.

Every float operation is the 32-bit one Android performs, in the same order, so values round where Android's do, and every child is placed at the integer frame Android computes.

### Optimization levels

Android's optimization flags are the layout's `optimizationLevel`. The default, `OptimizationLevel.standard`, is Android's default: the `Direct` pass and measure caching. `OptimizationLevel.none` leaves everything to the solver. The dependency-graph levels, `OptimizationLevel.graph` and `OptimizationLevel.graphWrap`, are an opt-in, as on Android, and run where Android runs the graph: in a layout without chains, flows, or grids that is bounded on both axes (with `graphWrap`, also when an axis wraps its content: the graph then resolves the bounded axes, and the solver runs too). At every level the layout gives Android's result at that level, apart from layouts Flutter and Android lay out a different number of times (see the README's limitations).

### Persistent model and replay

The engine model is built once and kept alive across frames, so a frame does only the work its changes need:

- **replay**: the configuration and the incoming constraints are those of the last layout, which repeated the one before it. Every child is asked again for the measures the last layout asked of it, and when every answer is the same, the children go back where they were without running the engine.
- **in-place**: a link, margin, bias, size, ratio, chain style, weight, or visibility changed, so the model is updated in place and measured again without a rebuild. New incoming constraints, and a child whose content changed size, also measure the existing model again.
- **rebuild**: the child set or a helper changed structurally, or the text direction changed, so the model is rebuilt from scratch.

Most real layouts are placed by `Direct`, and a measure of one takes microseconds. Chains and other simultaneous constraints are the solver's, and cost more as they grow, so for a large, chain-heavy screen, several small layouts are cheaper than one big one. The package README has the measured numbers.

## Relation to Android

The engine is a line-faithful port of `constraintlayout-core`, and of the part of Android's `ConstraintLayout` view that drives it, pinned to a specific upstream revision. It is checked against Android's own code at that revision, frame by frame: 60,000 real `ConstraintLayout` widget trees laid out by this package, and more than 1.8 million engine layouts (realistic screens, targeted edge cases, and adversarial ones), give the same frames as Android, with 0 differences, and on a sample of 2,000 layouts every operation of the solver matches Java's bit for bit. The package README has the details.

Right-to-left text follows Android's rules too: the horizontal bias of a child linked with start or end mirrors, so does the position of a vertical guideline, and a barrier's margin keeps its sign. `ConstraintGrid` mirrors as well, which Android's grid helpers leave unimplemented (see **Anchors & links**).

Parity holds for the same measure answers, in logical pixels. A Flutter `Text` does not measure like an Android `TextView`, so the layout rules match while the content sizes are Flutter's. Frames are whole logical pixels, which are Android's device pixels at a device pixel ratio of 1. And `ConstraintGrid`, which follows the core grid behind Compose rather than Android's view-based grid, has no Android result to compare with.
