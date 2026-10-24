# Changelog

## 1.0.0

Initial release, extracted from the flutter_constraint_layout showcase site.

- Design tokens as theme extensions: `SiteColors`, `BrandPalette`,
  `SiteTextStyles`, plus `SiteSpacing`, `SiteRadii`, `SiteLayout`, `SiteMotion`.
- `buildSiteTheme` and a `ThemeController` with a System / Light / Dark choice
  persisted in browser storage.
- Responsive primitives: `Breakpoint`, `ResponsiveValue`, `ResponsiveBuilder`,
  and an equal-height `ResponsiveGrid`.
- `SiteApp`, `SitePage`, and `buildSiteRouter`: go_router with path URLs and
  per-route document metadata.
- Chrome: `SiteShell`, `SiteNavBar`, the shared nav sheet, two footers, and the
  wordmark.
- Content: `CodeBlock` on shiki_flutter, the prose set, and `DocsShell` with a
  sticky rail and scroll-spy.
- Deep-linkable headings in `DocsShell`. Fragments are derived from the heading
  text with `slugify`, so `/docs#routing-and-deep-links` opens the page at that
  section, each heading carries a link anchor, and the address bar follows the
  reader as they scroll. Turn it off per shell with `deepLink: false`.
- `PageSection.slug`, `sectionIndexForSlug`, and the `readUrlFragment` /
  `writeUrlFragment` / `onUrlFragmentChanged` primitives (web-only, no-ops
  elsewhere).
- `SiteKit.init()`, one call for URL strategy, highlighter configuration,
  grammar warm-up, and capturing the fragment the page booted with before the
  router can rewrite the address bar.
- Geist, Geist Mono, and an 18-glyph SVG icon set bundled with the package.
