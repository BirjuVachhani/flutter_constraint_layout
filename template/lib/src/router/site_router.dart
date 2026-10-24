import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/site_config.dart';
import '../seo/page_meta.dart';
import '../widgets/nav_bar.dart';
import '../widgets/site_shell.dart';

/// One route in the site.
///
/// Pages are wrapped in a [SiteShell] (nav bar, selection region, scroll
/// tracking) unless [shell] is false, and swap without a transition, which is
/// what a website should feel like.
@immutable
class SitePage {
  const SitePage({
    required this.path,
    required this.builder,
    this.name,
    this.meta,
    this.shell = true,
    this.themeControl = ThemeControl.toggle,
    this.children = const [],
  });

  /// The URL path, e.g. `/` or `/docs`.
  final String path;

  /// Builds the page body, below the shell.
  final Widget Function(BuildContext context, GoRouterState state) builder;

  /// An optional route name for `context.goNamed`.
  final String? name;

  /// Document metadata for this route. Falls back to `SiteConfig.pageMeta[path]`
  /// and then to the site defaults.
  final SeoMeta? meta;

  /// Wrap the page in the shared [SiteShell].
  final bool shell;

  /// Which theme control this page's nav bar shows.
  final ThemeControl themeControl;

  /// Nested routes, for sub-paths that should render inside this page's own
  /// navigator rather than as siblings.
  final List<RouteBase> children;

  /// This page as a go_router route.
  GoRoute toRoute(SiteConfig config) {
    return GoRoute(
      path: path,
      name: name,
      routes: children,
      pageBuilder: (context, state) {
        final body = builder(context, state);
        return NoTransitionPage(
          key: state.pageKey,
          child: shell
              ? SiteShell(
                  currentRoute: state.uri.path,
                  themeControl: themeControl,
                  child: body,
                )
              : body,
        );
      },
    );
  }
}

/// Builds the site's [GoRouter]: one route per [SitePage], each wrapped in the
/// shared shell, with per-route document metadata applied on every navigation.
///
/// `SiteApp` calls this for you. Use it directly when you need to own the
/// router (to add redirects, guards, or a `refreshListenable`).
GoRouter buildSiteRouter({
  required SiteConfig config,
  required List<SitePage> pages,
  String initialLocation = '/',
  List<RouteBase> extraRoutes = const [],
  Widget Function(BuildContext context, GoRouterState state)? notFoundBuilder,
  GoRouterRedirect? redirect,
  Listenable? refreshListenable,
}) {
  assert(pages.isNotEmpty, 'A site needs at least one page to route to.');

  /// Resolves the metadata for a location: the page's own, else the config's
  /// entry for that path, else the site defaults.
  SeoMeta metaFor(String location) {
    final path = Uri.parse(location).path;
    for (final page in pages) {
      if (page.path == path && page.meta != null) return page.meta!;
    }
    return config.metaFor(path);
  }

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    // Keeps the document title and meta description in step with the active
    // route. Runs on the initial load and every navigation, and returns
    // whatever the caller's redirect decides (null by default, so it never
    // actually redirects). Web-only in effect: a no-op stub off web.
    redirect: (context, state) {
      applyPageMeta(metaFor(state.uri.toString()));
      return redirect?.call(context, state);
    },
    routes: [
      for (final page in pages) page.toRoute(config),
      ...extraRoutes,
    ],
    errorBuilder: (context, state) {
      final builder = notFoundBuilder;
      if (builder != null) {
        return SiteShell(currentRoute: state.uri.path, child: builder(context, state));
      }
      // No 404 page supplied: fall back to the first route's content, the way
      // a static host that serves index.html for unknown paths behaves.
      return SiteShell(
        currentRoute: pages.first.path,
        child: pages.first.builder(context, state),
      );
    },
  );
}
