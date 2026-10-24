import 'package:flutter/material.dart';

import '../theme/context_extensions.dart';
import '../theme/tokens.dart';
import 'site_icon.dart';

/// Builds the trigger, given whether the menu is [open] and a [toggle] callback.
typedef DropdownTriggerBuilder =
    Widget Function(BuildContext context, bool open, VoidCallback toggle);

/// Builds the popup content, given a [close] callback for menu items to call.
typedef DropdownOverlayBuilder =
    Widget Function(BuildContext context, VoidCallback close);

/// A trigger that opens an anchored, animated popup.
///
/// Built on [OverlayPortal] rather than `MenuAnchor` so the popup has a real
/// opaque surface, a controlled fade/scale open, and an outside tap that
/// closes it. Pair it with [MenuPanel] and [MenuItemRow] for the stock look, or
/// return anything from [overlayBuilder].
class SiteDropdown extends StatefulWidget {
  const SiteDropdown({
    super.key,
    required this.triggerBuilder,
    required this.overlayBuilder,
    this.targetAnchor = Alignment.bottomLeft,
    this.followerAnchor = Alignment.topLeft,
    this.panelAlignment = Alignment.topLeft,
    this.scaleAlignment = Alignment.topLeft,
    this.offset = const Offset(0, 6),
  });

  /// Anchors the popup to the trigger's right edge; use for a control that sits
  /// at the right of its row, so the menu opens inward.
  const SiteDropdown.alignRight({
    super.key,
    required this.triggerBuilder,
    required this.overlayBuilder,
    this.offset = const Offset(0, 6),
  }) : targetAnchor = Alignment.bottomRight,
       followerAnchor = Alignment.topRight,
       panelAlignment = Alignment.topRight,
       scaleAlignment = Alignment.topRight;

  final DropdownTriggerBuilder triggerBuilder;
  final DropdownOverlayBuilder overlayBuilder;

  /// Point on the trigger the popup is anchored to.
  final Alignment targetAnchor;

  /// Point on the popup pinned to [targetAnchor].
  final Alignment followerAnchor;

  /// Alignment of the popup within the follower box.
  final Alignment panelAlignment;

  /// Origin of the open scale animation (usually matches [followerAnchor]).
  final Alignment scaleAlignment;

  /// Extra offset from the anchor, e.g. a small gap below the trigger.
  final Offset offset;

  @override
  State<SiteDropdown> createState() => _SiteDropdownState();
}

class _SiteDropdownState extends State<SiteDropdown>
    with SingleTickerProviderStateMixin {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  // Created in initState rather than as an inline `late final`: a lazy
  // initializer would build the Ticker during teardown if the menu was never
  // opened, which throws.
  late final AnimationController _anim;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: SiteMotion.fast);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _openMenu() {
    setState(() => _open = true);
    _portal.show();
    _anim.forward(from: 0);
  }

  void _closeMenu() {
    if (!_open) return;
    _anim.reverse().then((_) {
      if (!mounted) return;
      _portal.hide();
      setState(() => _open = false);
    });
  }

  void _toggle() => _open ? _closeMenu() : _openMenu();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Positioned.fill(
          child: Stack(
            children: [
              // Outside-tap barrier.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeMenu,
                ),
              ),
              CompositedTransformFollower(
                link: _link,
                targetAnchor: widget.targetAnchor,
                followerAnchor: widget.followerAnchor,
                offset: widget.offset,
                child: Align(
                  alignment: widget.panelAlignment,
                  child: AnimatedBuilder(
                    animation: _anim,
                    builder: (context, child) {
                      final t = SiteMotion.enter.transform(_anim.value);
                      return Opacity(
                        opacity: t,
                        child: Transform.translate(
                          offset: Offset(0, (1 - t) * 4),
                          child: Transform.scale(
                            scale: 0.98 + 0.02 * t,
                            alignment: widget.scaleAlignment,
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: widget.overlayBuilder(context, _closeMenu),
                  ),
                ),
              ),
            ],
          ),
        ),
        child: widget.triggerBuilder(context, _open, _toggle),
      ),
    );
  }
}

/// A solid, bordered, rounded popover card for [SiteDropdown] menus.
class MenuPanel extends StatelessWidget {
  const MenuPanel({
    super.key,
    required this.children,
    this.width = 220,
    this.maxHeight = 360,
  });

  final List<Widget> children;
  final double width;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 24,
              spreadRadius: -6,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(4),
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }
}

/// A single row in a [MenuPanel]: an optional leading glyph, a label, and an
/// optional trailing widget (a checkmark, a shortcut hint).
class MenuItemRow extends StatefulWidget {
  const MenuItemRow({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.materialIcon,
    this.trailing,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final SiteIcons? icon;
  final IconData? materialIcon;
  final Widget? trailing;

  /// Paint the row as the active choice.
  final bool selected;

  @override
  State<MenuItemRow> createState() => _MenuItemRowState();
}

class _MenuItemRowState extends State<MenuItemRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconColor = widget.selected
        ? colors.foreground
        : colors.mutedForeground;

    final row = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered || widget.selected
                ? colors.surfaceInset
                : Colors.transparent,
            borderRadius: BorderRadius.circular(SiteRadii.xs),
          ),
          child: Row(
            children: [
              if (widget.icon != null || widget.materialIcon != null) ...[
                AnyIcon(
                  siteIcon: widget.icon,
                  icon: widget.materialIcon,
                  size: 15,
                  color: iconColor,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.label,
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 8),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
    return SelectionContainer.disabled(child: row);
  }
}

/// A hairline separating groups of [MenuItemRow]s.
class MenuSeparator extends StatelessWidget {
  const MenuSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Divider(height: 1, color: context.colors.border),
    );
  }
}
