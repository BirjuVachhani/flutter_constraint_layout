#!/usr/bin/env python3
"""select_corpus: picks the layouts of engine_corpus.json from the parity corpora and
the pinned Java oracle's results (README.md in this directory).

  python3 -I select_corpus.py <out.json> [--seed 20261025] [--runs <parity runs dir>]
                             [--meta <out.tsv>]
  python3 -I select_corpus.py --export <corpus.json> <dir>   # <dir>/<path>.in per path
  python3 -I select_corpus.py --check <corpus.json> <dir>    # against <dir>/<path>.java

Each pool is one corpus on one path, with Java's status and geometry at one level:

  pool        path     corpus input            Java result (column)
  R           core257  p0/java/R.in            p0/gate/java/R.java (J257)
  VR2         view257  p1/java/VR2.in          p1/java/VR2.java (J257)
  T2          view257  p1/java/T2.in           p1/java/T2.java (J257; ND ids and
                                               the in-place sequences skipped)
  T2core      core257  p3/p3c/java/T2core.in   p3/p3c/java/T2core.J257d.java
  A           core257  p0/java/A.in            p0/gate/java/A.java (J257; ND, HANG, SO
                                               and EXC skipped; ok-printed kept)
  R0, A0      core0    as R and A              the J0 column
  VR20, T20   view0    as VR2 and T2           the J0 column

A layout's keys are its generator, its feature tags (the corpus line's second field),
and mechanism flags read from the oracle: `direct` (J257 differs from J0), `today`
(the geometry the engine's earlier graph-first design wrote into the corpus line
differs from Java's), `multipass` and `multiiter` (DirectProbe's passes and
iterations), `partial` and `complete` (Direct left some axis unresolved, or none),
`printed`, `toosmall`, `negpos` (a frame starts at a negative coordinate), `negsize`
(Direct gave a widget a negative size). Per pool, a
greedy cover picks layouts until every generator, every generator-and-tag pair and
every generator-and-flag pair is covered (several times for flags), preferring the
shorter op list; the rest of the pool's budget goes to short `direct` layouts, round
robin over the generators. Every layout that finishes with a printed exception
(`ok-printed`) is taken first. Candidates per key are the shortest ones plus a seeded
random sample, so the result is reproducible from the seed.
"""
import json
import os
import random
import re
import sys
from collections import defaultdict

BUDGET = {"R": 300, "VR2": 450, "T2": 550, "T2core": 150, "A": 350,
          "R0": 40, "A0": 60, "VR20": 50, "T20": 50}
NEED = {"gen": 6, "tag": 2, "mech": 3, "combo": 1}
WEIGHT = {"gen": 4.0, "tag": 1.0, "mech": 2.0, "combo": 0.5}


def args(argv):
    # The parity work's runs directory (README.md): --runs, else $CL_PARITY_RUNS.
    o = {"out": None, "seed": 20261025, "runs": os.environ.get("CL_PARITY_RUNS"), "meta": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--seed":
            o["seed"] = int(argv[i + 1]); i += 2
        elif a == "--runs":
            o["runs"] = argv[i + 1]; i += 2
        elif a == "--meta":
            o["meta"] = argv[i + 1]; i += 2
        elif a.startswith("--"):
            sys.exit("select_corpus: unknown option " + a)
        else:
            o["out"] = a; i += 1
    if not o["out"]:
        sys.exit(__doc__.split("\n\n")[1])
    if not o["runs"]:
        sys.exit("select_corpus: give the parity runs directory (--runs, or $CL_PARITY_RUNS)")
    return o


def gstatus(g):
    """(status, geometry) of a Java geometry field: ok unless it starts with `!s | `."""
    if g.startswith("!"):
        return g[1:].split(" | ", 1)[0], g
    return "ok", g


NEGPOS = re.compile(r": \((-\d+), |, (-\d+)\) ")


def mech_of(p_field, g257, g0, today, dump):
    m = set()
    if g0 is not None and g257 != g0:
        m.add("direct")
    if today is not None and today != g257:
        m.add("today")
    if p_field:
        kv = dict(x.split("=", 1) for x in p_field.split(" ")[1:] if "=" in x and not x.startswith("excs"))
        if kv.get("passes", "1") not in ("1", "-"):
            m.add("multipass")
        if any(x not in ("1", "-") for x in kv.get("it", "1").split(",")):
            m.add("multiiter")
        res = kv.get("res", "-")
        if "/" in res:
            a, n = res.split("/")
            m.add("complete" if a == n else "partial")
        if kv.get("exc", "0") != "0":
            m.add("printed")
        if kv.get("ts", "00") != "00":
            m.add("toosmall")
    if dump:
        body = dump.split(" ", 1)[1] if " " in dump else "-"
        if body != "-":
            ents = body.split(" ")
            if any(len(f) == 6 and "-" in f[3] for f in (e.split(":") for e in ents)):
                m.add("negsize")
            if not p_field:
                part = False
                for e in ents:
                    f = e.split(":")
                    if len(f) == 6 and "-" in f[1]:
                        part = True
                    elif len(f) == 4 and "-" in f[2]:
                        part = True
                    elif len(f) == 3 and f[2] == "_":
                        part = True
                m.add("partial" if part else "complete")
    if NEGPOS.search(g257):
        m.add("negpos")
    if g257.startswith("!ok-printed"):
        m.add("printed")
    return m


def read_nd(path):
    nd = set()
    try:
        for l in open(path):
            p = l.rstrip("\n").split("\t")
            if len(p) > 1 and p[1] == "ND":
                nd.add(p[0])
    except OSError:
        pass
    return nd


def field(p, prefix):
    return next((x for x in p[2:] if x.startswith(prefix)), None)


def load_pool(name, R, rng):
    """Candidates of one pool: dicts with id, gen, path, ops, status, geometry, keys."""
    spec = {
        "R": ("core257", R + "/p0/java/R.in", R + "/p0/gate/java/R.java", 0, R + "/p3/p3c/java/R.J257d.java", None),
        "VR2": ("view257", R + "/p1/java/VR2.in", R + "/p1/java/VR2.java", 0, R + "/p3/p3c/java/VR2.J257dt.java", None),
        "T2": ("view257", R + "/p1/java/T2.in", R + "/p1/java/T2.java", 0, R + "/p3/p3c/java/T2.J257dt.java", R + "/p1/java/T2.mism.nd"),
        "T2core": ("core257", R + "/p3/p3c/java/T2core.in", R + "/p3/p3c/java/T2core.J257d.java", 0, None, None),
        "A": ("core257", R + "/p0/java/A.in", R + "/p0/gate/java/A.java", 0, None, R + "/p0/gate/nd/A.mism.nd"),
        "R0": ("core0", R + "/p0/java/R.in", R + "/p0/gate/java/R.java", 1, None, None),
        "A0": ("core0", R + "/p0/java/A.in", R + "/p0/gate/java/A.java", 1, None, None),
        "VR20": ("view0", R + "/p1/java/VR2.in", R + "/p1/java/VR2.java", 1, None, None),
        "T20": ("view0", R + "/p1/java/T2.in", R + "/p1/java/T2.java", 1, None, None),
    }[name]
    path, fin, fjava, col, fdump, fnd = spec
    nd = read_nd(fnd) if fnd else set()
    level = "257" if col == 0 else "0"
    j0core = {}
    if name == "T2core":
        for l in open(R + "/p1/trace/work/T2core0.java"):
            p = l.rstrip("\n").split("\t")
            j0core[p[0]] = p[2] if len(p) > 2 else None
    out = []
    fd = open(fdump) if fdump else None
    with open(fin) as fi, open(fjava) as fj:
        for li, lj in zip(fi, fj):
            pd = None
            if fd is not None:
                pd = fd.readline().rstrip("\n").split("\t")
            pi = li.rstrip("\n").split("\t")
            pj = lj.rstrip("\n").split("\t")
            if pi[0] != pj[0] or (pd is not None and pd[0] != pi[0]):
                sys.exit("select_corpus: %s: id order differs at %s" % (name, pi[0]))
            lid = pi[0]
            gen = lid.rsplit(":", 1)[0]
            if lid in nd or pj[1] != "ok" or len(pj) < 3 + col:
                continue
            if name == "T2core":
                g = pj[2]
                g0 = j0core.get(lid)
            else:
                g = pj[2 + col]
                g0 = pj[3] if col == 0 and len(pj) > 3 else None
            if gen == "T2-inplace":
                # VOpDriver's mid-list L is the non-dirty re-measure, ViewHost's the
                # dirty path (FORMATS.md 17.1); every entry here must be VOpDriver's
                # own result on its op list, so the in-place sequences stay out.
                continue
            status, _ = gstatus(g)
            if status not in ("ok", "ok-printed"):
                continue
            if name in ("R", "VR2", "T2", "T2core", "R0", "VR20", "T20") and status != "ok":
                continue
            ops = pi[-1]
            pf = field(pj, "P%s " % level)
            dump = field(pd, "D257 ") if pd is not None else (field(pj, "D257 ") if name == "T2core" else None)
            today = pi[4] if len(pi) >= 6 and pi[2] == "graphfirst" else None
            if today is not None and today.startswith("!"):
                today = None
            mech = mech_of(pf, g, g0 if col == 0 else None, today if col == 0 else None, dump)
            tags = [t for t in pi[1].split(",") if t and t != "-"] if len(pi) >= 6 else []
            keys = {("gen", gen)}
            keys |= {("tag", gen + ":" + t) for t in tags}
            keys |= {("mech", gen + ":" + m) for m in mech}
            keys.add(("combo", gen + ":" + "+".join(sorted(mech))))
            out.append({"id": lid, "gen": gen, "path": path, "ops": ops, "status": status,
                        "geometry": g, "keys": keys, "mech": mech, "n": len(ops)})
    if fd is not None:
        fd.close()
    return out


def select(name, cands, budget, rng):
    # Sorted iteration everywhere: the keys are sets, whose order depends on the
    # process's string hash seed, and the random sample must not.
    by_key = defaultdict(list)
    for c in cands:
        for k in sorted(c["keys"]):
            by_key[k].append(c)
    pre = {}
    for k in sorted(by_key):
        lst = by_key[k]
        lst.sort(key=lambda c: (c["n"], c["id"]))
        for c in lst[:12]:
            pre[c["id"]] = c
        for c in rng.sample(lst, min(6, len(lst))):
            pre[c["id"]] = c
    pool = sorted(pre.values(), key=lambda c: (c["n"], c["id"]))
    have = defaultdict(int)
    chosen, chosen_ids = [], set()
    # Every layout whose solver loop prints (Java catches and prints an exception at
    # this level) is taken first: there are few (11 of A at 257, 13 at 0).
    for c in sorted(cands, key=lambda c: c["id"]):
        if c["status"] == "ok-printed" and len(chosen) < budget:
            chosen.append(c); chosen_ids.add(c["id"])
            for k in c["keys"]:
                have[k] += 1

    def gain(c):
        g = 0.0
        for k in c["keys"]:
            if have[k] < NEED[k[0]]:
                g += WEIGHT[k[0]]
        return g
    # Lazy greedy: a max-heap of stale gains.
    import heapq
    heap = [(-gain(c), c["n"], c["id"], c) for c in pool]
    heapq.heapify(heap)
    while heap and len(chosen) < budget:
        ng, n, cid, c = heapq.heappop(heap)
        if cid in chosen_ids:
            continue
        g = gain(c)
        if g <= 0:
            break
        if heap and -g > heap[0][0]:
            heapq.heappush(heap, (-g, n, cid, c))
            continue
        chosen.append(c); chosen_ids.add(cid)
        for k in c["keys"]:
            have[k] += 1
    # Fill: short `direct` layouts (then any), round robin over the generators.
    gens = sorted({c["gen"] for c in cands})
    rest = defaultdict(list)
    for c in sorted(cands, key=lambda c: (("direct" not in c["mech"]), c["n"], c["id"])):
        if c["id"] not in chosen_ids:
            rest[c["gen"]].append(c)
    while len(chosen) < budget and any(rest.values()):
        for g in gens:
            if rest[g] and len(chosen) < budget:
                c = rest[g].pop(0)
                chosen.append(c); chosen_ids.add(c["id"])
    return chosen


def export(json_path, outdir):
    """Writes VOpDriver batch inputs (`id \\t ops`) per path from the corpus file."""
    import os
    entries = json.load(open(json_path))
    files = {}
    for e in entries:
        f = files.get(e["path"])
        if f is None:
            f = files[e["path"]] = open(os.path.join(outdir, e["path"] + ".in"), "w")
        f.write("%s\t%s\n" % (e["id"], e["ops"]))
    for f in files.values():
        f.close()
    sys.stderr.write("select_corpus: exported %d entries to %s (%s)\n" % (
        len(entries), outdir, ", ".join(sorted(files))))


def check(json_path, outdir):
    """Compares VOpDriver's results (<outdir>/<path>.java, one level) with the corpus."""
    import os
    entries = json.load(open(json_path))
    java = {}
    for path in sorted({e["path"] for e in entries}):
        for l in open(os.path.join(outdir, path + ".java")):
            p = l.rstrip("\n").split("\t")
            java[(path, p[0])] = (p[1], p[2] if len(p) > 2 else "")
    bad = 0
    for e in entries:
        st, g = java.get((e["path"], e["id"]), ("missing", ""))
        status = gstatus(g)[0] if st == "ok" else st
        if status != e["status"] or g != e["geometry"]:
            bad += 1
            if bad <= 5:
                sys.stderr.write("  %s %s\n    corpus %s\n    java   %s\n" % (
                    e["path"], e["id"], e["geometry"], g))
    sys.stderr.write("select_corpus: %d entries checked against VOpDriver, %d differ\n" % (
        len(entries), bad))
    return 1 if bad else 0


def main():
    if len(sys.argv) == 4 and sys.argv[1] in ("--export", "--check"):
        sys.exit((export if sys.argv[1] == "--export" else check)(sys.argv[2], sys.argv[3]))
    o = args(sys.argv[1:])
    rng = random.Random(o["seed"])
    entries, meta = [], []
    for name in ("R", "VR2", "T2", "T2core", "A", "R0", "A0", "VR20", "T20"):
        cands = load_pool(name, o["runs"], rng)
        sel = select(name, cands, BUDGET[name], rng)
        sel.sort(key=lambda c: c["id"])
        sys.stderr.write("select_corpus: %-6s %7d candidates, %4d chosen, %d direct, ops %d chars\n" % (
            name, len(cands), len(sel), sum(1 for c in sel if "direct" in c["mech"]),
            sum(c["n"] for c in sel)))
        for c in sel:
            entries.append({"id": c["id"], "path": c["path"], "ops": c["ops"],
                            "status": c["status"], "geometry": c["geometry"]})
            meta.append("%s\t%s\t%s\t%s" % (name, c["id"], c["path"], ",".join(sorted(c["mech"]))))
    with open(o["out"], "w") as f:
        f.write("[\n")
        for i, e in enumerate(entries):
            f.write(json.dumps(e, separators=(", ", ": ")) + (",\n" if i + 1 < len(entries) else "\n"))
        f.write("]\n")
    if o["meta"]:
        with open(o["meta"], "w") as f:
            f.write("pool\tid\tpath\tflags\n" + "\n".join(meta) + "\n")
    sys.stderr.write("select_corpus: %d entries\n" % len(entries))


if __name__ == "__main__":
    main()
