package androidx.constraintlayout.core;

import androidx.constraintlayout.core.widgets.ConstraintAnchor;

/**
 * TraceJava sink. The patched LinearSystem, ArrayRow,
 * ArrayLinkedVariables, PriorityGoalRow and SolverVariable call these methods only when
 * {@link #sb} is not null, so with no sink installed they behave and print exactly as
 * upstream. Grammar: tool/parity/FORMATS.md section 7b. Every method only
 * reads solver state.
 */
public final class SolverTrace {
    private SolverTrace() {
    }

    /** The trace of the current layout; null when tracing is off. */
    public static StringBuilder sb;

    private static final char[] HEX = "0123456789abcdef".toCharArray();

    static void f(StringBuilder b, float x) {
        int bits = Float.floatToRawIntBits(x);
        for (int shift = 28; shift >= 0; shift -= 4) {
            b.append(HEX[(bits >>> shift) & 0xf]);
        }
    }

    static void var(StringBuilder b, SolverVariable v) {
        if (v == null) {
            b.append('-');
        } else {
            b.append(v.id);
        }
    }

    /** {@code <n> <v>:<f> ...} in ArrayLinkedVariables list order. */
    static void row(StringBuilder b, ArrayRow r) {
        ArrayRow.ArrayRowVariables vars = r.variables;
        if (vars instanceof ArrayLinkedVariables) {
            ((ArrayLinkedVariables) vars).traceTo(b);
            return;
        }
        int n = vars.getCurrentSize();
        b.append(n);
        for (int i = 0; i < n; i++) {
            SolverVariable v = vars.getVariable(i);
            b.append(' ').append(v == null ? -1 : v.id).append(':');
            f(b, vars.getVariableValue(i));
        }
    }

    static String anchorName(ConstraintAnchor a) {
        String owner = a.getOwner() == null ? null : a.getOwner().getDebugName();
        String t;
        switch (a.getType()) {
            case LEFT:
                t = "L";
                break;
            case TOP:
                t = "T";
                break;
            case RIGHT:
                t = "R";
                break;
            case BOTTOM:
                t = "B";
                break;
            case BASELINE:
                t = "S";
                break;
            case CENTER:
                t = "C";
                break;
            case CENTER_X:
                t = "CX";
                break;
            case CENTER_Y:
                t = "CY";
                break;
            default:
                t = "N";
                break;
        }
        return (owner == null ? "?" : owner) + "." + t;
    }

    static void line(String s) {
        sb.append(s).append('\n');
    }

    static void newVariable(SolverVariable v, char type, int strength, String name) {
        sb.append("V ").append(v.id).append(' ').append(type).append(' ').append(strength)
                .append(' ').append(name == null ? "-" : name).append('\n');
    }

    static void equality(SolverVariable a, int value) {
        sb.append("Q ");
        var(sb, a);
        sb.append(' ').append(value).append('\n');
    }

    static void addConstraint(ArrayRow r) {
        sb.append("A ");
        var(sb, r.mVariable);
        sb.append(' ').append(r.mIsSimpleDefinition ? '1' : '0').append(' ');
        f(sb, r.mConstantValue);
        sb.append(' ');
        row(sb, r);
        sb.append('\n');
    }

    static void updated(ArrayRow r) {
        sb.append("U ");
        f(sb, r.mConstantValue);
        sb.append(' ');
        row(sb, r);
        sb.append('\n');
    }

    static void subject(ArrayRow r, boolean extra) {
        sb.append("R ");
        var(sb, extra ? null : r.mVariable);
        sb.append(' ').append(extra ? '1' : '0').append(' ');
        f(sb, r.mConstantValue);
        sb.append(' ');
        row(sb, r);
        sb.append('\n');
    }

    static void removedExtra(ArrayRow r) {
        sb.append("RX ");
        var(sb, r.mVariable);
        sb.append('\n');
    }

    static void addFinal(ArrayRow r) {
        sb.append("AF ");
        var(sb, r.mVariable);
        sb.append(' ');
        f(sb, r.mConstantValue);
        sb.append('\n');
    }

    static void addRow(int index, ArrayRow r) {
        sb.append("AR ").append(index).append(' ');
        var(sb, r.mVariable);
        sb.append(' ');
        f(sb, r.mConstantValue);
        sb.append(' ');
        row(sb, r);
        sb.append('\n');
    }

    static void compact(int index, ArrayRow r) {
        sb.append("CP ").append(index).append(' ');
        var(sb, r.mVariable);
        sb.append('\n');
    }

    static void minimize(int rows, int cols, boolean goalEmpty) {
        sb.append("MZ ").append(rows).append(' ').append(cols).append(' ')
                .append(goalEmpty ? '1' : '0').append('\n');
    }

    static void candidate(boolean temp, int tries, SolverVariable c) {
        sb.append("C ").append(temp ? 'T' : 'G').append(' ').append(tries).append(' ');
        var(sb, c);
        sb.append('\n');
    }

    static void optimizeEnd(boolean temp, int tries, String reason) {
        sb.append("OE ").append(temp ? 'T' : 'G').append(' ').append(tries).append(' ')
                .append(reason).append('\n');
    }

    static void pivotChoice(int rowIndex, SolverVariable entering, boolean temp) {
        sb.append("P ").append(rowIndex).append(' ');
        var(sb, entering);
        sb.append(' ').append(temp ? 'T' : 'G').append('\n');
    }

    static void noPivot(boolean temp) {
        sb.append("NP ").append(temp ? 'T' : 'G').append('\n');
    }

    static void bfs(boolean infeasible) {
        sb.append(infeasible ? "BF 1\n" : "BF 0\n");
    }

    static void bfsPivot(int rowIndex, int column) {
        sb.append("B ").append(rowIndex).append(' ').append(column).append('\n');
    }

    static void pivot(SolverVariable leaving, SolverVariable entering, float amount, ArrayRow r) {
        sb.append("PI ");
        var(sb, leaving);
        sb.append(' ');
        var(sb, entering);
        sb.append(' ');
        f(sb, amount);
        sb.append(' ');
        f(sb, r.mConstantValue);
        sb.append(' ');
        row(sb, r);
        sb.append('\n');
    }

    static void goalVector(SolverVariable v) {
        sb.append("G ").append(v.id);
        float[] g = v.mGoalStrengthVector;
        for (int i = 0; i < g.length; i++) {
            sb.append(' ');
            f(sb, g[i]);
        }
        sb.append('\n');
    }

    static void goalRemoved(SolverVariable v) {
        sb.append("GR ").append(v.id).append('\n');
    }

    static void finalValue(SolverVariable v, float value) {
        sb.append("FV ").append(v.id).append(' ');
        f(sb, value);
        sb.append('\n');
    }

    static void synonym(SolverVariable v, SolverVariable synonym, float value) {
        sb.append("SY ").append(v.id).append(' ');
        var(sb, synonym);
        sb.append(' ');
        f(sb, value);
        sb.append('\n');
    }

    static void computed(ArrayRow r) {
        sb.append("F ");
        var(sb, r.mVariable);
        sb.append(' ');
        f(sb, r.mVariable.computedValue);
        sb.append('\n');
    }

    static void readback(SolverVariable v, int value) {
        sb.append("O ");
        if (v == null) {
            sb.append("- -");
        } else {
            sb.append(v.id).append(' ');
            f(sb, v.computedValue);
        }
        sb.append(' ').append(value).append('\n');
    }
}
