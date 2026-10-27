# flutter_constraint_layout

[![pub package](https://img.shields.io/pub/v/flutter_constraint_layout.svg)](https://pub.dev/packages/flutter_constraint_layout)
[![CI](https://github.com/BirjuVachhani/flutter_constraint_layout/actions/workflows/test.yml/badge.svg)](https://github.com/BirjuVachhani/flutter_constraint_layout/actions/workflows/test.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/flutter_constraint_layout/LICENSE)

Android's ConstraintLayout for Flutter. Instead of nesting `Row`, `Column`,
`Stack`, and `Padding`, put every child directly in one flat
`ConstraintLayout` and link its edges to the edges of the layout or of a
sibling. The engine then solves where everything goes and how big it is,
with Android's own layout code ported to Dart, so a layout lands on the
pixels Android gives it. Chains, barriers, guidelines, aspect ratios,
percent sizes, circular positioning, flows, and grids are all included, in
pure Dart, on every platform Flutter supports.

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
  [visibility](#visibility), [groups](#groups), [flow](#flow), [grid](#grid),
  [z-order](#z-order), [right-to-left](#right-to-left)
- [A complete example](#a-complete-example)
- [Sizing and scrolling](#sizing-and-scrolling)
- [Debug visualization](#debug-visualization)
- [Common mistakes](#common-mistakes)
- [Android parity](#android-parity)
- [Optimization levels](#optimization-levels)
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
a port of the same code, and it lays a layout out as Android does, frame for
frame (see [Android parity](#android-parity)).

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
  of a set of widgets.
- **[Flow](#flow)** (wrapping rows, like `Wrap`) and **[grid](#grid)** (rows
  and columns with spans, skips, and weights). Both are virtual layouts: the
  widgets they arrange stay direct children that other links can target.
- **[Circular positioning](#circular-positioning)**,
  **[visibility](#visibility)** (`visible`, `invisible`, `gone`),
  **[groups](#groups)** that set the visibility of several children at once,
  and **[z-order](#z-order)** (`zIndex`).
- **[Right-to-left](#right-to-left)** layouts through `start` and `end`.
- **[Debug overlays](#debug-visualization)** that draw the constraint graph
  the way Android Studio's design surface does.
- **[Android's results](#android-parity)**: the same measure passes, `Direct`
  pass, and Cassowary solver as Android's ConstraintLayout, in its 32-bit
  float arithmetic, at its [optimization levels](#optimization-levels).
  Checked against Android's own code, every layout of the parity corpora
  gets Android's frames.
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
[`example/main.dart`](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/flutter_constraint_layout/example/main.dart).

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
      horizontalBias: 0.25, // a quarter of the free width on its start side
      verticalBias: 0.9, // near the bottom
      child: const Chip(label: Text('Biased')),
    ),
  ],
)
```

In a right-to-left layout, the horizontal bias of a child linked with `start`
or `end` is mirrored, as on Android: 0 then puts it against the right link,
which is its start. A child linked only with `left` and `right` keeps its bias
measured from the left. See [right-to-left](#right-to-left).

### Dimensions

`width` and `height` each take a `Dimension`. Both default to `.wrapContent`.

| Dimension | Size on that axis |
| --- | --- |
| `.wrapContent` | The child's own size, rounded up to a whole pixel. It is not limited by the links: content larger than the space between them overflows it. |
| `.fixed(n)` | Exactly `n` logical pixels, rounded to the nearest whole pixel. |
| `.matchConstraint` | Fills the space between the two links on that axis, less their margins. With only one link, the child sizes to its content. |
| `.spread(min: a, max: b)` | Like `.matchConstraint`, kept between `min` and `max` (both optional). With only one link, the child's own size is kept between them, and when a bound changes it the other dimension follows, so text wraps at a capped width. |
| `.constrainedWrap(min: a, max: b)` | The child's own size, but no larger than the space between its links, and kept between `min` and `max`. When the cap applies, the other dimension follows the capped size, so text wraps inside the links; see the note below. |
| `.percent(f, min: a, max: b)` | The fraction `f` (0 to 1) of the layout's size on that axis, kept between `min` and `max`. |
| `.matchParent` | The layout's full size on that axis. Where the links point is ignored, but their margins still inset it. On an axis where the layout sizes to its content there is nothing to fill, so the child takes its own size (see [children on an unbounded axis](#children-on-an-unbounded-axis)). |

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
> links, or `.constrainedWrap()` to keep a short text as narrow as its content:
> either way a long text wraps inside the links and its height follows. To keep
> it on one line instead, add `maxLines: 1` and an ellipsis, as above.

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
  vertical chain). In right-to-left text, a head linked with `start` or `end`
  has its bias mirrored like any other child's, so 0 puts the group against
  the right link, the chain's start.

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

A vertical guideline mirrors in right-to-left layouts, as on Android: `begin`
and `percent` are then measured from the right and `end` from the left. The
layout above therefore mirrors as a whole: in right-to-left text the sidebar
takes the right 30% of the width. Horizontal guidelines are the same in both
directions.

Like Android's `Guideline` view, a guideline is always `gone`: its own frame
is 0 x 0 at the line's position, and a link into it with a `goneMargin` uses
that gone margin instead of its `margin`.

### Barriers

A `Barrier` is an invisible line that follows the outermost edge of the widgets
in `referenced`: the end-most `end` edge, the lowest `bottom` edge, and so on.
Link to it to clear the widest or tallest of those widgets, whichever one that
turns out to be.

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
`margin` (0 by default) moves the barrier itself, and keeps its sign as it
does on Android: a positive value moves every barrier right or down, whatever
its edge and the text direction.

- On a `.right` or `.bottom` barrier, a positive value moves it further out,
  past the edge it tracks; on a `.left` or `.top` barrier, it moves it back
  over its widgets.
- A `.start` or `.end` barrier first resolves to the left or right edge for
  the text direction, then takes its margin the same way. In right-to-left
  text a positive margin therefore moves an `.end` barrier (the left edge
  there) back over its widgets, and a `.start` barrier (the right edge) past
  them, so a layout that gives a directional barrier a margin is not the
  mirror of its left-to-right twin. For a gap that mirrors, put it on the
  links, or negate the margin in right-to-left text.

Like Android's `Barrier` view, a barrier is always `gone`: it draws nothing,
its own frame is 0 x 0 at its position, and a link into it with a
`goneMargin` uses that gone margin.

Link a child's `top` or `bottom` to a barrier, not its `baseline`: a baseline
linked to a barrier's `top` or `bottom` can make the solver fail, as Android's
does, when the solver rather than the `Direct` pass places the barrier (see
[common mistakes](#common-mistakes)).

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

Invisible and gone children are also left out of the semantics tree, so screen
readers neither announce nor activate them, as on Android.

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
state, unlike a child removed with `if`. To set it for several children at
once, use a [group](#groups).

### Groups

A `ConstraintGroup` sets the visibility of several children at once, like
Android's `Group`. Its `visibility` replaces the `visibility` of every child
listed in `referenced`, so one value from your state shows or hides a whole
section of the layout:

```dart
Widget contactCard({required bool expanded}) {
  return ConstraintLayout(
    children: [
      Constrained(
        id: #name,
        start: .startOf(parent, margin: 16),
        top: .topOf(parent, margin: 16),
        child: const Text('Ada Lovelace'),
      ),
      Constrained(
        id: #email,
        start: .startOf(#name),
        top: .bottomOf(#name, margin: 8),
        child: const Text('ada@example.com'),
      ),
      Constrained(
        id: #phone,
        start: .startOf(#name),
        top: .bottomOf(#email, margin: 8),
        child: const Text('+44 20 7946 0000'),
      ),
      // Both detail rows take the group's visibility, whatever their own.
      ConstraintGroup(
        id: #details,
        referenced: [#email, #phone],
        visibility: expanded ? .visible : .gone,
      ),
    ],
  );
}
```

- **The group wins.** A referenced child takes the group's visibility for
  layout, painting, hit testing, and semantics, even when its own `visibility`
  says otherwise. When several groups reference the same child, the one that
  comes last in `children` wins.
- **A group only sets visibility.** As Android's `Group` view is, a group is
  a child of the layout in its own right: an unlinked widget that wraps
  nothing, laid out at 0 x 0 at the layout's origin (or gone, with the group).
  It never moves or sizes anything, but it takes part in the solve where it
  stands in `children`, as on Android, which can decide how a tie between
  equally good solutions is broken. No link can target a group, and no
  barrier, flow, grid, or other group can reference one. A group can
  reference `Constrained` children, flows, and grids. Guidelines and barriers
  have no visibility, so a group leaves them as they are.
- **Changing its `visibility` costs what changing the children's would.**
  Each referenced child is updated exactly as if its own `visibility` had
  changed.

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

A flow wraps within its own width. As on Android, a flow whose size the solver
resolves (a `.matchConstraint` width between margins or sibling links, as
above) is measured again at that size after the first solve, so its rows fit
inside its bounds rather than inside the whole layout's.

### Grid

`ConstraintGrid` places the widgets in `referenced` into a grid of `rows` by
`columns` cells, filling it row by row (or column by column with
`orientation: Axis.vertical`) from the start edge: the left edge, or the right
edge in [right-to-left](#right-to-left) text. Like a flow it is virtual, so
the tiles stay siblings that other constraints can target. Give a tile
`.matchConstraint` on both axes to fill its cell; otherwise it keeps its own
size, centered in the cell. The grid's own `width` and `height` default to
`.matchConstraint`, so link both sides of each axis, or give it a size.

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
  order, so row by row unless `orientation` is vertical). The entries are
  sorted by `index` and apply to the referenced widgets *in order*: the
  lowest-index entry places the first widget, the next entry the second
  widget, and the remaining widgets fill the free cells. So `'0:2x1, 4:1x2'`,
  in either order, gives the first widget cell 0 and the one below it, and the
  second widget cells 4 and 5. Entries beyond the number of widgets are
  ignored. In a grid with a single row or column, write `index:N` instead (`N`
  cells); the grid adds the extra cells the span needs, unless `skips` is set
  too (see below).
- **`skips`** uses the same syntax to leave cells empty: `'1:1x2'` skips cells
  1 and 2. The entries apply in order of `index`, and one that does not fit
  (it overlaps an earlier one or runs off the grid) stops the ones after it.
  In a grid with a single row or column, a skip `index:N` adds its `N` cells
  to the grid, and then the spans add none (as in the core grid behind
  Compose; Android's view-based grid has no `index:N` form): with
  `spans: '0:2'` and `skips: '2:1'`, three widgets on three columns get four
  columns, and the third widget gets no cell.
- **`rowWeights` and `columnWeights`** share the space unevenly, one entry per
  row or column: `columnWeights: [2, 1, 1]` makes the first column twice as
  wide as each of the others. A shorter list is padded with weights of 1, so
  `[2]` is the same as `[2, 1, 1]` on three columns, and a longer list is
  trimmed to the number of rows or columns.

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

Following Android's rules, two more values mirror in right-to-left text:

- **Horizontal bias** of a child with a `start` or `end` link: the layout uses
  `1 - horizontalBias`, so the bias is measured from the start and 0 puts the
  child against its right link. That includes the bias of a packed chain whose
  head is linked with `start` or `end`. A child linked only with `left` and
  `right` keeps its bias measured from the left.
- **Vertical guidelines**: `begin` is measured from the right edge, `end` from
  the left edge, and `percent` from the right (the line sits at `1 - percent`
  of the width from the left). Horizontal guidelines do not change.

`ConstraintFlow` mirrors too: in right-to-left text its rows start at the
right edge, and `contentHorizontalBias` is measured from the start. A chain's
head is its start-most member in either direction.

`ConstraintGrid` mirrors its columns: in right-to-left text the first column
is the rightmost, so the cells fill from the right edge, and widgets linked to
a grid's tiles follow them. Cell numbers in `spans` and `skips`, and the
entries of `columnWeights`, still count from the first column. The grid itself
is placed by its own links (with `start` and `end` it moves to the mirrored
position), and its cells mirror within its bounds. A tile's `horizontalBias`
is measured from the start edge of its cell, as for a child with a `start` or
`end` link, so a tile smaller than its cell mirrors too. Android's grid
helpers leave right-to-left unimplemented, so this follows the rest of this
package instead (the grid is outside the parity contract; see
[limitations](#limitations-and-differences-from-android)). Positions are whole
pixels, so a column edge that falls exactly on a half pixel can sit 1 px off
the exact mirror.

A barrier's `margin` does not mirror. As on Android, it keeps its sign in
both text directions: a positive value moves every barrier right, a `.start`
or `.end` one included, so in right-to-left text it moves an `.end` barrier
back over its widgets (see [barriers](#barriers)). A gap on the links that
target the barrier mirrors with the layout.

As on Android, `start` and `end` take precedence as a pair: when either is
set, the child's `left` and `right` links are ignored. Prefer one pair or the
other rather than mixing them. For example, `start: .startOf(parent)` with
`right: .rightOf(parent)` has only one active horizontal link, not two.

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
  are loose, as Android's layout fills an `EXACTLY` measure spec. Inside
  `Center` or `Align` it still fills the available space; it does not shrink
  to its children.
- **On an unbounded axis it sizes to its children**: it ends at the furthest
  child edge, plus the margin of any link to the layout's far edge. The
  incoming minimum on that axis is its minimum size, as Android's `minWidth`
  and `minHeight` are: the children are laid out in a layout at least that
  big, so a child linked to both edges centers in it.
- **With no children** it does the same: it fills a bounded axis, and takes
  the incoming minimum on an unbounded one.

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

### Whole pixels

Android lays a layout out in whole pixels, and so does this one, in whole
logical pixels:

- **Sizes you give round to the nearest pixel**: `.fixed` sizes, margins and
  gone margins, `min` and `max` bounds, a circle's radius, a guideline's
  `begin` or `end`, a barrier's margin, and a flow's gaps and padding. Biases,
  percents, ratios, and angles are taken as 32-bit floats, as Android takes
  them.
- **Sizes a child measures round up.** A child's measured size and baseline
  are taken as `max(0, (v - 0.001).ceil())`: a text 99.4 wide measures 100,
  so it is placed 100 wide rather than clipped or wrapped again at 99, as
  Android's `TextView` rounds its width up. The tolerance absorbs the noise of
  glyph metrics: a text 99.0005 wide measures 99, and one 99.002 wide
  measures 100.
- **Placement is exact.** Every child is placed at the integer frame the
  engine computes. A child whose last layout during the measure already has
  exactly that size keeps it; any other child is laid out again, tight at its
  frame.
- **The layout's own size** on a bounded axis is its maximum, rounded to a
  whole pixel for the engine. On an unbounded axis, the incoming minimum
  rounds up as a measured size does.

### Children on an unbounded axis

On an axis where the layout sizes to its content, such as the scrolling axis
of a `ListView`, there is no size for a child to fill. Android measures a
`match_parent` or `wrap_content` child there under an `UNSPECIFIED` measure
spec, and this layout does the same: the child is laid out with unbounded
constraints on that axis and takes its own size. That applies to
`.wrapContent`, to `.matchParent`, and to a match-constraint size while it is
measured for its content.

Most children size themselves under unbounded constraints: text, icons,
images, buttons, and a `Column` or `Row` of them. Some cannot, because they
need a bound to decide their size, for example:

- a scroll view along its scroll axis (`ListView`, `GridView`, `PageView`,
  `CustomScrollView`);
- a `TextField`, or any other `InputDecorator`, across an unbounded width;
- a `Row` or `Column` whose `Expanded` or `Flexible` children fill an
  unbounded main axis;
- a box that expands to fill its constraints, such as `SizedBox.expand()`.

When such a child comes out of its layout without a finite size, the layout
cannot place it, and it throws a `FlutterError` that names the child and the
axis, in every build. In a debug build, Flutter reports the child's own error
first.

```text
The ConstraintLayout child #list has no finite height after its layout under unbounded constraints.
```

Give the child a fixed size on that axis (`.fixed`), bound the layout on that
axis (with a `SizedBox`, say), or use a child that sizes itself there
(`shrinkWrap: true` for a `ListView`). Intrinsic-size and dry-layout queries
do not throw for such a child: they measure it at its minimum on that axis,
reporting the child's own error if its dry layout fails.

### Intrinsic sizes, dry layout, and baseline

`ConstraintLayout` reports intrinsic sizes, computes dry layouts, and has a
baseline, so it works inside the widgets that size or align their children by
them: `IntrinsicHeight` and `IntrinsicWidth`, the content of `AlertDialog` and
`SimpleDialog`, popup menu items, `IntrinsicColumnWidth` table columns,
`Baseline`, and a `Row` with `CrossAxisAlignment.baseline`.

- **Its intrinsic size is the size it wraps its children to.** The maximum
  intrinsic width for a given height is the width the layout takes when its
  width is unbounded and its height is that height, as in a horizontal list;
  the maximum intrinsic height is the same on the other axis. The minimum
  intrinsic sizes are worked out the same way, but with each child that sizes
  to its content measured at its own minimum intrinsic size, so wrapping text
  counts its longest word rather than its whole line.
- **Its dry layout** is the size it takes under given constraints, worked out
  without laying out any child: each child is asked for its own dry layout
  instead.
- **Its baseline** is the highest baseline among its visible children, so
  `Baseline` or a baseline-aligned `Row` lines the layout up by its top line
  of text. Invisible and gone children do not count, and neither do
  guidelines, barriers, groups, flows, or grids. Without a child that has a
  baseline, the layout has none. (Android's `ConstraintLayout` reports no
  baseline of its own.)

The rules above still apply inside these widgets. `IntrinsicHeight` gives the
layout a tight height, so the layout is exactly as tall as its content, but the
content area of an `AlertDialog` has a bounded height, which the layout fills:
wrap it in `IntrinsicHeight` there to make it only as tall as its content.

A dry layout with both axes bounded needs no engine run, since the layout
fills them. An intrinsic size, or a dry layout on an unbounded axis, is worked
out by measuring a throwaway copy of the layout through the same pipeline as a
layout pass (Android's measure, through the engine's `ViewHost`), with each
child's own dry layout and dry baseline standing in for its layout. No child
is laid out and the layout's own model is left untouched, so a query costs
about as much as a layout pass that runs the engine, and an `IntrinsicHeight`
or `IntrinsicWidth` around the layout adds one such query to each of its
layouts.

A query that repeats the last one of its kind, under the same configuration
and constraints, is replayed as a layout is (see [performance](#performance)):
each child is asked again for each dry measure the last query asked of it, and
when every answer is the same, the query returns that query's result without
running the engine. For that, the layout keeps the throwaway copy of its last
query of each kind (one for dry layouts, maximum intrinsic sizes, and dry
baselines, one for minimum intrinsic widths, and one for minimum intrinsic
heights): up to three, besides its own model. In the widget benchmark, a
keystroke in a 40-field form takes 0.142 ms, and 0.379 ms with the form
inside an `IntrinsicHeight` (debug build).

A query asks a child for its dry baseline only where that baseline can place
a widget (at either end of a baseline link, or in a flow aligned by
baselines) or where the child's last layout found a baseline. Many render
objects cannot compute a dry baseline (an `Image`, a `RotatedBox`, a scroll
view), and asking one throws in a debug build; none of them has a baseline in
a layout either.

A child that cannot compute a dry layout, such as a `LayoutBuilder`, makes
these queries fail in debug builds, as it does under Flutter's own layouts.
The layout reports the error and measures that child at the smallest size its
constraints allow, but Flutter leaves the child unable to lay out again, so
more errors follow. A child with tight constraints, such as one with a fixed
size, is never asked for its size: give such a child a fixed size, or use a
widget that supports dry layout.

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
[docs/DEBUG_VISUALIZATION.md](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/docs/DEBUG_VISUALIZATION.md).

## Common mistakes

When a widget is not where you expect it, turn on the
[debug overlay](#debug-visualization) to see the links the engine is solving,
then look for the symptom here.

| Symptom | Cause | Fix |
| --- | --- | --- |
| A child sits at the layout's left or top edge. | It has no link on that axis, or it is not wrapped in `Constrained`. | Link it on that axis, inside a `Constrained`. |
| A child linked on both sides of an axis does not stretch. | Links only position it; at the default `.wrapContent` size it centers between them. | Set `width: .matchConstraint` (or `height:`). |
| A `.matchConstraint` child is only as big as its content. | It is linked on only one side of that axis. | Link both sides. |
| Long text overlaps its neighbors or runs off the layout. | A `.wrapContent` `Text` is measured against the layout's full width. | Set `width: .matchConstraint`, or `.constrainedWrap()` to keep short text as narrow as its content. |
| `Incorrect use of ParentDataWidget.` | Another widget, such as `Padding`, sits between the `ConstraintLayout` and the `Constrained`. | Move it inside: `Constrained(child: Padding(...))`. |
| `Constrained link targets unknown id ...` | A typo, or an id from another `ConstraintLayout`: ids are scoped to one layout. | Fix the id; see [unknown and duplicate ids](#unknown-and-duplicate-ids). |
| `Constrained links loop back on themselves: ...` | The links form a loop, such as two children whose tops link to each other or an edge linked to itself, so no child in it has a position to start from. | Link one edge of the loop to `parent` or to a child outside it; see [unknown and duplicate ids](#unknown-and-duplicate-ids). |
| A widget lines up with the wrong sibling. | Two children share an id. | Rename one; see [unknown and duplicate ids](#unknown-and-duplicate-ids). |
| A chain style has no effect. | It is set on a member other than the chain's head. | Set it on the start-most (or top) member. |
| The layout fills the screen instead of fitting its children. | On a bounded axis it takes the maximum size, even inside `Center`. | Wrap it in `UnconstrainedBox`, or size it with `SizedBox`. |
| The layout fills the height of an `AlertDialog` instead of fitting its children. | The dialog's content area has a bounded height, and on a bounded axis the layout takes the maximum size. | Wrap it in `IntrinsicHeight`. |
| `The _RenderLayoutBuilder class does not support dry layout.` inside `IntrinsicHeight`, `IntrinsicWidth`, a dialog, or a menu. | A child is, or contains, a `LayoutBuilder`, which cannot be measured without laying it out. See [intrinsic sizes](#intrinsic-sizes-dry-layout-and-baseline). | Give that child a fixed size, or replace the `LayoutBuilder`. |
| `The ConstraintLayout child #list has no finite height after its layout under unbounded constraints.` | The layout is unbounded on that axis (inside a scroll view, say), so the child is measured with unbounded constraints there, and it cannot size itself without a bound, as a `ListView` cannot. | Give the child a fixed size on that axis, bound the layout with a `SizedBox`, or use a child that sizes itself (`shrinkWrap: true` for a `ListView`); see [children on an unbounded axis](#children-on-an-unbounded-axis). |
| In right-to-left text, a `.start` or `.end` barrier's `margin` moves it the wrong way. | A barrier's `margin` keeps its sign, as on Android: a positive value moves every barrier right or down. | Put the gap on the links that target the barrier; see [barriers](#barriers). |
| Children collapse into the layout's top-left corner (a `.wrapContent` child at 0 x 0, so it vanishes; in a list item, the layout itself comes out 0 high), and `EXCEPTION : Null check operator used on a null value` is printed (`EXCEPTION : Unexpected null value.` in a web debug build). | A child's `baseline` is linked to a barrier's `top` or `bottom`, and the barrier is left to the solver: at the default level when it references a widget the [`Direct` pass](#optimization-levels) does not place, such as a chain member, a percent size, or, in a layout that sizes its height to its content, a widget linked to the layout's bottom (a vertically centered icon, say), and at `.none` always. Android's solver throws a `NullPointerException` on that link and gives the same frames. | Link the child's `top` or `bottom` to the barrier instead, as in `top: .bottomOf(#barrier)`. |

### Unknown and duplicate ids

Ids are plain symbols, so a typo compiles. Here is what happens when one slips
through.

**A link or reference to an id that no sibling defines.** In debug builds the
layout throws a `FlutterError` that names the id:

```text
Constrained link targets unknown id Symbol("titel"). Targets must be `parent` or the id of a sibling Constrained in the same ConstraintLayout.
```

`circle` links, `Barrier`, `ConstraintFlow`, `ConstraintGrid`, and
`ConstraintGroup` report unknown ids the same way. A link or `referenced` entry
that names a `ConstraintGroup` is reported too, with a message that says so: a
group only sets the visibility of the children it references, so it is not a
target. The layout pass is abandoned, so the other children are not positioned
until the id is fixed. In profile and release builds the check is compiled
out: the bad link or reference is skipped (a skipped link leaves its edge
unconstrained), and the rest of the layout resolves. In profile and release
WebAssembly builds and in `--obfuscate` builds, a link that writes an id in a
different form from the child's id
(`#item0` for `Symbol('item0')`) is skipped the same way; see
[core concepts](#core-concepts).

**Links that loop back on themselves.** Four kinds of loop leave none of their
children a position to start from:

- two children whose matching edges link to each other, such as two tops;
- an edge linked to itself, such as `top: .topOf(#a)` on the child `#a`;
- two children linked both ways on both sides, each one's start and the
  other's end linked to each other, which makes a chain with no ends;
- a chain whose first child's start links one way to its last child, while
  the last child's end links back to the first child.

Debug builds report each of them like an unknown id, with a `FlutterError`
that names every link of the loop:

```text
Constrained links loop back on themselves: Symbol("a") top to Symbol("b") top, Symbol("b") top to Symbol("a") top. None of these children has a position to start from. Link one of these edges to `parent` or to a child outside the loop instead.
```

Baseline links are not followed, so two children whose baselines link to each
other are not reported. In profile and release builds the check is compiled
out, and the layout lays out every kind. Android never finishes laying out a
layout with the last kind. It lays out the others, as this layout does: when
nothing else anchors the loop, its children sit at the layout's left or top
edge, in either text direction. Two children whose tops link to each other,
for example, both sit at the top edge.

**Two children with the same id.** This is not reported at runtime: links to
that id resolve to the last child that uses it.

The companion analyzer plugin,
[`flutter_constraint_layout_lints`](https://pub.dev/packages/flutter_constraint_layout_lints),
flags both id mistakes as you type, with the warnings
`undefined_constraint_id` and `duplicate_constraint_id`. Enable it in the
`analysis_options.yaml` at the root of your package, then restart the Dart
analysis server:

```yaml
plugins:
  flutter_constraint_layout_lints: ^1.0.0
```

The warnings appear in your IDE and in `dart analyze`, which exits with a
non-zero status when it reports them, so it can enforce them in CI.
`flutter analyze` does not report them. See the plugin's page for its options
and for what static analysis can and cannot see.

## Android parity

`ConstraintLayout` lays a layout out as Android's `ConstraintLayout` does,
frame for frame. It runs Android's own pipeline, ported line by line to Dart
(see [how it works](#how-it-works)):

- every child is measured as Android's view measurer measures a child view,
  under the measure spec Android would give it, and its baseline is read, as
  Android reads the baseline of every child it measures;
- the layout is solved by Android's measure passes at its
  [optimization level](#optimization-levels): the `Direct` pass and the
  Cassowary solver of `androidx.constraintlayout.core`;
- every float operation is the 32-bit operation Android's Java code performs,
  in the same order, with Java's integer casts, so every value rounds where
  Android's does;
- every child is placed at the integer frame Android computes.

This is measured, not assumed. The reference is Android's own code at the
revision the engine is pinned to: upstream's `constraintlayout-core` in Java,
driven through a Java port of the `ConstraintLayout` view layer (`onMeasure`,
the child measurer, `MeasureSpec`). That reference was itself checked against
real Android views (ConstraintLayout 2.2.1, run by Robolectric 4.16 on SDK 35)
on 732,597 layouts, with no difference. Against it, the layout's size and
every child's position and size must be equal, to the pixel. At Android's
default level:

| Laid out | Layouts | Frames that differ from Android's |
| --- | --- | --- |
| Real `ConstraintLayout` widget trees, through this package: realistic screens (lists, settings, chat, toolbars, forms, cards, nested and right-to-left layouts) and targeted cases | 60,000 | 0 |
| The engine's `ViewHost` path, the one this package runs: realistic screens with text and box content | 319,827 | 0 |
| The same path: targeted cases (percent sizes with a minimum, crossed and negative edges, odd biases, ratios, chains, gone widgets, circles, flows, wrap content, measure strategies, in-place changes) | 469,990 | 0 |
| The engine's core path: realistic, targeted, and adversarial layouts | 1,059,439 | 0 |

Also measured:

- On all 60,000 widget trees, the size a dry layout reports is the size the
  first layout takes (from its second layout on, 1 tree at the default level
  changes size, as Android's second layout does, while a dry layout keeps the
  first layout's size), and a second layout of the same tree is Android's own
  second layout of it.
- A layout changed in place gives what a fresh build of the result gives, as
  Android's own views do at the default level, over 48,403 sequences of
  changes. At the other levels Android's views keep some state from one
  layout to the next, and the engine keeps the same (see
  [limitations](#limitations-and-differences-from-android)).
- The engine's corpora match Android at `OptimizationLevel.none` and at the
  opt-in graph levels too, apart from layouts on which Android's own code
  throws or hangs.
- On a sample of 2,000 layouts, the trace of the solver (every variable, row,
  pivot, and value) is, bit for bit, the trace Android's Java code writes.

A layout counts when Android gives it one answer. Left out, and counted, are
the layouts whose result on Android depends on its hash order (164), and those
on which Android's code hangs (8), overflows its stack (110), or throws out of
its layout (111), all but 10 of them in the adversarial corpus.

The contract is Android's frames for the same measure answers: a layout whose
children measure to the same sizes and baselines gets the same frames. It does
not make a Flutter `Text` measure like an Android `TextView`, frames are whole
logical pixels, and `ConstraintGrid` has no Android counterpart to compare
with; see [limitations](#limitations-and-differences-from-android).

A sample of the corpora, with Android's frames, runs with the test suites:
1,600 widget trees in this package's
[`test/parity/`](https://github.com/BirjuVachhani/flutter_constraint_layout/tree/main/packages/flutter_constraint_layout/test/parity),
and 2,560 engine layouts in the engine's
[`test/parity/`](https://github.com/BirjuVachhani/flutter_constraint_layout/tree/main/packages/constraint_engine/test/parity).

## Optimization levels

`optimizationLevel` takes Android's optimization flags
(`app:layout_optimizationLevel` in XML, `setOptimizationLevel` in code) as an
`OptimizationLevel`, combined with `|`. At every level the layout does what
Android does at that level, and the default is Android's default:

```dart
ConstraintLayout(
  optimizationLevel: OptimizationLevel.standard, // the default
  children: [
    // ...
  ],
)
```

| Level | Android's value | What Android does |
| --- | --- | --- |
| `.standard` | 257 | The default: `.direct` and `.cacheMeasures`. |
| `.direct` | 1 | In the first measure pass, the `Direct` pass places everything that follows directly from the links before the solver runs: a widget linked to edges already placed, a centered widget at its bias, a match-constraint size spread between placed edges, guidelines, and a barrier once all of its widgets are placed. It measures the children it sizes as it goes. The solver then settles the rest, such as chains, aspect ratios, and percent sizes, and takes `Direct`'s values for everything else. |
| `.cacheMeasures` | 256 | A child already measured at its current size under an equivalent request keeps that size without being measured again. |
| `.none` | 0 | No optimization: the solver resolves every layout, and every measure asks the child. `Direct` rounds some positions differently from the solver, so Android's frames here can differ from those at `.standard`; the layout follows Android at each. |
| `.graph` | 64 | The dependency graph, an opt-in. Android runs it when no child is in a chain, a flow, or a grid, and both of the layout's axes are bounded: the graph resolves the layout first, and the solver runs only if it leaves something unresolved. Any other layout is measured as it is without the flag. |
| `.graphWrap` | 128 | As `.graph`, and also when an axis is unbounded: the graph then resolves only the bounded axes, and the solver runs as well. |
| `.barrier`, `.chains`, `.dimensions`, `.ratio`, `.groups` | 2, 4, 8, 16, 32 | Nothing: Android reads them nowhere. They are accepted for parity. |
| `.dependencyOrdering`, `.grouping` | 512, 1024 | Not ported, so they change nothing. Android's default leaves them off. |

`OptimizationLevel.standard | OptimizationLevel.graph` is Android's 321.
Changing `optimizationLevel` measures the layout again without rebuilding its
model. Without `.direct`, and at the graph levels, a layout laid out again
can differ from its first layout, as Android's does (see
[limitations](#limitations-and-differences-from-android)).

Keep `.standard` unless you are matching an Android layout that sets another
level. The graph levels exist for parity with layouts that opt into them, and
they are not a speed-up here: every measure here is Android's measure after a
change, which builds the graph again. In the engine's benchmark, a measure of
600 widgets linked one way takes 0.219 ms at `.standard` and 0.338 ms at
`.standard | .graph` (through `ViewHost`, compiled ahead of time, on an Apple
M4).

## Performance

A layout pass that runs the engine runs Android's pipeline: the children are
measured, the `Direct` pass places what follows directly from the links, the
solver settles the rest, and the children whose size the solver decided are
measured again. What that costs depends on how much is left to the solver.

- **Most real layouts are placed by `Direct`.** When every child follows from
  its links, as in a form, a list item, a settings row, or a card, the solver
  only takes `Direct`'s values, and a measure costs microseconds. On 4,781
  realistic screens sampled from the parity corpus, the median measure takes
  6.0 µs through `ViewHost`, the path this package runs (4.2 µs on the
  engine's core path), compiled ahead of time on an Apple M4.
- **Chains, aspect ratios, and percent sizes are the solver's**, as on
  Android, and its cost grows faster than the widget count. Each
  `ConstraintLayout` is solved on its own, so for a large, chain-heavy screen,
  several small layouts (one per list item, say) are cheaper than one big one.

### What a layout pass does

The engine model persists between frames, and each layout pass does no more
work than its changes need:

- **Replay.** When the configuration and the incoming constraints are those
  of the last layout, and that layout gave the same result as the one before
  it, every child is asked again for each measure the last layout asked of it.
  When every answer is the same, the children are placed where the last layout
  placed them, without running the engine. A replay saves the engine's work,
  not the children's layouts: asking a child again costs little when it is
  clean and its constraints are unchanged, because Flutter's own layout cache
  answers, and a child whose answer changed ends the replay. A result is
  replayed only once a full run has repeated it, so the second layout after a
  build always runs the engine: Android's own second layout can differ from
  its first, on a few degenerate layouts at the default level and more often
  at the others (see
  [limitations](#limitations-and-differences-from-android)).
- **In place.** A `Constrained` property changed (a link, margin, bias, size,
  ratio, chain style, weight, or visibility), or the `visibility` of a
  `ConstraintGroup` changed, which updates each `Constrained` child it
  references as a change of that child's own visibility would. The affected
  widgets are updated in the existing model, which is measured again. New
  incoming constraints, a child whose content changed size, or a new
  `optimizationLevel` also measure the existing model again without
  rebuilding it.
- **Rebuild.** Children were added, removed, or reordered, an id changed, the
  text direction changed, a property of a `Guideline`, `Barrier`,
  `ConstraintFlow`, or `ConstraintGrid` changed, or a `ConstraintGroup`'s
  `referenced` list changed (or its `visibility`, when it references a flow or
  a grid). The model is rebuilt from scratch.

Changing `zIndex` or a debug flag only repaints. A dry layout or intrinsic
size is measured on a throwaway copy of the model and replays the same way;
see [intrinsic sizes](#intrinsic-sizes-dry-layout-and-baseline).

A replay is exact: given the same answers, a full run would repeat the last
one. To check it, run with `--dart-define=cl.verifyReplay=true`: every
replayed layout and dry query then also runs in full, and a difference is
reported as an error.

### Measured

The engine's benchmark,
[`resolver_benchmark.dart`](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/constraint_engine/benchmark/resolver_benchmark.dart),
measures screens of 80 x 40 widgets in stacked rows. Compiled ahead of time
(the closest to a release build) on an Apple M4, a measure through `ViewHost`
takes (p50):

| Rows | Widgets | Each widget linked to the one before it | Each row a spread chain |
| --- | --- | --- | --- |
| 3 of 3 | 9 | 0.002 ms | 0.034 ms |
| 8 of 6 | 48 | 0.014 ms | 0.319 ms |
| 20 of 12 | 240 | 0.084 ms | 0.976 ms |
| 40 of 15 | 600 | 0.219 ms | 3.316 ms |
| 50 of 24 | 1,200 | 0.449 ms | 9.461 ms |

Building the model and measuring it once, as a structural change does, takes
0.412 ms for the 600 widgets linked one way and 3.602 ms for the 600 in chains
(core path). In the parity tooling's benchmark (`rbench6`, on the same
chained screens), Android's own code, compiled by the JVM's JIT on the same
machine, takes 0.023 ms on the 9 chained widgets, where the engine takes
0.033 ms, and 5.749 ms on the 600, where the engine takes 3.179 ms (core
path). On 600 widgets of 60 x 40 linked one way it takes 4.036 ms, where the
engine takes 0.171 ms: each time Android's solver takes a value that
`Direct` placed, it scans its variables for a synonym that it can never find,
and the engine skips that scan.

The widget benchmark,
[`flutter_layout_benchmark.dart`](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/flutter_constraint_layout/benchmark/flutter_layout_benchmark.dart),
runs under `flutter test`, in debug mode (JIT, with asserts), so its times are
inflated against a release build; read them as ratios. For 600 children of
80 x 40 in 40 rows, a layout pass takes (p50):

| 600 children | Replay | Engine pass, new constraints | Engine pass, every child laid out |
| --- | --- | --- | --- |
| Each linked to the one before it | 0.093 ms | 0.475 ms | 1.424 ms |
| Each row a spread chain | 0.091 ms | 4.863 ms | 6.048 ms |
| Spread chains with a 2:1 ratio cell in each row | 0.092 ms | 5.030 ms | 6.091 ms |

On realistic children (text with baselines, wrap content), a keystroke in a
40-field form of 87 children replays in 0.142 ms (0.379 ms with the form in an
`IntrinsicHeight`), and the first layout of 50 list rows, each its own
`ConstraintLayout` of 6 children, takes 9.682 ms, most of it in the
children's own text layout.

Android's measure sequence can measure a child more than once in a pass, and
placement lays a child out again at its frame unless its last measure already
had that size. A layout under the same constraints as the child's last one is
answered by Flutter's layout cache without running the child's layout.

## Limitations and differences from Android

- **Logical pixels, not device pixels.** Android lays out in whole device
  pixels, after converting every `dp` value to pixels at the screen's density.
  This package lays out in whole logical pixels (see
  [whole pixels](#whole-pixels)), so its frames are Android's at a device pixel
  ratio of 1, which is what the parity checks compare. At any other ratio, an
  edge that Android rounds in device pixels, such as a centered child that
  falls on a half pixel, can land up to a logical pixel away from where this
  package puts it. There is no device-pixel mode.
- **Content is measured by Flutter.** Parity holds for the same measure
  answers. A Flutter `Text` does not measure like an Android `TextView`
  (fonts, shaping, and line heights differ), and this package rounds a
  measured size up by its own rule, so the layout rules match while the
  content sizes are Flutter's: the same screen with the same text can come out
  a few pixels different from an Android build of it.
- **`ConstraintGrid` is outside the parity contract.** It follows `GridCore`
  from core 1.1.1, the grid that Jetpack Compose's ConstraintLayout uses, not
  the view-based `Grid` helper of Android's ConstraintLayout 2.2.1, which
  builds its cells out of views, so there is no Android result to compare it
  with. The view-based grid ignores a weight list with the wrong number of
  entries, where this one pads it with weights of 1 or trims it, and it hands
  spans to the widgets in the order they are listed, where this one sorts them
  by cell index first. This one also mirrors its columns in right-to-left
  text, which Android's grid helpers leave unimplemented, and a layout that
  holds a grid lets the solver treat nearly equal goals as a tie, so that a
  weighted grid keeps its weights where Android's 32-bit solver can collapse
  them. See [grid](#grid).
- **Android's own history.** Android's layout keeps some state from one
  measure to the next, and so does this one, so a layout laid out again can
  differ from its first layout exactly where Android's does. At the default
  level that is a few degenerate layouts, for example some flows that are a
  match constraint on both axes, which can move once when they are laid out
  again. Without `.direct` (`.none`, `.cacheMeasures`, and the graph levels
  without it), a barrier whose position follows without the solver, because
  every widget it references is gone and not counted, keeps a flag that holds
  it at 0 from its second layout on. At the graph levels the dependency graph
  also keeps what its last run left, and on some layouts changed in place
  Android's graph throws a `NullPointerException`: this package throws there
  too, as a layout error (on all but a few, which Flutter does not lay out
  again where Android does, see below). Every later layout that runs the
  graph then throws again, as Android's next measure does, until that
  change is undone or the layout's model is rebuilt (a child added, removed
  or moved, or a new text direction, rebuilds it). A dry layout or an
  intrinsic size measures a new model, so it gives the size of a first
  layout. When Android measures a layout again without any child having
  changed (a new size from its parent, say), it also keeps more of the
  previous measure's state, which can change the result of a degenerate
  layout; here every measure starts as Android's measure after a change
  does, the path every first layout and every content change takes.
- **When a layout is laid out again.** Where the result depends on the
  layout before it (the levels other than the default), it also depends on
  how often a layout is laid out, and Flutter and Android do not lay out on
  the same events: a change to the content of a gone child lays the layout
  out again on Android, not here, and a change between visible and invisible
  lays it out again here, not on Android. Over the 48,403 sequences of
  changes above, applied to Android's views as an app that sets only what
  changed would, that leaves 5 sequences laid out unlike Android's at `.none`
  and at `.cacheMeasures`, 7 at each graph level without `.direct`, 2 at
  `.standard | .graph` and at `.standard | .graph | .graphWrap`, and none at
  the default level.
- **Where Android never finishes.** Where Android's code would loop forever,
  as on the last kind of [link loop](#unknown-and-duplicate-ids), this package
  finishes and gives a layout of its own.
- **A bounded axis is always filled.** Flutter's constraints do not say
  whether a child should fill a bounded space (Android's `match_parent`) or
  wrap its content within it (`wrap_content` in a bounded parent), so the
  layout always fills a bounded axis, as Android fills an `EXACTLY` measure
  spec. To size it to its content within a bound, wrap it in `IntrinsicHeight`
  or `IntrinsicWidth`.
- **A `goneMargin` of 0 means "not set".** When the target is gone, the
  regular `margin` stays in effect; you cannot replace it with exactly 0.
- **No `guidelineUseRtl`.** A vertical guideline always mirrors in a
  right-to-left layout, which is Android's default; there is no equivalent of
  Android's `guidelineUseRtl="false"` to keep one in place. See
  [right-to-left](#right-to-left).
- **A baseline of its own.** Android's `ConstraintLayout` reports no baseline,
  so its parent cannot align it by one. This one reports the highest baseline
  among its visible children, so `Baseline` and a baseline-aligned `Row` can
  align it; see
  [intrinsic sizes, dry layout, and baseline](#intrinsic-sizes-dry-layout-and-baseline).
- **Id and link mistakes.** Unknown ids throw in debug builds and are skipped
  in release builds; duplicate ids are not reported. Links that loop back on
  themselves throw in debug builds too and are laid out in release builds;
  Android does not report them, and never finishes laying out one kind of
  them. See [unknown and duplicate ids](#unknown-and-duplicate-ids).
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
  - **The dependency-ordering and grouping passes**
    (`OptimizationLevel.dependencyOrdering` and `.grouping`), which Android's
    default leaves off.
- **No view-layer helpers** such as Android's `Layer` or `ConstraintSet`. In
  Flutter, rebuild with different properties instead of applying a constraint
  set. Android's `Group` is here as [`ConstraintGroup`](#groups).

## How it works

`ConstraintLayout` maps each child to a widget in
[`constraint_engine`](https://pub.dev/packages/constraint_engine), a pure-Dart,
line-faithful port of `androidx.constraintlayout.core` and of the part of
Android's `ConstraintLayout` view that drives it. The port is pinned to
upstream commit `9cd4b5a4079a14175f91dc897abd83270799364a`;
[UPSTREAM.md](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/constraint_engine/UPSTREAM.md)
records the pin, how it compares with the released versions, and every
intentional divergence.

Each child is configured as Android configures the widget of a child view
from its layout params: one engine widget per child, in child order (a
`ConstraintGroup` included), linked as Android links it. A layout pass then
does what Android's `onMeasure` and `onLayout` do:

1. **The layout's measure specs.** A bounded axis is `EXACTLY` its maximum,
   rounded to a whole pixel, so the layout fills it. An unbounded axis is
   `UNSPECIFIED`, so the layout wraps its children there, with the incoming
   minimum as its minimum size.
2. **Measuring.** The engine's `ViewHost`, its port of `onMeasure`, resets
   every widget's measure state as Android does after a change (keeping what
   Android keeps from one measure to the next), and measures the layout at its
   [optimization level](#optimization-levels). Every child measure goes
   through Android's view measurer, which picks the child's measure spec from
   its dimension and the pass. The child is then laid out under the box
   constraints the spec stands for (`EXACTLY` is tight, `AT_MOST` is loose,
   `UNSPECIFIED` is unbounded); its size is rounded up to whole pixels, and its
   alphabetic baseline is read.
3. **Solving.** At the default level, the `Direct` pass first places
   everything that follows directly from the links. Upstream's `LinearSystem`
   settles the rest: an implementation of the Cassowary linear-arithmetic
   constraint algorithm (the family behind Apple's Auto Layout), which
   expresses the layout as weighted equations and inequalities and minimizes
   the error with an incremental simplex method, in 32-bit float as on
   Android. Children whose size the solver decided are measured again at that
   size, and the layout is solved again when an answer changed.
4. **Placement.** Each child is placed at its integer frame. A child whose
   last layout during the measure already has exactly that size keeps it; any
   other child is laid out again, tight at its frame. The layout's own size is
   its measured size, constrained by the incoming constraints.

## Links

- Documentation: [constraints.birju.dev/docs](https://constraints.birju.dev/docs)
- Repository: [github.com/BirjuVachhani/flutter_constraint_layout](https://github.com/BirjuVachhani/flutter_constraint_layout)
- Issue tracker: [github.com/BirjuVachhani/flutter_constraint_layout/issues](https://github.com/BirjuVachhani/flutter_constraint_layout/issues)
- Changelog: [CHANGELOG.md](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/flutter_constraint_layout/CHANGELOG.md)

## License

BSD 3-Clause. See
[LICENSE](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/flutter_constraint_layout/LICENSE).
The debug visualization adapts the rendering of Android Studio's layout editor:
`lib/src/debug/debug_painter.dart` and `lib/src/debug/debug_palette.dart` keep
the Android Open Source Project's copyright line and are also covered by the
Apache License 2.0, whose notice is included in the same LICENSE file.
