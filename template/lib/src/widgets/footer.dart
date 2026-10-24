import 'package:flutter/material.dart';

import '../config/site_config.dart';
import '../responsive/breakpoints.dart';
import '../theme/context_extensions.dart';
import '../theme/tokens.dart';
import 'section.dart';
import 'site_icon.dart';
import 'wordmark.dart';

/// The full footer: wordmark and blurb on one side, link columns on the other,
/// with an optional copyright line under a divider.
///
/// Everything comes from `SiteConfig`. On compact widths the two halves stack.
class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final config = context.site;
    final colors = context.colors;
    final compact = context.isCompact;

    final brandBlock = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wordmark(alwaysShowTagline: true),
          if ((config.footerBlurb ?? config.description).isNotEmpty) ...[
            const SizedBox(height: SiteSpacing.md),
            Text(
              config.footerBlurb ?? config.description,
              style: context.text.bodySmall,
            ),
          ],
        ],
      ),
    );

    final columns = Wrap(
      spacing: 64,
      runSpacing: 32,
      children: [
        for (final column in config.footerColumns)
          _FooterColumn(column: column),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ContentContainer(
            child: Padding(
              padding: const EdgeInsets.only(top: 48, bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (compact) ...[
                    brandBlock,
                    if (config.footerColumns.isNotEmpty) ...[
                      const SizedBox(height: 40),
                      columns,
                    ],
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: brandBlock),
                        columns,
                      ],
                    ),
                  if (config.copyright != null) ...[
                    const SizedBox(height: 40),
                    Divider(height: 1, color: colors.border),
                    const SizedBox(height: 20),
                    Text(config.copyright!, style: context.text.caption),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A centered, single-block footer: logo, wordmark, and one wrapped row of
/// links. Right for a landing page that already ends in a call to action.
class CompactFooter extends StatelessWidget {
  const CompactFooter({super.key, this.showLogo = true});

  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    final config = context.site;
    // Every link the site knows about, flattened into one row.
    final links = <NavItem>[
      ...config.navLinks,
      ...config.navActions,
      for (final column in config.footerColumns) ...column.links,
    ];
    // De-duplicate by label, keeping the first occurrence, so a link that
    // appears in both the nav and a footer column is listed once.
    final seen = <String>{};
    final unique = [for (final l in links) if (seen.add(l.label)) l];

    return ContentContainer(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SiteSpacing.xxxl),
        child: Column(
          children: [
            if (showLogo) ...[
              const LogoMark(size: 48),
              const SizedBox(height: SiteSpacing.sm),
            ],
            const Wordmark(alwaysShowTagline: true),
            const SizedBox(height: SiteSpacing.sm),
            Wrap(
              spacing: SiteSpacing.md,
              runSpacing: SiteSpacing.md,
              alignment: WrapAlignment.center,
              children: [
                for (final link in unique)
                  FooterLink(
                    label: link.label,
                    external: link.isExternal,
                    onTap: () => link.activate(context),
                  ),
              ],
            ),
            if (config.copyright != null) ...[
              const SizedBox(height: SiteSpacing.lg),
              Text(config.copyright!, style: context.text.caption),
            ],
          ],
        ),
      ),
    );
  }
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn({required this.column});

  final FooterColumn column;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          column.title,
          style: TextStyle(
            color: context.colors.foreground,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        for (final link in column.links)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FooterLink(
              label: link.label,
              external: link.isExternal,
              onTap: () => link.activate(context),
            ),
          ),
      ],
    );
  }
}

/// A muted link that brightens and underlines on hover.
class FooterLink extends StatefulWidget {
  const FooterLink({
    super.key,
    required this.label,
    required this.onTap,
    this.external = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool external;

  @override
  State<FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<FooterLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = _hovered ? colors.foreground : colors.mutedForeground;
    final link = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                decoration: _hovered
                    ? TextDecoration.underline
                    : TextDecoration.none,
                decorationColor: colors.foreground,
              ),
            ),
            if (widget.external) ...[
              const SizedBox(width: 3),
              SiteIcon(SiteIcons.arrowUpRight, size: 13, color: color),
            ],
          ],
        ),
      ),
    );
    return SelectionContainer.disabled(child: link);
  }
}
