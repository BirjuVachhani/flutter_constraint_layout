/// How a chain distributes its members along the chain axis.
///
/// Set on the *head* of the chain (the first member, whose outer edge links to
/// something outside the chain). Android `layout_constraintHorizontal_chainStyle`
/// / `layout_constraintVertical_chainStyle`.
enum ChainStyle {
  /// Members are spread out with equal gaps, including before the first and
  /// after the last member.
  spread,

  /// Members are spread out with equal gaps between them, but the first and
  /// last members sit flush against their outer anchors.
  spreadInside,

  /// Members are packed together in the middle; the head's bias moves the
  /// packed group along the axis.
  packed,
}

/// Whether a `Constrained` child is laid out, and whether it is drawn.
///
/// Android `View.VISIBLE` / `INVISIBLE` / `GONE`. A `ConstraintGroup` that
/// references a child replaces the child's own visibility with its own.
enum ConstraintVisibility {
  /// Laid out and drawn. The default.
  visible,

  /// Laid out at its normal size and position (siblings constrain against it
  /// exactly as if visible), but not drawn, not hit-testable, and left out of
  /// the semantics tree.
  invisible,

  /// Collapses to a zero-size point; margins of links targeting it are
  /// replaced by their `goneMargin`. Not drawn, not hit-testable, and left out
  /// of the semantics tree.
  gone,
}

/// Which edge of its referenced widgets a `Barrier` tracks.
enum BarrierEdge {
  /// The leftmost left edge (absolute).
  left,

  /// The rightmost right edge (absolute).
  right,

  /// The topmost top edge.
  top,

  /// The bottommost bottom edge.
  bottom,

  /// The start-most start edge (RTL-aware): the left edge in left-to-right
  /// text, the right edge in right-to-left text.
  start,

  /// The end-most end edge (RTL-aware): the right edge in left-to-right
  /// text, the left edge in right-to-left text.
  end,
}

/// What kind of engine object a child of `ConstraintLayout` maps to.
///
/// Stored in `ConstraintParentData`; set by `Constrained`, `Guideline`,
/// `Barrier`, `ConstraintFlow`, `ConstraintGrid`, and `ConstraintGroup`.
enum HelperKind {
  /// A regular constrained child.
  none,

  /// A guideline: an invisible anchor line at a fixed or fractional position.
  guideline,

  /// A barrier: an invisible anchor line tracking an edge of referenced
  /// widgets.
  barrier,

  /// A flow: a virtual layout arranging referenced widgets in chains.
  flow,

  /// A grid: a virtual layout arranging referenced widgets in rows and
  /// columns.
  grid,

  /// A group: sets the visibility of referenced widgets. Its own engine
  /// widget is an unlinked widget measured at 0 x 0, as Android's Group's.
  group,
}

/// How a `ConstraintFlow` handles running out of space on its main axis.
enum FlowWrap {
  /// Lay all referenced widgets out in a single chain, even if it overflows.
  none,

  /// Wrap into as many chains (rows/columns) as needed.
  chain,

  /// Wrap like [chain], but align the widgets into a regular grid.
  aligned,
}

/// How a `ConstraintFlow` aligns widgets on the cross axis of each row.
enum FlowVerticalAlign {
  /// Align tops.
  top,

  /// Align bottoms.
  bottom,

  /// Center each widget on the row's biggest widget.
  center,

  /// Align text baselines.
  baseline,
}

/// How a `ConstraintFlow` aligns widgets on the cross axis of each column.
enum FlowHorizontalAlign {
  /// Align start edges.
  start,

  /// Align end edges.
  end,

  /// Center each widget on the column's biggest widget.
  center,
}

/// What text `ConstraintLayout.debugShowBlueprint` draws inside each widget
/// box.
enum DebugLabelStyle {
  /// The child's [Symbol] id, e.g. `avatar`.
  id,

  /// The child widget's runtimeType, e.g. `Text` (Android Studio's class-name
  /// style).
  label,

  /// The id with the runtimeType below it. The default.
  both,

  /// No text.
  none,
}
