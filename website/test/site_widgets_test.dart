import 'package:flutter_constraint_layout_website/src/data/examples.dart';
import 'package:flutter_constraint_layout_website/src/data/snippets.dart';
import 'package:flutter_constraint_layout_website/src/theme/app_theme.dart';
import 'package:flutter_constraint_layout_website/src/theme/theme_controller.dart';
import 'package:flutter_constraint_layout_website/src/widgets/brand.dart';
import 'package:flutter_constraint_layout_website/src/widgets/code_block.dart';
import 'package:flutter_constraint_layout_website/src/widgets/copy_button.dart';
import 'package:flutter_constraint_layout_website/src/widgets/footer.dart';
import 'package:flutter_constraint_layout_website/src/widgets/nav_bar.dart';
import 'package:flutter_constraint_layout_website/src/widgets/pill.dart';
import 'package:flutter_constraint_layout_website/src/widgets/section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mounts [child] under the scopes the app provides, on a viewport [width]
/// logical pixels wide (below 900 the site uses its compact layout).
///
/// The test font is wider than the site's Geist faces, so text here runs
/// longer than in a browser: a layout that holds here holds with room to
/// spare there.
Future<void> pumpAt(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final controller = ThemeController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    AppTheme(
      controller: controller,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('InstallCommand', () {
    /// Mounts the pill the way the home hero does: in a Wrap inside the
    /// page's content column.
    Future<void> pumpPill(WidgetTester tester, double width, String command) {
      return pumpAt(
        tester,
        width,
        ContentContainer(
          child: Wrap(children: [InstallCommand(command: command)]),
        ),
      );
    }

    void expectCopyButtonInside(WidgetTester tester, String command) {
      final pill = tester.getRect(find.byType(InstallCommand));
      final copy = tester.getRect(
        find.descendant(
          of: find.byType(InstallCommand),
          matching: find.byType(CopyButton),
        ),
      );
      final text = tester.getRect(find.text(command));
      expect(pill.right, lessThanOrEqualTo(tester.view.physicalSize.width));
      expect(copy.left, greaterThanOrEqualTo(pill.left));
      expect(copy.right, lessThanOrEqualTo(pill.right));
      expect(text.left, greaterThanOrEqualTo(pill.left));
      expect(text.right, lessThanOrEqualTo(copy.left));
    }

    for (final width in [320.0, 390.0, 1280.0]) {
      testWidgets(
        'keeps the copy button inside the pill at ${width.toInt()}px',
        (tester) async {
          await pumpPill(tester, width, Snippets.install);
          expectCopyButtonInside(tester, Snippets.install);
        },
      );
    }

    testWidgets('fits a command of any length', (tester) async {
      final command = 'flutter pub add ${'a_much_longer_package_name' * 4}';
      await pumpPill(tester, 390, command);
      expectCopyButtonInside(tester, command);
    });
  });

  group('Brand', () {
    Finder wordmark() => find.text('flutter_constraint_layout');

    /// The wordmark's line box is 20px tall at its natural size.
    void expectNaturalSize(WidgetTester tester) {
      expect(tester.getRect(wordmark()).height, moreOrLessEquals(20));
    }

    for (final width in [200.0, 320.0, 390.0]) {
      testWidgets(
        'the wordmark clears the theme toggle at ${width.toInt()}px',
        (tester) async {
          await pumpAt(tester, width, const NavBar(currentRoute: '/'));
          final word = tester.getRect(wordmark());
          // The site starts in dark mode, so the toggle offers light mode.
          final toggle = tester.getRect(find.byTooltip('Light mode'));
          expect(word.left, greaterThanOrEqualTo(0));
          expect(word.right, lessThanOrEqualTo(toggle.left));
        },
      );
    }

    for (final width in [900.0, 1280.0]) {
      testWidgets(
        'a wide nav keeps the wordmark at full size and the tagline yields '
        'at ${width.toInt()}px',
        (tester) async {
          await pumpAt(tester, width, const NavBar(currentRoute: '/'));
          expectNaturalSize(tester);
          final word = tester.getRect(wordmark());
          final tagline = tester.getRect(
            find.textContaining('for Flutter by', findRichText: true),
          );
          expect(tagline.left, greaterThanOrEqualTo(word.right));
          expect(
            tagline.right,
            lessThanOrEqualTo(tester.getRect(find.text('Home')).left),
          );
        },
      );
    }
  });

  group('FooterBrand', () {
    Finder inBrand(Finder matching) =>
        find.descendant(of: find.byType(FooterBrand), matching: matching);
    Finder wordmark() => inBrand(find.text('flutter_constraint_layout'));
    Finder tagline() =>
        inBrand(find.textContaining('for Flutter by', findRichText: true));

    Future<void> pumpFooter(WidgetTester tester, double width) => pumpAt(
      tester,
      width,
      const SingleChildScrollView(child: SimpleFooter()),
    );

    for (final width in [320.0, 390.0]) {
      testWidgets(
        'a narrow footer sets the tagline below the wordmark at '
        '${width.toInt()}px',
        (tester) async {
          await pumpFooter(tester, width);
          final word = tester.getRect(wordmark());
          expect(word.left, greaterThanOrEqualTo(0));
          expect(word.right, lessThanOrEqualTo(width));
          // Below, with the footer's full width to itself, rather than
          // squeezed into whatever the wordmark leaves beside it.
          expect(
            tester.getRect(tagline()).top,
            greaterThanOrEqualTo(word.bottom),
          );
        },
      );
    }

    testWidgets('a wide footer keeps the tagline beside the wordmark', (
      tester,
    ) async {
      await pumpFooter(tester, 1280);
      final word = tester.getRect(wordmark());
      final line = tester.getRect(tagline());
      expect(line.top, moreOrLessEquals(word.top));
      expect(line.left, greaterThanOrEqualTo(word.right));
    });
  });

  group('CodeBlock', () {
    /// Mounts a header-less block the way the installation docs do:
    /// shrink-wrapped to its code at the start of the content column.
    Future<void> pumpBlock(
      WidgetTester tester,
      double width,
      String code,
      String lang,
    ) {
      return pumpAt(
        tester,
        width,
        ContentContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CodeBlock(code: code, lang: lang, showLineNumbers: false),
            ],
          ),
        ),
      );
    }

    Rect rectIn(WidgetTester tester, Finder matching) => tester.getRect(
      find.descendant(of: find.byType(CodeBlock), matching: matching),
    );

    /// The chip sits beside the code, never over it: the viewport the code
    /// scrolls in ends where the chip begins.
    void expectViewportClearsChip(WidgetTester tester) {
      expect(
        rectIn(tester, find.byType(Scrollable)).right,
        lessThanOrEqualTo(rectIn(tester, find.byType(CopyButton)).left),
      );
    }

    /// The last character of [code] lies inside the viewport, not clipped.
    void expectCodeEndVisible(WidgetTester tester, String code) {
      final text = rectIn(
        tester,
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == code,
        ),
      );
      final viewport = rectIn(tester, find.byType(Scrollable));
      expect(text.right, lessThanOrEqualTo(viewport.right));
    }

    ScrollPosition scrollPosition(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(CodeBlock),
            matching: find.byType(Scrollable),
          ),
        )
        .position;

    for (final (code, lang) in [
      (Snippets.install, 'shellscript'),
      (Snippets.importLine, 'dart'),
    ]) {
      testWidgets('the copy chip clears "$code" when it fits', (tester) async {
        await pumpBlock(tester, 1280, code, lang);
        // Nothing to scroll: the block is as wide as its code.
        expect(scrollPosition(tester).maxScrollExtent, 0);
        expectViewportClearsChip(tester);
        expectCodeEndVisible(tester, code);
      });

      testWidgets('the copy chip clears "$code" while it scrolls', (
        tester,
      ) async {
        await pumpBlock(tester, 390, code, lang);
        final position = scrollPosition(tester);
        // The block is narrower than its code at this width.
        expect(position.maxScrollExtent, greaterThan(0));
        expectViewportClearsChip(tester);

        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        expectViewportClearsChip(tester);
        expectCodeEndVisible(tester, code);
      });
    }
  });

  group('LiveExample debug toggles', () {
    for (final width in [320.0, 390.0]) {
      testWidgets('the preview header fits at ${width.toInt()}px', (
        tester,
      ) async {
        // Use the shipped fonts: the fallback test font makes even the two
        // toggle labels alone wider than a 320px preview's header.
        final mono = FontLoader('Geist Mono')
          ..addFont(rootBundle.load('assets/fonts/GeistMono-500.ttf'));
        final sans = FontLoader('Geist')
          ..addFont(rootBundle.load('assets/fonts/Geist-400.ttf'));
        await mono.load();
        await sans.load();
        await pumpAt(
          tester,
          width,
          SingleChildScrollView(
            child: ContentContainer(
              child: docExamples['quick-start']!.capped(440),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final chains = tester.getRect(find.text('chains'));
        final blueprint = tester.getRect(find.text('blueprint'));
        expect(chains.right, lessThanOrEqualTo(blueprint.left));
        expect(blueprint.right, lessThanOrEqualTo(width - 20));
      });
    }

    testWidgets('announce their label once and toggle from a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpAt(
        tester,
        1280,
        SingleChildScrollView(child: docExamples['quick-start']!.capped(440)),
      );

      for (final label in ['chains', 'blueprint']) {
        expect(
          tester.getSemantics(find.text(label)),
          isSemantics(
            label: label,
            isButton: true,
            hasToggledState: true,
            isToggled: false,
            hasTapAction: true,
          ),
        );
      }

      tester.semantics.tap(find.semantics.byLabel('blueprint'));
      await tester.pump();
      expect(
        tester.getSemantics(find.text('blueprint')),
        isSemantics(label: 'blueprint', isToggled: true),
      );
      semantics.dispose();
    });
  });
}
