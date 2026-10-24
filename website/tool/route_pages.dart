// Writes the static route shells into a web build: `<route>.html` for every
// route in `staticRoutes`, and `404.html` for any other path. Run from
// website/ after `flutter build web`, as the deploy workflow does:
//
//   dart run tool/route_pages.dart build/web
//
// See lib/src/seo/route_pages.dart for why GitHub Pages needs these.
import 'dart:io';

import 'package:flutter_constraint_layout_website/src/seo/route_pages.dart';

void main(List<String> args) {
  final dir = args.isEmpty ? 'build/web' : args.single;
  final index = File('$dir/index.html').readAsStringSync();
  for (final route in staticRoutes) {
    File('$dir$route.html').writeAsStringSync(routeShell(index, route));
    stdout.writeln('Wrote $dir$route.html');
  }
  File('$dir/404.html').writeAsStringSync(index);
  stdout.writeln('Wrote $dir/404.html');
}
