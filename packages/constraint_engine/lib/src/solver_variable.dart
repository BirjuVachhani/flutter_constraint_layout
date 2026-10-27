// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.SolverVariable (upstream pinned
// in UPSTREAM.md). Debug naming/printing branches (INTERNAL_DEBUG,
// VAR_USE_HASH, DO_NOT_USE) omitted.
//
// Java floats: computedValue, mSynonymDelta and the two strength vectors
// hold binary32 values (jfloat.dart), and the vectors are Float32Lists.

import 'dart:typed_data';

import 'array_row.dart';
import 'debug/solver_trace.dart';
import 'jfloat.dart';
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

  /// The solved value: a Java float, so always a binary32 value.
  double computedValue = 0;
  bool isFinalValue = false;

  /// Never written by upstream (always 0); enforceBFS reads it.
  final Float32List mStrengthVector = Float32List(MAX_STRENGTH);

  /// The goal's strength vector for this variable (PriorityGoalRow).
  final Float32List mGoalStrengthVector = Float32List(MAX_STRENGTH);

  /// Whether [mGoalStrengthVector] may hold a nonzero entry: set by every
  /// writer of the vector (PriorityGoalRow), cleared by [reset]. Not
  /// upstream: reset runs for every variable of the system on every solve,
  /// and most variables never enter the goal, so it clears only a vector
  /// that was written. Upstream's Arrays.fill leaves the same all-zero
  /// vector.
  bool mGoalStrengthVectorDirty = false;

  SolverVariableType mType;

  /// The rows that use this variable, in the order they were added (upstream's
  /// array; only `[0, mClientEquationsCount)` is ever read). Always a
  /// fixed-length list: it grows by copying into a list twice as long, the
  /// contents upstream's Arrays.copyOf gives, so element access stays
  /// monomorphic (a growable list behind the same field type would make every
  /// access polymorphic).
  List<ArrayRow?> mClientEquations = List<ArrayRow?>.filled(16, null);
  int mClientEquationsCount = 0;

  /// Not upstream: the OR of [ArrayRow.mClientBit] over the rows added to
  /// [mClientEquations] since the list was last emptied, so a superset of the
  /// bits of the rows in `[0, mClientEquationsCount)`. [addToRow] skips its
  /// duplicate scan when the row's bit is clear. Exact: every append ORs the
  /// appended row's bit in, a removal only takes a row out (a superset stays
  /// a superset), every write of 0 to [mClientEquationsCount] writes 0 here,
  /// and a row's bit never changes. So a clear bit means no row in the list
  /// is that row: the scan would find nothing and fall through to the append,
  /// which is what the skip does. Only this file writes the list and its
  /// count.
  int _clientMask = 0;

  int usageInRowCount = 0;

  /// Not upstream: how many entries of the goal arrays of every
  /// [PriorityGoalRow] hold this variable. Maintained only by
  /// PriorityGoalRow (an append adds one, a removal or a clear of the array
  /// takes one away), and not touched by [reset], which does not take the
  /// variable out of a goal array. While it is 0 the variable is in no goal
  /// array, which lets PriorityGoalRow find a goal without upstream's linear
  /// search; see PriorityGoalRow.
  int goalOccurrences = 0;

  /// Whether this variable is a synonym of [mSynonym] (plus
  /// [mSynonymDelta]). A field upstream; here a getter and setter over a
  /// private field so that debug builds can count the synonyms that exist
  /// ([debugLiveSynonyms]). Release builds store and load the field as
  /// before.
  bool get mIsSynonym => _isSynonym;
  set mIsSynonym(bool value) {
    assert(
      value == _isSynonym || _debugCountSynonym(value),
      'counts the live synonyms for the debug check of the synonym-scan '
      'skip in LinearSystem.addEqualityConstant; the count must see every '
      'change of mIsSynonym, and the counting itself always succeeds',
    );
    _isSynonym = value;
  }

  bool _isSynonym = false;

  /// Debug only (called from an assert): counts a change of [mIsSynonym] to
  /// [value]. Returns true.
  static bool _debugCountSynonym(bool value) {
    debugLiveSynonyms += value ? 1 : -1;
    return true;
  }

  /// Debug builds only (0 in release builds): how many SolverVariables in
  /// this isolate have [mIsSynonym] set, counted by its setter, through which
  /// every write goes. LinearSystem's debug check of the synonym-scan skip
  /// runs its O(n) scan only while this is not 0: with no synonym anywhere,
  /// no variable can be a synonym of the one being fixed, so the check holds
  /// without the scan.
  static int debugLiveSynonyms = 0;

  int mSynonym = -1;

  /// A Java float, so always a binary32 value.
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
    final bit = row.mClientBit;
    // The duplicate scan runs only when [row]'s bit is set in _clientMask;
    // a clear bit proves [row] is not in the list (see _clientMask).
    if ((_clientMask & bit) != 0) {
      for (var i = 0; i < mClientEquationsCount; i++) {
        if (identical(mClientEquations[i], row)) {
          return;
        }
      }
    }
    if (mClientEquationsCount >= mClientEquations.length) {
      final length = mClientEquations.length;
      mClientEquations = List<ArrayRow?>.filled(length * 2, null)
        ..setRange(0, length, mClientEquations);
    }
    mClientEquations[mClientEquationsCount] = row;
    mClientEquationsCount++;
    _clientMask |= bit;
  }

  void removeFromRow(ArrayRow row) {
    // A clear bit proves [row] is not in the list (see _clientMask): the
    // search would find nothing and change nothing.
    if ((_clientMask & row.mClientBit) == 0) {
      return;
    }
    // Representation change: upstream searches from the front for the first
    // occurrence. A row occurs at most once in the list (addToRow appends a
    // row only when the list does not hold it, removals take entries out,
    // and the list is emptied only as a whole), so the search from the back
    // finds the same entry, and the row removed is usually one added
    // recently. The shift of the entries after it is upstream's.
    final count = mClientEquationsCount;
    for (var i = count - 1; i >= 0; i--) {
      if (identical(mClientEquations[i], row)) {
        for (var j = i; j < count - 1; j++) {
          mClientEquations[j] = mClientEquations[j + 1];
        }
        mClientEquationsCount--;
        if (mClientEquationsCount == 0) {
          _clientMask = 0;
        }
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
    _clientMask = 0;
  }

  /// Fix this variable at [value] (a Java float: stored as its binary32
  /// value) and substitute it into every row that uses it.
  void setFinalValue(LinearSystem system, double value) {
    setFinalFloat(system, f32(value));
  }

  /// [setFinalValue] for a [value] that is already binary32, as every value
  /// the solver computes is (row constants, float sums, ints within 2^24):
  /// the solver's own callers skip the rounding, which would change nothing.
  void setFinalFloat(LinearSystem system, double value) {
    assert(
      isF32(value),
      'setFinalFloat($value): the value must already be a binary32 value '
      '(Java passes a float); callers with any other double use '
      'setFinalValue, which rounds it first',
    );
    if (kSolverTrace) SolverTrace.finalValue(this, value);
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
    _clientMask = 0;
  }

  /// Make this variable a synonym of [synonymVariable] plus [value] (a Java
  /// float: stored as its binary32 value). Nothing in the core calls it at
  /// the default optimization level; LinearSystem counts the calls so its
  /// addEqualityConstant can skip a synonym scan that would find nothing.
  void setSynonym(
    LinearSystem system,
    SolverVariable synonymVariable,
    double value,
  ) {
    value = f32(value);
    if (kSolverTrace) SolverTrace.synonym(this, synonymVariable, value);
    system.noteSynonym();
    mIsSynonym = true;
    mSynonym = synonymVariable.id;
    mSynonymDelta = value;
    final count = mClientEquationsCount;
    mDefinitionId = -1;
    for (var i = 0; i < count; i++) {
      mClientEquations[i]!.updateFromSynonymVariable(system, this, false);
    }
    mClientEquationsCount = 0;
    _clientMask = 0;
    system.displayReadableRows();
  }

  void reset() {
    // Not upstream: a variable already in the state this method leaves is
    // left alone. Each field below already holds, bit for bit, the value the
    // method writes (the doubles +0.0, not -0.0), the client list is empty so
    // the clearing loop runs no iteration, and the goal vector is not dirty
    // so it is not cleared: the writes would change nothing. About 60% of
    // the resets of a measure find the variable so (each anchor's variable is
    // reset at the end of a layout and again by the next LinearSystem.reset,
    // and a widget's unused anchors are reset at every layout).
    if (id == -1 &&
        mType == SolverVariableType.unknown &&
        mDefinitionId == -1 &&
        mClientEquationsCount == 0 &&
        _clientMask == 0 &&
        usageInRowCount == 0 &&
        strength == STRENGTH_NONE &&
        !isFinalValue &&
        !_isSynonym &&
        mSynonym == -1 &&
        !inGoal &&
        !mGoalStrengthVectorDirty &&
        mName == null &&
        _isPositiveZero(computedValue) &&
        _isPositiveZero(mSynonymDelta)) {
      assert(
        _goalStrengthVectorIsZero(),
        'SolverVariable.reset: the goal strength vector of $this holds a '
        'nonzero entry although no writer marked it dirty, so a code path '
        'writes mGoalStrengthVector without setting mGoalStrengthVectorDirty '
        'and reset would leave a stale goal strength for the next solve',
      );
      return;
    }
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
    _clientMask = 0;
    usageInRowCount = 0;
    inGoal = false;
    // Upstream: Arrays.fill(mGoalStrengthVector, 0). A vector nothing wrote
    // is all zeros already (see mGoalStrengthVectorDirty); a plain loop is
    // faster than Float32List.fillRange.
    if (mGoalStrengthVectorDirty) {
      final goal = mGoalStrengthVector;
      for (var i = 0; i < MAX_STRENGTH; i++) {
        goal[i] = 0;
      }
      mGoalStrengthVectorDirty = false;
    }
    assert(
      _goalStrengthVectorIsZero(),
      'SolverVariable.reset: the goal strength vector of $this holds a '
      'nonzero entry although no writer marked it dirty, so a code path '
      'writes mGoalStrengthVector without setting mGoalStrengthVectorDirty '
      'and reset would leave a stale goal strength for the next solve',
    );
  }

  /// Whether [x] is +0.0, the value [reset] writes (-0.0 == 0 is true, but
  /// its bits differ).
  @pragma('vm:prefer-inline')
  static bool _isPositiveZero(double x) => x == 0 && !x.isNegative;

  bool _goalStrengthVectorIsZero() {
    for (var i = 0; i < MAX_STRENGTH; i++) {
      if (mGoalStrengthVector[i] != 0) {
        return false;
      }
    }
    return true;
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
