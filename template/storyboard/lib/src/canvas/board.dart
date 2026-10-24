import 'package:flutter/material.dart';

import '../catalog/catalog.dart';
import 'dot_grid.dart';
import 'specimen_frame.dart';

/// The canvas content: one column per group, laid out left to right.
///
/// Column width is the widest frame in that group, so a nav bar or a page
/// pattern gets its own generous lane without stretching everything else.
class Board extends StatelessWidget {
  const Board({
    super.key,
    required this.groups,
    required this.frameKeys,
    required this.selectedId,
    required this.onSelect,
    this.showGrid = true,
    this.padding = 96,
    this.columnGap = 72,
    this.frameGap = 44,
  });

  final List<SpecimenGroup> groups;

  /// One key per specimen id, so the page can measure a frame and pan to it.
  final Map<String, GlobalKey> frameKeys;

  final String? selectedId;
  final ValueChanged<String> onSelect;

  final bool showGrid;
  final double padding;
  final double columnGap;
  final double frameGap;

  @override
  Widget build(BuildContext context) {
    return DotGrid(
      enabled: showGrid,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, group) in groups.indexed)
              Padding(
                padding: EdgeInsets.only(
                  right: index == groups.length - 1 ? 0 : columnGap,
                ),
                child: _Column(
                  group: group,
                  frameKeys: frameKeys,
                  selectedId: selectedId,
                  onSelect: onSelect,
                  frameGap: frameGap,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.group,
    required this.frameKeys,
    required this.selectedId,
    required this.onSelect,
    required this.frameGap,
  });

  final SpecimenGroup group;
  final Map<String, GlobalKey> frameKeys;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final double frameGap;

  @override
  Widget build(BuildContext context) {
    final width = group.specimens
        .map((s) => s.width)
        .reduce((a, b) => a > b ? a : b);

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GroupHeader(group: group),
          for (final specimen in group.specimens)
            Padding(
              padding: EdgeInsets.only(top: frameGap),
              child: SpecimenFrame(
                key: frameKeys[specimen.id],
                specimen: specimen,
                selected: specimen.id == selectedId,
                onTap: () => onSelect(specimen.id),
              ),
            ),
        ],
      ),
    );
  }
}
