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

/// Metadata for one docs section: its content [id] and display [title].
class DocsSection {
  const DocsSection(this.id, this.title);

  /// Key the reading column switches on to build this section's body. Internal
  /// to the page; [slug] is what appears in a URL.
  final String id;

  final String title;

  /// The URL fragment that deep-links to this section, derived from [title].
  String get slug => slugify(title);
}

/// A named group of sections, rendered as one labeled block in the nav.
class DocsSectionGroup {
  const DocsSectionGroup(this.title, this.sections);

  final String title;
  final List<DocsSection> sections;
}

/// The docs, grouped and ordered top-to-bottom: what ConstraintLayout is, the
/// positioning primitives, then chains, helpers, virtual layouts, a worked
/// example, and finally how the engine resolves it all. The sidebar and nav
/// popup render these groups; the reading column and scroll-spy walk the
/// flattened [docsSections] in this order.
const docsGroups = <DocsSectionGroup>[
  DocsSectionGroup('Getting started', [
    DocsSection('introduction', 'Introduction'),
    DocsSection('features', 'Features'),
    DocsSection('installation', 'Installation'),
    DocsSection('quick-start', 'Quick start'),
  ]),
  DocsSectionGroup('Positioning', [
    DocsSection('anchors', 'Anchors & links'),
    DocsSection('centering-bias', 'Centering & bias'),
    DocsSection('dimensions', 'Dimensions'),
    DocsSection('aspect-ratio', 'Aspect ratio'),
  ]),
  DocsSectionGroup('Chains & helpers', [
    DocsSection('chains', 'Chains'),
    DocsSection('guidelines', 'Guidelines'),
    DocsSection('barriers', 'Barriers'),
    DocsSection('circular', 'Circular positioning'),
    DocsSection('visibility', 'Visibility'),
  ]),
  DocsSectionGroup('Virtual layouts', [
    DocsSection('flow', 'Flow'),
    DocsSection('grid', 'Grid'),
  ]),
  DocsSectionGroup('Putting it together', [
    DocsSection('profile-card', 'A profile card'),
  ]),
  DocsSectionGroup('Under the hood', [
    DocsSection('engine', 'How the engine works'),
    DocsSection('android', 'Relation to Android'),
  ]),
];

/// The groups flattened into reading order, for the anchor keys, scroll-spy,
/// and the content column (all index-based).
final docsSections = <DocsSection>[
  for (final group in docsGroups) ...group.sections,
];

/// Index into [docsSections] of the section [reference] points at, or null
/// when nothing matches.
///
/// [reference] is normalized first, so a raw fragment (`#chains`), a slug
/// (`chains`), or a title (`Chains`) all work. Derived slugs are checked
/// first; the content [DocsSection.id] is checked second, which keeps older
/// `?section=engine` style links working now that the canonical fragment for
/// that section is `#how-the-engine-works`.
int? docsSectionIndexForSlug(String reference) {
  final needle = slugify(reference);
  if (needle.isEmpty) return null;
  for (var i = 0; i < docsSections.length; i++) {
    if (docsSections[i].slug == needle) return i;
  }
  for (var i = 0; i < docsSections.length; i++) {
    if (slugify(docsSections[i].id) == needle) return i;
  }
  return null;
}
