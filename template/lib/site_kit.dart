/// A template package for building Flutter web sites: design tokens,
/// light/dark theming, responsive primitives, URL routing, SEO metadata,
/// syntax-highlighted code, and a component library.
///
/// Start in `main`:
///
/// ```dart
/// import 'package:site_kit/site_kit.dart';
///
/// void main() async {
///   await SiteKit.init();
///   runApp(SiteApp(config: siteConfig, pages: pages));
/// }
/// ```
///
/// From there, `context.colors`, `context.text`, `context.brand`,
/// `context.site`, and `context.breakpoint` are the five lookups nearly every
/// widget needs.
///
/// This library re-exports the parts of `go_router` and `shiki_flutter` that
/// its own API asks for, so a page can call `context.go('/docs')` or name a
/// code theme from this one import.
library;

// Routing types leak through SitePage, SiteApp, and buildSiteRouter, and pages
// navigate with `context.go`, so the whole of go_router comes along rather than
// making every consumer add a second import for it.
export 'package:go_router/go_router.dart';
// Only the pieces `SiteKit.init(codeTheme:, codeLanguages:)` and
// `CodeBlock(theme:)` need. Import `package:shiki_flutter/shiki_flutter.dart`
// directly for the rest of that package.
export 'package:shiki_flutter/shiki_flutter.dart'
    show
        CodeLanguage,
        CodeLanguages,
        PierreThemes,
        ShikiDualTheme,
        ShikiTheme,
        ShikiThemeBase,
        ShikiThemes;

export 'src/app.dart';
export 'src/config/site_config.dart';
export 'src/highlight/highlighter_service.dart';
export 'src/init.dart';
export 'src/navigation/sections.dart';
export 'src/responsive/breakpoints.dart';
export 'src/router/site_router.dart';
export 'src/seo/page_meta.dart';
export 'src/theme/app_theme.dart';
export 'src/theme/context_extensions.dart';
export 'src/theme/site_palette.dart';
export 'src/theme/text_styles.dart';
export 'src/theme/theme_controller.dart'
    show ThemeController, SiteThemeScope, readStoredThemeMode;
export 'src/theme/tokens.dart';
export 'src/util/initial_fragment.dart';
export 'src/util/launch_link.dart';
export 'src/util/url_fragment.dart';
export 'src/widgets/code_block.dart';
export 'src/widgets/copy_button.dart';
export 'src/widgets/cta_band.dart';
export 'src/widgets/docs_shell.dart';
export 'src/widgets/dropdown.dart';
export 'src/widgets/feature_card.dart';
export 'src/widgets/footer.dart';
export 'src/widgets/hero.dart';
export 'src/widgets/inline_link_text.dart';
export 'src/widgets/nav_bar.dart';
export 'src/widgets/nav_sheet.dart';
export 'src/widgets/pills.dart';
export 'src/widgets/prose.dart';
export 'src/widgets/section.dart';
export 'src/widgets/site_button.dart';
export 'src/widgets/site_icon.dart';
export 'src/widgets/site_shell.dart';
export 'src/widgets/theme_switcher.dart';
export 'src/widgets/wordmark.dart';
