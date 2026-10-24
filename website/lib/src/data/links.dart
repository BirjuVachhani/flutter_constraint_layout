import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// External URLs referenced across the site.
abstract final class Links {
  static const String github =
      'https://github.com/BirjuVachhani/constraint_layout';
  static const String pubDev = 'https://pub.dev/packages/flutter_constraint_layout';
  static const String author = 'https://github.com/BirjuVachhani';

  /// Android's ConstraintLayout, the layout this package ports to Flutter.
  static const String androidConstraintLayout =
      'https://developer.android.com/develop/ui/views/layout/constraint-layout';

  /// The upstream engine this port tracks.
  static const String androidxCore =
      'https://github.com/androidx/constraintlayout';

  /// Opens [url] in a new browser tab (or the platform default handler).
  static Future<void> open(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('Could not open $url: $error');
    }
  }
}
