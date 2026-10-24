import 'package:flutter/material.dart';
import 'package:site_kit/site_kit.dart';

import 'src/pages/canvas_page.dart';
import 'src/pages/solo_page.dart';
import 'src/storyboard_config.dart';

Future<void> main() async {
  // One call sets up the URL strategy, the shared syntax highlighter, and its
  // light/dark code theme. Everything the storyboard shows assumes it has run.
  await SiteKit.init();
  runApp(const StoryboardApp());
}

/// The storyboard is itself a site_kit site: same config scope, same theme
/// controller, same router. Its pages opt out of the shared shell because the
/// canvas brings its own chrome.
class StoryboardApp extends StatelessWidget {
  const StoryboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SiteApp(
      config: storyboardConfig,
      title: 'site_kit storyboard',
      pages: [
        SitePage(
          path: '/',
          shell: false,
          builder: (context, state) =>
              CanvasPage(focusId: state.uri.queryParameters['frame']),
        ),
        SitePage(
          path: '/frame/:id',
          shell: false,
          builder: (context, state) =>
              SoloPage(specimenId: state.pathParameters['id']!),
        ),
      ],
    );
  }
}
