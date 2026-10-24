# Test porting guide (Java JUnit -> Dart test)

Convert Android ConstraintLayout `core` tests to Dart tests for `constraint_engine`.
The engine resolves a layout with the dependency graph first and falls back to the
ported `LinearSystem` (Cassowary) solver when the graph declines; UPSTREAM.md lists
the decline rules. The asserted coordinates are engine-agnostic golden values, so a
ported test must reproduce them whichever path resolves it. Tests that drive the
solver directly (`LinearSystem`, `ArrayRow`, `SolverVariable`) are ported too.

Source tests live upstream at
https://github.com/androidx/constraintlayout/tree/main/constraintlayout/core/src/test/java/androidx/constraintlayout/core
(the port is pinned to that repository's final commit; see `../UPSTREAM.md`). A local
clone is handy for grepping. It is optional and git-ignored: from the repository root,
`git clone https://github.com/androidx/constraintlayout inspo/constraintlayout`.

`../UPSTREAM.md` maps every upstream test file to its Dart port and lists the ones
that are not ported, with the reason.

Engine package under test: import `package:constraint_engine/constraint_engine.dart`.
Test framework: `package:test/test.dart`.

## Constructors (Dart has no overloading, use named constructors)
- `new ConstraintWidgetContainer(0,0,W,H)` -> `ConstraintWidgetContainer.rect(0,0,W,H)`
- `new ConstraintWidgetContainer(W,H)` -> `ConstraintWidgetContainer.size(W,H)`
- `new ConstraintWidgetContainer("name",W,H)` -> `ConstraintWidgetContainer.sizeNamed("name",W,H)`
- `new ConstraintWidget(W,H)` -> `ConstraintWidget.size(W,H)`
- `new ConstraintWidget(x,y,W,H)` -> `ConstraintWidget.rect(x,y,W,H)`
- `new ConstraintWidget("name",W,H)` -> `ConstraintWidget.sizeNamed("name",W,H)`
- `new ConstraintWidget("name")` -> `ConstraintWidget.named("name")`
- `new ConstraintWidget()` -> `ConstraintWidget()`
- `new Guideline()` -> `Guideline()`;  `new Barrier()` -> `Barrier()`

## Enums / constants
- `ConstraintAnchor.Type.LEFT|RIGHT|TOP|BOTTOM|BASELINE|CENTER|CENTER_X|CENTER_Y`
  -> `ConstraintAnchorType.left|right|top|bottom|baseline|center|centerX|centerY`
- `ConstraintWidget.DimensionBehaviour.FIXED|WRAP_CONTENT|MATCH_CONSTRAINT|MATCH_PARENT`
  -> `DimensionBehaviour.fixed|wrapContent|matchConstraint|matchParent`
- `ConstraintWidget.MATCH_CONSTRAINT_SPREAD|WRAP|PERCENT|RATIO` -> unchanged (`ConstraintWidget.MATCH_CONSTRAINT_SPREAD` ...)
- `ConstraintWidget.CHAIN_SPREAD|CHAIN_SPREAD_INSIDE|CHAIN_PACKED` -> unchanged
- `ConstraintWidget.GONE|VISIBLE|INVISIBLE|HORIZONTAL|VERTICAL|UNKNOWN` -> unchanged
- `ConstraintWidget.ANCHOR_LEFT` etc -> unchanged
- `Guideline.VERTICAL|HORIZONTAL` -> `Guideline.vertical|horizontal`
- `Barrier.LEFT|RIGHT|TOP|BOTTOM` -> `Barrier.left|right|top|bottom`
- `Optimizer.OPTIMIZATION_STANDARD|NONE|GRAPH` -> unchanged
- `BasicMeasure.EXACTLY|AT_MOST|UNSPECIFIED|WRAP_CONTENT|MATCH_PARENT|FIXED` -> unchanged
- `Measure.SELF_DIMENSIONS|TRY_GIVEN_DIMENSIONS|USE_GIVEN_DIMENSIONS` -> unchanged
- float literals: `0.5f` -> `0.5`, `1f` -> `1.0`, `0.2f` -> `0.2`
- Java integer division `a / b` -> `a ~/ b`; casts `(int) expr` -> `expr.toInt()`

## Methods
- `widget.connect(Type.X, target, Type.Y, margin)` -> unchanged: `widget.connect(ConstraintAnchorType.x, target, ConstraintAnchorType.y, margin)`
- `widget.connect(fromAnchor, toAnchor, margin)` (anchor,anchor,margin overload) -> `widget.connectAnchors(fromAnchor, toAnchor, margin)`
- `widget.setDimensionRatio("H,16:9")` -> `widget.setDimensionRatioString("H,16:9")`
- `widget.setDimensionRatio(ratioFloat, side)` -> `widget.setDimensionRatio(ratioDouble, side)`
- `guideline.setGuidePercent(0.5f)` -> `guideline.setGuidePercent(0.5)`
- `guideline.setGuidePercent(intValue)` -> `guideline.setGuidePercentInt(intValue)`
- `root.add(a); root.add(b);` -> unchanged (or `root.addAll([a, b])`)
- `root.setMeasurer(sMeasurer)` -> unchanged
- `root.measure(opt, EXACTLY, w, EXACTLY, h, 0,0,0,0)` -> `root.measure(opt, BasicMeasure.EXACTLY, w, BasicMeasure.EXACTLY, h, 0, 0, 0, 0)`
- `root.updateHierarchy()` -> unchanged
- getters `getWidth/getHeight/getLeft/getTop/getRight/getBottom/getX/getY/getDebugName/getBaselineDistance` -> unchanged
- `getGuidelineAnchor()`/no-arg guideline `getAnchor()` -> `guideline.getGuidelineAnchor()`
- `widget.setDebugSolverName(system, "name")` -> `widget.setDebugName('name')` (upstream's
  version also names the widget's solver variables, which only matters for debug output)

## Solver classes
- `SolverVariable.Type.UNRESTRICTED|CONSTANT|SLACK|ERROR|UNKNOWN`
  -> `SolverVariableType.unrestricted|constant|slack|error|unknown`
- `SolverVariable.STRENGTH_*` -> unchanged
- Java overloads are split into named methods; each ported file's header lists its own:
  - `row.createRowEquals(variable, value)` -> `row.createRowEqualsConstant(variable, value)`
    (`createRowEquals(a, b, margin)` keeps its name)
  - `row.createRowGreaterThan(a, intValue, slack)` -> `row.createRowGreaterThanConstant(a, intValue, slack)`
    (`createRowGreaterThan(a, b, slack, margin)` keeps its name)
  - `row.addError(system, strength)` -> `row.addErrorToRow(system, strength)`
  - `system.addEquality(a, value)` -> `system.addEqualityConstant(a, value)`
    (`addEquality(a, b, margin, strength)` keeps its name)
- Upstream's test support classes `Amount`, `EquationVariable`, and `LinearEquation` are
  ported under `test/support/`. `var` is reserved in Dart, so the `LinearEquation`
  `var(...)` DSL calls become `v(...)`.
- For virtual-layout (Flow, Grid) tests, `test/support/virtual_layout_measurer.dart` provides
  the measurer that upstream's FlowTest defines inline.

## Measurer (anonymous class -> Dart class)
```java
static BasicMeasure.Measurer sMeasurer = new BasicMeasure.Measurer() {
  @Override public void measure(ConstraintWidget widget, BasicMeasure.Measure measure) { ... }
  @Override public void didMeasures() {}
};
```
becomes a top-level class:
```dart
class _Measurer implements Measurer {
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    final horizontalBehavior = measure.horizontalBehavior;
    final verticalBehavior = measure.verticalBehavior;
    final horizontalDimension = measure.horizontalDimension;
    final verticalDimension = measure.verticalDimension;
    // ... same body, using DimensionBehaviour.fixed etc ...
    widget.setMeasureRequested(false);
  }
  @override
  void didMeasures() {}
}
final _Measurer sMeasurer = _Measurer();
```

## Assertions
- `assertEquals(actual, expected)` -> `expect(actual, expected)`  (note: Java arg order is (expected, actual) in the JUnit signature but these tests usually pass the COMPUTED value first; keep the SAME two values, order does not affect `expect` equality)
- `assertEquals(actual, expected, delta)` -> `expect(actual, closeTo(expected, delta))`
- `assertTrue(x)` -> `expect(x, isTrue)`
- `assertFalse(x)` -> `expect(x, isFalse)`

## Structure
- Each `@Test public void fooBar()` -> `test('fooBar', () { ... });`
- File -> `void main() { group('<FileName>', () { <tests> }); }`
- Keep upstream's class name as the group and each method name as the test name, so a
  failure maps straight back to its Java original. Start the file with a
  `// Ported from androidx.constraintlayout.core.<Class> (upstream pinned in UPSTREAM.md).`
  comment, plus a note on any conversion that is not mechanical.
- Delete all `System.out.println(...)`, `import` lines, `@Test`, class wrapper.

## What to port, skip, or drop
The solver is ported, so tests that call solver APIs (`getSystem()`, `addToSolver(...)`,
`updateFromSolver(...)`, `resetSolverVariables(...)`, `getCache()`, `minimize()`) or use
circular positioning (`connectCircularConstraint`) are ported and run like any other.
`../UPSTREAM.md` lists four ported tests that still leave those solver runs out.

- Keep every run when a test repeats a layout under several optimization levels
  (`OPTIMIZATION_NONE`, `OPTIMIZATION_STANDARD`, `OPTIMIZATION_GRAPH`, ...): port each
  `setOptimizationLevel(...)` or `measure(...)` call together with its assertions.
- Drop diagnostic-only scaffolding instead of skipping the test: `System.out.println`,
  `System.nanoTime()` timing, and `Metrics metrics = new Metrics(); root.fillMetrics(metrics);`.
  `Metrics` instrumentation is not ported, and upstream never asserts on it.
- A method whose `@Test` is commented out upstream does not run there either. Port it
  with `skip:` and the reason, as `nested_layout_test.dart` does for
  `NestedLayout.testNestedLayout`, or leave it out, as with `WidgetsPositioningTest`'s
  `testAddingWidgets` and `testWidgetStrengthPositioning`.
  Example: `test('name', () { ... }, skip: 'disabled upstream too (@Test is commented out)');`
- A test that needs an unported module (`state/`, `parser/`, `motion/`, `dsl/`, `scout/`,
  `utils/GridEngine`) is not ported at all; list it in UPSTREAM.md with the reason.
- Never skip a test to hide a failure. A wrong coordinate is either an engine bug or a
  conversion error, and either one needs fixing.

## Running
`dart test test/<file>_test.dart`, then the whole suite with `dart test`.
Report: total tests, passing, skipped, and any FAILING with the expected-vs-actual so the
engine owner can decide if it is an engine bug or a conversion error.
