// Every layout that features_test.dart and golden/layout_golden_test.dart lay
// out, as data, for tests that run the same layouts under other constraints
// (see intrinsics_test.dart). Each fixture names the test it comes from; keep
// the two in step when a layout there changes or a new one is added.

import 'package:flutter/material.dart';
import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

/// One layout: the children of a ConstraintLayout, the size its test gives
/// the layout, and the text direction it is laid out in.
class LayoutFixture {
  const LayoutFixture(
    this.name,
    this.children, {
    this.size = const Size(800, 600),
    this.direction = TextDirection.ltr,
  });

  final String name;
  final List<Widget> Function() children;
  final Size size;
  final TextDirection direction;
}

// ---------------------------------------------------------------------------
// features_test.dart (every host is 800 x 600 unless noted)
// ---------------------------------------------------------------------------

Widget _box(Symbol id) => SizedBox(key: ValueKey(id));

Widget _cell(Symbol id, double w, double h) => Constrained(
  id: id,
  width: Dimension.fixed(w),
  height: Dimension.fixed(h),
  child: _box(id),
);

Widget _chip(Symbol id, double width) => Constrained(
  id: id,
  child: SizedBox(key: ValueKey(id), width: width, height: 35),
);

List<Widget> _chain(ChainStyle? style, {double? weightA, double? weightB}) => [
  Constrained(
    id: #a,
    start: .startOf(parent),
    end: .startOf(#b),
    top: .topOf(parent),
    width: weightA == null ? .fixed(100) : .matchConstraint,
    height: .fixed(50),
    horizontalChainStyle: style,
    horizontalWeight: weightA,
    child: _box(#a),
  ),
  Constrained(
    id: #b,
    start: .endOf(#a),
    end: .endOf(parent),
    top: .topOf(parent),
    width: weightB == null ? .fixed(100) : .matchConstraint,
    height: .fixed(50),
    horizontalWeight: weightB,
    child: _box(#b),
  ),
];

List<Widget> _pair(ConstraintVisibility vis) => [
  Constrained(
    id: #a,
    start: .startOf(parent),
    top: .topOf(parent),
    width: .fixed(100),
    height: .fixed(50),
    visibility: vis,
    child: _box(#a),
  ),
  Constrained(
    id: #b,
    start: .endOf(#a, margin: 10),
    top: .topOf(parent),
    width: .fixed(100),
    height: .fixed(50),
    child: _box(#b),
  ),
];

Widget _tappable(Symbol id, ConstraintVisibility vis) => Constrained(
  id: id,
  start: .startOf(parent),
  top: .topOf(parent),
  width: .fixed(100),
  height: .fixed(50),
  visibility: vis,
  child: GestureDetector(
    key: ValueKey(id),
    onTap: () {},
    child: Container(color: const Color(0xFF00FF00)),
  ),
);

List<Widget> _guidelinePercent(double percent) => [
  Guideline.vertical(id: #g, percent: percent),
  Constrained(
    id: #a,
    start: .rightOf(#g),
    top: .topOf(parent),
    width: .fixed(100),
    height: .fixed(50),
    child: _box(#a),
  ),
];

List<Widget> _labeled(double bWidth, {double margin = 0}) => [
  Constrained(
    id: #name,
    start: .startOf(parent),
    top: .topOf(parent),
    width: .fixed(100),
    height: .fixed(30),
    child: _box(#name),
  ),
  Constrained(
    id: #email,
    start: .startOf(parent),
    top: .bottomOf(#name),
    width: .fixed(bWidth),
    height: .fixed(30),
    child: _box(#email),
  ),
  Barrier(
    id: #labelsEnd,
    edge: .end,
    referenced: const [#name, #email],
    margin: margin,
  ),
  Constrained(
    id: #value,
    start: .rightOf(#labelsEnd),
    top: .topOf(parent),
    width: .fixed(50),
    height: .fixed(30),
    child: _box(#value),
  ),
];

List<Widget> _chipFlow(FlowWrap wrap, {double padding = 0}) => [
  _chip(#c0, 91),
  _chip(#c1, 66),
  _chip(#c2, 66),
  _chip(#c3, 61),
  ConstraintFlow(
    id: #flow,
    referenced: const [#c0, #c1, #c2, #c3],
    start: .startOf(parent, margin: 12),
    end: .endOf(parent, margin: 12),
    top: .topOf(parent, margin: 12),
    width: .matchConstraint,
    wrap: wrap,
    horizontalGap: 8,
    verticalGap: 8,
    horizontalChainStyle: .packed,
    contentHorizontalBias: 0,
    padding: padding,
  ),
];

List<Widget> _reflowFlow(List<Symbol> refs) => [
  _cell(#a, 300, 40),
  _cell(#b, 300, 40),
  _cell(#c, 300, 40),
  ConstraintFlow(
    id: #flow,
    referenced: refs,
    start: .startOf(parent),
    end: .endOf(parent),
    top: .topOf(parent),
    width: .matchConstraint,
    height: .wrapContent,
    wrap: .chain,
  ),
];

List<Widget> _startEndReplaceAbsolute() => [
  Constrained(
    id: #start,
    start: .startOf(parent),
    left: .leftOf(parent),
    right: .rightOf(parent),
    top: .topOf(parent),
    horizontalBias: 0.25,
    width: .fixed(100),
    height: .fixed(20),
    child: _box(#start),
  ),
  Constrained(
    id: #end,
    end: .endOf(parent),
    left: .leftOf(parent),
    right: .rightOf(parent),
    top: .bottomOf(#start),
    horizontalBias: 0.25,
    width: .fixed(100),
    height: .fixed(20),
    child: _box(#end),
  ),
];

List<Widget> _biased() => [
  Constrained(
    id: #startEnd,
    start: .startOf(parent),
    end: .endOf(parent),
    top: .topOf(parent),
    bottom: .bottomOf(parent),
    width: .fixed(100),
    height: .fixed(100),
    horizontalBias: 0.25,
    verticalBias: 0.25,
    child: _box(#startEnd),
  ),
  Constrained(
    id: #leftRight,
    left: .leftOf(parent),
    right: .rightOf(parent),
    top: .topOf(parent),
    width: .fixed(100),
    height: .fixed(50),
    horizontalBias: 0.25,
    child: _box(#leftRight),
  ),
];

Widget _marker(Symbol id, Symbol vertical, Symbol horizontal) => Constrained(
  id: id,
  left: .leftOf(vertical),
  top: .topOf(horizontal),
  width: .fixed(10),
  height: .fixed(10),
  child: _box(id),
);

List<Widget> _guided() => [
  const Guideline.vertical(id: #vPercent, percent: 0.25),
  const Guideline.vertical(id: #vBegin, begin: 100),
  const Guideline.vertical(id: #vEnd, end: 150),
  const Guideline.horizontal(id: #hPercent, percent: 0.25),
  const Guideline.horizontal(id: #hBegin, begin: 100),
  const Guideline.horizontal(id: #hEnd, end: 150),
  _marker(#atPercent, #vPercent, #hPercent),
  _marker(#atBegin, #vBegin, #hBegin),
  _marker(#atEnd, #vEnd, #hEnd),
];

List<Widget> _marginChain(ChainStyle style) => [
  for (var i = 0; i < 3; i++)
    Constrained(
      id: Symbol('c$i'),
      start: i == 0
          ? .startOf(parent, margin: 24)
          : .endOf(Symbol('c${i - 1}')),
      end: i == 2 ? .endOf(parent, margin: 24) : .startOf(Symbol('c${i + 1}')),
      top: .topOf(parent),
      width: .fixed(24),
      height: .fixed(24),
      horizontalChainStyle: i == 0 ? style : null,
      child: _box(Symbol('c$i')),
    ),
];

const _rtl = TextDirection.rtl;

/// The layouts of features_test.dart.
final List<LayoutFixture> featureFixtures = [
  LayoutFixture(
    'dimensions: percent width',
    () => [
      Constrained(
        id: #a,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        width: .percent(0.5),
        height: .fixed(40),
        child: _box(#a),
      ),
    ],
  ),
  LayoutFixture(
    'dimensions: percent with max',
    () => [
      Constrained(
        id: #a,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        width: .percent(0.9, max: 300),
        height: .fixed(40),
        child: _box(#a),
      ),
    ],
  ),
  LayoutFixture(
    'dimensions: percent with min',
    () => [
      Constrained(
        id: #a,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        width: .percent(0.1, min: 200),
        height: .fixed(40),
        child: _box(#a),
      ),
    ],
  ),
  LayoutFixture(
    'dimensions: spread with max',
    () => [
      Constrained(
        id: #a,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        width: .spread(max: 250),
        height: .fixed(40),
        child: _box(#a),
      ),
    ],
  ),
  LayoutFixture(
    'dimensions: constrainedWrap',
    () => [
      Constrained(
        id: #big,
        start: .startOf(parent, margin: 200),
        end: .endOf(parent, margin: 200),
        top: .topOf(parent),
        width: .constrainedWrap(),
        height: .fixed(40),
        child: SizedBox(key: const ValueKey(#big), width: 700),
      ),
      Constrained(
        id: #small,
        start: .startOf(parent, margin: 200),
        end: .endOf(parent, margin: 200),
        top: .topOf(parent, margin: 100),
        width: .constrainedWrap(),
        height: .fixed(40),
        child: SizedBox(key: const ValueKey(#small), width: 100),
      ),
    ],
  ),
  LayoutFixture('chains: spread', () => _chain(null)),
  LayoutFixture('chains: spreadInside', () => _chain(.spreadInside)),
  LayoutFixture('chains: packed', () => _chain(.packed)),
  LayoutFixture(
    'chains: weighted',
    () => _chain(null, weightA: 1, weightB: 3),
  ),
  for (final vis in ConstraintVisibility.values)
    LayoutFixture('visibility: ${vis.name} pair', () => _pair(vis)),
  for (final vis in const [
    ConstraintVisibility.invisible,
    ConstraintVisibility.visible,
  ])
    LayoutFixture(
      'visibility: ${vis.name} tappable',
      () => [_tappable(Symbol(vis.name), vis)],
    ),
  LayoutFixture(
    'circular positioning',
    () => [
      Constrained(
        id: #hub,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        bottom: .bottomOf(parent),
        width: .fixed(100),
        height: .fixed(100),
        child: _box(#hub),
      ),
      Constrained(
        id: #east,
        circle: .around(#hub, angle: 90, radius: 200),
        width: .fixed(20),
        height: .fixed(20),
        child: _box(#east),
      ),
      Constrained(
        id: #north,
        circle: .around(#hub, angle: 0, radius: 150),
        width: .fixed(20),
        height: .fixed(20),
        child: _box(#north),
      ),
    ],
  ),
  for (final percent in [0.25, 0.75])
    LayoutFixture(
      'guidelines: vertical at $percent',
      () => _guidelinePercent(percent),
    ),
  LayoutFixture(
    'guidelines: begin and end',
    () => [
      const Guideline.vertical(id: #gb, begin: 150),
      const Guideline.horizontal(id: #ge, end: 100),
      Constrained(
        id: #a,
        start: .rightOf(#gb),
        bottom: .topOf(#ge),
        width: .fixed(100),
        height: .fixed(50),
        child: _box(#a),
      ),
    ],
  ),
  LayoutFixture('barriers: furthest edge', () => _labeled(250)),
  LayoutFixture('barriers: margin', () => _labeled(250, margin: 10)),
  LayoutFixture('barriers: resized reference', () => _labeled(60)),
  LayoutFixture(
    'flow: no wrap',
    () => [
      _cell(#a, 100, 40),
      _cell(#b, 100, 40),
      _cell(#c, 100, 40),
      ConstraintFlow(
        id: #flow,
        referenced: const [#a, #b, #c],
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        width: .matchConstraint,
        horizontalChainStyle: ChainStyle.packed,
        horizontalGap: 10,
      ),
    ],
  ),
  LayoutFixture(
    'flow: chain wrap',
    () => [
      _cell(#a, 300, 40),
      _cell(#b, 300, 40),
      _cell(#c, 300, 40),
      ConstraintFlow(
        id: #flow,
        referenced: const [#a, #b, #c],
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        width: .matchConstraint,
        height: .wrapContent,
        wrap: .chain,
      ),
    ],
  ),
  LayoutFixture(
    'flow: maxElementsWrap',
    () => [
      _cell(#a, 100, 40),
      _cell(#b, 100, 40),
      _cell(#c, 100, 40),
      ConstraintFlow(
        id: #flow,
        referenced: const [#a, #b, #c],
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        width: .matchConstraint,
        height: .wrapContent,
        wrap: .chain,
        maxElementsWrap: 2,
      ),
    ],
  ),
  for (final wrap in [FlowWrap.chain, FlowWrap.aligned])
    for (final width in [332.0, 331.0])
      LayoutFixture(
        'flow: ${wrap.name} wrap at $width',
        () => _chipFlow(wrap),
        size: Size(width, 600),
      ),
  for (final width in [352.0, 351.0])
    LayoutFixture(
      'flow: padding at $width',
      () => _chipFlow(.chain, padding: 10),
      size: Size(width, 600),
    ),
  LayoutFixture(
    'flow: padding, right-to-left',
    () => _chipFlow(.chain, padding: 10),
    size: const Size(352, 600),
    direction: _rtl,
  ),
  LayoutFixture(
    'flow: the website example',
    () {
      const chips = {
        #constraint: 90.95,
        #layout: 66.15,
        #wraps: 65.62,
        #when: 61.39,
        #it: 36.42,
        #runs: 55.3,
        #out: 48.42,
        #of: 40.83,
        #room: 59.41,
      };
      return [
        for (final MapEntry(key: id, value: width) in chips.entries)
          _chip(id, width),
        ConstraintFlow(
          id: #flow,
          referenced: chips.keys.toList(),
          start: .startOf(parent, margin: 12),
          end: .endOf(parent, margin: 12),
          top: .topOf(parent, margin: 12),
          width: .matchConstraint,
          wrap: .chain,
          horizontalGap: 8,
          verticalGap: 8,
          horizontalChainStyle: .packed,
          contentHorizontalBias: 0,
        ),
      ];
    },
    size: const Size(316, 188),
  ),
  LayoutFixture(
    'grid: rows and columns',
    () => [
      _cell(#a, 10, 10),
      _cell(#b, 10, 10),
      _cell(#c, 10, 10),
      _cell(#d, 10, 10),
      ConstraintGrid(
        id: #grid,
        referenced: const [#a, #b, #c, #d],
        rows: 2,
        columns: 2,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        bottom: .bottomOf(parent),
      ),
    ],
  ),
  LayoutFixture(
    'grid: column weights',
    () => [
      _cell(#a, 10, 10),
      _cell(#b, 10, 10),
      ConstraintGrid(
        id: #grid,
        referenced: const [#a, #b],
        rows: 1,
        columns: 2,
        columnWeights: const [1, 3],
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        bottom: .bottomOf(parent),
      ),
    ],
  ),
  LayoutFixture(
    'grid: spans',
    () => [
      Constrained(
        id: #a,
        width: .matchConstraint,
        height: .matchConstraint,
        child: _box(#a),
      ),
      _cell(#b, 10, 10),
      _cell(#c, 10, 10),
      ConstraintGrid(
        id: #grid,
        referenced: const [#a, #b, #c],
        rows: 2,
        columns: 2,
        spans: '0:1x2',
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        bottom: .bottomOf(parent),
      ),
    ],
  ),
  LayoutFixture(
    'flow: reflow, three referenced',
    () => _reflowFlow(const [
      #a,
      #b,
      #c,
    ]),
  ),
  LayoutFixture(
    'flow: reflow, two referenced',
    () => _reflowFlow(const [
      #a,
      #b,
    ]),
  ),
  for (final direction in TextDirection.values)
    LayoutFixture(
      'right-to-left: start/end replace absolute links (${direction.name})',
      _startEndReplaceAbsolute,
      direction: direction,
    ),
  for (final direction in TextDirection.values)
    LayoutFixture(
      'right-to-left: biased (${direction.name})',
      _biased,
      direction: direction,
    ),
  LayoutFixture(
    'right-to-left: packed start/end chain',
    () => [
      Constrained(
        id: #a,
        start: .startOf(parent),
        end: .startOf(#b),
        top: .topOf(parent),
        width: .fixed(100),
        height: .fixed(50),
        horizontalChainStyle: ChainStyle.packed,
        horizontalBias: 0,
        child: _box(#a),
      ),
      Constrained(
        id: #b,
        start: .endOf(#a),
        end: .endOf(parent),
        top: .topOf(parent),
        width: .fixed(100),
        height: .fixed(50),
        child: _box(#b),
      ),
    ],
    direction: _rtl,
  ),
  for (final direction in TextDirection.values)
    LayoutFixture(
      'right-to-left: guidelines (${direction.name})',
      _guided,
      direction: direction,
    ),
  LayoutFixture(
    'right-to-left: flow bias',
    () => [
      Constrained(
        id: #a,
        width: .fixed(100),
        height: .fixed(40),
        child: _box(#a),
      ),
      ConstraintFlow(
        id: #flow,
        referenced: const [#a],
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        width: .fixed(300),
        horizontalBias: 0.25,
      ),
    ],
    direction: _rtl,
  ),
  LayoutFixture(
    'right-to-left: flow rows',
    () => [
      for (final id in const [#a, #b, #c])
        Constrained(
          id: id,
          width: .fixed(100),
          height: .fixed(40),
          child: _box(id),
        ),
      ConstraintFlow(
        id: #flow,
        referenced: const [#a, #b, #c],
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        width: .matchConstraint,
        horizontalChainStyle: ChainStyle.packed,
        contentHorizontalBias: 0,
      ),
    ],
    direction: _rtl,
  ),
  LayoutFixture(
    'right-to-left: grid',
    () => [
      for (final id in const [#a, #b])
        Constrained(
          id: id,
          width: .matchConstraint,
          height: .matchConstraint,
          child: _box(id),
        ),
      ConstraintGrid(
        id: #grid,
        referenced: const [#a, #b],
        rows: 1,
        columns: 2,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        bottom: .bottomOf(parent),
      ),
    ],
    direction: _rtl,
  ),
  LayoutFixture(
    'right-to-left: barrier margin',
    () => [
      Constrained(
        id: #label,
        start: .startOf(parent, margin: 100),
        top: .topOf(parent),
        width: .fixed(100),
        height: .fixed(30),
        child: _box(#label),
      ),
      const Barrier(
        id: #labelEnd,
        edge: .end,
        referenced: [#label],
        margin: 10,
      ),
      Constrained(
        id: #marker,
        left: .leftOf(#labelEnd),
        top: .bottomOf(#label),
        width: .fixed(10),
        height: .fixed(10),
        child: _box(#marker),
      ),
    ],
    direction: _rtl,
  ),
  for (final style in ChainStyle.values)
    for (final direction in TextDirection.values)
      LayoutFixture(
        'right-to-left: ${style.name} chain with margins (${direction.name})',
        () => _marginChain(style),
        direction: direction,
      ),
  LayoutFixture(
    'right-to-left: weighted chain with margins',
    () => [
      Constrained(
        id: #cancel,
        start: .startOf(parent, margin: 16),
        end: .startOf(#confirm, margin: 8),
        top: .topOf(parent),
        width: .matchConstraint,
        height: .fixed(40),
        horizontalWeight: 1,
        child: _box(#cancel),
      ),
      Constrained(
        id: #confirm,
        start: .endOf(#cancel),
        end: .endOf(parent, margin: 16),
        top: .topOf(parent),
        width: .matchConstraint,
        height: .fixed(40),
        horizontalWeight: 2,
        child: _box(#confirm),
      ),
    ],
    direction: _rtl,
  ),
  LayoutFixture(
    'right-to-left: vertical chain with margins',
    () => [
      for (var i = 0; i < 3; i++)
        Constrained(
          id: Symbol('v$i'),
          start: .startOf(parent),
          top: i == 0
              ? .topOf(parent, margin: 40)
              : .bottomOf(Symbol('v${i - 1}')),
          bottom: i == 2
              ? .bottomOf(parent, margin: 40)
              : .topOf(Symbol('v${i + 1}')),
          width: .fixed(50),
          height: .fixed(50),
          verticalChainStyle: i == 0 ? ChainStyle.spreadInside : null,
          child: _box(Symbol('v$i')),
        ),
    ],
    direction: _rtl,
  ),
];

// ---------------------------------------------------------------------------
// golden/layout_golden_test.dart (400 x 300 unless noted)
// ---------------------------------------------------------------------------

const Color _blue = Color(0xFF3B82F6);
const Color _green = Color(0xFF22C55E);
const Color _amber = Color(0xFFF59E0B);
const Color _red = Color(0xFFEF4444);
const Color _purple = Color(0xFFA855F7);
const Color _teal = Color(0xFF14B8A6);
const List<Color> _palette = [_blue, _green, _amber, _red, _purple, _teal];

Widget _fill(Symbol id, Color color) =>
    ColoredBox(key: ValueKey(id), color: color);

Widget _sized(Symbol id, Color color, double width, double height) => SizedBox(
  key: ValueKey(id),
  width: width,
  height: height,
  child: ColoredBox(color: color),
);

Widget _label(Symbol id, String text, double size, Color color) => Text(
  text,
  key: ValueKey(id),
  style: TextStyle(fontSize: size, color: color, height: 1.2),
);

List<Widget> _horizontalChain(ChainStyle style) => [
  Constrained(
    id: #a,
    start: .startOf(parent),
    end: .startOf(#b),
    top: .topOf(parent),
    bottom: .bottomOf(parent),
    horizontalChainStyle: style,
    width: .fixed(80),
    height: .fixed(60),
    child: _fill(#a, _blue),
  ),
  Constrained(
    id: #b,
    start: .endOf(#a),
    end: .startOf(#c),
    top: .topOf(#a),
    width: .fixed(80),
    height: .fixed(60),
    child: _fill(#b, _green),
  ),
  Constrained(
    id: #c,
    start: .endOf(#b),
    end: .endOf(parent),
    top: .topOf(#a),
    width: .fixed(80),
    height: .fixed(60),
    child: _fill(#c, _amber),
  ),
];

List<Widget> _visibilityRow(ConstraintVisibility middle) => [
  Constrained(
    id: #a,
    start: .startOf(parent, margin: 16),
    top: .topOf(parent, margin: 16),
    width: .fixed(80),
    height: .fixed(60),
    child: _fill(#a, _blue),
  ),
  Constrained(
    id: #b,
    start: .endOf(#a, margin: 12),
    top: .topOf(#a),
    width: .fixed(80),
    height: .fixed(60),
    visibility: middle,
    child: _fill(#b, _green),
  ),
  Constrained(
    id: #c,
    start: .endOf(#b, margin: 12, goneMargin: 40),
    top: .topOf(#a),
    width: .fixed(80),
    height: .fixed(60),
    child: _fill(#c, _amber),
  ),
];

List<Widget> _startEndLayout() => [
  Constrained(
    id: #leading,
    start: .startOf(parent, margin: 16),
    top: .topOf(parent, margin: 16),
    width: .fixed(70),
    height: .fixed(50),
    child: _fill(#leading, _blue),
  ),
  Constrained(
    id: #next,
    start: .endOf(#leading, margin: 12),
    top: .topOf(#leading),
    width: .fixed(70),
    height: .fixed(50),
    child: _fill(#next, _green),
  ),
  Constrained(
    id: #absolute,
    left: .leftOf(parent, margin: 16),
    top: .bottomOf(#leading, margin: 16),
    width: .fixed(70),
    height: .fixed(50),
    child: _fill(#absolute, _amber),
  ),
];

List<Widget> _flowChildren(int count) => [
  for (var i = 0; i < count; i++)
    Constrained(
      id: Symbol('f$i'),
      width: .fixed(70),
      height: .fixed(34),
      child: _fill(Symbol('f$i'), _palette[i % _palette.length]),
    ),
];

const _goldenSize = Size(400, 300);

/// The layouts of golden/layout_golden_test.dart.
final List<LayoutFixture> goldenFixtures = [
  LayoutFixture(
    'golden: anchors_corners',
    () => [
      Constrained(
        id: #tl,
        start: .startOf(parent, margin: 16),
        top: .topOf(parent, margin: 16),
        width: .fixed(90),
        height: .fixed(50),
        child: _fill(#tl, _blue),
      ),
      Constrained(
        id: #tr,
        end: .endOf(parent, margin: 16),
        top: .topOf(parent, margin: 16),
        width: .fixed(90),
        height: .fixed(50),
        child: _fill(#tr, _green),
      ),
      Constrained(
        id: #bl,
        start: .startOf(parent, margin: 16),
        bottom: .bottomOf(parent, margin: 16),
        width: .fixed(90),
        height: .fixed(50),
        child: _fill(#bl, _amber),
      ),
      Constrained(
        id: #br,
        end: .endOf(parent, margin: 16),
        bottom: .bottomOf(parent, margin: 16),
        width: .fixed(90),
        height: .fixed(50),
        child: _fill(#br, _red),
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: anchors_stacked_siblings',
    () => [
      Constrained(
        id: #a,
        start: .startOf(parent, margin: 20),
        top: .topOf(parent, margin: 20),
        width: .fixed(140),
        height: .fixed(44),
        child: _fill(#a, _blue),
      ),
      Constrained(
        id: #b,
        start: .startOf(#a, margin: 24),
        top: .bottomOf(#a, margin: 12),
        width: .fixed(140),
        height: .fixed(44),
        child: _fill(#b, _green),
      ),
      Constrained(
        id: #c,
        start: .startOf(#b, margin: 24),
        top: .bottomOf(#b, margin: 12),
        width: .fixed(140),
        height: .fixed(44),
        child: _fill(#c, _amber),
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: centering_bias',
    () => [
      Constrained(
        id: #center,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        bottom: .bottomOf(parent),
        width: .fixed(100),
        height: .fixed(60),
        child: _fill(#center, _blue),
      ),
      Constrained(
        id: #left,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent, margin: 12),
        horizontalBias: 0.1,
        width: .fixed(70),
        height: .fixed(36),
        child: _fill(#left, _green),
      ),
      Constrained(
        id: #right,
        start: .startOf(parent),
        end: .endOf(parent),
        bottom: .bottomOf(parent, margin: 12),
        horizontalBias: 0.9,
        width: .fixed(70),
        height: .fixed(36),
        child: _fill(#right, _amber),
      ),
      Constrained(
        id: #high,
        start: .startOf(parent, margin: 12),
        top: .topOf(parent),
        bottom: .bottomOf(parent),
        verticalBias: 0.15,
        width: .fixed(36),
        height: .fixed(70),
        child: _fill(#high, _purple),
      ),
    ],
    size: _goldenSize,
  ),
  for (final style in ChainStyle.values)
    LayoutFixture(
      'golden: chain_${style.name}',
      () => _horizontalChain(style),
      size: _goldenSize,
    ),
  LayoutFixture(
    'golden: chain_weighted',
    () => [
      Constrained(
        id: #a,
        start: .startOf(parent),
        end: .startOf(#b),
        top: .topOf(parent),
        bottom: .bottomOf(parent),
        horizontalChainStyle: .spread,
        horizontalWeight: 1,
        width: .matchConstraint,
        height: .fixed(80),
        child: _fill(#a, _blue),
      ),
      Constrained(
        id: #b,
        start: .endOf(#a),
        end: .startOf(#c),
        top: .topOf(#a),
        horizontalWeight: 2,
        width: .matchConstraint,
        height: .fixed(80),
        child: _fill(#b, _green),
      ),
      Constrained(
        id: #c,
        start: .endOf(#b),
        end: .endOf(parent),
        top: .topOf(#a),
        horizontalWeight: 1,
        width: .matchConstraint,
        height: .fixed(80),
        child: _fill(#c, _amber),
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: chain_vertical_packed',
    () => [
      Constrained(
        id: #a,
        top: .topOf(parent),
        bottom: .topOf(#b),
        start: .startOf(parent),
        end: .endOf(parent),
        verticalChainStyle: .packed,
        verticalBias: 0.2,
        width: .fixed(160),
        height: .fixed(50),
        child: _fill(#a, _blue),
      ),
      Constrained(
        id: #b,
        top: .bottomOf(#a, margin: 8),
        bottom: .topOf(#c),
        start: .startOf(#a),
        width: .fixed(160),
        height: .fixed(50),
        child: _fill(#b, _green),
      ),
      Constrained(
        id: #c,
        top: .bottomOf(#b, margin: 8),
        bottom: .bottomOf(parent),
        start: .startOf(#a),
        width: .fixed(160),
        height: .fixed(50),
        child: _fill(#c, _amber),
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: guidelines',
    () => [
      const Guideline.vertical(id: #third, percent: 0.33),
      const Guideline.vertical(id: #fromEnd, end: 60),
      const Guideline.horizontal(id: #fromTop, begin: 80),
      Constrained(
        id: #a,
        start: .startOf(parent),
        end: .leftOf(#third),
        top: .topOf(parent),
        bottom: .topOf(#fromTop),
        width: .matchConstraint,
        height: .matchConstraint,
        child: _fill(#a, _blue),
      ),
      Constrained(
        id: #b,
        start: .rightOf(#third, margin: 8),
        end: .leftOf(#fromEnd, margin: 8),
        top: .bottomOf(#fromTop, margin: 8),
        width: .matchConstraint,
        height: .fixed(60),
        child: _fill(#b, _green),
      ),
      Constrained(
        id: #c,
        start: .rightOf(#fromEnd),
        end: .endOf(parent),
        top: .bottomOf(#fromTop, margin: 8),
        bottom: .bottomOf(parent, margin: 8),
        width: .matchConstraint,
        height: .matchConstraint,
        child: _fill(#c, _amber),
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: barrier_end',
    () => [
      Constrained(
        id: #short,
        start: .startOf(parent, margin: 12),
        top: .topOf(parent, margin: 12),
        width: .fixed(60),
        height: .fixed(40),
        child: _fill(#short, _blue),
      ),
      Constrained(
        id: #long,
        start: .startOf(parent, margin: 12),
        top: .bottomOf(#short, margin: 8),
        width: .fixed(150),
        height: .fixed(40),
        child: _fill(#long, _green),
      ),
      Constrained(
        id: #mid,
        start: .startOf(parent, margin: 12),
        top: .bottomOf(#long, margin: 8),
        width: .fixed(100),
        height: .fixed(40),
        child: _fill(#mid, _amber),
      ),
      const Barrier(id: #widest, edge: .end, referenced: [#short, #long, #mid]),
      Constrained(
        id: #value,
        start: .rightOf(#widest, margin: 16),
        end: .endOf(parent, margin: 12),
        top: .topOf(#short),
        bottom: .bottomOf(#mid),
        width: .matchConstraint,
        height: .matchConstraint,
        child: _fill(#value, _purple),
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: barrier_bottom',
    () => [
      for (final (i, height) in const [40.0, 90.0, 60.0].indexed)
        Constrained(
          id: Symbol('c$i'),
          start: i == 0
              ? .startOf(parent, margin: 16)
              : .endOf(Symbol('c${i - 1}'), margin: 10),
          top: .topOf(parent, margin: 16),
          width: .fixed(90),
          height: .fixed(height),
          child: _fill(Symbol('c$i'), _palette[i]),
        ),
      const Barrier(
        id: #below,
        edge: .bottom,
        referenced: [#c0, #c1, #c2],
        margin: 12,
      ),
      Constrained(
        id: #footer,
        start: .startOf(parent, margin: 16),
        end: .endOf(parent, margin: 16),
        top: .bottomOf(#below),
        width: .matchConstraint,
        height: .fixed(44),
        child: _fill(#footer, _teal),
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: circular_dial',
    () => [
      Constrained(
        id: #hub,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        bottom: .bottomOf(parent),
        width: .fixed(40),
        height: .fixed(40),
        child: _fill(#hub, _blue),
      ),
      for (var i = 0; i < 8; i++)
        Constrained(
          id: Symbol('s$i'),
          circle: .around(#hub, angle: i * 45, radius: 100),
          width: .fixed(28),
          height: .fixed(28),
          child: _fill(Symbol('s$i'), _palette[i % _palette.length]),
        ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: dimensions_modes',
    () => [
      Constrained(
        id: #half,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent, margin: 10),
        width: .percent(0.5),
        height: .fixed(40),
        child: _fill(#half, _blue),
      ),
      Constrained(
        id: #capped,
        start: .startOf(parent, margin: 10),
        end: .endOf(parent, margin: 10),
        top: .bottomOf(#half, margin: 10),
        width: .spread(max: 160),
        height: .fixed(40),
        child: _fill(#capped, _green),
      ),
      Constrained(
        id: #floored,
        start: .startOf(parent, margin: 140),
        end: .endOf(parent, margin: 140),
        top: .bottomOf(#capped, margin: 10),
        width: .spread(min: 200),
        height: .fixed(40),
        child: _fill(#floored, _amber),
      ),
      Constrained(
        id: #wrapped,
        start: .startOf(parent, margin: 10),
        end: .endOf(parent, margin: 10),
        top: .bottomOf(#floored, margin: 10),
        width: .constrainedWrap(max: 120),
        height: .fixed(40),
        child: _sized(#wrapped, _red, 300, 40),
      ),
      Constrained(
        id: #full,
        top: .bottomOf(#wrapped, margin: 10),
        width: .matchParent,
        height: .fixed(30),
        child: _fill(#full, _purple),
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: aspect_ratio',
    () => [
      const Guideline.horizontal(id: #split, percent: 0.5),
      Constrained(
        id: #wide,
        start: .startOf(parent, margin: 12),
        end: .endOf(parent, margin: 12),
        top: .topOf(parent, margin: 12),
        bottom: .topOf(#split, margin: 6),
        width: .matchConstraint,
        height: .matchConstraint,
        aspectRatio: 16 / 9,
        child: _fill(#wide, _blue),
      ),
      Constrained(
        id: #square,
        start: .startOf(parent, margin: 12),
        end: .endOf(parent, margin: 12),
        top: .bottomOf(#split, margin: 6),
        bottom: .bottomOf(parent, margin: 12),
        width: .matchConstraint,
        height: .matchConstraint,
        aspectRatio: 1,
        child: _fill(#square, _green),
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: dimensions_wrap_content',
    () => [
      Constrained(
        id: #a,
        start: .startOf(parent, margin: 16),
        top: .topOf(parent, margin: 16),
        child: _sized(#a, _blue, 120, 44),
      ),
      Constrained(
        id: #b,
        start: .endOf(#a, margin: 16),
        top: .topOf(#a),
        child: _sized(#b, _green, 60, 80),
      ),
      Constrained(
        id: #c,
        start: .startOf(#a),
        top: .bottomOf(#b, margin: 16),
        child: _sized(#c, _amber, 200, 30),
      ),
    ],
    size: _goldenSize,
  ),
  for (final visibility in ConstraintVisibility.values)
    LayoutFixture(
      'golden: visibility_${visibility.name}',
      () => _visibilityRow(visibility),
      size: const Size(400, 120),
    ),
  for (final direction in TextDirection.values)
    LayoutFixture(
      'golden: direction_${direction.name}',
      _startEndLayout,
      size: const Size(400, 160),
      direction: direction,
    ),
  for (final wrap in FlowWrap.values)
    LayoutFixture(
      'golden: flow_${wrap.name}',
      () => [
        ..._flowChildren(7),
        ConstraintFlow(
          id: #flow,
          referenced: const [#f0, #f1, #f2, #f3, #f4, #f5, #f6],
          start: .startOf(parent, margin: 12),
          end: .endOf(parent, margin: 12),
          top: .topOf(parent, margin: 12),
          width: .matchConstraint,
          wrap: wrap,
          horizontalGap: 10,
          verticalGap: 10,
          horizontalChainStyle: .packed,
        ),
      ],
      size: _goldenSize,
    ),
  LayoutFixture(
    'golden: flow_vertical',
    () => [
      ..._flowChildren(6),
      ConstraintFlow(
        id: #flow,
        referenced: const [#f0, #f1, #f2, #f3, #f4, #f5],
        orientation: Axis.vertical,
        start: .startOf(parent, margin: 12),
        top: .topOf(parent, margin: 12),
        bottom: .bottomOf(parent, margin: 12),
        height: .matchConstraint,
        wrap: .chain,
        horizontalGap: 10,
        verticalGap: 10,
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: flow_align_top',
    () => [
      for (var i = 0; i < 5; i++)
        Constrained(
          id: Symbol('f$i'),
          width: .fixed(70),
          height: .fixed(i.isEven ? 30.0 : 60.0),
          child: _fill(Symbol('f$i'), _palette[i % _palette.length]),
        ),
      ConstraintFlow(
        id: #flow,
        referenced: const [#f0, #f1, #f2, #f3, #f4],
        start: .startOf(parent, margin: 12),
        end: .endOf(parent, margin: 12),
        top: .topOf(parent, margin: 12),
        width: .matchConstraint,
        wrap: .chain,
        horizontalGap: 10,
        verticalGap: 10,
        verticalAlign: .top,
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: grid_basic',
    () => [
      for (var i = 0; i < 6; i++)
        Constrained(
          id: Symbol('g$i'),
          width: .fixed(60),
          height: .fixed(40),
          child: _fill(Symbol('g$i'), _palette[i % _palette.length]),
        ),
      ConstraintGrid(
        id: #grid,
        referenced: const [#g0, #g1, #g2, #g3, #g4, #g5],
        rows: 2,
        columns: 3,
        start: .startOf(parent, margin: 16),
        end: .endOf(parent, margin: 16),
        top: .topOf(parent, margin: 16),
        bottom: .bottomOf(parent, margin: 16),
        horizontalGap: 8,
        verticalGap: 8,
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: grid_spans_skips',
    () => [
      for (var i = 0; i < 4; i++)
        Constrained(
          id: Symbol('g$i'),
          width: .matchConstraint,
          height: .matchConstraint,
          child: _fill(Symbol('g$i'), _palette[i % _palette.length]),
        ),
      ConstraintGrid(
        id: #grid,
        referenced: const [#g0, #g1, #g2, #g3],
        rows: 3,
        columns: 3,
        spans: '0:1x2',
        skips: '4:1x1',
        start: .startOf(parent, margin: 16),
        end: .endOf(parent, margin: 16),
        top: .topOf(parent, margin: 16),
        bottom: .bottomOf(parent, margin: 16),
        horizontalGap: 6,
        verticalGap: 6,
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: grid_weights',
    () => [
      for (var i = 0; i < 4; i++)
        Constrained(
          id: Symbol('g$i'),
          width: .matchConstraint,
          height: .matchConstraint,
          child: _fill(Symbol('g$i'), _palette[i % _palette.length]),
        ),
      ConstraintGrid(
        id: #grid,
        referenced: const [#g0, #g1, #g2, #g3],
        rows: 2,
        columns: 2,
        rowWeights: const [1, 3],
        columnWeights: const [2, 1],
        start: .startOf(parent, margin: 16),
        end: .endOf(parent, margin: 16),
        top: .topOf(parent, margin: 16),
        bottom: .bottomOf(parent, margin: 16),
        horizontalGap: 6,
        verticalGap: 6,
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: baseline_align',
    () => [
      Constrained(
        id: #big,
        start: .startOf(parent, margin: 16),
        top: .topOf(parent, margin: 40),
        child: _label(#big, 'Ag', 42, _blue),
      ),
      Constrained(
        id: #mid,
        start: .endOf(#big, margin: 12),
        baseline: .baselineOf(#big),
        child: _label(#mid, 'Ag', 26, _green),
      ),
      Constrained(
        id: #small,
        start: .endOf(#mid, margin: 12),
        baseline: .baselineOf(#big),
        child: _label(#small, 'Ag', 14, _amber),
      ),
    ],
    size: const Size(400, 140),
  ),
  LayoutFixture(
    'golden: nested_layouts',
    () => [
      Constrained(
        id: #outer,
        start: .startOf(parent, margin: 20),
        end: .endOf(parent, margin: 20),
        top: .topOf(parent, margin: 20),
        bottom: .bottomOf(parent, margin: 20),
        width: .matchConstraint,
        height: .matchConstraint,
        child: ColoredBox(
          key: const ValueKey(#outer),
          color: const Color(0xFF1E2732),
          child: ConstraintLayout(
            children: [
              Constrained(
                id: #inner1,
                start: .startOf(parent, margin: 10),
                top: .topOf(parent, margin: 10),
                width: .fixed(80),
                height: .fixed(50),
                child: _fill(#inner1, _blue),
              ),
              Constrained(
                id: #inner2,
                end: .endOf(parent, margin: 10),
                bottom: .bottomOf(parent, margin: 10),
                width: .fixed(80),
                height: .fixed(50),
                child: _fill(#inner2, _green),
              ),
              Constrained(
                id: #inner3,
                start: .startOf(parent),
                end: .endOf(parent),
                top: .topOf(parent),
                bottom: .bottomOf(parent),
                width: .fixed(60),
                height: .fixed(60),
                child: _fill(#inner3, _amber),
              ),
            ],
          ),
        ),
      ),
    ],
    size: _goldenSize,
  ),
  LayoutFixture(
    'golden: z_index',
    () => [
      Constrained(
        id: #back,
        start: .startOf(parent, margin: 20),
        top: .topOf(parent, margin: 20),
        width: .fixed(140),
        height: .fixed(90),
        zIndex: 10,
        child: _fill(#back, _blue),
      ),
      Constrained(
        id: #front,
        start: .startOf(parent, margin: 90),
        top: .topOf(parent, margin: 50),
        width: .fixed(140),
        height: .fixed(90),
        child: _fill(#front, _amber),
      ),
    ],
    size: const Size(300, 180),
  ),
  LayoutFixture('golden: edge_empty', () => [], size: const Size(200, 100)),
  LayoutFixture(
    'golden: edge_unconstrained',
    () => [
      Constrained(id: #a, child: _sized(#a, _blue, 90, 40)),
      Constrained(
        id: #b,
        width: .fixed(60),
        height: .fixed(60),
        child: _fill(#b, _green),
      ),
    ],
    size: const Size(200, 120),
  ),
  LayoutFixture(
    'golden: edge_oversized_child',
    () => [
      Constrained(
        id: #wide,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent, margin: 10),
        width: .fixed(280),
        height: .fixed(40),
        child: _fill(#wide, _blue),
      ),
      Constrained(
        id: #tall,
        start: .startOf(parent, margin: 10),
        top: .topOf(parent),
        bottom: .bottomOf(parent),
        width: .fixed(40),
        height: .fixed(200),
        child: _fill(#tall, _green),
      ),
    ],
    size: const Size(200, 120),
  ),
  LayoutFixture(
    'golden: edge_single_chain',
    () => [
      Constrained(
        id: #only,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        bottom: .bottomOf(parent),
        horizontalChainStyle: .packed,
        width: .fixed(80),
        height: .fixed(40),
        child: _fill(#only, _blue),
      ),
    ],
    size: const Size(200, 100),
  ),
  LayoutFixture(
    'golden: edge_barrier_all_gone',
    () => [
      Constrained(
        id: #a,
        start: .startOf(parent, margin: 16),
        top: .topOf(parent, margin: 16),
        width: .fixed(80),
        height: .fixed(40),
        visibility: .gone,
        child: _fill(#a, _blue),
      ),
      const Barrier(id: #bar, edge: .end, referenced: [#a]),
      Constrained(
        id: #after,
        start: .rightOf(#bar, margin: 8),
        top: .topOf(parent, margin: 16),
        width: .fixed(80),
        height: .fixed(40),
        child: _fill(#after, _green),
      ),
    ],
    size: const Size(240, 100),
  ),
  LayoutFixture(
    'golden: edge_zero_size_parent',
    () => [
      Constrained(
        id: #a,
        start: .startOf(parent),
        end: .endOf(parent),
        top: .topOf(parent),
        width: .matchConstraint,
        height: .fixed(20),
        child: _fill(#a, _blue),
      ),
    ],
    size: Size.zero,
  ),
];
