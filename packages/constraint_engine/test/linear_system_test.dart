// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.LinearSystemTest (upstream
// pinned in UPSTREAM.md). The Java var(...) DSL calls become v(...);
// row.addError(system, strength) becomes row.addErrorToRow.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:test/test.dart';

import 'support/linear_equation.dart';

void main() {
  group('LinearSystemTest', () {
    late LinearSystem ls;

    setUp(() {
      ls = LinearSystem();
      LinearEquation.resetNaming();
    });

    void add(LinearEquation equation) {
      final row1 = LinearEquation.createRowFromEquation(ls, equation);
      ls.addConstraint(row1);
    }

    void addWithStrength(LinearEquation equation, int strength) {
      final row1 = LinearEquation.createRowFromEquation(ls, equation);
      row1.addErrorToRow(ls, strength);
      ls.addConstraint(row1);
    }

    test('testMinMax', () {
      // this shows how basic min/max + wrap works.
      add(LinearEquation(ls).v('Rl').equalsTo().v(0));
      add(LinearEquation(ls).v('Br').equalsTo().v('Bl').plus(300));
      addWithStrength(LinearEquation(ls).v('Al').equalsTo().v('Rl'), 1);
      addWithStrength(LinearEquation(ls).v('Ar').equalsTo().v('Rr'), 1);
      addWithStrength(
          LinearEquation(ls).v('Ar').greaterThan().v('Al').plus(150), 2);
      addWithStrength(
          LinearEquation(ls).v('Ar').lowerThan().v('Al').plus(200), 2);
      add(LinearEquation(ls).v('Rr').greaterThan().v('Ar'));
      add(LinearEquation(ls).v('Rr').greaterThan().v('Br'));
      add(LinearEquation(ls).v('Al').minus('Rl').equalsTo().v('Rr').minus('Ar'));
      add(LinearEquation(ls).v('Bl').minus('Rl').equalsTo().v('Rr').minus('Br'));
      ls.minimize();
      expect(ls.getValueFor('Al'), 50.0);
      expect(ls.getValueFor('Ar'), 250.0);
      expect(ls.getValueFor('Bl'), 0.0);
      expect(ls.getValueFor('Br'), 300.0);
      expect(ls.getValueFor('Rr'), 300.0);
    });

    test('testPriorityBasic', () {
      add(LinearEquation(ls).v(2, 'Xm').equalsTo().v('Xl').plus('Xr'));
      add(LinearEquation(ls).v('Xl').plus(10).lowerThan().v('Xr'));
      add(LinearEquation(ls).v('Xr').lowerThan().v(100));
      addWithStrength(LinearEquation(ls).v('Xm').equalsTo().v(50), 2);
      addWithStrength(LinearEquation(ls).v('Xl').equalsTo().v(30), 1);
      addWithStrength(LinearEquation(ls).v('Xr').equalsTo().v(60), 1);
      ls.minimize();
      expect(ls.getValueFor('Xm'), 50.0);
      expect(ls.getValueFor('Xl'), 40.0);
      expect(ls.getValueFor('Xr'), 60.0);
    });

    test('testPriorities', () {
      // | <- a -> | b
      // a - zero = c - a; 2a = c + zero; a = (c + zero) / 2
      addWithStrength(LinearEquation(ls).v('b').equalsTo().v(100), 3);
      addWithStrength(LinearEquation(ls).v('zero').equalsTo().v(0), 3);
      addWithStrength(LinearEquation(ls).v('a').equalsTo().v(300), 0);
      addWithStrength(LinearEquation(ls).v('c').equalsTo().v(200), 0);

      addWithStrength(
          LinearEquation(ls).v('c').lowerThan().v('b').minus(10), 2);
      addWithStrength(LinearEquation(ls).v('a').lowerThan().v('c'), 2);

      addWithStrength(
          LinearEquation(ls).v('a').minus('zero').equalsTo().v('c').minus('a'),
          1);

      ls.minimize();
      expect(ls.getValueFor('zero'), 0.0);
      expect(ls.getValueFor('a'), 45.0);
      expect(ls.getValueFor('b'), 100.0);
      expect(ls.getValueFor('c'), 90.0);
    });

    test('testOptimizeAndPriority', () {
      ls.reset();
      final eq1 = LinearEquation(ls);
      final eq2 = LinearEquation(ls);
      final eq3 = LinearEquation(ls);
      final eq4 = LinearEquation(ls);
      final eq5 = LinearEquation(ls);
      final eq6 = LinearEquation(ls);
      final eq7 = LinearEquation(ls);
      final eq8 = LinearEquation(ls);
      final eq9 = LinearEquation(ls);
      final eq10 = LinearEquation(ls);

      eq1.v('Root.left').equalsTo().v(0);
      eq2.v('Root.right').equalsTo().v(600);
      eq3.v('A.right').equalsTo().v('A.left').plus(100);
      eq4.v('A.left').greaterThan().v('Root.left');
      eq10.v('A.left').equalsTo().v('Root.left');
      eq5.v('A.right').lowerThan().v('B.left');
      eq6.v('B.right').greaterThan().v('B.left');
      eq7.v('B.right').lowerThan().v('Root.right');
      eq8.v('B.left').equalsTo().v('A.right');
      eq9.v('B.right').greaterThan().v('Root.right');

      final row1 = LinearEquation.createRowFromEquation(ls, eq1);
      ls.addConstraint(row1);

      final row2 = LinearEquation.createRowFromEquation(ls, eq2);
      ls.addConstraint(row2);

      final row3 = LinearEquation.createRowFromEquation(ls, eq3);
      ls.addConstraint(row3);

      final row10 = LinearEquation.createRowFromEquation(ls, eq10);
      ls.addSingleError(row10, 1, SolverVariable.STRENGTH_MEDIUM);
      ls.addSingleError(row10, -1, SolverVariable.STRENGTH_MEDIUM);
      ls.addConstraint(row10);

      final row4 = LinearEquation.createRowFromEquation(ls, eq4);
      ls.addSingleError(row4, -1, SolverVariable.STRENGTH_HIGH);
      ls.addConstraint(row4);

      final row5 = LinearEquation.createRowFromEquation(ls, eq5);
      ls.addSingleError(row5, 1, SolverVariable.STRENGTH_MEDIUM);
      ls.addConstraint(row5);

      final row6 = LinearEquation.createRowFromEquation(ls, eq6);
      ls.addSingleError(row6, -1, SolverVariable.STRENGTH_LOW);
      ls.addConstraint(row6);

      final row7 = LinearEquation.createRowFromEquation(ls, eq7);
      ls.addSingleError(row7, 1, SolverVariable.STRENGTH_LOW);
      ls.addConstraint(row7);

      final row8 = LinearEquation.createRowFromEquation(ls, eq8);
      row8.addErrorToRow(ls, SolverVariable.STRENGTH_LOW);
      ls.addConstraint(row8);

      final row9 = LinearEquation.createRowFromEquation(ls, eq9);
      ls.addSingleError(row9, -1, SolverVariable.STRENGTH_LOW);
      ls.addConstraint(row9);

      ls.minimize();
    });

    test('testPriority', () {
      for (var i = 0; i < 3; i++) {
        ls.reset();
        final eq1 = LinearEquation(ls);
        eq1.v('A').equalsTo().v(10);
        final row1 = LinearEquation.createRowFromEquation(ls, eq1);
        row1.addErrorToRow(ls, i % 3);
        ls.addConstraint(row1);

        final eq2 = LinearEquation(ls);
        eq2.v('A').equalsTo().v(100);
        final row2 = LinearEquation.createRowFromEquation(ls, eq2);
        row2.addErrorToRow(ls, (i + 1) % 3);
        ls.addConstraint(row2);

        final eq3 = LinearEquation(ls);
        eq3.v('A').equalsTo().v(1000);
        final row3 = LinearEquation.createRowFromEquation(ls, eq3);
        row3.addErrorToRow(ls, (i + 2) % 3);
        ls.addConstraint(row3);

        ls.minimize();
        if (i == 0) {
          expect(ls.getValueFor('A'), 1000.0, reason: 'iteration $i');
        } else if (i == 1) {
          expect(ls.getValueFor('A'), 100.0, reason: 'iteration $i');
        } else if (i == 2) {
          expect(ls.getValueFor('A'), 10.0, reason: 'iteration $i');
        }
      }
    });

    test('testAddEquation1', () {
      final e1 = LinearEquation(ls);
      e1.v('W3.left').equalsTo().v(0);
      ls.addConstraint(LinearEquation.createRowFromEquation(ls, e1));
      final result = ls.getGoal().toString();
      expect(result == '0 = 0.0' || result == ' goal -> (0.0) : ', isTrue,
          reason: 'unexpected goal: "$result"');
      expect(ls.getValueFor('W3.left'), 0.0);
    });

    test('testAddEquation2', () {
      final e1 = LinearEquation(ls);
      e1.v('W3.left').equalsTo().v(0);
      final e2 = LinearEquation(ls);
      e2.v('W3.right').equalsTo().v(600);
      ls.addConstraint(LinearEquation.createRowFromEquation(ls, e1));
      ls.addConstraint(LinearEquation.createRowFromEquation(ls, e2));
      final result = ls.getGoal().toString();
      expect(result == '0 = 0.0' || result == ' goal -> (0.0) : ', isTrue,
          reason: 'unexpected goal: "$result"');
      expect(ls.getValueFor('W3.left'), 0.0);
      expect(ls.getValueFor('W3.right'), 600.0);
    });

    test('testAddEquation3', () {
      final e1 = LinearEquation(ls);
      e1.v('W3.left').equalsTo().v(0);
      final e2 = LinearEquation(ls);
      e2.v('W3.right').equalsTo().v(600);
      final leftConstraint = LinearEquation(ls);
      leftConstraint.v('W4.left').equalsTo().v('W3.left');
      ls.addConstraint(LinearEquation.createRowFromEquation(ls, e1));
      ls.addConstraint(LinearEquation.createRowFromEquation(ls, e2));
      ls.addConstraint(LinearEquation.createRowFromEquation(ls, leftConstraint));
      expect(ls.getValueFor('W3.left'), 0.0);
      expect(ls.getValueFor('W3.right'), 600.0);
      expect(ls.getValueFor('W4.left'), 0.0);
    });

    test('testAddEquation4', () {
      final e1 = LinearEquation(ls);
      final e2 = LinearEquation(ls);
      final e3 = LinearEquation(ls);
      final e4 = LinearEquation(ls);
      e1.v(2, 'Xm').equalsTo().v('Xl').plus('Xr');
      final goalRow = ls.getGoal();
      ls.addConstraint(LinearEquation.createRowFromEquation(ls, e1));
      goalRow.addError(ls.getVariable('Xm', SolverVariableType.error));
      goalRow.addError(ls.getVariable('Xl', SolverVariableType.error));
      e2.v('Xl').plus(10).lowerThan().v('Xr');
      ls.addConstraint(LinearEquation.createRowFromEquation(ls, e2));
      e3.v('Xl').greaterThan().v(-10);
      ls.addConstraint(LinearEquation.createRowFromEquation(ls, e3));
      e4.v('Xr').lowerThan().v(100);
      ls.addConstraint(LinearEquation.createRowFromEquation(ls, e4));
      final goal = LinearEquation(ls);
      goal.v('Xm').minus('Xl');
      ls.minimizeGoal(LinearEquation.createRowFromEquation(ls, goal));
      final e5 = LinearEquation(ls);
      e5.v('Xm').equalsTo().v(50);
      ls.addConstraint(LinearEquation.createRowFromEquation(ls, e5));
      ls.minimizeGoal(goalRow);
      final xl = ls.getValueFor('Xl').toInt();
      final xm = ls.getValueFor('Xm').toInt();
      final xr = ls.getValueFor('Xr').toInt();
      expect(xl, 0);
      expect(xm, 50);
      expect(xr, 100);
    });
  });
}
