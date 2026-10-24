// Web implementation: read and write `window.location.hash` directly.
//
// Writes go through `history.replaceState`, never `pushState`. The scroll-spy
// rewrites the fragment every time the reader crosses into a new section, and
// pushing would bury the previous page under a stack of history entries, so
// one Back press would no longer leave the docs.

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The current URL fragment without its leading `#`, or null when there is
/// none. Percent escapes are decoded, so a hand-typed `#quick%20start` reads
/// back as `quick start` and still normalizes to a slug.
String? readUrlFragment() {
  final hash = web.window.location.hash;
  if (hash.isEmpty || hash == '#') return null;
  final raw = hash.substring(1);
  try {
    return Uri.decodeComponent(raw);
  } on ArgumentError {
    // A malformed escape sequence. Use the fragment as typed; the slug
    // normalizer will drop whatever it cannot use.
    return raw;
  }
}

/// Points the URL fragment at [slug], or clears it when null.
///
/// The path and query are preserved exactly, so this only ever changes what
/// comes after the `#`.
void writeUrlFragment(String? slug) {
  final location = web.window.location;
  final base = '${location.pathname}${location.search}';
  final url = (slug == null || slug.isEmpty) ? base : '$base#$slug';
  web.window.history.replaceState(null, '', url);
}

/// Calls [listener] whenever the fragment changes, and returns a disposer.
///
/// This fires when someone edits the hash in the address bar or follows a
/// same-document link, which is exactly how a reader tries out a deep link
/// without reloading. It does not fire for our own [writeUrlFragment] calls:
/// `replaceState` is silent by design.
void Function() onUrlFragmentChanged(void Function(String? fragment) listener) {
  // The converted function is captured, not re-created at removal time: each
  // `.toJS` makes a new JS object, and removeEventListener matches by identity.
  final callback = ((web.Event _) => listener(readUrlFragment())).toJS;
  web.window.addEventListener('hashchange', callback);
  return () => web.window.removeEventListener('hashchange', callback);
}
