# Live-editable examples: research and plan

Research date: 2026-07-25. Status: research only, nothing implemented in the
package or website. A proof-of-concept interpreter lives in the git-ignored
`playground/` app (see "Artifacts" at the end).

## Goal

Let site visitors edit the Dart code shown in each example card and see the
live preview update to match, fully client-side, on the statically hosted
Flutter web build (`flutter build web --wasm`, GitHub Pages).

## TL;DR

- **rfw: no.** It can render ConstraintLayout through a custom
  `LocalWidgetLibrary`, but it never parses or executes Dart. Visitors would
  edit rfw's own text format, which differs from the documented Dart on
  effectively every line. For a site whose product is the Dart API, that
  teaches the wrong language.
- **Off-the-shelf Dart interpreters: no.** dart_eval and tom_d4rt were both
  tested empirically against the real samples; both hard-fail on Dart 3.10
  dot shorthands, which every example uses. Other blockers stack on top.
- **Recommended: parse the real Dart in the browser with `package:analyzer`
  and interpret the AST with a small hand-rolled evaluator.** This is the only
  route that runs the exact code the docs display. It is no longer a guess:
  a working vertical slice interprets the two hardest examples verbatim and
  renders rect-for-rect identical to the hand-written builders, at 0.8 ms per
  parse+eval and about +132 KB gzip of bundle cost. The wasm build target was
  verified end-to-end in a real browser.

## The rfw question, answered

rfw (Remote Flutter Widgets, v1.1.3, published by flutter.dev, 2026-03) is a
runtime renderer for its own declarative format (`.rfwtxt` text / `.rfw`
binary). Findings:

- The text parser (`parseLibraryFile`) is pure Dart, synchronous, web-safe
  (including wasm), fast enough for per-keystroke reparsing, and throws
  `ParserException` with line/column. As a runtime, rfw is solid.
- A `constraint.layout` adapter is feasible: `Constrained`, `Barrier`, and
  `Guideline` are `ParentDataWidget`s, so rfw's internal wrapper widgets do
  not break parent-data application (same mechanism as rfw's own `Expanded`).
  Symbol ids would be encoded as strings, anchor links as maps.
- The format cannot express what the samples are made of: no arithmetic or
  operators, no function or method calls (`Theme.of(context)` is impossible),
  no local variables, no symbol literals, no enum dot shorthand, no loop
  index. A faithful translation of the `aligned-form` example turns
  `id: #l1` into `id: "l1"`, `top: .bottomOf(#l1, margin: 18)` into
  `top: {target: "l1", edge: "bottom", margin: 18.0}`, and hardcodes theme
  colors as ARGB ints. Every line differs from the code card.

So rfw would mean maintaining a third representation of every example (Dart
string + Dart builder + rfw text) and asking visitors to learn a syntax that
is not the package's API. Verdict: not a fit for this goal. It would only make
sense as a separately scoped, non-Dart playground, which is a different
feature.

## Everything else evaluated

| Option | Verdict | Decisive evidence |
| --- | --- | --- |
| **dart_eval + flutter_eval** | Blocked | Dot shorthands fail with `CompileError: Unknown expression type DotShorthandPropertyAccessImpl` (tested on 0.8.5; zero DotShorthand handling in compiler source). The samples contain 100+ shorthand sites. Also: flutter_eval 0.8.2 does not build on Flutter >= 3.41 (`Container.isAntiAlias`, issue #140, unfixed), `Theme.of(context).colorScheme` throws at runtime (ColorScheme unbound), no execution limits for user loops (issue #291), effectively single-maintainer. |
| **tom_d4rt** (maintained d4rt fork) | Blocked | Tested on 1.12.1: all three dot-shorthand forms fail ("Undefined variable"), `#hub` literals silently evaluate to null, and destructuring bridged `.indexed` records throws `PatternMatchException`. Supply chain is also marginal (unverified uploader, ~900 downloads, 1 star). |
| **DartPad embed** | Blocked | Public DartPad supports only a curated package allowlist; arbitrary packages are explicitly off the roadmap, and the lightweight-embedding initiative (#2702) was closed as not planned on 2026-07-13. flutter_constraint_layout is unpublished besides. Self-hosting `dart_services` works in principle but abandons static hosting and adds a forked-deployment ops burden per Flutter release. |
| **Zapp.run** | Dead | Domain unresolvable since ~March 2026 (Cloudflare zone refused); repo last pushed 2023. |
| **JSON UI runtimes** (stac, json_dynamic_widget) | Rejected | Same format mismatch as rfw but with JSON; json_dynamic_widget is marked discontinued on pub.dev. |
| **Server-side compile** (dart-services style, DDC hot reload) | Viable but costly | Real compiler fidelity, but abandons static hosting, seconds-scale latency, always-on instance, sandboxed-iframe and abuse controls needed. Keep as fallback only. |
| **Structured knobs** (model regenerates the code string) | Complement, not the goal | The site already ships this pattern (`VisibilityToggleDemo._codeFor`). Reliable direction (model to code), but by definition it is not free-text editing. Worth layering on later, not the deliverable. |
| **analyzer in the browser + hand-rolled AST interpreter** | **Validated, recommended** | Details below. |

## The validated approach

Ship `package:analyzer`'s `parseString` inside the website bundle, walk the
real AST, and evaluate the examples' (closed, declarative) Dart subset against
a registry of constructors that calls the real `flutter_constraint_layout` and Flutter
APIs compiled into the site. Visitors edit the exact Dart the docs display.

### What was actually proven (not estimated)

1. **The wasm build target works.** `parseString` compiled with dart2wasm runs
   correctly in real Chrome, including inside a genuine
   `flutter build web --wasm` bundle served without COOP/COEP headers (GitHub
   Pages conditions). An earlier "illegal cast" wasm failure turned out to be
   a Node-only artifact. The `--wasm` build also ships a dart2js fallback
   bundle automatically (used by Firefox/Safari), and that path is verified
   too. No build-target change needed.
2. **The interpreter is real.** `playground/lib/mini_eval.dart` (~773 lines:
   evaluator + registry) interprets the verbatim code strings of
   `aligned-form` and `radial-menu`, the two hardest samples. That covers:
   type-directed dot-shorthand resolution (`.startOf(parent)`, `edge: .end`,
   `width: .fixed(60)`), the `final cs = Theme.of(context).colorScheme;`
   prelude, a user-defined local function (`satellite(IconData icon)`),
   collection-for with `(i, icon)` record destructuring over `.indexed`,
   interpolated `Symbol('a$i')` ids, and arithmetic (`i * 72.0`).
   Widget tests assert every rendered rect equals the hand-written builder's.
   4/4 tests pass (re-verified on this machine).
3. **Latency is a non-issue.** Warm parse of radial-menu under dart2js on V8:
   0.22-0.34 ms. Full parse+eval: ~0.85 ms. Editing can re-evaluate every
   keystroke inside one frame; debouncing is optional.
4. **Bundle cost is known.** Measured inside the real website build:
   +492 KB raw / +132 KB gzip (~+15%) on top of the current ~900 KB gzip.
5. **Runaway input is solved.** A fuel counter at four choke points turns a
   typed `for (;;) {}` into an `EvalBudgetExceeded` error instead of a hung
   tab (about 10 lines; this is exactly what dart_eval cannot do, issue #291).
6. **Safety shape is right.** The evaluator can only instantiate what the
   registry allowlists; there is no general execution surface beyond the
   examples' vocabulary.

### Why the fit is unusually good here

- The corpus is small and closed: 17 examples, ~16 constructor names, ~10
  enums/constant tables, no callbacks, no async, no classes, no imports.
- The registry calls the real constructors, so defaults, asserts, and value
  equality come free, and dot shorthands resolve naturally because each
  registry parameter knows its expected type (which is exactly the
  information rfw/dart_eval lack).
- The paired code-string + builder corpus is a ready-made golden suite:
  `interpret(code)` must render identically to `builder(context)` for all 17.
  This also permanently fixes the existing hand-maintained drift between
  strings and builders (they already differ on small things like `const`).
- Existing site architecture helps: `PreviewStage` is public, the debug
  toggles already rebuild a `ConstraintLayout` from another instance's fields,
  and `CodeBlock`'s shiki token cache makes re-highlighting cheap.

### Known constraints to design around

- **Analyzer version pinning.** In this workspace the resolvable analyzer is
  capped by Flutter's `meta` pin (12.1.0 here today; 13.0.0 in a fresh app;
  14.x needs a meta override). 12.x and 13.x both parse the full modern
  surface (dot shorthands, records, interpolated symbols) with zero errors,
  but 13.0 renamed AST APIs (`NamedExpression` to sealed `Argument` types,
  formal-parameter reshuffle). Mitigation: pin the version and wrap the AST
  touchpoints in a small facade so major bumps are one-file fixes.
- **Web is not an officially supported analyzer target.** The parse-only path
  demonstrably compiles and runs, but a future analyzer release could regress
  it. The pin protects against surprise; parity tests catch regressions.
- **Release builds strip asserts.** Invariants like Guideline's
  "exactly one of begin/end/percent" must be re-validated by the editor layer
  and surfaced as diagnostics, or bad edits will silently mislay.
- **Non-uniform defaults.** `ConstraintGrid` defaults width/height to
  `.matchConstraint` while everything else defaults to `.wrapContent`; the
  registry must call real constructors (it does) rather than normalize
  defaults itself.
- **Int-to-double coercion.** `margin: 18` needs `num.toDouble()` once per
  registry adapter (already handled in the PoC).
- **Safari on the wasm path is untested** (no headless WebKit here), but by
  bootstrap policy Safari currently receives the verified dart2js bundle, so
  it cannot regress the feature today.

## Proposed plan (pending "Implement")

### Phase 0: product decisions (user input)

1. Scope: free-text editing on all 17 examples, or only the 13 teaching
   examples? (The PoC already proves the 4 hard flagships work, so all 17 is
   recommended and costs little extra.)
2. Failure UX: when a visitor types Dart outside the supported vocabulary, is
   an inline "unsupported construct" message with line/column acceptable?
   (This is inherent to every client-side option.)
3. Interaction: edit-in-place on the existing code card, or an explicit
   "edit" toggle per card with a reset button? (Recommendation: toggle +
   reset, keeps the default reading experience untouched.)

### Phase 1: editor surface spike (~1-2 days)

The one prerequisite no research covered: what visitors type into.
Candidates: `re_editor` / `flutter_code_editor`, or a plain `TextField`
layered with the existing shiki highlighter (transparent input over a
highlighted mirror, reusing `CodeBlock`'s token cache). Evaluate under the
`--wasm` build for: IME/mobile keyboards, undo depth, tab handling, selection,
and error-marker rendering. Deliverable: one page with a working editor over
one example, and a decision.

### Phase 2: productionize the interpreter (~2-3 days)

- Promote `playground/lib/mini_eval.dart` into the website (e.g.
  `website/lib/src/eval/`), split evaluator / registry / diagnostics.
- Extend the registry to the full corpus vocabulary: remaining constraint
  widgets (`Guideline`, `ConstraintFlow`, `ConstraintGrid`), the ~20 Flutter
  types the samples use, constant tables (the used `Icons.*` subset,
  `FontWeight`, `Alignment`, `EdgeInsets`, `BoxDecoration`, `Border`,
  `BoxShape`), `DemoBox`, and the `ColorScheme` getters the preludes touch.
- Diagnostics: carry AST offsets on semantic errors (syntax errors already
  have them), re-implement release-stripped invariants (Guideline
  exactly-one-of, unknown/duplicate ids, dangling `referenced` ids) as
  editor-surfaced validation.
- Wrap analyzer AST touchpoints in a facade; pin the analyzer version.

### Phase 3: wire into the site (~1-2 days)

- Add the edit mode to `LiveExample`'s code card; on change, parse + eval and
  swap the preview to the interpreted tree (builder remains the pristine
  default and the reset target). Debug toggles keep working since the
  interpreted root is a real `ConstraintLayout`.
- Error banner with line/column markers in the editor gutter.
- Parity suite: for all 17 examples, assert `interpret(code)` renders
  rect-identical to `builder(context)` (extend the PoC tests; reuse the
  `host()`/`rectOf()` pattern from `test/features_test.dart`). This suite
  doubles as the guard that future samples stay inside the vocabulary.

### Phase 4: hardening and rollout (~1 day)

- Cross-browser manual pass: Chrome (wasm path), Firefox/Safari (js
  fallback), one mobile browser for keyboard behavior.
- Bundle check against the measured +132 KB gzip budget; build-time check
  (29 s to 37 s measured on the spike).
- Ship. Optional later follow-ups: delete the hand-written builders once the
  parity suite is trusted (single source of truth: the code string); layer
  knob-style controls that rewrite the editor text (model-to-code) on top of
  selected examples.

Total: roughly 5-8 focused days, front-loaded with the only remaining unknown
(the editor widget UX), since the engine risk is already retired.

## Artifacts

- Proof of concept: `playground/lib/mini_eval.dart` (evaluator + registry),
  `playground/test/mini_eval_test.dart` (parity + fuel + latency tests).
  `playground/` is git-ignored and standalone; nothing in the package or
  website was changed by this research. Note: `website/build/web` contains a
  stale spike build artifact that the next `flutter build web` will replace.
- Ephemeral experiments (in `/tmp`, gone on reboot): analyzer dart2js/wasm
  probes, a throwaway `flutter build web --wasm` spike app with browser
  verification logs, dart_eval and tom_d4rt language-feature probes.
- Upstream references: dart_eval issues #140/#291/#297, DartPad embedding
  issue dart-lang/dart-pad#2702 (closed, not planned), rfw source in
  flutter/packages.
