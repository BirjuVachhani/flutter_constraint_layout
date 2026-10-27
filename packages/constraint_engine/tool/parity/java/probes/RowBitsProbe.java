package androidx.constraintlayout.core;

import androidx.constraintlayout.core.widgets.ConstraintAnchor;
import androidx.constraintlayout.core.widgets.ConstraintWidget;

/**
 * RowBitsProbe: the binary32 bits of the rows upstream's ArrayRow builds
 * (createRowCentering, createRowEqualMatchDimensions, createRowEqualDimension,
 * createRowDimensionRatio, createRowDimensionPercent, and a row after pivot),
 * and the int that LinearSystem.getObjectVariableValue reads back from a
 * computed value, on the pinned core classes ($CL_CORE). These are the
 * expected values of test/solver_float_test.dart.
 *
 * It is in the core's package because it calls package-private members
 * (ArrayRow.mConstantValue, createRowCentering, createRowDimensionPercent and
 * pivot):
 *   javac -d <dir> -cp $CL_CORE RowBitsProbe.java
 *   java -cp $CL_CORE:<dir> androidx.constraintlayout.core.RowBitsProbe
 */
public class RowBitsProbe {
    static String h(float f) {
        return String.format("0x%08x", Float.floatToRawIntBits(f));
    }

    static void row(String label, ArrayRow r, SolverVariable... vs) {
        StringBuilder b = new StringBuilder(label).append(" C=").append(h(r.mConstantValue));
        for (SolverVariable v : vs) {
            b.append(' ').append(v.id).append(':').append(h(r.variables.get(v)));
        }
        System.out.println(b);
    }

    public static void main(String[] args) {
        LinearSystem s = new LinearSystem();
        SolverVariable a = s.createSlackVariable(), b = s.createSlackVariable();
        SolverVariable c = s.createSlackVariable(), d = s.createSlackVariable();
        row("centering(10, 0.3f, 20)", s.createRow().createRowCentering(a, b, 10, 0.3f, c, d, 20), a, b, c, d);
        row("centering(-5, 0.7f, 0)", s.createRow().createRowCentering(a, b, -5, 0.7f, c, d, 0), a, b, c, d);
        row("centering(7, 0.45f, 3)", s.createRow().createRowCentering(a, b, 7, 0.45f, c, d, 3), a, b, c, d);
        row("equalMatch(1, 6, 3)", s.createRow().createRowEqualMatchDimensions(1f, 6f, 3f, a, b, c, d), a, b, c, d);
        row("equalMatch(0.3f, 1.1f, 0.7f)", s.createRow().createRowEqualMatchDimensions(0.3f, 1.1f, 0.7f, a, b, c, d), a, b, c, d);
        row("equalDimension(1, 6, 3; 8 8 5 7)", s.createRow().createRowEqualDimension(1f, 6f, 3f, a, 8, b, 8, c, 5, d, 7), a, b, c, d);
        row("ratio(0.29f)", s.createRow().createRowDimensionRatio(a, b, c, d, 0.29f), a, b, c, d);
        row("percent(0.33f)", s.createRow().createRowDimensionPercent(a, c, 0.33f), a, c);
        ArrayRow p = s.createRow().createRowCentering(a, b, 10, 0.3f, c, d, 20);
        p.pivot(c);
        row("centering(10, 0.3f, 20) pivot c", p, a, b, c, d);
        float[] cv = {12.5f, 0.49999997f, -7f, -6.5f, -6.6f, -0.6f, 8388607.5f, 1e10f, -1e10f, Float.NaN};
        ConstraintWidget w = new ConstraintWidget();
        ConstraintAnchor left = w.getAnchor(ConstraintAnchor.Type.LEFT);
        LinearSystem s2 = new LinearSystem();
        SolverVariable lv = s2.createObjectVariable(left);
        StringBuilder rb = new StringBuilder("readback");
        for (float x : cv) {
            lv.computedValue = x;
            rb.append(' ').append(h(x)).append("->").append(s2.getObjectVariableValue(left));
        }
        System.out.println(rb);
    }
}
