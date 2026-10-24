/// Lint rules for flutter_constraint_layout, delivered as an analyzer plugin.
///
/// This library is not the way to use the package: enable the plugin from
/// `analysis_options.yaml` instead (see the README), and the analysis server
/// loads `lib/main.dart`, the plugin's entry point. The rule classes are
/// exported here for tools and tests that drive them directly.
library;

export 'src/rules/duplicate_constraint_id.dart' show DuplicateConstraintId;
export 'src/rules/undefined_constraint_id.dart' show UndefinedConstraintId;
