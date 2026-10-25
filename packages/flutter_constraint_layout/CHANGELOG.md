## 1.0.0

Initial release.

- `ConstraintLayout`: one flat, constraint-based layout widget. Children are
  `Constrained` widgets identified by `Symbol` ids.
- Links from any edge (`left`, `right`, `start`, `end`, `top`, `bottom`,
  `baseline`) to the parent or a sibling, with `margin` and `goneMargin`.
  `start` and `end` follow the text direction, and in right-to-left layouts
  the horizontal bias of a child linked with them, the position of vertical
  guidelines, and `ConstraintFlow` mirror, as on Android. `ConstraintGrid`
  mirrors its columns (a tile's `horizontalBias` counts from the start edge of
  its cell) and the `margin` of a `.start` or `.end` barrier mirrors as well,
  which they do not on Android, so a layout written with `start` and `end`
  mirrors as a whole.
- Links that loop back on themselves, such as two children whose tops link to
  each other, never hang the layout, including the kind of chain loop that
  Android never finishes laying out. Debug builds report them with a
  `FlutterError`, as they report an unknown id.
- Dimensions: `.fixed`, `.wrapContent`, `.matchParent`, `.matchConstraint`,
  `.percent`, `.spread` (bounded), and `.constrainedWrap`, plus `aspectRatio`.
- Centering and bias, chains (`spread`, `spreadInside`, `packed`) with
  weights, circular positioning, `zIndex`, and `visible`, `invisible`, and
  `gone` visibility. Invisible and gone children, by their own visibility or
  a group's, are left out of the semantics tree, as on Android.
- Helpers: `Guideline`, `Barrier`, and `ConstraintGroup`, which sets the
  visibility of several children at once, like Android's `Group`. Virtual
  layouts: `ConstraintFlow` and `ConstraintGrid`, which follows the grid of
  constraintlayout-core 1.1.1 (a weight list of the wrong length is padded or
  trimmed, spans go to the widgets in order of cell index, and span entries
  past the last widget are ignored). A weighted grid keeps its weights even
  where fixed-size tiles fill or overflow a row or column.
- Intrinsic sizes, dry layout, and a baseline, so the layout works inside
  `IntrinsicHeight`, `IntrinsicWidth`, dialogs, popup menus,
  `IntrinsicColumnWidth` table columns, `Baseline`, and baseline-aligned
  `Row`s. Its baseline is the highest baseline among its visible children
  (Android's `ConstraintLayout` reports none).
- Debug visualization that replicates Android Studio's design surface:
  `debugShowChains`, `debugShowBlueprint`, `debugChainColor`, and
  `debugBlueprintLabelStyle`, enabled outside debug builds with
  `ConstraintLayout.allowDebugFlags`.
- Most layouts resolve on the engine's fast dependency graph, including most
  layouts with a `Barrier` that are bounded on both axes: a barrier layout
  stays on the graph when, by the engine's model of Android's layout pass,
  Android would lay it out the same way. The rest fall back to the engine's
  Cassowary solver (see Performance in the README). Chains on the graph place
  their members where Android does, and a `baseline` link's `margin` applies
  on both paths, as on Android.
- A persistent engine model invalidated in tiers (fast, in-place, rebuild).
  When nothing layout-affecting changed, the incoming constraints are the same,
  and no child's size or position depends on its content (no `.wrapContent` or
  `.constrainedWrap()` size, no match-constraint size missing one of its two
  links, and no baseline alignment), a layout pass reuses the previous geometry
  without running the engine.
- Built on `constraint_engine` 1.0.0.
