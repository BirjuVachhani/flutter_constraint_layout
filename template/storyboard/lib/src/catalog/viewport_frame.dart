import 'package:flutter/material.dart';
import 'package:site_kit/site_kit.dart';

/// A fixed-size window that lies to its subtree about the viewport.
///
/// It overrides [MediaQuery] size, so everything inside resolves breakpoints
/// against the frame rather than the browser window. That is what lets the
/// canvas show the same page at phone and desktop widths side by side, live,
/// without resizing anything.
class ViewportFrame extends StatelessWidget {
  const ViewportFrame({
    super.key,
    required this.width,
    required this.height,
    required this.child,
    this.label,
  });

  final double width;
  final double height;
  final Widget child;

  /// Caption above the frame. Defaults to `width × height · breakpoint`.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = Size(width, height);
    final breakpoint = Breakpoint.of(width);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label ??
                '${width.toInt()} × ${height.toInt()}  ·  ${breakpoint.name}'
                    '${breakpoint.isCompact ? ' (compact)' : ''}',
            style: context.text.caption,
          ),
        ),
        Container(
          width: width,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(SiteRadii.md),
            border: Border.all(color: colors.borderStrong),
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: size,
              // A simulated viewport has no notch and no keyboard.
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
              viewInsets: EdgeInsets.zero,
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}
