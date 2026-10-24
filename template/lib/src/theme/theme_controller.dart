import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'theme_store_stub.dart'
    if (dart.library.js_interop) 'theme_store_web.dart';

/// The `localStorage` key the selected mode is persisted under on web.
const String kThemeModeStorageKey = 'site_kit.theme_mode';

/// Holds the active [ThemeMode] and notifies listeners when it changes.
///
/// On web the choice is persisted in `localStorage`, so a reload keeps it. Off
/// web it is in-memory only. Persistence is opt-out via [persist], which is
/// what the storyboard uses to keep its own preview mode separate from the
/// site-wide one.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController({ThemeMode? initial, this.persist = true})
    : super(initial ?? readStoredThemeMode() ?? ThemeMode.system);

  /// Whether changes are written back to browser storage.
  final bool persist;

  bool get isSystem => value == ThemeMode.system;

  /// The brightness this mode resolves to right now, following the platform
  /// when the mode is [ThemeMode.system].
  Brightness get brightness => switch (value) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system =>
      SchedulerBinding.instance.platformDispatcher.platformBrightness,
  };

  bool get isDark => brightness == Brightness.dark;

  @override
  set value(ThemeMode mode) {
    if (mode == value) return;
    super.value = mode;
    if (persist) writeStoredValue(kThemeModeStorageKey, mode.name);
  }

  /// Flips between light and dark. From [ThemeMode.system] it commits to the
  /// opposite of whatever the platform currently shows.
  void toggle() => value = isDark ? ThemeMode.light : ThemeMode.dark;

  /// Steps system → light → dark → system, for a single-button three-way
  /// switch.
  void cycle() => value = switch (value) {
    ThemeMode.system => ThemeMode.light,
    ThemeMode.light => ThemeMode.dark,
    ThemeMode.dark => ThemeMode.system,
  };
}

/// The persisted [ThemeMode] from a previous visit, or null if there is none
/// (or storage is unavailable, as it always is off web).
ThemeMode? readStoredThemeMode() {
  final stored = readStoredValue(kThemeModeStorageKey);
  if (stored == null) return null;
  for (final mode in ThemeMode.values) {
    if (mode.name == stored) return mode;
  }
  return null;
}

/// Exposes a [ThemeController] to descendants and rebuilds them when the mode
/// changes. Access it with `SiteThemeScope.of(context)`.
class SiteThemeScope extends InheritedNotifier<ThemeController> {
  const SiteThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SiteThemeScope>();
    assert(
      scope != null,
      'SiteThemeScope.of() needs a SiteThemeScope ancestor. SiteApp installs '
      'one; add it yourself if you build the MaterialApp by hand.',
    );
    return scope!.notifier!;
  }

  /// The controller, or null when there is no scope above [context].
  static ThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SiteThemeScope>()?.notifier;
}
