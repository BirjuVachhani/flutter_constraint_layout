// Copyright (C) 2020 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.SolverVariableValues (upstream
// pinned in UPSTREAM.md). Debug display and dead (`if (false)`) branches
// omitted.
//
// Storage is typed, as upstream's arrays are: Int32Lists and a Float32List of
// values (Java floats), each float operation one rounding (jfloat.dart). A
// variable parameter is nullable and dereferenced only where upstream
// dereferences it (indexOf of null is not found, as upstream's).

import 'dart:typed_data';

import 'array_row.dart';
import 'cache.dart';
import 'jfloat.dart';
import 'solver_variable.dart';

/// Store a set of variables and their values in an array-based linked list
/// coupled with a custom hashmap.
class SolverVariableValues implements ArrayRowVariables {
  /// Java's `0.001f`.
  static const double _epsilon = kEps001;
  static const int _none = -1;

  int _size = 16;
  final int _hashSize = 16;

  Int32List mKeys = Int32List(16)..fillRange(0, 16, _none);
  Int32List mNextKeys = Int32List(16)..fillRange(0, 16, _none);

  Int32List mVariables = Int32List(16)..fillRange(0, 16, _none);
  Float32List mValues = Float32List(16);
  Int32List mPrevious = Int32List(16)..fillRange(0, 16, _none);
  Int32List mNext = Int32List(16)..fillRange(0, 16, _none);
  int mCount = 0;
  int mHead = -1;

  // Nullable for upstream-test parity: SolverVariableValuesTest constructs
  // the storage without an owning row.
  final ArrayRow? _row;
  final Cache mCache;

  SolverVariableValues(ArrayRow? row, Cache cache)
    : _row = row,
      mCache = cache {
    clear();
  }

  @override
  int getCurrentSize() => mCount;

  @override
  SolverVariable? getVariable(int index) {
    final count = mCount;
    if (count == 0) {
      return null;
    }
    var j = mHead;
    for (var i = 0; i < count; i++) {
      if (i == index && j != _none) {
        return mCache.mIndexedVariables[mVariables[j]];
      }
      j = mNext[j];
      if (j == _none) {
        break;
      }
    }
    return null;
  }

  @override
  double getVariableValue(int index) {
    final count = mCount;
    var j = mHead;
    for (var i = 0; i < count; i++) {
      if (i == index) {
        return mValues[j];
      }
      j = mNext[j];
      if (j == _none) {
        break;
      }
    }
    return 0;
  }

  @override
  bool contains(SolverVariable? variable) => indexOf(variable) != _none;

  @override
  int indexOf(SolverVariable? variable) {
    if (mCount == 0 || variable == null) {
      return _none;
    }
    final id = variable.id;
    var key = id % _hashSize;
    key = mKeys[key];
    if (key == _none) {
      return _none;
    }
    if (mVariables[key] == id) {
      return key;
    }
    while (mNextKeys[key] != _none && mVariables[mNextKeys[key]] != id) {
      key = mNextKeys[key];
    }
    if (mNextKeys[key] == _none) {
      return _none;
    }
    if (mVariables[mNextKeys[key]] == id) {
      return mNextKeys[key];
    }
    return _none;
  }

  @override
  double get(SolverVariable? variable) {
    final index = indexOf(variable);
    if (index != _none) {
      return mValues[index];
    }
    return 0;
  }

  @override
  void display() {}

  @override
  String toString() {
    var str = '$hashCode { ';
    final count = mCount;
    for (var i = 0; i < count; i++) {
      final v = getVariable(i);
      if (v == null) {
        continue;
      }
      str += '$v = ${getVariableValue(i)} ';
    }
    str += ' }';
    return str;
  }

  @override
  void clear() {
    final row = _row;
    final count = mCount;
    for (var i = 0; i < count; i++) {
      final v = getVariable(i);
      if (v != null && row != null) {
        v.removeFromRow(row);
      }
    }
    for (var i = 0; i < _size; i++) {
      mVariables[i] = _none;
      mNextKeys[i] = _none;
    }
    for (var i = 0; i < _hashSize; i++) {
      mKeys[i] = _none;
    }
    mCount = 0;
    mHead = -1;
  }

  /// Doubles the arrays as upstream's Arrays.copyOf does, then marks the new
  /// variable and next-key slots free. (Upstream leaves the new previous and
  /// next slots 0 and the port fills them with -1; nothing reads a free
  /// slot's links before addVariable writes them.)
  void _increaseSize() {
    final size = _size * 2;
    mVariables = Int32List(size)
      ..setAll(0, mVariables)
      ..fillRange(_size, size, _none);
    mValues = Float32List(size)..setAll(0, mValues);
    mPrevious = Int32List(size)
      ..setAll(0, mPrevious)
      ..fillRange(_size, size, _none);
    mNext = Int32List(size)
      ..setAll(0, mNext)
      ..fillRange(_size, size, _none);
    mNextKeys = Int32List(size)
      ..setAll(0, mNextKeys)
      ..fillRange(_size, size, _none);
    _size = size;
  }

  void _addToHashMap(SolverVariable variable, int index) {
    final hash = variable.id % _hashSize;
    var key = mKeys[hash];
    if (key == _none) {
      mKeys[hash] = index;
    } else {
      while (mNextKeys[key] != _none) {
        key = mNextKeys[key];
      }
      mNextKeys[key] = index;
    }
    mNextKeys[index] = _none;
  }

  void _removeFromHashMap(SolverVariable variable) {
    final hash = variable.id % _hashSize;
    var key = mKeys[hash];
    if (key == _none) {
      return;
    }
    final id = variable.id;
    // let's first find it
    if (mVariables[key] == id) {
      mKeys[hash] = mNextKeys[key];
      mNextKeys[key] = _none;
    } else {
      while (mNextKeys[key] != _none && mVariables[mNextKeys[key]] != id) {
        key = mNextKeys[key];
      }
      final currentKey = mNextKeys[key];
      if (currentKey != _none && mVariables[currentKey] == id) {
        mNextKeys[key] = mNextKeys[currentKey];
        mNextKeys[currentKey] = _none;
      }
    }
  }

  void _addVariable(int index, SolverVariable? variable, double value) {
    mVariables[index] = variable!.id;
    mValues[index] = value;
    mPrevious[index] = _none;
    mNext[index] = _none;
    final row = _row;
    if (row != null) {
      variable.addToRow(row);
    }
    variable.usageInRowCount++;
    mCount++;
  }

  int _findEmptySlot() {
    for (var i = 0; i < _size; i++) {
      if (mVariables[i] == _none) {
        return i;
      }
    }
    return -1;
  }

  void _insertVariable(int index, SolverVariable? variable, double value) {
    final availableSlot = _findEmptySlot();
    _addVariable(availableSlot, variable, value);
    if (index != _none) {
      mPrevious[availableSlot] = index;
      mNext[availableSlot] = mNext[index];
      mNext[index] = availableSlot;
    } else {
      mPrevious[availableSlot] = _none;
      if (mCount > 0) {
        mNext[availableSlot] = mHead;
        mHead = availableSlot;
      } else {
        mNext[availableSlot] = _none;
      }
    }
    if (mNext[availableSlot] != _none) {
      mPrevious[mNext[availableSlot]] = availableSlot;
    }
    _addToHashMap(variable!, availableSlot);
  }

  /// [value] is a Java float: the storage keeps its binary32 value.
  @override
  void put(SolverVariable? variable, double value) {
    value = f32(value);
    if (value > -_epsilon && value < _epsilon) {
      remove(variable, true);
      return;
    }
    if (mCount == 0) {
      _addVariable(0, variable, value);
      _addToHashMap(variable!, 0);
      mHead = 0;
    } else {
      final index = indexOf(variable);
      if (index != _none) {
        mValues[index] = value;
      } else {
        if (mCount + 1 >= _size) {
          _increaseSize();
        }
        final count = mCount;
        var previousItem = -1;
        var j = mHead;
        for (var i = 0; i < count; i++) {
          if (mVariables[j] == variable!.id) {
            mValues[j] = value;
            return;
          }
          if (mVariables[j] < variable.id) {
            previousItem = j;
          }
          j = mNext[j];
          if (j == _none) {
            break;
          }
        }
        _insertVariable(previousItem, variable, value);
      }
    }
  }

  @override
  int sizeInBytes() => 0;

  @override
  double remove(SolverVariable? v, bool removeFromDefinition) {
    final index = indexOf(v);
    if (index == _none) {
      return 0;
    }
    _removeFromHashMap(v!);
    final value = mValues[index];
    if (mHead == index) {
      mHead = mNext[index];
    }
    mVariables[index] = _none;
    if (mPrevious[index] != _none) {
      mNext[mPrevious[index]] = mNext[index];
    }
    if (mNext[index] != _none) {
      mPrevious[mNext[index]] = mPrevious[index];
    }
    mCount--;
    v.usageInRowCount--;
    final row = _row;
    if (removeFromDefinition && row != null) {
      v.removeFromRow(row);
    }
    return value;
  }

  /// [value] is a Java float.
  @override
  void add(SolverVariable? v, double value, bool removeFromDefinition) {
    assert(
      isF32(value),
      'SolverVariableValues.add($value): Java adds a float, and every caller '
      'passes a product or a stored coefficient that is already binary32',
    );
    if (value > -_epsilon && value < _epsilon) {
      return;
    }
    final index = indexOf(v);
    if (index == _none) {
      put(v, value);
    } else {
      // Java's `mValues[index] += value`: the store rounds the float sum.
      mValues[index] = fadd(mValues[index], value);
      if (mValues[index] > -_epsilon && mValues[index] < _epsilon) {
        mValues[index] = 0;
        remove(v, removeFromDefinition);
      }
    }
  }

  @override
  double use(ArrayRow definition, bool removeFromDefinition) {
    final value = get(definition.mVariable);
    remove(definition.mVariable, removeFromDefinition);
    // Scans the definition's slots linearly (not in list order), as
    // upstream's live branch does.
    final localDef = definition.variables as SolverVariableValues;
    final definitionSize = localDef.getCurrentSize();
    var j = 0;
    for (var i = 0; j < definitionSize; i++) {
      if (localDef.mVariables[i] != _none) {
        final definitionValue = localDef.mValues[i];
        final definitionVariable =
            mCache.mIndexedVariables[localDef.mVariables[i]];
        add(
          definitionVariable,
          fmul(definitionValue, value),
          removeFromDefinition,
        );
        j++;
      }
    }
    return value;
  }

  /// Negate every value (Java's `*= -1`, exact).
  @override
  void invert() {
    final count = mCount;
    var j = mHead;
    for (var i = 0; i < count; i++) {
      mValues[j] = mValues[j] * -1;
      j = mNext[j];
      if (j == _none) {
        break;
      }
    }
  }

  /// Divide every value by [amount], one float division each.
  @override
  void divideByAmount(double amount) {
    final count = mCount;
    var j = mHead;
    for (var i = 0; i < count; i++) {
      mValues[j] = fdiv(mValues[j], amount);
      j = mNext[j];
      if (j == _none) {
        break;
      }
    }
  }
}
