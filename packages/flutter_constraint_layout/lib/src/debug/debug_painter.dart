import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../types.dart';
import 'debug_palette.dart';
import 'debug_scene.dart';

// Rendering constants, lifted from Android Studio's design surface
// (DrawConnection / DrawConnectionUtils / FancyStroke). All logical pixels.
const double _arrowSide = 6;
const double _arrowHalfBase = 5;
const double _smallArrowSide = 4;
const double _smallArrowHalfBase = 3;
const double _bezierMaxControl = 90;
const double _zigzagStep = 6;
const double _zigzagAmplitude = 3;
const double _chainSpacing = 9;
const double _chainRatio = 0.6;
const double _chainSize = 2.5;
const double _marginTickHalf = 5;
const double _marginOverhang = 20;
const double _marginFontSize = 12;
const double _chipFontSize = 14;
const double _labelFontSize = 14;
const double _typeFontSize = 11;
const double _barrierFade = 12;

/// Paints [scene] onto [canvas] with the Android Studio design-surface
/// rendering. [origin] is the layout's paint offset; all scene coordinates
/// are layout-local.
void paintDebugScene(
  Canvas canvas,
  Offset origin,
  Size size,
  DebugScene scene,
  DebugPalette palette, {
  required bool blueprint,
  required DebugLabelStyle labelStyle,
}) {
  canvas.save();
  canvas.translate(origin.dx, origin.dy);
  _ScenePainter(canvas, size, scene, palette,
          blueprint: blueprint, labelStyle: labelStyle)
      .paint();
  canvas.restore();
}

// --------------------------------------------------------- path helpers --

/// Chops [source] into dashes of [on] px separated by [off] px.
@visibleForTesting
Path debugDashPath(Path source, double on, double off) {
  final result = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      result.addPath(
        metric.extractPath(distance, math.min(distance + on, metric.length)),
        Offset.zero,
      );
      distance += on + off;
    }
  }
  return result;
}

/// The Android Studio spring: a zigzag polyline from [a] to [b] with
/// wavelength 6 and amplitude +/-3, centered, with straight lead-in/out.
@visibleForTesting
Path debugZigzag(Offset a, Offset b) {
  final path = Path()..moveTo(a.dx, a.dy);
  final delta = b - a;
  final length = delta.distance;
  if (length < _zigzagStep * 2) {
    path.lineTo(b.dx, b.dy);
    return path;
  }
  final u = delta / length;
  final p = Offset(-u.dy, u.dx);
  final count = (length ~/ _zigzagStep) - 2;
  var at = a + u * ((length - count * _zigzagStep) / 2);
  path.lineTo(at.dx, at.dy);
  for (var i = 0; i < count; i++) {
    final q1 = at + u * 2 + p * _zigzagAmplitude;
    final q2 = at + u * 4 - p * _zigzagAmplitude;
    final q3 = at + u * _zigzagStep;
    path
      ..lineTo(q1.dx, q1.dy)
      ..lineTo(q2.dx, q2.dy)
      ..lineTo(q3.dx, q3.dy);
    at = q3;
  }
  path.lineTo(b.dx, b.dy);
  return path;
}

/// The Android Studio chain-link effect: two mirrored arc-length walks over
/// [source], alternating 9 px link bumps (amplitude 2.5) and 5.4 px gap bumps
/// (amplitude 0.5), as rounded cubic segments. Stroke the result with width 1
/// and round caps.
@visibleForTesting
Path debugChainEffect(Path source) {
  final result = Path();
  for (final flip in const [-1.0, 1.0]) {
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var link = true;
      final start = metric.getTangentForOffset(0)!;
      result.moveTo(start.position.dx, start.position.dy);
      var previous = start;
      while (true) {
        final segment = link ? _chainSpacing : _chainSpacing * _chainRatio;
        final next = distance + segment;
        if (next > metric.length) break;
        final tangent = metric.getTangentForOffset(next)!;
        link = !link;
        final sign = link ? 0.2 : 1.0;
        final amplitude = _chainSize * sign * flip;
        Offset normal(ui.Tangent t) =>
            Offset(-t.vector.dy, t.vector.dx) * amplitude;
        final c1 = previous.position + normal(previous);
        final c2 = tangent.position + normal(tangent);
        result.cubicTo(
            c1.dx, c1.dy, c2.dx, c2.dy, tangent.position.dx, tangent.position.dy);
        previous = tangent;
        distance = next;
      }
      final end = metric.getTangentForOffset(metric.length)!.position;
      result.lineTo(end.dx, end.dy);
    }
  }
  return result;
}

/// A filled arrowhead triangle: apex at [tip], pointing along [direction].
@visibleForTesting
Path debugArrow(Offset tip, Offset direction,
    {double side = _arrowSide, double halfBase = _arrowHalfBase}) {
  final u = direction / direction.distance;
  final p = Offset(-u.dy, u.dx);
  final base = tip - u * side;
  return Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(base.dx + p.dx * halfBase, base.dy + p.dy * halfBase)
    ..lineTo(base.dx - p.dx * halfBase, base.dy - p.dy * halfBase)
    ..close();
}

// -------------------------------------------------------- scene painter --

class _ScenePainter {
  _ScenePainter(
    this.canvas,
    this.size,
    this.scene,
    this.palette, {
    required this.blueprint,
    required this.labelStyle,
  });

  final Canvas canvas;
  final Size size;
  final DebugScene scene;
  final DebugPalette palette;
  final bool blueprint;
  final DebugLabelStyle labelStyle;

  late final Paint _stroke = Paint()
    ..color = palette.line
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..isAntiAlias = true;

  late final Paint _fill = Paint()
    ..color = palette.line
    ..isAntiAlias = true;

  void paint() {
    if (blueprint) {
      canvas.drawRect(
          Offset.zero & size, Paint()..color = palette.background);
      for (final box in scene.boxes.where((b) => !b.virtual)) {
        _paintBoxSurface(box);
      }
    }
    for (final box in scene.boxes.where((b) => b.virtual)) {
      _paintVirtualBounds(box);
    }
    for (final guideline in scene.guidelines) {
      _paintGuideline(guideline);
    }
    for (final barrier in scene.barriers) {
      _paintBarrier(barrier);
    }
    for (final connection in scene.connections) {
      _paintConnection(connection);
    }
    for (final box in scene.boxes.where((b) => !b.virtual)) {
      _paintBaseline(box);
    }
  }

  // ------------------------------------------------------- connections --

  void _paintConnection(DebugConnection c) {
    switch (c.type) {
      case DebugConnectionType.normal:
        _paintLeg(c.sourcePoint, c.targetPoint, c.sourceEdge, arrow: true);
        _paintMarginIndicator(c);
      case DebugConnectionType.adjacent:
        final direction = _arrivalDirection(c.sourcePoint, c.targetPoint);
        canvas.drawPath(
          debugArrow(c.targetPoint, direction,
              side: _smallArrowSide, halfBase: _smallArrowHalfBase),
          _fill,
        );
      case DebugConnectionType.spring:
        _paintSpring(c);
      case DebugConnectionType.chain:
        final path =
            _legPath(c.sourcePoint, c.targetPoint, c.sourceEdge, inset: 0);
        canvas.drawPath(
          debugChainEffect(path),
          Paint()
            ..color = palette.line
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.bevel
            ..isAntiAlias = true,
        );
      case DebugConnectionType.center:
        _paintLeg(c.sourcePoint, c.targetPoint, c.sourceEdge, arrow: true);
        final (source2, target2) = c.centerDashedLine!;
        _paintLeg(source2, target2, _oppositeEdge(c.sourceEdge), arrow: true);
        canvas.drawPath(
          debugDashPath(
            Path()
              ..moveTo(c.targetPoint.dx, c.targetPoint.dy)
              ..lineTo(target2.dx, target2.dy),
            4,
            6,
          ),
          _stroke,
        );
        _paintMarginIndicator(c);
      case DebugConnectionType.baseline:
        final s = c.sourcePoint;
        final d = c.targetPoint;
        canvas.drawPath(
          Path()
            ..moveTo(s.dx, s.dy)
            ..cubicTo(s.dx, s.dy - 40, d.dx, d.dy + 40, d.dx, d.dy),
          _stroke,
        );
        canvas.drawPath(debugArrow(d, const Offset(0, 1)), _fill);
      case DebugConnectionType.circular:
        canvas.drawPath(
          debugDashPath(
            Path()
              ..moveTo(c.sourcePoint.dx, c.sourcePoint.dy)
              ..lineTo(c.targetPoint.dx, c.targetPoint.dy),
            4,
            4,
          ),
          _stroke,
        );
        final direction = _arrivalDirection(c.targetPoint, c.sourcePoint);
        canvas.drawPath(
          debugArrow(c.sourcePoint, direction,
              side: _smallArrowSide, halfBase: _smallArrowHalfBase),
          _fill,
        );
    }
  }

  /// The direction of travel when arriving at [to] from [from].
  Offset _arrivalDirection(Offset from, Offset to) {
    final delta = to - from;
    if (delta.distance < 0.01) return const Offset(1, 0);
    return delta / delta.distance;
  }

  Offset _outward(DebugEdge edge) => switch (edge) {
        DebugEdge.left => const Offset(-1, 0),
        DebugEdge.right => const Offset(1, 0),
        DebugEdge.top => const Offset(0, -1),
        DebugEdge.bottom => const Offset(0, 1),
        DebugEdge.baseline => const Offset(0, 1),
      };

  DebugEdge _oppositeEdge(DebugEdge edge) => switch (edge) {
        DebugEdge.left => DebugEdge.right,
        DebugEdge.right => DebugEdge.left,
        DebugEdge.top => DebugEdge.bottom,
        DebugEdge.bottom => DebugEdge.top,
        DebugEdge.baseline => DebugEdge.baseline,
      };

  /// The curved connection path from [source] to [target], ending [inset] px
  /// short of the target (the arrow occupies that inset).
  Path _legPath(Offset source, Offset target, DebugEdge sourceEdge,
      {required double inset}) {
    final path = Path()..moveTo(source.dx, source.dy);
    final arrival = _axisArrival(source, target);
    final end = target - arrival * inset;
    // Straight when the endpoints are aligned on the connection axis.
    final aligned = arrival.dx != 0
        ? (source.dy - target.dy).abs() < 1
        : (source.dx - target.dx).abs() < 1;
    if (aligned) {
      path.lineTo(end.dx, end.dy);
      return path;
    }
    final manhattan =
        (source.dx - target.dx).abs() + (source.dy - target.dy).abs();
    final k = math.min(_bezierMaxControl, manhattan);
    final c1 = source + _outward(sourceEdge) * k;
    final c2 = end - arrival * k;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
    return path;
  }

  /// Arrival direction along the dominant axis, matching Studio's
  /// per-direction control points.
  Offset _axisArrival(Offset source, Offset target) {
    final delta = target - source;
    if (delta.dx.abs() >= delta.dy.abs()) {
      return Offset(delta.dx.isNegative ? -1 : 1, 0);
    }
    return Offset(0, delta.dy.isNegative ? -1 : 1);
  }

  void _paintLeg(Offset source, Offset target, DebugEdge sourceEdge,
      {required bool arrow}) {
    final arrival = _axisArrival(source, target);
    canvas.drawPath(
      _legPath(source, target, sourceEdge, inset: arrow ? _arrowSide : 0),
      _stroke,
    );
    if (arrow) canvas.drawPath(debugArrow(target, arrival), _fill);
  }

  void _paintSpring(DebugConnection c) {
    final path = debugZigzag(c.sourcePoint, c.targetPoint);
    canvas.drawPath(c.dashed ? debugDashPath(path, 4, 4) : path, _stroke);
    // Perpendicular end cap at the destination: 9 tall to the parent, 5 to a
    // sibling.
    final arrival = _arrivalDirection(c.sourcePoint, c.targetPoint);
    final perpendicular = Offset(-arrival.dy, arrival.dx);
    final half = (c.targetIsParent ? 9 : 5) / 2;
    canvas.drawLine(
      c.targetPoint - perpendicular * half,
      c.targetPoint + perpendicular * half,
      _stroke,
    );
    _paintMarginIndicator(c);
  }

  /// The margin run: value label, end ticks, and the dashed destination-edge
  /// extension with 20 px overhang.
  void _paintMarginIndicator(DebugConnection c) {
    if (c.margin <= 0) return;
    final s = c.sourcePoint;
    final d = c.targetPoint;
    final run = (s - d).distance;
    if (run < 8) return;
    final u = (s - d) / run;
    final perpendicular = Offset(-u.dy, u.dx);

    // Ticks at both ends of the span.
    for (final end in [s, d]) {
      canvas.drawLine(
        end - perpendicular * _marginTickHalf,
        end + perpendicular * _marginTickHalf,
        _stroke,
      );
    }

    // Dashed destination-edge extension through the target point.
    canvas.drawPath(
      debugDashPath(
        Path()
          ..moveTo(d.dx - perpendicular.dx * _marginOverhang,
              d.dy - perpendicular.dy * _marginOverhang)
          ..lineTo(d.dx + perpendicular.dx * _marginOverhang,
              d.dy + perpendicular.dy * _marginOverhang),
        4,
        6,
      ),
      _stroke,
    );

    _label(
      '${c.margin.round()}',
      Offset.lerp(s, d, 0.5)! + perpendicular * 9,
      _marginFontSize,
      palette.text,
    );
  }

  // ------------------------------------------------------------- boxes --

  void _paintBoxSurface(DebugWidgetBox box) {
    final opacity = box.invisible ? 0.5 : 1.0;
    canvas.drawRect(
      box.rect,
      Paint()
        ..color = palette.componentFill
            .withValues(alpha: palette.componentFill.a * opacity),
    );
    canvas.drawRect(
      box.rect,
      Paint()
        ..color = palette.line.withValues(alpha: palette.line.a * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    _paintBoxLabel(box, opacity);
    if (box.baselineY != null) _paintBaselineMark(box);
  }

  void _paintBoxLabel(DebugWidgetBox box, double opacity) {
    if (labelStyle == DebugLabelStyle.none) return;
    if (box.rect.width < 40 || box.rect.height < 24) return;
    final id = box.idLabel;
    final type = box.typeLabel;
    final textColor =
        palette.text.withValues(alpha: palette.text.a * opacity);
    switch (labelStyle) {
      case DebugLabelStyle.id:
        _label(id ?? type ?? '', box.rect.center, _labelFontSize, textColor);
      case DebugLabelStyle.label:
        _label(type ?? id ?? '', box.rect.center, _labelFontSize, textColor);
      case DebugLabelStyle.both:
        final primary = id ?? type ?? '';
        final secondary = id != null ? type : null;
        if (secondary == null || box.rect.height < 44) {
          _label(primary, box.rect.center, _labelFontSize, textColor);
        } else {
          _label(primary, box.rect.center - const Offset(0, 8),
              _labelFontSize, textColor);
          _label(
            secondary,
            box.rect.center + const Offset(0, 9),
            _typeFontSize,
            textColor.withValues(alpha: textColor.a * 0.8),
          );
        }
      case DebugLabelStyle.none:
        break;
    }
  }

  void _paintBaselineMark(DebugWidgetBox box) {
    final inset = box.rect.width / 5;
    final y = box.baselineY!;
    canvas.drawLine(
      Offset(box.rect.left + inset, y),
      Offset(box.rect.right - inset, y),
      Paint()
        ..color = palette.anchor
        ..strokeWidth = 1,
    );
  }

  void _paintVirtualBounds(DebugWidgetBox box) {
    canvas.drawPath(
      debugDashPath(Path()..addRect(box.rect), 4, 6),
      _stroke,
    );
    if (blueprint) _paintBoxLabel(box, 1);
  }

  // Android Studio paints a draggable anchor circle on every edge (solid when
  // connected, hollow when open) because those circles are the interactive
  // handles you drag to create constraints. This overlay is read-only, so the
  // edge circles would be pure noise; only the baseline pill is kept, since it
  // marks where a baseline-aligned child sits rather than being a drag target.
  void _paintBaseline(DebugWidgetBox box) {
    if (box.baselineY == null ||
        !box.connectedEdges.contains(DebugEdge.baseline)) {
      return;
    }
    final inset = box.rect.width / 5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          box.rect.left + inset,
          box.baselineY! - 3,
          box.rect.right - inset,
          box.baselineY! + 3,
        ),
        const Radius.circular(3),
      ),
      Paint()
        ..color = palette.anchor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  // ----------------------------------------------------------- helpers --

  void _paintGuideline(DebugGuidelineInfo guideline) {
    final line = guideline.vertical
        ? (Path()
          ..moveTo(guideline.position, 0)
          ..lineTo(guideline.position, size.height))
        : (Path()
          ..moveTo(0, guideline.position)
          ..lineTo(size.width, guideline.position));
    canvas.drawPath(debugDashPath(line, 2, 2), _stroke);
    final center = guideline.vertical
        ? Offset(guideline.position, 16)
        : Offset(24, guideline.position);
    _chip(guideline.chipText, center);
  }

  void _chip(String text, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: palette.text, fontSize: _chipFontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(
      center: center,
      width: painter.width + 8,
      height: painter.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = palette.line.withValues(alpha: 0.25),
    );
    painter.paint(
        canvas, center - Offset(painter.width / 2, painter.height / 2));
    painter.dispose();
  }

  void _paintBarrier(DebugBarrierInfo barrier) {
    canvas.drawPath(
      debugDashPath(
        Path()
          ..moveTo(barrier.start.dx, barrier.start.dy)
          ..lineTo(barrier.end.dx, barrier.end.dy),
        2,
        2,
      ),
      _stroke,
    );
    // Gradient fade on the facing side.
    final from = Offset.lerp(barrier.start, barrier.end, 0.5)!;
    final to = from + barrier.fadeDirection * _barrierFade;
    final darkened = Color.lerp(palette.line, const Color(0xFF000000), 0.4)!;
    final fadeRect = Rect.fromPoints(
      barrier.start,
      barrier.end + barrier.fadeDirection * _barrierFade,
    );
    canvas.drawRect(
      fadeRect,
      Paint()
        ..shader = ui.Gradient.linear(
          from,
          to,
          [darkened.withAlpha(0x8F), darkened.withAlpha(0)],
        ),
    );
  }

  // -------------------------------------------------------------- text --

  void _label(String text, Offset center, double fontSize, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
        canvas, center - Offset(painter.width / 2, painter.height / 2));
    painter.dispose();
  }
}
