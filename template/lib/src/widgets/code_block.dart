import 'package:flutter/material.dart';
import 'package:shiki_flutter/shiki_flutter.dart';

import '../highlight/highlighter_service.dart';
import '../theme/context_extensions.dart';
import '../theme/tokens.dart';
import 'copy_button.dart';
import 'site_icon.dart';

/// A rounded, bordered code card highlighted live by shiki_flutter.
///
/// With no [theme] the block follows the site's light/dark mode. It grows to
/// fit its content vertically, so it never traps the page's scroll; long lines
/// scroll horizontally inside the card.
///
/// Given a [filename] the block gains a header (file glyph, name, copy button)
/// separated from the code by a hairline. Without one there is no header chrome
/// and a subtle copy button floats in the top-right instead.
///
/// A [lang] that is not registered with [SiteHighlighter] renders as plain
/// monospaced text rather than failing, so an unexpected fenced language in
/// authored content degrades quietly.
class CodeBlock extends StatelessWidget {
  const CodeBlock({
    super.key,
    required this.code,
    this.lang = 'dart',
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

  /// A language id registered with [SiteHighlighter], e.g. `dart`, `yaml`.
  final String lang;

  /// The theme (or light/dark pair) to render with. Defaults to the shared
  /// [SiteHighlighter.theme], resolved against the ambient brightness.
  final ShikiThemeBase? theme;

  /// When set, renders a header bar with this file name. The copy button moves
  /// into the header instead of floating over the code.
  final String? filename;

  final bool showCopy;

  /// Show a line-number gutter.
  final bool showLineNumbers;

  final double fontSize;

  /// Draw a hairline under the header.
  final bool showDividers;

  /// Fill the card's height and scroll a long snippet internally instead of
  /// growing to fit. Requires a bounded height from the parent; use it when the
  /// card is height-capped beside a sibling.
  final bool fillHeight;

  /// Outer margin. Defaults to a 12px bottom gap for stacked blocks; pass
  /// [EdgeInsets.zero] when the card is sized to match a sibling.
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final service = SiteHighlighter.instance;
    final isDark = context.isDarkMode;
    final resolved = (theme ?? service.theme).resolve(isDark: isDark);

    final trimmed = code.trim();
    final background = service.backgroundOf(resolved.id, colors.surface);
    // Pick the ink from the card's own background, not the page's: a light code
    // theme inside a dark page still needs dark chrome on top of it.
    final onBackground = background.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
    final border = onBackground.withValues(alpha: 0.10);
    final hasHeader = filename != null;

    final textStyle = TextStyle(
      fontFamily: SiteFonts.mono,
      fontSize: fontSize,
      height: 20 / fontSize,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final language = service.languageFor(lang);

    // Async highlighting: the block shows plain code first and swaps to the
    // highlighted result when tokenization finishes, with the shared
    // highlighter's token cache making later rebuilds instant. Shrink-wrapped,
    // so the block grows to fit and never traps the page's vertical scroll.
    //
    // No wrapping SelectionArea here: `selectable: true` lets ShikiCodeView add
    // one only when there is no ancestor SelectionArea. SiteShell already
    // provides a page-level one, and nesting two breaks keyboard copy.
    final Widget body = language == null
        ? _PlainCode(
            code: trimmed,
            style: textStyle.copyWith(color: onBackground),
            padding: EdgeInsets.only(
              left: 15.6,
              top: hasHeader && !showDividers ? 0 : 12,
              bottom: 12,
              right: 15.6,
            ),
          )
        : ShikiCodeView(
            highlighter: service.highlighter,
            code: trimmed,
            lang: language,
            theme: resolved,
            selectable: true,
            textStyle: textStyle,
            gutterStyle: GutterStyle(
              spacing: 15.6,
              dividerColor: showDividers ? border : null,
              textColor: onBackground.withValues(alpha: 0.32),
              textScale: 0.9,
            ),
            showLineNumbers: showLineNumbers,
            paintBackground: false,
            padding: EdgeInsets.only(
              left: 15.6,
              top: hasHeader && !showDividers ? 0 : 12,
              bottom: 12,
              right: 15.6,
            ),
          );

    final Widget content = hasHeader
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                filename: filename!,
                onBackground: onBackground,
                copyText: showCopy ? trimmed : null,
              ),
              if (showDividers) Divider(height: 1, color: border),
              // Height-capped beside a sibling: fill the remaining card height
              // and scroll internally. Otherwise grow to fit.
              if (fillHeight)
                Expanded(child: SingleChildScrollView(child: body))
              else
                body,
            ],
          )
        : Stack(
            children: [
              body,
              if (showCopy)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _CopyChip(
                    text: trimmed,
                    onBackground: onBackground,
                    background: background,
                  ),
                ),
            ],
          );

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(SiteRadii.lg),
        border: Border.all(color: border),
      ),
      // No outer clip; it would trim the 1px border. The inner content is
      // clipped to the inner radius instead, so the corners stay clean.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SiteRadii.lg - 1),
        child: content,
      ),
    );
  }
}

/// The fallback body for an unregistered language: the same metrics as the
/// highlighted view, just without tokenization.
class _PlainCode extends StatelessWidget {
  const _PlainCode({
    required this.code,
    required this.style,
    required this.padding,
  });

  final String code;
  final TextStyle style;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: padding,
        child: Text(code, style: style, softWrap: false),
      ),
    );
  }
}

/// The header bar: a file glyph and name on the left, the copy button right.
class _Header extends StatelessWidget {
  const _Header({
    required this.filename,
    required this.onBackground,
    required this.copyText,
  });

  final String filename;
  final Color onBackground;

  /// Text to copy, or null to hide the button.
  final String? copyText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The right inset is trimmed to 10 so the copy glyph's own 6px padding
      // lands ~16px from the edge, matching the left.
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Row(
          children: [
            SiteIcon(
              SiteIcons.fileCode,
              size: 16,
              color: onBackground.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SelectionContainer.disabled(
                child: Text(
                  filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: SiteFonts.sans,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    height: 1.0,
                    color: onBackground,
                  ),
                ),
              ),
            ),
            if (copyText != null)
              CopyButton(
                text: copyText!,
                color: onBackground.withValues(alpha: 0.55),
                hoverColor: onBackground,
                size: 15,
              ),
          ],
        ),
      ),
    );
  }
}

/// A small copy button that stays legible floating over code.
class _CopyChip extends StatelessWidget {
  const _CopyChip({
    required this.text,
    required this.onBackground,
    required this.background,
  });

  final String text;
  final Color onBackground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          onBackground.withValues(alpha: 0.06),
          background,
        ),
        borderRadius: BorderRadius.circular(SiteRadii.sm),
        border: Border.all(color: onBackground.withValues(alpha: 0.10)),
      ),
      child: CopyButton(
        text: text,
        color: onBackground.withValues(alpha: 0.55),
        hoverColor: onBackground,
        size: 15,
      ),
    );
  }
}
