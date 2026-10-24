import 'package:flutter/material.dart';

/// The semantic color set for one brightness, exposed as a [ThemeExtension] so
/// any widget can read tokens via `context.colors`.
///
/// The defaults mirror the shadcn/ui "neutral" system: a monochrome,
/// dark-forward scale with hairline borders. Override any subset per site with
/// [copyWith] and hand the result to `SitePalette`.
@immutable
class SiteColors extends ThemeExtension<SiteColors> {
  const SiteColors({
    required this.background,
    required this.surface,
    required this.surfaceInset,
    required this.border,
    required this.borderStrong,
    required this.foreground,
    required this.mutedForeground,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.link,
    required this.danger,
    required this.navBackground,
    required this.shadow,
  });

  /// Page background.
  final Color background;

  /// Card / raised surface.
  final Color surface;

  /// Inset surface for chips, code header bars, hovered menu rows.
  final Color surfaceInset;

  /// Hairline border (low contrast).
  final Color border;

  /// Slightly stronger border for emphasis.
  final Color borderStrong;

  /// Primary text color.
  final Color foreground;

  /// Secondary / de-emphasized text.
  final Color mutedForeground;

  /// Solid button background.
  final Color primary;

  /// Text/icon color on top of [primary].
  final Color onPrimary;

  /// Sparingly-used success accent (emerald).
  final Color accent;

  /// Link / interactive accent (blue).
  final Color link;

  /// Destructive actions and error states.
  final Color danger;

  /// Translucent background for a blurred, sticky nav bar.
  final Color navBackground;

  /// Shadow color under floating surfaces (menus, popovers, code cards).
  final Color shadow;

  static const SiteColors dark = SiteColors(
    background: Color(0xFF0A0A0A),
    surface: Color(0xFF141414),
    // shadcn neutral accent/secondary/muted (oklch 26.9%).
    surfaceInset: Color(0xFF262626),
    border: Color(0x1AFFFFFF),
    borderStrong: Color(0xFF2A2A2A),
    foreground: Color(0xFFFAFAFA),
    mutedForeground: Color(0xFFA1A1A1),
    primary: Color(0xFFFAFAFA),
    onPrimary: Color(0xFF0A0A0A),
    // Pierre "green" and "azure" (the hues the code blocks paint with).
    accent: Color(0xFF5ECC71),
    link: Color(0xFF009FFF),
    danger: Color(0xFFFF678D),
    navBackground: Color(0xCC0A0A0A),
    shadow: Color(0x66000000),
  );

  static const SiteColors light = SiteColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceInset: Color(0xFFF5F5F5),
    border: Color(0xFFE6E6E6),
    borderStrong: Color(0xFFD4D4D4),
    foreground: Color(0xFF0A0A0A),
    mutedForeground: Color(0xFF6B6B6B),
    primary: Color(0xFF171717),
    onPrimary: Color(0xFFFAFAFA),
    // Pierre-light "green" and a deepened "azure" for contrast on white.
    accent: Color(0xFF18A46C),
    link: Color(0xFF0A7CC7),
    danger: Color(0xFFD32A61),
    navBackground: Color(0xF2FFFFFF),
    shadow: Color(0x14000000),
  );

  /// The default token set for [brightness].
  static SiteColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Every token paired with its name, in the order they are declared. Handy
  /// for rendering a style guide or diffing two palettes.
  Map<String, Color> get named => {
    'background': background,
    'surface': surface,
    'surfaceInset': surfaceInset,
    'border': border,
    'borderStrong': borderStrong,
    'foreground': foreground,
    'mutedForeground': mutedForeground,
    'primary': primary,
    'onPrimary': onPrimary,
    'accent': accent,
    'link': link,
    'danger': danger,
    'navBackground': navBackground,
    'shadow': shadow,
  };

  @override
  SiteColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceInset,
    Color? border,
    Color? borderStrong,
    Color? foreground,
    Color? mutedForeground,
    Color? primary,
    Color? onPrimary,
    Color? accent,
    Color? link,
    Color? danger,
    Color? navBackground,
    Color? shadow,
  }) {
    return SiteColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceInset: surfaceInset ?? this.surfaceInset,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      foreground: foreground ?? this.foreground,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      accent: accent ?? this.accent,
      link: link ?? this.link,
      danger: danger ?? this.danger,
      navBackground: navBackground ?? this.navBackground,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  SiteColors lerp(SiteColors? other, double t) {
    if (other == null) return this;
    return SiteColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceInset: Color.lerp(surfaceInset, other.surfaceInset, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      link: Color.lerp(link, other.link, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      navBackground: Color.lerp(navBackground, other.navBackground, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

/// Vivid hues sampled from the Pierre code themes (the palette the code blocks
/// paint syntax with), used for illustrations, charts, and demo surfaces.
///
/// Pulling accent colors from the code theme is what keeps illustrations
/// feeling branded rather than generic. Registered as a [ThemeExtension] by
/// `buildSiteTheme`, so `context.brand` reflects a site's own overrides rather
/// than always returning the stock hues.
@immutable
class BrandPalette extends ThemeExtension<BrandPalette> {
  const BrandPalette({
    required this.azure,
    required this.cyan,
    required this.green,
    required this.lime,
    required this.gold,
    required this.orange,
    required this.coral,
    required this.pink,
    required this.magenta,
    required this.purple,
    required this.canvas,
    required this.canvasGrid,
    required this.canvasBorder,
    required this.guide,
  });

  /// The brand's primary hue: Pierre "azure".
  final Color azure;
  final Color cyan;
  final Color green;
  final Color lime;
  final Color gold;
  final Color orange;
  final Color coral;
  final Color pink;
  final Color magenta;
  final Color purple;

  /// Background of an illustrative canvas.
  final Color canvas;

  /// Faint grid-dot color painted across a canvas (blueprint feel).
  final Color canvasGrid;

  /// Border around a canvas.
  final Color canvasBorder;

  /// Dashed guide / annotation stroke drawn over a canvas.
  final Color guide;

  /// A stable, high-contrast rotation of hues for multi-item visuals. Index
  /// into it with the item's position.
  List<Color> get swatches => [
    azure,
    green,
    orange,
    pink,
    purple,
    cyan,
    gold,
    coral,
  ];

  /// The hue for the [i]th item, wrapping around [swatches].
  Color swatch(int i) => swatches[i % swatches.length];

  /// Every hue paired with its token name, for style-guide rendering.
  Map<String, Color> get named => {
    'azure': azure,
    'cyan': cyan,
    'green': green,
    'lime': lime,
    'gold': gold,
    'orange': orange,
    'coral': coral,
    'pink': pink,
    'magenta': magenta,
    'purple': purple,
  };

  static const BrandPalette dark = BrandPalette(
    azure: Color(0xFF009FFF),
    cyan: Color(0xFF64D1DB),
    green: Color(0xFF5ECC71),
    lime: Color(0xFF86C427),
    gold: Color(0xFFFFCA00),
    orange: Color(0xFFFFA359),
    coral: Color(0xFFFF855E),
    pink: Color(0xFFFF678D),
    magenta: Color(0xFFD568EA),
    purple: Color(0xFF9D6AFB),
    canvas: Color(0xFF0C1117),
    canvasGrid: Color(0x1F009FFF),
    canvasBorder: Color(0x33009FFF),
    guide: Color(0xFFFFA359),
  );

  static const BrandPalette light = BrandPalette(
    azure: Color(0xFF0A7CC7),
    cyan: Color(0xFF1CA1C7),
    green: Color(0xFF18A46C),
    lime: Color(0xFF77A42A),
    gold: Color(0xFFC79310),
    orange: Color(0xFFD47628),
    coral: Color(0xFFD5512F),
    pink: Color(0xFFD32A61),
    magenta: Color(0xFFA631BE),
    purple: Color(0xFF693ACF),
    canvas: Color(0xFFEEF5FC),
    canvasGrid: Color(0x1F0A7CC7),
    canvasBorder: Color(0x330A7CC7),
    guide: Color(0xFFD47628),
  );

  static BrandPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  BrandPalette copyWith({
    Color? azure,
    Color? cyan,
    Color? green,
    Color? lime,
    Color? gold,
    Color? orange,
    Color? coral,
    Color? pink,
    Color? magenta,
    Color? purple,
    Color? canvas,
    Color? canvasGrid,
    Color? canvasBorder,
    Color? guide,
  }) {
    return BrandPalette(
      azure: azure ?? this.azure,
      cyan: cyan ?? this.cyan,
      green: green ?? this.green,
      lime: lime ?? this.lime,
      gold: gold ?? this.gold,
      orange: orange ?? this.orange,
      coral: coral ?? this.coral,
      pink: pink ?? this.pink,
      magenta: magenta ?? this.magenta,
      purple: purple ?? this.purple,
      canvas: canvas ?? this.canvas,
      canvasGrid: canvasGrid ?? this.canvasGrid,
      canvasBorder: canvasBorder ?? this.canvasBorder,
      guide: guide ?? this.guide,
    );
  }

  @override
  BrandPalette lerp(BrandPalette? other, double t) {
    if (other == null) return this;
    return BrandPalette(
      azure: Color.lerp(azure, other.azure, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      green: Color.lerp(green, other.green, t)!,
      lime: Color.lerp(lime, other.lime, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      orange: Color.lerp(orange, other.orange, t)!,
      coral: Color.lerp(coral, other.coral, t)!,
      pink: Color.lerp(pink, other.pink, t)!,
      magenta: Color.lerp(magenta, other.magenta, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      canvasGrid: Color.lerp(canvasGrid, other.canvasGrid, t)!,
      canvasBorder: Color.lerp(canvasBorder, other.canvasBorder, t)!,
      guide: Color.lerp(guide, other.guide, t)!,
    );
  }
}

/// Corner radii.
abstract final class SiteRadii {
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
  static const double pill = 999;

  /// Every radius paired with its token name, for style-guide rendering.
  static const Map<String, double> named = {
    'xs': xs,
    'sm': sm,
    'md': md,
    'lg': lg,
    'xl': xl,
    'pill': pill,
  };
}

/// The 4px spacing scale used for padding, gaps, and section rhythm.
abstract final class SiteSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  /// Vertical padding of a page section, compact and wide.
  static const double sectionCompact = 56;
  static const double sectionWide = 96;

  static const Map<String, double> named = {
    'xxs': xxs,
    'xs': xs,
    'sm': sm,
    'md': md,
    'lg': lg,
    'xl': xl,
    'xxl': xxl,
    'xxxl': xxxl,
  };
}

/// Fixed layout measurements.
abstract final class SiteLayout {
  /// Max width of a standard content container: a 1280px container minus its
  /// 20px gutters on each side.
  static const double contentMaxWidth = 1240;

  /// Max width of a reading column (docs prose, long-form copy).
  static const double readingMaxWidth = 768;

  /// Max width of a heading or lede block.
  static const double proseMaxWidth = 672;

  /// Horizontal gutter either side of the content container.
  static const double gutter = 20;

  /// Height of the sticky top navigation bar: a 36px control row with 12px
  /// padding on each side.
  static const double navHeight = 60;

  /// Width of a docs section rail.
  static const double railWidth = 220;
}

/// Font families. The names carry the `packages/site_kit/` prefix because the
/// fonts are declared in this package's `pubspec.yaml`; that prefix is what
/// makes them resolve in both this package and any app that depends on it.
abstract final class SiteFonts {
  static const String sans = 'packages/site_kit/Geist';
  static const String mono = 'packages/site_kit/Geist Mono';
}

/// Motion durations and curves, so hover, popover, and scroll animations stay
/// consistent across components.
abstract final class SiteMotion {
  /// Hover / press feedback.
  static const Duration fast = Duration(milliseconds: 120);

  /// Popovers and menus.
  static const Duration medium = Duration(milliseconds: 220);

  /// Scroll-to and page-level movement.
  static const Duration slow = Duration(milliseconds: 420);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve standard = Curves.easeInOutCubic;
}
