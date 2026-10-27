package androidx.constraintlayout.core.widgets;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.HashSet;

// verify-final: the Flutter adapter's in-place reset (_applyWidgetConfig),
// which resets every anchor of a widget and then restores the anchors'
// incoming dependents, for the oracle to replay.
public final class VfAccess {
    private VfAccess() {}

    private static final Field DEPENDENTS;

    static {
        try {
            DEPENDENTS = ConstraintAnchor.class.getDeclaredField("mDependents");
            DEPENDENTS.setAccessible(true);
        } catch (NoSuchFieldException e) {
            throw new RuntimeException(e);
        }
    }

    @SuppressWarnings("unchecked")
    public static void inPlaceReset(ConstraintWidget w) {
        try {
            ArrayList<HashSet<ConstraintAnchor>> saved = new ArrayList<>();
            for (ConstraintAnchor a : w.mAnchors) {
                saved.add((HashSet<ConstraintAnchor>) DEPENDENTS.get(a));
            }
            w.resetAnchors();
            for (int i = 0; i < w.mAnchors.size(); i++) {
                DEPENDENTS.set(w.mAnchors.get(i), saved.get(i));
            }
        } catch (IllegalAccessException e) {
            throw new RuntimeException(e);
        }
    }

    @SuppressWarnings("unchecked")
    private static HashSet<ConstraintAnchor> deps(ConstraintAnchor a) throws IllegalAccessException {
        return (HashSet<ConstraintAnchor>) DEPENDENTS.get(a);
    }

    private static void register(ConstraintAnchor a) throws IllegalAccessException {
        ConstraintAnchor t = a.mTarget;
        HashSet<ConstraintAnchor> d = deps(t);
        if (d == null) {
            d = new HashSet<>();
            DEPENDENTS.set(t, d);
        }
        d.add(a);
    }

    // baseline: every live link registered with its target (the adapter's
    // state after its in-place dependents restore).
    public static void rereg(ConstraintWidgetContainer root) {
        try {
            for (ConstraintWidget c : root.getChildren()) {
                for (ConstraintAnchor a : c.mAnchors) {
                    if (a.mTarget != null) register(a);
                }
            }
        } catch (IllegalAccessException e) {
            throw new RuntimeException(e);
        }
    }

    // baseline: the dependents Android's view layer leaves (see ops.dart
    // 'adeps'): all live links, except a link from a child configured before
    // X into X's top or bottom when X has a baseline link.
    public static void androidDeps(ConstraintWidgetContainer root) {
        try {
            java.util.ArrayList<ConstraintWidget> kids = root.getChildren();
            java.util.IdentityHashMap<ConstraintWidget, Integer> index = new java.util.IdentityHashMap<>();
            for (int i = 0; i < kids.size(); i++) index.put(kids.get(i), i);
            for (ConstraintAnchor a : root.mAnchors) DEPENDENTS.set(a, null);
            for (ConstraintWidget c : kids) {
                for (ConstraintAnchor a : c.mAnchors) DEPENDENTS.set(a, null);
            }
            for (ConstraintWidget c : kids) {
                for (ConstraintAnchor a : c.mAnchors) {
                    ConstraintAnchor t = a.mTarget;
                    if (t == null) continue;
                    ConstraintWidget x = t.mOwner;
                    Integer xi = index.get(x);
                    if (xi != null && x.mBaseline.mTarget != null
                            && (t.mType == ConstraintAnchor.Type.TOP || t.mType == ConstraintAnchor.Type.BOTTOM)
                            && index.get(c) < xi) {
                        continue;
                    }
                    register(a);
                }
            }
        } catch (IllegalAccessException e) {
            throw new RuntimeException(e);
        }
    }
}
