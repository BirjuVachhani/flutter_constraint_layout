// Copyright (C) 2016 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.WidgetContainer

import 'constraint_widget.dart';

/// A container of [ConstraintWidget]s.
class WidgetContainer extends ConstraintWidget {
  final List<ConstraintWidget> mChildren = [];

  WidgetContainer() : super();
  WidgetContainer.rect(int x, int y, int width, int height)
      : super.rect(x, y, width, height);
  WidgetContainer.size(int width, int height) : super.size(width, height);

  /// Add a child widget.
  void add(ConstraintWidget widget) {
    mChildren.add(widget);
    if (widget.getParent() != null) {
      final container = widget.getParent()! as WidgetContainer;
      container.remove(widget);
    }
    widget.setParent(this);
  }

  void addAll(List<ConstraintWidget> widgets) {
    for (final w in widgets) {
      add(w);
    }
  }

  /// Remove a child widget.
  void remove(ConstraintWidget widget) {
    mChildren.remove(widget);
    widget.setParent(null);
  }

  List<ConstraintWidget> getChildren() => mChildren;

  void removeAllChildren() {
    mChildren.clear();
  }
}
