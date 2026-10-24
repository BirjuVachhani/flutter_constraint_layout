// Copyright (C) 2019 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.analyzer.DimensionDependency

import 'dependency.dart';
import 'dependency_node.dart';
import 'horizontal_widget_run.dart';
import 'widget_run.dart';

class DimensionDependency extends DependencyNode {
  int wrapValue = 0;

  DimensionDependency(WidgetRun run) : super(run) {
    if (run is HorizontalWidgetRun) {
      mType = DependencyNodeType.horizontalDimension;
    } else {
      mType = DependencyNodeType.verticalDimension;
    }
  }

  @override
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
}
