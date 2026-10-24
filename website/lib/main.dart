import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shiki_flutter/shiki_flutter.dart';

import 'src/router/app_router.dart';
import 'src/theme/app_theme.dart';
import 'src/theme/theme_controller.dart';
import 'src/util/initial_fragment.dart';
import 'src/widgets/nav_sheet.dart';

void main() {
  // Clean URLs for the web (/, /docs) instead of hash fragments.
  usePathUrlStrategy();
  // Grab the `#section` the visitor arrived with before the router can rewrite
  // the address bar and drop it. The docs page consumes this on mount to jump
  // to the linked section. See src/util/initial_fragment.dart.
  captureInitialUrlFragment();
  // The site ships as a release web build, where ConstraintLayout's debug
  // overlays are off by default. Opt in so the per-preview "chains" and
  // "blueprint" toggles on the home page actually render.
  ConstraintLayout.allowDebugFlags = true;
  // The docs render every code block live with shiki_flutter, themed with the
  // Pierre light/dark pair so the code follows the site's light/dark mode.
  //
  // Web uses the embedded engine (shiki_flutter's default, and its fastest on
  // web). asyncWeb pushes tokenization off the main thread onto a Web Worker:
  // the dart2js-compiled web/shiki_tokenize_worker.js, installed and refreshed on
  // upgrade with `dart run shiki_flutter:install --default`.
  //
  // Compiling that worker with dart2js is what keeps the embedded engine correct
  // here. Its RegExp fast path relies on Dart's RegExp lowering to the browser's
  // native regex, which holds under dart2js but NOT under this app's own dart2wasm
  // build (flutter build web --wasm). So the worker must stay installed: it is
  // the always-taken path once its `ready` handshake lands. If it ever fails to
  // load (missing file, a worker-blocking CSP, or a slow handshake), shiki_flutter
  // falls back to inline tokenization on the wasm main thread, where the embedded
  // engine's fast path breaks and code renders unhighlighted.
  ShikiHighlighter.config = const ShikiHighlighterConfig(
    webEngine: ShikiHighlighterEmbeddedEngine(),
    asyncWeb: true,
    defaultTheme: .dual(
      light: PierreThemes.pierreLight,
      dark: PierreThemes.pierreDark,
    ),
  );
  runApp(const ConstraintLayoutSite());
}

/// Root of the showcase site. Owns the [ThemeController] and rebuilds the app
/// when the light/dark mode changes.
class ConstraintLayoutSite extends StatefulWidget {
  const ConstraintLayoutSite({super.key});

  @override
  State<ConstraintLayoutSite> createState() => _ConstraintLayoutSiteState();
}

class _ConstraintLayoutSiteState extends State<ConstraintLayoutSite> {
  final ThemeController _theme = ThemeController();

  /// Bridges the docs page's section list to the app-wide nav popup. Lives above
  /// the router so the shell's nav bar and the docs page share one instance.
  final NavSheetController _navSheet = NavSheetController();

  @override
  void dispose() {
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme(
      controller: _theme,
      child: NavSheetScope(
        controller: _navSheet,
        child: ListenableBuilder(
          listenable: _theme,
          builder: (context, _) {
            return MaterialApp.router(
              title: 'flutter_constraint_layout: constraint-based layout for Flutter',
              debugShowCheckedModeBanner: false,
              theme: buildTheme(Brightness.light),
              darkTheme: buildTheme(Brightness.dark),
              themeMode: _theme.value,
              routerConfig: appRouter,
            );
          },
        ),
      ),
    );
  }
}
