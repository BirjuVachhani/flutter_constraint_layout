import 'package:site_kit/site_kit.dart';

/// The storyboard's own site configuration.
///
/// It doubles as the worked example of a [SiteConfig]: the nav bar, footers,
/// and wordmark specimens on the canvas all render from exactly this object, so
/// editing it is the fastest way to see what each field drives.
const SiteConfig storyboardConfig = SiteConfig(
  name: 'site_kit',
  tagline: 'storyboard by',
  author: SiteAuthor(
    name: 'Birju Vachhani',
    url: 'https://github.com/BirjuVachhani',
  ),
  description:
      'Design tokens, theming, responsive layout, routing, and components for '
      'building Flutter web sites.',
  navLinks: [
    NavItem.route('Canvas', '/'),
    NavItem.route('Buttons', '/frame/buttons'),
    NavItem.external('Flutter', 'https://flutter.dev'),
  ],
  navActions: [
    NavItem.action(
      label: 'GitHub',
      icon: SiteIcons.github,
      url: 'https://github.com/BirjuVachhani',
    ),
  ],
  footerColumns: [
    FooterColumn('Foundations', [
      NavItem.route('Color', '/frame/colors-semantic'),
      NavItem.route('Typography', '/frame/type-scale'),
      NavItem.route('Spacing', '/frame/spacing'),
    ]),
    FooterColumn('Components', [
      NavItem.route('Buttons', '/frame/buttons'),
      NavItem.route('Code blocks', '/frame/code-block'),
      NavItem.route('Prose', '/frame/prose'),
    ]),
    FooterColumn('Elsewhere', [
      NavItem.external('Flutter', 'https://flutter.dev'),
      NavItem.external('pub.dev', 'https://pub.dev'),
    ]),
  ],
  footerBlurb:
      'Every component on this canvas ships in the package. Copy the config, '
      'swap the palette, and the whole site follows.',
  copyright: '© 2026 site_kit. Sample content for the storyboard.',
);
