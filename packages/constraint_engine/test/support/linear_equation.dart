// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.LinearEquation (test support
// class, upstream pinned in UPSTREAM.md).
//
// `var` is reserved in Dart, so the Java var(...) overloads become v(...)
// with runtime dispatch; plus/minus/withError/withSlack dispatch likewise.

import 'package:constraint_engine/constraint_engine.dart';

import 'amount.dart';
import 'equation_variable.dart';

enum _Type { equalsTo, lowerThan, greaterThan }

/// LinearEquation represents the linear equations fed into the solver: an
/// equality or an inequality between arbitrary lists of terms, in the form
/// `a0x0 + a1x1 + ... = C + a2x2 + a3x3 + ...`.
class LinearEquation {
  final List<EquationVariable> _leftSide = [];
  final List<EquationVariable> _rightSide = [];
  late List<EquationVariable> _currentSide;

  _Type _type = _Type.equalsTo;

  LinearSystem? _system;

  static int _artificialIndex = 0;
  static int _slackIndex = 0;
  static int _errorIndex = 0;

  static String getNextArtificialVariableName() => 'a${++_artificialIndex}';

  static String getNextSlackVariableName() => 's${++_slackIndex}';

  static String getNextErrorVariableName() => 'e${++_errorIndex}';

  /// Reset the counters for the automatic slack and error variable naming.
  static void resetNaming() {
    _artificialIndex = 0;
    _slackIndex = 0;
    _errorIndex = 0;
  }

  /// Base constructor, set the current side to the left side.
  LinearEquation([LinearSystem? system]) {
    _currentSide = _leftSide;
    _system = system;
  }

  /// Copy constructor.
  LinearEquation.copy(LinearEquation equation) {
    for (final v in equation._leftSide) {
      _leftSide.add(EquationVariable.copy(v));
    }
    for (final v in equation._rightSide) {
      _rightSide.add(EquationVariable.copy(v));
    }
    _currentSide = _rightSide;
  }

  bool isNull() {
    if (_leftSide.isEmpty && _rightSide.isEmpty) {
      return true;
    }
    if (_leftSide.length == 1 && _rightSide.length == 1) {
      final v1 = _leftSide[0];
      final v2 = _rightSide[0];
      if (v1.isConstant() &&
          v2.isConstant() &&
          v1.getAmount().isNull() &&
          v2.getAmount().isNull()) {
        return true;
      }
    }
    return false;
  }

  /// Transform a LinearEquation into an ArrayRow.
  static ArrayRow createRowFromEquation(
      LinearSystem linearSystem, LinearEquation e) {
    e.normalize();
    e.moveAllToTheRight();
    // Let's build a row from the LinearEquation
    final row = linearSystem.createRow();
    final eq = e.getRightSide();
    final count = eq.length;
    for (var i = 0; i < count; i++) {
      final v = eq[i];
      final sv = v.getSolverVariable();
      if (sv != null) {
        final previous = row.variables.get(sv);
        row.variables.put(sv, previous + v.getAmount().toFloat());
      } else {
        row.mConstantValue = v.getAmount().toFloat();
      }
    }
    return row;
  }

  /// Insert the equation in the system.
  void i() {
    if (_system == null) {
      return;
    }
    final row = createRowFromEquation(_system!, this);
    _system!.addConstraint(row);
  }

  void setLeftSide() {
    _currentSide = _leftSide;
  }

  void clearLeftSide() {
    _leftSide.clear();
  }

  void remove(SolverVariable v) {
    var ev = _find(v, _leftSide);
    if (ev != null) {
      _leftSide.remove(ev);
    }
    ev = _find(v, _rightSide);
    if (ev != null) {
      _rightSide.remove(ev);
    }
  }

  void setSystem(LinearSystem system) {
    _system = system;
  }

  /// Set the equality operator and switch to the right side.
  LinearEquation equalsTo() {
    _currentSide = _rightSide;
    return this;
  }

  /// Set the greater-than operator and switch to the right side.
  LinearEquation greaterThan() {
    _currentSide = _rightSide;
    _type = _Type.greaterThan;
    return this;
  }

  /// Set the lower-than operator and switch to the right side.
  LinearEquation lowerThan() {
    _currentSide = _rightSide;
    _type = _Type.lowerThan;
    return this;
  }

  /// Normalize the equation: an inequality is transformed into an equality by
  /// automatically adding a slack variable.
  void normalize() {
    if (_type == _Type.equalsTo) {
      return;
    }
    _currentSide = _leftSide;
    if (_type == _Type.lowerThan) {
      withSlack(1);
    } else if (_type == _Type.greaterThan) {
      withSlack(-1);
    }
    _type = _Type.equalsTo;
    _currentSide = _rightSide;
  }

  /// Regroup similar variables per side into one term,
  /// e.g. `2a + b + 3a = b - c` becomes `5a + b = b - c`.
  void simplify() {
    _simplifySide(_leftSide);
    _simplifySide(_rightSide);
  }

  void _simplifySide(List<EquationVariable> side) {
    EquationVariable? constant;
    final variables = <String, EquationVariable>{};
    final variablesNames = <String>[];
    for (final v in side) {
      if (v.isConstant()) {
        if (constant == null) {
          constant = v;
        } else {
          constant.add(v);
        }
      } else {
        final existing = variables[v.getName()!];
        if (existing != null) {
          existing.add(v);
        } else {
          variables[v.getName()!] = v;
          variablesNames.add(v.getName()!);
        }
      }
    }
    side.clear();
    if (constant != null) {
      side.add(constant);
    }
    variablesNames.sort();
    for (final name in variablesNames) {
      side.add(variables[name]!);
    }
    _removeNullTerms(side);
  }

  void moveAllToTheRight() {
    for (final v in _leftSide) {
      _rightSide.add(v.inverse());
    }
    _leftSide.clear();
  }

  /// Balance the equation to have one term on the left side, preferring an
  /// unconstrained variable, then slack, then error.
  void balance() {
    if (_leftSide.isEmpty && _rightSide.isEmpty) {
      return;
    }
    _currentSide = _leftSide;
    for (final v in _leftSide) {
      _rightSide.add(v.inverse());
    }
    _leftSide.clear();
    _simplifySide(_rightSide);
    EquationVariable? found;
    for (final v in _rightSide) {
      if (v.getType() == SolverVariableType.unrestricted) {
        found = v;
        break;
      }
    }
    if (found == null) {
      for (final v in _rightSide) {
        if (v.getType() == SolverVariableType.slack) {
          found = v;
          break;
        }
      }
    }
    if (found == null) {
      for (final v in _rightSide) {
        if (v.getType() == SolverVariableType.error) {
          found = v;
          break;
        }
      }
    }
    if (found == null) {
      return;
    }
    _rightSide.remove(found);
    found.inverse();
    if (!found.getAmount().isOne()) {
      final foundAmount = found.getAmount();
      for (final v in _rightSide) {
        v.getAmount().divide(foundAmount);
      }
      found.setAmount(Amount.of(1));
    }
    _simplifySide(_rightSide);
    _leftSide.add(found);
  }

  void _removeNullTerms(List<EquationVariable> list) {
    var hasNullTerm = false;
    for (final v in list) {
      if (v.getAmount().isNull()) {
        hasNullTerm = true;
        break;
      }
    }
    if (hasNullTerm) {
      // if some elements are now zero, remove them from the side
      final newSide = <EquationVariable>[];
      for (final v in list) {
        if (!v.getAmount().isNull()) {
          newSide.add(v);
        }
      }
      list.clear();
      list.addAll(newSide);
    }
  }

  /// Pivot this equation on the variable: it becomes the only term on the
  /// left side.
  void pivot(SolverVariable variable) {
    if (_leftSide.length == 1 &&
        identical(_leftSide[0].getSolverVariable(), variable)) {
      // no-op, we're already pivoted.
      return;
    }
    for (final v in _leftSide) {
      _rightSide.add(v.inverse());
    }
    _leftSide.clear();
    _simplifySide(_rightSide);
    EquationVariable? found;
    for (final v in _rightSide) {
      if (identical(v.getSolverVariable(), variable)) {
        found = v;
        break;
      }
    }
    if (found != null) {
      _rightSide.remove(found);
      found.inverse();
      if (!found.getAmount().isOne()) {
        final foundAmount = found.getAmount();
        for (final v in _rightSide) {
          v.getAmount().divide(foundAmount);
        }
        found.setAmount(Amount.of(1));
      }
      _leftSide.add(found);
    }
  }

  /// Returns true if the constant is negative.
  bool hasNegativeConstant() {
    for (final v in _rightSide) {
      if (v.isConstant() && v.getAmount().isNegative()) {
        return true;
      }
    }
    return false;
  }

  /// The constant on the right side, if present. The equation is expected to
  /// be balanced before using this function.
  Amount? getConstant() {
    for (final v in _rightSide) {
      if (v.isConstant()) {
        return v.getAmount();
      }
    }
    return null;
  }

  /// Inverse the equation (multiply both sides by -1).
  void inverse() {
    final amount = Amount.of(-1);
    for (final v in _leftSide) {
      v.multiplyAmount(amount);
    }
    for (final v in _rightSide) {
      v.multiplyAmount(amount);
    }
  }

  EquationVariable? getFirstUnconstrainedVariable() {
    for (final v in _leftSide) {
      if (v.getType() == SolverVariableType.unrestricted) {
        return v;
      }
    }
    for (final v in _rightSide) {
      if (v.getType() == SolverVariableType.unrestricted) {
        return v;
      }
    }
    return null;
  }

  EquationVariable? getLeftVariable() {
    if (_leftSide.length == 1) {
      return _leftSide[0];
    }
    return null;
  }

  /// Replace the variable v in this equation by the right side of equation l.
  void replace(SolverVariable v, LinearEquation l) {
    _replaceIn(v, l, _leftSide);
    _replaceIn(v, l, _rightSide);
  }

  void _replaceIn(
      SolverVariable v, LinearEquation l, List<EquationVariable> list) {
    final toReplace = _find(v, list);
    if (toReplace != null) {
      list.remove(toReplace);
      final amount = toReplace.getAmount();
      for (final lv in l._rightSide) {
        list.add(EquationVariable.scaled(amount, lv));
      }
    }
  }

  EquationVariable? _find(SolverVariable v, List<EquationVariable> list) {
    for (final ev in list) {
      if (identical(ev.getSolverVariable(), v)) {
        return ev;
      }
    }
    return null;
  }

  List<EquationVariable> getRightSide() => _rightSide;

  bool contains(SolverVariable solverVariable) {
    if (_find(solverVariable, _leftSide) != null) {
      return true;
    }
    if (_find(solverVariable, _rightSide) != null) {
      return true;
    }
    return false;
  }

  EquationVariable? getVariable(SolverVariable solverVariable) {
    final variable = _find(solverVariable, _rightSide);
    if (variable != null) {
      return variable;
    }
    return _find(solverVariable, _leftSide);
  }

  /// Add a term to the current side. Mirrors the Java var(...) overloads:
  /// `v(constant)`, `v(numerator, denominator)`, `v(name)`,
  /// `v(amount, name)`, `v(numerator, denominator, name)`.
  LinearEquation v(Object a, [Object? b, Object? c]) {
    if (a is int && b == null && c == null) {
      _currentSide.add(EquationVariable.constInt(_system!, a));
    } else if (a is int && b is int && c == null) {
      _currentSide.add(EquationVariable.constant(Amount(a, b)));
    } else if (a is String && b == null && c == null) {
      _currentSide.add(EquationVariable.unit(
          _system!, a, SolverVariableType.unrestricted));
    } else if (a is int && b is String && c == null) {
      _currentSide.add(EquationVariable.intAmount(
          _system!, a, b, SolverVariableType.unrestricted));
    } else if (a is int && b is int && c is String) {
      _currentSide.add(EquationVariable(
          _system!, Amount(a, b), c, SolverVariableType.unrestricted));
    } else {
      throw ArgumentError('unsupported v() arguments: $a, $b, $c');
    }
    return this;
  }

  /// Convenience add: `plus(name)`, `plus(amount, name)`, `plus(constant)`,
  /// `plus(numerator, denominator)`.
  LinearEquation plus(Object a, [Object? b]) {
    v(a, b);
    return this;
  }

  /// Convenience subtract: `minus(name)`, `minus(amount, name)`,
  /// `minus(constant)`, `minus(numerator, denominator)`.
  LinearEquation minus(Object a, [Object? b]) {
    if (a is String) {
      v(-1, a);
    } else if (a is int && b is String) {
      v(-1 * a, b);
    } else if (a is int && b is int) {
      v(a * -1, b);
    } else if (a is int) {
      v(a * -1);
    } else {
      throw ArgumentError('unsupported minus() arguments: $a, $b');
    }
    return this;
  }

  /// Add an error variable to the current side. Mirrors the Java overloads:
  /// `withError()`, `withError(strength)`, `withError(name, strength)`,
  /// `withError(amount, name)`.
  LinearEquation withError([Object? a, Object? b]) {
    if (a == null) {
      final name = getNextErrorVariableName();
      withError('$name+', 1);
      withError('$name-', -1);
    } else if (a is String && b is int) {
      _currentSide.add(EquationVariable.intAmount(
          _system!, b, a, SolverVariableType.error));
    } else if (a is Amount && b is String) {
      _currentSide
          .add(EquationVariable(_system!, a, b, SolverVariableType.error));
    } else if (a is int && b == null) {
      withError(getNextErrorVariableName(), a);
    } else {
      throw ArgumentError('unsupported withError() arguments: $a, $b');
    }
    return this;
  }

  LinearEquation withPositiveError() {
    final name = getNextErrorVariableName();
    withError('$name+', 1);
    return this;
  }

  EquationVariable addArtificialVar() {
    final e = EquationVariable.intAmount(
        _system!, 1, getNextArtificialVariableName(), SolverVariableType.error);
    _currentSide.add(e);
    return e;
  }

  /// Add a slack variable to the current side. Mirrors the Java overloads:
  /// `withSlack()`, `withSlack(strength)`, `withSlack(name, strength)`,
  /// `withSlack(amount, name)`.
  LinearEquation withSlack([Object? a, Object? b]) {
    if (a == null) {
      withSlack(getNextSlackVariableName(), 1);
    } else if (a is String && b is int) {
      _currentSide.add(EquationVariable.intAmount(
          _system!, b, a, SolverVariableType.slack));
    } else if (a is Amount && b is String) {
      _currentSide
          .add(EquationVariable(_system!, a, b, SolverVariableType.slack));
    } else if (a is int && b == null) {
      withSlack(getNextSlackVariableName(), a);
    } else {
      throw ArgumentError('unsupported withSlack() arguments: $a, $b');
    }
    return this;
  }

  @override
  String toString() {
    var result = _sideToString(_leftSide);
    switch (_type) {
      case _Type.equalsTo:
        result += '= ';
      case _Type.lowerThan:
        result += '<= ';
      case _Type.greaterThan:
        result += '>= ';
    }
    result += _sideToString(_rightSide);
    return result.trim();
  }

  String _sideToString(List<EquationVariable> side) {
    var result = '';
    var first = true;
    for (final v in side) {
      if (first) {
        if (v.getAmount().isPositive()) {
          result += '$v ';
        } else {
          result += '${v.signString()} $v ';
        }
        first = false;
      } else {
        result += '${v.signString()} $v ';
      }
    }
    if (side.isEmpty) {
      result = '0';
    }
    return result;
  }
}
