/// Prose components for authoring documentation in Dart: body text at a 768px
/// reading measure, headings, bullets, tables, and callouts.
///
/// Every text argument supports a small Markdown subset, see [inlineSpans]:
/// `` `code` `` renders as mono and `**bold**` as semibold. Code blocks are
/// left to span the full content width, so they sit outside this measure.
library;

import 'package:flutter/material.dart';

import '../theme/context_extensions.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';

/// The reading measure for prose.
const double kProseWidth = SiteLayout.readingMaxWidth;

/// A body paragraph. Wrap inline code in backticks.
class Prose extends StatelessWidget {
  const Prose(this.text, {super.key, this.maxWidth = kProseWidth});

  final String text;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Paragraphs sit ~20px apart (line pitch 25.5 plus a ~20px margin).
      padding: const EdgeInsets.only(bottom: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text.rich(
          TextSpan(children: inlineSpans(text, context.text)),
          style: context.text.body,
        ),
      ),
    );
  }
}

/// A heading inside a prose column.
class ProseHeading extends StatelessWidget {
  const ProseHeading(this.text, {super.key, this.level = 3});

  final String text;

  /// 2 for a section title, 3 for a subsection, 4 for a small run-in heading.
  final int level;

  @override
  Widget build(BuildContext context) {
    final styles = context.text;
    final (style, top, bottom) = switch (level) {
      <= 2 => (styles.h2, 32.0, 12.0),
      3 => (styles.h3, 26.0, 8.0),
      _ => (styles.h4, 20.0, 6.0),
    };
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: Text(text, style: style),
    );
  }
}

/// A bulleted or numbered list; each item supports inline `code`.
class ProseList extends StatelessWidget {
  const ProseList(this.items, {super.key, this.ordered = false});

  final List<String> items;

  /// Render `1.` `2.` markers instead of dots.
  final bool ordered;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final styles = context.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kProseWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, item) in items.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ordered)
                      Padding(
                        padding: const EdgeInsets.only(right: 10, left: 2),
                        child: SizedBox(
                          width: 18,
                          child: Text(
                            '${index + 1}.',
                            style: styles.body.copyWith(
                              color: colors.mutedForeground,
                            ),
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 10,
                          left: 4,
                          right: 14,
                        ),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.mutedForeground,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: inlineSpans(item, styles)),
                        style: styles.body,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A borderless table with horizontal row rules.
///
/// A body cell that is exactly one inline-code token renders as a code chip, so
/// property and type columns read as code.
class ProseTable extends StatelessWidget {
  const ProseTable({super.key, required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kProseWidth),
        child: Table(
          border: TableBorder(
            horizontalInside: BorderSide(color: colors.border),
            bottom: BorderSide(color: colors.border),
          ),
          columnWidths: const {0: IntrinsicColumnWidth()},
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          children: [
            TableRow(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.mutedForeground),
                ),
              ),
              children: [
                for (final header in headers)
                  _cell(context, header, header: true),
              ],
            ),
            for (final row in rows)
              TableRow(children: [for (final c in row) _cell(context, c)]),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, String text, {bool header = false}) {
    final styles = context.text;
    if (!header && _isCodeToken(text)) {
      return _codeChip(context, text.substring(1, text.length - 1));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12, right: 24),
      child: Text.rich(
        TextSpan(children: inlineSpans(text, styles)),
        style: styles.body.copyWith(
          fontSize: 14,
          height: 1.5,
          fontWeight: header ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  /// Whether [text] is a single inline-code token, e.g. `` `String` ``.
  static bool _isCodeToken(String text) {
    return text.length >= 2 &&
        text.startsWith('`') &&
        text.endsWith('`') &&
        !text.substring(1, text.length - 1).contains('`');
  }

  Widget _codeChip(BuildContext context, String label) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8, right: 24),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(SiteRadii.xs),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            label,
            style: context.text.mono.copyWith(fontSize: 13, height: 1.3),
          ),
        ),
      ),
    );
  }
}

/// The tone of a [Callout].
enum CalloutTone { note, tip, warning, danger }

/// A bordered box for an aside: a tip, a caveat, a warning.
class Callout extends StatelessWidget {
  const Callout(
    this.text, {
    super.key,
    this.tone = CalloutTone.note,
    this.title,
    this.icon,
  });

  final String text;
  final CalloutTone tone;

  /// A bold line above the body.
  final String? title;

  /// Overrides the tone's default glyph.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final styles = context.text;
    final (accent, defaultIcon) = switch (tone) {
      CalloutTone.note => (colors.mutedForeground, Icons.info_outline_rounded),
      CalloutTone.tip => (colors.accent, Icons.lightbulb_outline_rounded),
      CalloutTone.warning => (colors.link, Icons.error_outline_rounded),
      CalloutTone.danger => (colors.danger, Icons.warning_amber_rounded),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kProseWidth),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tone == CalloutTone.note
                ? colors.surface
                : accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(SiteRadii.md),
            border: Border.all(
              color: tone == CalloutTone.note
                  ? colors.border
                  : accent.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon ?? defaultIcon, size: 18, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: styles.label.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text.rich(
                      TextSpan(children: inlineSpans(text, styles)),
                      style: styles.body.copyWith(fontSize: 14.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Parses a small subset of Markdown inline syntax: `` `code` `` becomes plain
/// mono (no background box) and `**bold**` becomes semibold.
///
/// Bold may wrap inline code (`` **`code`** ``); the code then renders mono
/// *and* semibold, because a [TextSpan]'s style cascades to its children.
List<InlineSpan> inlineSpans(String text, SiteTextStyles styles) {
  // Match a bold run or an inline-code run, whichever starts first.
  // `allMatches` scans left to right, so a `**` inside an earlier code run is
  // consumed as part of that run and never treated as bold (and vice versa).
  final pattern = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`');
  final spans = <InlineSpan>[];
  var last = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > last) {
      spans.add(TextSpan(text: text.substring(last, match.start)));
    }
    final boldInner = match.group(1);
    if (boldInner != null) {
      // Recurse into the bold text for inline code; the w600 on this parent
      // cascades onto the code (and plain) children, keeping them bold.
      spans.add(
        TextSpan(
          style: const TextStyle(fontWeight: FontWeight.w600),
          children: _inlineCode(boldInner, styles),
        ),
      );
    } else {
      spans.add(_codeSpan(match.group(2)!, styles));
    }
    last = match.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}

/// Splits [text] into plain runs and inline-`code` runs. Sets no weight of its
/// own, so an enclosing bold [TextSpan] cascades through.
List<InlineSpan> _inlineCode(String text, SiteTextStyles styles) {
  final code = RegExp(r'`([^`]+)`');
  final spans = <InlineSpan>[];
  var last = 0;
  for (final match in code.allMatches(text)) {
    if (match.start > last) {
      spans.add(TextSpan(text: text.substring(last, match.start)));
    }
    spans.add(_codeSpan(match.group(1)!, styles));
    last = match.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}

/// A single inline-code span: plain mono, no background box. Leaves
/// `fontWeight` unset so it inherits any enclosing bold.
TextSpan _codeSpan(String content, SiteTextStyles styles) => TextSpan(
  text: content,
  style: TextStyle(
    fontFamily: styles.mono.fontFamily,
    fontSize: 14.5,
    color: styles.body.color,
  ),
);
