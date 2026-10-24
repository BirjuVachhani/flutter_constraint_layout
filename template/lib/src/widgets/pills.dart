import 'package:flutter/material.dart';

import '../theme/context_extensions.dart';
import '../theme/tokens.dart';
import 'copy_button.dart';
import 'site_icon.dart';

/// The tone of a [SiteBadge].
enum BadgeTone { neutral, accent, link, danger }

/// A small static label chip: a version number, a platform tag, a status.
class SiteBadge extends StatelessWidget {
  const SiteBadge(
    this.label, {
    super.key,
    this.icon,
    this.materialIcon,
    this.tone = BadgeTone.neutral,
    this.filled = false,
  });

  final String label;
  final SiteIcons? icon;
  final IconData? materialIcon;
  final BadgeTone tone;

  /// Tint the background with the tone color instead of using the inset
  /// surface. Reads as a status pill rather than a label.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = switch (tone) {
      BadgeTone.neutral => colors.mutedForeground,
      BadgeTone.accent => colors.accent,
      BadgeTone.link => colors.link,
      BadgeTone.danger => colors.danger,
    };
    final background = filled && tone != BadgeTone.neutral
        ? foreground.withValues(alpha: 0.12)
        : colors.surfaceInset;
    final border = filled && tone != BadgeTone.neutral
        ? foreground.withValues(alpha: 0.28)
        : colors.border;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(SiteRadii.pill),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null || materialIcon != null) ...[
            AnyIcon(
              siteIcon: icon,
              icon: materialIcon,
              size: 14,
              color: foreground,
            ),
            const SizedBox(width: 6),
          ],
          Text(label, style: context.text.caption.copyWith(color: foreground)),
        ],
      ),
    );
  }
}

/// A selectable pill, for a small set of mutually exclusive choices.
class SelectPill extends StatefulWidget {
  const SelectPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.materialIcon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final SiteIcons? icon;
  final IconData? materialIcon;

  @override
  State<SelectPill> createState() => _SelectPillState();
}

class _SelectPillState extends State<SelectPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = widget.selected;

    final background = selected
        ? colors.foreground
        : (_hovered ? colors.surfaceInset : colors.surface);
    final foreground = selected ? colors.background : colors.mutedForeground;
    final border = selected ? colors.foreground : colors.border;

    final pill = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: SiteMotion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(SiteRadii.pill),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null || widget.materialIcon != null) ...[
                AnyIcon(
                  siteIcon: widget.icon,
                  icon: widget.materialIcon,
                  size: 14,
                  color: foreground,
                ),
                const SizedBox(width: 7),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SelectionContainer.disabled(child: pill);
  }
}

/// A row of [SelectPill]s bound to one selected value.
class PillGroup<T> extends StatelessWidget {
  const PillGroup({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.labelOf,
    this.spacing = 8,
  });

  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T value) labelOf;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final value in values)
          SelectPill(
            label: labelOf(value),
            selected: value == selected,
            onTap: () => onChanged(value),
          ),
      ],
    );
  }
}

/// A dark pill holding a shell command with a copy button, for the install
/// line in a hero.
///
/// Stays dark in both light and dark mode, the way a terminal snippet reads
/// everywhere else.
class CommandPill extends StatelessWidget {
  const CommandPill({
    super.key,
    required this.command,
    this.prompt,
    this.height = 48,
  });

  /// The command text, and what the copy button puts on the clipboard.
  final String command;

  /// An optional non-copyable prefix, e.g. `$`.
  final String? prompt;

  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final background = isDark ? const Color(0xFF000000) : const Color(0xFF171717);
    return SelectionContainer.disabled(
      child: Container(
        height: height,
        padding: const EdgeInsets.only(left: 20, right: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(SiteRadii.md),
          border: isDark
              ? Border.all(color: Colors.white.withValues(alpha: 0.2))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (prompt != null) ...[
              Text(
                prompt!,
                style: const TextStyle(
                  fontFamily: SiteFonts.mono,
                  fontSize: 15,
                  color: Colors.white38,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                command,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: SiteFonts.mono,
                  fontSize: 15,
                  letterSpacing: -0.2,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 14),
            CopyButton(
              text: command,
              color: Colors.white70,
              hoverColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}
