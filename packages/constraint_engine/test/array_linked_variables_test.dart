// Copyright (C) 2021 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.ArrayLinkedVariablesTest
// (upstream pinned in UPSTREAM.md). ArrayLinkedVariables, the default row
// storage of ArrayRow, is not exported by the library, so it is imported from
// src/.
//
// Upstream's only assertion is assertTrue(true). The test adds and removes
// variables, which grows the list past its initial 8 slots and reuses freed
// ones, and prints the row with display() after each step. The engine keeps
// display() as a no-op, so the port also renders the row the way upstream's
// display() prints it, and checks each of those prints, and the final row,
// against what upstream's Java engine prints at the pinned commit. Those
// checks are not upstream's.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:constraint_engine/src/array_linked_variables.dart';
import 'package:constraint_engine/src/debug/solver_trace.dart';
import 'package:constraint_engine/src/jfloat.dart';
import 'package:test/test.dart';

/// The row as upstream's ArrayLinkedVariables.display() prints it.
String _display(ArrayLinkedVariables variables) {
  final sb = StringBuffer('{ ');
  final count = variables.getCurrentSize();
  for (var i = 0; i < count; i++) {
    final v = variables.getVariable(i);
    if (v == null) {
      continue;
    }
    sb.write('$v = ${variables.getVariableValue(i)} ');
  }
  sb.write(' }');
  return sb.toString();
}

void main() {
  group('ArrayLinkedVariablesTest', () {
    test('testNestedLayout', () {
      final displayed = <String>[];
      final cache = Cache();
      final row = ArrayRow(cache);
      final variables = ArrayLinkedVariables(row, cache);
      final v = List<SolverVariable?>.filled(9, null);
      for (var i = 0; i < v.length; i++) {
        final p = i ^ 3;
        v[i] = SolverVariable('dog$p($i)$p', SolverVariableType.unrestricted);
        cache.mIndexedVariables[i] = v[i];
        v[i]!.id = i;
        variables.add(v[i]!, 20, true);
        if (i % 2 == 1) {
          variables.remove(v[i ~/ 2]!, true);
        }
        variables.display();
        displayed.add(_display(variables));
      }
      for (var i = 0; i < v.length; i++) {
        if (i % 2 == 1) {
          variables.display();
          displayed.add(_display(variables));
          variables.add(v[i ~/ 2]!, 24, true);
        }
      }
      expect(true, isTrue);

      // Not upstream: what upstream's display() prints at each step, then
      // the final row.
      expect(displayed, [
        '{ dog3(0)3 = 20.0  }',
        '{ dog2(1)2 = 20.0  }',
        '{ dog2(1)2 = 20.0 dog1(2)1 = 20.0  }',
        '{ dog1(2)1 = 20.0 dog0(3)0 = 20.0  }',
        '{ dog1(2)1 = 20.0 dog0(3)0 = 20.0 dog7(4)7 = 20.0  }',
        '{ dog0(3)0 = 20.0 dog7(4)7 = 20.0 dog6(5)6 = 20.0  }',
        '{ dog0(3)0 = 20.0 dog7(4)7 = 20.0 dog6(5)6 = 20.0 '
            'dog5(6)5 = 20.0  }',
        '{ dog7(4)7 = 20.0 dog6(5)6 = 20.0 dog5(6)5 = 20.0 '
            'dog4(7)4 = 20.0  }',
        '{ dog7(4)7 = 20.0 dog6(5)6 = 20.0 dog5(6)5 = 20.0 '
            'dog4(7)4 = 20.0 dog11(8)11 = 20.0  }',
        '{ dog7(4)7 = 20.0 dog6(5)6 = 20.0 dog5(6)5 = 20.0 '
            'dog4(7)4 = 20.0 dog11(8)11 = 20.0  }',
        '{ dog3(0)3 = 24.0 dog7(4)7 = 20.0 dog6(5)6 = 20.0 '
            'dog5(6)5 = 20.0 dog4(7)4 = 20.0 dog11(8)11 = 20.0  }',
        '{ dog3(0)3 = 24.0 dog2(1)2 = 24.0 dog7(4)7 = 20.0 '
            'dog6(5)6 = 20.0 dog5(6)5 = 20.0 dog4(7)4 = 20.0 '
            'dog11(8)11 = 20.0  }',
        '{ dog3(0)3 = 24.0 dog2(1)2 = 24.0 dog1(2)1 = 24.0 '
            'dog7(4)7 = 20.0 dog6(5)6 = 20.0 dog5(6)5 = 20.0 '
            'dog4(7)4 = 20.0 dog11(8)11 = 20.0  }',
      ]);
      expect(
        _display(variables),
        '{ dog3(0)3 = 24.0 dog2(1)2 = 24.0 dog1(2)1 = 24.0 '
        'dog0(3)0 = 24.0 dog7(4)7 = 20.0 dog6(5)6 = 20.0 '
        'dog5(6)5 = 20.0 dog4(7)4 = 20.0 dog11(8)11 = 20.0  }',
      );
      expect([for (final s in v) s!.usageInRowCount], List.filled(9, 1));
    });
  });

  // Not upstream: the port's Java semantics in this class.
  group('binary32 storage', () {
    late Cache cache;
    late ArrayLinkedVariables variables;
    late SolverVariable v;

    setUp(() {
      cache = Cache();
      variables = ArrayLinkedVariables(ArrayRow(cache), cache);
      v = SolverVariable('v', SolverVariableType.unrestricted)..id = 1;
      cache.mIndexedVariables[1] = v;
    });

    test('put stores the float value, add sums in float', () {
      variables.put(v, 0.1);
      expect(variables.get(v), f32(0.1));
      variables.add(v, f32(0.2), true);
      expect(variables.get(v), fadd(f32(0.1), f32(0.2)));
      expect(variables.get(v), isNot(f32(0.1) + f32(0.2)));
    });

    test('a sum within 0.001f removes the entry', () {
      variables.put(v, 0.5);
      variables.add(v, f32(-0.4995), true);
      expect(variables.getCurrentSize(), 0);
      expect(v.usageInRowCount, 0);
      // 0.001f itself is not within the epsilon.
      variables.add(v, kEps001, true);
      expect(variables.get(v), kEps001);
    });
  });

  // Not upstream. Java passes a missing variable (a null cache slot, a row
  // without a subject) straight through, and throws only where it
  // dereferences it (see "Java null semantics" in UPSTREAM.md).
  group('Java null semantics', () {
    late Cache cache;
    late ArrayLinkedVariables variables;
    late SolverVariable v;

    setUp(() {
      cache = Cache();
      variables = ArrayLinkedVariables(ArrayRow(cache), cache);
      v = SolverVariable('v', SolverVariableType.unrestricted)..id = 1;
      cache.mIndexedVariables[1] = v;
    });

    test('an empty list answers for a missing variable without throwing', () {
      expect(variables.get(null), 0);
      expect(variables.remove(null, true), 0);
      expect(variables.contains(null), isFalse);
      expect(variables.indexOf(null), -1);
      // add returns before it looks at the variable for a value within the
      // epsilon.
      variables.add(null, f32(0.0005), true);
      expect(variables.getCurrentSize(), 0);
    });

    test('use of a definition without a subject, on an empty row', () {
      final definition = ArrayRow(cache)..variables.put(v, 2);
      expect(definition.mVariable, isNull);
      expect(variables.use(definition, false), 0);
      expect(variables.getCurrentSize(), 0);
    });

    test('a list that holds variables throws where Java would', () {
      variables.put(v, 1);
      Object? error;
      try {
        variables.get(null);
      } catch (e) {
        error = e;
      }
      expect(
        SolverTrace.javaExceptionClass(error!),
        'java.lang.NullPointerException',
      );
    });

    test('put of a missing variable writes the head slot, then throws', () {
      // Java: mHead = 0; mArrayValues[0] = value; then variable.id throws.
      expect(() => variables.put(null, 3), throwsA(isA<TypeError>()));
      expect(variables.getHead(), 0);
      expect(variables.getValue(0), 3);
      expect(variables.getCurrentSize(), 0);
    });
  });
}
