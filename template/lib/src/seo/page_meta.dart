// Per-route document metadata for the web build.
//
// A Flutter site is client-rendered, so `web/index.html` carries the static
// SEO and social tags that scrapers read up front (they never run this Dart).
// What this adds is keeping the live document title and description in step
// with the current route, which helps real users (browser tab, history) and
// JS-rendering crawlers such as Googlebot.
//
// The platform split uses the standard conditional-import idiom:
// `dart.library.js_interop` is defined only on web, so the VM (and widget
// tests) resolve to the no-op stub.
import 'page_meta_stub.dart' if (dart.library.js_interop) 'page_meta_web.dart';

/// Document metadata for a single route.
class SeoMeta {
  const SeoMeta({
    required this.title,
    required this.description,
    this.canonical,
    this.imageUrl,
  });

  /// Browser tab title and `og:title`.
  final String title;

  /// Meta description and `og:description`.
  final String description;

  /// Absolute canonical URL for this route. Null leaves the tag untouched.
  final String? canonical;

  /// Absolute URL of the social preview image for this route. Null leaves the
  /// static tag from `index.html` in place.
  final String? imageUrl;

  SeoMeta copyWith({
    String? title,
    String? description,
    String? canonical,
    String? imageUrl,
  }) {
    return SeoMeta(
      title: title ?? this.title,
      description: description ?? this.description,
      canonical: canonical ?? this.canonical,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}

/// Applies [meta] to the live document. No-op off web.
void applyPageMeta(SeoMeta meta) {
  setDocumentMeta(
    title: meta.title,
    description: meta.description,
    canonical: meta.canonical,
    imageUrl: meta.imageUrl,
  );
}
