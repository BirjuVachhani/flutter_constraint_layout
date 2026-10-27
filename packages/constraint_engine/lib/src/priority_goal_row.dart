// Copyright (C) 2020 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.PriorityGoalRow (upstream pinned
// in UPSTREAM.md).
//
// Java floats: the goal strength vectors are Float32Lists, each update is one
// float operation per Java expression (jfloat.dart), and goals compare
// exactly, as upstream's do, except in a system whose
// LinearSystem.goalTieEpsilon is set (containers with a GridCore).

import 'array_linked_variables.dart';
import 'array_row.dart';
import 'cache.dart';
import 'debug/solver_trace.dart';
import 'jfloat.dart';
import 'linear_system.dart';
import 'solver_variable.dart';

/// Implements a row containing goals taking priorities into account.
class PriorityGoalRow extends ArrayRow {
  /// Java's `EPSILON = 0.0001f`.
  static const double _epsilon = kEps0001;

  /// The tie tolerance of the port's former comparison (a double), kept
  /// only for [LinearSystem.goalTieEpsilon].
  static const double _tieEpsilon = 0.0001;
  static const int _notFound = -1;

  /// Whether the current [getPivotCandidate] compares goals with the tie
  /// tolerance ([LinearSystem.goalTieEpsilon]) instead of exactly.
  bool _tieMode = false;

  /// Upstream's goal array; `[0, _numGoals)` is the goal, in order. Always a
  /// fixed-length list (it grows by copying, as Arrays.copyOf does), so
  /// element access stays monomorphic. Upstream's mSortArray served only the
  /// dead sort branch of upstream's addToGoal (see [_addToGoal]) and is not
  /// kept.
  List<SolverVariable?> _arrayGoals = List<SolverVariable?>.filled(128, null);
  int _numGoals = 0;

  /// Not upstream: true while no variable occurs twice in the goal. Set by
  /// [clear] (an empty goal) and cleared for good by an append of a variable
  /// that may already be in a goal ([SolverVariable.goalOccurrences] not 0);
  /// see [_removeGoal].
  bool _unique = true;

  late final GoalVariableAccessor mAccessor = GoalVariableAccessor(this);

  Cache mCache;

  PriorityGoalRow(Cache cache) : mCache = cache, super(cache);

  @override
  void clear() {
    // Not upstream: the entries leave the goal, so each one's occurrence
    // count drops (see SolverVariable.goalOccurrences). Upstream only resets
    // the count of entries.
    for (var i = 0; i < _numGoals; i++) {
      _arrayGoals[i]!.goalOccurrences--;
    }
    _numGoals = 0;
    _unique = true;
    mConstantValue = 0;
  }

  @override
  bool isEmpty() => _numGoals == 0;

  @override
  SolverVariable? getPivotCandidate(LinearSystem system, List<bool>? avoid) {
    _tieMode = system.goalTieEpsilon;
    var pivot = _notFound;
    for (var i = 0; i < _numGoals; i++) {
      final variable = _arrayGoals[i]!;
      if (avoid![variable.id]) {
        continue;
      }
      mAccessor.init(variable);
      if (pivot == _notFound) {
        if (mAccessor.isNegative()) {
          pivot = i;
        }
      } else if (mAccessor.isSmallerThan(_arrayGoals[pivot]!)) {
        pivot = i;
      }
    }
    if (pivot == _notFound) {
      return null;
    }
    return _arrayGoals[pivot];
  }

  @override
  void addError(SolverVariable error) {
    mAccessor.init(error);
    mAccessor.reset();
    error.mGoalStrengthVectorDirty = true;
    error.mGoalStrengthVector[error.strength] = 1;
    _addToGoal(error);
    if (kSolverTrace) SolverTrace.goalVector(error);
  }

  void _addToGoal(SolverVariable variable) {
    if (_numGoals + 1 > _arrayGoals.length) {
      final length = _arrayGoals.length;
      _arrayGoals = List<SolverVariable?>.filled(length * 2, null)
        ..setRange(0, length, _arrayGoals);
    }
    // Not upstream: an append of a variable that is already in some goal can
    // make it occur twice here, so _removeGoal must go back to upstream's
    // forward search.
    if (variable.goalOccurrences != 0) {
      _unique = false;
    }
    _arrayGoals[_numGoals] = variable;
    _numGoals++;
    variable.goalOccurrences++;

    // Upstream then sorts the goal when `mArrayGoals[mNumGoals - 1].id >
    // variable.id`. That element is the variable just stored, so the test is
    // `variable.id > variable.id`, always false: dead code, not ported.

    variable.inGoal = true;
    variable.addToRow(this);
  }

  /// Upstream's removeGoal: take the first occurrence of [variable] out of
  /// the goal, keeping the order of the rest.
  ///
  /// Representation change (upstream searches from the front every time,
  /// over goals of thousands of variables on chain-heavy screens, and the
  /// goal removed is usually near the end). The array, its order and the
  /// shift are upstream's; only the search differs, and finds the same
  /// entry:
  /// - while [SolverVariable.goalOccurrences] is 0 the variable is in no
  ///   goal array, so upstream's search would find nothing and change
  ///   nothing, and this returns at once;
  /// - while [_unique] holds, the variable occurs at most once here, so the
  ///   last occurrence, found searching from the back, is the first one;
  /// - otherwise this searches from the front, as upstream does.
  /// [_unique] holds from [clear] (empty) until an append of a variable whose
  /// count is not 0; an append of one whose count is 0 adds its only
  /// occurrence, and a removal cannot make one twice.
  void _removeGoal(SolverVariable variable) {
    if (variable.goalOccurrences == 0) {
      return;
    }
    var i = -1;
    if (_unique) {
      for (var k = _numGoals - 1; k >= 0; k--) {
        if (identical(_arrayGoals[k], variable)) {
          i = k;
          break;
        }
      }
    } else {
      for (var k = 0; k < _numGoals; k++) {
        if (identical(_arrayGoals[k], variable)) {
          i = k;
          break;
        }
      }
    }
    if (i < 0) {
      return;
    }
    for (var j = i; j < _numGoals - 1; j++) {
      _arrayGoals[j] = _arrayGoals[j + 1];
    }
    _numGoals--;
    variable.goalOccurrences--;
    variable.inGoal = false;
    if (kSolverTrace) SolverTrace.goalRemoved(variable);
  }

  @override
  void updateFromRow(
    LinearSystem system,
    ArrayRow definition,
    bool removeFromDefinition,
  ) {
    final goalVariable = definition.mVariable;
    if (goalVariable == null) {
      return;
    }

    final rowVariables = definition.variables;
    final currentSize = rowVariables.getCurrentSize();
    // Representation change: the definition's entries in linked order,
    // walked once from the head instead of once per index by getVariable(i)
    // and getVariableValue(i). The loop changes the goal, goal vectors and
    // client lists, never the definition's list, so the slot reached after i
    // steps is the one both reach, and the variable (the same index
    // expression, with the same RangeError for a bad id) and the value read
    // there are theirs. Past the end of the chain the loop calls them as
    // before (getVariable answers null, and the null check throws).
    final alv = rowVariables is ArrayLinkedVariables ? rowVariables : null;
    var slot = alv == null ? ArrayLinkedVariables.NONE : alv.getHead();
    for (var i = 0; i < currentSize; i++) {
      final SolverVariable solverVariable;
      final double value;
      if (slot != ArrayLinkedVariables.NONE) {
        final v = alv!.mCache.mIndexedVariables[alv.getId(slot)];
        value = alv.getValue(slot);
        slot = alv.getNextIndice(slot);
        solverVariable = v!;
      } else {
        solverVariable = rowVariables.getVariable(i)!;
        value = rowVariables.getVariableValue(i);
      }
      mAccessor.init(solverVariable);
      if (mAccessor.addToGoal(goalVariable, value)) {
        _addToGoal(solverVariable);
      }
      if (kSolverTrace && solverVariable.inGoal) {
        SolverTrace.goalVector(solverVariable);
      }
      mConstantValue = fadd(
        mConstantValue,
        fmul(definition.mConstantValue, value),
      );
    }
    _removeGoal(goalVariable);
  }

  @override
  String toString() {
    var result = '';
    result += ' goal -> ($mConstantValue) : ';
    for (var i = 0; i < _numGoals; i++) {
      final v = _arrayGoals[i]!;
      mAccessor.init(v);
      result += '$mAccessor ';
    }
    return result;
  }
}

class GoalVariableAccessor {
  GoalVariableAccessor(this.mRow);

  late SolverVariable mVariable;
  final PriorityGoalRow mRow;

  void init(SolverVariable variable) {
    mVariable = variable;
  }

  /// Substitute [other]'s definition (scaled by [value], a Java float) into
  /// this variable's goal vector. Returns true when the variable was not in
  /// the goal yet and must be appended.
  bool addToGoal(SolverVariable other, double value) {
    mVariable.mGoalStrengthVectorDirty = true;
    final goal = mVariable.mGoalStrengthVector;
    final otherGoal = other.mGoalStrengthVector;
    if (mVariable.inGoal) {
      var empty = true;
      for (var i = 0; i < SolverVariable.MAX_STRENGTH; i++) {
        // Java: goal[i] += other[i] * value, two float roundings.
        goal[i] = fadd(goal[i], fmul(otherGoal[i], value));
        final v = goal[i];
        if (v.abs() < PriorityGoalRow._epsilon) {
          goal[i] = 0;
        } else {
          empty = false;
        }
      }
      if (empty) {
        mRow._removeGoal(mVariable);
      }
    } else {
      for (var i = 0; i < SolverVariable.MAX_STRENGTH; i++) {
        final strength = otherGoal[i];
        if (strength != 0) {
          var v = fmul(value, strength);
          if (v.abs() < PriorityGoalRow._epsilon) {
            v = 0;
          }
          goal[i] = v;
        } else {
          goal[i] = 0;
        }
      }
      return true;
    }
    return false;
  }

  void add(SolverVariable other) {
    mVariable.mGoalStrengthVectorDirty = true;
    for (var i = 0; i < SolverVariable.MAX_STRENGTH; i++) {
      mVariable.mGoalStrengthVector[i] = fadd(
        mVariable.mGoalStrengthVector[i],
        other.mGoalStrengthVector[i],
      );
      final value = mVariable.mGoalStrengthVector[i];
      if (value.abs() < PriorityGoalRow._epsilon) {
        mVariable.mGoalStrengthVector[i] = 0;
      }
    }
  }

  bool isNegative() {
    for (var i = SolverVariable.MAX_STRENGTH - 1; i >= 0; i--) {
      final value = mVariable.mGoalStrengthVector[i];
      if (value > 0) {
        return false;
      }
      if (value < 0) {
        return true;
      }
    }
    return false;
  }

  /// Whether this variable's goal vector is lexicographically smaller than
  /// [other]'s, from the strongest strength down. Exact, as upstream's
  /// (both vectors hold the binary32 values Java holds), except in a system
  /// with [LinearSystem.goalTieEpsilon] set.
  bool isSmallerThan(SolverVariable other) {
    final tieMode = mRow._tieMode;
    for (var i = SolverVariable.MAX_STRENGTH - 1; i >= 0; i--) {
      final comparedValue = other.mGoalStrengthVector[i];
      final value = mVariable.mGoalStrengthVector[i];
      if (tieMode) {
        // Not upstream, for containers holding a GridCore only (Grid has no
        // Android oracle): strengths within 0.0001 of each other are a tie,
        // so the candidate found first keeps the pivot. In an
        // over-constrained weighted grid (a tile as tall as its row), two
        // candidates can tie, and the exact comparison can steer the solve
        // to a collapsed solution tens of pixels away. See UPSTREAM.md.
        if ((value - comparedValue).abs() < PriorityGoalRow._tieEpsilon) {
          continue;
        }
        return value < comparedValue;
      }
      if (value == comparedValue) {
        continue;
      }
      return value < comparedValue;
    }
    return false;
  }

  bool isNull() {
    for (var i = 0; i < SolverVariable.MAX_STRENGTH; i++) {
      if (mVariable.mGoalStrengthVector[i] != 0) {
        return false;
      }
    }
    return true;
  }

  void reset() {
    final goal = mVariable.mGoalStrengthVector;
    for (var i = 0; i < SolverVariable.MAX_STRENGTH; i++) {
      goal[i] = 0;
    }
  }

  @override
  String toString() {
    var result = '[ ';
    for (var i = 0; i < SolverVariable.MAX_STRENGTH; i++) {
      result += '${mVariable.mGoalStrengthVector[i]} ';
    }
    result += '] $mVariable';
    return result;
  }
}
