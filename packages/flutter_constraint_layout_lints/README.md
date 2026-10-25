# flutter_constraint_layout_lints

An analyzer plugin with lint rules for
[`flutter_constraint_layout`](https://pub.dev/packages/flutter_constraint_layout).
The rules catch constraint mistakes that would otherwise only show up when the
layout runs: two children sharing an id, or a link at an id that nothing in the
layout defines.

| Rule | Severity | Catches |
| --- | --- | --- |
| [`duplicate_constraint_id`](#duplicate_constraint_id) | warning | A child of a `ConstraintLayout` (a `Constrained`, `Guideline`, `Barrier`, `ConstraintFlow`, `ConstraintGrid`, or `ConstraintGroup`) reuses an id already taken by an earlier child of the same layout. |
| [`undefined_constraint_id`](#undefined_constraint_id) | warning | A link, or a helper's `referenced` entry, names an id that no child of the same `ConstraintLayout` defines. |

## Getting started

Analyzer plugins are not added to `pubspec.yaml`. Enable this one with a
top-level `plugins` section in the `analysis_options.yaml` at the root of your
package (or of your pub workspace):

```yaml
plugins:
  flutter_constraint_layout_lints: ^1.0.0
```

Then restart the Dart analysis server (in VS Code, run
**Dart: Restart Analysis Server**). The server fetches and builds the plugin
itself, and both rules are on as soon as it loads. A layout like this one now
reports both warnings in the editor:

```dart
ConstraintLayout(
  children: [
    Constrained(id: #title, top: .topOf(parent), child: Text('Title')),
    Constrained(id: #title, top: .bottomOf(#titel), child: Text('Body')),
    //              ^^^^^^ duplicate_constraint_id
    //                                     ^^^^^^ undefined_constraint_id
  ],
)
```

`dart analyze` reports the same warnings, so it can enforce them in CI;
`flutter analyze` does not (see
[Requirements and limitations](#requirements-and-limitations)).

### Using a local copy

To work against a checkout of the plugin instead of the published package, give
it a `path`. A relative path resolves against the directory of the options file:

```yaml
plugins:
  flutter_constraint_layout_lints:
    path: ../path/to/flutter_constraint_layout_lints
```

### Pub workspaces

The `plugins` section only takes effect from the root options file of a
workspace (or of a standalone package): declaring it in a member package's own
`analysis_options.yaml` is reported as `plugins_in_inner_options`. A member with
no options file of its own uses the root file and gets the rules. A member that
has its own options file does not pick up the root `plugins` section, since the
analyzer resolves options from the closest file, so have that file include the
root one:

```yaml
# packages/app/analysis_options.yaml
include: ../../analysis_options.yaml
```

An included options file carries the `plugins` section through, so the rules
then apply to that package with no warning.

## Configuring

Both rules are registered as *warning* rules, so they are on by default. To turn
one off, list it under `diagnostics`, using the map form of the plugin entry:

```yaml
plugins:
  flutter_constraint_layout_lints:
    version: ^1.0.0
    diagnostics:
      duplicate_constraint_id: false
```

Suppress a single site the usual way, prefixed with the plugin name:

```dart
// ignore: flutter_constraint_layout_lints/duplicate_constraint_id
```

## Rules

### duplicate_constraint_id

Ids are the layout's addressing scheme: the engine keys every child by its id,
so a duplicate shadows the earlier child, and any link pointing at that id
resolves to only one of them. Nothing checks this when the layout runs, so the
mistake shows up only as a widget in the wrong place.

```dart
ConstraintLayout(
  children: [
    Constrained(id: #header, top: .topOf(parent), child: Text('a')),
    Constrained(id: #header, top: .topOf(parent), child: Text('b')),
    //              ^^^^^^^ warning: the id 'header' is already used
  ],
)
```

The rule reads the `children` list of each `ConstraintLayout` and compares the
`id` arguments of its direct elements, including the id of a `ConstraintGroup`:
a group takes no part in the layout, but its id belongs to the same set. It
understands symbol literals (`#header`) and references to constants
(`const headerId = #header;`), including inside a spread of an inline list. Ids
in the two branches of a collection `if` are treated as alternatives, not
duplicates.

Because this is static analysis, it only sees what the source spells out. It
cannot flag ids built at runtime (`Symbol(name)`), children produced by a `for`
element or returned from a helper method, or a spread of a list defined
elsewhere.

### undefined_constraint_id

Ids are scoped to one layout, and a link at an id nothing defines cannot be
resolved. A debug build throws a `FlutterError` naming the unknown id when the
layout runs; profile and release builds drop the link, so the edge it was meant
to anchor is left unconstrained and the child is placed as if the link were not
there. The usual causes are a typo and an id that was renamed on its child but
not at its use sites.

```dart
ConstraintLayout(
  children: [
    Constrained(id: #title, top: .topOf(parent), child: Text('Title')),
    Constrained(id: #body, top: .bottomOf(#titel), child: Text('Body')),
    //                                    ^^^^^^ warning: no child defines 'titel'
  ],
)
```

Checked for every link parameter (`top`, `bottom`, `baseline`, `left`, `right`,
`start`, `end`, `circle`) and for the `referenced` list of `Barrier`,
`ConstraintFlow`, `ConstraintGrid`, and `ConstraintGroup`. The reserved `parent`
target is always fine, and ids defined by a `Guideline`, a `Barrier`, or a child
sitting under a builder-style wrapper all count as defined.

The id of a `ConstraintGroup` counts as defined too, so a link at it, or a
helper's `referenced` entry naming it, is not reported. A group has no position
or size, so the layout itself reports either one when it runs: a debug build
throws a `FlutterError` that names the group.

Unlike a duplicate id, this one needs the *complete* set of a layout's ids before
it can call anything missing. Whenever a child could contribute an id that is not
visible in the source, the whole layout is skipped silently rather than guessed
at. That happens when:

- the `children` list is not written inline (built by a helper, held in a
  variable),
- a list element is a `for` element, or a spread of anything but an inline list,
- any widget inside the layout arrives through a variable, a method call, or
  another expression the walk cannot look inside,
- an id is built at runtime, as in `Symbol(name)`.

## Requirements and limitations

- Dart 3.12 or later (Flutter 3.44 or later), the lower bound of this package's
  SDK constraint. Analyzer plugins themselves arrived in Dart 3.10.
- The analysis server resolves the plugin's dependencies itself, and each SDK
  bounds the `analysis_server_plugin` version it will load. When a new SDK needs
  an `analysis_server_plugin` or `analyzer` release outside this package's
  constraints, the plugin does not load on that SDK until this package is
  updated.
- **The rules run in the IDE and in `dart analyze`, but not in
  `flutter analyze`.** Verified on Dart 3.13.7 / Flutter 3.47.8 with the plugin
  enabled: the analysis server the IDE talks to and `dart analyze` both report
  `duplicate_constraint_id` and `undefined_constraint_id` (and `dart analyze`,
  which treats warnings as fatal by default, exits non-zero), while
  `flutter analyze` finishes with no issues. Use `dart analyze` to enforce the
  rules in CI. Its first run takes longer while the plugin is compiled.

## Development

```sh
dart pub get
dart test
```

Tests use `analyzer_testing`'s `AnalysisRuleTest` harness against a stub of the
`flutter_constraint_layout` package, so they need neither Flutter nor the real
package. This package is deliberately not a member of the repository's pub
workspace: it resolves against an analyzer version tied to the SDK, which would
conflict with the Flutter-side resolution of the other packages.
