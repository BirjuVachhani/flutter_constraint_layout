// Copyright (C) 2016 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.WidgetContainer

import 'constraint_widget.dart';

/// A container of [ConstraintWidget]s.
class WidgetContainer extends ConstraintWidget {
  /// The children, in the order they were added.
  final List<ConstraintWidget> mChildren = [];

  /// Creates an empty container at (0, 0) with a size of 0 x 0.
  WidgetContainer() : super();

  /// Creates an empty container at ([x], [y]) with the given [width] and
  /// [height].
  WidgetContainer.rect(int x, int y, int width, int height)
    : super.rect(x, y, width, height);

  /// Creates an empty container at (0, 0) with the given [width] and
  /// [height].
  WidgetContainer.size(int width, int height) : super.size(width, height);

  /// Add a child widget, removing it from the parent it had.
  void add(ConstraintWidget widget) {
    mChildren.add(widget);
    if (widget.getParent() != null) {
      final container = widget.getParent()! as WidgetContainer;
      container.remove(widget);
    }
    widget.setParent(this);
  }

  /// Add multiple child widgets, in order, as [add] does.
  void addAll(List<ConstraintWidget> widgets) {
    for (final w in widgets) {
      add(w);
    }
  }

  /// Remove a child widget and clear its parent. The widget keeps the rest of
  /// its configuration.
  void remove(ConstraintWidget widget) {
    mChildren.remove(widget);
    // Upstream resets the widget here instead (ConstraintWidget.reset(), not
    // ported), clearing its connections, size, and other attributes, and so
    // does [add] when it re-adds a widget that already has a parent. GridCore
    // re-adds its box widgets on every measure, as upstream does, and this
    // engine measures virtual layouts again in layout()'s solver fallback, so
    // a reset would wipe the boxes' setup. Upstream's own grid collapses the
    // second time it is measured, for the same reason.
    widget.setParent(null);
  }

  /// Access the children ([mChildren] itself, not a copy).
  List<ConstraintWidget> getChildren() => mChildren;

  /// Remove all the children. Their parent references are left as they are.
  void removeAllChildren() {
    mChildren.clear();
  }
}
