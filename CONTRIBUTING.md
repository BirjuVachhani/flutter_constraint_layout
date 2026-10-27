# Contributing

This is the development guide for the flutter_constraint_layout repository. To
use the packages, start with the [README](README.md).

Questions, bug reports, and feature requests go to the
[issue tracker](https://github.com/BirjuVachhani/flutter_constraint_layout/issues).
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
git clone https://github.com/BirjuVachhani/flutter_constraint_layout.git
cd flutter_constraint_layout
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
(cd packages/flutter_constraint_layout_lints && dart analyze --fatal-infos)
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

### Android parity

The engine and the widgets must give the frames Android's own code gives. Three
checked-in gates hold a sample of the parity corpora together with the frames
the parity oracle (Android's code, below) computes for them, and they run with
the suites above:

| Gate | What it checks |
| --- | --- |
| [packages/constraint_engine/test/parity/engine_corpus_test.dart](packages/constraint_engine/test/parity/engine_corpus_test.dart) | 2,000 layouts replayed through the engine at `OPTIMIZATION_STANDARD` (257) and at level 0, on the core path and through `ViewHost`, against Android's frames and its printed-exception status |
| [packages/constraint_engine/test/parity/graph_corpus_test.dart](packages/constraint_engine/test/parity/graph_corpus_test.dart) | 560 layouts at the dependency-graph levels (64, 321, 192, and 449) |
| [packages/flutter_constraint_layout/test/parity/android_parity_test.dart](packages/flutter_constraint_layout/test/parity/android_parity_test.dart) | 1,600 real `ConstraintLayout` widget trees laid out by the widget package, against Android's frames at 257 |

Run them on their own after a change to the engine or to the widget package's
measuring and placement:

```sh
(cd packages/constraint_engine && dart test test/parity)
(cd packages/flutter_constraint_layout && flutter test test/parity)
```

A failure means the port has moved away from Android. The expected values are
Android's output, so never edit one to make a test pass: fix the port. The
same holds for every other test that cites a Java value (a `probe` id or a
`J257` comment).

Two switches check what the suites cannot see on their own:

- `flutter test --dart-define=cl.verifyReplay=true`, in
  `packages/flutter_constraint_layout`, runs every replayed layout, every
  replayed dry query, and every reused baseline in full as well, and reports a
  difference as an error. The whole suite must pass with it.
- `dart -Dcl.trace=true test -c source test/solver_float_test.dart`, in
  `packages/constraint_engine`, compiles the solver trace in and runs its
  end-to-end test, which is skipped otherwise. Keep `-c source`: the test
  runner's default compiler does not see the `-D` define, so without it the
  test stays skipped.

**The full parity gates.** The checked-in gates are a sample. The full gates
run the engine and the widget package over the whole parity corpora, about two
million layouts, against the parity oracle: upstream's Java core at the pin in
[UPSTREAM.md](packages/constraint_engine/UPSTREAM.md), driven by `VOpDriver`,
a Java port of the `ConstraintLayout` view layer (`onMeasure`, the child
measurer, `MeasureSpec`). They take hours, need a JDK 17 or later, and are not
run in CI. The tools are in
[packages/constraint_engine/tool/parity](packages/constraint_engine/tool/parity),
with the Flutter harness in
[packages/flutter_constraint_layout/tool/parity](packages/flutter_constraint_layout/tool/parity);
the README in `packages/constraint_engine/tool/parity` describes them in full.
In outline, from `packages/constraint_engine/tool/parity`:

1. Every script sources `env.sh`, which names the locations it reads and
   writes, all outside the repository under `CL_PARITY_WORK` (by default
   `${TMPDIR:-/tmp}/cl_parity`). Set `CL_HEAVY` to a command that runs one
   heavy step at a time, such as a lock; without it, heavy steps run at
   `nice 10`.
2. Build the oracle. Check out upstream's androidx/constraintlayout at the
   pinned commit into `CL_UPSTREAM`, then run `java/build_core.sh` (upstream's
   core) and `java/build.sh` (`VOpDriver`). `java/trace/build_trace.sh` builds
   the core with solver-trace hooks, and `java/dirty/build_dirty.sh` the
   emulation of Android's dirty second layout.
3. Build the Dart tools into `CL_BIN` (`dart/vfuzz.dart` and
   `dart/vtrace.dart` with `-Dcl.trace=true`, and `dart/gclass.dart`), and set
   up the Flutter harness, outside the repository, with
   `packages/flutter_constraint_layout/tool/parity/fl_harness/setup.sh`.
4. `gates/corpora.sh` writes the corpora, and `gates/java_refs.sh` runs the
   oracle on them.
5. Run the gates, each into an output directory of its own:
   `gates/corpus_gates.sh` (levels 257 and 0, on the core path and through
   `ViewHost`, plus the second layout and the solver trace),
   `gates/graph_gates.sh` (the graph levels), `gates/inplace_gates.sh`
   (in-place sequences on Android's live views and through `ViewHost`, at
   every level), `gates/fl_gates.sh` (real widget trees: frames, dry layouts,
   in-place changes, and replay), and `gates/exc.sh` (caught and thrown
   exceptions on the adversarial corpus).
   The target is 0 differences in every report. `gates/nd.sh` finds the
   differing layouts whose Java result depends on hash order, so that the next
   run leaves them out.
6. For a change that must not move a pixel, `gates/ref_runs.sh` hashes a
   build's outputs, and two builds then compare line for line by their
   `SHA256SUMS.content` files.
7. `view/fetch.sh` and `view/roborun.sh` run the same layouts on real Android
   views (Robolectric 4.16, SDK 35, ConstraintLayout 2.2.1), which checks the
   oracle itself and is the in-place gate's reference.

Never rebuild the oracle while a run is going, and never change an expected
value or a comparison to reach 0.

**Regenerating the checked-in corpora.** They come from the full corpora and
the oracle's results:

- for the engine,
  [select_corpus.py](packages/constraint_engine/test/parity/select_corpus.py)
  picks `engine_corpus.json`, and with `--export` and `--check` writes the
  oracle's batch input for a corpus file and compares the oracle's output
  with it;
  [select_graph_corpus.py](packages/constraint_engine/test/parity/select_graph_corpus.py)
  picks `graph_corpus.json`;
- for the widget package,
  [tool/parity/export_android_corpus.dart](packages/flutter_constraint_layout/tool/parity/export_android_corpus.dart)
  writes `android_corpus.json`, with
  [tool/parity/fl_model.dart](packages/flutter_constraint_layout/tool/parity/fl_model.dart)
  turning each op list into a widget tree, and with `--ops` and `--check`
  writes the oracle's batch input for the checked-in file and compares the
  oracle's output with it:

  ```sh
  cd packages/flutter_constraint_layout
  dart run tool/parity/export_android_corpus.dart --ops test/parity/android_corpus.json <dir>/fl.in
  # run the oracle on <dir>/fl.in at level 257 (java/jrun.sh), writing <dir>/fl.java
  dart run tool/parity/export_android_corpus.dart --check test/parity/android_corpus.json <dir>/fl.java
  ```

The two `test/parity/README.md` files, in
[the engine](packages/constraint_engine/test/parity/README.md) and in
[the widget package](packages/flutter_constraint_layout/test/parity/README.md),
describe each corpus, how its layouts were chosen, and the oracle's exact
options.

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
# The engine alone (Android's pipeline at 257 on chained and one-way rows, and
# the graph at 321), compiled AOT (closest to a Flutter release build) or JIT.
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
| `workspace` | `macos-latest`, for the goldens | `flutter pub get` at the root; `dart analyze --fatal-infos packages/constraint_engine packages/flutter_constraint_layout website`, which also enforces the lint plugin; `dart test` in the engine; `flutter test` in `flutter_constraint_layout` (with the goldens) and in `website`; `flutter build web --wasm` of the website, so a broken web compile fails before it reaches `main` |
| `lints` | `ubuntu-latest` | `dart pub get`, `dart analyze --fatal-infos`, and `dart test` in `packages/flutter_constraint_layout_lints` |
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
3. For a first release, check that the name is accepted. pub.dev rejects a new
   package whose name, with underscores removed and lowercased, matches an
   existing package's, and the dry run cannot detect this. Compare against
   `https://pub.dev/api/package-names` (send `Accept-Encoding: gzip`).
4. Merge the release into `main` and push it. The packages' `repository`,
   `documentation`, and README links point at `main` and at the live site, and
   pub.dev checks them when it scores a package.
5. Wait for the Deploy website workflow to finish, then check that
   `https://constraints.birju.dev/docs` loads (it is the `documentation:` URL of
   `flutter_constraint_layout`).
6. Publish with `dart pub publish` in this order: `constraint_engine` first,
   because `flutter_constraint_layout` depends on it, then
   `flutter_constraint_layout`, then `flutter_constraint_layout_lints`.

## Updating the upstream port

`constraint_engine` is a port of `androidx.constraintlayout.core` pinned to one
upstream commit. [UPSTREAM.md](packages/constraint_engine/UPSTREAM.md) records
that commit, how the port compares with the released core versions, the
ported scope, every intentional divergence, and which upstream tests are
ported. To move the port forward:

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
5. Move the parity oracle to the new revision as well, and regenerate the
   parity corpora from it (see [Android parity](#android-parity)): the
   checked-in frames describe Android at the old pin.

## Docs

- Package READMEs are rendered on pub.dev, so they link to repository files
  with absolute URLs
  (`https://github.com/BirjuVachhani/flutter_constraint_layout/blob/main/<path>`).
  Docs that live only in the repository, such as this file, the root README,
  and `docs/`, use relative links.
- The docs page on the website,
  [website/lib/src/pages/docs_page.dart](website/lib/src/pages/docs_page.dart)
  with its examples in
  [website/lib/src/data/examples.dart](website/lib/src/data/examples.dart), is
  the source of truth for the documentation.
  [website/web/docs.md](website/web/docs.md) mirrors it as one Markdown file
  (served at `/docs.md`), so update both together: every paragraph, list,
  table, and example of the page appears in it, in the same order and with
  the same text.
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
