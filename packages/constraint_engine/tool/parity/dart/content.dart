// The content model of the parity corpora (FORMATS.md section 6), in Dart.
//
// A regular widget of a VR or T layout carries content (`ct N KIND W H BL`):
// what its view's onMeasure answers. VOpDriver's view measurer (Java, p0-java)
// and this file must agree exactly:
//
// - the spec form ([Content.measure]) answers MeasureSpecs, as a View's
//   onMeasure does; it is what the engine's ViewMeasurer.measureContent hook
//   (Phase 2) calls through [ContentMeasurer];
// - the box-constraint form ([Content.layout]) answers Flutter box
//   constraints, as ContentModelBox (p0-flutter) does; [TodayContentMeasurer]
//   uses it to mirror today's adapter measurer.
//
// Kinds (W, H and BL are ints; BL is what getBaseline() returns, -1 for none):
//
//   box W H    a view with a fixed natural size W x H
//   text W H   a text W wide on one line, H per line: at width w it takes
//              H * ceil(W / w) (H * 50 at w <= 0), as ViewProbe's Content
//   none       a bare View: View.getDefaultSize(0, spec) on each axis
import 'dart:math' as math;

import 'package:constraint_engine/constraint_engine.dart';

enum ContentKind { box, text, none }

/// Java's 32-bit int arithmetic on a Dart int.
int _jint32(int v) => v.toSigned(32);

class Content {
  const Content(this.kind, this.w, this.h, this.baseline);

  /// Parses the fields of a `ct N KIND W H BL` op (the op split on spaces).
  factory Content.parseOp(List<String> t) {
    if (t.length != 6 || t[0] != 'ct') {
      throw ArgumentError('ct op: ${t.join(' ')}');
    }
    final kind = switch (t[2]) {
      'box' => ContentKind.box,
      'text' => ContentKind.text,
      'none' => ContentKind.none,
      _ => throw ArgumentError('content kind ${t[2]}'),
    };
    return Content(kind, int.parse(t[3]), int.parse(t[4]), int.parse(t[5]));
  }

  final ContentKind kind;

  /// Natural width (box), text width (text); unused for none.
  final int w;

  /// Natural height (box), line height (text); unused for none.
  final int h;

  /// What the view's getBaseline() returns: -1 for none.
  final int baseline;

  /// The `ct` op that declares this content for widget [id].
  String toOp(String id) => 'ct $id ${kind.name} $w $h $baseline';

  /// The height a text takes at [width] (ViewProbe's Content.heightAt),
  /// with Java's int arithmetic.
  int textHeightAt(int width) {
    if (width <= 0) return _jint32(h * 50);
    return _jint32(h * ((w + width - 1) ~/ width));
  }

  /// `resolve(n, spec)` of FORMATS.md 6.1: EXACTLY(s) gives s, AT_MOST(s)
  /// gives min(n, s), UNSPECIFIED gives n.
  static int resolve(int n, int mode, int size) {
    if (mode == BasicMeasure.EXACTLY) return size;
    if (mode == BasicMeasure.AT_MOST) return math.min(n, size);
    return n;
  }

  /// View.getDefaultSize(0, spec): EXACTLY and AT_MOST give the spec size,
  /// UNSPECIFIED gives 0.
  static int defaultSize(int mode, int size) =>
      mode == BasicMeasure.UNSPECIFIED ? 0 : size;

  /// The spec form: what the view measures to under the specs
  /// ([wMode], [wSize]) x ([hMode], [hSize]) (modes are BasicMeasure's
  /// UNSPECIFIED, EXACTLY and AT_MOST, which are Android's MeasureSpec
  /// modes), and its baseline.
  ({int width, int height, int baseline}) measure(
    int wMode,
    int wSize,
    int hMode,
    int hSize,
  ) {
    switch (kind) {
      case ContentKind.box:
        return (
          width: resolve(w, wMode, wSize),
          height: resolve(h, hMode, hSize),
          baseline: baseline,
        );
      case ContentKind.text:
        final width = resolve(w, wMode, wSize);
        return (
          width: width,
          height: resolve(textHeightAt(width), hMode, hSize),
          baseline: baseline,
        );
      case ContentKind.none:
        return (
          width: defaultSize(wMode, wSize),
          height: defaultSize(hMode, hSize),
          baseline: -1,
        );
    }
  }

  /// The spec form on packed MeasureSpecs (mode in the top two bits).
  ({int width, int height, int baseline}) measureSpecs(
    int widthSpec,
    int heightSpec,
  ) => measure(
    specMode(widthSpec),
    specSize(widthSpec),
    specMode(heightSpec),
    specSize(heightSpec),
  );

  /// The box-constraint form (FORMATS.md 6.2): the size a ContentModelBox
  /// takes under BoxConstraints(minW..maxW, minH..maxH). Infinite maxima are
  /// allowed; minima are finite.
  ({double width, double height}) layout(
    double minW,
    double maxW,
    double minH,
    double maxH,
  ) {
    double clamp(num v, double lo, double hi) =>
        v < lo ? lo : (v > hi ? hi : v.toDouble());
    switch (kind) {
      case ContentKind.box:
        return (width: clamp(w, minW, maxW), height: clamp(h, minH, maxH));
      case ContentKind.text:
        final width = clamp(w, minW, maxW);
        assert(
          width == width.roundToDouble(),
          'the text model is defined on integer widths; the adapter '
          'measures under integer or infinite constraints',
        );
        return (
          width: width,
          height: clamp(textHeightAt(width.toInt()), minH, maxH),
        );
      case ContentKind.none:
        return (
          width: maxW.isFinite ? maxW : minW,
          height: maxH.isFinite ? maxH : minH,
        );
    }
  }

  /// The baseline in the box-constraint form: null for none.
  double? get boxBaseline =>
      kind == ContentKind.none || baseline == -1 ? null : baseline.toDouble();

  @override
  bool operator ==(Object other) =>
      other is Content &&
      other.kind == kind &&
      other.w == w &&
      other.h == h &&
      other.baseline == baseline;

  @override
  int get hashCode => Object.hash(kind, w, h, baseline);

  @override
  String toString() => 'Content(${kind.name} $w x $h, baseline $baseline)';
}

/// MeasureSpec helpers (Android's encoding, which BasicMeasure shares).
const int _modeMask = 0x3 << BasicMeasure.MODE_SHIFT;
int specMode(int spec) => spec & _modeMask;
int specSize(int spec) => spec & ~_modeMask;
int makeSpec(int size, int mode) => (size & ~_modeMask) | (mode & _modeMask);

/// The content table of one layout: the `ct` ops replayed so far.
final Expando<Content> _contentOf = Expando<Content>('content');

/// The content [w] was given by a `ct` op, or null.
Content? contentOf(ConstraintWidget w) => _contentOf[w];

/// Records [c] as [w]'s content (a `ct` op).
void setContent(ConstraintWidget w, Content c) => _contentOf[w] = c;

/// The Dart mirror of VOpDriver's content op: what the engine's
/// ViewMeasurer.measureContent(widget, widthSpec, heightSpec) hook answers
/// for a widget of a VR or T layout (Phase 2 plugs it into ViewHost).
class ContentMeasurer {
  const ContentMeasurer();

  /// The view's measured size and baseline under the packed specs. A widget
  /// without content measures as `none` (a bare View).
  ({int width, int height, int baseline}) measureContent(
    ConstraintWidget widget,
    int widthSpec,
    int heightSpec,
  ) {
    final c = contentOf(widget) ?? const Content(ContentKind.none, 0, 0, -1);
    return c.measureSpecs(widthSpec, heightSpec);
  }
}

/// A child's last layout in an engine pass: the constraints it was laid out
/// under and the size it took (the adapter's _MeasuredLayout).
typedef BoxLayout = ({
  double minW,
  double maxW,
  double minH,
  double maxH,
  double width,
  double height,
});

/// A Dart mirror of today's adapter measurer (`_FlutterMeasurer.measure`,
/// flutter_constraint_layout constraint_layout.dart at dc0dc6a, lines
/// 1782-1987), where each child is a ContentModelBox whose size is the
/// content's box-constraint form. It gives "today's numbers" for corpora
/// with content at the engine level.
///
/// [rootMaxWidth] and [rootMaxHeight] are the layout's incoming maxima
/// (infinite on an unbounded axis); [needsBaseline] are the widgets whose
/// baseline the adapter queries (both ends of every baseline link).
class TodayContentMeasurer implements Measurer {
  TodayContentMeasurer(
    this.needsBaseline, {
    required this.rootMaxWidth,
    required this.rootMaxHeight,
  });

  final Set<ConstraintWidget> needsBaseline;
  final double rootMaxWidth;
  final double rootMaxHeight;

  /// Every child laid out in the current pass, with its latest layout.
  final Map<ConstraintWidget, BoxLayout> laidOut = {};

  /// How many child layouts the measurer made (each a RenderBox.layout in
  /// the real adapter).
  int childLayouts = 0;

  void beginPass() => laidOut.clear();

  BoxLayout _layoutChild(
    Content c,
    double minW,
    double maxW,
    double minH,
    double maxH,
  ) {
    childLayouts++;
    final s = c.layout(minW, maxW, minH, maxH);
    return (
      minW: minW,
      maxW: maxW,
      minH: minH,
      maxH: maxH,
      width: s.width,
      height: s.height,
    );
  }

  @override
  void measure(ConstraintWidget widget, Measure measure) {
    if (widget is VirtualLayout) {
      var widthMode = BasicMeasure.UNSPECIFIED;
      var heightMode = BasicMeasure.UNSPECIFIED;
      var widthSize = 0;
      var heightSize = 0;
      final givenStrategy =
          measure.measureStrategy == Measure.TRY_GIVEN_DIMENSIONS ||
          measure.measureStrategy == Measure.USE_GIVEN_DIMENSIONS;
      if (widget.getHorizontalDimensionBehaviour() ==
          DimensionBehaviour.matchParent) {
        widthSize = widget.getParent()?.getWidth() ?? 0;
        widthMode = BasicMeasure.EXACTLY;
      } else if (measure.horizontalBehavior == DimensionBehaviour.fixed) {
        widthSize = measure.horizontalDimension;
        widthMode = BasicMeasure.EXACTLY;
      } else if (measure.horizontalBehavior ==
              DimensionBehaviour.matchConstraint &&
          givenStrategy) {
        widthSize = measure.horizontalDimension;
        widthMode = BasicMeasure.EXACTLY;
      } else if (rootMaxWidth.isFinite) {
        widthSize = rootMaxWidth.round();
        widthMode = BasicMeasure.AT_MOST;
      }
      if (widget.getVerticalDimensionBehaviour() ==
          DimensionBehaviour.matchParent) {
        heightSize = widget.getParent()?.getHeight() ?? 0;
        heightMode = BasicMeasure.EXACTLY;
      } else if (measure.verticalBehavior == DimensionBehaviour.fixed) {
        heightSize = measure.verticalDimension;
        heightMode = BasicMeasure.EXACTLY;
      } else if (measure.verticalBehavior ==
              DimensionBehaviour.matchConstraint &&
          givenStrategy) {
        heightSize = measure.verticalDimension;
        heightMode = BasicMeasure.EXACTLY;
      } else if (rootMaxHeight.isFinite) {
        heightSize = rootMaxHeight.round();
        heightMode = BasicMeasure.AT_MOST;
      }
      widget.measure(widthMode, widthSize, heightMode, heightSize);
      measure.measuredWidth = widget.getMeasuredWidth();
      measure.measuredHeight = widget.getMeasuredHeight();
      measure.measuredHasBaseline = false;
      measure.measuredBaseline = 0;
      widget.setMeasureRequested(false);
      return;
    }

    final c = contentOf(widget);
    if (c == null) {
      // Helpers (guidelines, barriers) have no RenderBox to measure.
      measure.measuredWidth = measure.horizontalDimension;
      measure.measuredHeight = measure.verticalDimension;
      measure.measuredHasBaseline = false;
      measure.measuredBaseline = 0;
      widget.setMeasureRequested(false);
      return;
    }

    final wrapW =
        measure.horizontalBehavior == DimensionBehaviour.wrapContent ||
        (measure.horizontalBehavior == DimensionBehaviour.matchConstraint &&
            widget.mMatchConstraintDefaultWidth ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
            !_measuresAtGivenSize(widget, measure, horizontal: true));
    final wrapH =
        measure.verticalBehavior == DimensionBehaviour.wrapContent ||
        (measure.verticalBehavior == DimensionBehaviour.matchConstraint &&
            widget.mMatchConstraintDefaultHeight ==
                ConstraintWidget.MATCH_CONSTRAINT_WRAP &&
            !_measuresAtGivenSize(widget, measure, horizontal: false));

    final double minW, maxW, minH, maxH;
    if (wrapW) {
      minW = 0;
      maxW = rootMaxWidth;
    } else {
      minW = maxW = math.max(0, measure.horizontalDimension).toDouble();
    }
    if (wrapH) {
      minH = 0;
      maxH = rootMaxHeight;
    } else {
      minH = maxH = math.max(0, measure.verticalDimension).toDouble();
    }

    final last = laidOut[widget];
    final givenStrategy =
        measure.measureStrategy == Measure.TRY_GIVEN_DIMENSIONS ||
        measure.measureStrategy == Measure.USE_GIVEN_DIMENSIONS;
    if (!givenStrategy ||
        last == null ||
        !_isSimilarLayout(last, minW, maxW, minH, maxH)) {
      laidOut[widget] = _layoutChild(c, minW, maxW, minH, maxH);
    }
    var measured = laidOut[widget]!;

    var measuredWidth = wrapW
        ? measured.width.round()
        : measure.horizontalDimension;
    var measuredHeight = wrapH
        ? measured.height.round()
        : measure.verticalDimension;

    final width = _limit(
      measuredWidth,
      widget.mMatchConstraintMinWidth,
      widget.mMatchConstraintMaxWidth,
    );
    final height = _limit(
      measuredHeight,
      widget.mMatchConstraintMinHeight,
      widget.mMatchConstraintMaxHeight,
    );
    if (width != measuredWidth || height != measuredHeight) {
      final clampW = width != measuredWidth;
      final clampH = height != measuredHeight;
      measured = _layoutChild(
        c,
        clampW ? width.toDouble() : minW,
        clampW ? width.toDouble() : maxW,
        clampH ? height.toDouble() : minH,
        clampH ? height.toDouble() : maxH,
      );
      laidOut[widget] = measured;
      measuredWidth = clampW
          ? width
          : wrapW
          ? measured.width.round()
          : measure.horizontalDimension;
      measuredHeight = clampH
          ? height
          : wrapH
          ? measured.height.round()
          : measure.verticalDimension;
    }
    measure.measuredWidth = measuredWidth;
    measure.measuredHeight = measuredHeight;

    measure.measuredHasBaseline = false;
    measure.measuredBaseline = 0;
    if (needsBaseline.contains(widget)) {
      final baseline = c.boxBaseline;
      if (baseline != null) {
        measure.measuredHasBaseline = true;
        measure.measuredBaseline = baseline.round();
      }
    }

    widget.setMeasureRequested(false);
  }

  bool _measuresAtGivenSize(
    ConstraintWidget widget,
    Measure measure, {
    required bool horizontal,
  }) {
    if (measure.measureStrategy == Measure.USE_GIVEN_DIMENSIONS) return true;
    if (measure.measureStrategy != Measure.TRY_GIVEN_DIMENSIONS) return false;
    final measured = laidOut[widget];
    final otherDimensionStable =
        measured != null &&
        (horizontal
            ? measured.height.round() == widget.getHeight()
            : measured.width.round() == widget.getWidth());
    return otherDimensionStable ||
        (horizontal
            ? widget.isResolvedHorizontally()
            : widget.isResolvedVertically());
  }

  static int _limit(int size, int min, int max) {
    var limited = size;
    if (min > 0 && limited < min) limited = min;
    if (max > 0 && limited > max) limited = max;
    return limited;
  }

  static bool _isSimilarLayout(
    BoxLayout last,
    double minW,
    double maxW,
    double minH,
    double maxH,
  ) {
    bool similar(
      double lastMin,
      double lastMax,
      double min,
      double max,
      double extent,
    ) =>
        (min == lastMin && max == lastMax) ||
        (min == max && max == extent.roundToDouble());
    return similar(last.minW, last.maxW, minW, maxW, last.width) &&
        similar(last.minH, last.maxH, minH, maxH, last.height);
  }

  @override
  void didMeasures() {}
}
