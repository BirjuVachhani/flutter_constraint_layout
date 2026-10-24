import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'config/site_config.dart';
import 'navigation/sections.dart';
import 'router/site_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

/// The root widget of a site.
///
/// Owns the four things every page needs and would otherwise have to be wired
/// by hand: the [SiteConfig] scope, the [ThemeController] (with its persisted
/// light/dark choice), the [NavSheetController] bridge that lets any page put
/// its sections in the shared mobile menu, and a [GoRouter] built from [pages].
///
/// ```dart
/// void main() async {
///   await SiteKit.init();
///   runApp(SiteApp(config: siteConfig, pages: [
///     SitePage(path: '/', builder: (_, _) => const HomePage()),
///     SitePage(path: '/docs', builder: (_, _) => const DocsPage()),
///   ]));
/// }
/// ```
///
/// Pass [router] instead of [pages] when you need to own the router; wrap your
/// own with [buildSiteRouter] to keep the SEO redirect.
class SiteApp extends StatefulWidget {
  const SiteApp({
    super.key,
    required this.config,
    this.pages = const [],
    this.router,
    this.title,
    this.initialThemeMode,
    this.initialLocation = '/',
    this.notFoundBuilder,
    this.debugShowCheckedModeBanner = false,
    this.builder,
  }) : assert(
         pages.length > 0 || router != null,
         'SiteApp needs pages to route to, or a router of your own.',
       );

  /// Brand, navigation, footer, palette, and SEO defaults.
  final SiteConfig config;

  /// The site's routes. Ignored when [router] is given.
  final List<SitePage> pages;

  /// A router built by hand. Takes precedence over [pages].
  final GoRouter? router;

  /// The app title reported to the OS and the initial document title. Defaults
  /// to `SiteConfig.name`.
  final String? title;

  /// Overrides the persisted (or default) theme mode. Mostly for tests and
  /// previews; leave it null so a visitor's own choice sticks.
  final ThemeMode? initialThemeMode;

  final String initialLocation;

  /// Body of the 404 page. Without one, unknown paths render the first page.
  final Widget Function(BuildContext context, GoRouterState state)?
  notFoundBuilder;

  final bool debugShowCheckedModeBanner;

  /// Wraps the navigator, e.g. to inject an app-wide overlay or a scroll
  /// behavior. Runs below the theme, so `context.colors` works inside it.
  final TransitionBuilder? builder;

  @override
  State<SiteApp> createState() => _SiteAppState();
}

class _SiteAppState extends State<SiteApp> {
  late final ThemeController _theme = ThemeController(
    initial: widget.initialThemeMode,
  );

  /// Bridges a page's section list to the app-wide nav sheet. Lives above the
  /// router so the shell's nav bar and each page share one instance.
  final NavSheetController _navSheet = NavSheetController();

  late GoRouter _router = _buildRouter();

  @override
  void didUpdateWidget(SiteApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuilding the router resets navigation history, so only do it when the
    // routes themselves changed.
    if (oldWidget.router != widget.router ||
        oldWidget.pages != widget.pages ||
        oldWidget.config != widget.config) {
      _router = _buildRouter();
    }
  }

  @override
  void dispose() {
    _theme.dispose();
    super.dispose();
  }

  GoRouter _buildRouter() {
    return widget.router ??
        buildSiteRouter(
          config: widget.config,
          pages: widget.pages,
          initialLocation: widget.initialLocation,
          notFoundBuilder: widget.notFoundBuilder,
        );
  }

  @override
  Widget build(BuildContext context) {
    return SiteConfigScope(
      config: widget.config,
      child: SiteThemeScope(
        controller: _theme,
        child: NavSheetScope(
          controller: _navSheet,
          child: ListenableBuilder(
            listenable: _theme,
            builder: (context, _) {
              return MaterialApp.router(
                title: widget.title ?? widget.config.name,
                debugShowCheckedModeBanner: widget.debugShowCheckedModeBanner,
                theme: buildSiteTheme(
                  Brightness.light,
                  palette: widget.config.palette,
                  typography: widget.config.typography,
                ),
                darkTheme: buildSiteTheme(
                  Brightness.dark,
                  palette: widget.config.palette,
                  typography: widget.config.typography,
                ),
                themeMode: _theme.value,
                routerConfig: _router,
                builder: widget.builder,
              );
            },
          ),
        ),
      ),
    );
  }
}
