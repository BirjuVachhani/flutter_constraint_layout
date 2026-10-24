import 'package:flutter/material.dart';

import '../config/site_config.dart';
import '../navigation/sections.dart';
import '../theme/context_extensions.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'site_icon.dart';

/// Opens the app-wide navigation popup: the site links, the theme switch, and,
/// when a page with sections is on screen, that page's section list.
///
/// This is the single compact-width menu. [currentRoute] drives which link is
/// highlighted as active.
Future<void> showSiteNavSheet(
  BuildContext context, {
  required String currentRoute,
}) {
  // Captured before the dialog route builds: the sheet's own context sits under
  // the navigator, above the SiteConfigScope / NavSheetScope in the app.
  final config = context.site;
  final navSheet = NavSheetScope.maybeOf(context);
  final theme = SiteThemeScope.of(context);

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: SiteMotion.medium,
    pageBuilder: (context, _, _) => _NavSheet(
      currentRoute: currentRoute,
      config: config,
      navigator: navSheet?.sections,
      theme: theme,
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: SiteMotion.enter,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// The popup body: site links up top, then (only when a page registered one)
/// the grouped section list with the active section highlighted.
class _NavSheet extends StatelessWidget {
  const _NavSheet({
    required this.currentRoute,
    required this.config,
    required this.navigator,
    required this.theme,
  });

  final String currentRoute;
  final SiteConfig config;
  final SectionNavigator? navigator;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    void close() => Navigator.of(context).pop();

    final sectionGroups = navigator?.sectionGroups ?? const [];
    final hasSections = sectionGroups.isNotEmpty;

    // Icon-only nav actions get a labeled row here; a 36px glyph is not a
    // usable menu target.
    final items = [...config.navLinks, ...config.navActions];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 56, 12, 16),
        child: Align(
          // Anchored top-right so a short menu reads as dropping out of the nav
          // rather than floating mid-screen.
          alignment: Alignment.topRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: hasSections ? 300 : 240),
            // A Material both paints the panel and satisfies the InkWell
            // descendants (showGeneralDialog inserts none).
            child: Material(
              color: colors.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SiteRadii.lg),
                side: BorderSide(color: colors.border),
              ),
              child: Column(
                // Shrink-wrap so short menus hug their content; the scroll view
                // caps a long section list at the available height.
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in items)
                            _SheetItem(
                              label: item.label,
                              icon: item.icon,
                              materialIcon: item.materialIcon,
                              active: item.isActive(currentRoute),
                              external: item.isExternal,
                              onTap: () {
                                close();
                                item.activate(context);
                              },
                            ),
                          _SheetItem(
                            label: theme.isDark ? 'Light mode' : 'Dark mode',
                            icon: theme.isDark
                                ? SiteIcons.sun
                                : SiteIcons.moon,
                            onTap: theme.toggle,
                          ),
                          if (hasSections) ...[
                            const SizedBox(height: 12),
                            Divider(height: 1, color: colors.border),
                            const SizedBox(height: 12),
                            SectionList(
                              groups: sectionGroups,
                              activeIndex: navigator!.activeSection,
                              groupSpacing: 20,
                              onSelect: (index) {
                                close();
                                navigator!.scrollToSection(index);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A nav row inside the popup: an optional leading glyph, a 16px label, and a
/// trailing up-right arrow for external links.
class _SheetItem extends StatelessWidget {
  const _SheetItem({
    required this.label,
    required this.onTap,
    this.active = false,
    this.external = false,
    this.icon,
    this.materialIcon,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool external;
  final SiteIcons? icon;
  final IconData? materialIcon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SelectionContainer.disabled(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SiteRadii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (icon != null || materialIcon != null) ...[
                AnyIcon(
                  siteIcon: icon,
                  icon: materialIcon,
                  size: 18,
                  color: colors.foreground,
                ),
                const SizedBox(width: 12),
              ],
              // Flexed so the label fills the row and ellipsizes on tight
              // widths, with the trailing icon pinned right.
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? colors.foreground : colors.mutedForeground,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (external) ...[
                const SizedBox(width: 12),
                SiteIcon(
                  SiteIcons.arrowUpRight,
                  size: 16,
                  color: colors.mutedForeground,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
