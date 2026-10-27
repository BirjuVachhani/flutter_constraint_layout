// A barrier's margin keeps its sign in both text directions, as Android's
// view Barrier keeps it (see "Barriers" in the README): `.start` and `.end`
// resolve to the left or right edge for the direction, and a positive margin
// then moves the barrier right (or down), whatever its edge. In right-to-left
// text an `.end` barrier is a left barrier, so a positive margin moves it
// back over the widgets it tracks; the adapter used to negate it, mirroring
// the left-to-right layout instead.
//
// Every Java value is VOpDriver's at 257 on the view path: each probe id
// names an op list of test/parity/probes.in, whose output is
// test/parity/probes.J257.txt.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(List<Widget> children, {required TextDirection direction}) =>
    Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 100,
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

/// The probes' layout: #a at the start, an `.end` barrier over it with
/// [margin], and #k against the barrier, on its start side in left-to-right
/// text and on its end side in right-to-left text, as the probes link it.
List<Widget> endBarrier(double margin, {required bool rtl}) => [
  Constrained(
    id: #a,
    start: .startOf(parent),
    top: .topOf(parent),
    child: const SizedBox(width: 100, height: 20),
  ),
  Barrier(id: #br, edge: .end, referenced: const [#a], margin: margin),
  Constrained(
    id: #k,
    // The probes link k's left edge to the barrier's right in both
    // directions: k's start in left-to-right text, its end in right-to-left.
    start: rtl ? null : .endOf(#br),
    end: rtl ? .startOf(#br) : null,
    top: .topOf(parent),
    child: const SizedBox(width: 30, height: 20),
  ),
];

void main() {
  setUp(() => RenderConstraintLayout.debugRecordTranscripts = true);
  tearDown(() => RenderConstraintLayout.debugRecordTranscripts = false);

  testWidgets('an end barrier in right-to-left text adds its margin to the '
      'left edge it tracks', (tester) async {
    await tester.pumpWidget(
      host(endBarrier(8, rtl: true), direction: TextDirection.rtl),
    );
    // #a spans 300 to 400; the end barrier is its left edge plus 8.
    // Java J257: a (300, 0) 100 x 20, br (308, 0) 0 x 0, k (308, 0) 30 x 20
    // (VOpDriver view, probe p4:d5rtl). The barrier is a gone widget, placed
    // at its position at 0 x 0.
    expect(framesOf(tester), const [
      Rect.fromLTWH(300, 0, 100, 20),
      Rect.fromLTWH(308, 0, 0, 0),
      Rect.fromLTWH(308, 0, 30, 20),
    ]);
    // Java T257 (p4:d5rtl).
    expect(
      layoutOf(tester).debugViewHost!.measurer.transcript.toString(),
      'M:a:0:WW:0,0:A400/A100:100,20,-1,01 '
      'M:k:0:WW:0,0:A400/A100:30,20,-1,01',
    );
  });

  testWidgets('the mirrored placement now takes the negated margin', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(endBarrier(-8, rtl: true), direction: TextDirection.rtl),
    );
    // What the adapter used to give a margin of 8: the barrier 8 past #a's
    // left edge.
    // Java J257: a (300, 0) 100 x 20, br (292, 0) 0 x 0, k (292, 0) 30 x 20
    // (VOpDriver view, probe p4:d5rtl_mirrored).
    expect(framesOf(tester), const [
      Rect.fromLTWH(300, 0, 100, 20),
      Rect.fromLTWH(292, 0, 0, 0),
      Rect.fromLTWH(292, 0, 30, 20),
    ]);
  });

  testWidgets('an end barrier in left-to-right text adds its margin to the '
      'right edge it tracks', (tester) async {
    await tester.pumpWidget(
      host(endBarrier(8, rtl: false), direction: TextDirection.ltr),
    );
    // Java J257: a (0, 0) 100 x 20, br (108, 0) 0 x 0, k (108, 0) 30 x 20
    // (VOpDriver view, probe p4:d5ltr).
    expect(framesOf(tester), const [
      Rect.fromLTWH(0, 0, 100, 20),
      Rect.fromLTWH(108, 0, 0, 0),
      Rect.fromLTWH(108, 0, 30, 20),
    ]);
  });

  testWidgets('left and right barriers ignore the text direction', (
    tester,
  ) async {
    List<Widget> absolute() => [
      Constrained(
        id: #a,
        start: .startOf(parent, margin: 100),
        top: .topOf(parent),
        width: .fixed(100),
        height: .fixed(20),
        child: const SizedBox(),
      ),
      const Barrier(id: #bl, edge: .left, referenced: [#a], margin: 8),
      const Barrier(id: #brr, edge: .right, referenced: [#a], margin: 8),
      Constrained(
        id: #kl,
        left: .leftOf(#bl),
        top: .topOf(parent, margin: 40),
        width: .fixed(10),
        height: .fixed(10),
        child: const SizedBox(),
      ),
      Constrained(
        id: #kr,
        left: .leftOf(#brr),
        top: .topOf(parent, margin: 60),
        width: .fixed(10),
        height: .fixed(10),
        child: const SizedBox(),
      ),
    ];
    await tester.pumpWidget(host(absolute(), direction: TextDirection.ltr));
    // Java J257: a (100, 0) 100 x 20, bl (108, 0) 0 x 0, brr (208, 0) 0 x 0,
    // kl (108, 40) 10 x 10, kr (208, 60) 10 x 10 (VOpDriver view, probe
    // f:absbarrier:ltr).
    expect(framesOf(tester), const [
      Rect.fromLTWH(100, 0, 100, 20),
      Rect.fromLTWH(108, 0, 0, 0),
      Rect.fromLTWH(208, 0, 0, 0),
      Rect.fromLTWH(108, 40, 10, 10),
      Rect.fromLTWH(208, 60, 10, 10),
    ]);
    await tester.pumpWidget(host(absolute(), direction: TextDirection.rtl));
    // Java J257: a (200, 0) 100 x 20, bl (208, 0) 0 x 0, brr (308, 0) 0 x 0,
    // kl (208, 40) 10 x 10, kr (308, 60) 10 x 10 (VOpDriver view, probe
    // f:absbarrier:rtl).
    expect(framesOf(tester), const [
      Rect.fromLTWH(200, 0, 100, 20),
      Rect.fromLTWH(208, 0, 0, 0),
      Rect.fromLTWH(308, 0, 0, 0),
      Rect.fromLTWH(208, 40, 10, 10),
      Rect.fromLTWH(308, 60, 10, 10),
    ]);
  });
}
