import 'url_fragment.dart';

/// The fragment the page was opened with, captured before anything can rewrite
/// it.
///
/// Flutter's `PathUrlStrategy` leaves the hash out of the path it reports, so
/// the router's location is `/docs` even when the browser is at
/// `/docs#chains`. When the router then reports that location back, the engine
/// rewrites the address bar to `/docs` and the fragment is gone, potentially
/// before the docs page has mounted and read it.
///
/// Capturing it in `main()`, before `runApp`, sidesteps the race entirely. The
/// page restores the fragment as soon as it jumps, so the address bar ends up
/// pointing at the section either way.
String? _initial;
bool _captured = false;

/// Records the fragment the page booted with. Call once from `main()`, before
/// `runApp`. Later calls do nothing.
void captureInitialUrlFragment() {
  if (_captured) return;
  _captured = true;
  _initial = readUrlFragment();
}

/// The captured boot fragment, cleared as it is handed out.
///
/// It is consumed so that leaving the docs and coming back does not re-apply
/// the fragment the visitor arrived with an hour ago.
String? takeInitialUrlFragment() {
  final value = _initial;
  _initial = null;
  return value;
}
