// ConstraintAnchor is the join between two widgets: every constraint in the
// system is one anchor pointing at another. Its connection rules are what stop
// a layout from expressing nonsense (a left edge tied to a top edge), and its
// final-value cache is what lets the dependency graph resolve a widget without
// the solver. Both are easy to break silently, so they are pinned here
// directly rather than only through whole layouts.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

ConstraintWidget widgetNamed(String name, {bool baseline = false}) {
  final w = ConstraintWidget.size(100, 20);
  w.setDebugName(name);
  if (baseline) {
    w.setHasBaseline(true);
    w.setBaselineDistance(15);
  }
  return w;
}

void main() {
  group('connection validity', () {
    test('same-type connections are always allowed', () {
      final a = widgetNamed('A');
      final b = widgetNamed('B');
      for (final type in const [
        ConstraintAnchorType.left,
        ConstraintAnchorType.right,
        ConstraintAnchorType.top,
        ConstraintAnchorType.bottom,
      ]) {
        expect(
          a.getAnchor(type)!.isValidConnection(b.getAnchor(type)),
          isTrue,
          reason: '$type to $type',
        );
      }
    });

    test('horizontal anchors accept only horizontal targets', () {
      final a = widgetNamed('A');
      final b = widgetNamed('B');
      expect(a.mLeft.isValidConnection(b.mRight), isTrue);
      expect(a.mRight.isValidConnection(b.mLeft), isTrue);
      expect(a.mLeft.isValidConnection(b.mTop), isFalse);
      expect(a.mRight.isValidConnection(b.mBottom), isFalse);
      expect(a.mLeft.isValidConnection(b.mBaseline), isFalse);
    });

    test('vertical anchors accept only vertical targets', () {
      final a = widgetNamed('A');
      final b = widgetNamed('B');
      expect(a.mTop.isValidConnection(b.mBottom), isTrue);
      expect(a.mBottom.isValidConnection(b.mTop), isTrue);
      expect(a.mTop.isValidConnection(b.mLeft), isFalse);
      expect(a.mBottom.isValidConnection(b.mRight), isFalse);
    });

    test('a guideline exposes one anchor, on its own axis only', () {
      final a = widgetNamed('A');
      final vertical = Guideline()..setOrientation(Guideline.vertical);
      final horizontal = Guideline()..setOrientation(Guideline.horizontal);

      // A vertical guideline is a vertical line, so it answers to the
      // horizontal edges and to nothing else.
      final verticalAnchor = vertical.getAnchor(ConstraintAnchorType.left);
      expect(verticalAnchor, isNotNull);
      expect(verticalAnchor, same(vertical.getGuidelineAnchor()));
      expect(vertical.getAnchor(ConstraintAnchorType.right), same(verticalAnchor));
      expect(vertical.getAnchor(ConstraintAnchorType.top), isNull);
      expect(a.mLeft.isValidConnection(verticalAnchor), isTrue);

      final horizontalAnchor = horizontal.getAnchor(ConstraintAnchorType.top);
      expect(horizontalAnchor, isNotNull);
      expect(horizontal.getAnchor(ConstraintAnchorType.left), isNull);
      expect(a.mTop.isValidConnection(horizontalAnchor), isTrue);
    });

    test('an edge may target a guideline centre anchor', () {
      // Guidelines built through setOrientation expose a left/top anchor, so
      // this rule is only reachable by constructing the centre anchor
      // directly. It is carried over from the Java port, where a guideline's
      // anchor was typed centerX/centerY, and it still guards the case of a
      // guideline handed to the solver that way.
      final a = widgetNamed('A');
      final vertical = Guideline()..setOrientation(Guideline.vertical);
      final horizontal = Guideline()..setOrientation(Guideline.horizontal);

      final centerX = ConstraintAnchor(vertical, ConstraintAnchorType.centerX);
      final centerY = ConstraintAnchor(horizontal, ConstraintAnchorType.centerY);
      expect(a.mLeft.isValidConnection(centerX), isTrue);
      expect(a.mRight.isValidConnection(centerX), isTrue);
      expect(a.mTop.isValidConnection(centerY), isTrue);
      expect(a.mBottom.isValidConnection(centerY), isTrue);

      // The same anchor type on an ordinary widget stays invalid: only a
      // guideline gets the exemption.
      final b = widgetNamed('B');
      final plainCenterX = ConstraintAnchor(b, ConstraintAnchorType.centerX);
      expect(a.mLeft.isValidConnection(plainCenterX), isFalse);
    });

    test('baseline connections need a baseline on both sides', () {
      final withBaseline = widgetNamed('A', baseline: true);
      final other = widgetNamed('B', baseline: true);
      final without = widgetNamed('C');

      expect(withBaseline.mBaseline.isValidConnection(other.mBaseline), isTrue);
      expect(
        withBaseline.mBaseline.isValidConnection(without.mBaseline),
        isFalse,
      );
      expect(
        without.mBaseline.isValidConnection(withBaseline.mBaseline),
        isFalse,
      );
      // A baseline can still ride a vertical edge, but never a horizontal one.
      expect(withBaseline.mBaseline.isValidConnection(other.mTop), isTrue);
      expect(withBaseline.mBaseline.isValidConnection(other.mLeft), isFalse);
      expect(withBaseline.mBaseline.isValidConnection(other.mRight), isFalse);
    });

    test('center accepts every edge but not baseline or a half-center', () {
      final a = widgetNamed('A');
      final b = widgetNamed('B');
      final center = a.getAnchor(ConstraintAnchorType.center)!;
      expect(center.isValidConnection(b.mLeft), isTrue);
      expect(center.isValidConnection(b.mBottom), isTrue);
      expect(center.isValidConnection(b.mBaseline), isFalse);
      expect(
        center.isValidConnection(b.getAnchor(ConstraintAnchorType.centerX)),
        isFalse,
      );
      expect(
        center.isValidConnection(b.getAnchor(ConstraintAnchorType.centerY)),
        isFalse,
      );
    });

    test('half-center anchors are never a valid source', () {
      final a = widgetNamed('A');
      final b = widgetNamed('B');
      for (final type in const [
        ConstraintAnchorType.centerX,
        ConstraintAnchorType.centerY,
        ConstraintAnchorType.none,
      ]) {
        final anchor = a.getAnchor(type);
        if (anchor == null) continue;
        expect(anchor.isValidConnection(b.mLeft), isFalse, reason: '$type');
      }
    });

    test('a null target is never valid', () {
      expect(widgetNamed('A').mLeft.isValidConnection(null), isFalse);
    });
  });

  group('connecting and disconnecting', () {
    test('connect records the target, margins, and reverse dependency', () {
      final a = widgetNamed('A');
      final b = widgetNamed('B');

      expect(a.mLeft.connect(b.mRight, 12, 4), isTrue);
      expect(a.mLeft.isConnected(), isTrue);
      expect(a.mLeft.mTarget, same(b.mRight));
      expect(a.mLeft.getMargin(), 12);
      expect(b.mRight.hasDependents(), isTrue);
      expect(b.mRight.getDependents(), contains(a.mLeft));
    });

    test('an invalid connect is refused and changes nothing', () {
      final a = widgetNamed('A');
      final b = widgetNamed('B');
      expect(a.mLeft.connect(b.mTop, 8), isFalse);
      expect(a.mLeft.isConnected(), isFalse);
      expect(b.mTop.hasDependents(), isFalse);
    });

    test('forceConnection bypasses the rules', () {
      final a = widgetNamed('A');
      final b = widgetNamed('B');
      expect(a.mLeft.connect(b.mTop, 8, 0, true), isTrue);
      expect(a.mLeft.isConnected(), isTrue);
    });

    test('connecting to null resets the anchor', () {
      final a = widgetNamed('A');
      final b = widgetNamed('B');
      a.mLeft.connect(b.mRight, 12, 4);
      expect(a.mLeft.connect(null, 0), isTrue);
      expect(a.mLeft.isConnected(), isFalse);
      expect(a.mLeft.getMargin(), 0);
    });

    test('reset clears target, margins, and the final value', () {
      final a = widgetNamed('A');
      final b = widgetNamed('B');
      a.mLeft.connect(b.mRight, 12, 4);
      a.mLeft.setFinalValue(99);

      a.mLeft.reset();
      expect(a.mLeft.isConnected(), isFalse);
      expect(a.mLeft.getMargin(), 0);
      expect(a.mLeft.mGoneMargin, ConstraintAnchor.unsetGoneMargin);
      expect(a.mLeft.getFinalValue(), 0);
      expect(a.mLeft.getDependents(), anyOf(isNull, isEmpty));
    });

    test('margins only take on a connected anchor', () {
      final a = widgetNamed('A');
      final b = widgetNamed('B');

      // Setting a margin on a dangling anchor is a no-op: there is nothing for
      // it to be a margin from.
      a.mLeft.setMargin(20);
      expect(a.mLeft.getMargin(), 0);

      a.mLeft.connect(b.mRight, 0);
      a.mLeft.setMargin(20);
      a.mLeft.setGoneMargin(6);
      expect(a.mLeft.getMargin(), 20);
      expect(a.mLeft.mGoneMargin, 6);
    });

    test('the margin reported is the gone margin when the target is gone', () {
      final a = widgetNamed('A');
      final b = widgetNamed('B');
      a.mLeft.connect(b.mRight, 20, 6);
      expect(a.mLeft.getMargin(), 20);

      b.setVisibility(ConstraintWidget.GONE);
      expect(a.mLeft.getMargin(), 6);
    });
  });

  group('geometry helpers', () {
    test('getOpposite pairs the two edges of an axis', () {
      final a = widgetNamed('A');
      expect(a.mLeft.getOpposite(), same(a.mRight));
      expect(a.mRight.getOpposite(), same(a.mLeft));
      expect(a.mTop.getOpposite(), same(a.mBottom));
      expect(a.mBottom.getOpposite(), same(a.mTop));
      // Anchors that are not one of a pair have no opposite.
      expect(a.mBaseline.getOpposite(), isNull);
      expect(a.getAnchor(ConstraintAnchorType.center)?.getOpposite(), isNull);
    });

    test('isVerticalAnchor splits the axes', () {
      final a = widgetNamed('A');
      expect(a.mLeft.isVerticalAnchor(), isFalse);
      expect(a.mRight.isVerticalAnchor(), isFalse);
      expect(a.mTop.isVerticalAnchor(), isTrue);
      expect(a.mBottom.isVerticalAnchor(), isTrue);
      expect(a.mBaseline.isVerticalAnchor(), isTrue);
    });

    test('the final value is a cache that can be invalidated', () {
      final a = widgetNamed('A');
      expect(a.mLeft.getFinalValue(), 0);

      a.mLeft.setFinalValue(42);
      expect(a.mLeft.getFinalValue(), 42);

      a.mLeft.resetFinalResolution();
      expect(a.mLeft.getFinalValue(), 0);
    });

    test('centered dependents are detected through the opposite anchor', () {
      final a = widgetNamed('A');
      final b = widgetNamed('B');

      // One-sided: b hangs off a's right edge, nothing is centered on it.
      b.mLeft.connect(a.mRight, 0);
      expect(a.mRight.hasCenteredDependents(), isFalse);

      // Two-sided: b is centered between a's edges, so a's anchors now carry a
      // centered dependent and cannot be resolved in isolation.
      b.mRight.connect(a.mRight, 0);
      expect(a.mRight.hasCenteredDependents(), isTrue);
    });

    test('a dependent without an opposite anchor fails the null check, as '
        "upstream's NullPointerException (ConstraintAnchor.java 68)", () {
      final failsNullCheck = throwsA(
        isA<TypeError>().having(
          (e) => '$e',
          'message',
          contains('Null check operator'),
        ),
      );
      final a = widgetNamed('A');
      final b = widgetNamed('B', baseline: true);

      // B's baseline hangs off A's bottom. A baseline has no opposite anchor,
      // and upstream dereferences it anyway.
      b.mBaseline.connect(a.mBottom, 0);
      expect(b.mBaseline.getOpposite(), isNull);
      expect(a.mBottom.hasCenteredDependents, failsNullCheck);

      // The dependents are read in the order they were linked (the port's
      // order for upstream's HashSet), and the loop returns at the first
      // centered one: a centered dependent linked before the baseline
      // answers, one linked after it is never reached.
      final first = widgetNamed('first');
      final centered = widgetNamed('centered');
      final baseline = widgetNamed('baseline', baseline: true);
      centered.mTop.connect(first.mBottom, 0);
      centered.mBottom.connect(a.mTop, 0);
      baseline.mBaseline.connect(first.mBottom, 0);
      expect(first.mBottom.hasCenteredDependents(), isTrue);

      final last = widgetNamed('last');
      final early = widgetNamed('early', baseline: true);
      final after = widgetNamed('after');
      early.mBaseline.connect(last.mBottom, 0);
      after.mTop.connect(last.mBottom, 0);
      after.mBottom.connect(a.mTop, 0);
      expect(last.mBottom.hasCenteredDependents, failsNullCheck);
    });

    test('toString names the owner and the edge', () {
      final a = widgetNamed('header');
      expect('${a.mLeft}', 'header:left');
      expect('${a.mBaseline}', 'header:baseline');
    });
  });
}
