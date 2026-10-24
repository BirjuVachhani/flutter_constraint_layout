import 'package:flutter/material.dart';
import 'package:shiki_flutter/shiki_flutter.dart';

import '../highlight/highlighter_service.dart';
import '../theme/tokens.dart';
import 'app_icon.dart';
import 'copy_button.dart';

/// A rounded, bordered code card highlighted live by shiki_flutter.
///
/// When [theme] is null the block follows the site's light/dark mode. The block
/// grows to fit its content vertically (no inner vertical scroll) so it never
/// traps the page's scroll; long lines scroll horizontally.
///
/// If [filename] is given the block gains a header: a file-code
/// glyph, the file name, and the copy button on the right, separated from the
/// code by a hairline. Without a filename there is no header chrome and a subtle
/// copy button sits in the top-right instead, in a strip of its own beside the
/// code so it never covers a character.
class CodeBlock extends StatelessWidget {
  const CodeBlock({
    super.key,
    required this.code,
    required this.lang,
    this.theme,
    this.filename,
    this.showCopy = true,
    this.showLineNumbers = true,
    this.fontSize = 13,
    this.showDividers = false,
    this.fillHeight = false,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final String code;
  final String lang;

  /// The theme(s) to render with. Defaults to the site's Pierre light/dark
  /// pair ([HighlighterService.defaultTheme]), resolved against the
  /// ambient brightness by the widget.
  final ShikiThemeBase? theme;

  /// When set, renders a header bar showing this file name and a file-code
  /// icon. The copy button moves into the header instead of floating.
  final String? filename;

  final bool showCopy;

  /// Show a right-aligned line-number gutter.
  final bool showLineNumbers;

  final double fontSize;

  final bool showDividers;

  /// When true, the code body fills the card's height and scrolls internally
  /// instead of growing to fit. Used when the card is height-capped beside a
  /// live preview, so a long snippet scrolls rather than stretching the pair.
  /// Requires a bounded height from the parent (an [IntrinsicHeight] row under a
  /// max-height [ConstrainedBox], as `LiveExample` provides).
  final bool fillHeight;

  /// Outer margin around the card. Defaults to a 12px bottom gap for stacked
  /// docs blocks; pass [EdgeInsets.zero] when the card is sized to match a
  /// sibling (e.g. beside a live preview).
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final service = HighlighterService.instance;
    final isDark = Theme.brightnessOf(context) == .dark;
    final ShikiTheme theme = (this.theme ?? HighlighterService.defaultTheme)
        .resolve(isDark: isDark);
    // Resolve a concrete theme id for the background color; the widget resolves
    // the same brightness itself for the text.
    final themeId = theme.id;

    final trimmed = code.trim();
    final bg = service.displayBackground(themeId, colors.surface);
    final onBg = bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    final border = onBg.withValues(alpha: 0.10);

    // With a header the copy button lives in the header; without one it floats
    // in the top-right, beside the code rather than over it.
    final hasHeader = filename != null;
    final floatingCopy = !hasHeader && showCopy;

    // Async highlighting: the block shows the plain code first and swaps to the
    // highlighted result when tokenization finishes, with the shared
    // highlighter's token cache making later rebuilds instant. A virtualized
    // line view gives a real (non-faked) line-number gutter that stays
    // row-aligned, plus horizontal scrolling for long lines. Shrink-wrapped so
    // the block grows to fit and never traps the page's vertical scroll.
    // No wrapping SelectionArea here: `selectable: true` lets ShikiCodeView add
    // one itself only when there is no ancestor SelectionArea (its internal
    // `SelectionContainer.maybeOf` guard). The pages already provide a page-level
    // SelectionArea, so wrapping again would nest them, which breaks keyboard
    // copy (Cmd/Ctrl+C) on a manual selection.
    final body = ShikiCodeView(
      highlighter: service.highlighter,
      code: trimmed,
      lang: HighlighterService.languageForId(lang),
      theme: theme,
      selectable: true,
      textStyle: TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: fontSize,
        height: 20 / fontSize,
        fontFeatures: [.tabularFigures()],
      ),
      gutterStyle: GutterStyle(
        spacing: 15.6,
        dividerColor: showDividers ? border : null,
        textColor: onBg.withValues(alpha: 0.32),
        textScale: 0.9,
      ),
      showLineNumbers: showLineNumbers,
      paintBackground: false,
      padding: .only(
        left: 15.6,
        top: hasHeader && !showDividers ? 0 : 12,
        bottom: 12,
        // Beside a floating chip, its strip already leaves one inset of air, so
        // the code's own end padding only tops that gap up to the usual 15.6.
        right: floatingCopy ? 15.6 - _CopyChip.inset : 15.6,
      ),
    );

    final Widget content = hasHeader
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                filename: filename!,
                onBg: onBg,
                copyText: showCopy ? trimmed : null,
              ),
              if (showDividers)
                Divider(
                  height: 1,
                  color: border,
                ),
              // Height-capped beside a preview: fill the remaining card height
              // and scroll a long snippet internally rather than stretching the
              // pair. Otherwise grow to fit (no inner vertical scroll).
              if (fillHeight)
                Expanded(child: SingleChildScrollView(child: body))
              else
                body,
            ],
          )
        : Stack(
            children: [
              // The chip gets a strip of its own: the code's viewport ends an
              // inset short of the chip, so a long line scrolls up to it, never
              // under it, and its last characters stay readable at the end.
              if (floatingCopy)
                Padding(
                  padding: const EdgeInsets.only(right: _CopyChip.strip),
                  child: body,
                )
              else
                body,
              if (floatingCopy)
                Positioned(
                  top: _CopyChip.inset,
                  right: _CopyChip.inset,
                  child: _CopyChip(text: trimmed, onBg: onBg, bg: bg),
                ),
            ],
          );

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: border),
      ),
      // No outer clip (it would trim the 1px border); the inner content is
      // clipped to the inner radius instead, so rounded corners stay clean.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg - 1),
        child: content,
      ),
    );
  }
}

/// The optional header bar: a file-code glyph + file name on the left and the
/// copy button on the right, matching the reference header: the same
/// background as the code (no divider), `padding-inline: 16`, an 8px icon↔name
/// gap, and a min-height of roughly one line plus 24px.
class _Header extends StatelessWidget {
  const _Header({
    required this.filename,
    required this.onBg,
    required this.copyText,
  });

  final String filename;
  final Color onBg;

  /// Text to copy, or null to hide the button.
  final String? copyText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // padding-inline: 16 (right trimmed to 10 so the copy glyph's own 6px
      // padding lands ~16px from the edge). Vertical padding + minHeight give
      // the reference `calc(1lh + 24px)` header height.
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Row(
          children: [
            AppIcon(
              DiffIcon.fileCode,
              size: 16,
              color: onBg.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SelectionContainer.disabled(
                child: Text(
                  filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.sans,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    height: 1.0,
                    // The title uses the full foreground color (no dimming).
                    color: onBg,
                  ),
                ),
              ),
            ),
            if (copyText != null)
              CopyButton(
                text: copyText!,
                color: onBg.withValues(alpha: 0.55),
                hoverColor: onBg,
                size: 15,
              ),
          ],
        ),
      ),
    );
  }
}

/// A small copy button that stays legible when floating over code.
class _CopyChip extends StatelessWidget {
  const _CopyChip({required this.text, required this.onBg, required this.bg});

  final String text;
  final Color onBg;
  final Color bg;

  /// Gap between the chip and the card's top and right edges.
  static const double inset = 8;

  /// Size of the copy glyph.
  static const double _glyph = 15;

  /// The chip's width: the glyph plus [CopyButton]'s 6px padding on each side.
  static const double _extent = _glyph + 2 * 6;

  /// Width of the strip the chip takes beside the code: the chip with an
  /// [inset] on each side.
  static const double strip = inset + _extent + inset;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(onBg.withValues(alpha: 0.06), bg),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: onBg.withValues(alpha: 0.10)),
      ),
      child: CopyButton(
        text: text,
        color: onBg.withValues(alpha: 0.55),
        hoverColor: onBg,
        size: _glyph,
      ),
    );
  }
}
