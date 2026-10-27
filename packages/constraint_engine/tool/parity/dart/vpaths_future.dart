// The vfuzz paths of the upstream pipeline (FORMATS.md sections 5, 17 and 18):
//
//   core0    Phase 2: OpDriver's core path at level 0. The container is
//            measured through ConstraintWidgetContainer.measure(0, ...) with
//            the echo measurer (an oracle-local copy of the engine's
//            test/support/echo_measurer.dart, VOpDriver's `Echo`), as
//            OpDriver measures: setOptimizationLevel(0), then
//            measure(0, wrap ? AT_MOST : EXACTLY, width, ..., 0, 0, 0, 0)
//            with the wrap flags read from the container at that moment.
//            Geometry with BL's core rule, even for op lists with ct ops
//            (T2core).
//   view0    Phase 2: VOpDriver's view path at level 0 (FORMATS.md 8.6). One
//            ViewHost per layout with a ViewMeasurer whose measureContent is
//            content.dart's ContentMeasurer; padding, min and max from
//            `cpad`, `cmin`, `cmax`; the specs from `cspec`, else E(width)
//            for a FIXED axis and U(0) for a WRAP axis, read from the
//            container at each measure (VOpDriver.specsOf). ViewHost itself
//            makes guidelines and barriers GONE, marks the VirtualLayout
//            members, rebuilds the dependents and takes mNeedsBaseline from
//            the baseline links; `hbl` ops still set hasBaseline, as in
//            Java. Geometry with the view rule and the layout view's
//            measured size.
//   core257, view257  Phase 3: the same two paths at OPTIMIZATION_STANDARD
//            (257), where pass 0 runs Direct and the post-Direct measures.
//   core<level>, view<level>  Phase 5a (FORMATS.md 20): the same two paths at
//            any optimization level from 0 to 2047, e.g. the GRAPH levels
//            core64, core321 and view321, where BasicMeasure.solverMeasure
//            runs the dependency graph first when its rules allow (no chain,
//            no VirtualLayout, EXACTLY specs or GRAPH_WRAP). The container's
//            and the host's optimization level is the path's level.
//
// Every path replays the op list (an L op is one measure of the path), runs
// the implicit final measure, and reports OpDriver's geometry with a status
// from vpaths.dart's `guarded`: ok-printed only when the final measure
// printed, as VOpDriver reports it. With [recordTranscript] set, the view
// paths keep the request transcript of each layout's last measure in
// [lastTranscript] (VOpDriver's T field; vfuzz --transcript writes it to a side
// file). With [recordDirect] set (a build with -Dcl.trace=true), every path
// keeps the Direct dump of the last measure in [lastDirect] (VOpDriver's D
// field; vfuzz --direct). With [measureTwice] set, the view paths measure
// each layout a second time after re-applying its FIXED sizes, and
// [lastTwice] says whether that changed the status or the geometry (vfuzz
// --twice).
import 'package:constraint_engine/constraint_engine.dart';
import 'package:constraint_engine/src/debug/solver_trace.dart'
    show SolverTrace, kSolverTrace;

import 'content.dart';
import 'ops.dart';
import 'vpaths.dart' show LayoutPath, PathResult, geometry, guarded;

/// Set by vfuzz --transcript: the view paths record the measure-request
/// transcript (FORMATS.md 8.5) of each layout's last measure.
bool recordTranscript = false;

/// The transcript of the last layout a view path ran with
/// [recordTranscript] set (entries joined by one space, empty for none), or
/// null when nothing was recorded.
String? lastTranscript;

final RegExp _pathName = RegExp(r'^(core|view)(0|[1-9][0-9]{0,3})$');

/// The kind (`core` or `view`) and the optimization level of the path [name]
/// (`core<level>` or `view<level>`, level 0 to 2047 written without leading
/// zeros), or null when [name] is not such a path.
(String, int)? pathKindAndLevel(String name) {
  final m = _pathName.firstMatch(name);
  if (m == null) return null;
  final level = int.parse(m.group(2)!);
  return level <= 2047 ? (m.group(1)!, level) : null;
}

/// Whether [name] is a view path (`view<level>`).
bool isViewPath(String name) => pathKindAndLevel(name)?.$1 == 'view';

/// The level of [name]'s transcript (the `T<level>` label), or null for a
/// path that records none (a core path).
int? transcriptLevel(String name) {
  final p = pathKindAndLevel(name);
  return p != null && p.$1 == 'view' ? p.$2 : null;
}

/// The level of [name]'s Direct dump (the `D<level>` label), or null for an
/// unknown path. A level without the DIRECT bit (0, 64) never dumps, so its
/// dump is always `D<level> -`.
int? directLevel(String name) => pathKindAndLevel(name)?.$2;

/// The path [name], or null for an unknown one.
LayoutPath? futurePath(String name) {
  final p = pathKindAndLevel(name);
  if (p == null) return null;
  final (kind, level) = p;
  return kind == 'core'
      ? (ops) => runCore(ops, level: level)
      : (ops) => runView(ops, level: level);
}

/// Why a path is not available.
String futureReason(String name) =>
    '$name is not a path of the upstream pipeline (core<level> or '
    'view<level>, level 0 to 2047)';

// ---------------------------------------------------------------------------
// The Direct dump (FORMATS.md 8.4 and 18): DirectProbe.dumpDirect, in Dart
// ---------------------------------------------------------------------------

/// Set by vfuzz --direct: every path installs [SolverTrace.directSink] and
/// keeps the Direct dump of each layout's last measure in [lastDirect].
bool recordDirect = false;

/// The Direct dump of the last measure of the last layout a path ran with
/// [recordDirect] set (FORMATS.md 8.4 entries joined by one space), or null
/// when that measure made no dump (a level without DIRECT, or an error before
/// the dump point).
String? lastDirect;

/// Whether this build can dump: the engine calls the sink only when compiled
/// with -Dcl.trace=true.
bool get canDumpDirect => kSolverTrace;

String _fv(ConstraintAnchor a) =>
    a.hasFinalValue() ? '${a.getFinalValue()}' : '_';

/// DirectProbe.dumpDirect's text for [root]: per child in `mChildren` order,
/// `name:g<orientation>:<final value>` for a guideline,
/// `name:b<type>:<rh><rv>:<L>,<T>,<R>,<B>` for a barrier, and
/// `name:<rh><rv>:<L>,<T>,<R>,<B>,<S>:<mWidth>x<mHeight>:<baseline><+|->:<m|-><H|-><V|->`
/// for any other widget (Flows included). An anchor prints its final value or
/// `_`; a null name prints `null`, as Java's StringBuilder does.
String directDumpOf(ConstraintWidgetContainer root) {
  final sb = StringBuffer();
  for (final w in root.getChildren()) {
    if (sb.isNotEmpty) sb.write(' ');
    sb
      ..write(w.getDebugName() ?? 'null')
      ..write(':');
    if (w is Guideline) {
      sb
        ..write('g')
        ..write(w.getOrientation())
        ..write(':')
        ..write(_fv(w.getGuidelineAnchor()));
    } else if (w is Barrier) {
      sb
        ..write('b')
        ..write(w.getBarrierType())
        ..write(':')
        ..write(w.isResolvedHorizontally() ? 'h' : '-')
        ..write(w.isResolvedVertically() ? 'v' : '-')
        ..write(':')
        ..write(_fv(w.mLeft))
        ..write(',')
        ..write(_fv(w.mTop))
        ..write(',')
        ..write(_fv(w.mRight))
        ..write(',')
        ..write(_fv(w.mBottom));
    } else {
      sb
        ..write(w.isResolvedHorizontally() ? 'h' : '-')
        ..write(w.isResolvedVertically() ? 'v' : '-')
        ..write(':')
        ..write(_fv(w.mLeft))
        ..write(',')
        ..write(_fv(w.mTop))
        ..write(',')
        ..write(_fv(w.mRight))
        ..write(',')
        ..write(_fv(w.mBottom))
        ..write(',')
        ..write(_fv(w.mBaseline))
        ..write(':')
        ..write(w.mWidth)
        ..write('x')
        ..write(w.mHeight)
        ..write(':')
        ..write(w.getBaselineDistance())
        ..write(w.hasBaseline() ? '+' : '-')
        ..write(':')
        ..write(w.isMeasureRequested() ? 'm' : '-')
        ..write(w.isHorizontalSolvingPassDone() ? 'H' : '-')
        ..write(w.isVerticalSolvingPassDone() ? 'V' : '-');
    }
  }
  return sb.toString();
}

/// Installs the engine's Direct dump sink when [recordDirect] is set. The
/// engine hands only the root container to it, at pass 0's first solver
/// iteration (FORMATS.md 18).
void _installDirectSink() {
  if (!recordDirect) return;
  SolverTrace.directSink = (container) {
    lastDirect = directDumpOf(container);
  };
}

// ---------------------------------------------------------------------------
// --twice (FORMATS.md 18)
// ---------------------------------------------------------------------------

/// Set by vfuzz --twice: the view paths measure each layout once more after
/// the final measure (see [runView]).
bool measureTwice = false;

/// Set by vfuzz --twice-links (with [measureTwice]): before the second
/// measure, the own links of every VirtualLayout child are also put back to
/// what the op list left before the final measure, as Android connects a
/// Flow's layout params again on a dirty measure.
bool twiceRestoreLinks = false;

/// After a view path ran with [measureTwice] set: null when the second
/// measure was not run (the first one threw), else whether its status or
/// geometry differ from the first measure's. [lastTwiceDetail] holds both
/// results when they differ.
bool? lastTwice;

/// The class and the two results when [lastTwice] is true:
/// `class \t first \t second`. The class is `vl-links` when the own links of
/// a VirtualLayout child (its anchors' targets, margins and gone margins)
/// after the first measure differ from what the op list left before it, and
/// `other` otherwise.
String? lastTwiceDetail;

/// The own links of every VirtualLayout child of [root], to put back with
/// [_restoreLinks]: per anchor, its target, margin and gone margin.
List<(ConstraintAnchor, ConstraintAnchor?, int, int)> _saveLinks(
  ConstraintWidgetContainer root,
) => [
  for (final c in root.getChildren())
    if (c is VirtualLayout)
      for (final a in c.mAnchors) (a, a.mTarget, a.mMargin, a.mGoneMargin),
];

/// Puts back the links [_saveLinks] saved. The dependents are ViewHost's to
/// rebuild before the next measure.
void _restoreLinks(
  List<(ConstraintAnchor, ConstraintAnchor?, int, int)> saved,
) {
  for (final (a, target, margin, goneMargin) in saved) {
    a.mTarget = target;
    a.mMargin = margin;
    a.mGoneMargin = goneMargin;
  }
}

/// The own links of every VirtualLayout child of [root]: per anchor, its
/// target, margin and gone margin.
String _virtualLayoutLinks(ConstraintWidgetContainer root) {
  final sb = StringBuffer();
  for (final c in root.getChildren()) {
    if (c is! VirtualLayout) continue;
    sb.write('${c.getDebugName()}:');
    for (final a in c.mAnchors) {
      final t = a.mTarget;
      final target = t == null
          ? '-'
          : '${identityHashCode(t.mOwner)}.${t.mType.name}';
      sb.write(' ${a.mType.name}>$target/${a.mMargin}/${a.mGoneMargin}');
    }
    sb.write(';');
  }
  return sb.toString();
}

/// The FIXED sizes the op list [ops] configured, by widget name: the `w` op's
/// width and height, replaced by every later `sw` and `sh` op.
Map<String, (int?, int?)> configuredSizes(List<String> ops) {
  final sizes = <String, (int?, int?)>{};
  for (final op in ops) {
    final t = op.split(' ');
    switch (t[0]) {
      case 'w':
        sizes[t[1]] = (int.parse(t[2]), int.parse(t[3]));
      case 'sw':
        final s = sizes[t[1]];
        sizes[t[1]] = (int.parse(t[2]), s?.$2);
      case 'sh':
        final s = sizes[t[1]];
        sizes[t[1]] = (s?.$1, int.parse(t[2]));
    }
  }
  return sizes;
}

/// Re-applies to every child of [root] with a FIXED axis the size the op list
/// configured for it, as Android's setChildrenConstraints re-applies
/// LayoutParams before a measure and as ViewHost leaves to its caller
/// (resetMeasureState keeps FIXED sizes, which setFrame may have widened).
void reapplyFixedSizes(
  ConstraintWidgetContainer root,
  Map<String, (int?, int?)> sizes,
) {
  for (final w in root.getChildren()) {
    final s = sizes[w.getDebugName()];
    if (s == null) continue;
    if (s.$1 != null &&
        w.getHorizontalDimensionBehaviour() == DimensionBehaviour.fixed) {
      w.setWidth(s.$1!);
    }
    if (s.$2 != null &&
        w.getVerticalDimensionBehaviour() == DimensionBehaviour.fixed) {
      w.setHeight(s.$2!);
    }
  }
}

/// VOpDriver's `Echo` and the engine tests' EchoMeasurer
/// (test/support/echo_measurer.dart), oracle-local so the tool builds against
/// any tree.
class EchoMeasurer implements Measurer {
  const EchoMeasurer();

  @override
  void measure(ConstraintWidget widget, Measure measure) {
    var width = measure.horizontalBehavior == DimensionBehaviour.wrapContent
        ? widget.mWidth
        : measure.horizontalDimension;
    var height = measure.verticalBehavior == DimensionBehaviour.wrapContent
        ? widget.mHeight
        : measure.verticalDimension;
    if (widget.getHorizontalDimensionBehaviour() ==
        DimensionBehaviour.matchConstraint) {
      width = _clamp(
        width,
        widget.mMatchConstraintMinWidth,
        widget.mMatchConstraintMaxWidth,
      );
    }
    if (widget.getVerticalDimensionBehaviour() ==
        DimensionBehaviour.matchConstraint) {
      height = _clamp(
        height,
        widget.mMatchConstraintMinHeight,
        widget.mMatchConstraintMaxHeight,
      );
    }
    measure.measuredWidth = width;
    measure.measuredHeight = height;
    measure.measuredHasBaseline = widget.hasBaseline();
    measure.measuredBaseline = widget.getBaselineDistance();
    widget.setMeasureRequested(false);
  }

  @override
  void didMeasures() {}

  static int _clamp(int v, int min, int max) {
    var value = v;
    if (min > 0 && value < min) value = min;
    if (max > 0 && value > max) value = max;
    return value;
  }
}

/// The view measurer of the view paths: content.dart's spec form.
class ContentViewMeasurer extends ViewMeasurer {
  static const _content = ContentMeasurer();

  @override
  ({int width, int height, int baseline}) measureContent(
    ConstraintWidget widget,
    int widthSpec,
    int heightSpec,
  ) => _content.measureContent(widget, widthSpec, heightSpec);
}

String _oneLine(Object e) =>
    e.toString().replaceAll('\t', ' ').replaceAll('\n', ' ');

/// Replays [ops] into [root] (each L op runs [pass]), then runs the final
/// [pass]. Returns whether the final pass printed and what was thrown: as in
/// VOpDriver, only the final measure's printed exceptions make the status
/// ok-printed (each L op's output is captured and dropped there), while a
/// throw anywhere makes it EXC.
(bool, Object?) _replay(
  ConstraintWidgetContainer root,
  List<String> ops,
  void Function() pass, {
  void Function()? beforeFinal,
}) {
  final (_, thrownByOps) = guarded(() {
    applyOps(root, ops, layoutPass: pass);
  });
  if (thrownByOps != null) {
    return (false, thrownByOps);
  }
  beforeFinal?.call();
  return guarded(pass);
}

String _status(bool printed, Object? thrown) => thrown != null
    ? 'EXC:${_oneLine(thrown)}'
    : (printed ? 'ok-printed' : 'ok');

/// OpDriver's core path at [level] on [ops].
PathResult runCore(List<String> ops, {required int level}) {
  final (w, h) = rootSize(ops);
  final root = ConstraintWidgetContainer.rect(0, 0, w, h)..setDebugName('root');
  const measurer = EchoMeasurer();
  void pass() {
    // VOpDriver clears the probe before every measure, so the D field
    // describes the last one.
    lastDirect = null;
    final wrapW =
        root.getHorizontalDimensionBehaviour() ==
        DimensionBehaviour.wrapContent;
    final wrapH =
        root.getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent;
    root.setMeasurer(measurer);
    root.setOptimizationLevel(level);
    root.measure(
      level,
      wrapW ? BasicMeasure.AT_MOST : BasicMeasure.EXACTLY,
      root.getWidth(),
      wrapH ? BasicMeasure.AT_MOST : BasicMeasure.EXACTLY,
      root.getHeight(),
      0,
      0,
      0,
      0,
    );
  }

  lastTranscript = null;
  lastDirect = null;
  lastTwice = null;
  lastTwiceDetail = null;
  _installDirectSink();
  final (printed, thrown) = _replay(root, ops, pass);
  final status = _status(printed, thrown);
  final g = geometry(root);
  return PathResult(status, status == 'ok' ? g : '!$status | $g', root);
}

/// VOpDriver's view path at [level] on [ops].
PathResult runView(List<String> ops, {required int level}) {
  final (w, h) = rootSize(ops);
  final root = ConstraintWidgetContainer.rect(0, 0, w, h)..setDebugName('root');
  final measurer = ContentViewMeasurer();
  if (recordTranscript) {
    measurer.transcript = StringBuffer();
  }
  final host = ViewHost(root, measurer)..optimizationLevel = level;
  var childLayouts = 0;
  void pass() {
    // VOpDriver clears the probe before every measure, so the D field
    // describes the last one.
    lastDirect = null;
    final v = viewOf(root);
    host
      ..paddingLeft = v.padLeft
      ..paddingTop = v.padTop
      ..paddingRight = v.padRight
      ..paddingBottom = v.padBottom
      ..minWidth = v.minWidth
      ..minHeight = v.minHeight
      ..maxWidth = v.maxWidth
      ..maxHeight = v.maxHeight;
    final spec = v.spec;
    final int widthSpec, heightSpec;
    if (spec != null) {
      widthSpec = MeasureSpec.makeMeasureSpec(spec.wSize, spec.wMode);
      heightSpec = MeasureSpec.makeMeasureSpec(spec.hSize, spec.hMode);
    } else {
      widthSpec =
          root.getHorizontalDimensionBehaviour() ==
              DimensionBehaviour.wrapContent
          ? MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
          : MeasureSpec.makeMeasureSpec(root.getWidth(), MeasureSpec.EXACTLY);
      heightSpec =
          root.getVerticalDimensionBehaviour() == DimensionBehaviour.wrapContent
          ? MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
          : MeasureSpec.makeMeasureSpec(root.getHeight(), MeasureSpec.EXACTLY);
    }
    host.measure(widthSpec, heightSpec);
    childLayouts += measurer.measureCalls;
  }

  lastTranscript = null;
  lastDirect = null;
  lastTwice = null;
  lastTwiceDetail = null;
  _installDirectSink();
  String? linksBefore;
  List<(ConstraintAnchor, ConstraintAnchor?, int, int)>? saved;
  final (printed, thrown) = _replay(
    root,
    ops,
    pass,
    beforeFinal: measureTwice
        ? () {
            linksBefore = _virtualLayoutLinks(root);
            saved = _saveLinks(root);
          }
        : null,
  );
  if (recordTranscript) {
    lastTranscript = measurer.transcript.toString();
  }
  final status = _status(printed, thrown);
  String viewGeometry() => geometry(
    root,
    viewRule: true,
    rootW: host.getMeasuredWidth(),
    rootH: host.getMeasuredHeight(),
  );
  final g = viewGeometry();
  final result = status == 'ok' ? g : '!$status | $g';
  if (measureTwice && thrown == null) {
    // Laid out twice in one container: the FIXED sizes back to what the op
    // list configured, then the same host, measurer and specs again. The
    // dump and the transcript keep the first measure's.
    final keepDirect = lastDirect;
    final rewired = linksBefore != _virtualLayoutLinks(root);
    reapplyFixedSizes(root, configuredSizes(ops));
    if (twiceRestoreLinks && saved != null) {
      _restoreLinks(saved!);
    }
    final (printed2, thrown2) = guarded(pass);
    final status2 = _status(printed2, thrown2);
    final g2 = viewGeometry();
    final result2 = status2 == 'ok' ? g2 : '!$status2 | $g2';
    lastTwice = result2 != result;
    lastTwiceDetail = lastTwice!
        ? '${rewired ? 'vl-links' : 'other'}\t$result\t$result2'
        : null;
    lastDirect = keepDirect;
  }
  return PathResult(status, result, root, childLayouts: childLayouts);
}
