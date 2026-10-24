// Copyright (C) 2016 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.ArrayLinkedVariables (upstream
// pinned in UPSTREAM.md). Debug display omitted.

import 'array_row.dart';
import 'cache.dart';
import 'solver_variable.dart';

/// Store a set of variables and their values in an array-based linked list:
/// a linked list stored in several parallel arrays, ordered by variable id.
/// Efficient to set up, reset, and mutate, while keeping iteration ordered.
class ArrayLinkedVariables implements ArrayRowVariables {
  static const int NONE = -1;

  int mCurrentSize = 0;

  final ArrayRow _row;
  final Cache mCache;

  int _rowSize = 8;

  SolverVariable? _candidate;

  // _arrayIndices point to indexes in mCache.mIndexedVariables (the
  // SolverVariables); _arrayNextIndices point to indexes in _arrayIndices;
  // _arrayValues contain the associated values.
  List<int> _arrayIndices = List.filled(8, 0);
  List<int> _arrayNextIndices = List.filled(8, 0);
  List<double> _arrayValues = List.filled(8, 0);

  int _head = NONE;

  // While _didFillOnce is not set, _last is incremented monotonically so the
  // array is traversed linearly on the first fill (clear() only resets the
  // counters, it does not write NONE into every slot). After a full pass,
  // removed elements write NONE and free slots are found by scanning.
  int _last = NONE;
  bool _didFillOnce = false;

  static const double _epsilon = 0.001;

  ArrayLinkedVariables(ArrayRow arrayRow, Cache cache)
    : _row = arrayRow,
      mCache = cache;

  void _grow() {
    _rowSize *= 2;
    _arrayValues = [
      ..._arrayValues,
      ...List.filled(_rowSize - _arrayValues.length, 0.0),
    ];
    _arrayIndices = [
      ..._arrayIndices,
      ...List.filled(_rowSize - _arrayIndices.length, 0),
    ];
    _arrayNextIndices = [
      ..._arrayNextIndices,
      ...List.filled(_rowSize - _arrayNextIndices.length, 0),
    ];
  }

  /// Insert a variable with a given value in the linked list.
  @override
  void put(SolverVariable variable, double value) {
    if (value == 0) {
      remove(variable, true);
      return;
    }
    // Special casing empty list...
    if (_head == NONE) {
      _head = 0;
      _arrayValues[_head] = value;
      _arrayIndices[_head] = variable.id;
      _arrayNextIndices[_head] = NONE;
      variable.usageInRowCount++;
      variable.addToRow(_row);
      mCurrentSize++;
      if (!_didFillOnce) {
        _last++;
        if (_last >= _arrayIndices.length) {
          _didFillOnce = true;
          _last = _arrayIndices.length - 1;
        }
      }
      return;
    }
    var current = _head;
    var previous = NONE;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      if (_arrayIndices[current] == variable.id) {
        _arrayValues[current] = value;
        return;
      }
      if (_arrayIndices[current] < variable.id) {
        previous = current;
      }
      current = _arrayNextIndices[current];
      counter++;
    }

    // Not found, we need to insert: first find an available spot.
    var availableIndice = _last + 1;
    if (_didFillOnce) {
      if (_arrayIndices[_last] == NONE) {
        availableIndice = _last;
      } else {
        availableIndice = _arrayIndices.length;
      }
    }
    if (availableIndice >= _arrayIndices.length) {
      if (mCurrentSize < _arrayIndices.length) {
        for (var i = 0; i < _arrayIndices.length; i++) {
          if (_arrayIndices[i] == NONE) {
            availableIndice = i;
            break;
          }
        }
      }
    }
    // ... make sure to grow the array as needed.
    if (availableIndice >= _arrayIndices.length) {
      availableIndice = _arrayIndices.length;
      _didFillOnce = false;
      _last = availableIndice - 1;
      _grow();
    }

    // Finally, insert the element.
    _arrayIndices[availableIndice] = variable.id;
    _arrayValues[availableIndice] = value;
    if (previous != NONE) {
      _arrayNextIndices[availableIndice] = _arrayNextIndices[previous];
      _arrayNextIndices[previous] = availableIndice;
    } else {
      _arrayNextIndices[availableIndice] = _head;
      _head = availableIndice;
    }
    variable.usageInRowCount++;
    variable.addToRow(_row);
    mCurrentSize++;
    if (!_didFillOnce) {
      _last++;
    }
    if (mCurrentSize >= _arrayIndices.length) {
      _didFillOnce = true;
    }
    if (_last >= _arrayIndices.length) {
      _didFillOnce = true;
      _last = _arrayIndices.length - 1;
    }
  }

  /// Add value to an existing variable. Broadly identical to [put], differing
  /// in in-line deletion when the sum reaches zero, and adding rather than
  /// replacing.
  @override
  void add(SolverVariable variable, double value, bool removeFromDefinition) {
    if (value > -_epsilon && value < _epsilon) {
      return;
    }
    // Special casing empty list...
    if (_head == NONE) {
      _head = 0;
      _arrayValues[_head] = value;
      _arrayIndices[_head] = variable.id;
      _arrayNextIndices[_head] = NONE;
      variable.usageInRowCount++;
      variable.addToRow(_row);
      mCurrentSize++;
      if (!_didFillOnce) {
        _last++;
        if (_last >= _arrayIndices.length) {
          _didFillOnce = true;
          _last = _arrayIndices.length - 1;
        }
      }
      return;
    }
    var current = _head;
    var previous = NONE;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      final idx = _arrayIndices[current];
      if (idx == variable.id) {
        var v = _arrayValues[current] + value;
        if (v > -_epsilon && v < _epsilon) {
          v = 0;
        }
        _arrayValues[current] = v;
        // Possibly delete immediately.
        if (v == 0) {
          if (current == _head) {
            _head = _arrayNextIndices[current];
          } else {
            _arrayNextIndices[previous] = _arrayNextIndices[current];
          }
          if (removeFromDefinition) {
            variable.removeFromRow(_row);
          }
          if (_didFillOnce) {
            _last = current;
          }
          variable.usageInRowCount--;
          mCurrentSize--;
        }
        return;
      }
      if (_arrayIndices[current] < variable.id) {
        previous = current;
      }
      current = _arrayNextIndices[current];
      counter++;
    }

    // Not found, we need to insert: first find an available spot.
    var availableIndice = _last + 1;
    if (_didFillOnce) {
      if (_arrayIndices[_last] == NONE) {
        availableIndice = _last;
      } else {
        availableIndice = _arrayIndices.length;
      }
    }
    if (availableIndice >= _arrayIndices.length) {
      if (mCurrentSize < _arrayIndices.length) {
        for (var i = 0; i < _arrayIndices.length; i++) {
          if (_arrayIndices[i] == NONE) {
            availableIndice = i;
            break;
          }
        }
      }
    }
    // ... make sure to grow the array as needed.
    if (availableIndice >= _arrayIndices.length) {
      availableIndice = _arrayIndices.length;
      _didFillOnce = false;
      _last = availableIndice - 1;
      _grow();
    }

    // Finally, insert the element.
    _arrayIndices[availableIndice] = variable.id;
    _arrayValues[availableIndice] = value;
    if (previous != NONE) {
      _arrayNextIndices[availableIndice] = _arrayNextIndices[previous];
      _arrayNextIndices[previous] = availableIndice;
    } else {
      _arrayNextIndices[availableIndice] = _head;
      _head = availableIndice;
    }
    variable.usageInRowCount++;
    variable.addToRow(_row);
    mCurrentSize++;
    if (!_didFillOnce) {
      _last++;
    }
    if (_last >= _arrayIndices.length) {
      _didFillOnce = true;
      _last = _arrayIndices.length - 1;
    }
  }

  /// Update the current list with a new definition.
  @override
  double use(ArrayRow definition, bool removeFromDefinition) {
    final value = get(definition.mVariable!);
    remove(definition.mVariable!, removeFromDefinition);
    final definitionVariables = definition.variables;
    final definitionSize = definitionVariables.getCurrentSize();
    for (var i = 0; i < definitionSize; i++) {
      final definitionVariable = definitionVariables.getVariable(i)!;
      final definitionValue = definitionVariables.get(definitionVariable);
      add(definitionVariable, definitionValue * value, removeFromDefinition);
    }
    return value;
  }

  /// Remove a variable from the list; returns its value.
  @override
  double remove(SolverVariable variable, bool removeFromDefinition) {
    if (identical(_candidate, variable)) {
      _candidate = null;
    }
    if (_head == NONE) {
      return 0;
    }
    var current = _head;
    var previous = NONE;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      final idx = _arrayIndices[current];
      if (idx == variable.id) {
        if (current == _head) {
          _head = _arrayNextIndices[current];
        } else {
          _arrayNextIndices[previous] = _arrayNextIndices[current];
        }

        if (removeFromDefinition) {
          variable.removeFromRow(_row);
        }
        variable.usageInRowCount--;
        mCurrentSize--;
        _arrayIndices[current] = NONE;
        if (_didFillOnce) {
          _last = current;
        }
        return _arrayValues[current];
      }
      previous = current;
      current = _arrayNextIndices[current];
      counter++;
    }
    return 0;
  }

  /// Clear the list of variables.
  @override
  void clear() {
    var current = _head;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      final variable = mCache.mIndexedVariables[_arrayIndices[current]];
      if (variable != null) {
        variable.removeFromRow(_row);
      }
      current = _arrayNextIndices[current];
      counter++;
    }

    _head = NONE;
    _last = NONE;
    _didFillOnce = false;
    mCurrentSize = 0;
  }

  @override
  bool contains(SolverVariable variable) {
    if (_head == NONE) {
      return false;
    }
    var current = _head;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      if (_arrayIndices[current] == variable.id) {
        return true;
      }
      current = _arrayNextIndices[current];
      counter++;
    }
    return false;
  }

  @override
  int indexOf(SolverVariable variable) {
    if (_head == NONE) {
      return -1;
    }
    var current = _head;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      if (_arrayIndices[current] == variable.id) {
        return current;
      }
      current = _arrayNextIndices[current];
      counter++;
    }
    return -1;
  }

  /// Returns true if at least one of the variables is positive.
  bool hasAtLeastOnePositiveVariable() {
    var current = _head;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      if (_arrayValues[current] > 0) {
        return true;
      }
      current = _arrayNextIndices[current];
      counter++;
    }
    return false;
  }

  @override
  void invert() {
    var current = _head;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      _arrayValues[current] *= -1;
      current = _arrayNextIndices[current];
      counter++;
    }
  }

  @override
  void divideByAmount(double amount) {
    var current = _head;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      _arrayValues[current] /= amount;
      current = _arrayNextIndices[current];
      counter++;
    }
  }

  int getHead() => _head;

  @override
  int getCurrentSize() => mCurrentSize;

  /// Id in mCache.mIndexedVariables for the slot at [index].
  int getId(int index) => _arrayIndices[index];

  /// Value stored in the slot at [index].
  double getValue(int index) => _arrayValues[index];

  /// The next slot index after [index].
  int getNextIndice(int index) => _arrayNextIndices[index];

  /// Return a pivot candidate: the highest-strength variable among the
  /// negative-value entries.
  SolverVariable? getPivotCandidate() {
    if (_candidate == null) {
      var current = _head;
      var counter = 0;
      SolverVariable? pivot;
      while (current != NONE && counter < mCurrentSize) {
        if (_arrayValues[current] < 0) {
          final v = mCache.mIndexedVariables[_arrayIndices[current]]!;
          if (pivot == null || pivot.strength < v.strength) {
            pivot = v;
          }
        }
        current = _arrayNextIndices[current];
        counter++;
      }
      return pivot;
    }
    return _candidate;
  }

  /// Return a variable from its position in the linked list.
  @override
  SolverVariable? getVariable(int index) {
    var current = _head;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      if (counter == index) {
        return mCache.mIndexedVariables[_arrayIndices[current]];
      }
      current = _arrayNextIndices[current];
      counter++;
    }
    return null;
  }

  /// Return the value of a variable from its position in the linked list.
  @override
  double getVariableValue(int index) {
    var current = _head;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      if (counter == index) {
        return _arrayValues[current];
      }
      current = _arrayNextIndices[current];
      counter++;
    }
    return 0;
  }

  /// Return the value of a variable, 0 if not found.
  @override
  double get(SolverVariable v) {
    var current = _head;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      if (_arrayIndices[current] == v.id) {
        return _arrayValues[current];
      }
      current = _arrayNextIndices[current];
      counter++;
    }
    return 0;
  }

  @override
  int sizeInBytes() {
    var size = 0;
    size += 3 * (_arrayIndices.length * 4);
    size += 9 * 4;
    return size;
  }

  @override
  void display() {}

  @override
  String toString() {
    var result = '';
    var current = _head;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      result += ' -> ';
      result += '${_arrayValues[current]} : ';
      result += '${mCache.mIndexedVariables[_arrayIndices[current]]}';
      current = _arrayNextIndices[current];
      counter++;
    }
    return result;
  }
}
