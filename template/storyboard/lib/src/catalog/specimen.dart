import 'package:flutter/widgets.dart';

/// What the canvas paints behind a specimen's demo.
enum SpecimenSurface {
  /// The raised card surface. The default: most components are meant to sit on
  /// one, and it separates the demo from the canvas.
  card,

  /// The page background, for components that define their own surface (nav
  /// bars, footers, heroes).
  page,

  /// Nothing at all, for demos that paint edge to edge.
  none,
}

/// One entry on the canvas: a named, deep-linkable demo of a token set,
/// a component, or a page pattern.
@immutable
class Specimen {
  const Specimen({
    required this.id,
    required this.title,
    required this.builder,
    this.description,
    this.width = 420,
    this.surface = SpecimenSurface.card,
    this.padded = true,
  });

  /// Slug used by the rail, the `?frame=` deep link, and `/frame/:id`.
  final String id;

  final String title;

  /// One line on what the specimen is showing or why it exists.
  final String? description;

  /// Builds the demo.
  final WidgetBuilder builder;

  /// Width of the frame on the canvas. Wide components (nav bars, page
  /// patterns) ask for more.
  final double width;

  final SpecimenSurface surface;

  /// Inset the demo from the frame's edges. Turn it off for anything that
  /// should run edge to edge.
  final bool padded;
}

/// A titled column of specimens on the canvas.
@immutable
class SpecimenGroup {
  const SpecimenGroup({
    required this.id,
    required this.title,
    required this.specimens,
    this.blurb,
  });

  final String id;
  final String title;

  /// A line under the group title in the rail and above the column.
  final String? blurb;

  final List<Specimen> specimens;
}
