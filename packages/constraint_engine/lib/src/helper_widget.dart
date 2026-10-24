// Copyright (C) 2021 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.widgets.HelperWidget

import 'constraint_widget.dart';
import 'constraint_widget_container.dart';
import 'helper.dart';

class HelperWidget extends ConstraintWidget implements Helper {
  List<ConstraintWidget?> mWidgets = List<ConstraintWidget?>.filled(4, null);
  int mWidgetsCount = 0;

  HelperWidget() : super();

  @override
  void updateConstraints(ConstraintWidgetContainer container) {
    // nothing here
  }

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

  @override
  void removeAllIds() {
    mWidgetsCount = 0;
    for (var i = 0; i < mWidgets.length; i++) {
      mWidgets[i] = null;
    }
  }
}
