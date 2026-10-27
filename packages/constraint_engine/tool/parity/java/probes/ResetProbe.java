import androidx.constraintlayout.core.widgets.*;
import androidx.constraintlayout.core.widgets.ConstraintAnchor.Type;
import androidx.constraintlayout.core.widgets.analyzer.BasicMeasure;

/**
 * ResetProbe: the gone-reference barrier of fresh_state_test, measured three
 * times with Android's dirty-hierarchy rebuild (every child reset() and
 * configured again, CL 1249-1351) between measures, at levels 0 and 257.
 */
public class ResetProbe {
    static class Echo implements BasicMeasure.Measurer {
        @Override public void measure(ConstraintWidget w, BasicMeasure.Measure m) {
            m.measuredWidth = m.horizontalDimension;
            m.measuredHeight = m.verticalDimension;
            m.measuredBaseline = 0;
            m.measuredHasBaseline = false;
            w.setMeasureRequested(false);
        }
        @Override public void didMeasures() {}
    }

    static ConstraintWidgetContainer root;
    static ConstraintWidget W, K;
    static Barrier bar;

    static void configure(boolean wGone) {
        W.reset(); bar.reset(); K.reset();
        root.removeAllChildren();
        bar.removeAllIds(); bar.add(W); // updatePreLayout
        root.add(W);
        W.setVisibility(wGone ? ConstraintWidget.GONE : ConstraintWidget.VISIBLE);
        W.immediateConnect(Type.LEFT, root, Type.LEFT, 100, Integer.MIN_VALUE);
        W.setWidth(50); W.setHeight(50);
        root.add(bar);
        bar.setVisibility(ConstraintWidget.GONE); // the view Barrier is GONE
        bar.setBarrierType(Barrier.RIGHT); bar.setAllowsGoneWidget(false); bar.setMargin(5);
        root.add(K);
        K.immediateConnect(Type.LEFT, bar, Type.RIGHT, 0, Integer.MIN_VALUE);
        K.setWidth(30); K.setHeight(30);
    }

    static String frames() {
        StringBuilder sb = new StringBuilder();
        for (ConstraintWidget c : root.getChildren()) {
            sb.append(' ').append(c.getDebugName()).append('(').append(c.getX()).append(',')
              .append(c.getY()).append(' ').append(c.getWidth()).append('x').append(c.getHeight()).append(')');
        }
        return sb.toString();
    }

    public static void main(String[] args) {
        for (int level : new int[]{0, 257}) {
            root = new ConstraintWidgetContainer(0, 0, 400, 800);
            root.setDebugName("root");
            root.setMeasurer(new Echo());
            root.setOptimizationLevel(level);
            W = new ConstraintWidget(); W.setDebugName("W");
            bar = new Barrier(); bar.setDebugName("bar");
            K = new ConstraintWidget(); K.setDebugName("K");
            StringBuilder out = new StringBuilder("level " + level + ":");
            boolean[] steps = {true, false, true};
            for (boolean gone : steps) {
                configure(gone);
                root.measure(level, BasicMeasure.EXACTLY, 400, BasicMeasure.EXACTLY, 800, 0, 0, 0, 0);
                out.append(" |").append(frames());
            }
            System.out.println(out);
        }
    }
}
