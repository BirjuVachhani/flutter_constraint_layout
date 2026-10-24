// Reads and writes the browser URL's `#fragment`, which is how a page
// deep-links to a section inside itself.
//
// The fragment is deliberately kept out of the router. `usePathUrlStrategy()`
// builds a `PathUrlStrategy` with `includeHash: false`, so Flutter never puts
// the hash into the location go_router parses, and `GoRouterState.uri.fragment`
// is always empty. That is the right split anyway: a fragment is a scroll
// target inside a page, not a route. The page owns it, reading it on mount and
// rewriting it as the reader moves.
//
// Split by platform with the same conditional-import idiom as the SEO
// metadata and the theme store: `dart.library.js_interop` is defined only on
// web, so the VM (and widget tests) resolve to the no-op stub.
export 'url_fragment_stub.dart'
    if (dart.library.js_interop) 'url_fragment_web.dart';
