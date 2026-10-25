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
}
