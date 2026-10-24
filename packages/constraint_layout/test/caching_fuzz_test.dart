// Randomized stress test for the persistent engine model.
//
// Each seed builds a model containing a chain, a centered widget, a
// wrap-content widget, and a matchConstraint fill, then applies a long random
// mutation sequence (margins, biases, visibility cycles, dimension-type and
// matchConstraint sub-mode changes, chain style/weight changes, circular
// constraints, root resizes, content-size changes, child adds/removes,
// reorders, link retargets) to the persistent tree, recording geometry after
// every step.
// Afterwards every recorded step is replayed as a freshly built tree and must
// match exactly; the number of model rebuilds must also equal the number of
// structural steps, proving mutations were applied in place.

import 'dart:math';

import 'package:constraint_layout/constraint_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class IntrinsicBox extends LeafRenderObjectWidget {
  const IntrinsicBox(this.natural, {super.key});
  final Size natural;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderIntrinsicBox(natural);

  @override
  void updateRenderObject(
          BuildContext context, RenderIntrinsicBox renderObject) =>
      renderObject.natural = natural;
}

class RenderIntrinsicBox extends RenderBox {
  RenderIntrinsicBox(this._natural);

  Size _natural;
  set natural(Size value) {
    if (_natural == value) return;
    _natural = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    size = constraints.constrain(_natural);
  }
}

/// One anchor: a target (negative means `parent`) and which of the target's
/// two edges on that axis (0 = left/top, 1 = right/bottom).
typedef Anchor = (int target, int edge);

class ChildSpec {
  ChildSpec(this.uid);
  final int uid;

  Size natural = const Size(60, 30);
  int dimW = 0; // 0 fixed, 1 wrap, 2 matchConstraint, 3 matchParent
  int dimH = 0;
  double fixedW = 60;
  double fixedH = 30;
  // matchConstraint sub-mode: 0 spread, 1 constrainedWrap, 2 percent.
  int mcModeW = 0, mcModeH = 0;
  double mcPercentW = 0.5, mcPercentH = 0.5;
  double? mcMinW, mcMaxW, mcMinH, mcMaxH;
  Anchor? left, right, top, bottom;
  double leftMargin = 0, rightMargin = 0, topMargin = 0, bottomMargin = 0;
  double hBias = 0.5, vBias = 0.5;
  int visibility = 0; // 0 visible, 1 invisible, 2 gone
  int chainStyleH = 0; // 0 spread, 1 spreadInside, 2 packed (chain head only)
  double? weightH;
  (int target, double angle, double radius)? circle;
}

Symbol symOf(int uid) => Symbol('w$uid');

Dimension dimOf(
  int kind,
  double fixed,
  int mcMode,
  double mcPercent,
  double? mcMin,
  double? mcMax,
) =>
    switch (kind) {
      0 => Dimension.fixed(fixed),
      1 => .wrapContent,
      2 => switch (mcMode) {
          1 => Dimension.constrainedWrap(min: mcMin, max: mcMax),
          2 => Dimension.percent(mcPercent, min: mcMin, max: mcMax),
          _ => (mcMin == null && mcMax == null)
              ? Dimension.matchConstraint
              : Dimension.spread(min: mcMin, max: mcMax),
        },
      _ => .matchParent,
    };

HorizontalLink hLink(Anchor a, double margin) {
  final target = a.$1 < 0 ? parent : symOf(a.$1);
  return a.$2 == 0
      ? HorizontalLink.leftOf(target, margin: margin)
      : HorizontalLink.rightOf(target, margin: margin);
}

VerticalLink vLink(Anchor a, double margin) {
  final target = a.$1 < 0 ? parent : symOf(a.$1);
  return a.$2 == 0
      ? VerticalLink.topOf(target, margin: margin)
      : VerticalLink.bottomOf(target, margin: margin);
}

Widget widgetOf(ChildSpec s) => Constrained(
      key: ValueKey(s.uid),
      id: symOf(s.uid),
      left: s.left == null ? null : hLink(s.left!, s.leftMargin),
      right: s.right == null ? null : hLink(s.right!, s.rightMargin),
      top: s.top == null ? null : vLink(s.top!, s.topMargin),
      bottom: s.bottom == null ? null : vLink(s.bottom!, s.bottomMargin),
      circle: s.circle == null
          ? null
          : CircularLink.around(
              s.circle!.$1 < 0 ? parent : symOf(s.circle!.$1),
              angle: s.circle!.$2,
              radius: s.circle!.$3,
            ),
      horizontalBias: s.hBias,
      verticalBias: s.vBias,
      width: dimOf(s.dimW, s.fixedW, s.mcModeW, s.mcPercentW, s.mcMinW, s.mcMaxW),
      height: dimOf(s.dimH, s.fixedH, s.mcModeH, s.mcPercentH, s.mcMinH, s.mcMaxH),
      horizontalChainStyle: switch (s.chainStyleH) {
        1 => ChainStyle.spreadInside,
        2 => ChainStyle.packed,
        _ => null,
      },
      horizontalWeight: s.weightH,
      visibility: switch (s.visibility) {
        1 => ConstraintVisibility.invisible,
        2 => ConstraintVisibility.gone,
        _ => ConstraintVisibility.visible,
      },
      child: IntrinsicBox(s.natural),
    );

Widget host(List<ChildSpec> specs, Size size, {Key? key}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: ConstraintLayout(
            key: key,
            children: [for (final s in specs) widgetOf(s)],
          ),
        ),
      ),
    );

List<List<double>> geometryOf(WidgetTester tester) {
  final ro =
      tester.renderObject<RenderConstraintLayout>(find.byType(ConstraintLayout));
  return [
    [ro.size.width, ro.size.height],
    for (final child in ro.getChildrenAsList())
      [
        child.localToGlobal(Offset.zero, ancestor: ro).dx,
        child.localToGlobal(Offset.zero, ancestor: ro).dy,
        child.size.width,
        child.size.height,
      ],
  ];
}

/// The first three uids form a horizontal chain whose horizontal links stay
/// untouched by mutations, so the chain survives the run. Its style, widths,
/// and weights do mutate (fixed vs weighted spread).
const chainUids = 3;

List<ChildSpec> initialSpecs() {
  final chain0 = ChildSpec(0)
    ..left = (-1, 0)
    ..leftMargin = 8
    ..right = (1, 0)
    ..top = (-1, 0)
    ..topMargin = 8
    ..fixedW = 60
    ..fixedH = 24;
  final chain1 = ChildSpec(1)
    ..left = (0, 1)
    ..right = (2, 0)
    ..top = (0, 0)
    ..fixedW = 60
    ..fixedH = 24;
  final chain2 = ChildSpec(2)
    ..left = (1, 1)
    ..right = (-1, 1)
    ..rightMargin = 8
    ..top = (0, 0)
    ..fixedW = 60
    ..fixedH = 24;
  final centered = ChildSpec(3)
    ..left = (-1, 0)
    ..right = (-1, 1)
    ..top = (-1, 0)
    ..bottom = (-1, 1)
    ..fixedW = 80
    ..fixedH = 30;
  final wrap = ChildSpec(4)
    ..left = (-1, 0)
    ..leftMargin = 12
    ..top = (0, 1)
    ..topMargin = 10
    ..dimW = 1
    ..dimH = 1
    ..natural = const Size(70, 28);
  final fill = ChildSpec(5)
    ..left = (-1, 0)
    ..leftMargin = 20
    ..right = (-1, 1)
    ..rightMargin = 20
    ..top = (4, 1)
    ..topMargin = 6
    ..dimW = 2
    ..fixedH = 22;
  return [chain0, chain1, chain2, centered, wrap, fill];
}

const rootSizes = [
  Size(800, 600),
  Size(640, 480),
  Size(1024, 700),
  Size(390, 700),
];

class FuzzState {
  FuzzState() : specs = initialSpecs();
  final List<ChildSpec> specs;
  int nextUid = 6;
  Size rootSize = rootSizes.first;
  int structuralSteps = 0;

  bool isReferenced(int uid) => specs.any((s) => [
        s.left,
        s.right,
        s.top,
        s.bottom,
      ].any((a) => a != null && a.$1 == uid));

  /// A random spec eligible for general mutation (outside the chain).
  ChildSpec? randomMutable(Random rng) {
    final eligible = specs.where((s) => s.uid >= chainUids).toList();
    return eligible.isEmpty ? null : eligible[rng.nextInt(eligible.length)];
  }

  /// Applies one random mutation; returns a description for failure messages.
  String mutate(Random rng) {
    while (true) {
      switch (rng.nextInt(14)) {
        case 0: // margin tweak
          final s = randomMutable(rng);
          if (s == null) continue;
          final m = rng.nextInt(41).toDouble();
          switch (rng.nextInt(4)) {
            case 0:
              if (s.left == null) continue;
              s.leftMargin = m;
            case 1:
              if (s.right == null) continue;
              s.rightMargin = m;
            case 2:
              if (s.top == null) continue;
              s.topMargin = m;
            default:
              if (s.bottom == null) continue;
              s.bottomMargin = m;
          }
          return 'margin uid=${s.uid} -> $m';
        case 1: // bias tweak
          final s = randomMutable(rng);
          if (s == null) continue;
          final bias = [0.0, 0.25, 0.5, 0.75, 1.0][rng.nextInt(5)];
          if (rng.nextBool()) {
            s.hBias = bias;
          } else {
            s.vBias = bias;
          }
          return 'bias uid=${s.uid} -> $bias';
        case 2: // visibility cycle (any child, including chain members)
          final s = specs[rng.nextInt(specs.length)];
          s.visibility = (s.visibility + 1 + rng.nextInt(2)) % 3;
          return 'visibility uid=${s.uid} -> ${s.visibility}';
        case 3: // dimension type change
          final s = randomMutable(rng);
          if (s == null) continue;
          final kind = rng.nextInt(4);
          if (rng.nextBool()) {
            s.dimW = kind;
            if (kind == 0) s.fixedW = (20 + rng.nextInt(120)).toDouble();
          } else {
            s.dimH = kind;
            if (kind == 0) s.fixedH = (16 + rng.nextInt(80)).toDouble();
          }
          return 'dim uid=${s.uid} -> w:${s.dimW} h:${s.dimH}';
        case 4: // root resize
          final next = rootSizes[rng.nextInt(rootSizes.length)];
          if (next == rootSize) continue;
          rootSize = next;
          return 'resize -> $rootSize';
        case 5: // content (natural size) change
          final s = specs[rng.nextInt(specs.length)];
          s.natural = Size(
            (20 + rng.nextInt(120)).toDouble(),
            (10 + rng.nextInt(70)).toDouble(),
          );
          return 'content uid=${s.uid} -> ${s.natural}';
        case 6: // add child
          final s = ChildSpec(nextUid++);
          final anchorTarget =
              rng.nextBool() ? -1 : specs[rng.nextInt(specs.length)].uid;
          s
            ..left = (anchorTarget, rng.nextInt(2))
            ..leftMargin = rng.nextInt(30).toDouble()
            ..top = (
              rng.nextBool() ? -1 : specs[rng.nextInt(specs.length)].uid,
              rng.nextInt(2)
            )
            ..topMargin = rng.nextInt(30).toDouble()
            ..dimW = rng.nextInt(2)
            ..dimH = rng.nextInt(2)
            ..fixedW = (20 + rng.nextInt(100)).toDouble()
            ..fixedH = (16 + rng.nextInt(60)).toDouble()
            ..natural = Size(
              (20 + rng.nextInt(100)).toDouble(),
              (10 + rng.nextInt(60)).toDouble(),
            );
          specs.add(s);
          structuralSteps++;
          return 'add uid=${s.uid}';
        case 7: // remove the newest unreferenced non-chain child
          if (specs.length <= chainUids) continue;
          final s = specs.last;
          if (s.uid < chainUids || isReferenced(s.uid)) continue;
          specs.removeLast();
          structuralSteps++;
          return 'remove uid=${s.uid}';
        case 8: // reorder two children (uids and anchors are unaffected)
          if (specs.length < 2) continue;
          final i = rng.nextInt(specs.length);
          final j = rng.nextInt(specs.length);
          if (i == j) continue;
          final tmp = specs[i];
          specs[i] = specs[j];
          specs[j] = tmp;
          structuralSteps++;
          return 'reorder $i <-> $j';
        case 9: // retarget or drop one link (acyclic: target uid < own uid)
          final s = randomMutable(rng);
          if (s == null) continue;
          final candidates = [
            -1,
            for (final other in specs)
              if (other.uid < s.uid) other.uid,
          ];
          Anchor? roll() => rng.nextInt(5) == 0
              ? null
              : (candidates[rng.nextInt(candidates.length)], rng.nextInt(2));
          switch (rng.nextInt(4)) {
            case 0:
              s.left = roll();
            case 1:
              s.right = roll();
            case 2:
              s.top = roll();
            default:
              s.bottom = roll();
          }
          return 'retarget uid=${s.uid}';
        case 10: // chain style change on the chain head
          final style = rng.nextInt(3);
          if (specs.first.chainStyleH == style) continue;
          specs.first.chainStyleH = style;
          return 'chainStyle -> $style';
        case 11: // toggle the chain between fixed widths and weighted spread
          final weighted = specs[0].dimW != 2;
          for (var i = 0; i < chainUids; i++) {
            final s = specs[i];
            if (weighted) {
              s.dimW = 2;
              s.weightH = (1 + rng.nextInt(3)).toDouble();
            } else {
              s.dimW = 0;
              s.weightH = null;
            }
          }
          return 'chain weights -> ${weighted ? 'weighted' : 'fixed'}';
        case 12: // matchConstraint sub-mode change
          final s = randomMutable(rng);
          if (s == null) continue;
          double? bound() =>
              rng.nextInt(3) == 0 ? null : (20 + rng.nextInt(200)).toDouble();
          if (rng.nextBool()) {
            if (s.dimW != 2) continue;
            s.mcModeW = rng.nextInt(3);
            s.mcPercentW = [0.25, 0.5, 0.75][rng.nextInt(3)];
            s.mcMinW = bound();
            s.mcMaxW = bound();
            return 'mcMode uid=${s.uid} w -> ${s.mcModeW}';
          } else {
            if (s.dimH != 2) continue;
            s.mcModeH = rng.nextInt(3);
            s.mcPercentH = [0.25, 0.5, 0.75][rng.nextInt(3)];
            s.mcMinH = bound();
            s.mcMaxH = bound();
            return 'mcMode uid=${s.uid} h -> ${s.mcModeH}';
          }
        default: // circular constraint set/clear on a non-chain child
          final s = randomMutable(rng);
          if (s == null) continue;
          // Only target the stable centered widget so the reference is never
          // dangling and never cyclic.
          if (s.uid == 3) continue;
          if (s.circle != null && rng.nextInt(3) == 0) {
            s.circle = null;
            return 'circle uid=${s.uid} -> null';
          }
          s.circle = (
            3,
            rng.nextInt(360).toDouble(),
            (30 + rng.nextInt(120)).toDouble(),
          );
          return 'circle uid=${s.uid} -> ${s.circle}';
      }
    }
  }
}

void main() {
  for (final seed in [7, 42, 99, 1337, 271828]) {
    testWidgets('fuzzed mutation sequence matches fresh layouts (seed $seed)',
        (tester) async {
      const steps = 50;
      final rng = Random(seed);
      final state = FuzzState();

      await tester.pumpWidget(host(state.specs, state.rootSize));
      final ro = tester.renderObject<RenderConstraintLayout>(
          find.byType(ConstraintLayout));

      // Mutate the persistent tree, recording configuration and geometry.
      final descriptions = <String>['initial'];
      final configs = <(List<ChildSpec>, Size)>[
        ([...state.specs.map(_copy)], state.rootSize),
      ];
      final snapshots = <List<List<double>>>[geometryOf(tester)];
      for (var step = 0; step < steps; step++) {
        final description = state.mutate(rng);
        await tester.pumpWidget(host(state.specs, state.rootSize));
        expect(tester.takeException(), isNull,
            reason: 'seed $seed step $step ($description) threw');
        descriptions.add(description);
        configs.add(([...state.specs.map(_copy)], state.rootSize));
        snapshots.add(geometryOf(tester));
      }

      expect(
        ro.debugModelBuilds,
        1 + state.structuralSteps,
        reason: 'seed $seed: only structural steps may rebuild the model',
      );

      // Replay every recorded configuration as a fresh tree.
      for (var i = 0; i < configs.length; i++) {
        final (specs, size) = configs[i];
        await tester.pumpWidget(host(specs, size, key: UniqueKey()));
        expect(geometryOf(tester), snapshots[i],
            reason: 'seed $seed: fresh replay of step $i '
                '(${descriptions[i]}) diverged from the persistent tree');
      }
    });
  }
}

ChildSpec _copy(ChildSpec s) => ChildSpec(s.uid)
  ..natural = s.natural
  ..dimW = s.dimW
  ..dimH = s.dimH
  ..fixedW = s.fixedW
  ..fixedH = s.fixedH
  ..mcModeW = s.mcModeW
  ..mcModeH = s.mcModeH
  ..mcPercentW = s.mcPercentW
  ..mcPercentH = s.mcPercentH
  ..mcMinW = s.mcMinW
  ..mcMaxW = s.mcMaxW
  ..mcMinH = s.mcMinH
  ..mcMaxH = s.mcMaxH
  ..left = s.left
  ..right = s.right
  ..top = s.top
  ..bottom = s.bottom
  ..leftMargin = s.leftMargin
  ..rightMargin = s.rightMargin
  ..topMargin = s.topMargin
  ..bottomMargin = s.bottomMargin
  ..hBias = s.hBias
  ..vBias = s.vBias
  ..visibility = s.visibility
  ..chainStyleH = s.chainStyleH
  ..weightH = s.weightH
  ..circle = s.circle;
