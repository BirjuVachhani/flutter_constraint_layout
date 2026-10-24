import 'package:flutter/material.dart';

import '../responsive/breakpoints.dart';
import '../theme/context_extensions.dart';
import '../theme/tokens.dart';
import 'section.dart';

/// The closing call to action above the footer: a title, a paragraph, and a row
/// of buttons, framed by hairlines that pair with the footer's own top border.
class CtaBand extends StatelessWidget {
  const CtaBand({
    super.key,
    required this.title,
    this.body,
    this.actions = const [],
    this.centered = false,
  });

  final String title;
  final String? body;
  final List<Widget> actions;

  /// Center the block instead of aligning it to the content column's left
  /// edge. Right for a short, punchy closer.
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final styles = context.text;
    final compact = context.isCompact;
    final alignment = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;

    return ContentContainer(
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.border),
            bottom: BorderSide(color: colors.border),
          ),
        ),
        margin: const EdgeInsets.only(top: SiteSpacing.xxl),
        padding: EdgeInsets.symmetric(vertical: compact ? 48 : 64),
        child: Column(
          crossAxisAlignment: alignment,
          children: [
            Text(
              title,
              style: styles.h2,
              textAlign: centered ? TextAlign.center : TextAlign.start,
            ),
            if (body != null) ...[
              const SizedBox(height: SiteSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: SiteLayout.proseMaxWidth,
                ),
                child: Text(
                  body!,
                  style: styles.body.copyWith(
                    color: colors.mutedForeground,
                    height: 1.5,
                  ),
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: SiteSpacing.lg),
              Wrap(
                spacing: SiteSpacing.sm,
                runSpacing: SiteSpacing.sm,
                alignment: centered ? WrapAlignment.center : WrapAlignment.start,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
