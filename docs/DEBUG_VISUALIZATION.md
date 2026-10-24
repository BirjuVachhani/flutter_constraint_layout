# Debug Visualization for ConstraintLayout: `debugShowChains` and `debugShowBlueprint`

## Status: implemented (2026-07-25)

> This is the feature's original spec and build log, kept as a design
> reference. It was written when the Flutter package was the repository root
> and was still named `constraint_layout`, so:
>
> - Paths such as `lib/`, `test/`, `example/`, and `README.md` are relative to
>   `packages/flutter_constraint_layout/`. Paths that start with `packages/`,
>   `website/`, or `docs/` are relative to the repository root.
> - The package's entry library, `lib/constraint_layout.dart` in the text, is
>   now `lib/flutter_constraint_layout.dart`.
> - Test counts are as of 2026-07-25. At the 1.0.0 release the package suite
>   has 173 tests and the engine suite 350 passing plus 1 skipped.
> - `playground/` was a local, git-ignored scratch app. It no longer exists;
>   the Playground entry below says where its role lives now.

All phases below are complete. Final layout of the feature:

- `lib/src/debug/`: `debug_scene.dart`, `debug_extractor.dart`,
  `debug_palette.dart`, `debug_painter.dart` (not exported from the package
  entry; the public API is the four `ConstraintLayout` params, the static
  `ConstraintLayout.allowDebugFlags` added afterwards, and `DebugLabelStyle`
  in `types.dart`).
- `RenderConstraintLayout` gained four paint-only setters, the
  `debugDescribeScene()` bridge, and the `paint()` restructure (built
  assert-gated; now gated by `allowDebugFlags`, see the last divergence below).
- Tests: `test/debug/` holds 37 tests (palette 3, extractor 16, painter
  geometry 6, painter goldens 8, repaint/e2e 4) with goldens under
  `test/debug/goldens/`. Full adapter suite: 98 tests green; engine suite
  untouched (276 pass, 1 skip).
- Playground: the toggles were wired into every scenario of `playground/`, the
  scratch app, through `playground/lib/debug_options.dart` and app-bar
  buttons. That app has since been deleted. The website's live examples fill
  its role now: the live examples on the home page (the real-world examples
  and the feature previews) have "chains" and "blueprint" toggles in their
  preview headers (`website/lib/src/widgets/live_example.dart`), and the docs
  page has a live example for every layout feature. The package's runnable
  example is `example/main.dart`.

Minor divergences from the spec text, chosen during implementation:

- The per-edge anchor circles (the solid/hollow dots at each left/right/top/
  bottom midpoint, and their blueprint halo) are not painted. In Android Studio
  those circles are the interactive handles you drag to attach a constraint;
  this overlay is read-only, so they carry no meaning and only add noise. The
  baseline pill is kept, since it marks where a baseline-aligned child sits
  rather than being a drag target. The anchor sections below describe the
  original Android rendering and are retained as reference only.
- The spring's destination end cap is a centered perpendicular tick at the
  endpoint (length 9 to the parent, 5 to a sibling) rather than offset by the
  upstream gap constants; visually equivalent at 1 px stroke.
- Circular connections draw their small arrow at the source end. The spec's
  `{radius}px @ {angle}deg` midpoint label is not painted: with several hub
  spokes the labels overlap into an unreadable pile, and the dashed spoke plus
  the child's own position already convey the relationship.
- The golden harness paints scenes through a `CustomPaint.foregroundPainter`
  so the opaque base does not cover the overlay.
- Changed after implementation (2026-07-26): the overlay is no longer
  assert-gated. `paint()` honors the flags when the static
  `ConstraintLayout.allowDebugFlags` is true. It defaults to `kDebugMode`, so
  the overlays work in debug builds and are inert in profile and release unless
  an app opts in, as the website does to show them in its release build.
  Opting in keeps the overlay code in the release binary. Locked decision 4,
  the `paint()` code in section 5.3, and the README note in Phase 7 describe
  the original assert-gated design.

The rest of this document is the original implementation spec, kept as the
feature's design reference.

This document is a complete, self-contained implementation spec. An agent with no
prior context should be able to implement the whole feature, including tests, from
this document alone. Paths are relative to the Flutter package, which is
`packages/flutter_constraint_layout/` today (see the note at the top). Style
rule for all prose and docs written for this feature: never use em-dashes.

## 1. Context

The package is a Flutter port of Android ConstraintLayout (engine in
`packages/constraint_engine`, adapter in `lib/`). It has feature parity with
upstream but no way to visualize the constraint graph at runtime. Android
Studio's design surface draws constraints as curved lines with arrows, springs
(zigzags) for opposing constraints, interlocking chain-link strokes for chains,
margin value labels, anchor circles, dashed guidelines, and barrier fade lines.
It also has a "blueprint" mode: real widgets are not painted; instead each is a
translucent box with a border and label on a dark teal surface.

We replicate that rendering with two flags on the `ConstraintLayout` widget.
The rendering algorithms and palette below were extracted verbatim from the
Android Studio source (JetBrains/android GitHub mirror of AOSP
`platform/tools/adt/idea`, files `DrawConnection.java`,
`DrawConnectionUtils.java`, `FancyStroke.java`, `DrawAnchor.java`,
`DrawBarrier.java`, `DrawVerticalGuideline.java`, `BlueprintColorSet.java`,
`AndroidColorSet.java`, `ConstraintLayoutDecorator.java`,
`DrawNlComponentFrame.java`, `DrawTextRegion.java`). All values are logical
pixels.

## 2. Locked user decisions

1. `debugShowChains: bool` paints the overlay ON TOP of normally painted
   children. `debugShowBlueprint: bool` does NOT paint children; it paints the
   blueprint surface instead. Both flags also draw guidelines and barriers.
2. `debugChainColor: Color?` tints ALL overlay lines (constraints, chains,
   springs, guidelines, barriers, frames). Null means authentic Android Studio
   palette (blueprint palette in blueprint mode, design-surface palette in
   chains mode). The blueprint background color stays authentic even when
   tinted.
3. `debugBlueprintLabelStyle: DebugLabelStyle` with enum values exactly
   `{ id, label, both, none }`. `id` = the child's Symbol id, `label` = the
   child widget's runtimeType, `both` = id with runtimeType below (default),
   `none` = no text.
4. Debug builds only: every bit of overlay work runs inside
   `assert(() { ...; return true; }())` so it is tree-shaken from profile and
   release builds. The params exist in all modes but are inert outside debug.
5. Hard modularity requirement: `lib/src/constraint_layout.dart` must stay as
   clean as possible. All visualization logic lives in a new `lib/src/debug/`
   module. The render object only stores params and calls one entry point.
6. When both flags are true, blueprint wins (blueprint already includes all
   chain/constraint drawing). `hitTestChildren` stays unchanged in blueprint
   mode (children remain laid out and interactive).

## 3. Codebase reference (verified facts)

### 3.1 Adapter: `lib/src/constraint_layout.dart` (~969 lines)

- `ConstraintLayout` widget: `const ConstraintLayout({super.key, this.textDirection, super.children})`,
  extends `MultiChildRenderObjectWidget`. `createRenderObject` at line ~34,
  `updateRenderObject` at ~39. New params thread: widget field ->
  `createRenderObject` -> `updateRenderObject` -> render-object setter. The
  `textDirection` setter at ~79-86 is the pattern: guard equality, then mark.
  Debug setters must call `markNeedsPaint()` only and must NOT touch
  `_needsModelRebuild` or any dirty flags.
- `RenderConstraintLayout` internal state (all library-private):
  - `ConstraintWidgetContainer? _container` (the engine root).
  - `List<RenderBox> _modelChildren`, `List<ConstraintParentData> _modelChildData`,
    `List<ConstraintWidget> _modelWidgets`: three INDEX-ALIGNED lists. This is
    the only engine-widget-to-child mapping (the engine has no companion
    field).
  - `Map<Symbol, ConstraintWidget> _byId`.
  - Existing `@visibleForTesting` members: `debugLayoutPasses`,
    `debugModelBuilds`, `debugEnginePasses`, `debugFastPasses`,
    `debugConfigApplies`, and `ConstraintWidgetContainer? get debugEngineContainer`.
- `paint()` (lines ~786-793) is currently exactly:

```dart
@override
void paint(PaintingContext context, Offset offset) {
  for (final child in _paintOrder()) {
    final pd = child.parentData! as ConstraintParentData;
    if (pd.visibility != ConstraintVisibility.visible) continue;
    context.paintChild(child, pd.offset + offset);
  }
}
```

  `_paintOrder()` returns children stable-sorted by `zIndex`. There is NO other
  custom painting anywhere in the package (greenfield).
- Solved geometry: engine truth is `_modelWidgets[i].getX()/getY()/getWidth()/getHeight()`
  (ints); mirrored to `pd.offset` for real children. Helper children
  (`pd.helperKind != HelperKind.none`, i.e. guideline/barrier/flow/grid) have
  zero-size child subtrees; their geometry exists ONLY on the engine widget.
- `const Symbol parent = #parent` is the parent sentinel (top-level in
  `constraint_layout.dart`). The engine container `_container` is the engine
  widget for `parent`.
- Dart privacy is per-library, so a new `lib/src/debug/` library cannot read
  `_container` / `_modelWidgets`. The bridge is one new method (section 5.4).
- `ConstraintParentData` (`lib/src/constraint_parent_data.dart`): `Symbol? id`,
  `HelperKind helperKind`, `ConstraintVisibility visibility`, link fields
  (`left/right/start/end: HorizontalLink?`, `top/bottom/baseline: VerticalLink?`,
  `circle: CircularLink?`), `horizontalBias/verticalBias`, `width/height: Dimension`,
  chain style fields, `zIndex`, guideline fields (`guidelineAxis/Begin/End/Percent`),
  barrier fields (`barrierEdge/Referenced/Margin/AllowsGone`), flow/grid config
  fields. Extends `ContainerBoxParentData<RenderBox>` (so `.offset`).
- `lib/src/types.dart` holds the public enums (`ChainStyle`,
  `ConstraintVisibility`, `BarrierEdge`, `HelperKind`, `FlowWrap`, ...). Add
  `DebugLabelStyle` here. `lib/constraint_layout.dart` already exports
  `types.dart`.
- Test pattern (`test/features_test.dart`): `host(children)` wraps in
  `Directionality > Align(topLeft) > SizedBox(800x600) > ConstraintLayout`;
  render object reached via
  `tester.renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout))`.

### 3.2 Engine: `packages/constraint_engine/lib/src/` (port of androidx.constraintlayout.core)

- `ConstraintWidget` (`constraint_widget.dart`):
  - Anchors: `mLeft, mTop, mRight, mBottom, mBaseline, mCenterX, mCenterY, mCenter`
    (all `ConstraintAnchor`). `getAnchor(ConstraintAnchorType)` also exists.
  - Solved geometry: `getX()`, `getY()`, `getWidth()`, `getHeight()`,
    `getLeft()`, `getTop()`, `getRight()`, `getBottom()` (ints).
    `getWidth()/getHeight()` return 0 when GONE.
  - Visibility: `getVisibility()` with constants `ConstraintWidget.VISIBLE = 0`,
    `INVISIBLE = 4`, `GONE = 8`.
  - Chains: `mHorizontalChainStyle` / `mVerticalChainStyle` with constants
    `CHAIN_SPREAD = 0`, `CHAIN_SPREAD_INSIDE = 1`, `CHAIN_PACKED = 2`.
  - Circular: `mCircleConstraintAngle` (double, NaN when unset). The radius is
    stored as the margin of the center connection: read radius via
    `mCenter.getMargin()`, target via `mCenter.getTarget()!.getOwner()`.
  - Baseline: `hasBaseline()`, `getBaselineDistance()` (px from widget top).
  - `getDebugName()/setDebugName()` exist but are unused by the adapter; do not
    rely on them.
- `ConstraintAnchor` (`constraint_anchor.dart`): `getOwner()`, `getType()`
  (enum `ConstraintAnchorType { none, left, top, right, bottom, baseline, center, centerX, centerY }`),
  `getTarget()` (`ConstraintAnchor?`), `isConnected()`, `getMargin()` (returns
  the gone-margin automatically when the target widget is GONE, and 0 when the
  owner is GONE), `mGoneMargin`.
- CRITICAL CHAIN NUANCE: the container's chain bookkeeping
  (`mHorizontalChainsArray`, `ChainHead`) is populated ONLY on the Cassowary
  solver fallback path. On the dependency-graph path (the common case) those
  arrays are EMPTY. Chain detection for visualization MUST be derived from
  anchor topology: a connection `A.right -> B.left` is a chain link iff
  `B.left.getTarget()` points back at `A.right` (bidirectional opposite
  anchors). This is exactly what Android Studio's `ConstraintLayoutDecorator`
  does. Never read the chain arrays.
- RTL: the adapter resolves start/end into engine left/right anchors at
  model-build time. The extractor therefore reads ENGINE anchors and never
  re-derives from parent-data links.
- `Guideline` (`guideline.dart`, extends `ConstraintWidget`): `mOrientation`
  with `Guideline.horizontal = 0` (horizontal line) and `Guideline.vertical = 1`
  (vertical line); resolved position: a vertical guideline reads `getX()`
  (equals `getLeft()`), a horizontal one reads `getY()`. Zero thickness, full
  parent extent on the other axis.
- `Barrier` (`barrier.dart`, extends `HelperWidget`): `mBarrierType` with
  `Barrier.left = 0`, `right = 1`, `top = 2`, `bottom = 3`; after layout it
  collapses to a line (for left/right: `getLeft() == getRight()` is the x; for
  top/bottom: `getTop()` is the y). Referenced widgets: `mWidgets[0..mWidgetsCount)`
  from `HelperWidget`.
- `Flow` / `GridCore` extend `VirtualLayout` extends `HelperWidget`: they are
  positioned widgets with normal solved geometry. GridCore creates PRIVATE
  internal box widgets (`_boxWidgets`) that are added to the container as plain
  `ConstraintWidget`s; grid members' connections target those boxes. Those box
  widgets appear in `container.getChildren()` but NOT in the adapter's
  `_modelWidgets`.
- Container: `_container.getChildren()` returns `List<ConstraintWidget>` of all
  engine children (including grid boxes). `_container.getWidth()/getHeight()`
  is the solved layout size.

## 4. Android Studio rendering spec (replicate exactly)

### 4.1 Connection type classification (from `ConstraintLayoutDecorator`)

Types: `NORMAL, SPRING, CHAIN, CENTER, CENTER_WIDGET, BASELINE, ADJACENT`
(plus our `CIRCULAR`, which Studio handles separately). Selection rules, per
connected anchor:

1. Start with NORMAL.
2. If the OPPOSITE anchor of the same widget is also connected -> SPRING (the
   opposing-constraints / bias case; each side draws its own spring).
   - If both opposite anchors connect to the SAME target widget -> CENTER when
     the two target anchor types differ, CENTER_WIDGET when they are the same
     anchor. (We fold these into one `center` type with a flag.)
3. Chain: a connection whose target anchor's own target points back at the
   source anchor (bidirectional opposite anchors) -> CHAIN. Emit once per pair.
4. If source and destination endpoints are within 4 px -> ADJACENT (drawn with
   the small arrow only).
5. baseline -> baseline connections -> BASELINE.

### 4.2 Drawing constants (logical px)

| Item | Value |
|---|---|
| Normal stroke | 1 px solid |
| Dash pattern (margin drops, center line) | 4 on / 6 off |
| Spring dash (far leg of bias pair) | 4 on / 4 off |
| Guideline / barrier dash | 2 on / 2 off |
| Arrowhead | length 6 along axis, half-width 5 at base (`ARROW_SIDE=6`, `CONNECTION_ARROW_SIZE=5`) |
| Small arrowhead (ADJACENT) | length 4, half-width 3 |
| Bezier control offset | `min(90, manhattanDistance)` |
| Spring zigzag | wavelength 6, amplitude +/-3, straight centered lead-in/out |
| Spring end cap (to parent) | filled rect 1 wide x 9 tall, gap 4 from end |
| Spring end cap (to sibling) | filled rect 1 wide x 5 tall, gap 2 from end |
| Chain link stroke | period 9, link amplitude 2.5, gap segments 9*0.6=5.4 long with amplitude 2.5*0.2, two mirrored passes, inner stroke width 1, round caps |
| Center route corner radius | 10 (`GAP`) |
| Baseline bow | cubic, control points +/-40 vertically |
| Margin label font | Helvetica 12 plain (use default Flutter font; tests render Ahem anyway) |
| Margin end ticks | perpendicular, half-height 5 (total 10) |
| Margin dashed overhang | 20 px (`OVER_HANG`) |
| Anchor circle | diameter 12 (radius 6) |
| Anchor halo | background-colored circle 20% oversize (radius 7.2) under the anchor |
| Unconnected anchor | ring: radius-6 fill in line color, then radius-4.8 punch in background color |
| Baseline anchor | pill: from `x + w/5` to `x + w - w/5`, height 6, corner radius 3, centered on baseline y |
| Guideline chip font | 14, rounded-rect chip, padding 4 |
| Barrier fade | 12 px linear gradient perpendicular to the line, from line color darkened at alpha 0x8F to transparent |
| Widget frame (blueprint) | 1 px solid all edges + fill rect |
| Blueprint label font | ~14 centered (id line), 11 for the runtimeType line in `both` |

### 4.3 Palettes

Blueprint (`BlueprintColorSet.java`):

| Role | Color |
|---|---|
| background | `Color(0xFF225C6E)` |
| frames / constraints / margins | `Color(0xCC86CFE5)` |
| component fill | `Color(0x3386CFE5)` |
| text | `Color(0xFFDCDCDC)` |
| anchor fill | `Color(0xFFFFFFFF)` |

Design surface (chains mode over real UI, `AndroidColorSet.java`):

| Role | Color |
|---|---|
| background | none (transparent, children painted normally) |
| frames / constraints / margins | `Color(0xFFC0C0C0)` (Java `Color.lightGray`) |
| component fill | none |
| text | `Color(0xFF000000)` |
| anchor fill | `Color(0xFF000000)` |

Tinted (when `debugChainColor` != null): all strokes = base color; component
fill = base at alpha `0x33`; anchors = base; text = base darkened 30% in chains
mode / lightened 30% in blueprint mode (use `Color.lerp` with black/white at
t=0.3); blueprint background stays `0xFF225C6E`.

### 4.4 Geometry algorithms

**Normal connection.** Endpoints: source anchor point S with outward unit
direction `ds` (left `(-1,0)`, right `(1,0)`, top `(0,-1)`, bottom `(0,1)`),
destination point D with the destination edge's outward direction `dd`. Let
`m = |S.dx - D.dx| + |S.dy - D.dy|`, `k = min(90, m)`. The arrow occupies the
last `6` px: the curve ends at `D + dd*6` (the arrow base) and the arrowhead
triangle has its apex at D with base corners at `D + dd*6 +/- perp(dd)*5`.
Path:

```
moveTo(S)
cubicTo(S + ds*k,  (D + dd*6) + dd*k,  D + dd*6)
```

Stroke 1 px, then fill the arrow triangle.

**Margin indicator** (drawn when `margin > 0` on a normal/spring connection to
a parent, guideline, or sibling): along the connection axis, the margin span
runs from the destination edge to `destination edge + margin`. Draw:
1. A straight 1 px segment across the margin span, with a gap in the middle for
   the label.
2. The margin value text (integer string) centered in the gap, 12 px font, in
   the margin color.
3. Perpendicular ticks (length 10, centered on the line) at both ends of the
   span.
4. A dashed (4/6) line along the destination edge, extending 20 px beyond the
   connection line on both sides (the "what am I measuring to" line).

**Spring (zigzag).** For a horizontal spring from `x1` to `x2` at height `y`
(vertical is the transpose): `step = 6`, `count = floor(|x2-x1| / step) - 2`
(clamp >= 0), `x = x1 + (|x2-x1| - count*step)/2` (centering). Path:
`moveTo(x1,y); lineTo(x,y);` then `count` times:
`lineTo(x+2, y+3); lineTo(x+4, y-3); lineTo(x+6, y); x += 6;` then
`lineTo(x2,y)`. Stroke 1 px solid. End caps: filled rect 1 wide, 9 tall
(parent) / 5 tall (sibling), positioned at the destination end with gap 4 / 2.
If the widget's bias on that axis differs from 0.5 by more than 0.01, stroke
the LONGER side's zigzag with dash 4/4 instead of solid.

**Chain link stroke.** Given the connection path P (the same cubic as a normal
connection but WITHOUT the arrow inset: end directly at D), build the link
effect with `P.computeMetrics()`:

```
for flip in [-1, +1]:                      # two mirrored passes
  metric = P.computeMetrics().first
  dist = 0; link = true
  start = metric.getTangentForOffset(0)
  out.moveTo(start.position)
  while dist + segLen(link) <= metric.length:
    segLen = link ? 9.0 : 5.4              # 9 * CHAIN_RATIO(0.6)
    next = dist + segLen
    t0 = metric.getTangentForOffset(dist)
    t1 = metric.getTangentForOffset(next)
    link = !link
    sign = link ? 0.2 : 1.0                # after toggle, matching upstream
    amp = 2.5 * sign * flip
    n0 = perpendicular(t0.vector) * amp    # perp = (-dy, dx)
    n1 = perpendicular(t1.vector) * amp
    out.cubicTo(t0.position + n0, t1.position + n1, t1.position)
    dist = next
  out.lineTo(metric.getTangentForOffset(metric.length).position)
```

Stroke `out` with width 1, `StrokeCap.round`, `StrokeJoin.bevel`. The two
mirrored passes interlock into chain links. (Upstream: `FancyStroke.createChain`,
`mSize = 2.5`, `mSpacing = 9`, `CHAIN_RATIO = 0.6`, HALF_CHAIN1 = flip -1,
HALF_CHAIN2 = flip +1.)

**Center connection.** One connection object for the pair. Draw a rounded
orthogonal route from the source widget's edge midpoint out to the target and
back (corner arc radius 10), a dashed (4/6) straight line between the two
opposing anchor points through the widget, and an arrowhead at the destination.
Acceptable simplification if the orthogonal route is ambiguous: draw the two
legs as normal cubic connections plus the dashed center line; visually this
matches Studio closely.

**Baseline connection.** From `(source.center.dx, sourceBaselineY)` to
`(dest.center.dx, destBaselineY)`:
`moveTo(sx, sy); cubicTo((sx, sy-40), (dx, dy+40), (dx, dy))`, 1 px stroke,
plus a 1 px baseline tick inside each widget (from `x + w/5` to `x + w - w/5`
at the baseline y), plus a small arrow pointing down at the destination.

**Circular connection.** Dashed (4/4) straight line from source center to
target center, arrowhead at the source end, and a label `"{radius}px @ {angle}deg"`
at the line midpoint (12 px font).

**Anchors.** For every non-GONE, non-helper widget in both modes, draw at each
of left/right/top/bottom edge midpoints: halo circle radius 7.2 in the
background color (blueprint bg in blueprint mode; skip the halo in chains mode
where there is no flat background), then radius-6 circle in the anchor color if
that anchor `isConnected()`, else the unconnected ring (radius-6 anchor color,
radius-4.8 punch in background color; in chains mode punch with transparent
via `saveLayer` or simply draw a 1.2 px ring stroke instead). If the widget has
a baseline in use (its `mBaseline.isConnected()` or it is a baseline target),
draw the baseline pill.

**Guideline.** Dashed 2/2 1 px line across the full layout at the resolved
position. Chip: rounded rect (corner 6, padding 4) near the leading edge
(8 px from top for vertical, 8 px from left for horizontal) containing
`"{percent}%"` when `guidelinePercent != null` (percent as int), else
`"{begin}"` when `guidelineBegin != null`, else `"end {end}"`. Chip fill =
component fill color, text = text color, 14 px.

**Barrier.** Dashed 2/2 1 px line at the resolved position spanning the full
layout on the barrier's axis. Gradient fade: a rect 12 px deep on the side the
barrier faces (left barrier: fade extends left of the line; right: right; top:
up; bottom: down), filled with a linear gradient from the line color darkened
(multiply RGB by 0.6) at alpha `0x8F` at the line to fully transparent at 12 px.

**Virtual layouts (Flow/Grid).** Draw their solved bounds as a dashed 4/6 1 px
rect in the line color. No fill, no anchors, no label (chains mode); in
blueprint mode also draw the label per `DebugLabelStyle`.

**Blueprint surface.** Paint order: (1) background fill over the whole layout
size; (2) per real widget: component fill rect, then 1 px frame (all four
edges), INVISIBLE widgets at 50% opacity, GONE widgets skipped entirely;
(3) labels per `DebugLabelStyle` centered in the box (id line 14 px, type line
11 px at 80% text alpha below it; if the box is too small for text, skip
text); (4) helpers (guidelines, barriers, virtual bounds); (5) all
connections; (6) anchors. Chains mode paint order: children (already painted),
then helpers, connections, anchors, margin labels.

## 5. Public API and module design

### 5.1 New enum in `lib/src/types.dart`

```dart
/// What text `debugShowBlueprint` draws inside each widget box.
enum DebugLabelStyle {
  /// The child's [Symbol] id, e.g. `avatar`.
  id,

  /// The child widget's runtimeType, e.g. `Text` (Android Studio's class-name
  /// style).
  label,

  /// The id with the runtimeType below it.
  both,

  /// No text.
  none,
}
```

### 5.2 `ConstraintLayout` widget params

```dart
const ConstraintLayout({
  super.key,
  this.textDirection,
  this.debugShowChains = false,
  this.debugShowBlueprint = false,
  this.debugChainColor,
  this.debugBlueprintLabelStyle = DebugLabelStyle.both,
  super.children,
});
```

Doc comments must state: debug-build only (no-op in profile/release), blueprint
wins when both flags are set, `debugChainColor` tints the whole overlay.
`createRenderObject` passes all four; `updateRenderObject` assigns all four.

### 5.3 Render-object members (the ONLY additions besides `paint()` and the bridge)

Four private fields + four setters, each: guard equality, assign,
`markNeedsPaint()`. Nothing touches `_needsModelRebuild`, `configDirty`, or
`structuralDirty`. Suggested names: `_debugShowChains`, `_debugShowBlueprint`,
`_debugChainColor`, `_debugLabelStyle`.

`paint()` becomes:

```dart
@override
void paint(PaintingContext context, Offset offset) {
  var paintChildren = true;
  assert(() {
    if (_debugShowBlueprint) paintChildren = false;
    return true;
  }());
  if (paintChildren) {
    for (final child in _paintOrder()) {
      final pd = child.parentData! as ConstraintParentData;
      if (pd.visibility != ConstraintVisibility.visible) continue;
      context.paintChild(child, pd.offset + offset);
    }
  }
  assert(() {
    if ((_debugShowBlueprint || _debugShowChains) && _container != null) {
      final palette = _debugChainColor != null
          ? DebugPalette.tinted(_debugChainColor!, blueprint: _debugShowBlueprint)
          : _debugShowBlueprint
              ? const DebugPalette.blueprint()
              : const DebugPalette.design();
      paintDebugScene(
        context.canvas,
        offset,
        size,
        debugDescribeScene(),
        palette,
        blueprint: _debugShowBlueprint,
        labelStyle: _debugLabelStyle,
      );
    }
    return true;
  }());
}
```

Note `context.canvas` is read inside the assert AFTER all `paintChild` calls
(the getter re-acquires the canvas, which is required after child compositing).

### 5.4 The privacy bridge

```dart
/// Builds the debug-overlay scene from the current engine state.
///
/// Exposed for tests; also used by [paint] when a debug flag is set.
@visibleForTesting
DebugScene debugDescribeScene() => buildDebugScene(
      container: _container!,
      widgets: _modelWidgets,
      parentData: _modelChildData,
      children: _modelChildren,
    );
```

This is the only seam between the render object and the debug module, and it
matches the existing `debugEngineContainer` pattern. The extractor never
mutates its inputs.

### 5.5 New module files (`lib/src/debug/`, NOT exported from `lib/constraint_layout.dart`)

Tests and `constraint_layout.dart` import them via
`import 'debug/debug_scene.dart';` etc. Keeping them out of the public export
keeps the package API surface to the four widget params + the enum.

## 6. Scene model (`lib/src/debug/debug_scene.dart`)

Pure immutable data, no Flutter painting imports beyond `dart:ui` geometry.

```dart
enum DebugConnectionType { normal, adjacent, spring, center, chain, baseline, circular }

enum DebugEdge { left, right, top, bottom, baseline }

@immutable
class DebugConnection {
  const DebugConnection({
    required this.type,
    required this.sourcePoint,
    required this.targetPoint,
    required this.sourceEdge,
    required this.targetEdge,
    required this.horizontal,     // axis of the connection
    this.margin = 0,
    this.targetIsParent = false,
    this.dashed = false,          // spring far-leg / circular rendering hint
    this.chainStyle,              // ChainStyle, chain type only
    this.centerDashedLine,        // (Offset, Offset)? center type only
    this.circularAngle,
    this.circularRadius,
  });
  final DebugConnectionType type;
  final Offset sourcePoint;
  final Offset targetPoint;
  final DebugEdge sourceEdge;
  final DebugEdge targetEdge;
  final bool horizontal;
  final double margin;
  final bool targetIsParent;
  final bool dashed;
  final ChainStyle? chainStyle;
  final (Offset, Offset)? centerDashedLine;
  final double? circularAngle;
  final double? circularRadius;
}

@immutable
class DebugWidgetBox {
  const DebugWidgetBox({
    required this.rect,
    this.idLabel,
    this.typeLabel,
    this.invisible = false,
    this.virtual = false,        // flow/grid: dashed frame, no fill/anchors
    this.baselineY,              // absolute y, when baseline participates
    this.connectedEdges = const {},   // Set<DebugEdge>
  });
  final Rect rect;
  final String? idLabel;
  final String? typeLabel;
  final bool invisible;
  final bool virtual;
  final double? baselineY;
  final Set<DebugEdge> connectedEdges;
}

@immutable
class DebugGuidelineInfo {
  const DebugGuidelineInfo({required this.vertical, required this.position, required this.chipText});
  final bool vertical;   // vertical line (position is x) vs horizontal (position is y)
  final double position;
  final String chipText;
}

@immutable
class DebugBarrierInfo {
  const DebugBarrierInfo({required this.start, required this.end, required this.fadeDirection});
  final Offset start;
  final Offset end;
  final Offset fadeDirection;   // unit vector pointing away from the line, fade side
}

@immutable
class DebugScene {
  const DebugScene({
    required this.layoutSize,
    required this.boxes,
    required this.connections,
    required this.guidelines,
    required this.barriers,
  });
  final Size layoutSize;
  final List<DebugWidgetBox> boxes;
  final List<DebugConnection> connections;
  final List<DebugGuidelineInfo> guidelines;
  final List<DebugBarrierInfo> barriers;
}
```

Give every class `==`/`hashCode` or keep them identity-based; tests assert on
fields, so identity is fine. Add `toString()`s for test-failure readability.

## 7. Extractor (`lib/src/debug/debug_extractor.dart`)

Signature:

```dart
DebugScene buildDebugScene({
  required ConstraintWidgetContainer container,
  required List<ConstraintWidget> widgets,       // index-aligned
  required List<ConstraintParentData> parentData, // index-aligned
  required List<RenderBox> children,              // index-aligned
});
```

Algorithm:

1. Build `final indexOf = Map<ConstraintWidget, int>.identity()` over `widgets`.
2. `Rect rectOf(ConstraintWidget w) => Rect.fromLTWH(w.getX().toDouble(), w.getY().toDouble(), w.getWidth().toDouble(), w.getHeight().toDouble())`.
   For the container use `Rect.fromLTWH(0, 0, container.getWidth()..., ...)`.
3. Boxes: for each index i where `parentData[i].helperKind == HelperKind.none`
   and `widgets[i].getVisibility() != ConstraintWidget.GONE`:
   - `idLabel`: parse `parentData[i].id` via
     `RegExp(r'Symbol\("(.*)"\)')` on `id.toString()`; null id -> null.
   - `typeLabel`: from `children[i]`: walk `child.debugCreator` if it is a
     `DebugCreator` to the creating element's widget runtimeType; fallback
     `children[i].runtimeType.toString()` with a leading `Render` stripped and
     a leading `_` stripped.
   - `invisible`: `parentData[i].visibility == ConstraintVisibility.invisible`.
   - `baselineY`: `widgets[i].hasBaseline() ? rect.top + widgets[i].getBaselineDistance() : null`,
     only when the baseline anchor participates (connected or has dependents).
   - `connectedEdges`: from `mLeft/mRight/mTop/mBottom/mBaseline.isConnected()`.
   - For flow/grid helpers (`helperKind == .flow || .grid`) emit a box with
     `virtual: true`, labels from id, rect from the engine widget.
4. Connections: for each non-helper widget w (skip guidelines/barriers; DO
   process flow/grid members normally since their anchors target grid boxes or
   flow-created chains):
   - Circular first: if `w.mCenter.isConnected() && !w.mCircleConstraintAngle.isNaN`,
     emit `circular` (source center -> target owner center, angle
     `mCircleConstraintAngle`, radius `mCenter.getMargin()`), and do not also
     emit plain center-anchor connections for this widget.
   - For each of the four side anchors + baseline, when `isConnected()`:
     - Resolve `target = anchor.getTarget()!`, `targetOwner = target.getOwner()`.
     - `targetIsParent = identical(targetOwner, container)`.
     - Chain test: `target.getTarget() == anchor`'s owner-opposite; concretely
       `identical(target.getTarget(), anchor)` after confirming the two anchors
       are opposite types on the same axis. If chain: dedup with a
       `Set<(int, int, bool)>` keyed by the two model indices (sorted) + axis;
       emit once with `chainStyle` read from the chain head. Head finding: walk
       source-side anchors (left/top) while the previous widget's opposite
       anchor also chains back; cap iterations at `widgets.length`; read
       `mHorizontalChainStyle`/`mVerticalChainStyle` (map 0/1/2 to
       `ChainStyle.spread/spreadInside/packed`).
     - Center-pair test (non-chain): both `w.mLeft` and `w.mRight` (or
       `mTop`/`mBottom`) connected to the same `targetOwner`: emit ONE `center`
       connection for the axis (dedup by processing only when iterating the
       left/top anchor), with `centerDashedLine` = the two anchor points.
     - Spring test: opposite anchor connected to a DIFFERENT target: emit
       `spring` for this side. Set `dashed: true` on the side with more free
       space when the axis bias differs from 0.5 by > 0.01 (bias from the
       engine widget, `getHorizontalBiasPercent()/getVerticalBiasPercent()`,
       never from parent data: the adapter mirrors a start/end-linked child's
       horizontal bias in right-to-left layouts, and a flow sets its chain
       heads' bias).
     - Baseline anchors: type `baseline`.
     - Else `normal`; if the endpoints end up within 4 px, downgrade to
       `adjacent`.
     - Endpoints: source point = midpoint of the source widget's edge; target
       point on the target edge:
       - Parent target: perpendicular projection (keep the source's cross-axis
         coordinate, clamp into the parent edge span).
       - Sibling target: source cross-axis coordinate clamped to the target
         edge span; midpoint fallback when the spans do not overlap at all.
     - `margin = anchor.getMargin().toDouble()`.
     - Grid-box targets (`!indexOf.containsKey(targetOwner)` and not the
       container): keep the connection, computing the target rect from the box
       widget's solved geometry (synthesized destination). Do NOT emit a
       `DebugWidgetBox` for grid boxes.
5. Guidelines: for each model index with `helperKind == HelperKind.guideline`,
   read the engine `Guideline` widget: vertical iff
   `mOrientation == Guideline.vertical`; position `getX()` (vertical) or
   `getY()` (horizontal); chip text from parent data:
   `guidelinePercent != null -> '${(p * 100).round()}%'`,
   else `guidelineBegin != null -> '${begin.round()}'`,
   else `'end ${end.round()}'`.
6. Barriers: for each `helperKind == HelperKind.barrier`, line endpoints span
   the container on the barrier's cross axis at the resolved position; fade
   direction from `mBarrierType`: left -> `(-1, 0)`, right -> `(1, 0)`,
   top -> `(0, -1)`, bottom -> `(0, 1)`.
7. Return `DebugScene(layoutSize: container size, ...)`.

GONE handling: GONE widgets get no box; connections from OTHER widgets to a
GONE widget still resolve (the GONE widget has a collapsed solved point and
`getMargin()` on the source anchor already returns the gone-margin).
Connections FROM a GONE widget are skipped along with its box.

## 8. Palette (`lib/src/debug/debug_palette.dart`)

```dart
@immutable
class DebugPalette {
  const DebugPalette({
    required this.background,      // null-like transparent for design mode
    required this.line,            // constraints/chains/springs/guides/barriers/frames
    required this.componentFill,
    required this.text,
    required this.anchor,
  });
  const DebugPalette.blueprint()
      : background = const Color(0xFF225C6E),
        line = const Color(0xCC86CFE5),
        componentFill = const Color(0x3386CFE5),
        text = const Color(0xFFDCDCDC),
        anchor = const Color(0xFFFFFFFF);
  const DebugPalette.design()
      : background = const Color(0x00000000),
        line = const Color(0xFFC0C0C0),
        componentFill = const Color(0x00000000),
        text = const Color(0xFF000000),
        anchor = const Color(0xFF000000);
  factory DebugPalette.tinted(Color base, {required bool blueprint}) { ... }
  ...
}
```

`tinted`: line/anchor = base; componentFill = `base.withAlpha(0x33)`; text =
`Color.lerp(base, blueprint ? Colors-white-equivalent : black, 0.3)`;
background = blueprint ? `0xFF225C6E` : transparent. (Use `Color` literals, no
material import.)

## 9. Painter (`lib/src/debug/debug_painter.dart`)

Entry point:

```dart
void paintDebugScene(
  Canvas canvas,
  Offset origin,
  Size size,
  DebugScene scene,
  DebugPalette palette, {
  required bool blueprint,
  required DebugLabelStyle labelStyle,
});
```

Implementation notes:
- Translate the canvas by `origin` once (`canvas.save(); canvas.translate(...)`;
  restore at the end) so all scene coordinates are local.
- Private helpers, all pure:
  - `Path _dashPath(Path source, double on, double off)` using
    `computeMetrics()` + `metric.extractPath(start, start + on)` loops.
  - `Path _chainEffect(Path source)` implementing section 4.4 chain algorithm.
  - `Path _zigzag(Offset a, Offset b)` implementing the spring.
  - `Path _arrow(Offset tip, Offset dir, {double side = 6, double halfBase = 5})`.
  - `void _label(Canvas c, String text, Offset center, double fontSize, Color color)`
    creating a `TextPainter(textDirection: TextDirection.ltr)`, laying out,
    painting centered, and DISPOSING it (leak asserts fire in tests otherwise).
- Blueprint pre-pass: `canvas.drawRect(Offset.zero & size, Paint()..color = palette.background)`
  when `blueprint`.
- Boxes (blueprint only for fills/frames/labels; chains mode draws no boxes):
  fill (skip when `virtual`), frame 1 px (`PaintingStyle.stroke`,
  `strokeWidth: 1`), dashed 4/6 frame when `virtual`, 50% opacity when
  `invisible` (wrap in `canvas.saveLayer` with alpha paint, or blend colors
  directly: multiply each color's alpha by 0.5). Labels per `labelStyle`,
  skipped when `rect.width < 40 || rect.height < 24`.
- Connections: switch on type per section 4.4. Margin indicator drawn for
  `normal` and `spring` when `margin > 0`.
- Helpers: guidelines/barriers/virtual bounds per section 4.4.
- Anchors last (on top).
- All `Paint` objects: `isAntiAlias: true`, stroke width 1 unless specified.

## 10. Phases

Execute in order. Each phase ends with its verification green before moving on.
Run commands from the repo root unless stated. The full existing suites must
stay green throughout: engine `(cd packages/constraint_engine && dart test)`
is untouched by this feature; adapter `flutter test` currently passes 61 tests.

### Phase 0: Save this document into the repo

- Copy this document verbatim to `docs/DEBUG_VISUALIZATION.md` (create the
  `docs/` directory). It is both the implementation spec and, post-implementation,
  the feature's design doc. Update it at the end (Phase 7) if implementation
  drifted.

### Phase 1: Types, scene model, palette

- Edit `lib/src/types.dart`: add `DebugLabelStyle` (section 5.1).
- Create `lib/src/debug/debug_scene.dart` (section 6) and
  `lib/src/debug/debug_palette.dart` (section 8).
- Create `test/debug/debug_palette_test.dart`: assert the authentic constants
  (blueprint background `0xFF225C6E`, line `0xCC86CFE5`, fill `0x3386CFE5`;
  design line `0xFFC0C0C0`) and the tint rules (line == base, fill == base at
  alpha `0x33`, blueprint background unchanged under tint).
- Verify: `dart analyze lib test` clean; `flutter test test/debug/`.

### Phase 2: Extractor + bridge

- Create `lib/src/debug/debug_extractor.dart` (section 7).
- Edit `lib/src/constraint_layout.dart`: add ONLY the imports and the
  `debugDescribeScene()` method (section 5.4). No other changes in this phase.
- Create `test/debug/debug_extractor_test.dart`. Reuse the `host()` pattern
  from `test/features_test.dart` (copy the helper; it is 15 lines). Reach the
  scene via
  `tester.renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout)).debugDescribeScene()`.
  Test cases and required assertions:
  1. Three 80x40 fixed boxes in a horizontal spread chain across an 800-wide
     parent: exactly 2 `chain` connections (adjacent pairs, each emitted once)
     with `chainStyle == ChainStyle.spread` and `horizontal == true`; the two
     outer parent connections classified `spring`; anchors sets on boxes
     include left/right.
  2. Same chain with `spreadInside` and `packed`: `chainStyle` matches.
  3. Same three boxes chained vertically: 2 chain connections with
     `horizontal == false`.
  4. A box with `start: .startOf(parent, margin: 16)` only: 1 `normal`
     connection, `margin == 16`, `targetIsParent == true`, source edge left.
  5. A box constrained left to parent and right to a fixed sibling (opposite
     targets): 2 `spring` connections; with `horizontalBias: 0.2`, exactly one
     of them has `dashed == true`.
  6. A box centered in parent (`left`+`right` to parent): exactly 1 `center`
     connection with `centerDashedLine != null` (not 2 springs, not 2 normals).
  7. Baseline: two Text-like boxes linked `baseline: .baselineOf(#a)`: 1
     `baseline` connection; both boxes have `baselineY != null`.
  8. Circular: `circle: .around(#hub, angle: 90, radius: 100)`: 1 `circular`
     connection with `circularAngle == 90`, `circularRadius == 100`.
  9. Guideline (`Guideline.vertical(id: #g, percent: 0.25)` in an 800-wide
     host): one `DebugGuidelineInfo` with `vertical == true`,
     `position == 200`, `chipText == '25%'`; and a sibling constrained to it
     yields a `normal` connection (guideline is a valid target).
  10. Barrier below two boxes: one `DebugBarrierInfo` with
      `fadeDirection == const Offset(0, 1)` and the line y at the barrier's
      resolved position (compute from the taller box + margin).
  11. Flow (`ConstraintFlow` with 3 referenced chips): a `DebugWidgetBox` with
      `virtual == true` whose rect equals the flow's solved bounds.
  12. Grid (2x2 `ConstraintGrid` with 4 members): member connections exist and
      target synthesized rects (no crash), and NO `DebugWidgetBox` is emitted
      for the grid's internal box widgets (box count == real children + 1
      virtual grid box).
  13. GONE sibling: A constrained to B (`visibility: .gone`, gone-margin 24):
      no box for B; A's connection exists with `margin == 24`.
  14. INVISIBLE sibling: box present with `invisible == true`.
- Verify: `flutter test test/debug/`; `dart analyze lib test` clean; full
  `flutter test` still green (61 + new).

### Phase 3: Painter core (connections, chains, springs, anchors, margin labels)

- Create `lib/src/debug/debug_painter.dart` with the entry point and the
  private path helpers (section 9), implementing: normal Beziers + arrows,
  margin indicators (segment, label, ticks, dashed overhang), springs + caps +
  far-leg dash, chain effect (section 4.4 algorithm), adjacent small arrows,
  center route + dashed center line, baseline bow + ticks, circular dashed
  line + label, anchors (halo/solid/ring/pill).
- Unit tests `test/debug/debug_painter_geometry_test.dart` on the helpers
  (make them `@visibleForTesting` top-level functions):
  - `_dashPath` of a 100-long line with 4/6: `computeMetrics()` yields 10
    contours each 4 long (allow the trailing partial).
  - `_chainEffect` of a 90-long line: returns a non-empty path; two passes
    (verify by contour count > 1); path bounds within amplitude 2.5 + stroke
    of the line.
  - `_zigzag(Offset.zero, Offset(60, 0))`: bounds height 6 (amplitude +/-3),
    starts and ends on y == 0.
  - `_arrow`: exactly 3-point closed path with the specified dimensions.
- Golden tests `test/debug/debug_painter_golden_test.dart`: a test-local
  `CustomPainter` that calls `paintDebugScene` with a scene from
  `debugDescribeScene()`, hosted in a `RepaintBoundary` sized 800x600, compared
  with `matchesGoldenFile`:
  - `goldens/chains_chain_row.png`: the 3-box spread chain, design palette.
  - `goldens/chains_bias_spring.png`: the bias case, design palette.
  Bootstrap goldens with `flutter test --update-goldens test/debug/`, then a
  plain run must pass.
- Verify: `flutter test test/debug/`; analyzer clean.

### Phase 4: Painter blueprint surface + helpers

- Extend `debug_painter.dart`: background fill, component fills/frames,
  invisible 50% opacity, virtual dashed frames, labels honoring
  `DebugLabelStyle` (14 px id line, 11 px type line, centered, skip on small
  boxes), guideline dashed line + chip, barrier dashed line + gradient fade
  (use `ui.Gradient.linear` in a `Paint.shader`), virtual bounds.
- Goldens added:
  - `goldens/blueprint_both.png`, `goldens/blueprint_id.png`,
    `goldens/blueprint_label.png`, `goldens/blueprint_none.png`: one
    representative layout (2 constrained boxes + chain + guideline) at each
    label style, blueprint palette.
  - `goldens/blueprint_helpers.png`: guideline + barrier + flow + grid layout.
  - `goldens/chains_tinted.png`: the chain row with
    `DebugPalette.tinted(Color(0xFFFF4081), blueprint: false)`.
- Verify: `flutter test test/debug/`; analyzer clean.

### Phase 5: Widget params + render-object wiring (the only invasive edit)

- Edit `lib/src/constraint_layout.dart`:
  - Widget: 4 new fields + docs + constructor params (section 5.2), threaded
    through `createRenderObject` / `updateRenderObject`.
  - Render object: 4 fields + 4 equality-guarded `markNeedsPaint()` setters,
    constructor params, and the `paint()` restructure (section 5.3). Total
    surgery is about 60 lines; nothing else in the file changes.
- Create `test/debug/debug_repaint_test.dart`:
  - Pump `host` with a chain layout; record `debugLayoutPasses`,
    `debugModelBuilds`, `debugEnginePasses`, `debugConfigApplies`.
  - Re-pump identical layout with `debugShowChains: true`: all four counters
    UNCHANGED (paint-only), child rects identical.
  - Re-pump with `debugShowBlueprint: true`: counters still unchanged.
  - Blueprint hides children: pump a layout whose only child paints solid red;
    with `debugShowBlueprint: true`, capture via
    `tester.binding.runAsync` + `RepaintBoundary.toImage` (or a golden) and
    assert no red pixel at the child's center. Simplest robust form: golden
    `goldens/e2e_blueprint_hides_children.png`.
  - End-to-end golden `goldens/e2e_chains_overlay.png`: chains overlay over
    real (colored-container) children.
  - Hit test still works in blueprint: `GestureDetector` child still receives
    `tester.tapAt` with blueprint on.
- Verify: `flutter test` FULL suite green; `dart analyze lib test benchmark playground/lib` clean.
  (`playground/lib` no longer exists; see Phase 6.)

### Phase 6: Playground integration

> Historical. `playground/` was a local, git-ignored scratch app with one
> scenario per feature, and it has since been deleted, so the files this phase
> creates and edits no longer exist. The website's live examples fill its role
> now: the live examples on the home page have "chains" and "blueprint"
> toggles in their preview headers
> (`website/lib/src/widgets/live_example.dart`, enabled in the site's release
> build by `ConstraintLayout.allowDebugFlags` in `website/lib/main.dart`), and
> the docs page has a live example for every layout feature. The package's
> runnable example is `example/main.dart`.

- Create `playground/lib/debug_options.dart`:

```dart
class DebugOptions extends InheritedWidget {
  const DebugOptions({
    super.key,
    required this.showChains,
    required this.showBlueprint,
    required this.labelStyle,
    required super.child,
  });
  final bool showChains;
  final bool showBlueprint;
  final DebugLabelStyle labelStyle;
  static DebugOptions of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DebugOptions>()!;
  @override
  bool updateShouldNotify(DebugOptions old) =>
      showChains != old.showChains ||
      showBlueprint != old.showBlueprint ||
      labelStyle != old.labelStyle;
}
```

- Edit `playground/lib/main.dart` (`_PlaygroundHomeState`): two boolean state
  fields + `IconButton` toggles in the existing `AppBar.actions` (icons:
  `Icons.linear_scale` for chains, `Icons.grid_on` for blueprint, highlighted
  when active) and a `PopupMenuButton<DebugLabelStyle>`; wrap the scenario
  body in `DebugOptions`.
- Edit each scenario in `playground/lib/scenarios/` (mechanical, one pattern):
  read `final debug = DebugOptions.of(context);` and pass
  `debugShowChains: debug.showChains, debugShowBlueprint: debug.showBlueprint,
  debugBlueprintLabelStyle: debug.labelStyle` to the scenario's
  `ConstraintLayout`. Scenarios: `helpers_scenario.dart`,
  `profile_card_scenario.dart`, `basics_scenario.dart`, `bias_scenario.dart`,
  `match_constraint_scenario.dart`, `aspect_ratio_scenario.dart`,
  `gone_scenario.dart`, `cassowary_gap_scenario.dart`.
- Verify: `dart analyze playground/lib` clean. Manual check if a device is
  available: `cd playground && flutter run`, toggle both modes on the
  "Helpers & virtual layouts" and "Profile card" scenarios.

### Phase 7: Documentation + final verification

- `README.md`: add a "Debug visualization" section after "Usage": what each
  flag draws, `debugChainColor`, a `DebugLabelStyle` table, a code snippet, and
  an explicit note that overlay painting is assert-gated and stripped from
  profile/release builds. No em-dashes.
- Reconcile `docs/DEBUG_VISUALIZATION.md` with any implementation drift.
- Final verification (all must pass):
  - `dart analyze lib test benchmark playground/lib` clean from repo root.
    (`playground/lib` no longer exists; see Phase 6.)
  - `flutter test` full adapter suite green.
  - `cd packages/constraint_engine && dart analyze && dart test` still green
    (engine untouched: 276 pass, 1 skip expected).
  - Goldens stable: `flutter test test/debug/` twice without `--update-goldens`.

## 11. Risks and guardrails

- Fast path: the engine container and solved geometry persist across cached
  frames, so `debugDescribeScene()` always reads valid state. Debug setters
  only `markNeedsPaint` and cannot disturb the caching tiers; the repaint test
  in Phase 5 proves it.
- Never read `mHorizontalChainsArray`/`ChainHead` (empty on the graph path);
  chain detection is topology-derived only.
- Read engine anchors and engine bias, never parent-data `start`/`end` links
  or bias (RTL already resolved).
- `context.canvas` must be read after the `paintChild` loop (getter re-acquires
  the canvas after compositing).
- Dispose every `TextPainter` created during painting or `flutter test` leak
  asserts fail.
- Goldens: flutter_test renders all text with the deterministic test font, and
  gradients/paths are deterministic; use integer coordinates in golden
  fixtures; keep goldens under `test/debug/goldens/`.
- Blueprint skipping `paintChild` is safe with descendant `RepaintBoundary`s
  (their layers simply are not composited); leave a code comment saying so.
- The debug library imports engine types
  (`package:constraint_engine/constraint_engine.dart`); that dependency
  already exists for the adapter.
