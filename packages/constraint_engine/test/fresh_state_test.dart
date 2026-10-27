// ViewHost lays a layout out as Android's dirty measure does, however the
// engine-side widgets were edited in place: before every measure it calls
// ConstraintWidget.resetMeasureState on every child (Android's
// ConstraintWidget.reset(), CW 557-621, less what the layout params set
// again) and rebuilds the anchor dependents. Android gets there by
// rebuilding every widget of a changed hierarchy (CL 1249-1351). Like
// reset(), the reset keeps the resolved flags, a guideline's and a barrier's
// own resolved flag, mHasBaseline and the last measure specs, so a widget
// carries them from one measure to the next as Android's does.
//
// The groups below check, in order: the APIs that carry state from one pass
// or iteration to the next; the reset itself, field by field against a fresh
// widget, and what it keeps; and in-place sequences through ViewHost against
// Android: its live views (RoboOracle with -Drobo.inplace=1, the
// ConstraintLayout 2.2.1 view layer under Robolectric 4.16, at the level the
// test names), Java's ResetProbe (tool/parity/java/probes), and the pinned
// VOpDriver v2's fresh builds (its view path). Each test gives the op lists,
// under the ids it cites.
//
// Only src libraries are imported, so the file needs no change when the
// package's library starts to export the view layer.

import 'dart:math' as math;

import 'package:constraint_engine/src/analyzer/basic_measure.dart';
import 'package:constraint_engine/src/barrier.dart';
import 'package:constraint_engine/src/constraint_anchor.dart';
import 'package:constraint_engine/src/constraint_widget.dart';
import 'package:constraint_engine/src/constraint_widget_container.dart';
import 'package:constraint_engine/src/flow.dart';
import 'package:constraint_engine/src/guideline.dart';
import 'package:constraint_engine/src/linear_system.dart';
import 'package:constraint_engine/src/optimizer.dart';
import 'package:constraint_engine/src/view/measure_spec.dart';
import 'package:constraint_engine/src/view/view_host.dart';
import 'package:constraint_engine/src/view/view_measurer.dart';
import 'package:test/test.dart';

const _left = ConstraintAnchorType.left;
const _top = ConstraintAnchorType.top;
const _right = ConstraintAnchorType.right;
const _bottom = ConstraintAnchorType.bottom;
const _baseline = ConstraintAnchorType.baseline;
const _fixed = DimensionBehaviour.fixed;
const _wrap = DimensionBehaviour.wrapContent;
const _mc = DimensionBehaviour.matchConstraint;
const _parent = DimensionBehaviour.matchParent;

int _exactly(int size) =>
    MeasureSpec.makeMeasureSpec(size, MeasureSpec.EXACTLY);
int _atMost(int size) => MeasureSpec.makeMeasureSpec(size, MeasureSpec.AT_MOST);
int _unspecified() => MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED);

/// A child view's content (FORMATS.md 6.1): a box of a natural size, or a
/// text `w` wide on one line, `h` per line, that wraps at a narrower width.
class _Content {
  const _Content.box(this.w, this.h) : text = false, baseline = -1;
  const _Content.text(this.w, this.h, [this.baseline = -1]) : text = true;
  final bool text;
  final int w;
  final int h;
  final int baseline;
}

int _resolve(int n, int spec) {
  final mode = MeasureSpec.getMode(spec);
  final size = MeasureSpec.getSize(spec);
  if (mode == MeasureSpec.EXACTLY) return size;
  if (mode == MeasureSpec.AT_MOST) return n < size ? n : size;
  return n;
}

/// The child views: a pure function of the specs, as the parity contract
/// wants.
class _ContentMeasurer extends ViewMeasurer {
  final Map<ConstraintWidget, _Content> content = {};

  @override
  ({int width, int height, int baseline}) measureContent(
    ConstraintWidget widget,
    int widthSpec,
    int heightSpec,
  ) {
    final c = content[widget] ?? const _Content.box(0, 0);
    final width = _resolve(c.w, widthSpec);
    if (!c.text) {
      return (
        width: width,
        height: _resolve(c.h, heightSpec),
        baseline: c.baseline,
      );
    }
    final lines = width <= 0 ? 50 : (c.w + width - 1) ~/ width;
    return (
      width: width,
      height: _resolve(c.h * lines, heightSpec),
      baseline: c.baseline,
    );
  }
}

/// A layout view and its children, configured by a caller that applies the
/// whole configuration again before every measure, as Android's layout params
/// are applied again (and as the adapter's model sync will).
class _Scene {
  _Scene({int level = 0}) {
    host = ViewHost(root, measurer)..optimizationLevel = level;
  }

  final ConstraintWidgetContainer root = ConstraintWidgetContainer()
    ..setDebugName('root');
  final _ContentMeasurer measurer = _ContentMeasurer();
  late final ViewHost host;
  final Map<String, ConstraintWidget> by = {};

  /// The widget [name], created by [create] and added on first use.
  T get<T extends ConstraintWidget>(String name, T Function() create) {
    final existing = by[name];
    if (existing != null) return existing as T;
    final widget = create()..setDebugName(name);
    by[name] = widget;
    root.add(widget);
    return widget;
  }

  void measure(int widthSpec, int heightSpec) =>
      host.measure(widthSpec, heightSpec);

  /// VOpDriver's view-path geometry (FORMATS.md 8.2).
  String frames() {
    final b = StringBuffer(
      'root ${host.getMeasuredWidth()} x ${host.getMeasuredHeight()}',
    );
    for (final c in root.getChildren()) {
      final helper = c is Guideline || c is Barrier || c is Flow;
      if (c.getVisibility() == ConstraintWidget.GONE && !helper) {
        b.write(' | ${c.getDebugName()}: gone, 0 x 0');
      } else {
        b.write(
          ' | ${c.getDebugName()}: (${c.getX()}, ${c.getY()}) '
          '${c.getWidth()} x ${c.getHeight()}',
        );
      }
    }
    return b.toString();
  }
}

/// Configures a fixed child, its links reset and connected again.
ConstraintWidget _box(
  _Scene s,
  String name,
  int width,
  int height, {
  int visibility = ConstraintWidget.VISIBLE,
}) {
  final w = s.get(name, ConstraintWidget.new)
    ..setHorizontalDimensionBehaviour(_fixed)
    ..setVerticalDimensionBehaviour(_fixed)
    ..setWidth(width)
    ..setHeight(height)
    ..setVisibility(visibility)
    ..resetAnchors();
  s.measurer.content[w] = _Content.box(width, height);
  return w;
}

/// The echo measurer of VOpDriver's core path (the rules of
/// support/echo_measurer.dart's EchoMeasurer).
class _Echo implements Measurer {
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    var w = measure.horizontalBehavior == _wrap
        ? widget.mWidth
        : measure.horizontalDimension;
    var h = measure.verticalBehavior == _wrap
        ? widget.mHeight
        : measure.verticalDimension;
    if (widget.getHorizontalDimensionBehaviour() == _mc) {
      final min = widget.mMatchConstraintMinWidth;
      final max = widget.mMatchConstraintMaxWidth;
      if (min > 0 && w < min) w = min;
      if (max > 0 && w > max) w = max;
    }
    if (widget.getVerticalDimensionBehaviour() == _mc) {
      final min = widget.mMatchConstraintMinHeight;
      final max = widget.mMatchConstraintMaxHeight;
      if (min > 0 && h < min) h = min;
      if (max > 0 && h > max) h = max;
    }
    measure
      ..measuredWidth = w
      ..measuredHeight = h
      ..measuredHasBaseline = widget.hasBaseline()
      ..measuredBaseline = widget.getBaselineDistance();
    widget.setMeasureRequested(false);
  }

  @override
  void didMeasures() {}
}

String _finals(ConstraintWidget w) => [
  for (final a in [
    w.mLeft,
    w.mTop,
    w.mRight,
    w.mBottom,
    w.mBaseline,
    w.mCenterX,
    w.mCenterY,
    w.mCenter,
  ])
    a.hasFinalValue() ? '${a.getFinalValue()}' : '_',
].join(',');

String _links(ConstraintWidget w) => [
  for (final a in w.mAnchors)
    if (a.mTarget != null || a.mMargin != 0)
      '${a.mType.name}->${a.mTarget?.mOwner.getDebugName()}.'
          '${a.mTarget?.mType.name}/${a.mMargin}/${a.mGoneMargin}',
].join(' ');

/// Every field resetMeasureState resets, and the configuration it keeps.
Map<String, Object?> _state(ConstraintWidget w) => {
  'position': [w.mX, w.mY, w.mOffsetX, w.mOffsetY],
  'size': [w.mWidth, w.mHeight],
  'baseline distance': w.mBaselineDistance,
  'final values': _finals(w),
  'match-parent resolution': [w.mHorizontalResolution, w.mVerticalResolution],
  'resolved ratio': [
    w.mResolvedHasRatio,
    w.mResolvedDimensionRatioSide,
    w.mResolvedDimensionRatio,
  ],
  'terminal': [...w.isTerminalWidget],
  'in virtual layout': w.isInVirtualLayout(),
  'in barrier': [w.isInBarrier(0), w.isInBarrier(1)],
  'measure requested': w.mMeasureRequested,
  'resolved defaults': [...w.mResolvedMatchConstraintDefault],
  'overrides': [w.mWidthOverride, w.mHeightOverride],
  // Configuration, kept.
  'behaviours': [...w.mListDimensionBehaviors],
  'links': _links(w),
  'min': [w.mMinWidth, w.mMinHeight],
  'max': [w.getMaxWidth(), w.getMaxHeight()],
  'match styles': [
    w.mMatchConstraintDefaultWidth,
    w.mMatchConstraintMinWidth,
    w.mMatchConstraintMaxWidth,
    w.mMatchConstraintPercentWidth,
    w.mMatchConstraintDefaultHeight,
    w.mMatchConstraintMinHeight,
    w.mMatchConstraintMaxHeight,
    w.mMatchConstraintPercentHeight,
  ],
  'ratio': [w.mDimensionRatio, w.mDimensionRatioSide],
  'biases': [w.mHorizontalBiasPercent, w.mVerticalBiasPercent],
  'weights': [...w.mWeight],
  'chain styles': [w.mHorizontalChainStyle, w.mVerticalChainStyle],
  'visibility': w.getVisibility(),
  'wrap behaviour': w.getWrapBehaviorInParent(),
  'circle angle': w.mCircleConstraintAngle.isNaN
      ? 'NaN'
      : w.mCircleConstraintAngle,
};

/// The state Android's reset() (CW 557-621) leaves alone, so that
/// resetMeasureState keeps it from one measure to the next.
Map<String, Object?> _kept(ConstraintWidget w) => {
  'resolved': [w.mResolvedHorizontal, w.mResolvedVertical],
  'solving passes': [
    w.isHorizontalSolvingPassDone(),
    w.isVerticalSolvingPassDone(),
  ],
  'has baseline': w.hasBaseline(),
  'last specs': [
    w.getLastHorizontalMeasureSpec(),
    w.getLastVerticalMeasureSpec(),
  ],
  if (w is Guideline) 'guideline resolved': w.mResolved,
  if (w is Barrier) 'barrier resolved': w.mResolved,
};

void main() {
  group('state carried between passes', () {
    test('setFinalVertical gives the baseline a final value only when the '
        'widget has a baseline (CW 190-192)', () {
      final w = ConstraintWidget.sizeNamed('w', 50, 20)
        ..setBaselineDistance(15);
      w.setFinalVertical(100, 120);
      expect(w.mBaseline.hasFinalValue(), isTrue);
      expect(w.mBaseline.getFinalValue(), 115);
      expect([w.mY, w.mHeight, w.isResolvedVertically()], [100, 20, true]);

      final none = ConstraintWidget.sizeNamed('none', 50, 20);
      none.setFinalVertical(100, 130);
      expect(none.mBaseline.hasFinalValue(), isFalse);
      expect(none.mHeight, 30);
    });

    test('setFinalBaseline places the widget from its baseline, with the '
        'stored height, and needs a baseline (CW 201-212)', () {
      final w = ConstraintWidget.sizeNamed('w', 50, 20)
        ..setBaselineDistance(15);
      // Not first-wins, unlike setFinalVertical.
      w.setFinalVertical(0, 20);
      w.setFinalBaseline(60);
      expect(w.mY, 45);
      expect(_finals(w), '_,45,_,65,60,_,_,_');
      expect(w.isResolvedVertically(), isTrue);
      // The stored height even while gone (getHeight() is then 0).
      final gone = ConstraintWidget.sizeNamed('gone', 50, 20)
        ..setBaselineDistance(15)
        ..setVisibility(ConstraintWidget.GONE);
      gone.setFinalBaseline(60);
      expect(gone.mBottom.getFinalValue(), 65);

      final none = ConstraintWidget.sizeNamed('none', 50, 20);
      none.setFinalBaseline(60);
      expect(_finals(none), '_,_,_,_,_,_,_,_');
      expect(none.mResolvedVertical, isFalse);
    });

    test('setFinalLeft and setFinalTop resolve one edge, not the axis', () {
      final w = ConstraintWidget.sizeNamed('w', 50, 20);
      w.setFinalLeft(12);
      w.setFinalTop(34);
      expect([w.mX, w.mY], [12, 34]);
      expect(_finals(w), '12,34,_,_,_,_,_,_');
      expect(w.isResolvedHorizontally(), isFalse);
      expect(w.isResolvedVertically(), isFalse);
      w.mRight.setFinalValue(62);
      expect(w.isResolvedHorizontally(), isTrue);
    });

    test('setFinalFrame sets the frame and the baseline distance and marks '
        'the axes it names (CW 106-127)', () {
      final w = ConstraintWidget.sizeNamed('w', 50, 20);
      w.setFinalFrame(10, 20, 40, 60, 12, ConstraintWidget.VERTICAL);
      // setFrame keeps a fixed size that is larger, and records nothing.
      expect([w.mX, w.mY, w.mWidth, w.mHeight], [10, 20, 50, 40]);
      expect([w.getBaselineDistance(), w.hasBaseline()], [12, true]);
      expect([w.mResolvedHorizontal, w.mResolvedVertical], [false, true]);
      expect(_finals(w), '_,_,_,_,_,_,_,_');
      w.setFinalFrame(0, 0, 50, 20, 0, ConstraintWidget.HORIZONTAL);
      expect([w.mResolvedHorizontal, w.mResolvedVertical], [true, false]);
      w.setFinalFrame(0, 0, 50, 20, 0, ConstraintWidget.BOTH);
      expect([w.mResolvedHorizontal, w.mResolvedVertical], [true, true]);
      w.setFinalFrame(0, 0, 50, 20, 0, ConstraintWidget.UNKNOWN);
      expect([w.mResolvedHorizontal, w.mResolvedVertical], [false, false]);
    });

    test('the solving-pass flags are cleared by resetSolvingPassFlag and by '
        'resetFinalResolution (CW 142-163, 223-232)', () {
      final w = ConstraintWidget.sizeNamed('w', 50, 20)
        ..markHorizontalSolvingPassDone();
      expect(w.isHorizontalSolvingPassDone(), isTrue);
      expect(w.isVerticalSolvingPassDone(), isFalse);
      w
        ..markVerticalSolvingPassDone()
        ..resetSolvingPassFlag();
      expect(w.isHorizontalSolvingPassDone(), isFalse);
      expect(w.isVerticalSolvingPassDone(), isFalse);
      w
        ..markHorizontalSolvingPassDone()
        ..markVerticalSolvingPassDone()
        ..setFinalHorizontal(0, 50)
        ..resetFinalResolution();
      expect(w.isHorizontalSolvingPassDone(), isFalse);
      expect(w.isVerticalSolvingPassDone(), isFalse);
      expect(w.isResolvedHorizontally(), isFalse);
    });

    test('hasDanglingDimension counts a baseline link on the vertical axis '
        '(CW 251-261)', () {
      final root = ConstraintWidgetContainer.sizeNamed('root', 400, 400);
      final a = ConstraintWidget.sizeNamed('a', 10, 10);
      final w = ConstraintWidget.sizeNamed('w', 10, 10);
      root
        ..add(a)
        ..add(w);
      expect(w.hasDanglingDimension(ConstraintWidget.HORIZONTAL), isTrue);
      expect(w.hasDanglingDimension(ConstraintWidget.VERTICAL), isTrue);
      w.immediateConnect(_left, root, _left, 0, 0);
      expect(w.hasDanglingDimension(ConstraintWidget.HORIZONTAL), isTrue);
      w.immediateConnect(_right, root, _right, 0, 0);
      expect(w.hasDanglingDimension(ConstraintWidget.HORIZONTAL), isFalse);
      w.immediateConnect(_top, root, _top, 0, 0);
      w.immediateConnect(_baseline, a, _baseline, 0, 0);
      expect(w.hasDanglingDimension(ConstraintWidget.VERTICAL), isFalse);
    });

    test('hasResolvedTargets needs both targets final and takes the margins '
        'off, gone margins included (CW 264-279)', () {
      final root = ConstraintWidgetContainer.sizeNamed('root', 400, 400);
      final a = ConstraintWidget.sizeNamed('a', 10, 10);
      final w = ConstraintWidget.sizeNamed('w', 10, 10);
      root
        ..add(a)
        ..add(w);
      w.immediateConnect(_left, a, _right, 10, 3);
      w.immediateConnect(_right, root, _right, 20, 0);
      expect(w.hasResolvedTargets(ConstraintWidget.HORIZONTAL, 0), isFalse);
      a.mRight.setFinalValue(50);
      expect(w.hasResolvedTargets(ConstraintWidget.HORIZONTAL, 0), isFalse);
      root.mRight.setFinalValue(200);
      // (200 - 20) - (50 + 10) = 120.
      expect(w.hasResolvedTargets(ConstraintWidget.HORIZONTAL, 120), isTrue);
      expect(w.hasResolvedTargets(ConstraintWidget.HORIZONTAL, 121), isFalse);
      // A gone target: its link uses the gone margin, 3.
      a.setVisibility(ConstraintWidget.GONE);
      expect(w.hasResolvedTargets(ConstraintWidget.HORIZONTAL, 127), isTrue);
      expect(w.hasResolvedTargets(ConstraintWidget.HORIZONTAL, 128), isFalse);
      expect(w.hasResolvedTargets(ConstraintWidget.VERTICAL, 0), isFalse);
    });

    test('setLastMeasureSpec stores the specs and clears the measure '
        'request (CW 428-444)', () {
      final w = ConstraintWidget.sizeNamed('w', 10, 10);
      expect(w.getLastHorizontalMeasureSpec(), 0);
      expect(w.getLastVerticalMeasureSpec(), 0);
      expect(w.isMeasureRequested(), isTrue);
      w.setLastMeasureSpec(_exactly(10), _atMost(800));
      expect(w.getLastHorizontalMeasureSpec(), 0x4000000A);
      expect(w.getLastVerticalMeasureSpec(), 0x80000320);
      expect(w.isMeasureRequested(), isFalse);
      w.ensureMeasureRequested();
      expect(w.isMeasureRequested(), isTrue);
      w.setVisibility(ConstraintWidget.GONE);
      expect(w.isMeasureRequested(), isFalse);
    });

    test('the raw margins ignore visibility, gone margins and links '
        '(CW 1264-1287)', () {
      final root = ConstraintWidgetContainer.sizeNamed('root', 400, 400);
      final a = ConstraintWidget.sizeNamed('a', 10, 10)
        ..setVisibility(ConstraintWidget.GONE);
      final w = ConstraintWidget.sizeNamed('w', 10, 10)
        ..setVisibility(ConstraintWidget.GONE);
      root
        ..add(a)
        ..add(w);
      w.immediateConnect(_left, a, _right, 7, 1);
      w.mRight.mMargin = 5; // unlinked, as for a match-parent axis
      w.immediateConnect(_top, root, _top, 3, 0);
      w.immediateConnect(_bottom, a, _bottom, 4, 2);
      expect(w.mLeft.getMargin(), 0);
      expect(w.getHorizontalMargin(), 12);
      expect(w.getVerticalMargin(), 7);
    });

    test('a guideline is resolved by setFinalValue until a solve holds it '
        '(GL 213-230)', () {
      final root = ConstraintWidgetContainer.sizeNamed('root', 400, 400);
      final g = Guideline()
        ..setOrientation(Guideline.vertical)
        ..setGuideBegin(20);
      root.add(g);
      expect(g.isResolvedHorizontally(), isFalse);
      g.setFinalValue(37);
      expect(g.mAnchor.getFinalValue(), 37);
      expect(g.isResolvedHorizontally(), isTrue);
      expect(g.isResolvedVertically(), isTrue);
      g.addToSolver(LinearSystem(), false);
      expect(g.isResolvedHorizontally(), isFalse);
      expect(g.mAnchor.hasFinalValue(), isTrue);
    });

    test("a barrier answers isResolved with its own flag, not its anchors' "
        'final values (BR 91-98)', () {
      final root = ConstraintWidgetContainer.sizeNamed('root', 400, 400);
      final w = ConstraintWidget.sizeNamed('w', 10, 10)
        ..setVisibility(ConstraintWidget.GONE);
      final b = Barrier.named('b')
        ..setAllowsGoneWidget(false)
        ..add(w);
      root
        ..add(w)
        ..add(b);
      // Every reference is gone and not allowed: allSolved resolves it.
      expect(b.allSolved(), isTrue);
      expect(b.isResolvedHorizontally(), isTrue);
      b.addToSolver(LinearSystem(), false);
      // Consumed, though setFinalHorizontal's flag and final values stay.
      expect(b.mResolvedHorizontal, isTrue);
      expect(b.mLeft.hasFinalValue() && b.mRight.hasFinalValue(), isTrue);
      expect(b.isResolvedHorizontally(), isFalse);
      expect(b.isResolvedVertically(), isFalse);
    });

    test('a barrier that references a consumed barrier is solved, as at '
        'J0', () {
      // Java J0 (VOpDriver core, with the echo measurer: R 894 827;
      // w w1 60 70;b b0;add b0;b b1;add b1;w w4 20 36;add w4;b b2;add b2;
      // b top;add top;w t0 33 49;v w1 8;bg b0 0;ref b0 w1;bt b1 1;
      // ref b1 b0;bt b2 1;ref b2 w4;ref top b1;ref top b2;c t0 L top R 10;
      // c t0 R root R 5): b1 (20, 0) and top (20, 0). The port's earlier
      // model, which let the anchors' final values stand for b0's
      // resolution, pinned b1 and top at (0, 0).
      final root = ConstraintWidgetContainer.rect(0, 0, 894, 827)
        ..setDebugName('root');
      final w1 = ConstraintWidget.sizeNamed('w1', 60, 70);
      final b0 = Barrier.named('b0');
      final b1 = Barrier.named('b1');
      final w4 = ConstraintWidget.sizeNamed('w4', 20, 36);
      final b2 = Barrier.named('b2');
      final top = Barrier.named('top');
      final t0 = ConstraintWidget.sizeNamed('t0', 33, 49);
      root
        ..add(b0)
        ..add(b1)
        ..add(w4)
        ..add(b2)
        ..add(top);
      w1.setVisibility(ConstraintWidget.GONE);
      b0
        ..setAllowsGoneWidget(false)
        ..add(w1);
      b1
        ..setBarrierType(Barrier.right)
        ..add(b0);
      b2
        ..setBarrierType(Barrier.right)
        ..add(w4);
      top
        ..add(b1)
        ..add(b2);
      t0.connect(_left, top, _right, 10);
      t0.connect(_right, root, _right, 5);
      root
        ..setMeasurer(_Echo())
        ..setOptimizationLevel(0)
        ..measure(
          0,
          BasicMeasure.EXACTLY,
          894,
          BasicMeasure.EXACTLY,
          827,
          0,
          0,
          0,
          0,
        );
      String frame(ConstraintWidget c) =>
          '${c.getDebugName()}: (${c.getX()}, ${c.getY()}) '
          '${c.getWidth()} x ${c.getHeight()}';
      expect(
        root.getChildren().map(frame).join(' | '),
        'b0: (0, 0) 0 x 0 | b1: (20, 0) 0 x 0 | w4: (0, 0) 20 x 36 | '
        'b2: (20, 0) 0 x 0 | top: (20, 0) 0 x 0',
      );
    });
  });

  group('resetMeasureState', () {
    // A child configured the same way twice: one is laid out and given every
    // kind of derived state, then reset; the other is fresh.
    void configure(
      ConstraintWidgetContainer root,
      ConstraintWidget a,
      ConstraintWidget w,
    ) {
      w
        ..setHorizontalDimensionBehaviour(_mc)
        ..setVerticalDimensionBehaviour(_wrap)
        ..setHorizontalMatchStyle(
          ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
          0,
          300,
          1,
        )
        ..setDimensionRatio(0, ConstraintWidget.UNKNOWN)
        ..setHorizontalBiasPercent(0.3)
        ..setMinHeight(4);
      w.immediateConnect(_left, root, _left, 8, 0);
      w.immediateConnect(_right, root, _right, 6, 2);
      w.immediateConnect(_top, a, _bottom, 3, ConstraintAnchor.unsetGoneMargin);
    }

    ConstraintWidgetContainer build(ConstraintWidget w) {
      final root = ConstraintWidgetContainer.sizeNamed('root', 400, 400);
      final a = ConstraintWidget.sizeNamed('a', 40, 40)
        ..setBaselineDistance(30);
      root
        ..add(a)
        ..add(w);
      a.immediateConnect(_left, root, _left, 0, 0);
      configure(root, a, w);
      return root;
    }

    void dirty(ConstraintWidget w) {
      w
        ..setFinalHorizontal(5, 9)
        ..setFinalBaseline(7)
        ..markHorizontalSolvingPassDone()
        ..markVerticalSolvingPassDone()
        ..mCenter.setFinalValue(3)
        ..mOffsetX = 2
        ..mOffsetY = 3
        ..mHorizontalResolution = ConstraintWidget.DIRECT
        ..mVerticalResolution = ConstraintWidget.DIRECT
        ..mResolvedHasRatio = true
        ..mResolvedDimensionRatioSide = ConstraintWidget.VERTICAL
        ..mResolvedDimensionRatio = 2
        ..setInVirtualLayout(true)
        ..setInBarrier(ConstraintWidget.HORIZONTAL, true)
        ..setInBarrier(ConstraintWidget.VERTICAL, true)
        ..mWidthOverride = 11
        ..mHeightOverride = 12;
      w.isTerminalWidget[0] = false;
      w.mResolvedMatchConstraintDefault[1] =
          ConstraintWidget.MATCH_CONSTRAINT_RATIO_RESOLVED;
    }

    test('returns a laid-out widget to a fresh one, but for what Android '
        'keeps', () {
      final used = ConstraintWidget.sizeNamed('w', 0, 0);
      final measurer = _ContentMeasurer();
      final root = build(used);
      measurer.content[used] = const _Content.text(500, 20, 15);
      ViewHost(root, measurer)
        ..optimizationLevel = 0
        ..measure(_exactly(400), _exactly(400));
      // Spread between its links, capped at its match max.
      expect(used.getWidth(), 300);
      dirty(used);
      used.setLastMeasureSpec(_exactly(1), _exactly(2));
      used.setHasBaseline(true);
      used.resetMeasureState();

      final fresh = ConstraintWidget.sizeNamed('w', 0, 0);
      build(fresh);
      expect(_state(used), _state(fresh));
      // Kept, as Android's reset() keeps them: setFinalHorizontal's and
      // setFinalBaseline's flags, the solving-pass flags, the baseline flag
      // and the last specs.
      expect(_kept(used), {
        'resolved': [true, true],
        'solving passes': [true, true],
        'has baseline': true,
        'last specs': [_exactly(1), _exactly(2)],
      });
      // With the flag kept and the position reset, the next
      // setFinalHorizontal returns at once (CW 166-169).
      used.setFinalHorizontal(40, 90);
      expect([used.mX, used.mLeft.hasFinalValue()], [0, false]);
    });

    test('keeps a fixed size: the caller owns it', () {
      final w = ConstraintWidget.sizeNamed('w', 70, 30)
        ..setHorizontalDimensionBehaviour(_fixed)
        ..setVerticalDimensionBehaviour(_parent)
        ..setFrame(0, 0, 90, 40);
      w.resetMeasureState();
      expect([w.mWidth, w.mHeight], [90, 0]);
    });

    test('of a guideline zeroes its size and keeps its own flag', () {
      final root = ConstraintWidgetContainer.sizeNamed('root', 400, 300);
      final g = Guideline()
        ..setOrientation(Guideline.vertical)
        ..setGuideBegin(25);
      root.add(g);
      root.layout();
      expect(g.getHeight(), 300);
      g.setFinalValue(25);
      g.resetMeasureState();
      final fresh = Guideline()
        ..setOrientation(Guideline.vertical)
        ..setGuideBegin(25);
      ConstraintWidgetContainer.sizeNamed('root', 400, 300).add(fresh);
      expect(_state(g), _state(fresh));
      // reset() leaves the guideline's own flag (GL 213-230), but not its
      // anchor's final value, so addToSolver does not consume the flag.
      expect(_kept(g)['guideline resolved'], isTrue);
      expect(g.mAnchor.hasFinalValue(), isFalse);
      expect(g.isResolvedHorizontally(), isTrue);
    });

    test('of a barrier keeps its flags', () {
      final root = ConstraintWidgetContainer.sizeNamed('root', 400, 300);
      final w = ConstraintWidget.sizeNamed('w', 10, 10)
        ..setVisibility(ConstraintWidget.GONE);
      final b = Barrier.named('b')
        ..setAllowsGoneWidget(false)
        ..setMargin(5)
        ..add(w);
      root
        ..add(w)
        ..add(b);
      // Every reference is gone and not allowed: allSolved resolves the
      // barrier at its margin.
      expect(b.allSolved(), isTrue);
      expect([b.getX(), b.mResolvedHorizontal], [5, true]);
      b.resetMeasureState();
      final fresh = Barrier.named('b')
        ..setAllowsGoneWidget(false)
        ..setMargin(5)
        ..add(w);
      ConstraintWidgetContainer.sizeNamed('root', 400, 300).add(fresh);
      expect(_state(b), _state(fresh));
      expect(_kept(b)['resolved'], [true, false]);
      expect(_kept(b)['barrier resolved'], isTrue);
      // The flag outlives the x the reset zeroed: allSolved resolves the
      // barrier again, but its setFinalHorizontal returns at once, so it
      // stays at 0 (Android's live views, below).
      expect(b.allSolved(), isTrue);
      expect([b.getX(), b.mLeft.hasFinalValue()], [0, false]);
    });
  });

  group('in place through ViewHost, as on Android', () {
    void barrierStep(_Scene s, {required bool wGone}) {
      final w = _box(
        s,
        'W',
        50,
        50,
        visibility: wGone ? ConstraintWidget.GONE : ConstraintWidget.VISIBLE,
      );
      final bar = s.get('bar', Barrier.new)
        ..setBarrierType(Barrier.right)
        ..setAllowsGoneWidget(false)
        ..setMargin(5)
        ..removeAllIds()
        ..add(w);
      final k = _box(s, 'K', 30, 30);
      w.connect(_left, s.root, _left, 100);
      k.connect(_left, bar, _right, 0);
    }

    // ResetProbe's sequence: W 50 x 50 at left 100, a RIGHT barrier over W
    // that does not allow gone widgets, with margin 5, and K linked to the
    // barrier's right; W gone, visible, then gone again, each state applied
    // to the same widgets. The op lists (tool/parity/java/probes and the
    // RoboOracle, -Drobo.inplace=1): rp:1-gone is `R 400 800;w W 50 50;add W;
    // b bar;add bar;bt bar 1;bg bar 0;bm bar 5;ref bar W;w K 30 30;add K;
    // v W 8;c W L root L 100;c K L bar R 0;ct W box 50 50 -1;
    // ct K box 30 30 -1;cspec E 400 E 800`; rp:2-visible appends
    // `;L;v W 0;sw W 50;sh W 50;sw K 30;sh K 30;adeps`, and rp:3-gone appends
    // the same with `v W 8` after that. rp:1-gone-L is rp:1-gone with
    // `;L;sw W 50;sh W 50;sw K 30;sh K 30;adeps`: the gone state laid out
    // again with nothing changed.
    const goneFresh =
        'root 400 x 800 | W: gone, 0 x 0 | bar: (5, 0) 0 x 0 | '
        'K: (5, 0) 30 x 30';
    const visible =
        'root 400 x 800 | W: (100, 0) 50 x 50 | bar: (155, 0) 0 x 0 | '
        'K: (155, 0) 30 x 30';
    const goneKept =
        'root 400 x 800 | W: gone, 0 x 0 | bar: (0, 0) 0 x 0 | '
        'K: (0, 0) 30 x 30';

    test('a barrier that its gone references resolved keeps its flag '
        '(level 0)', () {
      // allSolved resolves the barrier in the first measure and sets its
      // flag, which nothing clears without the Direct pass: reset() keeps
      // it and zeroes the barrier's x, so the third measure's allSolved
      // leaves the barrier at 0 (setFinalHorizontal returns at once) and
      // addToSolver pins it there. Android's live views (RoboOracle at level
      // 0, rp:1-gone, rp:2-visible, rp:3-gone) and Java's ResetProbe give
      // exactly these frames; a fresh build of the third state gives bar 5
      // (VOpDriver J0, fs:bar-fresh-gone, the same as rp:1-gone).
      final s = _Scene();
      barrierStep(s, wGone: true);
      s.measure(_exactly(400), _exactly(800));
      expect(s.frames(), goneFresh);
      final bar = s.by['bar']! as Barrier;
      expect(bar.mResolvedHorizontal, isTrue, reason: 'never consumed');
      barrierStep(s, wGone: false);
      s.measure(_exactly(400), _exactly(800));
      expect(s.frames(), visible);
      barrierStep(s, wGone: true);
      s.measure(_exactly(400), _exactly(800));
      expect(s.frames(), goneKept);

      // The fresh build, and the same build laid out again: Android's live
      // views give bar 0 there too (rp:1-gone-L, and the dirty second
      // layout of rp:1-gone).
      final fresh = _Scene();
      barrierStep(fresh, wGone: true);
      fresh.measure(_exactly(400), _exactly(800));
      expect(fresh.frames(), goneFresh);
      barrierStep(fresh, wGone: true);
      fresh.measure(_exactly(400), _exactly(800));
      expect(fresh.frames(), goneKept);
    });

    test('a barrier that its gone references resolved is placed again by '
        'Direct (level 257)', () {
      // At OPTIMIZATION_STANDARD, Direct.solvingPass clears every widget's
      // resolution (resetFinalResolution) in the first solver pass of each
      // measure, before anything reads it, so allSolved places the barrier at
      // its margin again: Android's live views (RoboOracle at 257,
      // rp:3-gone) and Java's ResetProbe at 257 give the fresh build's frames
      // in the third state, and in a second layout of the first.
      final s = _Scene(level: Optimizer.OPTIMIZATION_STANDARD);
      barrierStep(s, wGone: true);
      s.measure(_exactly(400), _exactly(800));
      expect(s.frames(), goneFresh);
      barrierStep(s, wGone: false);
      s.measure(_exactly(400), _exactly(800));
      expect(s.frames(), visible);
      barrierStep(s, wGone: true);
      s.measure(_exactly(400), _exactly(800));
      expect(s.frames(), goneFresh);
      barrierStep(s, wGone: true);
      s.measure(_exactly(400), _exactly(800));
      expect(s.frames(), goneFresh);
    });

    test('the barrier sequence at every level', () {
      // Android's live views (RoboOracle, rp:3-gone and rp:1-gone-L at each
      // level): without OPTIMIZATION_DIRECT (0, 64, 192 and 256) the third
      // state keeps the flag and gives bar 0; with it (257, 321 and 449)
      // Direct's resetFinalResolution clears every flag before anything
      // reads it, so the third state equals the fresh build, as Java's
      // ResetProbe gives at 257.
      for (final level in [0, 64, 192, 256, 257, 321, 449]) {
        final direct = Optimizer.enabled(
          level,
          Optimizer.OPTIMIZATION_DIRECT,
        );
        final s = _Scene(level: level);
        for (final gone in [true, false, true]) {
          barrierStep(s, wGone: gone);
          s.measure(_exactly(400), _exactly(800));
        }
        expect(
          s.frames(),
          direct ? goneFresh : goneKept,
          reason: 'level $level',
        );
        final again = _Scene(level: level);
        for (var i = 0; i < 2; i++) {
          barrierStep(again, wGone: true);
          again.measure(_exactly(400), _exactly(800));
        }
        expect(
          again.frames(),
          direct ? goneFresh : goneKept,
          reason: 'level $level, laid out again',
        );
      }
    });

    test('a measure CACHE_MEASURES would keep (level 256)', () {
      // Java's op lists: fs:text-fresh-200 is `R 400 800;w T 0 0;add T;
      // hb T W;vb T W;c T L root L 0;c T T root T 0;ct T text 200 20 -1;
      // cspec E 400 E 800`; fs:text-inplace-nondirty is the same with
      // `ct T text 100 20 -1`, then `;L;ct T text 200 20 -1` appended.
      void step(_Scene s, int textWidth) {
        final t = s.get('T', ConstraintWidget.new)
          ..setHorizontalDimensionBehaviour(_wrap)
          ..setVerticalDimensionBehaviour(_wrap)
          ..resetAnchors();
        t.connect(_left, s.root, _left, 0);
        t.connect(_top, s.root, _top, 0);
        s.measurer.content[t] = _Content.text(textWidth, 20);
      }

      final s = _Scene(level: Optimizer.OPTIMIZATION_CACHE_MEASURES);
      step(s, 100);
      s.measure(_exactly(400), _exactly(800));
      expect(s.frames(), 'root 400 x 800 | T: (0, 0) 100 x 20');
      step(s, 200);
      // Every condition of CL 847-854 holds before the reset: the view's
      // size is the widget's, no measure is requested, and the next specs
      // are the last ones.
      final t = s.by['T']!;
      expect(t.isMeasureRequested(), isFalse);
      expect(s.measurer.measuredWidthOf(t), t.getWidth());
      expect(t.getLastHorizontalMeasureSpec(), _atMost(400));
      expect(t.getLastVerticalMeasureSpec(), _atMost(800));
      s.measure(_exactly(400), _exactly(800));
      // The view was measured again: a cache hit leaves its measured size.
      // (Java J256 measures once, with no hit: meas=1 hits=0.)
      expect(s.measurer.measuredWidthOf(t), 200);

      final fresh = _Scene(level: Optimizer.OPTIMIZATION_CACHE_MEASURES);
      step(fresh, 200);
      fresh.measure(_exactly(400), _exactly(800));
      expect(s.frames(), fresh.frames());
      // Java J256 (fs:text-fresh-200); Java's in-place L, without the
      // reset, keeps 100 x 20 from the cache (fs:text-inplace-nondirty).
      expect(s.frames(), 'root 400 x 800 | T: (0, 0) 200 x 20');
    });

    // Android's live views lay every in-place sequence of T2 out as a fresh
    // build of its final state at OPTIMIZATION_STANDARD (50,000 of 50,000),
    // where the Direct pass clears every resolved flag and the graph does not
    // run. At 0 and at CACHE_MEASURES (256), without Direct or the graph, the
    // only flag that outlives a measure is a barrier's (its addToSolver does
    // not clear the flags allSolved set, and nothing else sets one there), so
    // a sequence without a barrier equals its fresh build there too. The
    // GRAPH levels keep the graph's runs and nodes as well, which the
    // persistent_layout_test scenarios pin with Android's values.
    test('random in-place sequences equal their fresh builds where Android\'s '
        'do (levels 257, 0 and 256)', () {
      var compared = 0;
      for (final level in [
        Optimizer.OPTIMIZATION_STANDARD,
        Optimizer.OPTIMIZATION_NONE,
        Optimizer.OPTIMIZATION_CACHE_MEASURES,
      ]) {
        for (var seed = 0; seed < 300; seed++) {
          final r = math.Random(seed);
          final count = 2 + r.nextInt(5);
          final steps = [_randomLayout(r, count)];
          final edits = 1 + r.nextInt(3);
          for (var e = 0; e < edits; e++) {
            steps.add(_edit(r, steps.last));
          }
          final widthSpec = r.nextInt(3) == 0 ? _atMost(360) : _exactly(360);
          final heightSpec = switch (r.nextInt(4)) {
            0 => _atMost(640),
            1 => _unspecified(),
            _ => _exactly(640),
          };
          final hasBarrier = steps.any(
            (layout) => layout.any((c) => c.kind == 'b'),
          );
          if (level != Optimizer.OPTIMIZATION_STANDARD && hasBarrier) {
            continue;
          }
          compared++;
          final inPlace = _Scene(level: level);
          for (final step in steps) {
            _apply(inPlace, step);
            inPlace.measure(widthSpec, heightSpec);
          }
          final fresh = _Scene(level: level);
          _apply(fresh, steps.last);
          fresh.measure(widthSpec, heightSpec);
          expect(
            inPlace.frames(),
            fresh.frames(),
            reason:
                'level $level, seed $seed: '
                '${steps.map(_describe).join(' => ')}',
          );
        }
      }
      // 300 at 257, and the 211 sequences without a barrier at 0 and 256.
      expect(compared, 300 + 2 * 211);
    });
  });
}

/// One child of a random layout: what a caller applies before a measure.
class _Child {
  _Child(this.name, this.kind);

  final String name;

  /// 'w' a regular widget, 'g' a vertical guideline, 'b' a barrier.
  final String kind;
  DimensionBehaviour h = _fixed;
  DimensionBehaviour v = _fixed;
  int width = 0;
  int height = 0;
  int visibility = ConstraintWidget.VISIBLE;
  _Content content = const _Content.box(0, 0);
  double ratio = 0;
  double hBias = 0.5;
  final List<(ConstraintAnchorType, String, ConstraintAnchorType, int)> links =
      [];
  int begin = 0; // guideline
  int barrierType = Barrier.left; // barrier
  int margin = 0;
  bool allowsGone = true;
  final List<String> refs = [];

  _Child copy() => _Child(name, kind)
    ..h = h
    ..v = v
    ..width = width
    ..height = height
    ..visibility = visibility
    ..content = content
    ..ratio = ratio
    ..hBias = hBias
    ..links.addAll(links)
    ..begin = begin
    ..barrierType = barrierType
    ..margin = margin
    ..allowsGone = allowsGone
    ..refs.addAll(refs);
}

String _describe(List<_Child> layout) => layout
    .map(
      (c) => switch (c.kind) {
        'g' => '${c.name}:g${c.begin}',
        'b' =>
          '${c.name}:b${c.barrierType}/${c.margin}/${c.allowsGone}'
              '${c.refs}',
        _ =>
          '${c.name}:${_behaviourName(c.h)}${_behaviourName(c.v)}'
              '${c.width}x${c.height}'
              'v${c.visibility}r${c.ratio}'
              '${c.links.map((l) => '${l.$1.name[0]}${l.$2}.${l.$3.name[0]}${l.$4}').join(',')}',
      },
    )
    .join(' ');

const _behaviours = [_fixed, _wrap, _mc, _parent];

String _behaviourName(DimensionBehaviour b) => switch (b) {
  DimensionBehaviour.fixed => 'F',
  DimensionBehaviour.wrapContent => 'W',
  DimensionBehaviour.matchConstraint => 'M',
  DimensionBehaviour.matchParent => 'P',
};

void _randomizeWidget(math.Random r, _Child c, List<_Child> earlier) {
  c
    ..h = _behaviours[r.nextInt(4)]
    ..v = _behaviours[r.nextInt(4)]
    ..width = 10 + r.nextInt(120)
    ..height = 10 + r.nextInt(80)
    ..visibility = r.nextInt(8) == 0
        ? ConstraintWidget.GONE
        : ConstraintWidget.VISIBLE
    ..content = r.nextBool()
        ? _Content.box(10 + r.nextInt(150), 10 + r.nextInt(60))
        : _Content.text(
            20 + r.nextInt(400),
            12 + r.nextInt(10),
            r.nextBool() ? 9 : -1,
          )
    ..ratio = (c.h == _mc || c.v == _mc) && r.nextInt(4) == 0
        ? 0.5 + r.nextInt(4) * 0.25
        : 0
    ..hBias = r.nextBool() ? 0.5 : 0.3;
  c.links.clear();
  final targets = ['root', ...earlier.map((e) => e.name)];
  String pick() => targets[r.nextInt(targets.length)];
  c.links.add((_left, pick(), r.nextBool() ? _left : _right, r.nextInt(20)));
  if (r.nextBool() || c.h == _mc) {
    c.links.add((_right, pick(), r.nextBool() ? _right : _left, r.nextInt(20)));
  }
  if (r.nextInt(5) == 0 && earlier.any((e) => e.kind == 'w')) {
    final target = earlier.where((e) => e.kind == 'w').first.name;
    c.links.add((_baseline, target, _baseline, 0));
  } else {
    c.links.add((_top, pick(), r.nextBool() ? _top : _bottom, r.nextInt(20)));
    if (r.nextBool() || c.v == _mc) {
      c.links.add((
        _bottom,
        pick(),
        r.nextBool() ? _bottom : _top,
        r.nextInt(20),
      ));
    }
  }
}

List<_Child> _randomLayout(math.Random r, int count) {
  final layout = <_Child>[];
  for (var i = 0; i < count; i++) {
    final roll = r.nextInt(8);
    final _Child c;
    if (roll == 0 && layout.isNotEmpty) {
      c = _Child('b$i', 'b')
        ..barrierType = r.nextInt(4)
        ..margin = r.nextInt(10)
        ..allowsGone = r.nextBool();
      for (final e in layout) {
        if (e.kind == 'w' && r.nextBool()) c.refs.add(e.name);
      }
    } else if (roll == 1) {
      c = _Child('g$i', 'g')..begin = r.nextInt(200);
    } else {
      c = _Child('w$i', 'w');
      _randomizeWidget(r, c, layout);
    }
    layout.add(c);
  }
  return layout;
}

List<_Child> _edit(math.Random r, List<_Child> layout) {
  final next = [for (final c in layout) c.copy()];
  final changes = 1 + r.nextInt(3);
  for (var k = 0; k < changes; k++) {
    final i = r.nextInt(next.length);
    final c = next[i];
    switch (c.kind) {
      case 'g':
        c.begin = r.nextInt(200);
      case 'b':
        c
          ..margin = r.nextInt(10)
          ..allowsGone = r.nextBool();
      default:
        switch (r.nextInt(5)) {
          case 0:
            c.visibility = c.visibility == ConstraintWidget.GONE
                ? ConstraintWidget.VISIBLE
                : ConstraintWidget.GONE;
          case 1:
            c.content = _Content.text(20 + r.nextInt(400), 14, 11);
          case 2:
            c
              ..width = 10 + r.nextInt(120)
              ..height = 10 + r.nextInt(80);
          default:
            _randomizeWidget(r, c, next.sublist(0, i));
        }
    }
  }
  return next;
}

/// The caller: the whole configuration of [layout] applied to [s]'s
/// widgets, as layout params are applied again by Android.
void _apply(_Scene s, List<_Child> layout) {
  for (final c in layout) {
    switch (c.kind) {
      case 'g':
        s.get(c.name, Guideline.new)
          ..setOrientation(Guideline.vertical)
          ..setGuideBegin(c.begin);
      case 'b':
        final b = s.get(c.name, Barrier.new)
          ..setBarrierType(c.barrierType)
          ..setMargin(c.margin)
          ..setAllowsGoneWidget(c.allowsGone)
          ..removeAllIds();
        for (final ref in c.refs) {
          b.add(s.by[ref]!);
        }
      default:
        final w = s.get(c.name, ConstraintWidget.new)
          ..setVisibility(c.visibility)
          ..setHorizontalDimensionBehaviour(c.h)
          ..setVerticalDimensionBehaviour(c.v)
          ..setHorizontalMatchStyle(
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
            0,
            0,
            1,
          )
          ..setVerticalMatchStyle(
            ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
            0,
            0,
            1,
          )
          ..setDimensionRatio(c.ratio, ConstraintWidget.UNKNOWN)
          ..setHorizontalBiasPercent(c.hBias)
          ..resetAnchors();
        if (c.h == _fixed) w.setWidth(c.width);
        if (c.v == _fixed) w.setHeight(c.height);
        for (final (from, target, to, margin) in c.links) {
          w.immediateConnect(
            from,
            s.by[target] ?? s.root,
            to,
            margin,
            ConstraintAnchor.unsetGoneMargin,
          );
        }
        s.measurer.content[w] = c.content;
    }
  }
}
