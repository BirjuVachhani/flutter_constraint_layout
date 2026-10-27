# The engine's parity corpora

Two corpora of layouts, each layout with the status and geometry that Android's
ConstraintLayout computes for it. Their tests replay every layout through the engine
and require the same strings, byte for byte: every child's frame, the container's size,
and whether the solver loop printed a caught exception.

- `engine_corpus.json` (`engine_corpus_test.dart`): 2,000 layouts at
  `OPTIMIZATION_STANDARD` (257), Android's default, and at `OPTIMIZATION_NONE` (0).
- `graph_corpus.json` (`graph_corpus_test.dart`): 560 layouts at the dependency-graph
  levels 64, 321, 192 and 449.

The reference is the parity oracle: upstream's Java core at the pin in `UPSTREAM.md`
(`constraintlayout-core` 1.1.0-alpha04), driven by `VOpDriver`, which adds a Java port
of the view layer (`ConstraintLayout` 2.2.0-alpha04: `onMeasure`, the view `Measurer`,
`MeasureSpec`). Nothing in this directory is computed by the Dart engine. The oracle's
sources and the commands that build it at the pin are in `tool/parity/` (its README);
the corpora these layouts come from, their formats and the op grammar are described in
`tool/parity/FORMATS.md`.

## Entries

Each entry is `{id, path, ops, status, geometry}`:

- `id`: the layout's id in the parity corpora, `<generator>:<seed>`.
- `path`: how the layout is measured, as `test/support/op_replay.dart` implements it:
  - `core<level>`: the core path, `replayCore`. The container is measured with
    `measure(level, ...)` and the echo measurer, which answers every request from the
    widget itself (VOpDriver's `-Dpath=core`).
  - `view<level>`: the view path, `replayView`. One `ViewHost` measures the layout as
    Android's `onMeasure` does, and each child's content answers the measure specs
    (VOpDriver's `-Dpath=view`).

  The number is the optimization level: 257 is `OPTIMIZATION_STANDARD`, where pass 0
  runs Direct; 0 is `OPTIMIZATION_NONE`; 64 is `OPTIMIZATION_GRAPH`, 321 `STANDARD |
  GRAPH`, 192 `GRAPH | GRAPH_WRAP` and 449 `STANDARD | GRAPH | GRAPH_WRAP`, where
  `BasicMeasure` runs the dependency graph before, or instead of, the solver.
- `ops`: the op list, the exact sequence of engine calls that builds the layout, joined
  by `;`. The grammar is in `op_replay.dart` and `tool/parity/FORMATS.md` 4.
- `status`: `ok`, or `ok-printed` when the solver loop of the last measure caught and
  printed an exception, as Android's `ConstraintWidgetContainer.layout()` does.
- `geometry`: `root W x H`, then per child `name: (x, y) w x h`, or `name: gone, w x h`
  for a GONE child that the path does not place. A status other than `ok` is
  prefixed as `!ok-printed | `.

## The corpus at 257 and 0

| Path | Entries | From |
|---|---|---|
| `view257` | 1,000 | VR2 450 (R's layouts with text and box content), T2 550 (14 targeted families and their fresh builds, T2-fresh) |
| `core257` | 800 | R 300 (the realistic corpus), A 350 (adversarial), T2core 150 (T2 lists on the core path) |
| `core0` | 100 | R 40, A 60 |
| `view0` | 100 | VR2 50, T2 50 |

21 entries print a caught exception: the 11 layouts of A where Java prints at 257 and
finishes, and 10 at level 0.

### How the layouts were chosen

`select_corpus.py` (seed 20261025) reads the parity corpora (`R.in`, `VR2.in`, `T2.in`,
`T2core.in`, `A.in`) and the oracle's results for them, and picks a fixed budget per
corpus and path. A layout's keys are:

- its generator;
- its feature tags (chains, ratios, percents, guidelines, barriers, baselines, gone
  widgets, wrap containers, RTL, circles, Flows, AT_MOST specs, padding, and so on);
- mechanism flags from the oracle:
  - `direct`: the frames at 257 differ from those at level 0, so Direct decides them;
  - `today`: the engine's earlier graph-first design computed other frames (the
    corpus line's own geometry);
  - `multipass`, `multiiter`: BasicMeasure's passes 1 and 2, or more than one solver
    iteration;
  - `partial`, `complete`: Direct left an axis to the solver, or resolved every axis;
  - `printed`, `toosmall`;
  - `negpos`: a frame starts at a negative coordinate;
  - `negsize`: Direct gave a widget a negative size (crossed constraints).

A greedy cover takes, per corpus, layouts until every generator, every
generator-and-tag pair and every generator-and-flag pair is covered (flags three times),
preferring the shorter op list. The rest of the budget goes to short `direct` layouts,
round robin over the generators. Every layout that finishes with a printed exception is
taken first. 1,600 of the 1,800 entries at 257 are `direct`.

Excluded:

- layouts on which the oracle is not deterministic (ND: the triple run with other
  identity hashes disagrees);
- layouts on which Java hangs, overflows its stack or throws out of `onMeasure`;
- the in-place sequences of T2 (`T2-inplace`). There, the oracle's mid-list measure is
  Android's re-measure without a dirty hierarchy, while `ViewHost` always takes the
  dirty path, so the reference for them is Android's live views
  (`tool/parity/gates/inplace_gates.sh`, FORMATS.md 21), and the suite pins in-place
  layouts in `fresh_state_test.dart` and `persistent_layout_test.dart` with the live
  views' frames instead.

## The corpus at the dependency-graph levels

`graph_corpus.json` holds 560 entries, 80 per path: `core64`, `core321`, `core192` and
`core449` (40 from R and 40 from T2core each), and `view321`, `view192` and `view449` (40
from VR2 and 40 from T2 each). Every entry's status is `ok`.

At these levels `BasicMeasure` runs upstream's `DependencyGraph` when no child is in a
chain or is a virtual layout and the modes allow it, and the solver reads what the
graph resolved. The engine's graph is upstream's, with its rules for when it runs and
its results; this corpus pins that. Its layouts are ones on which the engine's earlier
graph, with its own declines and rounding, differed from Java at the level: each pool
(one corpus at one level) covers every generator and every route-and-mechanism pair of
those differences (which side's graph answered, and why the frames moved: a guideline,
a baseline, a percent, an odd bias, crossed links and the rest), preferring the shorter
op list, up to 40 layouts. Every entry fails on that earlier engine. Excluded: the
in-place sequences of T2, Java statuses other than `ok` and `ok-printed`, and the
layouts the triple run found not deterministic.

`select_graph_corpus.py` (seed 20261026) chooses them, from the corpus inputs, the
oracle's results at the four levels and the classification of the earlier engine's
differences (`gclass`, `tool/parity/dart/gclass.dart`); its docstring lists every input
file.

## The Java side

The oracle is the v2 build of `VOpDriver`, compiled from `tool/parity/java/src` against
upstream's core at the pin (`tool/parity/java/build_core.sh` and `build.sh`). It is run
with:

```
java -XX:+UnlockExperimentalVMOptions -XX:hashCode=2 -Xmx1g -Xss32m -XX:+UseSerialGC \
  -XX:-OmitStackTraceInFastThrow -XX:CICompilerCount=2 \
  -cp <upstream core classes at the pin>:<VOpDriver classes> \
  VOpDriver batch <in> <out> <progress> 0 <levels> [-Dpath=core|view]
```

`tool/parity/java/jrun.sh <in> <out> <levels> [-D...]` runs exactly this, and restarts
after a hang. `-XX:hashCode=2` makes every identity hash equal, so each anchor's
dependents iterate in insertion order (up to 10 dependents; Android's own order is the
identity-hash order, random per launch, and does not change frames on these layouts).

The results `select_corpus.py` reads, under the parity work's runs directory (`--runs`,
or `$CL_PARITY_RUNS`), are those of the gates: the primary runs at 257 and 0 with
`-Dprobe` (`R.java`, `VR2.java`, `T2.java`, `A.java`; `T2core0.java` at level 0 on the
core path), the runs at 257 with `-Ddirect` (and `-Dtranscript` on the view path), and
the ND files of the triple run. `tool/parity/gates/java_refs.sh` makes the same files
under its own names; the docstring of `select_corpus.py` lists the layout it expects.

## Regenerating

Both sides, from the corpora and the oracle:

```
python3 -I select_corpus.py engine_corpus.json --seed 20261025 --runs <parity runs dir>
python3 -I select_graph_corpus.py graph_corpus.json --seed 20261026 --runs <parity runs dir>
```

The same seed and inputs give the same file.

The Java side of the checked-in engine corpus alone, against the oracle:

```
python3 -I select_corpus.py --export engine_corpus.json <dir>
jrun.sh <dir>/core257.in <dir>/core257.java 257 -Dpath=core
jrun.sh <dir>/view257.in <dir>/view257.java 257 -Dpath=view
jrun.sh <dir>/core0.in <dir>/core0.java 0 -Dpath=core
jrun.sh <dir>/view0.in <dir>/view0.java 0 -Dpath=view
python3 -I select_corpus.py --check engine_corpus.json <dir>
```

The check reported 0 differences on all 2,000 entries when the file was made. For the
graph corpus, write each path's `id \t ops` lines (the JSON's `id` and `ops`), run
`jrun.sh` at the path's level with `-Dpath=core` or `-Dpath=view`, and compare each
result's geometry column with the entry's `geometry`.

The Dart side is the tests themselves:

```
dart test test/parity/engine_corpus_test.dart test/parity/graph_corpus_test.dart
```
