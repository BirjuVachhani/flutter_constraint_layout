// Non-web stub: there is no browser storage to read or write off the web, so
// the selected theme mode simply does not persist. Exists to satisfy the
// conditional import in `theme_store.dart` on IO/desktop builds (and under the
// VM in widget tests).

/// Reads the stored value for [key] (always null off web).
String? readStoredValue(String key) => null;

/// Stores [value] under [key] (no-op off web).
void writeStoredValue(String key, String value) {}
