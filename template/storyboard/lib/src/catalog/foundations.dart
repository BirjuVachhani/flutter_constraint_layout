import 'package:flutter/material.dart';
import 'package:site_kit/site_kit.dart';

import 'demo_kit.dart';
import 'specimen.dart';

/// Foundations: the tokens every component is built from. Four columns, one
/// per concern, so the canvas reads left to right from color to layout.
final List<SpecimenGroup> foundationGroups = [
  _color,
  _typography,
  _spaceAndShape,
  _iconography,
  _layout,
];

final SpecimenGroup _color = SpecimenGroup(
  id: 'color',
  title: 'Color',
  blurb: 'Semantic tokens first, brand hues second.',
  specimens: [
    Specimen(
      id: 'colors-semantic',
      title: 'Semantic tokens',
      description:
          'context.colors. Every component reads these, never a raw hex, which '
          'is what makes one palette swap re-skin the whole site.',
      width: 380,
      builder: (context) => SpecStack(
        gap: 10,
        children: [
          for (final entry in context.colors.named.entries)
            Swatch(name: entry.key, color: entry.value),
        ],
      ),
    ),
    Specimen(
      id: 'colors-brand',
      title: 'Brand palette',
      description:
          'context.brand. Vivid hues sampled from the code theme, so '
          'illustrations and syntax highlighting agree.',
      width: 380,
      builder: (context) {
        final brand = context.brand;
        return SpecStack(
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final entry in brand.named.entries)
                  SizedBox(
                    width: 160,
                    child: Swatch(name: entry.key, color: entry.value),
                  ),
              ],
            ),
            const SpecLabel('swatch rotation'),
            Row(
              children: [
                for (var i = 0; i < 8; i++)
                  Expanded(
                    child: Container(
                      height: 34,
                      margin: EdgeInsets.only(right: i == 7 ? 0 : 4),
                      decoration: BoxDecoration(
                        color: brand.swatch(i),
                        borderRadius: BorderRadius.circular(SiteRadii.xs),
                      ),
                    ),
                  ),
              ],
            ),
            Text(
              'brand.swatch(i) cycles these for multi-series visuals.',
              style: context.text.caption,
            ),
          ],
        );
      },
    ),
    Specimen(
      id: 'colors-canvas',
      title: 'Illustration canvas',
      description:
          'canvas, canvasGrid, canvasBorder, and guide: the surface for '
          'diagrams and previews.',
      width: 380,
      builder: (context) {
        final brand = context.brand;
        return Container(
          height: 150,
          decoration: BoxDecoration(
            color: brand.canvas,
            border: Border.all(color: brand.canvasBorder),
            borderRadius: BorderRadius.circular(SiteRadii.md),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 20,
                top: 20,
                child: _Box(color: brand.azure),
              ),
              Positioned(
                right: 20,
                bottom: 20,
                child: _Box(color: brand.green),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 74,
                child: Container(height: 1, color: brand.guide),
              ),
            ],
          ),
        );
      },
    ),
  ],
);

final SpecimenGroup _typography = SpecimenGroup(
  id: 'typography',
  title: 'Typography',
  blurb: 'One ramp, read through context.text.',
  specimens: [
    Specimen(
      id: 'type-scale',
      title: 'Type scale',
      description:
          'context.text.<name>. Headings scale with SiteTypography.scale; body '
          'copy does not, so a bigger display never costs readability.',
      width: 520,
      builder: (context) {
        final styles = context.text;
        return SpecStack(
          gap: 18,
          children: [
            for (final entry in styles.named.entries)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.key}  ·  '
                    '${entry.value.fontSize!.toStringAsFixed(1)}px  ·  '
                    'w${entry.value.fontWeight?.value ?? 400}',
                    style: context.text.caption,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The quick brown fox',
                    style: entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
          ],
        );
      },
    ),
    Specimen(
      id: 'type-families',
      title: 'Families',
      description:
          'Geist and Geist Mono ship inside the package, so a consuming app '
          'declares no fonts of its own.',
      width: 520,
      builder: (context) => SpecStack(
        children: [
          const SpecLabel('sans · SiteFonts.sans'),
          for (final weight in [
            FontWeight.w400,
            FontWeight.w500,
            FontWeight.w600,
            FontWeight.w700,
          ])
            Text(
              'Sphinx of black quartz, judge my vow — ${weight.value}',
              style: TextStyle(
                fontFamily: SiteFonts.sans,
                fontSize: 17,
                fontWeight: weight,
              ),
            ),
          const SizedBox(height: 6),
          const SpecLabel('mono · SiteFonts.mono'),
          for (final weight in [
            FontWeight.w400,
            FontWeight.w500,
            FontWeight.w700,
          ])
            Text(
              'const x = 0xFF_00_A3; // ${weight.value}',
              style: TextStyle(
                fontFamily: SiteFonts.mono,
                fontSize: 15,
                fontWeight: weight,
              ),
            ),
        ],
      ),
    ),
  ],
);

final SpecimenGroup _spaceAndShape = SpecimenGroup(
  id: 'space',
  title: 'Space & shape',
  blurb: 'The 4px scale, corner radii, surfaces, motion.',
  specimens: [
    Specimen(
      id: 'spacing',
      title: 'Spacing scale',
      description: 'SiteSpacing. Gaps, padding, and section rhythm.',
      builder: (context) => SpecStack(
        gap: 8,
        children: [
          for (final entry in SiteSpacing.named.entries)
            SpecRow(
              label: '${entry.key}  ${entry.value.toInt()}',
              child: MeasureBlock(size: entry.value),
            ),
          const SizedBox(height: 4),
          SpecRow(
            label: 'section',
            child: Text(
              '${SiteSpacing.sectionCompact.toInt()} compact  ·  '
              '${SiteSpacing.sectionWide.toInt()} wide',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    ),
    Specimen(
      id: 'radii',
      title: 'Corner radii',
      description: 'SiteRadii, from a code chip to a full pill.',
      builder: (context) => SpecWrap(
        gap: 14,
        children: [
          for (final entry in SiteRadii.named.entries)
            Column(
              children: [
                MeasureBlock(size: 0, radius: entry.value.clamp(0, 20)),
                const SizedBox(height: 6),
                Text(entry.key, style: context.text.caption),
              ],
            ),
        ],
      ),
    ),
    Specimen(
      id: 'surfaces',
      title: 'Surfaces & borders',
      description:
          'How the three background tokens layer, and what each border weight '
          'is for.',
      builder: (context) {
        final colors = context.colors;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(SiteRadii.md),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('background', style: context.text.caption),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(SiteRadii.sm),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('surface + border', style: context.text.caption),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surfaceInset,
                        borderRadius: BorderRadius.circular(SiteRadii.xs),
                        border: Border.all(color: colors.borderStrong),
                      ),
                      child: Text(
                        'surfaceInset + borderStrong',
                        style: context.text.caption,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
    Specimen(
      id: 'motion',
      title: 'Motion',
      description:
          'SiteMotion. Tap a bar to run it: fast for hover, medium for '
          'popovers, slow for scroll-to.',
      builder: (context) => const _MotionDemo(),
    ),
  ],
);

final SpecimenGroup _iconography = SpecimenGroup(
  id: 'icons',
  title: 'Iconography',
  blurb: 'The bundled SVG set, plus any Material glyph.',
  specimens: [
    Specimen(
      id: 'icon-set',
      title: 'SiteIcons',
      description:
          'Tinted with BlendMode.srcIn, so multi-opacity glyphs keep their '
          'depth. Anything outside this set falls back to Material.',
      builder: (context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final icon in SiteIcons.values)
            SizedBox(
              width: 88,
              child: Column(
                children: [
                  Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.colors.surfaceInset,
                      borderRadius: BorderRadius.circular(SiteRadii.sm),
                    ),
                    child: SiteIcon(icon, size: 20),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    icon.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.caption,
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
    Specimen(
      id: 'icon-sizes',
      title: 'Icon sizing',
      description: 'The sizes the components actually use.',
      builder: (context) => SpecStack(
        children: [
          for (final size in [13.0, 15.0, 16.0, 18.0, 20.0, 28.0])
            SpecRow(
              label: '${size.toInt()}px',
              child: Row(
                children: [
                  SiteIcon(SiteIcons.github, size: size),
                  const SizedBox(width: 14),
                  SiteIcon(SiteIcons.arrowUpRight, size: size),
                  const SizedBox(width: 14),
                  SiteIcon(
                    SiteIcons.check,
                    size: size,
                    color: context.colors.accent,
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  ],
);

final SpecimenGroup _layout = SpecimenGroup(
  id: 'layout',
  title: 'Layout & responsive',
  blurb: 'Breakpoints, the content column, adaptive grids.',
  specimens: [
    Specimen(
      id: 'breakpoints',
      title: 'Breakpoints',
      description:
          'context.breakpoint reads the viewport; ResponsiveBuilder reads the '
          'parent, so a panel adapts like a window would.',
      width: 460,
      builder: (context) {
        final active = context.breakpoint;
        return SpecStack(
          gap: 10,
          children: [
            for (final bp in Breakpoint.values)
              Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      bp.name,
                      style: context.text.label.copyWith(
                        color: bp == active
                            ? context.colors.foreground
                            : context.colors.mutedForeground,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 26,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: bp == active
                            ? context.brand.azure.withValues(alpha: 0.16)
                            : context.colors.surfaceInset,
                        borderRadius: BorderRadius.circular(SiteRadii.xs),
                        border: Border.all(
                          color: bp == active
                              ? context.brand.azure.withValues(alpha: 0.5)
                              : context.colors.border,
                        ),
                      ),
                      child: Text(
                        '≥ ${bp.minWidth.toInt()}px'
                        '${bp.isCompact ? '  ·  compact' : ''}'
                        '${bp == active ? '  ·  active' : ''}',
                        style: context.text.caption,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    ),
    Specimen(
      id: 'responsive-grid',
      title: 'ResponsiveGrid',
      description:
          'Column count follows the grid\'s own width, and every card in a row '
          'takes the tallest one\'s height. Resize the window to watch it '
          'reflow.',
      width: 520,
      builder: (context) => ResponsiveGrid(
        columns: const ResponsiveValue<int>(xs: 1, sm: 2, md: 3),
        children: [
          for (var i = 1; i <= 5; i++)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.surfaceInset,
                borderRadius: BorderRadius.circular(SiteRadii.sm),
                border: Border.all(color: context.colors.border),
              ),
              child: Text(
                i.isOdd
                    ? 'Card $i'
                    : 'Card $i with a longer body that wraps onto more lines.',
                style: context.text.bodySmall,
              ),
            ),
        ],
      ),
    ),
    Specimen(
      id: 'content-container',
      title: 'ContentContainer',
      description:
          'The shared horizontal rhythm: a ${SiteLayout.contentMaxWidth.toInt()}px '
          'column with ${SiteLayout.gutter.toInt()}px gutters, so every section '
          'lines up.',
      width: 520,
      surface: SpecimenSurface.page,
      padded: false,
      builder: (context) => Container(
        color: context.brand.azure.withValues(alpha: 0.07),
        child: ContentContainer(
          maxWidth: 360,
          child: Container(
            height: 70,
            alignment: Alignment.center,
            color: context.brand.azure.withValues(alpha: 0.16),
            child: Text('content column', style: context.text.caption),
          ),
        ),
      ),
    ),
    Specimen(
      id: 'section-heading',
      title: 'SectionHeading',
      description: 'Eyebrow, title, subtitle with inline links, and an action.',
      width: 520,
      builder: (context) => SectionHeading(
        eyebrow: 'Foundations',
        title: 'Everything is a token.',
        subtitle:
            'Read colors from context.colors and type from context.text. See '
            'the Flutter docs for how ThemeExtension resolves.',
        subtitleLinks: const [
          TextLink('Flutter docs', url: 'https://docs.flutter.dev'),
        ],
        trailing: SiteButton(
          label: 'Docs',
          size: SiteButtonSize.sm,
          variant: SiteButtonVariant.secondary,
          trailingIcon: SiteIcons.arrowRight,
          onPressed: () {},
        ),
      ),
    ),
  ],
);

class _Box extends StatelessWidget {
  const _Box({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 34,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(SiteRadii.xs),
      ),
    );
  }
}

/// Runs each [SiteMotion] duration on its own bar so the three speeds can be
/// compared side by side.
class _MotionDemo extends StatefulWidget {
  const _MotionDemo();

  @override
  State<_MotionDemo> createState() => _MotionDemoState();
}

class _MotionDemoState extends State<_MotionDemo> {
  bool _out = false;

  @override
  Widget build(BuildContext context) {
    const entries = <(String, Duration, Curve)>[
      ('fast · 120ms', SiteMotion.fast, SiteMotion.enter),
      ('medium · 220ms', SiteMotion.medium, SiteMotion.enter),
      ('slow · 420ms', SiteMotion.slow, SiteMotion.standard),
    ];
    return GestureDetector(
      onTap: () => setState(() => _out = !_out),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SpecStack(
          gap: 12,
          children: [
            for (final (label, duration, curve) in entries)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.text.caption),
                  const SizedBox(height: 5),
                  Container(
                    height: 26,
                    decoration: BoxDecoration(
                      color: context.colors.surfaceInset,
                      borderRadius: BorderRadius.circular(SiteRadii.xs),
                    ),
                    child: AnimatedAlign(
                      duration: duration,
                      curve: curve,
                      alignment: _out
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 44,
                        height: 26,
                        decoration: BoxDecoration(
                          color: context.brand.azure,
                          borderRadius: BorderRadius.circular(SiteRadii.xs),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            Text('Tap to replay.', style: context.text.caption),
          ],
        ),
      ),
    );
  }
}
