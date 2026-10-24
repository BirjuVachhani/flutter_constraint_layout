import 'package:flutter/material.dart';

import 'tokens.dart';

/// A site's full color story: the semantic [SiteColors] and the vivid
/// [BrandPalette] for each brightness.
///
/// Pass one to `SiteConfig` to re-skin every component at once. Start from
/// [SitePalette.defaults] and override only what changes:
///
/// ```dart
/// SitePalette.defaults.copyWith(
///   dark: SiteColors.dark.copyWith(link: const Color(0xFFB388FF)),
/// )
/// ```
@immutable
class SitePalette {
  const SitePalette({
    required this.light,
    required this.dark,
    required this.brandLight,
    required this.brandDark,
  });

  /// The stock palette: shadcn-neutral semantics with Pierre-derived hues.
  static const SitePalette defaults = SitePalette(
    light: SiteColors.light,
    dark: SiteColors.dark,
    brandLight: BrandPalette.light,
    brandDark: BrandPalette.dark,
  );

  final SiteColors light;
  final SiteColors dark;
  final BrandPalette brandLight;
  final BrandPalette brandDark;

  SiteColors colorsFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  BrandPalette brandFor(Brightness brightness) =>
      brightness == Brightness.dark ? brandDark : brandLight;

  SitePalette copyWith({
    SiteColors? light,
    SiteColors? dark,
    BrandPalette? brandLight,
    BrandPalette? brandDark,
  }) {
    return SitePalette(
      light: light ?? this.light,
      dark: dark ?? this.dark,
      brandLight: brandLight ?? this.brandLight,
      brandDark: brandDark ?? this.brandDark,
    );
  }
}

/// The type ramp: which families to use and how large the base sizes are.
///
/// Only the families and a scale factor are configurable. Individual component
/// sizes stay in the components, so a site keeps one coherent rhythm.
@immutable
class SiteTypography {
  const SiteTypography({
    this.sans = SiteFonts.sans,
    this.mono = SiteFonts.mono,
    this.scale = 1.0,
  }) : assert(scale > 0, 'A type scale must be positive to size any text.');

  static const SiteTypography defaults = SiteTypography();

  /// UI / body family.
  final String sans;

  /// Code and wordmark family.
  final String mono;

  /// Multiplier applied to the display and heading ramp. 1.0 is the reference
  /// design; nudge it for a denser or airier site.
  final double scale;

  SiteTypography copyWith({String? sans, String? mono, double? scale}) {
    return SiteTypography(
      sans: sans ?? this.sans,
      mono: mono ?? this.mono,
      scale: scale ?? this.scale,
    );
  }
}
