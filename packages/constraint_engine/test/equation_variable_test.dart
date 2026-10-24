// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.EquationVariableTest (upstream
// pinned in UPSTREAM.md).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/equation_variable.dart';

void main() {
  group('EquationVariableTest', () {
    late LinearSystem linearSystem;
    late EquationVariable ev1;
    late EquationVariable ev2;

    setUp(() {
      linearSystem = LinearSystem();
      ev1 = EquationVariable.constInt(linearSystem, 200);
      ev2 = EquationVariable.constInt(linearSystem, 200);
    });

    test('testEquality', () {
      expect(ev1.getAmount() == ev2.getAmount(), isTrue);
    });

    test('testAddition', () {
      ev1.add(ev2);
      expect(ev1.getAmount().getNumerator(), 400);
    });

    test('testSubtraction', () {
      ev1.subtract(ev2);
      expect(ev1.getAmount().getNumerator(), 0);
    });

    test('testMultiply', () {
      ev1.multiply(ev2);
      expect(ev1.getAmount().getNumerator(), 40000);
    });

    test('testDivide', () {
      ev1.divide(ev2);
      expect(ev1.getAmount().getNumerator(), 1);
    });

    test('testCompatible', () {
      expect(ev1.isCompatible(ev2), isTrue);
      ev2 = EquationVariable.intAmount(
          linearSystem, 200, 'TEST', SolverVariableType.unrestricted);
      expect(ev1.isCompatible(ev2), isFalse);
    });
  });
}
