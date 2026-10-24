import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../seo/page_meta.dart';
import '../theme/site_palette.dart';
import '../util/launch_link.dart';
import '../widgets/site_icon.dart';

/// One entry in the nav bar, the mobile nav sheet, or a footer column.
///
/// Exactly one destination should be set: [route] for an in-app go_router path,
/// [url] for an external link, or [onTap] for an arbitrary action.
@immutable
class NavItem {
  const NavItem({
    required this.label,
    this.route,
    this.url,
    this.onTap,
    this.icon,
    this.materialIcon,
    this.iconOnly = false,
    this.tooltip,
  }) : assert(
         route != null || url != null || onTap != null,
         'A NavItem needs somewhere to go: pass route, url, or onTap.',
       ),
       assert(
         !iconOnly || icon != null || materialIcon != null,
         'An icon-only NavItem needs an icon to render in place of its label.',
       );

  /// A link to an in-app route.
  const NavItem.route(
    this.label,
    String this.route, {
    this.icon,
    this.materialIcon,
    this.tooltip,
  }) : url = null,
       onTap = null,
       iconOnly = false;

  /// A link that opens outside the app. Rendered with a trailing up-right
  /// arrow wherever links are listed.
  const NavItem.external(
    this.label,
    String this.url, {
    this.icon,
    this.materialIcon,
    this.tooltip,
  }) : route = null,
       onTap = null,
       iconOnly = false;

  /// A square icon button for the right end of the nav bar (GitHub, Discord).
  const NavItem.action({
    required this.label,
    this.icon,
    this.materialIcon,
    this.route,
    this.url,
    this.onTap,
    String? tooltip,
  }) : iconOnly = true,
       tooltip = tooltip ?? label,
       assert(
         icon != null || materialIcon != null,
         'An action needs an icon; it renders no label.',
       ),
       assert(
         route != null || url != null || onTap != null,
         'A NavItem needs somewhere to go: pass route, url, or onTap.',
       );

  /// Text shown for the item, and the tooltip fallback for icon-only actions.
  final String label;

  /// An in-app route path, e.g. `/docs`.
  final String? route;

  /// An external URL.
  final String? url;

  /// An arbitrary action, for items that neither navigate nor link out.
  final VoidCallback? onTap;

  /// A glyph from the bundled set.
  final SiteIcons? icon;

  /// Any Material glyph, for icons the bundled set does not cover.
  final IconData? materialIcon;

  /// Render as a square icon button rather than a text link.
  final bool iconOnly;

  /// Tooltip for icon-only items.
  final String? tooltip;

  /// Whether this item leaves the site.
  bool get isExternal => url != null;

  /// Whether [currentRoute] is this item's destination. A route matches its own
  /// sub-paths (`/docs` is active on `/docs/routing`) so nested pages keep the
  /// parent highlighted; `/` matches exactly.
  bool isActive(String currentRoute) {
    final target = route;
    if (target == null) return false;
    if (target == '/') return currentRoute == '/';
    return currentRoute == target || currentRoute.startsWith('$target/');
  }

  /// Runs this item's destination: navigates, opens the link, or calls back.
  void activate(BuildContext context) {
    if (onTap != null) {
      onTap!();
      return;
    }
    if (url != null) {
      openLink(url!);
      return;
    }
    if (route != null) context.go(route!);
  }
}

/// A titled group of links in the footer.
@immutable
class FooterColumn {
  const FooterColumn(this.title, this.links);

  final String title;
  final List<NavItem> links;
}

/// The person or org behind the site, credited beside the wordmark.
@immutable
class SiteAuthor {
  const SiteAuthor({required this.name, this.url});

  final String name;

  /// Profile link. When set, the name renders as a link.
  final String? url;
}

/// Draws the site's logo at the requested size.
typedef LogoBuilder = Widget Function(BuildContext context, double size);

/// Everything a site brands and wires up: identity, navigation, footer, colors,
/// type, and SEO defaults.
///
/// Install it once with `SiteApp(config: ...)` (or a bare [SiteConfigScope]),
/// and every component below reads from it through `context.site`.
@immutable
class SiteConfig {
  const SiteConfig({
    required this.name,
    this.description = '',
    this.tagline,
    this.author,
    this.origin,
    this.logo,
    this.navLinks = const [],
    this.navActions = const [],
    this.footerColumns = const [],
    this.footerBlurb,
    this.copyright,
    this.palette = SitePalette.defaults,
    this.typography = SiteTypography.defaults,
    this.pageMeta = const {},
  });

  /// The wordmark, rendered in the mono family (`site_kit`, `acme.dev`).
  final String name;

  /// One-sentence description. Used as the default meta description and in the
  /// footer when no [footerBlurb] is given.
  final String description;

  /// Short phrase after the wordmark, e.g. `for Flutter by`. The [author] name
  /// is appended to it.
  final String? tagline;

  /// Credited beside the wordmark, after [tagline].
  final SiteAuthor? author;

  /// Canonical origin the site is served from, e.g.
  /// `Uri.parse('https://acme.dev')`. Required for canonical and Open Graph
  /// URLs; without it those tags are left alone.
  final Uri? origin;

  /// Draws the logo mark. Defaults to a generated monogram tile.
  final LogoBuilder? logo;

  /// Primary text links in the nav bar and nav sheet.
  final List<NavItem> navLinks;

  /// Icon buttons at the right end of the nav bar (GitHub, Discord, ...).
  final List<NavItem> navActions;

  /// Link columns in the full footer.
  final List<FooterColumn> footerColumns;

  /// Paragraph under the wordmark in the full footer. Falls back to
  /// [description].
  final String? footerBlurb;

  /// Small print at the very bottom, e.g. `© 2026 Acme`.
  final String? copyright;

  /// Semantic colors and brand hues for both brightnesses.
  final SitePalette palette;

  /// Font families and type scale.
  final SiteTypography typography;

  /// Per-route document metadata, keyed by path (`/`, `/docs`). Routes with no
  /// entry fall back to [name] and [description].
  final Map<String, SeoMeta> pageMeta;

  /// The metadata for [path], falling back to the site defaults.
  SeoMeta metaFor(String path) {
    final normalized = Uri.parse(path).path;
    return pageMeta[normalized] ??
        SeoMeta(
          title: name,
          description: description,
          canonical: origin?.resolve(normalized).toString(),
        );
  }

  SiteConfig copyWith({
    String? name,
    String? description,
    String? tagline,
    SiteAuthor? author,
    Uri? origin,
    LogoBuilder? logo,
    List<NavItem>? navLinks,
    List<NavItem>? navActions,
    List<FooterColumn>? footerColumns,
    String? footerBlurb,
    String? copyright,
    SitePalette? palette,
    SiteTypography? typography,
    Map<String, SeoMeta>? pageMeta,
  }) {
    return SiteConfig(
      name: name ?? this.name,
      description: description ?? this.description,
      tagline: tagline ?? this.tagline,
      author: author ?? this.author,
      origin: origin ?? this.origin,
      logo: logo ?? this.logo,
      navLinks: navLinks ?? this.navLinks,
      navActions: navActions ?? this.navActions,
      footerColumns: footerColumns ?? this.footerColumns,
      footerBlurb: footerBlurb ?? this.footerBlurb,
      copyright: copyright ?? this.copyright,
      palette: palette ?? this.palette,
      typography: typography ?? this.typography,
      pageMeta: pageMeta ?? this.pageMeta,
    );
  }
}

/// Makes a [SiteConfig] available to the whole widget tree.
class SiteConfigScope extends InheritedWidget {
  const SiteConfigScope({
    super.key,
    required this.config,
    required super.child,
  });

  final SiteConfig config;

  static SiteConfig of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SiteConfigScope>();
    assert(
      scope != null,
      'context.site needs a SiteConfigScope ancestor. SiteApp installs one; '
      'wrap your app in SiteConfigScope if you build MaterialApp by hand.',
    );
    return scope!.config;
  }

  static SiteConfig? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SiteConfigScope>()?.config;

  @override
  bool updateShouldNotify(SiteConfigScope oldWidget) =>
      config != oldWidget.config;
}

extension SiteConfigContext on BuildContext {
  /// The site's configuration: brand, navigation, footer, palette, SEO.
  SiteConfig get site => SiteConfigScope.of(this);
}
