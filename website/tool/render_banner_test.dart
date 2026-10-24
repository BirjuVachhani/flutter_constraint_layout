// Renders web/banner.png, the 1920x1080 social-preview image (og:image,
// twitter:image, and the JSON-LD image in web/index.html), from the site's own
// wordmark, logo, and fonts, so it cannot fall out of step with the name. Run
// it from website/ after changing any of them:
//
//   flutter test tool/render_banner_test.dart
//
// It is a generator rather than a test, so it lives outside test/ and the
// suite never rewrites the image.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_constraint_layout_website/src/theme/tokens.dart';
import 'package:flutter_constraint_layout_website/src/widgets/brand.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _size = Size(1920, 1080);

// The logo tile's own fill (web/favicon.svg), so the mark sits flush on it.
const Color _background = Color(0xFF0C1117);
const Color _wordmarkColor = Color(0xFFF2F5F8);
const Color _subtitleColor = Color(0xFF8A97A6);

const String _subtitle = 'Constraint-based layout for Flutter';

Future<void> _loadFont(String family, String file) async {
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
  await loader.load();
}

void main() {
  testWidgets('render web/banner.png', (tester) async {
    await _loadFont(AppFonts.mono, 'assets/fonts/GeistMono-700.ttf');
    await _loadFont(AppFonts.sans, 'assets/fonts/Geist-400.ttf');
    tester.view
      ..physicalSize = _size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: boundary, child: const _Banner()),
    );
    await tester.runAsync(() async {
      final render = boundary.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await render.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('web/banner.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: _background,
        child: SizedBox.fromSize(
          size: _size,
          child: const Column(
            children: [
              SizedBox(height: 200),
              CustomPaint(size: Size.square(300), painter: _LogoPainter()),
              SizedBox(height: 68),
              Text(
                wordmark,
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontWeight: FontWeight.w700,
                  fontSize: 103,
                  height: 1,
                  color: _wordmarkColor,
                ),
              ),
              SizedBox(height: 16),
              Text(
                _subtitle,
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 45,
                  height: 1,
                  color: _subtitleColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// web/favicon.svg, drawn shape for shape at any size (its viewBox is 256).
class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  static const Color _blue = Color(0xFF1FBCFD);
  static const Color _green = Color(0xFF5ECC71);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 256);

    RRect box(double x, double r, double side) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x, x, side, side), Radius.circular(r));

    canvas.drawRRect(box(6, 58, 244), Paint()..color = _background);
    canvas.drawRRect(
      box(8, 56, 240),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = _blue.withValues(alpha: 0.35),
    );
    _dashedLine(canvas, const Offset(89, 128), const Offset(167, 128), _blue);
    _dashedLine(canvas, const Offset(128, 89), const Offset(128, 167), _green);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(48, 48, 82, 82),
        const Radius.circular(20),
      ),
      Paint()..color = _blue,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(126, 126, 82, 82),
        const Radius.circular(20),
      ),
      Paint()..color = _green,
    );
  }

  // stroke-dasharray="2 12" with round caps, as in the SVG.
  void _dashedLine(Canvas canvas, Offset from, Offset to, Color color) {
    final paint = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.5);
    final length = (to - from).distance;
    final step = (to - from) / length;
    for (var d = 0.0; d < length; d += 14) {
      canvas.drawLine(from + step * d, from + step * (d + 2).clamp(0, length), paint);
    }
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}
