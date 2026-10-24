# 0.1.0

- Initial version.
- Added `duplicate_constraint_id`: warns when a child of a `ConstraintLayout`
  reuses an id already taken by an earlier child of the same layout.
- Added `undefined_constraint_id`: warns when a link, or a helper's `referenced`
  entry, names an id no child of the same layout defines.
