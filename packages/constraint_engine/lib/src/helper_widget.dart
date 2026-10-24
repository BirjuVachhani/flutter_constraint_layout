// Copyright (C) 2021 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.HelperWidget

import 'constraint_widget.dart';
import 'constraint_widget_container.dart';
import 'helper.dart';

/// Base class of the helpers that reference other widgets, such as
/// [Barrier] and [VirtualLayout].
class HelperWidget extends ConstraintWidget implements Helper {
  /// The referenced widgets. Only the first [mWidgetsCount] entries are
  /// used.
  List<ConstraintWidget?> mWidgets = List<ConstraintWidget?>.filled(4, null);

  /// The number of referenced widgets.
  int mWidgetsCount = 0;

  /// Creates a helper that references no widgets.
  HelperWidget() : super();

  /// Does nothing for a plain helper.
  @override
  void updateConstraints(ConstraintWidgetContainer container) {
    // nothing here
  }

  /// Add a widget to the helper: reference [widget]. The helper itself is
  /// ignored.
  @override
  void add(ConstraintWidget widget) {
    if (widget == this) {
      return;
    }
    if (mWidgetsCount + 1 > mWidgets.length) {
      mWidgets = List<ConstraintWidget?>.of(mWidgets)
        ..addAll(List<ConstraintWidget?>.filled(mWidgets.length, null));
    }
    mWidgets[mWidgetsCount] = widget;
    mWidgetsCount++;
  }

  /// Reset the widgets list contained by this helper.
  @override
  void removeAllIds() {
    mWidgetsCount = 0;
    for (var i = 0; i < mWidgets.length; i++) {
      mWidgets[i] = null;
    }
  }
}
