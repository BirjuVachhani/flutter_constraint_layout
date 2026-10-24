// Copyright (C) 2021 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.LinearEquationTest (upstream
// pinned in UPSTREAM.md). The Java var(...) DSL calls become v(...).

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/linear_equation.dart';

void main() {
  group('LinearEquationTest', () {
    late LinearSystem ls;
    late LinearEquation le;

    setUp(() {
      ls = LinearSystem();
      le = LinearEquation();
      le.setSystem(ls);
      LinearEquation.resetNaming();
    });

    test('testDisplay1', () {
      le.v('A').equalsTo().v(100);
      expect(le.toString(), 'A = 100');
    });

    test('testDisplay2', () {
      le.v('A').equalsTo().v('B');
      expect(le.toString(), 'A = B');
    });

    test('testDisplay3', () {
      le.v('A').greaterThan().v('B');
      expect(le.toString(), 'A >= B');
    });

    test('testDisplay4', () {
      le.v('A').lowerThan().v('B');
      expect(le.toString(), 'A <= B');
    });

    test('testDisplay5', () {
      le.v('A').greaterThan().v('B').plus(100);
      expect(le.toString(), 'A >= B + 100');
    });

    test('testDisplay6', () {
      le.v('A').plus('B').minus('C').plus(50)
          .greaterThan().v('B').plus('C').minus(100);
      expect(le.toString(), 'A + B - C + 50 >= B + C - 100');
    });

    test('testDisplay7', () {
      le.v('A').lowerThan().v('B');
      le.normalize();
      expect(le.toString(), 'A + s1 = B');
    });

    test('testDisplay8', () {
      le.v('A').greaterThan().v('B');
      le.normalize();
      expect(le.toString(), 'A - s1 = B');
    });

    test('testDisplay9', () {
      le.v('A').greaterThan().v('B').withError();
      le.normalize();
      expect(le.toString(), 'A - s1 = B + e1+ - e1-');
    });

    test('testDisplaySimplify', () {
      le.v('A').plus(5).minus(2).plus(2, 'B').minus(3, 'B')
          .greaterThan().v('C').minus(3, 'C').withError();
      expect(le.toString(), 'A + 5 - 2 + 2 B - 3 B >= C - 3 C + e1+ - e1-');
      le.normalize();
      expect(le.toString(), 'A + 5 - 2 + 2 B - 3 B - s1 = C - 3 C + e1+ - e1-');
      le.simplify();
      expect(le.toString(), '3 + A - B - s1 = - 2 C + e1+ - e1-');
    });

    test('testDisplayBalance1', () {
      le.v('A').plus(5).minus(2).plus(2, 'B').minus(3, 'B')
          .greaterThan().v('C').minus(3, 'C').withError();
      le.normalize();
      le.balance();
      expect(le.toString(), 'A = - 3 + B - 2 C + e1+ - e1- + s1');
    });

    test('testDisplayBalance2', () {
      le.plus(5).minus(2).minus(2, 'A').minus(3, 'B').equalsTo().v(5, 'C');
      le.balance();
      expect(le.toString(), 'A = 3/2 - 3/2 B - 5/2 C');
    });

    test('testDisplayBalance3', () {
      le.plus(5).equalsTo().v(3);
      le.balance();
    });

    test('testDisplayBalance4', () {
      // s1 = - 200 - e1- + 236 + e1- + e2+ - e2-
      le.withSlack().equalsTo().v(-200).withError('e1-', -1).plus(236);
      le.withError('e1-', 1).withError('e2+', 1).withError('e2-', -1);
      le.balance();
      expect(le.toString(), 's1 = 36 + e2+ - e2-');
    });

    test('testDisplayBalance5', () {
      // 236 + e1- + e2+ - e2- = e1- - e2+ + e2-
      le.v(236).withError('e1-', 1).withError('e2+', 1).withError('e2-', -1);
      le.equalsTo().withError('e1-', 1).withError('e2+', -1).withError('e2-', 1);
      le.balance();
      // 2 e2+ = -236 + 2 e2- so e2+ = -118 + e2-
      expect(le.toString(), 'e2+ = - 118 + e2-');
    });
  });
}
