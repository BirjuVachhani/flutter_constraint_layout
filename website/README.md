# flutter_constraint_layout website

The documentation site for
[`flutter_constraint_layout`](../packages/flutter_constraint_layout), live at
[constraints.birju.dev](https://constraints.birju.dev): a landing page and docs
that teach Flutter developers what ConstraintLayout is and how it works, styled
with a monochrome, dark-forward palette and vivid Pierre-derived accents.

Every docs example is a real `ConstraintLayout` rendered live beside its source
(see `lib/src/data/examples.dart`), so the site doubles as a working integration
test of the package. The live previews on the home page add `chains` and
`blueprint` toggles that turn on the package's debug overlays; `lib/main.dart`
sets `ConstraintLayout.allowDebugFlags = true` so they render in the release
build the site ships as. The code cards are tokenized live by `shiki_flutter`
with the Pierre light/dark theme pair (see
`lib/src/highlight/highlighter_service.dart`).

## Run it

The site is a member of the repository's pub workspace and renders the local
copies of `flutter_constraint_layout` and `constraint_engine`, so resolve once
from the repository root, then run it from here:

```sh
flutter pub get        # at the repository root
cd website
flutter run -d chrome
```

## Test and analyze

```sh
dart analyze --fatal-infos website   # at the repository root; runs the lint plugin too
cd website
flutter test              # docs slugs and deep links
```

CI runs both in the `workspace` job of
[`.github/workflows/test.yml`](../.github/workflows/test.yml).

## Build for the web

```sh
flutter build web --wasm
```

The output is written to `build/web/`. A `--wasm` build also emits a JavaScript
fallback for browsers without WasmGC; drop the flag for a plain JS build. The
site is served from the root of its domain, so the default base href (`/`) is
the right one.

## Deploy

[`.github/workflows/deploy-website.yml`](../.github/workflows/deploy-website.yml)
builds the site with `flutter build web --wasm --base-href "/"` on the latest
Flutter stable and publishes `build/web/` to GitHub Pages at
<https://constraints.birju.dev>. It runs on pushes to `main` that touch
`website/`, `packages/constraint_engine/`, `packages/flutter_constraint_layout/`,
the root `pubspec.yaml`, or the workflow itself, and can be started by hand from
the Actions tab.

The custom domain comes from the repository's Pages settings (Settings, Pages,
Custom domain): a GitHub Actions deploy ignores any `CNAME` file in the
artifact. `web/CNAME` is kept in step with that setting so the build output
stays self-describing; change the two together.

## Syntax highlighting

`lib/main.dart` configures `shiki_flutter` with its embedded engine and
`asyncWeb: true`, so on the web every code block is tokenized in a Web Worker:
`web/shiki_tokenize_worker.js`, a dart2js build that ships inside
`shiki_flutter`. Refresh it whenever `shiki_flutter` is upgraded, from this
directory:

```sh
dart run shiki_flutter:install --default
```

Under the `--wasm` build the worker is not optional. The embedded engine's
RegExp fast path relies on Dart's RegExp lowering to the browser's native regex,
which holds in the dart2js-compiled worker but not on the dart2wasm main thread.
If the worker fails to load, `shiki_flutter` falls back to tokenizing inline and
the code renders unhighlighted.

## Structure

```
lib/
  main.dart                     # entry: URL strategy, highlighter, MaterialApp.router
  src/
    theme/                      # design tokens, ThemeData, dark/light controller
    router/app_router.dart      # go_router: / and /docs
    seo/                        # per-route document metadata (web only)
    highlight/                  # the shared ShikiHighlighter, Pierre themed
    data/                       # docs sections, live and real-world examples, snippets, links
    util/                       # URL fragment helpers behind the docs deep links
    widgets/                    # nav, footer, code block, live example, previews…
    pages/                      # home_page, docs_page, docs_content (prose widgets)
assets/fonts/                   # Geist + Geist Mono (OFL)
assets/icons/                   # SVG icons
web/                            # index.html (static SEO), docs.md, llms.txt, robots.txt,
                                # sitemap.xml, CNAME, the shiki worker
test/                           # slug and deep-link tests for the docs page
```

## Docs as plain text

The full docs page is mirrored as a single Markdown file at `web/docs.md`
(served at <https://constraints.birju.dev/docs.md>, and what the docs page's
"Copy as Markdown" and "Download .md" actions fetch) and summarized for AI
assistants at `web/llms.txt`. The interactive docs in
`lib/src/pages/docs_page.dart`, with their example sources in
`lib/src/data/examples.dart`, are the source of truth: update `web/docs.md`
whenever either changes.

## Notes

- **Fonts** (Geist, Geist Mono) are vendored as OFL `.ttf` files under
  `assets/fonts/`, so the site depends on no font CDN at runtime.
- **Deep links**: every docs section is linkable as `/docs#<slug>`, with the
  slug derived from its heading (`lib/src/data/docs_sections.dart`), and older
  `/docs?section=<id>` links still resolve.
- **Routing** uses clean URLs via `usePathUrlStrategy()`, so any route other
  than `/` relies on the host serving `index.html` for it. GitHub Pages has no
  rewrite rules, so the deploy workflow copies `build/web/index.html` to
  `docs.html` (Pages serves it for `/docs`) and to `404.html` (served for any
  other unknown path), which lets a direct load or a refresh of any route boot
  the app. A new top-level route needs its own copy in
  `.github/workflows/deploy-website.yml`. On another static host, configure an
  SPA fallback instead, and if serving from a sub-path, pass
  `--base-href /your-path/` to `flutter build web`.
- **Theme** switches the whole site with the nav toggle; the code blocks follow
  with the Pierre light / Pierre dark pair.
