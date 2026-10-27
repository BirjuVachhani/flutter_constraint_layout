#!/usr/bin/env python3
"""gclass_in: writes gclass's input for the layouts that differ at a GRAPH level (FORMATS.md 20).

  gclass_in.py --dart A.txt --java J.java --levels 64,321 --level 64
               --solver S.java --solver-levels 257,0 --solver-level 0
               --ids differ.ids --out gin.tsv [--map GEN_A=GEN_B ...] [--skip GEN ...]

A is a vfuzz file of the port at the level (core<level> or view<level>), J the Java run
at the level (its geometry column picked by --level through --levels), S the Java run
that holds Java's solver result at that level (J0 for 64, J257 for 321 and the view
path), and differ.ids the ids vcompare wrote with --mismatch-ids. --map works as in
vcompare: A's id T2-inplace:<seed> reads Java's T2-fresh:<seed>, and its op list is the
T2-fresh line's (the fresh build of the same final state). --skip is accepted so that a
gate can pass this script vcompare's options; it changes nothing, as differ.ids already
leaves the skipped generators out.

Output, one line per id in the order of differ.ids: id, ops, X (A's geometry), J (Java's
geometry at the level), JS (Java's solver geometry), each geometry with its
`!status | ` prefix. An id whose Java line has no geometry at that column gets its line
status there. The input files are streamed; only the listed ids are kept.
"""
import sys


def die(msg):
    sys.stderr.write("gclass_in: %s\n" % msg)
    sys.exit(2)


def parse_args(argv):
    o = {"map": {}}
    i = 0
    while i < len(argv):
        a = argv[i]
        if i + 1 >= len(argv):
            die("%s needs a value" % a)
        v = argv[i + 1]
        if a == "--map":
            k, _, t = v.partition("=")
            if not k or not t:
                die("--map wants GEN_A=GEN_B")
            o["map"][k] = t
        elif a == "--skip":
            pass
        elif a in ("--dart", "--java", "--levels", "--level", "--solver", "--solver-levels",
                   "--solver-level", "--ids", "--out"):
            o[a[2:].replace("-", "_")] = v
        else:
            die("unknown option %s" % a)
        i += 2
    for k in ("dart", "java", "levels", "level", "solver", "solver_levels", "solver_level",
              "ids", "out"):
        if k not in o:
            die("--%s is needed" % k.replace("_", "-"))
    return o


def column(levels, level):
    ls = levels.split(",")
    if level not in ls:
        die("level %s is not in %s" % (level, levels))
    return ls.index(level)


def java_geoms(path, col, want):
    out = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            i = raw.find("\t")
            if i < 0 or raw[:i] not in want:
                continue
            p = raw.rstrip("\n").split("\t")
            out[p[0]] = p[2 + col] if len(p) > 2 + col else p[1]
    return out


def main(argv):
    o = parse_args(argv)
    ids = [l.strip() for l in open(o["ids"], encoding="utf-8") if l.strip()]

    def b_id(aid):
        gen, _, seed = aid.rpartition(":")
        return "%s:%s" % (o["map"].get(gen, gen), seed)

    bids = {b_id(a) for a in ids}
    want_a = set(ids) | bids
    dart = {}
    with open(o["dart"], encoding="utf-8", errors="replace") as f:
        for raw in f:
            i = raw.find("\t")
            if i < 0 or raw[:i] not in want_a:
                continue
            p = raw.rstrip("\n").split("\t")
            dart[p[0]] = (p[4], p[-1])
    j = java_geoms(o["java"], column(o["levels"], o["level"]), bids)
    js = java_geoms(o["solver"], column(o["solver_levels"], o["solver_level"]), bids)
    missing = 0
    with open(o["out"], "w", encoding="utf-8") as out:
        for aid in ids:
            bid = b_id(aid)
            a = dart.get(aid)
            ops = dart.get(bid, a)
            if a is None or ops is None or bid not in j or bid not in js:
                missing += 1
                continue
            out.write("%s\t%s\t%s\t%s\t%s\n" % (aid, ops[1], a[0], j[bid], js[bid]))
    sys.stderr.write("gclass_in: %d ids, %d written, %d missing\n" % (
        len(ids), len(ids) - missing, missing))
    return 0 if missing == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
