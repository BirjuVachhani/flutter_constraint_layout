import 'package:flutter/material.dart';

import '../responsive/breakpoints.dart';
import '../theme/context_extensions.dart';
import '../theme/tokens.dart';
import 'site_icon.dart';

/// One entry in a [FeatureGrid].
@immutable
class Feature {
  const Feature({
    required this.title,
    required this.description,
    this.icon,
    this.materialIcon,
    this.color,
    this.onTap,
  });

  final String title;
  final String description;
  final SiteIcons? icon;
  final IconData? materialIcon;

  /// Tint for the icon tile. Defaults to the brand's primary hue.
  final Color? color;

  /// Makes the whole card tappable.
  final VoidCallback? onTap;
}

/// A bordered card: a tinted icon tile over a title and a description.
///
/// Its height is driven by its content; put it in a [FeatureGrid] (or any
/// [ResponsiveGrid]) to make every card in a row match the tallest.
class FeatureCard extends StatefulWidget {
  const FeatureCard({super.key, required this.feature, this.padding = 20});

  final Feature feature;
  final double padding;

  @override
  State<FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<FeatureCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final styles = context.text;
    final feature = widget.feature;
    final tint = feature.color ?? context.brand.azure;
    final tappable = feature.onTap != null;

    Widget card = AnimatedContainer(
      duration: SiteMotion.fast,
      padding: EdgeInsets.all(widget.padding),
      decoration: ShapeDecoration(
        color: _hovered && tappable ? colors.surfaceInset : null,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(SiteRadii.lg),
          side: BorderSide(
            color: _hovered && tappable ? colors.borderStrong : colors.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (feature.icon != null || feature.materialIcon != null) ...[
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: tint.withValues(alpha: 0.12),
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(SiteRadii.md),
                ),
              ),
              child: AnyIcon(
                siteIcon: feature.icon,
                icon: feature.materialIcon,
                size: 20,
                color: tint,
              ),
            ),
            const SizedBox(height: SiteSpacing.md),
          ],
          Text(feature.title, style: styles.h4),
          const SizedBox(height: SiteSpacing.xs),
          Text(
            feature.description,
            style: styles.bodySmall.copyWith(height: 1.5),
          ),
        ],
      ),
    );

    if (tappable) {
      card = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(onTap: feature.onTap, child: card),
      );
    }
    return card;
  }
}

/// A responsive grid of [FeatureCard]s where every card in a row shares the
/// tallest card's height.
class FeatureGrid extends StatelessWidget {
  const FeatureGrid({
    super.key,
    required this.features,
    this.columns = const ResponsiveValue<int>(xs: 1, sm: 2, md: 3),
    this.spacing = SiteSpacing.md,
  });

  final List<Feature> features;
  final ResponsiveValue<int> columns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return ResponsiveGrid(
      columns: columns,
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final feature in features) FeatureCard(feature: feature),
      ],
    );
  }
}
