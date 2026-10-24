import 'package:flutter/material.dart';

import 'site_palette.dart';
import 'text_styles.dart';
import 'tokens.dart';

/// Theme lookups, read straight off the [BuildContext].
///
/// These are the shortest path from a widget to the design tokens:
/// `context.colors.border`, `context.text.h2`, `context.brand.azure`.
extension SiteThemeContext on BuildContext {
  /// The active semantic color tokens.
  ///
  /// Throws if the ambient theme was not built by `buildSiteTheme`, which is
  /// what installs the extension.
  SiteColors get colors {
    final extension = Theme.of(this).extension<SiteColors>();
    assert(
      extension != null,
      'context.colors needs a theme built by buildSiteTheme(); the ambient '
      'ThemeData carries no SiteColors extension.',
    );
    return extension ?? SiteColors.of(Theme.brightnessOf(this));
  }

  /// The active named text styles.
  SiteTextStyles get text {
    final extension = Theme.of(this).extension<SiteTextStyles>();
    assert(
      extension != null,
      'context.text needs a theme built by buildSiteTheme(); the ambient '
      'ThemeData carries no SiteTextStyles extension.',
    );
    return extension ??
        SiteTextStyles.from(
          colors: SiteColors.of(Theme.brightnessOf(this)),
          typography: const SiteTypography(),
        );
  }

  /// The vivid brand hues for the current brightness.
  BrandPalette get brand =>
      Theme.of(this).extension<BrandPalette>() ??
      BrandPalette.of(Theme.brightnessOf(this));

  /// Whether the ambient theme is dark.
  bool get isDarkMode => Theme.brightnessOf(this) == Brightness.dark;
}
