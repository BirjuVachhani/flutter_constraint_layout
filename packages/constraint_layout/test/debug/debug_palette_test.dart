import 'dart:ui';

import 'package:constraint_layout/src/debug/debug_palette.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blueprint palette matches Android Studio BlueprintColorSet', () {
    const p = DebugPalette.blueprint();
    expect(p.background, const Color(0xFF225C6E));
    expect(p.line, const Color(0xCC86CFE5));
    expect(p.componentFill, const Color(0x3386CFE5));
    expect(p.text, const Color(0xFFDCDCDC));
    expect(p.anchor, const Color(0xFFFFFFFF));
  });

  test('design palette matches Android Studio AndroidColorSet', () {
    const p = DebugPalette.design();
    expect(p.background.a, 0);
    expect(p.line, const Color(0xFFC0C0C0));
    expect(p.componentFill.a, 0);
    expect(p.text, const Color(0xFF000000));
  });

  test('tinted palette derives everything from the base color', () {
    const base = Color(0xFFFF4081);
    final chains = DebugPalette.tinted(base, blueprint: false);
    expect(chains.line, base);
    expect(chains.anchor, base);
    expect(chains.componentFill, base.withAlpha(0x33));
    expect(chains.background.a, 0, reason: 'no surface in chains mode');
    expect(chains.text, Color.lerp(base, const Color(0xFF000000), 0.3));

    final blueprint = DebugPalette.tinted(base, blueprint: true);
    expect(blueprint.background, const Color(0xFF225C6E),
        reason: 'blueprint surface stays authentic under tint');
    expect(blueprint.line, base);
    expect(blueprint.text, Color.lerp(base, const Color(0xFFFFFFFF), 0.3));
  });
}
