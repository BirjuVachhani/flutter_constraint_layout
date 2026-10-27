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
//
// Java floats: mConstantValue and every coefficient hold binary32 values,
// each float operation is one rounding in Java's evaluation order
// (jfloat.dart), and a method whose Java parameter is a float uses the
// parameter's binary32 value.

import 'array_linked_variables.dart';
import 'cache.dart';
import 'debug/solver_trace.dart';
import 'jfloat.dart';
import 'linear_system.dart';
import 'solver_variable.dart';

/// Storage backend for one row's variables. Implemented by
/// [ArrayLinkedVariables] and SolverVariableValues.
///
/// The values are Java floats (binary32). A variable parameter is nullable
/// because Java passes a missing variable (a null cache slot, a row without
/// a subject) straight through: each implementation throws exactly where
/// its Java original dereferences it, and not before (for example, `get` of
/// a missing variable in an empty row returns 0).
abstract class ArrayRowVariables {
  int getCurrentSize();
  SolverVariable? getVariable(int index);
  double getVariableValue(int index);
  double get(SolverVariable? variable);
  int indexOf(SolverVariable? variable);
  void display();
  void clear();
  bool contains(SolverVariable? variable);
  void put(SolverVariable? variable, double value);
  int sizeInBytes();
  void invert();
  double remove(SolverVariable? v, bool removeFromDefinition);
  void divideByAmount(double amount);
  void add(SolverVariable? v, double value, bool removeFromDefinition);
  double use(ArrayRow definition, bool removeFromDefinition);
}

/// Java's `1E12F`: 1e12 is not a binary32 value.
const double _kWeight1e12f = 999999995904.0;

class ArrayRow implements Row {
  /// Not upstream: this row's bit in the client-row mask of
  /// [SolverVariable] (see SolverVariable.addToRow), fixed for the row's
  /// life. Rows take the bits round-robin as they are created, so rows made
  /// close together, as the rows of one variable usually are, differ. Any
  /// assignment keeps the mask exact; this one only keeps its false
  /// positives rare.
  final int mClientBit = _nextClientBit();

  static int _clientBitSerial = 0;

  /// 64 bits where ints are 64-bit for bit operations; 32 where a shift by
  /// 32 or more gives 0 (JavaScript), so that no row's bit is 0.
  static final int _clientBitCount = (1 << 40) == 0 ? 32 : 64;

  static int _nextClientBit() {
    final bit = 1 << (_clientBitSerial++ % _clientBitCount);
    assert(
      bit != 0,
      'a row with no client bit would let SolverVariable.addToRow skip the '
      'duplicate scan for it and add the row to a client list twice',
    );
    return bit;
  }

  SolverVariable? mVariable;

  /// Not upstream: the index LinearSystem last stored this row at in its
  /// mRows. LinearSystem writes it with every store of the row into mRows,
  /// so the row is at that index exactly when the entry there is this row;
  /// a row that left mRows keeps a stale value, which that test rejects.
  int mRowIndex = -1;

  /// Not upstream: the reset count of the LinearSystem whose createRow last
  /// handed out this row (-1 for a row built directly). A row added to a
  /// system in the epoch it was created in started empty in that epoch, so
  /// every entry it holds was stored then (see Cache.mUnregisteredEntry).
  int mSystemEpoch = -1;

  /// The row's constant: a Java float, so always a binary32 value.
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
    variable.computedValue = fi(value);
    mConstantValue = fi(value);
    mIsSimpleDefinition = true;
    return this;
  }

  ArrayRow createRowEqualsConstant(SolverVariable variable, int value) {
    if (value < 0) {
      mConstantValue = fi(-1 * value);
      variables.put(variable, 1);
    } else {
      mConstantValue = fi(value);
      variables.put(variable, -1);
    }
    return this;
  }

  ArrayRow createRowEquals(
    SolverVariable variableA,
    SolverVariable variableB,
    int margin,
  ) {
    var inverse = false;
    if (margin != 0) {
      var m = margin;
      if (m < 0) {
        m = -1 * m;
        inverse = true;
      }
      mConstantValue = fi(m);
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
    variables.put(error, fi(sign));
    return this;
  }

  ArrayRow createRowGreaterThan(
    SolverVariable variableA,
    SolverVariable variableB,
    SolverVariable slack,
    int margin,
  ) {
    var inverse = false;
    if (margin != 0) {
      var m = margin;
      if (m < 0) {
        m = -1 * m;
        inverse = true;
      }
      mConstantValue = fi(m);
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
    SolverVariable a,
    int b,
    SolverVariable slack,
  ) {
    mConstantValue = fi(b);
    variables.put(a, -1);
    return this;
  }

  ArrayRow createRowLowerThan(
    SolverVariable variableA,
    SolverVariable variableB,
    SolverVariable slack,
    int margin,
  ) {
    var inverse = false;
    if (margin != 0) {
      var m = margin;
      if (m < 0) {
        m = -1 * m;
        inverse = true;
      }
      mConstantValue = fi(m);
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

  /// The weights are Java floats: the row uses their binary32 values.
  ArrayRow createRowEqualMatchDimensions(
    double currentWeight,
    double totalWeights,
    double nextWeight,
    SolverVariable variableStartA,
    SolverVariable variableEndA,
    SolverVariable variableStartB,
    SolverVariable variableEndB,
  ) {
    currentWeight = f32(currentWeight);
    totalWeights = f32(totalWeights);
    nextWeight = f32(nextWeight);
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
        final cw = fdiv(currentWeight, totalWeights);
        final nw = fdiv(nextWeight, totalWeights);
        final w = fdiv(cw, nw);
        // endA - startA == w * (endB - startB)
        variables.put(variableStartA, 1);
        variables.put(variableEndA, -1);
        variables.put(variableEndB, w);
        variables.put(variableStartB, -w);
      }
    }
    return this;
  }

  /// The weights are Java floats: the row uses their binary32 values.
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
    int marginEndB,
  ) {
    currentWeight = f32(currentWeight);
    totalWeights = f32(totalWeights);
    nextWeight = f32(nextWeight);
    if (totalWeights == 0 || (currentWeight == nextWeight)) {
      mConstantValue = fi(
        -marginStartA - marginEndA + marginStartB + marginEndB,
      );
      variables.put(variableStartA, 1);
      variables.put(variableEndA, -1);
      variables.put(variableEndB, 1);
      variables.put(variableStartB, -1);
    } else {
      final cw = fdiv(currentWeight, totalWeights);
      final nw = fdiv(nextWeight, totalWeights);
      final w = fdiv(cw, nw);
      // Java: ((-msA - meA) + w * msB) + w * meB, the int part summed first.
      mConstantValue = fadd(
        fadd(fi(-marginStartA - marginEndA), fmul(w, fi(marginStartB))),
        fmul(w, fi(marginEndB)),
      );
      variables.put(variableStartA, 1);
      variables.put(variableEndA, -1);
      variables.put(variableEndB, w);
      variables.put(variableStartB, -w);
    }
    return this;
  }

  /// [bias] is a Java float: the row uses its binary32 value.
  ArrayRow createRowCentering(
    SolverVariable variableA,
    SolverVariable variableB,
    int marginA,
    double bias,
    SolverVariable variableC,
    SolverVariable variableD,
    int marginB,
  ) {
    bias = f32(bias);
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
        mConstantValue = fi(-marginA + marginB);
      }
    } else if (bias <= 0) {
      // A = B + m
      variables.put(variableA, -1);
      variables.put(variableB, 1);
      mConstantValue = fi(marginA);
    } else if (bias >= 1) {
      // D = C - m
      variables.put(variableD, -1);
      variables.put(variableC, 1);
      mConstantValue = fi(-marginB);
    } else {
      // Java: 1 * (1 - bias), -1 * (1 - bias), -1 * bias, 1 * bias; the
      // subtraction is one float rounding, the products by +-1 are exact.
      final inverseBias = fsub(1, bias);
      variables.put(variableA, 1 * inverseBias);
      variables.put(variableB, -1 * inverseBias);
      variables.put(variableC, -1 * bias);
      variables.put(variableD, 1 * bias);
      if (marginA > 0 || marginB > 0) {
        // Java: -marginA * (1 - bias) + marginB * bias.
        mConstantValue = fadd(
          fmul(fi(-marginA), fsub(1, bias)),
          fmul(fi(marginB), bias),
        );
      }
    }
    return this;
  }

  ArrayRow addErrorToRow(LinearSystem system, int strength) {
    variables.put(system.createErrorVariable(strength, 'ep'), 1);
    variables.put(system.createErrorVariable(strength, 'em'), -1);
    return this;
  }

  /// [percent] is a Java float: the row uses its binary32 value.
  ArrayRow createRowDimensionPercent(
    SolverVariable variableA,
    SolverVariable variableC,
    double percent,
  ) {
    percent = f32(percent);
    variables.put(variableA, -1);
    variables.put(variableC, percent);
    return this;
  }

  /// Create a constraint to express `A = B + (C - D) * ratio`.
  /// Used for ratio, e.g. `Right = Left + (Bottom - Top) * percent`.
  /// [ratio] is a Java float: the row uses its binary32 value.
  ArrayRow createRowDimensionRatio(
    SolverVariable variableA,
    SolverVariable variableB,
    SolverVariable variableC,
    SolverVariable variableD,
    double ratio,
  ) {
    ratio = f32(ratio);
    variables.put(variableA, -1);
    variables.put(variableB, 1);
    variables.put(variableC, ratio);
    variables.put(variableD, -ratio);
    return this;
  }

  /// Create a constraint to express `At + (Ab-At)/2 = Bt + (Bb-Bt)/2 - angle`.
  /// [angleComponent] is a Java float: the row uses its binary32 value.
  ArrayRow createRowWithAngle(
    SolverVariable at,
    SolverVariable ab,
    SolverVariable bt,
    SolverVariable bb,
    double angleComponent,
  ) {
    angleComponent = f32(angleComponent);
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
      mConstantValue = mConstantValue * -1;
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

    final rowVariables = variables;
    final currentSize = rowVariables.getCurrentSize();
    // Representation change: the entries in linked order, walked once from
    // the head instead of once per index by getVariableValue(i) and
    // getVariable(i). Nothing in the loop changes the list, so the slot
    // reached after i steps is the one both of them reach, and the variable
    // and value read there are theirs (the same index expression, so the
    // same RangeError for a bad id); past the end of the chain the loop
    // calls them as before, and they answer 0 and null.
    final alv = rowVariables is ArrayLinkedVariables ? rowVariables : null;
    var slot = alv == null ? ArrayLinkedVariables.NONE : alv.getHead();
    for (var i = 0; i < currentSize; i++) {
      final double amount;
      final SolverVariable variable;
      if (slot != ArrayLinkedVariables.NONE) {
        amount = alv!.getValue(slot);
        variable = alv.mCache.mIndexedVariables[alv.getId(slot)]!;
        slot = alv.getNextIndice(slot);
      } else {
        amount = rowVariables.getVariableValue(i);
        variable = rowVariables.getVariable(i)!;
      }
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

  /// Make [v] the subject of this row. Java's enforceBFS passes a cache slot
  /// as it is, so [v] can be null: as upstream, the old subject is moved back
  /// into the row first, and remove() throws only if it walks a variable.
  void pivot(SolverVariable? v) {
    final traceLeaving = kSolverTrace ? mVariable : null;
    if (mVariable != null) {
      // first, move back the variable to its column
      variables.put(mVariable!, -1);
      mVariable!.mDefinitionId = -1;
      mVariable = null;
    }

    // Exact: the stored coefficient negated.
    final amount = variables.remove(v, true) * -1;
    mVariable = v;
    if (amount == 1) {
      if (kSolverTrace) SolverTrace.pivot(traceLeaving, v, amount, this);
      return;
    }
    mConstantValue = fdiv(mConstantValue, amount);
    variables.divideByAmount(amount);
    if (kSolverTrace) SolverTrace.pivot(traceLeaving, v, amount, this);
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
    LinearSystem system,
    ArrayRow definition,
    bool removeFromDefinition,
  ) {
    final value = variables.use(definition, removeFromDefinition);

    mConstantValue = fadd(
      mConstantValue,
      fmul(definition.mConstantValue, value),
    );
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
    LinearSystem system,
    SolverVariable? variable,
    bool removeFromDefinition,
  ) {
    if (variable == null || !variable.isFinalValue) {
      return;
    }
    final value = variables.get(variable);
    mConstantValue = fadd(mConstantValue, fmul(variable.computedValue, value));
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
    LinearSystem system,
    SolverVariable? variable,
    bool removeFromDefinition,
  ) {
    if (variable == null || !variable.mIsSynonym) {
      return;
    }
    final value = variables.get(variable);
    mConstantValue = fadd(mConstantValue, fmul(variable.mSynonymDelta, value));
    variables.remove(variable, removeFromDefinition);
    if (removeFromDefinition) {
      variable.removeFromRow(this);
    }
    // Java passes the cache slot as it is, even null.
    variables.add(
      system.mCache.mIndexedVariables[variable.mSynonym],
      value,
      removeFromDefinition,
    );
    if (LinearSystem.SIMPLIFY_SYNONYMS && variables.getCurrentSize() == 0) {
      mIsSimpleDefinition = true;
      system.hasSimpleDefinition = true;
    }
  }

  // Upstream carries an always-true `all` flag with a dead slack-preferring
  // branch; only the live branch is ported.
  SolverVariable? _pickPivotInVariables(
    List<bool>? avoid,
    SolverVariable? exclude,
  ) {
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
        // Java passes a missing variable on to add().
        final variable = row.variables.getVariable(i);
        final val = row.variables.getVariableValue(i);
        variables.add(variable, val, true);
      }
    }
  }

  @override
  void addError(SolverVariable error) {
    // Java's float literals 1F, 1E3F, 1E6F, 1E9F, 1E12F.
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
      weight = _kWeight1e12f;
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

    // Divergence from upstream, which loops until no defined, final or
    // synonym variable is left in the row. Each round substitutes one more
    // level of definitions, so with definitions that do not refer back to
    // each other it ends within one round per variable of the system. Some
    // cyclic barrier layouts leave definitions that do (upstream spins
    // forever on them, see UPSTREAM.md); give up instead, and let the solver
    // loop's catch keep the last frames.
    final maxRounds = system.mNumRows + system.mVariablesID + 1;
    var rounds = 0;
    var done = false;
    while (!done) {
      if (++rounds > maxRounds) {
        throw StateError(
          'ArrayRow.updateFromSystem: no fixed point after $maxRounds rounds',
        );
      }
      final rowVariables = variables;
      final currentSize = rowVariables.getCurrentSize();
      // Representation change, as in chooseSubjectInVariables: one walk in
      // linked order instead of getVariable(i) from the head for each i. The
      // scan only reads, so it sees the slots getVariable(i) would.
      final alv = rowVariables is ArrayLinkedVariables ? rowVariables : null;
      var slot = alv == null ? ArrayLinkedVariables.NONE : alv.getHead();
      for (var i = 0; i < currentSize; i++) {
        final SolverVariable variable;
        if (slot != ArrayLinkedVariables.NONE) {
          variable = alv!.mCache.mIndexedVariables[alv.getId(slot)]!;
          slot = alv.getNextIndice(slot);
        } else {
          variable = rowVariables.getVariable(i)!;
        }
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
