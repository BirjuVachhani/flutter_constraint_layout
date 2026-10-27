#!/usr/bin/env python3
"""guardcheck (p3-c): every layout where the Dart guard fired (vfuzz's <out>.guard,
`id \\t trips`) must be one on which Java overflows its stack at the level (geometry
status SO). Prints the counts; exit 1 when a trip falls elsewhere.
  guardcheck.py <out.guard> <java result file> <levels e.g. 257,0> <level> [--map A=B]
"""
import sys
guard, java, levels, level = sys.argv[1:5]
mp = {}
if len(sys.argv) > 6 and sys.argv[5] == "--map":
    a, _, b = sys.argv[6].partition("=")
    mp[a] = b
li = levels.split(",").index(level)
trips = {}
for l in open(guard):
    p = l.rstrip("\n").split("\t")
    if len(p) == 2:
        trips[p[0]] = int(p[1])
so = set()
for l in open(java):
    i = l.find("\t")
    p = l.rstrip("\n").split("\t")
    g = p[2 + li] if len(p) > 2 + li else ""
    if g == "!SO" or g.startswith("!SO |"):
        so.add(p[0])
def jid(x):
    gen, _, seed = x.rpartition(":")
    return "%s:%s" % (mp.get(gen, gen), seed)
bad = sorted(k for k in trips if jid(k) not in so)
print("guardcheck: %d layouts tripped the guard (%d trips); Java SO at J%s: %d; trips on a "
      "Java SO: %d; trips elsewhere: %d%s" % (
          len(trips), sum(trips.values()), level, len(so), len(trips) - len(bad), len(bad),
          "" if not bad else " (" + ", ".join(bad[:10]) + ")"))
sys.exit(1 if bad else 0)
