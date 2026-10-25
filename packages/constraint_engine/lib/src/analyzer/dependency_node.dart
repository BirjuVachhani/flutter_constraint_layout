// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.DependencyNode

import 'dependency.dart';
import 'dimension_dependency.dart';
import 'widget_run.dart';

enum DependencyNodeType {
  unknown,
  horizontalDimension,
  verticalDimension,
  left,
  right,
  top,
  bottom,
  baseline,
}

class DependencyNode implements Dependency {
  Dependency? updateDelegate;
  bool delegateToWidgetRun = false;
  bool readyToSolve = false;

  WidgetRun mRun;
  DependencyNodeType mType = DependencyNodeType.unknown;
  int mMargin = 0;
  int value = 0;
  int mMarginFactor = 1;
  DimensionDependency? mMarginDependency;
  bool resolved = false;

  DependencyNode(this.mRun);

  /// Whether one of RunGroup's wrap-size traversals is inside this node.
  bool traversing = false;

  final List<Dependency> mDependencies = [];
  final List<DependencyNode> mTargets = [];

  @override
  String toString() =>
      '${mRun.mWidget.getDebugName()}:$mType(${resolved ? value : "unresolved"}) '
      '<t=${mTargets.length}:d=${mDependencies.length}>';

  void resolve(int value) {
    if (resolved) {
      return;
    }
    resolved = true;
    this.value = value;
    for (final node in List<Dependency>.of(mDependencies)) {
      node.update(node);
    }
  }

  @override
  void update(Dependency node) {
    for (final target in mTargets) {
      if (!target.resolved) {
        return;
      }
    }
    readyToSolve = true;
    if (updateDelegate != null) {
      updateDelegate!.update(this);
    }
    if (delegateToWidgetRun) {
      mRun.update(this);
      return;
    }
    DependencyNode? target;
    var numTargets = 0;
    for (final t in mTargets) {
      if (t is DimensionDependency) {
        continue;
      }
      target = t;
      numTargets++;
    }
    if (target != null && numTargets == 1 && target.resolved) {
      if (mMarginDependency != null) {
        if (mMarginDependency!.resolved) {
          mMargin = mMarginFactor * mMarginDependency!.value;
        } else {
          return;
        }
      }
      resolve(target.value + mMargin);
    }
    if (updateDelegate != null) {
      updateDelegate!.update(this);
    }
  }

  void addDependency(Dependency dependency) {
    mDependencies.add(dependency);
    if (resolved) {
      dependency.update(dependency);
    }
  }

  String name() {
    var definition = mRun.mWidget.getDebugName() ?? '';
    if (mType == DependencyNodeType.left || mType == DependencyNodeType.right) {
      definition += '_HORIZONTAL';
    } else {
      definition += '_VERTICAL';
    }
    definition += ':${mType.name}';
    return definition;
  }

  void clear() {
    mTargets.clear();
    mDependencies.clear();
    resolved = false;
    value = 0;
    readyToSolve = false;
    delegateToWidgetRun = false;
    // Divergence from upstream, whose clear() keeps the margin, its factor,
    // its dimension dependency and the update delegate of the last graph.
    // Every node is cleared before the graph is wired again, so it must come
    // out as a fresh node does: a margin dependency left behind makes
    // update() recompute the margin from a stale dimension even after
    // apply() set a plain one. On a container laid out again, a widget on
    // the baseline of a sibling that turned gone sat as far below as that
    // sibling's last measured baseline. UPSTREAM.md.
    mMargin = 0;
    mMarginFactor = 1;
    mMarginDependency = null;
    updateDelegate = null;
  }
}
