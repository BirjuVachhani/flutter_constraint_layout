# constraint_engine

The layout engine behind Android's ConstraintLayout, in pure Dart. You describe
widgets as rectangles and the constraints between their edges, and the engine
works out the position and size of every widget. It is a line-faithful port of
`androidx.constraintlayout.core` with both of its resolution strategies: a
dependency-graph resolver handles most layouts directly, and the
Cassowary-style `LinearSystem` solver takes over for the layouts the graph
cannot resolve. No Flutter dependency.

> **Building a Flutter app?** Use
> [flutter_constraint_layout](https://pub.dev/packages/flutter_constraint_layout)
> instead. It is built on this package and provides ConstraintLayout as
> Flutter widgets (`ConstraintLayout`, `Constrained`, `Guideline`, `Barrier`,
> `ConstraintFlow`, `ConstraintGrid`), with a debug visualizer.

## When to use it

Use `constraint_engine` directly when you want ConstraintLayout's behavior
outside Flutter's widget layer:

- custom renderers: canvas and game UIs, terminal UIs, SVG or PDF output;
- server-side or build-time layout;
- tests and tools that check how a constraint layout resolves;
- studying or porting ConstraintLayout itself, including upstream's tests.

In a Flutter app, flutter_constraint_layout does the work this package leaves
to you: it measures children through their render objects, keeps the engine
model in sync across frames, and maps `start` and `end` to the text direction.

## Installation

```sh
dart pub add constraint_engine
```

The package needs Dart 3.12 or later and has no dependencies.

```dart
import 'package:constraint_engine/constraint_engine.dart';
```

## Usage

This walkthrough builds the top of the layout in the
[runnable example](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/constraint_engine/example/constraint_engine_example.dart):
a fixed-size logo, a label that wraps its text, and a banner that stretches
across the container. The code uses Dart's dot shorthands, so `.left` stands
for `ConstraintAnchorType.left` and `.wrapContent` for
`DimensionBehaviour.wrapContent`.

### 1. Create a container

```dart
final root = ConstraintWidgetContainer.sizeNamed('root', 400, 300);
```

The container is the root of the layout. Its dimension behaviour is `fixed` by
default, so it is exactly 400 x 300.

### 2. Create widgets and add them

```dart
final logo = ConstraintWidget.sizeNamed('logo', 48, 48);
final title = ConstraintWidget.named('title');
final banner = ConstraintWidget.sizeNamed('banner', 0, 40);
root.addAll([logo, title, banner]);
```

A `ConstraintWidget` is a rectangle in the layout model, not something that
draws: your code decides what each one stands for. The name is optional and only
shows up in debugging output such as `getDebugName()` and `toString()`. The size
given to the constructor is the widget's stored size, which a `fixed` axis
keeps.

### 3. Connect anchors

```dart
logo.connect(.left, root, .left, 16);
logo.connect(.top, root, .top, 16);

title.connect(.left, logo, .right, 12);
title.connect(.top, logo, .top);
title.connect(.bottom, logo, .bottom);

banner.connect(.left, root, .left, 16);
banner.connect(.right, root, .right, 16);
banner.connect(.top, logo, .bottom, 16);
```

`connect(from, target, to, [margin])` ties this widget's `from` anchor to the
target's `to` anchor, `margin` pixels apart. A margin is measured away from the
target, so a margin on a `right` or `bottom` anchor moves the widget left or
up. A widget constrained on both sides of an axis is centered between them,
which is how the title lines up with the middle of the logo.

### 4. Choose dimension behaviours

```dart
title.setHorizontalDimensionBehaviour(.wrapContent);
title.setVerticalDimensionBehaviour(.wrapContent);
banner.setHorizontalDimensionBehaviour(.matchConstraint);
```

Each axis of a widget has a `DimensionBehaviour`. `fixed`, the default, keeps
the stored size; `wrapContent` asks the measurer for the content's size; and
`matchConstraint` takes the space between the widget's anchors. The banner's
height stays fixed at 40.

### 5. Provide a measurer

The engine cannot know how big a label's text is, so it asks a `Measurer` that
your code implements:

```dart
class TextMeasurer implements Measurer {
  TextMeasurer(this.texts);

  final Map<ConstraintWidget, String> texts;

  @override
  void measure(ConstraintWidget widget, Measure measure) {
    // A fixed-pitch font: 8 px per character, 20 px per line.
    final text = texts[widget];
    final naturalWidth = text == null ? widget.getWidth() : text.length * 8;
    final naturalHeight = text == null ? widget.getHeight() : 20;

    // Wrap-content axes take the natural size. The engine sizes every other
    // axis itself, so echo back the size it proposes.
    measure.measuredWidth =
        measure.horizontalBehavior == DimensionBehaviour.wrapContent
        ? naturalWidth
        : measure.horizontalDimension;
    measure.measuredHeight =
        measure.verticalBehavior == DimensionBehaviour.wrapContent
        ? naturalHeight
        : measure.verticalDimension;
    measure.measuredBaseline = 0;
    measure.measuredHasBaseline = false;
  }

  @override
  void didMeasures() {}
}
```

```dart
root.setMeasurer(TextMeasurer({title: 'Pure Dart layout'}));
```

Without a measurer, `layout()` installs a default one under which a
wrap-content widget keeps its stored size. That is enough when every size is
known up front and the layout has no `Flow` or `GridCore`, which only work
through a measurer that runs their own measure pass. See
[The measurer](#the-measurer) for the full contract.

### 6. Lay out and read the result

```dart
root.layout();

for (final widget in root.getChildren()) {
  print(
    '${widget.getDebugName()}: x ${widget.getX()}, y ${widget.getY()}, '
    '${widget.getWidth()} x ${widget.getHeight()}',
  );
}
```

```text
logo: x 16, y 16, 48 x 48
title: x 76, y 30, 128 x 20
banner: x 16, y 80, 368 x 40
```

Positions are relative to the container's top-left corner, and `getLeft()`,
`getTop()`, `getRight()`, and `getBottom()` give the edges. Sizes, positions,
and margins are integers, in whatever unit your renderer uses. The title's 16
characters measure 128 x 20, so centering it on the 48 px logo puts its top at
16 + (48 - 20) / 2 = 30. The banner is 400 - 16 - 16 = 368 wide.

### Laying out again

The model is persistent: change sizes, constraints, or visibility, then call
`layout()` again. Each call rebuilds the dependency graph from the current
model. Sizes are stored on the widgets in both directions, though: a `fixed`
axis reads the stored size, and a layout writes resolved sizes back, including
0 x 0 for a `GONE` widget. Set a size again (for example with
`setDimension(width, height)`) when an earlier layout may have changed it,
such as when a gone widget becomes visible.

The full example also builds a chain and a biased widget, then widens the
container and lays it out again. In a checkout of the repository, run it from
`packages/constraint_engine`:

```sh
dart run example/constraint_engine_example.dart
```

## Key concepts

### Widgets and anchors

Every `ConstraintWidget` has anchors, named by `ConstraintAnchorType`: `left`,
`top`, `right`, `bottom`, and `baseline`, plus `centerX`, `centerY`, and
`center`. The container is a widget too, so children constrain to its anchors
the same way they constrain to each other. `left` and `right` connect only to
`left` or `right` anchors, and `top` and `bottom` only to `top` or `bottom`
ones. `connect` silently ignores an invalid pair such as `left` to `top`.

- **Centering and bias.** A widget connected on both sides of an axis is
  centered between the two targets. `setHorizontalBiasPercent` and
  `setVerticalBiasPercent` move it through the free space: 0 puts it against
  the left (or top) target, 1 against the right (or bottom) one, and 0.5, the
  default, in the middle. `connect(.centerX, target, .centerX)` connects both
  `left` and `right` to the target's matching edges, and `centerY` does the
  same for `top` and `bottom`.
- **Circular positioning.** `connectCircularConstraint(target, angle, radius)`
  puts the widget's center `radius` px from the target's center, at `angle`
  degrees clockwise from the top. That is what the `center` anchor is for. A
  connected `center` anchor replaces the widget's edge constraints, so
  connecting `center` to `center` with `connect`, which sets no angle, does
  not center a widget: it stays at (0, 0). Use the anchor pairs or `centerX`
  and `centerY` instead.
- **Baselines.** `connect(.baseline, other, .baseline)` aligns two widgets'
  text baselines. Both widgets must already have a baseline when you connect
  them (`setBaselineDistance` with a positive value), or the connection is
  ignored. A measurer should report baselines as well, because the engine
  copies `measuredBaseline` and `measuredHasBaseline` onto the widget after
  every measure.

### Dimension behaviours

| `DimensionBehaviour` | Size along that axis |
| --- | --- |
| `fixed` (default) | The stored size, from the constructor, `setWidth`, `setHeight`, or `setDimension`. |
| `wrapContent` | The content's natural size, as reported by the measurer. |
| `matchConstraint` | Derived from the constraints, according to the match-constraint mode (below). |
| `matchParent` | The container's size minus the widget's margins on that axis. |

A `wrapContent` container sizes itself around its children: call
`root.setHorizontalDimensionBehaviour(.wrapContent)` (or the vertical one) and
read `root.getWidth()` after `layout()`.

### Match-constraint modes

`setHorizontalMatchStyle(mode, min, max, percent)` and
`setVerticalMatchStyle(...)` choose how a `matchConstraint` axis is sized. The
modes are `ConstraintWidget` constants:

- `MATCH_CONSTRAINT_SPREAD` (the default) fills the space between the anchors.
- `MATCH_CONSTRAINT_WRAP` uses the content's size, capped at the space between
  the anchors. The measurer may be asked about such an axis as
  `matchConstraint`, so check the widget's `mMatchConstraintDefaultWidth` (or
  `mMatchConstraintDefaultHeight`) and report the content's size there too,
  except when it is measured again after a solve (see
  [the measurer](#the-measurer)).
- `MATCH_CONSTRAINT_PERCENT` takes `percent` (0 to 1) of the container's size,
  even when the widget is anchored to siblings. Passing a `percent` between 0
  and 1 with the spread mode switches to this mode.

`min` and `max` bound the result, and 0 means no bound:

```dart
// Stretch between the anchors, but never wider than 120 px.
widget.setHorizontalDimensionBehaviour(.matchConstraint);
widget.setHorizontalMatchStyle(
  ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
  0, // min
  120, // max
  1, // percent, unused by the spread mode
);
```

An aspect ratio derives one axis from the other. It needs at least one
`matchConstraint` axis:

```dart
final video = ConstraintWidget.sizeNamed('video', 320, 0);
video.setVerticalDimensionBehaviour(.matchConstraint);
video.setDimensionRatioString('16:9'); // width:height, so 320 x 180
video.connect(.left, root, .left);
video.connect(.top, root, .top);
```

When both axes are `matchConstraint`, prefix the side to compute: `'H,16:9'`
derives the height from the width, `'W,16:9'` the width from the height.
`setDimensionRatio(ratio, side)` is upstream's numeric form.

### Chains

Widgets linked to each other in both directions along an axis form a chain:
`a.right` to `b.left` and `b.left` to `a.right`. The first widget (leftmost or
topmost) is the chain head and holds the chain's settings. When the container
is right-to-left (`setRtl(true)`), the rightmost widget heads a horizontal
chain.

- **Style.** `setHorizontalChainStyle` (or `setVerticalChainStyle`) on the head
  takes `ConstraintWidget.CHAIN_SPREAD` (the default: equal gaps at both ends
  and between the widgets), `CHAIN_SPREAD_INSIDE` (the first and last widgets
  sit against the chain's anchors, the rest spread between them), or
  `CHAIN_PACKED` (the widgets stay together, placed by the head's bias).
- **Weights.** `matchConstraint` members share the leftover space, equally by
  default or in proportion to `setHorizontalWeight` / `setVerticalWeight`:

```dart
final a = ConstraintWidget.sizeNamed('a', 0, 20);
final b = ConstraintWidget.sizeNamed('b', 0, 20);
a.setHorizontalDimensionBehaviour(.matchConstraint);
b.setHorizontalDimensionBehaviour(.matchConstraint);
a.connect(.left, root, .left);
a.connect(.right, b, .left);
b.connect(.left, a, .right);
b.connect(.right, root, .right);
a.setHorizontalWeight(1);
b.setHorizontalWeight(3);
root.addAll([a, b]);
// In a 400 px wide container, a is 100 px wide and b is 300 px.
```

### Guidelines and barriers

Both are invisible helpers that other widgets constrain to. Add them to the
container like any other widget.

```dart
// A vertical line a quarter of the way across the container.
final guide = Guideline()
  ..setOrientation(Guideline.vertical)
  ..setGuidePercent(0.25);

// A vertical line along the right edge of whichever label reaches furthest.
final barrier = Barrier()
  ..setBarrierType(Barrier.right)
  ..add(nameLabel)
  ..add(emailLabel);

root.addAll([guide, barrier]);
nameLabel.connect(.left, guide, .left);
emailLabel.connect(.left, guide, .left);
field.connect(.left, barrier, .right, 8);
```

A `Guideline` sits at a fixed distance from the container's left or top edge
(`setGuideBegin`) or its right or bottom edge (`setGuideEnd`), or at a
fraction of its size (`setGuidePercent`). A `Guideline.vertical` guideline is a
vertical line, so widgets constrain their `left` or `right` anchors to it, and
a `Guideline.horizontal` one takes `top` and `bottom`. A `Barrier` follows the
outermost `left`, `right`, `top`, or `bottom` edge of the widgets added to it,
offset by `setMargin`.

### Visibility and gone margins

`setVisibility` takes `ConstraintWidget.VISIBLE`, `INVISIBLE`, or `GONE`. An
invisible widget keeps its space (the engine draws nothing either way). A gone
widget collapses to 0 x 0, its own margins stop applying, and widgets
constrained to it switch to their gone margin, if they have one:

```dart
a.connect(.left, root, .left, 10);
b.connect(.left, a, .right, 8);
b.setGoneMargin(.left, 32); // after connect: connecting resets it

a.setVisibility(ConstraintWidget.GONE);
root.layout();
// a collapses at the container's left edge, so b.getX() is 32.
// With a visible, b.getX() is 10 + a's width + 8.
```

### The measurer

`Measurer.measure(widget, measure)` is how the engine learns content sizes.
The `Measure` carries the request:

- `horizontalBehavior` and `verticalBehavior`: how each axis is being
  measured. The engine may pass a behaviour that differs from the widget's
  own, for example `fixed` for a `matchConstraint` axis it has already
  resolved.
- `horizontalDimension` and `verticalDimension`: the size the engine proposes.
  On a `wrapContent` axis it is not a limit: it holds the widget's stored size
  or 0.
- `measureStrategy`: `Measure.SELF_DIMENSIONS`, `TRY_GIVEN_DIMENSIONS`, or
  `USE_GIVEN_DIMENSIONS`, the measure strategies of upstream's `BasicMeasure`.

Write the answer to `measuredWidth`, `measuredHeight`, `measuredBaseline`, and
`measuredHasBaseline`. The engine reuses its `Measure` objects across calls,
so set all four every time. Report the content's natural size on
`wrapContent` axes (and on `MATCH_CONSTRAINT_WRAP` axes), and echo the
proposed size on the others.

After the solver has run, `layout()` measures some children again (see
[how resolution works](#how-resolution-works)), first with
`TRY_GIVEN_DIMENSIONS` and then with `USE_GIVEN_DIMENSIONS`. On those passes
the proposed size of a `MATCH_CONSTRAINT_WRAP` axis is the solver's, capped by
the anchors and by the min and max. Measure the content at that size, so that
content that reflows, such as wrapping text, sizes its other axis there.
Android's measurer does so on `USE_GIVEN_DIMENSIONS`, and on
`TRY_GIVEN_DIMENSIONS` once the other axis is stable (the content's last
measured size on it is the widget's current size); until then it measures the
content again.

`Flow` and `GridCore` are virtual layouts: helpers that arrange the widgets
added to them into wrapping rows or columns, or into a grid. They size
themselves, and work out how to arrange their widgets, in a measure pass of
their own that only your measurer can run: under the default measurer their
widgets are left unplaced. Call their
`measure(widthMode, widthSize, heightMode, heightSize)` with
`BasicMeasure.EXACTLY` and the proposed size on a `fixed` axis, and
`BasicMeasure.AT_MOST` and the space available to the layout (here
`availableWidth` and `availableHeight`, for example the container's size) on
the others, then report `getMeasuredWidth()` and `getMeasuredHeight()`:

```dart
if (widget is VirtualLayout) {
  final fixedW = measure.horizontalBehavior == DimensionBehaviour.fixed;
  final fixedH = measure.verticalBehavior == DimensionBehaviour.fixed;
  widget.measure(
    fixedW ? BasicMeasure.EXACTLY : BasicMeasure.AT_MOST,
    fixedW ? measure.horizontalDimension : availableWidth,
    fixedH ? BasicMeasure.EXACTLY : BasicMeasure.AT_MOST,
    fixedH ? measure.verticalDimension : availableHeight,
  );
  measure.measuredWidth = widget.getMeasuredWidth();
  measure.measuredHeight = widget.getMeasuredHeight();
  measure.measuredBaseline = 0;
  measure.measuredHasBaseline = false;
  return;
}
```

The virtual layout then measures the widgets added to it through the same
measurer.

`didMeasures()` marks the end of a batch of measures on the `measure(...)`
entry point described below; `layout()` does not call it, and an empty body
is typical.

## How resolution works

`layout()` resolves in up to two stages:

1. **Dependency graph.** Each edge and dimension becomes a node that depends
   on others: a left edge on its target plus the margin, a match-constraint
   width on both of its edges. The graph measures the children, then resolves
   the nodes in dependency order. Most layouts finish here.
2. **Cassowary solver.** When the graph cannot resolve a layout faithfully,
   `layout()` restores the widget state from before the graph pass,
   re-measures wrap-sized children, and solves the layout as a system of
   linear equations and inequalities with the ported `LinearSystem`. The
   solver gets the same input upstream's solver would. A child whose content
   size on one axis depends on a size the solver set on the other (a
   `matchConstraint` axis, or a `MATCH_CONSTRAINT_WRAP` axis the solver
   capped) is then measured again at that size, and the layout is solved
   again if a size changed, as upstream's `BasicMeasure.solverMeasure` does.

The graph declines, and hands the whole layout to the solver, for chains with
`GONE` or ratio-sized members, chains along a `wrapContent` axis of the
container, `MATCH_CONSTRAINT_WRAP` widgets, circular constraints, nested
containers, widgets centered between two anchors along a `wrapContent` axis,
wrap results whose children overflow the computed bounds, wrap results larger
than the container's `setMaxWidth` or `setMaxHeight`, and virtual layouts.
It also hands over any layout it leaves partly unresolved, which currently
includes every layout that contains a `Barrier`: the graph tracks only the
barrier's position.

Upstream works the other way around: its default path is the solver, with the
graph as an optional optimization. The graph is the cheaper path. The bundled
[resolver benchmark](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/constraint_engine/benchmark/resolver_benchmark.dart)
times both on generated screens of increasing size, and a solver-routed screen
takes ten or more times as long as a graph-resolved one (run it with
`dart run benchmark/resolver_benchmark.dart`).

`ConstraintWidgetContainer.measure(...)` is upstream's `onMeasure`-style entry
point (it runs `BasicMeasure.solverMeasure`). It is kept for parity and many of
the ported tests use it, but `layout()` is the simpler entry and the one
flutter_constraint_layout calls. `setOptimizationLevel` and the `Optimizer`
constants are ported as well; they tune the solver and the `measure(...)`
path, but `layout()` always tries the graph first, whatever the level.

## API style

The API deliberately mirrors upstream's Java API: the same class names
(`ConstraintWidget`, `ConstraintWidgetContainer`, `ConstraintAnchor`,
`Guideline`, `Barrier`, `Flow`, `GridCore`, `LinearSystem`, `BasicMeasure`),
the same method names (`connect`, `setHorizontalDimensionBehaviour`,
`setHorizontalMatchStyle`, `setGuidePercent`), Java-style getters such as
`getX()` and `getWidth()`, upstream's integer constants
(`ConstraintWidget.MATCH_CONSTRAINT_SPREAD`, `ConstraintWidget.GONE`,
`BasicMeasure.EXACTLY`), and upstream's public `m`-prefixed fields. Upstream
documentation, tests, and code therefore translate almost line by line.

The differences come from Dart. Named constructors replace overloads
(`ConstraintWidget.size`, `.rect`, `.named`, `.sizeNamed`), nested Java enums
become top-level Dart enums (`ConstraintAnchor.Type.LEFT` is
`ConstraintAnchorType.left`, and
`ConstraintWidget.DimensionBehaviour.MATCH_CONSTRAINT` is
`DimensionBehaviour.matchConstraint`), the `Guideline` and `Barrier`
constants are lower case (`Guideline.vertical`, `Barrier.left`), a few
overloads get their own names (`connectAnchors`, `setDimensionRatioString`,
`setGuidePercentInt`), and `double` replaces `float`. The
[porting guide](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/constraint_engine/test/PORTING_GUIDE.md)
maps each of these.

The library also exports the solver's building blocks (`LinearSystem`,
`ArrayRow`, `SolverVariable`, `ChainHead`, and the rest), which the ported
solver tests exercise directly.

## Relation to upstream

The port is pinned to upstream commit
[`9cd4b5a`](https://github.com/androidx/constraintlayout/tree/9cd4b5a4079a14175f91dc897abd83270799364a),
the final commit of the androidx/constraintlayout GitHub repository (core
1.1.0-alpha04). Development has since moved to the AOSP androidx monorepo. The
widget model, the dependency-graph resolver, and the solver are at parity with
the released core 1.1.1: the one upstream change to them since the pin is
applied here. `GridCore` still follows the pinned commit, which the released
core has changed since (its flags, for example, became a bitmask).

- **Ported:** the widget model and the dependency-graph resolver (`widgets/`
  and `widgets/analyzer/`), the `LinearSystem` solver and its supporting
  classes, and the virtual layouts (`VirtualLayout`, `Flow`, and
  `utils/GridCore`).
- **Not ported:** MotionLayout (`motion/`); the `parser/`, `dsl/`, and
  `state/` layers behind JSON constraint sets and Jetpack Compose
  (flutter_constraint_layout plays that role here); `utils/GridEngine`, which
  `GridCore` does not use; `Placeholder`; the `Direct` and `Grouping`
  optimizers (the graph-first entry plays their role); and `Metrics`.

Upstream's core unit tests for the ported code are ported to Dart under
[`test/`](https://github.com/BirjuVachhani/flutter_constraint_layout/tree/main/packages/constraint_engine/test),
keeping upstream's class and method names.
[UPSTREAM.md](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/constraint_engine/UPSTREAM.md)
maps each upstream test class to its Dart file and lists the ones left out,
each with its reason. It also records the pinned revision, the parity check,
and every intentional divergence, such as `double` arithmetic where upstream
uses 32-bit `float` (which moves a few test values by 1 to 2 px) and the
graph-first entry point.

## License

BSD 3-Clause License, Copyright (c) 2026, Birju Vachhani.

The files under `lib/src/`, and the tests ported from upstream's core test
suite (with their `test/support/` classes), are a Dart port of
androidx.constraintlayout core, Copyright (C) The Android Open Source Project,
and carry `SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause`: the upstream portions
remain under the Apache License, Version 2.0, and the modifications are under
the BSD 3-Clause License. The
[LICENSE](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/constraint_engine/LICENSE)
file contains both licenses.
