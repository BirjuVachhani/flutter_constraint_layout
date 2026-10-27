// Copyright (C) 2016 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.ArrayLinkedVariables (upstream
// pinned in UPSTREAM.md). Debug display omitted.
//
// Storage is typed, as upstream's arrays are: Int32List indices and a
// Float32List of values, so every stored coefficient is a binary32 value,
// and each Java float operation on one is a single rounding (jfloat.dart).
//
// Java null semantics: a variable parameter is nullable, and is dereferenced
// only where upstream dereferences it. Upstream's get, remove, contains and
// indexOf of a null variable walk the list before touching it, so on an
// empty list they return without throwing; add returns early for a value
// within the epsilon; put and add of a null variable write the head slot of
// an empty list before they throw. The port reproduces each of these.

import 'dart:typed_data';

import 'array_row.dart';
import 'cache.dart';
import 'jfloat.dart';
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
  // _arrayValues contain the associated values (Java floats).
  Int32List _arrayIndices = Int32List(8);
  Int32List _arrayNextIndices = Int32List(8);
  Float32List _arrayValues = Float32List(8);

  int _head = NONE;

  // While _didFillOnce is not set, _last is incremented monotonically so the
  // array is traversed linearly on the first fill (clear() only resets the
  // counters, it does not write NONE into every slot). After a full pass,
  // removed elements write NONE and free slots are found by scanning.
  int _last = NONE;
  bool _didFillOnce = false;

  /// Java's `0.001f`.
  static const double _epsilon = kEps001;

  ArrayLinkedVariables(ArrayRow arrayRow, Cache cache)
    : _row = arrayRow,
      mCache = cache;

  /// Doubles the arrays, as upstream's Arrays.copyOf (new slots are 0).
  void _grow() {
    _rowSize *= 2;
    _arrayValues = Float32List(_rowSize)..setAll(0, _arrayValues);
    _arrayIndices = Int32List(_rowSize)..setAll(0, _arrayIndices);
    _arrayNextIndices = Int32List(_rowSize)..setAll(0, _arrayNextIndices);
  }

  /// Not upstream: true only while the list is well formed, that is while
  /// (I1) following _arrayNextIndices from _head visits exactly mCurrentSize
  /// slots and then NONE, (I2) the ids stored along that chain rise strictly,
  /// (I3) none of them is NONE, and (I4) [_idMask] has the bit of each of
  /// them. While it holds, the walks below stop at the first stored id at or
  /// above the one they look for, and [contains] skips the walk when
  /// [_idMask] rules the id out; their answers, and the slot before the one
  /// they stop at, are those of upstream's full walks, which look at every
  /// one of the mCurrentSize slots for an equal id.
  ///
  /// Why it stays true: a new list and [clear] leave an empty chain. An
  /// insertion (put, add) takes a slot that is off the chain and links it
  /// after the last smaller id, which keeps I1 and I2 when the id is new (it
  /// was not found), and I3 and I4 when the id stored equals the variable's
  /// and is not NONE; otherwise the insertion clears the flag. The slot is
  /// off the chain: while _didFillOnce is false every chain slot is at or
  /// below _last (each insertion then takes _last + 1, or a NONE slot or a
  /// new one, and advances _last; a removal leaves _last alone; _grow and
  /// [clear] reset both), so _last + 1 is free; a NONE slot is off the chain
  /// by I3; and _grow adds new slots. A removal unlinks a slot, which keeps
  /// all four (I4 asks only for a superset). The one write that an exception
  /// can cut short, the head store for a null variable, clears the flag
  /// first. No other code writes the arrays or the counts: _grow copies the
  /// slots, invert and divideByAmount touch values only.
  bool _ordered = true;

  /// Not upstream: the OR of `1 << (id & _idBitMask)` over every id stored
  /// since the last [clear], so a superset of the bits of the ids on the
  /// chain (I4).
  int _idMask = 0;

  /// 64 bit positions where ints are 64-bit for bit operations, 32 where a
  /// shift by 32 or more gives 0 (JavaScript), so that no id has a 0 bit.
  static const int _idBitMask = identical(0, 0.0) ? 31 : 63;

  /// Not upstream: flags [mCache] when the entry just stored for [variable]
  /// is not the cache table's entry for its id (see
  /// Cache.mUnregisteredEntry). Reads only; no exception.
  @pragma('vm:prefer-inline')
  void _noteUnregistered(SolverVariable variable) {
    final table = mCache.mIndexedVariables;
    final id = variable.id;
    if (id < 0 || id >= table.length || !identical(table[id], variable)) {
      mCache.mUnregisteredEntry = true;
    }
  }

  /// Insert a variable with a given value in the linked list. [value] is a
  /// Java float: the list stores its binary32 value.
  @override
  void put(SolverVariable? variable, double value) {
    value = f32(value);
    if (value == 0) {
      remove(variable, true);
      return;
    }
    // Special casing empty list...
    if (_head == NONE) {
      if (variable == null) {
        // The store below throws, leaving _head at 0 over an empty list.
        _ordered = false;
      }
      _head = 0;
      _arrayValues[_head] = value;
      _arrayIndices[_head] = variable!.id;
      final stored = _arrayIndices[_head];
      _idMask |= 1 << (stored & _idBitMask);
      if (stored == NONE || stored != variable.id) {
        _ordered = false;
      }
      _noteUnregistered(variable);
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
    var found = false;
    if (_ordered) {
      // Under I1 and I2 the first slot whose id is not below the variable's
      // is the one upstream's walk finds, and the slot before it is the last
      // one that walk sees below.
      final id = variable!.id;
      while (current != NONE) {
        final stored = _arrayIndices[current];
        if (stored >= id) {
          found = stored == id;
          break;
        }
        previous = current;
        current = _arrayNextIndices[current];
      }
    } else {
      var counter = 0;
      while (current != NONE && counter < mCurrentSize) {
        if (_arrayIndices[current] == variable!.id) {
          found = true;
          break;
        }
        if (_arrayIndices[current] < variable.id) {
          previous = current;
        }
        current = _arrayNextIndices[current];
        counter++;
      }
    }
    if (found) {
      _arrayValues[current] = value;
      return;
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
    _arrayIndices[availableIndice] = variable!.id;
    final stored = _arrayIndices[availableIndice];
    _idMask |= 1 << (stored & _idBitMask);
    if (stored == NONE || stored != variable.id) {
      _ordered = false;
    }
    _noteUnregistered(variable);
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
  /// in in-line deletion when the sum reaches zero (within 0.001f), and
  /// adding rather than replacing. [value] is a Java float.
  @override
  void add(SolverVariable? variable, double value, bool removeFromDefinition) {
    _add(NONE, variable, value, removeFromDefinition, false);
  }

  /// [add], with the walk of an [_ordered] list started after [cursor]
  /// instead of at the head. [cursor] is NONE, or (only while the list is
  /// [_ordered]) a slot on the chain whose id is below [variable]'s, as are
  /// the ids of every slot before it (I2): upstream's walk finds the same
  /// slot (the first whose id is not below [variable]'s) and the same slot
  /// before it, which this walk passes too or starts from. Returns the
  /// cursor for a later add of a greater id: the slot of [variable] after
  /// the call, or the slot before it when the entry was deleted, or
  /// [cursor] when nothing changed.
  int _add(
    int cursor,
    SolverVariable? variable,
    double value,
    bool removeFromDefinition,
    bool registered,
  ) {
    assert(
      isF32(value),
      'ArrayLinkedVariables.add($value): Java adds a float, and every caller '
      'passes a product or a stored coefficient that is already binary32; a '
      'wider value means an operation upstream rounds was not rounded',
    );
    assert(
      cursor == NONE || _ordered,
      'ArrayLinkedVariables._add: a cursor walk needs a well-formed list '
      '(see _ordered), or it could miss the entry upstream finds',
    );
    if (value > -_epsilon && value < _epsilon) {
      return cursor;
    }
    // Special casing empty list...
    if (_head == NONE) {
      if (variable == null) {
        // The store below throws, leaving _head at 0 over an empty list.
        _ordered = false;
      }
      _head = 0;
      _arrayValues[_head] = value;
      _arrayIndices[_head] = variable!.id;
      final stored = _arrayIndices[_head];
      _idMask |= 1 << (stored & _idBitMask);
      if (stored == NONE || stored != variable.id) {
        _ordered = false;
      }
      if (!registered) {
        _noteUnregistered(variable);
      }
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
      return _head;
    }
    var current = _head;
    var previous = NONE;
    var found = false;
    if (_ordered) {
      // As in put: under I1 and I2 the first slot whose id is not below the
      // variable's is the one upstream's walk finds, and the slot before it
      // is the last one that walk sees below.
      final id = variable!.id;
      if (cursor != NONE) {
        previous = cursor;
        current = _arrayNextIndices[cursor];
      }
      while (current != NONE) {
        final stored = _arrayIndices[current];
        if (stored >= id) {
          found = stored == id;
          break;
        }
        previous = current;
        current = _arrayNextIndices[current];
      }
    } else {
      var counter = 0;
      while (current != NONE && counter < mCurrentSize) {
        final idx = _arrayIndices[current];
        if (idx == variable!.id) {
          found = true;
          break;
        }
        if (_arrayIndices[current] < variable.id) {
          previous = current;
        }
        current = _arrayNextIndices[current];
        counter++;
      }
    }
    if (found) {
      var v = fadd(_arrayValues[current], value);
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
          variable!.removeFromRow(_row);
        }
        if (_didFillOnce) {
          _last = current;
        }
        variable!.usageInRowCount--;
        mCurrentSize--;
        return previous;
      }
      return current;
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
    _arrayIndices[availableIndice] = variable!.id;
    final stored = _arrayIndices[availableIndice];
    _idMask |= 1 << (stored & _idBitMask);
    if (stored == NONE || stored != variable.id) {
      _ordered = false;
    }
    if (!registered) {
      _noteUnregistered(variable);
    }
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
    return availableIndice;
  }

  /// Update the current list with a new definition: replace its subject by
  /// the definition's variables, each scaled by the subject's coefficient (a
  /// float product), and return that coefficient.
  @override
  double use(ArrayRow definition, bool removeFromDefinition) {
    final value = get(definition.mVariable);
    remove(definition.mVariable, removeFromDefinition);
    final definitionVariables = definition.variables;
    final definitionSize = definitionVariables.getCurrentSize();
    if (definitionVariables is ArrayLinkedVariables &&
        !identical(definitionVariables, this)) {
      _useLinked(
        definitionVariables,
        definitionSize,
        value,
        removeFromDefinition,
      );
      return value;
    }
    for (var i = 0; i < definitionSize; i++) {
      final definitionVariable = definitionVariables.getVariable(i);
      final definitionValue = definitionVariables.get(definitionVariable);
      add(
        definitionVariable,
        fmul(definitionValue, value),
        removeFromDefinition,
      );
    }
    return value;
  }

  /// [use]'s loop over another list [d] of [definitionSize] entries, as a
  /// representation change: upstream's loop calls `d.getVariable(i)` and
  /// `d.get(variable)`, each walking [d] from its head, and each add walks
  /// this list from its head, so a row of n entries costs O(n^2). This walks
  /// [d] once, and this list about once.
  ///
  /// Exact, operation for operation: [d] is not this list, and an add changes
  /// only this list, the variables' client lists and their usage counts, so
  /// [d] stays as it was through the loop and the slot reached after i steps
  /// is the one `d.getVariable(i)` reaches; the variable read there is the
  /// same index expression. `d.get(variable)` answers the value of the first
  /// slot, in walk order, whose stored id is `variable.id`. While the stored
  /// ids seen so far rise strictly, every earlier slot's id is below the
  /// current one, so when `variable.id` is the current slot's id that first
  /// slot is the current one and its value is the answer. Otherwise (ids out
  /// of order, a variable whose id moved, a null cache slot, a chain that
  /// ends early) the loop calls `d.getVariable(i)` and `d.get(variable)`
  /// as upstream does, with their exceptions.
  ///
  /// The adds get the same variables and the same float products, in the
  /// same order. The leading entries read from their slot have strictly
  /// rising ids, so while this list is [_ordered] each one's add starts its
  /// walk where the one before left off ([_add]'s cursor); from the first
  /// other entry on, every add walks from the head.
  void _useLinked(
    ArrayLinkedVariables d,
    int definitionSize,
    double value,
    bool removeFromDefinition,
  ) {
    var current = d._head;
    // Below every Int32List value, so the first stored id always rises.
    var lastId = -0x80000001;
    var rising = true;
    var cursor = NONE;
    var useCursor = true;
    final sameCache = identical(d.mCache, mCache);
    for (var i = 0; i < definitionSize; i++) {
      final SolverVariable? definitionVariable;
      final double definitionValue;
      var fromSlot = false;
      if (current != NONE) {
        final id = d._arrayIndices[current];
        definitionVariable = d.mCache.mIndexedVariables[id];
        if (id > lastId) {
          lastId = id;
        } else {
          rising = false;
        }
        if (rising &&
            definitionVariable != null &&
            definitionVariable.id == id) {
          definitionValue = d._arrayValues[current];
          fromSlot = true;
        } else {
          definitionValue = d.get(definitionVariable);
        }
        current = d._arrayNextIndices[current];
      } else {
        definitionVariable = d.getVariable(i);
        definitionValue = d.get(definitionVariable);
      }
      final product = fmul(definitionValue, value);
      // An entry read from its slot is the cache table's entry for its id
      // (the variable is `table[id]`, and its id is id), so storing it here
      // needs no check against the table when both lists share the cache.
      final registered = fromSlot && sameCache;
      if (useCursor && fromSlot && _ordered) {
        cursor = _add(
          cursor,
          definitionVariable,
          product,
          removeFromDefinition,
          registered,
        );
      } else {
        useCursor = false;
        _add(
          NONE,
          definitionVariable,
          product,
          removeFromDefinition,
          registered,
        );
      }
    }
  }

  /// Remove a variable from the list; returns its value.
  @override
  double remove(SolverVariable? variable, bool removeFromDefinition) {
    if (identical(_candidate, variable)) {
      _candidate = null;
    }
    if (_head == NONE) {
      return 0;
    }
    var current = _head;
    var previous = NONE;
    if (_ordered) {
      // As in put: the walk stops at the first id that is not below the
      // variable's, which under I1 and I2 is the slot upstream's walk finds
      // if any, with the same slot before it.
      final id = variable!.id;
      while (current != NONE) {
        final stored = _arrayIndices[current];
        if (stored >= id) {
          if (stored != id) {
            return 0;
          }
          break;
        }
        previous = current;
        current = _arrayNextIndices[current];
      }
      if (current == NONE) {
        return 0;
      }
    } else {
      var counter = 0;
      while (true) {
        if (current == NONE || counter >= mCurrentSize) {
          return 0;
        }
        if (_arrayIndices[current] == variable!.id) {
          break;
        }
        previous = current;
        current = _arrayNextIndices[current];
        counter++;
      }
    }
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
    // An empty chain (see _ordered).
    _ordered = true;
    _idMask = 0;
  }

  @override
  bool contains(SolverVariable? variable) {
    if (_head == NONE) {
      return false;
    }
    var current = _head;
    if (_ordered) {
      // [_idMask], then the walk up to the first id that is not below the
      // variable's (see _ordered): no slot holds the id when its bit is
      // clear, and none after a greater id.
      final id = variable!.id;
      if ((_idMask & (1 << (id & _idBitMask))) == 0) {
        return false;
      }
      while (current != NONE) {
        final stored = _arrayIndices[current];
        if (stored >= id) {
          return stored == id;
        }
        current = _arrayNextIndices[current];
      }
      return false;
    }
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      if (_arrayIndices[current] == variable!.id) {
        return true;
      }
      current = _arrayNextIndices[current];
      counter++;
    }
    return false;
  }

  @override
  int indexOf(SolverVariable? variable) {
    if (_head == NONE) {
      return -1;
    }
    var current = _head;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      if (_arrayIndices[current] == variable!.id) {
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

  /// Negate every value (Java's `*= -1`, exact).
  @override
  void invert() {
    var current = _head;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      _arrayValues[current] = _arrayValues[current] * -1;
      current = _arrayNextIndices[current];
      counter++;
    }
  }

  /// Divide every value by [amount], one float division each (Java's `/=`).
  @override
  void divideByAmount(double amount) {
    assert(
      isF32(amount),
      'ArrayLinkedVariables.divideByAmount($amount): Java divides by a '
      'float, and ArrayRow.pivot passes a stored coefficient, which is '
      'binary32',
    );
    var current = _head;
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      // The Float32List store is the binary32 rounding of the quotient.
      _arrayValues[current] = _arrayValues[current] / amount;
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
          // Java keeps a missing variable while no pivot is chosen, and
          // throws only when it compares one.
          final v = mCache.mIndexedVariables[_arrayIndices[current]];
          if (pivot == null || pivot.strength < v!.strength) {
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
  double get(SolverVariable? v) {
    var current = _head;
    if (_ordered && current != NONE) {
      // As in remove: the walk up to the first id that is not below the
      // variable's (see _ordered). An empty list answers 0 below without
      // reading the variable, as upstream's.
      final id = v!.id;
      while (current != NONE) {
        final stored = _arrayIndices[current];
        if (stored >= id) {
          return stored == id ? _arrayValues[current] : 0;
        }
        current = _arrayNextIndices[current];
      }
      return 0;
    }
    var counter = 0;
    while (current != NONE && counter < mCurrentSize) {
      if (_arrayIndices[current] == v!.id) {
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
