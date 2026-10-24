import 'dart:io';

import 'package:flutter_constraint_layout_website/src/seo/page_meta.dart';
import 'package:flutter_constraint_layout_website/src/seo/route_pages.dart';
import 'package:flutter_test/flutter_test.dart';

// The deploy writes a static shell per route from index.html (see
// tool/route_pages.dart). These run against the source web/index.html, so a
// drift between its static tags and page_meta.dart fails here, in CI, instead
// of in the deploy.
void main() {
  final index = File('web/index.html').readAsStringSync();

  for (final route in staticRoutes) {
    test('the $route shell carries its own metadata', () {
      final meta = metaForLocation(route);
      final html = routeShell(index, route);

      expect(html, contains('<title>${meta.title}</title>'));
      expect(html, contains('<link rel="canonical" href="${meta.canonical}">'));
      expect(html, contains('<meta property="og:url" content="${meta.canonical}">'));
      expect(html, contains('<meta name="description" content="${meta.description}">'));
      expect(html, contains('<meta property="og:title" content="${meta.title}">'));
      expect(html, contains('<meta name="twitter:title" content="${meta.title}">'));

      final home = metaForLocation('/');
      expect(html, isNot(contains('<link rel="canonical" href="${home.canonical}">')));
      expect(html, isNot(contains('<title>${home.title}</title>')));
    });
  }

  test('a route without its own metadata is rejected', () {
    expect(() => routeShell(index, '/no-such-route'), throwsStateError);
  });

  test('a stale index.html is rejected rather than half-rewritten', () {
    final stale = index.replaceAll('<title>', '<title>Old ');
    expect(() => routeShell(stale, staticRoutes.first), throwsStateError);
  });
}
