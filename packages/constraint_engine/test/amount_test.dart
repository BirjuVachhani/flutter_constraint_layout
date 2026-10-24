// Copyright (C) 2015 The Android Open Source Project
// Modifications copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0 AND BSD-3-Clause
//
// Ported from androidx.constraintlayout.core.AmountTest (upstream pinned in
// UPSTREAM.md).

import 'package:test/test.dart';

import 'support/amount.dart';

void main() {
  group('AmountTest', () {
    late Amount a1;
    late Amount a2;

    setUp(() {
      a1 = Amount(2, 3);
      a2 = Amount(3, 5);
    });

    test('testAdd', () {
      a1.add(a2);
      expect(a1.getNumerator(), 19);
      expect(a1.getDenominator(), 15);
    });

    test('testSubtract', () {
      a1.subtract(a2);
      expect(a1.getNumerator(), 1);
      expect(a1.getDenominator(), 15);
    });

    test('testMultiply', () {
      a1.multiply(a2);
      expect(a1.getNumerator(), 2);
      expect(a1.getDenominator(), 5);
    });

    test('testDivide', () {
      a1.divide(a2);
      expect(a1.getNumerator(), 10);
      expect(a1.getDenominator(), 9);
    });

    test('testSimplify', () {
      a1.set(20, 30);
      expect(a1.getNumerator(), 2);
      expect(a1.getDenominator(), 3);
      a1.set(77, 88);
      expect(a1.getNumerator(), 7);
      expect(a1.getDenominator(), 8);
    });

    test('testEquality', () {
      a2.set(a1.getNumerator(), a1.getDenominator());
      expect(a1 == a2, isTrue);
    });
  });
}
