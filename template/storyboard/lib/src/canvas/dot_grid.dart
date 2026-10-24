import 'package:flutter/material.dart';
import 'package:site_kit/site_kit.dart';

/// The canvas backdrop: a faint dot grid.
///
/// Painted as a child-sized [CustomPaint] inside the transformed subtree, so it
/// pans and zooms with the content instead of sliding under it.
class DotGrid extends StatelessWidget {
  const DotGrid({
    super.key,
    required this.child,
    this.spacing = 32,
    this.enabled = true,
  });

  final Widget child;
  final double spacing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return CustomPaint(
      painter: _DotGridPainter(
        color: context.colors.foreground.withValues(alpha: 0.10),
        spacing: spacing,
      ),
      child: child,
    );
  }
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter({required this.color, required this.spacing});

  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += spacing) {
      for (var y = 0.0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) =>
      old.color != color || old.spacing != spacing;
}
