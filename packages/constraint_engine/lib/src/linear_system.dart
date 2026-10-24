// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.LinearSystem (upstream pinned in
// UPSTREAM.md). Metrics instrumentation and debug printing omitted; dead
// branches guarded by DO_NOT_USE upstream are not ported.
//
// Java overloads are split into named methods:
//   addEquality(a, b, margin, strength) -> addEquality
//   addEquality(a, value)               -> addEqualityConstant

import 'dart:math' as math;

import 'array_row.dart';
import 'cache.dart';
import 'constraint_anchor.dart';
import 'constraint_widget.dart';
import 'priority_goal_row.dart';
import 'solver_variable.dart';
import 'solver_variable_values.dart';

/// The row contract used by the solver: implemented by [ArrayRow] and
/// [PriorityGoalRow].
abstract class Row {
  SolverVariable? getPivotCandidate(LinearSystem system, List<bool>? avoid);
  void clear();
  void initFromRow(Row row);
  void addError(SolverVariable variable);
  void updateFromSystem(LinearSystem system);
  SolverVariable? getKey();
  bool isEmpty();
  void updateFromRow(LinearSystem system, ArrayRow definition, bool b);
  void updateFromFinalVariable(
    LinearSystem system,
    SolverVariable variable,
    bool removeFromDefinition,
  );
}

/// An ArrayRow backed by the hash-based SolverVariableValues storage, used
/// when [LinearSystem.OPTIMIZED_ENGINE] is enabled.
class ValuesRow extends ArrayRow {
  ValuesRow(Cache cache) : super.raw() {
    variables = SolverVariableValues(this, cache);
  }
}

/// Represents and solves a system of linear equations.
///
/// This is the Cassowary-style solver that
/// [ConstraintWidgetContainer.layout] falls back to. Get a variable for each
/// anchor with [createObjectVariable], add equations with [addEquality],
/// [addGreaterThan], [addLowerThan], [addCentering], and the like, call
/// [minimize], then read the results with [getObjectVariableValue]. An
/// equation's `strength` is one of the [SolverVariable] `STRENGTH_`
/// constants: [SolverVariable.STRENGTH_FIXED] makes it required, and the
/// solver satisfies the others by order of strength.
class LinearSystem {
  static bool USE_DEPENDENCY_ORDERING = false;
  static bool USE_BASIC_SYNONYMS = true;
  static bool SIMPLIFY_SYNONYMS = true;
  static bool USE_SYNONYMS = true;
  static bool SKIP_COLUMNS = true;
  static bool OPTIMIZED_ENGINE = false;

  /// Default size for the object pools.
  ///
  /// Instance field, not static: upstream 2.2.1 (change I8952e, b/376718273)
  /// fixed a shared mutable static so one solver growing its pool no longer
  /// affects every other instance.
  int _poolSize = 1000;

  bool hasSimpleDefinition = false;

  int mVariablesID = 0;

  Map<String, SolverVariable>? _variables;

  late Row _goal;

  int _tableSize = 32;
  late int _maxColumns = _tableSize;
  List<ArrayRow?> mRows = [];

  // if true, will use graph optimizations
  /// If true, [minimize] only computes the values, without optimizing, when
  /// every row is a simple definition.
  bool graphOptimizer = false;

  /// Same as [graphOptimizer]. The container's solver loop sets it when the
  /// optimization level includes the graph optimizations.
  bool newgraphOptimizer = false;

  late List<bool> _alreadyTestedCandidates = List.filled(_tableSize, false);

  int mNumColumns = 1;
  int mNumRows = 0;
  late int _maxRows = _tableSize;

  final Cache mCache = Cache();

  late List<SolverVariable?> _poolVariables = List<SolverVariable?>.filled(
    _poolSize,
    null,
  );
  int _poolVariablesCount = 0;

  late Row _tempGoal;

  /// Creates an empty system.
  LinearSystem() {
    mRows = List<ArrayRow?>.filled(_tableSize, null);
    _releaseRows();
    _goal = PriorityGoalRow(mCache);
    if (OPTIMIZED_ENGINE) {
      _tempGoal = ValuesRow(mCache);
    } else {
      _tempGoal = ArrayRow(mCache);
    }
  }

  /*------------------------------------------------------------------------*/
  // Memory management
  /*------------------------------------------------------------------------*/

  /// Reallocate memory to accommodate increased amount of variables.
  void _increaseTableSize() {
    _tableSize *= 2;
    mRows = [
      ...mRows,
      ...List<ArrayRow?>.filled(_tableSize - mRows.length, null),
    ];
    mCache.mIndexedVariables = [
      ...mCache.mIndexedVariables,
      ...List<SolverVariable?>.filled(
        _tableSize - mCache.mIndexedVariables.length,
        null,
      ),
    ];
    _alreadyTestedCandidates = List.filled(_tableSize, false);
    _maxColumns = _tableSize;
    _maxRows = _tableSize;
  }

  /// Release ArrayRows back to their pool.
  void _releaseRows() {
    if (OPTIMIZED_ENGINE) {
      for (var i = 0; i < mNumRows; i++) {
        final row = mRows[i];
        if (row != null) {
          mCache.mOptimizedArrayRowPool.release(row);
        }
        mRows[i] = null;
      }
    } else {
      for (var i = 0; i < mNumRows; i++) {
        final row = mRows[i];
        if (row != null) {
          mCache.mArrayRowPool.release(row);
        }
        mRows[i] = null;
      }
    }
  }

  /// Reset the LinearSystem object so that it can be reused.
  void reset() {
    for (var i = 0; i < mCache.mIndexedVariables.length; i++) {
      final variable = mCache.mIndexedVariables[i];
      variable?.reset();
    }
    mCache.mSolverVariablePool.releaseAll(_poolVariables, _poolVariablesCount);
    _poolVariablesCount = 0;

    for (var i = 0; i < mCache.mIndexedVariables.length; i++) {
      mCache.mIndexedVariables[i] = null;
    }
    _variables?.clear();
    mVariablesID = 0;
    _goal.clear();
    mNumColumns = 1;
    for (var i = 0; i < mNumRows; i++) {
      mRows[i]?.mUsed = false;
    }
    _releaseRows();
    mNumRows = 0;
    if (OPTIMIZED_ENGINE) {
      _tempGoal = ValuesRow(mCache);
    } else {
      _tempGoal = ArrayRow(mCache);
    }
  }

  /*------------------------------------------------------------------------*/
  // Creation of rows / variables / errors
  /*------------------------------------------------------------------------*/

  /// Returns the solver variable for [anchor], a [ConstraintAnchor],
  /// registering it with this system on first use (or after [reset]).
  /// Returns null for null or for any other object.
  SolverVariable? createObjectVariable(Object? anchor) {
    if (anchor == null) {
      return null;
    }
    if (mNumColumns + 1 >= _maxColumns) {
      _increaseTableSize();
    }
    SolverVariable? variable;
    if (anchor is ConstraintAnchor) {
      variable = anchor.getSolverVariable();
      if (variable == null) {
        anchor.resetSolverVariable(mCache);
        variable = anchor.getSolverVariable();
      }
      if (variable!.id == -1 ||
          variable.id > mVariablesID ||
          mCache.mIndexedVariables[variable.id] == null) {
        if (variable.id != -1) {
          variable.reset();
        }
        mVariablesID++;
        mNumColumns++;
        variable.id = mVariablesID;
        variable.mType = SolverVariableType.unrestricted;
        mCache.mIndexedVariables[mVariablesID] = variable;
      }
    }
    return variable;
  }

  /// Creates an empty row (an equation), from the pool when possible, to fill
  /// in and pass to [addConstraint].
  ArrayRow createRow() {
    ArrayRow? row;
    if (OPTIMIZED_ENGINE) {
      row = mCache.mOptimizedArrayRowPool.acquire();
      if (row == null) {
        row = ValuesRow(mCache);
      } else {
        row.reset();
      }
    } else {
      row = mCache.mArrayRowPool.acquire();
      if (row == null) {
        row = ArrayRow(mCache);
      } else {
        row.reset();
      }
    }
    SolverVariable.increaseErrorId();
    return row;
  }

  /// Creates a slack variable (restricted to positive values).
  SolverVariable createSlackVariable() {
    if (mNumColumns + 1 >= _maxColumns) {
      _increaseTableSize();
    }
    final variable = _acquireSolverVariable(SolverVariableType.slack, null);
    mVariablesID++;
    mNumColumns++;
    variable.id = mVariablesID;
    mCache.mIndexedVariables[mVariablesID] = variable;
    return variable;
  }

  /// Creates an extra variable (a slack), which [addConstraint] uses for a
  /// row that has no suitable subject variable.
  SolverVariable createExtraVariable() {
    if (mNumColumns + 1 >= _maxColumns) {
      _increaseTableSize();
    }
    final variable = _acquireSolverVariable(SolverVariableType.slack, null);
    mVariablesID++;
    mNumColumns++;
    variable.id = mVariablesID;
    mCache.mIndexedVariables[mVariablesID] = variable;
    return variable;
  }

  /// Adds a new error variable of [strength] to [row], with [sign] as its
  /// coefficient.
  void addSingleError(ArrayRow row, int sign, int strength) {
    final error = createErrorVariable(strength, null);
    row.addSingleError(error, sign);
  }

  SolverVariable _createVariable(String name, SolverVariableType type) {
    if (mNumColumns + 1 >= _maxColumns) {
      _increaseTableSize();
    }
    final variable = _acquireSolverVariable(type, null);
    variable.setName(name);
    mVariablesID++;
    mNumColumns++;
    variable.id = mVariablesID;
    _variables ??= <String, SolverVariable>{};
    _variables![name] = variable;
    mCache.mIndexedVariables[mVariablesID] = variable;
    return variable;
  }

  /// Creates an error variable of [strength] and adds it to the goal that
  /// [minimize] minimizes. [prefix] is not used.
  SolverVariable createErrorVariable(int strength, String? prefix) {
    if (mNumColumns + 1 >= _maxColumns) {
      _increaseTableSize();
    }
    final variable = _acquireSolverVariable(SolverVariableType.error, prefix);
    mVariablesID++;
    mNumColumns++;
    variable.id = mVariablesID;
    variable.strength = strength;
    mCache.mIndexedVariables[mVariablesID] = variable;
    _goal.addError(variable);
    return variable;
  }

  /// Returns a SolverVariable instance of the given type.
  SolverVariable _acquireSolverVariable(
    SolverVariableType type,
    String? prefix,
  ) {
    var variable = mCache.mSolverVariablePool.acquire();
    if (variable == null) {
      variable = SolverVariable.typed(type, prefix);
      variable.setType(type, prefix);
    } else {
      variable.reset();
      variable.setType(type, prefix);
    }
    if (_poolVariablesCount >= _poolSize) {
      _poolSize *= 2;
      _poolVariables = [
        ..._poolVariables,
        ...List<SolverVariable?>.filled(
          _poolSize - _poolVariables.length,
          null,
        ),
      ];
    }
    _poolVariables[_poolVariablesCount++] = variable;
    return variable;
  }

  /*------------------------------------------------------------------------*/
  // Accessors of rows / variables / errors
  /*------------------------------------------------------------------------*/

  /// Simple accessor for the current goal, used when minimizing the system.
  Row getGoal() => _goal;

  /// The row at index [n], or null.
  ArrayRow? getRow(int n) => mRows[n];

  /// The computed value of the variable named [name] (see [getVariable]),
  /// which is created, unrestricted, if it does not exist.
  double getValueFor(String name) {
    final v = getVariable(name, SolverVariableType.unrestricted);
    return v.computedValue;
  }

  /// The solved position of [object], a [ConstraintAnchor], as an `int`
  /// (the computed value plus 0.5, truncated), or 0 when the anchor has no
  /// solver variable.
  int getObjectVariableValue(Object object) {
    final anchor = object as ConstraintAnchor;
    // Upstream gates this on Chain.USE_CHAIN_OPTIMIZATION (statically false).
    // if (anchor.hasFinalValue()) return anchor.getFinalValue();
    final variable = anchor.getSolverVariable();
    if (variable != null) {
      return (variable.computedValue + 0.5).toInt();
    }
    return 0;
  }

  /// Returns a SolverVariable instance given a name and a type.
  SolverVariable getVariable(String name, SolverVariableType type) {
    _variables ??= <String, SolverVariable>{};
    var variable = _variables![name];
    variable ??= _createVariable(name, type);
    return variable;
  }

  /*------------------------------------------------------------------------*/
  // System resolution
  /*------------------------------------------------------------------------*/

  /// Minimize the current goal of the system.
  void minimize() {
    if (_goal.isEmpty()) {
      _computeValues();
      return;
    }
    if (graphOptimizer || newgraphOptimizer) {
      var fullySolved = true;
      for (var i = 0; i < mNumRows; i++) {
        final r = mRows[i]!;
        if (!r.mIsSimpleDefinition) {
          fullySolved = false;
          break;
        }
      }
      if (!fullySolved) {
        minimizeGoal(_goal);
      } else {
        _computeValues();
      }
    } else {
      minimizeGoal(_goal);
    }
  }

  /// Minimize the given goal with the current system.
  void minimizeGoal(Row goal) {
    // First, make sure the system is in Basic Feasible Solved form (BFS):
    // all the constants of the restricted variables should be positive.
    _enforceBFS(goal);
    _optimize(goal, false);
    _computeValues();
  }

  /// Remove the rows that are simple definitions (a variable equal to a
  /// constant), giving their variables those values.
  void cleanupRows() {
    var i = 0;
    while (i < mNumRows) {
      final current = mRows[i]!;
      if (current.variables.getCurrentSize() == 0) {
        current.mIsSimpleDefinition = true;
      }
      if (current.mIsSimpleDefinition) {
        current.mVariable!.computedValue = current.mConstantValue;
        current.mVariable!.removeFromRow(current);
        for (var j = i; j < mNumRows - 1; j++) {
          mRows[j] = mRows[j + 1];
        }
        mRows[mNumRows - 1] = null;
        mNumRows--;
        i--;
        if (OPTIMIZED_ENGINE) {
          mCache.mOptimizedArrayRowPool.release(current);
        } else {
          mCache.mArrayRowPool.release(current);
        }
      }
      i++;
    }
  }

  /// Add the equation to the system.
  void addConstraint(ArrayRow? row) {
    if (row == null) {
      return;
    }
    if (mNumRows + 1 >= _maxRows || mNumColumns + 1 >= _maxColumns) {
      _increaseTableSize();
    }

    var added = false;
    if (!row.mIsSimpleDefinition) {
      // Update the equation with the variables already defined in the system
      row.updateFromSystem(this);

      if (row.isEmpty()) {
        return;
      }

      // First, ensure that if we have a constant it's positive
      row.ensurePositiveConstant();

      // Then pick a good variable to use for the row
      if (row.chooseSubject(this)) {
        // extra variable added... let's try to see if we can remove it
        final extra = createExtraVariable();
        row.mVariable = extra;
        final numRows = mNumRows;
        _addRow(row);
        if (mNumRows == numRows + 1) {
          added = true;
          _tempGoal.initFromRow(row);
          _optimize(_tempGoal, true);
          if (extra.mDefinitionId == -1) {
            if (identical(row.mVariable, extra)) {
              // move extra to be parametric
              final pivotCandidate = row.pickPivot(extra);
              if (pivotCandidate != null) {
                row.pivot(pivotCandidate);
              }
            }
            if (!row.mIsSimpleDefinition) {
              row.mVariable!.updateReferencesWithNewDefinition(this, row);
            }
            if (OPTIMIZED_ENGINE) {
              mCache.mOptimizedArrayRowPool.release(row);
            } else {
              mCache.mArrayRowPool.release(row);
            }
            mNumRows--;
          }
        }
      }

      if (!row.hasKeyVariable()) {
        // Can happen if row resolves to nil
        return;
      }
    }
    if (!added) {
      _addRow(row);
    }
  }

  void _addRow(ArrayRow row) {
    if (SIMPLIFY_SYNONYMS && row.mIsSimpleDefinition) {
      row.mVariable!.setFinalValue(this, row.mConstantValue);
    } else {
      mRows[mNumRows] = row;
      row.mVariable!.mDefinitionId = mNumRows;
      mNumRows++;
      row.mVariable!.updateReferencesWithNewDefinition(this, row);
    }
    if (SIMPLIFY_SYNONYMS && hasSimpleDefinition) {
      // compact the rows...
      for (var i = 0; i < mNumRows; i++) {
        if (mRows[i] != null && mRows[i]!.mIsSimpleDefinition) {
          final removedRow = mRows[i]!;
          removedRow.mVariable!.setFinalValue(this, removedRow.mConstantValue);
          if (OPTIMIZED_ENGINE) {
            mCache.mOptimizedArrayRowPool.release(removedRow);
          } else {
            mCache.mArrayRowPool.release(removedRow);
          }
          mRows[i] = null;
          var lastRow = i + 1;
          for (var j = i + 1; j < mNumRows; j++) {
            mRows[j - 1] = mRows[j];
            if (mRows[j - 1]!.mVariable!.mDefinitionId == j) {
              mRows[j - 1]!.mVariable!.mDefinitionId = j - 1;
            }
            lastRow = j;
          }
          if (lastRow < mNumRows) {
            mRows[lastRow] = null;
          }
          mNumRows--;
          i--;
        }
      }
      hasSimpleDefinition = false;
    }
  }

  /// Remove [row] if it is a simple definition, fixing its variable at the
  /// row's constant value. Other rows are left in place.
  void removeRow(ArrayRow row) {
    if (row.mIsSimpleDefinition && row.mVariable != null) {
      if (row.mVariable!.mDefinitionId != -1) {
        for (var i = row.mVariable!.mDefinitionId; i < mNumRows - 1; i++) {
          final rowVariable = mRows[i + 1]!.mVariable!;
          if (rowVariable.mDefinitionId == i + 1) {
            rowVariable.mDefinitionId = i;
          }
          mRows[i] = mRows[i + 1];
        }
        mNumRows--;
      }
      if (!row.mVariable!.isFinalValue) {
        row.mVariable!.setFinalValue(this, row.mConstantValue);
      }
      if (OPTIMIZED_ENGINE) {
        mCache.mOptimizedArrayRowPool.release(row);
      } else {
        mCache.mArrayRowPool.release(row);
      }
    }
  }

  /// Optimize the system given a goal to minimize. The system should be in
  /// BFS form. Returns the number of iterations.
  int _optimize(Row goal, bool b) {
    var done = false;
    var tries = 0;
    for (var i = 0; i < mNumColumns; i++) {
      _alreadyTestedCandidates[i] = false;
    }

    while (!done) {
      tries++;
      if (tries >= 2 * mNumColumns) {
        return tries;
      }

      if (goal.getKey() != null) {
        _alreadyTestedCandidates[goal.getKey()!.id] = true;
      }
      final pivotCandidate = goal.getPivotCandidate(
        this,
        _alreadyTestedCandidates,
      );
      if (pivotCandidate != null) {
        if (_alreadyTestedCandidates[pivotCandidate.id]) {
          return tries;
        } else {
          _alreadyTestedCandidates[pivotCandidate.id] = true;
        }
      }

      if (pivotCandidate != null) {
        // there's a negative variable in the goal that we can pivot on.
        // We now need to select which equation of the system we should do
        // the pivot on: only look at restricted variables equations
        // containing the column we are trying to pivot on, preferring
        // strong strength over weak.
        var min = double.maxFinite;
        var pivotRowIndex = -1;

        for (var i = 0; i < mNumRows; i++) {
          final current = mRows[i]!;
          final variable = current.mVariable!;
          if (variable.mType == SolverVariableType.unrestricted) {
            // skip unrestricted variables equations (to only look at Cs)
            continue;
          }
          if (current.mIsSimpleDefinition) {
            continue;
          }

          if (current.hasVariable(pivotCandidate)) {
            // the current row does contain the variable we want to pivot on
            final aJ = current.variables.get(pivotCandidate);
            if (aJ < 0) {
              final value = -current.mConstantValue / aJ;
              if (value < min) {
                min = value;
                pivotRowIndex = i;
              }
            }
          }
        }
        // At this point, we ought to have an equation to pivot on
        if (pivotRowIndex > -1) {
          // We found an equation to pivot on
          final pivotEquation = mRows[pivotRowIndex]!;
          pivotEquation.mVariable!.mDefinitionId = -1;
          pivotEquation.pivot(pivotCandidate);
          pivotEquation.mVariable!.mDefinitionId = pivotRowIndex;
          pivotEquation.mVariable!.updateReferencesWithNewDefinition(
            this,
            pivotEquation,
          );
          // now that we pivoted, we're going to continue looping on the next
          // goal columns, until we exhaust all possibilities of improvement
        }
      } else {
        // There is no candidate goal column to pivot on, exit the loop.
        done = true;
      }
    }
    return tries;
  }

  /// Make sure that the system is in Basic Feasible Solved form (BFS).
  /// Returns the number of iterations.
  int _enforceBFS(Row goal) {
    var tries = 0;
    bool done;

    // At this point, we might not be in BFS form, i.e. one of the restricted
    // equations has a negative constant; check if that's the case.
    var infeasibleSystem = false;
    for (var i = 0; i < mNumRows; i++) {
      final variable = mRows[i]!.mVariable!;
      if (variable.mType == SolverVariableType.unrestricted) {
        continue; // C can be either positive or negative.
      }
      if (mRows[i]!.mConstantValue < 0) {
        infeasibleSystem = true;
        break;
      }
    }

    // The system is not in BFS form: go back to it by selecting equations
    // with a negative constant and pivoting to remove it.
    if (infeasibleSystem) {
      done = false;
      tries = 0;
      while (!done) {
        tries++;
        var min = double.maxFinite;
        var strength = 0;
        var pivotRowIndex = -1;
        var pivotColumnIndex = -1;

        for (var i = 0; i < mNumRows; i++) {
          final current = mRows[i]!;
          final variable = current.mVariable!;
          if (variable.mType == SolverVariableType.unrestricted) {
            // skip unrestricted variables equations, as C can be either
            // positive or negative.
            continue;
          }
          if (current.mIsSimpleDefinition) {
            continue;
          }
          if (current.mConstantValue < 0) {
            // examine this row, see if we can find a good pivot
            if (SKIP_COLUMNS) {
              final size = current.variables.getCurrentSize();
              for (var j = 0; j < size; j++) {
                final candidate = current.variables.getVariable(j)!;
                final aJ = current.variables.get(candidate);
                if (aJ <= 0) {
                  continue;
                }
                for (var k = 0; k < SolverVariable.MAX_STRENGTH; k++) {
                  final value = candidate.mStrengthVector[k] / aJ;
                  if ((value < min && k == strength) || k > strength) {
                    min = value;
                    pivotRowIndex = i;
                    pivotColumnIndex = candidate.id;
                    strength = k;
                  }
                }
              }
            } else {
              for (var j = 1; j < mNumColumns; j++) {
                final candidate = mCache.mIndexedVariables[j]!;
                final aJ = current.variables.get(candidate);
                if (aJ <= 0) {
                  continue;
                }
                for (var k = 0; k < SolverVariable.MAX_STRENGTH; k++) {
                  final value = candidate.mStrengthVector[k] / aJ;
                  if ((value < min && k == strength) || k > strength) {
                    min = value;
                    pivotRowIndex = i;
                    pivotColumnIndex = j;
                    strength = k;
                  }
                }
              }
            }
          }
        }

        if (pivotRowIndex != -1) {
          // We have a pivot!
          final pivotEquation = mRows[pivotRowIndex]!;
          pivotEquation.mVariable!.mDefinitionId = -1;
          pivotEquation.pivot(mCache.mIndexedVariables[pivotColumnIndex]!);
          pivotEquation.mVariable!.mDefinitionId = pivotRowIndex;
          pivotEquation.mVariable!.updateReferencesWithNewDefinition(
            this,
            pivotEquation,
          );
        } else {
          done = true;
        }
        if (tries > mNumColumns / 2) {
          // fail safe: tried too many times
          done = true;
        }
      }
    }

    return tries;
  }

  void _computeValues() {
    for (var i = 0; i < mNumRows; i++) {
      final row = mRows[i]!;
      row.mVariable!.computedValue = row.mConstantValue;
    }
  }

  /// Debug hook (no-op in the port; upstream prints the system state).
  void displayReadableRows() {}

  /// The number of rows (equations) in the system.
  int getNumEquations() => mNumRows;

  /// The number of variables created since the system was created or
  /// [reset].
  int getNumVariables() => mVariablesID;

  /// The cache of pooled rows and variables this system uses.
  Cache getCache() => mCache;

  /*------------------------------------------------------------------------*/
  // Equations
  /*------------------------------------------------------------------------*/

  /// Add an equation of the form `a >= b + margin`.
  void addGreaterThan(
    SolverVariable a,
    SolverVariable b,
    int margin,
    int strength,
  ) {
    final row = createRow();
    final slack = createSlackVariable();
    slack.strength = 0;
    row.createRowGreaterThan(a, b, slack, margin);
    if (strength != SolverVariable.STRENGTH_FIXED) {
      final slackValue = row.variables.get(slack);
      addSingleError(row, (-1 * slackValue).toInt(), strength);
    }
    addConstraint(row);
  }

  /// Add a required equation of the form `a >= b + margin`, as barriers use.
  /// [hasMatchConstraintWidgets] is not used.
  void addGreaterBarrier(
    SolverVariable a,
    SolverVariable b,
    int margin,
    bool hasMatchConstraintWidgets,
  ) {
    final row = createRow();
    final slack = createSlackVariable();
    slack.strength = 0;
    row.createRowGreaterThan(a, b, slack, margin);
    addConstraint(row);
  }

  /// Add an equation of the form `a <= b + margin`.
  void addLowerThan(
    SolverVariable a,
    SolverVariable b,
    int margin,
    int strength,
  ) {
    final row = createRow();
    final slack = createSlackVariable();
    slack.strength = 0;
    row.createRowLowerThan(a, b, slack, margin);
    if (strength != SolverVariable.STRENGTH_FIXED) {
      final slackValue = row.variables.get(slack);
      addSingleError(row, (-1 * slackValue).toInt(), strength);
    }
    addConstraint(row);
  }

  /// Add a required equation of the form `a <= b + margin`, as barriers use.
  /// [hasMatchConstraintWidgets] is not used.
  void addLowerBarrier(
    SolverVariable a,
    SolverVariable b,
    int margin,
    bool hasMatchConstraintWidgets,
  ) {
    final row = createRow();
    final slack = createSlackVariable();
    slack.strength = 0;
    row.createRowLowerThan(a, b, slack, margin);
    addConstraint(row);
  }

  /// Add an equation of the form `(1 - bias) * (a - b) = bias * (c - d)`.
  void addCentering(
    SolverVariable a,
    SolverVariable b,
    int m1,
    double bias,
    SolverVariable c,
    SolverVariable d,
    int m2,
    int strength,
  ) {
    final row = createRow();
    row.createRowCentering(a, b, m1, bias, c, d, m2);
    if (strength != SolverVariable.STRENGTH_FIXED) {
      row.addErrorToRow(this, strength);
    }
    addConstraint(row);
  }

  /// Add an equation of the form `a - b = (c - d) * ratio`.
  void addRatio(
    SolverVariable a,
    SolverVariable b,
    SolverVariable c,
    SolverVariable d,
    double ratio,
    int strength,
  ) {
    final row = createRow();
    row.createRowDimensionRatio(a, b, c, d, ratio);
    if (strength != SolverVariable.STRENGTH_FIXED) {
      row.addErrorToRow(this, strength);
    }
    addConstraint(row);
  }

  void addSynonym(SolverVariable a, SolverVariable b, int margin) {
    if (a.mDefinitionId == -1 && margin == 0) {
      if (b.mIsSynonym) {
        margin += b.mSynonymDelta.toInt();
        b = mCache.mIndexedVariables[b.mSynonym]!;
      }
      if (a.mIsSynonym) {
        margin -= a.mSynonymDelta.toInt();
        a = mCache.mIndexedVariables[a.mSynonym]!;
      } else {
        a.setSynonym(this, b, 0);
      }
    } else {
      addEquality(a, b, margin, SolverVariable.STRENGTH_FIXED);
    }
  }

  /// Add an equation of the form `a = b + margin`.
  ArrayRow? addEquality(
    SolverVariable a,
    SolverVariable b,
    int margin,
    int strength,
  ) {
    if (USE_BASIC_SYNONYMS &&
        strength == SolverVariable.STRENGTH_FIXED &&
        b.isFinalValue &&
        a.mDefinitionId == -1) {
      a.setFinalValue(this, b.computedValue + margin);
      return null;
    }
    final row = createRow();
    row.createRowEquals(a, b, margin);
    if (strength != SolverVariable.STRENGTH_FIXED) {
      row.addErrorToRow(this, strength);
    }
    addConstraint(row);
    return row;
  }

  /// Add an equation of the form `a = value`.
  void addEqualityConstant(SolverVariable a, int value) {
    if (USE_BASIC_SYNONYMS && a.mDefinitionId == -1) {
      a.setFinalValue(this, value.toDouble());
      for (var i = 0; i < mVariablesID + 1; i++) {
        final variable = mCache.mIndexedVariables[i];
        if (variable != null &&
            variable.mIsSynonym &&
            variable.mSynonym == a.id) {
          variable.setFinalValue(this, value + variable.mSynonymDelta);
        }
      }
      return;
    }
    final idx = a.mDefinitionId;
    if (a.mDefinitionId != -1) {
      final row = mRows[idx]!;
      if (row.mIsSimpleDefinition) {
        row.mConstantValue = value.toDouble();
      } else {
        if (row.variables.getCurrentSize() == 0) {
          row.mIsSimpleDefinition = true;
          row.mConstantValue = value.toDouble();
        } else {
          final newRow = createRow();
          newRow.createRowEqualsConstant(a, value);
          addConstraint(newRow);
        }
      }
    } else {
      final row = createRow();
      row.createRowDefinition(a, value);
      addConstraint(row);
    }
  }

  /// Create a constraint to express `A = C * percent`.
  static ArrayRow createRowDimensionPercent(
    LinearSystem linearSystem,
    SolverVariable variableA,
    SolverVariable variableC,
    double percent,
  ) {
    final row = linearSystem.createRow();
    return row.createRowDimensionPercent(variableA, variableC, percent);
  }

  /// Add the equations constraining a widget center to another widget center,
  /// positioned on a circle, following an angle and radius.
  void addCenterPoint(
    ConstraintWidget widget,
    ConstraintWidget target,
    double angle,
    int radius,
  ) {
    final al = createObjectVariable(
      widget.getAnchor(ConstraintAnchorType.left),
    )!;
    final at = createObjectVariable(
      widget.getAnchor(ConstraintAnchorType.top),
    )!;
    final ar = createObjectVariable(
      widget.getAnchor(ConstraintAnchorType.right),
    )!;
    final ab = createObjectVariable(
      widget.getAnchor(ConstraintAnchorType.bottom),
    )!;

    final bl = createObjectVariable(
      target.getAnchor(ConstraintAnchorType.left),
    )!;
    final bt = createObjectVariable(
      target.getAnchor(ConstraintAnchorType.top),
    )!;
    final br = createObjectVariable(
      target.getAnchor(ConstraintAnchorType.right),
    )!;
    final bb = createObjectVariable(
      target.getAnchor(ConstraintAnchorType.bottom),
    )!;

    var row = createRow();
    var angleComponent = math.sin(angle) * radius;
    row.createRowWithAngle(at, ab, bt, bb, angleComponent);
    addConstraint(row);
    row = createRow();
    angleComponent = math.cos(angle) * radius;
    row.createRowWithAngle(al, ar, bl, br, angleComponent);
    addConstraint(row);
  }
}
