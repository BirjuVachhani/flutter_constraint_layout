import 'components.dart';
import 'foundations.dart';
import 'patterns.dart';
import 'specimen.dart';

export 'specimen.dart';

/// Every group on the canvas, left to right: foundations first, then the
/// components built on them, then whole pages.
final List<SpecimenGroup> catalog = [
  ...foundationGroups,
  ...componentGroups,
  ...patternGroups,
];

/// Every specimen, flattened in canvas order.
final List<Specimen> allSpecimens = [
  for (final group in catalog) ...group.specimens,
];

/// The specimen registered under [id], or null when there is none.
Specimen? specimenById(String id) {
  for (final specimen in allSpecimens) {
    if (specimen.id == id) return specimen;
  }
  return null;
}

/// The group [id] belongs to, or null.
SpecimenGroup? groupOf(String id) {
  for (final group in catalog) {
    if (group.specimens.any((s) => s.id == id)) return group;
  }
  return null;
}
