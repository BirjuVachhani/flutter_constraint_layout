package oracle;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.view.View;
import android.view.ViewGroup;
import androidx.constraintlayout.widget.ConstraintLayout;
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams;
import java.lang.reflect.Field;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

/** ViewProbe's three probes on real views (FORMATS.md, p0-view). */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35, manifest = Config.NONE)
public class RoboSmoke {
    static String f(String n, View v) {
        return n + "=(" + v.getLeft() + "," + v.getTop() + "," + v.getWidth() + "x" + v.getHeight() + ")";
    }

    static ConstraintLayout root(Context c) {
        ConstraintLayout r = new ConstraintLayout(c);
        return r;
    }

    static void layout(ConstraintLayout r, int w, int h) {
        r.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY));
        r.layout(0, 0, r.getMeasuredWidth(), r.getMeasuredHeight());
    }

    @Test
    public void probes() throws Exception {
        Context c = RuntimeEnvironment.getApplication();
        ApplicationInfo ai = c.getApplicationInfo();
        System.out.println("SDK_INT=" + android.os.Build.VERSION.SDK_INT + " targetSdk=" + ai.targetSdkVersion
                + " flags=0x" + Integer.toHexString(ai.flags));
        ai.targetSdkVersion = 35;
        ai.flags |= ApplicationInfo.FLAG_SUPPORTS_RTL;
        new View(c);
        for (Field fl : View.class.getDeclaredFields()) {
            String n = fl.getName();
            if (java.lang.reflect.Modifier.isStatic(fl.getModifiers()) && fl.getType() == boolean.class
                    && (n.contains("Unspecified") || n.contains("Remeasure") || n.contains("MakeMeasureSpec")
                        || n.contains("MeasureCache") || n.contains("Compatibility"))) {
                fl.setAccessible(true);
                System.out.println(n + "=" + fl.get(null));
            }
        }
        System.out.println("CL class from " + ConstraintLayout.class.getProtectionDomain().getCodeSource().getLocation());
        System.out.println("core from " + androidx.constraintlayout.core.LinearSystem.class.getProtectionDomain().getCodeSource().getLocation());
        System.out.println("View from " + View.class.getProtectionDomain().getCodeSource().getLocation());
        {
            ConstraintLayout r = root(c);
            ContentView d = new ContentView(c, ContentView.BOX, 300, 50, -1);
            d.setId(1);
            LayoutParams lp = new LayoutParams(0, 0);
            lp.leftToLeft = LayoutParams.PARENT_ID; lp.leftMargin = 10;
            lp.topToTop = LayoutParams.PARENT_ID; lp.topMargin = 10;
            r.addView(d, lp);
            layout(r, 400, 800);
            System.out.println("match x match, one link per axis: " + f("D", d) + " measures=" + d.measures);
        }
        {
            ConstraintLayout r = root(c);
            ContentView a = new ContentView(c, ContentView.TEXT, 1000, 20, -1);
            a.setId(1);
            LayoutParams lp = new LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.topToTop = LayoutParams.PARENT_ID; lp.topMargin = 10;
            r.addView(a, lp);
            layout(r, 400, 800);
            System.out.println("matchParent x wrap text: " + f("A", a));
        }
        {
            ConstraintLayout r = root(c);
            ContentView b = new ContentView(c, ContentView.BOX, 100, 40, 30);
            b.setId(1);
            ContentView cc = new ContentView(c, ContentView.BOX, 100, 20, 15);
            cc.setId(2);
            LayoutParams lb = new LayoutParams(100, 40);
            lb.leftToLeft = LayoutParams.PARENT_ID; lb.topToTop = LayoutParams.PARENT_ID; lb.topMargin = 100;
            LayoutParams lc = new LayoutParams(100, 20);
            lc.leftToRight = 1; lc.baselineToBaseline = 1;
            r.addView(b, lb);
            r.addView(cc, lc);
            layout(r, 400, 800);
            System.out.println("fixed-size baseline pair: " + f("B", b) + " " + f("C", cc));
        }
    }
}
