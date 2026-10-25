import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A single vivid, labelled box used as a placeholder child inside the live
/// layout previews, painted from the Pierre-derived [BrandPalette].
///
/// The examples use [DemoBox] instead of real content so the reader's attention
/// stays on the *constraints* (where the box lands and how big it is), not on
/// what is inside it. It adapts to however the constraint engine sizes it:
///
/// - On a `wrapContent` axis the engine hands it loose constraints, so the box
///   hugs its label.
/// - On a `fixed` / `matchConstraint` / `matchParent` axis the engine hands it
///   tight constraints, so the box fills that axis and centers its label.
class DemoBox extends StatelessWidget {
  const DemoBox(
    this.label, {
    super.key,
    this.color,
    this.outlined = false,
  });

  /// Short label drawn in the center of the box.
  final String label;

  /// Fill color. When null it is derived from [label] so sibling boxes labelled
  /// `A`, `B`, `C` (or `1`, `2`, `3`) come out as an ordered, branded set,
  /// without the example code having to spell out a color for each box.
  final Color? color;

  /// Draw as a tinted outline instead of a solid fill (used for "ghost"
  /// widgets such as an `invisible` child that still reserves its space).
  final bool outlined;

  /// Maps a label to a stable [BrandPalette] hue: A/a/1 -> first swatch,
  /// B/b/2 -> second, and so on, falling back to azure.
  static Color _autoColor(BrandPalette brand, String label) {
    if (label.isEmpty) return brand.azure;
    final c = label.codeUnitAt(0);
    final isLetter = (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
    final isDigit = c >= 48 && c <= 57;
    if (isLetter) return brand.swatch((c | 0x20) - 97);
    if (isDigit) return brand.swatch(c - 49);
    return brand.azure;
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final fill = color ?? _autoColor(brand, label);
    // Pick a label color that stays legible whether the hue is bright (dark
    // mode) or deep (light mode).
    final onFill = fill.computeLuminance() > 0.55
        ? const Color(0xFF07090C)
        : Colors.white;

    final labelWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 13,
          height: 1.15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: outlined ? fill : onFill,
        ),
      ),
    );

    final decoration = outlined
        ? BoxDecoration(
            color: fill.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: fill, width: 1.5),
          )
        // Flat fill, no shadow or glow: the box reads as a plain constrained
        // rectangle so the eye stays on where it lands, not on styling.
        : BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadii.sm),
          );

    // The box's own size is driven by the constraints the engine passes. A tight
    // axis (fixed / matchConstraint / matchParent) fills and centers the label;
    // a loose axis (wrapContent) hugs the label. An Align factor of 1 expresses
    // both: it shrink-wraps a loose axis, and a tight axis is forced to its
    // size by the constraints, with the label centered. No LayoutBuilder: the
    // examples sit in IntrinsicHeight rows, which ask for a dry layout.
    return DecoratedBox(
      decoration: decoration,
      child: Align(
        alignment: Alignment.center,
        widthFactor: 1,
        heightFactor: 1,
        child: labelWidget,
      ),
    );
  }
}
