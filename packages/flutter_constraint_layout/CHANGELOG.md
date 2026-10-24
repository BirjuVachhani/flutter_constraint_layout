## 1.0.0

Initial release.

- `ConstraintLayout`: one flat, constraint-based layout widget. Children are
  `Constrained` widgets identified by `Symbol` ids.
- Links from any edge (`left`, `right`, `start`, `end`, `top`, `bottom`,
  `baseline`) to the parent or a sibling, with `margin` and `goneMargin`.
  `start` and `end` follow the ambient text direction.
- Dimensions: `.fixed`, `.wrapContent`, `.matchParent`, `.matchConstraint`,
  `.percent`, `.spread` (bounded), and `.constrainedWrap`, plus `aspectRatio`.
- Centering and bias, chains (`spread`, `spreadInside`, `packed`) with
  weights, circular positioning, `zIndex`, and `visible`, `invisible`, and
  `gone` visibility.
- Helpers: `Guideline` and `Barrier`. Virtual layouts: `ConstraintFlow` and
  `ConstraintGrid`.
- Debug visualization that replicates Android Studio's design surface:
  `debugShowChains`, `debugShowBlueprint`, `debugChainColor`, and
  `debugBlueprintLabelStyle`, enabled outside debug builds with
  `ConstraintLayout.allowDebugFlags`.
- A persistent engine model invalidated in tiers (fast, in-place, rebuild).
  When nothing layout-affecting changed, the incoming constraints are the same,
  and no child's size or position depends on its content (no `.wrapContent` or
  `.constrainedWrap()` size, no match-constraint size missing one of its two
  links, and no baseline alignment), a layout pass reuses the previous geometry
  without running the engine.
- Built on `constraint_engine` 1.0.0.
