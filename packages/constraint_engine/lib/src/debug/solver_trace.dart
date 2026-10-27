// Copyright (C) 2026 Birju Vachhani
// SPDX-License-Identifier: Apache-2.0
//
// No upstream counterpart. A debug-only trace of the solver's operations,
// event for event and field for field the trace a patched upstream core
// writes (the parity tooling's TraceJava), so that a Dart trace and a Java
// trace of the same layout are byte-identical when the port computes what
// Android computes, and the first line where they differ names the first
// operation where it does not.
//
// The engine calls these methods only under `if (kSolverTrace)`, a constant
// that is false unless the program is compiled with `-Dcl.trace=true`. In
// every other build the calls, and this class with them, are tree-shaken.
//
// Grammar: one event per line, ASCII, fields separated by one space. A float
// prints as the lowercase 8-digit hex of its binary32 bits (Java's
// Float.floatToRawIntBits); a variable prints as its id, or `-` for null.
//
// | Event | Line                                   | Where                     |
// |-------|----------------------------------------|---------------------------|
// | RS    | `RS`                                   | LinearSystem.reset entry  |
// | V     | `V <id> <U S X E N> <strength> <name>` | a variable gets a new id  |
// | Q     | `Q <v> <int>`                          | addEqualityConstant entry |
// | A     | `A <subject> <simple> <const> <row>`   | addConstraint entry       |
// | U     | `U <const> <row>`                      | after updateFromSystem    |
// | D     | `D E` or `D K`                         | the row is dropped        |
// | R     | `R <subject> <extra> <const> <row>`    | after chooseSubject       |
// | RX    | `RX <subject>`                         | the extra variable left   |
// | AR    | `AR <index> <subject> <const> <row>`   | addRow stores the row     |
// | AF    | `AF <subject> <const>`                 | addRow, a final value     |
// | CP    | `CP <index> <subject>`                 | addRow's compaction       |
// | M     | `M <pass> <iteration>`                 | before the root minimize  |
// | MZ    | `MZ <rows> <columns> <goalEmpty>`      | minimize entry            |
// | BF    | `BF <infeasible>`                      | enforceBFS, after its scan|
// | B     | `B <row> <column>`                     | enforceBFS pivot          |
// | C     | `C <G or T> <tries> <candidate>`       | optimize candidate        |
// | P     | `P <row> <entering> <G or T>`          | optimize pivot row        |
// | NP    | `NP <G or T>`                          | optimize, no pivot row    |
// | OE    | `OE <G or T> <tries> <reason>`         | optimize returns          |
// | PI    | `PI <leaving> <entering> <amount> <const> <row>` | ArrayRow.pivot  |
// | G     | `G <v> <f0> ... <f8>`                  | a goal vector changed     |
// | GR    | `GR <v>`                               | a variable left the goal  |
// | FV    | `FV <v> <value>`                       | setFinalValue entry       |
// | SY    | `SY <v> <synonym> <value>`             | setSynonym entry          |
// | F     | `F <v> <value>`                        | computeValues, each row   |
// | O     | `O <v> <value> <int>` or `O - - 0`     | getObjectVariableValue    |
// | PS    | `PS <pass>`                            | root layout() entry       |
// | X     | `X <exception class>`                  | the solver loop's catch   |
//
// `<row>` is `<n> <id>:<value> ...`, the row's variables in list order
// (ascending id for ArrayLinkedVariables). The driver writes `T` before and
// `E` after each layout.
//
// Besides the trace lines, the same switch carries one more hook that is not
// a trace line: [SolverTrace.directSink]. The root container hands itself to
// it at the oracle's Direct dump point (pass 0, first solver iteration, right
// before the system is reset, at a DIRECT level), so the parity tooling can
// print Direct's resolution of every child in the oracle's format.

import '../array_linked_variables.dart';
import '../array_row.dart';
import '../constraint_anchor.dart';
import '../constraint_widget_container.dart';
import '../jfloat.dart';
import '../solver_variable.dart';

/// True only when compiled with `-Dcl.trace=true` (the parity tool vtrace).
/// A constant false everywhere else, so each `if (kSolverTrace) ...` call
/// site, and [SolverTrace] with it, is tree-shaken from release builds.
const bool kSolverTrace = bool.fromEnvironment('cl.trace');

/// The solver trace: formatting helpers and one method per event. Every
/// event method returns at once while [sink] is null.
abstract final class SolverTrace {
  /// Receives one event line, without its newline. Null: tracing is off.
  static void Function(String line)? sink;

  /// Receives the root container at Direct's dump point: in
  /// [ConstraintWidgetContainer.layout], pass 0, the first iteration of the
  /// solver loop, before the system is reset, when the container optimizes
  /// for [Optimizer.OPTIMIZATION_DIRECT]. By then Direct and the post-Direct
  /// measures have run and nothing has been added to the solver, so every
  /// child holds what Direct resolved. Null: off. Only the parity tools set
  /// it; it is not a trace line and [sink] does not see it.
  static void Function(ConstraintWidgetContainer container)? directSink;

  // -------------------------------------------------------------------------
  // Formatting
  // -------------------------------------------------------------------------

  /// The lowercase 8-digit hex of [value]'s binary32 bits.
  static String f(double value) {
    assert(
      isF32(value),
      'SolverTrace.f($value): every float the solver keeps is binary32; '
      'f32Bits would round a wider value and hide the missed rounding this '
      'trace exists to find',
    );
    return f32Bits(value).toRadixString(16).padLeft(8, '0');
  }

  /// The id of [variable], or `-` for null.
  static String vid(SolverVariable? variable) =>
      variable == null ? '-' : '${variable.id}';

  /// `<n> <id>:<value> ...`: the variables of [r] in list order.
  static String row(ArrayRow r) {
    final vars = r.variables;
    final sb = StringBuffer();
    if (vars is ArrayLinkedVariables) {
      final n = vars.mCurrentSize;
      sb.write(n);
      var current = vars.getHead();
      var counter = 0;
      while (current != ArrayLinkedVariables.NONE && counter < n) {
        sb
          ..write(' ')
          ..write(vars.getId(current))
          ..write(':')
          ..write(f(vars.getValue(current)));
        current = vars.getNextIndice(current);
        counter++;
      }
      return sb.toString();
    }
    final n = vars.getCurrentSize();
    sb.write(n);
    for (var i = 0; i < n; i++) {
      final v = vars.getVariable(i);
      sb
        ..write(' ')
        ..write(v == null ? -1 : v.id)
        ..write(':')
        ..write(f(vars.getVariableValue(i)));
    }
    return sb.toString();
  }

  /// `<debugName or ?>.<letter>` for an object variable's anchor.
  static String anchorName(ConstraintAnchor a) {
    final letter = switch (a.mType) {
      ConstraintAnchorType.left => 'L',
      ConstraintAnchorType.top => 'T',
      ConstraintAnchorType.right => 'R',
      ConstraintAnchorType.bottom => 'B',
      ConstraintAnchorType.baseline => 'S',
      ConstraintAnchorType.center => 'C',
      ConstraintAnchorType.centerX => 'CX',
      ConstraintAnchorType.centerY => 'CY',
      ConstraintAnchorType.none => 'N',
    };
    return '${a.mOwner.getDebugName() ?? '?'}.$letter';
  }

  /// The class Java prints for the exception it would throw where Dart threw
  /// [error]: a failed null check is Java's NullPointerException, any
  /// RangeError (IndexError included) its ArrayIndexOutOfBoundsException,
  /// another TypeError a ClassCastException. Anything else is
  /// `dart.<runtimeType>`, which no Java trace contains, as it should not:
  /// Java does not throw it.
  static String javaExceptionClass(Object error) {
    if (error is TypeError &&
        error.toString().contains('Null check operator')) {
      return 'java.lang.NullPointerException';
    }
    if (error is RangeError) {
      return 'java.lang.ArrayIndexOutOfBoundsException';
    }
    if (error is TypeError) {
      return 'java.lang.ClassCastException';
    }
    return 'dart.${error.runtimeType}';
  }

  // -------------------------------------------------------------------------
  // Events
  // -------------------------------------------------------------------------

  /// A fixed event line: `RS`, `D E`, `D K`.
  static void line(String event) {
    final s = sink;
    if (s == null) return;
    s(event);
  }

  /// V: [v] got a new id. [type] is `U`, `S`, `X`, `E` or `N`.
  static void newVariable(
    SolverVariable v,
    String type,
    int strength,
    String? name,
  ) {
    final s = sink;
    if (s == null) return;
    s('V ${v.id} $type $strength ${name ?? '-'}');
  }

  /// Q: addEqualityConstant(a, value) entry.
  static void equality(SolverVariable? a, int value) {
    final s = sink;
    if (s == null) return;
    s('Q ${vid(a)} $value');
  }

  /// A: addConstraint entry.
  static void addConstraint(ArrayRow r) {
    final s = sink;
    if (s == null) return;
    s(
      'A ${vid(r.mVariable)} ${r.mIsSimpleDefinition ? 1 : 0} '
      '${f(r.mConstantValue)} ${row(r)}',
    );
  }

  /// U: the row after updateFromSystem.
  static void updated(ArrayRow r) {
    final s = sink;
    if (s == null) return;
    s('U ${f(r.mConstantValue)} ${row(r)}');
  }

  /// R: the row after chooseSubject; [extra] when it needs an extra
  /// variable.
  static void subject(ArrayRow r, bool extra) {
    final s = sink;
    if (s == null) return;
    s(
      'R ${extra ? '-' : vid(r.mVariable)} ${extra ? 1 : 0} '
      '${f(r.mConstantValue)} ${row(r)}',
    );
  }

  /// RX: the extra variable left the basis and the row was released.
  static void removedExtra(ArrayRow r) {
    final s = sink;
    if (s == null) return;
    s('RX ${vid(r.mVariable)}');
  }

  /// AF: addRow turns a simple definition into a final value.
  static void addFinal(ArrayRow r) {
    final s = sink;
    if (s == null) return;
    s('AF ${vid(r.mVariable)} ${f(r.mConstantValue)}');
  }

  /// AR: addRow stores [r] at [index].
  static void addRow(int index, ArrayRow r) {
    final s = sink;
    if (s == null) return;
    s('AR $index ${vid(r.mVariable)} ${f(r.mConstantValue)} ${row(r)}');
  }

  /// CP: addRow's compaction removes the simple row at [index].
  static void compact(int index, ArrayRow r) {
    final s = sink;
    if (s == null) return;
    s('CP $index ${vid(r.mVariable)}');
  }

  /// MZ: minimize entry.
  static void minimize(int rows, int columns, bool goalEmpty) {
    final s = sink;
    if (s == null) return;
    s('MZ $rows $columns ${goalEmpty ? 1 : 0}');
  }

  /// BF: enforceBFS after its infeasibility scan.
  static void bfs(bool infeasible) {
    final s = sink;
    if (s == null) return;
    s(infeasible ? 'BF 1' : 'BF 0');
  }

  /// B: enforceBFS pivots [row] on the variable with id [column].
  static void bfsPivot(int row, int column) {
    final s = sink;
    if (s == null) return;
    s('B $row $column');
  }

  /// C: optimize's candidate; [temp] for addConstraint's temporary goal.
  static void candidate(bool temp, int tries, SolverVariable? c) {
    final s = sink;
    if (s == null) return;
    s('C ${temp ? 'T' : 'G'} $tries ${vid(c)}');
  }

  /// P: optimize pivots [row] on [entering].
  static void pivotChoice(int row, SolverVariable entering, bool temp) {
    final s = sink;
    if (s == null) return;
    s('P $row ${vid(entering)} ${temp ? 'T' : 'G'}');
  }

  /// NP: optimize found no row to pivot its candidate on.
  static void noPivot(bool temp) {
    final s = sink;
    if (s == null) return;
    s('NP ${temp ? 'T' : 'G'}');
  }

  /// OE: optimize returns; [reason] is `cap`, `tested` or `done`.
  static void optimizeEnd(bool temp, int tries, String reason) {
    final s = sink;
    if (s == null) return;
    s('OE ${temp ? 'T' : 'G'} $tries $reason');
  }

  /// PI: ArrayRow.pivot moved [r]'s subject from [leaving] to [entering],
  /// dividing by [amount].
  static void pivot(
    SolverVariable? leaving,
    SolverVariable? entering,
    double amount,
    ArrayRow r,
  ) {
    final s = sink;
    if (s == null) return;
    s(
      'PI ${vid(leaving)} ${vid(entering)} ${f(amount)} '
      '${f(r.mConstantValue)} ${row(r)}',
    );
  }

  /// G: [v]'s goal strength vector after a change.
  static void goalVector(SolverVariable v) {
    final s = sink;
    if (s == null) return;
    final sb = StringBuffer('G ${v.id}');
    final g = v.mGoalStrengthVector;
    for (var i = 0; i < g.length; i++) {
      sb
        ..write(' ')
        ..write(f(g[i]));
    }
    s(sb.toString());
  }

  /// GR: [v] left the goal.
  static void goalRemoved(SolverVariable v) {
    final s = sink;
    if (s == null) return;
    s('GR ${v.id}');
  }

  /// FV: setFinalValue entry.
  static void finalValue(SolverVariable v, double value) {
    final s = sink;
    if (s == null) return;
    s('FV ${v.id} ${f(value)}');
  }

  /// SY: setSynonym entry.
  static void synonym(SolverVariable v, SolverVariable? synonym, double value) {
    final s = sink;
    if (s == null) return;
    s('SY ${v.id} ${vid(synonym)} ${f(value)}');
  }

  /// F: computeValues gave [r]'s subject its value.
  static void computed(ArrayRow r) {
    final s = sink;
    if (s == null) return;
    s('F ${vid(r.mVariable)} ${f(r.mVariable!.computedValue)}');
  }

  /// O: getObjectVariableValue read [v] as [value]; `O - - 0` for none.
  static void readback(SolverVariable? v, int value) {
    final s = sink;
    if (s == null) return;
    s(v == null ? 'O - - 0' : 'O ${v.id} ${f(v.computedValue)} $value');
  }

  /// PS: the root container's layout() starts pass [pass].
  static void pass(int pass) {
    final s = sink;
    if (s == null) return;
    s('PS $pass');
  }

  /// M: the root container's solver loop minimizes, in iteration
  /// [iteration] (from 1) of pass [pass].
  static void minimizeCall(int pass, int iteration) {
    final s = sink;
    if (s == null) return;
    s('M $pass $iteration');
  }

  /// X: a container's solver loop caught [error].
  static void caught(Object error) {
    final s = sink;
    if (s == null) return;
    s('X ${javaExceptionClass(error)}');
  }

  /// Direct's dump point: hands [container] to [directSink].
  static void directDump(ConstraintWidgetContainer container) {
    final s = directSink;
    if (s == null) return;
    s(container);
  }
}
