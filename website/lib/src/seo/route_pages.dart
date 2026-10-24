// Static HTML shells for the site's path routes. GitHub Pages has no rewrite
// rules: for an extensionless path it serves the matching `.html` file, and
// for anything else `404.html`. The deploy therefore writes one shell per
// route from the built `index.html`, with the home page's static title,
// description, and canonical URL swapped for the route's own (from
// page_meta.dart). Crawlers and link previews that never run the app then see
// the right page instead of a duplicate of the home page.
//
// Pure Dart (page_meta.dart resolves to its no-op stub off the web), so the
// deploy runs it with `dart run tool/route_pages.dart`.
import 'page_meta.dart';

/// The routes that get their own static shell, besides `/` itself.
///
/// A new top-level route belongs here, or a direct load of it falls through
/// to `404.html`.
const List<String> staticRoutes = ['/docs'];

/// Returns [indexHtml] rewritten to carry [route]'s metadata.
///
/// Throws a [StateError] when a tag the rewrite expects is missing, which
/// means `web/index.html` and page_meta.dart have drifted apart.
String routeShell(String indexHtml, String route) {
  final home = metaForLocation('/');
  final meta = metaForLocation(route);
  if (identical(meta, home)) {
    throw StateError('page_meta.dart has no metadata for $route.');
  }

  var html = indexHtml;
  void swap(String from, String to) {
    if (!html.contains(from)) {
      throw StateError(
        'index.html has no `$from`. Keep the static tags in web/index.html '
        'in step with the home metadata in lib/src/seo/page_meta.dart.',
      );
    }
    html = html.replaceAll(from, to);
  }

  swap('<title>${_text(home.title)}</title>',
      '<title>${_text(meta.title)}</title>');
  for (final (attribute, name) in const [
    ('name', 'description'),
    ('property', 'og:description'),
    ('name', 'twitter:description'),
  ]) {
    swap('<meta $attribute="$name" content="${_attr(home.description)}">',
        '<meta $attribute="$name" content="${_attr(meta.description)}">');
  }
  for (final (attribute, name) in const [
    ('property', 'og:title'),
    ('name', 'twitter:title'),
  ]) {
    swap('<meta $attribute="$name" content="${_attr(home.title)}">',
        '<meta $attribute="$name" content="${_attr(meta.title)}">');
  }
  swap('<link rel="canonical" href="${_attr(home.canonical)}">',
      '<link rel="canonical" href="${_attr(meta.canonical)}">');
  swap('<meta property="og:url" content="${_attr(home.canonical)}">',
      '<meta property="og:url" content="${_attr(meta.canonical)}">');
  return html;
}

String _text(String value) =>
    value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _attr(String value) => _text(value).replaceAll('"', '&quot;');
