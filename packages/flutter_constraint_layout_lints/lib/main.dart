import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/rules/duplicate_constraint_id.dart';
import 'src/rules/undefined_constraint_id.dart';

/// The entry point the analysis server looks up by name. Do not rename.
final plugin = ConstraintLayoutLintsPlugin();

class ConstraintLayoutLintsPlugin extends Plugin {
  @override
  String get name => 'flutter_constraint_layout_lints';

  @override
  void register(PluginRegistry registry) {
    // Registered as a warning rule: enabled by default once the plugin is on,
    // since every diagnostic here is a real bug rather than a style choice.
    registry.registerWarningRule(DuplicateConstraintId());
    registry.registerWarningRule(UndefinedConstraintId());
  }
}
