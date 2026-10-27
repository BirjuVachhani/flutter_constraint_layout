// JFloatVectors (Phase 1, p1-setup): Java-generated vectors for the port's
// packages/constraint_engine/lib/src/jfloat.dart.
//
// Build and run (light: about ten seconds):
//   javac -d <classes> tool/parity/jfloat/JFloatVectors.java
//   java -cp <classes> JFloatVectors <outDir> [perPrimitive] [seed] [select]
//
// Defaults: 100000 vectors per primitive, seed 20261025, 2000 selected per primitive.
// Writes, for each primitive, <outDir>/<primitive>.jsonl (every vector, one JSON array per
// line, the edge cases first, then the random ones) and <outDir>/<primitive>.edges (the
// edge-case count), and <outDir>/jfloat_vectors.json (the selection checked into
// packages/constraint_engine/test/: up to half the selection evenly spaced over the edge
// cases, the rest evenly spaced over the random vectors). The output depends only on the
// arguments and the JVM's arithmetic: the same seed gives the same files.
//
// Every expected value is the running JVM's own result:
//   f32                         (float) d
//   fadd fsub fmul fdiv jfrem   a + b, a - b, a * b, a / b, a % b on floats
//   fi                          (float) v for an int or long v
//   jint                        (int) d for a float or double d
//   toRadians                   Math.toRadians(d)
//   parseFloat32                Float.parseFloat(s), or null on NumberFormatException
//
// Encodings: a float is the 8 lowercase hex digits of floatToRawIntBits, a double the 16
// of doubleToRawLongBits, an fi input a decimal string (it can be a long), a jint result
// a JSON number, a parse input a JSON string with every character outside printable ASCII
// escaped as \\uXXXX.
//   f32           [d, r]          fadd .. jfrem  [a, b, r]      fi    [v, r]
//   jint          [d, int]        toRadians      [d, r]         parseFloat32  [s, r|null]

import java.io.BufferedWriter;
import java.io.IOException;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.SplittableRandom;

public final class JFloatVectors {

    static final String[] PRIMITIVES = {
        "f32", "fadd", "fsub", "fmul", "fdiv", "fi", "jint", "jfrem", "toRadians", "parseFloat32",
    };

    static SplittableRandom rnd;
    static int perPrimitive;

    // ---------------------------------------------------------------------------------
    // Encoding
    // ---------------------------------------------------------------------------------

    static final char[] HEX = "0123456789abcdef".toCharArray();

    static String h32(int v) {
        char[] c = new char[10];
        c[0] = '"';
        c[9] = '"';
        for (int i = 8; i >= 1; i--) {
            c[i] = HEX[v & 15];
            v >>>= 4;
        }
        return new String(c);
    }

    static String h64(long v) {
        char[] c = new char[18];
        c[0] = '"';
        c[17] = '"';
        for (int i = 16; i >= 1; i--) {
            c[i] = HEX[(int) (v & 15)];
            v >>>= 4;
        }
        return new String(c);
    }

    static String fh(float f) {
        return h32(Float.floatToRawIntBits(f));
    }

    static String dh(double d) {
        return h64(Double.doubleToRawLongBits(d));
    }

    static String js(String s) {
        StringBuilder b = new StringBuilder(s.length() + 2);
        b.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '"') {
                b.append("\\\"");
            } else if (c == '\\') {
                b.append("\\\\");
            } else if (c < 0x20 || c > 0x7e) {
                b.append(String.format("\\u%04x", (int) c));
            } else {
                b.append(c);
            }
        }
        return b.append('"').toString();
    }

    /** The edge cases and the random vectors of one primitive. */
    static final class Set {
        final List<String> edges = new ArrayList<>();
        final List<String> random = new ArrayList<>();

        void fillRandom(Runnable one) {
            while (edges.size() + random.size() < perPrimitive) {
                one.run();
            }
        }
    }

    // ---------------------------------------------------------------------------------
    // Value pools
    // ---------------------------------------------------------------------------------

    static float[] specialFloats() {
        float[] base = {
            0f, 1f, 0.5f, 2f, 3f, 0.1f, 0.3f, 0.7f, 1f / 3f, 2f / 3f, 16f / 9f, 0.001f, 0.0001f,
            Float.MIN_VALUE, 2 * Float.MIN_VALUE, 3 * Float.MIN_VALUE, Float.MIN_NORMAL,
            Math.nextDown(Float.MIN_NORMAL), Math.nextUp(Float.MIN_NORMAL), Float.MAX_VALUE,
            Math.nextDown(Float.MAX_VALUE), Float.POSITIVE_INFINITY, 16777216f, 16777218f,
            8388608.5f, Math.nextUp(1f), Math.nextDown(1f), Math.nextDown(0.5f), 1e-20f, 1e20f,
            360f, 90f, 30f, 450f, 720f, 180f, 0x1p-75f, 0x1.8p-75f, 0x1p64f, 0x1p-64f, 9f, 100f,
            1000f, 1e7f, 12.5f, 6.5f, 7f, 2147483520f, 2147483648f, 0x1p127f, 0x1p-126f, 0x1p-140f,
        };
        List<Float> l = new ArrayList<>();
        for (float f : base) {
            l.add(f);
            l.add(-f);
        }
        l.add(Float.NaN);
        l.add(Float.intBitsToFloat(0x7fc00001));
        l.add(Float.intBitsToFloat(0xffc00000));
        float[] out = new float[l.size()];
        for (int i = 0; i < out.length; i++) {
            out[i] = l.get(i);
        }
        return out;
    }

    /** Any float, NaN, infinities and subnormals included. */
    static float anyFloat() {
        return Float.intBitsToFloat(rnd.nextInt());
    }

    /** A finite float with an exponent in [lo, hi] and either sign. */
    static float floatInRange(int lo, int hi) {
        float m = 1f + (float) rnd.nextDouble();
        if (m >= 2f) {
            m = Math.nextDown(2f);
        }
        float f = Math.scalb(m, rnd.nextInt(lo, hi + 1));
        return rnd.nextBoolean() ? f : -f;
    }

    /** A pixel-like value: an integer, maybe with a binary or random fraction. */
    static float pixel() {
        float base = rnd.nextInt(-5000, 5001);
        switch (rnd.nextInt(6)) {
            case 0:
                return base;
            case 1:
                return base + 0.5f;
            case 2:
                return base + 0.25f;
            case 3:
                return base + (float) rnd.nextDouble();
            case 4:
                return base * (float) rnd.nextDouble();
            default:
                return (float) rnd.nextDouble();
        }
    }

    /** A float from one of the pools, chosen at random. */
    static float mixedFloat() {
        switch (rnd.nextInt(5)) {
            case 0:
                return anyFloat();
            case 1:
                return floatInRange(-149, 127);
            case 2:
                return floatInRange(-30, 30);
            case 3:
                return pixel();
            default: {
                float[] s = SPECIAL;
                return s[rnd.nextInt(s.length)];
            }
        }
    }

    static float[] SPECIAL;

    // ---------------------------------------------------------------------------------
    // f32: (float) d
    // ---------------------------------------------------------------------------------

    static String f32v(double d) {
        return "[" + dh(d) + "," + fh((float) d) + "]";
    }

    static Set genF32() {
        Set s = new Set();
        double[] base = {
            0.0, 1.0, 0.5, 0.001, 0.0001, 0.1, 0.3, 0.7, 1.0 / 3, 2.0 / 3, 16.0 / 9, Math.PI, Math.E,
            1e-40, 1e-45, 1e-46, 1e38, 1e39, Double.MAX_VALUE, Double.MIN_VALUE, Double.MIN_NORMAL,
            Float.MAX_VALUE, (double) Float.MAX_VALUE + Math.ulp(Float.MAX_VALUE) / 2,
            Math.nextDown((double) Float.MAX_VALUE + Math.ulp(Float.MAX_VALUE) / 2),
            Math.nextUp((double) Float.MAX_VALUE + Math.ulp(Float.MAX_VALUE) / 2), 0x1p128,
            Float.MIN_VALUE, 0x1p-150, Math.nextUp(0x1p-150), Math.nextDown(0x1p-150), 3 * 0x1p-150,
            5 * 0x1p-150, Float.MIN_NORMAL, Float.MIN_NORMAL - 0x1p-150,
            Math.nextUp(Float.MIN_NORMAL - 0x1p-150), Math.nextDown(Float.MIN_NORMAL - 0x1p-150),
            Double.POSITIVE_INFINITY, 2147483647.0, 2147483648.0, 16777217.0, 16777219.0,
            0.49999998, 0.4999999701976776,
        };
        for (double d : base) {
            s.edges.add(f32v(d));
            s.edges.add(f32v(-d));
        }
        long[] nans = {0x7ff8000000000000L, 0x7ff0000000000001L, 0x7ff8000000000001L,
            0xfff8000000000000L, 0x7fffffffffffffffL};
        for (long n : nans) {
            s.edges.add(f32v(Double.longBitsToDouble(n)));
        }
        // Midpoints between neighbouring floats, and one double ulp to either side.
        for (int i = 0; i < 600; i++) {
            float f = Math.abs(i % 3 == 0 ? floatInRange(-149, 126) : floatInRange(-30, 30));
            if (Float.isInfinite(Math.nextUp(f))) {
                continue;
            }
            double mid = ((double) f + (double) Math.nextUp(f)) / 2;
            for (double d : new double[] {mid, Math.nextUp(mid), Math.nextDown(mid)}) {
                s.edges.add(f32v(d));
                s.edges.add(f32v(-d));
            }
        }
        // Subnormal midpoints.
        for (int k = 0; k < 64; k++) {
            double mid = (2 * k + 1) * 0x1p-150;
            s.edges.add(f32v(mid));
            s.edges.add(f32v(Math.nextUp(mid)));
            s.edges.add(f32v(Math.nextDown(mid)));
        }
        s.fillRandom(() -> {
            double d;
            switch (rnd.nextInt(4)) {
                case 0:
                    d = Double.longBitsToDouble(rnd.nextLong());
                    break;
                case 1:
                    d = Math.scalb(1 + rnd.nextDouble(), rnd.nextInt(-160, 131));
                    break;
                case 2: {
                    float f = Math.abs(floatInRange(-149, 126));
                    double mid = ((double) f + (double) Math.nextUp(f)) / 2;
                    d = mid + rnd.nextInt(-3, 4) * Math.ulp(mid);
                    break;
                }
                default:
                    d = rnd.nextDouble() * 10000 - 5000;
                    break;
            }
            if (rnd.nextBoolean()) {
                d = -d;
            }
            s.random.add(f32v(d));
        });
        return s;
    }

    // ---------------------------------------------------------------------------------
    // fadd fsub fmul fdiv jfrem: a op b on floats
    // ---------------------------------------------------------------------------------

    interface FloatOp {
        float apply(float a, float b);
    }

    static String binv(float a, float b, FloatOp op) {
        return "[" + fh(a) + "," + fh(b) + "," + fh(op.apply(a, b)) + "]";
    }

    static Set genBinary(String name, FloatOp op) {
        Set s = new Set();
        for (float a : SPECIAL) {
            for (float b : SPECIAL) {
                s.edges.add(binv(a, b, op));
            }
        }
        if (name.equals("fadd") || name.equals("fsub")) {
            // Sums at a midpoint, just off one, and across wide exponent gaps.
            for (int i = 0; i < 1500; i++) {
                float a = Math.abs(floatInRange(-100, 100));
                float u = Math.ulp(a);
                float[] bs = {u / 2, Math.nextUp(u / 2), Math.nextDown(u / 2), 1.5f * u, 2.5f * u,
                    Math.scalb(a, -rnd.nextInt(20, 64)), Math.scalb(floatInRange(0, 0), -rnd.nextInt(20, 64))};
                for (float b : bs) {
                    float bb = name.equals("fsub") ? -b : b;
                    s.edges.add(binv(a, bb, op));
                    s.edges.add(binv(-a, -bb, op));
                }
            }
        }
        if (name.equals("fmul")) {
            // Products of two 13-bit odd significands: 25 or 26 significant bits, many at a
            // midpoint; some scaled into the subnormal range.
            for (int i = 0; i < 4000; i++) {
                int m1 = rnd.nextInt(4096, 8192) | 1;
                int m2 = rnd.nextInt(4096, 8192) | 1;
                int e1 = i % 4 == 0 ? rnd.nextInt(-90, -60) : rnd.nextInt(-40, 20);
                int e2 = i % 4 == 0 ? rnd.nextInt(-90, -60) : rnd.nextInt(-40, 20);
                float a = Math.scalb((float) m1, e1);
                float b = Math.scalb((float) m2, e2);
                s.edges.add(binv(rnd.nextBoolean() ? a : -a, b, op));
            }
        }
        if (name.equals("fdiv")) {
            // Exact quotients and quotients near a midpoint's neighbourhood.
            for (int i = 0; i < 1500; i++) {
                float q = floatInRange(-20, 20);
                float b = floatInRange(-20, 20);
                float a = q * b;
                s.edges.add(binv(a, b, op));
                s.edges.add(binv(Math.nextUp(a), b, op));
                s.edges.add(binv(Math.nextDown(a), b, op));
            }
        }
        if (name.equals("jfrem")) {
            // Angles, huge quotients, negative dividends, exact multiples.
            float[] angles = {-1080f, -720f, -450f, -360f, -270f, -90f, -30f, -0.5f, 0f, 30f, 90f,
                359.5f, 360f, 360.5f, 450f, 720f, 1e9f};
            for (float a : angles) {
                s.edges.add(binv(a, 360f, op));
                s.edges.add(binv(a, -360f, op));
            }
            for (int i = 0; i < 1500; i++) {
                float b = floatInRange(-20, 20);
                s.edges.add(binv(floatInRange(60, 127), b, op));
                s.edges.add(binv(b * rnd.nextInt(-1000, 1000), b, op));
                s.edges.add(binv(floatInRange(-149, -100), floatInRange(-149, -120), op));
            }
        }
        s.fillRandom(() -> {
            float a;
            float b;
            switch (rnd.nextInt(6)) {
                case 0:
                    a = anyFloat();
                    b = anyFloat();
                    break;
                case 1:
                    a = floatInRange(-30, 30);
                    b = floatInRange(-30, 30);
                    break;
                case 2:
                    a = pixel();
                    b = name.equals("jfrem") ? 360f : (float) rnd.nextDouble();
                    break;
                case 3:
                    a = pixel();
                    b = pixel();
                    break;
                case 4: {
                    a = floatInRange(-60, 60);
                    float r = 1f + (float) (rnd.nextDouble() * Math.scalb(1.0, -rnd.nextInt(0, 30)));
                    b = a * r;
                    break;
                }
                default:
                    a = mixedFloat();
                    b = mixedFloat();
                    break;
            }
            s.random.add(binv(a, b, op));
        });
        return s;
    }

    // ---------------------------------------------------------------------------------
    // fi: (float) v for an int or a long
    // ---------------------------------------------------------------------------------

    static String fiv(long v) {
        return "[\"" + v + "\"," + fh((float) v) + "]";
    }

    static Set genFi() {
        Set s = new Set();
        long[] base = {0, 1, 2, 3, 7, 100, 1000, 16777215, 16777216, 16777217, 16777218, 16777219,
            33554431, 33554433, 33554434, 33554435, 33554438, Integer.MAX_VALUE,
            Integer.MAX_VALUE - 1L, Integer.MAX_VALUE - 63L, Integer.MAX_VALUE - 64L,
            Integer.MAX_VALUE - 127L, Integer.MAX_VALUE - 128L, Integer.MAX_VALUE - 129L,
            Long.MAX_VALUE, Long.MAX_VALUE - 1, (1L << 53) + 1, (1L << 53) - 1, 1L << 53,
            (1L << 60) + (1L << 36) + 1, (1L << 60) + (1L << 36), (1L << 60) + (1L << 36) - 1};
        for (long v : base) {
            s.edges.add(fiv(v));
            s.edges.add(fiv(-v));
        }
        s.edges.add(fiv(Integer.MIN_VALUE));
        s.edges.add(fiv(Integer.MIN_VALUE + 1L));
        s.edges.add(fiv(Long.MIN_VALUE));
        s.edges.add(fiv(Long.MIN_VALUE + 1));
        for (int k = 24; k <= 62; k++) {
            long p = 1L << k;
            long half = 1L << (k - 24); // half a float ulp above 2^k
            long[] around = {p, p + 1, p - 1, p + half, p + half + 1, p + half - 1, p + 3 * half,
                p + 3 * half - 1, p + 3 * half + 1, p + 2 * half};
            for (long v : around) {
                s.edges.add(fiv(v));
                s.edges.add(fiv(-v));
            }
        }
        s.fillRandom(() -> {
            long v;
            switch (rnd.nextInt(5)) {
                case 0:
                    v = rnd.nextInt();
                    break;
                case 1:
                    v = rnd.nextInt() >> rnd.nextInt(32);
                    break;
                case 2:
                    v = rnd.nextLong();
                    break;
                case 3:
                    v = rnd.nextLong() >> rnd.nextInt(64);
                    break;
                default:
                    v = rnd.nextInt(-10000, 10001);
                    break;
            }
            s.random.add(fiv(v));
        });
        return s;
    }

    // ---------------------------------------------------------------------------------
    // jint: (int) d for a float or a double
    // ---------------------------------------------------------------------------------

    static String jintv(double d) {
        return "[" + dh(d) + "," + (int) d + "]";
    }

    static Set genJint() {
        Set s = new Set();
        double[] base = {0.0, 0.4, 0.5, 0.6, 0.9999999, 1.0, 1.5, 2.5, 6.5, 7.0, 6.6, 0.1,
            2147483647.0, 2147483646.5, 2147483647.5, 2147483648.0, 2147483520.0, 2147483648.5,
            2147483649.0, 1e10, 1e300, Double.MAX_VALUE, Double.MIN_VALUE, Float.MIN_VALUE,
            Float.MAX_VALUE, Math.nextDown(0.5f), Math.nextDown(2147483648.0),
            Math.nextUp(2147483647.0), Math.nextDown(2147483647.0), Double.POSITIVE_INFINITY,
            Math.nextDown(1.0), Math.nextUp(1.0), 4503599627370496.5, 1e19};
        for (double d : base) {
            s.edges.add(jintv(d));
            s.edges.add(jintv(-d));
        }
        s.edges.add(jintv(Double.NaN));
        s.edges.add(jintv(Double.longBitsToDouble(0xfff8000000000001L)));
        s.edges.add(jintv(-2147483648.0));
        s.edges.add(jintv(-2147483648.5));
        s.edges.add(jintv(-2147483647.5));
        s.edges.add(jintv(-2147483649.0));
        s.edges.add(jintv(Math.nextUp(-2147483648.0)));
        s.edges.add(jintv(Math.nextDown(-2147483648.0)));
        for (float f : SPECIAL) {
            s.edges.add(jintv(f));
        }
        s.fillRandom(() -> {
            double d;
            switch (rnd.nextInt(5)) {
                case 0:
                    d = Double.longBitsToDouble(rnd.nextLong());
                    break;
                case 1:
                    d = anyFloat();
                    break;
                case 2:
                    d = (rnd.nextDouble() * 2 - 1) * 3e9;
                    break;
                case 3:
                    d = pixel();
                    break;
                default:
                    d = (float) ((rnd.nextDouble() * 2 - 1) * 3e9);
                    break;
            }
            s.random.add(jintv(d));
        });
        return s;
    }

    // ---------------------------------------------------------------------------------
    // toRadians: Math.toRadians(d)
    // ---------------------------------------------------------------------------------

    static String radv(double d) {
        return "[" + dh(d) + "," + dh(Math.toRadians(d)) + "]";
    }

    static Set genToRadians() {
        Set s = new Set();
        for (int a = -720; a <= 1080; a++) {
            s.edges.add(radv(a));
            s.edges.add(radv(a + 0.5f));
        }
        double[] base = {0.0, Double.NaN, Double.POSITIVE_INFINITY, Double.MAX_VALUE,
            Double.MIN_VALUE, 1e-300, 1e300, Float.MAX_VALUE, Float.MIN_VALUE};
        for (double d : base) {
            s.edges.add(radv(d));
            s.edges.add(radv(-d));
        }
        s.fillRandom(() -> {
            double d;
            switch (rnd.nextInt(4)) {
                case 0:
                    // A float angle plus 90f, widened, as a circle constraint computes it.
                    d = (float) ((rnd.nextDouble() * 2 - 1) * 10000) + 90f;
                    break;
                case 1:
                    d = Double.longBitsToDouble(rnd.nextLong());
                    break;
                case 2:
                    d = (rnd.nextDouble() * 2 - 1) * 1e6;
                    break;
                default:
                    d = anyFloat();
                    break;
            }
            s.random.add(radv(d));
        });
        return s;
    }

    // ---------------------------------------------------------------------------------
    // parseFloat32: Float.parseFloat(s)
    // ---------------------------------------------------------------------------------

    static String parsev(String str) {
        String expected;
        try {
            expected = fh(Float.parseFloat(str));
        } catch (NumberFormatException e) {
            expected = "null";
        }
        return "[" + js(str) + "," + expected + "]";
    }

    static String digits(int n) {
        StringBuilder b = new StringBuilder(n);
        for (int i = 0; i < n; i++) {
            b.append((char) ('0' + rnd.nextInt(10)));
        }
        return b.toString();
    }

    static String hexDigits(int n) {
        StringBuilder b = new StringBuilder(n);
        for (int i = 0; i < n; i++) {
            b.append("0123456789abcdefABCDEF".charAt(rnd.nextInt(22)));
        }
        return b.toString();
    }

    static String randomDecimal() {
        StringBuilder b = new StringBuilder();
        int sign = rnd.nextInt(10);
        if (sign == 0) {
            b.append('-');
        } else if (sign == 1) {
            b.append('+');
        }
        int intLen = rnd.nextInt(0, 12);
        int fracLen = rnd.nextInt(0, 12);
        if (intLen + fracLen == 0) {
            intLen = 1;
        }
        if (rnd.nextInt(8) == 0) {
            b.append("000", 0, rnd.nextInt(1, 4));
        }
        b.append(digits(intLen));
        if (fracLen > 0 || rnd.nextInt(4) == 0) {
            b.append('.').append(digits(fracLen));
        }
        if (rnd.nextInt(3) == 0) {
            b.append(rnd.nextBoolean() ? 'e' : 'E');
            int es = rnd.nextInt(3);
            if (es == 0) {
                b.append('-');
            } else if (es == 1) {
                b.append('+');
            }
            b.append(rnd.nextInt(0, 50));
        }
        if (rnd.nextInt(10) == 0) {
            b.append("fFdD".charAt(rnd.nextInt(4)));
        }
        return b.toString();
    }

    static String randomHex() {
        StringBuilder b = new StringBuilder();
        if (rnd.nextInt(6) == 0) {
            b.append(rnd.nextBoolean() ? '-' : '+');
        }
        b.append(rnd.nextBoolean() ? "0x" : "0X");
        int intLen = rnd.nextInt(0, 9);
        int fracLen = rnd.nextInt(0, 12);
        if (intLen + fracLen == 0) {
            intLen = 1;
        }
        b.append(hexDigits(intLen));
        if (fracLen > 0 || rnd.nextInt(4) == 0) {
            b.append('.').append(hexDigits(fracLen));
        }
        b.append(rnd.nextBoolean() ? 'p' : 'P');
        int es = rnd.nextInt(3);
        if (es == 0) {
            b.append('-');
        } else if (es == 1) {
            b.append('+');
        }
        b.append(rnd.nextInt(0, 160));
        if (rnd.nextInt(8) == 0) {
            b.append("fFdD".charAt(rnd.nextInt(4)));
        }
        return b.toString();
    }

    /** A random short string over the characters of the grammar (valid or not). */
    static String randomNoise() {
        String alphabet = "0123456789.eE+-fFdDxXpPaAbBNnIiaty \t";
        int n = rnd.nextInt(0, 9);
        StringBuilder b = new StringBuilder(n);
        for (int i = 0; i < n; i++) {
            b.append(alphabet.charAt(rnd.nextInt(alphabet.length())));
        }
        return b.toString();
    }

    static final char[] PADS = {' ', '\t', '\n', '\r', '\u0000', '\u001f', '\u000b', ' ',
        ' ', '　'};

    static String pad(String s) {
        StringBuilder b = new StringBuilder();
        int lead = rnd.nextInt(0, 3);
        for (int i = 0; i < lead; i++) {
            b.append(PADS[rnd.nextInt(PADS.length)]);
        }
        b.append(s);
        int trail = rnd.nextInt(0, 3);
        for (int i = 0; i < trail; i++) {
            b.append(PADS[rnd.nextInt(PADS.length)]);
        }
        return b.toString();
    }

    /** The exact midpoint above f, in decimal. */
    static BigDecimal midAbove(float f) {
        return new BigDecimal(f).add(new BigDecimal(Math.nextUp(f))).divide(BigDecimal.valueOf(2));
    }

    /** A decimal 10^-(scale + extra): far below the value's last digit. */
    static BigDecimal tiny(BigDecimal v, int extra) {
        return BigDecimal.ONE.scaleByPowerOfTen(-(Math.max(v.scale(), 0) + extra));
    }

    static void midpointStrings(List<String> out, float f) {
        BigDecimal mid = midAbove(f);
        BigDecimal t = tiny(mid, 5 + rnd.nextInt(0, 40));
        out.add(mid.toString());
        out.add(mid.toPlainString());
        out.add(mid.add(t).toString());
        out.add(mid.subtract(t).toString());
        out.add(mid.add(t).toPlainString());
        out.add(mid.subtract(t).toPlainString());
    }

    static Set genParse() {
        Set s = new Set();
        List<String> e = new ArrayList<>();
        String[] ratio = {"16", "9", "4", "3", "21", "1", "2", "2.35", "1.85", "1.33", "0.5", "1.0",
            "16.0", "9.0", ".5", "5.", " 16", "16 ", "\t9", "+16", "-16", "1e2", "1E-2", "1.5f",
            "2d", "1.7777778", "1.7777777777777777", "0.5625", "0.75", "1.3333334",
            "1.33333333333", "3.14159", "W", "H", "w", "h", "16:9", "1:1", "W,16:9", "H,1:2", "1,5",
            "1_0", "1..5", "", " ", "0", "-0", "0.0", "00", "-0.0", "1/2", "½", "١٦",
            "16px", "16dp", "auto", "NaN", "Infinity", "-Infinity", "+Infinity", "+NaN", "-NaN",
            "0x10", "0x1p4", "0x1.8p1", "1e", "1e+", "1e-", "e5", ".e5", ".", "+", "-", "--1",
            "+-1", "1.2.3", "1e1.5", "1f5", "1ff", "1fd", "1e5f", "1e5d", "1E+5D", "Inf", "inf",
            "nan", "NAN", "infinity", "Infinityf", "NaNf", "NaN ", " NaN", "\u0000NaN",
            "\u0000 16 \u001f", " 16", "16 ", " 16", "1 2", "0x", "0x1", "0xp1",
            "0x.p1", "0x1.p1", "0x.1p1", "0X1P1", "0x1p", "0x1p+", "0x1p1e", "0x1p1f", "0x1p1d",
            "0x1p1fd", "00x1p1", "-0x1p1", "+0x1.8p1", "0x0p0", "-0x0p0", "0x0.0p0",
            "0x0p99999999999", "0x1p2147483647", "0x1p2147483648", "0x1p-2147483648",
            "0x1p-2147483649", "0x1p-149", "0x1p-150", "0x1.000001p-150", "0x1.8p-150",
            "0x1.fffffep127", "0x1.ffffffp127", "0x1.fffffefp127", "0x1.fffffe8p127", "0x1p128",
            "0x1.000001p0", "0x1.000003p0", "0x1.0000011p0", "0x1.0000010000000000001p0",
            "0x0.000002p-126", "0x0.000001p-126", "0x0.0000008p-126", "0x0.0000018p-126",
            "0x00000000000000000001p0", "0x.0000000000000000000000000001p100",
            "3.4028235e38", "3.4028236e38", "-3.4028236e38", "3.4028234e38", "3.402823e38",
            "3.40282346638528859811704183484516925440e38", "1e38", "1e39", "1e40", "1.4e-45",
            "1.401298464324817e-45", "7.006492321624085e-46", "7.006492321624086e-46", "1e-46",
            "1e-45", "2e-45", "1e-50", "0.0000000000000000000000000000000000000000000014",
            "1e400", "1e-400", "1e2147483647", "1e2147483648", "1e-2147483648", "1e99999999999",
            "-1e99999999999", "0e99999999999", "0.0e-999999", "1e000000000000000000000001",
            "0.001", "0.0001", "0.1", "0.2", "0.3", "0.7", "1.1", "1.17549435e-38",
            "1.1754942e-38", "1.17549424e-38", "8388608.5", "16777217", "16777219", "33554433",
            "2147483647", "2147483648", "9007199254740993", "1.00000017881393432617187499",
            "1.000000178813934326171875", "1.00000017881393432617187501"};
        for (String r : ratio) {
            e.add(r);
        }
        // Exact boundary values around overflow and underflow.
        BigDecimal max = new BigDecimal(Float.MAX_VALUE);
        BigDecimal halfUlpMax = new BigDecimal(Math.ulp(Float.MAX_VALUE)).divide(BigDecimal.valueOf(2));
        BigDecimal top = max.add(halfUlpMax);
        e.add(top.toString());
        e.add(top.toPlainString());
        e.add(top.subtract(tiny(top, 5)).toPlainString());
        e.add(top.add(tiny(top, 5)).toPlainString());
        BigDecimal bottom = new BigDecimal(0x1p-150);
        e.add(bottom.toString());
        e.add(bottom.toPlainString());
        e.add(bottom.add(tiny(bottom, 5)).toString());
        e.add(bottom.subtract(tiny(bottom, 5)).toString());
        BigDecimal threeHalf = new BigDecimal(3 * 0x1p-150);
        e.add(threeHalf.toString());
        e.add(threeHalf.subtract(tiny(threeHalf, 7)).toString());
        BigDecimal subTop = new BigDecimal(Float.MIN_NORMAL).subtract(new BigDecimal(0x1p-150));
        e.add(subTop.toString());
        e.add(subTop.subtract(tiny(subTop, 9)).toString());
        // Midpoints between neighbouring floats: exact, a hair above, a hair below. Parsing
        // through a double rounds the hair away and then breaks the tie: these catch that.
        for (int i = 0; i < 1200; i++) {
            float f = Math.abs(i % 4 == 0 ? floatInRange(-149, 126) : floatInRange(-30, 30));
            if (Float.isInfinite(Math.nextUp(f))) {
                continue;
            }
            midpointStrings(e, f);
        }
        // More than 200 significant digits (Java keeps 200 and a sticky digit).
        for (int i = 0; i < 300; i++) {
            float f = Math.abs(floatInRange(-149, 126));
            BigDecimal mid = midAbove(f);
            String plain = mid.toPlainString();
            if (!plain.contains(".")) {
                plain = plain + ".";
            }
            StringBuilder zeros = new StringBuilder();
            for (int z = 0; z < 220; z++) {
                zeros.append('0');
            }
            e.add(plain + zeros);
            e.add(plain + zeros + "1");
            e.add(digits(rnd.nextInt(201, 320)) + "e" + rnd.nextInt(-400, -150));
            e.add("0." + digits(rnd.nextInt(201, 320)) + "e" + rnd.nextInt(-40, 40));
        }
        // Float.toString round trips, Float and Double hex strings.
        for (float f : SPECIAL) {
            e.add(Float.toString(f));
            if (!Float.isNaN(f) && !Float.isInfinite(f)) {
                e.add(Float.toHexString(f));
                e.add(new BigDecimal(f).toString());
            }
        }
        s.edges.addAll(e.stream().map(JFloatVectors::parsev).toList());
        s.fillRandom(() -> {
            String str;
            switch (rnd.nextInt(10)) {
                case 0:
                    str = Float.toString(floatInRange(-149, 127));
                    break;
                case 1:
                    str = Double.toString(Math.scalb(1 + rnd.nextDouble(), rnd.nextInt(-155, 130))
                            * (rnd.nextBoolean() ? 1 : -1));
                    break;
                case 2: {
                    List<String> l = new ArrayList<>();
                    float f = Math.abs(floatInRange(-149, 126));
                    if (Float.isInfinite(Math.nextUp(f))) {
                        f = 1f;
                    }
                    midpointStrings(l, f);
                    str = l.get(rnd.nextInt(l.size()));
                    break;
                }
                case 3:
                case 4:
                    str = randomDecimal();
                    break;
                case 5:
                    str = randomHex();
                    break;
                case 6:
                    str = rnd.nextBoolean() ? Float.toHexString(anyFloat())
                            : Double.toHexString(Double.longBitsToDouble(rnd.nextLong()));
                    break;
                case 7:
                    str = randomNoise();
                    break;
                case 8:
                    str = pad(rnd.nextBoolean() ? randomDecimal() : Float.toString(pixel()));
                    break;
                default:
                    str = new BigDecimal(Math.scalb(1 + rnd.nextDouble(), rnd.nextInt(-160, 130)))
                            .round(new java.math.MathContext(rnd.nextInt(1, 40))).toString();
                    break;
            }
            s.random.add(parsev(str));
        });
        return s;
    }

    // ---------------------------------------------------------------------------------
    // Output
    // ---------------------------------------------------------------------------------

    static List<String> select(Set s, int count) {
        List<String> out = new ArrayList<>();
        int fromEdges = Math.min(s.edges.size(), count / 2);
        for (int i = 0; i < fromEdges; i++) {
            out.add(s.edges.get((int) ((long) i * s.edges.size() / fromEdges)));
        }
        int fromRandom = Math.min(count - fromEdges, s.random.size());
        for (int i = 0; i < fromRandom; i++) {
            out.add(s.random.get((int) ((long) i * s.random.size() / fromRandom)));
        }
        return out;
    }

    public static void main(String[] args) throws IOException {
        if (args.length < 1) {
            System.err.println("usage: JFloatVectors <outDir> [perPrimitive] [seed] [select]");
            System.exit(2);
        }
        Path out = Paths.get(args[0]);
        perPrimitive = args.length > 1 ? Integer.parseInt(args[1]) : 100000;
        long seed = args.length > 2 ? Long.parseLong(args[2]) : 20261025L;
        int select = args.length > 3 ? Integer.parseInt(args[3]) : 2000;
        Files.createDirectories(out);
        Map<String, Set> sets = new LinkedHashMap<>();
        for (String name : PRIMITIVES) {
            // One stream per primitive, so changing one generator leaves the others as they are.
            rnd = new SplittableRandom(seed ^ name.hashCode());
            SPECIAL = specialFloats();
            Set s;
            switch (name) {
                case "f32":
                    s = genF32();
                    break;
                case "fadd":
                    s = genBinary(name, (a, b) -> a + b);
                    break;
                case "fsub":
                    s = genBinary(name, (a, b) -> a - b);
                    break;
                case "fmul":
                    s = genBinary(name, (a, b) -> a * b);
                    break;
                case "fdiv":
                    s = genBinary(name, (a, b) -> a / b);
                    break;
                case "jfrem":
                    s = genBinary(name, (a, b) -> a % b);
                    break;
                case "fi":
                    s = genFi();
                    break;
                case "jint":
                    s = genJint();
                    break;
                case "toRadians":
                    s = genToRadians();
                    break;
                default:
                    s = genParse();
                    break;
            }
            sets.put(name, s);
            try (BufferedWriter w = Files.newBufferedWriter(out.resolve(name + ".jsonl"),
                    StandardCharsets.UTF_8)) {
                for (String v : s.edges) {
                    w.write(v);
                    w.write('\n');
                }
                for (String v : s.random) {
                    w.write(v);
                    w.write('\n');
                }
            }
            Files.writeString(out.resolve(name + ".edges"), s.edges.size() + "\n");
            System.out.println(name + ": " + (s.edges.size() + s.random.size()) + " vectors ("
                    + s.edges.size() + " edge cases)");
        }
        try (BufferedWriter w = Files.newBufferedWriter(out.resolve("jfloat_vectors.json"),
                StandardCharsets.UTF_8)) {
            w.write("{\n");
            w.write("  \"generator\": \"JFloatVectors.java (Phase 1, p1-setup)\",\n");
            w.write("  \"java\": " + js(System.getProperty("java.vendor") + " "
                    + System.getProperty("java.version")) + ",\n");
            w.write("  \"seed\": " + seed + ",\n");
            w.write("  \"perPrimitive\": " + select + ",\n");
            w.write("  \"generatedFrom\": " + perPrimitive + ",\n");
            int p = 0;
            for (Map.Entry<String, Set> en : sets.entrySet()) {
                List<String> sel = select(en.getValue(), select);
                w.write("  \"" + en.getKey() + "\": [\n");
                for (int i = 0; i < sel.size(); i++) {
                    w.write("    " + sel.get(i) + (i + 1 < sel.size() ? ",\n" : "\n"));
                }
                w.write(++p < sets.size() ? "  ],\n" : "  ]\n");
            }
            w.write("}\n");
        }
        System.out.println("selection: " + select + " per primitive -> "
                + out.resolve("jfloat_vectors.json"));
    }
}
