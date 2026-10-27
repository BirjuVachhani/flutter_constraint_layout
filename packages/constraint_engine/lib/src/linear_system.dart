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
//
// Java floats: every float operation is one binary32 rounding (jfloat.dart),
// in Java's evaluation order, and comparisons are exact. The solver trace
// (debug/solver_trace.dart) is compiled in only with -Dcl.trace=true.

import 'dart:math' as math;

import 'array_linked_variables.dart';
import 'array_row.dart';
import 'cache.dart';
import 'constraint_anchor.dart';
import 'constraint_widget.dart';
import 'debug/solver_trace.dart';
import 'jfloat.dart';
import 'priority_goal_row.dart';
import 'solver_variable.dart';
import 'solver_variable_values.dart';

/// The largest magnitude up to which every int is a binary32 value (2^24).
const int _kFloatExactInt = 16777216;

/// Java's `(float) i`: [fi], minus the rounding for an int within 2^24 in
/// magnitude, which converts to float exactly.
@pragma('vm:prefer-inline')
double _fi(int i) =>
    (i >= -_kFloatExactInt && i <= _kFloatExactInt) ? i.toDouble() : fi(i);

/// Java's `f + i` for a float [f] and an int [i]: `fadd(f, fi(i))`. An int
/// within 2^24 is its own float, so `f + i` in double is the very sum fadd
/// rounds, and one rounding of it is the float sum.
@pragma('vm:prefer-inline')
double _plusInt(double f, int i) {
  assert(
    isF32(f),
    '_plusInt($f, $i): Java adds an int to a float, so the float operand '
    'must already be binary32',
  );
  return (i >= -_kFloatExactInt && i <= _kFloatExactInt)
      ? f32(f + i)
      : fadd(f, fi(i));
}

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
/// This is the Cassowary-style solver of every
/// [ConstraintWidgetContainer.layout] pass, which holds what the Direct pass
/// resolved as constants. Get a variable for each
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
  int _poolSize = _kInitialPoolSize;

  static const int _kInitialPoolSize = 1000;

  /// The tables' first size (upstream's TABLE_SIZE).
  static const int _kInitialTableSize = 32;

  bool hasSimpleDefinition = false;

  /// Not upstream (the column-indexed ratio test, see [_columnScanIsExact]):
  /// false once a row in `mRows[0, mNumRows)` may be null or have no
  /// subject. Only an enforceBFS pivot onto a null table entry (which throws
  /// right after, leaving the row without a subject), [removeRow] and
  /// [cleanupRows] (no caller in the engine; they release rows) can do that;
  /// [reset] sets it.
  bool _rowsSound = true;

  /// Not upstream (the column-indexed ratio test): true once [_addRow]
  /// stored a row that was not handed out by [createRow] since the last
  /// [reset], or that does not keep an ArrayLinkedVariables of this system's
  /// cache; [reset] clears it.
  bool _foreignRows = false;

  /// Not upstream (the column-indexed ratio test): the number of [reset]s so
  /// far, the epoch of the rows [createRow] hands out (ArrayRow.mSystemEpoch).
  int _epoch = 0;

  /// Whether [PriorityGoalRow] treats goal strengths within 0.0001 of each
  /// other as a tie, as the port's former double solver did, instead of
  /// comparing them exactly as upstream does. A container holding a GridCore
  /// sets it for each solve (Grid has no Android oracle, and the tie keeps
  /// its weighted tracks; see UPSTREAM.md); [reset] clears it.
  bool goalTieEpsilon = false;

  /// How many times [SolverVariable.setSynonym] ran on this system since the
  /// last [reset]: an upper bound on its live synonyms (see
  /// [addEqualityConstant]).
  int mSynonymCount = 0;

  int mVariablesID = 0;

  Map<String, SolverVariable>? _variables;

  late Row _goal;

  // The four fields below were `late` with initializers, read first (or
  // overwritten by _increaseTableSize, _acquireSolverVariable) before
  // _tableSize or _poolSize can change, so their lazy values were always
  // the initial ones; initialized eagerly, each read skips the late check.
  int _tableSize = _kInitialTableSize;
  int _maxColumns = _kInitialTableSize;
  List<ArrayRow?> mRows = [];

  // if true, will use graph optimizations
  /// If true, [minimize] only computes the values, without optimizing, when
  /// every row is a simple definition.
  bool graphOptimizer = false;

  /// Same as [graphOptimizer]. The container's solver loop sets it when the
  /// optimization level includes the graph optimizations.
  bool newgraphOptimizer = false;

  List<bool> _alreadyTestedCandidates = List<bool>.filled(
    _kInitialTableSize,
    false,
  );

  int mNumColumns = 1;
  int mNumRows = 0;
  int _maxRows = _kInitialTableSize;

  final Cache mCache = Cache();

  List<SolverVariable?> _poolVariables = List<SolverVariable?>.filled(
    _kInitialPoolSize,
    null,
  );
  int _poolVariablesCount = 0;

  /// Upstream's mTempGoal, which upstream allocates in the constructor and in
  /// every [reset]; null until first used after either. Representation
  /// change: [_tempGoal] allocates it on first use, of the type upstream
  /// would have allocated then ([_tempGoalOptimized] records
  /// [OPTIMIZED_ENGINE] at that point). A fresh row has no state and nothing
  /// refers to it before its first use (only [addConstraint] uses it), so
  /// allocating it later is the same row. Most solves never use it
  /// (Direct-complete layouts add no row at all), and skip the allocation.
  Row? _tempGoalRow;
  bool _tempGoalOptimized = false;

  Row get _tempGoal => _tempGoalRow ??= _tempGoalOptimized
      ? ValuesRow(mCache)
      : ArrayRow(mCache);

  /// Creates an empty system.
  LinearSystem() {
    mRows = List<ArrayRow?>.filled(_tableSize, null);
    _releaseRows();
    _goal = PriorityGoalRow(mCache);
    _tempGoalOptimized = OPTIMIZED_ENGINE;
  }

  /*------------------------------------------------------------------------*/
  // Memory management
  /*------------------------------------------------------------------------*/

  /// Reallocate memory to accommodate increased amount of variables.
  ///
  /// The tables grow as upstream's Arrays.copyOf does (the old entries, then
  /// nulls), into fixed-length lists: the same contents, while a growable
  /// list behind the same field type would make every access polymorphic.
  void _increaseTableSize() {
    _tableSize *= 2;
    final rows = mRows;
    mRows = List<ArrayRow?>.filled(_tableSize, null)
      ..setRange(0, rows.length, rows);
    final indexed = mCache.mIndexedVariables;
    mCache.mIndexedVariables = List<SolverVariable?>.filled(_tableSize, null)
      ..setRange(0, indexed.length, indexed);
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
    if (kSolverTrace) SolverTrace.line('RS');
    // Representation change: upstream walks the whole table, twice. Every
    // non-null entry sits at an index from 0 to mVariablesID: each create
    // method writes its variable at mVariablesID right after incrementing
    // it, nothing else in the engine writes a LinearSystem's table (the
    // cache is this system's own), _increaseTableSize copies entries to the
    // same indices and pads with nulls, and the count only drops back to 0
    // here, after the table is cleared. So walking indices 0 to mVariablesID
    // resets the same variables in the same order and nulls every entry that
    // is not null.
    final indexed = mCache.mIndexedVariables;
    final used = math.min(mVariablesID + 1, indexed.length);
    for (var i = 0; i < used; i++) {
      final variable = indexed[i];
      variable?.reset();
    }
    mCache.mSolverVariablePool.releaseAll(_poolVariables, _poolVariablesCount);
    _poolVariablesCount = 0;

    for (var i = 0; i < used; i++) {
      indexed[i] = null;
    }
    assert(
      () {
        for (var i = used; i < indexed.length; i++) {
          if (indexed[i] != null) return false;
        }
        return true;
      }(),
      'LinearSystem.reset cleared the variable table only up to '
      'mVariablesID, yet an entry above it is set: some code wrote the '
      'table at another index, and the next solve would reach a stale '
      'variable through it',
    );
    _variables?.clear();
    mVariablesID = 0;
    _goal.clear();
    mNumColumns = 1;
    for (var i = 0; i < mNumRows; i++) {
      mRows[i]?.mUsed = false;
    }
    _releaseRows();
    mNumRows = 0;
    // Upstream allocates a new temporary goal here (see _tempGoalRow).
    _tempGoalRow = null;
    _tempGoalOptimized = OPTIMIZED_ENGINE;
    // The ratio test's guards (see _columnScanIsExact): the rows are gone.
    _rowsSound = true;
    _foreignRows = false;
    _epoch++;
    mCache.mUnregisteredEntry = false;
    // Not upstream: the port's own state. Every variable is reset above, so
    // none is a synonym any more.
    goalTieEpsilon = false;
    mSynonymCount = 0;
  }

  /// Called by [SolverVariable.setSynonym]; see [mSynonymCount].
  void noteSynonym() {
    mSynonymCount++;
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
        if (kSolverTrace) {
          SolverTrace.newVariable(
            variable,
            'U',
            0,
            SolverTrace.anchorName(anchor),
          );
        }
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
    row.mSystemEpoch = _epoch;
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
    if (kSolverTrace) SolverTrace.newVariable(variable, 'S', 0, null);
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
    if (kSolverTrace) SolverTrace.newVariable(variable, 'X', 0, null);
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
    if (kSolverTrace) SolverTrace.newVariable(variable, 'N', 0, name);
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
    if (kSolverTrace) SolverTrace.newVariable(variable, 'E', strength, null);
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
      // Arrays.copyOf's contents, in a fixed-length list (see
      // _increaseTableSize).
      _poolSize *= 2;
      final pool = _poolVariables;
      _poolVariables = List<SolverVariable?>.filled(_poolSize, null)
        ..setRange(0, pool.length, pool);
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

  /// The solved position of [object], a [ConstraintAnchor], as an `int`:
  /// Java's `(int) (computedValue + 0.5f)`, a float sum truncated toward
  /// zero (so -7 reads back as -6), or 0 when the anchor has no solver
  /// variable.
  int getObjectVariableValue(Object object) {
    final anchor = object as ConstraintAnchor;
    // Upstream gates this on Chain.USE_CHAIN_OPTIMIZATION (statically false).
    // if (anchor.hasFinalValue()) return anchor.getFinalValue();
    final variable = anchor.getSolverVariable();
    if (variable != null) {
      final value = jint(fadd(variable.computedValue, 0.5));
      if (kSolverTrace) SolverTrace.readback(variable, value);
      return value;
    }
    if (kSolverTrace) SolverTrace.readback(null, 0);
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
    if (kSolverTrace) {
      SolverTrace.minimize(mNumRows, mNumColumns, _goal.isEmpty());
    }
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
    // It releases rows; the column scan gives way to the full scan.
    _rowsSound = false;
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
          mRows[j]?.mRowIndex = j;
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
    if (kSolverTrace) SolverTrace.addConstraint(row);
    if (mNumRows + 1 >= _maxRows || mNumColumns + 1 >= _maxColumns) {
      _increaseTableSize();
    }

    var added = false;
    if (!row.mIsSimpleDefinition) {
      // Update the equation with the variables already defined in the system
      row.updateFromSystem(this);
      if (kSolverTrace) SolverTrace.updated(row);

      if (row.isEmpty()) {
        if (kSolverTrace) SolverTrace.line('D E');
        return;
      }

      // First, ensure that if we have a constant it's positive
      row.ensurePositiveConstant();

      // Then pick a good variable to use for the row
      final extraNeeded = row.chooseSubject(this);
      if (kSolverTrace) SolverTrace.subject(row, extraNeeded);
      if (extraNeeded) {
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
            if (kSolverTrace) SolverTrace.removedExtra(row);
          }
        }
      }

      if (!row.hasKeyVariable()) {
        // Can happen if row resolves to nil
        if (kSolverTrace) SolverTrace.line('D K');
        return;
      }
    }
    if (!added) {
      _addRow(row);
    }
  }

  void _addRow(ArrayRow row) {
    if (SIMPLIFY_SYNONYMS && row.mIsSimpleDefinition) {
      if (kSolverTrace) SolverTrace.addFinal(row);
      row.mVariable!.setFinalFloat(this, row.mConstantValue);
    } else {
      mRows[mNumRows] = row;
      row.mRowIndex = mNumRows;
      row.mVariable!.mDefinitionId = mNumRows;
      if (kSolverTrace) SolverTrace.addRow(mNumRows, row);
      mNumRows++;
      final rowVariables = row.variables;
      if (row.mSystemEpoch != _epoch ||
          rowVariables is! ArrayLinkedVariables ||
          !identical(rowVariables.mCache, mCache)) {
        _foreignRows = true;
      }
      row.mVariable!.updateReferencesWithNewDefinition(this, row);
    }
    if (SIMPLIFY_SYNONYMS && hasSimpleDefinition) {
      // compact the rows...
      for (var i = 0; i < mNumRows; i++) {
        if (mRows[i] != null && mRows[i]!.mIsSimpleDefinition) {
          final removedRow = mRows[i]!;
          if (kSolverTrace) SolverTrace.compact(i, removedRow);
          removedRow.mVariable!.setFinalFloat(this, removedRow.mConstantValue);
          if (OPTIMIZED_ENGINE) {
            mCache.mOptimizedArrayRowPool.release(removedRow);
          } else {
            mCache.mArrayRowPool.release(removedRow);
          }
          mRows[i] = null;
          var lastRow = i + 1;
          for (var j = i + 1; j < mNumRows; j++) {
            mRows[j - 1] = mRows[j];
            mRows[j - 1]?.mRowIndex = j - 1;
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
    // It can release a row it leaves in mRows; the column scan gives way to
    // the full scan.
    _rowsSound = false;
    if (row.mIsSimpleDefinition && row.mVariable != null) {
      if (row.mVariable!.mDefinitionId != -1) {
        for (var i = row.mVariable!.mDefinitionId; i < mNumRows - 1; i++) {
          final rowVariable = mRows[i + 1]!.mVariable!;
          if (rowVariable.mDefinitionId == i + 1) {
            rowVariable.mDefinitionId = i;
          }
          mRows[i] = mRows[i + 1];
          mRows[i]?.mRowIndex = i;
        }
        mNumRows--;
      }
      if (!row.mVariable!.isFinalValue) {
        row.mVariable!.setFinalFloat(this, row.mConstantValue);
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
        if (kSolverTrace) SolverTrace.optimizeEnd(b, tries, 'cap');
        return tries;
      }

      if (goal.getKey() != null) {
        _alreadyTestedCandidates[goal.getKey()!.id] = true;
      }
      final pivotCandidate = goal.getPivotCandidate(
        this,
        _alreadyTestedCandidates,
      );
      if (kSolverTrace) SolverTrace.candidate(b, tries, pivotCandidate);
      if (pivotCandidate != null) {
        if (_alreadyTestedCandidates[pivotCandidate.id]) {
          if (kSolverTrace) SolverTrace.optimizeEnd(b, tries, 'tested');
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
        // strong strength over weak. The ratio test is in float and strict:
        // the first row wins a tie.
        var min = kFloatMax;
        var pivotRowIndex = -1;

        if (_columnScanIsExact(pivotCandidate)) {
          // Only the rows that can hold the candidate, through its client
          // list (see _columnScanIsExact), with upstream's filters and
          // float division. Upstream visits the rows in index order and keeps
          // the first strictly smaller value, which picks the lowest index
          // among the rows with the least value below kFloatMax (NaN never
          // wins; -0.0 and 0.0 tie). The client list is in another order,
          // so a tie goes to the lower index explicitly; the first test
          // keeps kFloatMax itself out, as upstream's `value < min` does.
          final clients = pivotCandidate.mClientEquations;
          final count = pivotCandidate.mClientEquationsCount;
          for (var k = 0; k < count; k++) {
            final current = clients[k]!;
            final i = current.mRowIndex;
            if (i < 0 || i >= mNumRows || !identical(mRows[i], current)) {
              // Not a row of the system (the goal, the temporary goal, a
              // released row).
              continue;
            }
            final variable = current.mVariable!;
            if (variable.mType == SolverVariableType.unrestricted) {
              continue;
            }
            if (current.mIsSimpleDefinition) {
              continue;
            }
            if (current.hasVariable(pivotCandidate)) {
              final aJ = current.variables.get(pivotCandidate);
              if (aJ < 0) {
                final value = fdiv(-current.mConstantValue, aJ);
                if (value < min ||
                    (value == min &&
                        pivotRowIndex != -1 &&
                        i < pivotRowIndex)) {
                  min = value;
                  pivotRowIndex = i;
                }
              }
            }
          }
        } else {
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
                final value = fdiv(-current.mConstantValue, aJ);
                if (value < min) {
                  min = value;
                  pivotRowIndex = i;
                }
              }
            }
          }
        }
        // At this point, we ought to have an equation to pivot on
        if (pivotRowIndex > -1) {
          // We found an equation to pivot on
          final pivotEquation = mRows[pivotRowIndex]!;
          if (kSolverTrace) {
            SolverTrace.pivotChoice(pivotRowIndex, pivotCandidate, b);
          }
          pivotEquation.mVariable!.mDefinitionId = -1;
          pivotEquation.pivot(pivotCandidate);
          pivotEquation.mVariable!.mDefinitionId = pivotRowIndex;
          pivotEquation.mVariable!.updateReferencesWithNewDefinition(
            this,
            pivotEquation,
          );
          // now that we pivoted, we're going to continue looping on the next
          // goal columns, until we exhaust all possibilities of improvement
        } else {
          if (kSolverTrace) SolverTrace.noPivot(b);
        }
      } else {
        // There is no candidate goal column to pivot on, exit the loop.
        done = true;
      }
    }
    if (kSolverTrace) SolverTrace.optimizeEnd(b, tries, 'done');
    return tries;
  }

  /// The column-indexed ratio test: whether visiting only the rows in
  /// [candidate]'s client list gives what upstream's scan of every row
  /// gives. Representation change; upstream's scan stays as the fallback.
  ///
  /// The scan reads every row and has no side effect; it can throw only
  /// where a row of `mRows[0, mNumRows)` is null or has no subject, which
  /// [_rowsSound] rules out. A row it does not visit could matter only if it
  /// held the candidate's id, and every such row is in the client list:
  /// - every entry of every row was stored since the last [reset] (rows come
  ///   from [createRow], which empties them, in this epoch: not
  ///   [_foreignRows]), and each entry stored is the cache table's entry for
  ///   its id (not Cache.mUnregisteredEntry); a table entry, once written,
  ///   keeps its slot until [reset], and ids are handed out once per epoch;
  /// - so a row holding the candidate's id k holds `table[k]`, which is the
  ///   candidate (checked below), and storing it called its addToRow, which
  ///   added the row to its client list (rows enter client lists only so);
  /// - a row leaves the client list only when the entry leaves the row
  ///   (ArrayLinkedVariables.remove and add with removeFromDefinition, and
  ///   updateFromRow, updateFromFinalVariable and updateFromSynonymVariable
  ///   with it, remove the entry too), or when the whole list is emptied:
  ///   updateReferencesWithNewDefinition, setFinalValue and setSynonym first
  ///   take the variable out of every client row, and reset gives the
  ///   variable a new id (a row still holding the old one does not hold the
  ///   new one).
  /// A row is a row of the system when it is at its ArrayRow.mRowIndex,
  /// which every store into mRows writes.
  bool _columnScanIsExact(SolverVariable candidate) {
    if (!_rowsSound || _foreignRows || mCache.mUnregisteredEntry) {
      return false;
    }
    final table = mCache.mIndexedVariables;
    final id = candidate.id;
    if (id < 0 || id >= table.length || !identical(table[id], candidate)) {
      return false;
    }
    // Exact either way; the column only pays when it is shorter.
    return candidate.mClientEquationsCount < mNumRows;
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

    if (kSolverTrace) SolverTrace.bfs(infeasibleSystem);
    // The system is not in BFS form: go back to it by selecting equations
    // with a negative constant and pivoting to remove it.
    if (infeasibleSystem) {
      done = false;
      tries = 0;
      while (!done) {
        tries++;
        var min = kFloatMax;
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
                // Java passes a missing variable to get(), which throws only
                // when it walks a non-empty row.
                final candidate = current.variables.getVariable(j);
                final aJ = current.variables.get(candidate);
                if (aJ <= 0) {
                  continue;
                }
                for (var k = 0; k < SolverVariable.MAX_STRENGTH; k++) {
                  final value = fdiv(candidate!.mStrengthVector[k], aJ);
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
                final candidate = mCache.mIndexedVariables[j];
                final aJ = current.variables.get(candidate);
                if (aJ <= 0) {
                  continue;
                }
                for (var k = 0; k < SolverVariable.MAX_STRENGTH; k++) {
                  final value = fdiv(candidate!.mStrengthVector[k], aJ);
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
          if (kSolverTrace) {
            SolverTrace.bfsPivot(pivotRowIndex, pivotColumnIndex);
          }
          pivotEquation.mVariable!.mDefinitionId = -1;
          final entering = mCache.mIndexedVariables[pivotColumnIndex];
          if (entering == null) {
            // pivot(null) throws once the row has lost its subject.
            _rowsSound = false;
          }
          pivotEquation.pivot(entering);
          pivotEquation.mVariable!.mDefinitionId = pivotRowIndex;
          pivotEquation.mVariable!.updateReferencesWithNewDefinition(
            this,
            pivotEquation,
          );
        } else {
          done = true;
        }
        if (tries > mNumColumns ~/ 2) {
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
      if (kSolverTrace) SolverTrace.computed(row);
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
      addSingleError(row, jint(-1 * slackValue), strength);
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
      addSingleError(row, jint(-1 * slackValue), strength);
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
  /// [bias] is a Java float: the row uses its binary32 value.
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
    bias = f32(bias);
    final row = createRow();
    row.createRowCentering(a, b, m1, bias, c, d, m2);
    if (strength != SolverVariable.STRENGTH_FIXED) {
      row.addErrorToRow(this, strength);
    }
    addConstraint(row);
  }

  /// Add an equation of the form `a - b = (c - d) * ratio`. [ratio] is a
  /// Java float: the row uses its binary32 value.
  void addRatio(
    SolverVariable a,
    SolverVariable b,
    SolverVariable c,
    SolverVariable d,
    double ratio,
    int strength,
  ) {
    ratio = f32(ratio);
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
        margin += jint(b.mSynonymDelta);
        b = mCache.mIndexedVariables[b.mSynonym]!;
      }
      if (a.mIsSynonym) {
        margin -= jint(a.mSynonymDelta);
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
      a.setFinalFloat(this, _plusInt(b.computedValue, margin));
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
    if (kSolverTrace) SolverTrace.equality(a, value);
    if (USE_BASIC_SYNONYMS && a.mDefinitionId == -1) {
      a.setFinalFloat(this, _fi(value));
      // Upstream scans every variable here for synonyms of a, which makes n
      // equalities cost O(n^2). The scan is skipped while mSynonymCount is
      // 0, and that is exact: its body runs only for a variable with
      // mIsSynonym set, and only SolverVariable.setSynonym sets it, counting
      // the call on this system. reset() zeroes the count only after
      // resetting every registered variable (mIsSynonym false), and a
      // variable registered later is fresh or is reset first
      // (createObjectVariable, _acquireSolverVariable). So while the count
      // is 0 no variable of this system is a synonym, the scan would call
      // nothing, and skipping it changes no state, no float and no trace
      // event. On the layout path the count stays 0: addSynonym has no
      // caller in the core, and addEquality's own setSynonym call is behind
      // upstream's DO_NOT_USE, which is false (that branch is not ported).
      if (mSynonymCount != 0) {
        for (var i = 0; i < mVariablesID + 1; i++) {
          final variable = mCache.mIndexedVariables[i];
          if (variable != null &&
              variable.mIsSynonym &&
              variable.mSynonym == a.id) {
            variable.setFinalFloat(
              this,
              fadd(_fi(value), variable.mSynonymDelta),
            );
          }
        }
      } else {
        // The debug check runs the O(n) scan only while some variable in
        // the isolate is a synonym (SolverVariable.debugLiveSynonyms, which
        // counts every write of mIsSynonym): with none, no variable can be a
        // synonym of a, and the scan would find nothing. Running it on every
        // call made debug builds quadratic again.
        assert(
          SolverVariable.debugLiveSynonyms == 0 || !_hasSynonymOf(a),
          'addEqualityConstant skipped the synonym scan because no '
          'setSynonym ran since the last reset, yet a variable is a synonym '
          'of ${a.id}: the skip would drop its setFinalValue, so some code '
          'path sets mIsSynonym without SolverVariable.setSynonym',
        );
      }
      return;
    }
    final idx = a.mDefinitionId;
    if (a.mDefinitionId != -1) {
      final row = mRows[idx]!;
      if (row.mIsSimpleDefinition) {
        row.mConstantValue = _fi(value);
      } else {
        if (row.variables.getCurrentSize() == 0) {
          row.mIsSimpleDefinition = true;
          row.mConstantValue = _fi(value);
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

  /// Whether a variable of this system is a synonym of [a] (the condition
  /// of upstream's synonym scan in [addEqualityConstant]); for debug checks.
  bool _hasSynonymOf(SolverVariable a) {
    for (var i = 0; i < mVariablesID + 1; i++) {
      final variable = mCache.mIndexedVariables[i];
      if (variable != null &&
          variable.mIsSynonym &&
          variable.mSynonym == a.id) {
        return true;
      }
    }
    return false;
  }

  /// Create a constraint to express `A = C * percent`. [percent] is a Java
  /// float: the row uses its binary32 value.
  static ArrayRow createRowDimensionPercent(
    LinearSystem linearSystem,
    SolverVariable variableA,
    SolverVariable variableC,
    double percent,
  ) {
    percent = f32(percent);
    final row = linearSystem.createRow();
    return row.createRowDimensionPercent(variableA, variableC, percent);
  }

  /// Add the equations constraining a widget center to another widget center,
  /// positioned on a circle, following an angle and radius.
  ///
  /// [angle] is a Java float in radians (the caller passes
  /// `(float) Math.toRadians(angle + 90)`). Each component is Java's
  /// `(float) (Math.sin(angle) * radius)`: computed in double, rounded once.
  void addCenterPoint(
    ConstraintWidget widget,
    ConstraintWidget target,
    double angle,
    int radius,
  ) {
    angle = f32(angle);
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
    var angleComponent = f32(math.sin(angle) * radius);
    row.createRowWithAngle(at, ab, bt, bb, angleComponent);
    addConstraint(row);
    row = createRow();
    angleComponent = f32(math.cos(angle) * radius);
    row.createRowWithAngle(al, ar, bl, br, angleComponent);
    addConstraint(row);
  }
}
