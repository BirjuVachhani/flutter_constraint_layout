// Web implementation: keep the live document title, description, canonical
// link, and the title/description halves of the Open Graph and Twitter cards in
// step with the current route. The tags normally already exist in
// `web/index.html`, so these upserts just rewrite an existing element's
// content; they create the element when missing so the code survives markup
// changes.
//
// Social scrapers read the static HTML without running any of this, so route
// switches only affect what real users and JS-rendering crawlers see, never the
// shared link preview. Put the canonical, per-site tags in `web/index.html`.

import 'package:web/web.dart' as web;

/// Updates the live document metadata for the current route.
void setDocumentMeta({
  required String title,
  required String description,
  String? canonical,
  String? imageUrl,
}) {
  web.document.title = title;

  _upsertMeta('name', 'description', description);
  _upsertMeta('property', 'og:title', title);
  _upsertMeta('property', 'og:description', description);
  _upsertMeta('name', 'twitter:title', title);
  _upsertMeta('name', 'twitter:description', description);
  if (canonical != null) {
    _upsertMeta('property', 'og:url', canonical);
    _upsertCanonical(canonical);
  }
  if (imageUrl != null) {
    _upsertMeta('property', 'og:image', imageUrl);
    _upsertMeta('name', 'twitter:image', imageUrl);
  }
}

/// Sets `content` on `<meta [attr]="[key]">`, creating it in `<head>` if it is
/// not already there. [attr] is `name` or `property`.
void _upsertMeta(String attr, String key, String content) {
  final existing = web.document.querySelector('meta[$attr="$key"]');
  if (existing != null) {
    existing.setAttribute('content', content);
    return;
  }
  final meta = web.document.createElement('meta') as web.HTMLMetaElement
    ..setAttribute(attr, key)
    ..setAttribute('content', content);
  web.document.head?.appendChild(meta);
}

/// Sets `href` on `<link rel="canonical">`, creating it if absent.
void _upsertCanonical(String href) {
  final existing = web.document.querySelector('link[rel="canonical"]');
  if (existing != null) {
    existing.setAttribute('href', href);
    return;
  }
  final link = web.document.createElement('link') as web.HTMLLinkElement
    ..setAttribute('rel', 'canonical')
    ..setAttribute('href', href);
  web.document.head?.appendChild(link);
}
