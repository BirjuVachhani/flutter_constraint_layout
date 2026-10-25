// Copyright (C) 2020 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.PriorityGoalRow (upstream pinned
// in UPSTREAM.md).

import 'array_row.dart';
import 'cache.dart';
import 'linear_system.dart';
import 'solver_variable.dart';

/// Implements a row containing goals taking priorities into account.
class PriorityGoalRow extends ArrayRow {
  static const double _epsilon = 0.0001;
  static const int _notFound = -1;

  List<SolverVariable?> _arrayGoals = List<SolverVariable?>.filled(128, null);
  List<SolverVariable?> _sortArray = List<SolverVariable?>.filled(128, null);
  int _numGoals = 0;
  late final GoalVariableAccessor mAccessor = GoalVariableAccessor(this);

  Cache mCache;

  PriorityGoalRow(Cache cache) : mCache = cache, super(cache);

  @override
  void clear() {
    _numGoals = 0;
    mConstantValue = 0;
  }

  @override
  bool isEmpty() => _numGoals == 0;

  @override
  SolverVariable? getPivotCandidate(LinearSystem system, List<bool>? avoid) {
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
    error.mGoalStrengthVector[error.strength] = 1;
    _addToGoal(error);
  }

  void _addToGoal(SolverVariable variable) {
    if (_numGoals + 1 > _arrayGoals.length) {
      _arrayGoals = [
        ..._arrayGoals,
        ...List<SolverVariable?>.filled(_arrayGoals.length, null),
      ];
      _sortArray = [..._arrayGoals];
    }
    _arrayGoals[_numGoals] = variable;
    _numGoals++;

    // Upstream parity: this compares the just-added element with itself, so
    // the sort branch never runs; kept for fidelity.
    if (_numGoals > 1 && _arrayGoals[_numGoals - 1]!.id > variable.id) {
      for (var i = 0; i < _numGoals; i++) {
        _sortArray[i] = _arrayGoals[i];
      }
      final sorted = _sortArray.sublist(0, _numGoals)
        ..sort((a, b) => a!.id - b!.id);
      for (var i = 0; i < _numGoals; i++) {
        _arrayGoals[i] = sorted[i];
      }
    }

    variable.inGoal = true;
    variable.addToRow(this);
  }

  void _removeGoal(SolverVariable variable) {
    for (var i = 0; i < _numGoals; i++) {
      if (identical(_arrayGoals[i], variable)) {
        for (var j = i; j < _numGoals - 1; j++) {
          _arrayGoals[j] = _arrayGoals[j + 1];
        }
        _numGoals--;
        variable.inGoal = false;
        return;
      }
    }
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
    for (var i = 0; i < currentSize; i++) {
      final solverVariable = rowVariables.getVariable(i)!;
      final value = rowVariables.getVariableValue(i);
      mAccessor.init(solverVariable);
      if (mAccessor.addToGoal(goalVariable, value)) {
        _addToGoal(solverVariable);
      }
      mConstantValue += definition.mConstantValue * value;
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

  bool addToGoal(SolverVariable other, double value) {
    if (mVariable.inGoal) {
      var empty = true;
      for (var i = 0; i < SolverVariable.MAX_STRENGTH; i++) {
        mVariable.mGoalStrengthVector[i] +=
            other.mGoalStrengthVector[i] * value;
        final v = mVariable.mGoalStrengthVector[i];
        if (v.abs() < PriorityGoalRow._epsilon) {
          mVariable.mGoalStrengthVector[i] = 0;
        } else {
          empty = false;
        }
      }
      if (empty) {
        mRow._removeGoal(mVariable);
      }
    } else {
      for (var i = 0; i < SolverVariable.MAX_STRENGTH; i++) {
        final strength = other.mGoalStrengthVector[i];
        if (strength != 0) {
          var v = value * strength;
          if (v.abs() < PriorityGoalRow._epsilon) {
            v = 0;
          }
          mVariable.mGoalStrengthVector[i] = v;
        } else {
          mVariable.mGoalStrengthVector[i] = 0;
        }
      }
      return true;
    }
    return false;
  }

  void add(SolverVariable other) {
    for (var i = 0; i < SolverVariable.MAX_STRENGTH; i++) {
      mVariable.mGoalStrengthVector[i] += other.mGoalStrengthVector[i];
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

  bool isSmallerThan(SolverVariable other) {
    for (var i = SolverVariable.MAX_STRENGTH - 1; i >= 0; i--) {
      final comparedValue = other.mGoalStrengthVector[i];
      final value = mVariable.mGoalStrengthVector[i];
      // Divergence from upstream, which compares exactly: strengths within
      // epsilon of each other are a tie, so the candidate found first keeps
      // the pivot. Upstream computes in 32-bit float and this port in double,
      // so an exact tie carries different rounding noise in each, and the
      // exact comparison broke it differently: in a weighted chain whose
      // content does not fit a track (a grid tile as tall as its row), the
      // two picks reached solutions tens of pixels apart. See UPSTREAM.md.
      if ((value - comparedValue).abs() < PriorityGoalRow._epsilon) {
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
    for (var i = 0; i < mVariable.mGoalStrengthVector.length; i++) {
      mVariable.mGoalStrengthVector[i] = 0;
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
