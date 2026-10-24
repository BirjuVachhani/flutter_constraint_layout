import 'package:flutter/material.dart';
import 'package:site_kit/site_kit.dart';

/// Filler copy and data for the specimens.
///
/// Kept in one place so the demos stay about the components rather than about
/// inventing text, and so nothing here reads as real product documentation.
abstract final class SampleContent {
  static const String dartSnippet = '''
import 'package:site_kit/site_kit.dart';

Future<void> main() async {
  await SiteKit.init();
  runApp(SiteApp(
    config: siteConfig,
    pages: [
      SitePage(path: '/', builder: (_, _) => const HomePage()),
      SitePage(path: '/docs', builder: (_, _) => const DocsPage()),
    ],
  ));
}
''';

  static const String yamlSnippet = '''
dependencies:
  site_kit:
    path: ../template
''';

  static const String shellSnippet = '''
flutter pub add site_kit
dart run shiki_flutter:install --default
flutter build web --wasm
''';

  static const String proseParagraph =
      'Body copy sits at a 768px measure, which keeps a line near 72 '
      'characters. Inline `code` renders as plain mono with no background box, '
      'and **bold** runs may wrap code, so **`SiteConfig`** comes out mono and '
      'semibold at once.';

  static const List<String> bullets = [
    'Tokens through `context.colors` and `context.text`.',
    'Breakpoints through `context.breakpoint`, which folds the layout below '
        '900px.',
    'Routing through `go_router`, with real paths rather than hash fragments.',
  ];

  static const List<String> steps = [
    'Add the package and run `SiteKit.init()` in `main`.',
    'Describe the site once in a `SiteConfig`.',
    'List your pages and hand them to `SiteApp`.',
  ];

  static const List<String> tableHeaders = ['Property', 'Type', 'Description'];

  static const List<List<String>> tableRows = [
    ['`name`', '`String`', 'The wordmark, rendered in the mono family.'],
    ['`navLinks`', '`List<NavItem>`', 'Primary links in the bar and the sheet.'],
    ['`palette`', '`SitePalette`', 'Semantic colors and brand hues, per mode.'],
    ['`pageMeta`', '`Map<String, SeoMeta>`', 'Per-route title and description.'],
  ];

  static const String linkParagraph =
      'Links are matched by label, so the copy stays readable in source. This '
      'sentence links out to Flutter and across to the buttons frame, and the '
      'widget disposes both recognizers for you.';

  static const String heroLede =
      'site_kit is the theme, components, and plumbing behind a documentation '
      'site, extracted into one package. Light and dark, responsive to the '
      'phone, and routed with go_router.';

  static const String ctaBody =
      'Everything on this canvas is a real widget from the package, rendered '
      'live. Change a token and every frame follows it in the same frame.';

  /// A grouped section list, for the rail and docs-shell specimens.
  static const List<PageSectionGroup> docsGroups = [
    PageSectionGroup('Getting started', [
      PageSection('install', 'Installation'),
      PageSection('config', 'Configuration'),
      PageSection('routing', 'Routing'),
    ]),
    PageSectionGroup('Theming', [
      PageSection('tokens', 'Design tokens'),
      PageSection('palette', 'Custom palettes'),
      PageSection('type', 'Typography'),
    ]),
    PageSectionGroup('Components', [
      PageSection('buttons', 'Buttons'),
      PageSection('code', 'Code blocks'),
      PageSection('prose', 'Prose'),
    ]),
  ];

  /// Body content for one docs section in the pattern specimens.
  static List<Widget> docsSectionBody(PageSection section) => [
    Prose(
      'This is the `${section.id}` section. A real page would build different '
      'content per id, mixing prose, code, and live demos.',
    ),
    const CodeBlock(
      code: 'await SiteKit.init();',
      lang: 'dart',
      showLineNumbers: false,
    ),
  ];
}

/// Feature cards for the grid specimens, tinted from the brand palette.
List<Feature> sampleFeatures(BuildContext context) {
  final brand = context.brand;
  return [
    Feature(
      title: 'Design tokens',
      description:
          'Colors, type, spacing, and radii as theme extensions, so nothing '
          'hard-codes a hex.',
      materialIcon: Icons.palette_outlined,
      color: brand.azure,
    ),
    Feature(
      title: 'Light and dark',
      description:
          'One controller, three modes, persisted in the browser between '
          'visits.',
      materialIcon: Icons.contrast_rounded,
      color: brand.purple,
    ),
    Feature(
      title: 'Responsive',
      description:
          'Five breakpoints, an adaptive grid, and chrome that folds into a '
          'sheet on phones.',
      materialIcon: Icons.devices_rounded,
      color: brand.green,
    ),
    Feature(
      title: 'Real URLs',
      description:
          'go_router with path URLs, deep links, and per-route document '
          'metadata.',
      materialIcon: Icons.link_rounded,
      color: brand.orange,
    ),
    Feature(
      title: 'Highlighted code',
      description:
          'shiki_flutter tokenizes off the main thread and follows the active '
          'theme.',
      materialIcon: Icons.code_rounded,
      color: brand.pink,
    ),
  ];
}
