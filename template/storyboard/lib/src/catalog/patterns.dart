import 'package:flutter/material.dart';
import 'package:site_kit/site_kit.dart';

import 'sample_content.dart';
import 'specimen.dart';
import 'viewport_frame.dart';

/// Patterns: whole pages, rendered live at two viewport widths so the
/// responsive behavior is visible side by side instead of described.
final List<SpecimenGroup> patternGroups = [_patterns];

final SpecimenGroup _patterns = SpecimenGroup(
  id: 'patterns',
  title: 'Page patterns',
  blurb: 'Full pages at desktop and phone widths, live.',
  specimens: [
    Specimen(
      id: 'pattern-landing',
      title: 'Landing page',
      description:
          'Shell, hero, feature grid, CTA, footer. The frame overrides the '
          'MediaQuery size, so this really is the desktop layout.',
      width: 1180,
      surface: SpecimenSurface.none,
      padded: false,
      builder: (context) => const ViewportFrame(
        width: 1160,
        height: 760,
        child: _LandingPage(),
      ),
    ),
    Specimen(
      id: 'pattern-landing-mobile',
      title: 'Landing page, phone',
      description:
          'The same widget tree at 390px: nav links fold into the menu button, '
          'the grid drops to one column, section padding tightens.',
      width: 420,
      surface: SpecimenSurface.none,
      padded: false,
      builder: (context) => const ViewportFrame(
        width: 390,
        height: 760,
        child: _LandingPage(),
      ),
    ),
    Specimen(
      id: 'pattern-docs',
      title: 'Docs page',
      description:
          'DocsShell: a sticky rail beside the reading column, with scroll-spy '
          'keeping the two in step. Scroll inside the frame. Deep linking is '
          'switched off in these frames, so the headings show no link anchor '
          'and the canvas keeps its own URL.',
      width: 1180,
      surface: SpecimenSurface.none,
      padded: false,
      builder: (context) => const ViewportFrame(
        width: 1160,
        height: 760,
        child: _DocsPage(),
      ),
    ),
    Specimen(
      id: 'pattern-docs-mobile',
      title: 'Docs page, phone',
      description:
          'The rail collapses into a breadcrumb bar that opens the shared nav '
          'sheet, with the same sections in it.',
      width: 420,
      surface: SpecimenSurface.none,
      padded: false,
      builder: (context) => const ViewportFrame(
        width: 390,
        height: 760,
        child: _DocsPage(),
      ),
    ),
  ],
);

/// A miniature but complete landing page, assembled only from exported
/// components.
class _LandingPage extends StatelessWidget {
  const _LandingPage();

  @override
  Widget build(BuildContext context) {
    return SiteShell(
      currentRoute: '/',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HeroSection(
              headline: 'Ship a Flutter site in an afternoon.',
              lede: SampleContent.heroLede,
              ledeLinks: const [
                TextLink('go_router', url: 'https://pub.dev/packages/go_router'),
              ],
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
            SiteSection(
              top: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeading(
                    title: 'Everything a docs site needs.',
                    subtitle:
                        'One import, one config object, and the chrome is done.',
                  ),
                  const SizedBox(height: SiteSpacing.xl),
                  FeatureGrid(features: sampleFeatures(context)),
                ],
              ),
            ),
            CtaBand(
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
              ],
            ),
            const CompactFooter(),
          ],
        ),
      ),
    );
  }
}

/// A miniature docs page driven by [DocsShell].
class _DocsPage extends StatelessWidget {
  const _DocsPage();

  @override
  Widget build(BuildContext context) {
    return SiteShell(
      currentRoute: '/docs',
      child: DocsShell(
        groups: SampleContent.docsGroups,
        sectionBuilder: (context, section, index) =>
            SampleContent.docsSectionBody(section),
        footer: const CompactFooter(showLogo: false),
        // Two framed docs pages share the canvas, and the canvas has a URL of
        // its own. Deep linking is off here so they do not all write to the
        // one address bar; on a real page it is on, and each heading carries a
        // link anchor.
        deepLink: false,
      ),
    );
  }
}
