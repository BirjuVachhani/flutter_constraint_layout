# site_kit

A template package for building Flutter web sites: design tokens, light and
dark theming, responsive layout primitives, URL routing, SEO metadata,
syntax-highlighted code, and a component library.

It is the theme and chrome behind a documentation site, extracted so the next
site starts at "write the content" instead of "build a nav bar".

```dart
import 'package:site_kit/site_kit.dart';

Future<void> main() async {
  await SiteKit.init();
  runApp(SiteApp(config: siteConfig, pages: pages));
}
```

One import. `site_kit` re-exports `go_router` and the `shiki_flutter` types its
own API uses, so `context.go('/docs')` and `ShikiThemes.githubDark` work
without a second dependency.

---

## Contents

**Setup**
[Requirements](#requirements) ·
[Install](#install) ·
[SiteKit.init](#sitekitinit) ·
[Web project setup](#web-project-setup) ·
[Deploying](#deploying) ·
[Other platforms](#other-platforms)

**Usage**
[The five lookups](#the-five-lookups) ·
[Configure the site](#configure-the-site) ·
[Routes and pages](#routes-and-pages) ·
[Layout and sections](#layout-and-sections) ·
[Responsive layout](#responsive-layout) ·
[Components](#components) ·
[Documentation pages](#documentation-pages) ·
[SEO](#seo)

**Customization**
[Palette](#palette) ·
[Typography](#typography) ·
[Logo and wordmark](#logo-and-wordmark) ·
[Navigation chrome](#navigation-chrome) ·
[Footers](#footers) ·
[Code themes and languages](#code-themes-and-languages) ·
[Your own components](#your-own-components)

**Advanced**
[Owning the router](#owning-the-router) ·
[Pages without the shell](#pages-without-the-shell) ·
[Custom section navigators](#custom-section-navigators) ·
[Theme control and persistence](#theme-control-and-persistence) ·
[Selection and copy](#selection-and-copy) ·
[Testing](#testing) ·
[Bundle size and performance](#bundle-size-and-performance)

**Reference**
[API index](#api-index) ·
[Troubleshooting](#troubleshooting) ·
[Storyboard](#storyboard) ·
[Package layout](#package-layout)

---

## What you get

| Area | What ships |
| --- | --- |
| Tokens | `SiteColors`, `BrandPalette`, `SiteTextStyles`, `SiteSpacing`, `SiteRadii`, `SiteLayout`, `SiteMotion`, `SiteFonts` |
| Theming | `buildSiteTheme`, `ThemeController` with a persisted System / Light / Dark choice |
| Responsive | `Breakpoint`, `ResponsiveValue`, `ResponsiveBuilder`, `ResponsiveGrid`, `context.isCompact` |
| Routing | `SiteApp`, `SitePage`, `buildSiteRouter`, path URLs, per-route document metadata |
| Chrome | `SiteShell`, `SiteNavBar`, `showSiteNavSheet`, `SiteFooter`, `CompactFooter`, `Wordmark`, `LogoMark` |
| Content | `CodeBlock`, `Prose`, `ProseHeading`, `ProseList`, `ProseTable`, `Callout`, `InlineLinkText` |
| Blocks | `HeroSection`, `FeatureGrid`, `CtaBand`, `SiteSection`, `SectionHeading`, `DocsShell` |
| Controls | `SiteButton`, `SiteIconButton`, `SiteBadge`, `SelectPill`, `PillGroup`, `CommandPill`, `CopyButton`, `SiteDropdown`, `ThemeModeMenu` |
| Assets | Geist and Geist Mono, plus an 18-glyph SVG icon set, bundled in the package |

Every component reads its colors and type from the theme, so one palette swap
re-skins the whole site.

---

# Setup

## Requirements

- Flutter 3.44 or newer, Dart SDK 3.12 or newer.
- Built for the web. It runs on desktop and mobile too, with the web-only
  pieces degrading to no-ops (see [Other platforms](#other-platforms)).

## Install

Add the package. It is not published to pub.dev, so depend on it by path or by
git:

```yaml
dependencies:
  site_kit:
    path: ../template
```

```yaml
dependencies:
  site_kit:
    git:
      url: https://github.com/BirjuVachhani/flutter_constraint_layout.git
      path: template
```

The git form tracks the repository's default branch; add a `ref:` (a commit or
a tag) under `git:` to pin the version you build against.

Then:

```bash
flutter pub get
dart run shiki_flutter:install --default
```

The second command writes `web/shiki_tokenize_worker.js` into **your** app, not
into the package. It is what keeps syntax highlighting off the main thread. See
[Web project setup](#web-project-setup).

Nothing else goes in your `pubspec.yaml`. The fonts and icons are declared by
the package, so they arrive with the dependency.

## SiteKit.init

Call it once, before `runApp`:

```dart
Future<void> main() async {
  await SiteKit.init();
  runApp(SiteApp(config: siteConfig, pages: pages));
}
```

It does five things:

1. **Ensures the Flutter binding**, so it is safe to touch platform channels.
2. **Captures the `#fragment` the page booted with**, before the router can
   rewrite the address bar and drop it, so `/docs#theming` lands on that
   heading (see [Deep links](#deep-links)).
3. **Switches the web URL strategy to real paths**: `/docs`, not `/#/docs`.
4. **Configures the shared syntax highlighter**: regex engine, async mode, and
   the light/dark code theme every `CodeBlock` defaults to.
5. **Warms the highlighter** by compiling its grammars up front, so the first
   code block on screen paints already highlighted rather than as plain text
   that swaps a frame later.

Every step except the fragment capture (a no-op off web) can be switched off or
tuned:

```dart
await SiteKit.init(
  // Keep hash URLs, e.g. when the host cannot be configured for a fallback.
  usePathUrls: false,

  // Any single theme or light/dark pair from shiki_flutter.
  codeTheme: const ShikiDualTheme(
    light: ShikiThemes.githubLight,
    dark: ShikiThemes.githubDark,
  ),

  // Only the grammars this site actually renders.
  codeLanguages: [CodeLanguages.dart, CodeLanguages.json],

  // Tokenize inline instead of on a worker or isolate.
  asyncHighlighting: false,

  // Skip the grammar precompile; the first block then swaps in when ready.
  warmUpHighlighter: false,

  // Swap the regex engine. ShikiHighlighterNativeEngine is ~2.4x faster on
  // desktop and comes from the separate shiki_flutter_native_engine package,
  // which you would add and import yourself.
  ioEngine: const ShikiHighlighterNativeEngine(),

  // Already called WidgetsFlutterBinding.ensureInitialized() yourself.
  ensureBinding: false,
);
```

`SiteKit.isInitialized` reports whether it has run. Calling `init` again
re-applies the configuration and rebuilds the highlighter, dropping its token
cache with it.

| Parameter | Default | Effect |
| --- | --- | --- |
| `usePathUrls` | `true` | `usePathUrlStrategy()` on web, no-op elsewhere |
| `codeTheme` | Pierre light/dark pair | Default theme for `CodeBlock` |
| `codeLanguages` | `dart`, `yaml`, `shellscript`, `json` | Grammars registered by id |
| `asyncHighlighting` | `true` | Web Worker on web, isolate on native |
| `webEngine` / `ioEngine` | shiki defaults | Regex engine per platform |
| `warmUpHighlighter` | `true` | Await grammar compilation before the first frame |
| `ensureBinding` | `true` | Call `WidgetsFlutterBinding.ensureInitialized()` |

## Web project setup

Three files in your app's `web/` directory matter.

**`web/index.html`** carries the static SEO and social tags. Social scrapers do
not run Dart, so whatever is here is what a shared link previews as, on every
route:

```html
<title>acme: the short pitch</title>
<meta name="description" content="One sentence about the site.">
<link rel="canonical" href="https://acme.dev/">
<meta name="theme-color" content="#0A0A0A">

<meta property="og:type" content="website">
<meta property="og:site_name" content="acme">
<meta property="og:title" content="acme: the short pitch">
<meta property="og:description" content="One sentence about the site.">
<meta property="og:url" content="https://acme.dev/">
<meta property="og:image" content="https://acme.dev/banner.png">
<meta name="twitter:card" content="summary_large_image">
```

Add a background color so the first paint is not a white flash in dark mode:

```html
<style>
  html, body { margin: 0; background-color: #0A0A0A; }
  @media (prefers-color-scheme: light) {
    html, body { background-color: #FFFFFF; }
  }
</style>
```

**`web/shiki_tokenize_worker.js`** comes from
`dart run shiki_flutter:install --default`. Re-run that after every
`shiki_flutter` upgrade. Without it, tokenization falls back to the main
thread.

**`web/robots.txt` and `web/sitemap.xml`** are worth writing by hand for a
client-rendered site, since there is nothing to crawl your links from.

## Deploying

- **Path URLs need a server-side fallback.** The host must serve `index.html`
  for unknown paths, or a refresh on `/docs` returns a 404. On GitHub Pages,
  copy `index.html` to `404.html` as part of the build. On Netlify, add a
  `/* /index.html 200` rewrite. On Firebase Hosting, set
  `"rewrites": [{"source": "**", "destination": "/index.html"}]`.
- **Serving from a sub-path?** Build with
  `flutter build web --base-href /my-site/`.
- **If you build with `--wasm`, the shiki worker is not optional.** The
  embedded regex engine's fast path relies on Dart's RegExp lowering to the
  browser's native regex. That holds in the dart2js-compiled worker, but not
  under dart2wasm on the main thread. Without the worker installed, code
  renders unhighlighted.

## Other platforms

The package is web-first but not web-only. On desktop and mobile:

- `usePathUrlStrategy()` resolves to a non-web stub and does nothing.
- Document metadata (`SeoMeta`) resolves to a no-op stub, so nothing throws.
- The theme choice is in memory only; there is no `localStorage` to persist it.
- Everything else, including the highlighter, works unchanged.

That is what makes the widget tests in this package run under the plain VM.

---

# Usage

## The five lookups

Nearly every widget you write needs one of these:

```dart
context.colors.border      // semantic color tokens (SiteColors)
context.text.h2            // the named type ramp (SiteTextStyles)
context.brand.azure        // vivid brand hues (BrandPalette)
context.site.navLinks      // the SiteConfig
context.breakpoint         // xs / sm / md / lg / xl
```

Plus the small conveniences: `context.isCompact`, `context.isDesktop`,
`context.isDarkMode`, `context.screenWidth`, `context.screenHeight`, and
`context.responsive<T>(xs: ..., md: ...)`.

`context.colors` and `context.text` read theme extensions, so they only resolve
under a theme built by `buildSiteTheme`. `SiteApp` does that for you.

### Token cheat sheet

| Token | Values |
| --- | --- |
| `SiteColors` | `background`, `surface`, `surfaceInset`, `border`, `borderStrong`, `foreground`, `mutedForeground`, `primary`, `onPrimary`, `accent`, `link`, `danger`, `navBackground`, `shadow` |
| `SiteTextStyles` | `display`, `h1`, `h2`, `h3`, `h4`, `lede`, `body`, `bodySmall`, `label`, `caption`, `overline`, `mono`, `wordmark` |
| `BrandPalette` | `azure`, `cyan`, `green`, `lime`, `gold`, `orange`, `coral`, `pink`, `magenta`, `purple`, plus `canvas`, `canvasGrid`, `canvasBorder`, `guide`, and `swatch(i)` |
| `SiteSpacing` | `xxs` 4, `xs` 8, `sm` 12, `md` 16, `lg` 24, `xl` 32, `xxl` 48, `xxxl` 64, `sectionCompact` 56, `sectionWide` 96 |
| `SiteRadii` | `xs` 6, `sm` 8, `md` 10, `lg` 14, `xl` 20, `pill` 999 |
| `SiteLayout` | `contentMaxWidth` 1240, `readingMaxWidth` 768, `proseMaxWidth` 672, `gutter` 20, `navHeight` 60, `railWidth` 220 |
| `SiteMotion` | `fast` 120ms, `medium` 220ms, `slow` 420ms, `enter`, `standard` |

`named` returns a name-to-value map: as a getter on any `SiteColors`,
`BrandPalette`, or `SiteTextStyles` instance (`context.colors.named`), and as
the static `SiteSpacing.named` and `SiteRadii.named`. That is how the
storyboard renders its style guides.

## Configure the site

One object describes the brand, the navigation, the footer, the palette, and
the SEO defaults:

```dart
final siteConfig = SiteConfig(
  name: 'acme',
  tagline: 'for Flutter by',
  author: const SiteAuthor(name: 'You', url: 'https://github.com/you'),
  description: 'One sentence, used as the default meta description.',
  origin: Uri.parse('https://acme.dev'),
  navLinks: const [
    NavItem.route('Home', '/'),
    NavItem.route('Docs', '/docs'),
    NavItem.external('pub.dev', 'https://pub.dev/packages/acme'),
  ],
  navActions: const [
    NavItem.action(
      label: 'GitHub',
      icon: SiteIcons.github,
      url: 'https://github.com/you/acme',
    ),
  ],
  footerColumns: const [
    FooterColumn('Product', [
      NavItem.route('Home', '/'),
      NavItem.route('Docs', '/docs'),
    ]),
    FooterColumn('Resources', [
      NavItem.external('GitHub', 'https://github.com/you/acme'),
    ]),
  ],
  footerBlurb: 'A longer paragraph for the footer, if the description is too '
      'terse there.',
  copyright: '© 2026 Acme',
  pageMeta: const {
    '/docs': SeoMeta(
      title: 'Documentation: acme',
      description: 'Guides for acme: installation, configuration, theming.',
    ),
  },
);
```

`SiteConfig` is `const`-constructible as long as you do not set `origin`, since
`Uri.parse` is not a `const` constructor. Use `final` when you do.

| Field | Purpose |
| --- | --- |
| `name` | The wordmark, rendered in the mono family. Also the fallback page title |
| `description` | Default meta description, and the footer blurb fallback |
| `tagline` | Short phrase after the wordmark, e.g. `for Flutter by` |
| `author` | Name and optional profile URL, credited after the tagline |
| `origin` | Canonical origin, e.g. `Uri.parse('https://acme.dev')`. Required for canonical and `og:url` tags |
| `logo` | `(context, size) => Widget`. Defaults to a monogram tile |
| `navLinks` | Text links in the nav bar and the mobile sheet |
| `navActions` | Icon buttons at the right of the nav bar; labeled rows in the sheet |
| `footerColumns` | Link columns in `SiteFooter` |
| `footerBlurb` | Paragraph under the wordmark in `SiteFooter` |
| `copyright` | Small print at the bottom of either footer |
| `palette` | Semantic colors and brand hues, per brightness |
| `typography` | Font families and the heading scale |
| `pageMeta` | Per-route `SeoMeta`, keyed by path |

### NavItem

Four ways to build one:

```dart
const NavItem.route('Docs', '/docs')                       // in-app navigation
const NavItem.external('pub.dev', 'https://pub.dev/...')   // opens a new tab
const NavItem.action(                                       // icon-only button
  label: 'GitHub',
  icon: SiteIcons.github,
  url: 'https://github.com/you/acme',
)
NavItem(label: 'Search', onTap: openSearch, materialIcon: Icons.search)
```

Exactly one destination is required: `route`, `url`, or `onTap`. External items
get a trailing up-right arrow wherever they are listed. `isActive` treats a
route as active on its own sub-paths, so `/docs` stays highlighted on
`/docs/routing`, while `/` matches exactly.

## Routes and pages

```dart
runApp(SiteApp(
  config: siteConfig,
  pages: [
    SitePage(path: '/', builder: (context, state) => const HomePage()),
    SitePage(
      path: '/docs',
      name: 'docs',
      builder: (context, state) => DocsPage(
        section: state.uri.queryParameters['section'],
      ),
    ),
    SitePage(
      path: '/changelog',
      meta: const SeoMeta(
        title: 'Changelog: acme',
        description: 'What changed in every release.',
      ),
      builder: (context, state) => const ChangelogPage(),
    ),
  ],
  notFoundBuilder: (context, state) => const NotFoundPage(),
));
```

`SiteApp` installs four things above the router: the config scope, the theme
controller, the nav-sheet bridge, and the `MaterialApp.router` itself. Each
`SitePage` becomes a `GoRoute` with a `NoTransitionPage`, wrapped in
`SiteShell`, which is what a website should feel like: no slide, no fade, just
the new page.

| `SitePage` field | Purpose |
| --- | --- |
| `path` | URL path, e.g. `/` or `/docs/:id` |
| `builder` | `(context, GoRouterState state) => Widget` |
| `name` | Optional route name for `context.goNamed('docs')` |
| `meta` | Per-route document metadata; overrides `SiteConfig.pageMeta` |
| `shell` | Wrap in `SiteShell`. Default `true` |
| `themeControl` | `ThemeControl.toggle`, `.menu`, or `.none` for this page's nav |
| `children` | Nested `RouteBase`s |

| `SiteApp` field | Purpose |
| --- | --- |
| `config` | The `SiteConfig` |
| `pages` | The routes. Ignored when `router` is set |
| `router` | A `GoRouter` you built yourself |
| `title` | OS-level app title. Defaults to `config.name` |
| `initialThemeMode` | Overrides the persisted choice. Mostly for tests |
| `initialLocation` | First route. Default `/` |
| `notFoundBuilder` | Body of the 404 page. Without one, unknown paths render the first page |
| `builder` | `TransitionBuilder` wrapping the navigator, below the theme |

Navigate with go_router, re-exported by this package:

```dart
context.go('/docs');
context.go('/docs?section=routing');
context.goNamed('docs');
```

## Layout and sections

Three widgets carry the page rhythm:

```dart
// The shared horizontal column: 1240px wide with 20px gutters. Every section
// that uses it lines up on the same left and right edges, at every width.
ContentContainer(child: ...)

// A ContentContainer with vertical padding that follows the breakpoint
// (56px compact, 96px wide), plus an optional full-bleed background.
SiteSection(
  background: context.colors.surface,
  border: true,     // hairline along the top edge
  top: 32,          // override the breakpoint padding
  child: ...,
)

// Eyebrow, title, subtitle with inline links, and an optional trailing action
// (dropped on compact widths).
SectionHeading(
  eyebrow: 'Guides',
  title: 'Everything in one import.',
  subtitle: 'Read the go_router docs for the routing half.',
  subtitleLinks: const [
    TextLink('go_router', url: 'https://pub.dev/packages/go_router'),
  ],
  trailing: SiteButton(label: 'All guides', size: SiteButtonSize.sm, onPressed: ...),
)
```

A whole landing page, using only exported pieces:

```dart
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HeroSection(
            headline: 'Constraint-based layout for Flutter.',
            lede: 'A faithful port of ConstraintLayout, in pure Dart.',
            actions: [
              const CommandPill(command: 'flutter pub add acme'),
              SiteButton(
                label: 'Documentation',
                variant: SiteButtonVariant.secondary,
                leadingMaterialIcon: Icons.menu_book_rounded,
                onPressed: () => context.go('/docs'),
              ),
            ],
          ),
          SiteSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeading(
                  title: 'Everything a docs site needs.',
                  subtitle: 'One config object, and the chrome is done.',
                ),
                const SizedBox(height: SiteSpacing.xl),
                FeatureGrid(features: features),
              ],
            ),
          ),
          CtaBand(
            title: 'Free and open source.',
            body: 'Star the repo, open an issue, or pull it from pub.dev.',
            actions: [
              SiteButton(
                label: 'View on GitHub',
                leadingIcon: SiteIcons.github,
                trailingIcon: SiteIcons.arrowUpRight,
                size: SiteButtonSize.sm,
                onPressed: () => openLink('https://github.com/you/acme'),
              ),
            ],
          ),
          const CompactFooter(),
        ],
      ),
    );
  }
}
```

Note what is absent: no `Scaffold`, no nav bar, no `SelectionArea`. `SiteShell`
supplies all three. `HeroSection` already pads past the sticky nav, so it goes
straight at the top of the body.

## Responsive layout

```dart
// Which band the viewport is in.
if (context.isCompact) { ... }              // below md (900px)
switch (context.breakpoint) { ... }         // xs / sm / md / lg / xl

// A value per band, cascading down to the nearest one that is set.
const columns = ResponsiveValue<int>(xs: 1, sm: 2, lg: 4);
final count = columns.resolve(context);

// Inline, without allocating.
final padding = context.responsive<double>(xs: 16, md: 32, xl: 48);

// Different subtrees per band. Measures the PARENT's constraints, not the
// window, so a panel inside a split view adapts like a small window would.
ResponsiveBuilder(
  builder: (context, breakpoint, constraints) => breakpoint.isCompact
      ? const _Stacked()
      : const _SideBySide(),
)

// A grid where every card in a row takes the tallest card's height, which a
// Wrap cannot do.
ResponsiveGrid(
  columns: const ResponsiveValue<int>(xs: 1, sm: 2, md: 3),
  spacing: SiteSpacing.md,
  children: cards,
)
```

| Band | Width | Notes |
| --- | --- | --- |
| `xs` | `< 600` | Phones |
| `sm` | `>= 600` | Large phones, small tablets |
| `md` | `>= 900` | The compact cutoff: nav links and side rails fold below this |
| `lg` | `>= 1200` | Desktop; `context.isDesktop` |
| `xl` | `>= 1536` | Wide desktop |

## Components

### Buttons

```dart
SiteButton(
  label: 'Get started',
  variant: SiteButtonVariant.primary,   // primary secondary outline ghost danger
  size: SiteButtonSize.md,              // sm md lg
  leadingIcon: SiteIcons.github,        // bundled glyph
  trailingMaterialIcon: Icons.east,     // or any Material glyph
  expand: false,                        // stretch to the parent width
  busy: false,                          // spinner in place of the leading icon
  tooltip: 'Start here',
  onPressed: () {},                     // null disables it
)

SiteIconButton(
  icon: SiteIcons.github,
  tooltip: 'GitHub',
  selected: false,                      // filled resting state, for a toggle
  onPressed: () {},
)
```

### Badges and pills

```dart
SiteBadge('v1.0.0', icon: SiteIcons.folders)
SiteBadge('Passing', tone: BadgeTone.accent, filled: true)   // neutral accent link danger

SelectPill(label: 'Dart', selected: true, onTap: () {})

PillGroup<String>(
  values: const ['Dart', 'YAML', 'Shell'],
  selected: language,
  labelOf: (value) => value,
  onChanged: (value) => setState(() => language = value),
)

// A shell command with a copy button. Stays dark in both modes.
CommandPill(command: 'flutter pub add acme', prompt: r'$')

CopyButton(text: 'copied to the clipboard', onCopied: () {})
```

### Code blocks

```dart
CodeBlock(
  code: source,
  lang: 'dart',                 // an id registered with SiteHighlighter
  filename: 'main.dart',        // adds a header bar; moves the copy button into it
  showLineNumbers: true,
  showCopy: true,
  fontSize: 13,
  showDividers: false,          // hairline under the header
  theme: PierreThemes.pierreDark,  // pin a theme instead of following the site
  margin: EdgeInsets.zero,
)
```

Unregistered languages render as plain monospaced text rather than throwing, so
an unexpected fenced language in authored content degrades quietly. Long lines
scroll horizontally inside the card; the block never traps the page's vertical
scroll.

### Prose

```dart
const ProseHeading('Anchors and links', level: 2)   // 2, 3, or 4
const Prose('Body copy at a 768px measure. Inline `code` and **bold** work.')
const ProseList(['First point.', 'Second point.'])
const ProseList(['Add the package.', 'Call init.'], ordered: true)
const ProseTable(
  headers: ['Property', 'Type', 'Description'],
  rows: [
    ['`name`', '`String`', 'The wordmark.'],
  ],
)
const Callout('A caveat worth boxing.', tone: CalloutTone.tip, title: 'Tip')
```

Every string supports a small Markdown subset: `` `code` `` renders as plain
mono and `**bold**` as semibold, and bold may wrap code. A table cell that is
exactly one code token renders as a chip. `inlineSpans(text, context.text)` is
exported if you want that parsing in your own widget.

### Links in copy

```dart
InlineLinkText(
  'Read the Flutter docs, or jump to installation.',
  links: const [
    TextLink('Flutter docs', url: 'https://docs.flutter.dev'),
    TextLink('installation', route: '/docs?section=install'),
  ],
)

InlineLinkText.single('One link inline.', label: 'One link', url: '...')
```

Labels are matched left to right, overlaps are skipped, and labels that do not
appear are dropped rather than throwing. The widget owns and disposes the
gesture recognizers, so callers stay stateless.

### Feature cards

```dart
FeatureGrid(
  columns: const ResponsiveValue<int>(xs: 1, sm: 2, md: 3),
  features: [
    Feature(
      title: 'Design tokens',
      description: 'Colors, type, spacing, and radii as theme extensions.',
      materialIcon: Icons.palette_outlined,
      color: context.brand.azure,     // defaults to the brand's primary hue
      onTap: () => context.go('/docs?section=tokens'),
    ),
  ],
)
```

### Menus and dropdowns

```dart
SiteDropdown.alignRight(
  triggerBuilder: (context, open, toggle) => SiteButton(
    label: 'Actions',
    variant: SiteButtonVariant.secondary,
    size: SiteButtonSize.sm,
    trailingIcon: SiteIcons.chevronDown,
    onPressed: toggle,
  ),
  overlayBuilder: (context, close) => MenuPanel(
    width: 210,
    children: [
      MenuItemRow(
        label: 'Copy as Markdown',
        icon: SiteIcons.copy,
        onTap: () { close(); copyMarkdown(); },
      ),
      const MenuSeparator(),
      MenuItemRow(
        label: 'Open in a new tab',
        icon: SiteIcons.arrowUpRight,
        selected: false,
        onTap: () { close(); openLink(url); },
      ),
    ],
  ),
)
```

Built on `OverlayPortal` rather than `MenuAnchor`, so the popup has a real
opaque surface, a controlled fade and scale on open, and an outside tap that
closes it. Use the default constructor with `targetAnchor`, `followerAnchor`,
`panelAlignment`, `scaleAlignment`, and `offset` for other placements.

### Icons

```dart
SiteIcon(SiteIcons.github, size: 18, color: context.colors.foreground)
```

The bundled set is `copy`, `check`, `fileCode`, `chevronDown`, `colorAuto`,
`colorDark`, `colorLight`, `sun`, `moon`, `github`, `discord`, `arrowUpRight`,
`arrowRight`, `x`, `menu`, `refresh`, `folders`, `link`. Anything else is a
Material glyph: every component that takes a `SiteIcons` also takes an
`IconData`, and `AnyIcon` renders whichever is set.

Glyphs are tinted with `BlendMode.srcIn`, which preserves per-path alpha, so
multi-opacity icons keep their depth.

## Documentation pages

`DocsShell` is the sticky rail, the reading column, the scroll-spy, and the
compact breadcrumb bar in one widget.

```dart
const docsGroups = [
  PageSectionGroup('Getting started', [
    PageSection('install', 'Installation'),
    PageSection('config', 'Configuration'),
  ]),
  PageSectionGroup('Theming', [
    PageSection('tokens', 'Design tokens'),
    PageSection('palette', 'Custom palettes'),
  ]),
];

class DocsPage extends StatelessWidget {
  const DocsPage({super.key, this.section});

  final String? section;

  @override
  Widget build(BuildContext context) {
    return DocsShell(
      groups: docsGroups,
      initialSectionId: section,          // from ?section= in the URL
      header: const DocsActions(),        // optional, above the first section
      footer: const SiteFooter(),
      sectionBuilder: (context, section, index) => switch (section.id) {
        'install' => const [
          Prose('Add `acme` to your pubspec.'),
          CodeBlock(code: 'flutter pub add acme', lang: 'shellscript'),
        ],
        'config' => const [Prose('Describe the site once.')],
        _ => const [Prose('TODO')],
      },
    );
  }
}
```

Behavior worth knowing:

- The shell renders each section's title for you. Set `showSectionTitles:
  false` to take that over.
- It registers itself as the page's `SectionNavigator`, so on a phone the
  mobile menu lists exactly the sections the desktop rail shows.
- **Give it the page body directly.** It manages its own scroll view (wide) or
  a `Column` with an `Expanded` (compact), so it needs a bounded height from
  its parent. Putting it inside another `SingleChildScrollView` will not work.
- `onSectionChanged(section, index)` fires from both the scroll-spy and the
  rail. It is the hook for analytics. The URL is already handled for you, see
  below.
- `railWidth` and `railGap` tune the desktop layout.

### Deep links

Every heading is linkable, with no per-section wiring. The fragment is derived
from the heading text by `slugify`: lowercase, punctuation dropped, words
joined with hyphens. `Routing and deep links` becomes
`/docs#routing-and-deep-links`, and `Routing & deep links` becomes
`/docs#routing-deep-links`.

Deriving the slug from the title rather than hand-writing it beside the title
is what stops the two from drifting apart when a heading is reworded.

What you get:

- **Arriving at `/docs#theming` opens the page already at that heading.** It
  jumps rather than animating, then re-measures a moment later and corrects
  itself, because web fonts and asynchronous syntax highlighting can settle
  after the first frame and shift everything below them.
- **Each heading carries a faded link anchor** that comes up to full on hover.
  Clicking it puts that section's link in the address bar. It deliberately does
  not scroll: the reader is already looking at that heading, so moving the page
  under them would be a surprise.
- **The address bar follows the reader.** The scroll-spy rewrites the fragment
  as sections come into view, through `history.replaceState`, so copying the
  URL always shares the right spot and no history entries pile up. The first
  section clears the fragment instead of writing `#introduction` the moment the
  page opens.
- **Editing the hash by hand works too.** A `hashchange` listener catches
  someone pasting `#chains` into the address bar of an already-open tab.
- **`initialSectionId` still works** for links that must live in the route
  itself, such as `?section=`. It accepts a slug, a content id, or a title, and
  the fragment wins when both are present. Matching falls back to
  `PageSection.id`, so links written against an id keep working after the
  heading is reworded.

`slugify` and `sectionIndexForSlug(sections, reference)` are exported, so a
link elsewhere on the site can build the same URL:

```dart
context.go('/docs#${slugify('Routing & deep links')}');
```

Turn the whole thing off with `deepLink: false` when the shell is not the
page's main content, such as a preview inside a frame or two shells on screen
at once, which would otherwise fight over one address bar. The heading anchors
are hidden along with it, since there would be no URL for them to point at.
`initialSectionId` is still honoured.

One setup note: the fragment is read in `SiteKit.init()`, before `runApp`. The
router reports its own location on startup, which can rewrite the address bar
and drop the hash before the docs page has mounted; capturing it first
sidesteps that. Deep links still work without `SiteKit.init()` as long as the
router does not clear the hash, but do not rely on it.

## SEO

A Flutter site is client-rendered, so metadata lives in two places:

1. **`web/index.html`**, read by social scrapers and by crawlers that do not
   run JavaScript. This is the shared link preview for every route.
2. **`SiteConfig.pageMeta` and `SitePage.meta`**, applied on every navigation
   for real users (browser tab, history) and for JS-rendering crawlers such as
   Googlebot.

```dart
pageMeta: const {
  '/docs': SeoMeta(
    title: 'Documentation: acme',
    description: 'Guides for acme.',
    imageUrl: 'https://acme.dev/og/docs.png',   // optional per-route preview
  ),
},
```

Routes with no entry fall back to `config.name` and `config.description`, and
with `origin` set they also get a canonical URL derived from it, which updates
the canonical link and `og:url` (`config.metaFor('/').canonical` is
`https://acme.dev/`). An entry in `pageMeta` or a `SitePage.meta` is
used as written, so give it a `canonical:` of its own if that route needs one.
Without a canonical URL, those two tags are left untouched.

Off web, `applyPageMeta` is a no-op stub.

---

# Customization

## Palette

Every color flows from `SiteConfig.palette`. Override a subset rather than
restating a whole palette:

```dart
final siteConfig = SiteConfig(
  name: 'acme',
  palette: SitePalette.defaults.copyWith(
    dark: SiteColors.dark.copyWith(
      link: const Color(0xFFB388FF),
      accent: const Color(0xFF7CE38B),
    ),
    light: SiteColors.light.copyWith(link: const Color(0xFF6D28D9)),
  ),
);
```

For a full re-skin, build both brightnesses:

```dart
const palette = SitePalette(
  light: SiteColors(
    background: Color(0xFFFFFDF8),
    surface: Color(0xFFFFFFFF),
    surfaceInset: Color(0xFFF4F0E8),
    border: Color(0xFFE7E0D3),
    borderStrong: Color(0xFFD6CCB8),
    foreground: Color(0xFF1A1712),
    mutedForeground: Color(0xFF6B6559),
    primary: Color(0xFF1A1712),
    onPrimary: Color(0xFFFFFDF8),
    accent: Color(0xFF1F7A54),
    link: Color(0xFF9A3412),
    danger: Color(0xFFB91C1C),
    navBackground: Color(0xF2FFFDF8),
    shadow: Color(0x14000000),
  ),
  dark: SiteColors.dark,
  brandLight: BrandPalette.light,
  brandDark: BrandPalette.dark,
);
```

`BrandPalette` is the vivid, illustrative half: chart series, icon tints, and
diagram canvases. `brand.swatch(i)` cycles eight of its hues (`swatches`) for
multi-series visuals.

Keep the code theme in step with the brand hues if you change either; the
defaults are deliberately sampled from the same source, which is what makes
syntax highlighting and illustrations look related.

## Typography

```dart
typography: const SiteTypography(
  sans: 'Inter',                 // a family your app declares
  mono: 'JetBrains Mono',
  scale: 1.1,                    // multiplies the heading ramp only
),
```

`scale` moves `display`, `h1`, `h2`, and `h3`; body copy stays put, so a larger
display never costs reading comfort. The defaults are `SiteFonts.sans` and
`SiteFonts.mono`, which carry the `packages/site_kit/` prefix that makes the
bundled Geist families resolve in a consuming app.

To use your own fonts, declare them in your app's `pubspec.yaml` and pass the
family names. They do not need the package prefix, since they are yours.

For finer control, build the ramp yourself and pass the theme in by hand:

```dart
final theme = buildSiteTheme(Brightness.dark).copyWith(
  extensions: [
    SiteColors.dark,
    BrandPalette.dark,
    SiteTextStyles.from(
      colors: SiteColors.dark,
      typography: const SiteTypography(),
    ).copyWith(display: const TextStyle(fontSize: 72, height: 1.0)),
  ],
);
```

## Logo and wordmark

The default logo is a monogram tile drawn in code, tinted with the brand's
primary hue. Replace it wholesale:

```dart
logo: (context, size) => Image.asset('assets/logo.png', width: size),
```

```dart
logo: (context, size) => SvgPicture.asset(
  'assets/logo.svg',
  width: size,
  colorFilter: ColorFilter.mode(context.colors.foreground, BlendMode.srcIn),
),
```

Every `LogoMark` in the tree picks it up: the nav bar, the hero, both footers.

`Wordmark` renders `config.name` in mono, plus the tagline and author when
there is room:

```dart
const Wordmark()                                    // nav bar default
const Wordmark(showLogo: true, alwaysShowTagline: true)
Wordmark(onTap: () => context.go('/home'))
```

## Navigation chrome

```dart
SitePage(
  path: '/',
  themeControl: ThemeControl.menu,   // toggle (default) | menu | none
  builder: ...,
)
```

Add your own control to the bar, e.g. a search button or a version picker:

```dart
SiteShell(
  currentRoute: '/docs',
  navTrailing: SiteIconButton(
    materialIcon: Icons.search_rounded,
    tooltip: 'Search',
    onPressed: openSearch,
  ),
  child: body,
)
```

The mobile sheet is opened by the nav bar's menu button, and can be opened from
anywhere:

```dart
showSiteNavSheet(context, currentRoute: '/docs');
```

It lists `navLinks`, `navActions` (as labeled rows, since a 36px glyph is not a
usable menu target), a light/dark row, and the on-screen page's sections when
one is registered.

## Footers

```dart
const SiteFooter()      // wordmark and blurb beside link columns
const CompactFooter()   // centered logo, wordmark, one wrapped row of links
const CompactFooter(showLogo: false)
```

Both read `SiteConfig`. `CompactFooter` flattens `navLinks`, `navActions`, and
every `footerColumns` entry into a single de-duplicated row, so a small site
needs no extra configuration.

For something bespoke, `FooterLink` is exported and matches the hover treatment.

## Code themes and languages

Set them once at init:

```dart
await SiteKit.init(
  codeTheme: const ShikiDualTheme(
    light: ShikiThemes.githubLight,
    dark: ShikiThemes.githubDark,
  ),
  codeLanguages: [
    CodeLanguages.dart,
    CodeLanguages.yaml,
    CodeLanguages.shellscript,
    CodeLanguages.json,
    CodeLanguages.kotlin,
  ],
);
```

Or per block with `CodeBlock(theme: ...)`, which pins that card regardless of
the site's mode.

The shared service is reachable if you need it:

```dart
SiteHighlighter.instance.languageFor('dart');        // CodeLanguage?
SiteHighlighter.instance.supportsLanguage('rust');   // bool
SiteHighlighter.instance.highlighter;                // the ShikiHighlighter
SiteHighlighter.instance.defaultBackground(          // match a pane to a card
  isDark: context.isDarkMode,
  fallback: context.colors.surface,
);
```

Pass a `ShikiCodeView` the same `highlighter:` to share one token cache.

## Your own components

Build on the tokens and your widgets stay in step with every future palette
change:

```dart
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(SiteSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(SiteRadii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.caption),
          const SizedBox(height: SiteSpacing.xs),
          Text(value, style: context.text.h2),
        ],
      ),
    );
  }
}
```

Three conventions the built-in components follow, worth matching:

- Paint hover and press states yourself with `AnimatedContainer` and
  `SiteMotion.fast`; the theme turns Material ink off.
- Wrap non-content chrome in `SelectionContainer.disabled` so it stays out of
  page-wide text selection.
- Read sizes from `SiteSpacing` and `SiteRadii` rather than typing numbers.

---

# Advanced

## Owning the router

Use `buildSiteRouter` directly when you need redirects, guards, or a
`refreshListenable`, and hand the result to `SiteApp`:

```dart
final router = buildSiteRouter(
  config: siteConfig,
  pages: pages,
  refreshListenable: authState,
  redirect: (context, state) {
    if (state.uri.path.startsWith('/admin') && !authState.signedIn) {
      return '/sign-in';
    }
    return null;
  },
  extraRoutes: [
    ShellRoute(
      builder: (context, state, child) => AdminShell(child: child),
      routes: [
        GoRoute(path: '/admin', builder: (context, state) => const Admin()),
      ],
    ),
  ],
);

runApp(SiteApp(config: siteConfig, router: router));
```

`buildSiteRouter` keeps the SEO redirect in place and chains yours after it, so
per-route metadata is still applied. Building a bare `GoRouter` yourself means
losing that; call `applyPageMeta(config.metaFor(path))` from your own redirect
if you go that route.

`SiteApp` rebuilds the router when `pages`, `router`, or `config` changes, and
otherwise holds onto it, since rebuilding resets navigation history.

## Pages without the shell

```dart
SitePage(
  path: '/embed/:id',
  shell: false,
  builder: (context, state) => EmbedView(id: state.pathParameters['id']!),
)
```

The page then owns its own `Scaffold`, chrome, and selection region. The
storyboard uses this for its canvas. You still get the config scope, the theme,
the nav-sheet bridge, and per-route metadata.

You can also mount the shell yourself around part of a page:

```dart
SiteShell(
  currentRoute: '/docs',
  themeControl: ThemeControl.menu,
  selectable: false,        // for a canvas or an editor that owns selection
  navTrailing: const VersionPicker(),
  child: body,
)
```

## Custom section navigators

Any page can put its own sections in the mobile nav sheet by implementing
`SectionNavigator` and registering with the `NavSheetScope`. This is what
`DocsShell` does internally:

```dart
class _MyPageState extends State<MyPage> implements SectionNavigator {
  NavSheetController? _navSheet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navSheet = NavSheetScope.maybeOf(context)?..sections = this;
  }

  @override
  void dispose() {
    // Deregister only if still the current page, so a fast route change does
    // not clear the incoming page's registration.
    if (_navSheet?.sections == this) _navSheet?.sections = null;
    super.dispose();
  }

  @override
  List<PageSectionGroup> get sectionGroups => myGroups;

  @override
  int get activeSection => _active;

  @override
  void scrollToSection(int index) { /* ... */ }
}
```

`SectionList`, `SectionTile`, and `SectionGroupLabel` are exported, so a custom
rail can reuse the exact widgets the sheet uses and the two can never drift.
`flattenSections(groups)` gives the index-ordered list the callbacks refer to.

## Theme control and persistence

```dart
final controller = SiteThemeScope.of(context);

controller.value = ThemeMode.dark;   // set directly
controller.toggle();                 // light <-> dark
controller.cycle();                  // system -> light -> dark -> system
controller.isDark;                   // resolves system against the platform
controller.brightness;               // the Brightness it currently renders as
```

On web the choice is written to `localStorage` under
`site_kit.theme_mode`, and read back by `readStoredThemeMode()` when the
controller is constructed. Storage failures (private mode, a strict cookie
policy, a full quota) are swallowed: the switch still works, it just does not
persist.

To opt out, or to keep a preview's mode separate from the site's:

```dart
ThemeController(initial: ThemeMode.dark, persist: false)
```

`SiteApp(initialThemeMode: ...)` overrides whatever was persisted, which is
what you want in tests and screenshots and not what you want in production.

Three switcher widgets are provided: `ThemeToggleButton` (one tap, light and
dark), `ThemeModeMenu` (a three-way dropdown), and `ThemeModeSegmented` (a
three-way inline control). `themeModeIcon(mode)` and `themeModeLabel(mode)` are
exported for building your own.

## Selection and copy

`SiteShell` wraps the page body in **one** `SelectionArea`. Do not add another:
nested selection regions break keyboard copy (Cmd/Ctrl+C) inside code blocks,
which is the one place readers most expect it to work.

Code blocks cooperate with the ancestor region rather than creating their own.
Chrome (buttons, nav links, badges, tile labels) is wrapped in
`SelectionContainer.disabled`, so a select-all does not sweep up the furniture.

If a page genuinely needs to own selection, pass `selectable: false` to
`SiteShell`.

## Testing

Widget tests run under the plain VM: the web-only pieces resolve to stubs.
Pump under the same scopes `SiteApp` installs:

```dart
Future<void> pumpSite(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    SiteConfigScope(
      config: siteConfig,
      child: SiteThemeScope(
        controller: ThemeController(initial: ThemeMode.dark, persist: false),
        child: NavSheetScope(
          controller: NavSheetController(),
          child: MaterialApp(
            theme: buildSiteTheme(Brightness.dark, palette: siteConfig.palette),
            home: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
}
```

`persist: false` keeps a test from touching browser storage. Setting
`tester.view.physicalSize` is how you exercise the compact layouts; see
`test/site_kit_test.dart` for worked examples of both.

Widget tests render with Ahem, so text is boxes. For goldens that should look
real, load the bundled fonts off disk in `setUpAll`, using their prefixed
family names:

```dart
Future<void> loadSiteFonts() async {
  final loader = FontLoader('packages/site_kit/Geist');
  for (final file in ['Geist-400.ttf', 'Geist-500.ttf', 'Geist-600.ttf']) {
    final bytes = await File('path/to/site_kit/assets/fonts/$file')
        .readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}
```

## Bundle size and performance

- **Fonts**: roughly 200 KB for seven Geist faces. Font assets declared by a
  package are always bundled, and pointing `SiteTypography` at other families
  does not remove them. To drop weights, edit the `fonts:` section of the
  package's own `pubspec.yaml`.
- **Icons**: about 10 KB of SVG, bundled and decoded on first use.
- **Grammars**: the four default languages are referenced from
  `SiteHighlighter.defaultLanguages`, so they stay in the bundle even when
  `SiteKit.init(codeLanguages: ...)` names a different set. They are small, and
  a docs site normally wants all four. To shrink further, fork
  `highlighter_service.dart` and narrow that default.
- **Worker**: `web/shiki_tokenize_worker.js` is about 172 KB, fetched once.
- Tokenization is cached by the shared highlighter, so re-rendering a code
  block (a theme flip, a resize, a rebuild) does not re-tokenize.
- The nav bar's scrolled state is a `ValueNotifier`, so scrolling rebuilds the
  bar rather than the page body.

---

# Reference

## API index

| Export | What it is |
| --- | --- |
| `SiteKit.init` | One-call setup: binding, boot fragment, URL strategy, highlighter |
| `SiteApp` | Root widget: scopes, theme, router |
| `SitePage`, `buildSiteRouter` | Route definitions and the router factory |
| `SiteConfig`, `NavItem`, `FooterColumn`, `SiteAuthor` | Site description |
| `SiteConfigScope`, `context.site` | Config lookup |
| `SiteColors`, `BrandPalette`, `SiteTextStyles` | Theme extensions |
| `SiteSpacing`, `SiteRadii`, `SiteLayout`, `SiteMotion`, `SiteFonts` | Constants |
| `SitePalette`, `SiteTypography`, `buildSiteTheme` | Theme construction |
| `ThemeController`, `SiteThemeScope`, `readStoredThemeMode` | Theme mode |
| `Breakpoint`, `ResponsiveValue`, `ResponsiveBuilder`, `ResponsiveGrid` | Responsiveness |
| `SeoMeta`, `applyPageMeta` | Document metadata |
| `SiteHighlighter` | The shared shiki highlighter |
| `openLink` | Safe external link opening |
| `SiteShell`, `SiteNavBar`, `ThemeControl`, `showSiteNavSheet` | Page chrome |
| `SiteFooter`, `CompactFooter`, `FooterLink` | Footers |
| `Wordmark`, `LogoMark` | Brand marks |
| `ContentContainer`, `SiteSection`, `SectionHeading`, `SiteDivider` | Layout |
| `HeroSection`, `FeatureGrid`, `Feature`, `FeatureCard`, `CtaBand` | Page blocks |
| `DocsShell` | Docs page with rail, scroll-spy, and heading deep links |
| `PageSection`, `PageSectionGroup`, `flattenSections` | Section model |
| `slugify`, `sectionIndexForSlug` | Heading slugs and resolving a reference |
| `readUrlFragment`, `writeUrlFragment`, `onUrlFragmentChanged` | The URL fragment, web-only |
| `SectionNavigator`, `NavSheetController`, `NavSheetScope` | Nav-sheet bridge |
| `SectionList`, `SectionTile`, `SectionGroupLabel` | Rail widgets |
| `CodeBlock` | Highlighted code card |
| `Prose`, `ProseHeading`, `ProseList`, `ProseTable`, `Callout`, `inlineSpans` | Documentation prose |
| `InlineLinkText`, `TextLink` | Links inside body copy |
| `SiteButton`, `SiteIconButton` | Buttons |
| `SiteBadge`, `SelectPill`, `PillGroup`, `CommandPill`, `CopyButton` | Small controls |
| `SiteDropdown`, `MenuPanel`, `MenuItemRow`, `MenuSeparator` | Menus |
| `SiteIcon`, `SiteIcons`, `AnyIcon` | Icons |
| `ThemeToggleButton`, `ThemeModeMenu`, `ThemeModeSegmented` | Theme switchers |

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `context.colors needs a theme built by buildSiteTheme()` | The widget is above `SiteApp`, or under a `MaterialApp` with a plain `ThemeData`. Build the theme with `buildSiteTheme` |
| `context.site needs a SiteConfigScope ancestor` | Rendering outside `SiteApp`. Wrap the subtree in `SiteConfigScope` (tests included) |
| A refresh on `/docs` 404s | The host is not falling back to `index.html`. See [Deploying](#deploying) |
| Code renders unhighlighted in a `--wasm` build | The shiki worker is missing. Run `dart run shiki_flutter:install --default` |
| Code renders unhighlighted for one language | That language is not in `codeLanguages`. `CodeBlock` degrades to plain mono by design |
| Cmd/Ctrl+C does nothing in a code block | A second `SelectionArea` was added inside the shell's. Remove it |
| The nav bar overflows | Too many `navLinks` for the width. They fold below 900px; trim the list or move some into the footer |
| Fonts render as fallbacks | The family name lost its prefix. Use `SiteFonts.sans` / `SiteFonts.mono`, not `'Geist'` |
| `DocsShell` throws an unbounded-height error | It is inside another scroll view. Give it the page body directly |
| A `#heading` link opens the page at the top | `SiteKit.init()` was skipped, so the router cleared the hash before the page read it |
| Two docs shells fight over the address bar | Only one can own the URL. Pass `deepLink: false` to the others |
| The theme resets on every reload | Storage is blocked (private mode), or the controller was built with `persist: false` |

## Storyboard

`storyboard/` is a Flutter web app with a pannable, zoomable canvas of every
token, component, and page pattern in this package, live in light and dark.
Page patterns render at desktop and phone widths side by side, genuinely laid
out for those sizes.

```bash
cd storyboard
flutter run -d chrome
```

Every frame has a URL (`/frame/<id>`), and the rail doubles as an index of what
the package can do. See [storyboard/README.md](storyboard/README.md).

## Package layout

```
lib/
  site_kit.dart              the single public import
  src/
    app.dart                 SiteApp: scopes, theme, router
    init.dart                SiteKit.init()
    config/site_config.dart  SiteConfig, NavItem, FooterColumn
    theme/                   tokens, palette, type ramp, ThemeData, controller
    responsive/              breakpoints, ResponsiveValue, ResponsiveGrid
    router/                  SitePage and buildSiteRouter
    navigation/              PageSection model, rail list, nav-sheet bridge
    seo/                     per-route document metadata (web + stub)
    highlight/               the shared shiki highlighter
    util/                    link launching, URL fragment helpers
    widgets/                 the component library
assets/
  fonts/                     Geist, Geist Mono
  icons/                     the SVG glyph set
test/
  site_kit_test.dart         theme, breakpoints, config, prose, widgets
  deep_link_test.dart        slugs and DocsShell heading deep links
storyboard/                  the component canvas app
```

The package is standalone: it is not a member of the repository's pub
workspace, so it can be copied out and depended on from anywhere. Run
`flutter pub get`, `flutter analyze`, and `flutter test` inside `template/` and
`template/storyboard/` separately.
