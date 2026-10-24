import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in a new browser tab (or the platform's default handler).
///
/// Never throws: a blocked pop-up or an unhandled scheme is logged in debug and
/// otherwise ignored, so a dead link cannot take a page down. Returns whether
/// the launch was accepted.
Future<bool> openLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    debugPrint('site_kit: not a valid URL, ignoring: $url');
    return false;
  }
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (error) {
    debugPrint('site_kit: could not open $url: $error');
    return false;
  }
}
