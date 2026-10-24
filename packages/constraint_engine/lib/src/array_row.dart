// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.ArrayRow (upstream pinned in
// UPSTREAM.md). Debug display and FULL_NEW_CHECK validation omitted.
//
// Java overloads are split into named methods:
//   createRowEquals(v, value)        -> createRowEqualsConstant
//   createRowEquals(a, b, margin)    -> createRowEquals
//   createRowGreaterThan(a, b, slack) -> createRowGreaterThanConstant

import 'array_linked_variables.dart';
import 'cache.dart';
import 'linear_system.dart';
import 'solver_variable.dart';

/// Storage backend for one row's variables. Implemented by
/// [ArrayLinkedVariables] and SolverVariableValues.
abstract class ArrayRowVariables {
  int getCurrentSize();
  SolverVariable? getVariable(int index);
  double getVariableValue(int index);
  double get(SolverVariable variable);
  int indexOf(SolverVariable variable);
  void display();
  void clear();
  bool contains(SolverVariable variable);
  void put(SolverVariable variable, double value);
  int sizeInBytes();
  void invert();
  double remove(SolverVariable v, bool removeFromDefinition);
  void divideByAmount(double amount);
  void add(SolverVariable v, double value, bool removeFromDefinition);
  double use(ArrayRow definition, bool removeFromDefinition);
}

class ArrayRow implements Row {
  SolverVariable? mVariable;
  double mConstantValue = 0;
  bool mUsed = false;

  final List<SolverVariable> mVariablesToUpdate = [];

  late ArrayRowVariables variables;

  bool mIsSimpleDefinition = false;

  ArrayRow.raw();

  ArrayRow(Cache cache) {
    variables = ArrayLinkedVariables(this, cache);
  }

  bool hasKeyVariable() {
    return !((mVariable == null) ||
        (mVariable!.mType != SolverVariableType.unrestricted &&
            mConstantValue < 0));
  }

  @override
  String toString() => toReadableString();

  String toReadableString() {
    var s = '';
    if (mVariable == null) {
      s += '0';
    } else {
      s += '$mVariable';
    }
    s += ' = ';
    var addedVariable = false;
    if (mConstantValue != 0) {
      s += '$mConstantValue';
      addedVariable = true;
    }
    final count = variables.getCurrentSize();
    for (var i = 0; i < count; i++) {
      final v = variables.getVariable(i);
      if (v == null) {
        continue;
      }
      var amount = variables.getVariableValue(i);
      if (amount == 0) {
        continue;
      }
      final name = v.toString();
      if (!addedVariable) {
        if (amount < 0) {
          s += '- ';
          amount *= -1;
        }
      } else {
        if (amount > 0) {
          s += ' + ';
        } else {
          s += ' - ';
          amount *= -1;
        }
      }
      if (amount == 1) {
        s += name;
      } else {
        s += '$amount $name';
      }
      addedVariable = true;
    }
    if (!addedVariable) {
      s += '0.0';
    }
    return s;
  }

  void reset() {
    mVariable = null;
    variables.clear();
    mConstantValue = 0;
    mIsSimpleDefinition = false;
  }

  bool hasVariable(SolverVariable v) => variables.contains(v);

  ArrayRow createRowDefinition(SolverVariable variable, int value) {
    mVariable = variable;
    variable.computedValue = value.toDouble();
    mConstantValue = value.toDouble();
    mIsSimpleDefinition = true;
    return this;
  }

  ArrayRow createRowEqualsConstant(SolverVariable variable, int value) {
    if (value < 0) {
      mConstantValue = -1.0 * value;
      variables.put(variable, 1);
    } else {
      mConstantValue = value.toDouble();
      variables.put(variable, -1);
    }
    return this;
  }

  ArrayRow createRowEquals(
      SolverVariable variableA, SolverVariable variableB, int margin) {
    var inverse = false;
    if (margin != 0) {
      var m = margin;
      if (m < 0) {
        m = -1 * m;
        inverse = true;
      }
      mConstantValue = m.toDouble();
    }
    if (!inverse) {
      variables.put(variableA, -1);
      variables.put(variableB, 1);
    } else {
      variables.put(variableA, 1);
      variables.put(variableB, -1);
    }
    return this;
  }

  ArrayRow addSingleError(SolverVariable error, int sign) {
    variables.put(error, sign.toDouble());
    return this;
  }

  ArrayRow createRowGreaterThan(SolverVariable variableA,
      SolverVariable variableB, SolverVariable slack, int margin) {
    var inverse = false;
    if (margin != 0) {
      var m = margin;
      if (m < 0) {
        m = -1 * m;
        inverse = true;
      }
      mConstantValue = m.toDouble();
    }
    if (!inverse) {
      variables.put(variableA, -1);
      variables.put(variableB, 1);
      variables.put(slack, 1);
    } else {
      variables.put(variableA, 1);
      variables.put(variableB, -1);
      variables.put(slack, -1);
    }
    return this;
  }

  ArrayRow createRowGreaterThanConstant(
      SolverVariable a, int b, SolverVariable slack) {
    mConstantValue = b.toDouble();
    variables.put(a, -1);
    return this;
  }

  ArrayRow createRowLowerThan(SolverVariable variableA, SolverVariable variableB,
      SolverVariable slack, int margin) {
    var inverse = false;
    if (margin != 0) {
      var m = margin;
      if (m < 0) {
        m = -1 * m;
        inverse = true;
      }
      mConstantValue = m.toDouble();
    }
    if (!inverse) {
      variables.put(variableA, -1);
      variables.put(variableB, 1);
      variables.put(slack, -1);
    } else {
      variables.put(variableA, 1);
      variables.put(variableB, -1);
      variables.put(slack, 1);
    }
    return this;
  }

  ArrayRow createRowEqualMatchDimensions(
      double currentWeight,
      double totalWeights,
      double nextWeight,
      SolverVariable variableStartA,
      SolverVariable variableEndA,
      SolverVariable variableStartB,
      SolverVariable variableEndB) {
    mConstantValue = 0;
    if (totalWeights == 0 || (currentWeight == nextWeight)) {
      // endA - startA == endB - startB
      variables.put(variableStartA, 1);
      variables.put(variableEndA, -1);
      variables.put(variableEndB, 1);
      variables.put(variableStartB, -1);
    } else {
      if (currentWeight == 0) {
        variables.put(variableStartA, 1);
        variables.put(variableEndA, -1);
      } else if (nextWeight == 0) {
        variables.put(variableStartB, 1);
        variables.put(variableEndB, -1);
      } else {
        final cw = currentWeight / totalWeights;
        final nw = nextWeight / totalWeights;
        final w = cw / nw;
        // endA - startA == w * (endB - startB)
        variables.put(variableStartA, 1);
        variables.put(variableEndA, -1);
        variables.put(variableEndB, w);
        variables.put(variableStartB, -w);
      }
    }
    return this;
  }

  ArrayRow createRowEqualDimension(
      double currentWeight,
      double totalWeights,
      double nextWeight,
      SolverVariable variableStartA,
      int marginStartA,
      SolverVariable variableEndA,
      int marginEndA,
      SolverVariable variableStartB,
      int marginStartB,
      SolverVariable variableEndB,
      int marginEndB) {
    if (totalWeights == 0 || (currentWeight == nextWeight)) {
      mConstantValue =
          (-marginStartA - marginEndA + marginStartB + marginEndB).toDouble();
      variables.put(variableStartA, 1);
      variables.put(variableEndA, -1);
      variables.put(variableEndB, 1);
      variables.put(variableStartB, -1);
    } else {
      final cw = currentWeight / totalWeights;
      final nw = nextWeight / totalWeights;
      final w = cw / nw;
      mConstantValue =
          -marginStartA - marginEndA + w * marginStartB + w * marginEndB;
      variables.put(variableStartA, 1);
      variables.put(variableEndA, -1);
      variables.put(variableEndB, w);
      variables.put(variableStartB, -w);
    }
    return this;
  }

  ArrayRow createRowCentering(
      SolverVariable variableA,
      SolverVariable variableB,
      int marginA,
      double bias,
      SolverVariable variableC,
      SolverVariable variableD,
      int marginB) {
    if (identical(variableB, variableC)) {
      // centering on the same position: 0 = A + D - 2 * B
      variables.put(variableA, 1);
      variables.put(variableD, 1);
      variables.put(variableB, -2);
      return this;
    }
    if (bias == 0.5) {
      // centered: 0 = A - B - C + D - Ma + Mb
      variables.put(variableA, 1);
      variables.put(variableB, -1);
      variables.put(variableC, -1);
      variables.put(variableD, 1);
      if (marginA > 0 || marginB > 0) {
        mConstantValue = (-marginA + marginB).toDouble();
      }
    } else if (bias <= 0) {
      // A = B + m
      variables.put(variableA, -1);
      variables.put(variableB, 1);
      mConstantValue = marginA.toDouble();
    } else if (bias >= 1) {
      // D = C - m
      variables.put(variableD, -1);
      variables.put(variableC, 1);
      mConstantValue = -marginB.toDouble();
    } else {
      variables.put(variableA, 1 * (1 - bias));
      variables.put(variableB, -1 * (1 - bias));
      variables.put(variableC, -1 * bias);
      variables.put(variableD, 1 * bias);
      if (marginA > 0 || marginB > 0) {
        mConstantValue = -marginA * (1 - bias) + marginB * bias;
      }
    }
    return this;
  }

  ArrayRow addErrorToRow(LinearSystem system, int strength) {
    variables.put(system.createErrorVariable(strength, 'ep'), 1);
    variables.put(system.createErrorVariable(strength, 'em'), -1);
    return this;
  }

  ArrayRow createRowDimensionPercent(
      SolverVariable variableA, SolverVariable variableC, double percent) {
    variables.put(variableA, -1);
    variables.put(variableC, percent);
    return this;
  }

  /// Create a constraint to express `A = B + (C - D) * ratio`.
  /// Used for ratio, e.g. `Right = Left + (Bottom - Top) * percent`.
  ArrayRow createRowDimensionRatio(SolverVariable variableA,
      SolverVariable variableB, SolverVariable variableC, SolverVariable variableD,
      double ratio) {
    variables.put(variableA, -1);
    variables.put(variableB, 1);
    variables.put(variableC, ratio);
    variables.put(variableD, -ratio);
    return this;
  }

  /// Create a constraint to express `At + (Ab-At)/2 = Bt + (Bb-Bt)/2 - angle`.
  ArrayRow createRowWithAngle(SolverVariable at, SolverVariable ab,
      SolverVariable bt, SolverVariable bb, double angleComponent) {
    variables.put(bt, 0.5);
    variables.put(bb, 0.5);
    variables.put(at, -0.5);
    variables.put(ab, -0.5);
    mConstantValue = -angleComponent;
    return this;
  }

  int sizeInBytes() {
    var size = 0;
    if (mVariable != null) {
      size += 4;
    }
    size += 4;
    size += 4;
    size += variables.sizeInBytes();
    return size;
  }

  void ensurePositiveConstant() {
    if (mConstantValue < 0) {
      mConstantValue *= -1;
      variables.invert();
    }
  }

  /// Pick a subject variable out of the existing ones: an unrestricted
  /// variable, or a negative new variable; otherwise an extra variable must be
  /// added to the system. Returns true if an extra variable is needed.
  bool chooseSubject(LinearSystem system) {
    var addedExtra = false;
    final pivotCandidate = chooseSubjectInVariables(system);
    if (pivotCandidate == null) {
      addedExtra = true;
    } else {
      pivot(pivotCandidate);
    }
    if (variables.getCurrentSize() == 0) {
      mIsSimpleDefinition = true;
    }
    return addedExtra;
  }

  SolverVariable? chooseSubjectInVariables(LinearSystem system) {
    SolverVariable? restrictedCandidate;
    SolverVariable? unrestrictedCandidate;
    double unrestrictedCandidateAmount = 0;
    double restrictedCandidateAmount = 0;
    var unrestrictedCandidateIsNew = false;
    var restrictedCandidateIsNew = false;

    final currentSize = variables.getCurrentSize();
    for (var i = 0; i < currentSize; i++) {
      final amount = variables.getVariableValue(i);
      final variable = variables.getVariable(i)!;
      if (variable.mType == SolverVariableType.unrestricted) {
        if (unrestrictedCandidate == null) {
          unrestrictedCandidate = variable;
          unrestrictedCandidateAmount = amount;
          unrestrictedCandidateIsNew = _isNew(variable, system);
        } else if (unrestrictedCandidateAmount > amount) {
          unrestrictedCandidate = variable;
          unrestrictedCandidateAmount = amount;
          unrestrictedCandidateIsNew = _isNew(variable, system);
        } else if (!unrestrictedCandidateIsNew && _isNew(variable, system)) {
          unrestrictedCandidate = variable;
          unrestrictedCandidateAmount = amount;
          unrestrictedCandidateIsNew = true;
        }
      } else if (unrestrictedCandidate == null) {
        if (amount < 0) {
          if (restrictedCandidate == null) {
            restrictedCandidate = variable;
            restrictedCandidateAmount = amount;
            restrictedCandidateIsNew = _isNew(variable, system);
          } else if (restrictedCandidateAmount > amount) {
            restrictedCandidate = variable;
            restrictedCandidateAmount = amount;
            restrictedCandidateIsNew = _isNew(variable, system);
          } else if (!restrictedCandidateIsNew && _isNew(variable, system)) {
            restrictedCandidate = variable;
            restrictedCandidateAmount = amount;
            restrictedCandidateIsNew = true;
          }
        }
      }
    }

    if (unrestrictedCandidate != null) {
      return unrestrictedCandidate;
    }
    return restrictedCandidate;
  }

  /// A variable is new if its usage count is zero or one (present in no row,
  /// or only in the row being inserted).
  bool _isNew(SolverVariable variable, LinearSystem system) {
    return variable.usageInRowCount <= 1;
  }

  void pivot(SolverVariable v) {
    if (mVariable != null) {
      // first, move back the variable to its column
      variables.put(mVariable!, -1);
      mVariable!.mDefinitionId = -1;
      mVariable = null;
    }

    final amount = variables.remove(v, true) * -1;
    mVariable = v;
    if (amount == 1) {
      return;
    }
    mConstantValue = mConstantValue / amount;
    variables.divideByAmount(amount);
  }

  // Row compatibility

  @override
  bool isEmpty() {
    return mVariable == null &&
        mConstantValue == 0 &&
        variables.getCurrentSize() == 0;
  }

  @override
  void updateFromRow(
      LinearSystem system, ArrayRow definition, bool removeFromDefinition) {
    final value = variables.use(definition, removeFromDefinition);

    mConstantValue += definition.mConstantValue * value;
    if (removeFromDefinition) {
      definition.mVariable!.removeFromRow(this);
    }
    if (LinearSystem.SIMPLIFY_SYNONYMS &&
        mVariable != null &&
        variables.getCurrentSize() == 0) {
      mIsSimpleDefinition = true;
      system.hasSimpleDefinition = true;
    }
  }

  @override
  void updateFromFinalVariable(
      LinearSystem system, SolverVariable? variable, bool removeFromDefinition) {
    if (variable == null || !variable.isFinalValue) {
      return;
    }
    final value = variables.get(variable);
    mConstantValue += variable.computedValue * value;
    variables.remove(variable, removeFromDefinition);
    if (removeFromDefinition) {
      variable.removeFromRow(this);
    }
    if (LinearSystem.SIMPLIFY_SYNONYMS && variables.getCurrentSize() == 0) {
      mIsSimpleDefinition = true;
      system.hasSimpleDefinition = true;
    }
  }

  void updateFromSynonymVariable(
      LinearSystem system, SolverVariable? variable, bool removeFromDefinition) {
    if (variable == null || !variable.mIsSynonym) {
      return;
    }
    final value = variables.get(variable);
    mConstantValue += variable.mSynonymDelta * value;
    variables.remove(variable, removeFromDefinition);
    if (removeFromDefinition) {
      variable.removeFromRow(this);
    }
    variables.add(
        system.mCache.mIndexedVariables[variable.mSynonym]!, value, removeFromDefinition);
    if (LinearSystem.SIMPLIFY_SYNONYMS && variables.getCurrentSize() == 0) {
      mIsSimpleDefinition = true;
      system.hasSimpleDefinition = true;
    }
  }

  // Upstream carries an always-true `all` flag with a dead slack-preferring
  // branch; only the live branch is ported.
  SolverVariable? _pickPivotInVariables(List<bool>? avoid, SolverVariable? exclude) {
    double value = 0;
    SolverVariable? pivot;

    final currentSize = variables.getCurrentSize();
    for (var i = 0; i < currentSize; i++) {
      final currentValue = variables.getVariableValue(i);
      if (currentValue < 0) {
        // We can return the first negative candidate as in
        // ArrayLinkedVariables they are already sorted by id.
        final v = variables.getVariable(i)!;
        if (!((avoid != null && avoid[v.id]) || identical(v, exclude))) {
          if (v.mType == SolverVariableType.slack ||
              v.mType == SolverVariableType.error) {
            if (currentValue < value) {
              value = currentValue;
              pivot = v;
            }
          }
        }
      }
    }
    return pivot;
  }

  SolverVariable? pickPivot(SolverVariable? exclude) =>
      _pickPivotInVariables(null, exclude);

  @override
  SolverVariable? getPivotCandidate(LinearSystem system, List<bool>? avoid) =>
      _pickPivotInVariables(avoid, null);

  @override
  void clear() {
    variables.clear();
    mVariable = null;
    mConstantValue = 0;
  }

  /// Used to initiate a goal from a given row (to see if we can remove an
  /// extra var).
  @override
  void initFromRow(Row row) {
    if (row is ArrayRow) {
      mVariable = null;
      variables.clear();
      for (var i = 0; i < row.variables.getCurrentSize(); i++) {
        final variable = row.variables.getVariable(i)!;
        final val = row.variables.getVariableValue(i);
        variables.add(variable, val, true);
      }
    }
  }

  @override
  void addError(SolverVariable error) {
    var weight = 1.0;
    if (error.strength == SolverVariable.STRENGTH_LOW) {
      weight = 1.0;
    } else if (error.strength == SolverVariable.STRENGTH_MEDIUM) {
      weight = 1e3;
    } else if (error.strength == SolverVariable.STRENGTH_HIGH) {
      weight = 1e6;
    } else if (error.strength == SolverVariable.STRENGTH_HIGHEST) {
      weight = 1e9;
    } else if (error.strength == SolverVariable.STRENGTH_EQUALITY) {
      weight = 1e12;
    }
    variables.put(error, weight);
  }

  @override
  SolverVariable? getKey() => mVariable;

  @override
  void updateFromSystem(LinearSystem system) {
    if (system.mRows.isEmpty) {
      return;
    }

    var done = false;
    while (!done) {
      final currentSize = variables.getCurrentSize();
      for (var i = 0; i < currentSize; i++) {
        final variable = variables.getVariable(i)!;
        if (variable.mDefinitionId != -1 ||
            variable.isFinalValue ||
            variable.mIsSynonym) {
          mVariablesToUpdate.add(variable);
        }
      }
      final size = mVariablesToUpdate.length;
      if (size > 0) {
        for (var i = 0; i < size; i++) {
          final variable = mVariablesToUpdate[i];
          if (variable.isFinalValue) {
            updateFromFinalVariable(system, variable, true);
          } else if (variable.mIsSynonym) {
            updateFromSynonymVariable(system, variable, true);
          } else {
            updateFromRow(system, system.mRows[variable.mDefinitionId]!, true);
          }
        }
        mVariablesToUpdate.clear();
      } else {
        done = true;
      }
    }
    if (LinearSystem.SIMPLIFY_SYNONYMS &&
        mVariable != null &&
        variables.getCurrentSize() == 0) {
      mIsSimpleDefinition = true;
      system.hasSimpleDefinition = true;
    }
  }
}
