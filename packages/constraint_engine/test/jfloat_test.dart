// Copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0
//
// No upstream counterpart. Checks lib/src/jfloat.dart, the port's Java float
// semantics, against Java's own results.
//
// jfloat_vectors.json holds 2,000 vectors per primitive: inputs and the
// result the JVM computed for each (`(float) d`, `a + b`, `a - b`, `a * b`,
// `a / b` and `a % b` on floats, `(float)` of an int or a long, `(int)` of a
// float or a double, Math.toRadians, Float.parseFloat). They are a selection
// from the 100,000 per primitive that JFloatVectors.java generates: up to
// 1,000 evenly spaced over its edge cases (subnormals, signed zeros, ties,
// overflow, NaN, infinities, ints and longs beyond 2^24 and 2^53, decimal
// strings a hair off a binary32 midpoint, ratio-string forms, Java's
// whitespace and suffix rules) and the rest evenly spaced over its random
// vectors. The full 1,000,000 vectors are checked by check_vectors.dart, next
// to the generator.
//
// To regenerate (JDK 21 or later, which computes Math.toRadians as JDK 9+
// does; the file's "java" field records the JVM used):
//
//   javac -d <classes> JFloatVectors.java
//   java -cp <classes> JFloatVectors <outDir> 100000 20261025 2000
//   cp <outDir>/jfloat_vectors.json packages/constraint_engine/test/
//
// The generator and the full check live in the parity tooling, in
// tool/parity/jfloat/ (JFloatVectors.java and check_vectors.dart, with the
// commands in tool/parity/README.md). The same seed gives the same file.
//
// Encodings: a float is the 8 hex digits of its raw bits, a double the 16,
// an fi input a decimal string (it can be a long), a jint result a number, a
// parse result null where Java throws NumberFormatException. A result
// matches when its binary32 bits are the expected bits; an expected NaN
// matches any NaN, since Java does not specify NaN payloads.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:constraint_engine/src/jfloat.dart';
import 'package:test/test.dart';

const _primitives = [
  'f32',
  'fadd',
  'fsub',
  'fmul',
  'fdiv',
  'fi',
  'jint',
  'jfrem',
  'toRadians',
  'parseFloat32',
];

File _vectorFile() {
  for (final path in const [
    'test/jfloat_vectors.json',
    'packages/constraint_engine/test/jfloat_vectors.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return file;
    }
  }
  throw StateError(
    'jfloat_vectors.json not found; run the test from packages/constraint_engine',
  );
}

double _dFromHex(String h) {
  final b = ByteData(8)
    ..setUint32(0, int.parse(h.substring(0, 8), radix: 16))
    ..setUint32(4, int.parse(h.substring(8), radix: 16));
  return b.getFloat64(0);
}

String _dHex(double v) {
  final b = ByteData(8)..setFloat64(0, v);
  return b.getUint32(0).toRadixString(16).padLeft(8, '0') +
      b.getUint32(4).toRadixString(16).padLeft(8, '0');
}

double _fFromHex(String h) => f32FromBits(int.parse(h, radix: 16));

/// 2^[e] exactly, for -1022 <= e <= 1023 (Dart has no hex float literals).
double _p2(int e) =>
    (ByteData(8)..setUint64(0, (e + 1023) << 52)).getFloat64(0);

String _fHex(double v) => f32Bits(v).toRadixString(16).padLeft(8, '0');

bool _sameFloat(double actual, String expected) {
  if (_fFromHex(expected).isNaN) {
    return actual.isNaN;
  }
  return isF32(actual) && _fHex(actual) == expected;
}

bool _sameDouble(double actual, String expected) {
  if (_dFromHex(expected).isNaN) {
    return actual.isNaN;
  }
  return _dHex(actual) == expected;
}

/// Null when the vector [v] of [primitive] matches, else what went wrong.
String? _check(String primitive, List<Object?> v) {
  switch (primitive) {
    case 'f32':
      final r = f32(_dFromHex(v[0] as String));
      return _sameFloat(r, v[1] as String) ? null : 'got ${_fHex(r)}';
    case 'fadd' || 'fsub' || 'fmul' || 'fdiv' || 'jfrem':
      final a = _fFromHex(v[0] as String);
      final b = _fFromHex(v[1] as String);
      final r = switch (primitive) {
        'fadd' => fadd(a, b),
        'fsub' => fsub(a, b),
        'fmul' => fmul(a, b),
        'fdiv' => fdiv(a, b),
        _ => jfrem(a, b),
      };
      return _sameFloat(r, v[2] as String) ? null : 'got ${_fHex(r)}';
    case 'fi':
      final r = fi(int.parse(v[0] as String));
      return _sameFloat(r, v[1] as String) ? null : 'got ${_fHex(r)}';
    case 'jint':
      final r = jint(_dFromHex(v[0] as String));
      return r == v[1] ? null : 'got $r';
    case 'toRadians':
      final r = toRadians(_dFromHex(v[0] as String));
      return _sameDouble(r, v[1] as String) ? null : 'got ${_dHex(r)}';
    case 'parseFloat32':
      final s = v[0] as String;
      final expected = v[1] as String?;
      final r = tryParseFloat32(s);
      if (expected == null) {
        if (r != null) {
          return 'got ${_fHex(r)} where Java throws';
        }
        try {
          parseFloat32(s);
          return 'parseFloat32 returned where Java throws';
        } on FormatException {
          return null;
        }
      }
      if (r == null) {
        return 'got null where Java returns $expected';
      }
      if (!_sameFloat(parseFloat32(s), expected)) {
        return 'parseFloat32 and tryParseFloat32 disagree';
      }
      return _sameFloat(r, expected) ? null : 'got ${_fHex(r)}';
  }
  throw ArgumentError.value(primitive, 'primitive', 'not a jfloat primitive');
}

void main() {
  group('Java vectors', () {
    final data =
        jsonDecode(_vectorFile().readAsStringSync()) as Map<String, Object?>;

    test('the file holds 2,000 vectors for every primitive', () {
      expect(data['perPrimitive'], 2000);
      for (final p in _primitives) {
        expect((data[p] as List).length, 2000, reason: p);
      }
    });

    for (final p in _primitives) {
      test('$p matches Java on every vector', () {
        final mismatches = <String>[];
        for (final v in (data[p] as List).cast<List<Object?>>()) {
          final why = _check(p, v);
          if (why != null) {
            mismatches.add('${jsonEncode(v)}: $why');
          }
        }
        expect(mismatches, isEmpty, reason: mismatches.take(10).join('\n'));
      });
    }
  });

  group('f32 and the binary32 constants', () {
    test('rounds to nearest, ties to even, with overflow and underflow', () {
      expect(f32Bits(f32(0.1)), 0x3dcccccd);
      // 1 + 2^-24 is halfway between 1 and nextUp(1): ties to the even 1.
      expect(f32(1 + _p2(-24)), 1.0);
      expect(f32(1 + 3 * _p2(-24)), 1 + _p2(-22));
      // Float.MAX_VALUE plus half its ulp rounds to infinity.
      expect(f32(kFloatMax + _p2(103)), double.infinity);
      expect(f32(kFloatMax + _p2(102)), kFloatMax);
      expect(f32(2 * _p2(-150)), _p2(-149));
      expect(f32(_p2(-150)), 0.0); // A tie with zero, the even neighbour.
      expect(f32(3 * _p2(-150)), 2 * _p2(-149));
      expect(f32(double.nan).isNaN, isTrue);
    });

    test("kEps001, kEps0001 and kFloatMax are Java's 0.001f, 0.0001f and "
        'Float.MAX_VALUE', () {
      expect(kEps001, f32(0.001));
      expect(f32Bits(kEps001), 0x3a83126f);
      expect(kEps0001, f32(0.0001));
      expect(f32Bits(kEps0001), 0x38d1b717);
      expect(f32Bits(kFloatMax), 0x7f7fffff);
      expect(isF32(kFloatMax), isTrue);
    });

    test('f32Bits and f32FromBits round-trip the raw bits', () {
      expect(f32FromBits(0xbf800000), -1.0);
      expect(f32Bits(-0.0), 0x80000000);
      expect(f32FromBits(-1082130432), -1.0); // A Java int's bits work too.
    });
  });

  group('Java expressions the port spells with jfloat', () {
    test('Direct centering: (int) (0.5f + 0.7f * 45) is 32', () {
      expect(jint(fadd(0.5, fmul(f32(0.7), fi(45)))), 32);
      expect((0.5 + 0.7 * 45).toInt(), 31); // In double: one pixel off.
    });

    test('ratio truncation: (int) (0.29f * 100) is 29, (int) (0.57f * 100) '
        'is 57', () {
      expect(jint(fmul(f32(0.29), fi(100))), 29);
      expect(jint(fmul(f32(0.57), fi(100))), 57);
      expect((0.29 * 100).toInt(), 28);
    });

    test('readback: (int) (computedValue + 0.5f)', () {
      // The float just below 0.5: the float sum rounds to 1.0f.
      expect(jint(fadd(f32(0.49999997), 0.5)), 1);
      expect(jint(fadd(12.5, 0.5)), 13);
      expect(jint(fadd(-7, 0.5)), -6); // A negative integer reads one higher.
      expect(jint(fadd(-6.5, 0.5)), -6);
      expect(jint(fadd(f32(-0.6), 0.5)), 0);
    });

    test('createRowCentering: 1f - bias rounds once from the stored float', () {
      final bias = f32(0.3);
      expect(f32Bits(fsub(1, bias)), 0x3f333333); // Java's 1f - 0.3f.
      expect(fsub(1, bias), isNot(1 - 0.3)); // The double difference.
    });
  });

  group('jint', () {
    test("is Java's (int): NaN to 0, saturation, truncation toward zero", () {
      expect(jint(double.nan), 0);
      expect(jint(double.infinity), 2147483647);
      expect(jint(double.negativeInfinity), -2147483648);
      expect(jint(3e9), 2147483647);
      expect(jint(-3e9), -2147483648);
      expect(jint(-2.5), -2);
      expect(jint(-0.4), 0);
      expect(jint(2147483647.5), 2147483647);
      expect(jint(-2147483648.5), -2147483648);
    });
  });

  group('fi', () {
    test('rounds an int to the nearest float, ties to even', () {
      expect(fi(16777217), 16777216.0);
      expect(fi(16777219), 16777220.0);
      expect(fi(2147483647), 2147483648.0);
      expect(fi(-2147483648), -2147483648.0);
    });

    test('rounds a wide integer once, never through a double', () {
      // 2^60 + 2^36 + 1 is just above a binary32 midpoint. Through a double
      // it first rounds to the midpoint, which then ties down to 2^60.
      const v = (1 << 60) + (1 << 36) + 1;
      expect(fi(v), _p2(60) + _p2(37));
      expect(f32(v.toDouble()), _p2(60));
    });
  });

  group('jfrem', () {
    test("is Java's float %: truncating, with the dividend's sign", () {
      expect(jfrem(450, 360), 90.0);
      expect(jfrem(-30, 360), -30.0);
      expect(jfrem(-720, 360), -0.0);
      expect(jfrem(-720, 360).isNegative, isTrue);
      expect(jfrem(1, 0).isNaN, isTrue);
      expect(jfrem(double.infinity, 360).isNaN, isTrue);
      expect(jfrem(5, double.infinity), 5.0);
      expect(-30 % 360, 330); // Dart's % is not Java's.
    });
  });

  group('toRadians', () {
    test('is JDK 9+ Math.toRadians, one double multiplication', () {
      expect(toRadians(90), 90 * 0.017453292519943295);
      expect(_dHex(toRadians(180)), '400921fb54442d18'); // Math.PI's bits.
      // A circle constraint's angle: (float) Math.toRadians(angle + 90).
      expect(f32Bits(f32(toRadians(fadd(45, 90)))), 0x4016cbe4);
    });
  });

  group('parseFloat32', () {
    test('parses the parts of a ratio string as Float.parseFloat does', () {
      expect(parseFloat32('16'), 16.0);
      expect(parseFloat32(' 9 '), 9.0);
      expect(parseFloat32('\t1.5f\n'), 1.5);
      expect(parseFloat32('2d'), 2.0);
      expect(parseFloat32('.5'), 0.5);
      expect(parseFloat32('5.'), 5.0);
      expect(parseFloat32('+16'), 16.0);
      expect(parseFloat32('-0').isNegative, isTrue);
      expect(parseFloat32('1e2'), 100.0);
      expect(parseFloat32('0x1.8p1'), 3.0);
      expect(parseFloat32('-Infinity'), double.negativeInfinity);
      expect(parseFloat32('NaN').isNaN, isTrue);
      expect(f32Bits(parseFloat32('1.7777778')), f32Bits(fdiv(16, 9)));
    });

    test('throws FormatException where Java throws NumberFormatException', () {
      for (final s in [
        '',
        ' ',
        'W',
        '16:9',
        '1,5',
        '1_0',
        '1..5',
        '1e',
        'e5',
        '.',
        '-',
        'nan',
        'Inf',
        'NaNf',
        '0x1',
        '0x1p',
        '1ff',
        ' 16',
        '16px',
      ]) {
        expect(() => parseFloat32(s), throwsFormatException, reason: s);
        expect(tryParseFloat32(s), isNull, reason: s);
      }
    });

    test('rounds the decimal once, never through a double', () {
      // Just below the midpoint 17316095 between the floats 17316094 and
      // 17316096. A double rounds it to the midpoint, which then ties to
      // the even 17316096; Java rounds the exact decimal down.
      const s = '17316094.999999999';
      expect(parseFloat32(s), 17316094.0);
      expect(f32(double.parse(s)), 17316096.0);
    });

    test('keeps 200 significant digits and a sticky one, as Java does', () {
      final exactTie = '1.000000059604644775390625${'0' * 300}';
      final aboveTie = '${exactTie}1';
      expect(parseFloat32(exactTie), 1.0); // 1 + 2^-24 ties to even.
      expect(parseFloat32(aboveTie), 1 + _p2(-23));
    });
  });

  group('operand checks', () {
    var assertsOn = false;
    assert(assertsOn = true, 'only records whether asserts run');

    test(
      'a float operation rejects an operand that is not binary32',
      () {
        expect(() => fadd(0.1, 1), throwsA(isA<AssertionError>()));
        expect(() => fmul(1, 1 / 3), throwsA(isA<AssertionError>()));
        expect(fadd(f32(0.1), 1), f32(f32(0.1) + 1));
      },
      skip: assertsOn ? false : 'asserts are off',
    );
  });
}
