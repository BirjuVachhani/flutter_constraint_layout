#!/usr/bin/env python3
"""select_graph_corpus: picks the layouts of graph_corpus.json, the engine's parity
corpus at the dependency-graph optimization levels, from the parity corpora and the
pinned Java oracle's results at those levels (graph_corpus_test.dart).

  python3 -I select_graph_corpus.py <out.json> --runs <parity runs dir> [--seed 20261026]

At OPTIMIZATION_GRAPH (64), OPTIMIZATION_STANDARD | OPTIMIZATION_GRAPH (321) and the
OPTIMIZATION_GRAPH_WRAP levels 192 and 449, BasicMeasure runs upstream's
DependencyGraph before (or instead of) the solver. Each pool is one corpus on one path
at one level, with Java's status and geometry at that level (relative to --runs):

  pool          path      corpus input               Java result (column)
  R@64, R@321   core<N>   p0/java/R.in               p5a/graph/java/R.J64_321.java
  T2core@...    core<N>   p3/p3c/java/T2core.in      p5a/graph/java/T2core.J64_321.java
  VR2@321       view321   p1/java/VR2.in             p5a/graph/java/VR2.J321.java
  T2@321        view321   p1/java/T2.in              p5a/graph/java/T2.J321.java
  <c>@192, @449 core/view p5a/p5a-engine/java/<c>.J192_449.java

The candidates of a pool are the layouts on which the earlier engine differed
from Java at that level (the classification files <c>.<level>.gclass.tsv of the GRAPH
gate: p5a/graph/today for 64 and 321, p5a/p5a-engine/wrap_before for 192 and 449),
each with its route (which side ran the graph) and its mechanism. A greedy cover takes,
per pool, layouts until every generator and every route-and-mechanism pair is covered,
preferring the shorter op list (candidates per key are the shortest ones plus a seeded
random sample), up to the pool's budget. Excluded: the in-place sequences of T2
(T2-inplace; Java's reference for them is another op list), Java statuses other than
ok and ok-printed, and the layouts the triple run found not deterministic (the ND
files next to the Java results, where they exist).
"""
import json
import os
import random
import sys
from collections import defaultdict

BUDGET = 40
CORPORA = {
    "R": ("core", "p0/java/R.in"),
    "T2core": ("core", "p3/p3c/java/T2core.in"),
    "VR2": ("view", "p1/java/VR2.in"),
    "T2": ("view", "p1/java/T2.in"),
}
POOLS = [
    ("R", 64), ("R", 321), ("R", 192), ("R", 449),
    ("T2core", 64), ("T2core", 321), ("T2core", 192), ("T2core", 449),
    ("VR2", 321), ("VR2", 192), ("VR2", 449),
    ("T2", 321), ("T2", 192), ("T2", 449),
]


def java_file(runs, c, level):
    if level in (192, 449):
        return os.path.join(runs, "p5a/p5a-engine/java/%s.J192_449.java" % c), [192, 449]
    if c in ("R", "T2core"):
        return os.path.join(runs, "p5a/graph/java/%s.J64_321.java" % c), [64, 321]
    return os.path.join(runs, "p5a/graph/java/%s.J321.java" % c), [321]


def gclass_file(runs, c, level):
    d = "p5a/p5a-engine/wrap_before" if level in (192, 449) else "p5a/graph/today"
    return os.path.join(runs, d, "%s.%d.gclass.tsv" % (c, level))


def read_nd(path):
    nd = set()
    if os.path.exists(path):
        for l in open(path):
            t = l.rstrip("\n").split("\t")
            if len(t) > 1 and t[1] == "ND":
                nd.add(t[0])
    return nd


def main(argv):
    out, runs, seed = None, None, 20261026
    i = 0
    while i < len(argv):
        if argv[i] == "--runs":
            runs = argv[i + 1]; i += 2
        elif argv[i] == "--seed":
            seed = int(argv[i + 1]); i += 2
        else:
            out = argv[i]; i += 1
    if not out or not runs:
        sys.exit(__doc__.split("\n\n")[1])
    rng = random.Random(seed)
    entries = []
    for c, level in POOLS:
        kind, corpus = CORPORA[c]
        cls = {}
        for l in open(gclass_file(runs, c, level)):
            t = l.rstrip("\n").split("\t")
            if t[0].startswith("T2-inplace:"):
                continue
            cls[t[0]] = (t[1], t[2], t[3])
        jpath, jlevels = java_file(runs, c, level)
        nd = read_nd(jpath[: -len(".java")] + ".nd")
        col = jlevels.index(level)
        java = {}
        for l in open(jpath):
            t = l.rstrip("\n").split("\t")
            if t[0] in cls and t[1] == "ok" and len(t) > 2 + col and t[0] not in nd:
                g = t[2 + col]
                status = g[1:].split(" | ", 1)[0] if g.startswith("!") else "ok"
                if status in ("ok", "ok-printed"):
                    java[t[0]] = (status, g)
        ops = {}
        for l in open(os.path.join(runs, corpus)):
            i0 = l.find("\t")
            if l[:i0] in java:
                ops[l[:i0]] = l.rstrip("\n").split("\t")[-1]
        by_key = defaultdict(list)
        for k in java:
            gen, route, mech = cls[k]
            by_key[("gen", gen)].append(k)
            by_key[("mech", route, mech)].append(k)
        cands = set()
        for key, ids in sorted(by_key.items()):
            ids.sort(key=lambda k: (len(ops[k]), k))
            cands.update(ids[:3])
            cands.update(rng.sample(ids, min(2, len(ids))))
        picked, covered = [], set()
        while len(picked) < BUDGET:
            best, gain = None, 0
            for k in sorted(cands - set(picked)):
                gen, route, mech = cls[k]
                g = (("gen", gen) not in covered) * 2 + (("mech", route, mech) not in covered)
                if g > gain or (g == gain and g > 0 and len(ops[k]) < len(ops[best])):
                    best, gain = k, g
            if best is None:
                break
            picked.append(best)
            gen, route, mech = cls[best]
            covered.update([("gen", gen), ("mech", route, mech)])
        rest = sorted(set(java) - set(picked), key=lambda k: (len(ops[k]), k))
        picked += rest[: BUDGET - len(picked)]
        for k in sorted(picked):
            status, g = java[k]
            entries.append({"id": k, "path": "%s%d" % (kind, level), "ops": ops[k],
                            "status": status, "geometry": g})
    with open(out, "w") as f:
        f.write("[\n")
        for i, e in enumerate(entries):
            f.write(json.dumps(e, separators=(", ", ": ")) + (",\n" if i + 1 < len(entries) else "\n"))
        f.write("]\n")
    print("%d entries" % len(entries))


if __name__ == "__main__":
    main(sys.argv[1:])
