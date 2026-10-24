import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kit/site_kit.dart';

import '../canvas/board.dart';
import '../canvas/rail.dart';
import '../canvas/toolbar.dart';
import '../catalog/catalog.dart';

/// Smallest and largest canvas zoom.
const double _kMinScale = 0.15;
const double _kMaxScale = 2.5;

/// The storyboard's main view: a rail of frames beside a pannable, zoomable
/// canvas holding every specimen at once.
///
/// Drag to pan, scroll or pinch to zoom, click a rail entry to fly to a frame.
/// `?frame=<id>` focuses one on load, which is what the "open on its own"
/// button and every deep link into the canvas use.
class CanvasPage extends StatefulWidget {
  const CanvasPage({super.key, this.focusId});

  /// A specimen id to fly to once the first frame is laid out.
  final String? focusId;

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  final GlobalKey _viewportKey = GlobalKey();
  final GlobalKey _boardKey = GlobalKey();
  final Map<String, GlobalKey> _frameKeys = {
    for (final specimen in allSpecimens) specimen.id: GlobalKey(),
  };

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  Animation<Matrix4>? _flight;

  String? _selected;
  bool _showGrid = true;
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
    _anim.addListener(() {
      final flight = _flight;
      if (flight != null) _transform.value = flight.value;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = widget.focusId;
      if (target != null && _frameKeys.containsKey(target)) {
        _focus(target);
      } else {
        // Land slightly zoomed out at the top-left: enough of the board to
        // read as a canvas, still large enough to read. Fitting everything
        // would drop to ~20%, where nothing is legible; that is what the Fit
        // button (⌘1) is for.
        _animateTo(_matrixOf(0.75, const Offset(24, 24)), animate: false);
      }
    });
  }

  @override
  void didUpdateWidget(CanvasPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new `?frame=` on the same route (browser back, or a link from the solo
    // page) should fly to the newly requested frame.
    final target = widget.focusId;
    if (target != oldWidget.focusId &&
        target != null &&
        _frameKeys.containsKey(target)) {
      _focus(target);
    }
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _onTransform() {
    final scale = _transform.value.storage[0];
    if ((scale - _scale).abs() > 0.001) setState(() => _scale = scale);
  }

  // ---------------------------------------------------------------- geometry

  /// A uniform scale-and-translate matrix, the only shape this canvas uses.
  /// Built by hand rather than through `Matrix4.translate`, whose signature has
  /// churned across vector_math versions.
  Matrix4 _matrixOf(double scale, Offset translation) => Matrix4.identity()
    ..setEntry(0, 0, scale)
    ..setEntry(1, 1, scale)
    ..setEntry(2, 2, scale)
    ..setEntry(0, 3, translation.dx)
    ..setEntry(1, 3, translation.dy);

  Offset get _translation =>
      Offset(_transform.value.storage[12], _transform.value.storage[13]);

  Size? get _viewportSize =>
      (_viewportKey.currentContext?.findRenderObject() as RenderBox?)?.size;

  RenderBox? get _boardBox =>
      _boardKey.currentContext?.findRenderObject() as RenderBox?;

  void _animateTo(Matrix4 target, {bool animate = true}) {
    if (!animate) {
      _anim.stop();
      _transform.value = target;
      return;
    }
    _flight = Matrix4Tween(begin: _transform.value.clone(), end: target)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOutCubic));
    _anim.forward(from: 0);
  }

  /// Scales about the viewport's center, so the content under the middle of the
  /// screen stays put.
  void _zoomBy(double factor) {
    final viewport = _viewportSize;
    if (viewport == null) return;
    final focal = Offset(viewport.width / 2, viewport.height / 2);
    final current = _scale;
    final target = (current * factor).clamp(_kMinScale, _kMaxScale);
    if (target == current) return;
    final ratio = target / current;
    final translation = focal - (focal - _translation) * ratio;
    _animateTo(_matrixOf(target, translation));
  }

  /// Frames the whole board in the viewport.
  void _fit({bool animate = true}) {
    final viewport = _viewportSize;
    final board = _boardBox;
    if (viewport == null || board == null) return;
    final content = board.size;
    if (content.isEmpty) return;
    // Whichever axis runs out first decides the scale; never zoom past 1:1.
    final scale = [
      viewport.width / content.width,
      viewport.height / content.height,
    ].reduce((a, b) => a < b ? a : b).clamp(_kMinScale, 1.0);
    final translation = Offset(
      (viewport.width - content.width * scale) / 2,
      (viewport.height - content.height * scale) / 2,
    );
    setState(() => _selected = null);
    _animateTo(_matrixOf(scale, translation), animate: animate);
  }

  /// Returns to 1:1 at the top-left of the board.
  void _reset() {
    _animateTo(_matrixOf(1, const Offset(48, 48)));
  }

  /// Centers [id] in the viewport at a scale that fits it comfortably.
  void _focus(String id) {
    final viewport = _viewportSize;
    final board = _boardBox;
    final frame =
        _frameKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || board == null || frame == null) return;

    // Frame position in unscaled board coordinates: the transform lives above
    // the board, so this walk is pure layout offsets.
    final origin = frame.localToGlobal(Offset.zero, ancestor: board);
    final rect = origin & frame.size;

    // Fit the frame with a margin, but never blow a small frame up past 1:1.
    const margin = 80.0;
    final scale =
        [
              (viewport.width - margin * 2) / rect.width,
              (viewport.height - margin * 2) / rect.height,
              1.0,
            ].reduce((a, b) => a < b ? a : b).clamp(_kMinScale, _kMaxScale);

    final translation = Offset(
      viewport.width / 2 - rect.center.dx * scale,
      viewport.height / 2 - rect.center.dy * scale,
    );
    setState(() => _selected = id);
    _animateTo(_matrixOf(scale, translation));
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final compact = context.isCompact;

    final canvas = Expanded(
      child: ColoredBox(
        color: colors.background,
        child: InteractiveViewer(
          key: _viewportKey,
          transformationController: _transform,
          // The board sizes itself; it is far larger than the viewport.
          constrained: false,
          boundaryMargin: const EdgeInsets.all(4000),
          minScale: _kMinScale,
          maxScale: _kMaxScale,
          child: Board(
            key: _boardKey,
            groups: catalog,
            frameKeys: _frameKeys,
            selectedId: _selected,
            showGrid: _showGrid,
            onSelect: _focus,
          ),
        ),
      ),
    );

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.equal, meta: true): _ZoomIntent(1.25),
        SingleActivator(LogicalKeyboardKey.equal, control: true):
            _ZoomIntent(1.25),
        SingleActivator(LogicalKeyboardKey.minus, meta: true): _ZoomIntent(0.8),
        SingleActivator(LogicalKeyboardKey.minus, control: true):
            _ZoomIntent(0.8),
        SingleActivator(LogicalKeyboardKey.digit0, meta: true): _ResetIntent(),
        SingleActivator(LogicalKeyboardKey.digit0, control: true):
            _ResetIntent(),
        SingleActivator(LogicalKeyboardKey.digit1, meta: true): _FitIntent(),
        SingleActivator(LogicalKeyboardKey.digit1, control: true): _FitIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ZoomIntent: CallbackAction<_ZoomIntent>(
            onInvoke: (intent) {
              _zoomBy(intent.factor);
              return null;
            },
          ),
          _FitIntent: CallbackAction<_FitIntent>(
            onInvoke: (_) {
              _fit();
              return null;
            },
          ),
          _ResetIntent: CallbackAction<_ResetIntent>(
            onInvoke: (_) {
              _reset();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: colors.background,
            body: Column(
              children: [
                CanvasToolbar(
                  scale: _scale,
                  onZoomIn: () => _zoomBy(1.25),
                  onZoomOut: () => _zoomBy(0.8),
                  onFit: _fit,
                  onReset: _reset,
                  showGrid: _showGrid,
                  onToggleGrid: () => setState(() => _showGrid = !_showGrid),
                ),
                Expanded(
                  child: Row(
                    children: [
                      // The rail is the primary way around the canvas, so it
                      // only folds away on genuinely narrow windows.
                      if (!compact)
                        CanvasRail(selectedId: _selected, onSelect: _focus),
                      canvas,
                    ],
                  ),
                ),
              ],
            ),
            floatingActionButton: compact
                ? FloatingActionButton.extended(
                    backgroundColor: colors.surfaceInset,
                    foregroundColor: colors.foreground,
                    onPressed: () => _openFramePicker(context),
                    icon: const SiteIcon(SiteIcons.menu, size: 18),
                    label: const Text('Frames'),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  /// The compact-width stand-in for the rail: the same list in a sheet.
  void _openFramePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surface,
      showDragHandle: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: CanvasRail(
          width: double.infinity,
          selectedId: _selected,
          onSelect: (id) {
            Navigator.of(sheetContext).pop();
            _focus(id);
          },
        ),
      ),
    );
  }
}

class _ZoomIntent extends Intent {
  const _ZoomIntent(this.factor);

  final double factor;
}

class _FitIntent extends Intent {
  const _FitIntent();
}

class _ResetIntent extends Intent {
  const _ResetIntent();
}
