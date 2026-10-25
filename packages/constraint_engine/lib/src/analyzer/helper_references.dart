// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.HelperReferences

import '../barrier.dart';
import '../constraint_widget.dart';
import 'dependency.dart';
import 'dependency_node.dart';
import 'widget_run.dart';

class HelperReferences extends WidgetRun {
  HelperReferences(ConstraintWidget widget) : super(widget);

  @override
  void clear() {
    mRunGroup = null;
    start.clear();
    // Divergence from upstream, which only clears start: update() resolves
    // end and the dimension as well.
    end.clear();
    mDimension.clear();
  }

  @override
  void reset() {
    start.resolved = false;
    end.resolved = false;
    mDimension.resolved = false;
  }

  @override
  bool supportsWrapComputation() => false;

  void _addDependency(DependencyNode node) {
    start.mDependencies.add(node);
    node.mTargets.add(start);
  }

  /// Whether [barrier] positions itself from [reference]. Divergence from
  /// upstream, which skips any GONE reference when gone widgets are not
  /// allowed: this asks [ConstraintWidget.allowedInBarrier], as upstream's
  /// Barrier.addToSolver does, so a gone barrier still counts inside another
  /// barrier on both paths.
  static bool counts(Barrier barrier, ConstraintWidget reference) =>
      barrier.getAllowsGoneWidget() || reference.allowedInBarrier();

  static bool _skips(Barrier barrier, ConstraintWidget refWidget) =>
      !counts(barrier, refWidget);

  @override
  void apply() {
    if (mWidget is Barrier) {
      start.delegateToWidgetRun = true;
      final barrier = mWidget as Barrier;
      final type = barrier.getBarrierType();
      switch (type) {
        case Barrier.left:
          start.mType = DependencyNodeType.left;
          for (var i = 0; i < barrier.mWidgetsCount; i++) {
            final refWidget = barrier.mWidgets[i]!;
            if (_skips(barrier, refWidget)) {
              continue;
            }
            final target = refWidget.mHorizontalRun!.start;
            target.mDependencies.add(start);
            start.mTargets.add(target);
          }
          _addDependency(mWidget.mHorizontalRun!.start);
          _addDependency(mWidget.mHorizontalRun!.end);
          break;
        case Barrier.right:
          start.mType = DependencyNodeType.right;
          for (var i = 0; i < barrier.mWidgetsCount; i++) {
            final refWidget = barrier.mWidgets[i]!;
            if (_skips(barrier, refWidget)) {
              continue;
            }
            final target = refWidget.mHorizontalRun!.end;
            target.mDependencies.add(start);
            start.mTargets.add(target);
          }
          _addDependency(mWidget.mHorizontalRun!.start);
          _addDependency(mWidget.mHorizontalRun!.end);
          break;
        case Barrier.top:
          start.mType = DependencyNodeType.top;
          for (var i = 0; i < barrier.mWidgetsCount; i++) {
            final refWidget = barrier.mWidgets[i]!;
            if (_skips(barrier, refWidget)) {
              continue;
            }
            final target = refWidget.mVerticalRun!.start;
            target.mDependencies.add(start);
            start.mTargets.add(target);
          }
          _addDependency(mWidget.mVerticalRun!.start);
          _addDependency(mWidget.mVerticalRun!.end);
          break;
        case Barrier.bottom:
          start.mType = DependencyNodeType.bottom;
          for (var i = 0; i < barrier.mWidgetsCount; i++) {
            final refWidget = barrier.mWidgets[i]!;
            if (_skips(barrier, refWidget)) {
              continue;
            }
            final target = refWidget.mVerticalRun!.end;
            target.mDependencies.add(start);
            start.mTargets.add(target);
          }
          _addDependency(mWidget.mVerticalRun!.start);
          _addDependency(mWidget.mVerticalRun!.end);
          break;
      }
    }
  }

  @override
  void update(Dependency dependency) {
    final barrier = mWidget as Barrier;
    final type = barrier.getBarrierType();

    // Divergence from upstream, which seeds min with -1 as "unset" and max
    // with 0: a reference at -1 was then forgotten, and references that all
    // lie at negative positions resolved the barrier at 0. Seeding both from
    // the first reference gives the outermost edge, as the solver does.
    var min = 0;
    var max = 0;
    var initialized = false;
    for (final node in start.mTargets) {
      final value = node.value;
      if (!initialized) {
        min = value;
        max = value;
        initialized = true;
        continue;
      }
      if (value < min) {
        min = value;
      }
      if (max < value) {
        max = value;
      }
    }
    if (type == Barrier.left || type == Barrier.top) {
      start.resolve(min + barrier.getMargin());
    } else {
      start.resolve(max + barrier.getMargin());
    }
    // Divergence from upstream, which only ever resolves start: a barrier is
    // a line, so its end is its start and its dimension is 0. Upstream leaves
    // both unresolved, which fails DependencyGraph's all-resolved check for
    // every layout that contains a barrier; its solver-first entry never
    // needed them. Nothing depends on these two nodes.
    end.resolve(start.value);
    mDimension.resolve(0);
  }

  @override
  void applyToWidget() {
    if (mWidget is Barrier) {
      final barrier = mWidget as Barrier;
      final type = barrier.getBarrierType();
      // Divergence from upstream, which leaves the other axis as it was: the
      // solver never constrains a barrier across its axis, so it reports 0
      // there, and the graph does the same.
      if (type == Barrier.left || type == Barrier.right) {
        mWidget.setX(start.value);
        mWidget.setY(0);
      } else {
        mWidget.setY(start.value);
        mWidget.setX(0);
      }
    }
  }
}
