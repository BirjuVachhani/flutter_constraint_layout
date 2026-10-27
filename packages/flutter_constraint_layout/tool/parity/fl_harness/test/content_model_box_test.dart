// ContentModelBox follows FORMATS.md 6.2 exactly: its layout, dry layout,
// intrinsic sizes and baseline equal the shared Dart model (the file
// tool/parity/dart/content.dart of the engine, which setup.sh copies to
// shared/content.dart: the box-constraint form) and the spec form under the
// three MeasureSpec modes.
import 'package:cl_fl_harness/content_model_box.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/content.dart' as shared;

const _kinds = {
  ContentKind.box: shared.ContentKind.box,
  ContentKind.text: shared.ContentKind.text,
  ContentKind.none: shared.ContentKind.none,
};

void main() {
  final contents = <ContentModel>[
    for (final k in ContentKind.values)
      for (final (w, h, b) in [(0, 0, -1), (37, 20, 15), (300, 50, 0), (1000, 20, 16), (9, 13, -1)])
        ContentModel(k, w, h, b),
  ];
  final extents = <double>[0, 1, 7, 36, 37, 38, 120, 299, 300, 301, 999, 1000, 4000];

  test('box-constraint form equals the shared model on every constraint kind', () {
    var checked = 0;
    for (final c in contents) {
      final s = shared.Content(_kinds[c.kind]!, c.w, c.h, c.baseline);
      for (final a in extents) {
        for (final b in extents) {
          // EXACTLY x EXACTLY, AT_MOST x AT_MOST, UNSPECIFIED, and mixes.
          final cases = [
            (a, a, b, b),
            (0.0, a, 0.0, b),
            (0.0, double.infinity, 0.0, double.infinity),
            (a, a, 0.0, double.infinity),
            (0.0, a, b, b),
          ];
          for (final (minW, maxW, minH, maxH) in cases) {
            final mine = c.layout(minW, maxW, minH, maxH);
            final theirs = s.layout(minW, maxW, minH, maxH);
            expect(
              (mine.width, mine.height),
              (theirs.width, theirs.height),
              reason: '$c under $minW..$maxW x $minH..$maxH',
            );
            checked++;
          }
        }
        expect(c.boxBaseline, s.boxBaseline, reason: '$c baseline');
      }
    }
    expect(checked, greaterThan(4000), reason: 'the grid must be exercised');
  });

  testWidgets('RenderContentModelBox: layout, dry layout, baseline and intrinsics', (tester) async {
    for (final c in contents) {
      final ro = RenderContentModelBox(c);
      for (final w in extents) {
        for (final h in extents) {
          final cs = [
            BoxConstraints.tight(Size(w, h)),
            BoxConstraints.loose(Size(w, h)),
            const BoxConstraints(),
            BoxConstraints(minWidth: w, maxWidth: w),
          ];
          for (final con in cs) {
            final expected = c.layout(con.minWidth, con.maxWidth, con.minHeight, con.maxHeight);
            ro.layout(con, parentUsesSize: true);
            expect(ro.size, Size(expected.width, expected.height), reason: '$c $con');
            expect(ro.getDryLayout(con), ro.size, reason: 'dry $c $con');
            expect(
              ro.getDryBaseline(con, TextBaseline.alphabetic),
              c.boxBaseline,
              reason: 'dry baseline $c',
            );
          }
        }
        expect(ro.getMaxIntrinsicWidth(w), c.intrinsicWidth);
        expect(ro.getMinIntrinsicWidth(w), c.intrinsicWidth);
        expect(ro.getMaxIntrinsicHeight(w), c.intrinsicHeight(w));
      }
    }
  });

  testWidgets('text wraps by whole lines at the given width (ViewProbe content)', (tester) async {
    const text = ContentModel(ContentKind.text, 1000, 20, -1);
    // MATCH_PARENT x wrap at 400: ceil(1000 / 400) = 3 lines.
    expect(text.layout(400, 400, 0, double.infinity).height, 60);
    // Width 0: 50 lines, as ViewProbe's Content.
    expect(text.layout(0, 0, 0, double.infinity).height, 1000);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: SizedBox(width: 400, child: ContentModelBox(content: text))),
      ),
    );
    expect(tester.getSize(find.byType(ContentModelBox)), const Size(400, 60));
  });

  testWidgets('the real baseline is BL, and none for -1 or kind none', (tester) async {
    Future<double> topUnderBaseline(ContentModel c) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Baseline(
              baseline: 100,
              baselineType: TextBaseline.alphabetic,
              child: ContentModelBox(content: c),
            ),
          ),
        ),
      );
      return tester.getTopLeft(find.byType(ContentModelBox)).dy;
    }

    // With a baseline the child's top is 100 - BL; without one, a Baseline
    // widget aligns the child's bottom edge.
    expect(await topUnderBaseline(const ContentModel(ContentKind.text, 80, 20, 15)), 85);
    expect(await topUnderBaseline(const ContentModel(ContentKind.box, 80, 30, -1)), 70);
    // A baseline of 0 is a real baseline in Flutter (Android counts it as
    // none through setBaselineDistance; the adapter's engine does the same).
    expect(await topUnderBaseline(const ContentModel(ContentKind.box, 80, 30, 0)), 100);
    // A bare View takes a bounded maximum (here the 600 high test surface)
    // and has no baseline, whatever BL says.
    expect(await topUnderBaseline(const ContentModel(ContentKind.none, 80, 30, 12)), 100 - 600);
  });
}
