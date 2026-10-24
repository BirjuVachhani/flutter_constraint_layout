/// Static (non-live) code samples shown across the site: install commands, the
/// pubspec line, and the home-page hero. Every runnable layout example that has
/// a rendered preview lives in `data/examples.dart` instead, paired with the
/// widget it builds.
///
/// Raw strings (`r'''...'''`) keep `$`, `\`, and quotes literal.
abstract final class Snippets {
  /// The hero snippet: a flat ConstraintLayout, no nested boxes.
  static const String hero = r'''
ConstraintLayout(
  children: [
    Constrained(
      id: #avatar,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      width: .fixed(56),
      height: .fixed(56),
      child: const CircleAvatar(),
    ),
    Constrained(
      id: #name,
      start: .endOf(#avatar, margin: 12),
      end: .endOf(parent, margin: 16),
      top: .topOf(#avatar),
      width: .matchConstraint,
      child: const Text('Ada Lovelace'),
    ),
  ],
)''';

  /// Install command for the hero pill and the installation section.
  static const String install = 'flutter pub add flutter_constraint_layout';

  /// The dependency line for a manual pubspec edit.
  static const String pubspec = r'''
dependencies:
  flutter_constraint_layout: ^0.1.0
''';

  /// The single import that brings in every widget, dimension, link, and helper.
  static const String importLine =
      "import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';";
}
