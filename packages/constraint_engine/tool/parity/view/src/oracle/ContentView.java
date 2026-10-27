package oracle;

import android.content.Context;
import android.view.View;

/**
 * A real android.view.View whose onMeasure is the shared content model
 * (FORMATS.md section 6.1): what the app's view answers. Everything around it
 * (ConstraintLayout's view layer, View.measure, getChildMeasureSpec,
 * resolveSizeAndState, layout) is the real framework and library code.
 *
 *   box  W H   EXACTLY s -> s, AT_MOST s -> min(n, s), UNSPECIFIED -> n
 *   text W H   width as box with n = W; height n = H * ceil(W / width)
 *              (H * 50 at width <= 0), then resolved like box
 *   none       View.onMeasure (getDefaultSize(0, spec)); no baseline
 */
public final class ContentView extends View {
    public static final int BOX = 0, TEXT = 1, NONE = 2;

    int kind;
    int contentW;
    int contentH;
    int baseline;
    /** onMeasure calls, for the measure-count statistics. */
    public int measures;

    public ContentView(Context context, int kind, int w, int h, int baseline) {
        super(context);
        this.kind = kind;
        this.contentW = w;
        this.contentH = h;
        this.baseline = baseline;
    }

    /** An in-place content change (a later state's ct op): relayout when it differs. */
    public void setContent(int kind, int w, int h, int baseline) {
        if (kind == this.kind && w == contentW && h == contentH && baseline == this.baseline) return;
        this.kind = kind;
        this.contentW = w;
        this.contentH = h;
        this.baseline = baseline;
        requestLayout();
    }

    static int resolve(int n, int spec) {
        int mode = MeasureSpec.getMode(spec);
        int size = MeasureSpec.getSize(spec);
        if (mode == MeasureSpec.EXACTLY) return size;
        if (mode == MeasureSpec.AT_MOST) return Math.min(n, size);
        return n;
    }

    int textHeightAt(int width) {
        if (width <= 0) return contentH * 50;
        return contentH * ((contentW + width - 1) / width);
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        measures++;
        if (kind == NONE) {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec);
            return;
        }
        int width = resolve(contentW, widthMeasureSpec);
        int natural = kind == TEXT ? textHeightAt(width) : contentH;
        int height = resolve(natural, heightMeasureSpec);
        setMeasuredDimension(width, height);
    }

    @Override
    public int getBaseline() {
        return kind == NONE ? -1 : baseline;
    }
}
