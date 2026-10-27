// Copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0
//
// No upstream counterpart. Java's numeric semantics for the port: upstream's
// engine computes in IEEE 754 binary32 (Java `float`), with one rounding per
// operation, and converts with Java's `(int)` cast, Java's `%`,
// Math.toRadians and Float.parseFloat. The port keeps each Java float in a
// Dart `double` that holds a binary32 value, and writes each Java float
// operation as exactly one call below, in Java's evaluation order, so the
// double carries the bits Android computes.
//
// | Java                                     | Dart                        |
// |------------------------------------------|-----------------------------|
// | `(float) d`                              | `f32(d)`                    |
// | `a + b`, `a - b`, `a * b`, `a / b`       | `fadd`, `fsub`, `fmul`,     |
// |   on floats                              |   `fdiv`                    |
// | `(float) i`, an int operand of a float   | `fi(i)`                     |
// |   operation                              |                             |
// | `(int) x`                                | `jint(x)`                   |
// | `a % b` on floats                        | `jfrem(a, b)`               |
// | `Math.toRadians(x)`                      | `toRadians(x)`              |
// | `Float.parseFloat(s)`                    | `parseFloat32(s)`           |
// | `0.001f`, `0.0001f`, `Float.MAX_VALUE`   | `kEps001`, `kEps0001`,      |
// |                                          |   `kFloatMax`               |
//
// Exact operations need no helper: unary minus, `Math.abs` (`abs()`),
// comparisons and `==`, widening a float to double, and `Math.max` or
// `Math.min` on floats (`dart:math`'s max and min share Java's NaN and
// signed-zero rules). Java's `+=` on a float is `x = fadd(x, y)`.

import 'dart:typed_data';

// One shared scratch slot: a store rounds a double to binary32 (IEEE
// roundTiesToEven, with overflow to infinity and gradual underflow), and the
// load widens it back exactly. The Uint32List view reads the raw bits.
final Float32List _scratch = Float32List(1);
final Uint32List _scratchBits = Uint32List.view(_scratch.buffer);

const int _two53 = 9007199254740992;

/// Java's `(float) x` for a double [x]: the nearest binary32 value, ties to
/// even, with overflow to infinity, gradual underflow to subnormals, and NaN
/// kept NaN.
///
/// Also the rounding behind every other helper here, and the value a
/// `Float32List` store keeps.
@pragma('vm:prefer-inline')
double f32(double x) {
  _scratch[0] = x;
  return _scratch[0];
}

/// Whether [x] is a binary32 value, as every Java float the port keeps must
/// be. NaN counts as one.
@pragma('vm:prefer-inline')
bool isF32(double x) => x.isNaN || f32(x) == x;

/// Java's `Float.floatToRawIntBits((float) x)` as an unsigned 32-bit int:
/// the raw bits of [x] rounded to binary32. The solver trace prints these.
@pragma('vm:prefer-inline')
int f32Bits(double x) {
  _scratch[0] = x;
  return _scratchBits[0];
}

/// Java's `Float.intBitsToFloat(bits)`: the binary32 value whose raw bits are
/// the low 32 bits of [bits].
@pragma('vm:prefer-inline')
double f32FromBits(int bits) {
  _scratchBits[0] = bits;
  return _scratch[0];
}

/// Java's `a + b` on two floats: one rounding of the exact sum.
///
/// The double sum of two binary32 values, rounded once more to binary32, is
/// the correctly rounded binary32 sum: a double has 53 bits, at least the
/// 2p + 2 = 50 that make the second rounding innocuous for `+ - * /`.
@pragma('vm:prefer-inline')
double fadd(double a, double b) {
  assert(
    isF32(a) && isF32(b),
    'fadd($a, $b): Java adds two floats, so each operand must already be '
    'binary32 (round it with f32, or convert an int with fi); a wider '
    'operand would round twice and miss the bits Android computes',
  );
  return f32(a + b);
}

/// Java's `a - b` on two floats: one rounding of the exact difference.
@pragma('vm:prefer-inline')
double fsub(double a, double b) {
  assert(
    isF32(a) && isF32(b),
    'fsub($a, $b): Java subtracts two floats, so each operand must already '
    'be binary32 (round it with f32, or convert an int with fi); a wider '
    'operand would round twice and miss the bits Android computes',
  );
  return f32(a - b);
}

/// Java's `a * b` on two floats: one rounding of the exact product (a double
/// holds the product of two binary32 values exactly).
@pragma('vm:prefer-inline')
double fmul(double a, double b) {
  assert(
    isF32(a) && isF32(b),
    'fmul($a, $b): Java multiplies two floats, so each operand must already '
    'be binary32 (round it with f32, or convert an int with fi); a wider '
    'operand would round twice and miss the bits Android computes',
  );
  return f32(a * b);
}

/// Java's `a / b` on two floats: one rounding of the exact quotient,
/// including `x / 0` (a signed infinity) and `0 / 0` (NaN).
@pragma('vm:prefer-inline')
double fdiv(double a, double b) {
  assert(
    isF32(a) && isF32(b),
    'fdiv($a, $b): Java divides two floats, so each operand must already be '
    'binary32 (round it with f32, or convert an int with fi); a wider '
    'operand would round twice and miss the bits Android computes',
  );
  return f32(a / b);
}

/// Java's `(float) i` for an integer [i], which is also how Java converts an
/// int operand of a float operation (`margin + value` is
/// `fadd(fi(margin), value)`): the nearest binary32 value, ties to even.
///
/// Exact for every Java int (they convert to double exactly, then round
/// once). An integer beyond 2^53 in magnitude, which no Java int can be,
/// rounds exactly as Java's `(float)` of a long does.
@pragma('vm:prefer-inline')
double fi(int i) {
  if (-_two53 <= i && i <= _two53) {
    return f32(i.toDouble());
  }
  return _fiWide(i);
}

double _fiWide(int i) {
  // i.toDouble() would round to 53 bits first, and that rounding can land on
  // a binary32 midpoint the exact integer is not on.
  final bits = _roundToFloatBits(BigInt.from(i).abs(), BigInt.one, 0);
  return f32FromBits(i < 0 ? bits | 0x80000000 : bits);
}

/// Java's `(int) x` for a float or a double [x] (JLS 5.1.3): NaN gives 0, a
/// value at or beyond the int range saturates to `Integer.MIN_VALUE`
/// (-2147483648) or `Integer.MAX_VALUE` (2147483647), and anything else
/// truncates toward zero.
///
/// Use it for every Java `(int)` cast: Dart's `toInt()` throws on NaN and
/// the infinities, and `round()`, `floor()` and `ceil()` are not the cast.
/// Java's `(int) Math.ceil(x)` is `jint(x.ceilToDouble())`.
@pragma('vm:prefer-inline')
int jint(double x) {
  if (x.isNaN) {
    return 0;
  }
  if (x >= 2147483647.0) {
    return 2147483647;
  }
  if (x <= -2147483648.0) {
    return -2147483648;
  }
  return x.truncate();
}

/// Java's `a % b` on two floats (JLS 15.17.3): the remainder of the
/// truncating division, with the sign of the dividend, computed exactly
/// (C's `fmod`). NaN when either operand is NaN, [a] is infinite or [b] is
/// zero; [a] itself when [b] is infinite or [a] is zero.
///
/// Dart's `%` is not this: it is the Euclidean modulo, never negative.
/// Java's `(angle % 360)` is `jfrem(angle, 360)`.
@pragma('vm:prefer-inline')
double jfrem(double a, double b) {
  assert(
    isF32(a) && isF32(b),
    'jfrem($a, $b): Java takes the remainder of two floats, so each operand '
    'must already be binary32 (round it with f32, or convert an int with '
    'fi)',
  );
  // The remainder of two binary32 values is exact and is itself a binary32
  // value, so the f32 only normalizes the type of the result.
  return f32(a.remainder(b));
}

/// Java's `Math.toRadians(angdeg)` as JDK 9 and later compute it:
/// `angdeg * DEGREES_TO_RADIANS` in double, one rounding, with
/// `DEGREES_TO_RADIANS = 0.017453292519943295`. (JDK 8 computed
/// `angdeg / 180.0 * PI`, which can differ by one double ulp.)
///
/// The argument and the result are doubles, as in Java. A circle constraint
/// computes `(float) Math.toRadians(angle + 90)` from a float angle, which
/// is `f32(toRadians(fadd(angle, 90)))`.
@pragma('vm:prefer-inline')
double toRadians(double angdeg) => angdeg * 0.017453292519943295;

/// Java's `0.001f`, the epsilon of `ArrayLinkedVariables` and
/// `SolverVariableValues`: `f32(0.001)`, which is
/// 0.001000000047497451305389404296875, written out exactly so it can be a
/// constant.
const double kEps001 = 0.001000000047497451305389404296875;

/// Java's `0.0001f`, the epsilon of `PriorityGoalRow`: `f32(0.0001)`, which
/// is 0.0000999999974737875163555145263671875, written out exactly so it can
/// be a constant.
const double kEps0001 = 0.0000999999974737875163555145263671875;

/// Java's `Float.MAX_VALUE`, the largest finite binary32 value
/// ((2 - 2^-23) * 2^127), which `LinearSystem.optimize` and `enforceBFS`
/// start their minimum ratio from.
const double kFloatMax = 3.4028234663852886e38;

/// Java's `Float.parseFloat(s)`: the decimal (or hexadecimal) number in [s]
/// rounded directly to binary32, ties to even.
///
/// The string is rounded once from its exact value, never through a double,
/// which could round twice. Throws a [FormatException] wherever Java throws
/// `NumberFormatException`. The accepted grammar is Java's
/// (`Double.valueOf(String)`):
///
/// * leading and trailing characters up to U+0020 are dropped, as
///   `String.trim()` does (spaces and control characters, not U+00A0);
/// * an optional `+` or `-`, then `NaN`, `Infinity`, a decimal number or a
///   hexadecimal number;
/// * a decimal number is ASCII digits with at most one `.` and at least one
///   digit, then an optional exponent (`e` or `E`, an optional sign, at
///   least one digit), then an optional suffix `f`, `F`, `d` or `D`;
/// * a hexadecimal number is `0x` or `0X`, hex digits with at most one `.`
///   and at least one digit, a required binary exponent (`p` or `P`, an
///   optional sign, at least one decimal digit), then the optional suffix.
///
/// A ratio string such as `"16:9"` is not a number: split it first, as
/// `ConstraintWidget.setDimensionRatio(String)` does.
double parseFloat32(String s) {
  final value = _parseJavaFloat(s);
  if (value == null) {
    throw FormatException('For input string: "$s"', s);
  }
  return value;
}

/// [parseFloat32], returning null where Java throws
/// `NumberFormatException`.
double? tryParseFloat32(String s) => _parseJavaFloat(s);

/// Exact binary32 powers of ten, 10^0 to 10^10 (5^10 < 2^24).
const List<double> _pow10f = [
  1e0,
  1e1,
  1e2,
  1e3,
  1e4,
  1e5,
  1e6,
  1e7,
  1e8,
  1e9,
  1e10,
];

// Exponent digits beyond this magnitude saturate. Any exponent this large
// makes the value infinite or zero for every string that fits in memory.
const int _expCap = 1000000000;

// Java keeps 200 significant digits and replaces the rest with one sticky
// digit (FloatingDecimal.SINGLE_MAX_NDIGITS). Any binary32 midpoint has
// fewer significant digits than that, so the rounding is unchanged.
const int _maxDigits = 200;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isHexDigit(int c) =>
    _isDigit(c) || (c >= 0x61 && c <= 0x66) || (c >= 0x41 && c <= 0x46);

double? _parseJavaFloat(String s) {
  // String.trim(): drop the code units up to U+0020 at both ends.
  var start = 0;
  var end = s.length;
  while (start < end && s.codeUnitAt(start) <= 0x20) {
    start++;
  }
  while (end > start && s.codeUnitAt(end - 1) <= 0x20) {
    end--;
  }
  if (start == end) {
    return null;
  }
  var i = start;
  var negative = false;
  final first = s.codeUnitAt(i);
  if (first == 0x2D) {
    negative = true;
    i++;
  } else if (first == 0x2B) {
    i++;
  }
  if (i == end) {
    return null;
  }
  final c = s.codeUnitAt(i);
  if (c == 0x4E) {
    // 'N': exactly "NaN" must follow the sign.
    return end - i == 3 && s.startsWith('NaN', i) ? double.nan : null;
  }
  if (c == 0x49) {
    // 'I': exactly "Infinity" must follow the sign.
    if (end - i == 8 && s.startsWith('Infinity', i)) {
      return negative ? double.negativeInfinity : double.infinity;
    }
    return null;
  }
  if (c == 0x30 && i + 1 < end) {
    final x = s.codeUnitAt(i + 1);
    if (x == 0x78 || x == 0x58) {
      return _parseHex(s, i + 2, end, negative);
    }
  }
  return _parseDecimal(s, i, end, negative);
}

/// The suffix rule shared by both forms: at most one of `f F d D`, last.
bool _validTail(String s, int pos, int end) {
  if (pos == end) {
    return true;
  }
  if (pos != end - 1) {
    return false;
  }
  final c = s.codeUnitAt(pos);
  return c == 0x66 || c == 0x46 || c == 0x64 || c == 0x44;
}

double _signed(int bits, bool negative) =>
    f32FromBits(negative ? bits | 0x80000000 : bits);

double? _parseDecimal(String s, int i, int end, bool negative) {
  var pos = i;
  var sawDigit = false;
  var dot = -1;
  var firstNonZero = -1;
  var lastNonZero = -1;
  while (pos < end) {
    final c = s.codeUnitAt(pos);
    if (_isDigit(c)) {
      sawDigit = true;
      if (c != 0x30) {
        if (firstNonZero < 0) {
          firstNonZero = pos;
        }
        lastNonZero = pos;
      }
    } else if (c == 0x2E) {
      if (dot >= 0) {
        return null; // A second point.
      }
      dot = pos;
    } else {
      break;
    }
    pos++;
  }
  if (!sawDigit) {
    return null;
  }
  final intEnd = dot >= 0 ? dot : pos;
  var exponent = 0;
  if (pos < end) {
    final c = s.codeUnitAt(pos);
    if (c == 0x65 || c == 0x45) {
      pos++;
      if (pos == end) {
        return null; // Java reads past the end here and fails.
      }
      var expNegative = false;
      final sign = s.codeUnitAt(pos);
      if (sign == 0x2D) {
        expNegative = true;
        pos++;
      } else if (sign == 0x2B) {
        pos++;
      }
      final expStart = pos;
      while (pos < end && _isDigit(s.codeUnitAt(pos))) {
        exponent = exponent * 10 + (s.codeUnitAt(pos) - 0x30);
        if (exponent > _expCap) {
          exponent = _expCap;
        }
        pos++;
      }
      if (pos == expStart) {
        return null; // An exponent without digits.
      }
      if (expNegative) {
        exponent = -exponent;
      }
    }
  }
  if (!_validTail(s, pos, end)) {
    return null;
  }
  if (firstNonZero < 0) {
    return negative ? -0.0 : 0.0;
  }

  // The significant digits, from the first nonzero digit to the last.
  final digits = <int>[];
  for (var p = firstNonZero; p <= lastNonZero; p++) {
    final c = s.codeUnitAt(p);
    if (c != 0x2E) {
      digits.add(c);
    }
  }
  // The place value of the last nonzero digit is 10^place.
  final place = lastNonZero < intEnd
      ? intEnd - lastNonZero - 1
      : -(lastNonZero - dot);
  var nDigits = digits.length;
  var e10 = exponent + place;
  if (nDigits > _maxDigits) {
    // Keep 200 digits and one sticky 1 in the 201st place, as Java does.
    e10 += nDigits - (_maxDigits + 1);
    digits.length = _maxDigits + 1;
    digits[_maxDigits] = 0x31;
    nDigits = _maxDigits + 1;
  }
  // The value is digits * 10^e10, between 10^(nDigits - 1 + e10) and
  // 10^(nDigits + e10).
  if (nDigits - 1 + e10 >= 39) {
    return negative ? double.negativeInfinity : double.infinity; // >= 1e39.
  }
  if (nDigits + e10 <= -46) {
    return negative ? -0.0 : 0.0; // Below 1e-46, under 2^-150.
  }
  if (nDigits <= 7 && e10 >= -10 && e10 <= 10) {
    // Exact binary32 operands, so one correctly rounded operation.
    var m = 0;
    for (final c in digits) {
      m = m * 10 + (c - 0x30);
    }
    final magnitude = e10 >= 0
        ? fmul(m.toDouble(), _pow10f[e10])
        : fdiv(m.toDouble(), _pow10f[-e10]);
    return negative ? -magnitude : magnitude;
  }
  final mantissa = BigInt.parse(String.fromCharCodes(digits));
  final five = BigInt.from(5);
  // digits * 10^e10 = digits * 5^e10 * 2^e10.
  final bits = e10 >= 0
      ? _roundToFloatBits(mantissa * five.pow(e10), BigInt.one, e10)
      : _roundToFloatBits(mantissa, five.pow(-e10), e10);
  return _signed(bits, negative);
}

double? _parseHex(String s, int i, int end, bool negative) {
  // Java's pattern, after the sign and 0x:
  // ((hex+)\.?|(hex*)\.(hex+))[pP][-+]?(digit+)[fFdD]?
  var pos = i;
  final digits = StringBuffer();
  var fractionDigits = 0;
  var dot = false;
  while (pos < end) {
    final c = s.codeUnitAt(pos);
    if (_isHexDigit(c)) {
      digits.writeCharCode(c);
      if (dot) {
        fractionDigits++;
      }
    } else if (c == 0x2E && !dot) {
      dot = true;
    } else {
      break;
    }
    pos++;
  }
  if (digits.isEmpty) {
    return null;
  }
  if (pos == end) {
    return null; // The binary exponent is required.
  }
  final p = s.codeUnitAt(pos);
  if (p != 0x70 && p != 0x50) {
    return null;
  }
  pos++;
  var expNegative = false;
  if (pos < end) {
    final sign = s.codeUnitAt(pos);
    if (sign == 0x2D) {
      expNegative = true;
      pos++;
    } else if (sign == 0x2B) {
      pos++;
    }
  }
  final expStart = pos;
  var exponent = 0;
  var overflow = false;
  while (pos < end && _isDigit(s.codeUnitAt(pos))) {
    exponent = exponent * 10 + (s.codeUnitAt(pos) - 0x30);
    if (exponent > 2147483647) {
      overflow = true; // Integer.parseInt fails: Java saturates below.
      exponent = 2147483647;
    }
    pos++;
  }
  if (pos == expStart || !_validTail(s, pos, end)) {
    return null;
  }
  final significand = BigInt.parse(digits.toString(), radix: 16);
  if (significand == BigInt.zero) {
    return negative ? -0.0 : 0.0;
  }
  if (overflow) {
    // Java: a nonzero significand with an exponent beyond the int range is
    // infinite or zero by the exponent's sign.
    if (expNegative) {
      return negative ? -0.0 : 0.0;
    }
    return negative ? double.negativeInfinity : double.infinity;
  }
  final e2 = (expNegative ? -exponent : exponent) - 4 * fractionDigits;
  return _signed(_roundToFloatBits(significand, BigInt.one, e2), negative);
}

/// The raw bits of the binary32 value nearest to `n / d * 2^e2` (ties to
/// even), for positive integers [n] and [d]: 0x7f800000 when it overflows,
/// 0 when it underflows.
int _roundToFloatBits(BigInt n, BigInt d, int e2) {
  assert(
    n > BigInt.zero && d > BigInt.zero,
    'only positive magnitudes reach the rounding; the parsers return signed '
    'zeros before calling it',
  );
  // k = floor(log2(n / d)).
  var k = n.bitLength - d.bitLength;
  if (k >= 0 ? n < (d << k) : (n << -k) < d) {
    k--;
  }
  final exponent = k + e2; // 2^exponent <= value < 2^(exponent + 1).
  if (exponent >= 128) {
    return 0x7f800000;
  }
  if (exponent < -150) {
    return 0;
  }
  // The weight of the last significand bit: 24 bits for a normal value,
  // fixed at 2^-149 for a subnormal one.
  var ulp = exponent - 23;
  if (ulp < -149) {
    ulp = -149;
  }
  final shift = e2 - ulp;
  final numerator = shift >= 0 ? n << shift : n;
  final denominator = shift >= 0 ? d : d << -shift;
  var q = numerator ~/ denominator;
  final twiceRemainder = (numerator - q * denominator) << 1;
  final half = twiceRemainder.compareTo(denominator);
  if (half > 0 || (half == 0 && q.isOdd)) {
    q += BigInt.one;
  }
  var m = q.toInt(); // At most 2^24.
  if (m == 1 << 24) {
    m = 1 << 23;
    ulp++;
  }
  if (m < 1 << 23) {
    return m; // Subnormal (ulp is 2^-149), or zero.
  }
  final biased = ulp + 23 + 127;
  if (biased >= 255) {
    return 0x7f800000;
  }
  return (biased << 23) | (m - (1 << 23));
}
