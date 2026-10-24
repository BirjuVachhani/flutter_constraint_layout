import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kit/site_kit.dart';

const SiteConfig _config = SiteConfig(
  name: 'acme',
  description: 'A test site.',
  navLinks: [
    NavItem.route('Home', '/'),
    NavItem.route('Docs', '/docs'),
    NavItem.external('pub.dev', 'https://pub.dev'),
  ],
  pageMeta: {
    '/docs': SeoMeta(title: 'Docs · acme', description: 'Guides.'),
  },
);

/// Pumps [child] under the same scopes `SiteApp` installs.
Future<void> pumpSite(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1200, 900),
  SiteConfig config = _config,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    SiteConfigScope(
      config: config,
      child: SiteThemeScope(
        controller: ThemeController(initial: ThemeMode.dark, persist: false),
        child: NavSheetScope(
          controller: NavSheetController(),
          child: MaterialApp(
            theme: buildSiteTheme(Brightness.dark, palette: config.palette),
            home: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('theme', () {
    test('installs the token extensions for both brightnesses', () {
      for (final brightness in Brightness.values) {
        final theme = buildSiteTheme(brightness);
        expect(theme.extension<SiteColors>(), isNotNull);
        expect(theme.extension<BrandPalette>(), isNotNull);
        expect(theme.extension<SiteTextStyles>(), isNotNull);
        expect(theme.brightness, brightness);
      }
    });

    test('a palette override reaches the extension', () {
      const pink = Color(0xFFFF00AA);
      final palette = SitePalette.defaults.copyWith(
        dark: SiteColors.dark.copyWith(link: pink),
      );
      final theme = buildSiteTheme(Brightness.dark, palette: palette);
      expect(theme.extension<SiteColors>()!.link, pink);
      // Untouched tokens keep their defaults.
      expect(
        theme.extension<SiteColors>()!.background,
        SiteColors.dark.background,
      );
    });

    test('typography scale drives headings but not body', () {
      final base = SiteTextStyles.from(
        colors: SiteColors.dark,
        typography: const SiteTypography(),
      );
      final large = SiteTextStyles.from(
        colors: SiteColors.dark,
        typography: const SiteTypography(scale: 2),
      );
      expect(large.display.fontSize, base.display.fontSize! * 2);
      expect(large.body.fontSize, base.body.fontSize);
    });

    testWidgets('context lookups resolve', (tester) async {
      late SiteColors colors;
      late SiteTextStyles text;
      late BrandPalette brand;
      await pumpSite(
        tester,
        Builder(
          builder: (context) {
            colors = context.colors;
            text = context.text;
            brand = context.brand;
            return const SizedBox.shrink();
          },
        ),
      );
      expect(colors.background, SiteColors.dark.background);
      expect(text.display.fontSize, greaterThan(text.body.fontSize!));
      expect(brand.azure, BrandPalette.dark.azure);
    });
  });

  group('ThemeController', () {
    test('toggles and cycles', () {
      final controller = ThemeController(
        initial: ThemeMode.light,
        persist: false,
      );
      addTearDown(controller.dispose);

      expect(controller.isDark, isFalse);
      controller.toggle();
      expect(controller.value, ThemeMode.dark);
      controller.cycle();
      expect(controller.value, ThemeMode.system);
      controller.cycle();
      expect(controller.value, ThemeMode.light);
    });

    test('notifies only on a real change', () {
      final controller = ThemeController(
        initial: ThemeMode.dark,
        persist: false,
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.value = ThemeMode.dark;
      expect(notifications, 0);
      controller.value = ThemeMode.light;
      expect(notifications, 1);
    });
  });

  group('breakpoints', () {
    test('bands are half-open and ordered', () {
      expect(Breakpoint.of(0), Breakpoint.xs);
      expect(Breakpoint.of(599), Breakpoint.xs);
      expect(Breakpoint.of(600), Breakpoint.sm);
      expect(Breakpoint.of(899), Breakpoint.sm);
      expect(Breakpoint.of(900), Breakpoint.md);
      expect(Breakpoint.of(1535), Breakpoint.lg);
      expect(Breakpoint.of(4000), Breakpoint.xl);
      expect(Breakpoint.sm < Breakpoint.md, isTrue);
    });

    test('compact is everything below md', () {
      expect(Breakpoint.xs.isCompact, isTrue);
      expect(Breakpoint.sm.isCompact, isTrue);
      expect(Breakpoint.md.isCompact, isFalse);
    });

    test('ResponsiveValue cascades down to the nearest set band', () {
      const value = ResponsiveValue<int>(xs: 1, md: 3);
      expect(value.resolveFor(Breakpoint.xs), 1);
      expect(value.resolveFor(Breakpoint.sm), 1);
      expect(value.resolveFor(Breakpoint.md), 3);
      expect(value.resolveFor(Breakpoint.xl), 3);
    });

    testWidgets('context.isCompact follows the viewport', (tester) async {
      late bool compact;
      Widget probe() => Builder(
        builder: (context) {
          compact = context.isCompact;
          return const SizedBox.shrink();
        },
      );

      await pumpSite(tester, probe(), size: const Size(500, 800));
      expect(compact, isTrue);

      await pumpSite(tester, probe(), size: const Size(1400, 800));
      expect(compact, isFalse);
    });
  });

  group('SiteConfig', () {
    test('a route is active on itself and its sub-paths, not siblings', () {
      const docs = NavItem.route('Docs', '/docs');
      expect(docs.isActive('/docs'), isTrue);
      expect(docs.isActive('/docs/routing'), isTrue);
      expect(docs.isActive('/docsearch'), isFalse);
      expect(docs.isActive('/'), isFalse);

      const home = NavItem.route('Home', '/');
      expect(home.isActive('/'), isTrue);
      expect(home.isActive('/docs'), isFalse);
    });

    test('metaFor prefers the per-route entry, else the site defaults', () {
      expect(_config.metaFor('/docs').title, 'Docs · acme');
      expect(_config.metaFor('/').title, 'acme');
      expect(_config.metaFor('/').description, 'A test site.');
    });

    test('canonical URLs resolve against the origin when one is set', () {
      final config = _config.copyWith(origin: Uri.parse('https://acme.dev'));
      expect(config.metaFor('/pricing').canonical, 'https://acme.dev/pricing');
      expect(_config.metaFor('/pricing').canonical, isNull);
    });
  });

  group('prose', () {
    final styles = SiteTextStyles.from(
      colors: SiteColors.dark,
      typography: const SiteTypography(),
    );

    String textOf(List<InlineSpan> spans) =>
        spans.map((s) => s.toPlainText()).join();

    test('splits inline code and bold out of plain runs', () {
      final spans = inlineSpans('use `run()` and **stop**', styles);
      expect(textOf(spans), 'use run() and stop');
    });

    test('bold may wrap inline code, keeping both styles', () {
      final spans = inlineSpans('call **`init()`** first', styles);
      expect(textOf(spans), 'call init() first');
      final bold = spans[1] as TextSpan;
      expect(bold.style!.fontWeight, FontWeight.w600);
      expect(
        (bold.children!.first as TextSpan).style!.fontFamily,
        styles.mono.fontFamily,
      );
    });

    test('leaves text with no markers alone', () {
      final spans = inlineSpans('nothing to see', styles);
      expect(spans, hasLength(1));
      expect(textOf(spans), 'nothing to see');
    });
  });

  group('sections', () {
    test('flattens groups into reading order', () {
      const groups = [
        PageSectionGroup('A', [PageSection('a1', 'A1'), PageSection('a2', 'A2')]),
        PageSectionGroup('B', [PageSection('b1', 'B1')]),
      ];
      expect(
        flattenSections(groups).map((s) => s.id),
        ['a1', 'a2', 'b1'],
      );
    });
  });

  group('widgets', () {
    testWidgets('SiteButton renders and fires', (tester) async {
      var taps = 0;
      await pumpSite(
        tester,
        Center(
          child: SiteButton(label: 'Press me', onPressed: () => taps++),
        ),
      );
      expect(find.text('Press me'), findsOneWidget);
      await tester.tap(find.text('Press me'));
      expect(taps, 1);
    });

    testWidgets('a disabled SiteButton ignores taps', (tester) async {
      await pumpSite(
        tester,
        const Center(child: SiteButton(label: 'Nope', onPressed: null)),
      );
      await tester.tap(find.text('Nope'));
      // Nothing to assert beyond "did not throw and did not call back"; the
      // callback is null, so a tap that reached it would have crashed.
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unregistered language degrades to plain text', (
      tester,
    ) async {
      await pumpSite(
        tester,
        const CodeBlock(
          code: 'not a real language',
          lang: 'definitely-not-registered',
          showLineNumbers: false,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('not a real language'), findsOneWidget);
    });

    testWidgets('the nav bar folds its links away when compact', (
      tester,
    ) async {
      await pumpSite(
        tester,
        const SiteNavBar(currentRoute: '/'),
        size: const Size(1400, 800),
      );
      expect(find.text('Docs'), findsOneWidget);

      await pumpSite(
        tester,
        const SiteNavBar(currentRoute: '/'),
        size: const Size(500, 800),
      );
      expect(find.text('Docs'), findsNothing);
    });

    testWidgets('ResponsiveGrid drops columns as it narrows', (tester) async {
      Widget grid() => ResponsiveGrid(
        columns: const ResponsiveValue<int>(xs: 1, sm: 2, md: 3),
        children: [
          for (var i = 0; i < 3; i++) SizedBox(height: 40, child: Text('$i')),
        ],
      );

      await pumpSite(tester, grid(), size: const Size(1400, 800));
      // One row of three: every cell shares the row's vertical position.
      expect(tester.getTopLeft(find.text('0')).dy,
          tester.getTopLeft(find.text('2')).dy);

      await pumpSite(tester, grid(), size: const Size(500, 800));
      expect(tester.getTopLeft(find.text('0')).dy,
          lessThan(tester.getTopLeft(find.text('2')).dy));
    });
  });
}
