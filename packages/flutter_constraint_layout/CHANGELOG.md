## 1.0.0

Initial release.

- `ConstraintLayout`: one flat, constraint-based layout widget. Children are
  `Constrained` widgets identified by `Symbol` ids.
- Android's layout pipeline, ported to Dart: each child is measured as
  Android's view measurer measures a child view, and the layout is solved by
  Android's measure passes, its `Direct` pass, and its Cassowary solver, in
  Android's 32-bit float arithmetic, so a layout gets Android's frames.
  Checked against Android's own code: 0 differences on 60,000 real widget
  trees and on more than 1.8 million engine layouts (realistic, targeted,
  and adversarial) at Android's default level, and on the engine layouts at
  level 0 and at the graph levels too. See Android parity in the README.
- `optimizationLevel`: Android's optimization flags as `OptimizationLevel`
  values, combined with `|`. The default, `OptimizationLevel.standard`, is
  Android's (`direct` and `cacheMeasures`). The dependency-graph levels
  (`graph`, `graphWrap`) are an opt-in and run where Android runs the graph.
  A layout keeps from one layout to the next what Android's keeps, so at the
  levels without `direct` and at the graph levels a layout laid out again
  gives what Android's own views give, which can differ from its first
  layout.
- Links from any edge (`left`, `right`, `start`, `end`, `top`, `bottom`,
  `baseline`) to the parent or a sibling, with `margin` and `goneMargin`.
  `start` and `end` follow the text direction, and in right-to-left layouts
  the horizontal bias of a child linked with them, the position of vertical
  guidelines, and `ConstraintFlow` mirror, as on Android. A barrier's `margin`
  keeps its sign in both directions, as on Android. `ConstraintGrid` mirrors
  its columns (a tile's `horizontalBias` counts from the start edge of its
  cell), which Android's grid helpers leave unimplemented.
- Links that loop back on themselves, such as two children whose tops link to
  each other, never hang the layout, including the kind of chain loop that
  Android never finishes laying out. Debug builds report them with a
  `FlutterError`, as they report an unknown id.
- Dimensions: `.fixed`, `.wrapContent`, `.matchParent`, `.matchConstraint`,
  `.percent`, `.spread` (bounded), and `.constrainedWrap`, plus `aspectRatio`.
  On an axis where the layout sizes to its content, a child is measured with
  unbounded constraints there, as Android measures `match_parent` and
  `wrap_content` under an `UNSPECIFIED` measure spec; a child that cannot size
  itself without a bound, such as a `ListView`, fails the layout with an error
  that names it and the axis, in every build.
- Whole logical pixels: sizes you give round to the nearest pixel, a child's
  measured size and baseline round up as `max(0, (v - 0.001).ceil())`, so
  text is never clipped in its frame, and every child is placed at its integer
  frame. The baseline of every measured child is read, as Android reads it.
- On an unbounded axis, the incoming minimum is the layout's minimum size, as
  Android's `minWidth` and `minHeight` are; a bounded axis is filled.
- Centering and bias, chains (`spread`, `spreadInside`, `packed`) with
  weights, circular positioning, `zIndex`, and `visible`, `invisible`, and
  `gone` visibility. Invisible and gone children, by their own visibility or
  a group's, are left out of the semantics tree, as on Android.
- Helpers: `Guideline` and `Barrier`, always gone as Android's view helpers
  are, and `ConstraintGroup`, which sets the visibility of several children at
  once and, like Android's `Group`, takes part in the solve as a 0 x 0 widget
  at the layout's origin. Virtual layouts: `ConstraintFlow`, and
  `ConstraintGrid`, which follows the grid of constraintlayout-core 1.1.1 (a
  weight list of the wrong length is padded or trimmed, spans go to the
  widgets in order of cell index, and span entries past the last widget are
  ignored) and stays outside the parity contract, since Android has no such
  grid to compare with. A weighted grid keeps its weights even where
  fixed-size tiles fill or overflow a row or column.
- Intrinsic sizes, dry layout, and a baseline, so the layout works inside
  `IntrinsicHeight`, `IntrinsicWidth`, dialogs, popup menus,
  `IntrinsicColumnWidth` table columns, `Baseline`, and baseline-aligned
  `Row`s. A dry query measures a throwaway copy of the layout through the same
  pipeline without laying out any child, so it gives the size of a first
  layout. The layout's baseline is the highest baseline among its visible
  children (Android's `ConstraintLayout` reports none).
- A persistent engine model invalidated in tiers (replay, in place,
  rebuild). A layout, or a dry query, that repeats the last one replays it
  when every child answers its measures as before, without running the
  engine; `--dart-define=cl.verifyReplay=true` runs every replay in full too
  and reports any difference.
- Debug visualization that replicates Android Studio's design surface:
  `debugShowChains`, `debugShowBlueprint`, `debugChainColor`, and
  `debugBlueprintLabelStyle`, enabled outside debug builds with
  `ConstraintLayout.allowDebugFlags`.
- Built on `constraint_engine` 1.0.0.
