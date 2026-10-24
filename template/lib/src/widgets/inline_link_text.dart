import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/context_extensions.dart';
import '../util/launch_link.dart';

/// One link inside a run of body copy: the first occurrence of [label] becomes
/// tappable.
@immutable
class TextLink {
  const TextLink(this.label, {this.url, this.route, this.onTap})
    : assert(
        url != null || route != null || onTap != null,
        'A TextLink needs somewhere to go: pass url, route, or onTap.',
      );

  final String label;
  final String? url;
  final String? route;
  final VoidCallback? onTap;
}

/// Body copy with one or more inline links woven into it.
///
/// Each [TextLink] matches the first occurrence of its label that has not
/// already been claimed by an earlier link, so overlapping labels resolve
/// left to right. Labels that never appear are dropped, and the text still
/// renders, which keeps a copy edit from throwing.
///
/// Owns and disposes its gesture recognizers, so callers stay stateless.
class InlineLinkText extends StatefulWidget {
  const InlineLinkText(
    this.text, {
    super.key,
    this.links = const [],
    this.style,
    this.textAlign,
  });

  /// Convenience for the common single-link case.
  InlineLinkText.single(
    this.text, {
    super.key,
    required String label,
    String? url,
    String? route,
    VoidCallback? onTap,
    this.style,
    this.textAlign,
  }) : links = [TextLink(label, url: url, route: route, onTap: onTap)];

  final String text;
  final List<TextLink> links;

  /// Defaults to `context.text.body`.
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  State<InlineLinkText> createState() => _InlineLinkTextState();
}

class _InlineLinkTextState extends State<InlineLinkText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  void _activate(TextLink link) {
    if (link.onTap != null) {
      link.onTap!();
    } else if (link.url != null) {
      openLink(link.url!);
    } else if (link.route != null) {
      context.go(link.route!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = widget.style ?? context.text.body;

    // Recognizers are rebuilt each build (a link's target can change with the
    // config); the old ones are disposed first so none leak.
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    // Resolve each link to a match, skipping any span already claimed. Sorting
    // by position lets the spans be emitted in a single left-to-right pass.
    final matches = <(int start, int end, TextLink link)>[];
    final claimed = <int>{};
    for (final link in widget.links) {
      var from = 0;
      while (true) {
        final index = widget.text.indexOf(link.label, from);
        if (index < 0) break;
        final end = index + link.label.length;
        final overlaps = matches.any((m) => index < m.$2 && m.$1 < end);
        if (!overlaps && !claimed.contains(index)) {
          matches.add((index, end, link));
          claimed.add(index);
          break;
        }
        from = index + 1;
      }
    }
    matches.sort((a, b) => a.$1.compareTo(b.$1));

    final linkStyle = TextStyle(
      color: colors.foreground,
      decoration: TextDecoration.underline,
      decorationColor: colors.mutedForeground,
      decorationThickness: 1,
    );

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final (start, end, link) in matches) {
      if (start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, start)));
      }
      final recognizer = TapGestureRecognizer()..onTap = () => _activate(link);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: widget.text.substring(start, end),
          style: linkStyle,
          recognizer: recognizer,
          mouseCursor: SystemMouseCursors.click,
        ),
      );
      cursor = end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(style: style, children: spans),
      textAlign: widget.textAlign,
    );
  }
}
