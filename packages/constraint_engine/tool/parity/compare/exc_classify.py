#!/usr/bin/env python3
"""exc_classify: exception classification of a Dart run on the upstream pipeline
(vfuzz --path core0 or core257) on the A corpus against the pinned oracle at the same
level (gates/exc.sh runs it).

  exc_classify.py <dart.txt> --level 0|257 [--java A.java] [--java-levels 257,0]
                  [--nd A.mism.nd] [--detail exc0.J<level>.java] [--java-trace T]
                  [--dart-trace D] [--guard dart.txt.guard] [--out table.tsv]

<dart.txt> is a vfuzz file (`vfuzz --corpus <A ids> ... --path core<level>`): all of A,
or a subset such as exc0.in. Its status field is the Dart status: ok, ok-printed (the
solver loop caught and printed), EXC:<message> (thrown out of measure). Java's status at
the level comes from --java (a VOpDriver result file; its geometry column for --level
through --java-levels) and --nd (jbatch3.sh output: ND ids). --detail adds Java's passes
and printed exceptions with their top frame (the P<level> field of a -Dprobe run on the
repros). Defaults per level, in $CL_JAVA (gates/java_refs.sh writes them; default
$CL_PARITY_WORK/java):
  0    --java A.J0.java (levels 0), --detail exc0.J0.java, --java-trace exc0.J0.trace,
       no --nd (vcompare --nd excludes an id at every level; ND is a 257 notion)
  257  --java A.java (levels 257,0), --nd A.mism.nd (when it exists), --detail and
       --java-trace exc0.J257.{java,trace}

Classes (layouts ok on both sides are only counted):
  i     both print: Java's solver loop prints at the level and the Dart one catches too.
        With the Dart trace (--dart-trace: vtrace --path core<level> --level <level>),
        `same` when the Dart and Java blocks are identical up to and including Java's
        first X event (Java throws at the same operation: keep the swallow and the
        partial-state readback, Android's behaviour); otherwise the first diverging
        event. Frames must equal Java's.
  ii    the Dart side prints or throws, Java finishes without printing (or prints where
        the Dart side throws): fix as upstream behaves (trace-diff against TraceJava).
  iv    Java prints, the Dart side does not: the printed status differs, also a fix.
  iii   Java hangs (HANG), overflows (SO) or throws out of measure (JEXC, including the
        OutOfMemoryError of a runaway layout) at the level: outside the contract. The
        Dart status is reported (a Java SO should be a Dart guard trip that completes).
  ND    the id is ND at 257 (--nd): Android's own order decides; excluded, counted.
Guard trips (--guard, vfuzz's <out>.guard): every layout where the Dart guard fired
must be a Java SO at the level; a trip elsewhere is a failure (`guard-not-SO`).
Failures: ii, iv, i whose frames differ or whose trace diverges before Java's first X,
and guard trips outside Java SO. Exit status 1 when there is a failure, else 0.
"""
import os
import sys
from collections import Counter

J = os.environ.get("CL_JAVA") or os.path.join(
    os.environ.get("CL_PARITY_WORK")
    or os.path.join(os.environ.get("TMPDIR", "/tmp"), "cl_parity"), "java")
DEFAULTS = {
    "0": {"java": J + "/A.J0.java", "java_levels": "0", "nd": None,
          "detail": J + "/exc0.J0.java", "java_trace": J + "/exc0.J0.trace"},
    "257": {"java": J + "/A.java", "java_levels": "257,0",
            # Only when the ND run (gates/nd.sh) made one.
            "nd": J + "/A.mism.nd" if os.path.exists(J + "/A.mism.nd") else None,
            "detail": J + "/exc0.J257.java",
            "java_trace": J + "/exc0.J257.trace"},
}


def args(argv):
    o = {"files": [], "level": None, "java": None, "java_levels": None, "nd": None,
         "detail": None, "dart_trace": None, "java_trace": None, "guard": None, "out": None}
    keys = {"--level": "level", "--java": "java", "--java-levels": "java_levels",
            "--nd": "nd", "--detail": "detail", "--dart-trace": "dart_trace",
            "--java-trace": "java_trace", "--guard": "guard", "--out": "out"}
    i = 0
    while i < len(argv):
        a = argv[i]
        key = keys.get(a)
        if key:
            if i + 1 >= len(argv):
                sys.exit("exc_classify: %s needs a value" % a)
            o[key] = argv[i + 1]; i += 2
        elif a.startswith("--"):
            sys.exit("exc_classify: unknown option %s" % a)
        else:
            o["files"].append(a); i += 1
    if len(o["files"]) != 1 or o["level"] not in DEFAULTS:
        sys.exit(__doc__.split("\n\n")[1])
    for k, v in DEFAULTS[o["level"]].items():
        if o[k] is None:
            o[k] = v
    if o["dart_trace"] and not o["java_trace"]:
        sys.exit("exc_classify: --dart-trace needs --java-trace")
    return o


def split(g):
    """(status, body) of a geometry string."""
    if not g.startswith("!"):
        return "ok", g
    s, _, body = g[1:].partition(" | ")
    return s, body


def jclass(line_status, gstatus):
    if line_status == "ND":
        return "ND"
    if line_status == "HANG":
        return "HANG"
    if line_status.startswith("EXC") or gstatus.startswith("EXC"):
        return "JEXC"
    if gstatus == "SO":
        return "SO"
    return gstatus  # ok or ok-printed


def blocks(path, ids, level):
    """id -> list of events (T to E) for the ids wanted, build-0 blocks at [level]."""
    out, cur, key = {}, None, None
    with open(path) as f:
        for l in f:
            l = l.rstrip("\n")
            if l.startswith("T "):
                p = l.split(" ")
                key = p[1] if p[1] in ids and p[2:4] == [level, "0"] else None
                cur = [] if key else None
                if key:
                    out[key] = cur
            if cur is not None:
                cur.append(l)
    return out


def main():
    o = args(sys.argv[1:])
    level = o["level"]
    li = o["java_levels"].split(",").index(level)
    dart = {}
    with open(o["files"][0]) as f:
        for l in f:
            p = l.rstrip("\n").split("\t")
            if len(p) < 6:
                continue
            _, body = split(p[4]) if p[4] != "-" else (p[3], "")
            dart[p[0]] = ("EXC" if p[3].startswith("EXC") else p[3], body, p[3])
    nd = set()
    if o["nd"]:
        with open(o["nd"]) as f:
            for l in f:
                p = l.rstrip("\n").split("\t")
                if len(p) > 1 and p[1] == "ND":
                    nd.add(p[0])
    java = {}
    with open(o["java"]) as f:
        for l in f:
            k = l[:l.find("\t")]
            if k not in dart:
                continue
            p = l.rstrip("\n").split("\t")
            g = p[2 + li] if len(p) > 2 + li else ""
            gs, body = split(g) if g else (p[1], "")
            java[k] = ("ND" if k in nd else jclass(p[1], gs), body)
    detail = {}
    try:
        with open(o["detail"]) as f:
            tag = "P%s " % level
            for l in f:
                p = l.rstrip("\n").split("\t")
                for x in p:
                    if x.startswith(tag):
                        kv = x[len(tag):]
                        passes = kv.split("passes=", 1)[1].split(" ", 1)[0] if "passes=" in kv else "?"
                        excs = kv.split("excs=", 1)[1] if "excs=" in kv else ""
                        detail[p[0]] = (passes, excs)
    except (OSError, TypeError):
        pass
    guard = {}
    if o["guard"]:
        with open(o["guard"]) as f:
            for l in f:
                p = l.rstrip("\n").split("\t")
                if len(p) == 2:
                    guard[p[0]] = int(p[1])
    rows, counts, fails = [], Counter(), []
    iii = Counter()
    for i, (ds, dbody, draw) in dart.items():
        js, jbody = java.get(i, ("missing", ""))
        if js == "ND":
            cls = "ND"
        elif js in ("HANG", "SO", "JEXC"):
            cls = "iii"
            iii["%s/dart %s%s" % (js, "EXC" if ds == "EXC" else ds,
                                  "+guard" if i in guard else "")] += 1
        elif js == "missing":
            cls = "no-java"
        elif ds == "ok-printed" and js == "ok-printed":
            cls = "i"
        elif ds in ("ok-printed", "EXC") and js == "ok":
            cls = "ii"
        elif ds == "ok" and js == "ok-printed":
            cls = "iv"
        elif ds == "EXC" and js == "ok-printed":
            cls = "ii"
        else:
            counts["ok"] += 1
            if i in guard:
                counts["guard-not-SO"] += 1
                fails.append(i)
                rows.append([i, "guard-not-SO", draw if not draw.startswith("EXC") else "EXC",
                             js, "equal" if dbody == jbody else "differ"])
            continue
        counts[cls] += 1
        if i in guard and js != "SO":
            counts["guard-not-SO"] += 1
        frames = "-" if cls in ("iii", "ND") else ("equal" if dbody == jbody else "differ")
        rows.append([i, cls, draw if not draw.startswith("EXC") else "EXC", js, frames])
    # Traces: Java's first X, then the same-operation check (any pass: the Dart side runs
    # BasicMeasure's passes 1 and 2 since Phase 2).
    want = set(r[0] for r in rows if r[1] in ("i", "ii", "iv"))
    jb = blocks(o["java_trace"], want, level) if o["java_trace"] else {}
    db = blocks(o["dart_trace"], want, level) if o["dart_trace"] else {}
    trace = {}
    for r in rows:
        i = r[0]
        b = jb.get(i)
        xj = next((k for k, e in enumerate(b) if e.startswith("X ")), None) if b else None
        pass_x = sum(1 for e in b[:xj] if e.startswith("PS ")) - 1 if xj is not None else None
        if not o["dart_trace"] or r[1] in ("iii", "ND", "guard-not-SO"):
            trace[i] = "-" if xj is None else "Java's first X at event %d (pass %d)" % (xj, pass_x)
            continue
        a = db.get(i)
        if a is None or b is None:
            trace[i] = "no %s block" % ("Dart" if a is None else "Java")
            continue
        n = min(len(a), len(b))
        k = 0
        while k < n and a[k] == b[k]:
            k += 1
        if xj is None:
            trace[i] = "identical" if k == len(a) == len(b) else "diverges at event %d (Java prints no X)" % k
        elif k > xj:
            trace[i] = "same (first X at event %d, pass %d)" % (xj, pass_x)
        else:
            trace[i] = "diverges at event %d, before Java's first X at %d (pass %d)" % (k, xj, pass_x)
    for r in rows:
        i, cls = r[0], r[1]
        t = trace.get(i, "-")
        bad = (cls in ("ii", "iv", "guard-not-SO") or
               (cls == "i" and (r[4] == "differ" or t.startswith("diverges"))) or
               (i in guard and r[3] != "SO"))
        if bad and i not in fails:
            fails.append(i)
        passes, excs = detail.get(i, ("?", ""))
        first = excs.split(" | ", 1)[0] if excs else "-"
        r += [passes, guard.get(i, 0), t, first[:300], "FAIL" if bad else "-"]
    rows.sort(key=lambda r: (r[1], r[0]))
    head = ["id", "class", "dart", "java", "frames", "java_passes", "dart_guard_trips",
            "trace", "java_first_exception", "verdict"]
    if o["out"]:
        with open(o["out"], "w") as f:
            f.write("\t".join(head) + "\n")
            for r in rows:
                f.write("\t".join(str(x) for x in r) + "\n")
    print("exc_classify level %s: %d Dart layouts; classes %s; failures %d" % (
        level, len(dart), dict(sorted((k, v) for k, v in counts.items() if v)), len(fails)))
    if iii:
        print("  iii by Java status / Dart status: %s" % dict(sorted(iii.items())))
    for r in rows:
        if r[1] in ("iii", "ND"):
            continue
        print("  %-18s %-3s dart %-10s java %-10s frames %-6s passes %-2s %s%s" % (
            r[0], r[1], r[2], r[3], r[4], r[5], r[7] if r[7] != "-" else "",
            "  FAIL" if r[9] == "FAIL" else ""))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
