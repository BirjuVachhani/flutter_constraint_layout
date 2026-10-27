// Copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0
//
// Not upstream. The solver's Java float semantics: binary32 storage, one
// rounding per Java float operation, Java's float epsilons, exact goal
// comparisons (with the tie mode of containers holding a GridCore), the
// readback (int) (v + 0.5f), the synonym-scan skip, and the solver trace.
//
// Every expected value is Java's, from upstream's core at the pin:
// - the row bits and the readback come from RowBitsProbe
//   (tool/parity/java/probes/RowBitsProbe.java), compiled against it, which
//   calls ArrayRow.createRow* and pivot, and
//   LinearSystem.getObjectVariableValue;
// - the layouts and the trace come from VOpDriver (the parity oracle) at
//   OPTIMIZATION_NONE, upstream's solver alone, which is what layout() runs
//   at that level. The layouts are ones where the port's former double
//   solver was a pixel off.

import 'package:constraint_engine/constraint_engine.dart';
import 'package:constraint_engine/src/debug/solver_trace.dart';
import 'package:constraint_engine/src/jfloat.dart';
import 'package:test/test.dart';

/// The binary32 bits of [x], as Java's Float.floatToRawIntBits.
int bits(double x) => f32Bits(x);

/// A missing variable, for a null check that fails at run time.
SolverVariable? _missing() => null;

/// A [width] x [height] container at OPTIMIZATION_NONE: its layout() is
/// upstream's solver alone.
ConstraintWidgetContainer _levelZero(int width, int height) =>
    ConstraintWidgetContainer.rect(0, 0, width, height)
      ..setOptimizationLevel(Optimizer.OPTIMIZATION_NONE);

void main() {
  group('row construction in binary32 (Java bits)', () {
    late LinearSystem system;
    late SolverVariable a, b, c, d;

    setUp(() {
      system = LinearSystem();
      a = system.createSlackVariable();
      b = system.createSlackVariable();
      c = system.createSlackVariable();
      d = system.createSlackVariable();
    });

    /// The row's constant and the coefficients of [vs], as bits.
    List<int> rowBits(ArrayRow row, List<SolverVariable> vs) => [
      bits(row.mConstantValue),
      for (final v in vs) bits(row.variables.get(v)),
    ];

    test('createRowCentering with a bias that is not a binary32 decimal', () {
      // (A - B - 10)(1 - 0.3f) = (C - D - 20) 0.3f: the coefficients are
      // fsub(1, 0.3f) and 0.3f, the constant -10 * 0.7f + 20 * 0.3f in
      // float. The bias is passed as the double 0.3; the row uses 0.3f.
      final row = system.createRow().createRowCentering(
        a,
        b,
        10,
        0.3,
        c,
        d,
        20,
      );
      expect(rowBits(row, [a, b, c, d]), [
        0xbf800000, // -1.0
        0x3f333333, // 0.7f (fsub(1, 0.3f))
        0xbf333333,
        0xbe99999a, // -0.3f
        0x3e99999a,
      ]);
    });

    test('createRowCentering drops margins that are not positive', () {
      final row = system.createRow().createRowCentering(a, b, -5, 0.7, c, d, 0);
      expect(rowBits(row, [a, b, c, d]), [
        0x00000000,
        0x3e99999a, // fsub(1, 0.7f)
        0xbe99999a,
        0xbf333333,
        0x3f333333,
      ]);
    });

    test('createRowCentering keeps Java float noise in its constant', () {
      // -7 * 0.55f + 3 * 0.45f is -2.5000002 in float, not -2.5.
      final row = system.createRow().createRowCentering(a, b, 7, 0.45, c, d, 3);
      expect(rowBits(row, [a, b, c, d]), [
        0xc0200001,
        0x3f0ccccd,
        0xbf0ccccd,
        0xbee66666,
        0x3ee66666,
      ]);
    });

    test('createRowEqualMatchDimensions divides the weights in float', () {
      // w = (1 / 6) / (3 / 6) in float is 0x3eaaaaab.
      var row = system.createRow().createRowEqualMatchDimensions(
        1,
        6,
        3,
        a,
        b,
        c,
        d,
      );
      expect(rowBits(row, [a, b, c, d]), [
        0x00000000,
        0x3f800000,
        0xbf800000,
        0xbeaaaaab,
        0x3eaaaaab,
      ]);
      row = system.createRow().createRowEqualMatchDimensions(
        0.3,
        1.1,
        0.7,
        a,
        b,
        c,
        d,
      );
      expect(rowBits(row, [a, b, c, d]), [
        0x00000000,
        0x3f800000,
        0xbf800000,
        0xbedb6db8,
        0x3edb6db8,
      ]);
    });

    test('createRowEqualDimension sums the int margins first', () {
      // ((-8 - 8) + w * 5) + w * 7 with w = 0x3eaaaaab is -12.0 in float.
      final row = system.createRow().createRowEqualDimension(
        1,
        6,
        3,
        a,
        8,
        b,
        8,
        c,
        5,
        d,
        7,
      );
      expect(rowBits(row, [a, b, c, d]), [
        0xc1400000,
        0x3f800000,
        0xbf800000,
        0xbeaaaaab,
        0x3eaaaaab,
      ]);
    });

    test('ratio and percent rows use the binary32 value', () {
      final ratio = system.createRow().createRowDimensionRatio(
        a,
        b,
        c,
        d,
        0.29,
      );
      expect(rowBits(ratio, [a, b, c, d]), [
        0x00000000,
        0xbf800000,
        0x3f800000,
        0x3e947ae1,
        0xbe947ae1,
      ]);
      final percent = LinearSystem.createRowDimensionPercent(
        system,
        a,
        c,
        0.33,
      );
      expect(rowBits(percent, [a, c]), [0x00000000, 0xbf800000, 0x3ea8f5c3]);
    });

    test('pivot divides every coefficient in float', () {
      final row = system.createRow().createRowCentering(
        a,
        b,
        10,
        0.3,
        c,
        d,
        20,
      );
      row.pivot(c);
      expect(row.mVariable, same(c));
      expect(rowBits(row, [a, b, c, d]), [
        0xc0555555,
        0x40155555,
        0xc0155555,
        0x00000000, // c left the row: it is the subject now
        0x3f800000,
      ]);
    });
  });

  group('getObjectVariableValue is (int) (computedValue + 0.5f)', () {
    test('Java values', () {
      final widget = ConstraintWidget();
      final left = widget.getAnchor(ConstraintAnchorType.left)!;
      final system = LinearSystem();
      final variable = system.createObjectVariable(left)!;
      // computedValue bits -> Java's int.
      const cases = <int, int>{
        0x41480000: 13, // 12.5: half up
        0x3effffff: 1, // the float below 0.5: 0.49999997f + 0.5f is 1.0f
        0xc0e00000: -6, // -7: a negative integer reads back one higher
        0xc0d00000: -6, // -6.5
        0xc0d33333: -6, // -6.6
        0xbf19999a: 0, // -0.6
        0x4affffff: 8388608, // 8388607.5f + 0.5f
        0x501502f9: 2147483647, // 1e10f saturates
        0xd01502f9: -2147483648, // -1e10f saturates
        0x7fc00000: 0, // NaN
      };
      for (final MapEntry(key: b, value: expected) in cases.entries) {
        variable.computedValue = f32FromBits(b);
        expect(
          system.getObjectVariableValue(left),
          expected,
          reason: 'computedValue 0x${b.toRadixString(16)}',
        );
      }
    });
  });

  group('layouts the solver resolves as Java does (J0)', () {
    /// A [width] x 20 widget centered in a [parentWidth] x 100 container
    /// with horizontal [bias], on the solver alone; returns its left.
    int centeredLeft(int parentWidth, int width, double bias) {
      final root = _levelZero(parentWidth, 100);
      final a = ConstraintWidget.size(width, 20);
      root.add(a);
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      a.setHorizontalBiasPercent(bias);
      root.layout();
      expect(a.getWidth(), width, reason: 'a fixed width stays fixed');
      return a.getLeft();
    }

    test('a centered widget with an odd bias', () {
      // The double solver gave 55 (and a width of 23), 129, 167 and 77.
      expect(centeredLeft(207, 22, 0.3), 56);
      expect(centeredLeft(207, 22, 0.7), 130);
      expect(centeredLeft(207, 22, 0.9), 166);
      expect(centeredLeft(207, 37, 0.45), 76);
    });

    test('a weighted spread chain', () {
      // Weights 1, 2, 3 over 203 px: the double solver gave b 67 px.
      final root = _levelZero(203, 100);
      final widgets = [
        for (var i = 0; i < 3; i++)
          ConstraintWidget.size(0, 20)
            ..setHorizontalDimensionBehaviour(
              DimensionBehaviour.matchConstraint,
            )
            ..setHorizontalWeight(i + 1.0),
      ];
      widgets.forEach(root.add);
      final [a, b, c] = widgets;
      a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
      a.connect(ConstraintAnchorType.right, b, ConstraintAnchorType.left);
      b.connect(ConstraintAnchorType.left, a, ConstraintAnchorType.right);
      b.connect(ConstraintAnchorType.right, c, ConstraintAnchorType.left);
      c.connect(ConstraintAnchorType.left, b, ConstraintAnchorType.right);
      c.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
      for (final w in widgets) {
        w.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
      }
      root.layout();
      expect([a.getLeft(), a.getWidth()], [0, 34]);
      expect([b.getLeft(), b.getWidth()], [34, 68]);
      expect([c.getLeft(), c.getWidth()], [102, 101]);
    });
  });

  group('PriorityGoalRow', () {
    late LinearSystem system;
    late PriorityGoalRow goal;
    late SolverVariable first, second;

    setUp(() {
      system = LinearSystem();
      goal = system.getGoal() as PriorityGoalRow;
      first = system.createErrorVariable(SolverVariable.STRENGTH_HIGHEST, null);
      second = system.createErrorVariable(
        SolverVariable.STRENGTH_HIGHEST,
        null,
      );
      // Both negative at the same strength, 0.00005 apart.
      first.mGoalStrengthVector[SolverVariable.STRENGTH_HIGHEST] = -1;
      second.mGoalStrengthVector[SolverVariable.STRENGTH_HIGHEST] = f32(
        -1.00005,
      );
    });

    List<bool> avoid() => List.filled(system.mNumColumns + 1, false);

    test('compares goal strengths exactly, as upstream', () {
      expect(goal.getPivotCandidate(system, avoid()), same(second));
    });

    test('a GridCore container keeps the tie tolerance', () {
      system.goalTieEpsilon = true;
      expect(goal.getPivotCandidate(system, avoid()), same(first));
      system.reset();
      expect(system.goalTieEpsilon, isFalse, reason: 'reset clears it');
    });

    test('the container switches the tie mode on for a GridCore', () {
      final root = ConstraintWidgetContainer.rect(0, 0, 100, 100);
      final system = LinearSystem();
      root.addChildrenToSolver(system);
      expect(system.goalTieEpsilon, isFalse);
      root.add(GridCore());
      root.addChildrenToSolver(system);
      expect(system.goalTieEpsilon, isTrue);
    });

    test('keeps a goal strength of exactly 0.0001f (Java epsilon)', () {
      // |0.0001f| < 0.0001f is false, so Java keeps it; the double 0.0001
      // would have dropped it.
      final x = system.createSlackVariable();
      goal.mAccessor.init(x);
      expect(goal.mAccessor.addToGoal(first, -kEps0001), isTrue);
      expect(
        x.mGoalStrengthVector[SolverVariable.STRENGTH_HIGHEST],
        kEps0001,
      );
      goal.mAccessor.init(x);
      // A value just below the epsilon is dropped.
      final below = f32FromBits(f32Bits(kEps0001) - 1);
      expect(goal.mAccessor.addToGoal(first, -below), isTrue);
      expect(x.mGoalStrengthVector[SolverVariable.STRENGTH_HIGHEST], 0);
    });

    test('reset clears a goal vector that was written', () {
      expect(first.mGoalStrengthVectorDirty, isTrue);
      system.reset();
      expect(first.mGoalStrengthVector, everyElement(0));
      expect(first.mGoalStrengthVectorDirty, isFalse);
    });
  });

  group('synonym scan of addEqualityConstant', () {
    test('runs only after setSynonym, and gives the same values', () {
      final system = LinearSystem();
      final a = system.getVariable('a', SolverVariableType.unrestricted);
      final b = system.getVariable('b', SolverVariableType.unrestricted);
      final c = system.getVariable('c', SolverVariableType.unrestricted);
      system.addEqualityConstant(c, 4);
      expect(system.mSynonymCount, 0);
      expect(c.computedValue, 4);
      b.setSynonym(system, a, 3.25);
      expect(system.mSynonymCount, 1);
      system.addEqualityConstant(a, 10);
      expect(a.computedValue, 10);
      expect(b.isFinalValue, isTrue);
      expect(b.computedValue, 13.25, reason: 'the synonym follows a');
      system.reset();
      expect(system.mSynonymCount, 0);
    });
  });

  group('solver trace formatting', () {
    test('floats print as binary32 bits', () {
      expect(SolverTrace.f(1), '3f800000');
      expect(SolverTrace.f(-0.0), '80000000');
      expect(SolverTrace.f(f32(0.3)), '3e99999a');
      expect(SolverTrace.f(double.nan), '7fc00000');
    });

    test('rows print in list order', () {
      final system = LinearSystem();
      final v1 = system.createSlackVariable();
      final v2 = system.createSlackVariable();
      final row = system.createRow()
        ..variables.put(v2, 2)
        ..variables.put(v1, -1);
      expect(SolverTrace.row(row), '2 1:bf800000 2:40000000');
    });

    test('anchors, nulls and exception classes', () {
      final w = ConstraintWidget()..setDebugName('box');
      expect(
        SolverTrace.anchorName(w.getAnchor(ConstraintAnchorType.baseline)!),
        'box.S',
      );
      expect(
        SolverTrace.anchorName(
          ConstraintWidget().getAnchor(ConstraintAnchorType.centerX)!,
        ),
        '?.CX',
      );
      expect(SolverTrace.vid(null), '-');
      Object? nullCheck;
      try {
        _missing()!.id;
      } catch (e) {
        nullCheck = e;
      }
      expect(
        SolverTrace.javaExceptionClass(nullCheck!),
        'java.lang.NullPointerException',
      );
      expect(
        SolverTrace.javaExceptionClass(RangeError.index(-1, const [])),
        'java.lang.ArrayIndexOutOfBoundsException',
      );
      expect(
        SolverTrace.javaExceptionClass(StateError('x')),
        'dart.StateError',
      );
    });

    test('events go to the sink, and nowhere without one', () {
      // Created before the sink is installed: with -Dcl.trace=true the
      // engine itself reports the new variable.
      final system = LinearSystem();
      final v = system.createSlackVariable();
      final lines = <String>[];
      SolverTrace.sink = lines.add;
      addTearDown(() => SolverTrace.sink = null);
      SolverTrace.equality(v, 7);
      SolverTrace.finalValue(v, 1.5);
      SolverTrace.readback(null, 0);
      SolverTrace.goalVector(v);
      SolverTrace.sink = null;
      SolverTrace.line('RS');
      expect(lines, [
        'Q 1 7',
        'FV 1 3fc00000',
        'O - - 0',
        'G 1 00000000 00000000 00000000 00000000 00000000 00000000 '
            '00000000 00000000 00000000',
      ]);
    });
  });

  group(
    'solver trace end to end (compile with -Dcl.trace=true)',
    skip: kSolverTrace
        ? null
        : 'the trace is compiled out; run `dart -Dcl.trace=true test '
              '-c source test/solver_float_test.dart` (the define reaches '
              'only the source compiler)',
    () {
      test('a centered widget, bias 0.3: the events TraceJava writes', () {
        final lines = <String>[];
        SolverTrace.sink = lines.add;
        addTearDown(() => SolverTrace.sink = null);
        final root = _levelZero(207, 100)..setDebugName('root');
        final a = ConstraintWidget.size(22, 20)..setDebugName('a');
        root.add(a);
        a.connect(ConstraintAnchorType.left, root, ConstraintAnchorType.left);
        a.connect(ConstraintAnchorType.right, root, ConstraintAnchorType.right);
        a.connect(ConstraintAnchorType.top, root, ConstraintAnchorType.top);
        a.setHorizontalBiasPercent(0.3);
        root.layout();
        // VOpDriver -Dtrace at level 0 on the same layout (syn-bias:266),
        // without its T and E lines.
        expect(lines, [
          'PS 0',
          'RS',
          'V 1 U 0 root.L',
          'V 2 U 0 root.T',
          'V 3 U 0 root.R',
          'V 4 U 0 root.B',
          'V 5 U 0 a.L',
          'V 6 U 0 a.T',
          'V 7 U 0 a.R',
          'V 8 U 0 a.B',
          'V 9 U 0 root.S',
          'Q 1 0',
          'FV 1 00000000',
          'FV 3 434f0000',
          'Q 2 0',
          'FV 2 00000000',
          'FV 4 42c80000',
          'V 10 U 0 a.S',
          'A - 0 41b00000 2 5:3f800000 7:bf800000',
          'U 41b00000 2 5:3f800000 7:bf800000',
          'PI - 7 3f800000 41b00000 1 5:3f800000',
          'R 7 0 41b00000 1 5:3f800000',
          'AR 0 7 41b00000 1 5:3f800000',
          'A - 0 00000000 4 1:bf333333 3:be99999a 5:3f333333 7:3e99999a',
          'U c25e0000 1 5:3f800000',
          'PI - 5 3f800000 425e0000 0',
          'R 5 0 425e0000 0',
          'AF 5 425e0000',
          'FV 5 425e0000',
          'CP 0 7',
          'FV 7 429b0000',
          'FV 6 00000000',
          'FV 8 41a00000',
          'M 0 1',
          'MZ 0 11 1',
          'O 1 00000000 0',
          'O 2 00000000 0',
          'O 3 434f0000 207',
          'O 4 42c80000 100',
          'O 5 425e0000 56',
          'O 6 00000000 0',
          'O 7 429b0000 78',
          'O 8 41a00000 20',
        ]);
      });
    },
  );
}
