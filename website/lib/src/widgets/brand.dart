import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/links.dart';
import '../theme/tokens.dart';

/// The text of the site's wordmark: the package name, set in mono. The nav,
/// the footer, and the social-preview banner (tool/render_banner_test.dart)
/// all read it from here.
const String wordmark = 'flutter_constraint_layout';

/// The wordmark: a semibold mono [wordmark] that links home, followed
/// by a muted tagline (`for Flutter by <author>`) whose author name is a link.
/// The tagline is hidden on compact layouts, like a `hidden md:inline`
/// treatment.
class Brand extends StatefulWidget {
  const Brand({super.key, this.onTap});

  /// Tapping the wordmark. Usually navigates home.
  final VoidCallback? onTap;

  @override
  State<Brand> createState() => _BrandState();
}

class _BrandState extends State<Brand> {
  late final TapGestureRecognizer _authorTap;
  bool _wordHovered = false;
  bool _authorHovered = false;

  @override
  void initState() {
    super.initState();
    _authorTap = TapGestureRecognizer()..onTap = () => Links.open(Links.author);
  }

  @override
  void dispose() {
    _authorTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showTagline = !context.isCompact;

    // The "flutter_constraint_layout" wordmark in mono, semibold, dims on hover.
    final word = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _wordHovered = true),
      onExit: (_) => setState(() => _wordHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          wordmark,
          style: TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 15.5,
            height: 20 / 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: _wordHovered
                ? colors.foreground.withValues(alpha: 0.8)
                : colors.foreground,
          ),
        ),
      ),
    );

    // The wordmark keeps its natural size while it fits and scales down when
    // the row is narrower than the name (a 320px phone, beside the nav
    // actions), so a name of any length never runs under them. The tagline
    // yields first: it gets only the room the wordmark leaves.
    final brand = LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: word,
            ),
          ),
          if (showTagline)
            // Flexible so the tagline ellipsizes instead of overflowing when
            // the nav row is tight (e.g. near the compact/wide breakpoint). The
            // gap sits inside it, so a wordmark that fills the row leaves
            // nothing to overflow.
            Flexible(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontFamily: AppFonts.sans,
                      fontSize: 14,
                      height: 20 / 14,
                      color: colors.mutedForeground,
                    ),
                    children: [
                      const TextSpan(text: 'for Flutter by '),
                      TextSpan(
                        text: 'Birju Vachhani',
                        recognizer: _authorTap,
                        onEnter: (_) => setState(() => _authorHovered = true),
                        onExit: (_) => setState(() => _authorHovered = false),
                        mouseCursor: SystemMouseCursors.click,
                        style: TextStyle(
                          color: _authorHovered
                              ? colors.foreground.withValues(alpha: 0.8)
                              : colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );

    return SelectionContainer.disabled(child: brand);
  }
}

class FooterBrand extends StatefulWidget {
  const FooterBrand({super.key, this.onTap});

  /// Tapping the wordmark. Usually navigates home.
  final VoidCallback? onTap;

  @override
  State<FooterBrand> createState() => _FooterBrandState();
}

class _FooterBrandState extends State<FooterBrand> {
  late final TapGestureRecognizer _authorTap;
  bool _wordHovered = false;
  bool _authorHovered = false;

  @override
  void initState() {
    super.initState();
    _authorTap = TapGestureRecognizer()..onTap = () => Links.open(Links.author);
  }

  @override
  void dispose() {
    _authorTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // The "flutter_constraint_layout" wordmark in mono, semibold, dims on hover.
    final word = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _wordHovered = true),
      onExit: (_) => setState(() => _wordHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          wordmark,
          style: TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 15.5,
            height: 20 / 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: _wordHovered
                ? colors.foreground.withValues(alpha: 0.8)
                : colors.foreground,
          ),
        ),
      ),
    );

    // A Wrap, not a Row: when the wordmark and tagline do not fit on one line
    // (a phone-width footer), the tagline moves below the wordmark whole
    // instead of squeezing into a narrow column beside it, and a wordmark
    // wider than the footer scales down. Geist and Geist Mono share vertical
    // metrics, so the two 20px lines sit on one baseline when they share a run.
    final brand = Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      children: [
        FittedBox(fit: BoxFit.scaleDown, child: word),
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontFamily: AppFonts.sans,
              fontSize: 14,
              height: 20 / 14,
              color: colors.mutedForeground,
            ),
            children: [
              const TextSpan(text: 'for Flutter by '),
              TextSpan(
                text: 'Birju Vachhani',
                recognizer: _authorTap,
                onEnter: (_) => setState(() => _authorHovered = true),
                onExit: (_) => setState(() => _authorHovered = false),
                mouseCursor: SystemMouseCursors.click,
                style: TextStyle(
                  color: _authorHovered
                      ? colors.foreground.withValues(alpha: 0.8)
                      : colors.mutedForeground,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );

    return SelectionContainer.disabled(child: brand);
  }
}
