import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/context_extensions.dart';

/// The bundled icon set, shipped as SVG under `assets/icons/`.
///
/// These are the glyphs the chrome needs (nav, code blocks, menus, theme
/// switching). Anything else is a Material glyph: every component that takes a
/// [SiteIcons] also accepts an [IconData].
enum SiteIcons {
  /// Two overlapping rounded squares; the front one at 40% opacity for depth.
  copy,

  /// A single checkmark, shown after a successful copy.
  check,

  /// A document with `</>`, for a code-block header.
  fileCode,

  /// A downward chevron for dropdown triggers.
  chevronDown,

  /// A disc that is half-lit: the "follow system" theme.
  colorAuto,

  /// A filled crescent: the dark theme.
  colorDark,

  /// A filled sun disc: the light theme.
  colorLight,

  /// An outlined sun with rays.
  sun,

  /// An outlined crescent moon.
  moon,

  /// The GitHub mark.
  github,

  /// The Discord mark.
  discord,

  /// An arrow pointing up-and-right; marks links that open externally.
  arrowUpRight,

  /// A short rightward arrow.
  arrowRight,

  /// A close (✕) glyph.
  x,

  /// A three-line "hamburger" menu glyph.
  menu,

  /// A circular refresh arrow.
  refresh,

  /// Stacked folders.
  folders,

  /// A horizontal chain link, for the anchor beside a deep-linkable heading.
  /// Drawn with strokes rather than a filled path, which renders identically
  /// at this weight and keeps the geometry legible.
  link;

  /// Path to this icon's SVG asset. Enum names are camelCase and asset files
  /// are kebab-case (`fileCode` → `assets/icons/file-code.svg`).
  String get asset {
    final kebab = name.replaceAllMapped(
      RegExp('[A-Z]'),
      (m) => '-${m[0]!.toLowerCase()}',
    );
    return 'assets/icons/$kebab.svg';
  }
}

/// Renders a [SiteIcons] glyph as a crisp, single-color vector.
///
/// The glyph is tinted with [BlendMode.srcIn], which replaces its color while
/// preserving each path's alpha, so multi-opacity icons (such as
/// [SiteIcons.copy]'s layered squares) keep their depth. Defaults to the theme
/// `foreground` color.
class SiteIcon extends StatelessWidget {
  const SiteIcon(this.icon, {super.key, this.size = 16, this.color});

  final SiteIcons icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      icon.asset,
      // The assets live in this package, not the consuming app.
      package: 'site_kit',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? context.colors.foreground,
        BlendMode.srcIn,
      ),
    );
  }
}

/// Renders whichever of [siteIcon] or [icon] is set, so a component can accept
/// either the bundled set or any Material glyph with one code path.
///
/// [siteIcon] wins when both are given. Renders nothing when both are null.
class AnyIcon extends StatelessWidget {
  const AnyIcon({
    super.key,
    this.siteIcon,
    this.icon,
    this.size = 16,
    this.color,
  });

  final SiteIcons? siteIcon;
  final IconData? icon;
  final double size;
  final Color? color;

  /// Whether there is anything to draw.
  bool get isEmpty => siteIcon == null && icon == null;

  @override
  Widget build(BuildContext context) {
    final glyph = siteIcon;
    if (glyph != null) return SiteIcon(glyph, size: size, color: color);
    if (icon == null) return const SizedBox.shrink();
    return Icon(
      icon,
      size: size,
      color: color ?? context.colors.foreground,
    );
  }
}
