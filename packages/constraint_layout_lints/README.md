# constraint_layout_lints

An analyzer plugin with lint rules for
[`constraint_layout`](https://pub.dev/packages/constraint_layout). The rules
catch constraint mistakes that would otherwise only show up as a misplaced
widget at runtime.

## Rules

| Rule | Severity | Description |
| --- | --- | --- |
| `duplicate_constraint_id` | warning | A `Constrained` (or `Guideline`, `Barrier`, `Flow`, `Grid`) child reuses an id already taken by an earlier child of the same `ConstraintLayout`. |
| `undefined_constraint_id` | warning | A link, or a helper's `referenced` entry, names an id that no child of the same `ConstraintLayout` defines. |

### duplicate_constraint_id

Ids are the layout's addressing scheme: the engine keys every child by its id,
so a duplicate shadows the earlier child, and any link pointing at that id
resolves to only one of them.

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
`id` arguments of its direct elements. It understands symbol literals (`#header`)
and references to constants (`const headerId = #header;`), including inside a
spread of an inline list. Ids in the two branches of a collection `if` are
treated as alternatives, not duplicates.

Because this is static analysis, it only sees what the source spells out. It
cannot flag ids built at runtime (`Symbol(name)`), children returned from a
helper method, or a spread of a list defined elsewhere.

### undefined_constraint_id

Ids are scoped to one layout, and a link at an id nothing defines cannot be
resolved: the edge it was meant to anchor is left unconstrained and the child
drifts to the layout's origin. The usual causes are a typo and an id that was
renamed on its child but not at its use sites.

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
`ConstraintFlow`, and `ConstraintGrid`. The reserved `parent` target is always
fine, and ids defined by a `Guideline`, a `Barrier`, or a child sitting under a
builder-style wrapper all count as defined.

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

## Enabling

Add a top-level `plugins` section to the `analysis_options.yaml` at the root of
your package or workspace (nested options files cannot configure plugins):

```yaml
plugins:
  constraint_layout_lints:
    path: ../path/to/constraint_layout_lints
```

Restart the Dart Analysis Server after editing that section.

The section only takes effect from the root options file of a workspace (or of a
standalone package): declaring it in a member package's own
`analysis_options.yaml` is reported as `plugins_in_inner_options`. But a member
package that has its own options file does not pick up the root `plugins` section
either, since the analyzer resolves options from the closest file. Have that file
include the root one:

```yaml
# website/analysis_options.yaml
include: ../analysis_options.yaml
```

An included options file does carry the `plugins` section through, so the rules
then apply to that package with no warning.

Every rule here is registered as a *warning* rule, so it is on as soon as the
plugin is. To turn one off:

```yaml
plugins:
  constraint_layout_lints:
    path: ../path/to/constraint_layout_lints
    diagnostics:
      duplicate_constraint_id: false
```

Suppress a single site the usual way, prefixed with the plugin name:

```dart
// ignore: constraint_layout_lints/duplicate_constraint_id
```

## Requirements and limitations

- Dart 3.10 (Flutter 3.38) or later, which is when analyzer plugins landed.
- The plugin's `analyzer` dependency has to stay in lockstep with the Dart SDK,
  and each SDK bounds the `analysis_server_plugin` version it will load, so this
  package needs a bump roughly once per Dart release.
- **The rules run in the IDE, not in `dart analyze` / `flutter analyze`.**
  Verified against Dart 3.12.2 / Flutter 3.44.6: the analysis server loads the
  plugin and reports the warnings, while the command-line analyzer never builds
  the plugin isolate. CI therefore will not enforce these rules yet.

## Development

```sh
dart pub get
dart test
```

Tests use `analyzer_testing`'s `AnalysisRuleTest` harness against a stub of the
`constraint_layout` package, so they need neither Flutter nor the real package.
This package is deliberately not a member of the repo's pub workspace: it
resolves against an analyzer version tied to the SDK, which would conflict with
the Flutter-side resolution of the other packages.
