// Copyright (C) 2017 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.GoalRow (upstream pinned in
// UPSTREAM.md).

import 'array_row.dart';
import 'solver_variable.dart';

class GoalRow extends ArrayRow {
  GoalRow(super.cache);

  @override
  void addError(SolverVariable error) {
    super.addError(error);
    // error variables in the goal shouldn't be tracked (we only care if they
    // are in the system rows)
    error.usageInRowCount--;
  }
}
