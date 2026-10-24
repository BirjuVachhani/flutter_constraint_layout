// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.SolverVariable (upstream pinned
// in UPSTREAM.md). Debug naming/printing branches (INTERNAL_DEBUG,
// VAR_USE_HASH, DO_NOT_USE) omitted.

import 'array_row.dart';
import 'linear_system.dart';

/// Type of variables.
enum SolverVariableType {
  /// The variable can take negative or positive values.
  unrestricted,

  /// Not actually a variable, but a constant number.
  constant,

  /// Restricted to positive values; represents a slack.
  slack,

  /// Restricted to positive values; represents an error.
  error,

  /// Unknown (invalid) type.
  unknown,
}

/// Represents a given variable used in the [LinearSystem] linear expression
/// solver.
class SolverVariable implements Comparable<SolverVariable> {
  // Strengths, weakest first. The solver minimizes the errors of a higher
  // strength before any of a lower one.

  /// The weakest strength.
  static const int STRENGTH_NONE = 0;

  /// A strength above [STRENGTH_NONE].
  static const int STRENGTH_LOW = 1;

  /// A strength above [STRENGTH_LOW].
  static const int STRENGTH_MEDIUM = 2;

  /// A strength above [STRENGTH_MEDIUM].
  static const int STRENGTH_HIGH = 3;

  /// A strength above [STRENGTH_HIGH].
  static const int STRENGTH_HIGHEST = 4;

  /// A strength above [STRENGTH_HIGHEST].
  static const int STRENGTH_EQUALITY = 5;

  /// A strength above [STRENGTH_EQUALITY].
  static const int STRENGTH_BARRIER = 6;

  /// A strength above [STRENGTH_BARRIER].
  static const int STRENGTH_CENTERING = 7;

  /// The strength of a required equation: the [LinearSystem] `add` methods
  /// add no error variable for it.
  static const int STRENGTH_FIXED = 8;

  /// The number of strengths, one more than [STRENGTH_FIXED].
  static const int MAX_STRENGTH = 9;

  /// Upstream increments a counter that only feeds debug variable naming
  /// (omitted in the port), so this is a no-op kept for call-site parity.
  static void increaseErrorId() {}

  bool inGoal = false;

  String? mName;

  int id = -1;
  int mDefinitionId = -1;
  int strength = 0;
  double computedValue = 0;
  bool isFinalValue = false;

  final List<double> mStrengthVector = List.filled(MAX_STRENGTH, 0);
  final List<double> mGoalStrengthVector = List.filled(MAX_STRENGTH, 0);

  SolverVariableType mType;

  List<ArrayRow?> mClientEquations = List<ArrayRow?>.filled(16, null);
  int mClientEquationsCount = 0;
  int usageInRowCount = 0;
  bool mIsSynonym = false;
  int mSynonym = -1;
  double mSynonymDelta = 0;

  SolverVariable(String? name, SolverVariableType type)
    : mName = name,
      mType = type;

  SolverVariable.typed(SolverVariableType type, String? prefix) : mType = type;

  void clearStrengths() {
    for (var i = 0; i < MAX_STRENGTH; i++) {
      mStrengthVector[i] = 0;
    }
  }

  void addToRow(ArrayRow row) {
    for (var i = 0; i < mClientEquationsCount; i++) {
      if (identical(mClientEquations[i], row)) {
        return;
      }
    }
    if (mClientEquationsCount >= mClientEquations.length) {
      mClientEquations = [
        ...mClientEquations,
        ...List<ArrayRow?>.filled(mClientEquations.length, null),
      ];
    }
    mClientEquations[mClientEquationsCount] = row;
    mClientEquationsCount++;
  }

  void removeFromRow(ArrayRow row) {
    final count = mClientEquationsCount;
    for (var i = 0; i < count; i++) {
      if (identical(mClientEquations[i], row)) {
        for (var j = i; j < count - 1; j++) {
          mClientEquations[j] = mClientEquations[j + 1];
        }
        mClientEquationsCount--;
        return;
      }
    }
  }

  void updateReferencesWithNewDefinition(
    LinearSystem system,
    ArrayRow definition,
  ) {
    final count = mClientEquationsCount;
    for (var i = 0; i < count; i++) {
      mClientEquations[i]!.updateFromRow(system, definition, false);
    }
    mClientEquationsCount = 0;
  }

  void setFinalValue(LinearSystem system, double value) {
    computedValue = value;
    isFinalValue = true;
    mIsSynonym = false;
    mSynonym = -1;
    mSynonymDelta = 0;
    final count = mClientEquationsCount;
    mDefinitionId = -1;
    for (var i = 0; i < count; i++) {
      mClientEquations[i]!.updateFromFinalVariable(system, this, false);
    }
    mClientEquationsCount = 0;
  }

  void setSynonym(
    LinearSystem system,
    SolverVariable synonymVariable,
    double value,
  ) {
    mIsSynonym = true;
    mSynonym = synonymVariable.id;
    mSynonymDelta = value;
    final count = mClientEquationsCount;
    mDefinitionId = -1;
    for (var i = 0; i < count; i++) {
      mClientEquations[i]!.updateFromSynonymVariable(system, this, false);
    }
    mClientEquationsCount = 0;
    system.displayReadableRows();
  }

  void reset() {
    mName = null;
    mType = SolverVariableType.unknown;
    strength = STRENGTH_NONE;
    id = -1;
    mDefinitionId = -1;
    computedValue = 0;
    isFinalValue = false;
    mIsSynonym = false;
    mSynonym = -1;
    mSynonymDelta = 0;
    final count = mClientEquationsCount;
    for (var i = 0; i < count; i++) {
      mClientEquations[i] = null;
    }
    mClientEquationsCount = 0;
    usageInRowCount = 0;
    inGoal = false;
    for (var i = 0; i < mGoalStrengthVector.length; i++) {
      mGoalStrengthVector[i] = 0;
    }
  }

  String? getName() => mName;

  void setName(String name) {
    mName = name;
  }

  void setType(SolverVariableType type, String? prefix) {
    mType = type;
  }

  @override
  int compareTo(SolverVariable v) => id - v.id;

  @override
  String toString() => mName != null ? '$mName' : '$id';
}
