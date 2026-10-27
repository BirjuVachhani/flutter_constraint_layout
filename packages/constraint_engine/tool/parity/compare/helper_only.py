#!/usr/bin/env python3
"""helper_only: of the layouts a GRAPH-level comparison found different (<c>.<lv>.ids), how
many differ only in guideline frames, only in barrier frames, or only in helper frames.

  helper_only.py <dart.isg.gz> <corpus.in> <java> <levels> <level> <ids> [--map A=B]
"""
import gzip, sys

def frames(g):
    if g.startswith("!"):
        i = g.find(" | ")
        g = g[i + 3:] if i >= 0 else ""
    out = {}
    for part in g.split(" | "):
        if part.startswith("root "):
            out["root"] = part
            continue
        i = part.find(": ")
        if i >= 0:
            out[part[:i]] = part[i + 2:]
    return out

args = sys.argv[1:]
mp = {}
if "--map" in args:
    k = args.index("--map"); a, b = args[k + 1].split("="); mp[a] = b; del args[k:k + 2]
isg, corpus, java, levels, level, idf = args
col = levels.split(",").index(level)
ids = [l.strip() for l in open(idf) if l.strip()]
def bid(x):
    g, _, s = x.rpartition(":"); return "%s:%s" % (mp.get(g, g), s)
want = set(ids); wb = {bid(x) for x in ids}
X = {}
with gzip.open(isg, "rt") as f:
    for l in f:
        p = l.rstrip("\n").split("\t")
        if p[0] in want: X[p[0]] = p[2]
J = {}
with open(java) as f:
    for l in f:
        i = l.find("\t")
        if l[:i] in wb:
            p = l.rstrip("\n").split("\t"); J[p[0]] = p[2 + col]
helpers = {}
with open(corpus) as f:
    for l in f:
        i = l.find("\t")
        if l[:i] in wb:
            ops = l.rstrip("\n").split("\t")[-1].split(";")
            helpers[l[:i]] = ({o[2:] for o in ops if o.startswith("g ")}, {o[2:] for o in ops if o.startswith("b ")})
c = {"guideline only": 0, "barrier only": 0, "guideline and barrier only": 0, "other": 0}
for x in ids:
    a, b = frames(X[x]), frames(J[bid(x)])
    gl, br = helpers[bid(x)]
    names = {n for n in set(a) | set(b) if a.get(n) != b.get(n)}
    if names and names <= gl: c["guideline only"] += 1
    elif names and names <= br: c["barrier only"] += 1
    elif names and names <= (gl | br): c["guideline and barrier only"] += 1
    else: c["other"] += 1
print(len(ids), c)
