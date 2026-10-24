import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/context_extensions.dart';
import 'site_icon.dart';

/// An icon button that copies [text] to the clipboard and briefly swaps to a
/// checkmark as confirmation.
class CopyButton extends StatefulWidget {
  const CopyButton({
    super.key,
    required this.text,
    this.color,
    this.hoverColor,
    this.size = 16,
    this.tooltip = 'Copy',
    this.copiedTooltip = 'Copied!',
    this.onCopied,
  });

  final String text;

  /// Resting color. Defaults to the theme's muted foreground.
  final Color? color;

  /// Color on hover. Defaults to the theme foreground; pass a code block's
  /// `onBg` so the button stays legible when it floats over a light-themed
  /// block in dark mode (or the reverse).
  final Color? hoverColor;

  final double size;
  final String tooltip;
  final String copiedTooltip;

  /// Called after the clipboard write succeeds.
  final VoidCallback? onCopied;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;
  bool _hovered = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    widget.onCopied?.call();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final base = widget.color ?? colors.mutedForeground;
    final hover = widget.hoverColor ?? colors.foreground;
    final color = _copied ? colors.accent : (_hovered ? hover : base);

    final button = Tooltip(
      message: _copied ? widget.copiedTooltip : widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _copy,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: SiteIcon(
              _copied ? SiteIcons.check : SiteIcons.copy,
              size: widget.size,
              color: color,
            ),
          ),
        ),
      ),
    );
    // Chrome is not part of the page's copyable text.
    return SelectionContainer.disabled(child: button);
  }
}
