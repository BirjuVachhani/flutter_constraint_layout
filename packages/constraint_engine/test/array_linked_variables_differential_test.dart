// Copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0
//
// No upstream counterpart. ArrayLinkedVariables takes shortcuts while a list
// is well formed (walks that stop at the first id not below the one sought,
// an id mask, a cursor for use()), and SolverVariable skips client-list
// scans with a mask. Each must answer, throw and change state exactly as the
// full walks do. The layout corpora only reach well-formed lists, so this
// test also builds the others: ids of -1, two variables with one id, null
// table entries, null variables, a list left half written by an exception.
//
// Two worlds run the same random operations: one on the engine's
// ArrayLinkedVariables, one on the class as it was before the exact changes
// for speed that UPSTREAM.md lists
// (support/reference_array_linked_variables.dart). After every operation the
// test compares the result (float bits), the Java exception class of what was
// thrown, every list in walk order, and every variable's usage count and
// client rows.

import 'dart:math';

import 'package:constraint_engine/constraint_engine.dart';
import 'package:constraint_engine/src/array_linked_variables.dart';
import 'package:constraint_engine/src/debug/solver_trace.dart';
import 'package:constraint_engine/src/jfloat.dart';
import 'package:test/test.dart';

import 'support/reference_array_linked_variables.dart';

const int _kVariables = 24;
const int _kRows = 6;
const int _kTable = 48;

/// One side of the comparison: a cache, rows whose variables are lists of
/// one kind, and the variables.
class _World {
  _World({required this.reference}) {
    cache.mIndexedVariables = List<SolverVariable?>.filled(_kTable, null);
    for (var i = 0; i < _kVariables; i++) {
      final v = SolverVariable('v$i', SolverVariableType.unrestricted);
      vars.add(v);
    }
    for (var r = 0; r < _kRows; r++) {
      final row = ArrayRow(cache);
      row.variables = reference
          ? ReferenceArrayLinkedVariables(row, cache)
          : ArrayLinkedVariables(row, cache);
      rows.add(row);
    }
  }

  final bool reference;
  final Cache cache = Cache();
  final List<SolverVariable> vars = [];
  final List<ArrayRow> rows = [];

  SolverVariable? variable(int index) => index < 0 ? null : vars[index];

  /// Everything a later operation or a caller can observe, as a string.
  String state() {
    final sb = StringBuffer();
    for (var r = 0; r < _kRows; r++) {
      final list = rows[r].variables;
      final n = list.getCurrentSize();
      sb.write('r$r n=$n:');
      for (var i = 0; i < n; i++) {
        sb.write(
          ' ${_outcome(() {
            final v = list.getVariable(i);
            return v == null ? '-' : vars.indexOf(v);
          })}',
        );
        sb.write('=${f32Bits(list.getVariableValue(i))}');
      }
      sb.write(';');
    }
    for (var k = 0; k < _kVariables; k++) {
      final v = vars[k];
      sb.write(' v$k id=${v.id} use=${v.usageInRowCount} rows=[');
      final seen = <ArrayRow>{};
      for (var c = 0; c < v.mClientEquationsCount; c++) {
        final row = v.mClientEquations[c]!;
        // SolverVariable.removeFromRow searches from the back, which finds
        // upstream's (first) entry only while no row occurs twice.
        expect(seen.add(row), isTrue, reason: 'v$k lists a row twice');
        sb.write('${rows.indexOf(row)},');
      }
      sb.write(']');
    }
    for (var t = 0; t < _kTable; t++) {
      final v = cache.mIndexedVariables[t];
      if (v != null) sb.write(' t$t=${vars.indexOf(v)}');
    }
    return sb.toString();
  }
}

/// Runs [op] and reports its result or the Java class of what it threw.
String _outcome(Object? Function() op) {
  try {
    final r = op();
    if (r is double) return 'f${f32Bits(r)}';
    return '$r';
  } catch (e) {
    return 'threw ${SolverTrace.javaExceptionClass(e)}';
  }
}

/// Binary32 values a row holds or adds: small ones within 0.001f, values
/// that cancel, and ordinary ones.
final List<double> _values = [
  1,
  -1,
  2,
  -2,
  0.5,
  -0.5,
  f32(0.1),
  f32(-0.1),
  f32(0.0005),
  f32(-0.0005),
  kEps001,
  3,
  -3,
  f32(1.25),
  f32(-1.25),
];

/// Applies operation [code] to both worlds with the same arguments and
/// returns the two outcomes.
(String, String) _step(_World a, _World b, Random rng) {
  final code = rng.nextInt(100);
  final r = rng.nextInt(_kRows);
  // A variable index, sometimes none (null).
  final vi = rng.nextInt(10) == 0 ? -1 : rng.nextInt(_kVariables);
  final value = _values[rng.nextInt(_values.length)];
  final rfd = rng.nextBool();
  String run(_World w) {
    final list = w.rows[r].variables;
    final v = w.variable(vi);
    if (code < 20) {
      return _outcome(() {
        list.put(v, rng2Value(value));
        return null;
      });
    } else if (code < 45) {
      return _outcome(() {
        list.add(v, value, rfd);
        return null;
      });
    } else if (code < 55) {
      return _outcome(() => list.remove(v, rfd));
    } else if (code < 62) {
      return _outcome(() => list.get(v));
    } else if (code < 69) {
      return _outcome(() => list.contains(v));
    } else if (code < 72) {
      return _outcome(() => list.indexOf(v));
    } else if (code < 82) {
      // use(): a definition in another row, or in the same row.
      final d = (r + 1 + (code % 3 == 0 ? _kRows - 1 : 0)) % _kRows;
      final definition = w.rows[d];
      definition.mVariable = v;
      return _outcome(() => list.use(definition, rfd));
    } else if (code < 84) {
      return _outcome(() {
        list.clear();
        return null;
      });
    } else if (code < 86) {
      return _outcome(() {
        list.invert();
        return null;
      });
    } else if (code < 88) {
      return _outcome(() {
        list.divideByAmount(value == 0 ? 2 : value);
        return null;
      });
    } else if (code < 93) {
      // Register a variable at an id: the table entry and the variable's id.
      final id = 1 + rng2Int(_kTable - 1);
      return _outcome(() {
        if (v != null) {
          v.id = id;
          w.cache.mIndexedVariables[id] = v;
        }
        return null;
      });
    } else if (code < 96) {
      // Give a variable an id without the table (two variables, one id), or
      // the id -1 of a reset variable.
      final id = rng2Int(3) == 0 ? -1 : 1 + rng2Int(_kTable - 1);
      return _outcome(() {
        v?.id = id;
        return null;
      });
    } else if (code < 98) {
      // Empty a table entry.
      final id = rng2Int(_kTable);
      return _outcome(() {
        w.cache.mIndexedVariables[id] = null;
        return null;
      });
    } else {
      return _outcome(() {
        v?.reset();
        return null;
      });
    }
  }

  // The operation's random draws beyond the ones above come from a second
  // generator seeded the same way for both worlds.
  final seed = rng.nextInt(1 << 30);
  _rng2 = Random(seed);
  final ra = run(a);
  _rng2 = Random(seed);
  final rb = run(b);
  return (ra, rb);
}

Random _rng2 = Random(0);
int rng2Int(int n) => _rng2.nextInt(n);
double rng2Value(double v) =>
    _rng2.nextInt(8) == 0 ? 0 : (_rng2.nextBool() ? v : f32(v * 3));

void main() {
  group('ArrayLinkedVariables against the full walks', () {
    for (final seed in [1, 2, 3, 4, 5, 6, 7, 8]) {
      test('random operations, seed $seed', () {
        final engine = _World(reference: false);
        final reference = _World(reference: true);
        // Start with a registered variable at each id 1..24, in order.
        for (final w in [engine, reference]) {
          for (var k = 0; k < _kVariables; k++) {
            w.vars[k].id = k + 1;
            w.cache.mIndexedVariables[k + 1] = w.vars[k];
          }
        }
        final rng = Random(seed);
        for (var step = 0; step < 4000; step++) {
          final (got, want) = _step(engine, reference, rng);
          expect(got, want, reason: 'outcome of step $step (seed $seed)');
          expect(
            engine.state(),
            reference.state(),
            reason: 'state after step $step (seed $seed)',
          );
        }
      });
    }
  });

  test('a NONE id stored mid-list leaves the shortcuts off', () {
    // A variable whose id is -1 (reset) goes into a list that is not empty,
    // so its NONE id sits on the chain; once the slots run out, the
    // free-slot scan takes that slot while it is still linked, as upstream
    // does, and only the full walks still answer as upstream's.
    final engine = _World(reference: false);
    final reference = _World(reference: true);
    for (final w in [engine, reference]) {
      for (var k = 0; k < 10; k++) {
        w.vars[k].id = k + 1;
        w.cache.mIndexedVariables[k + 1] = w.vars[k];
      }
      final list = w.rows[0].variables;
      list.add(w.vars[0], 1, true); // id 1, slot 0
      w.vars[9].id = -1;
      list.add(w.vars[9], 2, true); // id -1 (NONE), slot 1, at the head
      for (var k = 1; k < 7; k++) {
        list.add(w.vars[k], 1, true); // ids 2..7, slots 2..7
      }
      list.add(w.vars[4], -1, true); // id 5 cancels: unlinked, not NONE
      w.vars[8].id = 9;
      w.cache.mIndexedVariables[9] = w.vars[8];
      list.add(w.vars[8], 3, true); // the scan reuses slot 1
      for (var k = 0; k < 9; k++) {
        list.put(w.vars[k], 4);
        list.add(w.vars[k], 1, true);
      }
    }
    expect(engine.state(), reference.state());
    for (var k = 0; k < 10; k++) {
      final e = engine.rows[0].variables, r = reference.rows[0].variables;
      expect(
        _outcome(() => e.contains(engine.vars[k])),
        _outcome(() => r.contains(reference.vars[k])),
      );
      expect(
        _outcome(() => e.get(engine.vars[k])),
        _outcome(() => r.get(reference.vars[k])),
      );
    }
  });

  test('use() of an entry whose variable moved to another id', () {
    // The definition holds ids 1, 3 and 5; the variable in the last slot
    // then takes id 1 (its slot still says 5, and the table still maps 5 to
    // it), so its value is the one stored for id 1, and its add must look
    // from the head, where the entry for id 1 is, not after the one for 3.
    final engine = _World(reference: false);
    final reference = _World(reference: true);
    for (final w in [engine, reference]) {
      for (var k = 0; k < 8; k++) {
        w.vars[k].id = k + 1;
        w.cache.mIndexedVariables[k + 1] = w.vars[k];
      }
      final target = w.rows[0].variables;
      for (final k in [1, 3, 5]) {
        target.put(w.vars[k], 1); // ids 2, 4, 6
      }
      final definition = w.rows[1];
      definition.variables.put(w.vars[0], 5); // id 1
      definition.variables.put(w.vars[2], 2); // id 3
      definition.variables.put(w.vars[4], 3); // id 5
      // The subject is in the target (id 6), so its entries are added with
      // a nonzero factor.
      definition.mVariable = w.vars[5];
      w.vars[4].id = 1;
      target.use(definition, false);
    }
    expect(engine.state(), reference.state());
  });

  test('a list left half written by a null put keeps the full walks', () {
    final engine = _World(reference: false);
    final reference = _World(reference: true);
    for (final w in [engine, reference]) {
      for (var k = 0; k < 4; k++) {
        w.vars[k].id = k + 1;
        w.cache.mIndexedVariables[k + 1] = w.vars[k];
      }
      final list = w.rows[0].variables;
      expect(
        () => list.put(null, 2),
        throwsA(isA<TypeError>()),
        reason: 'Java writes the head, then throws on the variable',
      );
      list.put(w.vars[2], 1);
      list.add(w.vars[0], 3, true);
      list.add(w.vars[1], 4, true);
    }
    expect(engine.state(), reference.state());
    for (var k = 0; k < 4; k++) {
      expect(
        engine.rows[0].variables.contains(engine.vars[k]),
        reference.rows[0].variables.contains(reference.vars[k]),
      );
      expect(
        f32Bits(engine.rows[0].variables.get(engine.vars[k])),
        f32Bits(reference.rows[0].variables.get(reference.vars[k])),
      );
    }
  });
}
