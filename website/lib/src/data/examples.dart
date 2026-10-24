import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';

import '../widgets/live_example.dart';
import '../widgets/preview.dart';

/// The catalog of live docs examples: each entry pairs the source shown in the
/// code card with the real `ConstraintLayout` it renders in the preview canvas.
///
/// The two halves are authored together so they cannot drift. The `child` of
/// every `Constrained` is a [DemoBox]: a plain, auto-colored placeholder so the
/// reader's eye stays on the constraints, not the contents. Swap it for any of
/// your own widgets.
///
/// Keyed by the docs section id (see `data/docs_sections.dart`).
final Map<String, LiveExample> docExamples = {
  'quick-start': LiveExample(
    previewHeight: 200,
    code: r'''
ConstraintLayout(
  children: [
    Constrained(
      id: #box,
      // My start edge, 16 from the parent's start edge.
      start: .startOf(parent, margin: 16),
      // My top edge, 16 from the parent's top edge.
      top: .topOf(parent, margin: 16),
      child: DemoBox('A'),
    ),
  ],
)''',
    builder: (context) => ConstraintLayout(
      children: [
        Constrained(
          id: #box,
          start: .startOf(parent, margin: 16),
          top: .topOf(parent, margin: 16),
          child: const DemoBox('A'),
        ),
      ],
    ),
  ),

  'anchors': LiveExample(
    previewHeight: 200,
    code: r'''
ConstraintLayout(
  children: [
    Constrained(
      id: #a,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      child: DemoBox('A'),
    ),
    Constrained(
      id: #b,
      // Chain off a sibling: B's start sits at A's end.
      start: .endOf(#a, margin: 12),
      top: .topOf(#a),
      child: DemoBox('B'),
    ),
  ],
)''',
    builder: (context) => ConstraintLayout(
      children: [
        Constrained(
          id: #a,
          start: .startOf(parent, margin: 16),
          top: .topOf(parent, margin: 16),
          child: const DemoBox('A'),
        ),
        Constrained(
          id: #b,
          start: .endOf(#a, margin: 12),
          top: .topOf(#a),
          child: const DemoBox('B'),
        ),
      ],
    ),
  ),

  'centering-bias': LiveExample(
    previewHeight: 220,
    caption:
        'Opposing anchors on an axis center the child; bias slides it along '
        '(0 = start/top, 1 = end/bottom).',
    code: r'''
ConstraintLayout(
  children: [
    Constrained(
      id: #box,
      // Both horizontal and both vertical anchors: centered by default...
      start: .startOf(parent),
      end: .endOf(parent),
      top: .topOf(parent),
      bottom: .bottomOf(parent),
      // ...then biased off-center: 25% across, 70% down.
      horizontalBias: 0.25,
      verticalBias: 0.7,
      child: DemoBox('A'),
    ),
  ],
)''',
    builder: (context) => ConstraintLayout(
      children: [
        Constrained(
          id: #box,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
          horizontalBias: 0.25,
          verticalBias: 0.7,
          child: const DemoBox('A'),
        ),
      ],
    ),
  ),

  'dimensions': LiveExample(
    previewHeight: 220,
    caption:
        'matchConstraint fills the gap between two anchors; percent takes a '
        'fraction of the parent. Both need both edges on the axis anchored.',
    code: r'''
ConstraintLayout(
  children: [
    Constrained(
      id: #bar,
      start: .startOf(parent, margin: 16),
      end: .endOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      width: .matchConstraint, // fill the space between the anchors
      height: .fixed(44),
      child: DemoBox('matchConstraint'),
    ),
    Constrained(
      id: #half,
      start: .startOf(parent, margin: 16),
      end: .endOf(parent, margin: 16),
      top: .bottomOf(#bar, margin: 12),
      width: .percent(0.5),    // half the parent's width
      horizontalBias: 0,       // ...pinned to the start
      height: .fixed(44),
      child: DemoBox('percent 0.5'),
    ),
  ],
)''',
    builder: (context) => ConstraintLayout(
      children: [
        Constrained(
          id: #bar,
          start: .startOf(parent, margin: 16),
          end: .endOf(parent, margin: 16),
          top: .topOf(parent, margin: 16),
          width: .matchConstraint,
          height: .fixed(44),
          child: const DemoBox('matchConstraint'),
        ),
        Constrained(
          id: #half,
          start: .startOf(parent, margin: 16),
          end: .endOf(parent, margin: 16),
          top: .bottomOf(#bar, margin: 12),
          width: .percent(0.5),
          horizontalBias: 0,
          height: .fixed(44),
          child: const DemoBox('percent 0.5'),
        ),
      ],
    ),
  ),

  'aspect-ratio': LiveExample(
    previewHeight: 220,
    caption:
        'One axis is fixed; the matchConstraint axis is derived to hold the '
        'ratio. Here height follows a 200px width at 16 : 9.',
    code: r'''
ConstraintLayout(
  children: [
    Constrained(
      id: #media,
      start: .startOf(parent),
      end: .endOf(parent),
      top: .topOf(parent),
      bottom: .bottomOf(parent),
      width: .fixed(200),
      height: .matchConstraint, // derived from the width...
      aspectRatio: 16 / 9,      // ...to keep width / height = 16 / 9
      child: DemoBox('16 : 9'),
    ),
  ],
)''',
    builder: (context) => ConstraintLayout(
      children: [
        Constrained(
          id: #media,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
          width: .fixed(200),
          height: .matchConstraint,
          aspectRatio: 16 / 9,
          child: const DemoBox('16 : 9'),
        ),
      ],
    ),
  ),

  'chains': LiveExample(
    previewHeight: 200,
    caption:
        'Three boxes linked start-to-end form a chain. The style set on the '
        'head (A) governs the whole group; try spreadInside or packed.',
    code: r'''
ConstraintLayout(
  children: [
    Constrained(
      id: #a,
      start: .startOf(parent),
      end: .startOf(#b),
      top: .topOf(parent),
      bottom: .bottomOf(parent),
      horizontalChainStyle: .spread, // set on the head
      child: DemoBox('A'),
    ),
    Constrained(
      id: #b,
      start: .endOf(#a),
      end: .startOf(#c),
      top: .topOf(#a),
      child: DemoBox('B'),
    ),
    Constrained(
      id: #c,
      start: .endOf(#b),
      end: .endOf(parent),
      top: .topOf(#a),
      child: DemoBox('C'),
    ),
  ],
)''',
    builder: (context) => ConstraintLayout(
      children: [
        Constrained(
          id: #a,
          start: .startOf(parent),
          end: .startOf(#b),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
          horizontalChainStyle: .spread,
          child: const DemoBox('A'),
        ),
        Constrained(
          id: #b,
          start: .endOf(#a),
          end: .startOf(#c),
          top: .topOf(#a),
          child: const DemoBox('B'),
        ),
        Constrained(
          id: #c,
          start: .endOf(#b),
          end: .endOf(parent),
          top: .topOf(#a),
          child: const DemoBox('C'),
        ),
      ],
    ),
  ),

  'guidelines': LiveExample(
    previewHeight: 200,
    caption:
        'A guideline is an invisible line at a fixed offset or a percent of the '
        'parent. Everything anchored to it moves together when it moves.',
    code: r'''
ConstraintLayout(
  children: [
    // A vertical line at 40% of the width.
    Guideline.vertical(id: #split, percent: 0.4),
    Constrained(
      id: #label,
      end: .leftOf(#split, margin: 8),
      top: .topOf(parent, margin: 16),
      child: DemoBox('label'),
    ),
    Constrained(
      id: #value,
      start: .rightOf(#split, margin: 8),
      top: .topOf(#label),
      child: DemoBox('value'),
    ),
  ],
)''',
    builder: (context) => ConstraintLayout(
      children: [
        const Guideline.vertical(id: #split, percent: 0.4),
        Constrained(
          id: #label,
          end: .leftOf(#split, margin: 8),
          top: .topOf(parent, margin: 16),
          child: const DemoBox('label'),
        ),
        Constrained(
          id: #value,
          start: .rightOf(#split, margin: 8),
          top: .topOf(#label),
          child: const DemoBox('value'),
        ),
      ],
    ),
  ),

  'barriers': LiveExample(
    previewHeight: 220,
    caption:
        'A barrier tracks the furthest edge of the widgets it references, so C '
        'clears whichever of A or B is wider, even as their content changes.',
    code: r'''
ConstraintLayout(
  children: [
    Constrained(
      id: #a,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      width: .fixed(70),
      child: DemoBox('A'),
    ),
    Constrained(
      id: #b,
      start: .startOf(parent, margin: 16),
      top: .bottomOf(#a, margin: 12),
      width: .fixed(130),
      child: DemoBox('B is wider'),
    ),
    // Sits at the rightmost end of A and B.
    Barrier(id: #barrier, edge: .end, referenced: [#a, #b], margin: 12),
    Constrained(
      id: #c,
      start: .startOf(#barrier),
      top: .topOf(#a),
      bottom: .bottomOf(#b),
      height: .matchConstraint,
      child: DemoBox('C'),
    ),
  ],
)''',
    builder: (context) => ConstraintLayout(
      children: [
        Constrained(
          id: #a,
          start: .startOf(parent, margin: 16),
          top: .topOf(parent, margin: 16),
          width: .fixed(70),
          child: const DemoBox('A'),
        ),
        Constrained(
          id: #b,
          start: .startOf(parent, margin: 16),
          top: .bottomOf(#a, margin: 12),
          width: .fixed(130),
          child: const DemoBox('B is wider'),
        ),
        const Barrier(
          id: #barrier,
          edge: .end,
          referenced: [#a, #b],
          margin: 12,
        ),
        Constrained(
          id: #c,
          start: .startOf(#barrier),
          top: .topOf(#a),
          bottom: .bottomOf(#b),
          height: .matchConstraint,
          child: const DemoBox('C'),
        ),
      ],
    ),
  ),

  'circular': LiveExample(
    previewHeight: 260,
    caption:
        'Place a widget at an angle and radius around another. 0° points '
        'straight up and angles run clockwise.',
    code: r'''
ConstraintLayout(
  children: [
    Constrained(
      id: #hub,
      start: .startOf(parent),
      end: .endOf(parent),
      top: .topOf(parent),
      bottom: .bottomOf(parent),
      child: DemoBox('hub'),
    ),
    Constrained(
      id: #a,
      circle: .around(#hub, angle: 0, radius: 72),
      child: DemoBox('0°'),
    ),
    Constrained(
      id: #b,
      circle: .around(#hub, angle: 120, radius: 72),
      child: DemoBox('120°'),
    ),
    Constrained(
      id: #c,
      circle: .around(#hub, angle: 240, radius: 72),
      child: DemoBox('240°'),
    ),
  ],
)''',
    builder: (context) => ConstraintLayout(
      children: [
        Constrained(
          id: #hub,
          start: .startOf(parent),
          end: .endOf(parent),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
          child: const DemoBox('hub'),
        ),
        Constrained(
          id: #a,
          circle: .around(#hub, angle: 0, radius: 72),
          child: const DemoBox('0°'),
        ),
        Constrained(
          id: #b,
          circle: .around(#hub, angle: 120, radius: 72),
          child: const DemoBox('120°'),
        ),
        Constrained(
          id: #c,
          circle: .around(#hub, angle: 240, radius: 72),
          child: const DemoBox('240°'),
        ),
      ],
    ),
  ),

  'visibility': LiveExample(
    previewHeight: 200,
    caption:
        'A gone widget collapses to a point and links targeting it switch to '
        'their goneMargin, so C closes the gap B left behind.',
    code: r'''
ConstraintLayout(
  children: [
    Constrained(
      id: #a,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      child: DemoBox('A'),
    ),
    Constrained(
      id: #b,
      start: .endOf(#a, margin: 12),
      top: .topOf(#a),
      visibility: .gone, // collapses to a zero-size point
      child: DemoBox('B'),
    ),
    Constrained(
      id: #c,
      // 12 past B normally; 40 past its collapsed point when B is gone.
      start: .endOf(#b, margin: 12, goneMargin: 40),
      top: .topOf(#a),
      child: DemoBox('C'),
    ),
  ],
)''',
    builder: (context) => ConstraintLayout(
      children: [
        Constrained(
          id: #a,
          start: .startOf(parent, margin: 16),
          top: .topOf(parent, margin: 16),
          child: const DemoBox('A'),
        ),
        Constrained(
          id: #b,
          start: .endOf(#a, margin: 12),
          top: .topOf(#a),
          visibility: .gone,
          child: const DemoBox('B'),
        ),
        Constrained(
          id: #c,
          start: .endOf(#b, margin: 12, goneMargin: 40),
          top: .topOf(#a),
          child: const DemoBox('C'),
        ),
      ],
    ),
  ),

  'flow': LiveExample(
    previewHeight: 220,
    caption:
        'ConstraintFlow lays its referenced siblings out in a chain and wraps '
        'to new rows when it runs out of width, the constraint-based answer to '
        'Wrap.',
    code: r'''
const labels = [
  'constraint', 'layout', 'wraps', 'when', 'it',
  'runs', 'out', 'of', 'room',
];

ConstraintLayout(
  children: [
    for (final (i, label) in labels.indexed)
      Constrained(id: Symbol('c$i'), child: DemoBox(label)),
    ConstraintFlow(
      id: #flow,
      referenced: [for (var i = 0; i < labels.length; i++) Symbol('c$i')],
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
  ],
)''',
    builder: (context) {
      const labels = [
        'constraint',
        'layout',
        'wraps',
        'when',
        'it',
        'runs',
        'out',
        'of',
        'room',
      ];
      return ConstraintLayout(
        children: [
          for (final (i, label) in labels.indexed)
            Constrained(id: Symbol('c$i'), child: DemoBox(label)),
          ConstraintFlow(
            id: #flow,
            referenced: [
              for (var i = 0; i < labels.length; i++) Symbol('c$i'),
            ],
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
        ],
      );
    },
  ),

  'grid': LiveExample(
    previewHeight: 240,
    caption:
        'ConstraintGrid places its referenced siblings into rows and columns. '
        "Spans use Android's index:RxC syntax, so cell 0 spans two columns.",
    code: r'''
ConstraintLayout(
  children: [
    for (var i = 0; i < 5; i++)
      Constrained(
        id: Symbol('t$i'),
        width: .matchConstraint,
        height: .matchConstraint,
        child: DemoBox('${i + 1}'),
      ),
    ConstraintGrid(
      id: #grid,
      referenced: [for (var i = 0; i < 5; i++) Symbol('t$i')],
      rows: 2,
      columns: 3,
      spans: '0:1x2', // cell 0 spans two columns
      horizontalGap: 8,
      verticalGap: 8,
      start: .startOf(parent, margin: 12),
      end: .endOf(parent, margin: 12),
      top: .topOf(parent, margin: 12),
      bottom: .bottomOf(parent, margin: 12),
    ),
  ],
)''',
    builder: (context) => ConstraintLayout(
      children: [
        for (var i = 0; i < 5; i++)
          Constrained(
            id: Symbol('t$i'),
            width: .matchConstraint,
            height: .matchConstraint,
            child: DemoBox('${i + 1}'),
          ),
        ConstraintGrid(
          id: #grid,
          referenced: [for (var i = 0; i < 5; i++) Symbol('t$i')],
          rows: 2,
          columns: 3,
          spans: '0:1x2',
          horizontalGap: 8,
          verticalGap: 8,
          start: .startOf(parent, margin: 12),
          end: .endOf(parent, margin: 12),
          top: .topOf(parent, margin: 12),
          bottom: .bottomOf(parent, margin: 12),
        ),
      ],
    ),
  ),

  'profile-card': LiveExample(
    previewHeight: 220,
    filename: 'profile_card.dart',
    caption:
        'Avatar, name, and handle across the top; a barrier below the taller of '
        'them; the bio spans the full width beneath. One flat layer, no nesting.',
    code: r'''
ConstraintLayout(
  children: [
    Constrained(
      id: #avatar,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent, margin: 16),
      width: .fixed(56),
      height: .fixed(56),
      child: DemoBox('IMG'),
    ),
    Constrained(
      id: #name,
      start: .endOf(#avatar, margin: 12),
      end: .endOf(parent, margin: 16),
      top: .topOf(#avatar),
      width: .matchConstraint,
      height: .fixed(24),
      child: DemoBox('Ada Lovelace'),
    ),
    Constrained(
      id: #handle,
      start: .startOf(#name),
      top: .bottomOf(#name, margin: 6),
      height: .fixed(20),
      child: DemoBox('@ada'),
    ),
    Barrier(id: #headerEnd, edge: .bottom, referenced: [#avatar, #handle]),
    Constrained(
      id: #bio,
      start: .startOf(parent, margin: 16),
      end: .endOf(parent, margin: 16),
      top: .bottomOf(#headerEnd, margin: 16),
      width: .matchConstraint,
      height: .fixed(48),
      child: DemoBox('Enchantress of numbers'),
    ),
  ],
)''',
    builder: (context) => ConstraintLayout(
      children: [
        Constrained(
          id: #avatar,
          start: .startOf(parent, margin: 16),
          top: .topOf(parent, margin: 16),
          width: .fixed(56),
          height: .fixed(56),
          child: const DemoBox('IMG'),
        ),
        Constrained(
          id: #name,
          start: .endOf(#avatar, margin: 12),
          end: .endOf(parent, margin: 16),
          top: .topOf(#avatar),
          width: .matchConstraint,
          height: .fixed(24),
          child: const DemoBox('Ada Lovelace'),
        ),
        Constrained(
          id: #handle,
          start: .startOf(#name),
          top: .bottomOf(#name, margin: 6),
          height: .fixed(20),
          child: const DemoBox('@ada'),
        ),
        const Barrier(
          id: #headerEnd,
          edge: .bottom,
          referenced: [#avatar, #handle],
        ),
        Constrained(
          id: #bio,
          start: .startOf(parent, margin: 16),
          end: .endOf(parent, margin: 16),
          top: .bottomOf(#headerEnd, margin: 16),
          width: .matchConstraint,
          height: .fixed(48),
          child: const DemoBox('Enchantress of numbers'),
        ),
      ],
    ),
  ),
};
