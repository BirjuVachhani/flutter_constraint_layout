// Part of the adapter library: the view measurers that size the children of
// a RenderConstraintLayout for the engine's ViewHost (by laying them out or,
// for the dry-layout queries, by asking for their dry layout), the records a
// full run keeps for the transcript replay, and the layout's own measure
// specs.
part of '../constraint_layout.dart';

/// The latest layout a measurer gave a child during an engine pass: its
/// constraints, and the size the child took under them (or, for a
/// [_DryMeasurer], would take).
typedef _MeasuredLayout = ({BoxConstraints constraints, Size size});

/// A content child of an [_EngineModel] ([_EngineModel.contentOf]): its
/// [RenderBox], and what the model's measurer keeps of it, in fields of its
/// own rather than in maps keyed by the child.
///
/// Representation choices that change no value the measurer answers and no
/// layout it asks of the child:
///  * the latest layout of the current pass ([laidOutPass] and the two
///    after it) is what an entry of a map cleared at every pass held: it
///    counts only while [laidOutPass] is the measurer's current pass;
///  * a measure under the specs of the child's last measure uses the box
///    constraints made for those specs again ([specConstraints]): they are
///    a function of the specs, and box constraints are read by value
///    everywhere (Flutter's `layout`, the child's own layout), so an equal
///    object is the same constraints;
///  * [storedWithBaseline] lets the measurer skip storing into
///    [_FlutterMeasurer._laidOutWithBaseline] the value the child's entry
///    already holds: only this measurer stores that entry while its model
///    lives.
final class _ContentChild {
  _ContentChild(this.box);

  /// The child.
  final RenderBox box;

  /// The pass of the measurer ([_FlutterMeasurer._pass]) whose content
  /// measure last laid the child out (or asked for its dry layout), and that
  /// layout: [_FlutterMeasurer.laidOutOf] while it is the current pass.
  int laidOutPass = -1;

  /// The constraints of that layout.
  BoxConstraints laidOutConstraints = const BoxConstraints();

  /// The size the child took under them (or would take, for a
  /// [_DryMeasurer]).
  Size laidOutSize = Size.zero;

  /// The measure specs of the child's last content measure, and the box
  /// constraints [_FlutterMeasurer._constraintsOf] made of them, which the
  /// next measure under the same specs uses again (box constraints are
  /// values: an equal object is the same constraints to every reader).
  int specWidth = 0;
  int specHeight = 0;
  BoxConstraints? specConstraints;

  /// Debug builds only: the constraints the child had when
  /// [_FlutterMeasurer.childBaseline] last read its baseline, or null when
  /// the read is forgotten (see [_FlutterMeasurer._layOut]).
  BoxConstraints? readConstraints;

  /// The baseline that read gave.
  double? readBaseline;

  /// The value the measurer last stored for the child in
  /// [_FlutterMeasurer._laidOutWithBaseline], or null before it stored one.
  bool? storedWithBaseline;
}

/// One [_FlutterMeasurer.measureContent] call of a full run: the child's
/// widget (and its [_ContentChild], null for a widget without a
/// [RenderBox]), the two measure specs it was asked with, and its answer.
typedef _ContentRecord = ({
  ConstraintWidget widget,
  _ContentChild? content,
  int widthSpec,
  int heightSpec,
  int width,
  int height,
  int baseline,
});

/// One [ViewMeasurer.measure] call of a full run: the [Measure]'s request
/// fields on entry and its answer fields on return.
typedef _RequestRecord = ({
  ConstraintWidget widget,
  int strategy,
  DimensionBehaviour? horizontalBehavior,
  DimensionBehaviour? verticalBehavior,
  int horizontalDimension,
  int verticalDimension,
  int measuredWidth,
  int measuredHeight,
  int measuredBaseline,
  bool measuredHasBaseline,
  bool measuredNeedsSolverPass,
});

/// The replay transcript of one full run: every measure request the engine
/// made ([requests]: measureChildren, Direct, the post-Direct measures, the
/// re-measure loop, the virtual layouts and their members, the GONE and cache
/// answers included) and every content measure ([contents]), each in call
/// order.
///
/// A virtual layout measures its members inside its own request, so their
/// requests complete, and are recorded, before its own.
final class _ReplayTranscript {
  /// The measure requests, in the order they completed.
  final List<_RequestRecord> requests = <_RequestRecord>[];

  /// The content measures, in call order.
  final List<_ContentRecord> contents = <_ContentRecord>[];

  /// Whether this transcript records the same run as [other]: the same
  /// requests and content measures in the same order, each with the same
  /// widget (by identity) and the same fields.
  bool sameAs(_ReplayTranscript other) {
    if (requests.length != other.requests.length ||
        contents.length != other.contents.length) {
      return false;
    }
    for (var i = 0; i < requests.length; i++) {
      final a = requests[i];
      final b = other.requests[i];
      if (!identical(a.widget, b.widget) || a != b) return false;
    }
    for (var i = 0; i < contents.length; i++) {
      final a = contents[i];
      final b = other.contents[i];
      if (!identical(a.widget, b.widget) || a != b) return false;
    }
    return true;
  }
}

/// The persistent model's [ViewMeasurer]: Android's view measurer, which
/// [ViewMeasurer.measure] ports (ConstraintLayout.java 709-996), with each
/// child view's `onMeasure` done by laying the child's [RenderBox] out.
///
/// [measureContent] gives the child the box constraints of its measure specs:
/// `EXACTLY(s)` is a tight `s`, `AT_MOST(s)` is `0..s` and `UNSPECIFIED` is
/// `0..infinity`, each axis on its own. It answers the size the child takes,
/// rounded up to whole pixels as `max(0, (v - 0.001).ceil())` ("Whole pixels"
/// in the README: Android's views measure in whole pixels, and a `TextView`
/// rounds its width up; the tolerance absorbs glyph-metric noise), and the
/// child's alphabetic baseline, read for every child it measures as Android
/// does, rounded up the same way, or -1 when the child has none. A Group's
/// widget, which has no [RenderBox], answers 0 x 0 with no baseline, as
/// Android's Group view measures; a cell box a `ConstraintGrid` adds takes
/// the size of an EXACTLY spec, else 0. So the answer is a function of the
/// request alone, which the transcript replay relies on.
///
/// Everything else Android's measurer does is [ViewMeasurer.measure]'s: the
/// specs by behaviour and strategy, the measure cache, the match-constraint
/// min and max and the measure again at a clamped size, and the answer's
/// flags. A child that has no finite size after its layout fails the layout
/// with a [FlutterError] in every build (see [layoutChild], and "Children on
/// an unbounded axis" in the README).
///
/// While [recording] is set, the measurer also keeps every request and every
/// content measure of the run, for the transcript replay.
///
/// [_DryMeasurer] measures the same way without laying anything out.
class _FlutterMeasurer extends ViewMeasurer {
  /// Creates the measurer of [model]'s content children
  /// ([_EngineModel.contentOf]) for [_layout].
  _FlutterMeasurer(this._layout, this._model);

  /// The layout whose children this measures, named in error reports and
  /// keeping the counters.
  final RenderConstraintLayout _layout;

  final _EngineModel _model;

  /// The current pass, counted by [beginPass]: a child's layout belongs to
  /// it when [_ContentChild.laidOutPass] is this.
  int _pass = 0;

  /// The latest layout a content measure of the current pass gave [widget]'s
  /// child (or, for a [_DryMeasurer], asked for), or null when no content
  /// measure of the pass laid it out. Placement keeps that layout when it
  /// already has the child's resolved size.
  _MeasuredLayout? laidOutOf(ConstraintWidget widget) =>
      _laidOut(_model.contentOf[widget]);

  /// [laidOutOf] the child of [content] (null for a child that is not a
  /// content child).
  _MeasuredLayout? _laidOut(_ContentChild? content) =>
      content == null || content.laidOutPass != _pass
      ? null
      : (constraints: content.laidOutConstraints, size: content.laidOutSize);

  /// Whether a content measure of the current pass laid the child of
  /// [content] out, the latest one at a size of [width] x [height].
  bool _laidOutAt(_ContentChild? content, double width, double height) =>
      content != null &&
      content.laidOutPass == _pass &&
      content.laidOutSize.width == width &&
      content.laidOutSize.height == height;

  /// The transcript of the full run in progress, or null when this pass does
  /// not record (a replay, or a dry query that is not kept for a replay).
  _ReplayTranscript? recording;

  /// Whether [recording] also keeps the measure requests, not only the
  /// content measures: a layout's run needs both (see
  /// [_ReplayTranscript.sameAs]), a dry query's replay only the content
  /// measures.
  bool _recordsRequests = true;

  /// Starts a pass: forgets the layouts of the previous one, and records the
  /// new one into a fresh [recording] when [record] is set (with its measure
  /// requests unless [requests] is false).
  ///
  /// The only per-pass reset of the measurer: [ViewHost.measure] starts the
  /// request transcript and the counters itself ([ViewMeasurer.beginMeasure]),
  /// and the child views' state carries over from one pass to the next, as a
  /// `View`'s does.
  void beginPass({required bool record, bool requests = true}) {
    _pass++;
    recording = record ? _ReplayTranscript() : null;
    _recordsRequests = requests;
  }

  /// [ViewMeasurer.measure], unchanged, recording the request and its answer
  /// while [recording] is set.
  ///
  /// The request fields are read before the call and the answer after it, as
  /// the engine's own request transcript reads them. Nothing else differs.
  @override
  void measure(ConstraintWidget widget, Measure measure) {
    final recording = this.recording;
    if (recording == null || !_recordsRequests) {
      super.measure(widget, measure);
      return;
    }
    final strategy = measure.measureStrategy;
    final horizontalBehavior = measure.horizontalBehavior;
    final verticalBehavior = measure.verticalBehavior;
    final horizontalDimension = measure.horizontalDimension;
    final verticalDimension = measure.verticalDimension;
    super.measure(widget, measure);
    recording.requests.add((
      widget: widget,
      strategy: strategy,
      horizontalBehavior: horizontalBehavior,
      verticalBehavior: verticalBehavior,
      horizontalDimension: horizontalDimension,
      verticalDimension: verticalDimension,
      measuredWidth: measure.measuredWidth,
      measuredHeight: measure.measuredHeight,
      measuredBaseline: measure.measuredBaseline,
      measuredHasBaseline: measure.measuredHasBaseline,
      measuredNeedsSolverPass: measure.measuredNeedsSolverPass,
    ));
  }

  /// The child view's `onMeasure` for [widget] under [widthSpec] and
  /// [heightSpec]: its size and baseline in whole pixels (see the class
  /// documentation).
  @override
  ({int width, int height, int baseline}) measureContent(
    ConstraintWidget widget,
    int widthSpec,
    int heightSpec,
  ) => _measureContent(
    widget,
    _model.contentOf[widget],
    widthSpec,
    heightSpec,
  );

  /// [measureContent] of [widget], whose [_ContentChild] is [content] (null
  /// for a widget without a [RenderBox]): a replay passes the one its record
  /// holds.
  ({int width, int height, int baseline}) _measureContent(
    ConstraintWidget widget,
    _ContentChild? content,
    int widthSpec,
    int heightSpec,
  ) {
    final ({int width, int height, int baseline}) answer;
    if (content == null) {
      assert(
        widget is! Guideline && widget is! Barrier && widget is! VirtualLayout,
        'Only content children, Group widgets and the widgets a grid adds '
        'reach measureContent: guidelines and barriers are GONE and get the '
        'GONE answer, and ViewMeasurer measures a virtual layout through its '
        'own measure, so a $widget here means the model lost its RenderBox',
      );
      answer = _groupWidgets.contains(widget)
          // A Group's widget: the Group view's onMeasure sets 0 x 0, because
          // a Group does not measure itself as a view (ConstraintHelper
          // 253-260, Group.java 71-74), and a Group has no baseline.
          ? (width: 0, height: 0, baseline: -1)
          // A widget the engine added, a ConstraintGrid's cell box (GridCore
          // adds them to the container, where Android's view Grid adds box
          // views; the grid is outside the parity contract): no view and no
          // content, so it takes the size an EXACTLY spec gives it, and 0
          // otherwise.
          : (
              width: _givenSize(widthSpec),
              height: _givenSize(heightSpec),
              baseline: -1,
            );
    } else {
      final constraints = limitContent(
        content.box,
        _specConstraints(content, widthSpec, heightSpec),
        wrapWidth: MeasureSpec.getMode(widthSpec) != MeasureSpec.EXACTLY,
        wrapHeight: MeasureSpec.getMode(heightSpec) != MeasureSpec.EXACTLY,
      );
      final size = layoutChild(content, constraints);
      content
        ..laidOutPass = _pass
        ..laidOutConstraints = constraints
        ..laidOutSize = size;
      final baseline = _readsBaselineOf(widget, content)
          ? childBaseline(content, constraints)
          : null;
      answer = (
        width: _wholePixels(size.width),
        height: _wholePixels(size.height),
        baseline: baseline == null ? -1 : _wholePixels(baseline),
      );
    }
    recording?.contents.add((
      widget: widget,
      content: content,
      widthSpec: widthSpec,
      heightSpec: heightSpec,
      width: answer.width,
      height: answer.height,
      baseline: answer.baseline,
    ));
    return answer;
  }

  /// Lays [child] out under [constraints] and returns its size.
  ///
  /// The child must come out of its layout with a finite size. One that
  /// cannot size itself under unbounded constraints (a vertical `ListView`
  /// on an unbounded height, say) fails its layout, which Flutter reports, or
  /// takes an infinite size. Either way this throws a [FlutterError], in
  /// every build: the layout cannot go on without the child's size (see
  /// "Children on an unbounded axis" in the README). Android measures such a
  /// child under an UNSPECIFIED spec, which these constraints are;
  /// [_unsizedChildError] names the axis and the fixes.
  Size layoutChild(_ContentChild content, BoxConstraints constraints) {
    final child = content.box;
    _layOut(child, content, constraints, parentUsesSize: true);
    if (!child.hasSize) throw _unsizedChildError(child, constraints);
    final size = child.size;
    if (!size.isFinite) throw _unsizedChildError(child, constraints);
    return size;
  }

  /// Lays [child] out tight at its frame, [constraints], for its placement
  /// ([RenderConstraintLayout._place]); [content] is its [_ContentChild],
  /// null for a child that is not a content child.
  void placeChild(
    RenderBox child,
    _ContentChild? content,
    BoxConstraints constraints,
  ) => _layOut(child, content, constraints, parentUsesSize: false);

  /// Every layout of a child by this measurer: a measure ([layoutChild]) or a
  /// placement ([placeChild]).
  ///
  /// In a debug build it first forgets the baseline [childBaseline] last read
  /// from the child of [content] when this layout can run the child's
  /// `performLayout`: when the child needs layout, or [constraints] differ
  /// from its constraints. See [childBaseline] for why that keeps every kept
  /// read exact.
  void _layOut(
    RenderBox child,
    _ContentChild? content,
    BoxConstraints constraints, {
    required bool parentUsesSize,
  }) {
    if (kDebugMode &&
        content != null &&
        content.readConstraints != null &&
        (child.debugNeedsLayout ||
            !_sameConstraints(child.constraints, constraints))) {
      content.readConstraints = null;
    }
    child.layout(constraints, parentUsesSize: parentUsesSize);
  }

  /// Whether [a] and [b] are equal constraints, the same object first (in a
  /// debug build, [BoxConstraints.==] checks both are valid before it
  /// compares them).
  static bool _sameConstraints(Constraints a, BoxConstraints b) =>
      identical(a, b) || a == b;

  /// The alphabetic baseline of the child of [content], which [layoutChild]
  /// last laid out under [constraints], or null if it has none.
  ///
  /// Also notes whether the child had one ([_laidOutWithBaseline]), which
  /// decides whether a later dry query asks it for its dry baseline.
  ///
  /// In a debug build it answers again, without asking the child, the last
  /// baseline it read from the child ([_ContentChild.readBaseline]) when the
  /// child had equal constraints then ([_ContentChild.readConstraints]) and
  /// the read is still kept: asking costs a timeline event with its
  /// arguments on every call there, cached or not.
  ///
  /// Exact (a replay of Flutter's own cache, checked by the dual run of
  /// `--dart-define=cl.verifyReplay=true`): `getDistanceToBaseline` with
  /// `onlyReal` returns the entry of the child's layout cache for its current
  /// constraints, computing and storing it when absent
  /// (`RenderBox._computeIntrinsics`, which caches unless
  /// [RenderObject.debugCheckingIntrinsics], when nothing is kept here). That
  /// cache is only cleared, all at once, by the child's `markNeedsLayout`,
  /// and an entry is never replaced. A kept read is the entry the read left
  /// for its constraints, and stays exactly that entry while neither of these
  /// happened since:
  ///  * the child's `markNeedsLayout`, which also sets its `_needsLayout`
  ///    until its next layout. The cache held the read's entry, so that
  ///    `markNeedsLayout` deferred to the parent (`markParentNeedsLayout`)
  ///    and did not queue the child as a relayout boundary of its own, and
  ///    later ones return early while `_needsLayout` holds; so the child is
  ///    next laid out by this layout, through [_layOut], which sees
  ///    `debugNeedsLayout` and forgets the read;
  ///  * a `performLayout` of the child, whose layout callbacks could mark
  ///    it: only a layout that needs one or brings new constraints runs it,
  ///    and [_layOut] forgets the read before any such layout.
  /// So a kept read equals what the child would answer, and skipping the
  /// call changes no value; only the debug timeline loses the cached calls'
  /// events. Release and profile builds always ask (only a debug build
  /// tracks [RenderObject.debugNeedsLayout]), and there a cached call costs
  /// little.
  double? childBaseline(_ContentChild content, BoxConstraints constraints) {
    final child = content.box;
    final reuse = kDebugMode && !RenderObject.debugCheckingIntrinsics;
    double? baseline;
    final read = content.readConstraints;
    if (reuse && read != null && _sameConstraints(read, constraints)) {
      _layout.debugReusedBaselines++;
      baseline = content.readBaseline;
      if (_verifyReplay) {
        // The dual run: what the child answers when asked.
        final asked = child.getDistanceToBaseline(
          TextBaseline.alphabetic,
          onlyReal: true,
        );
        if (asked != baseline) {
          _layout.debugReusedBaselineMismatches++;
          _reportReusedBaselineMismatch(child, constraints, baseline, asked);
          baseline = asked;
          content.readBaseline = asked;
        }
      }
    } else {
      baseline = child.getDistanceToBaseline(
        TextBaseline.alphabetic,
        onlyReal: true,
      );
      if (reuse) {
        content
          ..readConstraints = constraints
          ..readBaseline = baseline;
      }
    }
    // Stored only when it changes: only this measurer stores it for the
    // child while the model lives, so the stored value is still the last one
    // it stored.
    final withBaseline = baseline != null;
    if (content.storedWithBaseline != withBaseline) {
      _laidOutWithBaseline[child] = withBaseline;
      content.storedWithBaseline = withBaseline;
    }
    return baseline;
  }

  void _reportReusedBaselineMismatch(
    RenderBox child,
    BoxConstraints constraints,
    double? reused,
    double? asked,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary(
            'A ConstraintLayout reused a child\'s baseline that differs from '
            'the child\'s answer.',
          ),
          ErrorDescription(
            'Under $constraints the layout reused the baseline $reused it '
            'read before, and the child now answers $asked.',
          ),
          ErrorHint('The measure takes the child\'s answer.'),
        ]),
        library: 'flutter_constraint_layout',
        context: ErrorDescription('while verifying a reused baseline'),
        informationCollector: () => <DiagnosticsNode>[
          _layout.describeForError('The ConstraintLayout was'),
          child.describeForError('The child was'),
        ],
      ),
    );
  }

  /// For each child a layout measured, whether its latest content measure
  /// found a baseline: true or false, or null before the child's first
  /// content measure in a layout. Written by layouts only, never by dry
  /// queries; read by [_DryMeasurer._readsBaselineOf].
  static final Expando<bool> _laidOutWithBaseline = Expando<bool>(
    'whether a ConstraintLayout child was last measured with a baseline',
  );

  /// The constraints [child] is measured under, from [constraints], the
  /// constraints of its measure specs, where [wrapWidth] and [wrapHeight] say
  /// whether an axis is measured for the child's content (its spec is not
  /// EXACTLY). Unchanged here; [_DryMeasurer] lowers them for the minimum
  /// intrinsic sizes.
  BoxConstraints limitContent(
    RenderBox child,
    BoxConstraints constraints, {
    required bool wrapWidth,
    required bool wrapHeight,
  }) => constraints;

  /// The widgets of the model's Group children (each a plain widget in the
  /// container at the Group's child index, without a [RenderBox]).
  late final Set<ConstraintWidget> _groupWidgets = <ConstraintWidget>{
    for (var i = 0; i < _model.widgets.length; i++)
      if (_model.childData[i].helperKind == HelperKind.group) _model.widgets[i],
  };

  /// Whether [measureContent] reads the baseline of [widget]'s child: always
  /// for a layout, which reads the baseline of every child it measures, as
  /// Android does. See [_DryMeasurer._readsBaselineOf].
  bool _readsBaselineOf(ConstraintWidget widget, _ContentChild content) => true;

  /// [_constraintsOf] [widthSpec] and [heightSpec] for the child of
  /// [content]: the same object as its last content measure's when the specs
  /// are the same, else new.
  static BoxConstraints _specConstraints(
    _ContentChild content,
    int widthSpec,
    int heightSpec,
  ) {
    final last = content.specConstraints;
    if (last != null &&
        content.specWidth == widthSpec &&
        content.specHeight == heightSpec) {
      return last;
    }
    final constraints = _constraintsOf(widthSpec, heightSpec);
    content
      ..specWidth = widthSpec
      ..specHeight = heightSpec
      ..specConstraints = constraints;
    return constraints;
  }

  /// The box constraints of a child measured under [widthSpec] and
  /// [heightSpec], each axis on its own: `EXACTLY(s)` is `s..s`, `AT_MOST(s)`
  /// is `0..s`, and `UNSPECIFIED` (whatever its size) is `0..infinity`.
  static BoxConstraints _constraintsOf(int widthSpec, int heightSpec) {
    final (minWidth, maxWidth) = _extentsOf(widthSpec);
    final (minHeight, maxHeight) = _extentsOf(heightSpec);
    return BoxConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
    );
  }

  /// The minimum and maximum extent of one axis measured under [spec].
  static (double, double) _extentsOf(int spec) {
    final size = MeasureSpec.getSize(spec).toDouble();
    return switch (MeasureSpec.getMode(spec)) {
      MeasureSpec.EXACTLY => (size, size),
      MeasureSpec.AT_MOST => (0, size),
      _ => (0, double.infinity),
    };
  }

  /// The size a widget without a view or content takes on an axis measured
  /// under [spec]: the spec's size when it is EXACTLY, else 0.
  static int _givenSize(int spec) =>
      MeasureSpec.getMode(spec) == MeasureSpec.EXACTLY
      ? MeasureSpec.getSize(spec)
      : 0;

  /// [extent] in whole pixels, rounded up unless it is within 0.001 of the
  /// whole pixel below, and never negative: `max(0, (v - 0.001).ceil())`
  /// (see "Whole pixels" in the README). A child 99.4 wide measures 100, one
  /// 99.0005 wide measures 99 and one 99.002 wide measures 100.
  static int _wholePixels(double extent) =>
      math.max(0, (extent - 0.001).ceil());

  /// The measure spec and the minimum size of one axis of the layout, whose
  /// constraints on it are [min] and [max]; see [_hostSpecsFor].
  static (int, int) _layoutAxis(double min, double max) => max.isFinite
      ? (MeasureSpec.makeMeasureSpec(max.round(), MeasureSpec.EXACTLY), 0)
      : (
          MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED),
          _wholePixels(min),
        );

  /// The error of a [child] that came out of its layout under [constraints]
  /// without a size, or with an infinite one (see [layoutChild]).
  static FlutterError _unsizedChildError(
    RenderBox child,
    BoxConstraints constraints,
  ) {
    final size = child.hasSize ? child.size : null;
    final unboundedWidth = !constraints.hasBoundedWidth;
    final unboundedHeight = !constraints.hasBoundedHeight;
    // The axes that failed: those whose extent is not finite, or, when the
    // child has no size at all, the unbounded ones, which caused it.
    final failsWidth = size == null ? unboundedWidth : !size.width.isFinite;
    final failsHeight = size == null ? unboundedHeight : !size.height.isFinite;
    final id = switch (child.parentData) {
      ConstraintParentData(:final id?) => id,
      _ => null,
    };
    final who = id == null
        ? 'A child of a ConstraintLayout'
        : 'The ConstraintLayout child ${_describeId(id)}';
    final parent = child.parent;
    final context = <DiagnosticsNode>[
      child.describeForError('The child was'),
      if (parent != null) parent.describeForError('The ConstraintLayout was'),
    ];
    if ((!failsWidth && !failsHeight) ||
        (failsWidth && !unboundedWidth) ||
        (failsHeight && !unboundedHeight)) {
      // No size on an axis that is bounded: not a matter of unbounded
      // constraints, but of the child's own layout, which Flutter reported
      // before this error.
      return FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary(
          '$who has no finite size after its layout under $constraints.',
        ),
        ...context,
        ErrorDescription(
          'Its layout failed, or it took an infinite size; see the error '
          'reported before this one. The ConstraintLayout cannot place a '
          'child without its size.',
        ),
      ]);
    }
    final axis = failsWidth && failsHeight
        ? 'width and height'
        : failsWidth
        ? 'width'
        : 'height';
    final direction = failsWidth && failsHeight
        ? 'on both axes'
        : failsWidth
        ? 'horizontally'
        : 'vertically';
    final scrollView = failsWidth && failsHeight
        ? 'a two-dimensional scroll view'
        : failsWidth
        ? 'a horizontal scroll view'
        : 'a vertical scroll view';
    return FlutterError.fromParts(<DiagnosticsNode>[
      ErrorSummary(
        '$who has no finite $axis after its layout under unbounded '
        'constraints.',
      ),
      ...context,
      ErrorDescription(
        'The ConstraintLayout is unbounded $direction (for example inside '
        '$scrollView), so it measures this child there with unbounded '
        'constraints ($constraints), as Android measures a match_parent or '
        'wrap_content child under an UNSPECIFIED measure spec. This child '
        'cannot size itself without a bound: it reported a layout error, or '
        'it took an infinite $axis.',
      ),
      ErrorHint(
        'Give the child a fixed $axis (Dimension.fixed), bound the '
        "ConstraintLayout's $axis (with a SizedBox, say), or use a child that "
        'sizes itself under unbounded constraints (for a ListView, '
        'shrinkWrap: true).',
      ),
    ]);
  }

  /// [id] as an error message names it: `#name`.
  static String _describeId(Symbol id) {
    // Symbol.toString() is 'Symbol("name")'.
    final text = id.toString();
    const prefix = 'Symbol("';
    if (text.startsWith(prefix) && text.endsWith('")')) {
      return '#${text.substring(prefix.length, text.length - 2)}';
    }
    return text;
  }
}

/// Measures children for the dry-layout queries: the dry layout, the
/// intrinsic sizes, and the dry baseline of a [RenderConstraintLayout].
///
/// Maps measure specs to constraints and rounds the answers as
/// [_FlutterMeasurer] does, but sizes each child with
/// [RenderBox.getDryLayout] and reads its baseline with
/// [RenderBox.getDryBaseline] instead of laying it out, so a query changes no
/// child. A child under tight constraints is not asked for its size, which
/// the constraints already fix, and a child whose dry size is infinite on an
/// axis measures at its minimum there: a query must not throw, so the error
/// of a layout ([_FlutterMeasurer.layoutChild]) does not apply.
///
/// A query reads the baseline of the children whose baseline can place a
/// widget and of the children whose latest layout found one, not of every
/// child as a layout does; see [_readsBaselineOf].
///
/// A child that cannot answer (in a debug build, a `LayoutBuilder` throws,
/// since it cannot compute a dry layout) has its error reported once per
/// query, and then measures at the smallest size its constraints allow and
/// without a baseline, so the query still returns a result.
class _DryMeasurer extends _FlutterMeasurer {
  /// Creates the measurer of a dry query of [layout] over [model].
  _DryMeasurer(super.layout, super.model, {this.minimumAxis});

  /// When set, each child that sizes to its content along this axis measures
  /// at no more than its own minimum intrinsic size along it.
  final Axis? minimumAxis;

  /// Children whose dry measurement threw during this query.
  final Set<RenderBox> _failed = <RenderBox>{};

  /// Whether the measurer is replaying a query's content measures
  /// ([RenderConstraintLayout._dryReplays]): then [_ask] reports nothing and
  /// remembers no failure, it only notes one in [_probeFailed], and the query
  /// runs in full instead, which asks and reports as it always does.
  bool _probing = false;

  /// Whether a child threw while [_probing].
  bool _probeFailed = false;

  /// Also starts a new query: [_failed] holds the failures of one query.
  @override
  void beginPass({required bool record, bool requests = true}) {
    super.beginPass(record: record, requests: requests);
    _failed.clear();
  }

  /// The widgets a baseline-aligned flow of the model arranges by their
  /// baselines.
  late final Set<ConstraintWidget> _baselineFlowMembers = <ConstraintWidget>{
    for (var i = 0; i < _model.widgets.length; i++)
      if (_model.childData[i] case ConstraintParentData(
        helperKind: HelperKind.flow,
        flowVerticalAlign: FlowVerticalAlign.baseline,
      ))
        if (_model.widgets[i] case final HelperWidget flow)
          for (var k = 0; k < flow.mWidgetsCount; k++) ?flow.mWidgets[k],
  };

  @override
  Size layoutChild(_ContentChild content, BoxConstraints constraints) {
    final child = content.box;
    if (constraints.isTight) return constraints.smallest;
    final size =
        _ask(child, () => child.getDryLayout(constraints)) ??
        constraints.smallest;
    // A child that expands to fill an unbounded axis could not be laid out
    // under these constraints at all. A query (for an intrinsic size, say)
    // measures it collapsed on that axis instead, which is also the intrinsic
    // size an expanding box reports.
    return Size(
      size.width.isFinite ? size.width : constraints.minWidth,
      size.height.isFinite ? size.height : constraints.minHeight,
    );
  }

  @override
  double? childBaseline(_ContentChild content, BoxConstraints constraints) =>
      dryBaseline(content.box, constraints, TextBaseline.alphabetic);

  /// The [baseline] of [child] under [constraints], or null if it has none.
  double? dryBaseline(
    RenderBox child,
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => _ask(child, () => child.getDryBaseline(constraints, baseline));

  /// Whether the query reads the baseline of [widget]'s child: when the
  /// baseline can place a widget, at either end of a baseline link (the
  /// layout params that ask for a baseline, [needsBaselineOf], which
  /// [ViewHost] sets before it measures) or in a baseline-aligned flow, and
  /// when the child's latest measure in a layout found a baseline. Any other
  /// child answers -1 without being asked: one whose latest layout found no
  /// baseline, and one the layout has not measured yet.
  ///
  /// A layout reads the baseline of every child it measures, as Android does,
  /// and the baselines change the solver's variables (a widget with a
  /// baseline gets its baseline variable early), so a query that skipped a
  /// child with a baseline could resolve a degenerate layout differently from
  /// the layout itself. But many render boxes cannot compute a dry baseline
  /// (an `Image`, a `RotatedBox`, a `CustomMultiChildLayout`, a scroll view):
  /// asked in a debug build, one throws, and Flutter does not recover a render
  /// box whose dry baseline threw, so every later read of its size fails an
  /// assertion. None of those has a baseline in a layout either, so once the
  /// layout has measured its children, a query asks exactly the children whose
  /// layout answer has a baseline, and answers -1 for the others as the layout
  /// does.
  @override
  bool _readsBaselineOf(ConstraintWidget widget, _ContentChild content) {
    if (needsBaselineOf(widget) || _baselineFlowMembers.contains(widget)) {
      return true;
    }
    return _FlutterMeasurer._laidOutWithBaseline[content.box] == true;
  }

  @override
  BoxConstraints limitContent(
    RenderBox child,
    BoxConstraints constraints, {
    required bool wrapWidth,
    required bool wrapHeight,
  }) {
    if (minimumAxis == Axis.horizontal && wrapWidth) {
      final minimum = _ask(
        child,
        () => child.getMinIntrinsicWidth(constraints.maxHeight),
      );
      if (minimum != null && minimum < constraints.maxWidth) {
        return constraints.copyWith(
          maxWidth: math.max(constraints.minWidth, minimum),
        );
      }
    } else if (minimumAxis == Axis.vertical && wrapHeight) {
      final minimum = _ask(
        child,
        () => child.getMinIntrinsicHeight(constraints.maxWidth),
      );
      if (minimum != null && minimum < constraints.maxHeight) {
        return constraints.copyWith(
          maxHeight: math.max(constraints.minHeight, minimum),
        );
      }
    }
    return constraints;
  }

  /// Runs [query] against [child] and returns its result, or null if it
  /// throws or the child already threw during this query.
  ///
  /// What it throws is reported rather than rethrown, so that one child that
  /// cannot be measured without a layout does not fail the whole query.
  T? _ask<T extends Object>(RenderBox child, T? Function() query) {
    if (_failed.contains(child)) return null;
    try {
      return query();
    } catch (exception, stack) {
      if (_probing) {
        _probeFailed = true;
        return null;
      }
      _failed.add(child);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'flutter_constraint_layout',
          context: ErrorDescription(
            'while measuring a child of a ConstraintLayout for a dry layout, '
            'intrinsic size, or dry baseline',
          ),
          informationCollector: () => <DiagnosticsNode>[
            _layout.describeForError('The ConstraintLayout was'),
            child.describeForError('The child was'),
            ErrorHint(
              'The ConstraintLayout measured the child at the smallest size '
              'its constraints allow, so the size it computed may be wrong. '
              'Flutter does not recover a render object whose dry layout '
              'threw, so such a child can report more errors when it is next '
              'laid out. A child with a fixed size is never asked for its '
              'size: give it one, or use a widget that supports dry layout.',
            ),
          ],
        ),
      );
      return null;
    }
  }
}

/// The measure specs and the minimum size [ViewHost] measures a
/// [RenderConstraintLayout] with under [constraints], as Android's parent
/// view would give them to the layout (one axis at a time; see "Sizing and
/// scrolling" in the README):
///
///  * a bounded axis, tight or loose, is `EXACTLY` at its maximum rounded to
///    whole pixels, with no minimum: the layout fills the space it is given
///    (there is no AT_MOST mode);
///  * an unbounded axis is `UNSPECIFIED(0)`, so the layout wraps its children
///    there, and the constraints' minimum, rounded up to whole pixels as a
///    child's size is, becomes the layout's `minWidth` or `minHeight`: the
///    engine's container is at least that big, and the children are placed
///    in it.
///
/// So the layout's size, `constraints.constrain` of the size [ViewHost]
/// measures, never exceeds the engine's container by more than 0.001.
({int widthSpec, int heightSpec, int minWidth, int minHeight}) _hostSpecsFor(
  BoxConstraints constraints,
) {
  final (widthSpec, minWidth) = _FlutterMeasurer._layoutAxis(
    constraints.minWidth,
    constraints.maxWidth,
  );
  final (heightSpec, minHeight) = _FlutterMeasurer._layoutAxis(
    constraints.minHeight,
    constraints.maxHeight,
  );
  return (
    widthSpec: widthSpec,
    heightSpec: heightSpec,
    minWidth: minWidth,
    minHeight: minHeight,
  );
}
