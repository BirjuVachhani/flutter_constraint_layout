// Copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0
//
// The view layer (lib/src/view): MeasureSpec and the framework helpers,
// ViewMeasurer (ConstraintLayout.Measurer, CL 709-996) and ViewHost (the
// layout view's onMeasure, CL 1681-1981), against the parity oracle.
//
// Every layout below is an op list of the parity tooling
// (tool/parity/FORMATS.md 4), the exact input the Java oracle ran: the
// pinned VOpDriver v2 on its view path, levels 257 and 0, with -Dprobe
// -Dtranscript (the op lists below, under their ids, run through
// tool/parity/java/jrun.sh). Each case expects Java's level-0 geometry, its
// T0 request transcript and its P0 counters.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:constraint_engine/src/jfloat.dart' show parseFloat32;
import 'package:test/test.dart';

import 'support/echo_measurer.dart';

void main() {
  group('MeasureSpec', () {
    test('packs a mode and a size into 32 bits, as Java does', () {
      expect(MeasureSpec.EXACTLY, BasicMeasure.EXACTLY);
      expect(MeasureSpec.AT_MOST, BasicMeasure.AT_MOST);
      expect(MeasureSpec.UNSPECIFIED, BasicMeasure.UNSPECIFIED);
      final spec = MeasureSpec.makeMeasureSpec(400, MeasureSpec.AT_MOST);
      expect(spec, 0x80000190);
      expect(MeasureSpec.getMode(spec), MeasureSpec.AT_MOST);
      expect(MeasureSpec.getSize(spec), 400);
      // Java's AT_MOST spec is a negative int; its bits read the same.
      expect(MeasureSpec.getMode(-2147483248), MeasureSpec.AT_MOST);
      expect(MeasureSpec.getSize(-2147483248), 400);
    });

    test('a negative size corrupts the spec exactly as in Java', () {
      // (-1 & ~MODE_MASK) | EXACTLY == 0x7FFFFFFF: size 2^30 - 1.
      final spec = MeasureSpec.makeMeasureSpec(-1, MeasureSpec.EXACTLY);
      expect(spec, 0x7FFFFFFF);
      expect(MeasureSpec.getMode(spec), MeasureSpec.EXACTLY);
      expect(MeasureSpec.getSize(spec), 0x3FFFFFFF);
      // -6 & 0x3FFFFFFF == 0x3FFFFFFA, and the mode bits come from the mode.
      expect(
        MeasureSpec.makeMeasureSpec(-6, MeasureSpec.UNSPECIFIED),
        0x3FFFFFFA,
      );
    });

    test('toShortString is the transcript form', () {
      expect(
        MeasureSpec.toShortString(
          MeasureSpec.makeMeasureSpec(400, MeasureSpec.EXACTLY),
        ),
        'E400',
      );
      expect(
        MeasureSpec.toShortString(
          MeasureSpec.makeMeasureSpec(800, MeasureSpec.AT_MOST),
        ),
        'A800',
      );
      expect(MeasureSpec.toShortString(0), 'U0');
      expect(MeasureSpec.toShortString(0xC0000005), '?5');
    });

    test(
      'getChildMeasureSpec follows AOSP ViewGroup for every parent mode',
      () {
        const mp = BasicMeasure.MATCH_PARENT;
        const wc = BasicMeasure.WRAP_CONTENT;
        String child(String parent, int padding, int dimension) {
          final mode = switch (parent[0]) {
            'E' => MeasureSpec.EXACTLY,
            'A' => MeasureSpec.AT_MOST,
            _ => MeasureSpec.UNSPECIFIED,
          };
          final spec = MeasureSpec.makeMeasureSpec(
            int.parse(parent.substring(1)),
            mode,
          );
          return MeasureSpec.toShortString(
            MeasureSpec.getChildMeasureSpec(spec, padding, dimension),
          );
        }

        // Parent EXACTLY: a size is EXACTLY, MATCH_PARENT EXACTLY at the
        // space left, WRAP_CONTENT AT_MOST at the space left.
        expect(child('E400', 40, 120), 'E120');
        expect(child('E400', 40, 0), 'E0');
        expect(child('E400', 40, mp), 'E360');
        expect(child('E400', 40, wc), 'A360');
        // Parent AT_MOST: MATCH_PARENT and WRAP_CONTENT are AT_MOST.
        expect(child('A300', 10, 500), 'E500');
        expect(child('A300', 10, mp), 'A290');
        expect(child('A300', 10, wc), 'A290');
        // Parent UNSPECIFIED: MATCH_PARENT and WRAP_CONTENT are UNSPECIFIED,
        // with the space left as the size (targetSdk 23 and later).
        expect(child('U250', 50, 30), 'E30');
        expect(child('U250', 50, mp), 'U200');
        expect(child('U250', 50, wc), 'U200');
        expect(child('U0', 0, wc), 'U0');
        // Padding beyond the parent's size leaves 0.
        expect(child('E40', 60, mp), 'E0');
        expect(child('A40', 60, wc), 'A0');
        expect(child('U40', 60, wc), 'U0');
        // Any other child dimension falls through Java's switch.
        expect(child('E400', 0, -3), 'U0');
        expect(child('A400', 0, -7), 'U0');
        expect(child('U400', 0, -3), 'U0');
        // A corrupted parent mode matches no case.
        expect(
          MeasureSpec.toShortString(
            MeasureSpec.getChildMeasureSpec(0xC0000190, 0, mp),
          ),
          'U0',
        );
      },
    );

    test('resolveSizeAndState follows AOSP View', () {
      final exactly = MeasureSpec.makeMeasureSpec(300, MeasureSpec.EXACTLY);
      final atMost = MeasureSpec.makeMeasureSpec(300, MeasureSpec.AT_MOST);
      final unspecified = MeasureSpec.makeMeasureSpec(
        300,
        MeasureSpec.UNSPECIFIED,
      );
      expect(MeasureSpec.resolveSizeAndState(540, exactly, 0), 300);
      expect(MeasureSpec.resolveSizeAndState(120, exactly, 0), 300);
      expect(
        MeasureSpec.resolveSizeAndState(540, atMost, 0),
        300 | MeasureSpec.MEASURED_STATE_TOO_SMALL,
      );
      expect(MeasureSpec.resolveSizeAndState(300, atMost, 0), 300);
      expect(MeasureSpec.resolveSizeAndState(120, atMost, 0), 120);
      expect(MeasureSpec.resolveSizeAndState(540, unspecified, 0), 540);
      // The state bits of the child state are kept, the others dropped.
      expect(
        MeasureSpec.resolveSizeAndState(120, unspecified, 0x01000005),
        120 | 0x01000000,
      );
      expect(
        MeasureSpec.resolveSizeAndState(120, unspecified, 0xFF000000),
        0xFF000078,
      );
    });
  });

  group('ViewHost at level 0 against VOpDriver J0', () {
    for (final p in _probes) {
      test('${p.id}: ${p.what}', () {
        final layout = _Layout.replay(p.ops);
        layout.measurer.transcript = StringBuffer();
        layout.measure();
        expect(layout.geometry(), p.geometry, reason: 'J0 geometry');
        expect(
          layout.measurer.transcript.toString(),
          p.transcript == '-' ? '' : p.transcript,
          reason: 'J0 request transcript (T0)',
        );
        expect(layout.measurer.measureCalls, p.measures, reason: 'P0 meas');
        expect(layout.measurer.cacheHits, 0, reason: 'P0 hits');
        expect(
          layout.root.isWidthMeasuredTooSmall(),
          p.tooSmallWidth,
          reason: 'P0 ts (width)',
        );
        expect(layout.root.isHeightMeasuredTooSmall(), false);
      });
    }
  });

  group('ViewHost', () {
    test('toosmall: the AT_MOST width is measured too small', () {
      final layout = _Layout.replay(_probe('probe:toosmall').ops);
      layout.measure();
      final host = layout.host;
      // resolveSizeAndState(260 + 40, A300) is 300; CL 1754-1756 then adds
      // the container's too-small state.
      expect(
        host.measuredWidthAndState,
        300 | MeasureSpec.MEASURED_STATE_TOO_SMALL,
      );
      expect(host.measuredHeightAndState, 800);
      expect(host.getMeasuredWidth(), 300);
      expect(host.lastMeasureWidth, host.measuredWidthAndState);
      expect(host.lastMeasureHeight, 800);
      // The padding offsets the children and is not part of the container.
      expect(layout.root.mPaddingLeft, 10);
      expect(layout.root.mPaddingTop, 20);
      expect(layout.root.getWidth(), 260);
      expect(layout.root.getHeight(), 740);
      expect(layout.measurer.paddingWidth, 40);
      expect(layout.measurer.paddingHeight, 60);
      expect(layout.measurer.paddingTop, 20);
      expect(layout.measurer.paddingBottom, 40);
    });

    test('pad: the max width and height bound the measured size', () {
      final layout = _Layout.replay(_probe('p2c:pad').ops);
      layout.measure();
      // EXACTLY 400 resolves to 400, then min(maxWidth 380, 400).
      expect(layout.host.measuredWidthAndState, 380);
      // UNSPECIFIED resolves to 63 + 60, then min(maxHeight 100, 123).
      expect(layout.host.measuredHeightAndState, 100);
      // setSelfDimensionBehaviour: EXACTLY gives min(380 - 40, 400 - 40).
      expect(layout.root.getWidth(), 340);
      expect(layout.root.getMaxWidth(), 340);
      expect(layout.root.getMaxHeight(), 40);
    });

    test('negative padding counts as 0', () {
      final layout = _Layout.replay(_probe('probe:C2').ops);
      layout.host
        ..paddingLeft = -5
        ..paddingTop = -6
        ..paddingRight = -7
        ..paddingBottom = -8;
      layout.measure();
      expect(layout.geometry(), _probe('probe:C2').geometry);
      expect(layout.measurer.paddingWidth, 0);
      expect(layout.measurer.paddingHeight, 0);
    });

    test('measuring again gives the same frames at the default level (the '
        'dirty path)', () {
      for (final id in ['probe:C1', 'probe:ratio', 'p2c:wrapmc', 'p2c:flow']) {
        final layout = _Layout.replay(_probe(id).ops);
        layout.measurer.transcript = StringBuffer();
        layout.measure();
        final first = layout.geometry();
        final transcript = layout.measurer.transcript.toString();
        layout.measure();
        expect(layout.geometry(), first, reason: id);
        expect(layout.geometry(), _probe(id).geometry, reason: id);
        expect(layout.measurer.transcript.toString(), transcript, reason: id);
      }
    });

    test('guidelines and barriers are GONE whatever the caller set', () {
      final layout = _Layout.replay(_probe('probe:gonebar').ops);
      final bar = layout.by['bar']!;
      final guideline = Guideline()
        ..setDebugName('gl')
        ..setOrientation(Guideline.vertical)
        ..setGuideBegin(30);
      layout.root.add(guideline);
      bar.setVisibility(ConstraintWidget.VISIBLE);
      guideline.setVisibility(ConstraintWidget.VISIBLE);
      layout.measure();
      expect(bar.getVisibility(), ConstraintWidget.GONE);
      expect(guideline.getVisibility(), ConstraintWidget.GONE);
      expect(guideline.getWidth(), 0);
      expect(guideline.getHeight(), 0);
      // K's left link into the GONE barrier takes its gone margin, 7.
      expect(layout.by['K']!.getX(), 7);
    });

    test('a baseline link marks both views as needing their baseline', () {
      final layout = _Layout.replay(_probe('p2c:base0b').ops);
      final p = layout.by['P']!, q = layout.by['Q']!, s = layout.by['S']!;
      expect(layout.measurer.needsBaselineOf(p), isFalse);
      layout.measure();
      expect(layout.measurer.needsBaselineOf(p), isTrue);
      expect(layout.measurer.needsBaselineOf(q), isTrue);
      expect(layout.measurer.needsBaselineOf(s), isTrue);
      // A baseline of 0 is a baseline for the measurer, but not for the
      // widget (setBaselineDistance: mHasBaseline = distance > 0).
      expect(p.getBaselineDistance(), 0);
      expect(p.hasBaseline(), isFalse);
      // A view without a baseline reports -1, and the widget keeps it.
      expect(q.getBaselineDistance(), -1);
      expect(q.hasBaseline(), isFalse);
      expect(s.getBaselineDistance(), 12);
      expect(s.hasBaseline(), isTrue);
      // The flags are sticky, as layout params keep them.
      q.mBaseline.reset();
      s.mBaseline.reset();
      layout.measure();
      expect(layout.measurer.needsBaselineOf(p), isTrue);
      expect(layout.measurer.needsBaselineOf(q), isTrue);
    });

    test('the host asserts that it still measures through its measurer', () {
      final layout = _Layout.replay(_probe('probe:C2').ops);
      layout.root.setMeasurer(_ContentMeasurer());
      expect(layout.measure, throwsA(isA<AssertionError>()));
    });
  });

  group('EchoMeasurer (test support)', () {
    // VOpDriver's Echo, the oracle's core-path measurer.
    test('echoes the stored size on a wrap axis, the request elsewhere', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 400, 800);
      final w = ConstraintWidget.sizeNamed('w', 70, 30)
        ..setVisibility(ConstraintWidget.GONE)
        ..setBaselineDistance(12);
      root.add(w);
      final m = Measure()
        ..horizontalBehavior = DimensionBehaviour.wrapContent
        ..verticalBehavior = DimensionBehaviour.fixed
        ..horizontalDimension = 5
        ..verticalDimension = 9;
      const EchoMeasurer().measure(w, m);
      // The raw field, not getWidth() (0 for a GONE widget).
      expect(m.measuredWidth, 70);
      expect(m.measuredHeight, 9);
      expect(m.measuredBaseline, 12);
      expect(m.measuredHasBaseline, isTrue);
      expect(w.mMeasureRequested, isFalse);
    });

    test('bounds a match-constraint axis by its own min and max', () {
      final w = ConstraintWidget.sizeNamed('w', 70, 30)
        ..setHorizontalDimensionBehaviour(DimensionBehaviour.matchConstraint)
        ..setHorizontalMatchStyle(
          ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
          80,
          120,
          1,
        )
        ..setVerticalDimensionBehaviour(DimensionBehaviour.matchConstraint)
        ..setVerticalMatchStyle(
          ConstraintWidget.MATCH_CONSTRAINT_SPREAD,
          0,
          20,
          1,
        );
      final m = Measure()
        ..horizontalBehavior = DimensionBehaviour.fixed
        ..verticalBehavior = DimensionBehaviour.wrapContent
        ..horizontalDimension = 50;
      const EchoMeasurer().measure(w, m);
      expect(m.measuredWidth, 80, reason: 'raised to the min');
      expect(m.measuredHeight, 20, reason: 'the raw 30, lowered to the max');
      expect(m.measuredHasBaseline, isFalse);
      expect(m.measuredBaseline, 0);
    });
  });

  group('ViewMeasurer', () {
    test('keeps each view\'s state between measures', () {
      final layout = _Layout.replay(_probe('probe:C1').ops);
      final b = layout.by['B']!;
      final measurer = layout.measurer;
      expect(measurer.measuredWidthOf(b), 0);
      expect(measurer.measuredHeightOf(b), 0);
      expect(measurer.baselineOf(b), -1);
      layout.measure();
      expect(measurer.measuredWidthOf(b), 100);
      expect(measurer.measuredHeightOf(b), 40);
      expect(measurer.baselineOf(b), 30);
      expect(measurer.needsBaselineOf(b), isTrue);
      measurer.forgetView(b);
      expect(measurer.measuredWidthOf(b), 0);
      expect(measurer.measuredHeightOf(b), 0);
      expect(measurer.baselineOf(b), -1);
      expect(measurer.needsBaselineOf(b), isFalse);
    });

    test('measured sizes keep MEASURED_SIZE_MASK, as View does', () {
      final layout = _Layout.replay(_probe('probe:C2').ops);
      final a = layout.by['A']!;
      // A view that reports a size with state bits.
      layout.measurer.contents[a] = const _Content.fixed(
        0x01000000 | 77,
        0x01000000 | 33,
        5,
      );
      layout.measurer.transcript = StringBuffer();
      layout.measure();
      expect(layout.measurer.measuredWidthOf(a), 77);
      expect(layout.measurer.measuredHeightOf(a), 33);
      expect(
        layout.measurer.transcript.toString(),
        'M:A:0:PW:0,0:E400/A800:77,33,5,11',
      );
    });

    test('records nothing without a transcript, and counts', () {
      final layout = _Layout.replay(_probe('p2c:flow').ops);
      expect(layout.measurer.transcript, isNull);
      layout.measure();
      expect(layout.measurer.transcript, isNull);
      expect(layout.measurer.measureCalls, 5);
      expect(layout.geometry(), _probe('p2c:flow').geometry);
      layout.measurer.beginMeasure();
      expect(layout.measurer.measureCalls, 0);
      expect(layout.measurer.cacheHits, 0);
    });

    test('CACHE_MEASURES at 257 answers a similar request from the widget', () {
      // probe:C3 at 257 (Java's T257): Direct measures D with a new Measure,
      //   P:D:0:FW:0,0:E0/A800:0,50,-1,01
      // and the re-measure loop's request is then a cache hit,
      //   R:D:1:MM:0,50:c:0,50,-1,00
      // Here the measurer alone answers the same two requests.
      final layout = _Layout.replay(_probe('probe:C3').ops);
      final d = layout.by['D']!;
      final measurer = layout.measurer
        ..optimizationLevel = Optimizer.OPTIMIZATION_STANDARD
        ..captureLayoutInfo(
          MeasureSpec.makeMeasureSpec(400, MeasureSpec.EXACTLY),
          MeasureSpec.makeMeasureSpec(800, MeasureSpec.EXACTLY),
          0,
          0,
          0,
          0,
        );
      final direct = Measure()
        ..horizontalBehavior = DimensionBehaviour.fixed
        ..verticalBehavior = DimensionBehaviour.wrapContent
        ..horizontalDimension = 0
        ..verticalDimension = 0
        ..measureStrategy = Measure.SELF_DIMENSIONS;
      measurer.measure(d, direct);
      expect(direct.measuredWidth, 0);
      expect(direct.measuredHeight, 50);
      expect(direct.measuredBaseline, -1);
      expect(direct.measuredHasBaseline, isFalse);
      expect(direct.measuredNeedsSolverPass, isTrue);
      expect(measurer.contentCalls, 1);
      expect(d.isMeasureRequested(), isFalse);
      // What ConstraintWidgetContainer.measureWidget then writes.
      d
        ..setWidth(direct.measuredWidth)
        ..setHeight(direct.measuredHeight)
        ..setHasBaseline(direct.measuredHasBaseline)
        ..setBaselineDistance(direct.measuredBaseline);

      final again = Measure()
        ..horizontalBehavior = DimensionBehaviour.matchConstraint
        ..verticalBehavior = DimensionBehaviour.matchConstraint
        ..horizontalDimension = 0
        ..verticalDimension = 50
        ..measureStrategy = Measure.TRY_GIVEN_DIMENSIONS;
      measurer.transcript = StringBuffer();
      measurer.measure(d, again);
      expect(measurer.cacheHits, 1);
      expect(measurer.contentCalls, 1, reason: 'no view measure');
      expect(again.measuredWidth, 0);
      expect(again.measuredHeight, 50);
      expect(again.measuredBaseline, -1);
      expect(measurer.transcript.toString(), endsWith(':MM:0,50:c:0,50,-1,00'));

      // Without CACHE_MEASURES the same request measures the view again.
      measurer.optimizationLevel = Optimizer.OPTIMIZATION_DIRECT;
      measurer.transcript = StringBuffer();
      measurer.measure(d, again);
      expect(measurer.cacheHits, 1);
      expect(measurer.contentCalls, 2);
      expect(
        measurer.transcript.toString(),
        endsWith(':MM:0,50:E0/E50:0,50,-1,00'),
      );
    });

    test('CACHE_MEASURES needs the view to be smaller than the container', () {
      final layout = _Layout.replay(_probe('probe:C3').ops);
      final d = layout.by['D']!;
      final measurer = layout.measurer
        ..optimizationLevel = Optimizer.OPTIMIZATION_STANDARD
        ..captureLayoutInfo(
          MeasureSpec.makeMeasureSpec(400, MeasureSpec.EXACTLY),
          MeasureSpec.makeMeasureSpec(800, MeasureSpec.EXACTLY),
          0,
          0,
          0,
          0,
        );
      Measure request(int strategy) => Measure()
        ..horizontalBehavior = DimensionBehaviour.fixed
        ..verticalBehavior = DimensionBehaviour.fixed
        ..horizontalDimension = 400
        ..verticalDimension = 50
        ..measureStrategy = strategy;
      final first = request(Measure.SELF_DIMENSIONS);
      measurer.measure(d, first);
      d
        ..setWidth(first.measuredWidth)
        ..setHeight(first.measuredHeight)
        ..setBaselineDistance(first.measuredBaseline);
      expect(d.getWidth(), 400);
      // The view is as wide as the container (400), so no cache hit.
      measurer.measure(d, request(Measure.SELF_DIMENSIONS));
      expect(measurer.cacheHits, 0);
      expect(measurer.contentCalls, 2);
    });

    test('a GONE widget is answered 0 x 0 without a view measure', () {
      final layout = _Layout.replay(_probe('p2c:gonestale').ops);
      final g = layout.by['G']!;
      final m = Measure()
        ..horizontalBehavior = DimensionBehaviour.fixed
        ..verticalBehavior = DimensionBehaviour.fixed
        ..horizontalDimension = 50
        ..verticalDimension = 50
        ..measuredWidth = 9
        ..measuredHeight = 9
        ..measuredBaseline = 9
        ..measuredHasBaseline = true
        ..measuredNeedsSolverPass = true;
      layout.measurer.measure(g, m);
      expect(m.measuredWidth, 0);
      expect(m.measuredHeight, 0);
      expect(m.measuredBaseline, 0);
      // Left as the caller set them (CL 714-719).
      expect(m.measuredHasBaseline, isTrue);
      expect(m.measuredNeedsSolverPass, isTrue);
      expect(layout.measurer.contentCalls, 0);
    });

    test('a widget without a parent is not measured', () {
      final orphan = ConstraintWidget.sizeNamed('orphan', 10, 10);
      final measurer = _ContentMeasurer();
      final m = Measure()
        ..horizontalBehavior = DimensionBehaviour.fixed
        ..verticalBehavior = DimensionBehaviour.fixed
        ..horizontalDimension = 10
        ..verticalDimension = 10
        ..measuredWidth = 3;
      measurer.transcript = StringBuffer();
      measurer.measure(orphan, m);
      expect(m.measuredWidth, 3);
      expect(measurer.contentCalls, 0);
      expect(measurer.transcript.toString(), 'X:orphan:0:FF:10,10:n:3,0,0,00');
    });

    test('the ratio branch runs only without DIRECT (CL 942-952)', () {
      // The ratio probe's first request at level 0:
      //   M:Q:0:FM:100,0:E100/A800+E100/E56:100,56,-1,01
      // At 257 the same request is answered from the wrap measure alone.
      for (final level in [0, Optimizer.OPTIMIZATION_DIRECT]) {
        final layout = _Layout.replay(_probe('probe:ratio').ops);
        final q = layout.by['Q']!;
        final measurer = layout.measurer
          ..optimizationLevel = level
          ..captureLayoutInfo(
            MeasureSpec.makeMeasureSpec(400, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(800, MeasureSpec.EXACTLY),
            0,
            0,
            0,
            0,
          );
        final m = Measure()
          ..horizontalBehavior = DimensionBehaviour.fixed
          ..verticalBehavior = DimensionBehaviour.matchConstraint
          ..horizontalDimension = 100
          ..verticalDimension = 0
          ..measureStrategy = Measure.SELF_DIMENSIONS;
        measurer.transcript = StringBuffer();
        measurer.measure(q, m);
        // (int) (0.5f + 100 / 1.7777778f) == 56; the box is 10 high.
        expect(m.measuredHeight, level == 0 ? 56 : 10);
        expect(
          measurer.transcript.toString(),
          endsWith(
            level == 0
                ? ':FM:100,0:E100/A800+E100/E56:100,56,-1,01'
                : ':FM:100,0:E100/A800:100,10,-1,01',
          ),
        );
      }
    });
  });
}

// ---------------------------------------------------------------------------
// The oracle's probes: op list and VOpDriver's level-0 results
// ---------------------------------------------------------------------------

typedef _Probe = ({
  String id,
  String what,
  String ops,
  String geometry,
  String transcript,
  int measures,
  bool tooSmallWidth,
});

_Probe _probe(String id) => _probes.firstWhere((p) => p.id == id);

const List<_Probe> _probes = [
  (
    id: 'probe:C3',
    what: 'match x match with one link per axis is skipped, then 0 x 0',
    ops:
        'R 400 800;w D 0 0;add D;hb D M;vb D M;c D L root L 10;'
        'c D T root T 10;ct D box 300 50 -1;cspec E 400 E 800',
    geometry: 'root 400 x 800 | D: (10, 10) 0 x 0',
    transcript: 'R:D:1:MM:0,0:E0/E0:0,0,-1,00',
    measures: 1,
    tooSmallWidth: false,
  ),
  (
    id: 'probe:C2',
    what: 'MATCH_PARENT is measured EXACTLY at the parent minus margins',
    ops:
        'R 400 800;w A 0 0;add A;hb A P;vb A W;c A T root T 10;'
        'ct A text 1000 20 -1;cspec E 400 E 800',
    geometry: 'root 400 x 800 | A: (0, 10) 400 x 60',
    transcript: 'M:A:0:PW:0,0:E400/A800:400,60,-1,01',
    measures: 1,
    tooSmallWidth: false,
  ),
  (
    id: 'probe:C1',
    what: 'the fixed baseline pair aligns C on B',
    ops:
        'R 400 800;w B 100 40;w C 100 20;add B;add C;hbl B 1;hbl C 1;'
        'ct B box 100 40 30;ct C box 100 20 15;c B L root L 0;'
        'c B T root T 100;c C L B R 0;c C S B S 0;cspec E 400 E 800',
    geometry: 'root 400 x 800 | B: (0, 100) 100 x 40 | C: (100, 115) 100 x 20',
    transcript:
        'M:B:0:FF:100,40:E100/E40:100,40,30,11 '
        'M:C:0:FF:100,20:E100/E20:100,20,15,11',
    measures: 2,
    tooSmallWidth: false,
  ),
  (
    id: 'probe:ratio',
    what: 'the view measurer\'s ratio branch, then RATIO_RESOLVED as FIXED',
    ops:
        'R 400 800;w Q 100 0;add Q;hb Q F;vb Q M;ra Q 1.7777778 -1;'
        'c Q L root L 0;c Q T root T 0;ct Q box 100 10 -1;cspec E 400 E 800',
    geometry: 'root 400 x 800 | Q: (0, 0) 100 x 56',
    transcript:
        'M:Q:0:FM:100,0:E100/A800+E100/E56:100,56,-1,01 '
        'R:Q:1:FF:100,56:E100/E56:100,56,-1,00',
    measures: 2,
    tooSmallWidth: false,
  ),
  (
    id: 'probe:gonebar',
    what: 'GONE widgets, a GONE barrier and a gone margin into it',
    ops:
        'R 400 800;w G 50 50;add G;v G 8;b bar;add bar;bt bar 1;ref bar G;'
        'w K 30 30;add K;c K L bar R 5;gm K L 7;c G L root L 20;'
        'ct G box 50 50 -1;ct K box 30 30 -1;cspec E 400 E 800',
    geometry:
        'root 400 x 800 | G: gone, 0 x 0 | bar: (0, 0) 0 x 0 | '
        'K: (7, 0) 30 x 30',
    transcript: 'M:G:0:FF:0,0:g:0,0,0,00 M:K:0:FF:30,30:E30/E30:30,30,-1,00',
    measures: 2,
    tooSmallWidth: false,
  ),
  (
    id: 'probe:toosmall',
    what: 'AT_MOST with padding, measured too small',
    ops:
        'R 300 800;w F 500 20;add F;hb F F;vb F F;c F L root L 0;'
        'ct F box 500 20 -1;cspec A 300 E 800;cpad 10 20 30 40',
    geometry: 'root 300 x 800 | F: (10, 20) 500 x 20',
    transcript: 'M:F:0:FF:500,20:E500/E20:500,20,-1,00',
    measures: 1,
    tooSmallWidth: true,
  ),
  (
    id: 'p2c:base0b',
    what: 'baselines 0 and -1',
    ops:
        'R 400 800;w P 100 40;add P;w Q 100 20;add Q;w S 100 20;add S;'
        'hbl P 1;hbl Q 1;hbl S 1;ct P box 100 40 0;ct Q box 100 20 -1;'
        'ct S box 100 20 12;c P L root L 0;c P T root T 50;c Q L P R 0;'
        'c Q S P S 0;c S L Q R 0;c S S Q S 5;cspec E 400 E 800',
    geometry:
        'root 400 x 800 | P: (0, 50) 100 x 40 | Q: (100, 0) 100 x 20 | '
        'S: (200, 0) 100 x 20',
    transcript:
        'M:P:0:FF:100,40:E100/E40:100,40,0,10 '
        'M:Q:0:FF:100,20:E100/E20:100,20,-1,10 '
        'M:S:0:FF:100,20:E100/E20:100,20,12,11',
    measures: 3,
    tooSmallWidth: false,
  ),
  (
    id: 'p2c:base0',
    what: 'baselines 0 and -1 without baseline links',
    ops:
        'R 400 800;w P 100 40;add P;w Q 100 20;add Q;w S 100 20;add S;'
        'ct P box 100 40 0;ct Q box 100 20 -1;ct S box 100 20 12;'
        'c P L root L 0;c P T root T 50;c Q L P R 0;c Q S P S 0;'
        'c S L Q R 0;c S S Q S 5;cspec E 400 E 800',
    geometry:
        'root 400 x 800 | P: (0, 50) 100 x 40 | Q: (100, 0) 100 x 20 | '
        'S: (200, 0) 100 x 20',
    transcript:
        'M:P:0:FF:100,40:E100/E40:100,40,0,10 '
        'M:Q:0:FF:100,20:E100/E20:100,20,-1,00 '
        'M:S:0:FF:100,20:E100/E20:100,20,12,11',
    measures: 3,
    tooSmallWidth: false,
  ),
  (
    id: 'p2c:gonestale',
    what: 'a GONE answer keeps the stale measuredHasBaseline',
    ops:
        'R 400 800;w B 100 40;add B;w G 50 50;add G;v G 8;'
        'ct B box 100 40 30;ct G box 50 50 -1;c B L root L 0;'
        'c B T root T 0;cspec E 400 E 800',
    geometry: 'root 400 x 800 | B: (0, 0) 100 x 40 | G: gone, 0 x 0',
    transcript: 'M:B:0:FF:100,40:E100/E40:100,40,30,11 M:G:0:FF:0,0:g:0,0,0,10',
    measures: 2,
    tooSmallWidth: false,
  ),
  (
    id: 'p2c:pad',
    what: 'padding, margins, UNSPECIFIED and the max size',
    ops:
        'R 400 800;w A 0 0;add A;hb A P;vb A W;c A L root L 7;'
        'c A R root R 9;c A T root T 3;ct A text 1000 20 -1;'
        'cspec E 400 U 0;cpad 10 20 30 40;cmax 380 100',
    geometry: 'root 380 x 100 | A: (17, 23) 324 x 60',
    transcript: 'M:A:0:PW:0,0:E344/U0:344,60,-1,01',
    measures: 1,
    tooSmallWidth: false,
  ),
  (
    id: 'p2c:atmostfit',
    what: 'AT_MOST content that fits, with padding',
    ops:
        'R 400 800;w F 100 50;add F;c F L root L 5;c F T root T 6;'
        'ct F box 100 50 -1;cspec A 300 A 300;cpad 1 2 3 4',
    geometry: 'root 109 x 62 | F: (6, 8) 100 x 50',
    transcript: 'M:F:0:FF:100,50:E100/E50:100,50,-1,00',
    measures: 1,
    tooSmallWidth: false,
  ),
  (
    id: 'p2c:cmin',
    what: 'UNSPECIFIED with the min size',
    ops:
        'R 400 800;w F 50 50;add F;c F L root L 0;c F R root R 0;'
        'c F T root T 0;ct F box 50 50 -1;cspec U 0 U 0;cmin 200 100',
    geometry: 'root 200 x 100 | F: (75, 0) 50 x 50',
    transcript: 'M:F:0:FF:50,50:E50/E50:50,50,-1,00',
    measures: 1,
    tooSmallWidth: false,
  ),
  (
    id: 'p2c:empty',
    what: 'no child: the min size, and nothing measured',
    ops: 'R 400 800;cspec A 300 U 0;cmin 50 60',
    geometry: 'root 50 x 60',
    transcript: '-',
    measures: 0,
    tooSmallWidth: false,
  ),
  (
    id: 'p2c:wrapmc',
    what: 'a wrap-default match constraint re-measured TRY_GIVEN',
    ops:
        'R 300 800;w T 0 0;add T;hb T M;hm T 1 0 0 1.0;vb T W;'
        'c T L root L 10;c T R root R 10;c T T root T 0;'
        'ct T text 500 20 -1;cspec E 300 E 800',
    geometry: 'root 300 x 800 | T: (10, 0) 280 x 40',
    transcript:
        'M:T:0:MW:0,0:A300/A800:300,40,-1,01 '
        'R:T:1:MW:280,40:E280/A800:280,40,-1,00',
    measures: 2,
    tooSmallWidth: false,
  ),
  (
    id: 'p2c:minmax',
    what: 'the match max clamps the measure, which is then measured again',
    ops:
        'R 400 800;w M 0 0;add M;hb M M;hm M 1 0 150 1.0;vb M W;'
        'c M L root L 0;c M R root R 0;c M T root T 0;'
        'ct M text 400 20 -1;cspec E 400 E 800',
    geometry: 'root 400 x 800 | M: (125, 0) 150 x 60',
    transcript:
        'M:M:0:MW:0,0:A400/A800+E150/A800:150,60,-1,01 '
        'R:M:1:MW:150,60:E150/A800:150,60,-1,00',
    measures: 2,
    tooSmallWidth: false,
  ),
  (
    id: 'p2c:mpmargin',
    what: 'MATCH_PARENT on both axes, under AT_MOST, with margins',
    ops:
        'R 400 800;w A 0 0;add A;hb A P;vb A P;c A L root L 11;'
        'c A R root R 13;c A T root T 17;c A B root B 19;'
        'ct A text 900 20 9;cspec A 400 E 800;cpad 2 3 5 7',
    geometry: 'root 400 x 800 | A: (13, 20) 369 x 754',
    transcript: 'M:A:0:PP:0,0:A369/E754:369,754,9,11',
    measures: 1,
    tooSmallWidth: false,
  ),
  (
    id: 'p2c:flow',
    what: 'a Flow measures its members inside its own request',
    ops:
        'R 1133 896;rtl;fl flow;add flow;w m0 0 0;ct m0 box 62 45 -1;'
        'add m0;w m1 0 0;ct m1 box 52 28 -1;add m1;w m2 0 0;'
        'ct m2 text 72 16 11;add m2;w below 0 0;ct below text 249 21 16;'
        'add below;fo flow 0;fwm flow 1;fhs flow 2;fvs flow 1;fhb flow 0.1;'
        'fvb flow 0.6;fha flow 1;fva flow 3;fhg flow 0;fvg flow 8;'
        'fme flow 2;fpad flow 13 9 0 5;ref flow m0;ref flow m1;ref flow m2;'
        'frtl flow 1;hb flow W;vb flow W;c flow R root R 16;'
        'c flow L root L 7;c flow T root T 4;hb m0 W;vb m0 W;hb m1 W;'
        'vb m1 W;hb m2 W;vb m2 W;hb below W;vb below W;'
        'c below L root L 5;c below T flow B 2;rtl;fixw;fixh;cw 1133;'
        'ch 896;adeps',
    geometry:
        'root 1133 x 896 | flow: (499, 4) 127 x 83 | '
        'm0: (564, 13) 62 x 45 | m1: (512, 22) 52 x 28 | '
        'm2: (549, 66) 72 x 16 | below: (5, 89) 249 x 21',
    transcript:
        'F:m0:0:WW:0,0:A1133/A896:62,45,-1,01 '
        'F:m1:0:WW:0,0:A1133/A896:52,28,-1,01 '
        'F:m2:0:WW:0,0:A1133/A896:72,16,11,11 '
        'M:flow:0:WW:0,0:A1133/A896:127,83,-1,01 '
        'M:below:0:WW:0,0:A1133/A896:249,21,16,11',
    measures: 5,
    tooSmallWidth: false,
  ),
];

// ---------------------------------------------------------------------------
// The content model (FORMATS.md 6.1) and an op-list replayer
// ---------------------------------------------------------------------------

/// What a child view's onMeasure answers: a box of a natural size, a text
/// [w] wide on one line and [h] per line, or a bare View.
class _Content {
  const _Content.box(this.w, this.h, this.baseline) : kind = 'box';
  const _Content.text(this.w, this.h, this.baseline) : kind = 'text';
  const _Content.none() : kind = 'none', w = 0, h = 0, baseline = -1;

  /// A view that always reports exactly ([w], [h]), whatever the specs.
  const _Content.fixed(this.w, this.h, this.baseline) : kind = 'fixed';

  final String kind;
  final int w;
  final int h;
  final int baseline;

  static int _resolve(int n, int spec) => switch (MeasureSpec.getMode(spec)) {
    MeasureSpec.EXACTLY => MeasureSpec.getSize(spec),
    MeasureSpec.AT_MOST =>
      n < MeasureSpec.getSize(spec) ? n : MeasureSpec.getSize(spec),
    _ => n,
  };

  ({int width, int height, int baseline}) measure(int ws, int hs) {
    switch (kind) {
      case 'box':
        return (
          width: _resolve(w, ws),
          height: _resolve(h, hs),
          baseline: baseline,
        );
      case 'text':
        final width = _resolve(w, ws);
        final natural = width <= 0 ? h * 50 : h * ((w + width - 1) ~/ width);
        return (
          width: width,
          height: _resolve(natural, hs),
          baseline: baseline,
        );
      case 'fixed':
        return (width: w, height: h, baseline: baseline);
      default:
        int bare(int spec) =>
            MeasureSpec.getMode(spec) == MeasureSpec.UNSPECIFIED
            ? 0
            : MeasureSpec.getSize(spec);
        return (width: bare(ws), height: bare(hs), baseline: -1);
    }
  }
}

class _ContentMeasurer extends ViewMeasurer {
  final Map<ConstraintWidget, _Content> contents = Map.identity();

  /// How many view measures [measureContent] answered.
  int contentCalls = 0;

  @override
  ({int width, int height, int baseline}) measureContent(
    ConstraintWidget widget,
    int widthSpec,
    int heightSpec,
  ) {
    contentCalls++;
    final content = contents[widget] ?? const _Content.none();
    return content.measure(widthSpec, heightSpec);
  }
}

/// One layout built from an op list, as VOpDriver builds it, with its host.
class _Layout {
  _Layout._(this.root, this.host, this.measurer);

  final ConstraintWidgetContainer root;
  final ViewHost host;
  final _ContentMeasurer measurer;
  final Map<String, ConstraintWidget> by = {};
  int? _widthSpec;
  int? _heightSpec;

  static ConstraintAnchorType _anchor(String s) => switch (s) {
    'L' => ConstraintAnchorType.left,
    'R' => ConstraintAnchorType.right,
    'T' => ConstraintAnchorType.top,
    'B' => ConstraintAnchorType.bottom,
    'S' => ConstraintAnchorType.baseline,
    'C' => ConstraintAnchorType.center,
    'CX' => ConstraintAnchorType.centerX,
    'CY' => ConstraintAnchorType.centerY,
    _ => throw ArgumentError('anchor $s'),
  };

  static DimensionBehaviour _behaviour(String s) => switch (s) {
    'F' => DimensionBehaviour.fixed,
    'W' => DimensionBehaviour.wrapContent,
    'M' => DimensionBehaviour.matchConstraint,
    'P' => DimensionBehaviour.matchParent,
    _ => throw ArgumentError('behaviour $s'),
  };

  static int _mode(String s) => switch (s) {
    'E' => MeasureSpec.EXACTLY,
    'A' => MeasureSpec.AT_MOST,
    'U' => MeasureSpec.UNSPECIFIED,
    _ => throw ArgumentError('spec mode $s'),
  };

  factory _Layout.replay(String ops) {
    final list = ops.split(';');
    final r = list.first.split(' ');
    final root = ConstraintWidgetContainer.rect(
      0,
      0,
      int.parse(r[1]),
      int.parse(r[2]),
    )..setDebugName('root');
    final measurer = _ContentMeasurer();
    final host = ViewHost(root, measurer)..optimizationLevel = 0;
    final layout = _Layout._(root, host, measurer);
    final by = layout.by..['root'] = root;
    ConstraintWidget n(String name) =>
        by[name] ?? (throw ArgumentError('unknown $name'));
    Flow flow(String name) => n(name) as Flow;
    for (final op in list.skip(1)) {
      final t = op.split(' ');
      int i(int k) => int.parse(t[k]);
      switch (t[0]) {
        case 'rtl':
          root.setRtl(true);
        case 'ltr':
          root.setRtl(false);
        case 'fixw':
          root.setHorizontalDimensionBehaviour(DimensionBehaviour.fixed);
        case 'fixh':
          root.setVerticalDimensionBehaviour(DimensionBehaviour.fixed);
        case 'cw':
          root.setWidth(i(1));
        case 'ch':
          root.setHeight(i(1));
        case 'w':
          by[t[1]] = ConstraintWidget.sizeNamed(t[1], i(2), i(3));
        case 'b':
          by[t[1]] = Barrier.named(t[1]);
        case 'fl':
          by[t[1]] = Flow()..setDebugName(t[1]);
        case 'add':
          root.add(n(t[1]));
        case 'bt':
          (n(t[1]) as Barrier).setBarrierType(i(2));
        case 'ref':
          (n(t[1]) as HelperWidget).add(n(t[2]));
        case 'c':
          n(t[1]).connect(_anchor(t[2]), n(t[3]), _anchor(t[4]), i(5));
        case 'gm':
          n(t[1]).setGoneMargin(_anchor(t[2]), i(3));
        case 'hb':
          n(t[1]).setHorizontalDimensionBehaviour(_behaviour(t[2]));
        case 'vb':
          n(t[1]).setVerticalDimensionBehaviour(_behaviour(t[2]));
        case 'hm':
          n(t[1]).setHorizontalMatchStyle(i(2), i(3), i(4), parseFloat32(t[5]));
        case 'ra':
          n(t[1]).setDimensionRatio(parseFloat32(t[2]), i(3));
        case 'v':
          n(t[1]).setVisibility(i(2));
        case 'hbl':
          n(t[1]).setHasBaseline(t[2] == '1');
        case 'ct':
          measurer.contents[n(t[1])] = switch (t[2]) {
            'box' => _Content.box(i(3), i(4), i(5)),
            'text' => _Content.text(i(3), i(4), i(5)),
            _ => const _Content.none(),
          };
        case 'fo':
          flow(t[1]).setOrientation(i(2));
        case 'fwm':
          flow(t[1]).setWrapMode(i(2));
        case 'fhs':
          flow(t[1]).setHorizontalStyle(i(2));
        case 'fvs':
          flow(t[1]).setVerticalStyle(i(2));
        case 'fhb':
          flow(t[1]).setHorizontalBias(parseFloat32(t[2]));
        case 'fvb':
          flow(t[1]).setVerticalBias(parseFloat32(t[2]));
        case 'fha':
          flow(t[1]).setHorizontalAlign(i(2));
        case 'fva':
          flow(t[1]).setVerticalAlign(i(2));
        case 'fhg':
          flow(t[1]).setHorizontalGap(i(2));
        case 'fvg':
          flow(t[1]).setVerticalGap(i(2));
        case 'fme':
          flow(t[1]).setMaxElementsWrap(i(2));
        case 'fpad':
          flow(t[1])
            ..setPaddingLeft(i(2))
            ..setPaddingTop(i(3))
            ..setPaddingRight(i(4))
            ..setPaddingBottom(i(5));
        case 'frtl':
          flow(t[1]).applyRtl(t[2] == '1');
        case 'adeps':
          // ViewHost rebuilds Android's dependents itself.
          break;
        case 'cspec':
          layout._widthSpec = MeasureSpec.makeMeasureSpec(i(2), _mode(t[1]));
          layout._heightSpec = MeasureSpec.makeMeasureSpec(i(4), _mode(t[3]));
        case 'cpad':
          host
            ..paddingLeft = i(1)
            ..paddingTop = i(2)
            ..paddingRight = i(3)
            ..paddingBottom = i(4);
        case 'cmin':
          host
            ..minWidth = i(1)
            ..minHeight = i(2);
        case 'cmax':
          host
            ..maxWidth = i(1)
            ..maxHeight = i(2);
        default:
          throw ArgumentError('op $op');
      }
    }
    return layout;
  }

  /// One onMeasure with the `cspec` specs, else VOpDriver's defaults: a
  /// FIXED axis is EXACTLY at the container's size, a WRAP axis U(0).
  void measure() {
    final ws =
        _widthSpec ??
        (root.getHorizontalDimensionBehaviour() ==
                DimensionBehaviour.wrapContent
            ? MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
            : MeasureSpec.makeMeasureSpec(
                root.getWidth(),
                MeasureSpec.EXACTLY,
              ));
    final hs =
        _heightSpec ??
        (root.getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent
            ? MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
            : MeasureSpec.makeMeasureSpec(
                root.getHeight(),
                MeasureSpec.EXACTLY,
              ));
    host.measure(ws, hs);
  }

  /// VOpDriver's geometry on the view path (FORMATS.md 2 and 8.2): the
  /// layout's measured size, then each child's frame as onLayout places it;
  /// a GONE child prints its size only, unless it is a guideline or a helper.
  String geometry() {
    final sb = StringBuffer(
      'root ${host.getMeasuredWidth()} x ${host.getMeasuredHeight()}',
    );
    for (final w in root.getChildren()) {
      final placed = w is Guideline || w is HelperWidget;
      if (w.getVisibility() == ConstraintWidget.GONE && !placed) {
        sb.write(
          ' | ${w.getDebugName()}: gone, ${w.getWidth()} x ${w.getHeight()}',
        );
      } else {
        sb.write(
          ' | ${w.getDebugName()}: (${w.getX()}, ${w.getY()}) '
          '${w.getWidth()} x ${w.getHeight()}',
        );
      }
    }
    return sb.toString();
  }
}
