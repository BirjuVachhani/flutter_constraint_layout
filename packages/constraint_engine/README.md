# constraint_engine

The layout engine of Android's ConstraintLayout, in pure Dart. You describe
widgets as rectangles and the constraints between their edges, and the engine
works out the position and size of every widget, as Android does. It is a
literal port of Android's layout pipeline: upstream's core library
(`androidx.constraintlayout.core`: the `Direct` pass, the Cassowary-style
`LinearSystem` solver, the dependency graph, the widget model) and the measure
pass of the ConstraintLayout view (`onMeasure`, its child measurer and
`MeasureSpec`), computed in Java's 32-bit float arithmetic. Checked layout by
layout against Android's own Java engine, on nearly 1.5 million distinct
layouts (about 1.9 million runs at Android's default optimization level alone,
through the core and view paths and as Flutter widget trees, and more at its
other levels), it gives the same frames on every one, outside the few cases
where Android itself has no single result (see
[What parity means](#what-parity-means)). No Flutter dependency.

> **Building a Flutter app?** Use
> [flutter_constraint_layout](https://pub.dev/packages/flutter_constraint_layout)
> instead. It is built on this package and provides ConstraintLayout as
> Flutter widgets (`ConstraintLayout`, `Constrained`, `Guideline`, `Barrier`,
> `ConstraintFlow`, `ConstraintGrid`, `ConstraintGroup`), with a debug
> visualizer.

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

There is no default measurer, as upstream has none: `measure()` throws a
`StateError` when a container with children has no measurer. See
[The measurer](#the-measurer) for the full contract.

### 6. Measure and read the result

```dart
root.measure(
  root.getOptimizationLevel(),
  BasicMeasure.EXACTLY,
  root.getWidth(),
  BasicMeasure.EXACTLY,
  root.getHeight(),
  0, 0, 0, 0,
);

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

`measure(level, widthMode, widthSize, heightMode, heightSize, lastWidth,
lastHeight, paddingX, paddingY)` is upstream's entry, the one Android's
`onMeasure` calls: it measures the children, lays the layout out, and measures
again the children whose size depends on the result (see
[How the engine lays out](#how-the-engine-lays-out)). `BasicMeasure.EXACTLY`
with the container's own size measures a fixed-size layout.

Positions are relative to the container's top-left corner, and `getLeft()`,
`getTop()`, `getRight()`, and `getBottom()` give the edges. Sizes, positions,
and margins are integers, in whatever unit your renderer uses. The title's 16
characters measure 128 x 20, so centering it on the 48 px logo puts its top at
16 + (48 - 20) / 2 = 30. The banner is 400 - 16 - 16 = 368 wide.

### Laying out again

The model is persistent: change sizes, constraints, or visibility, then
measure again. As upstream's core, a container measured directly keeps state
from one measure to the next: the final values Direct gave the anchors are
reset only by the next Direct pass, a size override the solver left pending is
applied by the next solve, and a `fixed` axis keeps the size a solve widened
it to. Set your fixed sizes again (for example with `setDimension(width,
height)`) before measuring, as Android's layout params do. To get exactly what
Android gives on every measure, measure through `ViewHost` (next section),
which first resets every child's measure state as Android's view layer does.

The full example also builds a chain and a biased widget, then widens the
container and measures it again. In a checkout of the repository, run it from
`packages/constraint_engine`:

```sh
dart run example/constraint_engine_example.dart
```

## Android's entry: ViewHost

`ViewHost` is the ConstraintLayout view's `onMeasure` (ConstraintLayout.java,
the dirty path that runs whenever a child requested layout), ported over the
engine. Give it the container and a `ViewMeasurer`, the port of the view's
child measurer, and measure the layout under the `MeasureSpec`s its parent
gives it:

```dart
import 'dart:math' as math;

class LabelViews extends ViewMeasurer {
  LabelViews(this.texts);

  final Map<ConstraintWidget, String> texts;

  // The child view's own onMeasure: the only hook a host implements.
  @override
  ({int width, int height, int baseline}) measureContent(
    ConstraintWidget widget,
    int widthSpec,
    int heightSpec,
  ) {
    final text = texts[widget] ?? '';
    final width = _resolve(text.length * 8, widthSpec);
    final lines = width <= 0 ? 1 : (text.length * 8 + width - 1) ~/ width;
    final height = _resolve(lines * 20, heightSpec);
    return (width: width, height: height, baseline: text.isEmpty ? -1 : 15);
  }

  static int _resolve(int natural, int spec) =>
      switch (MeasureSpec.getMode(spec)) {
        MeasureSpec.EXACTLY => MeasureSpec.getSize(spec),
        MeasureSpec.AT_MOST => math.min(natural, MeasureSpec.getSize(spec)),
        _ => natural,
      };
}

final host = ViewHost(root, LabelViews({title: 'Pure Dart layout'}));
host.measure(
  MeasureSpec.makeMeasureSpec(400, MeasureSpec.EXACTLY),
  MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED),
);
print('${host.getMeasuredWidth()} x ${host.getMeasuredHeight()}'); // 400 x 120
```

With the container and children of the walkthrough, the frames are the same,
and the layout wraps its height around them under the unbounded height spec:
120. Before every measure the host does what Android's view layer does:

- it resets every child's measure state as Android's
  `ConstraintWidget.reset()` does before the layout params are applied again
  (`ConstraintWidget.resetMeasureState`), keeping the configuration and what
  `reset()` keeps: the resolved flags, a guideline's and a barrier's own
  flag, `hasBaseline`, the last measure specs and the dependency graph's runs
  and nodes. So a layout measured again carries the same history as
  Android's: at `OPTIMIZATION_STANDARD` none that changes a layout, but
  without `OPTIMIZATION_DIRECT` a barrier that `allSolved` resolved stays at
  0 from its second measure on, and at the `OPTIMIZATION_GRAPH` levels the
  graph is wired from what its last run left (see `UPSTREAM.md`, "Android's
  dirty measure");
- it makes every `Guideline` and `Barrier` GONE, as Android's view helpers
  always are (they report 0 x 0, and a link into one uses its gone margin);
- it marks the members of each virtual layout, and rebuilds every anchor's
  dependents from the links the widgets hold, in the order Android's
  `setChildrenConstraints` makes them (`rebuildViewDependents`);
- it marks the children a baseline link needs the baseline of.

Then it sets the container's behaviours, size, minimum and maximum from the
specs and from the host's own `paddingLeft`, `paddingTop`, `paddingRight`,
`paddingBottom`, `minWidth`, `minHeight`, `maxWidth` and `maxHeight` (the
layout view's), measures it at `optimizationLevel` (`OPTIMIZATION_STANDARD` by
default) and resolves the layout's measured size, with Android's
`MEASURED_STATE_TOO_SMALL` bit when a wrap-content axis did not fit
(`measuredWidthAndState`). Read the children's
frames from the widgets afterwards: `getX()` and `getY()` include the padding.
A child the host has to keep in sync across measures, as the Flutter adapter
does, is configured in place: change its links, sizes and styles as Android's
layout params would set them, then measure again.

`ViewMeasurer` implements every rule of Android's child measurer, in
Android's order: the child's measure specs from its behaviour and the
measure strategy, the measure cache (`OPTIMIZATION_CACHE_MEASURES`), the GONE
and both-spread short cuts, the match-constraint minimum and maximum (with a
second measure of the view when they change a size), the ratio branch without
`OPTIMIZATION_DIRECT`, the baseline and `measuredNeedsSolverPass` rules. It
keeps each child view's measured size and baseline between measures, as a
`View` does. A `VirtualLayout` child is measured through its own `measure`.
Set `transcript` to a `StringBuffer` to record every measure request in the
parity oracle's format.

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
  not center a widget: as on Android, it lays out at (0, 0). Use the anchor
  pairs or `centerX` and `centerY` instead.
- **Baselines.** `connect(.baseline, other, .baseline)` aligns two widgets'
  text baselines. Both widgets must already have a baseline when you connect
  them (`setBaselineDistance` with a positive value), or the connection is
  ignored. A measurer reports baselines as well, because the engine copies
  `measuredBaseline` and `measuredHasBaseline` onto the widget after every
  measure.

### Dimension behaviours

| `DimensionBehaviour` | Size along that axis |
| --- | --- |
| `fixed` (default) | The stored size, from the constructor, `setWidth`, `setHeight`, or `setDimension`. |
| `wrapContent` | The content's natural size, as reported by the measurer. |
| `matchConstraint` | Derived from the constraints, according to the match-constraint mode (below). |
| `matchParent` | The container's size minus the widget's margins on that axis. |

A `wrapContent` container sizes itself around its children: measure it with
`BasicMeasure.AT_MOST` (or `UNSPECIFIED`) on that axis, or through
`ViewHost` with an `AT_MOST` or `UNSPECIFIED` spec, and read its size
afterwards.

### Match-constraint modes

`setHorizontalMatchStyle(mode, min, max, percent)` and
`setVerticalMatchStyle(...)` choose how a `matchConstraint` axis is sized. The
modes are `ConstraintWidget` constants:

- `MATCH_CONSTRAINT_SPREAD` (the default) fills the space between the anchors.
- `MATCH_CONSTRAINT_WRAP` uses the content's size, capped at the space between
  the anchors.
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
`setDimensionRatio(ratio, side)` is upstream's numeric form. The ratio is held
as Java's float quotient of its two parts.

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
a `Guideline.horizontal` one takes `top` and `bottom`. Orient a guideline
before linking to it: a guideline is horizontal until oriented, so a link into
the `left` or `right` of an unoriented one finds no anchor and is dropped. A
`Barrier` follows the outermost `left`, `right`, `top`, or `bottom` edge of the
widgets added to it, offset by `setMargin`. Measured through `ViewHost`, both
are GONE widgets of size 0 x 0, as on Android.

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
// After a measure, a collapses at the container's left edge, so b.getX()
// is 32. With a visible, b.getX() is 10 + a's width + 8.
```

### The measurer

`Measurer.measure(widget, measure)` is how the engine learns content sizes,
the core library's contract that upstream's own tests implement. The
`Measure` carries the request:

- `horizontalBehavior` and `verticalBehavior`: how each axis is being
  measured. The engine may pass a behaviour that differs from the widget's
  own: `fixed` for an axis Direct or the solver has already resolved, or
  `wrapContent` for a spread `matchConstraint` axis with fewer than two links.
- `horizontalDimension` and `verticalDimension`: the size the engine proposes.
  On a `wrapContent` axis it is not a limit: it holds the widget's stored size
  or 0.
- `measureStrategy`: `Measure.SELF_DIMENSIONS` for a measure before a solve,
  `TRY_GIVEN_DIMENSIONS` and `USE_GIVEN_DIMENSIONS` for the re-measures after
  one, the measure strategies of upstream's `BasicMeasure`.

Write the answer to `measuredWidth`, `measuredHeight`, `measuredBaseline`, and
`measuredHasBaseline`, and set `measuredNeedsSolverPass` when the answer
differs from the proposed size and the layout should be solved again. The
engine reuses its `Measure` objects across calls (`BasicMeasure.mMeasure`, and
the one of the Direct pass), so set every output on every call; an output you
leave is the previous request's, as on Android. The engine copies the answer
onto the widget (`setWidth`, `setHeight`, `setHasBaseline`,
`setBaselineDistance`).

What else a measurer does is up to it, and decides whether the result is
Android's. Android's child measurer turns each request into measure specs,
keeps every size within the widget's match-constraint minimum and maximum
(measuring the view again when that changes a size), asks for a
`MATCH_CONSTRAINT_WRAP` axis's content again after a solve until the other
axis is stable, and answers repeated similar requests from its cache. To get
Android's results, extend `ViewMeasurer` and implement its one hook,
`measureContent`, as in the [ViewHost](#androids-entry-viewhost) example, or
copy those rules into your own `Measurer`.

`Flow` and `GridCore` are virtual layouts: helpers that arrange the widgets
added to them into wrapping rows or columns, or into a grid. They size
themselves in a measure pass of their own, which only a measurer runs: call
their `measure(widthMode, widthSize, heightMode, heightSize)` with
`BasicMeasure.EXACTLY` and the proposed size on an axis whose size is known
(a `fixed` axis, or a `matchConstraint` axis on a re-measure after a solve),
and `BasicMeasure.AT_MOST` and the space available on the others, then report
`getMeasuredWidth()` and `getMeasuredHeight()`. The virtual layout then
measures the widgets added to it through the same measurer. `ViewMeasurer`
does this itself, from the specs.

A `GridCore` follows the container's direction: in a right-to-left container
its first column is the rightmost, so its cells fill from the right, while the
cell positions in its spans and skips and its column weights still count from
the first column. Upstream's `GridCore` leaves right-to-left unhandled; this
one lays the grid out as the mirror image of its left-to-right layout. Grid
layouts are outside the parity contract: Android's view `Grid` is not core
`GridCore`, so there is no Android result to compare with.

`didMeasures()` marks the end of the first batch of measures of a
`measure(...)` call (upstream's `measureChildren`); an empty body is typical.

## How the engine lays out

`ConstraintWidgetContainer.measure(level, ...)` runs upstream's
`BasicMeasure.solverMeasure` at `level`, which is Android's pipeline:

1. **Dependency graph** (only at the `OPTIMIZATION_GRAPH` levels). When no
   child is in a chain or is a virtual layout and both modes are `EXACTLY`,
   upstream's `DependencyGraph` tries to resolve the whole layout, and when it
   resolves every widget nothing else runs. At `OPTIMIZATION_GRAPH_WRAP` it
   runs whatever the modes, but resolves only the `EXACTLY` axes, and when a
   mode is not `EXACTLY` the solver runs anyway. On an `EXACTLY` axis where
   the container's own behaviour is `wrapContent`, the graph computes the
   container's size itself when its runs allow it. `ViewHost` makes every
   `EXACTLY` axis `fixed`, so through it the graph never computes a wrap
   size.
2. **Measure the children** (`measureChildren`), except those the solver sizes
   on its own (match constraint on both axes) and, at
   `OPTIMIZATION_DIRECT`, those Direct may size.
3. **Pass 0** (`layout()`). At `OPTIMIZATION_DIRECT`, upstream's `Direct`
   pass walks the constraints from the container's edges, its guidelines and
   its barriers, and gives final positions, in whole pixels, to every axis it
   can place without the solver, measuring each widget as soon as both of its
   sizes can be known; then every child it left with a measure request is
   measured. Then the solver: each iteration builds the `LinearSystem` from
   the container and its children (holding what Direct resolved as
   constants), minimizes it, and reads every frame back. It runs again, at
   most 9 times in all, while a frame records a size override (a minimum or a
   maximum changed a solved size), while the container's minimum raises its
   size, and once when a wrap-content axis of the container came out larger
   than the size the pass started from. An exception inside a solve is
   caught and printed (`EXCEPTION : ...`), and the frames are read from what
   was solved, as on Android.
4. **Re-measures** (passes 1 and 2). The virtual layouts with a
   `matchConstraint` axis are measured again (`TRY_GIVEN_DIMENSIONS`), then
   the other `matchConstraint` children twice (`TRY_GIVEN_DIMENSIONS`, then
   `USE_GIVEN_DIMENSIONS`), each round followed by another solve when a size,
   a baseline or a measurer's `measuredNeedsSolverPass` changed.

`layout()` is one of those passes on its own: the Direct pass when the level
has `OPTIMIZATION_DIRECT` and the pass is the first (`setPass(0)`), then the
solver loop, with the sizes the children have by then. Without a measurer it
measures nothing, and Direct resolves only what needs no measure.

Every float in the pipeline is a Java `float`: each operation is one binary32
rounding in Java's evaluation order (`f32`, `fadd`, `fmul` and the rest, in
`jfloat.dart`), each `(int)` cast truncates toward zero, inputs such as biases,
percents and ratios are stored as binary32 values, and a position is read back
from the solver as `(int) (value + 0.5f)`. That is what makes a widget land on
Android's pixel, not one beside it.

### Optimization levels

`setOptimizationLevel` takes a mask of `Optimizer` flags, and the
`optimizationLevel` of `measure(...)` should be the same value:

| Level | Flags | What runs |
| --- | --- | --- |
| 257, `OPTIMIZATION_STANDARD` (the default, as on Android) | `DIRECT`, `CACHE_MEASURES` | Direct, then the solver; `ViewMeasurer` answers repeated similar requests from its cache |
| 0, `OPTIMIZATION_NONE` | none | the solver alone |
| 321 | `STANDARD`, `GRAPH` | the dependency graph first where its rules let it run, else as 257 |
| 449 | `STANDARD`, `GRAPH`, `GRAPH_WRAP` | the same, and the graph also runs when a mode is not `EXACTLY`, on the `EXACTLY` axes, before the solver |
| 64, 192 | `GRAPH` (and `GRAPH_WRAP`) without Direct | the graph first, else the solver alone |

The GRAPH levels are opt-in, as on Android, and at each of them the engine
does exactly what Android does at the same level: the dependency graph is
upstream's, with its rules for when it runs and its results, so those levels
are checked against Android at the same level. They are not a faster default:
on the benchmark screens below, the graph alone (321) takes longer than
Direct and a trivial solve (257). `OPTIMIZATION_BARRIER`, `CHAIN`,
`DIMENSIONS`, `RATIO` and `GROUPS` are read nowhere, upstream included;
`OPTIMIZATION_DEPENDENCY_ORDERING` and `OPTIMIZATION_GROUPING` belong to
passes this port leaves out (their flags are kept for parity).

## What parity means

The engine is checked against upstream's Java engine itself: upstream's core
at the pinned commit, driven by a Java port of the ConstraintLayout view's
measure pass (`VOpDriver`), which a check on real Android views (Robolectric,
the released ConstraintLayout 2.2.1 view layer) matches on every layout that
layout params can express. Both sides replay the same op lists, the exact
sequence of engine calls that builds each layout, and every child's frame and
the layout's size must be equal. The
corpora: R, 319,827 realistic screens from 16 generators (lists, forms,
settings, chat, toolbars, cards, nested layouts; half with barriers); VR2,
the same with text and box content measured through the view path; T2,
470,000 layouts in 15 families that target one mechanism each (percent sizes
with minimums, crossed links, negative edges, odd biases, ratios, chains,
wrap-content containers, gone widgets, circles, Flows, measure specs, in-place
changes); T2core, the 379,995 T2 layouts the core path can run; and A,
360,000 adversarial layouts from 18 generators. At
`OPTIMIZATION_STANDARD`:

| Corpus and path | Compared | Differ | Excluded |
| --- | --- | --- | --- |
| R, `measure()` | 319,827 | 0 (and Direct's state: 0) | none |
| A, `measure()`, frames and printed exceptions | 359,617 | 0 | ND 154, HANG 8, SOE 110, JEXC 111 |
| T2core, `measure()` | 379,995 | 0 (Direct's state: 0) | none |
| VR2, `ViewHost` | 319,827 | 0 (Direct's state 0, measure requests 0) | none |
| T2, `ViewHost` | 469,990 | 0 (Direct's state 0, measure requests 0) | ND 10 |
| Solver trace, 2,000 layouts | 2,000 | 0: every variable, row, pivot, goal update and final value, bit for bit | none |
| FL: 60,000 layouts as real Flutter widget trees, through flutter_constraint_layout | 60,000 | 0 (the dry layout too) | none |

The excluded classes are Android's own limits, counted and reported:

- **ND**: Android's result depends on identity hashes, which order its hash
  sets and differ from launch to launch (found by running the oracle under
  three hash settings). The engine iterates its sets in insertion order, the
  order the oracle's hash setting gives up to ten entries.
- **HANG**: Java never returns (8 layouts). The engine finishes: its bounded
  `ArrayRow.updateFromSystem` and its chain walks stop where Java's loop
  forever (see UPSTREAM.md).
- **SOE**: Java's `Direct` recurses until its stack overflows (110 layouts).
  The engine's guard stops the walk, and the solver lays the layout out.
- **JEXC**: Java throws out of `onMeasure` (111 layouts, a null anchor or
  target in Direct). The engine throws too, on each of them.

At the GRAPH levels, R and T2core at 64, 321, 192 and 449 (core path) and VR2
and T2 at 321, 192 and 449 (view path) differ from Java at the same level on
0 layouts (T2core excludes 168 JEXC at every level: Java's graph throws on a
baseline link from a widget without a baseline, where the engine's guard
leaves the link to the solver). At `OPTIMIZATION_NONE`, R, A, T2core, VR2
and T2 (frames and measure requests) differ on 0 layouts too (A excludes 6
HANG and 1 JEXC), and the solver trace sample is identical event for event.
At those levels T2's 50,000 in-place sequences are compared with Android's
live views instead of Java's fresh builds.

**In place, on Android's live views.** T2's in-place sequences, each state
applied to the same live views (the layout params set again, so every
measure takes Android's dirty path) and to the same engine widgets through
`ViewHost`, differ on 0 at every level checked: 0, 64, 192, 256, 257, 321
and 449, the second layout of each sequence included. The comparison leaves
out the corpus's in-place `bl N 0` and `hbl N 0` ops, which model an earlier
adapter that cleared the baseline flags between states, as neither Android
nor the current adapter does; with them, 70 sequences at 64 and 321, and 79
at 192 and 449, differ (see `UPSTREAM.md`). At 257 the live views lay every
sequence out as a fresh build. At the other levels they keep what
`reset()` keeps, a barrier's resolved flag and the dependency graph's runs
and nodes, so 187, 429, 577, 187, 239 and 386 sequences there (at 0, 64,
192, 256, 321 and 449) end unlike their fresh build, on the live views and
in the engine alike, and 41 (64, 321) and 160 (192, 449) throw a
`NullPointerException` in the graph, which the engine throws too, on the same
sequences and at the same state.

The contract has two more boundaries:

- **A layout measured again in the same container** is compared with
  Android's own second layout, not with a fresh build. On 28 degenerate T2
  layouts Android's second layout differs from its first at 257 (27
  match-constraint x match-constraint Flows, which keep the chain list of the
  previous measure, and one chain whose anchors keep stale solver ids); the
  engine gives Android's second layout on all 28. On one more, Java's second
  layout never returns. At level 0, where a barrier keeps its resolved flag,
  Android's second layout differs from its first on 6,469 VR2 and 1,239 T2
  layouts, and the engine's equals it on every one.
- **Grid layouts** (`GridCore`) are outside the contract (see
  [The measurer](#the-measurer)).

[UPSTREAM.md](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/constraint_engine/UPSTREAM.md)
lists every place where the engine's code differs from upstream's, each with
its reason and the tests that pin it (or a note that none does). None of them
changes a frame on the corpora outside the classes above. Upstream's null
dereferences are kept: where Android's solve throws (on the corpora, and on
links no corpus makes, such as a baseline linked to the top or bottom of a
barrier that Direct does not place), the engine throws at the same
operation, prints the exception as Android does, and reads back Android's
frames. The tools and corpora that check all this are in
[tool/parity](https://github.com/BirjuVachhani/flutter_constraint_layout/tree/main/packages/constraint_engine/tool/parity),
with the commands that rebuild the Java oracle at the pin and rerun every
check.

## Performance

AOT builds on an Apple M4 Mac, medians of three runs.

**Realistic screens.** A sample of 4,781 layouts of the corpus R, each
measured again in its own container:

| Path | Total | Median per layout |
| --- | --- | --- |
| `measure()` at 257 | 34.5 ms | 4.2 us |
| `ViewHost` at 257, with content views | 50.3 ms | 6.0 us |
| `measure()` at 321 | 36.0 ms | 5.9 us |
| `measure()` at 0 (the solver alone) | 192.3 ms | 16.8 us |

The 3,241 layouts that Direct resolves completely take 13.9 ms of the 34.5
(median 3.2 us). The engine's earlier design, which resolved through the
dependency graph first in double arithmetic, took 560.9 ms on the same
layouts; upstream's Java engine on the JVM takes about 31 ms at 257 on a
similar sample of 4,861 layouts.

**Large screens.** The bundled
[resolver benchmark](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/constraint_engine/benchmark/resolver_benchmark.dart)
times stacked rows of 80 x 40 items in a 1080 px wide container, p50 in ms.
"Resolve" measures a persistent container again, "cold" builds the model and
measures it once, and "view" measures through `ViewHost`:

| Widgets | 257, spread-chain rows: resolve / cold / view | 257, rows linked one way: resolve / cold | 321, one way: resolve / cold |
| --- | --- | --- | --- |
| 9 | 0.033 / 0.039 / 0.034 | 0.001 / 0.006 | 0.003 / 0.007 |
| 48 | 0.317 / 0.356 / 0.319 | 0.010 / 0.031 | 0.017 / 0.034 |
| 240 | 0.949 / 1.089 / 0.976 | 0.059 / 0.165 | 0.102 / 0.183 |
| 600 | 3.228 / 3.602 / 3.316 | 0.157 / 0.412 | 0.277 / 0.470 |
| 1,200 | 9.061 / 12.589 / 9.461 | 0.318 / 0.850 | 0.548 / 0.964 |

Chains always go through the solver on Android, so they cost the most. On
the parity tooling's screens of 600 widgets (`tool/parity/bench/rbench6.dart`,
80 x 40 cells in spread chains, or 60 x 40 cells linked one way), the engine
takes 3.2 ms with chains and 0.17 ms without at 257, and upstream's Java
engine on the JVM 5.7 ms and 4.0 ms: Java's `addEquality` scans every variable
for synonyms, which makes a flat screen quadratic, and the engine skips that
scan, which is exact (see UPSTREAM.md). Run the benchmark with:

```sh
dart compile exe benchmark/resolver_benchmark.dart -o /tmp/bench && /tmp/bench AOT
```

Debug builds are slower: the engine checks its invariants in asserts there,
and Dart's JIT does not inline as AOT does.

## API style

The API deliberately mirrors upstream's Java API: the same class names
(`ConstraintWidget`, `ConstraintWidgetContainer`, `ConstraintAnchor`,
`Guideline`, `Barrier`, `Flow`, `GridCore`, `LinearSystem`, `BasicMeasure`),
the same method names (`connect`, `setHorizontalDimensionBehaviour`,
`setHorizontalMatchStyle`, `setGuidePercent`), Java-style getters such as
`getX()` and `getWidth()`, upstream's integer constants
(`ConstraintWidget.MATCH_CONSTRAINT_SPREAD`, `ConstraintWidget.GONE`,
`BasicMeasure.EXACTLY`), and upstream's public `m`-prefixed fields. Upstream
documentation, tests, and code therefore translate almost line by line. The
view-layer port follows Android's names too: `ViewHost` is the
ConstraintLayout view, `ViewMeasurer` its child measurer, `MeasureSpec`
Android's `View.MeasureSpec`.

The differences come from Dart. Named constructors replace overloads
(`ConstraintWidget.size`, `.rect`, `.named`, `.sizeNamed`), nested Java enums
become top-level Dart enums (`ConstraintAnchor.Type.LEFT` is
`ConstraintAnchorType.left`, and
`ConstraintWidget.DimensionBehaviour.MATCH_CONSTRAINT` is
`DimensionBehaviour.matchConstraint`), the `Guideline` and `Barrier`
constants are lower case (`Guideline.vertical`, `Barrier.left`), a few
overloads get their own names (`connectAnchors`, `setDimensionRatioString`,
`setGuidePercentInt`, `ConstraintWidgetContainer.measureWidget`), and a Java
`float` is a Dart `double` that holds a binary32 value. The
[porting guide](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/constraint_engine/test/PORTING_GUIDE.md)
maps each of these.

The library also exports the solver's building blocks (`LinearSystem`,
`ArrayRow`, `SolverVariable`, `ChainHead`, and the rest), which the ported
solver tests exercise directly, and `f32` and `fsub` from the float layer.

## Relation to upstream

The port is pinned to upstream commit
[`9cd4b5a`](https://github.com/androidx/constraintlayout/tree/9cd4b5a4079a14175f91dc897abd83270799364a),
the final commit of the androidx/constraintlayout GitHub repository (core
1.1.0-alpha04, ConstraintLayout 2.2.0-alpha04). Development has since moved to
the AOSP androidx monorepo. The ported scope is at parity with the released
core 1.1.1 and ConstraintLayout 2.2.1: the one later change to the solver and
the widgets, a pool-size fix, is applied, `GridCore` follows the released
file, and the released view layer is code-identical to the pinned one on API
17 and later.

- **Ported:** the widget model, the dependency graph and the `Direct` pass
  (`widgets/` and `widgets/analyzer/`), the `LinearSystem` solver and its
  supporting classes, the virtual layouts (`VirtualLayout`, `Flow`, and
  `utils/GridCore`), `utils/GridEngine` (a standalone grid cell-placement
  class that `GridCore` does not use), and from the view layer
  (`ConstraintLayout.java`) the measure pass of `onMeasure`, its child
  `Measurer`, `setChildrenConstraints`' anchor state and Android's
  `View.MeasureSpec` helpers.
- **Not ported:** MotionLayout (`motion/`); the `parser/`, `dsl/`, and
  `state/` layers behind JSON constraint sets and Jetpack Compose
  (flutter_constraint_layout plays that role here); `Placeholder`; the
  `Grouping` pass and dependency ordering; `Direct.solveChain`, which is dead
  upstream; and `Metrics`.

Every upstream core unit test for the ported code is ported to Dart under
[`test/`](https://github.com/BirjuVachhani/flutter_constraint_layout/tree/main/packages/constraint_engine/test),
with its whole upstream body and upstream's class and method names, and every
active one passes with upstream's own assertions (a `closeTo` only where
upstream's `assertEquals` has a delta).
[UPSTREAM.md](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/constraint_engine/UPSTREAM.md)
maps each upstream test class to its Dart file and lists the out-of-scope
ones, each with its reason. It also records the pinned revision and every
place where the code differs from upstream's.

## License

BSD 3-Clause License, Copyright (c) 2026, Birju Vachhani.

The files ported from upstream, under `lib/src/` and among the tests ported
from upstream's core test suite (with their `test/support/` classes), are a
Dart port of androidx.constraintlayout (Copyright (C) The Android Open Source
Project) and carry `SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause`:
the upstream portions remain under the Apache License, Version 2.0, and the
modifications are under the BSD 3-Clause License. Each file's header names its
license. The
[LICENSE](https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/packages/constraint_engine/LICENSE)
file contains both licenses.
