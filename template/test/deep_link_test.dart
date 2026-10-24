import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kit/site_kit.dart';

const SiteConfig _config = SiteConfig(name: 'acme');

const List<PageSectionGroup> _groups = [
  PageSectionGroup('Getting started', [
    PageSection('install', 'Installation'),
    PageSection('config', 'Configuration'),
  ]),
  PageSectionGroup('Guides', [
    PageSection('routing', 'Routing & deep links'),
    PageSection('theming', 'Theming'),
    PageSection('engine', 'How the engine works'),
  ]),
];

final List<PageSection> _sections = flattenSections(_groups);

/// Mounts a [DocsShell] under the scopes `SiteApp` provides, with [section] as
/// the incoming deep link.
///
/// The browser fragment itself cannot be exercised here: `readUrlFragment`
/// resolves to the non-web stub under the VM. What this covers is everything
/// downstream of it, which is where the behavior lives.
Future<void> pumpDocs(
  WidgetTester tester, {
  String? section,
  bool deepLink = true,
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final controller = ThemeController(persist: false);
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    SiteConfigScope(
      config: _config,
      child: SiteThemeScope(
        controller: controller,
        child: NavSheetScope(
          controller: NavSheetController(),
          child: MaterialApp(
            theme: buildSiteTheme(Brightness.dark),
            home: Scaffold(
              body: DocsShell(
                groups: _groups,
                initialSectionId: section,
                deepLink: deepLink,
                sectionBuilder: (context, section, index) => [
                  // Tall enough that every section can be scrolled to.
                  SizedBox(height: 600, child: Text('body:${section.id}')),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // The deep-link jump runs in a post-frame callback, then corrects itself
  // once the layout has settled 300ms later.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Current offset of the page's own scroll view (the outermost one).
double pageOffset(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .pixels;

/// The link anchor after the [index]th heading, in reading order.
Finder anchorIcon(int index) => find
    .byWidgetPredicate((w) => w is SiteIcon && w.icon == SiteIcons.link)
    .at(index);

void main() {
  group('slugify', () {
    test('lowercases, drops punctuation, and hyphenates spaces', () {
      expect(slugify('Theming'), 'theming');
      expect(slugify('Quick start'), 'quick-start');
      expect(slugify('Routing & deep links'), 'routing-deep-links');
      expect(slugify('How the engine works'), 'how-the-engine-works');
    });

    test('collapses runs of separators and trims the ends', () {
      expect(slugify('  Spaced   out  '), 'spaced-out');
      expect(slugify('!!!Chains!!!'), 'chains');
      expect(slugify('a -- b'), 'a-b');
      expect(slugify('#chains'), 'chains');
    });

    test('keeps digits, and survives having nothing to keep', () {
      expect(slugify('Flutter 3.44 support'), 'flutter-3-44-support');
      expect(slugify('***'), '');
      expect(slugify(''), '');
    });

    test('is idempotent, so a slug re-normalizes to itself', () {
      for (final section in _sections) {
        expect(slugify(section.slug), section.slug);
      }
    });
  });

  group('PageSection.slug', () {
    test('derives from the title, not the id', () {
      expect(const PageSection('engine', 'How the engine works').slug,
          'how-the-engine-works');
      expect(const PageSection('routing', 'Routing & deep links').slug,
          'routing-deep-links');
    });
  });

  group('sectionIndexForSlug', () {
    int indexOfTitle(String title) =>
        _sections.indexWhere((s) => s.title == title);

    test('resolves a derived slug', () {
      expect(
        sectionIndexForSlug(_sections, 'routing-deep-links'),
        indexOfTitle('Routing & deep links'),
      );
    });

    test('resolves a raw fragment and a title', () {
      expect(sectionIndexForSlug(_sections, '#theming'),
          indexOfTitle('Theming'));
      expect(sectionIndexForSlug(_sections, 'Theming'),
          indexOfTitle('Theming'));
      expect(sectionIndexForSlug(_sections, 'THEMING'),
          indexOfTitle('Theming'));
    });

    test('falls back to the content id, keeping older links alive', () {
      // `engine` is the id; the heading now slugs to `how-the-engine-works`,
      // and both still resolve.
      expect(
        sectionIndexForSlug(_sections, 'engine'),
        indexOfTitle('How the engine works'),
      );
      expect(
        sectionIndexForSlug(_sections, 'routing'),
        indexOfTitle('Routing & deep links'),
      );
    });

    test('returns null for anything unknown', () {
      expect(sectionIndexForSlug(_sections, 'nope'), isNull);
      expect(sectionIndexForSlug(_sections, ''), isNull);
      expect(sectionIndexForSlug(_sections, '#'), isNull);
      expect(sectionIndexForSlug(const [], 'install'), isNull);
    });

    test('every section is reachable by its own slug and id', () {
      for (var i = 0; i < _sections.length; i++) {
        expect(sectionIndexForSlug(_sections, _sections[i].slug), i);
        expect(sectionIndexForSlug(_sections, _sections[i].id), i);
      }
    });
  });

  group('deep-link scrolling', () {
    testWidgets('no deep link leaves the page at the top', (tester) async {
      await pumpDocs(tester);
      expect(pageOffset(tester), 0);
    });

    testWidgets('a slug scrolls the page down', (tester) async {
      await pumpDocs(tester, section: 'theming');
      expect(pageOffset(tester), greaterThan(0));
    });

    testWidgets('a later section lands further down than an earlier one', (
      tester,
    ) async {
      await pumpDocs(tester, section: 'configuration');
      final config = pageOffset(tester);

      await pumpDocs(tester, section: 'theming');
      final theming = pageOffset(tester);

      expect(config, greaterThan(0));
      expect(theming, greaterThan(config));
    });

    testWidgets('a content id lands in the same place as its slug', (
      tester,
    ) async {
      await pumpDocs(tester, section: 'engine');
      final byId = pageOffset(tester);

      await pumpDocs(tester, section: 'how-the-engine-works');
      expect(byId, greaterThan(0));
      expect(pageOffset(tester), moreOrLessEquals(byId, epsilon: 1));
    });

    testWidgets('the first section is a no-op, not a scroll', (tester) async {
      await pumpDocs(tester, section: 'installation');
      expect(pageOffset(tester), 0);
    });

    testWidgets('an unknown slug leaves the page alone', (tester) async {
      await pumpDocs(tester, section: 'does-not-exist');
      expect(pageOffset(tester), 0);
    });
  });

  group('heading anchors', () {
    testWidgets('every heading carries one', (tester) async {
      await pumpDocs(tester);
      expect(
        find.byWidgetPredicate((w) => w is SiteIcon && w.icon == SiteIcons.link),
        findsNWidgets(_sections.length),
      );
    });

    testWidgets('they reveal in two stages: heading, then icon', (
      tester,
    ) async {
      await pumpDocs(tester);

      // The anchor sits under two AnimatedOpacity layers, one per stage. Their
      // product is what the reader actually sees, and multiplying is agnostic
      // to how they are nested.
      double visibleOpacity() => tester
          .widgetList<AnimatedOpacity>(
            find.ancestor(
              of: anchorIcon(0),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .fold(1, (total, layer) => total * layer.opacity);

      // At rest a heading is just a heading.
      expect(visibleOpacity(), 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      // Hovering the heading fades the anchor in, faded.
      await mouse.moveTo(tester.getCenter(find.text('Installation').last));
      await tester.pumpAndSettle();
      expect(visibleOpacity(), closeTo(0.32, 0.01));

      // Hovering the icon itself brings it to full.
      await mouse.moveTo(tester.getCenter(anchorIcon(0)));
      await tester.pumpAndSettle();
      expect(visibleOpacity(), 1);
    });

    testWidgets('clicking one does not move the page', (tester) async {
      await pumpDocs(tester);
      expect(pageOffset(tester), 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Installation').last));
      await tester.pumpAndSettle();

      // The reader is already looking at the heading they clicked; the anchor
      // hands them a link, it does not take them on a trip.
      await tester.tap(anchorIcon(0));
      await tester.pumpAndSettle();

      expect(pageOffset(tester), 0);
    });

    testWidgets('an unhovered anchor is not tappable', (tester) async {
      await pumpDocs(tester);
      // Opacity does not stop hit testing on its own; IgnorePointer does. On a
      // touch device, which never hovers, the anchor must not be a hidden
      // target beside every heading.
      expect(
        find
            .byWidgetPredicate(
              (w) => w is SiteIcon && w.icon == SiteIcons.link,
            )
            .hitTestable(),
        findsNothing,
      );
    });

    testWidgets('deepLink: false hides them', (tester) async {
      await pumpDocs(tester, deepLink: false);
      expect(
        find.byWidgetPredicate((w) => w is SiteIcon && w.icon == SiteIcons.link),
        findsNothing,
      );
      // The headings themselves are still there.
      expect(find.text('Installation'), findsWidgets);
    });

    testWidgets('deepLink: false still honours initialSectionId', (
      tester,
    ) async {
      await pumpDocs(tester, section: 'theming', deepLink: false);
      expect(pageOffset(tester), greaterThan(0));
    });
  });

  group('rail', () {
    testWidgets('selecting a section scrolls to it', (tester) async {
      await pumpDocs(tester);
      expect(pageOffset(tester), 0);

      // The rail tile, not the heading of the same name.
      await tester.tap(
        find.descendant(
          of: find.byType(SectionTile),
          matching: find.text('Theming'),
        ),
      );
      await tester.pumpAndSettle();

      expect(pageOffset(tester), greaterThan(0));
    });
  });
}
