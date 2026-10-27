// Right-to-left flips in float, and the circle angle as given.
//
// Android resolves a child's layout params for the text direction in Java
// float: a right-to-left child with a start or end link uses
// `1f - horizontalBias`, and a vertical guideline `1f - guidePercent`. One
// float subtraction of the float input differs from the binary32 rounding of
// the double difference by one ulp for 414 of the 999 values from 0.001 to
// 0.999, enough to move a pixel when the product lands near a half.
//
// Every Java value is VOpDriver's at 257 on the view path: each probe id
// names an op list of test/parity/probes.in, whose output is
// test/parity/probes.J257.txt.

import 'package:constraint_engine/constraint_engine.dart' as engine;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(
  List<Widget> children, {
  double width = 400,
  double height = 100,
  TextDirection direction = TextDirection.rtl,
}) => Directionality(
  textDirection: direction,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      height: height,
      child: ConstraintLayout(children: children),
    ),
  ),
);

RenderConstraintLayout layoutOf(WidgetTester tester) =>
    tester.renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout));

/// The frame of every child, in child order, as placed: offset and size.
List<Rect> framesOf(WidgetTester tester) => [
  for (final child in layoutOf(tester).getChildrenAsList())
    (child.parentData! as BoxParentData).offset & child.size,
];

/// Android's resolved bias of a right-to-left start/end child: `1f - bias`.
double floatFlip(double bias) => engine.fsub(1, engine.f32(bias));

/// The flip computed in double and stored as binary32, which the adapter did
/// before: not Android's.
double doubleFlip(double bias) => engine.f32(1 - bias);

Widget centered(Symbol id, double bias, {bool startEnd = true}) => Constrained(
  id: id,
  start: startEnd ? .startOf(parent) : null,
  end: startEnd ? .endOf(parent) : null,
  left: startEnd ? null : .leftOf(parent),
  right: startEnd ? null : .rightOf(parent),
  top: .topOf(parent),
  horizontalBias: bias,
  width: .fixed(10),
  height: .fixed(10),
  child: const SizedBox(),
);

void main() {
  group('the horizontal bias of a right-to-left start/end child', () {
    testWidgets('is 1 - bias in float', (tester) async {
      await tester.pumpWidget(host([centered(#a, 0.058)]));
      final stored = layoutOf(
        tester,
      ).debugEngineContainer!.getChildren().single.getHorizontalBiasPercent();
      expect(stored, 0.9420000314712524);
      expect(stored, floatFlip(0.058));
      expect(doubleFlip(0.058), 0.9419999718666077);
    });

    testWidgets('flips every bias from 0.001 to 0.999 in float', (
      tester,
    ) async {
      final biases = [for (var i = 1; i < 1000; i++) i / 1000];
      await tester.pumpWidget(
        host(
          [
            for (var i = 0; i < biases.length; i++)
              centered(Symbol('c$i'), biases[i]),
          ],
          width: 2000,
          height: 20,
        ),
      );
      final widgets = layoutOf(tester).debugEngineContainer!.getChildren();
      var oneUlpApart = 0;
      for (var i = 0; i < biases.length; i++) {
        final stored = widgets[i].getHorizontalBiasPercent();
        expect(stored, floatFlip(biases[i]), reason: 'bias ${biases[i]}');
        if (stored != doubleFlip(biases[i])) oneUlpApart++;
      }
      expect(oneUlpApart, 414);
    });

    testWidgets('is kept in left-to-right text, and for absolute links', (
      tester,
    ) async {
      await tester.pumpWidget(
        host([centered(#a, 0.058)], direction: TextDirection.ltr),
      );
      expect(
        layoutOf(
          tester,
        ).debugEngineContainer!.getChildren().single.getHorizontalBiasPercent(),
        engine.f32(0.058),
      );
      await tester.pumpWidget(host([centered(#a, 0.058, startEnd: false)]));
      expect(
        layoutOf(
          tester,
        ).debugEngineContainer!.getChildren().single.getHorizontalBiasPercent(),
        engine.f32(0.058),
      );
    });

    testWidgets('decides a pixel', (tester) async {
      // 250 of slack: the float flip of 0.09 gives 0.9099999666 * 250 =
      // 227.4999917, and (int) (0.5f + 227.49999f) is 227; the double flip's
      // 0.9100000262 gives 228.
      // Java J257: a (227, 0) 50 x 20 (VOpDriver view, probe
      // f:rtlbias:float); the double flip's value gives a (228, 0) 50 x 20
      // (f:rtlbias:double).
      await tester.pumpWidget(
        host([
          Constrained(
            id: #a,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            horizontalBias: 0.09,
            width: .fixed(50),
            height: .fixed(20),
            child: const SizedBox(),
          ),
        ], width: 300),
      );
      expect(framesOf(tester), const [Rect.fromLTWH(227, 0, 50, 20)]);
    });
  });

  group('a vertical guideline in right-to-left text', () {
    testWidgets('mirrors its percent in float, deciding a pixel', (
      tester,
    ) async {
      await tester.pumpWidget(
        host([
          const Guideline.vertical(id: #gd, percent: 0.09),
          Constrained(
            id: #a,
            left: .leftOf(#gd),
            top: .topOf(parent),
            width: .fixed(10),
            height: .fixed(10),
            child: const SizedBox(),
          ),
        ], width: 250),
      );
      final guideline =
          layoutOf(tester).debugEngineContainer!.getChildren().first
              as engine.Guideline;
      expect(guideline.getRelativePercent(), floatFlip(0.09));
      expect(floatFlip(0.09), isNot(doubleFlip(0.09)));
      // (int) (0.5f + 0.90999997f * 250) is 227; the double flip gives 228.
      // Java J257: gd (227, 0) 0 x 0, a (227, 0) 10 x 10 (VOpDriver view,
      // probe f:rtlpct:float); the double flip's value gives 228
      // (f:rtlpct:double). The guideline is a gone widget, placed at its
      // position at 0 x 0.
      expect(framesOf(tester), const [
        Rect.fromLTWH(227, 0, 0, 0),
        Rect.fromLTWH(227, 0, 10, 10),
      ]);
    });

    testWidgets('trades begin and end', (tester) async {
      await tester.pumpWidget(
        host([
          const Guideline.vertical(id: #b, begin: 30),
          const Guideline.vertical(id: #e, end: 30),
        ]),
      );
      final children = layoutOf(tester).debugEngineContainer!.getChildren();
      final begin = children[0] as engine.Guideline;
      final end = children[1] as engine.Guideline;
      expect(begin.getRelativeEnd(), 30);
      expect(begin.getRelativeBegin(), -1);
      expect(end.getRelativeBegin(), 30);
      expect(end.getRelativeEnd(), -1);
      // Java J257: b (370, 0) 0 x 0, e (30, 0) 0 x 0 (VOpDriver view, probe
      // f:rtlbeginend).
      expect(framesOf(tester), const [
        Rect.fromLTWH(370, 0, 0, 0),
        Rect.fromLTWH(30, 0, 0, 0),
      ]);
    });
  });

  group('a circle angle is used as given', () {
    Future<Rect> circled(WidgetTester tester, double angle) async {
      await tester.pumpWidget(
        host(
          [
            Constrained(
              id: #hub,
              left: .leftOf(parent, margin: 190),
              top: .topOf(parent, margin: 190),
              width: .fixed(20),
              height: .fixed(20),
              child: const SizedBox(),
            ),
            Constrained(
              id: #a,
              circle: .around(#hub, angle: angle, radius: 100),
              width: .fixed(10),
              height: .fixed(10),
              child: const SizedBox(),
            ),
          ],
          height: 400,
          direction: TextDirection.ltr,
        ),
      );
      return framesOf(tester)[1];
    }

    testWidgets('30 and 330 degrees', (tester) async {
      // Java J257: a (245, 108) 10 x 10 (VOpDriver view, probe p4:circle30).
      expect(await circled(tester, 30), const Rect.fromLTWH(245, 108, 10, 10));
      // Java J257: a (145, 108) 10 x 10 (VOpDriver view, probe p4:circle330).
      expect(
        await circled(tester, 330),
        const Rect.fromLTWH(145, 108, 10, 10),
      );
    });

    testWidgets('-30 degrees is 330, not the XML parser\'s 30', (tester) async {
      // Android's XML parser would turn -30 into (360 - -30) % 360 = 30; a
      // programmatic angle reaches the engine unchanged.
      // Java J257: a (145, 108) 10 x 10 (VOpDriver view, probe f:circle-30).
      expect(
        await circled(tester, -30),
        const Rect.fromLTWH(145, 108, 10, 10),
      );
      final widget = layoutOf(tester).debugEngineContainer!.getChildren()[1];
      expect(widget.mCircleConstraintAngle, -30);
    });
  });
}
