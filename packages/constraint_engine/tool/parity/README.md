# Parity tooling

The tools that check the engine against Android, layout by layout: the Java oracle
(upstream's core at the pin, driven through a Java port of ConstraintLayout's view
layer), the generators of the parity corpora, the Dart drivers that run the corpora
through the engine, the comparators, and a check of the oracle itself on real Android
views. With them, every parity result in `README.md` and `UPSTREAM.md` can be rebuilt
from the repository: build the oracle at the pin, generate the corpora, run Java and the
engine on them, and compare. Nothing here is generated output: the corpora, the Java
results and every report are written to a work directory outside the repository.

`FORMATS.md` is the reference for every format, op and corpus; the tools cite it by
section ("FORMATS.md 8.4").

## What is here

| Directory | What |
|---|---|
| `env.sh` | The locations every script uses, as environment variables with defaults under one work directory (below). Sourced by the scripts. |
| `java/` | The oracle: `src/VOpDriver.java` (batch driver: op lists in, frames and probes out), `src/ViewHost.java` (a Java port of the view layer's `onMeasure`, child `Measurer` and `MeasureSpec`), `src/androidx/...` (`DirectProbe`, which dumps Direct's state and the measure-request transcript, and the access helpers that read package-private core state), `stubs/` (three annotation stubs the core compiles against), `build_core.sh` (upstream's core at the pin), `build.sh` (the oracle), `jrun.sh` (the primary run), `jbatch3.sh` (ND detection), `vop.sh` (one VOpDriver command), `echo_compare.py` and `robo_compare.py`. |
| `java/trace/` | TraceJava: `mk_trace.py` patches upstream's solver sources with trace hooks, `SolverTrace.java` is the sink, `build_trace.sh` builds them over the core (FORMATS.md 7b). |
| `java/dirty/` | `DirtyTwice.java`: Android's dirty second layout (every child `reset()` and configured again), with `build_dirty.sh`, `jdirty.sh` and `dirty_split.py` (FORMATS.md 19.2). |
| `java/probes/` | `DepsProbe.java`, `ResetProbe.java` and `RowBitsProbe.java`, the probes behind `test/dependents_state_test.dart`, `test/fresh_state_test.dart` and `test/solver_float_test.dart`. |
| `dart/` | The Dart harness: `vfuzz.dart` (corpus generator and runner), `vtrace.dart` (solver trace driver), `gclass.dart` (classifies GRAPH-level differences), the generators (`corpora.dart`, `gens.dart`, `vgens.dart`, `fgens.dart`, `tgens.dart`, with `fspec.dart`, `vspec.dart`, `respec.dart`, `temit.dart`), the op interpreter `ops.dart`, the paths `vpaths.dart` and `vpaths_future.dart`, the content model `content.dart`, `vrun.sh` and `vstats.py`. |
| `compare/` | `vcompare.py` (frames), `dcompare.py` (Direct dumps), `tcompare.py` (measure-request transcripts), `tracediff.py` (solver traces), `gclass_in.py`, `guardcheck.py`, `exc_classify.py`, `helper_only.py`, `keepbl.py` (the in-place gate's corpus: T2-inplace without its `bl N 0` and `hbl N 0` ops, FORMATS.md 21). |
| `view/` | The RoboOracle: `src/` (real `ConstraintLayout` views under Robolectric), `fetch.sh` (downloads Robolectric, the Android jar and ConstraintLayout 2.2.1), `robocp.sh`, `roborun.sh`, and `tools/` (`jstrip.py` for the version diff, `glate.py`, `gcompare.py`, `dclass.py`, `dstream.py`, `sample.py`). |
| `gates/` | One script per gate (below), and the scripts that write the corpora and the Java references. |
| `jfloat/` | `JFloatVectors.java`, which computes the JVM's float results behind `test/jfloat_vectors.json`, and `check_vectors.dart`, which checks the engine on all of them. |
| `bench/` | `rbench6.dart` and `bbench6.dart`, the benchmarks behind the corpus and screen numbers in `README.md`. |
| `data/` | Id lists of the derived inputs: `trace_sample.ids` (the 2,000-layout solver trace sample), `exc0.ids` (the 242 exception repros), `t2core_nd.ids` (the T2 layouts Java's identity hashes decide). |

The Flutter harness, which lays the FL corpus out through the adapter as real widget
trees, is in `packages/flutter_constraint_layout/tool/parity/fl_harness/`
(`packages/flutter_constraint_layout/tool/parity/README.md` describes it).

The Dart sources are analyzed with the engine (`dart analyze` finds no issue in them).
The Flutter harness is a package of its own, set up outside the repository, so the
adapter's `analysis_options.yaml` excludes `tool/parity/fl_harness/**`.

## Requirements

- A JDK, 17 or later (the results were measured on JDK 21); `javac` and `java` on the
  path.
- The Dart and Flutter SDKs the repository uses, with `flutter pub get` run at the
  repository root.
- Python 3, `git`, `curl`, `unzip`, and `shasum`.
- About 10 GB of free disk for every corpus and Java reference, and a few hundred MB
  more for the RoboOracle's downloads.

The heaviest steps (the Java batches, the Dart corpus runs, the Flutter runs) take
minutes each; the Java references for every gate take under an hour. The scripts in
`gates/` run their heavy steps through `heavy` (`env.sh`): set `CL_HEAVY` to a command
that serializes them (a lock, a priority wrapper), or leave it empty to run them at
`nice -n 10`. The runners they call that way (`java/jrun.sh`, `java/jbatch3.sh`,
`java/dirty/jdirty.sh`, `view/roborun.sh`, `dart/vrun.sh` and the harness's `run_fl.sh`)
take no lock of their own, and only `roborun.sh` and `run_fl.sh` lower their priority:
when you run one directly, as in the RoboOracle example below, put it behind your own
lock.

## The work directory

Every location is an environment variable, with a default under `CL_PARITY_WORK`
(`${TMPDIR:-/tmp}/cl_parity`):

| Variable | Default | Holds |
|---|---|---|
| `CL_UPSTREAM` | `$CL_PARITY_WORK/upstream` | upstream's checkout at the pin |
| `CL_CORE` | `$CL_PARITY_WORK/classes/core` | upstream's core, compiled |
| `CL_ORACLE` | `$CL_PARITY_WORK/classes/oracle` | VOpDriver |
| `CL_TRACE` | `$CL_PARITY_WORK/classes/trace` | TraceJava |
| `CL_DIRTY` | `$CL_PARITY_WORK/classes/dirty` | DirtyTwice |
| `CL_BIN` | `$CL_PARITY_WORK/bin` | `vfuzz.exe`, `vtrace.exe`, `gclass.exe` |
| `CL_CORPORA` | `$CL_PARITY_WORK/corpora` | the corpus files |
| `CL_JAVA` | `$CL_PARITY_WORK/java` | the Java references |
| `CL_ROBO` | `$CL_PARITY_WORK/robo` | the RoboOracle's downloads and classes |
| `CL_FL` | `$CL_PARITY_WORK/fl` | the Flutter harness |

The commands below run in a shell from `packages/constraint_engine`, with
`CL_PARITY_WORK` exported (a directory outside the repository) and `T=tool/parity`; the
scripts derive every other location from it.

## 1. Fetch upstream at the pin

```sh
export CL_PARITY_WORK=$HOME/cl_parity
T=tool/parity
git clone https://github.com/androidx/constraintlayout "$CL_PARITY_WORK/upstream"
git -C "$CL_PARITY_WORK/upstream" checkout 9cd4b5a4079a14175f91dc897abd83270799364a
```

A clone you already have (the repository's git-ignored `inspo/constraintlayout`, for
one) works too: point `CL_UPSTREAM` at it. `build_core.sh` refuses a checkout at any
other commit.

## 2. Build the oracle and the tools

```sh
$T/java/build_core.sh            # upstream's core: every file of core/src/main/java
$T/java/build.sh                 # VOpDriver, ViewHost, DirectProbe
$T/java/trace/build_trace.sh     # TraceJava (the solver with trace hooks)
$T/java/dirty/build_dirty.sh     # DirtyTwice
$T/java/vop.sh version           # v2 2026-10-25 helpers GONE on the view path
$T/java/vop.sh probes            # D=(10,10,0x50), A=(0,10,400x60), B=(0,100,100x40) C=(100,115,100x20)

B=$CL_PARITY_WORK/bin; mkdir -p "$B"
dart compile exe -Dcl.trace=true $T/dart/vfuzz.dart -o "$B/vfuzz.exe"
dart compile exe -Dcl.trace=true $T/dart/vtrace.dart -o "$B/vtrace.exe"
dart compile exe $T/dart/gclass.dart -o "$B/gclass.exe"
```

The core compiles with three annotation stubs (`java/stubs/`) in place of the AndroidX
annotation library. Built on JDK 21, the core and TraceJava classes are byte-identical
to the ones the results were measured with, and the oracle differs only in one error
message.

`vfuzz` and `vtrace` are built with `-Dcl.trace=true`, which compiles in the engine's
trace switch: the Direct dumps and the trace need it, and it changes no result. To check
another checkout's engine, add `--packages=<checkout>/.dart_tool/package_config.json`.

## 3. Generate the corpora

```sh
$T/gates/corpora.sh "R VR VR2 T T2 A T2core sample exc0"
```

`corpora.sh` runs every generator at its seeds (FORMATS.md 3) and writes `R.in`,
`VR.in`, `VR2.in`, `T.in`, `T2.in` and `A.in`, then the derived inputs: `T2core.in` (T2
without Flows, layout-view ops, in-place sequences and the ND ids of
`data/t2core_nd.ids`), `sample.in` and `exc0.in` (by the id lists in `data/`). Its two
other steps, `FL.txt` and `TIP.txt` for the Flutter gates, come once the Flutter harness
is set up (step 5, "The Flutter harness"): `FL` needs it, and with no step named,
`corpora.sh` runs all eleven and stops at `FL` when the harness is missing. Generation
is deterministic.

R, VR and VR2 are generated through the engine: their `rsc` and `nbrsc` generators
replay raw op lists on the engine and print the configured floats they read back. The
corpus files the recorded results ran on were made by the engine's earlier design,
which held those floats as doubles (`vx card 0.3`); this engine holds them in binary32
and prints the value's exact decimal (`vx card 0.30000001192092896`). Regenerated from
this checkout, R holds the same 319,827 ids in the same order, and 34,122 op lists
(in `rsccards`, `rscnest`, `nbrsccards` and `nbrscnest`; VR and VR2 the same) differ in
that spelling only. Both spellings parse to the same binary32 value on both sides, so
the layouts and every result are the same; only the op text, and so the hashes of files
that repeat it, differ. A, T, T2, T2core, `TIP.txt` and the exception repros come out
byte for byte as recorded (the trace sample takes half of its layouts from R).

## 4. Run Java

```sh
$T/gates/java_refs.sh "R A VR2 T2 T2core trace exc0 graph"
```

Its `FL` step, the references of the Flutter gates, needs `FL.txt` and comes with the
Flutter harness (step 5); with no step named, the script runs all nine and stops at `FL`
when `FL.txt` is missing, before `graph`. The script's header lists every file it writes
into `CL_JAVA` and the flags of each run: the primary runs at 257 and 0 (`-Dprobe`), the
Direct dumps (`-Ddirect`) and transcripts (`-Dtranscript`) at 257, the core path for
T2core, TraceJava on the trace sample and on the exception repros at 257 and 0, the FL
references with Android's dirty second layout, and the GRAPH levels 64, 321, 192 and
449. Never rebuild the oracle while a run is
going: a running JVM loads not-yet-loaded classes from the new build.

ND (Android's own hash-order nondeterminism) is looked for only where a gate finds a
difference: run the gate, then `gates/nd.sh <corpus> <levels> <the gate's .ids file>
[core]`, which runs the triple run (`java/jbatch3.sh`) on those layouts and writes the
`.nd` file the gate reads, then run the gate again. A layout the engine matches needs
no check.

## 5. The gates

Each gate prints its counts and writes its reports, the differing ids and the side
files into the output directory given. The target of every gate is 0 differences
outside the excluded classes (ND, HANG, SOE, JEXC); `README.md` ("What parity means")
and `UPSTREAM.md` ("The parity contract") give the recorded results, and FORMATS.md 20.2
the content hashes of the final engine's outputs.

| Gate | Command | What it checks |
|---|---|---|
| 257 and level 0 | `gates/corpus_gates.sh <out>` | Frames of R, A (with the printed status; every guard trip must be a Java stack overflow), T2core, VR2 and T2 against J257; Direct's state (dcompare) and the measure requests (tcompare); the second layout in the same container against Android's dirty second layout at 257 and 0 (`twice`; `twicefull` compares every layout); the solver trace sample event for event (`trace`); and the same frames, transcripts and trace at level 0 (`level0`, T2's in-place sequences left to the in-place gate). Steps can be named: `corpus_gates.sh <out> "R A"`. |
| GRAPH levels | `gates/graph_gates.sh <out> [corpora] [levels]` | R and T2core at 64, 321, 192 and 449, VR2 and T2 at 321, 192 and 449, against Java at the same level (T2's in-place sequences left to the in-place gate); each difference classified by route and mechanism (`gclass`). |
| In place, on live views | `gates/inplace_gates.sh <out> [levels]` | T2's 50,000 in-place sequences applied state by state to Android's live views (RoboOracle, `-Drobo.inplace=1`) and to the engine through `ViewHost`, at 0, 64, 192, 256, 257, 321 and 449: the frames in place, the dirty second layout, the fresh builds, and the sequences each side throws on and at which state (FORMATS.md 21). Needs the RoboOracle (`view/fetch.sh`). |
| Exceptions | `gates/exc.sh 257 <out> full`, `gates/exc.sh 0 <out> full` | Every exception the engine catches is one Java catches at the same solver operation (class i, `same`); none where Java has none (classes ii and iv: 0). |
| Real Flutter trees | `gates/fl_gates.sh <out>` | FL through the adapter against J257 (strict), the dry layout against the real size, in-place sequences against fresh builds (Android's live views equal them at 257, the adapter's default), the replay dual run and the second layout against Android's (`FLr`), and the transcripts. Needs the Flutter harness in `CL_FL`. |
| Bit identity | `gates/ref_runs.sh <out>`, then `diff <ref>/SHA256SUMS.content <out>/SHA256SUMS.content` | The Dart outputs at 257 (R, A, T2core, VR2, T2, the trace, FL, the second layouts), reduced to their content and hashed: a change that must not move a pixel leaves every line identical. |
| The oracle on real views | `view/fetch.sh`, then `view/roborun.sh <in> <out>` and `java/robo_compare.py <VOpDriver result> <out>` | VOpDriver's view path against real Android views (Robolectric 4.16, SDK 35, ConstraintLayout 2.2.1): 0 differences on VR, T, VR2 and T2; with `-Drobo.level`, T2-fresh at 0, 64, 192, 256, 321 and 449 against Java at the same level: 0. |
| Floats | `jfloat/` (below) | The engine's Java float layer against the JVM. |
| The suite's corpora | `dart test test/parity` | The 2,560 layouts of `test/parity/` against the Java strings they hold. |

### The Flutter harness

```sh
../flutter_constraint_layout/tool/parity/fl_harness/setup.sh   # into $CL_FL
$T/gates/corpora.sh "FL TIP"
$T/gates/java_refs.sh FL
$T/gates/fl_gates.sh "$CL_PARITY_WORK/out/fl"
```

`setup.sh [checkout]` copies the harness to `CL_FL` with path dependencies on a
checkout's adapter and engine (this one by default) and runs `flutter pub get` there.

### The RoboOracle

`view/fetch.sh` downloads, from the official repositories, and checks against the SHA-1
each repository publishes:

- Robolectric 4.16 and its runtime dependencies, from Maven Central
  (`https://repo1.maven.org/maven2/org/robolectric/...`);
- Robolectric's Android 15 framework jar, `android-all-instrumented`
  `15-robolectric-13954326-i7` (SDK 35), from Maven Central;
- ConstraintLayout 2.2.1 (`androidx.constraintlayout:constraintlayout:2.2.1`, the AAR
  and its sources jar) and `constraintlayout-core` 1.1.1 (jar and sources), with the
  androidx test, tracing and annotation libraries Robolectric loads, from Google's
  Maven repository (`https://dl.google.com/android/maven2/...`).

About 400 MB, most of it Robolectric's native runtime and the Android jar. `roborun.sh
<in> <out> [start] [count] [pin|rel]` compiles `view/src` and lays every line of a
corpus out on real views, with the pinned core (`pin`, `$CL_CORE`) or the released core
1.1.1 (`rel`). Flags after the fifth argument (FORMATS.md 10): `-Drobo.inplace=1`
applies an in-place sequence to live views (`-Drobo.inplace=changed` touches only the
views that change), `-Drobo.level=<n>` sets the layout view's optimization level
(default 257, Android's), and `-Drobo.twice=dirty|layout` lays the final views out a
second time after a `requestLayout` (into `<out>.twice`). Its output reads like a
VOpDriver result at the run's level (257 by default):

```sh
$T/view/fetch.sh
mkdir -p "$CL_PARITY_WORK/out"
$T/view/roborun.sh "$CL_PARITY_WORK/corpora/VR2.in" "$CL_PARITY_WORK/out/VR2.robo"
python3 -I $T/java/robo_compare.py "$CL_PARITY_WORK/java/VR2.java" "$CL_PARITY_WORK/out/VR2.robo"
# T2's in-place sequences on live views at level 0, and the fresh final states
grep '^T2-inplace:' "$CL_PARITY_WORK/corpora/T2.in" > "$CL_PARITY_WORK/out/TIP2.in"
$T/view/roborun.sh "$CL_PARITY_WORK/out/TIP2.in" "$CL_PARITY_WORK/out/TIP2.L0.robo" 0 -1 pin \
  -Drobo.inplace=1 -Drobo.level=0
python3 -I $T/compare/vcompare.py "$CL_PARITY_WORK/out/TIP2.L0.robo" "$CL_PARITY_WORK/out/TIP2.L0.robo.fresh" \
  --levels 257 --level 257 --strict --helpers full
# The same sequences through the engine, against the live views, at every level
$T/gates/inplace_gates.sh "$CL_PARITY_WORK/out/inplace"
```

To compare the released 2.2.1 view layer with the pinned one (FORMATS.md 13), unzip the
two sources jars `fetch.sh` downloads and diff them against
`$CL_UPSTREAM/constraintlayout/constraintlayout/src/main/java` and the core sources,
with `view/tools/jstrip.py` removing comments and blank lines.

### Java's floats

```sh
javac -d "$CL_PARITY_WORK/jf" $T/jfloat/JFloatVectors.java
java -cp "$CL_PARITY_WORK/jf" JFloatVectors "$CL_PARITY_WORK/jf/out" 100000 20261025 2000
dart run $T/jfloat/check_vectors.dart "$CL_PARITY_WORK/jf/out"   # 1,000,000 vectors, 0 mismatches
cmp "$CL_PARITY_WORK/jf/out/jfloat_vectors.json" test/jfloat_vectors.json
```

The same seed reproduces `test/jfloat_vectors.json` byte for byte (on JDK 21; the file
records the JVM).

### Benchmarks

`bench/rbench6.dart` times the baseline suite's screens (spread-chain rows, the same with
a ratio cell, one-way rows; 9 to 600 widgets) through `measure()` at 257, 0 and 321 and
through `ViewHost` at 257. `bench/bbench6.dart` times a sample of the corpus R, each
layout measured again in its own container: `bbench6 300 15 --ref <R.core257.isg.gz>
--vr <VR2.in> --vrref <VR2.view257.isg.gz> <R's 16 generator files>`, with R split per
generator in R's order into `bar_<gen>.txt` (the 8 barrier generators) and
`nob_<gen>.txt` (the 8 others), which gives the 4,781 layouts of `README.md`; the
`.isg.gz` references come from `gates/ref_runs.sh`, and every sampled layout's frames
are checked against them. Build both AOT (`dart compile exe`), as the numbers were.

## Notes

- Every Python tool runs with `python3 -I`.
- The scripts write nothing into the repository; the Flutter harness refuses a `CL_FL`
  inside it.
- Comments in the tools sometimes name the stage of the parity work that added a tool
  or a format (Phase 0 to Phase 6, p0-java and the like) and the baseline suite (BL)
  whose corpus R the parity corpora start from; they date the code, nothing more. So
  do the names of the earlier tools a tool was copied from, none of which is in the
  repository: BL's own (bfuzz, ffuzz, bclass, OpDriver and the like), the earlier
  rounds of work whose generators and transforms the corpora reuse (converge,
  verify-converge, engine-final, verify-final), and ViewProbe, the small Java port
  of the view layer's measure that came before VOpDriver.
- `ref_runs.sh` keeps the Flutter runner's tag `p5a`, which the recorded content hashes
  carry.
