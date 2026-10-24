// Non-web stub: there is no browser URL to read or write off the web, so
// deep-linking by fragment is inert. Exists to satisfy the conditional import
// in `url_fragment.dart` on IO/desktop builds (and under the VM in widget
// tests).

/// The current URL fragment without its leading `#` (always null off web).
String? readUrlFragment() => null;

/// Points the URL fragment at [slug], or clears it when null (no-op off web).
void writeUrlFragment(String? slug) {}

/// Subscribes to fragment changes; returns a disposer (no-op off web).
void Function() onUrlFragmentChanged(void Function(String? fragment) listener) {
  return () {};
}
