import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/examples.dart';
import '../data/links.dart';
import '../data/real_world_examples.dart';
import '../data/snippets.dart';
import '../theme/tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icon.dart';
import '../widgets/brand_mark.dart';
import '../widgets/footer.dart';
import '../widgets/interactive_demos.dart';
import '../widgets/pill.dart';
import '../widgets/section.dart';

/// The maximum height a feature section's code card is allowed on the home
/// page. Past this, the snippet scrolls inside its card instead of stretching
/// the section (and its paired preview) ever taller. See `LiveExample.capped`.
const double _kHomeCodeCap = 440;

/// The landing page: hero with a live preview, feature sections that each pair
/// an idea with the layout it produces, a closing CTA, and the footer.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // The app shell provides the page-wide SelectionArea, so none is wrapped
    // here (a nested region would break keyboard copy in the code blocks).
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _Hero(),
          _FeaturesOverview(),
          _AnchorsFeature(),
          _DimensionsFeature(),
          _HelpersFeature(),
          _VirtualFeature(),
          _InteractiveFeature(),
          _RealWorldSection(),
          _EngineFeature(),
          _CtaBand(),
          SimpleFooter(),
        ],
      ),
    );
  }
}

class _Hero extends StatefulWidget {
  const _Hero();

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  late final TapGestureRecognizer _androidTap = TapGestureRecognizer()
    ..onTap = () => Links.open(Links.androidConstraintLayout);

  @override
  void dispose() {
    _androidTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final compact = context.isCompact;

    final headlineSize = compact ? 34.0 : 54.0;

    Widget headline = Text(
      'Constraint-based layout for Flutter.',
      style: TextStyle(
        color: colors.foreground,
        fontSize: headlineSize,
        fontWeight: FontWeight.w600,
        height: 1.05,
        letterSpacing: headlineSize * -0.025,
      ),
    );

    final subhead = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            color: colors.mutedForeground,
            fontSize: compact ? 16 : 19,
            height: 1.5,
          ),
          children: [
            TextSpan(
              text: 'flutter_constraint_layout',
              style: TextStyle(
                fontFamily: AppFonts.mono,
                color: colors.foreground,
                fontSize: compact ? 14.5 : 17,
              ),
            ),
            const TextSpan(text: ' is a faithful port of Android\'s '),
            TextSpan(
              text: 'ConstraintLayout',
              style: TextStyle(
                color: colors.foreground,
                decoration: TextDecoration.underline,
                decorationColor: colors.mutedForeground,
                decorationThickness: 1,
              ),
              recognizer: _androidTap,
            ),
            const TextSpan(
              text:
                  ' to Flutter, in pure Dart. Position and size every child by '
                  'the constraints you declare, and keep your widget tree flat '
                  'instead of nesting rows, columns, and stacks.',
            ),
          ],
        ),
      ),
    );

    final actions = Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const InstallCommand(command: Snippets.install),
        AppButton(
          label: 'Documentation',
          icon: Icons.menu_book_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: () => context.go('/docs'),
        ),
      ],
    );

    // Text-only hero, constrained to a comfortable measure so the headline
    // wraps for reading instead of stretching the full page width.
    final textColumn = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 780),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandMark(size: 60),
          const SizedBox(height: 20),
          headline,
          const SizedBox(height: 16),
          subhead,
          const SizedBox(height: 24),
          actions,
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        top: AppLayout.navHeight + (compact ? 44 : 88),
        bottom: compact ? 24 : 44,
      ),
      child: ContentContainer(
        child: Align(
          alignment: Alignment.centerLeft,
          child: textColumn,
        ),
      ),
    );
  }
}

/// Shared layout for a feature section: heading, then content.
class _FeatureBlock extends StatelessWidget {
  const _FeatureBlock({
    required this.title,
    required this.subtitle,
    required this.child,
    this.subtitleLink,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final (String label, String url)? subtitleLink;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 18 : 28),
      child: ContentContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(
              title: title,
              subtitle: subtitle,
              subtitleLink: subtitleLink,
            ),
            SizedBox(height: compact ? 24 : 36),
            child,
          ],
        ),
      ),
    );
  }
}

/// The at-a-glance feature grid near the top of the page: the full surface the
/// package covers, each with a one-line description. Its selling points (a
/// complete port and a Flutter-native API) are stated on their own terms, not as
/// a comparison to anything else.
class _FeaturesOverview extends StatelessWidget {
  const _FeaturesOverview();

  static const _items = <(IconData, String, String)>[
    (
      Icons.done_all_rounded,
      'The full layout toolkit',
      'Anchors, chains, barriers, guidelines, circular placement, flow, grid, '
          'and visibility, ported faithfully from Android ConstraintLayout.',
    ),
    (
      Icons.code_rounded,
      'A cleaner Dart API',
      'Dot-shorthand such as .startOf(#header) and .matchConstraint, Symbol '
          'ids, and static typing, with no XML or string DSL to learn.',
    ),
    (
      Icons.layers_clear_rounded,
      'Flat widget trees',
      'Every child is a direct sibling, so one layer of constraints replaces '
          'nested rows, columns, and stacks.',
    ),
    (
      Icons.aspect_ratio_rounded,
      'Sizes only constraints express',
      'Fill the span between two anchors, take a percent of the parent, hold '
          'an aspect ratio, or bound a wrap, beyond plain wrap and fill.',
    ),
    (
      Icons.link_rounded,
      'Chains with weights',
      'Share an axis like flexbox, spread, spreadInside, or packed, and split '
          'the leftover space by per-child weight.',
    ),
    (
      Icons.straighten_rounded,
      'Guidelines and barriers',
      'Anchor to a shared percentage line, or to a barrier that tracks the '
          'furthest edge of a group so content always clears it.',
    ),
    (
      Icons.grid_view_rounded,
      'Virtual layouts',
      'ConstraintFlow and ConstraintGrid arrange referenced children without '
          'wrapping them, so they stay siblings other constraints can target.',
    ),
    (
      Icons.donut_large_rounded,
      'Circular positioning',
      'Place a child at an angle and radius around another, for dials, clock '
          'faces, and radial menus.',
    ),
    (
      Icons.public_rounded,
      'Pure Dart, every platform',
      'RTL-aware start and end anchors, no native code, and a resolver '
          'verified at parity with androidx core 1.1.1.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 18 : 28),
      child: ContentContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeading(
              title: 'Everything ConstraintLayout does, in Dart.',
              subtitle:
                  'A faithful, complete port with a Flutter-native API. These '
                  'are the pieces you get, all behind a single import.',
            ),
            SizedBox(height: compact ? 24 : 36),
            LayoutBuilder(
              builder: (context, c) {
                final cols = compact ? 1 : (c.maxWidth >= 960 ? 3 : 2);
                return _FeatureGrid(items: _items, cols: cols);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The feature grid, laid out as a single `ConstraintLayout` so every card in a
/// row takes the height of the tallest card in that row.
///
/// Each card is two constrained siblings: a bordered *surface* whose height is a
/// match-constraint stretched down to a per-row bottom `Barrier`, and the
/// icon/title/description *content* on top at its natural (wrap-content) height.
/// Only the content feeds the barrier, so the barrier settles on the tallest
/// content in the row and every surface fills to meet it. The content never
/// anchors to the stretched surface (that back-reference is what would make the
/// dependency circular): both anchor independently to the shared column edges
/// and row line, the content just inset by the card padding.
///
/// Columns are split by percentage `Guideline`s and the whole thing wraps its
/// own height, so it drops in where the old `Wrap` sat with no fixed sizing.
class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.items, required this.cols});

  final List<(IconData, String, String)> items;
  final int cols;

  /// Gap between cards, and the padding from a card's edge to its content.
  static const double _gap = 16;
  static const double _pad = 20;

  @override
  Widget build(BuildContext context) {
    final rowCount = (items.length + cols - 1) ~/ cols;

    Symbol guide(int i) => Symbol('featGuide$i');
    Symbol surface(int i) => Symbol('featSurface$i');
    Symbol body(int i) => Symbol('featBody$i');
    Symbol barrier(int r) => Symbol('featBarrier$r');

    final children = <Widget>[
      // Interior column dividers: evenly spaced percentage guidelines.
      for (var i = 1; i < cols; i++)
        Guideline.vertical(id: guide(i), percent: i / cols),
    ];

    for (final (i, (icon, title, desc)) in items.indexed) {
      final col = i % cols;
      final row = i ~/ cols;
      final last = col == cols - 1;

      // Surface edges: flush to the parent on the outer sides, inset half a gap
      // from the interior guideline between two columns.
      final HorizontalLink sLeft =
          col == 0 ? .leftOf(parent) : .rightOf(guide(col), margin: _gap / 2);
      final HorizontalLink sRight =
          last ? .rightOf(parent) : .leftOf(guide(col + 1), margin: _gap / 2);
      final VerticalLink sTop = row == 0
          ? .topOf(parent)
          : .bottomOf(barrier(row - 1), margin: _gap);

      // Content edges: the same targets, inset by the padding. Anchored to the
      // column and row (never to the surface), so there is no back-reference.
      final HorizontalLink cLeft = col == 0
          ? .leftOf(parent, margin: _pad)
          : .rightOf(guide(col), margin: _gap / 2 + _pad);
      final HorizontalLink cRight = last
          ? .rightOf(parent, margin: _pad)
          : .leftOf(guide(col + 1), margin: _gap / 2 + _pad);
      final VerticalLink cTop = row == 0
          ? .topOf(parent, margin: _pad)
          : .bottomOf(barrier(row - 1), margin: _gap + _pad);

      children.add(Constrained(
        id: surface(i),
        left: sLeft,
        right: sRight,
        top: sTop,
        bottom: .bottomOf(barrier(row)),
        width: .matchConstraint,
        height: .matchConstraint,
        child: const _FeatureCardSurface(),
      ));
      children.add(Constrained(
        id: body(i),
        left: cLeft,
        right: cRight,
        top: cTop,
        width: .matchConstraint,
        height: .wrapContent,
        child: _FeatureCardBody(icon: icon, title: title, desc: desc),
      ));
    }

    // One bottom barrier per row over that row's content, offset by the padding
    // so each surface keeps an even inset below the tallest content in the row.
    for (var row = 0; row < rowCount; row++) {
      final start = row * cols;
      final end = (start + cols).clamp(0, items.length);
      children.add(Barrier(
        id: barrier(row),
        edge: .bottom,
        referenced: [for (var i = start; i < end; i++) body(i)],
        margin: _pad,
      ));
    }

    return ConstraintLayout(children: children);
  }
}

/// The bordered box behind a feature card. Empty on purpose: it carries only the
/// border and stretches to the row's shared height, while [_FeatureCardBody]
/// paints on top of it.
class _FeatureCardSurface extends StatelessWidget {
  const _FeatureCardSurface();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(color: context.colors.border),
        ),
      ),
    );
  }
}

/// A feature card's content: an accent-tinted icon over a title and a one-line
/// description. Its natural height is what drives its row's barrier.
class _FeatureCardBody extends StatelessWidget {
  const _FeatureCardBody({
    required this.icon,
    required this.title,
    required this.desc,
  });

  final IconData icon;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: brand.azure.withValues(alpha: 0.12),
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          child: Icon(icon, size: 20, color: brand.azure),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: TextStyle(
            color: colors.foreground,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          desc,
          style: TextStyle(
            color: colors.mutedForeground,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// The real-world section: components that are genuinely awkward or impossible
/// with plain Row / Column / Stack, to show where the constraint model actually
/// earns its keep. Each example gets its own heading and description directly
/// above the code and preview, so the reason it needs constraints is stated
/// right where it is shown.
class _RealWorldSection extends StatelessWidget {
  const _RealWorldSection();

  static const _items = <(String, String, String)>[
    (
      'aligned-form',
      'Align a column to the widest label',
      'The values line up just past the longest label. A barrier tracks the '
          'widest of the four, so rename any label and the whole value column '
          'shifts to match, all in one flat layer with no table or nested rows.',
    ),
    (
      'radial-menu',
      'Place actions around a circle',
      'Five actions positioned by angle and radius around the center hub. No '
          'Row, Column, or Stack arranges children on a circle: it takes the '
          'constraint engine to solve the trigonometry for you.',
    ),
    (
      'overlap-seam',
      'Overlap the seam between two regions',
      'The avatar anchors both its top and bottom to the cover\'s bottom edge, '
          'so its center lands on the seam and it straddles the banner and the '
          'body below. Overlapping a boundary like this is a Stack-and-offset '
          'job in plain Flutter.',
    ),
    (
      'guideline-split',
      'Share one line across panes and a handle',
      'A single guideline sets the split; both panes and the handle anchor to '
          'it. The handle stays centered on the seam and the whole thing reflows '
          'with the container, with no manual offsets and no LayoutBuilder.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final gap = compact ? 44.0 : 64.0;
    return _FeatureBlock(
      title: 'For the layouts Flutter cannot express.',
      subtitle:
          'Anything a Row and a Column already do easily is not a reason to '
          'reach for constraints. These are the layouts that are: each is one '
          'flat layer of anchored siblings, with no Row, Column, or Stack '
          'nesting to fake it.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, (id, title, description)) in _items.indexed) ...[
            if (index > 0) SizedBox(height: gap),
            _RealWorldItem(
              title: title,
              description: description,
              example: realWorldExamples[id]!,
            ),
          ],
        ],
      ),
    );
  }
}

/// One entry in the [_RealWorldSection]: a title and a short description sitting
/// directly above the example's code and preview, so each example carries its
/// own reason for needing the constraint model.
class _RealWorldItem extends StatelessWidget {
  const _RealWorldItem({
    required this.title,
    required this.description,
    required this.example,
  });

  final String title;
  final String description;
  final Widget example;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 768),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.foreground,
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: TextStyle(
                  color: colors.mutedForeground,
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        example,
      ],
    );
  }
}

class _AnchorsFeature extends StatelessWidget {
  const _AnchorsFeature();

  @override
  Widget build(BuildContext context) {
    return _FeatureBlock(
      title: 'Anchor edges, do not nest boxes.',
      subtitle:
          'Every child is a direct child of one ConstraintLayout, and each says '
          'where its edges go: pinned to the parent, or to a sibling by id. '
          'Read the code beside the layout it produces.',
      child: docExamples['anchors']!.capped(_kHomeCodeCap),
    );
  }
}

class _DimensionsFeature extends StatelessWidget {
  const _DimensionsFeature();

  @override
  Widget build(BuildContext context) {
    return _FeatureBlock(
      title: 'Sizes only constraints can express.',
      subtitle:
          'Beyond wrap-to-content and fill-the-parent, a child can fill the '
          'space between two anchors, take a percent of the parent, or hold an '
          'aspect ratio, all resolved for you.',
      child: docExamples['dimensions']!.capped(_kHomeCodeCap),
    );
  }
}

class _HelpersFeature extends StatelessWidget {
  const _HelpersFeature();

  @override
  Widget build(BuildContext context) {
    return _FeatureBlock(
      title: 'Helpers for real layouts.',
      subtitle:
          'Guidelines, barriers, chains, and circular positioning handle the '
          'arrangements that usually mean extra wrapper widgets. A barrier '
          'tracks the furthest edge of a group, so content clears it every time.',
      child: docExamples['barriers']!.capped(_kHomeCodeCap),
    );
  }
}

class _VirtualFeature extends StatelessWidget {
  const _VirtualFeature();

  @override
  Widget build(BuildContext context) {
    return _FeatureBlock(
      title: 'Rows, grids, and wraps, kept flat.',
      subtitle:
          'Flow is the constraint answer to Wrap and Grid to GridView, with one '
          'difference: they are virtual. They arrange the children you name '
          'without wrapping them in a subtree, so those children stay direct '
          'siblings a barrier, chain, or another constraint can still target.',
      child: docExamples['flow']!.capped(_kHomeCodeCap),
    );
  }
}

/// An interactive touch on the landing page: the visibility toggle, so a reader
/// can drive a real ConstraintLayout and watch it reflow, rather than only read
/// static examples.
class _InteractiveFeature extends StatelessWidget {
  const _InteractiveFeature();

  @override
  Widget build(BuildContext context) {
    return _FeatureBlock(
      title: 'Change a property, watch it reflow.',
      subtitle:
          'Position and size are just properties, so they animate and toggle '
          'like any other. Flip B between visible, invisible, and gone and watch '
          'C respond: invisible holds the space, gone collapses it and C slides '
          'in on its goneMargin.',
      child: const VisibilityToggleDemo(
        sideBySide: true,
        maxHeight: _kHomeCodeCap,
      ),
    );
  }
}

/// The "Constraints Engine" section: educates the reader on both strategies the
/// engine uses (the dependency graph and the Cassowary solver) and the
/// persistent model that keeps steady-state frames cheap, mirroring the engine
/// section in the package READMEs and the docs.
class _EngineFeature extends StatelessWidget {
  const _EngineFeature();

  static const _platforms = [
    ('iOS', Icons.phone_iphone_rounded),
    ('Android', Icons.android_rounded),
    ('Web', Icons.language_rounded),
    ('macOS', Icons.laptop_mac_rounded),
    ('Windows', Icons.desktop_windows_rounded),
    ('Linux', Icons.computer_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;

    const graph = _EngineCard(
      icon: Icons.account_tree_rounded,
      tag: 'Fast path',
      title: 'Dependency graph',
      body:
          'Most layouts are deterministic: once the parent size and a child\'s '
          'anchors are known, its position follows by propagation. The graph '
          'resolves each measurable quantity in dependency order and measures '
          'every child exactly once, with no iteration and no search. This is '
          'the path almost every real screen takes.',
    );
    const solver = _EngineCard(
      icon: Icons.functions_rounded,
      tag: 'Fallback',
      title: 'Cassowary solver',
      body:
          'Some layouts go beyond what the graph resolves: barriers, circular '
          'links, Flow and Grid, a chain with a gone or aspect-ratio member, or '
          'a chain along an axis that sizes to its content. For those the '
          'engine falls back to a linear constraint solver, the same Cassowary '
          'algorithm behind Apple\'s Auto Layout.',
    );

    final cards = compact
        ? const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [graph, SizedBox(height: 16), solver],
          )
        : const IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: graph),
                SizedBox(width: 16),
                Expanded(child: solver),
              ],
            ),
          );

    return _FeatureBlock(
      title: 'Two engines under one layout.',
      subtitle:
          'The engine resolves most layouts with a fast dependency graph and '
          'falls back to a Cassowary constraint solver for the genuinely '
          'simultaneous ones. Both parts are pure Dart, ported from androidx, '
          'so the layout runs on every platform Flutter targets.',
      subtitleLink: ('Cassowary', Links.androidxCore),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cards,
          const SizedBox(height: 16),
          const _EngineCard(
            icon: Icons.cached_rounded,
            tag: 'Every frame',
            title: 'Persistent, incremental model',
            body:
                'The model is built once and kept alive across frames, then '
                'invalidated in tiers. A steady-state frame reuses the previous '
                'geometry (carrying scrolling and animation for free); a changed '
                'margin or dimension re-resolves in place; only a structural '
                'change rebuilds. A 1200-widget screen resolves in well under a '
                'millisecond.',
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, icon) in _platforms)
                AppBadge(label, icon: icon),
            ],
          ),
        ],
      ),
    );
  }
}

/// One engine card in the [_EngineFeature] section: an accent icon and a small
/// tag pill over a title and an explanatory paragraph, on the site's card
/// surface. Used for both the two strategy cards and the persistent-model card.
class _EngineCard extends StatelessWidget {
  const _EngineCard({
    required this.icon,
    required this.tag,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String tag;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: brand.azure.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(icon, size: 20, color: brand.azure),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceInset,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                    color: colors.mutedForeground,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: colors.foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              color: colors.mutedForeground,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// The closing call-to-action above the footer, framed by a hairline that pairs
/// with the footer's own top border.
class _CtaBand extends StatelessWidget {
  const _CtaBand();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final compact = context.isCompact;
    return ContentContainer(
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.border),
            bottom: BorderSide(color: colors.border),
          ),
        ),
        margin: const EdgeInsets.only(top: 48),
        padding: EdgeInsets.symmetric(vertical: compact ? 48 : 64),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Free, open source, and built for Flutter.',
              style: TextStyle(
                color: colors.foreground,
                fontSize: 24,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.3,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 672),
              child: Text(
                'flutter_constraint_layout is developed in the open and free for '
                'everyone to use. Star the repo, open an issue, or pull it in '
                'from pub.dev. Every contribution and bug report makes the '
                'layout better.',
                style: TextStyle(
                  color: colors.mutedForeground,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                AppButton(
                  label: 'View on GitHub',
                  leadingDiffIcon: DiffIcon.github,
                  size: AppButtonSize.sm,
                  trailingDiffIcon: DiffIcon.arrowUpRight,
                  onPressed: () => Links.open(Links.github),
                ),
                AppButton(
                  label: 'pub.dev',
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.sm,
                  trailingDiffIcon: DiffIcon.arrowUpRight,
                  onPressed: () => Links.open(Links.pubDev),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
