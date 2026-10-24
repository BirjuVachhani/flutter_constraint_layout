# flutter_constraint_layout monorepo

A Flutter port of Android's ConstraintLayout, plus the pure-Dart engine it runs
on and the tooling around them. This directory is a workspace shell: it holds no
Dart code of its own, only the members below and a single shared lock file.

## Packages

| Path | Package | What it is |
| --- | --- | --- |
| [packages/flutter_constraint_layout](packages/flutter_constraint_layout) | `flutter_constraint_layout` | The Flutter widget layer: `ConstraintLayout`, `Constrained`, helpers, and the debug visualizer. Start here. |
| [packages/constraint_engine](packages/constraint_engine) | `constraint_engine` | Pure-Dart resolution engine, a line-faithful port of `androidx.constraintlayout.core`. No Flutter dependency. |
| [packages/flutter_constraint_layout_lints](packages/flutter_constraint_layout_lints) | `flutter_constraint_layout_lints` | Analyzer plugin catching constraint mistakes that otherwise surface at runtime. Deliberately not a workspace member: it resolves against the SDK's analyzer. |
| [website](website) | `flutter_constraint_layout_website` | The documentation site. |
| [template](template) | `site_kit` | Reusable theme, routing, and component kit extracted from the website, with an interactive storyboard in [template/storyboard](template/storyboard). |

`template/` is standalone rather than a workspace member, so it can be consumed
as a dependency from other repos without inheriting this one's resolution.

## Getting started

One resolve at the root covers every member:

```bash
flutter pub get
```

Then work inside a package:

```bash
cd packages/flutter_constraint_layout && flutter test
cd packages/constraint_engine  && dart test
cd website                     && flutter run -d chrome
```

`flutter analyze` from the root walks the whole tree; each package carries its
own `analysis_options.yaml`.

## Tests and coverage

The two suites are separate, but the Flutter suite also executes engine code, so
a line counts as covered if either suite reached it. Collect both, then merge:

```bash
(cd packages/flutter_constraint_layout && flutter test --coverage \
    --coverage-package=flutter_constraint_layout --coverage-package=constraint_engine)
(cd packages/constraint_engine && dart run coverage:test_with_coverage)
python3 tool/coverage_report.py --scope all
```

The `--coverage-package` flags matter: without them the Flutter run reports only
its own `lib/`, and the engine lines it exercises go uncounted.

`--scope lib` reports the widget layer alone, `--scope engine` the engine alone.
[tool/uncovered.py](tool/uncovered.py) prints the uncovered lines with their
source text.

Golden images live beside their tests under
`packages/flutter_constraint_layout/test/**/goldens/` and are generated on macOS, which
is why [CI](.github/workflows/test.yml) pins a macOS runner. Refresh them with
`flutter test --update-goldens` from inside that package.

## Docs

- [docs/DEBUG_VISUALIZATION.md](docs/DEBUG_VISUALIZATION.md): design and build
  log for the blueprint/debug overlay.
- [docs/LIVE_EDITABLE_EXAMPLES_RESEARCH.md](docs/LIVE_EDITABLE_EXAMPLES_RESEARCH.md):
  research into running editable examples in the browser.

## License

See [LICENSE](LICENSE).
