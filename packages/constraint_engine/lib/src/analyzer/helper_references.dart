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
  }

  @override
  void reset() {
    start.resolved = false;
  }

  @override
  bool supportsWrapComputation() => false;

  void _addDependency(DependencyNode node) {
    start.mDependencies.add(node);
    node.mTargets.add(start);
  }

  @override
  void apply() {
    if (mWidget is Barrier) {
      start.delegateToWidgetRun = true;
      final barrier = mWidget as Barrier;
      final type = barrier.getBarrierType();
      final allowsGoneWidget = barrier.getAllowsGoneWidget();
      switch (type) {
        case Barrier.left:
          start.mType = DependencyNodeType.left;
          for (var i = 0; i < barrier.mWidgetsCount; i++) {
            final refWidget = barrier.mWidgets[i]!;
            if (!allowsGoneWidget &&
                refWidget.getVisibility() == ConstraintWidget.GONE) {
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
            if (!allowsGoneWidget &&
                refWidget.getVisibility() == ConstraintWidget.GONE) {
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
            if (!allowsGoneWidget &&
                refWidget.getVisibility() == ConstraintWidget.GONE) {
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
            if (!allowsGoneWidget &&
                refWidget.getVisibility() == ConstraintWidget.GONE) {
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

    var min = -1;
    var max = 0;
    for (final node in start.mTargets) {
      final value = node.value;
      if (min == -1 || value < min) {
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
  }

  @override
  void applyToWidget() {
    if (mWidget is Barrier) {
      final barrier = mWidget as Barrier;
      final type = barrier.getBarrierType();
      if (type == Barrier.left || type == Barrier.right) {
        mWidget.setX(start.value);
      } else {
        mWidget.setY(start.value);
      }
    }
  }
}
