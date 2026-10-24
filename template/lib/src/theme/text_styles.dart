import 'package:flutter/material.dart';

import 'site_palette.dart';
import 'tokens.dart';

/// The site's named text styles, exposed as a [ThemeExtension] so components
/// and pages read one ramp via `context.text`.
///
/// Built by `buildSiteTheme` from the active [SiteTypography] and [SiteColors],
/// so a site changes families or scale in one place.
@immutable
class SiteTextStyles extends ThemeExtension<SiteTextStyles> {
  const SiteTextStyles({
    required this.display,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.h4,
    required this.lede,
    required this.body,
    required this.bodySmall,
    required this.label,
    required this.caption,
    required this.overline,
    required this.mono,
    required this.wordmark,
  });

  /// Hero headline.
  final TextStyle display;

  /// Page title.
  final TextStyle h1;

  /// Section title.
  final TextStyle h2;

  /// Subsection title.
  final TextStyle h3;

  /// Card / block title.
  final TextStyle h4;

  /// Hero and section standfirst copy.
  final TextStyle lede;

  /// Default body copy.
  final TextStyle body;

  /// Dense body copy (tables, callouts, footers).
  final TextStyle bodySmall;

  /// Buttons, nav links, form labels.
  final TextStyle label;

  /// Metadata and helper text.
  final TextStyle caption;

  /// Small uppercase group label.
  final TextStyle overline;

  /// Inline code and other monospaced runs.
  final TextStyle mono;

  /// The brand wordmark.
  final TextStyle wordmark;

  /// Every style paired with its token name, for style-guide rendering.
  Map<String, TextStyle> get named => {
    'display': display,
    'h1': h1,
    'h2': h2,
    'h3': h3,
    'h4': h4,
    'lede': lede,
    'body': body,
    'bodySmall': bodySmall,
    'label': label,
    'caption': caption,
    'overline': overline,
    'mono': mono,
    'wordmark': wordmark,
  };

  /// Derives the ramp for [colors] and [typography].
  ///
  /// Headings scale with [SiteTypography.scale]; body copy does not, so a
  /// larger display size never costs reading comfort.
  factory SiteTextStyles.from({
    required SiteColors colors,
    required SiteTypography typography,
  }) {
    final sans = typography.sans;
    final mono = typography.mono;
    final s = typography.scale;
    final fg = colors.foreground;
    final muted = colors.mutedForeground;

    return SiteTextStyles(
      display: TextStyle(
        fontFamily: sans,
        color: fg,
        fontSize: 54 * s,
        fontWeight: FontWeight.w600,
        height: 1.05,
        // `tracking-tight` scales with the type size (-0.025em).
        letterSpacing: 54 * s * -0.025,
      ),
      h1: TextStyle(
        fontFamily: sans,
        color: fg,
        fontSize: 30 * s,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 30 * s * -0.025,
      ),
      h2: TextStyle(
        fontFamily: sans,
        color: fg,
        fontSize: 24 * s,
        fontWeight: FontWeight.w500,
        height: 1.3,
        letterSpacing: -0.3,
      ),
      h3: TextStyle(
        fontFamily: sans,
        color: fg,
        fontSize: 20 * s,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      h4: TextStyle(
        fontFamily: sans,
        color: fg,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.4,
      ),
      lede: TextStyle(
        fontFamily: sans,
        color: muted,
        fontSize: 19,
        height: 1.5,
      ),
      body: TextStyle(
        fontFamily: sans,
        color: fg,
        fontSize: 16,
        height: 1.6,
      ),
      bodySmall: TextStyle(
        fontFamily: sans,
        color: muted,
        fontSize: 14,
        height: 1.6,
      ),
      label: TextStyle(
        fontFamily: sans,
        color: fg,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        height: 1.2,
      ),
      caption: TextStyle(
        fontFamily: sans,
        color: muted,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        height: 1.4,
      ),
      overline: TextStyle(
        fontFamily: sans,
        color: fg,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
        height: 1.4,
      ),
      mono: TextStyle(
        fontFamily: mono,
        color: fg,
        fontSize: 14.5,
        height: 1.5,
      ),
      wordmark: TextStyle(
        fontFamily: mono,
        color: fg,
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 20 / 15.5,
      ),
    );
  }

  @override
  SiteTextStyles copyWith({
    TextStyle? display,
    TextStyle? h1,
    TextStyle? h2,
    TextStyle? h3,
    TextStyle? h4,
    TextStyle? lede,
    TextStyle? body,
    TextStyle? bodySmall,
    TextStyle? label,
    TextStyle? caption,
    TextStyle? overline,
    TextStyle? mono,
    TextStyle? wordmark,
  }) {
    return SiteTextStyles(
      display: display ?? this.display,
      h1: h1 ?? this.h1,
      h2: h2 ?? this.h2,
      h3: h3 ?? this.h3,
      h4: h4 ?? this.h4,
      lede: lede ?? this.lede,
      body: body ?? this.body,
      bodySmall: bodySmall ?? this.bodySmall,
      label: label ?? this.label,
      caption: caption ?? this.caption,
      overline: overline ?? this.overline,
      mono: mono ?? this.mono,
      wordmark: wordmark ?? this.wordmark,
    );
  }

  @override
  SiteTextStyles lerp(SiteTextStyles? other, double t) {
    if (other == null) return this;
    return SiteTextStyles(
      display: TextStyle.lerp(display, other.display, t)!,
      h1: TextStyle.lerp(h1, other.h1, t)!,
      h2: TextStyle.lerp(h2, other.h2, t)!,
      h3: TextStyle.lerp(h3, other.h3, t)!,
      h4: TextStyle.lerp(h4, other.h4, t)!,
      lede: TextStyle.lerp(lede, other.lede, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      bodySmall: TextStyle.lerp(bodySmall, other.bodySmall, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
      overline: TextStyle.lerp(overline, other.overline, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
      wordmark: TextStyle.lerp(wordmark, other.wordmark, t)!,
    );
  }
}
