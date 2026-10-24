import 'package:flutter_constraint_layout_website/src/data/docs_sections.dart';
import 'package:flutter_constraint_layout_website/src/pages/docs_page.dart';
import 'package:flutter_constraint_layout_website/src/theme/app_theme.dart';
import 'package:flutter_constraint_layout_website/src/theme/theme_controller.dart';
import 'package:flutter_constraint_layout_website/src/widgets/app_icon.dart';
import 'package:flutter_constraint_layout_website/src/widgets/nav_sheet.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mounts the docs page under the scopes the app provides, with a deep link
/// of [section] (a slug, a legacy id, or null for none).
///
/// The browser fragment itself cannot be exercised here: `readUrlFragment`
/// resolves to the non-web stub under the VM. What this covers is everything
/// downstream of it, which is where the behavior lives.
Future<void> pumpDocs(WidgetTester tester, {String? section}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final controller = ThemeController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    AppTheme(
      controller: controller,
      child: NavSheetScope(
        controller: NavSheetController(),
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(body: DocsPage(initialSection: section)),
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
double pageOffset(WidgetTester tester) {
  return tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;
}

void main() {
  group('slugify', () {
    test('lowercases, drops punctuation, and hyphenates spaces', () {
      expect(slugify('Chains'), 'chains');
      expect(slugify('Quick start'), 'quick-start');
      expect(slugify('Anchors & links'), 'anchors-links');
      expect(slugify('Centering & bias'), 'centering-bias');
      expect(slugify('A profile card'), 'a-profile-card');
      expect(slugify('How the engine works'), 'how-the-engine-works');
      expect(slugify('Relation to Android'), 'relation-to-android');
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
      for (final section in docsSections) {
        expect(slugify(section.slug), section.slug);
      }
    });
  });

  group('section slugs', () {
    test('every section has a non-empty, unique slug', () {
      final seen = <String, String>{};
      for (final section in docsSections) {
        expect(section.slug, isNotEmpty, reason: '"${section.title}"');
        expect(
          seen.containsKey(section.slug),
          isFalse,
          reason:
              'slug "${section.slug}" is shared by "${seen[section.slug]}" and '
              '"${section.title}"; two headings cannot deep-link to one anchor',
        );
        seen[section.slug] = section.title;
      }
    });

    test('legacy ids stay unique too, since lookup falls back to them', () {
      final ids = docsSections.map((s) => slugify(s.id)).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('docsSectionIndexForSlug', () {
    int indexOfTitle(String title) =>
        docsSections.indexWhere((s) => s.title == title);

    test('resolves a derived slug', () {
      expect(
        docsSectionIndexForSlug('anchors-links'),
        indexOfTitle('Anchors & links'),
      );
      expect(docsSectionIndexForSlug('chains'), indexOfTitle('Chains'));
    });

    test('resolves a raw fragment and a title', () {
      expect(docsSectionIndexForSlug('#chains'), indexOfTitle('Chains'));
      expect(docsSectionIndexForSlug('Quick start'), indexOfTitle('Quick start'));
      expect(docsSectionIndexForSlug('QUICK-START'), indexOfTitle('Quick start'));
    });

    test('falls back to the content id, keeping older links alive', () {
      // `engine` was the hand-written id; the heading now slugs to
      // `how-the-engine-works`, and both still resolve.
      expect(
        docsSectionIndexForSlug('engine'),
        indexOfTitle('How the engine works'),
      );
      expect(
        docsSectionIndexForSlug('circular'),
        indexOfTitle('Circular positioning'),
      );
      expect(
        docsSectionIndexForSlug('android'),
        indexOfTitle('Relation to Android'),
      );
    });

    test('returns null for anything unknown', () {
      expect(docsSectionIndexForSlug('nope'), isNull);
      expect(docsSectionIndexForSlug(''), isNull);
      expect(docsSectionIndexForSlug('#'), isNull);
    });

    test('every section is reachable by its own slug and id', () {
      for (var i = 0; i < docsSections.length; i++) {
        expect(docsSectionIndexForSlug(docsSections[i].slug), i);
        expect(docsSectionIndexForSlug(docsSections[i].id), i);
      }
    });
  });

  group('deep-link scrolling', () {
    testWidgets('no deep link leaves the page at the top', (tester) async {
      await pumpDocs(tester);
      expect(pageOffset(tester), 0);
    });

    testWidgets('a slug scrolls the page down', (tester) async {
      await pumpDocs(tester, section: 'chains');
      expect(pageOffset(tester), greaterThan(0));
    });

    testWidgets('a later section lands further down than an earlier one', (
      tester,
    ) async {
      await pumpDocs(tester, section: 'anchors-links');
      final anchors = pageOffset(tester);

      await pumpDocs(tester, section: 'grid');
      final grid = pageOffset(tester);

      expect(anchors, greaterThan(0));
      expect(grid, greaterThan(anchors));
    });

    testWidgets('a legacy id lands in the same place as its slug', (
      tester,
    ) async {
      await pumpDocs(tester, section: 'engine');
      final byId = pageOffset(tester);

      await pumpDocs(tester, section: 'how-the-engine-works');
      final bySlug = pageOffset(tester);

      expect(byId, greaterThan(0));
      expect(bySlug, moreOrLessEquals(byId, epsilon: 1));
    });

    testWidgets('the first section is a no-op, not a scroll', (tester) async {
      await pumpDocs(tester, section: 'introduction');
      expect(pageOffset(tester), 0);
    });

    testWidgets('an unknown slug leaves the page alone', (tester) async {
      await pumpDocs(tester, section: 'does-not-exist');
      expect(pageOffset(tester), 0);
    });
  });

  group('heading anchor', () {
    /// The link icon after the [index]th section heading, in reading order.
    Finder anchorIcon(int index) => find
        .byWidgetPredicate((w) => w is AppIcon && w.icon == DiffIcon.link)
        .at(index);

    testWidgets('every heading carries one', (tester) async {
      await pumpDocs(tester);
      expect(
        find.byWidgetPredicate((w) => w is AppIcon && w.icon == DiffIcon.link),
        findsNWidgets(docsSections.length),
      );
    });

    /// The heading text for section [index], as opposed to the rail tile of
    /// the same name.
    Finder headingText(int index) => find.byWidgetPredicate(
      (w) =>
          w is Text &&
          w.data == docsSections[index].title &&
          w.style?.fontSize == 30,
    );

    testWidgets('it reveals in two stages: heading, then icon', (tester) async {
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
      await mouse.moveTo(tester.getCenter(headingText(0)));
      await tester.pumpAndSettle();
      expect(visibleOpacity(), closeTo(0.32, 0.01));

      // Hovering the icon itself brings it to full.
      await mouse.moveTo(tester.getCenter(anchorIcon(0)));
      await tester.pumpAndSettle();
      expect(visibleOpacity(), 1);
    });

    testWidgets('clicking it does not move the page', (tester) async {
      await pumpDocs(tester);
      expect(pageOffset(tester), 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(headingText(0)));
      await tester.pumpAndSettle();

      // The reader is already looking at the heading they clicked; the anchor
      // hands them a link, it does not take them on a trip.
      await tester.tap(anchorIcon(0));
      await tester.pumpAndSettle();

      expect(pageOffset(tester), 0);
    });
  });
}
