import 'url_fragment.dart';

/// The fragment the page was opened with, captured before anything can rewrite
/// it.
///
/// Flutter's `PathUrlStrategy` leaves the hash out of the path it reports, so
/// the router's location is `/docs` even when the browser is at
/// `/docs#chains`. When the router then reports that location back, the engine
/// rewrites the address bar to `/docs` and the fragment is gone, potentially
/// before the page that wanted it has mounted.
///
/// `SiteKit.init()` captures it first thing, before `runApp`, which sidesteps
/// the race entirely. `DocsShell` restores the fragment as soon as it jumps, so
/// the address bar ends up pointing at the section either way.
String? _initial;
bool _captured = false;

/// Records the fragment the page booted with.
///
/// Called by `SiteKit.init()`. Call it yourself only if you are skipping that
/// and still want deep links to survive the router's first location report.
/// Later calls do nothing.
void captureInitialUrlFragment() {
  if (_captured) return;
  _captured = true;
  _initial = readUrlFragment();
}

/// The captured boot fragment, cleared as it is handed out.
///
/// It is consumed so that leaving a deep-linked page and coming back does not
/// re-apply the fragment the visitor arrived with. `DocsShell` consumes it on
/// mount; a page that handles its own deep links can consume it instead.
String? takeInitialUrlFragment() {
  final value = _initial;
  _initial = null;
  return value;
}
