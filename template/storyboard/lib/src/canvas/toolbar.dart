import 'package:flutter/material.dart';
import 'package:site_kit/site_kit.dart';

/// The canvas toolbar: identity on the left, view controls on the right.
class CanvasToolbar extends StatelessWidget {
  const CanvasToolbar({
    super.key,
    required this.scale,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.onReset,
    required this.showGrid,
    required this.onToggleGrid,
    this.height = 56,
  });

  /// Current canvas scale, shown as a percentage.
  final double scale;

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  final VoidCallback onReset;

  final bool showGrid;
  final VoidCallback onToggleGrid;

  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Controls drop out as the window narrows, widest-first: the wordmark and
    // the grid toggle below md, then "fit" below sm. Zoom and the theme switch
    // always survive, since the keyboard shortcuts are the only other way to
    // reach them.
    final breakpoint = context.breakpoint;
    final showWordmark = breakpoint >= Breakpoint.md;
    final showGridToggle = breakpoint >= Breakpoint.md;
    final showFit = breakpoint >= Breakpoint.sm;

    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: showWordmark ? 16 : 8),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          const LogoMark(size: 28),
          if (showWordmark) ...[
            const SizedBox(width: 10),
            // Flexible so a mid-width window ellipsizes the wordmark instead
            // of overflowing the row.
            Flexible(
              child: Text(
                'site_kit',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.wordmark,
              ),
            ),
            const SizedBox(width: 8),
            const SiteBadge('storyboard'),
          ],
          const Spacer(),
          SiteIconButton(
            materialIcon: Icons.remove_rounded,
            tooltip: 'Zoom out  (⌘ −)',
            onPressed: onZoomOut,
          ),
          Tooltip(
            message: 'Reset to 100%  (⌘ 0)',
            child: TextButton(
              onPressed: onReset,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(48, 32),
                foregroundColor: colors.mutedForeground,
              ),
              child: Text(
                '${(scale * 100).round()}%',
                style: TextStyle(
                  fontFamily: SiteFonts.mono,
                  fontSize: 12.5,
                  color: colors.mutedForeground,
                ),
              ),
            ),
          ),
          SiteIconButton(
            materialIcon: Icons.add_rounded,
            tooltip: 'Zoom in  (⌘ +)',
            onPressed: onZoomIn,
          ),
          if (showFit)
            SiteIconButton(
              materialIcon: Icons.fit_screen_outlined,
              tooltip: 'Fit everything  (⌘ 1)',
              onPressed: onFit,
            ),
          if (showGridToggle) ...[
            const SizedBox(width: 4),
            _Divider(color: colors.border),
            const SizedBox(width: 4),
            SiteIconButton(
              materialIcon: Icons.grid_4x4_rounded,
              tooltip: showGrid ? 'Hide grid' : 'Show grid',
              selected: showGrid,
              onPressed: onToggleGrid,
            ),
          ],
          const SizedBox(width: 10),
          const ThemeModeSegmented(),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 20, color: color);
  }
}
