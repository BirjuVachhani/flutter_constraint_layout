import 'package:flutter/material.dart';

import '../theme/context_extensions.dart';
import '../theme/theme_controller.dart';
import 'dropdown.dart';
import 'site_button.dart';
import 'site_icon.dart';

/// The glyph that stands for [mode] in a switcher.
SiteIcons themeModeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.system => SiteIcons.colorAuto,
  ThemeMode.light => SiteIcons.colorLight,
  ThemeMode.dark => SiteIcons.colorDark,
};

/// The label for [mode] in a switcher.
String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};

/// A one-tap light/dark toggle: shows the mode it will switch *to*.
///
/// From [ThemeMode.system] it commits to the opposite of whatever the platform
/// currently shows. Use [ThemeModeMenu] when "follow system" should stay
/// reachable.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final controller = SiteThemeScope.of(context);
    final toDark = !controller.isDark;
    return SiteIconButton(
      icon: toDark ? SiteIcons.moon : SiteIcons.sun,
      tooltip: toDark ? 'Dark mode' : 'Light mode',
      size: size,
      onPressed: controller.toggle,
    );
  }
}

/// A three-way theme picker: System, Light, Dark, in a dropdown.
class ThemeModeMenu extends StatelessWidget {
  const ThemeModeMenu({super.key, this.alignRight = true, this.size = 36});

  /// Open the menu inward from the trigger's right edge, for a control at the
  /// end of a nav row.
  final bool alignRight;

  final double size;

  @override
  Widget build(BuildContext context) {
    final controller = SiteThemeScope.of(context);

    Widget trigger(BuildContext context, bool open, VoidCallback toggle) {
      return SiteIconButton(
        icon: themeModeIcon(controller.value),
        tooltip: 'Theme: ${themeModeLabel(controller.value)}',
        size: size,
        selected: open,
        onPressed: toggle,
      );
    }

    Widget overlay(BuildContext context, VoidCallback close) {
      return MenuPanel(
        width: 176,
        children: [
          for (final mode in ThemeMode.values)
            MenuItemRow(
              label: themeModeLabel(mode),
              icon: themeModeIcon(mode),
              selected: controller.value == mode,
              trailing: controller.value == mode
                  ? SiteIcon(
                      SiteIcons.check,
                      size: 14,
                      color: context.colors.foreground,
                    )
                  : null,
              onTap: () {
                controller.value = mode;
                close();
              },
            ),
        ],
      );
    }

    return alignRight
        ? SiteDropdown.alignRight(
            triggerBuilder: trigger,
            overlayBuilder: overlay,
          )
        : SiteDropdown(triggerBuilder: trigger, overlayBuilder: overlay);
  }
}

/// A three-way theme picker rendered inline as a segmented control, for a
/// settings row or a mobile menu where a popup would be fussy.
class ThemeModeSegmented extends StatelessWidget {
  const ThemeModeSegmented({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = SiteThemeScope.of(context);
    final colors = context.colors;
    return SelectionContainer.disabled(
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colors.surfaceInset,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              _Segment(
                mode: mode,
                selected: controller.value == mode,
                onTap: () => controller.value = mode,
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: themeModeLabel(mode),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 30,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.background : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? colors.border : Colors.transparent,
              ),
            ),
            child: SiteIcon(
              themeModeIcon(mode),
              size: 14,
              color: selected ? colors.foreground : colors.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}
