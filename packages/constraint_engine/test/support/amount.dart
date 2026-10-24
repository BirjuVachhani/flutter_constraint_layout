// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.Amount (test support class,
// upstream pinned in UPSTREAM.md).

/// Represents the amount of a given `EquationVariable`, can be fractional.
class Amount {
  int _numerator = 0;
  int _denominator = 1;

  /// Base constructor, set the numerator and denominator.
  Amount(int numerator, int denominator) {
    _numerator = numerator;
    _denominator = denominator;
    _simplify();
  }

  /// Alternate constructor: numerator only, denominator one. Does not
  /// simplify (upstream parity).
  Amount.of(int numerator)
      : _numerator = numerator,
        _denominator = 1;

  Amount.copy(Amount amount) {
    _numerator = amount._numerator;
    _denominator = amount._denominator;
    _simplify();
  }

  void set(int numerator, int denominator) {
    _numerator = numerator;
    _denominator = denominator;
    _simplify();
  }

  /// Add an amount to the current one.
  Amount add(Amount amount) {
    if (_denominator == amount._denominator) {
      _numerator += amount._numerator;
    } else {
      _numerator =
          _numerator * amount._denominator + amount._numerator * _denominator;
      _denominator = _denominator * amount._denominator;
    }
    _simplify();
    return this;
  }

  /// Add an integer amount.
  Amount addInt(int amount) {
    _numerator += amount * _denominator;
    return this;
  }

  /// Subtract an amount from the current one.
  Amount subtract(Amount amount) {
    if (_denominator == amount._denominator) {
      _numerator -= amount._numerator;
    } else {
      _numerator =
          _numerator * amount._denominator - amount._numerator * _denominator;
      _denominator = _denominator * amount._denominator;
    }
    _simplify();
    return this;
  }

  /// Multiply an amount with the current one.
  Amount multiply(Amount amount) {
    _numerator = _numerator * amount._numerator;
    _denominator = _denominator * amount._denominator;
    _simplify();
    return this;
  }

  /// Divide the current amount by the given amount.
  Amount divide(Amount amount) {
    _numerator = _numerator * amount._denominator;
    _denominator = _denominator * amount._numerator;
    _simplify();
    return this;
  }

  /// Inverse the current amount as a fraction (a/b becomes b/a).
  Amount inverseFraction() {
    final n = _numerator;
    _numerator = _denominator;
    _denominator = n;
    _simplify();
    return this;
  }

  /// Inverse the current amount (positive to negative or the reverse).
  Amount inverse() {
    _numerator *= -1;
    _simplify();
    return this;
  }

  int getNumerator() => _numerator;

  int getDenominator() => _denominator;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Amount) return false;
    return _numerator == other._numerator && _denominator == other._denominator;
  }

  @override
  int get hashCode => Object.hash(_numerator, _denominator);

  /// Simplify: reduce by the GCD; normalize signs so the denominator is
  /// positive.
  void _simplify() {
    if (_numerator < 0 && _denominator < 0) {
      _numerator *= -1;
      _denominator *= -1;
    } else if (_numerator >= 0 && _denominator < 0) {
      _numerator *= -1;
      _denominator *= -1;
    }
    if (_denominator > 1) {
      int commonDenominator;
      if (_denominator == 2 && _numerator % 2 == 0) {
        commonDenominator = 2;
      } else {
        commonDenominator = _gcd(_numerator, _denominator);
      }
      _numerator ~/= commonDenominator;
      _denominator ~/= commonDenominator;
    }
  }

  /// Iterative binary GCD algorithm.
  static int _gcd(int u, int v) {
    int shift;

    if (u < 0) {
      u *= -1;
    }
    if (v < 0) {
      v *= -1;
    }
    if (u == 0) {
      return v;
    }
    if (v == 0) {
      return u;
    }

    for (shift = 0; ((u | v) & 1) == 0; shift++) {
      u >>= 1;
      v >>= 1;
    }

    while ((u & 1) == 0) {
      u >>= 1;
    }

    do {
      while ((v & 1) == 0) {
        v >>= 1;
      }
      if (u > v) {
        final t = v;
        v = u;
        u = t;
      }
      v = v - u;
    } while (v != 0);
    return u << shift;
  }

  bool isOne() => _numerator == 1 && _denominator == 1;

  bool isMinusOne() => _numerator == -1 && _denominator == 1;

  bool isPositive() => _numerator >= 0 && _denominator >= 0;

  bool isNegative() => _numerator < 0;

  bool isNull() => _numerator == 0;

  void setToZero() {
    _numerator = 0;
    _denominator = 1;
  }

  /// Returns the floating point value of the Amount.
  double toFloat() {
    if (_denominator >= 1) {
      return _numerator / _denominator;
    }
    return 0;
  }

  @override
  String toString() {
    if (_denominator == 1) {
      if (_numerator == 1 || _numerator == -1) {
        return '';
      }
      if (_numerator < 0) {
        return '${_numerator * -1}';
      }
      return '$_numerator';
    }
    if (_numerator < 0) {
      return '${_numerator * -1}/$_denominator';
    }
    return '$_numerator/$_denominator';
  }

  String valueString() {
    if (_denominator == 1) {
      return '$_numerator';
    }
    return '$_numerator/$_denominator';
  }
}
