// Value semantics of the public data types.
//
// These are not decoration. `Constrained.applyParentData` diffs every field
// with `!=` to decide between an in-place engine update, a model rebuild, and
// doing nothing at all (see caching_invalidation_test.dart). A `==` that is
// wrong in either direction silently breaks that: too loose and a real change
// is dropped, too strict and every frame rebuilds the model. `hashCode` has to
// agree with `==` for the same reason, since parent data ends up in sets and
// maps.
//
// toString is covered here too: it is what shows up in a widget inspector and
// in failed-expectation output, so it should stay readable.

import 'dart:ui';

import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_constraint_layout/src/debug/debug_scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dimension', () {
    test('constants are identical instances', () {
      expect(Dimension.wrapContent, same(Dimension.wrapContent));
      expect(Dimension.matchParent, same(Dimension.matchParent));
      expect(Dimension.matchConstraint, same(Dimension.matchConstraint));
    });

    test('fixed compares by pixels', () {
      expect(const Dimension.fixed(40), const Dimension.fixed(40));
      expect(
        const Dimension.fixed(40).hashCode,
        const Dimension.fixed(40).hashCode,
      );
      expect(const Dimension.fixed(40), isNot(const Dimension.fixed(41)));
      expect(const Dimension.fixed(40), isNot(Dimension.wrapContent));
    });

    test('match-constraint variants compare by every field', () {
      const spread = Dimension.spread(min: 10, max: 20);
      expect(spread, const Dimension.spread(min: 10, max: 20));
      expect(spread.hashCode, const Dimension.spread(min: 10, max: 20).hashCode);

      expect(spread, isNot(const Dimension.spread(min: 10)));
      expect(spread, isNot(const Dimension.spread(min: 10, max: 21)));
      // Same bounds, different mode: wrap and percent must not collide with
      // spread, or a mode switch would be treated as a no-op.
      expect(spread, isNot(const Dimension.constrainedWrap(min: 10, max: 20)));
      expect(
        const Dimension.percent(0.5),
        isNot(const Dimension.percent(0.6)),
      );
      expect(Dimension.matchConstraint, const Dimension.spread());
    });

    test('toString names the constructor that produced it', () {
      expect('${Dimension.wrapContent}', 'Dimension.wrapContent');
      expect('${Dimension.matchParent}', 'Dimension.matchParent');
      expect('${Dimension.matchConstraint}', 'Dimension.matchConstraint');
      expect('${const Dimension.fixed(40)}', 'Dimension.fixed(40.0)');
      expect('${const Dimension.spread()}', 'Dimension.matchConstraint');
      expect(
        '${const Dimension.spread(min: 10)}',
        'Dimension.spread(min: 10.0)',
      );
      expect(
        '${const Dimension.spread(min: 10, max: 20)}',
        'Dimension.spread(min: 10.0, max: 20.0)',
      );
      expect(
        '${const Dimension.constrainedWrap(max: 20)}',
        'Dimension.constrainedWrap(max: 20.0)',
      );
      expect('${const Dimension.percent(0.5)}', 'Dimension.percent(0.5)');
      expect(
        '${const Dimension.percent(0.5, max: 300)}',
        'Dimension.percent(0.5, max: 300.0)',
      );
    });
  });

  group('links', () {
    test('horizontal links compare by target, edge, and margins', () {
      const link = HorizontalLink.startOf(#a, margin: 8, goneMargin: 4);
      expect(link, const HorizontalLink.startOf(#a, margin: 8, goneMargin: 4));
      expect(
        link.hashCode,
        const HorizontalLink.startOf(#a, margin: 8, goneMargin: 4).hashCode,
      );

      expect(link, isNot(const HorizontalLink.startOf(#b, margin: 8, goneMargin: 4)));
      expect(link, isNot(const HorizontalLink.endOf(#a, margin: 8, goneMargin: 4)));
      expect(link, isNot(const HorizontalLink.startOf(#a, margin: 9, goneMargin: 4)));
      // The gone margin only matters when the target is gone, but it still has
      // to invalidate: a layout that goes gone later must use the new value.
      expect(link, isNot(const HorizontalLink.startOf(#a, margin: 8, goneMargin: 5)));
    });

    test('vertical links compare by target, edge, and margins', () {
      const link = VerticalLink.topOf(#a, margin: 8, goneMargin: 4);
      expect(link, const VerticalLink.topOf(#a, margin: 8, goneMargin: 4));
      expect(
        link.hashCode,
        const VerticalLink.topOf(#a, margin: 8, goneMargin: 4).hashCode,
      );
      expect(link, isNot(const VerticalLink.bottomOf(#a, margin: 8, goneMargin: 4)));
      expect(link, isNot(const VerticalLink.baselineOf(#a)));
    });

    test('circular links compare by target, angle, and radius', () {
      const link = CircularLink.around(#hub, angle: 45, radius: 100);
      expect(link, const CircularLink.around(#hub, angle: 45, radius: 100));
      expect(
        link.hashCode,
        const CircularLink.around(#hub, angle: 45, radius: 100).hashCode,
      );
      expect(link, isNot(const CircularLink.around(#hub, angle: 46, radius: 100)));
      expect(link, isNot(const CircularLink.around(#hub, angle: 45, radius: 101)));
      expect(link, isNot(const CircularLink.around(#other, angle: 45, radius: 100)));
    });

    test('an edge is not equal to a same-shaped link of the other axis', () {
      // Both hash over (target, edge, margin, goneMargin); the types must still
      // not compare equal, since parent data holds them in separate slots.
      expect(
        const HorizontalLink.leftOf(#a),
        isNot(const VerticalLink.topOf(#a)),
      );
    });
  });

  group('debug scene', () {
    test('connection toString reports type, edges, and modifiers', () {
      const plain = DebugConnection(
        type: DebugConnectionType.normal,
        sourcePoint: Offset(1, 2),
        targetPoint: Offset(3, 4),
        sourceEdge: DebugEdge.left,
        targetEdge: DebugEdge.right,
        horizontal: true,
      );
      expect(
        '$plain',
        'DebugConnection(DebugConnectionType.normal, DebugEdge.leftOffset(1.0, 2.0)'
            ' -> DebugEdge.rightOffset(3.0, 4.0))',
      );

      const decorated = DebugConnection(
        type: DebugConnectionType.chain,
        sourcePoint: Offset.zero,
        targetPoint: Offset.zero,
        sourceEdge: DebugEdge.top,
        targetEdge: DebugEdge.bottom,
        horizontal: false,
        margin: 8,
        targetIsParent: true,
        dashed: true,
        chainStyle: ChainStyle.packed,
      );
      final text = '$decorated';
      expect(text, contains('[parent]'));
      expect(text, contains('margin 8.0'));
      expect(text, contains('ChainStyle.packed'));
      expect(text, contains('dashed'));
    });

    test('widget box toString reports id, type, and flags', () {
      const bare = DebugWidgetBox(rect: Rect.fromLTWH(0, 0, 10, 10));
      expect('$bare', 'DebugWidgetBox(Rect.fromLTRB(0.0, 0.0, 10.0, 10.0))');

      const full = DebugWidgetBox(
        rect: Rect.fromLTWH(0, 0, 10, 10),
        idLabel: 'avatar',
        typeLabel: 'Image',
        invisible: true,
        virtual: true,
      );
      final text = '$full';
      expect(text, contains('#avatar'));
      expect(text, contains('Image'));
      expect(text, contains('invisible'));
      expect(text, contains('virtual'));
    });

    test('guideline, barrier, and scene toString', () {
      const vertical = DebugGuidelineInfo(
        vertical: true,
        position: 120,
        chipText: '25%',
      );
      expect('$vertical', 'DebugGuidelineInfo(x=120.0, "25%")');
      expect(
        '${const DebugGuidelineInfo(vertical: false, position: 8, chipText: '8')}',
        'DebugGuidelineInfo(y=8.0, "8")',
      );

      const barrier = DebugBarrierInfo(
        start: Offset.zero,
        end: Offset(10, 0),
        fadeDirection: Offset(0, 1),
      );
      expect(
        '$barrier',
        'DebugBarrierInfo(Offset(0.0, 0.0) -> Offset(10.0, 0.0), '
            'fade Offset(0.0, 1.0))',
      );

      const scene = DebugScene(
        layoutSize: Size(100, 50),
        boxes: [DebugWidgetBox(rect: Rect.fromLTWH(0, 0, 1, 1))],
        connections: [],
        guidelines: [vertical],
        barriers: [barrier],
      );
      expect(
        '$scene',
        'DebugScene(Size(100.0, 50.0), 1 boxes, 0 connections, '
            '1 guidelines, 1 barriers)',
      );
    });
  });
}
