import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/material.dart';

import '../widgets/live_example.dart';

/// Real UI that is genuinely awkward or impossible to build with plain `Row`,
/// `Column`, and `Stack`, so it earns the constraint model.
///
/// The teaching examples in `examples.dart` use `DemoBox` placeholders so the
/// eye stays on the constraints. These render real widgets, but each one leans
/// on something no single Flutter layout widget offers out of the box: a value
/// column that aligns to the *widest* label via a `Barrier`, actions placed on
/// a circle by angle and radius, an avatar centered on the seam between two
/// regions, and two panes that share one `Guideline` with a handle sitting on
/// it. Each is one flat layer of anchored siblings, with no `Row` / `Column` /
/// `Stack` nesting.
///
/// Each example's prose lives above it on the page (see the home real-world
/// section), so these carry no `caption`.
///
/// Keyed by a short id, shown on the home page's real-world section.
final Map<String, LiveExample> realWorldExamples = {
  // A label/value panel whose value column starts just past the *longest*
  // label. A Barrier tracks the widest of the four labels, so the values stay
  // aligned no matter which label is renamed. No Row or Column measures its
  // widest sibling for you; this is the constraint-native way to do it.
  'aligned-form': LiveExample(
    filename: 'summary_panel.dart',
    previewHeight: 260,
    previewPadding: const EdgeInsets.all(24),
    maxHeight: 400,
    debugToggles: true,
    code: r'''
final cs = Theme.of(context).colorScheme;

TextStyle label = TextStyle(fontSize: 14, color: cs.onSurfaceVariant);
TextStyle value = TextStyle(
  fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface);

ConstraintLayout(
  children: [
    // Four labels of different widths, stacked down the start edge.
    Constrained(
      id: #l1, start: .startOf(parent), top: .topOf(parent),
      child: Text('Plan', style: label)),
    Constrained(
      id: #l2, start: .startOf(parent), top: .bottomOf(#l1, margin: 18),
      child: Text('Billing cycle', style: label)),
    Constrained(
      id: #l3, start: .startOf(parent), top: .bottomOf(#l2, margin: 18),
      child: Text('Seats', style: label)),
    Constrained(
      id: #l4, start: .startOf(parent), top: .bottomOf(#l3, margin: 18),
      child: Text('Renews on', style: label)),

    // One line at the end of whichever label is widest.
    Barrier(id: #gutter, edge: .end, referenced: [#l1, #l2, #l3, #l4],
      margin: 24),

    // Every value begins at that line and shares its label's baseline.
    Constrained(
      id: #v1, start: .startOf(#gutter), baseline: .baselineOf(#l1),
      child: Text('Team', style: value)),
    Constrained(
      id: #v2, start: .startOf(#gutter), baseline: .baselineOf(#l2),
      child: Text('Monthly', style: value)),
    Constrained(
      id: #v3, start: .startOf(#gutter), baseline: .baselineOf(#l3),
      child: Text('12 of 20 used', style: value)),
    Constrained(
      id: #v4, start: .startOf(#gutter), baseline: .baselineOf(#l4),
      child: Text('Aug 1, 2026', style: value)),
  ],
)''',
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      final label = TextStyle(fontSize: 14, color: cs.onSurfaceVariant);
      final value = TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      );
      return ConstraintLayout(
        children: [
          Constrained(
            id: #l1,
            start: .startOf(parent),
            top: .topOf(parent),
            child: Text('Plan', style: label),
          ),
          Constrained(
            id: #l2,
            start: .startOf(parent),
            top: .bottomOf(#l1, margin: 18),
            child: Text('Billing cycle', style: label),
          ),
          Constrained(
            id: #l3,
            start: .startOf(parent),
            top: .bottomOf(#l2, margin: 18),
            child: Text('Seats', style: label),
          ),
          Constrained(
            id: #l4,
            start: .startOf(parent),
            top: .bottomOf(#l3, margin: 18),
            child: Text('Renews on', style: label),
          ),
          const Barrier(
            id: #gutter,
            edge: .end,
            referenced: [#l1, #l2, #l3, #l4],
            margin: 24,
          ),
          Constrained(
            id: #v1,
            start: .startOf(#gutter),
            baseline: .baselineOf(#l1),
            child: Text('Team', style: value),
          ),
          Constrained(
            id: #v2,
            start: .startOf(#gutter),
            baseline: .baselineOf(#l2),
            child: Text('Monthly', style: value),
          ),
          Constrained(
            id: #v3,
            start: .startOf(#gutter),
            baseline: .baselineOf(#l3),
            child: Text('12 of 20 used', style: value),
          ),
          Constrained(
            id: #v4,
            start: .startOf(#gutter),
            baseline: .baselineOf(#l4),
            child: Text('Aug 1, 2026', style: value),
          ),
        ],
      );
    },
  ),

  // A radial action menu: each action sits at an angle and radius around a
  // center hub. Nothing in Flutter positions children on a circle; it takes
  // the constraint engine's trigonometry (the `circle` link).
  'radial-menu': LiveExample(
    filename: 'radial_menu.dart',
    previewHeight: 300,
    previewPadding: const EdgeInsets.all(16),
    maxHeight: 400,
    debugToggles: true,
    code: r'''
final cs = Theme.of(context).colorScheme;
const actions = [
  Icons.ios_share, Icons.favorite_border, Icons.bookmark_border,
  Icons.link_rounded, Icons.more_horiz,
];

Widget satellite(IconData icon) => Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
    );

ConstraintLayout(
  children: [
    // The hub, centered in the layout.
    Constrained(
      id: #hub,
      start: .startOf(parent), end: .endOf(parent),
      top: .topOf(parent), bottom: .bottomOf(parent),
      width: .fixed(60), height: .fixed(60),
      child: DecoratedBox(
        decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
        child: Icon(Icons.add, color: cs.onPrimary),
      ),
    ),
    // Each action, 72 apart, on a 96px circle around the hub.
    for (final (i, icon) in actions.indexed)
      Constrained(
        id: Symbol('a$i'),
        width: .fixed(44), height: .fixed(44),
        circle: .around(#hub, angle: i * 72.0, radius: 96),
        child: satellite(icon),
      ),
  ],
)''',
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      const actions = [
        Icons.ios_share,
        Icons.favorite_border,
        Icons.bookmark_border,
        Icons.link_rounded,
        Icons.more_horiz,
      ];
      Widget satellite(IconData icon) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          shape: BoxShape.circle,
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
      );
      return ConstraintLayout(
        children: [
          Constrained(
            id: #hub,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
            width: .fixed(60),
            height: .fixed(60),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add, color: cs.onPrimary),
            ),
          ),
          for (final (i, icon) in actions.indexed)
            Constrained(
              id: Symbol('a$i'),
              width: .fixed(44),
              height: .fixed(44),
              circle: .around(#hub, angle: i * 72.0, radius: 96),
              child: satellite(icon),
            ),
        ],
      );
    },
  ),

  // A profile header whose avatar straddles the seam between the cover band and
  // the body. The avatar pins both its top and bottom to the cover's bottom
  // edge, centering it on that line so it overlaps both regions. In plain
  // Flutter this is a Stack with a Positioned avatar nudged by a manual offset.
  'overlap-seam': LiveExample(
    filename: 'profile_header.dart',
    previewHeight: 280,
    previewPadding: const EdgeInsets.all(20),
    maxHeight: 400,
    debugToggles: true,
    code: r'''
final cs = Theme.of(context).colorScheme;

// A ring so the avatar reads cleanly over the seam.
Widget avatar() => Container(
      decoration: BoxDecoration(
        color: cs.primary,
        shape: BoxShape.circle,
        border: Border.all(color: cs.surface, width: 3),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.person, color: cs.onPrimary, size: 34),
    );

ConstraintLayout(
  children: [
    // A cover band filling the width across the top.
    Constrained(
      id: #cover,
      start: .startOf(parent), end: .endOf(parent), top: .topOf(parent),
      width: .matchConstraint, height: .fixed(96),
      child: DecoratedBox(
        decoration: BoxDecoration(color: cs.primaryContainer),
      ),
    ),
    // The avatar: top and bottom both pinned to the cover's bottom edge, so its
    // center lands on the seam and it straddles the band and the body.
    Constrained(
      id: #avatar,
      start: .startOf(parent), end: .endOf(parent),
      top: .bottomOf(#cover), bottom: .bottomOf(#cover),
      width: .fixed(72), height: .fixed(72),
      child: avatar(),
    ),
    // Name and handle, centered under the avatar.
    Constrained(
      id: #name,
      start: .startOf(parent), end: .endOf(parent),
      top: .bottomOf(#avatar, margin: 14),
      child: Text('Ada Lovelace',
        style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface)),
    ),
    Constrained(
      id: #handle,
      start: .startOf(parent), end: .endOf(parent),
      top: .bottomOf(#name, margin: 2),
      child: Text('@ada',
        style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
    ),
  ],
)''',
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      Widget avatar() => Container(
        decoration: BoxDecoration(
          color: cs.primary,
          shape: BoxShape.circle,
          border: Border.all(color: cs.surface, width: 3),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.person, color: cs.onPrimary, size: 34),
      );
      return ConstraintLayout(
        children: [
          Constrained(
            id: #cover,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .topOf(parent),
            width: .matchConstraint,
            height: .fixed(96),
            child: DecoratedBox(
              decoration: BoxDecoration(color: cs.primaryContainer),
            ),
          ),
          Constrained(
            id: #avatar,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .bottomOf(#cover),
            bottom: .bottomOf(#cover),
            width: .fixed(72),
            height: .fixed(72),
            child: avatar(),
          ),
          Constrained(
            id: #name,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .bottomOf(#avatar, margin: 14),
            child: Text(
              'Ada Lovelace',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          Constrained(
            id: #handle,
            start: .startOf(parent),
            end: .endOf(parent),
            top: .bottomOf(#name, margin: 2),
            child: Text(
              '@ada',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
    },
  ),

  // A before / after comparison split by one Guideline. Both panes fill up to
  // the line, and the handle centers on it, straddling the seam. Move the
  // guideline and all three follow it. In plain Flutter the handle is a
  // Positioned child whose offset must be recomputed from the container width.
  'guideline-split': LiveExample(
    filename: 'comparison.dart',
    previewHeight: 260,
    previewPadding: const EdgeInsets.all(16),
    maxHeight: 400,
    debugToggles: true,
    code: r'''
final cs = Theme.of(context).colorScheme;

Widget pane(Color bg, String label, Color fg, Alignment at) => ColoredBox(
      color: bg,
      child: Align(
        alignment: at,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(label,
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
        ),
      ),
    );

ConstraintLayout(
  children: [
    // One line at 55% of the width that both panes and the handle share.
    Guideline.vertical(id: #split, percent: 0.55),

    // "Before" fills from the start edge to the line.
    Constrained(
      id: #before,
      start: .startOf(parent), end: .leftOf(#split),
      top: .topOf(parent), bottom: .bottomOf(parent),
      width: .matchConstraint, height: .matchConstraint,
      child: pane(cs.surfaceContainerHighest, 'Before',
        cs.onSurfaceVariant, Alignment.topLeft),
    ),
    // "After" fills from the line to the end edge.
    Constrained(
      id: #after,
      start: .rightOf(#split), end: .endOf(parent),
      top: .topOf(parent), bottom: .bottomOf(parent),
      width: .matchConstraint, height: .matchConstraint,
      child: pane(cs.primaryContainer, 'After',
        cs.onPrimaryContainer, Alignment.topRight),
    ),
    // The handle: both edges anchor to the line, so it centers on the seam.
    Constrained(
      id: #knob,
      left: .leftOf(#split), right: .rightOf(#split),
      top: .topOf(parent), bottom: .bottomOf(parent),
      width: .fixed(40), height: .fixed(40),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface, shape: BoxShape.circle,
          border: Border.all(color: cs.outlineVariant),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.compare_arrows, size: 20, color: cs.onSurfaceVariant),
      ),
    ),
  ],
)''',
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      Widget pane(Color bg, String label, Color fg, Alignment at) => ColoredBox(
        color: bg,
        child: Align(
          alignment: at,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      );
      return ConstraintLayout(
        children: [
          const Guideline.vertical(id: #split, percent: 0.55),
          Constrained(
            id: #before,
            start: .startOf(parent),
            end: .leftOf(#split),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
            width: .matchConstraint,
            height: .matchConstraint,
            child: pane(
              cs.surfaceContainerHighest,
              'Before',
              cs.onSurfaceVariant,
              Alignment.topLeft,
            ),
          ),
          Constrained(
            id: #after,
            start: .rightOf(#split),
            end: .endOf(parent),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
            width: .matchConstraint,
            height: .matchConstraint,
            child: pane(
              cs.primaryContainer,
              'After',
              cs.onPrimaryContainer,
              Alignment.topRight,
            ),
          ),
          Constrained(
            id: #knob,
            left: .leftOf(#split),
            right: .rightOf(#split),
            top: .topOf(parent),
            bottom: .bottomOf(parent),
            width: .fixed(40),
            height: .fixed(40),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                shape: BoxShape.circle,
                border: Border.all(color: cs.outlineVariant),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.compare_arrows,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    },
  ),
};
