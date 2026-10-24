import 'package:flutter_constraint_layout/flutter_constraint_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../highlight/highlighter_service.dart';
import '../theme/tokens.dart';
import 'code_block.dart';

/// A docs example shown as source code beside the widget it renders: the exact
/// `ConstraintLayout` from the snippet, running live in a preview pane.
///
/// On a wide viewport the two sit side by side (code on the left, preview on the
/// right) and share one height, so their cards line up top and bottom. When
/// space is tight they stack with the preview on top, so the reader sees the
/// result first and the code that produced it right below.
///
/// The [code] string is what's displayed and copyable; [builder] returns the
/// equivalent live widget. Keeping them in one call site is what makes the two
/// halves stay in sync as examples evolve.
class LiveExample extends StatelessWidget {
  const LiveExample({
    super.key,
    required this.code,
    required this.builder,
    this.filename = 'main.dart',
    this.previewHeight = 260,
    this.previewPadding = const EdgeInsets.all(16),
    this.caption,
    this.maxHeight,
    this.debugToggles = false,
  });

  /// Dart source shown in the code card (and copied by the copy button).
  final String code;

  /// Builds the live widget that [code] describes.
  final WidgetBuilder builder;

  /// File name shown in the code card header.
  final String filename;

  /// Height of the preview when it stands alone (the stacked, compact layout).
  /// Side by side, the preview instead matches the code card's height.
  final double previewHeight;

  /// Inner padding between the pane frame and the rendered layout.
  final EdgeInsets previewPadding;

  /// Optional one-line note rendered beneath the example.
  final String? caption;

  /// Optional cap on the side-by-side pair's height. When set (wide layout
  /// only), the code card scrolls internally past this height instead of
  /// growing, and the preview matches it. Null lets the pair grow to fit.
  final double? maxHeight;

  /// Whether the preview shows the "chains" and "blueprint" debug toggles in
  /// its header, letting the reader overlay the constraint design surface on
  /// the live layout. Used on the home page only.
  final bool debugToggles;

  /// A copy of this example capped to [height] tall in the side-by-side layout,
  /// and with the debug toggles turned on. Lets a shared example (used in the
  /// docs at full height, no toggles) become the home-page variant without
  /// duplicating its code and builder.
  LiveExample capped(double height) => LiveExample(
    code: code,
    builder: builder,
    filename: filename,
    previewHeight: previewHeight,
    previewPadding: previewPadding,
    caption: caption,
    maxHeight: height,
    debugToggles: true,
  );

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    // Capping only applies to the wide, side-by-side layout, where the preview
    // is forced to match the code card's height. Compact stacks, so a long
    // snippet just scrolls the page instead.
    final capHeight = !compact ? maxHeight : null;

    // Side by side, drop the card's bottom margin so the two cards share edges.
    final code = CodeBlock(
      code: this.code,
      lang: 'dart',
      filename: filename,
      showDividers: false,
      fillHeight: capHeight != null,
      margin: compact ? const EdgeInsets.only(bottom: 12) : EdgeInsets.zero,
    );

    Widget row = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PreviewPane(
                builder: builder,
                padding: previewPadding,
                fixedHeight: previewHeight,
                debugToggles: debugToggles,
              ),
              const SizedBox(height: 12),
              code,
            ],
          )
        // IntrinsicHeight lets the code card set the height and the preview
        // stretch to match it, so both cards are exactly the same height.
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 55, child: code),
                const SizedBox(width: 16),
                Expanded(
                  flex: 45,
                  child: _PreviewPane(
                    builder: builder,
                    padding: previewPadding,
                    debugToggles: debugToggles,
                  ),
                ),
              ],
            ),
          );

    if (capHeight != null) {
      // Cap the pair: IntrinsicHeight reports the code's full natural height, so
      // this ConstrainedBox clamps it (and the preview) only when it overflows.
      row = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: capHeight),
        child: row,
      );
    }

    if (caption == null) return row;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        const SizedBox(height: 10),
        Text(
          caption!,
          style: TextStyle(
            fontFamily: AppFonts.sans,
            fontSize: 13.5,
            height: 1.5,
            color: context.colors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

/// The preview column: a small "preview" header (mirroring the code card's file
/// header) above the rendered layout, on the very same card surface, border, and
/// radius as the code block it sits beside.
///
/// With [fixedHeight] the pane is that tall (the stacked, compact layout); with
/// it null the rendered body is [Expanded] so the pane fills whatever height its
/// parent gives it (the side-by-side layout, where an [IntrinsicHeight] makes
/// that the code card's height).
class _PreviewPane extends StatefulWidget {
  const _PreviewPane({
    required this.builder,
    required this.padding,
    this.fixedHeight,
    this.debugToggles = false,
  });

  final WidgetBuilder builder;
  final EdgeInsets padding;
  final double? fixedHeight;

  /// Whether the header shows the chains/blueprint debug toggles.
  final bool debugToggles;

  @override
  State<_PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<_PreviewPane> {
  bool _showChains = false;
  bool _showBlueprint = false;

  /// Rebuilds the example's root `ConstraintLayout` with the currently toggled
  /// debug flags, copying its children and other props over. The example
  /// builders construct a plain `ConstraintLayout`, so this is how the toggles
  /// reach it without every builder having to thread the flags through. A root
  /// that is not a `ConstraintLayout` is returned untouched.
  ///
  /// Outside a debug build the blueprint draws no labels. A label names the
  /// child by its `Symbol` id and widget type, which only a debug build reports
  /// faithfully: the release web build minifies type names, and dart2wasm
  /// Symbol-literal ids too, so a label would read like `minified:Class497`.
  Widget _applyDebug(Widget rendered) {
    if (!_showChains && !_showBlueprint) return rendered;
    if (rendered is ConstraintLayout) {
      return ConstraintLayout(
        key: rendered.key,
        textDirection: rendered.textDirection,
        debugShowChains: _showChains,
        debugShowBlueprint: _showBlueprint,
        debugChainColor: rendered.debugChainColor,
        debugBlueprintLabelStyle: kDebugMode
            ? rendered.debugBlueprintLabelStyle
            : DebugLabelStyle.none,
        children: rendered.children,
      );
    }
    return rendered;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brand = context.brand;
    final isDark = Theme.brightnessOf(context) == .dark;

    // Match the code block exactly: the same Pierre-theme background, the same
    // onBg-derived hairline border, and the same corner radius.
    final bg = HighlighterService.instance.defaultBackground(
      isDark: isDark,
      fallback: colors.surface,
    );
    final onBg = bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    final border = onBg.withValues(alpha: 0.10);

    final render = PreviewStage(
      padding: widget.padding,
      child: _applyDebug(widget.builder(context)),
    );
    final body = widget.fixedHeight != null
        ? SizedBox(height: widget.fixedHeight, child: render)
        : Expanded(child: render);

    // No divider under the header: the dotted grid of the stage reads as the
    // boundary between the label and the rendered layout.
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PreviewHeader(
          onBg: onBg,
          dot: brand.azure,
          accent: brand.azure,
          showToggles: widget.debugToggles,
          showChains: _showChains,
          showBlueprint: _showBlueprint,
          onToggleChains: () => setState(() => _showChains = !_showChains),
          onToggleBlueprint: () =>
              setState(() => _showBlueprint = !_showBlueprint),
        ),
        body,
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: border),
      ),
      // No outer clip (it would trim the border); clip the inner content to the
      // inner radius so the rendered layout stays inside the rounded corners.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg - 1),
        child: content,
      ),
    );
  }
}

/// The preview card's header row, laid out to the same height as the code
/// card's file header: an accent dot in place of the file glyph, then a mono
/// `preview` label. On the home page it also carries the chains/blueprint debug
/// toggles on the right.
class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({
    required this.onBg,
    required this.dot,
    required this.accent,
    this.showToggles = false,
    this.showChains = false,
    this.showBlueprint = false,
    this.onToggleChains,
    this.onToggleBlueprint,
  });

  final Color onBg;
  final Color dot;
  final Color accent;
  final bool showToggles;
  final bool showChains;
  final bool showBlueprint;
  final VoidCallback? onToggleChains;
  final VoidCallback? onToggleBlueprint;

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: Padding(
        // Matches the code header's padding + min-height, so the two headers
        // line up across the pair. The right pad tightens when toggles show, so
        // their border sits about as far in as the copy glyph opposite.
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
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
              // Expanded so the label, not the row, gives way on a narrow
              // pane: it ellipsizes before the toggles overflow.
              Expanded(
                child: Text(
                  'preview',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    height: 1.0,
                    color: onBg.withValues(alpha: 0.85),
                  ),
                ),
              ),
              if (showToggles) ...[
                _DebugToggle(
                  label: 'chains',
                  icon: Icons.polyline,
                  active: showChains,
                  onBg: onBg,
                  accent: accent,
                  onTap: onToggleChains!,
                ),
                const SizedBox(width: 6),
                _DebugToggle(
                  label: 'blueprint',
                  icon: Icons.architecture,
                  active: showBlueprint,
                  onBg: onBg,
                  accent: accent,
                  onTap: onToggleBlueprint!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A small toggle chip in a preview header, styled for the code-theme surface
/// (its colors derive from [onBg] and the brand [accent]). Active means the
/// matching `ConstraintLayout` debug flag is on.
class _DebugToggle extends StatelessWidget {
  const _DebugToggle({
    required this.label,
    required this.icon,
    required this.active,
    required this.onBg,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color onBg;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? onBg : onBg.withValues(alpha: 0.5);
    final bgColor = active ? accent.withValues(alpha: 0.20) : Colors.transparent;
    final borderColor = active
        ? accent.withValues(alpha: 0.55)
        : onBg.withValues(alpha: 0.16);
    return Semantics(
      button: true,
      toggled: active,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: active ? accent : fg),
                const SizedBox(width: 5),
                // The Semantics above already carries the label; excluding the
                // visible text keeps screen readers from announcing it twice.
                ExcludeSemantics(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11.5,
                      height: 1.0,
                      color: fg,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The framed surface every live preview renders on: a dotted "grid paper"
/// canvas with the layout laid over a very faded `#212121` panel, its bounds
/// marked by thin red corner and edge handles so the reader can see exactly
/// where the `ConstraintLayout` box begins and ends.
///
/// Exposed (not private) so the interactive demos render on the very same stage
/// as the static examples.
class PreviewStage extends StatelessWidget {
  const PreviewStage({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  /// The layout to render inside the bounds frame (usually a `ConstraintLayout`,
  /// which fills the framed area).
  final Widget child;

  /// Inset between the grid canvas and the bounds frame.
  final EdgeInsets padding;

  /// The bounds handles: iOS system red, thin.
  static const Color _handle = Color(0xFFFF453A);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.brightnessOf(context) == .dark;
    // The dot color is a faint tint of the foreground so the grid reads on
    // either theme without drawing the eye off the layout.
    final onBg = isDark ? Colors.white : Colors.black;
    final dotColor = onBg.withValues(alpha: 0.07);
    // A very faded #212121 panel marks the layout's box against the canvas:
    // just visible on the dark code theme, a hair of grey on a light one.
    final boundsFill = isDark
        ? const Color(0xFF212121).withValues(alpha: 0.38)
        : const Color(0xFF212121).withValues(alpha: 0.04);

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _DotGridPainter(dotColor)),
        Padding(
          padding: padding,
          child: DecoratedBox(
            decoration: BoxDecoration(color: boundsFill),
            child: CustomPaint(
              foregroundPainter: const _BoundsHandlePainter(_handle),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

/// Paints the faint dotted grid paper behind a preview: a 1px dot every 16px.
class _DotGridPainter extends CustomPainter {
  const _DotGridPainter(this.color);

  final Color color;

  static const double _step = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = _step / 2; y < size.height; y += _step) {
      for (double x = _step / 2; x < size.width; x += _step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Paints the bounds handles over a preview's layout box: a thin L-bracket at
/// each corner and a short tick at the midpoint of each edge, so the extent of
/// the `ConstraintLayout` is legible like a selection in a design tool.
class _BoundsHandlePainter extends CustomPainter {
  const _BoundsHandlePainter(this.color);

  final Color color;

  /// Corner bracket arm length and edge tick length.
  static const double _arm = 10;
  static const double _tick = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    // Four corner L-brackets.
    canvas.drawPath(
      Path()
        ..moveTo(0, _arm)
        ..lineTo(0, 0)
        ..lineTo(_arm, 0),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w - _arm, 0)
        ..lineTo(w, 0)
        ..lineTo(w, _arm),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w, h - _arm)
        ..lineTo(w, h)
        ..lineTo(w - _arm, h),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(_arm, h)
        ..lineTo(0, h)
        ..lineTo(0, h - _arm),
      paint,
    );

    // Four edge-midpoint ticks, each a short bar centered on its edge.
    final cx = w / 2;
    final cy = h / 2;
    canvas.drawLine(Offset(cx - _tick / 2, 0), Offset(cx + _tick / 2, 0), paint);
    canvas.drawLine(Offset(cx - _tick / 2, h), Offset(cx + _tick / 2, h), paint);
    canvas.drawLine(Offset(0, cy - _tick / 2), Offset(0, cy + _tick / 2), paint);
    canvas.drawLine(Offset(w, cy - _tick / 2), Offset(w, cy + _tick / 2), paint);
  }

  @override
  bool shouldRepaint(_BoundsHandlePainter oldDelegate) =>
      oldDelegate.color != color;
}
