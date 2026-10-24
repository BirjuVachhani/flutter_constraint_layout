// Copyright (C) 2018 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.Helper

import 'constraint_widget.dart';
import 'constraint_widget_container.dart';

/// Interface to virtual objects (helpers) such as Barrier.
abstract class Helper {
  /// Update the helper's constraints for [container]. A host calls it after
  /// setting the referenced widgets ([add]), before layout; the engine does
  /// not call it.
  void updateConstraints(ConstraintWidgetContainer container);

  /// Reference [widget] from this helper.
  void add(ConstraintWidget widget);

  /// Remove every referenced widget.
  void removeAllIds();
}
