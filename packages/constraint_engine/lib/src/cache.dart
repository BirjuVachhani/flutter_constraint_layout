// Copyright (C) 2016 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.Cache (upstream pinned in
// UPSTREAM.md).

import 'array_row.dart';
import 'pools.dart';
import 'solver_variable.dart';

/// Cache for common solver objects.
class Cache {
  final SimplePool<ArrayRow> mOptimizedArrayRowPool = SimplePool(256);
  final SimplePool<ArrayRow> mArrayRowPool = SimplePool(256);
  final SimplePool<SolverVariable> mSolverVariablePool = SimplePool(256);
  List<SolverVariable?> mIndexedVariables = List<SolverVariable?>.filled(
    32,
    null,
  );

  /// Not upstream: set when a row that uses this cache stores a variable
  /// that is not [mIndexedVariables]' entry for its id (an id two variables
  /// share, or a variable that no system registered). While it is clear,
  /// every stored id k of every row belongs to `mIndexedVariables[k]`, which
  /// LinearSystem's column-indexed ratio test relies on; LinearSystem.reset
  /// clears it with the rows.
  bool mUnregisteredEntry = false;
}
