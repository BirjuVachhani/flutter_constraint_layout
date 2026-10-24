import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/material.dart';

import '../highlight/highlighter_service.dart';
import '../theme/tokens.dart';
import 'code_block.dart';
import 'live_example.dart';
import 'pill.dart';
import 'preview.dart';

/// An interactive companion to the static visibility example: a segmented
/// control that flips one child between `visible`, `invisible`, and `gone` so
/// the reader can watch the layout reflow, and see how `goneMargin` closes the
/// gap. Because visibility is just a property, the whole change is one
/// `setState`, no rebuild of the layout itself.
///
/// It renders on the same [PreviewStage] as the static examples, so the dotted
/// canvas and red bounds handles match the rest of the page.
///
/// With [sideBySide] it lays the code and preview out like a [LiveExample]
/// (code left, preview right on a wide viewport; stacked on a compact one),
/// with the pills below the pair, so it lines up with the home page's other
/// sections. Left off (the default), the preview sits above the pills with the
/// code below, the layout the docs use.
class VisibilityToggleDemo extends StatefulWidget {
  const VisibilityToggleDemo({
    super.key,
    this.height = 200,
    this.sideBySide = false,
    this.maxHeight,
  });

  /// Height of the preview stage when it stands alone: the docs layout, and the
  /// compact stacked side-by-side layout. Side by side on a wide viewport it
  /// instead matches the code card's height.
  final double height;

  /// Whether to lay the code and preview out side by side (see the class doc).
  final bool sideBySide;

  /// Optional cap on the side-by-side pair's height (wide layout only), like
  /// [LiveExample.maxHeight]: past it the code card scrolls internally and the
  /// preview matches. Ignored when [sideBySide] is false.
  final double? maxHeight;

  @override
  State<VisibilityToggleDemo> createState() => _VisibilityToggleDemoState();
}

class _VisibilityToggleDemoState extends State<VisibilityToggleDemo> {
  // Start gone so the first thing the reader does (flip to visible) makes B
  // appear and push C over, the clearest demonstration of the effect.
  ConstraintVisibility _visibility = ConstraintVisibility.gone;

  static const _options = <(String, ConstraintVisibility)>[
    ('visible', ConstraintVisibility.visible),
    ('invisible', ConstraintVisibility.invisible),
    ('gone', ConstraintVisibility.gone),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brand = context.brand;
    final isDark = Theme.brightnessOf(context) == .dark;

    // Match the code/preview cards: same theme background, border, and radius.
    final bg = HighlighterService.instance.defaultBackground(
      isDark: isDark,
      fallback: colors.surface,
    );
    final onBg = bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    final border = onBg.withValues(alpha: 0.10);

    // The segmented control that drives B's visibility, shared by both layouts.
    final pills = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            "B's visibility:",
            style: TextStyle(
              color: colors.mutedForeground,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        for (final (label, value) in _options)
          SelectPill(
            label: label,
            selected: _visibility == value,
            onTap: () => setState(() => _visibility = value),
          ),
      ],
    );

    // The source for exactly the selection above: the `visibility:` line tracks
    // the pills, so the reader can map the control to the code.
    final codeText = _codeFor(_visibility);

    // Docs layout: the preview card, the pills, then the code beneath them.
    if (!widget.sideBySide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _previewCard(
              bg: bg, border: border, onBg: onBg, dot: brand.azure, fill: false),
          const SizedBox(height: 14),
          pills,
          const SizedBox(height: 16),
          CodeBlock(
            code: codeText,
            lang: 'dart',
            filename: 'visibility.dart',
            margin: EdgeInsets.zero,
          ),
        ],
      );
    }

    // Home layout: code and preview side by side (code left, preview right) on a
    // wide viewport, stacked on a compact one, mirroring the LiveExample
    // sections. The pills sit below the pair.
    final compact = context.isCompact;
    // Capping applies only to the wide, side-by-side layout, where the preview
    // is forced to match the code card's height.
    final capHeight = !compact ? widget.maxHeight : null;
    final code = CodeBlock(
      code: codeText,
      lang: 'dart',
      filename: 'visibility.dart',
      showDividers: false,
      fillHeight: capHeight != null,
      margin: compact ? const EdgeInsets.only(bottom: 12) : EdgeInsets.zero,
    );

    Widget row = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _previewCard(
                  bg: bg,
                  border: border,
                  onBg: onBg,
                  dot: brand.azure,
                  fill: false),
              const SizedBox(height: 12),
              code,
            ],
          )
        // IntrinsicHeight lets the code card set the height and the preview
        // stretch to match, so both cards are exactly the same height.
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 55, child: code),
                const SizedBox(width: 16),
                Expanded(
                  flex: 45,
                  child: _previewCard(
                      bg: bg,
                      border: border,
                      onBg: onBg,
                      dot: brand.azure,
                      fill: true),
                ),
              ],
            ),
          );

    if (capHeight != null) {
      row = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: capHeight),
        child: row,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        const SizedBox(height: 14),
        pills,
      ],
    );
  }

  /// The preview card: the mono `visibility` header above the live layout on a
  /// [PreviewStage], on the same surface as the code card beside it. With [fill]
  /// the stage expands to the card's height (the side-by-side layout); otherwise
  /// it is [VisibilityToggleDemo.height] tall (the docs and compact layouts).
  Widget _previewCard({
    required Color bg,
    required Color border,
    required Color onBg,
    required Color dot,
    required bool fill,
  }) {
    final stage = PreviewStage(child: _layout());
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg - 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(onBg, dot),
            if (fill)
              Expanded(child: stage)
            else
              SizedBox(height: widget.height, child: stage),
          ],
        ),
      ),
    );
  }

  /// The layout's source with `B`'s `visibility` set to the current [v], kept
  /// in step with [_layout] so the code always matches what the preview shows.
  String _codeFor(ConstraintVisibility v) {
    return '''
ConstraintLayout(
  children: [
    Constrained(
      id: #a,
      start: .startOf(parent, margin: 16),
      top: .topOf(parent),
      bottom: .bottomOf(parent),
      child: const DemoBox('A'),
    ),
    Constrained(
      id: #b,
      start: .endOf(#a, margin: 12),
      top: .topOf(#a),
      bottom: .bottomOf(#a),
      visibility: ConstraintVisibility.${v.name},
      child: const DemoBox('B'),
    ),
    Constrained(
      id: #c,
      // 40px gone-margin closes the gap when B collapses.
      start: .endOf(#b, margin: 12, goneMargin: 40),
      top: .topOf(#a),
      bottom: .bottomOf(#a),
      child: const DemoBox('C'),
    ),
  ],
)''';
  }

  /// The mono `visibility` label header, mirroring the live examples' preview
  /// header so this card sits flush with them.
  Widget _header(Color onBg, Color dot) {
    return SelectionContainer.disabled(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 28),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                'visibility',
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                  height: 1.0,
                  color: onBg.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A, B, C in a row, where B's visibility is state-driven and C keeps a
  /// larger `goneMargin` so it closes the gap when B collapses.
  Widget _layout() {
    return ConstraintLayout(
      children: [
        Constrained(
          id: #a,
          start: .startOf(parent, margin: 16),
          top: .topOf(parent),
          bottom: .bottomOf(parent),
          child: const DemoBox('A'),
        ),
        Constrained(
          id: #b,
          start: .endOf(#a, margin: 12),
          top: .topOf(#a),
          bottom: .bottomOf(#a),
          visibility: _visibility,
          child: const DemoBox('B'),
        ),
        Constrained(
          id: #c,
          // 12 past B normally; 40 past its collapsed point when B is gone.
          start: .endOf(#b, margin: 12, goneMargin: 40),
          top: .topOf(#a),
          bottom: .bottomOf(#a),
          child: const DemoBox('C'),
        ),
      ],
    );
  }
}
