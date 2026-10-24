// Per-route document metadata for the web build. The site is a client-rendered
// Flutter app, so `web/index.html` carries the static SEO/social tags that
// scrapers read up front (they never run this Dart). What this file adds is
// keeping the live document title and description in step with the current
// route, which helps real users (browser tab, history) and JS-rendering
// crawlers such as Googlebot.
//
// Platform split uses the same conditional-import idiom as the highlighter
// engine config and docs loader: `dart.library.js_interop` is defined only on
// web, so the VM (and widget tests) resolves to the no-op stub.
import 'page_meta_stub.dart' if (dart.library.js_interop) 'page_meta_web.dart';

/// Canonical origin the site is served from (GitHub Pages custom domain).
const String _origin = 'https://constraintlayout.birju.dev';

/// Document metadata for a single route.
class SeoMeta {
  const SeoMeta({
    required this.title,
    required this.description,
    required this.canonical,
  });

  final String title;
  final String description;
  final String canonical;
}

const SeoMeta _home = SeoMeta(
  title: 'flutter_constraint_layout: constraint-based layout for Flutter',
  description:
      'A faithful port of Android ConstraintLayout to Flutter, in pure Dart. '
      'Position and size every child by the constraints you declare, and keep '
      'your widget tree flat instead of nesting rows, columns, and stacks.',
  canonical: '$_origin/',
);

const SeoMeta _docs = SeoMeta(
  title: 'Documentation: flutter_constraint_layout',
  description:
      'Guides for flutter_constraint_layout: installation, anchoring edges, bias and '
      'centering, constraint dimensions, aspect ratios, chains, guidelines, '
      'barriers, circular positioning, and the virtual Flow and Grid layouts.',
  canonical: '$_origin/docs',
);

/// Resolves the [SeoMeta] for a router [location] (path, ignoring any query),
/// falling back to the home metadata for unknown paths.
SeoMeta metaForLocation(String location) {
  final path = Uri.parse(location).path;
  return switch (path) {
    '/docs' => _docs,
    _ => _home,
  };
}

/// Applies the metadata for [location] to the live document. No-op off web.
void applyPageMetaForLocation(String location) {
  final meta = metaForLocation(location);
  setDocumentMeta(
    title: meta.title,
    description: meta.description,
    canonical: meta.canonical,
  );
}
