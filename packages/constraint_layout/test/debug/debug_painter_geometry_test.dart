// Unit tests for the path-effect helpers behind the debug painter: dash
// chopping, the spring zigzag, the chain-link effect, and arrowheads.

import 'dart:ui';

import 'package:constraint_layout/src/debug/debug_painter.dart';
import 'package:flutter_test/flutter_test.dart';

Path line(double length) => Path()
  ..moveTo(0, 0)
  ..lineTo(length, 0);

void main() {
  test('dashPath chops a 100px line into 10 dashes of 4 on / 6 off', () {
    final dashed = debugDashPath(line(100), 4, 6);
    final metrics = dashed.computeMetrics().toList();
    expect(metrics, hasLength(10));
    for (final m in metrics) {
      expect(m.length, closeTo(4, 0.01));
    }
  });

  test('dashPath keeps the trailing partial dash', () {
    final dashed = debugDashPath(line(12), 4, 6);
    final metrics = dashed.computeMetrics().toList();
    // 0-4 full, 10-12 partial.
    expect(metrics, hasLength(2));
    expect(metrics.last.length, closeTo(2, 0.01));
  });

  test('zigzag has amplitude +/-3 and starts/ends on the axis', () {
    final path = debugZigzag(Offset.zero, const Offset(60, 0));
    final bounds = path.getBounds();
    expect(bounds.top, closeTo(-3, 0.01));
    expect(bounds.bottom, closeTo(3, 0.01));
    expect(bounds.left, 0);
    expect(bounds.right, 60);
    final metric = path.computeMetrics().single;
    expect(metric.getTangentForOffset(0)!.position.dy, 0);
    expect(metric.getTangentForOffset(metric.length)!.position.dy,
        closeTo(0, 0.01));
  });

  test('zigzag degenerates to a straight line when too short', () {
    final path = debugZigzag(Offset.zero, const Offset(8, 0));
    expect(path.getBounds(), const Rect.fromLTRB(0, 0, 8, 0));
  });

  test('chain effect draws two mirrored passes within the link amplitude',
      () {
    final effect = debugChainEffect(line(90));
    final metrics = effect.computeMetrics().toList();
    expect(metrics, hasLength(2), reason: 'one contour per mirrored pass');
    final bounds = effect.getBounds();
    // Cubic control points sit at amplitude 2.5; the curve stays within it.
    expect(bounds.top, greaterThanOrEqualTo(-2.6));
    expect(bounds.bottom, lessThanOrEqualTo(2.6));
    expect(bounds.top, lessThan(-1));
    expect(bounds.bottom, greaterThan(1));
  });

  test('arrow is a closed triangle with spec dimensions', () {
    final arrow = debugArrow(const Offset(10, 0), const Offset(1, 0));
    expect(arrow.getBounds(), const Rect.fromLTRB(4, -5, 10, 5));
    final small = debugArrow(const Offset(10, 0), const Offset(1, 0),
        side: 4, halfBase: 3);
    expect(small.getBounds(), const Rect.fromLTRB(6, -3, 10, 3));
  });
}
