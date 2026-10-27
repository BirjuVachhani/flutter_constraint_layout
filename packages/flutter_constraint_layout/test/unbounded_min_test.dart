// A Flutter minimum on an unbounded axis is the ConstraintLayout's own
// minimum size, Android's minWidth and minHeight (see "Sizing and scrolling"
// in the README): the engine's container is at least that big, and the
// children are placed in it, rather than placed in the wrapped size and the
// layout enlarged around them.
//
// Expected frames and request transcripts are Java's: VOpDriver at the pin,
// view path, level 257, with `cmin` for the minimum (each `p4:` and `p4b:` id
// names an op list of test/parity/probes.in, whose output is
// test/parity/probes.J257.txt). Every probe gives the same frames at level 0.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => RenderConstraintLayout.debugRecordTranscripts = true);
  tearDown(() => RenderConstraintLayout.debugRecordTranscripts = false);

  /// A 50 x 20 box linked to all four edges of the layout, so it centers in
  /// whatever size the layout ends up.
  List<Widget> centered() => [
    Constrained(
      id: #a,
      left: .leftOf(parent),
      right: .rightOf(parent),
      top: .topOf(parent),
      bottom: .bottomOf(parent),
      child: const SizedBox(width: 50, height: 20),
    ),
  ];

  group('the minimum of an unbounded axis is the layout\'s minimum', () {
    testWidgets('on both axes, the child centers in it (p4:d8min)', (
      tester,
    ) async {
      // Java J257: root 300 x 200, a (125, 90) 50 x 20 (VOpDriver view,
      // p4:d8min: U0 x U0 with cmin 300 200).
      const constraints = BoxConstraints(minWidth: 300, minHeight: 200);
      await _pump(tester, constraints, centered());
      expect(_geometry(tester, ['a']), 'root 300 x 200 | a: (125, 90) 50 x 20');
      expect(_transcript(tester), 'M:a:0:WW:0,0:U0/U0:50,20,-1,01');
      final host = _layout(tester).debugViewHost!;
      expect(host.minWidth, 300);
      expect(host.minHeight, 200);
    });

    testWidgets('without a minimum, the layout wraps the child (p4:d8nomin)', (
      tester,
    ) async {
      // Java J257: root 50 x 20, a (0, 0) 50 x 20 (VOpDriver view,
      // p4:d8nomin: U0 x U0).
      await _pump(tester, const BoxConstraints(), centered());
      expect(_geometry(tester, ['a']), 'root 50 x 20 | a: (0, 0) 50 x 20');
      expect(_transcript(tester), 'M:a:0:WW:0,0:U0/U0:50,20,-1,01');
    });

    testWidgets('a fractional minimum rounds up to whole pixels', (
      tester,
    ) async {
      // Java J257: root 301 x 200, a (126, 90) 50 x 20 (VOpDriver view,
      // p4b:d8frac: U0 x U0 with cmin 301 200). The minimum rounds as a
      // child's size does ("Whole pixels" in the README): 300.4 is 301, and
      // 200.0005, within 0.001 of 200, is 200. The layout's size is its
      // constraints' constrain of the engine's 301 x 200, so its height is the
      // minimum, 0.0005 more.
      const constraints = BoxConstraints(minWidth: 300.4, minHeight: 200.0005);
      await _pump(tester, constraints, centered());
      expect(
        _geometry(tester, ['a']),
        'root 301 x 200.0005 | a: (126, 90) 50 x 20',
      );
      final host = _layout(tester).debugViewHost!;
      expect((host.minWidth, host.minHeight), (301, 200));
      expect((host.getMeasuredWidth(), host.getMeasuredHeight()), (301, 200));
    });

    testWidgets('on the unbounded axis only: height (p4b:d8h)', (
      tester,
    ) async {
      // Java J257: root 400 x 100, a (0, 40) 50 x 20 (VOpDriver view,
      // p4b:d8h: E400 x U0 with cmin 0 100; a linked left, top and bottom).
      const constraints = BoxConstraints(
        minWidth: 400,
        maxWidth: 400,
        minHeight: 100,
      );
      await _pump(tester, constraints, [
        Constrained(
          id: #a,
          left: .leftOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
          child: const SizedBox(width: 50, height: 20),
        ),
      ]);
      expect(_geometry(tester, ['a']), 'root 400 x 100 | a: (0, 40) 50 x 20');
      expect(_transcript(tester), 'M:a:0:WW:0,0:A400/U0:50,20,-1,01');
      final host = _layout(tester).debugViewHost!;
      expect((host.minWidth, host.minHeight), (0, 100));
    });

    testWidgets('on the unbounded axis only: width (p4b:d8w)', (tester) async {
      // Java J257: root 120 x 100, a (35, 0) 50 x 20 (VOpDriver view,
      // p4b:d8w: U0 x E100 with cmin 120 0; a linked left, right and top).
      const constraints = BoxConstraints(
        minWidth: 120,
        minHeight: 100,
        maxHeight: 100,
      );
      await _pump(tester, constraints, [
        Constrained(
          id: #a,
          left: .leftOf(parent),
          right: .rightOf(parent),
          top: .topOf(parent),
          child: const SizedBox(width: 50, height: 20),
        ),
      ]);
      expect(_geometry(tester, ['a']), 'root 120 x 100 | a: (35, 0) 50 x 20');
      expect(_transcript(tester), 'M:a:0:WW:0,0:U0/A100:50,20,-1,01');
    });

    testWidgets('a bounded axis fills its maximum and ignores its minimum', (
      tester,
    ) async {
      // Java J257: root 400 x 300, a (175, 140) 50 x 20 (VOpDriver view,
      // p4b:bounded: E400 x E300). A bounded axis is measured EXACTLY at its
      // maximum, tight or loose (the layout has no AT_MOST mode), so its
      // minimum never reaches the engine.
      const constraints = BoxConstraints(
        minWidth: 100,
        maxWidth: 400,
        minHeight: 50,
        maxHeight: 300,
      );
      await _pump(tester, constraints, centered());
      expect(
        _geometry(tester, ['a']),
        'root 400 x 300 | a: (175, 140) 50 x 20',
      );
      expect(_transcript(tester), 'M:a:0:WW:0,0:A400/A300:50,20,-1,01');
      final host = _layout(tester).debugViewHost!;
      expect((host.minWidth, host.minHeight), (0, 0));
    });

    testWidgets('an empty layout takes the minimum (p4:emptyunbounded)', (
      tester,
    ) async {
      // Java J257: root 30 x 40 (VOpDriver view, p4:emptyunbounded: U0 x U0
      // with cmin 30 40, no child).
      await _pump(
        tester,
        const BoxConstraints(minWidth: 30, minHeight: 40),
        const [],
      );
      expect(_geometry(tester, []), 'root 30 x 40');
    });
  });

  group('dry layout and intrinsics agree with the layout there', () {
    for (final (label, constraints) in const [
      (
        'both axes unbounded with a minimum',
        BoxConstraints(minWidth: 300, minHeight: 200),
      ),
      ('both axes unbounded', BoxConstraints()),
      (
        'a fractional minimum',
        BoxConstraints(minWidth: 300.4, minHeight: 200.0005),
      ),
      (
        'the height unbounded with a minimum',
        BoxConstraints(minWidth: 400, maxWidth: 400, minHeight: 100),
      ),
      (
        'the width unbounded with a minimum',
        BoxConstraints(minWidth: 120, minHeight: 100, maxHeight: 100),
      ),
    ]) {
      testWidgets('the dry layout is the layout\'s size: $label', (
        tester,
      ) async {
        await _pump(tester, constraints, centered());
        final ro = _layout(tester);
        expect(ro.getDryLayout(constraints), ro.size);
      });
    }

    testWidgets('the dry layout of an empty layout is its size', (
      tester,
    ) async {
      const constraints = BoxConstraints(minWidth: 30, minHeight: 40);
      await _pump(tester, constraints, const []);
      final ro = _layout(tester);
      expect(ro.size, const Size(30, 40));
      expect(ro.getDryLayout(constraints), ro.size);
    });

    testWidgets('the intrinsic sizes are the wrapped size, with no minimum', (
      tester,
    ) async {
      // An intrinsic query has no minimum of its own (its constraints are
      // unbounded on the measured axis, from 0), so the intrinsic sizes are
      // the size the layout wraps its children to: p4:d8nomin's 50 x 20,
      // whatever minimum the layout is laid out with.
      await _pump(
        tester,
        const BoxConstraints(minWidth: 300, minHeight: 200),
        centered(),
      );
      final ro = _layout(tester);
      expect(ro.getMaxIntrinsicWidth(double.infinity), 50);
      expect(ro.getMinIntrinsicWidth(double.infinity), 50);
      expect(ro.getMaxIntrinsicHeight(double.infinity), 20);
      expect(ro.getMinIntrinsicHeight(double.infinity), 20);
      expect(ro.getMaxIntrinsicHeight(300), 20);
    });

    testWidgets('a layout sized by its intrinsic width honors the minimum', (
      tester,
    ) async {
      // Java J257: root 300 x 20, a (125, 0) 50 x 20 (VOpDriver view,
      // p4b:iw: E300 x U0). IntrinsicWidth asks for the wrapped width, 50,
      // and tightens its own minimum of 300 to it, so the layout is laid out
      // tight at 300 wide, with the height unbounded.
      await _pump(
        tester,
        const BoxConstraints(minWidth: 300),
        centered(),
        wrap: (layout) => IntrinsicWidth(child: layout),
      );
      expect(_geometry(tester, ['a']), 'root 300 x 20 | a: (125, 0) 50 x 20');
      expect(_transcript(tester), 'M:a:0:WW:0,0:A300/U0:50,20,-1,01');
    });

    testWidgets('the dry baseline is the layout\'s baseline (p4b:d8text)', (
      tester,
    ) async {
      // Java J257: root 200 x 60, t (0, 0) 120 x 20 (VOpDriver view,
      // p4b:d8text: U0 x U0 with cmin 200 60; a text 120 / 20 with baseline
      // 15 linked left and top). The layout's baseline is t's, 15: a Baseline
      // at 100 puts the layout's top at 85.
      const constraints = BoxConstraints(minWidth: 200, minHeight: 60);
      await _pump(
        tester,
        constraints,
        [
          Constrained(
            id: #t,
            left: .leftOf(parent),
            top: .topOf(parent),
            child: const _Baselined(width: 120, height: 20, baseline: 15),
          ),
        ],
        outer: (box) => Baseline(
          baseline: 100,
          baselineType: TextBaseline.alphabetic,
          child: box,
        ),
      );
      expect(_geometry(tester, ['t']), 'root 200 x 60 | t: (0, 0) 120 x 20');
      expect(_transcript(tester), 'M:t:0:WW:0,0:U0/U0:120,20,15,11');
      expect(tester.getTopLeft(find.byType(ConstraintLayout)).dy, 85);
      final ro = _layout(tester);
      expect(ro.getDryBaseline(constraints, TextBaseline.alphabetic), 15);
      expect(ro.getDryLayout(constraints), ro.size);
    });
  });
}

/// Pumps a ConstraintLayout of [children] under [constraints], as the parity
/// harness builds a probe: Directionality, Align top-left, and an OverflowBox
/// that gives the layout exactly [constraints]. [wrap], when given, wraps the
/// layout inside the OverflowBox, and [outer] wraps the OverflowBox.
Future<void> _pump(
  WidgetTester tester,
  BoxConstraints constraints,
  List<Widget> children, {
  Widget Function(Widget layout)? wrap,
  Widget Function(Widget box)? outer,
}) {
  final Widget layout = ConstraintLayout(children: children);
  final Widget box = OverflowBox(
    alignment: Alignment.topLeft,
    minWidth: constraints.minWidth,
    maxWidth: constraints.maxWidth,
    minHeight: constraints.minHeight,
    maxHeight: constraints.maxHeight,
    child: wrap == null ? layout : wrap(layout),
  );
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: outer == null ? box : outer(box),
      ),
    ),
  );
}

RenderConstraintLayout _layout(WidgetTester tester) =>
    tester.renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout));

/// The frames of the laid-out ConstraintLayout in the parity geometry format
/// (FORMATS 2): the root's size, then each child under its name in [names].
String _geometry(WidgetTester tester, List<String> names) {
  final ro = _layout(tester);
  String n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  final children = ro.getChildrenAsList();
  expect(children, hasLength(names.length), reason: 'one name per child');
  final sb = StringBuffer('root ${n(ro.size.width)} x ${n(ro.size.height)}');
  for (var i = 0; i < children.length; i++) {
    final child = children[i];
    final offset = (child.parentData! as BoxParentData).offset;
    sb.write(
      ' | ${names[i]}: (${n(offset.dx)}, ${n(offset.dy)}) '
      '${n(child.size.width)} x ${n(child.size.height)}',
    );
  }
  return sb.toString();
}

/// The request transcript of the layout's last full run.
String _transcript(WidgetTester tester) =>
    _layout(tester).debugViewHost!.measurer.transcript.toString();

/// A box of a fixed natural size with a baseline, like a one-line text.
class _Baselined extends LeafRenderObjectWidget {
  const _Baselined({
    required this.width,
    required this.height,
    required this.baseline,
  });

  final double width;
  final double height;
  final double baseline;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBaselined(Size(width, height), baseline);
}

class _RenderBaselined extends RenderBox {
  _RenderBaselined(this._natural, this._baseline);

  final Size _natural;
  final double _baseline;

  @override
  void performLayout() {
    size = constraints.constrain(_natural);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(_natural);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _baseline;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) => _baseline;

  @override
  double computeMinIntrinsicWidth(double height) => _natural.width;

  @override
  double computeMaxIntrinsicWidth(double height) => _natural.width;

  @override
  double computeMinIntrinsicHeight(double width) => _natural.height;

  @override
  double computeMaxIntrinsicHeight(double width) => _natural.height;
}
