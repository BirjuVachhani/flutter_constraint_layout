import 'package:flutter/material.dart';

import '../responsive/breakpoints.dart';
import '../theme/context_extensions.dart';
import '../theme/tokens.dart';
import 'inline_link_text.dart';
import 'section.dart';
import 'wordmark.dart';

/// The landing page's opening block: an optional logo and eyebrow over a
/// headline, a lede, and a row of actions.
///
/// Text-only by default, capped to a comfortable measure so the headline wraps
/// for reading instead of stretching the page. Pass an [aside] (a screenshot, a
/// live preview, a code card) to split the hero in two on wide viewports; it
/// drops below the text on compact ones.
///
/// The top padding already clears the sticky nav, so drop this straight at the
/// top of a page body.
class HeroSection extends StatelessWidget {
  const HeroSection({
    super.key,
    required this.headline,
    this.lede,
    this.ledeLinks = const [],
    this.eyebrow,
    this.actions = const [],
    this.aside,
    this.asideFlex = 5,
    this.showLogo = true,
    this.logoSize = 60,
    this.maxTextWidth = 780,
  });

  final String headline;

  /// Standfirst copy under the headline.
  final String? lede;

  /// Links woven into [lede].
  final List<TextLink> ledeLinks;

  /// A small uppercase label or badge above the headline.
  final Widget? eyebrow;

  /// Buttons and pills under the lede, wrapped on narrow widths.
  final List<Widget> actions;

  /// Content beside the text on wide viewports.
  final Widget? aside;

  /// Flex of [aside] against the text column's flex of 6.
  final int asideFlex;

  final bool showLogo;
  final double logoSize;

  /// Cap on the text column, so the headline wraps for reading.
  final double maxTextWidth;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final colors = context.colors;
    final styles = context.text;

    final headlineStyle = compact
        ? styles.display.copyWith(fontSize: 34, letterSpacing: 34 * -0.025)
        : styles.display;

    final textColumn = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: aside == null ? maxTextWidth : 620),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLogo) ...[
            LogoMark(size: logoSize),
            const SizedBox(height: SiteSpacing.lg),
          ],
          if (eyebrow != null) ...[
            eyebrow!,
            const SizedBox(height: SiteSpacing.md),
          ],
          Text(headline, style: headlineStyle),
          if (lede != null) ...[
            const SizedBox(height: SiteSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: InlineLinkText(
                lede!,
                links: ledeLinks,
                style: compact
                    ? styles.lede.copyWith(fontSize: 16)
                    : styles.lede,
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: SiteSpacing.lg),
            Wrap(
              spacing: SiteSpacing.sm,
              runSpacing: SiteSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );

    final Widget body;
    if (aside == null) {
      body = Align(alignment: Alignment.centerLeft, child: textColumn);
    } else if (compact) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          textColumn,
          const SizedBox(height: SiteSpacing.xl),
          aside!,
        ],
      );
    } else {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 6, child: textColumn),
          const SizedBox(width: SiteSpacing.xxl),
          Expanded(flex: asideFlex, child: aside!),
        ],
      );
    }

    return ColoredBox(
      color: colors.background,
      child: Padding(
        padding: EdgeInsets.only(
          top: SiteLayout.navHeight + (compact ? 44 : 88),
          bottom: compact ? 24 : 44,
        ),
        child: ContentContainer(child: body),
      ),
    );
  }
}
