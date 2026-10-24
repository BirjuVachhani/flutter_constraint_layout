import 'package:flutter/material.dart';
import 'package:site_kit/site_kit.dart';

/// Small building blocks shared by the specimens: labeled rows, stacks, and
/// swatches. Deliberately plain, so nothing here competes with the component
/// being shown.

/// A vertical stack with a consistent gap between children.
class SpecStack extends StatelessWidget {
  const SpecStack({super.key, required this.children, this.gap = 14});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, child) in children.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : gap),
            child: child,
          ),
      ],
    );
  }
}

/// A labeled row: a muted caption on the left, the sample on the right.
class SpecRow extends StatelessWidget {
  const SpecRow({
    super.key,
    required this.label,
    required this.child,
    this.labelWidth = 104,
    this.alignment = CrossAxisAlignment.center,
  });

  final String label;
  final Widget child;
  final double labelWidth;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: alignment,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(label, style: _monoLabel(context)),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// A caption above a cluster of samples.
class SpecLabel extends StatelessWidget {
  const SpecLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text.toUpperCase(), style: context.text.overline),
    );
  }
}

/// A wrapped row of samples with even gaps.
class SpecWrap extends StatelessWidget {
  const SpecWrap({super.key, required this.children, this.gap = 10});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

/// One color chip: the color, its token name, and its hex value.
class Swatch extends StatelessWidget {
  const Swatch({
    super.key,
    required this.name,
    required this.color,
    this.width = double.infinity,
  });

  final String name;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: width,
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(SiteRadii.xs),
              border: Border.all(color: colors.border),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.label.copyWith(fontSize: 13),
                ),
                Text(hexOf(color), style: _monoLabel(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A dashed measuring block, for showing a spacing or radius value.
class MeasureBlock extends StatelessWidget {
  const MeasureBlock({
    super.key,
    required this.size,
    this.height = 22,
    this.radius,
  });

  final double size;
  final double height;

  /// When set, draws a rounded box of this radius instead of a bar.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    if (radius != null) {
      return Container(
        width: 56,
        height: 40,
        decoration: BoxDecoration(
          color: brand.azure.withValues(alpha: 0.14),
          border: Border.all(color: brand.azure.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(radius!),
        ),
      );
    }
    return Container(
      width: size,
      height: height,
      decoration: BoxDecoration(
        color: brand.azure.withValues(alpha: 0.18),
        border: Border.all(color: brand.azure.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// `#RRGGBB`, or `#RRGGBBAA` when the color is translucent.
String hexOf(Color color) {
  String two(double channel) =>
      (channel * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final rgb = '${two(color.r)}${two(color.g)}${two(color.b)}'.toUpperCase();
  if (color.a >= 1) return '#$rgb';
  return '#$rgb${two(color.a).toUpperCase()}';
}

TextStyle _monoLabel(BuildContext context) => TextStyle(
  fontFamily: SiteFonts.mono,
  fontSize: 11.5,
  height: 1.4,
  color: context.colors.mutedForeground,
);
