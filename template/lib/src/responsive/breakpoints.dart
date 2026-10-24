import 'package:flutter/widgets.dart';

/// The named width bands the layout adapts across.
///
/// Bands are half-open: a viewport belongs to the largest band whose minimum
/// width it meets.
enum Breakpoint {
  /// Phones, portrait. `< 600`.
  xs(0),

  /// Large phones and small tablets. `>= 600`.
  sm(600),

  /// Tablets and small laptops. `>= 900`.
  md(900),

  /// Desktops. `>= 1200`.
  lg(1200),

  /// Wide desktops. `>= 1536`.
  xl(1536);

  const Breakpoint(this.minWidth);

  /// Smallest viewport width in this band, in logical pixels.
  final double minWidth;

  /// The band [width] falls into.
  static Breakpoint of(double width) {
    // Walk down so the first match is the largest satisfied band.
    for (final bp in Breakpoint.values.reversed) {
      if (width >= bp.minWidth) return bp;
    }
    return Breakpoint.xs;
  }

  bool operator >=(Breakpoint other) => minWidth >= other.minWidth;
  bool operator >(Breakpoint other) => minWidth > other.minWidth;
  bool operator <=(Breakpoint other) => minWidth <= other.minWidth;
  bool operator <(Breakpoint other) => minWidth < other.minWidth;

  /// Whether the layout should collapse to a single column with drawer menus.
  /// True below [Breakpoint.md], the point the nav links and side rails fold.
  bool get isCompact => this < Breakpoint.md;
}

/// A value that changes with the viewport width.
///
/// Only [xs] is required; any band left null falls back to the nearest smaller
/// one that is set, so `ResponsiveValue(xs: 1, md: 3)` yields 1, 1, 3, 3, 3.
@immutable
class ResponsiveValue<T> {
  const ResponsiveValue({required this.xs, this.sm, this.md, this.lg, this.xl});

  final T xs;
  final T? sm;
  final T? md;
  final T? lg;
  final T? xl;

  /// The value for [breakpoint], cascading down to the nearest set band.
  T resolveFor(Breakpoint breakpoint) => switch (breakpoint) {
    Breakpoint.xl => xl ?? lg ?? md ?? sm ?? xs,
    Breakpoint.lg => lg ?? md ?? sm ?? xs,
    Breakpoint.md => md ?? sm ?? xs,
    Breakpoint.sm => sm ?? xs,
    Breakpoint.xs => xs,
  };

  /// The value for the viewport [context] is laid out in.
  T resolve(BuildContext context) => resolveFor(context.breakpoint);
}

/// Viewport queries, read straight off the [BuildContext].
extension BreakpointContext on BuildContext {
  /// Width of the nearest [MediaQuery], in logical pixels.
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// Height of the nearest [MediaQuery], in logical pixels.
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// The band the viewport currently falls into.
  Breakpoint get breakpoint => Breakpoint.of(screenWidth);

  /// Whether the compact (phone / small tablet) layout should be used: nav
  /// links collapse into a menu and side rails fold away.
  bool get isCompact => breakpoint.isCompact;

  /// Whether the viewport is at least [Breakpoint.lg] wide.
  bool get isDesktop => breakpoint >= Breakpoint.lg;

  /// Picks a value per band without allocating a [ResponsiveValue].
  T responsive<T>({required T xs, T? sm, T? md, T? lg, T? xl}) =>
      ResponsiveValue<T>(
        xs: xs,
        sm: sm,
        md: md,
        lg: lg,
        xl: xl,
      ).resolve(this);
}

/// Builds different subtrees per breakpoint.
///
/// Reads the *incoming constraints*, not the window, so it also works for a
/// panel inside a wider page (a preview frame, a split view, a storyboard
/// canvas). Pass `useScreenWidth: true` to follow the viewport instead.
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.builder,
    this.useScreenWidth = false,
  });

  final Widget Function(
    BuildContext context,
    Breakpoint breakpoint,
    BoxConstraints constraints,
  )
  builder;

  /// Measure the viewport rather than the parent's constraints.
  final bool useScreenWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = useScreenWidth || !constraints.hasBoundedWidth
            ? context.screenWidth
            : constraints.maxWidth;
        return builder(context, Breakpoint.of(width), constraints);
      },
    );
  }
}

/// An equal-height grid whose column count follows the breakpoint.
///
/// Every card in a row takes the height of the tallest card in that row (an
/// [IntrinsicHeight] per row), which is what a [Wrap] cannot do. The last row
/// keeps the column rhythm instead of stretching its cards across the width.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.columns = const ResponsiveValue<int>(xs: 1, sm: 2, md: 3),
    this.spacing = 16,
    this.runSpacing = 16,
    this.equalHeight = true,
  });

  final List<Widget> children;

  /// Columns per breakpoint. Measured against the grid's own width, so a grid
  /// inside a narrow panel drops columns like it would on a narrow window.
  final ResponsiveValue<int> columns;

  /// Horizontal gap between cards.
  final double spacing;

  /// Vertical gap between rows.
  final double runSpacing;

  /// Stretch every card in a row to the tallest one. Turn it off for content
  /// with no shared surface to align (plain text lists, images).
  final bool equalHeight;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return ResponsiveBuilder(
      builder: (context, breakpoint, _) {
        final cols = columns.resolveFor(breakpoint).clamp(1, children.length);
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += cols) {
          final end = (start + cols).clamp(0, children.length);
          final cells = <Widget>[];
          for (var i = start; i < end; i++) {
            if (i > start) cells.add(SizedBox(width: spacing));
            cells.add(Expanded(child: children[i]));
          }
          // Pad a short final row so its cards keep the column width instead of
          // stretching to fill the leftover space.
          for (var i = end; i < start + cols; i++) {
            cells
              ..add(SizedBox(width: spacing))
              ..add(const Expanded(child: SizedBox.shrink()));
          }
          final row = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: cells,
          );
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: start == 0 ? 0 : runSpacing),
              child: equalHeight ? IntrinsicHeight(child: row) : row,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}
