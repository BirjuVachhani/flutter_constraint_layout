import 'package:flutter/material.dart';
import 'package:site_kit/site_kit.dart';

import 'demo_kit.dart';
import 'sample_content.dart';
import 'specimen.dart';

/// Components: everything the package exports as a widget, grouped by the job
/// it does on a page.
final List<SpecimenGroup> componentGroups = [
  _actions,
  _content,
  _navigation,
  _pageBlocks,
];

final SpecimenGroup _actions = SpecimenGroup(
  id: 'actions',
  title: 'Actions',
  blurb: 'Buttons, pills, badges, copy.',
  specimens: [
    Specimen(
      id: 'buttons',
      title: 'SiteButton',
      description:
          'Five variants across three sizes. Hover and press are painted by '
          'the component, not Material ink.',
      width: 460,
      builder: (context) => SpecStack(
        gap: 16,
        children: [
          for (final variant in SiteButtonVariant.values)
            SpecRow(
              label: variant.name,
              child: SpecWrap(
                children: [
                  for (final size in SiteButtonSize.values)
                    SiteButton(
                      label: size.name,
                      variant: variant,
                      size: size,
                      onPressed: () {},
                    ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          const SpecLabel('states & icons'),
          SpecWrap(
            children: [
              SiteButton(
                label: 'With icon',
                leadingIcon: SiteIcons.github,
                size: SiteButtonSize.sm,
                onPressed: () {},
              ),
              SiteButton(
                label: 'External',
                variant: SiteButtonVariant.secondary,
                trailingIcon: SiteIcons.arrowUpRight,
                size: SiteButtonSize.sm,
                onPressed: () {},
              ),
              const SiteButton(
                label: 'Disabled',
                size: SiteButtonSize.sm,
                onPressed: null,
              ),
              const SiteButton(
                label: 'Working',
                variant: SiteButtonVariant.secondary,
                size: SiteButtonSize.sm,
                busy: true,
                onPressed: null,
              ),
            ],
          ),
          const SizedBox(height: 2),
          const SpecLabel('expand'),
          SiteButton(
            label: 'Fills its parent',
            variant: SiteButtonVariant.outline,
            size: SiteButtonSize.sm,
            expand: true,
            onPressed: () {},
          ),
        ],
      ),
    ),
    Specimen(
      id: 'icon-buttons',
      title: 'SiteIconButton',
      description: 'The square hover-pill button the nav bar and toolbars use.',
      builder: (context) => SpecStack(
        children: [
          SpecRow(
            label: 'default',
            child: Row(
              children: [
                SiteIconButton(
                  icon: SiteIcons.github,
                  tooltip: 'GitHub',
                  onPressed: () {},
                ),
                SiteIconButton(
                  icon: SiteIcons.discord,
                  tooltip: 'Discord',
                  onPressed: () {},
                ),
                SiteIconButton(
                  materialIcon: Icons.search_rounded,
                  tooltip: 'Search',
                  onPressed: () {},
                ),
              ],
            ),
          ),
          SpecRow(
            label: 'selected',
            child: SiteIconButton(
              icon: SiteIcons.folders,
              tooltip: 'Selected',
              selected: true,
              onPressed: () {},
            ),
          ),
          const SpecRow(
            label: 'disabled',
            child: SiteIconButton(
              icon: SiteIcons.refresh,
              tooltip: 'Unavailable',
              onPressed: null,
            ),
          ),
        ],
      ),
    ),
    Specimen(
      id: 'badges',
      title: 'SiteBadge',
      description: 'Static label chips, in four tones.',
      builder: (context) => SpecStack(
        children: [
          const SpecLabel('outline'),
          SpecWrap(
            children: [
              for (final tone in BadgeTone.values)
                SiteBadge(tone.name, tone: tone),
            ],
          ),
          const SpecLabel('filled'),
          SpecWrap(
            children: [
              for (final tone in BadgeTone.values)
                SiteBadge(tone.name, tone: tone, filled: true),
            ],
          ),
          const SpecLabel('with icon'),
          const SpecWrap(
            children: [
              SiteBadge('v0.1.0', icon: SiteIcons.folders),
              SiteBadge(
                'Passing',
                icon: SiteIcons.check,
                tone: BadgeTone.accent,
                filled: true,
              ),
            ],
          ),
        ],
      ),
    ),
    Specimen(
      id: 'pills',
      title: 'SelectPill & PillGroup',
      description: 'A small set of mutually exclusive choices.',
      builder: (context) => const _PillDemo(),
    ),
    Specimen(
      id: 'command-pill',
      title: 'CommandPill',
      description:
          'The install line for a hero. Stays dark in both modes, the way a '
          'terminal snippet reads everywhere else.',
      builder: (context) => const Align(
        alignment: Alignment.centerLeft,
        child: CommandPill(command: 'flutter pub add site_kit', prompt: r'$'),
      ),
    ),
    Specimen(
      id: 'copy-button',
      title: 'CopyButton',
      description:
          'Writes to the clipboard and swaps to a checkmark for 1.6 seconds.',
      builder: (context) => SpecStack(
        children: [
          const SpecRow(
            label: 'default',
            child: Align(
              alignment: Alignment.centerLeft,
              child: CopyButton(text: 'Copied from the storyboard.'),
            ),
          ),
          SpecRow(
            label: 'tinted',
            child: Align(
              alignment: Alignment.centerLeft,
              child: CopyButton(
                text: 'Copied from the storyboard.',
                size: 20,
                color: context.brand.azure,
              ),
            ),
          ),
        ],
      ),
    ),
  ],
);

final SpecimenGroup _content = SpecimenGroup(
  id: 'content',
  title: 'Content',
  blurb: 'Code, prose, tables, callouts, cards.',
  specimens: [
    Specimen(
      id: 'code-block',
      title: 'CodeBlock',
      description:
          'Highlighted by shiki_flutter, off the main thread, following the '
          'site\'s light/dark mode.',
      width: 560,
      builder: (context) => SpecStack(
        gap: 6,
        children: [
          const SpecLabel('with a filename header'),
          const CodeBlock(
            code: SampleContent.dartSnippet,
            lang: 'dart',
            filename: 'main.dart',
          ),
          const SpecLabel('bare, floating copy button'),
          const CodeBlock(
            code: SampleContent.yamlSnippet,
            lang: 'yaml',
            showLineNumbers: false,
          ),
          const SpecLabel('shell'),
          const CodeBlock(
            code: SampleContent.shellSnippet,
            lang: 'shellscript',
            showLineNumbers: false,
          ),
          const SpecLabel('pinned theme, ignoring light/dark'),
          const CodeBlock(
            code: 'const answer = 42;',
            lang: 'dart',
            theme: PierreThemes.pierreDark,
            showLineNumbers: false,
          ),
          const SpecLabel('unregistered language, degrades to plain mono'),
          const CodeBlock(
            code: '# heading\n- unhighlighted, not crashed',
            lang: 'markdown',
            showLineNumbers: false,
          ),
        ],
      ),
    ),
    Specimen(
      id: 'prose',
      title: 'Prose',
      description:
          'Docs authored in Dart. Every string takes `code` and **bold** '
          'inline.',
      width: 560,
      builder: (context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProseHeading('Anchors and links', level: 2),
          Prose(SampleContent.proseParagraph),
          ProseHeading('What you get'),
          ProseList(SampleContent.bullets),
          ProseList(SampleContent.steps, ordered: true),
        ],
      ),
    ),
    Specimen(
      id: 'prose-table',
      title: 'ProseTable',
      description:
          'A borderless table with row rules. A cell that is one `code` token '
          'renders as a chip.',
      width: 560,
      builder: (context) => const ProseTable(
        headers: SampleContent.tableHeaders,
        rows: SampleContent.tableRows,
      ),
    ),
    Specimen(
      id: 'callouts',
      title: 'Callout',
      description: 'Asides in four tones.',
      width: 560,
      builder: (context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Callout(
            'Tokens resolve through `context.colors`, so a callout follows the '
            'palette without knowing it.',
          ),
          Callout(
            'Pass `title:` for a lead line above the body.',
            tone: CalloutTone.tip,
            title: 'Tip',
          ),
          Callout(
            'Path URLs need the host to serve `index.html` for unknown paths.',
            tone: CalloutTone.warning,
            title: 'Deploying',
          ),
          Callout(
            'Nesting two SelectionAreas breaks keyboard copy inside code '
            'blocks.',
            tone: CalloutTone.danger,
            title: 'Avoid',
          ),
        ],
      ),
    ),
    Specimen(
      id: 'inline-links',
      title: 'InlineLinkText',
      description:
          'Weaves links into body copy and owns their gesture recognizers, so '
          'the caller stays stateless.',
      width: 560,
      builder: (context) => InlineLinkText(
        SampleContent.linkParagraph,
        links: const [
          TextLink('Flutter', url: 'https://flutter.dev'),
          TextLink('the buttons frame', route: '/frame/buttons'),
        ],
      ),
    ),
    Specimen(
      id: 'feature-grid',
      title: 'FeatureCard & FeatureGrid',
      description:
          'Cards in a row share the tallest one\'s height, which a Wrap cannot '
          'do.',
      width: 700,
      builder: (context) => FeatureGrid(features: sampleFeatures(context)),
    ),
  ],
);

final SpecimenGroup _navigation = SpecimenGroup(
  id: 'navigation',
  title: 'Navigation & chrome',
  blurb: 'Wordmark, nav, rails, menus, footers.',
  specimens: [
    Specimen(
      id: 'wordmark',
      title: 'Wordmark & LogoMark',
      description:
          'Both read SiteConfig. The logo defaults to a monogram tile; set '
          'SiteConfig.logo to replace it.',
      width: 460,
      builder: (context) => SpecStack(
        children: [
          const SpecRow(label: 'wordmark', child: Wordmark()),
          const SpecRow(
            label: 'with logo',
            child: Wordmark(showLogo: true, alwaysShowTagline: true),
          ),
          SpecRow(
            label: 'logo sizes',
            child: Row(
              children: [
                for (final size in [24.0, 32.0, 48.0, 64.0])
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: LogoMark(size: size),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    Specimen(
      id: 'nav-bar',
      title: 'SiteNavBar',
      description:
          'Links, actions, and the theme control, all from SiteConfig. The '
          'bottom hairline fades in once the page scrolls.',
      width: 820,
      surface: SpecimenSurface.page,
      padded: false,
      builder: (context) => const Column(
        children: [
          SiteNavBar(currentRoute: '/'),
          SizedBox(height: 12),
          SiteNavBar(currentRoute: '/', themeControl: ThemeControl.menu),
        ],
      ),
    ),
    Specimen(
      id: 'theme-switchers',
      title: 'Theme switching',
      description:
          'Three controls over one ThemeController. The choice is persisted in '
          'localStorage on web.',
      width: 460,
      builder: (context) => SpecStack(
        children: [
          const SpecRow(
            label: 'toggle',
            child: Align(
              alignment: Alignment.centerLeft,
              child: ThemeToggleButton(),
            ),
          ),
          const SpecRow(
            label: 'menu',
            child: Align(
              alignment: Alignment.centerLeft,
              child: ThemeModeMenu(alignRight: false),
            ),
          ),
          const SpecRow(
            label: 'segmented',
            child: Align(
              alignment: Alignment.centerLeft,
              child: ThemeModeSegmented(),
            ),
          ),
          Text(
            'Current mode: ${themeModeLabel(SiteThemeScope.of(context).value)}',
            style: context.text.caption,
          ),
        ],
      ),
    ),
    Specimen(
      id: 'dropdown',
      title: 'SiteDropdown',
      description:
          'An OverlayPortal popover: real surface, fade and scale on open, '
          'outside tap to close.',
      width: 460,
      builder: (context) => const _DropdownDemo(),
    ),
    Specimen(
      id: 'section-rail',
      title: 'SectionList',
      description:
          'The grouped section list shared by the docs rail and the mobile nav '
          'sheet, so the two can never drift.',
      width: 460,
      builder: (context) => const _SectionListDemo(),
    ),
    Specimen(
      id: 'nav-sheet',
      title: 'Nav sheet',
      description:
          'The single compact-width menu. It lists site links plus whatever '
          'sections the on-screen page registered.',
      width: 460,
      builder: (context) => Align(
        alignment: Alignment.centerLeft,
        child: SiteButton(
          label: 'Open nav sheet',
          variant: SiteButtonVariant.secondary,
          size: SiteButtonSize.sm,
          leadingIcon: SiteIcons.menu,
          onPressed: () => showSiteNavSheet(context, currentRoute: '/'),
        ),
      ),
    ),
    Specimen(
      id: 'footer-full',
      title: 'SiteFooter',
      description: 'Wordmark and blurb beside link columns, from SiteConfig.',
      width: 820,
      surface: SpecimenSurface.page,
      padded: false,
      builder: (context) => const SiteFooter(),
    ),
    Specimen(
      id: 'footer-compact',
      title: 'CompactFooter',
      description:
          'Centered logo, wordmark, and one wrapped row of every known link.',
      width: 820,
      surface: SpecimenSurface.page,
      padded: false,
      builder: (context) => const CompactFooter(),
    ),
  ],
);

final SpecimenGroup _pageBlocks = SpecimenGroup(
  id: 'blocks',
  title: 'Page blocks',
  blurb: 'The big slabs a landing page is made of.',
  specimens: [
    Specimen(
      id: 'hero',
      title: 'HeroSection',
      description:
          'Logo, headline, lede with inline links, and actions. Its top '
          'padding already clears the sticky nav.',
      width: 900,
      surface: SpecimenSurface.page,
      padded: false,
      builder: (context) => HeroSection(
        headline: 'Ship a Flutter site in an afternoon.',
        lede: SampleContent.heroLede,
        ledeLinks: const [TextLink('go_router', url: 'https://pub.dev/packages/go_router')],
        actions: [
          const CommandPill(command: 'flutter pub add site_kit'),
          SiteButton(
            label: 'Documentation',
            variant: SiteButtonVariant.secondary,
            leadingMaterialIcon: Icons.menu_book_rounded,
            onPressed: () {},
          ),
        ],
      ),
    ),
    Specimen(
      id: 'hero-split',
      title: 'HeroSection with an aside',
      description:
          'Pass `aside:` to split the hero in two on wide viewports; it drops '
          'below the text when the layout goes compact.',
      width: 900,
      surface: SpecimenSurface.page,
      padded: false,
      builder: (context) => HeroSection(
        showLogo: false,
        eyebrow: const SiteBadge('New', tone: BadgeTone.accent, filled: true),
        headline: 'Constraints, not nesting.',
        lede: 'The aside takes any widget: a screenshot, a live demo, a code card.',
        actions: [SiteButton(label: 'Get started', onPressed: () {})],
        aside: const CodeBlock(
          code: SampleContent.dartSnippet,
          lang: 'dart',
          filename: 'example.dart',
          margin: EdgeInsets.zero,
        ),
      ),
    ),
    Specimen(
      id: 'cta-band',
      title: 'CtaBand',
      description: 'The closing call to action, framed by hairlines.',
      width: 900,
      surface: SpecimenSurface.page,
      padded: false,
      builder: (context) => CtaBand(
        title: 'Free, open source, and built for Flutter.',
        body: SampleContent.ctaBody,
        actions: [
          SiteButton(
            label: 'View on GitHub',
            leadingIcon: SiteIcons.github,
            trailingIcon: SiteIcons.arrowUpRight,
            size: SiteButtonSize.sm,
            onPressed: () {},
          ),
          SiteButton(
            label: 'pub.dev',
            variant: SiteButtonVariant.secondary,
            trailingIcon: SiteIcons.arrowUpRight,
            size: SiteButtonSize.sm,
            onPressed: () {},
          ),
        ],
      ),
    ),
    Specimen(
      id: 'sections',
      title: 'SiteSection',
      description:
          'Vertical rhythm: 56px of padding when compact, 96px when wide, with '
          'an optional full-bleed background and top hairline.',
      width: 900,
      surface: SpecimenSurface.page,
      padded: false,
      builder: (context) => Column(
        children: [
          SiteSection(
            top: 32,
            bottom: 32,
            child: SectionHeading(
              title: 'A plain section',
              subtitle: 'Padding follows the breakpoint.',
            ),
          ),
          SiteSection(
            top: 32,
            bottom: 32,
            border: true,
            background: context.colors.surface,
            child: const SectionHeading(
              title: 'With a background and border',
              subtitle: 'The background runs edge to edge; the content does not.',
            ),
          ),
        ],
      ),
    ),
  ],
);

class _PillDemo extends StatefulWidget {
  const _PillDemo();

  @override
  State<_PillDemo> createState() => _PillDemoState();
}

class _PillDemoState extends State<_PillDemo> {
  String _selected = 'Dart';

  @override
  Widget build(BuildContext context) {
    return SpecStack(
      children: [
        const SpecLabel('PillGroup'),
        PillGroup<String>(
          values: const ['Dart', 'YAML', 'Shell'],
          selected: _selected,
          labelOf: (value) => value,
          onChanged: (value) => setState(() => _selected = value),
        ),
        Text('Selected: $_selected', style: context.text.caption),
      ],
    );
  }
}

class _DropdownDemo extends StatefulWidget {
  const _DropdownDemo();

  @override
  State<_DropdownDemo> createState() => _DropdownDemoState();
}

class _DropdownDemoState extends State<_DropdownDemo> {
  String _picked = 'Nothing yet';

  @override
  Widget build(BuildContext context) {
    return SpecStack(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SiteDropdown(
            triggerBuilder: (context, open, toggle) => SiteButton(
              label: 'Actions',
              variant: SiteButtonVariant.secondary,
              size: SiteButtonSize.sm,
              trailingIcon: SiteIcons.chevronDown,
              onPressed: toggle,
            ),
            overlayBuilder: (context, close) => MenuPanel(
              width: 210,
              children: [
                MenuItemRow(
                  label: 'Copy as Markdown',
                  icon: SiteIcons.copy,
                  onTap: () {
                    setState(() => _picked = 'Copy as Markdown');
                    close();
                  },
                ),
                MenuItemRow(
                  label: 'Download .md',
                  materialIcon: Icons.file_download_outlined,
                  onTap: () {
                    setState(() => _picked = 'Download .md');
                    close();
                  },
                ),
                const MenuSeparator(),
                MenuItemRow(
                  label: 'Open in new tab',
                  icon: SiteIcons.arrowUpRight,
                  onTap: () {
                    setState(() => _picked = 'Open in new tab');
                    close();
                  },
                ),
              ],
            ),
          ),
        ),
        Text('Last choice: $_picked', style: context.text.caption),
      ],
    );
  }
}

class _SectionListDemo extends StatefulWidget {
  const _SectionListDemo();

  @override
  State<_SectionListDemo> createState() => _SectionListDemoState();
}

class _SectionListDemoState extends State<_SectionListDemo> {
  int _active = 1;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: SiteLayout.railWidth,
      child: SectionList(
        groups: SampleContent.docsGroups,
        activeIndex: _active,
        onSelect: (index) => setState(() => _active = index),
      ),
    );
  }
}
