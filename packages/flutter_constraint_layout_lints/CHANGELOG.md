## 1.0.0

Initial release.

- `duplicate_constraint_id`: warns when a child of a `ConstraintLayout` reuses
  an id already taken by an earlier child of the same layout.
- `undefined_constraint_id`: warns when a link, or a helper's `referenced`
  entry, names an id that no child of the same layout defines.
