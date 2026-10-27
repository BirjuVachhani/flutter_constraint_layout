// Copyright (C) 2020 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.SolverVariableValuesTest
// (upstream pinned in UPSTREAM.md). The seeded java.util.Random sequence in
// testBasic6 differs from Dart's Random, but the assertions are
// self-consistent (values are checked against a results map), so which subset
// gets removed does not matter.

import 'dart:math';

import 'package:constraint_engine/constraint_engine.dart';
import 'package:constraint_engine/src/jfloat.dart';
import 'package:test/test.dart';

void main() {
  group('SolverVariableValuesTest', () {
    test('testOperations', () {
      final cache = Cache();
      final variable5 = SolverVariable('v5', SolverVariableType.slack);
      final variable1 = SolverVariable('v1', SolverVariableType.slack);
      final variable3 = SolverVariable('v3', SolverVariableType.slack);
      final variable7 = SolverVariable('v7', SolverVariableType.slack);
      final variable11 = SolverVariable('v11', SolverVariableType.slack);
      final variable12 = SolverVariable('v12', SolverVariableType.slack);

      variable5.id = 5;
      variable1.id = 1;
      variable3.id = 3;
      variable7.id = 7;
      variable11.id = 11;
      variable12.id = 12;
      cache.mIndexedVariables[variable5.id] = variable5;
      cache.mIndexedVariables[variable1.id] = variable1;
      cache.mIndexedVariables[variable3.id] = variable3;
      cache.mIndexedVariables[variable7.id] = variable7;
      cache.mIndexedVariables[variable11.id] = variable11;
      cache.mIndexedVariables[variable12.id] = variable12;

      final values = SolverVariableValues(null, cache);
      values.put(variable5, 1);
      values.put(variable1, -1);
      values.put(variable3, -1);
      values.put(variable7, 1);
      values.put(variable11, 1);
      values.put(variable12, -1);
      values.remove(variable1, true);
      values.remove(variable3, true);
      values.remove(variable7, true);
      values.add(variable5, 1, true);

      final currentSize = values.getCurrentSize();
      for (var i = 0; i < currentSize; i++) {
        values.getVariable(i);
      }
    });

    test('testBasic', () {
      final cache = Cache();
      final variable1 = SolverVariable('A', SolverVariableType.slack);
      final variable2 = SolverVariable('B', SolverVariableType.slack);
      final variable3 = SolverVariable('C', SolverVariableType.slack);
      variable1.id = 0;
      variable2.id = 1;
      variable3.id = 2;
      cache.mIndexedVariables[variable1.id] = variable1;
      cache.mIndexedVariables[variable2.id] = variable2;
      cache.mIndexedVariables[variable3.id] = variable3;
      final values = SolverVariableValues(null, cache);

      variable1.id = 10;
      variable2.id = 100;
      variable3.id = 1000;

      values.put(variable1, 1);
      values.put(variable2, 2);
      values.put(variable3, 3);

      expect(values.get(variable1), 1.0);
      expect(values.get(variable2), 2.0);
      expect(values.get(variable3), 3.0);
    });

    test('testBasic2', () {
      final cache = Cache();
      final values = SolverVariableValues(null, cache);
      final variable1 = SolverVariable('A', SolverVariableType.slack);
      final variable2 = SolverVariable('B', SolverVariableType.slack);
      final variable3 = SolverVariable('C', SolverVariableType.slack);

      variable1.id = 32;
      variable2.id = 32 * 2;
      variable3.id = 32 * 3;

      values.put(variable1, 1);
      values.put(variable2, 2);
      values.put(variable3, 3);

      expect(values.get(variable1), 1.0);
      expect(values.get(variable2), 2.0);
      expect(values.get(variable3), 3.0);
    });

    test('testBasic3', () {
      final cache = Cache();
      final values = SolverVariableValues(null, cache);
      final variables = <SolverVariable>[];
      for (var i = 0; i < 10000; i++) {
        final variable = SolverVariable('A$i', SolverVariableType.slack);
        variable.id = i * 32;
        values.put(variable, i.toDouble());
        variables.add(variable);
      }
      var i = 0;
      for (final variable in variables) {
        expect(values.get(variable), i.toDouble());
        i++;
      }
    });

    test('testBasic4', () {
      final cache = Cache();
      final values = SolverVariableValues(null, cache);
      final variables = <SolverVariable>[];
      for (var i = 0; i < 10000; i++) {
        final variable = SolverVariable('A$i', SolverVariableType.slack);
        variable.id = i;
        values.put(variable, i.toDouble());
        variables.add(variable);
      }
      var i = 0;
      for (final variable in variables) {
        expect(values.get(variable), i.toDouble());
        i++;
      }
    });

    test('testBasic5', () {
      final cache = Cache();
      final values = SolverVariableValues(null, cache);
      final variables = <SolverVariable>[];
      for (var i = 0; i < 10000; i++) {
        final variable = SolverVariable('A$i', SolverVariableType.slack);
        variable.id = i;
        values.put(variable, i.toDouble());
        variables.add(variable);
      }
      var i = 0;
      for (final variable in variables) {
        if (i % 2 == 0) {
          values.remove(variable, false);
        }
        i++;
      }
      i = 0;
      for (final variable in variables) {
        if (i % 2 != 0) {
          expect(values.get(variable), i.toDouble());
        }
        i++;
      }
    });

    test('testBasic6', () {
      final cache = Cache();
      final values = SolverVariableValues(null, cache);
      final variables = <SolverVariable>[];
      final results = <SolverVariable, double>{};
      for (var i = 0; i < 100; i++) {
        final variable = SolverVariable('A$i', SolverVariableType.slack);
        variable.id = i;
        values.put(variable, i.toDouble());
        results[variable] = i.toDouble();
        variables.add(variable);
      }
      // Upstream parity: the "removed" variables are only excluded from the
      // verification list; they are never removed from the storage itself.
      final toRemove = <SolverVariable>[];
      final random = Random(1234);
      for (final variable in variables) {
        if (random.nextDouble() > 0.3) {
          toRemove.add(variable);
        }
      }
      for (final variable in toRemove) {
        variables.remove(variable);
      }
      for (var i = 0; i < 100; i++) {
        final variable = SolverVariable('B$i', SolverVariableType.slack);
        variable.id = 100 + i;
        values.put(variable, i.toDouble());
        results[variable] = i.toDouble();
        variables.add(variable);
      }
      for (final variable in variables) {
        expect(values.get(variable), results[variable]);
      }
    });

    // Not upstream: Java floats and Java's null semantics in this class.
    test('binary32 values and missing variables', () {
      final cache = Cache();
      final v = SolverVariable('v', SolverVariableType.slack)..id = 3;
      cache.mIndexedVariables[3] = v;
      final values = SolverVariableValues(null, cache);
      // indexOf of a missing variable is "not found", as upstream's.
      expect(values.get(null), 0);
      expect(values.remove(null, true), 0);
      expect(values.contains(null), isFalse);
      values.add(null, f32(0.0005), true);
      values.put(v, 0.1);
      expect(values.get(v), f32(0.1));
      values.add(v, f32(0.2), true);
      expect(values.get(v), fadd(f32(0.1), f32(0.2)));
      values.divideByAmount(f32(0.3));
      expect(values.get(v), fdiv(fadd(f32(0.1), f32(0.2)), f32(0.3)));
    });
  });
}
