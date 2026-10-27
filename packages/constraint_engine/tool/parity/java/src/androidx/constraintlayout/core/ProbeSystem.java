package androidx.constraintlayout.core;

import java.lang.reflect.Field;

/**
 * Phase 0 oracle (p0-java): the container's LinearSystem with two observation hooks.
 * It changes no behaviour: reset() and minimize() call the hook, then upstream's code.
 * It lives in this package to read the package-private counters for DirectProbe.
 */
public class ProbeSystem extends LinearSystem {

    /** Observer of the solver loop of ConstraintWidgetContainer.layout(). */
    public interface Hook {
        /** Called at the entry of every reset(), before upstream's reset runs. */
        void onReset();

        /** Called at the entry of every minimize(), before upstream's minimize runs. */
        void onMinimize(ProbeSystem system);
    }

    public Hook hook;

    private static final Field NUM_GOALS;

    static {
        Field f = null;
        try {
            f = PriorityGoalRow.class.getDeclaredField("mNumGoals");
            f.setAccessible(true);
        } catch (NoSuchFieldException e) {
            throw new IllegalStateException("PriorityGoalRow.mNumGoals is missing", e);
        }
        NUM_GOALS = f;
    }

    @Override
    public void reset() {
        if (hook != null) {
            hook.onReset();
        }
        super.reset();
    }

    @Override
    public void minimize() throws Exception {
        if (hook != null) {
            hook.onMinimize(this);
        }
        super.minimize();
    }

    /** Rows stored in the tableau (mNumRows). */
    public int rows() {
        return mNumRows;
    }

    /** mNumColumns: variables created plus one. */
    public int columns() {
        return mNumColumns;
    }

    /** mVariablesID: the highest variable id handed out. */
    public int variables() {
        return mVariablesID;
    }

    public boolean goalEmpty() {
        return getGoal().isEmpty();
    }

    /** Entries of the goal row (PriorityGoalRow.mNumGoals). */
    public int goalSize() {
        Row goal = getGoal();
        if (goal instanceof PriorityGoalRow) {
            try {
                return NUM_GOALS.getInt(goal);
            } catch (IllegalAccessException e) {
                throw new IllegalStateException(e);
            }
        }
        return goal.isEmpty() ? 0 : -1;
    }

    /** Variables with an id in 1..mVariablesID that are not final. */
    public int freeVariables() {
        int free = 0;
        SolverVariable[] vars = mCache.mIndexedVariables;
        for (int i = 1; i <= mVariablesID && i < vars.length; i++) {
            SolverVariable v = vars[i];
            if (v != null && !v.isFinalValue) {
                free++;
            }
        }
        return free;
    }
}
