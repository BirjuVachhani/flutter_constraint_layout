/// A pure-Dart port of the layout pipeline of Android's ConstraintLayout
/// (`androidx.constraintlayout.core` and the measure pass of the
/// ConstraintLayout view), with no Flutter dependency.
///
/// Describe a layout as [ConstraintWidget]s, rectangles whose edges are
/// constrained to each other, inside a [ConstraintWidgetContainer], set a
/// [Measurer] for the content, then measure the container to compute every
/// widget's position and size:
///
/// ```dart
/// final root = ConstraintWidgetContainer.sizeNamed('root', 400, 300);
/// final logo = ConstraintWidget.sizeNamed('logo', 48, 48);
/// root.add(logo);
/// logo.connect(.left, root, .left, 16);
/// logo.connect(.top, root, .top, 16);
/// root.setMeasurer(textMeasurer); // a Measurer of your content
/// root.measure(root.getOptimizationLevel(), BasicMeasure.EXACTLY, 400,
///     BasicMeasure.EXACTLY, 300, 0, 0, 0, 0);
/// print('${logo.getX()}, ${logo.getY()}'); // 16, 16
/// ```
///
/// The main types:
///
/// * [ConstraintWidgetContainer]: the root of a layout.
///   [ConstraintWidgetContainer.measure] is upstream's entry, the one
///   Android's `onMeasure` calls: it measures the children, lays the layout
///   out ([ConstraintWidgetContainer.layout], one pass), and measures again
///   the children whose size depends on the result.
/// * [ViewHost]: Android's own entry, the ConstraintLayout view's
///   `onMeasure`, which measures the layout under [MeasureSpec]s through a
///   [ViewMeasurer], Android's child measurer with one hook for the child
///   view's own measure.
/// * [ConstraintWidget]: a rectangle with [ConstraintAnchor]s (named by
///   [ConstraintAnchorType]) and a [DimensionBehaviour] per axis.
/// * [Measurer] and [Measure]: how the engine asks the host for the size of
///   content, such as text.
/// * The helpers [Guideline] and [Barrier], and the virtual layouts [Flow]
///   and [GridCore].
///
/// Every layout runs Android's pipeline at the container's optimization
/// level ([Optimizer.OPTIMIZATION_STANDARD] by default, as on Android):
/// upstream's `Direct` pass and the Cassowary-style [LinearSystem] solver,
/// with the dependency graph first at the opt-in
/// [Optimizer.OPTIMIZATION_GRAPH] levels, all in Java's 32-bit float
/// arithmetic, so the frames are Android's. The library also exports the
/// solver's building blocks ([LinearSystem], [ArrayRow], [SolverVariable],
/// and the rest), which the ported upstream tests use directly.
///
/// The API mirrors upstream's Java API, with its class and method names,
/// integer constants such as [ConstraintWidget.GONE], and public
/// `m`-prefixed fields, so upstream documentation and code translate almost
/// line by line.
library;

export 'src/analyzer/basic_measure.dart' show BasicMeasure, Measure, Measurer;
export 'src/array_row.dart';
export 'src/barrier.dart';
export 'src/cache.dart';
export 'src/chain.dart';
export 'src/chain_head.dart';
export 'src/constraint_anchor.dart';
export 'src/constraint_widget.dart';
export 'src/constraint_widget_container.dart';
export 'src/flow.dart';
export 'src/goal_row.dart';
export 'src/grid_core.dart';
export 'src/grid_engine.dart';
export 'src/guideline.dart';
export 'src/helper.dart';
export 'src/helper_widget.dart';
export 'src/jfloat.dart' show f32, fsub;
export 'src/linear_system.dart';
export 'src/optimizer.dart';
export 'src/priority_goal_row.dart';
export 'src/solver_variable.dart';
export 'src/solver_variable_values.dart';
export 'src/view/measure_spec.dart';
export 'src/view/view_dependents.dart' show rebuildViewDependents;
export 'src/view/view_host.dart';
export 'src/view/view_measurer.dart';
export 'src/virtual_layout.dart';
export 'src/widget_container.dart';
