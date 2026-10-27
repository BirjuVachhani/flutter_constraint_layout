# The adapter's Android parity corpus

`android_corpus.json` holds 1,600 layouts, each as a real `ConstraintLayout` widget tree
together with the frames Android's ConstraintLayout computes for the same layout.
`android_parity_test.dart` lays every tree out through the adapter and requires Android's
geometry string, byte for byte: the layout's size and every child's offset and size.

The reference is the parity oracle that `packages/constraint_engine/test/parity/README.md`
describes: upstream's Java core at the pin in `UPSTREAM.md` (`constraintlayout-core`
1.1.0-alpha04), driven by `VOpDriver`, a Java port of the view layer (`ConstraintLayout`
2.2.0-alpha04: `onMeasure`, the view `Measurer`, `MeasureSpec`). Every layout is measured
on the oracle's view path at `OPTIMIZATION_STANDARD` (257), Android's default and the
adapter's. Nothing in this directory is computed by the adapter.

## Entries

Each entry is `{id, ops, tree, geometry}`:

- `id`: the layout's id in the parity corpora, `<generator>:<seed>`.
- `ops`: the op list the oracle measured, joined by `;` (the grammar is the engine's
  `test/support/op_replay.dart`). Its `ct` ops give each child's content.
- `tree`: the same layout as Flutter widgets, which `parity_tree.dart` builds (below).
- `geometry`: the oracle's result, `root W x H`, then per child, in child order,
  `name: (x, y) w x h`, or `name: gone, w x h` for a gone child that Android does not
  place. Guidelines and barriers are gone widgets, as Android's view helpers always are:
  they print their position at `0 x 0`.

### The tree

```
tree      {rtl, constraints: [minW, maxW, minH, maxH], children: [child...]}
child     {id, kind: widget | guideline | barrier | flow, ...}
widget    width, height: dim; left, right, top, bottom, baseline: link (absent: none);
          circle: [target, angle, radius]; hBias, vBias (absent: 0.5); ratio;
          hChain, vChain (1 spread inside, 2 packed; absent: spread);
          hWeight, vWeight; visibility (4 invisible, 8 gone; absent: visible);
          content: [box | text | none, W, H, baseline]
guideline orientation: horizontal | vertical; one of begin, end, percent
barrier   edge: left | right | top | bottom; margin; allowsGone (absent: true); refs
flow      width, height, links, biases and visibility as a widget's; refs;
          flow: {orientation (0 horizontal, 1 vertical), wrap (0 none, 1 chain,
          2 aligned), hStyle, vStyle, hBias, vBias, hAlign (0 start, 1 end,
          2 center), vAlign (0 top, 1 bottom, 2 center, 3 baseline), hGap, vGap,
          maxElements, padding}
dim       "wrap" | "parent" | ["fixed", px] | ["spread", min, max] |
          ["cwrap", min, max] | ["percent", fraction, min, max]  (min, max 0: none)
link      [target ("parent" or a sibling's id), the target's edge, margin, goneMargin
          (0: none)]
```

`constraints` are the layout's incoming box constraints: tight on an axis the oracle
measures EXACTLY, `0..infinity` (`maxW` or `maxH` null) on an axis it measures
UNSPECIFIED. The test puts the layout under exactly those constraints, as the FL runner
does: a `Directionality`, an `Align` at the top left, an `OverflowBox` with the
constraints, then the `ConstraintLayout`, under a fresh key per entry, laid out up to
`EnginePhase.layout`.

Every child of a `widget` is a `ContentModelBox` (`content_model_box.dart`), a leaf whose
layout follows the content op: `box W H` a fixed size, `text W H` a text `W` wide on one
line and `H` per line (at width `w` it takes `H * ceil(W / w)`), `none` a bare view (the
maximum of a bounded axis, else the minimum). The box gives under tight constraints what
the oracle's content view gives under EXACTLY, under `0..s` what it gives under
`AT_MOST(s)`, and under `0..infinity` what it gives under UNSPECIFIED, which are the
constraints the adapter turns those specs into. So the adapter and the oracle get the
same measure answers, and the frames must match.

How the tree expresses the op list:

- Links are absolute (`left`, `right`, `top`, `bottom`, `baseline`), never start or
  end, so a bias is used as given in both directions; a circle is a `CircularLink`, with
  the angle as the op list gives it.
- A vertical guideline of a right-to-left layout holds `1 - p` for the op list's percent
  `p`, which the adapter's mirror (`1 - x` in single precision, as Android computes it)
  turns back into exactly `p` for every entry; begin and end are traded the same way.
- A barrier's margin is used as given, in both directions, as on Android.
- A group is a plain widget in the op lists (`w G 0 0; hb G W; vb G W; ct G box 0 0 -1`,
  with its members' visibility set by `v` ops), so it is a 0 x 0 `Constrained` child
  here.
- A `["fixed", 0]` flow axis is a real size of 0, measured EXACTLY at 0. Android's layout
  params cannot say it (`0dp` is a match constraint), so the reference is the oracle's
  view path on its core widgets.

## How the layouts were chosen

The source is FL, the parity corpus of real widget trees (written by
`packages/constraint_engine/tool/parity/gates/corpora.sh FL`): 60,000 layouts, the
first 3,000 lines that the Flutter API can express from each of 20 generators of the
parity corpora VR (R's realistic layouts with text and box content: VR-fflist,
VR-ffrtl, VR-ffsettings, VR-ffchat, VR-fftoolbar, VR-rscform, VR-rsccards, VR-rscnest,
VR-fnrtl, VR-nbrscnest) and T (targeted families: T-measure, T-wrap, T-oddbias,
T-chain, T-gone, T-depsorder, T-virtual, T-circle, T-ratio, T-pctmin). Its oracle
results are `FL.J257.java` (`jrun.sh FL.txt FL.J257.java 257`).

`tool/parity/export_android_corpus.dart` (seed 20261026, 80 layouts per generator, 40
T-virtual layouts with a `.fixed(0)` flow) maps each line to its tree
(`tool/parity/fl_model.dart`) and takes, per generator, with the shorter op list first:

1. a greedy cover of the generator's tags, each tag twice: the corpus line's feature
   tags (chains, ratios, percents, guidelines, barriers, baselines, gone widgets,
   wrap containers, circles, flows and the rest), plus `rtl`, an unbounded axis, and a
   `.fixed(0)` flow;
2. for T-virtual, the shortest layouts with a `.fixed(0)` flow, up to 40;
3. a seeded draw from the shorter half of the generator's layouts, up to 80.

Every FL layout finishes on the oracle (no ND, hang, stack overflow or exception), so
none is left out. The file holds 1,600 entries: 470 right-to-left, 301 with an unbounded
axis, 694 with a barrier, 122 with a guideline, 305 with a baseline link, 606 with a gone
child, 184 with a percent size, 83 with a ratio, 80 with a circle, 80 with a flow (53
with a `.fixed(0)` axis).

## Regenerating

Both sides, from FL and the oracle (the same inputs and options give the same file):

```
dart run tool/parity/export_android_corpus.dart <FL.txt> <FL.J257.java> \
    test/parity/android_corpus.json --seed 20261026 --per-generator 80 \
    --fixed-zero-flows 40
```

The Java side of the checked-in file alone, against the oracle:

```
dart run tool/parity/export_android_corpus.dart --ops test/parity/android_corpus.json <dir>/fl.in
jrun.sh <dir>/fl.in <dir>/fl.java 257
dart run tool/parity/export_android_corpus.dart --check test/parity/android_corpus.json <dir>/fl.java
```

`jrun.sh` (`packages/constraint_engine/tool/parity/java/jrun.sh`, once the oracle is
built as that directory's README describes) runs the pinned VOpDriver v2 build on its
batch input: `java -XX:+UnlockExperimentalVMOptions -XX:hashCode=2 -Xmx1g -Xss32m
-XX:+UseSerialGC -XX:-OmitStackTraceInFastThrow -XX:CICompilerCount=2 -cp <core classes
at the pin>:<VOpDriver classes> VOpDriver batch <in> <out> <progress> 0 257`, restarting
after a hang. The view path is chosen by the `ct` and `cspec` ops. The check reported 0
differences on all 1,600 entries when the file was made. Build the oracle only from
upstream's core at the pin and the engine's `tool/parity/java` sources, unchanged: the
file records Android at the pin.

The Dart side is the test itself:

```
flutter test test/parity/android_parity_test.dart
```

## Probes

`probes.in` holds the op lists of the small layouts that the adapter's other tests cite
as `probe <id>` for their Java values (`group_ids_test.dart`, `rtl_float_test.dart`,
`barrier_rtl_margin_test.dart`, `features_test.dart`, `intrinsics_test.dart`,
`measurer_spec_test.dart`, `placement_test.dart`, `transcript_replay_test.dart`,
`unbounded_min_test.dart` and `virtual_layout_test.dart`), and `probes.J257.txt` the
oracle's results for them: the geometry, the `P257` summary and the `T257`
measure-request transcript (`VOpDriver` `-Dprobe -Dtranscript`). The `p4:`, `p4a:` and
`p4b:` probes give the same frames at level 0 (run the list at `257,0` to see it). They
mirror the tests' widget trees: one widget per child in child order, the links the
adapter connects (start and end resolved for the direction), and a `ct box W H -1` for a
`SizedBox` of that size, whose answers are the same under every measure spec.
Regenerate the results with:

```
jrun.sh test/parity/probes.in test/parity/probes.J257.txt 257 -Dprobe -Dtranscript
```
