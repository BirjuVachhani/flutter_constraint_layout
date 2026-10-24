import 'package:flutter/material.dart';

import '../theme/context_extensions.dart';
import 'nav_bar.dart';
import 'nav_sheet.dart';

/// The page scaffold every route shares: a pinned [SiteNavBar] over a
/// full-bleed body that scrolls behind it.
///
/// The body is wrapped in a single page-level [SelectionArea], so a code
/// block's selection and its Cmd/Ctrl+C copy are driven by one region. Pages
/// must not wrap their own; nesting selection regions breaks keyboard copy.
/// The nav stays outside it so the chrome is not selectable.
class SiteShell extends StatefulWidget {
  const SiteShell({
    super.key,
    required this.currentRoute,
    required this.child,
    this.themeControl = ThemeControl.toggle,
    this.navTrailing,
    this.selectable = true,
  });

  /// The active route path, for highlighting the matching nav link.
  final String currentRoute;

  final Widget child;

  final ThemeControl themeControl;

  /// Extra nav-bar content between the links and the theme control.
  final Widget? navTrailing;

  /// Wrap the body in a page-level [SelectionArea]. Turn it off for a page
  /// that manages selection itself (a canvas, an editor).
  final bool selectable;

  @override
  State<SiteShell> createState() => _SiteShellState();
}

class _SiteShellState extends State<SiteShell> {
  /// Whether the page has scrolled off the top. Drives the nav's bottom border,
  /// which is invisible at the top and fades in on scroll. Kept in a notifier
  /// so only the nav rebuilds, never the page body.
  final ValueNotifier<bool> _scrolled = ValueNotifier<bool>(false);

  @override
  void didUpdateWidget(SiteShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new route starts at the top; clear any leftover scrolled state.
    if (oldWidget.currentRoute != widget.currentRoute) {
      _scrolled.value = false;
    }
  }

  @override
  void dispose() {
    _scrolled.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    // Only the page's own vertical scroll (depth 0) counts, not a nested
    // horizontal scroller inside a code block.
    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
      final scrolled = notification.metrics.pixels > 0.5;
      if (scrolled != _scrolled.value) _scrolled.value = scrolled;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    Widget body = NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: widget.child,
    );
    if (widget.selectable) body = SelectionArea(child: body);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SiteNavBar(
              currentRoute: widget.currentRoute,
              scrolled: _scrolled,
              themeControl: widget.themeControl,
              trailing: widget.navTrailing,
              onMenu: () => showSiteNavSheet(
                context,
                currentRoute: widget.currentRoute,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
