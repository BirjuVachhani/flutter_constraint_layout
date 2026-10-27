import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/docs_sections.dart';
import '../data/examples.dart';
import '../data/snippets.dart';
import '../theme/tokens.dart';
import '../util/initial_fragment.dart';
import '../util/url_fragment.dart';
import '../widgets/app_icon.dart';
import '../widgets/code_block.dart';
import '../widgets/docs_md_actions.dart';
import '../widgets/footer.dart';
import '../widgets/interactive_demos.dart';
import '../widgets/nav_sheet.dart';
import '../widgets/section.dart';
import 'docs_content.dart';

/// Height of the breadcrumb bar pinned under the nav on compact layouts, where
/// the section rail collapses into a popup. Sections scroll behind it, so the
/// scroll-spy and scroll-to math offset by both the nav and this bar.
const double _kCompactBarHeight = 52;

/// The documentation page: a sticky section sidebar beside a scrolling reading
/// column. On compact widths the sidebar becomes a contents card at the top.
///
/// Every section is deep-linkable. Its URL fragment is derived from the
/// heading itself (see [slugify]), so `/docs#anchors-links` opens the page
/// already at "Anchors & links", and the address bar keeps pointing at
/// whatever the reader is currently on.
class DocsPage extends StatefulWidget {
  const DocsPage({super.key, this.initialSection});

  /// A section to scroll to on first load, from the legacy `?section=` query
  /// param. The URL fragment is the canonical form and takes precedence; this
  /// is read straight off the router because a query param, unlike a fragment,
  /// is part of the location go_router parses.
  final String? initialSection;

  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> implements DocsSectionNavigator {
  final ScrollController _controller = ScrollController();
  final List<GlobalKey> _keys = List.generate(
    docsSections.length,
    (_) => GlobalKey(),
  );
  int _active = 0;

  /// The app-wide nav popup bridge; we register with it so its section list and
  /// scroll target come from this page whenever the popup is opened on docs.
  NavSheetController? _navSheet;

  /// Removes the `hashchange` subscription. Set on web only.
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

  static const double _anchorGap = AppLayout.navHeight + 24;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _stopListeningToFragment = onUrlFragmentChanged(_onFragmentChanged);

    // A deep link arrives either as the canonical `/docs#anchors-links` or as
    // the older `/docs?section=anchors`. The fragment wins when both are set.
    //
    // The live fragment is read first, then the one captured at boot: the
    // router can wipe the hash out of the address bar on startup before this
    // page ever mounts (see captureInitialUrlFragment). Jumping restores it.
    final target =
        readUrlFragment() ?? takeInitialUrlFragment() ?? widget.initialSection;
    final index = target == null ? null : docsSectionIndexForSlug(target);
    if (index != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToDeepLink(index);
      });
    }
  }

  @override
  void didUpdateWidget(DocsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Arriving at `/docs?section=chains` while already on the docs page
    // rebuilds this widget rather than remounting it, so initState never runs
    // again. Honour the new target the same way a fresh load would.
    final target = widget.initialSection;
    if (target == null || target == oldWidget.initialSection) return;
    final index = docsSectionIndexForSlug(target);
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
    _navSheet = NavSheetScope.of(context)..docs = this;
  }

  @override
  void dispose() {
    if (_navSheet?.docs == this) _navSheet?.docs = null;
    _settleTimer?.cancel();
    _stopListeningToFragment?.call();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  // DocsSectionNavigator: lets the shared nav popup read the active section and
  // scroll here, regardless of which control (nav bar or breadcrumb) opened it.
  @override
  int get activeSection => _active;

  @override
  void scrollToSection(int index) => _scrollTo(index);

  void _onScroll() {
    // A scroll we started already knows its destination; let it finish without
    // the spy narrating every section it passes.
    if (_programmaticScrolls > 0) return;

    // On compact layouts the section headings scroll behind the pinned nav and
    // breadcrumb bar, so a heading counts as active once it passes below both.
    final threshold = context.isCompact
        ? AppLayout.navHeight + _kCompactBarHeight + 24
        : AppLayout.navHeight + 72;
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
      setState(() => _active = active);
      _writeFragmentFor(active);
    }
  }

  /// Points the URL fragment at [slug], or clears it when null, remembering
  /// what was written so the change is recognised as ours if it echoes back.
  void _writeFragment(String? slug) {
    _writtenFragment = slug;
    writeUrlFragment(slug);
  }

  /// Follows the reader: the address bar is always a link to what is on
  /// screen, so copying it shares that spot.
  ///
  /// The first section is the page itself, so it clears the fragment instead of
  /// writing `#introduction` the moment the docs open.
  void _writeFragmentFor(int index) =>
      _writeFragment(index == 0 ? null : docsSections[index].slug);

  /// Handles a click on a heading's link icon: re-anchor the page on that
  /// section, and put its deep link in the address bar.
  ///
  /// Unlike the scroll-spy, this always writes a slug, the first section
  /// included. The reader explicitly asked for that section's link, so
  /// `/docs#introduction` is what they should be able to copy.
  void _anchorTo(int index, {bool autoScroll = false}) {
    if (autoScroll) _scrollTo(index);
    _writeFragment(docsSections[index].slug);
  }

  /// Scrolls section [index] to just below the fixed chrome and points the URL
  /// at it. Returns the offset it settled on, or null when the section has not
  /// been laid out yet.
  double? _scrollTo(int index, {bool animate = true}) {
    final ctx = _keys[index].currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox;
    final dy = box.localToGlobal(Offset.zero).dy;
    // Compact stacks the nav over the pinned breadcrumb bar; land the heading
    // just below both so it isn't hidden behind them.
    final gap = context.isCompact
        ? AppLayout.navHeight + _kCompactBarHeight + 16
        : _anchorGap;
    // The first section has nothing above it but page chrome, so its anchor is
    // the top of the page. Scrolling the Markdown-actions row out of view to
    // tuck "Introduction" under the nav would read as a glitch.
    final target = index == 0
        ? 0.0
        : (_controller.offset + dy - gap).clamp(
            0.0,
            _controller.position.maxScrollExtent,
          );
    setState(() => _active = index);
    _writeFragmentFor(index);

    if (!animate) {
      _controller.jumpTo(target);
      return target;
    }
    _programmaticScrolls++;
    _controller
        .animateTo(
          target,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOutCubic,
        )
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
    final index = docsSectionIndexForSlug(fragment);
    if (index != null) _jumpToDeepLink(index);
  }

  /// Opens the app-wide navigation popup (site links + this page's section
  /// list). The popup reads the active section and scrolls via this page's
  /// [DocsSectionNavigator] registration, so nothing is returned here.
  void _openNav() => showAppNavSheet(context, currentRoute: '/docs');

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
      MediaQuery.sizeOf(context).height - AppLayout.navHeight - 24,
    );
    // One page-level scroll view so the scrollbar sits on the viewport's right
    // edge and the whole page scrolls from anywhere; the sidebar is pinned to
    // stay in view (CSS `position: sticky` equivalent).
    // The app shell provides the page-wide SelectionArea; none is wrapped here.
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _controller,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppLayout.navHeight + 24),
              child: ContentContainer(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StickyBox(
                      controller: _controller,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: railMaxHeight),
                        child: _Sidebar(active: _active, onTap: _scrollTo),
                      ),
                    ),
                    const SizedBox(width: 48),
                    Expanded(child: _sectionsColumn(context)),
                  ],
                ),
              ),
            ),
            const SimpleFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    // The section rail collapses into a popup: a breadcrumb bar pinned under the
    // nav opens it, and the reading column scrolls beneath both.
    return Column(
      children: [
        const SizedBox(height: AppLayout.navHeight),
        _CompactDocsBar(
          sectionTitle: docsSections[_active].title,
          onOpen: _openNav,
        ),
        Expanded(
          // The app shell provides the page-wide SelectionArea.
          child: SingleChildScrollView(
            controller: _controller,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionsColumn(context),
                const SimpleFooter(),
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
          // Copy the whole page as Markdown (for feeding to an LLM) / download
          // it. Sits above the first section; web-only, and self-contained
          // (renders nothing, no spacing, off web). See web/docs.md, which this
          // page is kept in sync with.
          const DocsMarkdownActions(),
          for (var i = 0; i < docsSections.length; i++)
            Padding(
              key: _keys[i],
              // Sections are separated with `space-y-8` (32px).
              padding: EdgeInsets.only(top: i == 0 ? 0 : 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(
                    section: docsSections[i],
                    onAnchorTap: () => _anchorTo(i),
                  ),
                  const SizedBox(height: 16),
                  ..._content(context, docsSections[i].id),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A section heading followed by its own deep link.
///
/// The heading text stays plain selectable text: making the whole line a tap
/// target would fight text selection. The link lives in the icon beside it.
class _SectionTitle extends StatefulWidget {
  const _SectionTitle({required this.section, required this.onAnchorTap});

  final DocsSection section;

  /// Re-anchors the page on this section and points the URL at it.
  final VoidCallback onAnchorTap;

  @override
  State<_SectionTitle> createState() => _SectionTitleState();
}

class _SectionTitleState extends State<_SectionTitle> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      hitTestBehavior: .opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Flexible(
            child: Text(
              widget.section.title,
              style: TextStyle(
                color: context.colors.foreground,
                fontSize: 30,
                fontWeight: FontWeight.w600,
                // Headings use `tracking-tight` (-0.025em ≈ -0.75px @30px).
                letterSpacing: -0.75,
                height: 1.2,
              ),
            ),
          ),
          Padding(
            padding: const .only(top: 6),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: hovering ? 1 : 0,
              child: _SectionAnchorLink(onTap: widget.onAnchorTap),
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
          padding: const .all(4),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: _hovered ? 1 : 0.32,
            child: Transform.rotate(
              angle: math.pi / 180 * -45,
              child: AppIcon(
                DiffIcon.link,
                size: 20,
                color: context.colors.foreground,
              ),
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

class _Sidebar extends StatefulWidget {
  const _Sidebar({required this.active, required this.onTap});

  final int active;
  final ValueChanged<int> onTap;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  final ScrollController _controller = ScrollController();
  final List<GlobalKey> _tileKeys = List.generate(
    docsSections.length,
    (_) => GlobalKey(),
  );

  @override
  void initState() {
    super.initState();
    // Deep links land with a non-zero active section; jump the rail there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealActive(animate: false);
    });
  }

  @override
  void didUpdateWidget(_Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _revealActive();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Scrolls the rail just enough to keep the active tile visible as the
  /// scroll-spy follows the page. The two edge-pinned policies are each a
  /// no-op when the tile is already inside that edge, so at most one animates.
  void _revealActive({bool animate = true}) {
    if (!_controller.hasClients) return;
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
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Walk the groups in order, carrying a running index into the flattened
    // section list so active-state and taps map back to the right anchor.
    final children = <Widget>[];
    var index = 0;
    for (var gi = 0; gi < docsGroups.length; gi++) {
      children.add(
        Padding(
          padding: EdgeInsets.only(top: gi == 0 ? 0 : 22, bottom: 8, left: 12),
          child: DocsGroupLabel(docsGroups[gi].title),
        ),
      );
      for (final section in docsGroups[gi].sections) {
        final i = index++;
        children.add(
          DocsSectionTile(
            key: _tileKeys[i],
            label: section.title,
            active: i == widget.active,
            onTap: () => widget.onTap(i),
          ),
        );
      }
    }
    return SizedBox(
      width: 220,
      child: SingleChildScrollView(
        controller: _controller,
        padding: const EdgeInsets.only(right: 12, bottom: 48),
        child: Column(
          // Stretch so the selected pill spans the full rail width,
          // rather than shrink-wrapping the label.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// Pins its [child] to a fixed screen position while [controller] scrolls, by
/// translating it downward by the current scroll offset - the equivalent of
/// CSS `position: sticky` for a short left rail inside a page-level scroll.
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
        // compact/wide breakpoint the old and new scroll views can both be
        // attached to this controller for a frame, and `offset` throws when
        // more than one position exists.
        final offset = controller.positions.length == 1
            ? controller.offset
            : 0.0;
        return Transform.translate(offset: Offset(0, offset), child: sticky);
      },
      child: child,
    );
  }
}

/// The compact trigger: a breadcrumb bar pinned under the nav that shows where
/// you are (`Docs › <section>`) and opens the navigation popup on tap, styled
/// as a compact mobile docs header.
class _CompactDocsBar extends StatelessWidget {
  const _CompactDocsBar({required this.sectionTitle, required this.onOpen});

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
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // The icon set has no right chevron; a quarter-turn of the
                  // dropdown chevron points it at the section title.
                  RotatedBox(
                    quarterTurns: 3,
                    child: AppIcon(
                      DiffIcon.chevronDown,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Section content ------------------------------------------------------

List<Widget> _content(BuildContext context, String id) {
  switch (id) {
    case 'introduction':
      return const [
        DocProse(
          'ConstraintLayout is a layout for Flutter, ported from Android, that '
          'positions and sizes children by the **constraints you declare** '
          'instead of by nesting boxes. Every child is a direct child of one '
          '`ConstraintLayout`, and each says where its own edges go: pinned to '
          'the parent, or to a sibling.',
        ),
        DocProse(
          'If you have built Flutter UIs you know the other way: a `Row` inside a '
          '`Column` inside a `Stack` inside a `Padding`, several levels deep, '
          'just to place a handful of widgets. ConstraintLayout keeps the tree '
          '**flat**. Relationships that would otherwise need wrapper widgets '
          '("put this after that", "line these up", "let this one fill the '
          'rest") become properties on the child itself.',
        ),
        DocH3('The mental model'),
        DocBullets([
          '**Anchor, not nest.** A child links its edges (`start`, `top`, and so '
              'on) to the parent or a sibling. `top: .bottomOf(#header)` reads as '
              '"my top goes at the header\'s bottom".',
          '**Ids, not order.** Children are identified by a `Symbol` id (like '
              '`#header`) and refer to each other by id, so the order of the list '
              'does not decide position.',
          '**Solve, not stack.** Android\'s own layout engine, ported to Dart, '
              'resolves every edge and size from the constraints. See **How '
              'the engine works**.',
        ]),
        DocProse(
          'The rest of these docs walk the features one at a time, each with a '
          'live example you can read beside the layout it produces. Everything '
          'is behind a single import. These docs are a guided tour; the '
          'package README on pub.dev is the full guide and also covers '
          'z-order, sizing inside scroll views, the debug overlay, common '
          'mistakes, Android parity, performance, and the limitations.',
        ),
      ];
    case 'features':
      return const [
        DocProse(
          'Most of Android\'s ConstraintLayout is here, behind a single import '
          'and a Flutter-native API. MotionLayout, `ConstraintSet`, and the '
          '`Layer` and `Placeholder` helpers are not ported. At a glance, this '
          'is what you get:',
        ),
        DocH3('Positioning'),
        DocBullets([
          '**Anchors and links.** Pin any edge (`start`, `end`, `top`, `bottom`, '
              'the absolute `left` / `right`, or the text `baseline`) to the '
              'parent or a sibling, with per-link `margin` and `goneMargin`.',
          '**Centering and bias.** Opposing anchors center a child; '
              '`horizontalBias` / `verticalBias` slide it along the axis, '
              'proportional as the parent resizes.',
          '**Circular positioning.** Place a child at an angle and radius around '
              'another, for dials, clock faces, and radial menus.',
        ]),
        DocH3('Sizing'),
        DocBullets([
          '**Dimensions beyond wrap and fill.** `.matchConstraint` fills the span '
              'between two anchors, `.percent` takes a fraction of the parent, '
              'and `.spread` / `.constrainedWrap` bound a fill or a wrap.',
          '**Aspect ratio.** Fix one axis and derive the other to hold a '
              '`width / height` ratio, ideal for 16 : 9 or square media.',
        ]),
        DocH3('Chains and helpers'),
        DocBullets([
          '**Chains with weights.** Widgets linked to each other share an axis '
              'like flexbox: `.spread`, `.spreadInside`, or `.packed`, splitting '
              'leftover space by per-child weight.',
          '**Guidelines.** An invisible line at a fixed offset or a percent of '
              'the parent that many siblings can share.',
          '**Barriers.** A line that tracks the furthest edge of a set of '
              'widgets, so content always clears the tallest or widest '
              'member.',
          '**Visibility.** Every child is `visible`, `invisible` (holds its '
              'space), or `gone` (collapses, switching links to `goneMargin`).',
          '**Groups.** A `ConstraintGroup` sets the visibility of several '
              'children at once, like Android\'s `Group`.',
        ]),
        DocH3('Virtual layouts'),
        DocBullets([
          '**Flow and Grid.** `ConstraintFlow` and `ConstraintGrid` arrange '
              'referenced children without wrapping them, so those children stay '
              'direct siblings other constraints can still target.',
        ]),
        DocH3('Under it all'),
        DocBullets([
          '**Android\'s pipeline.** The same measure passes, `Direct` pass, '
              'and Cassowary solver as Android\'s ConstraintLayout, in its '
              '32-bit float arithmetic, so a layout gets Android\'s frames.',
          '**Pure Dart, every platform.** RTL-aware anchors, no native code, '
              'and frames checked against Android\'s own code on nearly two '
              'million layouts.',
        ]),
        DocProse(
          'Each of these has its own section below, with a live example you can '
          'read beside the layout it produces.',
        ),
      ];
    case 'installation':
      return const [
        DocNote(
          'Requires Dart 3.12 or newer and Flutter 3.44 or newer. The API is '
          'designed around Dart dot shorthands such as `.startOf(parent)`, '
          'which every example in these docs uses.',
        ),
        DocProse('Add the package with the Flutter CLI:'),
        CodeBlock(
          code: Snippets.install,
          lang: 'shellscript',
          showLineNumbers: false,
        ),
        DocProse('Or add it to your `pubspec.yaml` directly:'),
        CodeBlock(
          code: Snippets.pubspec,
          lang: 'yaml',
          filename: 'pubspec.yaml',
        ),
        DocProse(
          'Then import it. That one import brings in every widget, dimension, '
          'link, and helper you will see in these docs:',
        ),
        CodeBlock(
          code: Snippets.importLine,
          lang: 'dart',
          showLineNumbers: false,
        ),
      ];
    case 'quick-start':
      return [
        const DocProse(
          'Here is a complete `ConstraintLayout` with one child, pinned 16 '
          'logical pixels from the parent\'s top-start corner. The source is on '
          'one side and the layout it renders on the other.',
        ),
        const DocNote(
          'Every example uses `DemoBox`, a plain colored box with a label, in '
          'place of real content, so the focus stays on the constraints. Swap it '
          'for any widget of your own.',
        ),
        docExamples['quick-start']!,
        const DocProse(
          'Read each link as **"my edge, at the target\'s edge"**: '
          '`start: .startOf(parent, margin: 16)` puts this child\'s start edge 16 '
          'past the parent\'s start edge. Point it at a sibling id instead of '
          '`parent` to pin to a sibling. That single idea, an edge linked to an '
          'edge, is the whole foundation.',
        ),
      ];
    case 'anchors':
      return [
        const DocProse(
          'A **link** ties one of this widget\'s edges to an edge of a target. '
          'The parameter names your edge; the constructor names the target\'s '
          'edge. Horizontal edges come in absolute (`left`, `right`) and '
          'RTL-aware (`start`, `end`) pairs; vertical edges are `top`, `bottom`, '
          'and the text `baseline`.',
        ),
        docExamples['anchors']!,
        const DocProse(
          'In the example, B links to A rather than to the parent: '
          '`start: .endOf(#a)` places B just after A and `top: .topOf(#a)` lines '
          'their tops up. Move A and B follows.',
        ),
        const DocH3('The links'),
        const DocTable(
          headers: ['Your edge', 'Kind', 'Constructors (the target\'s edge)'],
          rows: [
            [
              '`left` / `right`',
              'Absolute horizontal edges',
              '`.leftOf` `.rightOf` `.startOf` `.endOf`',
            ],
            [
              '`start` / `end`',
              'RTL-aware horizontal edges',
              '`.startOf` `.endOf` `.leftOf` `.rightOf`',
            ],
            ['`top` / `bottom`', 'Vertical edges', '`.topOf` `.bottomOf`'],
            [
              '`baseline`',
              'Text baseline',
              '`.baselineOf` `.topOf` `.bottomOf`',
            ],
            [
              '`circle`',
              'Center, on a circle around the target\'s center',
              '`.around` (see **Circular positioning**)',
            ],
          ],
        ),
        const DocProse(
          'Every link constructor except `.around` takes a `margin`, and a '
          '`goneMargin` used instead when the target is `gone` (see '
          '**Visibility**). A `top` or `bottom` link to `.baselineOf` is '
          'ignored; align baselines through `baseline`.',
        ),
        const DocProse(
          'Links must not loop back on themselves. Four kinds of loop leave '
          'none of their children a position to start from: two children '
          'whose matching edges link to each other (two tops, for example), '
          'an edge linked to itself, two children linked both ways on both '
          'sides, and a chain whose first child\'s start links one way to its '
          'last child while the last child\'s end links back to the first '
          'child. Debug builds report each of them with a `FlutterError`, as '
          'they report a link to an unknown id; baseline links are not '
          'followed, so two baselines linked to each other are not reported. '
          'Profile and release builds still lay the layout out. Android never '
          'finishes laying out a layout with the last kind, and lays out the '
          'others as this layout does: two children whose tops link to each '
          'other, for example, both sit at the top edge.',
        ),
        const DocNote(
          'Build each id the same way everywhere it appears. For ids made in a '
          'loop with `Symbol(\'item\$i\')`, refer to them through the same '
          'call, for example a helper `Symbol item(int i) => '
          'Symbol(\'item\$i\');`, never through a literal such as `#item0` or a '
          '`const Symbol(\'item0\')`. Release and profile WebAssembly builds, '
          'and builds compiled with `--obfuscate`, rename symbol literals, so '
          'there `#item0` is not equal to `Symbol(\'item0\')` and a link that '
          'mixes the two forms is silently skipped. Debug builds treat them as '
          'equal, so the mistake does not show up while you develop.',
        ),
        const DocH3('Right-to-left'),
        const DocProse(
          '`start` and `end` follow the text direction: the layout\'s '
          '`textDirection`, otherwise the ambient `Directionality`. A layout '
          'written with them mirrors in right-to-left text, and, following '
          'Android\'s rules, so do these:',
        ),
        const DocBullets([
          'The horizontal bias of a child with a `start` or `end` link: it '
              'becomes `1 - horizontalBias`, so it is measured from the start, '
              'a packed chain\'s bias included. A child linked only with `left` '
              'and `right` keeps its bias measured from the left.',
          'Vertical guidelines: `begin` and `percent` are measured from the '
              'right and `end` from the left. Horizontal guidelines do not '
              'change.',
          '`ConstraintFlow`: its rows start at the right edge, and '
              '`contentHorizontalBias` is measured from the start.',
        ]),
        const DocProse(
          '`ConstraintGrid` mirrors too, which Android\'s grid helpers leave '
          'unimplemented: its first column is the rightmost, so the cells fill '
          'from the right. Cell numbers in `spans` and `skips`, and the '
          'entries of `columnWeights`, still count from the first column, and '
          'a tile\'s `horizontalBias` is measured from the start edge of its '
          'cell.',
        ),
        const DocProse(
          'A barrier\'s own `margin` does not mirror: as on Android, a positive '
          'value moves every barrier right or down, a `.start` or `.end` one '
          'included. For a gap that mirrors, put it on the links that target '
          'the barrier.',
        ),
      ];
    case 'centering-bias':
      return [
        const DocProse(
          'Give a widget **both** opposing anchors on an axis (start and end, or '
          'top and bottom) and it centers between them. Add `horizontalBias` or '
          '`verticalBias` to slide it along that axis: 0 hugs the left or top, 1 '
          'hugs the right or bottom, and the default 0.5 is dead center. In '
          'right-to-left text the horizontal bias of a child linked with '
          '`start` or `end` mirrors, as on Android, so 0 hugs the right (see '
          '**Anchors & links**).',
        ),
        docExamples['centering-bias']!,
        const DocProse(
          'Bias is how you place something "a third of the way down" or "near the '
          'end" without hardcoding pixels: it stays proportional as the parent '
          'resizes.',
        ),
      ];
    case 'dimensions':
      return [
        const DocProse(
          'A child\'s `width` and `height` are each a `Dimension`. Beyond the '
          'familiar wrap-to-content and fill-the-parent, ConstraintLayout adds '
          'sizes that only make sense with constraints: fill the space **between '
          'two anchors**, or take a **percent** of the parent.',
        ),
        docExamples['dimensions']!,
        const DocH3('The dimensions'),
        const DocTable(
          headers: ['Dimension', 'Sizes to'],
          rows: [
            ['`.wrapContent`', 'The child\'s own content (the default).'],
            [
              '`.matchParent`',
              'The parent\'s full size. Link targets are ignored, but their '
                  'margins still inset it.',
            ],
            [
              '`.matchConstraint`',
              'The space between the two opposing anchors.',
            ],
            ['`.fixed(n)`', 'Exactly n logical pixels.'],
            ['`.percent(f)`', 'A fraction f of the parent on this axis.'],
            [
              '`.spread(min: a, max: b)`',
              'Like matchConstraint, but bounded.',
            ],
            ['`.constrainedWrap(...)`', 'Content, capped by the constraints.'],
          ],
        ),
        const DocNote(
          '`.matchConstraint` and `.spread` need **both** edges on the axis '
          'anchored to fill the space between them. With only one link the '
          'child sizes to its own content instead, which `.spread` keeps '
          'between its `min` and `max` (the other dimension follows, so text '
          'wraps at a capped width). `.percent` sizes to the parent, so one '
          'link is enough.',
        ),
      ];
    case 'aspect-ratio':
      return [
        const DocProse(
          'Set `aspectRatio` and the engine derives one dimension from the other '
          'to hold a `width / height` ratio. Fix one axis, make the other '
          '`matchConstraint`, and it is computed for you, ideal for media that '
          'must stay 16 : 9 or square.',
        ),
        docExamples['aspect-ratio']!,
      ];
    case 'chains':
      return [
        const DocProse(
          'When two or more widgets link to **each other** in a line (first to '
          'second, second back to first, and so on) they form a **chain**: a '
          'group that shares its space as a unit, much like flexbox\'s '
          'justify-content. The two outer edges anchor to something outside the '
          'chain.',
        ),
        docExamples['chains']!,
        const DocH3('Chain styles'),
        const DocProse(
          'Set the style on the chain\'s **head** (the first member) with '
          '`horizontalChainStyle` or `verticalChainStyle`:',
        ),
        const DocBullets([
          '**`.spread`** (default): equal gaps everywhere, including the ends.',
          '**`.spreadInside`**: the ends sit flush against the outer anchors, '
              'with equal gaps between members.',
          '**`.packed`**: members are packed together and the head\'s bias moves '
              'the packed group along the axis.',
        ]),
        const DocProse(
          'Give members a `matchConstraint` size along the axis plus a '
          '`horizontalWeight` or `verticalWeight` to split the leftover space by '
          'ratio, exactly like `Expanded`\'s flex.',
        ),
      ];
    case 'guidelines':
      return [
        const DocProse(
          'A `Guideline` is an invisible line at a fixed offset or a **percent** '
          'of the parent that siblings anchor to. It is ideal for a shared '
          'column edge: everything linked to it moves together when the guideline '
          'moves.',
        ),
        docExamples['guidelines']!,
        const DocProse(
          'Use `Guideline.vertical` for a vertical line (siblings link their '
          'horizontal edges to it) and `Guideline.horizontal` for a horizontal '
          'one. Position it with exactly one of `begin`, `end`, or `percent`.',
        ),
      ];
    case 'barriers':
      return [
        const DocProse(
          'A `Barrier` is a line that tracks the **furthest** edge of a set of '
          'widgets. Anchor a form\'s value column to a barrier over its labels '
          'and the column always clears the longest label, no matter which one '
          'grows.',
        ),
        docExamples['barriers']!,
        const DocProse(
          'Pick the `edge` to track (`start`, `end`, `top`, `bottom`, and the '
          'absolute `left` / `right`) and list the widgets in `referenced`. A '
          'barrier has no size and draws nothing; it only reports a position. '
          'Its own `margin` moves it, and keeps its sign as on Android: a '
          'positive value moves every barrier right or down, whatever its '
          'edge and the text direction. For a gap that mirrors in '
          'right-to-left text, put the margin on the links that target the '
          'barrier instead.',
        ),
      ];
    case 'circular':
      return [
        const DocProse(
          'The `circle` link places a widget at an **angle and radius** around '
          'another widget\'s center, for radial menus, clock faces, or anything '
          'arranged on a dial. 0 degrees points straight up and angles increase '
          'clockwise.',
        ),
        docExamples['circular']!,
      ];
    case 'visibility':
      return [
        const DocProse(
          'Every child has a `visibility`, mirroring Android\'s three states:',
        ),
        const DocBullets([
          '**`.visible`** (default): laid out and drawn.',
          '**`.invisible`**: laid out and holds its space, but is not drawn, '
              'siblings still anchor to it exactly as if it were there.',
          '**`.gone`**: collapses to a zero-size point and is skipped entirely, '
              'and links targeting it switch from `margin` to `goneMargin`.',
        ]),
        docExamples['visibility']!,
        const DocProse(
          '`gone` removes a widget and reflows around it in one step, and '
          '`goneMargin` lets neighbors keep a sensible gap when they do. Because '
          'it is only a property, toggling it keeps the child mounted, so its '
          'state survives the round trip. Invisible and gone children are '
          'also left out of the semantics tree, so screen readers neither '
          'announce nor activate them, as on Android. To set the visibility '
          'of several children at once, use a group (below).',
        ),
        const DocH3('Try it'),
        const DocProse(
          'Flip B between the three states and watch C: `invisible` keeps B\'s '
          'space (C does not move), while `gone` collapses it and C slides in on '
          'its `goneMargin`.',
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kProseWidth),
            child: const VisibilityToggleDemo(),
          ),
        ),
        const DocH3('Groups'),
        const DocProse(
          'A `ConstraintGroup` sets the visibility of several children at '
          'once, like Android\'s `Group`. Its `visibility` replaces the '
          '`visibility` of every child listed in `referenced`, so one value '
          'from your state shows or hides a whole section of the layout:',
        ),
        docExamples['groups']!,
        const DocBullets([
          '**The group wins.** A referenced child takes the group\'s '
              'visibility for layout, painting, hit testing, and semantics, '
              'whatever its own `visibility` says. When several groups '
              'reference the same child, the one that comes last in '
              '`children` wins.',
          '**A group only sets visibility.** Like Android\'s `Group`, it is a '
              'child of the layout with a widget of its own, laid out at '
              '0 x 0 at the layout\'s origin, but it never moves or sizes '
              'anything. No link can target it, and no barrier, flow, grid, or '
              'other group can reference it. It can reference `Constrained` '
              'children, flows, and grids; guidelines and barriers have no '
              'visibility, so it leaves them as they are.',
          '**Changing its `visibility` costs what changing the children\'s '
              'would.** Each referenced child is updated exactly as if its own '
              '`visibility` had changed.',
        ]),
      ];
    case 'flow':
      return [
        const DocProse(
          'If you have reached for `Wrap` to lay a run of chips or buttons out '
          'and let them spill onto the next line, `ConstraintFlow` is the '
          'constraint-native version. The difference is that it is **virtual**: '
          'it does not wrap the widgets it arranges in a subtree of its own.',
        ),
        const DocH3('What "virtual" means'),
        const DocProse(
          'A normal layout widget like `Row` or `Wrap` becomes the parent of its '
          'children: they live inside it, and nothing outside can point at them. '
          'A virtual layout is different. Its children stay **direct siblings** '
          'in the one `ConstraintLayout`; the flow only reads their sizes and '
          'hands back positions. You list the ones it should arrange by id in '
          '`referenced`, and they remain fair game for any other constraint, so '
          'a barrier or a chain can still target a widget that a flow is placing.',
        ),
        const DocProse(
          'It lays the referenced widgets out in a chain and wraps to a new run '
          'when it runs out of width, just like `Wrap`, but every wrapped run is '
          'itself a chain you can style.',
        ),
        docExamples['flow']!,
        const DocH3('Wrap modes'),
        const DocBullets([
          '**`.none`** (default): a single run that does not wrap (a plain '
              'chain).',
          '**`.chain`**: wraps into as many runs as it needs, filling each run '
              'before starting the next and laying each one out as its own '
              'chain, the closest match to `Wrap`.',
          '**`.aligned`**: wraps and also lines the runs up column-for-column, '
              'so the result reads as a grid.',
        ]),
        const DocProse(
          'Set `horizontalGap` and `verticalGap` for the spacing between items '
          'and runs, and `horizontalChainStyle` / `contentHorizontalBias` to '
          'control how each run distributes its slack, as a chain\'s style and '
          'bias do. `contentHorizontalBias` is always measured from the start, '
          'so it mirrors in right-to-left text.',
        ),
      ];
    case 'grid':
      return [
        const DocProse(
          '`ConstraintGrid` is to `GridView` what `ConstraintFlow` is to `Wrap`: '
          'it places its `referenced` children into a fixed grid of `rows` by '
          '`columns` cells, in order. Unlike `GridView` it does not scroll and '
          'does not become their parent; it is **virtual**, so the tiles stay '
          'siblings in the single layer that other constraints can still target.',
        ),
        const DocProse(
          'Children fill the cells row by row from the start edge: left to '
          'right, or right to left in right-to-left text. Give a tile '
          '`width: .matchConstraint` and `height: .matchConstraint` to fill its '
          'cell, or leave it to wrap its own content and sit within the cell.',
        ),
        docExamples['grid']!,
        const DocH3('Spans, skips, and weights'),
        const DocBullets([
          '**Spans** let one tile cover several cells: `spans: \'0:1x2\'` makes '
              'the tile at cell 0 span one row and two columns, using Android\'s '
              '`index:RxC` syntax. The entries are sorted by cell index and go '
              'to the tiles in order: the lowest index to the first tile, the '
              'next to the second. Entries beyond the last tile are ignored.',
          '**Skips** leave cells empty so the flow of tiles steps over them, '
              'with the same `index:RxC` syntax in `skips`.',
          '**Weights** (`rowWeights`, `columnWeights`) hand out the grid\'s space '
              'unevenly, so a column can take twice the width of its neighbor. '
              'A list shorter than the number of rows or columns is padded '
              'with weights of 1, and a longer one is trimmed.',
        ]),
        const DocProse(
          'Anchor the grid itself like any child (here all four edges to the '
          'parent), and it sizes and positions the whole set of tiles as a unit.',
        ),
      ];
    case 'profile-card':
      return [
        const DocProse(
          'Here is a small, real layout that uses several features at once: an '
          'avatar, a name and handle beside it, a **barrier** under the taller of '
          'the header pieces, and a bio spanning the full width below. It is one '
          'flat layer, with no `Row`, `Column`, or `Stack` nesting.',
        ),
        docExamples['profile-card']!,
        const DocProse(
          'Each piece states its own relationships: the name fills the width up '
          'to the parent\'s end (`matchConstraint`), the handle sits under the '
          'name, and the bio starts below `#headerEnd` (the barrier), so it '
          'always clears both the avatar and the text no matter which is taller.',
        ),
      ];
    case 'engine':
      return const [
        DocProse(
          'ConstraintLayout does not position children by nesting boxes; it '
          '**solves** for each child\'s location and size from the constraints '
          'you declared. It does that with Android\'s own layout pipeline, '
          'ported line by line from `androidx.constraintlayout` to pure Dart.',
        ),
        DocH3('Android\'s pipeline'),
        DocProse(
          'Each layout pass measures the layout the way Android\'s '
          '`ConstraintLayout` measures itself. Every child is measured as '
          'Android\'s view measurer measures a child view: laid out under the '
          'constraints of the measure spec Android would give it, with its '
          'size rounded up to whole pixels and its baseline read. In the first '
          'measure pass, the **`Direct`** pass places everything that follows '
          'directly from the links, such as a widget linked to edges already '
          'placed, a centered widget at its bias, a guideline, or a barrier '
          'once all of its widgets are placed. The **Cassowary solver** '
          'settles the rest, such as chains, aspect ratios, and percent sizes: '
          'a port of Android\'s `LinearSystem`, the algorithm family behind '
          'Apple\'s Auto Layout. Children whose size the solver decided are '
          'measured again at that size, and the layout is solved again when '
          'an answer changed.',
        ),
        DocProse(
          'Every float operation is the 32-bit one Android performs, in the '
          'same order, so values round where Android\'s do, and every child is '
          'placed at the integer frame Android computes.',
        ),
        DocH3('Optimization levels'),
        DocProse(
          'Android\'s optimization flags are the layout\'s `optimizationLevel`. '
          'The default, `OptimizationLevel.standard`, is Android\'s default: '
          'the `Direct` pass and measure caching. `OptimizationLevel.none` '
          'leaves everything to the solver. The dependency-graph levels, '
          '`OptimizationLevel.graph` and `OptimizationLevel.graphWrap`, are an '
          'opt-in, as on Android, and run where Android runs the graph: in a '
          'layout without chains, flows, or grids that is bounded on both '
          'axes (with `graphWrap`, also when an axis wraps its content: the '
          'graph then resolves the bounded axes, and the solver runs too). At '
          'every level the layout gives Android\'s result at that level, '
          'apart from layouts Flutter and Android lay out a different number '
          'of times (see the README\'s limitations).',
        ),
        DocH3('Persistent model and replay'),
        DocProse(
          'The engine model is built once and kept alive across frames, so a '
          'frame does only the work its changes need:',
        ),
        DocBullets([
          '**replay**: the configuration and the incoming constraints are '
              'those of the last layout, which repeated the one before it. '
              'Every child is asked again for the measures the last layout '
              'asked of it, and when every answer is the same, the children '
              'go back where they were without running the engine.',
          '**in-place**: a link, margin, bias, size, ratio, chain style, '
              'weight, or visibility changed, so the model is updated in place '
              'and measured again without a rebuild. New incoming constraints, '
              'and a child whose content changed size, also measure the '
              'existing model again.',
          '**rebuild**: the child set or a helper changed structurally, or the '
              'text direction changed, so the model is rebuilt from scratch.',
        ]),
        DocProse(
          'Most real layouts are placed by `Direct`, and a measure of one takes '
          'microseconds. Chains and other simultaneous constraints are the '
          'solver\'s, and cost more as they grow, so for a large, chain-heavy '
          'screen, several small layouts are cheaper than one big one. The '
          'package README has the measured numbers.',
        ),
      ];
    case 'android':
      return const [
        DocProse(
          'The engine is a line-faithful port of `constraintlayout-core`, and '
          'of the part of Android\'s `ConstraintLayout` view that drives it, '
          'pinned to a specific upstream revision. It is checked against '
          'Android\'s own code at that revision, frame by frame: 60,000 real '
          '`ConstraintLayout` widget trees laid out by this package, and more '
          'than 1.8 million engine layouts (realistic screens, targeted edge '
          'cases, and adversarial ones), give the same frames as Android, with '
          '0 differences, and on a sample of 2,000 layouts every operation of '
          'the solver matches Java\'s bit for bit. The package README has the '
          'details.',
        ),
        DocProse(
          'Right-to-left text follows Android\'s rules too: the horizontal bias '
          'of a child linked with start or end mirrors, so does the position '
          'of a vertical guideline, and a barrier\'s margin keeps its sign. '
          '`ConstraintGrid` mirrors as well, which Android\'s grid helpers '
          'leave unimplemented (see **Anchors & links**).',
        ),
        DocProse(
          'Parity holds for the same measure answers, in logical pixels. A '
          'Flutter `Text` does not measure like an Android `TextView`, so the '
          'layout rules match while the content sizes are Flutter\'s. Frames '
          'are whole logical pixels, which are Android\'s device pixels at a '
          'device pixel ratio of 1. And `ConstraintGrid`, which follows the '
          'core grid behind Compose rather than Android\'s view-based grid, '
          'has no Android result to compare with.',
        ),
      ];
    default:
      return const [];
  }
}
