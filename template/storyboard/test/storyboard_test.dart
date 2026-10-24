import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kit/site_kit.dart';
import 'package:storyboard/main.dart';
import 'package:storyboard/src/catalog/catalog.dart';
import 'package:storyboard/src/storyboard_config.dart';

/// Renders [child] the way the storyboard does: inside the config scope, the
/// theme, and a theme controller, at a viewport wide enough that nothing is
/// forced into its compact layout.
Future<void> pumpSpecimen(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    SiteConfigScope(
      config: storyboardConfig,
      child: SiteThemeScope(
        controller: ThemeController(persist: false),
        child: NavSheetScope(
          controller: NavSheetController(),
          child: MaterialApp(
            theme: buildSiteTheme(brightness),
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(width: 1400, child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('the catalog is well formed', (tester) async {
    expect(catalog, isNotEmpty);
    expect(allSpecimens.length, greaterThan(20));

    final ids = allSpecimens.map((s) => s.id).toList();
    expect(
      ids.toSet().length,
      ids.length,
      reason: 'specimen ids double as URLs, so they must be unique',
    );
    for (final specimen in allSpecimens) {
      expect(specimenById(specimen.id), same(specimen));
      expect(groupOf(specimen.id), isNotNull);
    }
  });

  // Each specimen renders on its own, so a failure names the frame that broke
  // rather than the whole canvas.
  for (final specimen in allSpecimens) {
    testWidgets('specimen "${specimen.id}" builds', (tester) async {
      await pumpSpecimen(tester, Builder(builder: specimen.builder));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('specimens build in light mode too', (tester) async {
    for (final specimen in allSpecimens.take(12)) {
      await pumpSpecimen(
        tester,
        Builder(builder: specimen.builder),
        brightness: Brightness.light,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '${specimen.id} failed in light mode',
      );
    }
  });

  testWidgets('the app boots and lays out the canvas', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const StoryboardApp());
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    // The rail lists every frame; the first group's title proves it rendered.
    expect(find.text(catalog.first.title.toUpperCase()), findsWidgets);
  });

  // The toolbar sheds controls as it narrows; these are the widths where it
  // would otherwise overflow.
  for (final width in [900.0, 600.0, 380.0]) {
    testWidgets('the canvas chrome fits at ${width.toInt()}px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const StoryboardApp());
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      if (width < 900) {
        // The rail is replaced by a button that opens the same list in a sheet.
        expect(find.text('Frames'), findsOneWidget);
        expect(find.text('Search frames'), findsNothing);
      } else {
        expect(find.text('Search frames'), findsOneWidget);
      }
    });
  }
}
