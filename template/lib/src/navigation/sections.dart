import 'package:flutter/material.dart';

import '../theme/context_extensions.dart';
import '../theme/tokens.dart';

/// Turns a heading into the slug used as its URL fragment.
///
/// Lowercases, drops everything that is not a letter or a digit, and joins the
/// remaining words with single hyphens, so `Anchors & links` becomes
/// `anchors-links` and `A profile card` becomes `a-profile-card`.
///
/// Deriving the slug from the title, rather than hand-writing it beside the
/// title, is what stops a heading and its deep link from drifting apart when
/// the heading is reworded.
///
/// It is idempotent, so it doubles as the normalizer for an incoming
/// reference: `#Quick Start`, `quick-start`, and `Quick start` all resolve to
/// the same slug.
String slugify(String title) => title
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// One in-page section: its content [id] and display [title].
@immutable
class PageSection {
  const PageSection(this.id, this.title);

  /// Key your `sectionBuilder` switches on to build this section's body.
  /// Internal to the page; [slug] is what appears in a URL.
  final String id;

  final String title;

  /// The URL fragment that deep-links to this section, derived from [title].
  ///
  /// `PageSection('routing', 'Routing and deep links')` is linked as
  /// `/docs#routing-and-deep-links`.
  String get slug => slugify(title);
}

/// A named group of sections, rendered as one labeled block in a rail or menu.
@immutable
class PageSectionGroup {
  const PageSectionGroup(this.title, this.sections);

  final String title;
  final List<PageSection> sections;
}

/// Flattens [groups] into reading order. Anchors, scroll-spy, and rail tiles
/// are all index-based against this list.
List<PageSection> flattenSections(List<PageSectionGroup> groups) => [
  for (final group in groups) ...group.sections,
];

/// Index into [sections] of the one [reference] points at, or null when
/// nothing matches.
///
/// [reference] is normalized first, so a raw fragment (`#routing`), a slug
/// (`routing`), or a title (`Routing`) all work. Derived slugs are checked
/// first and content ids second, which keeps hand-written links to an id
/// working after the heading it belongs to has been reworded.
int? sectionIndexForSlug(List<PageSection> sections, String reference) {
  final needle = slugify(reference);
  if (needle.isEmpty) return null;
  for (var i = 0; i < sections.length; i++) {
    if (sections[i].slug == needle) return i;
  }
  for (var i = 0; i < sections.length; i++) {
    if (slugify(sections[i].id) == needle) return i;
  }
  return null;
}

/// Implemented by a page that has an in-page section list, so the shared nav
/// sheet can list those sections and scroll to them no matter which control
/// opened it.
abstract interface class SectionNavigator {
  /// The grouped sections this page shows.
  List<PageSectionGroup> get sectionGroups;

  /// Index (into the flattened list) of the section currently in view.
  int get activeSection;

  /// Scrolls the page to the section at [index].
  void scrollToSection(int index);
}

/// Bridges the on-screen [SectionNavigator] up to the app-wide nav sheet.
///
/// A page registers itself while mounted; pages that have no sections leave it
/// null, and the sheet then shows site links only.
class NavSheetController {
  SectionNavigator? sections;
}

/// Exposes the single [NavSheetController] to the whole app. Install it above
/// the router so the shell's nav bar and each page reach the same one.
class NavSheetScope extends InheritedWidget {
  const NavSheetScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final NavSheetController controller;

  static NavSheetController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavSheetScope>()?.controller;

  static NavSheetController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(
      controller != null,
      'No NavSheetScope found. SiteApp installs one above the router; add it '
      'yourself if you build the router by hand.',
    );
    return controller!;
  }

  @override
  bool updateShouldNotify(NavSheetScope oldWidget) =>
      controller != oldWidget.controller;
}

/// A small uppercase category label above a group of section tiles. Shared by
/// the docs rail and the nav sheet.
class SectionGroupLabel extends StatelessWidget {
  const SectionGroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: Text(text.toUpperCase(), style: context.text.overline),
    );
  }
}

/// A single section entry in a rail or menu.
///
/// Selection changes color and adds a subtle pill, never weight, so the list
/// does not reflow as the scroll-spy moves.
class SectionTile extends StatefulWidget {
  const SectionTile({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<SectionTile> createState() => _SectionTileState();
}

class _SectionTileState extends State<SectionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = widget.active;
    final color = active || _hovered
        ? colors.foreground
        : colors.mutedForeground;

    final tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? colors.surfaceInset
                : (_hovered
                      ? colors.foreground.withValues(alpha: 0.05)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(SiteRadii.sm),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: color,
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
    return SelectionContainer.disabled(child: tile);
  }
}

/// The grouped section list: a [SectionGroupLabel] per group over its
/// [SectionTile]s, with a running index mapping tiles back to the flattened
/// list.
///
/// Shared by the docs rail and the nav sheet so the two never drift.
class SectionList extends StatelessWidget {
  const SectionList({
    super.key,
    required this.groups,
    required this.activeIndex,
    required this.onSelect,
    this.tileKeys,
    this.groupSpacing = 22,
  });

  final List<PageSectionGroup> groups;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  /// Optional keys, one per flattened section, so a caller can measure or
  /// reveal an individual tile.
  final List<GlobalKey>? tileKeys;

  final double groupSpacing;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var index = 0;
    for (var g = 0; g < groups.length; g++) {
      children.add(
        Padding(
          padding: EdgeInsets.only(
            top: g == 0 ? 0 : groupSpacing,
            bottom: 8,
            left: 12,
          ),
          child: SectionGroupLabel(groups[g].title),
        ),
      );
      for (final section in groups[g].sections) {
        final i = index++;
        children.add(
          SectionTile(
            key: tileKeys != null && i < tileKeys!.length ? tileKeys![i] : null,
            label: section.title,
            active: i == activeIndex,
            onTap: () => onSelect(i),
          ),
        );
      }
    }
    return Column(
      // Stretch so a selected pill spans the rail width instead of
      // shrink-wrapping its label.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
