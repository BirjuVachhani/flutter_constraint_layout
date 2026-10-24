import 'package:flutter/material.dart';
import 'package:site_kit/site_kit.dart';

import '../catalog/catalog.dart';

/// One specimen on its own page, at `/frame/:id`.
///
/// This is the deep-link half of the storyboard: every frame has a real URL you
/// can share, reload, or bookmark, which is the same routing the template gives
/// a site.
class SoloPage extends StatelessWidget {
  const SoloPage({super.key, required this.specimenId});

  final String specimenId;

  @override
  Widget build(BuildContext context) {
    final specimen = specimenById(specimenId);
    final group = groupOf(specimenId);
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          _SoloBar(
            title: specimen?.title ?? 'Unknown frame',
            group: group?.title,
            id: specimenId,
          ),
          Expanded(
            child: specimen == null
                ? _NotFound(id: specimenId)
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          // Wide specimens keep their intended width; narrow
                          // ones are not stretched across a big monitor.
                          maxWidth: specimen.width.clamp(360, 1240),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (specimen.description != null) ...[
                              Text(
                                specimen.description!,
                                style: context.text.bodySmall,
                              ),
                              const SizedBox(height: SiteSpacing.lg),
                            ],
                            Container(
                              padding: EdgeInsets.all(
                                specimen.padded ? 24 : 0,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(
                                  SiteRadii.lg,
                                ),
                                border: Border.all(color: colors.border),
                              ),
                              child: Builder(builder: specimen.builder),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SoloBar extends StatelessWidget {
  const _SoloBar({required this.title, required this.group, required this.id});

  final String title;
  final String? group;
  final String id;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: SiteLayout.navHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          SiteIconButton(
            materialIcon: Icons.arrow_back_rounded,
            tooltip: 'Back to the canvas',
            onPressed: () => context.go('/?frame=$id'),
          ),
          const SizedBox(width: 8),
          if (group != null) ...[
            Text(group!, style: context.text.caption),
            const SizedBox(width: 6),
            RotatedBox(
              quarterTurns: 3,
              child: SiteIcon(
                SiteIcons.chevronDown,
                size: 12,
                color: colors.mutedForeground,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.label,
            ),
          ),
          const Spacer(),
          const ThemeModeSegmented(),
        ],
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('No frame with the id "$id".', style: context.text.h3),
          const SizedBox(height: SiteSpacing.sm),
          Text(
            'It may have been renamed. The canvas lists every current id.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: SiteSpacing.lg),
          SiteButton(
            label: 'Back to the canvas',
            size: SiteButtonSize.sm,
            onPressed: () => context.go('/'),
          ),
        ],
      ),
    );
  }
}
