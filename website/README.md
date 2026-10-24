# flutter_constraint_layout website

The showcase site for [`flutter_constraint_layout`](../): a landing page and docs that
teach Flutter developers what ConstraintLayout is and how it works, styled with
a monochrome, dark-forward palette and vivid Pierre-derived accents.

Every docs example is a real `ConstraintLayout` rendered live beside its source
(see `lib/src/data/examples.dart`), so the site doubles as a working integration
test of the package. The code cards are tokenized live by `shiki_flutter` with
the Pierre light/dark theme pair (see
`lib/src/highlight/highlighter_service.dart`).

## Run it

```sh
cd website
flutter pub get
flutter run -d chrome
```

## Build for the web

```sh
flutter build web --wasm
```

The output is written to `build/web/`. The site ships to GitHub Pages under the
custom domain `constraints.birju.dev` (see `web/CNAME`), so no `--base-href`
is needed. Drop the `--wasm` flag for a plain JS build.

Web highlighting uses `shiki_flutter`'s pure-Dart embedded engine (no
WebAssembly, no Web Worker), which is plenty fast for the short snippets shown
here, so there is no worker to install.

## Structure

```
lib/
  main.dart                     # entry: MaterialApp.router + ThemeController
  src/
    theme/                      # design tokens, ThemeData, dark/light controller
    router/app_router.dart      # go_router: / and /docs
    seo/                        # per-route document metadata (web only)
    highlight/                  # the shared ShikiHighlighter, Pierre themed
    data/                       # docs sections, live examples, snippets, links
    widgets/                    # nav, footer, code block, live example, previews…
    pages/                      # home_page, docs_page, docs_content
assets/fonts/                   # Geist + Geist Mono (OFL)
```

## Docs as plain text

The full docs page is mirrored as a single Markdown file at `web/docs.md` (and
summarized for AI assistants at `web/llms.txt`). Keep `web/docs.md` in sync with
the interactive docs in `lib/src/pages/docs_page.dart` when either changes.

## Notes

- **Fonts** (Geist, Geist Mono) are vendored as OFL `.ttf` files under
  `assets/fonts/`, so the site needs no network at runtime.
- **Routing** uses clean URLs via `usePathUrlStrategy()`. When hosting on a
  static host, add an SPA fallback that serves `index.html` for unknown paths,
  and if serving from a sub-path, pass `--base-href /your-path/` to
  `flutter build web`.
- **Theme** switches the whole site with the nav toggle; the code blocks follow
  with the Pierre light / Pierre dark pair.
```
