import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/site_config.dart';
import '../responsive/breakpoints.dart';
import '../theme/context_extensions.dart';
import '../theme/tokens.dart';
import '../util/launch_link.dart';

/// The default logo: a rounded tile carrying the site's initial, tinted with
/// the brand's primary hue.
///
/// Drawn in code, so it scales cleanly and needs no asset. Replace it wholesale
/// by setting `SiteConfig.logo`.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 40, this.letter});

  final double size;

  /// The glyph to draw. Defaults to the first letter of `SiteConfig.name`.
  final String? letter;

  @override
  Widget build(BuildContext context) {
    final config = SiteConfigScope.maybeOf(context);
    final custom = config?.logo;
    if (custom != null) return custom(context, size);

    final brand = context.brand;
    final source = letter ?? config?.name ?? '?';
    final initial = source.isEmpty ? '?' : source.substring(0, 1);
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: brand.azure.withValues(alpha: 0.14),
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(size * 0.26),
            side: BorderSide(color: brand.azure.withValues(alpha: 0.32)),
          ),
        ),
        child: Center(
          child: Text(
            initial.toUpperCase(),
            style: TextStyle(
              fontFamily: SiteFonts.mono,
              fontSize: size * 0.46,
              fontWeight: FontWeight.w600,
              height: 1,
              letterSpacing: -1,
              color: brand.azure,
            ),
          ),
        ),
      ),
    );
  }
}

/// The wordmark: the site name in semibold mono, optionally followed by a muted
/// tagline whose author name links out.
///
/// Tapping the name navigates home by default. The tagline is hidden on compact
/// layouts unless [alwaysShowTagline] is set (the footer sets it, since it has
/// the room to wrap).
class Wordmark extends StatefulWidget {
  const Wordmark({
    super.key,
    this.onTap,
    this.alwaysShowTagline = false,
    this.showLogo = false,
    this.logoSize = 28,
  });

  /// Tapping the name. Defaults to navigating to `/`.
  final VoidCallback? onTap;

  /// Keep the tagline on compact widths.
  final bool alwaysShowTagline;

  /// Draw the logo mark before the name.
  final bool showLogo;

  final double logoSize;

  @override
  State<Wordmark> createState() => _WordmarkState();
}

class _WordmarkState extends State<Wordmark> {
  final TapGestureRecognizer _authorTap = TapGestureRecognizer();
  bool _nameHovered = false;
  bool _authorHovered = false;

  @override
  void dispose() {
    _authorTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = context.site;
    final colors = context.colors;
    final text = context.text;
    final showTagline =
        config.tagline != null &&
        (widget.alwaysShowTagline || !context.isCompact);

    final name = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _nameHovered = true),
      onExit: (_) => setState(() => _nameHovered = false),
      child: GestureDetector(
        onTap: widget.onTap ?? () => context.go('/'),
        child: Text(
          config.name,
          style: text.wordmark.copyWith(
            color: _nameHovered
                ? colors.foreground.withValues(alpha: 0.8)
                : colors.foreground,
          ),
        ),
      ),
    );

    final author = config.author;
    if (author?.url != null) {
      _authorTap.onTap = () => openLink(author!.url!);
    }

    final wordmark = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.showLogo
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.baseline,
      textBaseline: widget.showLogo ? null : TextBaseline.alphabetic,
      children: [
        if (widget.showLogo) ...[
          LogoMark(size: widget.logoSize),
          const SizedBox(width: 10),
        ],
        name,
        if (showTagline) ...[
          const SizedBox(width: 6),
          // Flexible so the tagline ellipsizes rather than overflowing when the
          // nav row is tight near the compact breakpoint.
          Flexible(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontFamily: config.typography.sans,
                  fontSize: 14,
                  height: 20 / 14,
                  color: colors.mutedForeground,
                ),
                children: [
                  TextSpan(text: config.tagline),
                  if (author != null) ...[
                    const TextSpan(text: ' '),
                    TextSpan(
                      text: author.name,
                      recognizer: author.url == null ? null : _authorTap,
                      onEnter: (_) => setState(() => _authorHovered = true),
                      onExit: (_) => setState(() => _authorHovered = false),
                      mouseCursor: author.url == null
                          ? MouseCursor.defer
                          : SystemMouseCursors.click,
                      style: TextStyle(
                        color: _authorHovered
                            ? colors.foreground.withValues(alpha: 0.8)
                            : colors.mutedForeground,
                      ),
                    ),
                  ],
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );

    return SelectionContainer.disabled(child: wordmark);
  }
}
