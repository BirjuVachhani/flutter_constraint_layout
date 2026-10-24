import 'package:flutter/material.dart';

import '../theme/context_extensions.dart';
import '../theme/tokens.dart';
import 'site_icon.dart';

/// The visual weight of a [SiteButton].
enum SiteButtonVariant {
  /// Solid, highest emphasis. One per view.
  primary,

  /// Filled with the inset surface. The workhorse.
  secondary,

  /// Bordered and transparent.
  outline,

  /// No chrome until hover.
  ghost,

  /// Solid, for destructive actions.
  danger,
}

/// Button height and type size.
enum SiteButtonSize { sm, md, lg }

/// A compact, shadcn-style button with hover feedback and optional leading and
/// trailing icons.
///
/// Icons come from either the bundled set ([leadingIcon]) or Material
/// ([leadingMaterialIcon]); the bundled glyph wins when both are set. A null
/// [onPressed] disables the button.
class SiteButton extends StatefulWidget {
  const SiteButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = SiteButtonVariant.primary,
    this.size = SiteButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.leadingMaterialIcon,
    this.trailingMaterialIcon,
    this.expand = false,
    this.busy = false,
    this.tooltip,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;

  final SiteButtonVariant variant;
  final SiteButtonSize size;

  final SiteIcons? leadingIcon;
  final SiteIcons? trailingIcon;
  final IconData? leadingMaterialIcon;
  final IconData? trailingMaterialIcon;

  /// Stretch to the parent's width instead of hugging the label. Useful in a
  /// compact column where buttons stack.
  final bool expand;

  /// Show a spinner in place of the leading icon and ignore taps.
  final bool busy;

  final String? tooltip;

  @override
  State<SiteButton> createState() => _SiteButtonState();
}

class _SiteButtonState extends State<SiteButton> {
  bool _hovered = false;
  bool _pressed = false;

  ({double fontSize, double iconSize, EdgeInsets padding}) get _metrics =>
      switch (widget.size) {
        SiteButtonSize.sm => (
          fontSize: 13.5,
          iconSize: 15,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        ),
        SiteButtonSize.md => (
          fontSize: 15,
          iconSize: 18,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        SiteButtonSize.lg => (
          fontSize: 16,
          iconSize: 20,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 17),
        ),
      };

  /// Background, foreground, and border for the current variant and state.
  ({Color background, Color foreground, Color? border}) _palette() {
    final colors = context.colors;
    // Pressed reads as a slightly deeper hover, so the two states never look
    // identical on a touch device that reports both.
    final lift = _pressed ? 0.12 : (_hovered ? 0.06 : 0.0);

    switch (widget.variant) {
      case SiteButtonVariant.primary:
        return (
          background: _pressed
              ? colors.primary.withValues(alpha: 0.80)
              : (_hovered ? colors.primary.withValues(alpha: 0.88)
                    : colors.primary),
          foreground: colors.onPrimary,
          border: null,
        );
      case SiteButtonVariant.danger:
        return (
          background: _hovered || _pressed
              ? colors.danger.withValues(alpha: _pressed ? 0.80 : 0.88)
              : colors.danger,
          foreground: Colors.white,
          border: null,
        );
      case SiteButtonVariant.secondary:
        return (
          background: Color.alphaBlend(
            colors.foreground.withValues(alpha: lift),
            colors.surfaceInset,
          ),
          foreground: colors.foreground,
          border: null,
        );
      case SiteButtonVariant.outline:
        return (
          background: colors.foreground.withValues(alpha: lift),
          foreground: colors.foreground,
          border: colors.borderStrong,
        );
      case SiteButtonVariant.ghost:
        return (
          background: colors.foreground.withValues(alpha: lift),
          foreground: colors.foreground,
          border: null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final (fontSize: fontSize, iconSize: iconSize, padding: padding) = _metrics;
    final (background: bg, foreground: fg, border: border) = _palette();
    final foreground = enabled ? fg : fg.withValues(alpha: 0.55);

    final leading = AnyIcon(
      siteIcon: widget.leadingIcon,
      icon: widget.leadingMaterialIcon,
      size: iconSize,
      color: foreground,
    );
    final trailing = AnyIcon(
      siteIcon: widget.trailingIcon,
      icon: widget.trailingMaterialIcon,
      size: iconSize,
      color: foreground,
    );

    Widget button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedContainer(
          duration: SiteMotion.fast,
          curve: Curves.easeOut,
          padding: padding,
          decoration: BoxDecoration(
            color: enabled ? bg : bg.withValues(alpha: bg.a * 0.5),
            borderRadius: BorderRadius.circular(SiteRadii.md),
            border: border == null ? null : Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.busy) ...[
                SizedBox.square(
                  dimension: iconSize,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 7),
              ] else if (!leading.isEmpty) ...[
                leading,
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              if (!trailing.isEmpty) ...[
                const SizedBox(width: 6),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return SelectionContainer.disabled(child: button);
  }
}

/// A square icon button with a rounded hover pill: the nav bar's GitHub and
/// theme controls, and the toolbar buttons.
class SiteIconButton extends StatefulWidget {
  const SiteIconButton({
    super.key,
    this.icon,
    this.materialIcon,
    required this.tooltip,
    required this.onPressed,
    this.size = 36,
    this.iconSize = 18,
    this.color,
    this.selected = false,
  }) : assert(
         icon != null || materialIcon != null,
         'A SiteIconButton renders no label, so it needs an icon.',
       );

  final SiteIcons? icon;
  final IconData? materialIcon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Width and height of the hit target and hover pill.
  final double size;
  final double iconSize;

  final Color? color;

  /// Paint the resting state as a filled pill, for a toggle that is on.
  final bool selected;

  @override
  State<SiteIconButton> createState() => _SiteIconButtonState();
}

class _SiteIconButtonState extends State<SiteIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.onPressed != null;
    final tint = (widget.color ?? colors.foreground).withValues(
      alpha: enabled ? 1 : 0.4,
    );

    final button = Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: SiteMotion.fast,
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.selected
                  ? colors.surfaceInset
                  : (_hovered && enabled
                        ? colors.foreground.withValues(alpha: 0.07)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(SiteRadii.sm),
            ),
            child: AnyIcon(
              siteIcon: widget.icon,
              icon: widget.materialIcon,
              size: widget.iconSize,
              color: tint,
            ),
          ),
        ),
      ),
    );
    return SelectionContainer.disabled(child: button);
  }
}
