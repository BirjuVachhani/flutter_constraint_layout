package oracle;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.view.View;
import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.PrintStream;
import java.io.Writer;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

/**
 * The real-view oracle (FORMATS.md section 10): every corpus line becomes a
 * fresh ConstraintLayout of real views, measured and laid out by the real
 * framework and view-layer code under Robolectric.
 *
 * System properties: robo.in, robo.out (appended), robo.progress, robo.start
 * (line index, default 0), robo.count (default all), robo.timeoutMs (default
 * 4000), robo.measures (adds an "M ..." field with onMeasure counts),
 * robo.inplace (a T-inplace op list is applied state by state to the same
 * live views; robo.out.fresh gets a fresh build of each final state; with
 * robo.inplace=changed only the views whose layout params, content or
 * visibility change are touched, so a state that changes nothing lays nothing
 * out again),
 * robo.level (the ConstraintLayout view's optimization level,
 * setOptimizationLevel, on every layout view the run builds; default 257,
 * Android's default) and robo.twice (after the final measure and layout,
 * nothing changes but a requestLayout, and the views are measured and laid
 * out a second time; robo.out.twice gets the second geometry). With
 * robo.twice=dirty the first child view requests the layout, so the second
 * onMeasure takes the dirty path (setChildrenConstraints: every child
 * reset() and configured again from its layout params), the second layout
 * DirtyTwice emulates. With any other value (robo.twice=layout) the layout
 * view alone requests it: onMeasure then reconfigures the children only when
 * one of them is still layout-requested (a GONE child, which onLayout never
 * lays out, stays so from its creation), and otherwise measures again over
 * the widgets as the last measure left them (no reset).
 * On a timeout the line is "id\tHANG" and the JVM exits with code 3, so the
 * caller restarts after it (roborun.sh does).
 */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35, manifest = Config.NONE)
public class RoboOracle {
    static final Object LOCK = new Object();
    static volatile long started;
    static volatile String currentId;

    static String oneLine(Throwable e) {
        return e.toString().replace('\t', ' ').replace('\n', ' ');
    }

    /** The fresh-build geometry of an in-place sequence's final state (robo.inplace). */
    static String lastFresh;

    /** robo.inplace=changed: an in-place state touches only the views that change. */
    static boolean inplaceChanged;

    /** The optimization level of every layout view (robo.level, default 257). */
    static int level = 257;

    /**
     * robo.twice: null (off), "dirty" (a child view requests the second
     * layout) or any other value (the layout view alone requests it).
     */
    static String twice;

    /** The second layout's "status \t geometry" (robo.twice), or null. */
    static String lastTwice;

    /** Lays out one op list; returns "status \t geometry[ \t M...]". */
    static String layoutOne(Context ctx, String ops, boolean measures) {
        return layoutOne(ctx, ops, measures, false);
    }

    /**
     * With [inplace] and an op list that has L ops, every state (cut before
     * each L, then the whole list) is applied to the same live views, and the
     * final geometry is returned; lastFresh gets a fresh build of the final
     * state.
     */
    static String layoutOne(Context ctx, String ops, boolean measures, boolean inplace) {
        lastFresh = null;
        lastTwice = null;
        java.util.List<RoboOps> states;
        try {
            states = inplace && ops.contains(";L;")
                    ? RoboOps.states(ops)
                    : java.util.Collections.singletonList(RoboOps.replay(ops));
        } catch (Throwable e) {
            return "EXC:replay " + oneLine(e);
        }
        for (RoboOps s : states) {
            if (s.unmapped != null) return "UNMAPPED:" + s.unmapped;
        }
        if (states.size() > 1) {
            lastFresh = layoutOne(ctx, states.get(states.size() - 1), measures, null);
            lastTwice = null; // the second layout is the in-place views', below
        }
        return layoutOne(ctx, states.get(0), measures, states.subList(1, states.size()));
    }

    /**
     * Runs [v] (measure and layout) with the solver's printed output captured;
     * returns "ok\t" and the geometry, with a "!status | " prefix when the run
     * threw or printed a caught exception.
     */
    static String runCaptured(RoboViews v, boolean measures) {
        PrintStream out = System.out, err = System.err;
        ByteArrayOutputStream captured = new ByteArrayOutputStream();
        PrintStream cap = new PrintStream(captured);
        System.setOut(cap);
        System.setErr(cap);
        String status = "ok";
        try {
            v.run();
        } catch (StackOverflowError e) {
            status = "SO";
        } catch (Throwable e) {
            status = "EXC:" + oneLine(e);
        } finally {
            System.setOut(out);
            System.setErr(err);
        }
        if (status.equals("ok") && captured.toString().contains("EXCEPTION")) status = "ok-printed";
        StringBuilder sb = new StringBuilder("ok\t");
        if (!status.equals("ok")) sb.append('!').append(status).append(" | ");
        try {
            sb.append(v.geometry());
        } catch (Throwable e) {
            sb.append("geometry-failed ").append(oneLine(e));
        }
        if (measures) sb.append('\t').append(v.measureCounts());
        return sb.toString();
    }

    /** Builds [r], runs it, then applies and runs each of [later] in place. */
    static String layoutOne(Context ctx, RoboOps r, boolean measures, java.util.List<RoboOps> later) {
        RoboViews v = new RoboViews(ctx, r, level);
        try {
            v.build();
        } catch (RoboViews.Unmappable u) {
            return "UNMAPPED:" + u.getMessage();
        } catch (Throwable e) {
            return "EXC:build " + oneLine(e);
        }
        if (later != null) {
            try {
                for (RoboOps s : later) {
                    v.run();
                    v.update(s, inplaceChanged);
                }
            } catch (RoboViews.Unmappable u) {
                return "UNMAPPED:" + u.getMessage();
            } catch (Throwable e) {
                return "EXC:inplace " + oneLine(e);
            }
        }
        String result = runCaptured(v, measures);
        if (twice != null) {
            // Nothing changed but a requestLayout. A child's request makes
            // onMeasure's updateHierarchy reconfigure every child (the dirty
            // path); the layout view's own request does so only while some
            // child is still layout-requested.
            if (twice.equals("dirty") && !v.views.isEmpty()) {
                v.views.get(0).requestLayout();
            } else {
                v.layout.requestLayout();
            }
            lastTwice = runCaptured(v, measures);
        }
        return result;
    }

    static Context setUpContext() {
        Context ctx = RuntimeEnvironment.getApplication();
        ApplicationInfo ai = ctx.getApplicationInfo();
        // A current app: no pre-M measure-spec compatibility, RTL supported.
        ai.targetSdkVersion = 35;
        ai.flags |= ApplicationInfo.FLAG_SUPPORTS_RTL;
        new View(ctx); // fixes View's static compatibility flags from the target SDK
        return ctx;
    }

    @Test
    public void run() throws Exception {
        Context ctx = setUpContext();
        String in = System.getProperty("robo.in");
        String outFile = System.getProperty("robo.out");
        String progress = System.getProperty("robo.progress", outFile + ".progress");
        long start = Long.parseLong(System.getProperty("robo.start", "0"));
        long count = Long.parseLong(System.getProperty("robo.count", "-1"));
        long timeout = Long.parseLong(System.getProperty("robo.timeoutMs", "4000"));
        boolean measures = System.getProperty("robo.measures") != null;
        boolean inplace = System.getProperty("robo.inplace") != null;
        inplaceChanged = "changed".equals(System.getProperty("robo.inplace"));
        level = Integer.parseInt(System.getProperty("robo.level", "257"));
        twice = System.getProperty("robo.twice");
        final Writer out = new FileWriter(outFile, true);
        final Writer fresh = inplace ? new FileWriter(outFile + ".fresh", true) : null;
        final Writer second = twice != null ? new FileWriter(outFile + ".twice", true) : null;
        Thread watchdog = new Thread(() -> {
            while (true) {
                try {
                    Thread.sleep(250);
                } catch (InterruptedException e) {
                    return;
                }
                long s = started;
                if (s != 0 && System.currentTimeMillis() - s > timeout) {
                    synchronized (LOCK) {
                        try {
                            out.write(currentId + "\tHANG\n");
                            out.flush();
                        } catch (Exception ignored) {
                        }
                    }
                    Runtime.getRuntime().halt(3);
                }
            }
        });
        watchdog.setDaemon(true);
        watchdog.start();
        long idx = -1, done = 0;
        long t0 = System.currentTimeMillis();
        try (BufferedReader r = new BufferedReader(new FileReader(in))) {
            String line;
            while ((line = r.readLine()) != null) {
                idx++;
                if (idx < start || line.isEmpty()) continue;
                if (count >= 0 && done >= count) break;
                int tab = line.indexOf('\t');
                String id = line.substring(0, tab);
                String ops = line.substring(line.lastIndexOf('\t') + 1);
                try (Writer p = new FileWriter(progress)) {
                    p.write(Long.toString(idx));
                }
                currentId = id;
                started = System.currentTimeMillis();
                String result = layoutOne(ctx, ops, measures, inplace);
                started = 0;
                synchronized (LOCK) {
                    out.write(id + "\t" + result + "\n");
                    if (fresh != null && lastFresh != null) fresh.write(id + "\t" + lastFresh + "\n");
                    if (second != null && lastTwice != null) second.write(id + "\t" + lastTwice + "\n");
                    if ((done & 255) == 0) out.flush();
                }
                done++;
            }
        }
        synchronized (LOCK) {
            out.flush();
            out.close();
            if (fresh != null) fresh.close();
            if (second != null) second.close();
        }
        try (Writer p = new FileWriter(progress)) {
            p.write("DONE");
        }
        System.out.println("RoboOracle: " + done + " layouts in " + (System.currentTimeMillis() - t0) + " ms");
    }
}
