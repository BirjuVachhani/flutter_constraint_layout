import 'package:flutter/material.dart';

import 'site_palette.dart';
import 'text_styles.dart';
import 'tokens.dart';

/// Builds the [ThemeData] for one [brightness], wiring in the [SiteColors] and
/// [SiteTextStyles] extensions plus a neutral, low-chrome Material baseline
/// (no splashes, hairline scrollbars, bordered tooltips).
///
/// Call it once per brightness and hand both to `MaterialApp.theme` /
/// `darkTheme`; `SiteApp` does that for you.
ThemeData buildSiteTheme(
  Brightness brightness, {
  SitePalette palette = SitePalette.defaults,
  SiteTypography typography = SiteTypography.defaults,
}) {
  final colors = palette.colorsFor(brightness);
  final brand = palette.brandFor(brightness);
  final text = SiteTextStyles.from(colors: colors, typography: typography);

  final scheme =
      ColorScheme.fromSeed(
        seedColor: colors.foreground,
        brightness: brightness,
      ).copyWith(
        surface: colors.background,
        onSurface: colors.foreground,
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        error: colors.danger,
      );

  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    fontFamily: typography.sans,
    // The components paint their own hover states, so the Material ink is
    // turned off rather than fighting it.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: colors.foreground.withValues(alpha: 0.04),
  );

  return base.copyWith(
    extensions: [colors, brand, text],
    textTheme: _textTheme(base.textTheme, text, typography.sans),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.foreground,
      selectionColor: colors.link.withValues(alpha: 0.28),
      selectionHandleColor: colors.link,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.dragged);
        return colors.foreground.withValues(alpha: hovered ? 0.45 : 0.28);
      }),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(SiteRadii.sm),
      crossAxisMargin: 3,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.surfaceInset,
        borderRadius: BorderRadius.circular(SiteRadii.sm),
        border: Border.all(color: colors.border),
      ),
      textStyle: TextStyle(
        color: colors.foreground,
        fontFamily: typography.sans,
        fontSize: 12,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colors.border,
      thickness: 1,
      space: 1,
    ),
  );
}

/// Maps the site ramp onto Material's [TextTheme] so stock widgets (dialogs,
/// menus, form fields) inherit the same families and colors.
TextTheme _textTheme(TextTheme base, SiteTextStyles site, String family) {
  return base.apply(fontFamily: family).copyWith(
    displayLarge: site.display,
    displayMedium: site.h1,
    displaySmall: site.h2,
    headlineLarge: site.h1,
    headlineMedium: site.h2,
    headlineSmall: site.h3,
    titleLarge: site.h3,
    titleMedium: site.h4,
    titleSmall: site.label,
    bodyLarge: site.lede.copyWith(color: site.body.color),
    bodyMedium: site.body,
    bodySmall: site.bodySmall,
    labelLarge: site.label,
    labelMedium: site.caption,
    labelSmall: site.overline,
  );
}
