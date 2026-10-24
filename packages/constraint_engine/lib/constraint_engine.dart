/// A pure-Dart port of the layout engine behind Android's ConstraintLayout
/// (`androidx.constraintlayout.core`), with no Flutter dependency.
///
/// Describe a layout as [ConstraintWidget]s, rectangles whose edges are
/// constrained to each other, inside a [ConstraintWidgetContainer], then call
/// [ConstraintWidgetContainer.layout] to compute every widget's position and
/// size:
///
/// ```dart
/// final root = ConstraintWidgetContainer.sizeNamed('root', 400, 300);
/// final logo = ConstraintWidget.sizeNamed('logo', 48, 48);
/// root.add(logo);
/// logo.connect(.left, root, .left, 16);
/// logo.connect(.top, root, .top, 16);
/// root.layout();
/// print('${logo.getX()}, ${logo.getY()}'); // 16, 16
/// ```
///
/// The main types:
///
/// * [ConstraintWidgetContainer]: the root of a layout, and the entry point,
///   [ConstraintWidgetContainer.layout].
/// * [ConstraintWidget]: a rectangle with [ConstraintAnchor]s (named by
///   [ConstraintAnchorType]) and a [DimensionBehaviour] per axis.
/// * [Measurer] and [Measure]: how the engine asks the host for the size of
///   content, such as text.
/// * The helpers [Guideline] and [Barrier], and the virtual layouts [Flow]
///   and [GridCore].
///
/// [ConstraintWidgetContainer.layout] resolves through a dependency graph
/// first, and falls back to the Cassowary-style [LinearSystem] solver for
/// the layouts the graph cannot resolve. The library also exports the
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
export 'src/guideline.dart';
export 'src/helper.dart';
export 'src/helper_widget.dart';
export 'src/linear_system.dart';
export 'src/optimizer.dart';
export 'src/priority_goal_row.dart';
export 'src/solver_variable.dart';
export 'src/solver_variable_values.dart';
export 'src/virtual_layout.dart';
export 'src/widget_container.dart';
