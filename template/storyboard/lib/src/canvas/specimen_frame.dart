import 'package:flutter/material.dart';
import 'package:site_kit/site_kit.dart';

import '../catalog/catalog.dart';

/// One framed demo on the canvas: a title, a note on what it shows, the id as a
/// copyable chip, and the live component underneath.
class SpecimenFrame extends StatefulWidget {
  const SpecimenFrame({
    super.key,
    required this.specimen,
    this.selected = false,
    this.onTap,
  });

  final Specimen specimen;

  /// Highlight the frame, e.g. because the rail just focused it.
  final bool selected;

  final VoidCallback? onTap;

  @override
  State<SpecimenFrame> createState() => _SpecimenFrameState();
}

class _SpecimenFrameState extends State<SpecimenFrame> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final specimen = widget.specimen;
    final accent = context.brand.azure;

    final Widget demo = Builder(builder: specimen.builder);

    final body = switch (specimen.surface) {
      SpecimenSurface.card => Container(
        padding: EdgeInsets.all(specimen.padded ? 20 : 0),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(SiteRadii.lg),
          border: Border.all(color: colors.border),
        ),
        child: demo,
      ),
      SpecimenSurface.page => Container(
        padding: EdgeInsets.all(specimen.padded ? 20 : 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(SiteRadii.lg),
          border: Border.all(color: colors.borderStrong),
        ),
        child: demo,
      ),
      SpecimenSurface.none => demo,
    };

    return SizedBox(
      width: specimen.width,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      specimen.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.h4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _IdChip(id: specimen.id, active: widget.selected),
                  const Spacer(),
                  // Visible on hover only, so the canvas stays quiet at rest.
                  AnimatedOpacity(
                    duration: SiteMotion.fast,
                    opacity: _hovered || widget.selected ? 1 : 0,
                    child: SiteIconButton(
                      materialIcon: Icons.open_in_full_rounded,
                      tooltip: 'Open this frame on its own',
                      size: 28,
                      iconSize: 14,
                      onPressed: () => context.go('/frame/${specimen.id}'),
                    ),
                  ),
                ],
              ),
              if (specimen.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  specimen.description!,
                  style: context.text.caption.copyWith(height: 1.5),
                ),
              ],
              const SizedBox(height: 12),
              AnimatedContainer(
                duration: SiteMotion.fast,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(SiteRadii.lg + 4),
                  border: Border.all(
                    color: widget.selected
                        ? accent.withValues(alpha: 0.8)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                padding: const EdgeInsets.all(2),
                child: body,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The specimen's id, shown as a mono chip. Doubles as the `/frame/:id` slug.
class _IdChip extends StatelessWidget {
  const _IdChip({required this.id, required this.active});

  final String id;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? context.brand.azure.withValues(alpha: 0.14)
            : colors.surfaceInset,
        borderRadius: BorderRadius.circular(SiteRadii.xs),
      ),
      child: Text(
        id,
        style: TextStyle(
          fontFamily: SiteFonts.mono,
          fontSize: 10.5,
          color: active ? context.brand.azure : colors.mutedForeground,
        ),
      ),
    );
  }
}

/// The header above a column of frames.
class GroupHeader extends StatelessWidget {
  const GroupHeader({super.key, required this.group});

  final SpecimenGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(group.title.toUpperCase(), style: context.text.overline),
        if (group.blurb != null) ...[
          const SizedBox(height: 4),
          Text(group.blurb!, style: context.text.caption),
        ],
        const SizedBox(height: 10),
        Container(
          height: 2,
          width: 44,
          decoration: BoxDecoration(
            color: context.brand.azure,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}
