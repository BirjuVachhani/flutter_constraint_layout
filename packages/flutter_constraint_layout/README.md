# flutter_constraint_layout

[![pub package](https://img.shields.io/pub/v/flutter_constraint_layout.svg)](https://pub.dev/packages/flutter_constraint_layout)
[![CI](https://github.com/BirjuVachhani/constraint_layout/actions/workflows/test.yml/badge.svg)](https://github.com/BirjuVachhani/constraint_layout/actions/workflows/test.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/BirjuVachhani/constraint_layout/blob/main/packages/flutter_constraint_layout/LICENSE)

Android's ConstraintLayout for Flutter. Instead of nesting `Row`, `Column`,
`Stack`, and `Padding`, put every child directly in one flat
`ConstraintLayout` and link its edges to the edges of the layout or of a
sibling. The engine then solves where everything goes and how big it is.
Chains, barriers, guidelines, aspect ratios, percent sizes, circular
positioning, flows, and grids are all included, in pure Dart, on every
platform Flutter supports.

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #avatar,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      child: const CircleAvatar(radius: 24),
    ),
    Constrained(
      id: #name,
      start: .endOf(#avatar, margin: 12), // just after the avatar
      top: .topOf(#avatar), // tops aligned
      child: const Text('Ada Lovelace'),
    ),
  ],
)
```

Every child gets an `id` (a `Symbol` such as `#avatar`) that its siblings use
to link to it, and `parent` is the layout itself. Read each link as "my edge,
at the target's edge": `start: .endOf(#avatar, margin: 12)` puts the name's
start edge 12 logical pixels past the avatar's end edge.

Full documentation with live examples:
**[constraints.birju.dev/docs](https://constraints.birju.dev/docs)**

## Contents

- [Why ConstraintLayout](#why-constraintlayout)
- [Features](#features)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Core concepts](#core-concepts)
- [Guides](#guides): [anchors and links](#anchors-and-links),
  [centering and bias](#centering-and-bias), [dimensions](#dimensions),
  [aspect ratio](#aspect-ratio), [chains](#chains), [guidelines](#guidelines),
  [barriers](#barriers), [circular positioning](#circular-positioning),
  [visibility](#visibility), [flow](#flow), [grid](#grid),
  [z-order](#z-order), [right-to-left](#right-to-left)
- [A complete example](#a-complete-example)
- [Sizing and scrolling](#sizing-and-scrolling)
- [Debug visualization](#debug-visualization)
- [Common mistakes](#common-mistakes)
- [Performance](#performance)
- [Limitations and differences from Android](#limitations-and-differences-from-android)
- [How it works](#how-it-works)

## Why ConstraintLayout

Flutter layouts are usually built by nesting: a `Padding` around a `Row` that
holds an avatar and a `Column` of texts, inside a `Stack` for the badge. Each
relationship costs a wrapper widget, and relationships between widgets in
different branches of that tree (line this value up with that label's
baseline, start below whichever of two widgets is taller, center this avatar on
that image's bottom edge) are hard to express at all.

`ConstraintLayout` keeps the tree flat. Every child sits directly in one list
and states its relationships as properties: which of its edges link to which
edges of the layout or of a sibling, how it is sized, and how it shares space
with its neighbors. In practice that means:

- **Shallower trees.** Spacing and alignment live on the link (`margin`), not
  in `Padding`, `SizedBox`, or `Align` wrappers.
- **Relationships across the whole layout.** Any child can align to any other
  child by id, wherever it is.
- **Constraints that nesting cannot state directly**, such as a barrier past
  the wider of two labels, a guideline that several widgets share, or a
  position on a circle around another widget.
- **Changes without restructuring.** Hide a child with `.gone` and its
  neighbors close the gap; change a link and the layout solves again.

If you know Android's ConstraintLayout, the concepts carry over: the engine is
a port of the same code.

## Features

- **[Links](#anchors-and-links)** from any edge (`start`, `end`, `left`,
  `right`, `top`, `bottom`, `baseline`) to the layout or a sibling, with
  `margin` and `goneMargin`. They do the work of `Padding`, `Positioned`, and
  most `Row` and `Column` nesting.
- **[Centering and bias](#centering-and-bias)** between two links, in place of
  `Center` and `Align`.
- **[Dimensions](#dimensions)**: fixed, wrap content, fill the space between
  two links (like `Expanded`), a percent of the layout (like
  `FractionallySizedBox`), bounded sizes, match parent, and
  [aspect ratio](#aspect-ratio).
- **[Chains](#chains)**: a row or column of linked widgets that share the
  space (spread, spread inside, or packed, with weights), like
  `mainAxisAlignment` and `Expanded` flex in a `Row`.
- **[Guidelines](#guidelines)** and **[barriers](#barriers)**: invisible lines
  to link to, at a fixed or percent position, or following the outermost edge
  of a group of widgets.
- **[Flow](#flow)** (wrapping rows, like `Wrap`) and **[grid](#grid)** (rows
  and columns with spans, skips, and weights). Both are virtual layouts: the
  widgets they arrange stay direct children that other links can target.
- **[Circular positioning](#circular-positioning)**,
  **[visibility](#visibility)** (`visible`, `invisible`, `gone`), and
  **[z-order](#z-order)** (`zIndex`).
- **[Right-to-left](#right-to-left)** layouts through `start` and `end`.
- **[Debug overlays](#debug-visualization)** that draw the constraint graph
  the way Android Studio's design surface does.
- **Pure Dart**: no platform code. The engine is a port of
  `androidx.constraintlayout.core`, published separately as
  [`constraint_engine`](https://pub.dev/packages/constraint_engine).

## Installation

Add the package with the Flutter CLI:

```sh
flutter pub add flutter_constraint_layout
```

or add it to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_constraint_layout: ^1.0.0
```

Then import it. This one import brings in every widget, link, dimension, and
helper:

```dart
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
```

**Requirements:** Dart 3.12 or later and Flutter 3.44 or later.

The API is designed around Dart's dot shorthands: `start: .startOf(parent)` is
short for `start: HorizontalLink.startOf(parent)`, and `width: .fixed(48)` for
`width: Dimension.fixed(48)`. Dot shorthands need language version 3.10 or
later, which comes from the lower bound of your own package's SDK constraint
(`sdk: ^3.12.0` qualifies). With an older lower bound, write the class names
out in full.

## Quick start

A complete app with a centered title, a subtitle aligned under it, and a button
in the bottom-end corner:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

void main() => runApp(const MaterialApp(home: Greeting()));

class Greeting extends StatelessWidget {
  const Greeting({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ConstraintLayout(
        children: [
          // 48 below the top of the layout, centered between its start and end.
          Constrained(
            id: #title,
            top: .topOf(parent, margin: 48),
            start: .startOf(parent),
            end: .endOf(parent),
            child: Text(
              'Hello, ConstraintLayout',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          // 8 below the title, with its start edge on the title's start edge.
          Constrained(
            id: #subtitle,
            top: .bottomOf(#title, margin: 8),
            start: .startOf(#title),
            child: const Text('Every edge is a link.'),
          ),
          // Pinned to the bottom-end corner.
          Constrained(
            id: #next,
            bottom: .bottomOf(parent, margin: 24),
            end: .endOf(parent, margin: 24),
            child: FilledButton(onPressed: () {}, child: const Text('Next')),
          ),
        ],
      ),
    );
  }
}
```

To see the links you just wrote, add `debugShowChains: true` to the
`ConstraintLayout` and hot reload: each link is drawn over the app (see
[debug visualization](#debug-visualization)). Another runnable app lives in
[`example/main.dart`](https://github.com/BirjuVachhani/constraint_layout/blob/main/packages/flutter_constraint_layout/example/main.dart).

## Core concepts

**Children and ids.** Wrap each child in `Constrained` and give it an `id`, a
`Symbol` such as `#avatar` that is unique within its layout. Links find their
targets by id, so the order of `children` does not affect positions; it only
sets the default paint order. A link can target a sibling declared later in the
list. Like `Positioned` in a `Stack`, `Constrained` must be a direct child of
its `ConstraintLayout` (a widget whose `build` returns a `Constrained` also
works). For ids generated in a loop, use `Symbol('item$i')`.

**Build each id the same way everywhere.** A child's id and every link or
`referenced` entry that names it must use the same form: the literal (such as
`#avatar`) everywhere, or `Symbol(...)` everywhere. Release and profile
WebAssembly builds (`flutter build web --wasm`), and builds compiled with
`--obfuscate`, rename symbol literals, so there `#item0` is not equal to
`Symbol('item0')`; a `const Symbol('item0')` is renamed like the literal. A
link or `referenced` entry that names a child in the other form targets an
unknown id, which those builds skip without an error (see
[unknown and duplicate ids](#unknown-and-duplicate-ids)). Debug builds treat
the forms as equal, so the mistake does not show up while you develop. For ids
built in a loop, a helper keeps every reference in the same form:

```dart
Symbol row(int i) => Symbol('row$i');

Widget rows(List<String> labels) {
  return ConstraintLayout(
    children: [
      for (final (i, label) in labels.indexed)
        Constrained(
          id: row(i),
          start: .startOf(parent, margin: 16),
          // The first row links to the layout, each later one to the row above.
          top: i == 0
              ? .topOf(parent, margin: 16)
              : .bottomOf(row(i - 1), margin: 8),
          child: Text(label),
        ),
    ],
  );
}
```

**The layout itself is `parent`.** The package exports a constant named
`parent` that targets the `ConstraintLayout`. It is reserved: do not use
`#parent` as a child id.

**Reading a link.** The parameter names *this* widget's edge, and the
constructor names the *target's* edge. Read each one as "my edge, at the
target's edge":

```dart
Constrained(
  id: #body,
  top: .bottomOf(#header, margin: 8), // my top edge, 8 below #header's bottom edge
  start: .startOf(parent, margin: 16), // my start edge, 16 in from the layout's start edge
  child: const Text('Body'),
)
```

**Margins** are the gap between the two edges, pushing this widget away from
its target. A negative margin pulls it past the target edge instead, which is
handy for overlaps. **`goneMargin`** replaces `margin` when the target is
`gone` (see [visibility](#visibility)).

**Links place a widget; `width` and `height` size it.** Linking both edges of
an axis does not stretch a widget the way `Positioned(left: 0, right: 0)` does
in a `Stack`. At the default size, `.wrapContent`, the widget keeps its own
size and centers between the two links. Set `width: .matchConstraint` (or
`height:`) to make it fill the space between them;
[dimensions](#dimensions) lists every option.

**An axis with no links.** A child with no horizontal link sits at the layout's
left edge, and one with no vertical link at its top edge.

**How big the layout is.** On an axis with a bounded maximum, such as the body
of a `Scaffold`, the layout takes the full size, even inside `Center`. On an
unbounded axis, such as the scrolling axis of a `ListView`, it is as big as its
content. [Sizing and scrolling](#sizing-and-scrolling) has the details.

## Guides

Every snippet in the guides is a `ConstraintLayout` that you can paste in place
of the `body:` of the quick start's `Scaffold`. Snippets that need data, such
as a list of tags or a flag from your state, are functions that take it; call
them from `body:`.

### Anchors and links

A link ties one of this widget's edges to an edge of a target: `parent` or a
sibling's id.

| Parameter | Positions this widget's | Link type | Constructors (the target's edge) |
| --- | --- | --- | --- |
| `start`, `end` | start or end edge, following the text direction | `HorizontalLink` | `.startOf`, `.endOf`, `.leftOf`, `.rightOf` |
| `left`, `right` | left or right edge, in either text direction | `HorizontalLink` | `.startOf`, `.endOf`, `.leftOf`, `.rightOf` |
| `top`, `bottom` | top or bottom edge | `VerticalLink` | `.topOf`, `.bottomOf` |
| `baseline` | text baseline | `VerticalLink` | `.baselineOf`, `.topOf`, `.bottomOf` |
| `circle` | center, on a circle around the target's center | `CircularLink` | `.around` (see [circular positioning](#circular-positioning)) |

Every link constructor except `.around` takes `margin` and `goneMargin`, both 0
by default. A `top` or `bottom` link to `.baselineOf` is ignored; align
baselines through the `baseline` parameter.

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #icon,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      child: const Icon(Icons.wifi, size: 32),
    ),
    Constrained(
      id: #label,
      start: .endOf(#icon, margin: 12), // just after the icon
      top: .topOf(#icon), // tops aligned
      child: const Text('Wi-Fi'),
    ),
    Constrained(
      id: #status,
      start: .startOf(#label), // start edges aligned
      top: .bottomOf(#label, margin: 4),
      child: const Text('Connected'),
    ),
    Constrained(
      id: #toggle,
      end: .endOf(parent, margin: 16),
      // Both vertical edges linked to the icon: centered on it.
      top: .topOf(#icon),
      bottom: .bottomOf(#icon),
      child: Switch(value: true, onChanged: (_) {}),
    ),
  ],
)
```

Baselines line up text of different sizes:

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #amount,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      child: const Text('42', style: TextStyle(fontSize: 48)),
    ),
    Constrained(
      id: #unit,
      start: .endOf(#amount, margin: 4),
      baseline: .baselineOf(#amount), // sits on the same baseline
      child: const Text('km', style: TextStyle(fontSize: 16)),
    ),
  ],
)
```

### Centering and bias

Link both edges of an axis and the widget centers between the two targets:
between the layout's edges, between two siblings (`start: .endOf(#a)` with
`end: .startOf(#b)` centers it in the gap), or on one sibling
(`start: .startOf(#a)` with `end: .endOf(#a)`). Linking both edges to the
*same* edge centers the widget on that edge, which is how you put an avatar on
the seam between a cover image and the content below it (see the
[complete example](#a-complete-example)).

`horizontalBias` and `verticalBias` slide the widget along the axis. A bias is
the share of the free space (the span between the links, less the widget's
size) that goes before the widget: 0 puts it against the left or top link, 1
against the right or bottom link, and the default 0.5 centers it. Because it is
a fraction, the position stays proportional as the layout resizes.

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #tag,
      start: .startOf(parent),
      end: .endOf(parent),
      top: .topOf(parent),
      bottom: .bottomOf(parent),
      horizontalBias: 0.25, // a quarter of the free width on its left
      verticalBias: 0.9, // near the bottom
      child: const Chip(label: Text('Biased')),
    ),
  ],
)
```

`horizontalBias` is measured from the left in both text directions; see
[right-to-left](#right-to-left).

### Dimensions

`width` and `height` each take a `Dimension`. Both default to `.wrapContent`.

| Dimension | Size on that axis |
| --- | --- |
| `.wrapContent` | The child's own size. It is not limited by the links: content larger than the space between them overflows it. |
| `.fixed(n)` | Exactly `n` logical pixels. |
| `.matchConstraint` | Fills the space between the two links on that axis, less their margins. With only one link, the child sizes to its content. |
| `.spread(min: a, max: b)` | Like `.matchConstraint`, kept between `min` and `max` (both optional). |
| `.constrainedWrap(min: a, max: b)` | The child's own size, but no larger than the space between its links, and kept between `min` and `max`. Suits content that does not reflow; see the note below. |
| `.percent(f, min: a, max: b)` | The fraction `f` (0 to 1) of the layout's size on that axis, kept between `min` and `max`. |
| `.matchParent` | The layout's full size on that axis. Where the links point is ignored, but their margins still inset it. |

```dart
ConstraintLayout(
  children: [
    // Fills the width between its links: the layout's width less 16 on each side.
    Constrained(
      id: #banner,
      start: .startOf(parent, margin: 16),
      end: .endOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      width: .matchConstraint,
      height: .fixed(56),
      child: const ColoredBox(color: Colors.indigo),
    ),
    // Half the layout's width, but never narrower than 200.
    Constrained(
      id: #panel,
      start: .startOf(parent),
      top: .bottomOf(#banner, margin: 16),
      width: .percent(0.5, min: 200),
      height: .fixed(120),
      child: const ColoredBox(color: Colors.teal),
    ),
    // As wide as its text, but never wider than the space beside the panel:
    // a long caption ends in an ellipsis instead of overflowing.
    Constrained(
      id: #caption,
      start: .endOf(#panel, margin: 16),
      end: .endOf(parent, margin: 16),
      top: .topOf(#panel),
      width: .constrainedWrap(),
      horizontalBias: 0,
      child: const Text(
        'A caption that is too long for the space beside the panel',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
)
```

> **Long text between two links.** A `Text` with the default `.wrapContent` is
> measured against the whole layout's width, so a long one grows past its links
> and overflows them. Give it `.matchConstraint` to fill the space between the
> links: it wraps inside them and its height follows. `.constrainedWrap()` caps
> the width in the same way but keeps the height measured before the cap, so use
> it for single-line text (with `maxLines: 1` and an ellipsis, as above), not for
> text that wraps.

### Aspect ratio

`aspectRatio` is width divided by height. It derives a `.matchConstraint` (or
`.spread`) dimension from the other one:

- If one dimension is `.matchConstraint`, it is computed from the other.
- If both are, the widget takes the largest size its links allow at that ratio.
- If neither is, the ratio is ignored.

```dart
ConstraintLayout(
  children: [
    // The width comes from the links; the height follows for 16:9.
    Constrained(
      id: #video,
      start: .startOf(parent),
      end: .endOf(parent),
      top: .topOf(parent),
      width: .matchConstraint,
      height: .matchConstraint,
      aspectRatio: 16 / 9,
      child: const ColoredBox(color: Colors.black),
    ),
  ],
)
```

### Chains

Widgets that link to each other in both directions form a chain: the first
member's `end` links to the second's `start`, the second's `start` links back
to the first's `end`, and so on. The two outer ends link to something outside
the chain, usually the layout. A chain distributes its members along the axis
as a group, like `mainAxisAlignment` in a `Row`.

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #home,
      start: .startOf(parent, margin: 24),
      end: .startOf(#search),
      bottom: .bottomOf(parent, margin: 16),
      horizontalChainStyle: .spreadInside, // set on the head
      child: const Icon(Icons.home),
    ),
    Constrained(
      id: #search,
      start: .endOf(#home),
      end: .startOf(#profile),
      bottom: .bottomOf(#home),
      child: const Icon(Icons.search),
    ),
    Constrained(
      id: #profile,
      start: .endOf(#search),
      end: .endOf(parent, margin: 24),
      bottom: .bottomOf(#home),
      child: const Icon(Icons.person),
    ),
  ],
)
```

The style is read from the chain's **head**, its first member in reading order:
the start-most member of a horizontal chain (the leftmost in left-to-right
text, the rightmost in right-to-left) and the top member of a vertical chain.
Set `horizontalChainStyle` or `verticalChainStyle` there; on other members it
is ignored.

- **`.spread`** (the default): equal gaps between the members and at both
  ends, like `MainAxisAlignment.spaceEvenly`.
- **`.spreadInside`**: the first and last members sit against the outer links,
  with equal gaps between the members, like `MainAxisAlignment.spaceBetween`.
- **`.packed`**: the members sit together, and the head's bias moves the group
  along the axis. The default 0.5 centers it, like `MainAxisAlignment.center`;
  0 or 1 puts it against the left or right link (the top or bottom link in a
  vertical chain).

Members sized `.matchConstraint` along the chain share the leftover space in
proportion to their `horizontalWeight` or `verticalWeight`, like `flex` on
`Expanded`:

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #cancel,
      start: .startOf(parent, margin: 16),
      end: .startOf(#confirm, margin: 8),
      top: .topOf(parent, margin: 16),
      width: .matchConstraint,
      horizontalWeight: 1, // one third of the space
      child: OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
    ),
    Constrained(
      id: #confirm,
      start: .endOf(#cancel),
      end: .endOf(parent, margin: 16),
      top: .topOf(#cancel),
      width: .matchConstraint,
      horizontalWeight: 2, // two thirds
      child: FilledButton(onPressed: () {}, child: const Text('Confirm')),
    ),
  ],
)
```

### Guidelines

A `Guideline` is an invisible line that siblings link to. Place it with exactly
one of `begin` (distance from the left or top), `end` (distance from the right
or bottom), or `percent` (a fraction of the layout's width or height, from the
left or top). `Guideline.vertical` is a vertical line, for siblings'
horizontal edges; `Guideline.horizontal` is a horizontal line, for their
vertical edges. Everything linked to a guideline moves when it moves.

```dart
ConstraintLayout(
  children: [
    // A vertical line at 30% of the layout's width.
    Guideline.vertical(id: #split, percent: 0.3),
    Constrained(
      id: #sidebar,
      start: .startOf(parent),
      end: .startOf(#split),
      top: .topOf(parent),
      bottom: .bottomOf(parent),
      width: .matchConstraint,
      height: .matchConstraint,
      child: const ColoredBox(color: Color(0xFFE0E0E0)),
    ),
    Constrained(
      id: #detail,
      start: .endOf(#split, margin: 24),
      end: .endOf(parent, margin: 24),
      top: .topOf(parent, margin: 24),
      width: .matchConstraint,
      child: const Text('Everything linked to #split moves with it.'),
    ),
  ],
)
```

Guideline positions are absolute: they do not mirror in right-to-left layouts.

### Barriers

A `Barrier` is an invisible line that follows the outermost edge of the widgets
in `referenced`: the end-most `end` edge, the lowest `bottom` edge, and so on.
Link to it to clear the widest or tallest of a group, whichever one that turns
out to be.

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #from,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      child: const Text('From'),
    ),
    Constrained(
      id: #subject,
      start: .startOf(parent, margin: 16),
      top: .bottomOf(#from, margin: 12),
      child: const Text('Subject'),
    ),
    // Follows the end edge of whichever label is wider.
    const Barrier(id: #labels, edge: .end, referenced: [#from, #subject]),
    Constrained(
      id: #fromValue,
      start: .endOf(#labels, margin: 12), // 12 past the wider label
      end: .endOf(parent, margin: 16),
      baseline: .baselineOf(#from),
      width: .matchConstraint,
      child: const Text('ada@example.com'),
    ),
    Constrained(
      id: #subjectValue,
      start: .endOf(#labels, margin: 12),
      end: .endOf(parent, margin: 16),
      baseline: .baselineOf(#subject),
      width: .matchConstraint,
      child: const Text('Notes on the Analytical Engine'),
    ),
  ],
)
```

`edge` is one of `.start`, `.end`, `.left`, `.right`, `.top`, or `.bottom`
(`start` and `end` follow the text direction). A `gone` widget still counts, at
the point it collapsed to, unless you set `allowsGone: false`.

To keep a gap from a barrier, put the margin on the links that target it, as
above: that works on every edge and in both text directions. The barrier's own
`margin` (0 by default) is added to its position, so a positive value always
moves it right or down: further out for a barrier on right or bottom edges, but
back over its widgets for one on left or top edges. `.start` in left-to-right
text and `.end` in right-to-left text track left edges, so they are in the
second group.

### Circular positioning

`circle: .around(target, angle: a, radius: r)` centers the widget on a circle
around the target's center. `angle` is in degrees, clockwise, with 0 pointing
straight up and 90 to the right; `radius` is the distance between the two
centers in logical pixels. The circle link positions the widget on its own; it
needs no other links.

```dart
ConstraintLayout(
  children: [
    Constrained(
      id: #avatar,
      start: .startOf(parent, margin: 24),
      top: .topOf(parent, margin: 24),
      child: const CircleAvatar(radius: 32, child: Text('AL')),
    ),
    // A status dot at the avatar's bottom-right, on its rim.
    Constrained(
      id: #online,
      circle: .around(#avatar, angle: 135, radius: 26),
      width: .fixed(14),
      height: .fixed(14),
      child: const DecoratedBox(
        decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
      ),
    ),
  ],
)
```

The same link in a loop lays out dials, clock faces, and radial menus:
`circle: .around(#hub, angle: i * 45, radius: 96)`.

### Visibility

Every `Constrained` child (and every flow and grid) has a `visibility`,
matching Android's three states:

- **`.visible`** (the default): laid out and painted.
- **`.invisible`**: laid out at its normal size and position, so siblings
  link to it as usual, but not painted and not hit-testable.
- **`.gone`**: collapses to a zero-size point where its links put it (its own
  margins are dropped). It is not painted or hit-testable, and links that target
  it switch from `margin` to their `goneMargin`.

`goneMargin` takes over only when it is non-zero. With the default of 0, a link
to a gone widget keeps its regular margin.

```dart
Widget nameRow({required bool showAvatar}) {
  return ConstraintLayout(
    children: [
      Constrained(
        id: #avatar,
        start: .startOf(parent, margin: 16),
        top: .topOf(parent, margin: 16),
        visibility: showAvatar ? .visible : .gone,
        child: const CircleAvatar(radius: 20),
      ),
      Constrained(
        id: #name,
        // 12 after the avatar. When the avatar is gone it collapses at the
        // layout's start edge, and goneMargin keeps the name 16 in from it.
        start: .endOf(#avatar, margin: 12, goneMargin: 16),
        top: .topOf(parent, margin: 16),
        child: const Text('Ada Lovelace'),
      ),
    ],
  );
}
```

Because `visibility` is a property, a hidden child stays mounted and keeps its
state, unlike a child removed with `if`.

### Flow

`ConstraintFlow` lays a list of siblings out in a row (or a column) and, with
`wrap` set, wraps them onto new rows when they run out of space, like `Wrap`.
It is a *virtual* layout: the widgets it arranges stay direct children of the
`ConstraintLayout`, listed by id in `referenced`, so other constraints can still
target them. They need no links of their own. The flow itself is positioned and
sized like a `Constrained` child, with links, `width` and `height` (default
`.wrapContent`), bias, and `visibility`.

```dart
Widget tagCloud(List<String> tags) {
  return ConstraintLayout(
    children: [
      for (final (i, tag) in tags.indexed)
        Constrained(id: Symbol('tag$i'), child: Chip(label: Text(tag))),
      ConstraintFlow(
        id: #tags,
        referenced: [for (var i = 0; i < tags.length; i++) Symbol('tag$i')],
        start: .startOf(parent, margin: 16),
        end: .endOf(parent, margin: 16),
        top: .topOf(parent, margin: 16),
        width: .matchConstraint,
        wrap: .chain,
        horizontalGap: 8,
        verticalGap: 8,
        horizontalChainStyle: .packed,
        contentHorizontalBias: 0, // pack each row against the start edge
      ),
    ],
  );
}
```

| Parameter | Default | Effect |
| --- | --- | --- |
| `orientation` | `Axis.horizontal` | The axis the widgets are laid out along. |
| `wrap` | `.none` | `.none` keeps one line even if it overflows; `.chain` wraps into rows that are each laid out as their own chain; `.aligned` wraps and also lines the widgets up in columns, like a grid. |
| `horizontalGap`, `verticalGap` | 0 | Horizontal and vertical space between neighbors. In a horizontal flow, `horizontalGap` separates the widgets in a row and `verticalGap` separates the rows. |
| `horizontalChainStyle`, `verticalChainStyle` | spread | Style of the chains the flow creates (see [chains](#chains)). |
| `contentHorizontalBias`, `contentVerticalBias` | 0.5 | Bias of those chains, which moves a packed row along its axis. |
| `verticalAlign` | `.center` | How widgets line up within a row: `.top`, `.bottom`, `.center`, or `.baseline`. |
| `horizontalAlign` | `.center` | How widgets line up within a column: `.start`, `.end`, or `.center`. |
| `maxElementsWrap` | `null` | The most widgets per row before wrapping; `null` fits as many as possible. |
| `padding` | 0 | Space inside the flow's bounds, on all four sides. |

### Grid

`ConstraintGrid` places the widgets in `referenced` into a grid of `rows` by
`columns` cells, filling it row by row (or column by column with
`orientation: Axis.vertical`). Like a flow it is virtual, so the tiles stay
siblings that other constraints can target. Give a tile `.matchConstraint` on
both axes to fill its cell; otherwise it keeps its own size, centered in the
cell. The grid's own `width` and `height` default to `.matchConstraint`, so link
both sides of each axis, or give it a size.

```dart
ConstraintLayout(
  children: [
    for (var i = 0; i < 5; i++)
      Constrained(
        id: Symbol('tile$i'),
        width: .matchConstraint, // fill the cell
        height: .matchConstraint,
        child: ColoredBox(color: Colors.primaries[i]),
      ),
    ConstraintGrid(
      id: #grid,
      referenced: [for (var i = 0; i < 5; i++) Symbol('tile$i')],
      rows: 2,
      columns: 3,
      spans: '0:1x2', // the first tile covers 1 row and 2 columns
      horizontalGap: 8,
      verticalGap: 8,
      start: .startOf(parent, margin: 16),
      end: .endOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      bottom: .bottomOf(parent, margin: 16),
    ),
  ],
)
```

- **`rows` and `columns`.** Leave one out to derive it from the other and the
  number of widgets, or both to derive both from the number of widgets.
- **`spans`** uses Android's `index:RxC` syntax, comma-separated: `R` rows by
  `C` columns, starting at cell `index` (cells are numbered from 0 in fill
  order, so row by row unless `orientation` is vertical). The entries apply to
  the referenced widgets *in order*: the first entry places the first widget,
  the second entry the second widget, and the remaining widgets fill the free
  cells. So `'0:2x1, 4:1x2'` gives the first widget cell 0 and the one below
  it, and the second widget cells 4 and 5. In a grid with a single row or
  column, write `index:N` instead (`N` cells); the grid adds the extra cells the
  span needs.
- **`skips`** uses the same syntax to leave cells empty: `'1:1x2'` skips cells
  1 and 2.
- **`rowWeights` and `columnWeights`** share the space unevenly, one entry per
  row or column: `columnWeights: [2, 1, 1]` makes the first column twice as
  wide as each of the others. A list with any other number of entries is
  ignored, and the rows or columns stay equal.

### Z-order

Children paint in list order, so later children paint on top. `zIndex`
overrides that order: a child's z value is its `zIndex` when set and its index
in `children` otherwise, higher values paint on top, and ties keep list order.
That makes `zIndex: 1` on the first child no higher than the second child
(whose index is 1), so use a value above the other children's indices, or give
every overlapping child a `zIndex`. Hit testing follows the same order, and
changing `zIndex` repaints without a new layout.

```dart
ConstraintLayout(
  children: [
    // Declared first but painted last: 10 is above every index in the list.
    Constrained(
      id: #badge,
      top: .topOf(#card, margin: -10), // negative margins: overhang the corner
      end: .endOf(#card, margin: -10),
      zIndex: 10,
      child: const CircleAvatar(radius: 12, child: Text('3')),
    ),
    Constrained(
      id: #card,
      start: .startOf(parent, margin: 24),
      top: .topOf(parent, margin: 24),
      width: .fixed(160),
      height: .fixed(100),
      child: const ColoredBox(color: Colors.amber),
    ),
  ],
)
```

### Right-to-left

`start` and `end` follow the text direction: the `textDirection` you pass to
`ConstraintLayout`, otherwise the ambient `Directionality`, otherwise left to
right. That covers link parameters (`start:`, `end:`), link targets
(`.startOf`, `.endOf`), and barrier edges (`.start`, `.end`). `left` and `right`
never flip. A layout written with `start` and `end` mirrors in right-to-left
locales:

```dart
ConstraintLayout(
  textDirection: TextDirection.rtl, // or leave it out to use Directionality
  children: [
    Constrained(
      id: #back,
      start: .startOf(parent, margin: 16), // the right edge in RTL
      top: .topOf(parent, margin: 16),
      child: const Icon(Icons.arrow_back),
    ),
    Constrained(
      id: #title,
      start: .endOf(#back, margin: 16), // to the left of the icon in RTL
      top: .topOf(#back),
      child: const Text('Settings'),
    ),
  ],
)
```

Some things do not mirror:

- `horizontalBias` is always measured from the left (0 is the left end, 1 the
  right end), including the bias of a packed chain.
- Guidelines are always placed from the left (`begin`, `percent`) or the right
  (`end`).
- A barrier's `margin` always moves it right or down (see
  [barriers](#barriers)).
- `ConstraintGrid` fills its cells from the left in both directions (upstream's
  grid does not handle right-to-left either).

For a mirrored layout, choose bias and guideline values from the text
direction, for example `horizontalBias: isRtl ? 0.8 : 0.2`. `ConstraintFlow`
does mirror: in right-to-left text its rows start at the right edge, and
`contentHorizontalBias` is measured from the start. A chain's head is its
start-most member in either direction.

## A complete example

A complete app: a profile card in a `ListView`, with a ratio-sized cover, an
avatar centered on the cover's bottom edge, a name that fills the space up to
the button, and a barrier so the bio always starts below the lowest of the
header pieces. The card is one flat layer: no `Row`, `Column`, or `Stack`.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

void main() {
  runApp(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [ProfileCard()],
        ),
      ),
    ),
  );
}

class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ConstraintLayout(
        children: [
          // Full width, with a 3:1 height.
          Constrained(
            id: #cover,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            width: .matchConstraint,
            height: .matchConstraint,
            aspectRatio: 3,
            child: const ColoredBox(color: Colors.indigo),
          ),
          // Both vertical links target the cover's bottom edge, so the
          // avatar is centered on it.
          Constrained(
            id: #avatar,
            start: .startOf(parent, margin: 16),
            top: .bottomOf(#cover),
            bottom: .bottomOf(#cover),
            child: const CircleAvatar(radius: 36, child: Text('AL')),
          ),
          Constrained(
            id: #follow,
            end: .endOf(parent, margin: 16),
            top: .bottomOf(#cover, margin: 12),
            child: FilledButton(onPressed: () {}, child: const Text('Follow')),
          ),
          // Fills the space from the avatar's start edge to the button.
          Constrained(
            id: #name,
            start: .startOf(#avatar),
            end: .startOf(#follow, margin: 12),
            top: .bottomOf(#avatar, margin: 8),
            width: .matchConstraint,
            child: Text('Ada Lovelace', style: textTheme.titleLarge),
          ),
          Constrained(
            id: #handle,
            start: .startOf(#name),
            top: .bottomOf(#name),
            child: Text('@ada', style: textTheme.bodyMedium),
          ),
          // Below whichever is lower: the handle or the button.
          const Barrier(id: #header, edge: .bottom, referenced: [#handle, #follow]),
          Constrained(
            id: #bio,
            start: .startOf(parent, margin: 16),
            end: .endOf(parent, margin: 16),
            top: .bottomOf(#header, margin: 12),
            bottom: .bottomOf(parent, margin: 16),
            width: .matchConstraint,
            child: const Text(
              'Mathematician and writer. Published the first algorithm '
              'intended to be carried out by a machine.',
            ),
          ),
        ],
      ),
    );
  }
}
```

The `ListView` gives the card an unbounded height, so the card is as tall as
its content. The next section explains why.

## Sizing and scrolling

How big the `ConstraintLayout` itself is depends on the constraints it gets on
each axis:

- **On a bounded axis it takes the maximum size**, even when the constraints
  are loose. Inside `Center` or `Align` it still fills the available space; it
  does not shrink to its children.
- **On an unbounded axis it sizes to its children**: it ends at the furthest
  child edge, plus the margin of any link to the layout's far edge.
- **With no children** it takes the smallest size its constraints allow.

So in a vertical `ListView`, a `SingleChildScrollView`, or a `Column` it is as
wide as it is allowed to be and as tall as its content, which makes it a good
fit for list items. In a `Row` or a horizontal list it is as wide as its
content and as tall as it is allowed to be. Wrap it in an `UnconstrainedBox` to
size it to its content on both axes, or in a `SizedBox` to give it an exact
size.

On an axis where it sizes to its content, a `.matchConstraint` size linked to
*both* of the layout's own edges on that axis (for example `top: .topOf(parent)`
and `bottom: .bottomOf(parent)` inside a scroll view) adds nothing to the
layout's size. It stretches to whatever size the other children give the
layout, which suits a full-height divider or background in a list item, and it
resolves to 0 when no other child gives the layout a size. To size a child to
its own content there, use `.wrapContent` or a fixed size.

`ConstraintLayout` does not implement intrinsic sizing, dry layout, or a
baseline of its own:

- **Intrinsic size queries return 0.** Inside `IntrinsicHeight` or
  `IntrinsicWidth` the layout collapses to zero height or width, and widgets
  that size their children from intrinsic dimensions (the content of
  `AlertDialog` and `SimpleDialog`, popup menus, and `IntrinsicColumnWidth`
  table columns) get 0 from it; a dialog around it stays at its minimum width.
  Give it an explicit size, for example with a `SizedBox`, in those places.
- **Dry layout is not supported.** If an ancestor asks for the layout's dry
  size, debug builds throw a `FlutterError` whose message begins
  `The RenderConstraintLayout class does not implement "computeDryLayout".`,
  and release builds get `Size.zero`.
- **It reports no baseline**, so it cannot take part in an ancestor's baseline
  alignment, such as a `Row` with `CrossAxisAlignment.baseline`.

## Debug visualization

Two flags on `ConstraintLayout` draw the constraint graph the engine is solving,
replicating Android Studio's design surface:

```dart
ConstraintLayout(
  debugShowChains: true, // draw the overlay on top of the children
  debugChainColor: Colors.pink, // optional: tint the overlay
  children: [
    Constrained(
      id: #title,
      start: .startOf(parent, margin: 16),
      end: .endOf(parent, margin: 16),
      top: .topOf(parent, margin: 24),
      horizontalBias: 0.3,
      child: const Text('Constraints, visualized'),
    ),
  ],
)
```

- **`debugShowChains`** paints the overlay over the normally painted children:
  constraint connections as curved arrows, opposing constraints as zigzag
  springs (the longer leg of a biased pair is dashed), chains as interlocking
  chain links, margin values with end ticks, plus guidelines, barriers, and the
  frames of flows and grids.
- **`debugShowBlueprint`** does not paint the children at all. Instead it draws
  Android Studio's blueprint surface: a dark teal background with a translucent
  framed box and a label per child, and the same constraint drawing. Children
  are still laid out and hit-testable. When both flags are set, the blueprint
  wins.
- **`debugChainColor`** tints every overlay line (constraints, chains, springs,
  guidelines, barriers, frames); anchors and labels derive shades from it. When
  it is `null`, the overlay uses Android Studio's palette.
- **`debugBlueprintLabelStyle`** picks the text inside each blueprint box:

  | Value | Draws |
  | --- | --- |
  | `DebugLabelStyle.id` | the child's id, for example `avatar` |
  | `DebugLabelStyle.label` | the child widget's runtime type, for example `Text` |
  | `DebugLabelStyle.both` | the id with the runtime type below it (the default) |
  | `DebugLabelStyle.none` | no text |

  The labels are reliable in debug builds. Profile and release builds do not
  record which widget created each child, so the type label falls back to the
  type of the child's render object, without its `Render` prefix (`Paragraph`
  for a `Text`). Release web builds, WebAssembly builds in profile or release
  mode, and builds compiled with `--obfuscate` minify that name as well, and
  the WebAssembly and `--obfuscate` builds also rename ids written as symbol
  literals (ids built at run time with `Symbol(...)` keep their names).

When a widget is not where you expect it, turn on `debugShowChains` and compare
the drawing with your links:

- Every link is drawn as a line from the edge it positions to its target edge.
  A widget with nothing drawn from either edge of an axis has no link on that
  axis, which is why it sits at the layout's left or top edge.
- The members of a chain are joined by chain links. Arrows or springs between
  them instead mean that a link back is missing, so no chain formed.
- Blueprint mode frames each child at its solved position and size, which
  shows where a child really ends, such as a `.wrapContent` `Text` that is
  wider than the space between its links.

By default the overlays render only in debug builds: both flags are honored when
`kDebugMode` is true and do nothing in profile and release builds. To force them
on outside debug mode (for a hosted showcase, a screenshot build, or a release
diagnostic), set the global switch before the layout paints, for example in
`main`:

```dart
ConstraintLayout.allowDebugFlags = true; // defaults to kDebugMode
```

Enabling it keeps the overlay's rendering code in the release binary, so leave
it at the default unless you need the overlays there. Outside debug builds the
blueprint labels can be unreadable (see `debugBlueprintLabelStyle` above), so
for a showcase or screenshots consider
`debugBlueprintLabelStyle: DebugLabelStyle.none`. The real-world examples
on the home page of [constraints.birju.dev](https://constraints.birju.dev) have
chains and blueprint toggles, so you can see both modes without running
anything. The design notes for the overlay are in
[docs/DEBUG_VISUALIZATION.md](https://github.com/BirjuVachhani/constraint_layout/blob/main/docs/DEBUG_VISUALIZATION.md).

## Common mistakes

When a widget is not where you expect it, turn on the
[debug overlay](#debug-visualization) to see the links the engine is solving,
then look for the symptom here.

| Symptom | Cause | Fix |
| --- | --- | --- |
| A child sits at the layout's left or top edge. | It has no link on that axis, or it is not wrapped in `Constrained`. | Link it on that axis, inside a `Constrained`. |
| A child linked on both sides of an axis does not stretch. | Links only position it; at the default `.wrapContent` size it centers between them. | Set `width: .matchConstraint` (or `height:`). |
| A `.matchConstraint` child is only as big as its content. | It is linked on only one side of that axis. | Link both sides. |
| Long text overlaps its neighbors or runs off the layout. | A `.wrapContent` `Text` is measured against the layout's full width. | Set `width: .matchConstraint`. |
| `Incorrect use of ParentDataWidget.` | Another widget, such as `Padding`, sits between the `ConstraintLayout` and the `Constrained`. | Move it inside: `Constrained(child: Padding(...))`. |
| `Constrained link targets unknown id ...` | A typo, or an id from another `ConstraintLayout`: ids are scoped to one layout. | Fix the id; see [unknown and duplicate ids](#unknown-and-duplicate-ids). |
| A widget lines up with the wrong sibling. | Two children share an id. | Rename one; see [unknown and duplicate ids](#unknown-and-duplicate-ids). |
| A chain style has no effect. | It is set on a member other than the chain's head. | Set it on the start-most (or top) member. |
| The layout fills the screen instead of fitting its children. | On a bounded axis it takes the maximum size, even inside `Center`. | Wrap it in `UnconstrainedBox`, or size it with `SizedBox`. |
| A dialog stays at its minimum width around the layout, or the layout gets zero height or width inside `IntrinsicHeight` or `IntrinsicWidth`. | The layout reports 0 for intrinsic sizes, which those widgets use to size their content. | Size it with `SizedBox`. |

### Unknown and duplicate ids

Ids are plain symbols, so a typo compiles. Here is what happens when one slips
through.

**A link or reference to an id that no sibling defines.** In debug builds the
layout throws a `FlutterError` that names the id:

```text
Constrained link targets unknown id Symbol("titel"). Targets must be `parent` or the id of a sibling Constrained in the same ConstraintLayout.
```

`circle` links, `Barrier`, `ConstraintFlow`, and `ConstraintGrid` report
unknown ids the same way. The layout pass is abandoned, so the other children
are not positioned until the id is fixed. In profile and release builds the
check is compiled out: the bad link or reference is skipped (a skipped link
leaves its edge unconstrained), and the rest of the layout resolves. In profile
and release WebAssembly builds and in `--obfuscate` builds, a link that writes
an id in a different form from the child's id (`#item0` for `Symbol('item0')`)
is skipped the same way; see [core concepts](#core-concepts).

**Two children with the same id.** This is not reported at runtime: links to
that id resolve to the last child that uses it.

The companion analyzer plugin,
[`flutter_constraint_layout_lints`](https://pub.dev/packages/flutter_constraint_layout_lints),
flags both mistakes as you type, with the warnings `undefined_constraint_id` and
`duplicate_constraint_id`. Enable it in the `analysis_options.yaml` at the root
of your package, then restart the Dart analysis server:

```yaml
plugins:
  flutter_constraint_layout_lints: ^1.0.0
```

The warnings appear in your IDE and in `dart analyze`, which exits with a
non-zero status when it reports them, so it can enforce them in CI.
`flutter analyze` does not report them. See the plugin's page for its options
and for what static analysis can and cannot see.

## Performance

Each `ConstraintLayout` solves its children with one of two strategies (see
[how it works](#how-it-works)). The **dependency graph** resolves each position
and size once, in dependency order, and handles most layouts. Some layouts are
genuine systems of simultaneous constraints, and those fall back to the
**Cassowary solver**, which costs far more. The whole layout falls back to the
solver when it contains any of:

- a `Barrier`, a `ConstraintFlow`, or a `ConstraintGrid`,
- a `circle` link or a `.constrainedWrap()` size,
- `aspectRatio` on a child whose width and height are both `.matchConstraint`,
- a chain with a `gone` member or a member sized by `aspectRatio`,
- on an axis where the layout sizes to its content (such as the scrolling axis
  of a list): a chain along that axis, a child linked on both sides of that
  axis, or a child that extends outside the layout,
- anything else the graph cannot resolve directly.

Guidelines, baselines, bias, percent and bounded sizes, weighted and packed
chains, and `invisible` or `gone` children outside chains all stay on the
graph.

The engine's benchmark
([`resolver_benchmark.dart`](https://github.com/BirjuVachhani/constraint_layout/blob/main/packages/constraint_engine/benchmark/resolver_benchmark.dart))
shows the difference. Compiled ahead of time and run on an Apple M4, a
synthetic layout of 1,200 fixed-size widgets (50 rows, each a 24-widget chain)
re-resolved on the graph path in a median of about 0.4 ms, and was built and
resolved from scratch in about 1 ms. The same layout with one aspect-ratio
member per row, which routes it to the solver, took roughly 75 to 90 ms per
pass; a 48-widget version of it took about 2 ms. Absolute numbers depend on the
hardware and vary from run to run; the ratio between the two paths is what to
plan around. The solver's cost grows faster than the widget count, and each
`ConstraintLayout` is solved on its own, so when a screen needs the solver,
several small layouts (such as one per list item) are cheaper than one large
one.

The engine model also persists between frames and is invalidated in tiers, so a
frame does no more work than its changes require:

- **Fast:** nothing that affects layout changed, the incoming constraints are
  the same, and no child's size or position can depend on its content (no
  `.wrapContent` or `.constrainedWrap()` sizes, no match-constraint size that
  lacks one of its two links, and no baseline alignment). The engine is skipped
  and the previous geometry is reused.
- **In place:** a `Constrained` property changed (a link, margin, bias, size,
  ratio, chain style, weight, or visibility). The affected widgets are updated
  in the existing model, which is then solved again. New incoming constraints,
  or a child whose content changed size, also re-solve the existing model
  without rebuilding it.
- **Rebuild:** children were added, removed, or reordered, an id changed, the
  text direction changed, or a property of a `Guideline`, `Barrier`,
  `ConstraintFlow`, or `ConstraintGrid` changed. The model is rebuilt from
  scratch.

Changing `zIndex` or a debug flag only repaints.

## Limitations and differences from Android

- **No intrinsic sizing, dry layout, or baseline** on the layout itself; see
  [sizing and scrolling](#sizing-and-scrolling).
- **Whole logical pixels.** Like Android's engine, which works in integer
  pixels, the engine computes positions and sizes in whole logical pixels:
  fixed sizes, margins, and gaps are rounded to the nearest integer, and
  children are placed at whole-pixel offsets. An edge can therefore land up to
  a logical pixel away from where fractional arithmetic would put it.
- **`.constrainedWrap()` does not re-measure height.** When it caps a child's
  width, the child keeps the height it measured at its natural width, so text
  that wraps at the capped width can be clipped. Use `.matchConstraint` or
  `.spread(max: ...)` for text that wraps; both measure the height at the final
  width.
- **A `goneMargin` of 0 means "not set".** When the target is gone, the
  regular `margin` stays in effect; you cannot replace it with exactly 0.
- **Right-to-left.** Android mirrors the horizontal bias of views constrained
  with start and end, and (by default) the position of vertical guidelines. Here
  neither mirrors; see [right-to-left](#right-to-left).
- **Id mistakes.** Unknown ids throw in debug builds and are skipped in release
  builds; duplicate ids are not reported. See
  [unknown and duplicate ids](#unknown-and-duplicate-ids).
- **Flow and Grid options.** `ConstraintFlow` takes one `padding` for all four
  sides and has no first-row or last-row chain styles or biases.
  `ConstraintGrid` does not expose Android's grid flags.
- **No built-in transitions.** A changed link or size takes effect at the next
  layout, without animation. To animate one, drive the value (a `margin`, a
  bias, or a `.fixed` size) from an `Animation` and rebuild; each frame then
  updates the engine model in place.
- **Not ported, by design:**
  - **MotionLayout.** Animation is a different feature in Flutter; a
    constraint-animation story would be Flutter-idiomatic, not a port.
  - **JSON constraint sets** (upstream's `parser/`, `dsl/`, and `state/`). The
    widget API replaces them.
  - **`Placeholder`.** It is niche; use conditional ids instead.
  - **The `Direct` and `Grouping` optimizers.** They are performance shortcuts
    in front of upstream's solver; here the dependency graph plays that role.
- **No view-layer helpers** such as Android's `Group`, `Layer`, or
  `ConstraintSet`. In Flutter, set each child's `visibility` from your state,
  and rebuild with different properties instead of applying a constraint set.

## How it works

`ConstraintLayout` maps each child to a widget in
[`constraint_engine`](https://pub.dev/packages/constraint_engine), a pure-Dart,
line-faithful port of `androidx.constraintlayout.core`. The port is pinned to
upstream commit `9cd4b5a4079a14175f91dc897abd83270799364a`, its solver and
widget classes are verified at parity with the released core 1.1.1 (only the
Grid helper still follows the pinned commit), and nearly all of upstream's core
tests are ported and passing;
[UPSTREAM.md](https://github.com/BirjuVachhani/constraint_layout/blob/main/packages/constraint_engine/UPSTREAM.md)
records the pin, the parity check, and every intentional divergence. During
layout the engine measures children through Flutter's own `RenderBox.layout`,
solves the constraints, and the layout places each child at the resolved
position and size.

The engine has two strategies, both ported from upstream. The dependency graph
models each edge and dimension as a node and resolves them in dependency order,
with no iteration and no search, so its cost grows close to linearly with the
widget count. The fallback is upstream's `LinearSystem`, an implementation of
the Cassowary linear-arithmetic constraint algorithm (the family behind Apple's
Auto Layout): it expresses the layout as weighted equations and inequalities
and minimizes the error with an incremental simplex method. Android runs the
solver by default with the graph as an optional optimization; this port tries
the graph first and falls back to the solver only for the layouts the graph
cannot resolve faithfully (listed under [performance](#performance)), so both
paths produce the same result Android does.

## Links

- Documentation: [constraints.birju.dev/docs](https://constraints.birju.dev/docs)
- Repository: [github.com/BirjuVachhani/constraint_layout](https://github.com/BirjuVachhani/constraint_layout)
- Issue tracker: [github.com/BirjuVachhani/constraint_layout/issues](https://github.com/BirjuVachhani/constraint_layout/issues)
- Changelog: [CHANGELOG.md](https://github.com/BirjuVachhani/constraint_layout/blob/main/packages/flutter_constraint_layout/CHANGELOG.md)

## License

BSD 3-Clause. See
[LICENSE](https://github.com/BirjuVachhani/constraint_layout/blob/main/packages/flutter_constraint_layout/LICENSE).
The debug visualization adapts the rendering of Android Studio's layout editor:
`lib/src/debug/debug_painter.dart` and `lib/src/debug/debug_palette.dart` keep
the Android Open Source Project's copyright line and are also covered by the
Apache License 2.0, whose notice is included in the same LICENSE file.
