# The adapter's parity tooling

The tools that check flutter_constraint_layout against Android on real Flutter widget
trees. The Java oracle, the corpus generators, the comparators and every gate are the
engine's: `packages/constraint_engine/tool/parity/README.md` says how to build the
oracle at the pin and run them, and `FORMATS.md` there documents every format.

## What is here

- `export_android_corpus.dart` and `fl_model.dart`: they write
  `test/parity/android_corpus.json`, the 1,600 layouts of the FL corpus as widget trees
  with Android's frames, which `test/parity/android_parity_test.dart` checks
  (`test/parity/README.md`).
- `fl_harness/`: the Flutter harness, a package of its own (`cl_fl_harness`) that lays
  corpus layouts out through the adapter as real `ConstraintLayout` trees of
  `ContentModelBox` children:
  - `lib/content_model_box.dart`: a leaf `RenderBox` whose layout, dry layout,
    intrinsic sizes and baseline follow a corpus `ct` op exactly, so a
    `ConstraintLayout` of them gets the measure answers the oracle's content views
    give;
  - `lib/src/fmodel.dart` and `lib/ftree.dart`: a corpus line replayed on engine
    widgets and read back as a widget tree, and `bin/ftree.dart`, which selects the FL
    corpus (the first 3,000 lines the Flutter API can express from each of 20
    generators);
  - `lib/fl_runner.dart`, `test/fl_shard0_test.dart` and `test/fl_shard1_test.dart`:
    the FL runner, which lays every line out through `flutter_test` and writes its
    frames in the corpus format, with its modes: `dry` (the dry layout against the real
    size), `inplace` (in-place sequences pumped into one `ConstraintLayout`), `replay`
    (four more layouts in the same `ConstraintLayout` under `cl.verifyReplay`, and the
    second layout's frames) and `transcript` (the measure requests);
  - `test/bench_form_test.dart` and `test/bench_list_test.dart`: the form-keystroke and
    list-first-layout benchmarks (time and child layouts per pass), and
    `test/content_model_box_test.dart`;
  - `setup.sh`, `run_fl.sh` and `pubspec.yaml.in`.

## Setting the harness up

The harness is not a member of this repository's workspace: `setup.sh` copies it to a
directory outside the repository (`$CL_FL`, by default `$CL_PARITY_WORK/fl`), writes its
`pubspec.yaml` with path dependencies on a checkout's `flutter_constraint_layout` and
`constraint_engine` (this checkout by default, or the one given), copies the engine's
shared content model (`tool/parity/dart/content.dart`) next to it, and runs
`flutter pub get` there:

```sh
export CL_PARITY_WORK=$HOME/cl_parity
packages/flutter_constraint_layout/tool/parity/fl_harness/setup.sh [checkout]
```

Run it again after changing the harness sources. Then:

```sh
[FL_LEVEL=<n>] fl_harness/run_fl.sh <FL.txt> <out.txt> [tag] [dry] [inplace] [replay] [transcript]
```

runs two shards under `flutter test --concurrency=2` in `$CL_FL` and merges them back
into the input's order (it takes no lock of its own: run it behind yours). `FL_LEVEL`
sets Android's optimization level of every `ConstraintLayout` the runner builds
(default 257, the adapter's default), so the in-place and replay modes can be checked
against Android's live views and DirtyTwice at any level: run the RoboOracle with
`-Drobo.inplace=changed -Drobo.level=<n>` on `TIP.txt` (an app that sets only what
changed, as a Flutter rebuild does) and `java/dirty/jdirty.sh FL.txt <out> <n>`, then
compare with `compare/vcompare.py` (FORMATS.md 10, 19 and 21). The engine's
`tool/parity/gates/corpora.sh "FL TIP"` writes the corpora (the steps go in one
argument), `gates/java_refs.sh FL` Android's results for them, and `gates/fl_gates.sh
<outdir>` runs every gate on them (FL frames and dry layouts, in-place sequences, replay
and second layouts, transcripts). The benchmarks run in `$CL_FL`:

```sh
cd "$CL_PARITY_WORK/fl"
flutter test --concurrency=2 test/bench_form_test.dart --dart-define=BENCH_OUT=<file>
```

Because the harness's imports resolve only in its own package, this package's
`analysis_options.yaml` excludes `tool/parity/fl_harness/**` from analysis.
