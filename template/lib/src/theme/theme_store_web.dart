// Web implementation: persist the selected theme mode in `localStorage` so a
// reload or a return visit keeps the choice. Storage can throw when the browser
// blocks it (Safari private mode, a strict cookie policy, storage full), so both
// calls swallow failures and degrade to "does not persist".

import 'package:web/web.dart' as web;

/// Reads the stored value for [key], or null when absent or unreadable.
String? readStoredValue(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

/// Stores [value] under [key], ignoring a blocked or full storage.
void writeStoredValue(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {
    // Persistence is a nicety; never let it break a theme switch.
  }
}
