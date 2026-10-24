import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/site_config.dart';
import '../responsive/breakpoints.dart';
import '../theme/context_extensions.dart';
import '../theme/tokens.dart';
import 'section.dart';
import 'site_button.dart';
import 'site_icon.dart';
import 'theme_switcher.dart';
import 'wordmark.dart';

/// Which theme control the nav bar shows.
enum ThemeControl {
  /// A one-tap light/dark toggle.
  toggle,

  /// A System / Light / Dark dropdown.
  menu,

  /// No theme control at all.
  none,
}

/// The sticky top navigation: wordmark on the left, links and actions on the
/// right.
///
/// It has a solid background and no bottom border while the page sits at the
/// top; once the page scrolls, a hairline fades in over 200ms. Below the
/// compact breakpoint the links collapse behind a menu button.
class SiteNavBar extends StatelessWidget {
  const SiteNavBar({
    super.key,
    required this.currentRoute,
    this.onMenu,
    this.scrolled,
    this.themeControl = ThemeControl.toggle,
    this.trailing,
  });

  final String currentRoute;

  /// Opens the compact menu. Null hides the menu button, which only makes sense
  /// for a site with no nav links.
  final VoidCallback? onMenu;

  /// Whether the page has scrolled past the top; drives the bottom border. Kept
  /// as a listenable so only the bar rebuilds, not the page body.
  final ValueListenable<bool>? scrolled;

  final ThemeControl themeControl;

  /// An extra widget between the links and the theme control, e.g. a search
  /// button or a version picker. Hidden on compact widths.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final config = context.site;
    final compact = context.isCompact;

    final themeWidget = switch (themeControl) {
      ThemeControl.toggle => const ThemeToggleButton(),
      ThemeControl.menu => const ThemeModeMenu(),
      ThemeControl.none => null,
    };

    final row = ContentContainer(
      child: Row(
        children: [
          // Expanded (rather than Wordmark + Spacer) so the brand takes the
          // leading space and its tagline ellipsizes under pressure, keeping
          // the links pinned right without overflowing the row.
          const Expanded(child: Wordmark()),
          if (!compact) ...[
            for (final item in config.navLinks)
              _NavLink(
                label: item.label,
                active: item.isActive(currentRoute),
                external: item.isExternal,
                onTap: () => item.activate(context),
              ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ],
            if (config.navActions.isNotEmpty || themeWidget != null)
              const _NavDivider(),
            for (final action in config.navActions)
              SiteIconButton(
                icon: action.icon,
                materialIcon: action.materialIcon,
                tooltip: action.tooltip ?? action.label,
                onPressed: () => action.activate(context),
              ),
            ?themeWidget,
          ] else ...[
            ?themeWidget,
            if (onMenu != null)
              SiteIconButton(
                icon: SiteIcons.menu,
                tooltip: 'Menu',
                onPressed: onMenu,
              ),
          ],
        ],
      ),
    );

    final listenable = scrolled;
    if (listenable == null) return _bar(context, row, false);
    return ValueListenableBuilder<bool>(
      valueListenable: listenable,
      builder: (context, isScrolled, child) =>
          _bar(context, child!, isScrolled),
      child: row,
    );
  }

  Widget _bar(BuildContext context, Widget child, bool isScrolled) {
    final colors = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: SiteLayout.navHeight,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          bottom: BorderSide(
            color: isScrolled ? colors.border : Colors.transparent,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// A button-styled nav link: the active route is foreground and medium weight;
/// the rest are muted, brightening over a subtle pill on hover. External links
/// carry a small up-right arrow.
class _NavLink extends StatefulWidget {
  const _NavLink({
    required this.label,
    required this.onTap,
    this.active = false,
    this.external = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool external;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textColor = widget.active || _hovered
        ? colors.foreground
        : colors.mutedForeground;

    final link = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: SiteMotion.fast,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? colors.foreground.withValues(alpha: 0.07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(SiteRadii.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: widget.active ? FontWeight.w500 : FontWeight.w400,
                  height: 1.0,
                ),
              ),
              if (widget.external) ...[
                const SizedBox(width: 2),
                SiteIcon(
                  SiteIcons.arrowUpRight,
                  size: 15,
                  color: colors.mutedForeground,
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return SelectionContainer.disabled(child: link);
  }
}

/// The thin vertical rule between the text links and the icon buttons.
class _NavDivider extends StatelessWidget {
  const _NavDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: context.colors.border,
    );
  }
}
