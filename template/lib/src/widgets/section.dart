import 'package:flutter/material.dart';

import '../responsive/breakpoints.dart';
import '../theme/context_extensions.dart';
import '../theme/tokens.dart';
import 'inline_link_text.dart';

/// Centers its [child] in a column no wider than [maxWidth], with a constant
/// gutter either side.
///
/// This is the horizontal rhythm of the whole site: every section that uses it
/// shares one left and right edge, at every width.
class ContentContainer extends StatelessWidget {
  const ContentContainer({
    super.key,
    required this.child,
    this.maxWidth = SiteLayout.contentMaxWidth,
    this.gutter = SiteLayout.gutter,
  });

  final Widget child;
  final double maxWidth;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + gutter * 2),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          // Fill the full max width so narrow content still aligns to the
          // shared edges instead of shrink-wrapping and drifting to center.
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}

/// A vertically-padded page section inside a [ContentContainer].
///
/// Vertical padding follows the breakpoint (56px compact, 96px wide) unless
/// [top] or [bottom] override it.
class SiteSection extends StatelessWidget {
  const SiteSection({
    super.key,
    required this.child,
    this.maxWidth = SiteLayout.contentMaxWidth,
    this.top,
    this.bottom,
    this.background,
    this.border = false,
  });

  final Widget child;
  final double maxWidth;
  final double? top;
  final double? bottom;

  /// Full-bleed background behind the section, painted edge to edge.
  final Color? background;

  /// Draw a hairline divider along the section's top edge.
  final bool border;

  @override
  Widget build(BuildContext context) {
    final vertical = context.isCompact
        ? SiteSpacing.sectionCompact
        : SiteSpacing.sectionWide;
    Widget content = Padding(
      padding: EdgeInsets.only(top: top ?? vertical, bottom: bottom ?? vertical),
      child: ContentContainer(maxWidth: maxWidth, child: child),
    );
    if (background != null || border) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          border: border
              ? Border(top: BorderSide(color: context.colors.border))
              : null,
        ),
        child: content,
      );
    }
    return content;
  }
}

/// A section title over an optional muted subtitle, capped to a reading
/// measure so the copy wraps instead of stretching the full content width.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleLinks = const [],
    this.eyebrow,
    this.maxWidth = SiteLayout.readingMaxWidth,
    this.trailing,
  });

  final String title;
  final String? subtitle;

  /// Links woven into [subtitle]. See [InlineLinkText].
  final List<TextLink> subtitleLinks;

  /// A small uppercase label above the title.
  final String? eyebrow;

  final double maxWidth;

  /// An action pinned to the heading's right edge (a "view all" button, a
  /// filter). Dropped on compact widths, where the row has no room.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final subtitleStyle = text.body.copyWith(
      color: context.colors.mutedForeground,
    );

    final column = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            Text(eyebrow!.toUpperCase(), style: text.overline),
            const SizedBox(height: SiteSpacing.sm),
          ],
          Text(title, style: text.h2),
          if (subtitle != null) ...[
            const SizedBox(height: SiteSpacing.xs),
            InlineLinkText(
              subtitle!,
              links: subtitleLinks,
              style: subtitleStyle,
            ),
          ],
        ],
      ),
    );

    if (trailing == null || context.isCompact) return column;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: column),
        const SizedBox(width: SiteSpacing.lg),
        trailing!,
      ],
    );
  }
}

/// A hairline divider that spans its parent's width.
class SiteDivider extends StatelessWidget {
  const SiteDivider({super.key, this.height = 1, this.indent = 0});

  final double height;
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: indent),
      child: SizedBox(
        height: height,
        child: ColoredBox(color: context.colors.border),
      ),
    );
  }
}
