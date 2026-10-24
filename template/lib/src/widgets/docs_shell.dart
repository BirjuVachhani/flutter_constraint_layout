import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../navigation/sections.dart';
import '../responsive/breakpoints.dart';
import '../theme/context_extensions.dart';
import '../theme/tokens.dart';
import '../util/initial_fragment.dart';
import '../util/url_fragment.dart';
import 'nav_sheet.dart';
import 'section.dart';
import 'site_icon.dart';

/// Height of the breadcrumb bar pinned under the nav on compact layouts, where
/// the section rail collapses into a popup. Sections scroll behind it, so the
/// scroll-spy and scroll-to math offset by both the nav and this bar.
const double _kCompactBarHeight = 52;

/// A documentation page: a sticky section rail beside a scrolling reading
/// column, with scroll-spy keeping the rail in step.
///
/// On compact widths the rail collapses into a breadcrumb bar that opens the
/// app-wide nav sheet, and the sheet lists these sections because the shell
/// registers itself as the page's [SectionNavigator].
///
/// Content is built per section, so a page can mix prose, code blocks, tables,
/// and live demos:
///
/// ```dart
/// DocsShell(
///   groups: docsGroups,
///   sectionBuilder: (context, section, index) => switch (section.id) {
///     'install' => const [Prose('Add it to your pubspec.')],
///     _ => const [Prose('TODO')],
///   },
///   footer: const SiteFooter(),
/// )
/// ```
///
/// Every heading is deep-linkable. Its fragment is derived from the heading
/// text itself (see [slugify]), so `/docs#anchors-and-links` opens the page
/// already at "Anchors and links", each heading carries a link anchor, and the
/// address bar keeps pointing at whatever the reader is currently on. Turn all
/// of that off with [deepLink] for a shell that is not the page's main
/// content.
class DocsShell extends StatefulWidget {
  const DocsShell({
    super.key,
    required this.groups,
    required this.sectionBuilder,
    this.initialSectionId,
    this.header,
    this.footer,
    this.onSectionChanged,
    this.currentRoute = '/docs',
    this.railWidth = SiteLayout.railWidth,
    this.railGap = 48,
    this.showSectionTitles = true,
    this.deepLink = true,
  });

  /// The grouped sections, in reading order.
  final List<PageSectionGroup> groups;

  /// Builds the body of one section. The section title is rendered for you
  /// unless [showSectionTitles] is false.
  final List<Widget> Function(
    BuildContext context,
    PageSection section,
    int index,
  )
  sectionBuilder;

  /// A section to scroll to on first load, e.g. from a `?section=` query
  /// parameter. Accepts a slug, a content id, or a title; unknown values are
  /// ignored.
  ///
  /// The URL fragment is the canonical deep link and takes precedence over
  /// this. Use it for links that have to survive as part of the route, since a
  /// query parameter, unlike a fragment, is part of the location go_router
  /// parses.
  final String? initialSectionId;

  /// Content above the first section, e.g. a row of page actions.
  final Widget? header;

  /// Content after the last section, typically a footer.
  final Widget? footer;

  /// Called when the scroll-spy or the rail moves to a different section.
  /// Useful for keeping the URL's `?section=` in step.
  final void Function(PageSection section, int index)? onSectionChanged;

  /// The route this page is served at, for the compact breadcrumb label and
  /// the nav sheet's active link.
  final String currentRoute;

  final double railWidth;
  final double railGap;

  /// Render each section's title above its content.
  final bool showSectionTitles;

  /// Tie the page to the browser URL's fragment: jump to `#slug` on load,
  /// rewrite it as the reader scrolls, follow it when it changes, and show a
  /// link anchor beside every heading.
  ///
  /// Turn it off for a shell that is not the page's main content: a preview
  /// inside a frame, a docs pane in a split view, or two shells on screen at
  /// once. They would otherwise fight over one address bar. With it off the
  /// anchors are hidden too, since there would be no URL for them to point at.
  final bool deepLink;

  @override
  State<DocsShell> createState() => _DocsShellState();
}

class _DocsShellState extends State<DocsShell> implements SectionNavigator {
  final ScrollController _controller = ScrollController();
  late List<PageSection> _sections;
  late List<GlobalKey> _keys;
  int _active = 0;

  /// The app-wide nav sheet bridge. Registering makes the sheet list these
  /// sections and scroll here, whichever control opened it.
  NavSheetController? _navSheet;

  /// Removes the `hashchange` subscription. Set on web, when [DocsShell.deepLink]
  /// is on.
  void Function()? _stopListeningToFragment;

  /// The last fragment this page wrote, so an echoed change is recognised as
  /// ours and does not bounce the reader back to where they already are.
  String? _writtenFragment;

  /// Non-zero while an animated scroll-to is running. The scroll-spy stands
  /// down for the duration: otherwise it would fire for every section the
  /// animation sweeps past, flickering the rail and dragging the URL through
  /// each one on the way.
  int _programmaticScrolls = 0;

  /// Pending second pass of a deep-link jump. Cancelled on dispose.
  Timer? _settleTimer;

  static const double _anchorGap = SiteLayout.navHeight + 24;

  @override
  void initState() {
    super.initState();
    _rebuildSections();
    _controller.addListener(_onScroll);
    if (widget.deepLink) {
      _stopListeningToFragment = onUrlFragmentChanged(_onFragmentChanged);
    }

    // A deep link arrives either as the canonical `/docs#anchors-and-links` or
    // as a `/docs?section=anchors` query parameter. The fragment wins.
    //
    // The live fragment is read first, then the one captured at boot: the
    // router can wipe the hash out of the address bar on startup before this
    // page ever mounts (see captureInitialUrlFragment). Jumping restores it.
    final target = widget.deepLink
        ? readUrlFragment() ?? takeInitialUrlFragment() ?? widget.initialSectionId
        : widget.initialSectionId;
    final index = target == null
        ? null
        : sectionIndexForSlug(_sections, target);
    if (index != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToDeepLink(index);
      });
    }
  }

  @override
  void didUpdateWidget(DocsShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groups != widget.groups) {
      _rebuildSections();
      // A shorter list can strand the active index past the end.
      _active = _active.clamp(0, math.max(0, _sections.length - 1));
    }

    // Arriving at `/docs?section=chains` while already on the docs page
    // rebuilds this widget rather than remounting it, so initState never runs
    // again. Honour the new target the same way a fresh load would.
    final target = widget.initialSectionId;
    if (target == null || target == oldWidget.initialSectionId) return;
    final index = sectionIndexForSlug(_sections, target);
    if (index == null) return;
    // didUpdateWidget runs during a build; the jump calls setState, so it has
    // to wait for the frame to finish.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToDeepLink(index);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navSheet = NavSheetScope.maybeOf(context)?..sections = this;
  }

  @override
  void dispose() {
    if (_navSheet?.sections == this) _navSheet?.sections = null;
    _settleTimer?.cancel();
    _stopListeningToFragment?.call();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _rebuildSections() {
    _sections = flattenSections(widget.groups);
    _keys = List.generate(_sections.length, (_) => GlobalKey());
  }

  // SectionNavigator: lets the shared nav sheet read and drive this page.
  @override
  List<PageSectionGroup> get sectionGroups => widget.groups;

  @override
  int get activeSection => _active;

  @override
  void scrollToSection(int index) => _scrollTo(index);

  void _setActive(int index) {
    if (index == _active) return;
    setState(() => _active = index);
    widget.onSectionChanged?.call(_sections[index], index);
  }

  void _onScroll() {
    // A scroll we started already knows its destination; let it finish without
    // the spy narrating every section it passes.
    if (_programmaticScrolls > 0) return;

    // On compact layouts headings scroll behind the pinned nav and breadcrumb
    // bar, so a heading counts as active once it passes below both.
    final threshold = context.isCompact
        ? SiteLayout.navHeight + _kCompactBarHeight + 24
        : SiteLayout.navHeight + 72;
    var active = 0;
    for (var i = 0; i < _keys.length; i++) {
      final ctx = _keys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      if (dy <= threshold) {
        active = i;
      } else {
        break;
      }
    }
    if (active != _active) {
      _setActive(active);
      _writeFragmentFor(active);
    }
  }

  /// Points the URL fragment at [slug], or clears it when null, remembering
  /// what was written so the change is recognised as ours if it echoes back.
  void _writeFragment(String? slug) {
    if (!widget.deepLink) return;
    _writtenFragment = slug;
    writeUrlFragment(slug);
  }

  /// Follows the reader: the address bar is always a link to what is on
  /// screen, so copying it shares that spot.
  ///
  /// The first section is the page itself, so it clears the fragment instead
  /// of writing `#introduction` the moment the page opens.
  void _writeFragmentFor(int index) =>
      _writeFragment(index == 0 ? null : _sections[index].slug);

  /// Handles a click on a heading's link anchor: put that section's deep link
  /// in the address bar.
  ///
  /// It deliberately does not scroll. The reader is already looking at the
  /// heading they clicked, so moving the page under them would be a surprise;
  /// they wanted the link, not the trip.
  ///
  /// Unlike the scroll-spy, this always writes a slug, the first section
  /// included. The reader explicitly asked for that section's link, so
  /// `#introduction` is what they should be able to copy.
  void _anchorTo(int index) => _writeFragment(_sections[index].slug);

  /// Scrolls section [index] to just below the fixed chrome and points the URL
  /// at it. Returns the offset it settled on, or null when the section has not
  /// been laid out yet.
  double? _scrollTo(int index, {bool animate = true}) {
    final ctx = _keys[index].currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox;
    final dy = box.localToGlobal(Offset.zero).dy;
    // Compact stacks the nav over the breadcrumb bar; land the heading just
    // below both so it is not hidden behind them.
    final gap = context.isCompact
        ? SiteLayout.navHeight + _kCompactBarHeight + 16
        : _anchorGap;
    // The first section has nothing above it but page chrome, so its anchor is
    // the top of the page. Scrolling a header row out of view to tuck the
    // first heading under the nav would read as a glitch.
    final target = index == 0
        ? 0.0
        : (_controller.offset + dy - gap).clamp(
            0.0,
            _controller.position.maxScrollExtent,
          );
    _setActive(index);
    _writeFragmentFor(index);

    if (!animate) {
      _controller.jumpTo(target);
      return target;
    }
    _programmaticScrolls++;
    _controller
        .animateTo(target, duration: SiteMotion.slow, curve: SiteMotion.standard)
        // Counted rather than flagged, so a second tap mid-flight does not let
        // the first one's completion re-arm the spy early.
        .whenComplete(() => _programmaticScrolls--);
    return target;
  }

  /// Lands on a deep-linked section without animating. The reader asked for
  /// this section, not for a tour of everything above it.
  ///
  /// The jump runs twice. Web fonts and the asynchronous code highlighter can
  /// settle after the first frame and shift every heading below them, so the
  /// target is re-measured a moment later and corrected. The correction is
  /// skipped if the reader has scrolled in the meantime, which shows up as an
  /// offset that is no longer the one we set.
  void _jumpToDeepLink(int index) {
    final landed = _scrollTo(index, animate: false);
    if (landed == null) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || !_controller.hasClients) return;
      if ((_controller.offset - landed).abs() > 1) return;
      _scrollTo(index, animate: false);
    });
  }

  /// The fragment changed underneath us: someone edited the hash in the
  /// address bar, or followed a same-document link. Our own writes use
  /// `replaceState` and never land here, but they are filtered anyway.
  void _onFragmentChanged(String? fragment) {
    if (!mounted || fragment == null || fragment == _writtenFragment) return;
    final index = sectionIndexForSlug(_sections, fragment);
    if (index != null) _jumpToDeepLink(index);
  }

  @override
  Widget build(BuildContext context) {
    return context.isCompact ? _buildCompact(context) : _buildWide(context);
  }

  Widget _buildWide(BuildContext context) {
    // The sticky rail is pinned `navHeight + 24` below the viewport top; cap it
    // at the remaining space so a section list taller than the window scrolls
    // within the rail instead of running off screen.
    final railMaxHeight = math.max(
      0.0,
      context.screenHeight - SiteLayout.navHeight - 24,
    );
    // One page-level scroll view, so the scrollbar sits on the viewport's right
    // edge and the whole page scrolls from anywhere; the rail is pinned in view
    // (the CSS `position: sticky` equivalent).
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _controller,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: SiteLayout.navHeight + 24),
              child: ContentContainer(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StickyBox(
                      controller: _controller,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: railMaxHeight),
                        child: _Rail(
                          width: widget.railWidth,
                          groups: widget.groups,
                          active: _active,
                          onSelect: _scrollTo,
                        ),
                      ),
                    ),
                    SizedBox(width: widget.railGap),
                    Expanded(child: _sectionsColumn(context)),
                  ],
                ),
              ),
            ),
            ?widget.footer,
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    // The rail collapses into a popup: a breadcrumb bar pinned under the nav
    // opens it, and the reading column scrolls beneath both.
    return Column(
      children: [
        const SizedBox(height: SiteLayout.navHeight),
        _CompactBar(
          sectionTitle: _sections.isEmpty ? '' : _sections[_active].title,
          onOpen: () =>
              showSiteNavSheet(context, currentRoute: widget.currentRoute),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _controller,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionsColumn(context),
                ?widget.footer,
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionsColumn(BuildContext context) {
    final compact = context.isCompact;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 20 : 0,
        compact ? 8 : 0,
        compact ? 20 : 0,
        96,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?widget.header,
          for (var i = 0; i < _sections.length; i++)
            Padding(
              key: _keys[i],
              padding: EdgeInsets.only(top: i == 0 ? 0 : 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showSectionTitles) ...[
                    _SectionHeading(
                      title: _sections[i].title,
                      // No anchor without deep linking: it would point at a URL
                      // this shell has agreed not to touch.
                      onAnchorTap: widget.deepLink ? () => _anchorTo(i) : null,
                    ),
                    const SizedBox(height: SiteSpacing.md),
                  ],
                  ...widget.sectionBuilder(context, _sections[i], i),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A section heading, optionally followed by its own deep link.
///
/// The anchor is revealed in two stages: hovering anywhere on the heading
/// fades the icon in, and hovering the icon itself brings it to full. At rest
/// the heading is just a heading.
///
/// The heading text stays plain selectable text: making the whole line a tap
/// target would fight text selection. The link lives in the icon beside it.
class _SectionHeading extends StatefulWidget {
  const _SectionHeading({required this.title, required this.onAnchorTap});

  final String title;

  /// Puts this section's deep link in the address bar. Null hides the anchor.
  final VoidCallback? onAnchorTap;

  @override
  State<_SectionHeading> createState() => _SectionHeadingState();
}

class _SectionHeadingState extends State<_SectionHeading> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final style = context.text.h1;
    final onTap = widget.onAnchorTap;
    if (onTap == null) return Text(widget.title, style: style);

    return MouseRegion(
      hitTestBehavior: HitTestBehavior.opaque,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Flexible(child: Text(widget.title, style: style)),
          Padding(
            // Nudged below the line box's centre to sit level with the glyphs,
            // which ride low in the box once leading is added. Taken from the
            // font size, so it holds at any SiteTypography.scale.
            padding: EdgeInsets.only(top: (style.fontSize ?? 30) * 0.2),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: _hovered ? 1 : 0,
              // An invisible anchor must not be tappable. Opacity alone does
              // not stop hit testing, so without this a touch device, which
              // never hovers, would carry a hidden target beside every
              // heading.
              child: IgnorePointer(
                ignoring: !_hovered,
                child: _SectionAnchorLink(onTap: onTap),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The faded chain-link icon after a section heading.
///
/// It sits at roughly a third opacity, present enough to read as an
/// affordance without competing with the heading, and comes up to full on
/// hover. Clicking it points the URL at the section's deep link.
class _SectionAnchorLink extends StatefulWidget {
  const _SectionAnchorLink({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_SectionAnchorLink> createState() => _SectionAnchorLinkState();
}

class _SectionAnchorLinkState extends State<_SectionAnchorLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final link = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          // Padding rather than a bare glyph, so the tap target covers most of
          // the heading's line box instead of just the 18px icon.
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: AnimatedOpacity(
            duration: SiteMotion.fast,
            opacity: _hovered ? 1 : 0.32,
            child: SiteIcon(
              SiteIcons.link,
              size: 18,
              color: context.colors.foreground,
            ),
          ),
        ),
      ),
    );
    return SelectionContainer.disabled(
      child: Tooltip(message: 'Link to this section', child: link),
    );
  }
}

/// The section rail: the grouped list in its own scroller, kept scrolled to
/// the active tile as the scroll-spy follows the page.
class _Rail extends StatefulWidget {
  const _Rail({
    required this.width,
    required this.groups,
    required this.active,
    required this.onSelect,
  });

  final double width;
  final List<PageSectionGroup> groups;
  final int active;
  final ValueChanged<int> onSelect;

  @override
  State<_Rail> createState() => _RailState();
}

class _RailState extends State<_Rail> {
  final ScrollController _controller = ScrollController();
  late List<GlobalKey> _tileKeys;

  @override
  void initState() {
    super.initState();
    _tileKeys = _makeKeys();
    // A deep link lands with a non-zero active section; jump the rail there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealActive(animate: false);
    });
  }

  @override
  void didUpdateWidget(_Rail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groups != widget.groups) _tileKeys = _makeKeys();
    if (widget.active != oldWidget.active) _revealActive();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<GlobalKey> _makeKeys() => List.generate(
    flattenSections(widget.groups).length,
    (_) => GlobalKey(),
  );

  /// Scrolls the rail just enough to keep the active tile visible. The two
  /// edge-pinned policies are each a no-op when the tile is already inside that
  /// edge, so at most one of them animates.
  void _revealActive({bool animate = true}) {
    if (!_controller.hasClients) return;
    if (widget.active >= _tileKeys.length) return;
    final object = _tileKeys[widget.active].currentContext?.findRenderObject();
    if (object == null) return;
    final duration = animate
        ? const Duration(milliseconds: 250)
        : Duration.zero;
    for (final policy in const [
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    ]) {
      _controller.position.ensureVisible(
        object,
        alignmentPolicy: policy,
        duration: duration,
        curve: SiteMotion.standard,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: SingleChildScrollView(
        controller: _controller,
        padding: const EdgeInsets.only(right: 12, bottom: 48),
        child: SectionList(
          groups: widget.groups,
          activeIndex: widget.active,
          onSelect: widget.onSelect,
          tileKeys: _tileKeys,
        ),
      ),
    );
  }
}

/// Pins its [child] to a fixed screen position while [controller] scrolls, by
/// translating it down by the current scroll offset: the equivalent of CSS
/// `position: sticky` for a short rail inside a page-level scroll.
class _StickyBox extends StatelessWidget {
  const _StickyBox({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, sticky) {
        // Guard on exactly one attached position: while resizing across the
        // compact breakpoint the old and new scroll views can both be attached
        // for a frame, and `offset` throws when there is more than one.
        final offset = controller.positions.length == 1
            ? controller.offset
            : 0.0;
        return Transform.translate(offset: Offset(0, offset), child: sticky);
      },
      child: child,
    );
  }
}

/// The compact trigger: a breadcrumb bar pinned under the nav showing where you
/// are, which opens the navigation popup on tap.
class _CompactBar extends StatelessWidget {
  const _CompactBar({required this.sectionTitle, required this.onOpen});

  final String sectionTitle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SelectionContainer.disabled(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: Container(
            height: _kCompactBarHeight,
            decoration: BoxDecoration(
              color: colors.background,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: ContentContainer(
              child: Row(
                children: [
                  Text(
                    'Docs',
                    style: TextStyle(
                      color: colors.mutedForeground,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // The icon set has no right chevron; a quarter turn of the
                  // dropdown chevron points it at the section title.
                  RotatedBox(
                    quarterTurns: 3,
                    child: SiteIcon(
                      SiteIcons.chevronDown,
                      size: 13,
                      color: colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SiteIcon(
                    SiteIcons.menu,
                    size: 18,
                    color: colors.foreground,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
