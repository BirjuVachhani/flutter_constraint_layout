// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.GuidelineReference

import '../constraint_widget.dart';
import '../guideline.dart';
import '../jfloat.dart';
import 'dependency.dart';
import 'dependency_node.dart';
import 'widget_run.dart';

class GuidelineReference extends WidgetRun {
  GuidelineReference(ConstraintWidget widget) : super(widget) {
    widget.mHorizontalRun!.clear();
    widget.mVerticalRun!.clear();
    orientation = (widget as Guideline).getOrientation();
  }

  @override
  void clear() {
    start.clear();
  }

  @override
  void reset() {
    start.resolved = false;
    end.resolved = false;
  }

  @override
  bool supportsWrapComputation() => false;

  void _addDependency(DependencyNode node) {
    start.mDependencies.add(node);
    node.mTargets.add(start);
  }

  @override
  void update(Dependency dependency) {
    if (!start.readyToSolve) {
      return;
    }
    if (start.resolved) {
      return;
    }
    final startTarget = start.mTargets[0];
    final guideline = mWidget as Guideline;
    // (int) (0.5f + startTarget.value * percent), in floats.
    final startPos = jint(
      fadd(0.5, fmul(fi(startTarget.value), guideline.getRelativePercent())),
    );
    start.resolve(startPos);
  }

  @override
  void apply() {
    final guideline = mWidget as Guideline;
    final relativeBegin = guideline.getRelativeBegin();
    final relativeEnd = guideline.getRelativeEnd();
    if (guideline.getOrientation() == ConstraintWidget.VERTICAL) {
      if (relativeBegin != -1) {
        start.mTargets.add(mWidget.mParent!.mHorizontalRun!.start);
        mWidget.mParent!.mHorizontalRun!.start.mDependencies.add(start);
        start.mMargin = relativeBegin;
      } else if (relativeEnd != -1) {
        start.mTargets.add(mWidget.mParent!.mHorizontalRun!.end);
        mWidget.mParent!.mHorizontalRun!.end.mDependencies.add(start);
        start.mMargin = -relativeEnd;
      } else {
        start.delegateToWidgetRun = true;
        start.mTargets.add(mWidget.mParent!.mHorizontalRun!.end);
        mWidget.mParent!.mHorizontalRun!.end.mDependencies.add(start);
      }
      _addDependency(mWidget.mHorizontalRun!.start);
      _addDependency(mWidget.mHorizontalRun!.end);
    } else {
      if (relativeBegin != -1) {
        start.mTargets.add(mWidget.mParent!.mVerticalRun!.start);
        mWidget.mParent!.mVerticalRun!.start.mDependencies.add(start);
        start.mMargin = relativeBegin;
      } else if (relativeEnd != -1) {
        start.mTargets.add(mWidget.mParent!.mVerticalRun!.end);
        mWidget.mParent!.mVerticalRun!.end.mDependencies.add(start);
        start.mMargin = -relativeEnd;
      } else {
        start.delegateToWidgetRun = true;
        start.mTargets.add(mWidget.mParent!.mVerticalRun!.end);
        mWidget.mParent!.mVerticalRun!.end.mDependencies.add(start);
      }
      _addDependency(mWidget.mVerticalRun!.start);
      _addDependency(mWidget.mVerticalRun!.end);
    }
  }

  @override
  void applyToWidget() {
    final guideline = mWidget as Guideline;
    if (guideline.getOrientation() == ConstraintWidget.VERTICAL) {
      mWidget.setX(start.value);
    } else {
      mWidget.setY(start.value);
    }
  }
}
