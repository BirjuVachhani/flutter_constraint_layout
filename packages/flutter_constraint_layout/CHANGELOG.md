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
- A persistent engine model invalidated in tiers (fast, in-place, rebuild), so
  a frame whose constraints did not change skips the engine entirely.
- Built on `constraint_engine` 1.0.0.
