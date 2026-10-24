// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.EquationVariable (test support
// class, upstream pinned in UPSTREAM.md). Java constructor overloads become
// named constructors.

import 'package:constraint_engine/constraint_engine.dart';

import 'amount.dart';

/// EquationVariable is used to represent a variable in a `LinearEquation`.
class EquationVariable {
  Amount _amount;
  SolverVariable? _variable;

  /// Base constructor: amount, name and type.
  EquationVariable(
      LinearSystem system, Amount amount, String name, SolverVariableType type)
      : _amount = amount,
        _variable = system.getVariable(name, type);

  /// Constant with the given amount.
  EquationVariable.constant(Amount amount) : _amount = amount;

  /// Integer amount, name and type.
  EquationVariable.intAmount(
      LinearSystem system, int amount, String name, SolverVariableType type)
      : _amount = Amount.of(amount),
        _variable = system.getVariable(name, type);

  /// Integer constant.
  EquationVariable.constInt(LinearSystem system, int amount)
      : _amount = Amount.of(amount);

  /// Factor of one, name and type.
  EquationVariable.unit(LinearSystem system, String name, SolverVariableType type)
      : _amount = Amount.of(1),
        _variable = system.getVariable(name, type);

  /// Multiply an amount with a given EquationVariable.
  EquationVariable.scaled(Amount amount, EquationVariable variable)
      : _amount = Amount.copy(amount) {
    _amount.multiply(variable._amount);
    _variable = variable.getSolverVariable();
  }

  /// Copy constructor.
  EquationVariable.copy(EquationVariable v)
      : _amount = Amount.copy(v._amount),
        _variable = v.getSolverVariable();

  String? getName() => _variable?.getName();

  SolverVariableType getType() =>
      _variable == null ? SolverVariableType.constant : _variable!.mType;

  SolverVariable? getSolverVariable() => _variable;

  bool isConstant() => _variable == null;

  Amount getAmount() => _amount;

  void setAmount(Amount amount) {
    _amount = amount;
  }

  /// Inverse the current amount (from negative to positive or the reverse).
  EquationVariable inverse() {
    _amount.inverse();
    return this;
  }

  /// Returns true if the variables are compatible (same type, same name).
  bool isCompatible(EquationVariable variable) {
    if (isConstant()) {
      return variable.isConstant();
    } else if (variable.isConstant()) {
      return false;
    }
    return identical(variable.getSolverVariable(), getSolverVariable());
  }

  void add(EquationVariable variable) {
    if (variable.isCompatible(this)) {
      _amount.add(variable._amount);
    }
  }

  void subtract(EquationVariable variable) {
    if (variable.isCompatible(this)) {
      _amount.subtract(variable._amount);
    }
  }

  void multiply(EquationVariable variable) {
    multiplyAmount(variable.getAmount());
  }

  void multiplyAmount(Amount amount) {
    _amount.multiply(amount);
  }

  void divide(EquationVariable variable) {
    _amount.divide(variable._amount);
  }

  @override
  String toString() {
    if (isConstant()) {
      return '$_amount';
    }
    if (_amount.isOne() || _amount.isMinusOne()) {
      return '$_variable';
    }
    return '$_amount $_variable';
  }

  /// The sign of the variable as a string, either + or -.
  String signString() {
    if (_amount.isPositive()) {
      return '+';
    }
    return '-';
  }
}
