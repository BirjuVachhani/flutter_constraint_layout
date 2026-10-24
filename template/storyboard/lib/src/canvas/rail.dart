import 'package:flutter/material.dart';
import 'package:site_kit/site_kit.dart';

import '../catalog/catalog.dart';

/// The left rail: a search box over the grouped list of frames.
///
/// The list itself is site_kit's own [SectionList], the same widget the docs
/// rail uses, so the storyboard's navigation is a specimen too.
class CanvasRail extends StatefulWidget {
  const CanvasRail({
    super.key,
    required this.selectedId,
    required this.onSelect,
    this.width = 268,
  });

  final String? selectedId;
  final ValueChanged<String> onSelect;
  final double width;

  @override
  State<CanvasRail> createState() => _CanvasRailState();
}

class _CanvasRailState extends State<CanvasRail> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The catalog narrowed to the query, matching on group title, frame title,
  /// and id, with empty groups dropped.
  List<SpecimenGroup> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return catalog;
    final result = <SpecimenGroup>[];
    for (final group in catalog) {
      final groupMatches = group.title.toLowerCase().contains(query);
      final specimens = groupMatches
          ? group.specimens
          : group.specimens
                .where(
                  (s) =>
                      s.title.toLowerCase().contains(query) ||
                      s.id.contains(query),
                )
                .toList();
      if (specimens.isNotEmpty) {
        result.add(
          SpecimenGroup(
            id: group.id,
            title: group.title,
            blurb: group.blurb,
            specimens: specimens,
          ),
        );
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final groups = _filtered;

    // Adapt the catalog to site_kit's section model, then map the flattened
    // index the list reports back to a specimen id.
    final sectionGroups = [
      for (final group in groups)
        PageSectionGroup(group.title, [
          for (final specimen in group.specimens)
            PageSection(specimen.id, specimen.title),
        ]),
    ];
    final ids = [
      for (final group in groups)
        for (final specimen in group.specimens) specimen.id,
    ];
    final activeIndex = widget.selectedId == null
        ? -1
        : ids.indexOf(widget.selectedId!);

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: _SearchField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? Center(
                    child: Text(
                      'No frames match "$_query".',
                      style: context.text.caption,
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 32),
                    child: SectionList(
                      groups: sectionGroups,
                      activeIndex: activeIndex,
                      onSelect: (index) => widget.onSelect(ids[index]),
                    ),
                  ),
          ),
          Divider(height: 1, color: colors.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              '${allSpecimens.length} frames  ·  ${catalog.length} groups',
              style: context.text.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: context.text.label.copyWith(fontWeight: FontWeight.w400),
      cursorColor: colors.foreground,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search frames',
        hintStyle: context.text.label.copyWith(
          color: colors.mutedForeground,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 17,
          color: colors.mutedForeground,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 34),
        filled: true,
        fillColor: colors.surfaceInset,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SiteRadii.sm),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SiteRadii.sm),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SiteRadii.sm),
          borderSide: BorderSide(color: colors.borderStrong),
        ),
      ),
    );
  }
}
