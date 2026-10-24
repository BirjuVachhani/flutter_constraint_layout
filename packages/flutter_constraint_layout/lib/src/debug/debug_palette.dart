import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The colors the debug overlay paints with.
///
/// The authentic values are lifted from Android Studio's design surface:
/// `BlueprintColorSet` for [DebugPalette.blueprint] and `AndroidColorSet` for
/// [DebugPalette.design].
@immutable
class DebugPalette {
  const DebugPalette({
    required this.background,
    required this.line,
    required this.componentFill,
    required this.text,
    required this.anchor,
  });

  /// Android Studio blueprint mode: dark teal surface, light cyan lines.
  const DebugPalette.blueprint()
      : background = const Color(0xFF225C6E),
        line = const Color(0xCC86CFE5),
        componentFill = const Color(0x3386CFE5),
        text = const Color(0xFFDCDCDC),
        anchor = const Color(0xFFFFFFFF);

  /// Android Studio design surface (overlay over the real UI): light gray
  /// lines, no background, no fills.
  const DebugPalette.design()
      : background = const Color(0x00000000),
        line = const Color(0xFFC0C0C0),
        componentFill = const Color(0x00000000),
        text = const Color(0xFF000000),
        anchor = const Color(0xFF000000);

  /// A palette where every overlay stroke uses [base]. The blueprint
  /// background stays authentic; text is shade-shifted for contrast.
  factory DebugPalette.tinted(Color base, {required bool blueprint}) {
    final contrast = blueprint ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    return DebugPalette(
      background:
          blueprint ? const Color(0xFF225C6E) : const Color(0x00000000),
      line: base,
      componentFill: base.withAlpha(0x33),
      text: Color.lerp(base, contrast, 0.3)!,
      anchor: base,
    );
  }

  /// Painted over the whole layout in blueprint mode. Fully transparent in
  /// design mode.
  final Color background;

  /// Constraint lines, chains, springs, guidelines, barriers, and frames.
  final Color line;

  /// The translucent fill of each widget box in blueprint mode.
  final Color componentFill;

  /// Margin values, blueprint labels, guideline chips.
  final Color text;

  /// The baseline mark and baseline pill.
  final Color anchor;
}
