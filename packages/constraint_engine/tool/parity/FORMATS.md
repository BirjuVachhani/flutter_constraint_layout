# Parity tooling: formats

The formats the parity tools read and write, the op syntax of the corpora, and what each
corpus, path and comparison means. README.md in this directory says how to build the
tools and run the gates; this file is the reference they cite by section number
("FORMATS.md 8.4"). The numbering is that of the parity work, which wrote one section per
stage; sections 9 and 14 held its working notes and are left out.

Paths are relative to `packages/constraint_engine/tool/parity/` unless they start with
`$`: `$CL_CORE`, `$CL_ORACLE`, `$CL_TRACE`, `$CL_ROBO`, `$CL_FL` and the rest are the
locations of `env.sh`. "The baseline suite" (BL) is the measurement suite that timed and
checked the previous release, whose corpus R the parity corpora start from; "J257" and
"J0" are the oracle's results at levels 257 and 0.

---------------------------------------------------------------------------------------

## 1. Corpus lines

`vfuzz` writes one line per generated layout, tab-separated:

```
id \t features \t path \t status \t geometry \t ops
```

- `id` is `<gen>:<seed>` (generator names in section 3). Ids are unique per corpus.
- `features`: comma-separated tags (the baseline suite's `features()` set plus `content`, `text`,
  `flow`, `circle`, `atmost`, `pad`, `cmin`, `cmax`, `inplace`, `group`), or `-`.
- `path`: the Dart path that produced `geometry` (section 5), or `none` when vfuzz ran
  with `--path none` (corpus only).
- `status`: `ok`, `ok-printed` (the solver loop caught and printed an exception),
  `EXC:<message>` (the layout threw out of the entry point), or `-` for `--path none`.
- `geometry`: OpDriver's format, byte for byte (section 2), or `-` for `--path none`.
- `ops`: the op list joined by `;`. It is the LAST field, so a vfuzz file is a valid
  `OpDriver batch` / `VOpDriver batch` input as it is (they read the id from the first
  field and the ops from the last).
- vfuzz writes no comment lines into the corpus file. Its summary goes to stdout and
  to `<out>.sum`; generator errors go to `<out>.err`.

## 2. Geometry and Java result lines

Geometry string (OpDriver `measureAndReport`, also produced by vfuzz):

```
[!<status> | ]root <W> x <H> | <name>: (<x>, <y>) <w> x <h> | <name>: gone, <w> x <h> ...
```

- Children in `mChildren` order. A GONE child that is not a Barrier prints size only.
- `!<status> | ` appears when the status is not `ok`: `!ok-printed | `,
  `!EXC:<message> | `, `!SO | `.
- Java result line (OpDriver and VOpDriver batch output):
  `id \t status \t geom(level1) \t geom(level2) ... [\t extra...]`, status `ok`, `ND`,
  `HANG`, or `EXC:<message>` (a throw outside the per-level try). Levels in the order
  given on the command line (`257,0` gives J257 then J0).
- Extra fields (DirectProbe, transcript): section 8.

## 3. Generator names

Run one generator per vfuzz call: `vfuzz <gen> <firstSeed> <count> <out> --path <p>`.

| Corpus | Generators | Seeds | Notes |
|---|---|---|---|
| R | `fflist ffrtl ffsettings ffchat fftoolbar rscform rsccards rscnest` (barrier layouts only) and `fnlist fnrtl fnsettings fnchat fntoolbar nbrscform nbrsccards nbrscnest` (no barriers) | 20,000 each from 300,100,000 | the baseline suite's labels, filters and ops (`--prep`/`--respec`/`--strip`, then `adeps`), so ids equal its ids; 319,827 layouts |
| VR | `VR-<R name>`, e.g. `VR-fflist` | same seeds as R | R's op list transformed (section 4.3) |
| T | `T-pctmin T-crossed T-negedge T-oddbias T-ratio T-pct T-measure T-gone T-circle T-virtual T-depsorder T-atmost T-chain T-wrap T-inplace`, plus `T-fresh` (the fresh build of each `T-inplace` sequence's final state, same seeds) | from 500,000,000; 50,000 for `T-pctmin T-chain T-wrap T-inplace T-fresh`, 20,000 for the rest | section 4.4 |
| A | `A-form A-formx A-rand A-ext A-extl A-chainy A-crossed A-cards A-nest A-vform A-vprofile A-vcard A-vtoolbar A-vgrid A-vcenter A-vadv A-vext A-vext2` | 20,000 each from 99,000,000 | 18 adversarial generators, raw op lists (no respec, no `adeps`); `vgrid` is a barrier table, not a Grid helper |
| VR2 | `VR2-<R name>` | VR's | section 16: VR with every guideline oriented at creation; 319,827 layouts |
| T2 | `T2-<family>`, `T2-inplace`, `T2-fresh` | T's | section 16: T with every guideline oriented at creation; `T2-fresh` is the fresh build of each `T2-inplace` final state; 470,000 layouts |

No corpus contains a Grid helper: Grid has no Android oracle (its view `Grid` is not core `GridCore`).

## 4. Op syntax

### 4.1 The base ops (`dart/ops.dart`, VOpDriver)

`R W H | rtl | ltr | wrapw | wraph | fixw | fixh | cw V | ch V`
`w N W H | b N | g N | add N | rm N`
`bt N TYPE | bm N MARGIN | bg N 0|1 | ref N CHILD`
`go N ORIENT | gb N V | ge N V | gp N PCT`
`c SRC A DST A MARGIN | x SRC A` (anchors `L R T B S C CX CY`)
`hb N F|W|M|P | vb N .. | hm N DEF MIN MAX PCT | vm N ..`
`mw N V | mh N V | hx N BIAS | vx N BIAS | gm N A V | v N VIS | bl N V`
`hc N STYLE | vc N STYLE | hw N W | vw N W | ra N RATIO SIDE`
`hbl N 0|1 | sw N V | sh N V | sx N V | sy N V | ipr N | iprest N | rereg | adeps | L`

Floats (`gp hm vm hx vx hw vw ra`) are decimal strings; Java parses them with
`Float.parseFloat`. `ops.dart` reads them with the engine's `parseFloat32` (jfloat.dart),
the same binary32 value; a build with `-Dcl.doubleparse=true` reads them with
`double.parse`, as the first corpora were made.

### 4.2 Content, Flow and layout-view ops

| Op | Meaning (upstream call) |
|---|---|
| `ct N KIND W H BL` | content of widget N for the view measurer (section 6). KIND `box`, `text` or `none`; `BL` is what `getBaseline()` returns, `-1` for none. The last `ct` for N wins. Core and echo paths ignore it. |
| `cc N TARGET ANGLE RADIUS` | `N.connectCircularConstraint(TARGET, ANGLE, RADIUS)`; ANGLE a float in degrees |
| `fl N` | a new core `Flow` named N (added with `add N`; members with `ref N M`) |
| `ref N M` | `HelperWidget.add` for any helper (the base op added to a Barrier only) |
| `fo N O` | `Flow.setOrientation(O)` (0 horizontal, 1 vertical) |
| `fwm N M` | `Flow.setWrapMode(M)` (0 none, 1 chain, 2 aligned, 3 chain_new) |
| `fhs N S`, `fvs N S` | `setHorizontalStyle`, `setVerticalStyle` (0 spread, 1 spread inside, 2 packed) |
| `fhb N B`, `fvb N B` | `setHorizontalBias`, `setVerticalBias` (float) |
| `fha N A`, `fva N A` | `setHorizontalAlign`, `setVerticalAlign` |
| `fhg N G`, `fvg N G` | `setHorizontalGap`, `setVerticalGap` |
| `fme N K` | `setMaxElementsWrap(K)` |
| `fpad N L T R B` | `setPaddingLeft/Top/Right/Bottom` |
| `frtl N 0|1` | `VirtualLayout.applyRtl(...)` (the view Flow's `resolveRtl`; emitted after the Flow's config, with the container's direction) |
| `cspec WM WS HM HS` | the specs the layout view receives in `onMeasure`, modes `E` (EXACTLY), `A` (AT_MOST), `U` (UNSPECIFIED). Without it a view path derives them from the container state: a FIXED axis gives `E(cw)`, a WRAP axis gives `U(0)` (the adapter wraps only an unbounded axis). |
| `cpad L T R B` | the layout view's padding (left, top, right, bottom; no start/end) |
| `cmin W H` | the layout view's `minWidth`, `minHeight` (default 0) |
| `cmax W H` | the layout view's `maxWidth`, `maxHeight` (default `Integer.MAX_VALUE`) |

`L` (a base op) is one measure pass of the path being run: on a view path one
`ViewHost.measure` with the current specs, on a core path one `measure(level, ...)`.
Every op list ends with an implicit final measure; frames are read after it.

A Group helper is not an op: it is a plain widget in child order,
`w G 0 0; add G; hb G W; vb G W; ct G box 0 0 -1`, with its members' visibility
applied by `v` ops (the view Group sets visibility outside measurement).

### 4.3 VR: R with content

VR is a pure function of R's op list:

1. For each regular widget (`w` op): `F` = the axis is FIXED (last `hb`/`vb` is `F`), and
   `cw x ch` = the `w` op's size (R puts the content size there on a non-fixed axis).
2. The `w` op becomes `w N (F_h ? cw : 0) (F_v ? ch : 0)`: a non-fixed axis starts at 0,
   as Android's `setWidth(0)` / `setWidth(WRAP)` and the adapter's normalization leave it.
3. Content, inserted right after the `w` op:
   - a widget with a WRAP, MATCH_CONSTRAINT or MATCH_PARENT axis gets
     `ct N text cw ch BL` when `cw > 0` and `ch > 0` (text width `cw`, line height `ch`,
     so its natural size is the configured size), and `ct N text cw 20 BL` when `cw > 0`
     and `ch == 0` (line height 20), else `ct N box cw ch BL`;
   - a widget with both axes FIXED gets `ct N box cw ch BL`.
   - `BL` is the widget's last `bl` value when it is > 0, else `-1`.
4. Every `bl` op is dropped (the content reports baselines; a fresh widget's distance is 0).

   Measured on R: every visible widget with a non-fixed axis has `cw > 0` and `ch > 0`
   (2,303,278 widgets), so VR's content always has the configured natural size; the
   line-height-20 and box fallbacks occur only on gone widgets (292,263), which are
   never measured. Visible fixed x fixed widgets: 1,313,635 boxes.
5. Everything else, `hbl`, `adeps` and the container ops included, is kept in place.

### 4.4 T families

Every T layout is emitted in the adapter's call order (`dart/temit.dart`, fspec
`emitSpecs` extended), ends with `adeps`, and carries content (stored size 0 on
non-fixed axes, a `ct` op per regular widget). Where Android and the adapter of the
previous release differ, T follows Android: an RTL bias flip is `fsub(1f, bias)` and a mirrored
guideline percent `fsub(1f, pct)` (written as the binary32 value's shortest double
string, which `Float.parseFloat` reads back exactly), a ratio is the binary32 quotient
of its two parts, a start/end barrier keeps the sign of its margin, as Android's does, and `hm`/`vm`
carry the match min and max on any behaviour (the view layer sets them on all). Unlike
VR, a T text content always has a baseline (a TextView does). A circle widget gets
`cc` instead of its other links (CL 1354-1596). A Flow is created with `fl`, configured
in child order (its `fo ... fpad` ops, `ref` members, `frtl`, then its own widget config).
Generators are in `dart/tgens.dart`; one line each here. In T a guideline is oriented
with its config in child order, so a link from an earlier sibling into a vertical
guideline's left or right edge is dropped; T2 (section 16) orients every guideline at
creation, as Android and the adapter do.

| Family | Size | What it stresses |
|---|---|---|
| T-pctmin | 50k | `.percent(f, min:)` with the min above, at and below `f * parent`, one and two links, biases, margins, gone targets, wrap parents |
| T-crossed | 20k | crossed and coincident links, gone targets collapsing onto their targets |
| T-negedge | 20k | exact negative edges, chained negative edges, Direct then readback |
| T-oddbias | 20k | odd biases in Direct and in the solver, RTL bias flips |
| T-ratio | 20k | ratios on one or both MC axes, with one or two links, ratio truncation |
| T-pct | 20k | percent sizes and percent guidelines landing near .5 |
| T-measure | 20k | match-parent x wrap text, MC x MC dangling, fixed baseline pairs, MC x wrap text, MC x MC text, constrained wrap, min/max clamp |
| T-gone | 20k | gone widgets with baselines, gone margins, gone match-parent and MC x MC |
| T-circle | 20k | circle constraints (`cc`) |
| T-virtual | 20k | one Flow (no Grid) whose members others link to |
| T-depsorder | 20k | earlier children linked into the top or bottom of a baseline-linked widget (the dependents order Android's view layer leaves) |
| T-atmost | 20k | `cspec` with AT_MOST and UNSPECIFIED, `cpad`, `cmin`, `cmax`, MC min and max on any behaviour |
| T-chain | 50k | chains, weights, styles, gone members, RTL, margins, splits at .5 |
| T-wrap | 50k | wrap containers with barriers, begin/end/percent guidelines and Groups |
| T-inplace | 50k | in-place sequences: fresh build, `L`, then 1 to 3 in-place config steps (the baseline suite's `emitInPlace`, content version), each followed by `adeps` and `L` except the last |
| T-fresh | 50k | the fresh build of each T-inplace final state (compare with `vcompare --map T-inplace=T-fresh`) |

## 5. vfuzz paths

`--path` takes:

- `none`: emit the corpus only (fields 3 to 5 are `none`, `-`, `-`).
- `core<level>`: OpDriver's core path at that optimization level, from 0 to 2047
  (`core0`, `core257`, `core64`, `core321`, ...): the container is measured through
  `ConstraintWidgetContainer.measure(level, ...)` with the echo measurer (17.1, 18.2,
  20.1).
- `view<level>`: VOpDriver's view path at that level (`view0`, `view257`, `view321`,
  ...): one `ViewHost` per layout, measuring each child through the content model
  (6.1; 17.1, 18.2, 20.1).

`--measurer` is accepted and ignored: a core path measures with the echo measurer, a view
path with the content model. The first corpora were made on two paths since retired,
`graphfirst` (the earlier graph-first `layout()`) and `forced` (its solver
fallback alone); their names survive in the `path` field of those corpus files only.

## 6. Content model

### 6.1 Spec form (VOpDriver's view measurer, the Dart `ContentMeasurer`)

`resolve(n, spec)`: `EXACTLY(s) -> s`, `AT_MOST(s) -> min(n, s)`, `UNSPECIFIED -> n`.

| Kind | width | height | baseline |
|---|---|---|---|
| `box W H` | `resolve(W, ws)` | `resolve(H, hs)` | `BL` |
| `text W H` | `width = resolve(W, ws)` | `nat = width <= 0 ? H * 50 : H * ((W + width - 1) / width)` (int division), then `resolve(nat, hs)` | `BL` (the first line's; independent of wrapping) |
| `none` | `EXACTLY(s)` or `AT_MOST(s) -> s`, `UNSPECIFIED -> 0` (`View.getDefaultSize(0, spec)`) | the same | `-1` |

This is ViewProbe's `Content` (text) generalized; `none` is a bare `View`.

### 6.2 Box-constraint form (ContentModelBox)

For `BoxConstraints(minW..maxW, minH..maxH)`:

- `box W H`: `size = constrain(W, H)`.
- `text W H`: `width = clamp(W, minW, maxW)`, `height = clamp(natH(width), minH, maxH)`
  with `natH` as above (an infinite `maxW` never occurs for a finite `W`).
- `none`: per axis, `bounded ? max : min`.
- baseline: `BL`, or none when `BL == -1`.

Under tight constraints this equals EXACTLY, under `0..s` AT_MOST, under `0..inf`
UNSPECIFIED, so 6.1 and 6.2 agree on every constraint the adapter produces.

## 7. Dart solver trace format

The engine's `lib/src/debug/solver_trace.dart` sits behind `const bool.fromEnvironment('cl.trace')`.
Its output is TraceJava's grammar (7b), event for event and field for field, so a
Dart trace and a Java trace of the same layout are byte-identical at parity:

- one event per line, ASCII, fields separated by one space, no trailing space;
- `<f>` is `%08x` (lowercase, 8 digits) of the binary32 bits: in Dart
  `(ByteData(4)..setFloat32(0, v)).getUint32(0).toRadixString(16).padLeft(8, '0')`
  (the value is binary32, so the conversion is exact);
- `<v>` is `SolverVariable.id`; ints in decimal; names `<debugName>.<A>`;
- the driver (vtrace.dart) writes `T <layoutId> <level> <build>` before and `E`
  after each layout, as VOpDriver does; the engine writes every other event at the
  site 7b names (the Dart port has the same methods);
- an event the Dart port cannot emit at the same point is a bug in the port or in the
  trace, not a tracediff option.
- `vtrace.dart`'s `installTraceSink` sets `SolverTrace.sink`; build vtrace with
  `-Dcl.trace=true`.

`compare/tracediff.py <dart.trace> <java.trace>` splits both files into
`T` blocks, matches blocks by `(layoutId, level, build)`, and compares the events of
each pair in order. It reports, per layout, the first diverging event with its index,
both lines, decoded floats, the last `M`/`PS`/`RS` context and a few events before,
then a summary (layouts compared, identical, diverging, only in one file, and the
diverging event kinds). `--kinds` restricts the comparison to some event kinds,
`--ignore` drops kinds, `--max` limits the reports.

### 7b. TraceJava grammar

TraceJava keeps section 7's letters and adds the events a first-divergence search needs.
Build: `java/trace/build_trace.sh` into `$CL_TRACE` (the whole core at the pin, with patched
`LinearSystem`, `ArrayRow`, `ArrayLinkedVariables`, `PriorityGoalRow`, `SolverVariable`
and a new `SolverTrace`). Run VOpDriver with
`CL_CP=$CL_TRACE java/jrun.sh <in> <out> <levels> -Dtrace=<file>`.
Without a sink the patched classes behave and print exactly as upstream.

Notation: `<f>` is `%08x` of `Float.floatToRawIntBits`; `<v>` a variable id; `<row>` is
`<n> <v>:<f> <v>:<f> ...`, a row's variables in `ArrayLinkedVariables` list order (which
is ascending id), `n` of them. `<A>` an anchor letter `L T R B S C CX CY N`.

| Event | Fields | Emitted at (Java line references are to the pin) |
|---|---|---|
| `T` | `<layoutId> <level> <build>` | driver, before each build of a layout (one per level, and per build when `-Dbuilds` > 1) |
| `PS` | `<pass>` | `ConstraintWidgetContainer.layout()` entry, the pass `BasicMeasure` set with `setPass` |
| `RS` | | `LinearSystem.reset()` entry |
| `V` | `<v> <type> <strength> <name>` | after a new id is assigned: `createObjectVariable` (type `U`, only when it assigns an id), `createSlackVariable` (`S`), `createExtraVariable` (`X`), `createErrorVariable` (`E`, its strength), `createVariable` (`N`); strength 0 except `E`; name `<debugName>.<A>` for object variables, else `-` |
| `Q` | `<v> <int>` | `addEquality(SolverVariable, int)` entry |
| `A` | `<subj or -> <simple 0/1> <const f> <row>` | `addConstraint(row)` entry (non-null row), before `updateFromSystem` |
| `U` | `<const f> <row>` | `addConstraint`, after `updateFromSystem` (rows that are not simple definitions) |
| `D` | `E` or `K` | `addConstraint` returns without storing: `E` empty after `updateFromSystem`, `K` no key variable |
| `R` | `<subj or -> <extra 0/1> <const f> <row>` | `addConstraint`, after `chooseSubject` (the row after its pivot; `-` and extra 1 when an extra variable is needed) |
| `AR` | `<index> <subj> <const f> <row>` | `addRow` stores the row at `index` (before `updateReferencesWithNewDefinition`) |
| `AF` | `<subj> <const f>` | `addRow`, a simple definition becomes a final value |
| `CP` | `<index> <subj>` | `addRow`'s compaction removes the simple row at `index` |
| `RX` | `<entering or ->` | `addConstraint`: the extra variable left the basis; the row is pivoted onto `entering` and released |
| `M` | `<pass> <iteration>` | `layout()`, before each `minimize()` (iteration = CWC's `countSolve`, from 1) |
| `MZ` | `<rows> <cols> <goalEmpty 0/1>` | `minimize()` entry (`mNumRows`, `mNumColumns`) |
| `BF` | `<infeasible 0/1>` | `enforceBFS`, after its infeasibility scan |
| `B` | `<row> <entering>` | `enforceBFS`, before each pivot |
| `C` | `<G or T> <tries> <candidate or ->` | `optimize`, after `getPivotCandidate` (`G` the system goal, `T` the temporary goal of `addConstraint`) |
| `P` | `<row> <entering> <G or T>` | `optimize`, before each pivot |
| `NP` | `<G or T>` | `optimize`, a candidate with no pivot row |
| `OE` | `<G or T> <tries> <cap, tested or done>` | `optimize` returns |
| `PI` | `<leaving or -> <entering> <amount f> <const f> <row>` | `ArrayRow.pivot`, after it (every pivot: `chooseSubject`, `optimize`, `enforceBFS`, `RX`) |
| `G` | `<v> <f0> ... <f8>` | a goal entry's strength vector after a change: `PriorityGoalRow.addError`, and in `updateFromRow` each variable left in the goal after `addToGoal` |
| `GR` | `<v>` | `PriorityGoalRow.removeGoal` removes `v` |
| `FV` | `<v> <f>` | `SolverVariable.setFinalValue` entry |
| `SY` | `<v> <synonym> <f>` | `SolverVariable.setSynonym` entry |
| `F` | `<v> <f>` | `computeValues`, each row subject in row order |
| `O` | `<v or -> <f> <int>` | `getObjectVariableValue`: the variable, its `computedValue`, the int returned |
| `X` | `<exception class>` | `layout()`'s solver loop catches an exception (at the catch) |
| `E` | | driver, after the layout's measure |

## 8. VOpDriver

### 8.1 Command line

```
java -XX:+UnlockExperimentalVMOptions -XX:hashCode=2 -Xmx1g -Xss32m -XX:+UseSerialGC \
  -XX:CICompilerCount=2 -cp $CL_CORE:$CL_ORACLE \
  [-D...] VOpDriver batch <in> <out> <progress> <startIdx> <levels>
... VOpDriver serve <levels>     # stdin "id\tops" lines, stdout result lines
... VOpDriver probes             # ViewProbe's three probes through the view path
java/jrun.sh <in> <out> [levels] [-D...]   # primary run, restarts after HANG
java/jbatch3.sh <in> <out> [levels] [primary.java]   # ND detection
... VOpDriver version            # build stamp (8.8)
```

`jrun.sh` uses the flags above plus `-XX:-OmitStackTraceInFastThrow` (HotSpot otherwise
drops the message and stack of an exception thrown often at one site, which would make
the P field's `excs` depend on JIT warm-up; no effect on results). `CL_CP` replaces the
core classes, e.g. `CL_CP=$CL_TRACE` with `-Dtrace=<file>`.

`batch` reads the id from the first tab field and the ops from the last, appends to
`<out>`, writes the line index to `<progress>` and `DONE` at the end. Lines starting
with `#` are skipped. `probes` runs these
op lists on the view path at 257 and prints ViewProbe's lines:
`R 400 800;w D 0 0;add D;hb D M;vb D M;c D L root L 10;c D T root T 10;ct D box 300 50 -1;cspec E 400 E 800`,
`R 400 800;w A 0 0;add A;hb A P;vb A W;c A T root T 10;ct A text 1000 20 -1;cspec E 400 E 800`,
`R 400 800;w B 100 40;w C 100 20;add B;add C;hbl B 1;hbl C 1;ct B box 100 40 30;ct C box 100 20 15;c B L root L 0;c B T root T 100;c C L B R 0;c C S B S 0;cspec E 400 E 800`.

Properties:

- `-Dpath=auto|core|view` (default `auto`): `auto` runs the view path when the op list
  has a `ct`, `cspec`, `cpad`, `cmin` or `cmax` op, else the core path. `core` measures
  with the echo measurer (`root.measure(level, ...)`). `view` is 8.6.
- `-Dbuilds=N` (default 1): builds at level 257; status `ND` when they differ.
- `-Dprobe`, `-Ddirect`, `-Dtranscript`: add the P, D and T fields; `-Dres` and
  `-Dfinals` add a `RES` field (last).
- `-DtimeoutMs=4000`: per layout; on a timeout the line is `id\tHANG` and the JVM exits
  with code 3 (`jrun.sh` restarts after it).
- `-Dtrace=<file>`: the 7b trace (with the TraceJava classpath).

### 8.2 Result line

`id \t status \t geom(L1) \t geom(L2) ... [\t extras]`, section 2. Extras follow all
geometry fields, per level in level order: `P<level>`, then `D<level>`, then `T<level>`,
each when enabled; `RES` last. So `-Dprobe -Ddirect` with `257,0` gives
`P257 \t D257 \t P0 \t D0`.

On the view path, `root W x H` is the layout view's measured size from
`resolveMeasuredDimension` (padding included, `& MEASURED_SIZE_MASK`, then
`min(maxWidth, ...)`); a child's `(x, y)` is `widget.getX()/getY()` (padding offset
included), the arguments `onLayout` passes to `child.layout`. A GONE child prints
`gone, w x h` unless it is a guideline or a helper (barrier, Flow), which `onLayout`
places anyway (CL 2019-2028). Guideline and barrier widgets are always GONE on the view
path (8.6), so they print `(x, y) 0 x 0`. On the core path everything is OpDriver's (`root` is
the container widget's size; only a barrier is exempt from the `gone` form).

### 8.3 P field (DirectProbe summary)

P, D and T describe the last measure of a build (the final one; an `L` op's measure is
cleared by it).

`P<level> passes=N it=a[,b[,c]] triv=T rows=R vars=V free=F goal=G res=a/n meas=M hits=H ts=WH exc=K [excs=...]`

- `passes`: `layout()` calls (1 to 3). `it`: solver-loop iterations per pass.
- `triv`: `1` when pass 0, iteration 1 reached `minimize()` with no stored row
  (`mNumRows == 0`) and an empty goal; `0` otherwise; `-` when that `minimize()` was not
  reached (an exception). `rows`, `vars` (`mVariablesID`), `free` (ids 1..vars whose
  variable is not final) and `goal` (goal entries) are taken at that same point (`-` if
  not reached).
- `res`: axes resolved after Direct and the post-Direct measures (D field time) over all
  axes: two per child, one for a guideline or a barrier (its orientation); `-` when the
  level has no DIRECT bit. Every axis resolved means `a == n`.
- `meas`: measurer calls; `hits`: CACHE_MEASURES hits (0 on the core path).
- `ts`: `isWidthMeasuredTooSmall`, `isHeightMeasuredTooSmall` of the container, `0`/`1`.
- `exc`: exceptions the solver loop printed (all passes). `excs` (only when `exc` > 0) is
  always last and takes the rest of the field: `<toString> @ <top frame>` per exception,
  joined by ` | `.

### 8.4 D field (Direct dump)

Taken at pass 0's first `LinearSystem.reset()`, i.e. after `Direct.solvingPass` and the
post-Direct measures, before anything is added to the solver. `D<level> -` without
Direct. Otherwise one entry per child, `mChildren` order, space-separated:

- widget: `<name>:<rh><rv>:<L>,<T>,<R>,<B>,<S>:<w>x<h>:<bd><hb>:<mr><sh><sv>`, with `rh`
  `h` if `isResolvedHorizontally()` else `-`, `rv` `v` or `-`; each anchor its final
  value or `_`; `w x h` the raw `mWidth x mHeight` (can be negative); `bd` the baseline
  distance, `hb` `+` or `-` for `hasBaseline()`; `mr` `m` if `isMeasureRequested()` else
  `-`; `sh`/`sv` `H`/`V` when the horizontal/vertical solving pass is done, else `-`.
- guideline: `<name>:g<orientation>:<value or _>`, the value of its anchor's final value.
- barrier: `<name>:b<type>:<rh><rv>:<L>,<T>,<R>,<B>`.

### 8.5 T field (measure-request transcript)

`T<level> <entry> <entry> ...`, one per `Measurer.measure` call, in completion order
(a VirtualLayout measures its members inside its own request, so the members' `F`
entries come before the VirtualLayout's entry; otherwise this is call order):

`<src>:<name>:<strategy>:<HB><VB>:<hdim>,<vdim>:<detail>:<mw>,<mh>,<mb>,<hasB><nsp>`

- `src`: `M` `measureChildren`, `D` Direct (its static `Measure`), `P` the post-Direct
  loop (a fresh `Measure`), `R` the re-measure loop (VirtualLayouts first, then
  `j = 0, 1`), `F` a VirtualLayout measuring a member, `X` other.
- `strategy` 0 SELF, 1 TRY_GIVEN, 2 USE_GIVEN; `HB VB` the incoming behaviours
  (`F W M P`); `hdim,vdim` the incoming dimensions.
- `detail`: `e` on the core path. On the view path: `g` GONE short cut, `n` no parent,
  `c` cache hit, `s` both axes spread match constraints under SELF (no view measure), or
  the specs of each `child.measure` as `<hspec>/<vspec>` with spec `E<n>`, `A<n>` or
  `U<n>`, two measures joined by `+`.
- answer: `measuredWidth`, `measuredHeight`, `measuredBaseline`, then `measuredHasBaseline`
  and `measuredNeedsSolverPass` as `0`/`1` (as the measurer left the `Measure`).

### 8.6 View path (Java `ViewHost` and view `Measurer`)

A port of the view layer at the pin (CL = `constraintlayout/.../widget/ConstraintLayout.java`):

- `ViewHost.measure(widthSpec, heightSpec)`: `onMeasure` (CL 1768-1879) over the widgets
  the op list built, without `setChildrenConstraints`: no widget is reset, so a fresh
  build starts its measure where Android's first (dirty) measure of new views does, and
  a mid-list `L` is Android's non-dirty re-measure (below):
  `container.updateHierarchy()`, `resolveSystem` (CL 1681-1721) with
  `captureLayoutInfo`, `setSelfDimensionBehaviour` (CL 1907-1981),
  `container.measure(level, ...)`, then `resolveMeasuredDimension` (CL 1733-1763,
  `View.resolveSizeAndState`). The container's optimization level is the run's level.
- Padding (`cpad`, physical, resolved): `paddingX = max(0, L)`, `paddingY = max(0, T)`,
  `paddingWidth = max(0, L) + max(0, R)`, `paddingHeight = max(0, T) + max(0, B)`
  (CL 1894-1905 with start/end resolved to left/right).
- Specs: `cspec`, else 4.2's default (FIXED `E(cw)`, WRAP `U(0)`).
- `Measurer.measure` (CL 709-996): spec derivation per behaviour and strategy,
  `useCurrent`, CACHE_MEASURES when the level has bit 256 (CL 844-872, `isSimilarSpec`),
  the GONE short cut, the both-spread skip, `child.measure`, `setLastMeasureSpec`, the
  match min/max clamp and second measure, the ratio branch only without DIRECT,
  `mNeedsBaseline`, `measuredNeedsSolverPass`. `getChildMeasureSpec` is AOSP's with
  `sUseZeroUnspecifiedMeasureSpec = false`; `makeMeasureSpec` is
  `(size & ~MODE_MASK) | mode`.
- Hierarchy state set at every `ViewHost.measure` (what `setChildrenConstraints` leaves
  and the op list cannot): every guideline and barrier widget is GONE (the view
  `Guideline` and `Barrier` call `super.setVisibility(GONE)` in their constructors,
  `Guideline.setVisibility` is empty, and CL 1371 copies the view's visibility to the
  widget; a `v` op on them is overridden). Consequence: a link into a guideline or a
  barrier that has a gone margin uses it (`ConstraintAnchor.getMargin`). Every
  VirtualLayout gets `updateConstraints(container)` (its members become
  `isInVirtualLayout`, CH 508-541).
- Child views: each widget has a content view (6.1); a widget without `ct` is `none`.
  A view starts at measured 0 x 0 with baseline -1; `getMeasuredWidth/Height` return
  the size `& 0x00FFFFFF`. A Flow widget's view is the view `Flow`:
  `VirtualLayout.measure(mode, size, mode, size)`, measured size
  `getMeasuredWidth/Height`, baseline -1. `mNeedsBaseline` holds for a widget with a
  baseline link and for the target widget of a baseline-to-baseline link, from the
  links present at a measure (setWidgetBaseline's flags; sticky, as LayoutParams keeps
  them).
- `L` mid-list: one `ViewHost.measure` in place (views keep their measured state; no
  widget is reset, which is Android's re-measure without a dirty hierarchy, not a
  rebuild). So VOpDriver's in-place result is not Android's dirty one: an in-place
  sequence's reference is the live views' (RoboOracle `-Drobo.inplace=1`, section 10;
  the in-place gate, section 21), which at 257 equals the fresh build (T-fresh).

### 8.7 Checks of the oracle itself

- Probes: `VOpDriver probes` prints `D=(10,10,0x50)`, `A=(0,10,400x60)`,
  `B=(0,100,100x40) C=(100,115,100x20)`, byte-identical to ViewProbe's output (a small
  Java port of the view layer's measure that came before VOpDriver).
- TraceJava: two runs over 1,000 R layouts (63 per generator, levels 257 and 0) give
  byte-identical traces, and so do two runs over 1,000 view-path layouts (500 VR, 500
  T); the trace build's geometry equals the plain build's in both.
- Core path against the baseline suite's own OpDriver on all of corpus R (319,827
  layouts, levels 257 and 0): byte-identical output.
- View path against the RoboOracle (section 10, real AOSP views with the 2.2.1 view
  layer): VR 319,827 compared, 0 differ; T 412,770 compared, 0 differ (57,230
  UNMAPPED: 50,000 in-place sequences, which the RoboOracle builds fresh only, and
  7,230 T-virtual layouts with a FIXED width of 0, which layout params cannot say).
  VR2 and T2 (section 16) the same: 0 differ.
- ND: `jbatch3.sh` over all of R (319,827 layouts; default hash and `hashCode=3`, three
  builds each, against the primary `hashCode=2` run): 0 ND.

### 8.8 Versions (`VOpDriver version` prints the stamp)

- v1: first release.
- v2 (the sources in `java/src`, and the build every parity result was measured with):
  the view path makes guideline and barrier widgets GONE and prints helpers with their
  position (8.2, 8.6); the transcript nests VirtualLayout members (8.5); `batch` skips
  `#` lines. Core-path output is unchanged. `build.sh` swaps the classes directory
  atomically.

## 10. Real-view oracle: RoboOracle

The RoboOracle lays every layout out on real Android views under Robolectric. The real
view layer reproduces ViewProbe's probes, `D=(10,10,0x50)`, `A=(0,10,400x60)`, `B=(0,100,100x40)`, `C=(100,115,100x20)`.

- Runtime: Robolectric 4.16, SDK 35 through
  `android-all-instrumented-15-robolectric-13954326-i7.jar` (Maven Central, SHA-1
  checked by `view/fetch.sh`, in `$CL_ROBO/android-all/`), offline mode. The framework classes
  (`View.measure`, `ViewGroup.getChildMeasureSpec`, `resolveSizeAndState`, RTL and
  margin resolution, `layout`) are AOSP's real code. `targetSdkVersion` is set to 35
  and `FLAG_SUPPORTS_RTL` is on.
- View layer: the ConstraintLayout 2.2.1 AAR `classes.jar` (Google Maven, SHA-1 checked).
  It is code-identical to the pinned 2.2.0-alpha04 view layer on API 17 and later
  (section 13). Core: `pin` = `$CL_CORE` (default), `rel` = released core 1.1.1.
- Command (a heavy step; primary run with `-XX:hashCode=2`):
  `view/roborun.sh <in> <out> [start] [count] [pin|rel]`
- Input: any section 1 corpus file (id is the first field, ops the last).
- Output, one line per input line: `id \t status \t geom257` (section 2's Java result
  line with one geometry column, so vcompare reads it like a VOpDriver run with levels
  `257`). Status: `ok`, `ok-printed` (the solver loop printed a caught exception),
  `EXC:<message>` (thrown out of measure or layout), `HANG`, or
  `UNMAPPED:<reason>` (the op list's final state cannot be written as LayoutParams;
  such layouts are not compared and are counted separately).
- Geometry: section 2's string from the real views, as VOpDriver's view path (8.2):
  `root` is the layout view's measured size; each child, in core `mChildren` order (the
  view order), prints `(getLeft(), getTop()) getWidth() x getHeight()`; a child whose
  op-state visibility is GONE and that is not a barrier prints `gone, w x h` with its
  real widget's size (`getViewWidget(v)`, 0 x 0; onLayout never places a GONE view, so
  after an in-place change the view keeps a stale frame that is not drawn).
- `-Drobo.inplace=1` (pass it after the 5th roborun.sh argument): a list with `L` ops
  (T-inplace) is cut before each `L`; the first state is built fresh, and every later
  state is applied to the same live views the way an app changes a live layout
  (LayoutParams rewritten in place and set again, as `ConstraintSet.applyTo` does;
  contents and visibilities changed in place), each followed by measure and layout.
  `<out>.fresh` gets a fresh build of the final state. Every regular child's
  `setLayoutParams` requests a layout, so every later state's `onMeasure` takes the
  dirty path (`setChildrenConstraints`: every child `reset()` and configured again),
  including a state that changes nothing.
- `-Drobo.inplace=changed`: as `1`, but a state touches only what changes, as an app
  that sets only the changed properties does: a view's LayoutParams are rewritten and
  set again only when they differ from its current ones (both after
  `LayoutParams.validate()`), a content or a visibility only when it changes, and
  nothing else requests a layout. A state that changes nothing lays nothing out again,
  as a Flutter rebuild with the same configuration does; a GONE child's content change
  still relayouts (its `requestLayout` reaches the layout view), where the adapter does
  not run the engine. Compare the FL runner's in-place mode with this mode.
- `-Drobo.level=<n>` (default 257): `ConstraintLayout.setOptimizationLevel(n)` on every
  layout view the run builds (the fresh build, the live views of `-Drobo.inplace`, and
  the `.fresh` build). The output reads like a VOpDriver result with one level column
  (vcompare: `--levels 257 --level 257` on two RoboOracle files, or extract the Java
  column of the level first). Without the flag, and with `-Drobo.level=257`, the
  output is byte-identical to the RoboOracle without the flag: on VR2 and T2-inplace
  (in place and `.fresh`) the sha256 of the outputs is unchanged.
- `-Drobo.twice=dirty|layout`: after the final measure and layout, a `requestLayout`
  and a second measure and layout of the unchanged views; `<out>.twice` gets the
  second geometry (`id \t ok \t geometry`). `dirty`: the first child view requests it,
  so `onMeasure` takes the dirty path; this is the second layout DirtyTwice (19.2)
  emulates, and on T2-fresh (50,000) at 0 and 257 DirtyTwice's second layout equals it
  on every layout. `layout` (any other value): the layout view alone requests it;
  `onMeasure` then reconfigures the children only while one of them is still
  layout-requested (a GONE child, which `onLayout` never lays out, stays so from its
  creation), and otherwise measures again over the widgets as the last measure left
  them, which is Android's non-dirty re-measure (VOpDriver's mid-list `L`, 8.6).
- `roborun.sh` runs the JVM with `-XX:-OmitStackTraceInFastThrow`, as `jrun.sh` does, so
  an exception's message in an `EXC` status does not depend on JIT warm-up.

How an op list becomes views (the op list is replayed on core widgets first, as
VOpDriver does, and the final state is read back):

| Final core state | View |
|---|---|
| regular widget with `ct` | `ContentView` (a real `View`; onMeasure is 6.1, `getBaseline()` is BL) |
| regular widget without `ct` | `ContentView` kind `none` (plain `View.onMeasure`) |
| behaviour F/W/P/M | `layout_width` = raw `mWidth` / `WRAP_CONTENT` / `MATCH_PARENT` / `0` with `matchConstraintDefault*`, min, max, percent from the core fields (a WRAP default on M becomes Android's `constrainedWidth`) |
| `mLeft.mTarget` etc. | `leftToLeft` / `leftToRight` / ... (target `root` is `PARENT_ID`), `leftMargin` = raw `mMargin`, `goneLeftMargin` = raw `mGoneMargin`; baseline: `baselineToBaseline/Top/Bottom`, `baselineMargin`, `goneBaselineMargin` |
| center link from `cc` | `circleConstraint`, `circleRadius` (`mMargin`), `circleAngle` |
| biases, ratio, chain styles, weights, visibility | `horizontalBias`, `verticalBias`, `dimensionRatio` (`"W,"`/`"H,"`/`""` + `Float.toString(ratio)`), `horizontal/verticalChainStyle`, `horizontal/verticalWeight`, `setVisibility` |
| Guideline | view `Guideline`, `orientation`, `guideBegin/End/Percent`, `guidelineUseRtl = false` (the ops already hold the resolved value) |
| Barrier | view `Barrier`, `setType`, `setMargin`, `setAllowsGoneWidget`, `setReferencedIds`; `WRAP_CONTENT` params |
| Flow (`fl` and its ops) | view `Flow` with the same setters; its own params as a regular widget |
| container | `ConstraintLayout` (`setOptimizationLevel`: `-Drobo.level`, default 257), `setLayoutDirection(RTL)` for `rtl`, `cpad` `setPadding`, `cmin`/`cmax` `setMinWidth/Height`/`setMaxWidth/Height`; specs from `cspec`, else FIXED `E(cw)` and WRAP `U(0)` (4.2) |

UNMAPPED reasons: `nocontent` (no `ct` op: a core-path list), `fixed<n>` (a FIXED size
of 0 or less: `layout_width = 0` is MATCH_CONSTRAINT in Android), `circle+links`
(Android applies only the circle), `childmin` (`mw`/`mh` on a child), `inplace` (`L`,
`ipr`, `iprest` without `-Drobo.inplace`), `op:rm`, `flowpad` (Flow start/end padding:
no view setter), `flowset:<p>`, `flowrtl`, `center`, `link`, `dangling`, `negbias`,
`negratio`, `helperlink`, `guidelinevis`, `barriervis`, `op:<op>` for anything else.

Checks at other levels (T2-inplace, 50,000 sequences, `-Drobo.inplace=1`,
`-Drobo.level` 0, 64, 192, 256, 257, 321, 449): the `.fresh` builds equal Java's
T2-fresh at the same level (VOpDriver v2, view path) on every sequence at every level.
In place, the live views differ from their own fresh build on 187, 429, 577, 187, 0,
239 and 386 sequences: at the levels without OPTIMIZATION_DIRECT, `reset()` keeps a
widget's resolved flags, so a barrier that `Barrier.allSolved` resolves keeps its
`mResolvedHorizontal` (or vertical) set while `reset()` zeroes its position, and
`setFinalHorizontal` then leaves it at 0; at the GRAPH levels the dependency graph's
runs and nodes also keep state from the last graph, and 41 (64, 321) and 160 (192, 449)
sequences throw a NullPointerException in the graph during an in-place measure. At 257
in place equals fresh on every sequence. The dirty second layout (`-Drobo.twice=dirty`)
of a fresh T2-fresh build differs from the first on 193 layouts at level 0 and on none
at 257. The engine through `ViewHost` keeps the same state and gives the live views'
layouts on every sequence at every level, throws included (section 21).

## 11. Flutter harness: ContentModelBox, ftree, FL runner

- Package `cl_fl_harness`: `packages/flutter_constraint_layout/tool/parity/fl_harness/`
  in the repository, set up outside it by `setup.sh` (in `$CL_FL`, with path
  dependencies on a checkout's `flutter_constraint_layout` and `constraint_engine`; a
  `dependency_overrides` entry resolves the engine outside the workspace).
- `lib/content_model_box.dart`: `ContentModelBox`, a leaf `RenderBox` whose layout,
  dry layout, intrinsics and baselines follow 6.2 exactly (intrinsic width W, none 0;
  intrinsic height H for box, `natH(width)` for text, none 0; baseline BL, none for
  -1 or kind none). `test/content_model_box_test.dart` checks it against the shared
  `dart/content.dart` on every constraint kind.
- `lib/src/fmodel.dart` (pure Dart) + `lib/ftree.dart` (widgets): a corpus line is
  replayed on engine widgets and the final state is read back as a real
  `ConstraintLayout` tree: absolute `left/right/top/bottom/baseline` links (never
  start/end, so the bias is used as given; an unset gone margin is 0, an explicit gone
  margin of 0 is unmapped), `cc` a `CircularLink`, `ra N r -1` `aspectRatio: r`, `hm/vm`
  a `Dimension` (`matchConstraint`/`spread`/`constrainedWrap`/`percent`, min/max), `v`
  `visibility`, guidelines (an RTL vertical one un-mirrored, since the adapter mirrors
  it again), barriers with absolute edges, Flows as `ConstraintFlow`, `ct` a
  `ContentModelBox`. The container: tight on a FIXED axis, `0..infinity` on a WRAP
  axis (U(0)), in a `Directionality` from `rtl`/`ltr`, each layout under a new key.
- Unmapped (skipped and counted per reason): `ratioside`, `cspec` other than the
  default, `cpad`, `cmin`, `cmax`, `childmin`, `inplace` (unless the in-place mode),
  `minmax-nonmc`, `mcstyle-nonmc`, `gone0`, `flowalign` (horizontal align 3),
  `flowwrap` (3), `flowpad` (per side), `flowset`, `rtlpct` (no exact round trip).
- `ftree select <perGen> <FL.txt> [--gens a,b] <corpus>...` writes `FL.txt` (section 1
  lines, unchanged), `.unmapped` and `.sum`; `ftree check <corpus>...` counts
  (`bin/ftree.dart`; `gates/corpora.sh` compiles it).
- Runner: `[FL_LEVEL=<n>] run_fl.sh <FL.txt> <out.txt> [tag] [dry] [inplace] [replay]
  [transcript]` (two shards under `flutter test --concurrency=2`, merged back into input
  order; `FL_LEVEL`, default 257, is Android's optimization level of every layout, each
  bit as its `OptimizationLevel` flag, and the transcript lines read `T<n>`).
  Output: section 1 lines, `id \t features \t fl-<tag> \t status \t geometry \t ops`.
  Geometry: `root` is the `RenderConstraintLayout` size; each child in child order
  prints its offset and size; a gone child prints `gone, w x h`; non-integral values
  print as decimals. Status `ok`, `UNMAPPED:<r>` or `EXC:<first line of the Flutter
  error>`. `dry` adds `<out>.dry` (`id \t equal|DIFF \t dry \t real`: `getDryLayout`
  against the laid-out size). `inplace` pumps every state of a T-inplace list (cut
  before each `L`) into the same `ConstraintLayout`, so the adapter's in-place path
  runs, and adds `<out>.fresh` (a fresh build of the final state). `replay` and
  `transcript`: 19.1.
- Corpus FL (`gates/corpora.sh FL`): 3,000 mappable lines from each of VR-fflist,
  VR-ffrtl, VR-ffsettings, VR-ffchat, VR-fftoolbar, VR-rscform, VR-rsccards,
  VR-rscnest, VR-fnrtl, VR-nbrscnest, T-measure, T-wrap, T-oddbias, T-chain, T-gone,
  T-depsorder, T-virtual, T-circle, T-ratio, T-pctmin (60,000).

## 12. Adapter benchmarks

`test/bench_form_test.dart` and `test/bench_list_test.dart` in the harness package
(`flutter test --concurrency=2` in `$CL_FL`; debug JIT like the repository's
`flutter_layout_benchmark.dart`). Each prints `BENCH <name> passes=<n> p50=<ms>
p90=<ms> min=<ms> mean=<ms> ...counts` and writes it to `--dart-define=BENCH_OUT=<file>`
(default `bench_<name>.txt` in `$CL_FL`). The time is `rootPipelineOwner.flushLayout()`
only (the build of the frame runs first, untimed). Child layouts are counted by a
`CountingProxy` around every child: calls to `layout()` and the `performLayout` runs they
lead to. `bench_form_test.dart` also reports `replayPasses/pass`, the layouts the adapter
replayed (`debugReplayPasses`).

- form: one ConstraintLayout of 87 children (40 labels baseline-aligned to 40
  match-constraint fields after a barrier, 4 error texts, a title, a button), 412
  wide, unbounded height; a keystroke changes field 20's text (single line).
- list: 50 rows, each its own ConstraintLayout of 6 children (avatar, title and
  subtitle in constrained wrap, a value on the title's baseline, chevron, divider), in
  a Column under an unbounded height; the first layout of 50 fresh rows.

## 13. Released 2.2.1 against the pinned 2.2.0-alpha04

Sources: the pin (`$CL_UPSTREAM/constraintlayout/constraintlayout/src/main/java`,
2.2.0-alpha04, minSdk 14; `$CL_UPSTREAM/constraintlayout/core/src/main/java`,
1.1.0-alpha04) against `constraintlayout:2.2.1` (AAR,
sources jar, POM; minSdk 21; depends on core 1.1.1, appcompat 1.2.0, core 1.3.2,
profileinstaller 1.4.0) and `constraintlayout-core:1.1.1` (jar, sources), from
dl.google.com, SHA-1 checked (`view/fetch.sh` downloads them into `$CL_ROBO`; unzip the
sources jars to compare). Raw `diff -r`, then a code-only diff with comments and blank
lines removed (`view/tools/jstrip.py`).

**No pixel-relevant change on the view path at API 17 or later.**

View layer, files whose code differs:

| File | Code change | Pixels |
|---|---|---|
| `ConstraintLayout.java` | every `SDK_INT < JELLY_BEAN_MR1` branch removed: pre-17 guideline values, pre-17 link and bias resolution (`leftToLeft`... with a start/end fallback), pre-17 `paddingX`, `isRtl()` false below 17, pre-17 `getPaddingWidth()`, the guarded `setMarginStart/End` in the `LayoutParams` copy constructor, the guard around `super.resolveLayoutDirection` | none at API 17+ |
| `Barrier.java` | pre-17 `updateType` branch (START as LEFT, END as RIGHT) removed | none at API 17+ |
| `helper/widget/Flow.java` | `paddingStart/End` attributes read without the API 17 guard | none at API 17+ |
| `helper/widget/Grid.java` | `View.generateViewId()` without the guard | none (Grid is outside the contract) |
| `ConstraintSet.java` | guards removed; XML `layout_constrainedWidth/Height` in a ConstraintSet now map to `CONSTRAINED_WIDTH/HEIGHT` (were `LAYOUT_CONSTRAINT_WIDTH/HEIGHT`) | only ConstraintSets loaded from XML (MotionLayout, `ConstraintSet.load`); not a layout's own params; the adapter has no ConstraintSet |
| `ConstraintProperties.java` | guards removed | none at API 17+ |
| `Carousel.java`, `motion/widget/{KeyFrames, KeyPosition, MotionController, MotionLayout, MotionPaths}.java` | motion | not on the ConstraintLayout path |
| `LogJson.java` | only in the pin (debug helper) | none |

`Guideline.java` differs only in Javadoc. Core: every file of `widgets/`,
`widgets/analyzer/` and the solver except `LinearSystem.java` is byte-identical.

| Core file | Change | Pixels |
|---|---|---|
| `LinearSystem.java` | `private static int sPoolSize` became the instance field `mPoolSize` (5 lines) | none; fixes an `ArrayIndexOutOfBoundsException` when a system created before another one grew the static size past 1000 then holds more than 1000 pool variables (two live containers interleaving large solves) |
| `utils/GridCore.java` | flags as an int bit set (`SUB_GRID_BY_COL_ROW = 1`, `SPANS_RESPECT_WIDGET_ORDER = 2`, `setFlags(int)`); weights with too few values padded with 1, bad values 1 (the pin returned null on a count mismatch); spans sorted by index | Grid only (outside the contract: Grid has no Android oracle) |
| `motion/*`, `parser/*`, `state/*` | Compose and motion | not on the view path |

Checked empirically: RoboOracle with core 1.1.1 (`rel`) gives byte-identical output to
the pinned core on a 20,000-layout sample of VR and T.

## 15. The Dart tools

Sources in `dart/` (the harness), `compare/` (Python comparators) and `bench/`; build
the Dart tools from `packages/constraint_engine` (README.md, step 2). With `--packages`
pointing at another checkout's `.dart_tool/package_config.json`, they build against that
checkout's engine instead.

```
vfuzz.exe <gen> <first> <count> <out> --path none|core<level>|view<level>
vfuzz.exe --corpus <in.txt> <out> --path <p> [--direct D] [--transcript T] [--twice|--twice-links]
vfuzz.exe --list [R|VR|VR2|T|T2|A]   # generator names
vfuzz.exe --seeds <gen>              # the corpus's first seed and count for <gen>
[VFUZZ=<exe>] dart/vrun.sh <corpus> <path> <outdir> [gen ...]   # every generator of a corpus
vtrace.exe <corpus> <out.trace> --path <p> [--level 257] [--max N]   # build with -Dcl.trace=true
gclass.exe <gin.tsv> <out.tsv>       # 20.1
python3 -I compare/vcompare.py <A> <B> --level 257 --exclude ND,HANG,SOE,JEXC [--map T-inplace=T-fresh]
         [--nd jbatch3.out] [--mismatch-ids F] [--mismatch-in F] [--show N] [--status]
         [--helpers full|pos|ignore] [--strict] [--quiet] [--skip GEN ...]
python3 -I compare/keepbl.py <in> <out>   # 21: an in-place corpus without its bl N 0 and hbl N 0 ops
python3 -I compare/tracediff.py <dart.trace> <java.trace> [--kinds ..] [--ignore ..] [--max N] [--ids-out F]
python3 -I compare/tcompare.py ...   # 17.3
python3 -I compare/dcompare.py ...   # 18.4
python3 -I compare/gclass_in.py ...  # 20.1
python3 -I compare/guardcheck.py <out.guard> <java> <levels> <level> [--map A=B]   # 18.7
python3 -I compare/exc_classify.py ...   # 18.9
python3 -I compare/helper_only.py <dart.isg.gz> <corpus.in> <java> <levels> <level> <ids> [--map A=B]
python3 -I dart/vstats.py <java-with-P-fields> [--levels 257] [--by gen]   # 8.3 statistics
```

`vfuzz --corpus` replays a saved corpus file (id from the first field, ops from the last,
streamed), so any corpus, VOpDriver input or id subset runs on a Dart path without
regenerating it. `vcompare.py` reads vfuzz lines (any `core<N>`, `view<N>` or `fl-<tag>`
path), Java result lines and RoboOracle lines; numbers may be non-integral (Flutter), an
`UNMAPPED:<r>` status on either side is excluded, and a line without geometry takes its
status from field 4. `--skip GEN` (also `tcompare.py`'s) drops a generator's layouts from
both inputs before anything is compared and reports how many: the gates pass `--skip
T2-inplace` wherever Java's fresh builds are not Android's in-place reference (level 0 and
the GRAPH levels; section 21). `tracediff.py --ids-out FILE` writes, per diverging layout, its id,
level, build, first diverging event and kinds.

The Dart `ContentMeasurer` (`dart/content.dart`) is the 6.1 spec form:
`measureContent(widget, widthSpec, heightSpec) -> (width, height, baseline)`, a widget
without `ct` measuring as `none`. Its caller, the engine's `ViewMeasurer`, applies
`View.getMeasuredWidth`'s `& 0x00FFFFFF`, as 8.6 does.

## 16. The corpora VR2 and T2, the trace sample and the exception repros

- `dart/temit.dart` `emitT(..., orientFirst:)`, `dart/tgens.dart` `t2Generators` and
  `dart/corpora.dart` `vr2Generators` emit VR2 and T2: every guideline is emitted
  `g N; go N O; add N`, oriented when it is created as Android's `onViewAdded` and the
  adapter (`Guideline()..setOrientation(...)`) do; the config loop keeps its `go` (a
  no-op, as the adapter's `_applyHelperConfig`). R, VR and T are unchanged.
- **Corpus text and the engine.** respec (R's `rsc*`/`nbrsc*` labels, and so VR and VR2)
  replays the raw ops on the engine and prints the floats it reads back. The corpus
  files the gates first ran on were made by the earlier graph-first engine, which held
  them as doubles (`vx card 0.3`); this engine holds them in binary32 and prints the
  value's exact decimal (`vx card 0.30000001192092896`): generated from this engine, R
  keeps its 319,827 ids in order, and 34,122 op lists (in `rsccards`, `rscnest`,
  `nbrsccards` and `nbrscnest`; VR and VR2 the same) differ in that spelling only.
  Both strings parse to the same binary32 value on both sides, so the layouts and
  every result are the same; only the op text differs.

| Corpus | Layouts | Against VR and T |
|---|---|---|
| VR2 | 319,827 | equal to VR once the creation `go` ops are dropped; op lists change in VR2-ffrtl (6,814) and VR2-fnrtl (7,068) only |
| T2 | 470,000 | equal to T once the creation `go` ops are dropped; op lists change in T2-wrap, T2-oddbias, T2-pct, T2-inplace, T2-fresh |

Checks: `view/tools/glate.py` finds 0 links to a not-yet-oriented guideline in all 32
generators. RoboOracle (real views) against J257: VR2 319,827 compared, 0 differ; T2
412,770 compared, 0 differ (UNMAPPED 57,230: 50,000 `inplace`, 7,230 `fixed0`); every
T2-inplace sequence applied in place to live views equals J257 on T2-fresh (50,000 of
50,000), so T2-fresh is the fresh build of T2-inplace's final state. ND (jbatch3.sh at
257,0 on every layout where the earlier graph-first engine differed from J257 or J0): VR2 0; T2
9, the ids of `data/t2core_nd.ids` (T2-fresh 500001444, 500018508, 500035177,
500036432, 500042421; T2-inplace 500018508, 500035177, 500036432, 500042421). Use
`--nd` at 257 only (`vcompare --nd` excludes an id at every level).

**T2core** is T2 without T2-virtual (Flow), T2-atmost (layout-view ops), T2-inplace
(`L`) and those ND ids: the T2 lists the core path runs (Java's `-Dpath=core`, which
ignores `ct`), 379,995 layouts.

**The trace sample** (`data/trace_sample.ids`, 2,000 layouts): 1,000 from R (all 16
labels) and 1,000 from T2 (chain 200, ratio 150, circle 150, pct 120, pctmin 120,
oddbias 100, wrap 40, fresh 40, crossed 20, negedge 20, gone 15, measure 15, depsorder
10). Tags: chain 664, weight 340, ratio 382, MC percent 845, guideline percent 374,
circle 150, odd bias 1,758. Eligible only: Java's level-0 run with one layout() pass, no
Flow, no layout-view op, no mid-list `L`, no ND; half of each side was drawn from the
layouts the earlier graph-first engine's solver laid out differently from Java. Run on the core
path with the echo measurer (the T2 part too: Java's core path ignores `ct`).

**The exception repros** (`data/exc0.ids`, 242 A layouts): every A layout that prints,
throws, hangs or overflows on either side at level 0 or 257, in the earlier graph-first engine or
on Java.

## 17. The paths at level 0, and transcripts

### 17.1 The paths core0 and view0

- **`core0`** is OpDriver's core path at level 0: a `ConstraintWidgetContainer.rect(0, 0, W,
  H)` named `root`, the echo measurer (`EchoMeasurer` in `vpaths_future.dart`, a copy
  of the engine's `test/support/echo_measurer.dart`, VOpDriver's `Echo`), and for every
  `L` op and the final measure `setMeasurer`, `setOptimizationLevel(0)` and
  `measure(0, wrapW ? AT_MOST : EXACTLY, root.getWidth(), wrapH ? AT_MOST : EXACTLY,
  root.getHeight(), 0, 0, 0, 0)`, the wrap flags read from the container at that moment.
  Geometry with OpDriver's core rule (only a barrier is exempt from the `gone` form),
  also for op lists with `ct` ops (T2core): Java's `-Dpath=core`.
- **`view0`** is VOpDriver's view path at level 0 (8.6): one `ViewHost` per layout
  (`optimizationLevel = 0`) with a `ViewMeasurer` whose `measureContent` is `content.dart`'s
  `ContentMeasurer` (6.1; `ContentViewMeasurer` in `vpaths_future.dart`). Before every
  measure the host takes padding, min and max from `viewOf(root)` (`cpad`, `cmin`, `cmax`
  replayed so far); the specs are `cspec`'s, else `E(root.getWidth())` for a FIXED axis and
  `U(0)` for a WRAP axis, read from the container at that measure (`VOpDriver.specsOf`).
  `ViewHost` itself makes guidelines and barriers GONE, marks VirtualLayout members, rebuilds
  the dependents and takes `mNeedsBaseline` from the baseline links; `hbl` ops still set
  `hasBaseline`, as in Java. Geometry with the view rule (8.2) and the root as the layout
  view's measured size (`host.getMeasuredWidth()`, `getMeasuredHeight()`); a child's
  `(x, y)` includes the padding (`getX()`, `getY()`).
- **Dirty path.** `ViewHost.measure` resets every child's measure state first as
  `reset()` does (keeping what `reset()` keeps: the resolved flags, a guideline's and a
  barrier's own flag, `hasBaseline`, the graph's runs and nodes), so a mid-list `L` and
  the final measure both run Android's dirty-hierarchy path, as the live views of the
  RoboOracle's `-Drobo.inplace=1` do. Java's mid-list `L` is the non-dirty re-measure
  (8.6), so T2-inplace is compared with the live views in place (section 21); at 257,
  where they equal the fresh builds, also with T2-fresh (`--map T2-inplace=T2-fresh`), for
  frames and transcripts alike. At level 0 and the GRAPH levels the gates leave it out of
  the comparison with Java (`--skip T2-inplace`): Android's live views lay 187 of its
  sequences out unlike their fresh build at 0 (429, 577, 239 and 386 at 64, 192, 321 and
  449).
- **Status.** As VOpDriver reports it: `ok-printed` when the final measure printed a caught
  exception (an `L` op's output is not counted: VOpDriver captures and drops it), `EXC:...`
  when anything threw (vpaths.dart's `guarded`), else `ok`.
- `child layouts` in the vfuzz summary counts the view measurer's `measure` calls on a
  view path, and 0 on a core path.
- `vtrace --path core0` works through the same table (`pathNamed`): trace parity against
  TraceJava at level 0 with `-Dpath=core`.

### 17.2 The transcript side file

`vfuzz ... --path view0 --transcript <side.txt>` writes one line per layout:

```
id \t T0 <entry> <entry> ...        (T0 - when the last measure made no request)
```

The entries are 8.5's grammar, recorded by the engine's `ViewMeasurer.transcript`
during each layout's last measure (`ViewHost.measure` clears it in `beginMeasure`), which
is what VOpDriver's T field holds. `<src>` comes from the Measure's identity: `M` or `R`
for BasicMeasure's own Measure (`M` under SELF_DIMENSIONS, which only `measureChildren`
passes; `R` under TRY_GIVEN or USE_GIVEN, the re-measure loop), `F` for a VirtualLayout
child's `mMeasure`, `P` for another Measure while the container is in pass 0 before its
solver loop, `D` for Direct's static Measure, `X` otherwise. At level 0 only `M`, `R`
and `F` occur. `--transcript` with a core path is a usage error (exit 2).

BasicMeasure reuses its one Measure across `ViewHost.measure` calls, as Android's layout
widget does across `onMeasure`, and the GONE short cut leaves `measuredHasBaseline` as the
previous request set it, so an in-place sequence's GONE request can carry the last
measure's flag where a fresh build has a new Measure: at 257, 4,815 T2-inplace layouts
differ from their T2-fresh build only there (`g:0,0,0,10` where the fresh build has
`g:0,0,0,00`; 4,807 at level 0, before the level-0 gate left T2-inplace out). No frame
changes. Java keeps the same history; `tcompare.py --history` reports these layouts
separately (18.5).

### 17.3 tcompare.py

```
python3 -I compare/tcompare.py <A> <B> [--level 0] [--exclude ND,HANG,SOE,JEXC]
        [--map T2-inplace=T2-fresh] [--nd FILE ...] [--show N] [--mismatch-ids FILE]
        [--order block|exact] [--history] [--quiet]
```

Each input is a side file (17.2) or a VOpDriver result file run with `-Dtranscript` (its
`T<level>` field; the T fields also name the levels, which locate the geometry column for
the exclusions). Two layouts are equal when their entry lists are identical. A differing
layout is classed by its first differing entry and, in it, the first differing field
(`src`, `name`, `strategy`, `behaviours`, `dims`, `detail`, `answer`), or `count` when one
list is a prefix of the other; the report gives the counts per generator, the first
differing fields and `--show N` examples. Exclusions follow vcompare.py, on the Java side:
ND (line status, or `--nd`), HANG, SOE (the level's geometry is `!SO`), JEXC (`EXC:` line
or geometry status). Exit status 0 when nothing differs, 1 otherwise, 2 on usage.

## 18. The paths at 257, Direct dumps, determinism and the guard

### 18.1 Building

The Direct dump needs the engine's trace switch, so build vfuzz and vtrace with
`-Dcl.trace=true` (vfuzz never sets the trace-line sink, so the cost is the
`if (kSolverTrace)` tests); README.md, step 2. Both import
`package:constraint_engine/src/analyzer/direct.dart` and `src/debug/solver_trace.dart`
(`SolverTrace.directSink`).

### 18.2 The paths core257 and view257

`core257` and `view257` are `core0` and `view0` (17.1) at level 257: the container's and
the host's optimization level is 257, so pass 0 of every measure runs Direct and the
post-Direct measures. `vtrace --path core257 --level 257` traces the core path at 257
(TraceJava's `-Dpath=core` at 257).

### 18.3 `--direct` and the Dart Direct dump

`vfuzz ... --path <p> --direct <side.txt>` writes one line per layout,
`id \t D<level> <entries>`, or `D<level> -` when the last measure made no dump (always at
a level without the DIRECT bit, such as 0 or 64). A build without `-Dcl.trace=true` is a
usage error (exit 2).

- **Where.** The engine hands the root container to `SolverTrace.directSink` in
  `layout()`, as the first statement of the solver loop's `try`, before
  `mSystem.reset()`, when `kSolverTrace && getParent() == null && mPass == 0 &&
  countSolve == 1 && optimizeFor(OPTIMIZATION_DIRECT)`: DirectProbe's point (`onReset`
  at pass 0, iteration 1). Direct and the post-Direct measures have run, nothing is in
  the solver.
- **What.** `directDumpOf(root)` in `vpaths_future.dart` is `DirectProbe.dumpDirect`
  (8.4) byte for byte: per child in `mChildren` order, `name:g<orientation>:<value>` for
  a guideline (its `getGuidelineAnchor()`), `name:b<type>:<rh><rv>:<L>,<T>,<R>,<B>` for a
  barrier, and `name:<rh><rv>:<L>,<T>,<R>,<B>,<S>:<mWidth>x<mHeight>:<baseline><+|->:<m|-><H|-><V|->`
  for any other widget, Flows included. An anchor prints its final value or `_`, a null
  name `null`.
- **When.** Each path clears the stored dump before every measure (each `L` op and the
  final one), as VOpDriver clears its probe, so the side file describes the last
  measure. `--twice` keeps the first final measure's dump.

### 18.4 dcompare.py

```
python3 -I compare/dcompare.py <A> <B> [--level 257] [--exclude ND,HANG,SOE,JEXC]
        [--map T2-inplace=T2-fresh] [--nd FILE ...] [--show N] [--mismatch-ids FILE] [--quiet]
```

Each input is a `--direct` side file or a VOpDriver result file run with `-Ddirect` (its
`D<level>` field). Two layouts are equal when their entry lists are identical. A
differing layout is classed by its first differing entry and, in it, the first differing
field: `name`, `kind` (`g<o>`, `b<t>` or a widget), `rh`, `rv`, `L`, `T`, `R`, `B`, `S`,
`value` (a guideline's), `size`, `baseline`, `measured`, `hpass`, `vpass`; `count` when
one list is a prefix of the other, `dump` when only one side made a dump. The report also
counts the kind of the first differing entry on the B side. Exclusions as tcompare's
(17.3), judged on the Java side. Exit 0 when nothing differs, 1 otherwise, 2 on usage.

### 18.5 Transcripts at 257

- **Sources.** `ViewMeasurer`'s transcript names a request by its `Measure`, in
  DirectProbe's order: `D` for `Direct.sMeasure` (Direct's last pass), `M` and `R` for
  BasicMeasure's own Measure, `F` for a VirtualLayout's, `P` for a new Measure in pass 0
  before the solver loop (Direct's solving passes and the post-Direct measures), `X`
  otherwise.
- **Side file.** `--transcript` on `view257` writes `T257` lines (17.2's format).
- **Rule.** `tcompare.py --level 257` compares with `--order block` by default: the
  entries of pass 0's Direct block, from the first `P` or `D` entry to the last one,
  with the `F` entries right before the first one (nested in it), compare as a
  multiset; the entries before and after compare in order. The reasons: at
  `-XX:hashCode=2` the oracle iterates a dependents set in insertion order only up to 10
  entries (the 11th treeifies the bin and moves the tree root first), and Android's own
  order there is the identity-hash order, random per launch. Layouts equal only under
  the rule are reported per generator as `absorbed`. `--order exact` compares every
  entry in order (the default at other levels).
- **History.** `--history` counts a layout whose lists differ only in the hasBaseline
  flag of GONE answers (detail `g`) or cache-hit answers (detail `c`) as `history`, per
  generator, instead of DIFFER. Both answers leave the flag as the previous request set
  it in BasicMeasure's reused Measure (17.2); at 257 CACHE_MEASURES adds the cache hits.
  Use it on T2 at 257 with `--map T2-inplace=T2-fresh`.

### 18.6 `--twice`

`vfuzz ... --path view<level> --twice` measures each layout a second time in the same
container, with the same host, measurer and specs, after re-applying every FIXED size the
op list configured (the `w` op's size, replaced by later `sw` and `sh` ops; only on an
axis whose behaviour is FIXED), as Android's `setChildrenConstraints` re-applies layout
params and as ViewHost leaves to its caller (`resetMeasureState` keeps FIXED sizes, which
`setFrame` may have widened). A layout whose status or geometry changes is written to
`<out>.twice` as `id \t class \t first \t second`, and the summary counts them per class:

- `vl-links`: the first measure changed the own links of a VirtualLayout child (its
  anchors' targets, margins or gone margins, compared with the state the op list left
  before the final measure). Upstream's Flow does this: in a vertical Flow laid out right
  to left with two or more columns, the last column's `createConstraints` connects
  `mRight.mOwner.mLeft` to the column's widest widget (Flow.java 644-647), and for the
  last column `mRight` is the Flow's own right anchor, so the Flow's own left anchor is
  re-linked. ViewHost resets the members' anchors before each measure
  (`rebuildViewDependents` step 1) but not the Flow's own, which Android resets with
  every child on a dirty measure and connects again from the layout params.
- `other`: anything else.

`--twice-links` (implies `--twice`) also puts every VirtualLayout child's own links
back, before the second measure, to what the op list left before the final measure, as
Android's layout params would (and as the adapter does). The transcript and the dump in
the side files are the first final measure's.

On T2 at 257, `--twice-links` leaves 29 layouts whose second layout differs from the
first (class `other` 20, `vl-links` 9). Each is history that upstream's core keeps from
one measure to the next and that Android's dirty path does not undo:

- the Flow's state from its previous measure: its chain list, which `Flow.addToSolver`
  reads in pass 0 before the Flow is measured again (in a fresh build the list is empty
  there), and its reused `mMeasure`: 27 T2-virtual layouts, all match-constraint x
  match-constraint Flows;
- solver variables of anchors that the last iteration did not register keep a stale id,
  which `createObjectVariable` does not reset when another variable holds that index:
  T2-chain:500034267 and 500040012 (the second measure prints a caught
  NullPointerException from `updateFromSystem`).

Android's own dirty second layout (DirtyTwice, 19.2) differs from its first on exactly
these: 28 layouts give a second layout, which the port equals byte for byte on all 28;
on T2-chain:500040012 Java's second layout never returns (HANG). VR2: 0 on both sides.

At level 0 a barrier that `Barrier.allSolved` resolved keeps its resolved flag into the
next measure (`reset()` keeps it, and nothing without `OPTIMIZATION_DIRECT` clears it), so
it stays at 0 there: `--twice-links` at `view0` leaves 6,469 VR2 layouts and 1,239 T2
layouts (T2-inplace aside; class `other` 1,223, `vl-links` 16) whose second layout
differs from the first, and DirtyTwice at level 0 gives the same second layout on every
one. `gates/corpus_gates.sh` runs the check at each level of `$TWICE_LEVELS` (default
`257 0`), T2-inplace left out (DirtyTwice's first layout of an in-place sequence is
VOpDriver's non-dirty one; section 21 compares those second layouts with the live
views'); its `twicefull` step runs DirtyTwice on every layout instead and compares both
layouts of every one: at 0, VR2 319,827 and T2 419,999 compared (1 Java HANG), 0 differ,
first or second.

### 18.7 Guard trips

Every path writes `<out>.guard`, `id \t trips`, for the layouts during which
`Direct.guardTrips` grew (any measure of the layout, `--twice` included), and the summary
prints the trips and the layouts. `compare/guardcheck.py <out>.guard <java> <levels>
<level>` checks that every such layout is a Java SO at the level.

### 18.8 Java runs

`gates/java_refs.sh` makes every Java reference the gates read (its header lists the
files, inputs and flags): the primary runs at 257 and 0 with `-Dprobe`, the Direct dumps
(`-Ddirect`) and transcripts (`-Dtranscript`) at 257, the core path for T2core
(`-Dpath=core`), TraceJava on the trace sample and on the exception repros, the FL
references (with DirtyTwice), and the GRAPH levels. Statuses at 257: every R, VR2 and
T2core layout `ok`; T2 469,999 `ok` and one `ok-printed`. On the 242 repros: 110 SO, 111
EXC (99 `getAnchor(...)` null in `Barrier.allSolved`, 12 a null `mTarget` in the
centering and spread solvers), 11 ok-printed, 7 HANG, 1 OutOfMemoryError, 2 ok.

### 18.9 Exception classification

`gates/exc.sh <0|257> <outdir> [full]` runs `compare/exc_classify.py` on the repros, and
with `full` on all of A: classes i (both print; with the Dart trace, `same` when the
traces agree through Java's first X, in any pass), ii (Dart prints or throws, Java does
not), iv (Java prints, Dart does not), iii (Java HANG, SO or JEXC, with the Dart status
alongside), ND (257 only); plus `guard-not-SO` for a guard trip on a layout Java
finishes. Target: no layout in ii or iv, every layout in i `same` with equal frames.

### 18.11 Engine-side test tooling

`packages/constraint_engine/test/support/op_replay.dart` ports this harness's op
interpreter (`ops.dart`), the geometry and `guarded` of `vpaths.dart`, the spec form of
`content.dart` and `runCore`/`runView`: `replayCore(ops, level:)` and `replayView(ops,
level:)` return `({String status, String geometry})` in vfuzz's format. Checked against
Java J0 on 12,000 corpus layouts (R, VR2, T2, A): 0 differ. `test/parity/` holds the
2,000-layout corpus with Java's strings, the 560-layout corpus at the GRAPH levels, their
tests and their README (selection scripts `select_corpus.py` and
`select_graph_corpus.py`; `--export` and `--check` re-run the Java side of the first).

## 19. The Flutter runner's modes and DirtyTwice

### 19.1 FL runner modes `replay` and `transcript`

`run_fl.sh <FL.txt> <out> [tag] [dry] [inplace] [replay] [transcript]` (section 11; an
unknown mode is a usage error, exit 2). `lib/fl_runner.dart` reads `FL_REPLAY` and
`FL_TRANSCRIPT`.

- **`replay`.** run_fl.sh passes `--dart-define=FL_REPLAY=true` and
  `--dart-define=cl.verifyReplay=true`. Each layout is pumped once (the line of `<out>`),
  then laid out four more times in the same `ConstraintLayout`
  (`RenderConstraintLayout.markNeedsLayout`, `pump(null, EnginePhase.layout)`): the second
  layout confirms the first or differs from it as Android's own second layout can, the
  third confirms the second, the fourth and fifth replay. Under `cl.verifyReplay` every
  replay also runs the full pipeline and compares. Two files:
  - `<out>.replay`: `id \t same|DIFF \t replays N \t mismatches M \t engine E \t second
    same|DIFF`, followed by the first geometry and the four later ones when any of them
    differs from the first. `same` means all five geometries are equal; `replays` is
    `debugReplayPasses` (replay hits), `mismatches` `debugReplayMismatches` (target 0),
    `engine` `debugEnginePasses` (a verified replay counts here too).
  - `<out>.second`: section 1 lines of the second layout, path `fl-<tag>-second` (status
    `ok`, or `EXC:<first line>` when Flutter reported an error during that layout), for
    the comparison with Android's dirty second layout (19.2).
- **`transcript`.** `RenderConstraintLayout.debugRecordTranscripts` is set for the run, so
  every model build gives its measurer a request transcript; `<out>.T` holds, per layout,
  `id \t T257 <entries>` (`T257 -` for none): the requests of the layout's last engine run
  in 8.5's grammar, which is 17.2's side-file format, so `tcompare.py --level 257` compares
  it with a VOpDriver `-Dtranscript` run.

### 19.2 DirtyTwice: Android's dirty second layout (`java/dirty/`)

Compiled into its own directory (`$CL_DIRTY`) against the pinned core and the oracle.

- `java/dirty/DirtyTwice.java`; `java/dirty/build_dirty.sh` (atomic as `build.sh`);
  `java/dirty/jdirty.sh <in> <out> [level] [ids] [-D...]` (all lines of `<in>` when
  `ids` is `-` or absent, else those listed; `-XX:hashCode=2` and the other flags of 8.1;
  restarts after a HANG; a heavy step); `java/dirty/dirty_split.py <out>` writes
  `<out>.first.java` and `<out>.second.java` (`id \t ok \t geometry`, Java result lines
  of section 2) and prints how many second layouts differ from the first.
- **What it emulates.** For each op list: VOpDriver's own fresh build and measure (the
  first result, equal to `FL.J257.java` on all of FL), then what
  `ConstraintLayout.setChildrenConstraints` does on a dirty hierarchy (CL 1249-1351):
  `reset()` on every child widget, `removeAllChildren()`, `removeAllIds()` on every helper,
  then the op list's configuration replayed onto the same widget objects (creation ops
  reuse them, the content views keep their measured state, `L` ops are not replayed), and a
  second measure. Output `id \t first \t second` (two geometries of section 2), `id \t HANG`
  (20 s) or `id \t THREW <exception>`.
- **`-Dorient=fresh|kept`** (default `fresh`). With `fresh`, every guideline goes back to
  its constructor orientation (HORIZONTAL) before the replay, as the fresh build had it when
  it ran the op list. The VR and T corpora (and so FL) orient a guideline in child order,
  after an earlier sibling may already have linked to its left or right edge; the fresh
  build drops such a link (a horizontal guideline has no left or right anchor), so the
  replay drops it too and the second layout is that of the configuration the first layout
  had. Android's view layer orients a guideline before any link (`LayoutParams.validate`),
  and the Flutter trees ftree builds never have the link. `kept` keeps the first build's
  orientation, so those links succeed in the replay: on FL that changes 1,456 second
  layouts (T-wrap 1,022, VR-fnrtl 226, VR-ffrtl 208), every one a layout with a link into
  a guideline's left or right before the guideline's `go` op. VR2 and T2 orient every
  guideline at creation, where the two modes agree.
- **The reference.** A layout laid out again in the same container is compared with this
  second layout, not with the fresh build. On FL (`fresh`, level 257) Java's second layout
  differs from its first on 3 layouts, all T-virtual match-constraint x match-constraint
  Flows (500004830, 500006310, 500006666).

## 20. Any optimization level, bit identity and the GRAPH levels

### 20.1 Paths and tools

- **`core<level>` and `view<level>`** (`dart/vpaths_future.dart`): the paths of 17.1 at any
  optimization level from 0 to 2047, written without leading zeros; the container's and the
  host's optimization level is the path's level. The GRAPH levels are `core64`,
  `core321`, `view321` and the GRAPH_WRAP levels (128, 192, 385, 449). `--direct` works on
  every path (a level without the DIRECT bit, such as 64, always dumps `D<level> -`);
  `--transcript` and `--twice` on every view path.
- vfuzz and vtrace depend only on the engine's lib (`jfloat.dart`, `analyzer/direct.dart`
  for `Direct.guardTrips`, `debug/solver_trace.dart`).
- **`dart/gclass.dart`** and **`compare/gclass_in.py`**: the route and mechanism
  classification of a GRAPH-level difference. `gclass_in.py --dart A --java J --levels L
  --level l --solver S --solver-levels SL --solver-level sl --ids differ.ids --out gin.tsv
  [--map T2-inplace=T2-fresh]` writes `id, ops, X, J, JS` for the differing ids (X the port
  at the level, J Java at the level, JS Java's solver result at the level: J0 for 64 and
  192, J257 for 321, 449 and the view path; a mapped id takes the T2-fresh op list);
  `gclass <gin.tsv> <out.tsv>` prints the routes (`port=solver, Java graph`: X equals JS;
  `port graph, Java=solver`: J equals JS; `both graph`) and, per route, the layouts each
  mechanism is present in and the sole mechanism of.

### 20.2 Bit identity at 257 (`gates/ref_runs.sh`)

`ref_runs.sh <outdir> [steps]` runs, in order, R, A and T2core on core257 (with the
Direct dump), VR2 and T2 on view257 (dump and transcript), `trace` (vtrace core257 on the
trace sample), `FL` (the FL runner, tag `p5a`, with `dry`; the real adapter of the
checkout the harness resolves), `twice` (view257 `--twice-links` on VR2 and T2) and `FLr`
(the FL runner's `replay` mode). It keeps `<c>.<path>.isg.gz` (id, status, geometry), the
side files gzipped (`.D`, `.T`, `.dry`, `.twice`, `FLr.second.isg`, `FLr.fl.replay`, the
trace) and the `.guard` files, and writes `SHA256SUMS.content` (the uncompressed content of
each kept file, and of each full output file before it is cut) and `SHA256SUMS` (the `.gz`
files). The check: the same script on another build into a new directory, then `diff` of
the two `SHA256SUMS.content` files (target: identical). `.sum` files hold timings and are
not hashed. `FLr.fl.replay` also holds counters (replay hits, engine runs) that can change
without any frame changing; judge a difference there by its `same`/`DIFF` and `second`
fields and by `FLr.second.isg`. The FL tag `p5a` is kept because the full output files
carry it in their hashes.

The content hashes of the final engine, on the corpus files the gates ran on (the full
output files of R, VR2 and FL repeat the op text, which section 16 says can differ in
float spelling when the corpora are generated again; the `.isg`, `.D`, `.T` and trace
contents do not):

| Content | Lines | sha256 of the content | Check against Java (all 0) |
|---|---|---|---|
| `R.core257.isg` | 319,827 | `fe187f651e53...` | R.java J257: 0 differ; D dump vs R.J257d.java: 0 |
| `A.core257.isg` | 360,000 | `f1e5624d85a9...` | A.java J257, `--nd A.mism.nd`: 0 of 359,617 (ND 154, HANG 8, SOE 110, JEXC 111); guard trips 110 in 110 |
| `T2core.core257.isg` | 379,995 | `db018c8cd3e2...` | T2core.J257d.java: 0 of 379,995 |
| `VR2.view257.isg` | 319,827 | `2f981928eb00...` | VR2.java: 0; D: 0; transcripts 0 (6,006 absorbed) |
| `T2.view257.isg` | 470,000 | `36216432aa56...` | T2.java with the map and `--nd T2.mism.nd`: 0 of 469,990 (ND 10); D: 0; transcripts 0 (4,815 history) |
| `sample.core257.trace` | 820,054 | `aedd87a00eb0...` | tracediff vs sample.J257.trace: 2,000 of 2,000 identical |
| `FL.fl.isg` | 60,000 | `a824bdc9b172...` | FL.J257.java `--strict`: 0 of 60,000; dry: 60,000 equal |
| `T2.view257.twice` | 29 | `c853e9fb037f...` | 18.6 (other 20, vl-links 9); VR2: 0 lines |
| `FLr.second.isg` | 60,000 | `3cd3af6917a9...` | Java's dirty second layout (FL.dirty.java): 0 of 60,000; replay mismatches 0 |

### 20.3 Java references at the GRAPH levels

`gates/java_refs.sh graph`: R (core path) at `64,321` and `192,449`, T2core (`-Dpath=core`)
at the same, VR2 and T2 (view path) at `321` and `192,449`. Statuses: R ok everywhere;
T2core 379,827 ok and 168 JEXC at each level (a NullPointerException on `mDependencies`
in upstream's graph, a baseline link from a widget that had no baseline when the graph was
built); VR2 ok; T2 at 321 469,958 ok, 1 ok-printed and 41 exceptions, all T2-inplace
(Java's non-dirty mid-list re-measure; never compared: the gate leaves T2-inplace to the
in-place gate, section 21).

ND (`gates/nd.sh`): jbatch3.sh on the layouts that differ in a first gate run, against the
primary file; T2core on the core path through `JAVA_TOOL_OPTIONS=-Dpath=core`, T2's ids
mapped to T2-fresh. jbatch3's in-run repeated builds apply only at level 257, so at the
GRAPH levels ND means a difference between the JVM runs with different identity hashes.
Before the GRAPH levels were reconciled with upstream, 10,918 R, 27,984 T2core, 7,293 VR2
and 16,303 T2 layouts were checked this way: 0 ND in each.

### 20.4 The GRAPH-level gate (`gates/graph_gates.sh`)

`graph_gates.sh <outdir> [corpora] [levels]` runs core64, core321, core192 and core449 on
R and T2core and view321, view192 and view449 on VR2 and T2, compares each with Java at
the same level (vcompare, helpers full, then by position and ignored; ND, HANG, SOE and
JEXC excluded; T2 with `--skip T2-inplace`, whose in-place sequences the in-place gate
compares with Android's live views, section 21), classifies the differences (gclass)
and writes per corpus and level `<c>.<lv>.{cmp,pos,ignore,gclass}.txt`, `.ids`,
`.gclass.tsv`, the Dart output as `<c>.<path>.isg.gz`, and `summary.tsv`. Target: 0
differences: T2 at 321, 192 and 449, 0 of 420,000. With the earlier `--map
T2-inplace=T2-fresh`, the in-place sequences that Android's live views lay out unlike
their fresh build differ instead (169 at 321, 498 at 192 and 307 at 449, 41, 160 and
160 of them throwing on both sides), each equal to the live views in place.
`compare/helper_only.py` counts the layouts that differ only in helper frames.

## 21. The in-place gate (`gates/inplace_gates.sh`)

`inplace_gates.sh <outdir> [levels]` (default `0 64 192 256 257 321 449`) checks that an
in-place sequence laid out through `ViewHost` gives what Android's live views give, at
each level. The corpus is T2-inplace (cut from `$CL_CORPORA/T2.in`) through
`compare/keepbl.py`, which drops the `bl N 0` and `hbl N 0` ops after the first `L`:
T-inplace's generator (`dart/temit.dart`, `emitInPlaceT`) writes them to model an earlier
adapter's in-place path, which cleared every widget's baseline flag between states.
Neither Android (`reset()` keeps `mHasBaseline`) nor the current adapter does, the live
views never read them (their output is byte-identical with and without them), and the
engine reads them: with them, 70 sequences at 64 and 321 (79 at 192 and 449) lose a stale
baseline margin dependency Android keeps. T2-fresh, the fresh builds of the final
states, runs too.

Per level, a heavy step each: the RoboOracle with `-Drobo.inplace=1 -Drobo.twice=dirty
-Drobo.level=<lv>` (section 10: every state's layout params set again on the same live
views, then the dirty second layout), vfuzz `view<lv> --twice-links` on the corpus (every
mid-list `L` is one `ViewHost.measure`), and vfuzz `view<lv>` on T2-fresh. Then
`vcompare --strict --helpers full` of the engine in place against the live views in place
(`inplace.L<lv>`), of the second layouts (`second.L<lv>`) and of the fresh builds
(`fresh.L<lv>`, `--map T2-fresh=T2-inplace`), and, not a gate, of the live views in place
against their own fresh builds (`history.L<lv>`). A sequence the live views throw on
(`EXC:inplace` at an earlier state, `!EXC` at the final measure) is excluded as JEXC;
`throws.L<lv>.txt` lists the sequences each side threw on, and the engine runs every
sequence it threw on again cut before its last `L` (`TIP2.pre<lv>.in`) to tell an earlier
state from the final one. `summary.tsv`: level, compared, differ, JEXC, UNMAPPED, second
layouts differing, fresh builds differing, throws (engine, live views, same sequences),
throws at an earlier state (engine, live views, same), history.

Target, at every level: 0 differences in place, in the second layout and in the fresh
builds, and the engine throws on the live views' sequences, at their state. Results
(about 35 s per level):

| Level | Compared | Differ | Second layouts differ | Fresh differ | Throws: engine / live views (earlier state) | History |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 50,000 | 0 | 0 | 0 | 0 / 0 | 187 |
| 64 | 49,959 | 0 | 0 | 0 | 41 / 41, the same (15 / 15) | 429 |
| 192 | 49,840 | 0 | 0 | 0 | 160 / 160, the same (72 / 72) | 577 |
| 256 | 50,000 | 0 | 0 | 0 | 0 / 0 | 187 |
| 257 | 50,000 | 0 | 0 | 0 | 0 / 0 | 0 |
| 321 | 49,959 | 0 | 0 | 0 | 41 / 41, the same (15 / 15) | 239 |
| 449 | 49,840 | 0 | 0 | 0 | 160 / 160, the same (72 / 72) | 386 |

The history column counts the live views' in-place layouts that differ from their fresh
build (the throws included): without `OPTIMIZATION_DIRECT` a barrier that
`Barrier.allSolved` resolved keeps its resolved flag while `reset()` zeroes its position,
and at the GRAPH levels the graph's runs and nodes keep what the last graph left. The
engine keeps the same state (UPSTREAM.md, "Android's dirty measure"). The throws are a
`NullPointerException` in the graph ("Cannot read field "resolved"", a run that still
updates as centered after losing a link), where the engine fails a null check.

### 21.1 The adapter at every level

The FL runner takes the level from `FL_LEVEL` (section 11), so the same checks run
through the adapter on real Flutter trees. On TIP.txt (T-inplace; 48,403 sequences, 1,597
UNMAPPED `ratioside`), the `inplace` mode against the RoboOracle at the same level:

| Level | 0 | 64 | 192 | 256 | 257 | 321 | 449 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Fresh builds against the live views' | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| In place against `-Drobo.inplace=changed` | 5 | 7 | 7 | 5 | 0 | 2 | 2 |
| In place against `-Drobo.inplace=1` | 15 | 23 | 24 | 15 | 0 | 8 | 9 |
| In place against the adapter's own fresh builds | 172 | 406 | 620 | 172 | 0 | 231 | 444 |
| Sequences the adapter throws on (live views) | 0 (0) | 39 (41) | 147 (160) | 0 (0) | 0 (0) | 39 (41) | 147 (160) |

The comparison that matches Flutter's model is `changed`: a Flutter rebuild with the same
configuration lays nothing out, as an app that sets only what changed does on Android.
Every difference left there is a layout laid out a different number of times on the two
sides, which changes a result wherever it depends on the layout before it: a change to a
GONE child's content lays the layout out again on Android (its `requestLayout` reaches
the layout view) and not in Flutter (the adapter lays a gone child out tight at 0 x 0, so
the child is its own relayout boundary), and a change between VISIBLE and INVISIBLE lays
it out again in Flutter (the adapter's configuration changed) and not on Android
(`View.setVisibility` requests a layout only for a change to or from GONE). The two and
thirteen sequences the adapter does not throw on are of the same kind. Against
`-Drobo.inplace=1`, which sets every view's layout params again in every state, a state
that changes nothing adds a layout on Android too.

In the `replay` mode under `cl.verifyReplay` (FL, 60,000 layouts, each laid out five
times in the same `ConstraintLayout`): 0 replay mismatches at every level (176,323 to
178,771 replays), and the second layout equals DirtyTwice's at the same level on all
60,000. The second layout differs from the first on 1,091 layouts at 0, 192 and 256,
1,092 at 64, and 3 at 257, 321 and 449, on both sides, and the third to fifth layouts
equal the second on every layout. The layout's size changes from the second layout on
for 19 of them (1 at 257, 321 and 449), which is where a dry layout (a new model: the
first layout's size) differs from the size the layout takes from its second layout on.
