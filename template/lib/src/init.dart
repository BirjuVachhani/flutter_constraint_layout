import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shiki_flutter/shiki_flutter.dart';

import 'highlight/highlighter_service.dart';
import 'util/initial_fragment.dart';

/// One-call setup for everything in the package that needs initializing before
/// the first frame.
///
/// Call it at the top of `main`, before `runApp`:
///
/// ```dart
/// void main() async {
///   await SiteKit.init();
///   runApp(SiteApp(config: siteConfig, pages: pages));
/// }
/// ```
///
/// It does five things:
///
/// 1. Ensures the Flutter binding, so it is safe to touch platform channels.
/// 2. Captures the `#fragment` the visitor arrived with, before the router can
///    rewrite the address bar and lose it. That is what makes `/docs#chains`
///    land on the right heading.
/// 3. Switches the web URL strategy to real paths (`/docs`, not `/#/docs`), so
///    links, refreshes, and deep links behave like a normal site. Remember the
///    server-side half: the host must serve `index.html` for unknown paths.
/// 4. Configures the shared syntax highlighter: engine, async mode, and the
///    light/dark code theme every `CodeBlock` defaults to.
/// 5. Optionally warms the highlighter by compiling its grammars up front, so
///    the first code block on screen paints already highlighted.
///
/// Every step is opt-out, so this stays usable in a test or inside a host app
/// that already owns part of the setup.
abstract final class SiteKit {
  static bool _initialized = false;

  /// Whether [init] has already run.
  static bool get isInitialized => _initialized;

  /// Initializes the package. Safe to call more than once; later calls with
  /// different arguments re-apply the configuration.
  static Future<void> init({
    bool usePathUrls = true,
    ShikiThemeBase? codeTheme,
    List<CodeLanguage>? codeLanguages,
    bool asyncHighlighting = true,
    ShikiHighlighterEngine? webEngine,
    ShikiHighlighterEngine? ioEngine,
    bool warmUpHighlighter = true,
    bool ensureBinding = true,
  }) async {
    if (ensureBinding) WidgetsFlutterBinding.ensureInitialized();

    // Grab the `#section` the visitor arrived with before the router can
    // rewrite the address bar and drop it. DocsShell consumes this on mount to
    // jump to the linked heading. See util/initial_fragment.dart.
    captureInitialUrlFragment();

    // Clean URLs on the web. A no-op off web: `flutter_web_plugins` resolves to
    // a non-web stub there.
    if (usePathUrls) usePathUrlStrategy();

    SiteHighlighter.configure(theme: codeTheme, languages: codeLanguages);
    final service = SiteHighlighter.instance;

    // Async highlighting keeps tokenization off the thread that is painting.
    //
    // On web that means a Web Worker, which has to be installed once per app
    // with `dart run shiki_flutter:install --default` (it writes
    // `web/shiki_tokenize_worker.js`). Without the worker file, shiki falls
    // back to tokenizing inline on the main thread: still correct under
    // dart2js, but under a `--wasm` build the embedded engine's RegExp fast
    // path does not hold and code can render unhighlighted. If you build with
    // `--wasm`, keep that worker installed.
    ShikiHighlighter.config = ShikiHighlighter.config.copyWith(
      webEngine: webEngine,
      ioEngine: ioEngine,
      asyncWeb: asyncHighlighting,
      asyncIO: asyncHighlighting,
      defaultTheme: service.theme,
      // Any bare shiki widget shares the site's preloaded highlighter and its
      // token cache, rather than spinning up a second one.
      defaultHighlighter: service.highlighter,
    );

    if (warmUpHighlighter) {
      // `preload` was already kicked off when the service built its
      // highlighter; awaiting the same grammars here just joins that work, so
      // the first paint is not the one that pays for the grammar compile.
      try {
        await service.highlighter.preload(
          langs: service.languages,
          themes: [
            service.theme.resolve(isDark: false),
            service.theme.resolve(isDark: true),
          ],
        );
      } catch (error, stack) {
        // A grammar that fails to compile must not take the app down: code
        // blocks degrade to plain text and everything else still runs.
        debugPrint('site_kit: highlighter warm-up failed: $error\n$stack');
      }
    }

    _initialized = true;
  }
}
