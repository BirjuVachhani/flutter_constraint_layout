// check_vectors (Phase 1, p1-setup): checks the port's jfloat.dart against every vector
// JFloatVectors.java wrote (100,000 per primitive), and reports mismatches per primitive.
//
//   cd packages/constraint_engine
//   dart run tool/parity/jfloat/check_vectors.dart <outDir of JFloatVectors>
//
// Exit code 0 when every vector matches, 1 otherwise. A float result matches when its
// binary32 bits are the expected bits (signed zeros included) and it is a binary32 value;
// an expected NaN matches any NaN (Java does not specify NaN payloads).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:constraint_engine/src/jfloat.dart';

double dFromHex(String h) {
  final b = ByteData(8)
    ..setUint32(0, int.parse(h.substring(0, 8), radix: 16))
    ..setUint32(4, int.parse(h.substring(8), radix: 16));
  return b.getFloat64(0);
}

String dHex(double v) {
  final b = ByteData(8)..setFloat64(0, v);
  return b.getUint32(0).toRadixString(16).padLeft(8, '0') +
      b.getUint32(4).toRadixString(16).padLeft(8, '0');
}

double fFromHex(String h) => f32FromBits(int.parse(h, radix: 16));

String fHex(double v) => f32Bits(v).toRadixString(16).padLeft(8, '0');

bool sameFloat(double actual, String expected) {
  if (fFromHex(expected).isNaN) {
    return actual.isNaN;
  }
  return isF32(actual) && fHex(actual) == expected;
}

bool sameDouble(double actual, String expected) {
  if (dFromHex(expected).isNaN) {
    return actual.isNaN;
  }
  return dHex(actual) == expected;
}

/// Returns null when [v] matches, else a description of the mismatch.
String? check(String primitive, List<Object?> v) {
  switch (primitive) {
    case 'f32':
      final r = f32(dFromHex(v[0] as String));
      return sameFloat(r, v[1] as String) ? null : 'got ${fHex(r)}';
    case 'fadd' || 'fsub' || 'fmul' || 'fdiv' || 'jfrem':
      final a = fFromHex(v[0] as String);
      final b = fFromHex(v[1] as String);
      final r = switch (primitive) {
        'fadd' => fadd(a, b),
        'fsub' => fsub(a, b),
        'fmul' => fmul(a, b),
        'fdiv' => fdiv(a, b),
        _ => jfrem(a, b),
      };
      return sameFloat(r, v[2] as String) ? null : 'got ${fHex(r)}';
    case 'fi':
      final r = fi(int.parse(v[0] as String));
      return sameFloat(r, v[1] as String) ? null : 'got ${fHex(r)}';
    case 'jint':
      final r = jint(dFromHex(v[0] as String));
      return r == v[1] ? null : 'got $r';
    case 'toRadians':
      final r = toRadians(dFromHex(v[0] as String));
      return sameDouble(r, v[1] as String) ? null : 'got ${dHex(r)}';
    case 'parseFloat32':
      final s = v[0] as String;
      final expected = v[1] as String?;
      final r = tryParseFloat32(s);
      Object? thrown;
      try {
        parseFloat32(s);
      } on FormatException catch (e) {
        thrown = e;
      }
      if ((r == null) != (thrown != null)) {
        return 'parseFloat32 and tryParseFloat32 disagree';
      }
      if (expected == null) {
        return r == null ? null : 'got ${fHex(r)}, Java throws';
      }
      if (r == null) {
        return 'got FormatException';
      }
      return sameFloat(r, expected) ? null : 'got ${fHex(r)}';
  }
  throw ArgumentError('unknown primitive $primitive');
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: check_vectors.dart <outDir of JFloatVectors>');
    exit(2);
  }
  final dir = args[0];
  const primitives = [
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
  var total = 0;
  var bad = 0;
  for (final p in primitives) {
    final lines = File('$dir/$p.jsonl').readAsLinesSync();
    var mismatches = 0;
    final shown = <String>[];
    for (final line in lines) {
      final v = jsonDecode(line) as List<Object?>;
      final why = check(p, v);
      if (why != null) {
        mismatches++;
        if (shown.length < 12) {
          shown.add('  $line: $why');
        }
      }
    }
    total += lines.length;
    bad += mismatches;
    stdout.writeln('$p: ${lines.length} vectors, $mismatches mismatches');
    shown.forEach(stdout.writeln);
  }
  stdout.writeln('total: $total vectors, $bad mismatches');
  exitCode = bad == 0 ? 0 : 1;
}
