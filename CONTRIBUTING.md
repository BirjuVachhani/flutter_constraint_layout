# Contributing

This is the development guide for the flutter_constraint_layout repository. To
use the packages, start with the [README](README.md).

Questions, bug reports, and feature requests go to the
[issue tracker](https://github.com/BirjuVachhani/constraint_layout/issues).
Pull requests target `main`; run the checks below for the packages you touched
before opening one, since CI runs the same ones.

## Repository layout

| Path | Package | Resolution | Distribution |
| --- | --- | --- | --- |
| [packages/constraint_engine](packages/constraint_engine) | `constraint_engine` | Workspace member | pub.dev |
| [packages/flutter_constraint_layout](packages/flutter_constraint_layout) | `flutter_constraint_layout` | Workspace member | pub.dev |
| [website](website) | `flutter_constraint_layout_website` | Workspace member | Deployed to GitHub Pages; not published |
| [packages/flutter_constraint_layout_lints](packages/flutter_constraint_layout_lints) | `flutter_constraint_layout_lints` | Standalone | pub.dev |
| [template](template) | `site_kit` | Standalone | Used by path or git; not published |
| [template/storyboard](template/storyboard) | `storyboard` | Standalone | Not published |

Also at the root: [docs/](docs) holds design notes, [tool/](tool) the coverage
scripts, and [.github/workflows/](.github/workflows) the CI and website
deploy workflows.

The root [pubspec.yaml](pubspec.yaml) is a pub workspace shell
(`flutter_constraint_layout_workspace`, `publish_to: none`) with no Dart code of
its own. Its `workspace:` list names the three members, which resolve together
against a single `pubspec.lock` at the root. Two kinds of package stay out of
the workspace on purpose:

- **The lints package** is an analyzer plugin. The analysis server builds and
  runs it from its own path, in its own isolate, against an `analyzer` version
  tied to the Dart SDK. As a member it would pull `analyzer` into every
  member's resolution and fight the Flutter packages' constraints.
- **site_kit** (`template/`) and its storyboard are standalone so other
  repositories can depend on site_kit by path or git without inheriting this
  workspace's resolution.

The root [analysis_options.yaml](analysis_options.yaml) enables the
repository's own lints plugin by path. Analyzer plugins can only be configured
in the root options file, so `packages/flutter_constraint_layout` and `website`
include it rather than redeclaring the plugin. Restart the analysis server
after editing its `plugins` section.

## Getting started

Use the latest Flutter stable release, which is what CI runs. The packages need
Dart 3.12 and Flutter 3.44 or later.

```sh
git clone https://github.com/BirjuVachhani/constraint_layout.git
cd constraint_layout
flutter pub get
```

That one resolve at the root covers the engine, the widget package, and the
website. The standalone packages resolve on their own:

```sh
(cd packages/flutter_constraint_layout_lints && dart pub get)
(cd template && flutter pub get)
(cd template/storyboard && flutter pub get)
```

## Analyzing

Analyze the workspace members from the root, by path, exactly as CI does:

```sh
dart analyze --fatal-infos packages/constraint_engine packages/flutter_constraint_layout website
```

Use `dart analyze` rather than `flutter analyze`: only `dart analyze` runs the
analyzer plugins enabled in the root `analysis_options.yaml`, so it is the one
that enforces this repo's own `flutter_constraint_layout_lints` rules
(`flutter analyze` reports no plugin diagnostics, as of Flutter 3.47).
`--fatal-infos` keeps infos fatal, as `flutter analyze` does by default.

An unscoped analyze at the root also walks into
`packages/flutter_constraint_layout_lints`, `template/`, and
`template/storyboard/`, which the root resolve does not cover. Unless each of
them has been resolved separately, every import in them is reported as missing.
Analyze them from their own directories instead:

```sh
(cd packages/flutter_constraint_layout_lints && dart analyze)
(cd template && flutter analyze)
(cd template/storyboard && flutter analyze)
```

Each package carries its own `analysis_options.yaml`. The one in `template/`
excludes `storyboard/`, which is analyzed on its own.

## Running the tests

```sh
(cd packages/constraint_engine && dart test)
(cd packages/flutter_constraint_layout && flutter test)   # includes the goldens
(cd website && flutter test)
(cd packages/flutter_constraint_layout_lints && dart test)
(cd template && flutter test)
(cd template/storyboard && flutter test)
```

The engine is pure Dart, so it runs under `dart test`. Its suite includes the
ported upstream core tests; [UPSTREAM.md](packages/constraint_engine/UPSTREAM.md)
maps them, and
[PORTING_GUIDE.md](packages/constraint_engine/test/PORTING_GUIDE.md) describes
how to port more. The lints tests use `analyzer_testing` against a stub of
`flutter_constraint_layout`, so they need neither Flutter nor the real package.

A change to the engine can move the widget package's layouts and the website's
examples, so run those suites too after touching
`packages/constraint_engine`.

### Goldens

The golden images live beside their tests under
`packages/flutter_constraint_layout/test/**/goldens/` and are generated on
macOS, which is why the workspace job in CI runs on a macOS runner. Refresh them
from inside that package, then review the changed images before committing:

```sh
cd packages/flutter_constraint_layout
flutter test --update-goldens
```

CI tracks the latest Flutter stable release rather than a pinned version, so
regenerate the goldens if a Flutter upgrade changes text or raster output. When
a comparison fails, `flutter test` writes the diff images to a `failures/`
directory next to the goldens; those directories are git-ignored.

### Coverage

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
source text, for files whose path contains a given substring:

```sh
python3 tool/uncovered.py lib/src/constraint_layout.dart
```

### Benchmarks

Neither benchmark runs in CI.

```sh
# The resolver alone, compiled AOT (closest to a Flutter release build) or JIT.
(cd packages/constraint_engine && dart compile exe benchmark/resolver_benchmark.dart -o /tmp/bench) && /tmp/bench AOT
(cd packages/constraint_engine && dart run benchmark/resolver_benchmark.dart)

# The widget layer. flutter test runs in debug mode, so read these as ratios.
(cd packages/flutter_constraint_layout && flutter test benchmark/flutter_layout_benchmark.dart)
```

## CI

[.github/workflows/test.yml](.github/workflows/test.yml) runs on every push to
`main`, on every pull request, and on demand, and a newer run for the same
branch or pull request cancels the older one. It has one job per independently
resolved unit:

| Job | Runner | Steps |
| --- | --- | --- |
| `workspace` | `macos-latest`, for the goldens | `flutter pub get` at the root; `dart analyze --fatal-infos packages/constraint_engine packages/flutter_constraint_layout website`, which also enforces the lint plugin; `dart test` in the engine; `flutter test` in `flutter_constraint_layout` (with the goldens) and in `website` |
| `lints` | `ubuntu-latest` | `dart pub get`, `dart analyze`, and `dart test` in `packages/flutter_constraint_layout_lints` |
| `site_kit` | `ubuntu-latest` | `flutter pub get`, `flutter analyze`, and `flutter test` in `template`, then the same in `template/storyboard` |

Every job installs the latest Flutter stable release with no version pin, so a
Flutter release that breaks a package shows up in CI first.

## Website

The documentation site in [website/](website) renders the two packages live
from this workspace, so every docs example is a real `ConstraintLayout`.

```sh
cd website
flutter run -d chrome        # develop
flutter build web --wasm     # release build, written to website/build/web
```

In IntelliJ IDEA or Android Studio, the shared `Website` run configuration in
`.run/` runs the same app.

The `--wasm` build also emits a JavaScript fallback for browsers without
WasmGC. The site highlights code in a Web Worker,
`website/web/shiki_tokenize_worker.js`; after upgrading `shiki_flutter`,
refresh it from `website/` with `dart run shiki_flutter:install --default`.

[.github/workflows/deploy-website.yml](.github/workflows/deploy-website.yml)
deploys the site to GitHub Pages at
[constraints.birju.dev](https://constraints.birju.dev). It runs on pushes to
`main` that touch `website/`, `packages/constraint_engine/`,
`packages/flutter_constraint_layout/`, the root `pubspec.yaml`, or the workflow
itself, and can be started by hand. It resolves the workspace at the root, runs
`flutter build web --wasm --base-href "/"` in `website/`, and publishes
`website/build/web`. Pages must be enabled with "GitHub Actions" as its source.

With an Actions deploy, the custom domain comes from the repository's Pages
settings (Settings > Pages > Custom domain), and the `CNAME` file in the build
output is ignored. [website/web/CNAME](website/web/CNAME) is still kept in sync
with that setting so the build output describes where it is served.

## Releasing

The three packages under `packages/` are released to pub.dev, each starting
at 1.0.0. `website`, `site_kit`, and the storyboard are `publish_to: none`.

1. Bump `version` in the package's `pubspec.yaml` and add a matching entry at
   the top of its `CHANGELOG.md`. If `flutter_constraint_layout` needs a new
   engine release, raise its `constraint_engine` constraint as well.
2. Run `dart pub publish --dry-run` in each package being released, fix what it
   reports, and check the file list it prints. Each published package has a
   `.pubignore`, which replaces the directory's `.gitignore` for publishing.
3. Publish with `dart pub publish` in this order: `constraint_engine` first,
   because `flutter_constraint_layout` depends on it, then
   `flutter_constraint_layout`, then `flutter_constraint_layout_lints`.

## Updating the upstream port

`constraint_engine` is a port of `androidx.constraintlayout.core` pinned to one
upstream commit. [UPSTREAM.md](packages/constraint_engine/UPSTREAM.md) records
that commit, how the port compares with the released core versions (including
the known `GridCore` gap), the ported scope, every intentional divergence, and
which upstream tests are ported. To move the port forward:

1. Diff the upstream sources between the pinned commit and the new revision,
   and apply the changes to the matching files under
   `packages/constraint_engine/lib/src/`. The pinned commit is the last one in
   the GitHub repository; newer core sources come from the AOSP androidx
   repository or from the `constraintlayout-core` source jars on Google Maven,
   as UPSTREAM.md describes. Each file names the upstream class it was ported
   from.
2. Port new or changed upstream tests following
   [PORTING_GUIDE.md](packages/constraint_engine/test/PORTING_GUIDE.md).
3. Record the new commit, and any new divergence, in UPSTREAM.md.
4. Run the engine suite (`dart test`), then the widget package and website
   suites, which exercise the engine through real layouts.

## Docs

- Package READMEs are rendered on pub.dev, so they link to repository files
  with absolute URLs
  (`https://github.com/BirjuVachhani/constraint_layout/blob/main/<path>`).
  Docs that live only in the repository, such as this file, the root README,
  and `docs/`, use relative links.
- The docs page on the website,
  [website/lib/src/pages/docs_page.dart](website/lib/src/pages/docs_page.dart)
  with its examples in
  [website/lib/src/data/examples.dart](website/lib/src/data/examples.dart), is
  the source of truth for the documentation.
  [website/web/docs.md](website/web/docs.md) mirrors it as one Markdown file
  (served at `/docs.md`), so update both together.
  [website/web/llms.txt](website/web/llms.txt) summarizes the docs for AI
  assistants.
- [docs/](docs) holds design notes:
  [DEBUG_VISUALIZATION.md](docs/DEBUG_VISUALIZATION.md), the spec and build log
  of the debug overlay, and
  [LIVE_EDITABLE_EXAMPLES_RESEARCH.md](docs/LIVE_EDITABLE_EXAMPLES_RESEARCH.md),
  research into letting visitors edit the website's examples.

## House style

- Never use em-dashes or en-dashes as punctuation in prose, which covers docs,
  READMEs, changelogs, and code comments. Use a colon, a comma, parentheses, or
  a separate sentence.
- Keep the tone plain and technical: no hype and no emojis in the docs.
- Commit messages start with a gitmoji shortcode followed by a lowercase
  summary in the imperative, for example
  `:bug: keep the model dirty until it is fully built`.

## License headers

The repository is licensed under BSD 3-Clause (see [LICENSE](LICENSE)), and the
three packages and site_kit each carry their own copy. Files written for this
project carry no license header.

Files ported or adapted from Apache-2.0 sources keep their upstream copyright
line, add our own, and carry an SPDX tag naming both licenses. Every file under
`packages/constraint_engine/lib/src/` is a port of androidx.constraintlayout
core, as are the engine tests ported from upstream's core test suite (and their
support classes under `test/support/`). Each starts like this, with the year
taken from the upstream file:

```dart
// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.LinearSystem (upstream pinned in
// UPSTREAM.md).
```

In `packages/flutter_constraint_layout`, `lib/src/debug/debug_painter.dart` and
`lib/src/debug/debug_palette.dart` adapt the rendering of Android Studio's
layout editor and start with
`// Portions copyright (C) The Android Open Source Project`, our copyright
line, and the same SPDX tag. The LICENSE files of both packages append the
Apache-2.0 text as a third-party notice. Any new file, library or test, that
is ported or adapted from Apache-2.0 sources needs the same kind of header.
