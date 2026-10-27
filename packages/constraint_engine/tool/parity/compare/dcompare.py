#!/usr/bin/env python3
"""dcompare: compares Direct dumps layout by layout (FORMATS.md 8.4 and 18).

Each input is either a vfuzz Direct side file (vfuzz --direct: one line per layout,
`id \\t D<level> <entries>`, `D<level> -` when the last measure made no dump) or a
VOpDriver result file run with -Ddirect (id, status, geometry per level, then the
extra fields, among them `D<level> ...` per level in level order). The format is
detected per file. Usually A is the Dart side file and B the Java oracle.

  dcompare.py <A> <B> [--level 257] [--exclude ND,HANG,SOE,JEXC] [--map GEN_A=GEN_B ...]
              [--nd FILE ...] [--show N] [--mismatch-ids FILE] [--quiet]

Entries (one per child, mChildren order):
  guideline  name:g<orientation>:<final value or _>
  barrier    name:b<type>:<rh><rv>:<L>,<T>,<R>,<B>
  widget     name:<rh><rv>:<L>,<T>,<R>,<B>,<S>:<mWidth>x<mHeight>:<baseline><+|->:<m|-><H|-><V|->

Equality: the two entry lists are identical. A differing layout is classed by the first
entry that differs and, in it, the first differing field:
  name, kind (g<o>, b<t> or widget), rh, rv, L, T, R, B, S (anchor final values),
  value (a guideline's final value), size, baseline (distance and hasBaseline),
  measured (m), hpass (H), vpass (V); `count` when one list is a prefix of the other,
  `dump` when one side made a dump and the other did not.

Exclusions, judged on whichever input is a Java file (B first) and counted, as in
vcompare.py and tcompare.py:
  ND    the line status is ND, or the id is ND in a --nd file (jbatch3.sh output)
  HANG  the line status is HANG
  SOE   the level's geometry status is SO (a Java stack overflow)
  JEXC  the line status or the level's geometry status is EXC:...
--level picks the D<level> field (a side file carries its level too).
--map T2-inplace=T2-fresh compares A's id T2-inplace:<seed> with B's T2-fresh:<seed>.
--mismatch-ids writes the differing ids.
Exit status: 0 when nothing differs outside the exclusions, 1 otherwise (2 on usage).
"""
import re
import sys
from collections import Counter, defaultdict

USAGE = __doc__.split("\n\n")[1]
CLASSES = ("ND", "HANG", "SOE", "JEXC")
SIDE = re.compile(r"^D(-?\d+) (.*)$")
DFIELD = re.compile(r"^D-?\d+ ")


def die(msg):
    sys.stderr.write("dcompare: %s\n%s\n" % (msg, USAGE))
    sys.exit(2)


def parse_args(argv):
    o = {"files": [], "level": "257", "exclude": "ND,HANG,SOE,JEXC", "map": {}, "nd": [],
         "show": 10, "mismatch_ids": None, "quiet": False}
    i = 0
    while i < len(argv):
        a = argv[i]

        def val():
            if i + 1 >= len(argv):
                die("%s needs a value" % a)
            return argv[i + 1]
        if a == "--level":
            o["level"] = val(); i += 2
        elif a == "--exclude":
            o["exclude"] = val(); i += 2
        elif a == "--map":
            k, _, v = val().partition("=")
            if not k or not v:
                die("--map wants GEN_A=GEN_B")
            o["map"][k] = v; i += 2
        elif a == "--nd":
            o["nd"].append(val()); i += 2
        elif a == "--show":
            o["show"] = int(val()); i += 2
        elif a == "--mismatch-ids":
            o["mismatch_ids"] = val(); i += 2
        elif a == "--quiet":
            o["quiet"] = True; i += 1
        elif a.startswith("--"):
            die("unknown option %s" % a)
        else:
            o["files"].append(a); i += 1
    if len(o["files"]) != 2:
        die("two input files are needed")
    o["exclude"] = {x for x in o["exclude"].split(",") if x}
    for x in o["exclude"]:
        if x not in CLASSES:
            die("unknown exclusion %s" % x)
    return o


class Rec:
    """One layout of one input: its entries (None when the line has no D field for the
    level, [] for `D<level> -`), and for a Java line the excluded class, if any."""
    __slots__ = ("entries", "cls")

    def __init__(self, entries, cls=None):
        self.entries, self.cls = entries, cls


def entries_of(body):
    return [] if body == "-" else body.split(" ")


def java_class(p, level_index):
    status = p[1] if len(p) > 1 else "?"
    if status == "ND":
        return "ND"
    if status == "HANG":
        return "HANG"
    if status.startswith("EXC"):
        return "JEXC"
    g = p[2 + level_index] if len(p) > 2 + level_index else ""
    if g.startswith("!SO |") or g == "!SO":
        return "SOE"
    if g.startswith("!EXC"):
        return "JEXC"
    return None


def load(path, level):
    """id -> Rec, and the detected kind (side or java)."""
    recs = {}
    kind = None
    tag = "D%s " % level
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            p = line.split("\t")
            if kind is None:
                # A Java HANG line (`id \t HANG`) also has two fields.
                kind = "side" if len(p) == 2 and SIDE.match(p[1]) else "java"
            if kind == "side":
                m = SIDE.match(p[1]) if len(p) == 2 else None
                if m is None:
                    die("%s: not a Direct side line: %s" % (path, line[:80]))
                if m.group(1) != str(level):
                    die("%s: side file is level %s, not %s" % (path, m.group(1), level))
                recs[p[0]] = Rec(entries_of(m.group(2)))
                continue
            # A Java line: the D fields name the levels, in level order; with -Dprobe
            # or -Dtranscript the P and T fields interleave, so read the levels from
            # whichever per-level field comes first.
            dfields = [x for x in p[2:] if DFIELD.match(x)]
            levels = [x.split(" ", 1)[0][1:] for x in dfields]
            d = next((x for x in dfields if x.startswith(tag)), None)
            li = levels.index(str(level)) if str(level) in levels else 0
            cls = java_class(p, li)
            recs[p[0]] = Rec(entries_of(d[len(tag):]) if d is not None else None, cls)
    return recs, kind or "empty"


def entry_fields(e):
    """name, kind and the ordered (field, value) pairs of one dump entry."""
    parts = e.split(":")
    if len(parts) == 3 and re.match(r"^g-?\d+$", parts[1]):
        return parts[0], parts[1], [("value", parts[2])]
    if len(parts) == 4 and re.match(r"^b-?\d+$", parts[1]):
        a = parts[3].split(",")
        return parts[0], parts[1], [("rh", parts[2][:1]), ("rv", parts[2][1:2])] + \
            list(zip(("L", "T", "R", "B"), a))
    if len(parts) == 6:
        # A widget: name:<rh><rv>:<L>,<T>,<R>,<B>,<S>:<w>x<h>:<bd><hb>:<m><H><V>.
        a = parts[2].split(",")
        flags = parts[5]
        return parts[0], "widget", [("rh", parts[1][:1]), ("rv", parts[1][1:2])] + \
            list(zip(("L", "T", "R", "B", "S"), a)) + \
            [("size", parts[3]), ("baseline", parts[4]), ("measured", flags[:1]),
             ("hpass", flags[1:2]), ("vpass", flags[2:3])]
    return parts[0], "?", [("raw", e)]


def first_difference(a, b):
    """(index, field) of the first difference between two entry lists."""
    for i, (x, y) in enumerate(zip(a, b)):
        if x == y:
            continue
        nx, kx, fx = entry_fields(x)
        ny, ky, fy = entry_fields(y)
        if nx != ny:
            return i, "name"
        if kx != ky:
            return i, "kind"
        for (name, u), (_, v) in zip(fx, fy):
            if u != v:
                return i, name
        return i, "entry"
    return min(len(a), len(b)), "count"


def main(argv):
    o = parse_args(argv)
    A, kind_a = load(o["files"][0], o["level"])
    B, kind_b = load(o["files"][1], o["level"])
    if kind_a == "java" and all(r.entries is None for r in A.values() if r.cls is None):
        die("%s has no D%s field: run VOpDriver with -Ddirect" % (o["files"][0], o["level"]))
    if kind_b == "java" and all(r.entries is None for r in B.values() if r.cls is None):
        die("%s has no D%s field: run VOpDriver with -Ddirect" % (o["files"][1], o["level"]))
    nd_ids = set()
    for fn in o["nd"]:
        with open(fn, encoding="utf-8", errors="replace") as f:
            for raw in f:
                p = raw.rstrip("\n").split("\t")
                if len(p) > 1 and p[1] == "ND":
                    nd_ids.add(p[0])

    def b_id(aid):
        gen, _, seed = aid.rpartition(":")
        return "%s:%s" % (o["map"].get(gen, gen), seed)

    counts = Counter()
    by_gen = defaultdict(Counter)
    excluded = Counter()
    first_field = Counter()
    first_kind = Counter()
    mism = []
    examples = []
    seen_b = set()
    for aid, a in A.items():
        bid = b_id(aid)
        gen = aid.rpartition(":")[0]
        b = B.get(bid)
        if b is None:
            counts["missing in B"] += 1
            by_gen[gen]["missing"] += 1
            continue
        seen_b.add(bid)
        cls = "ND" if bid in nd_ids else (b.cls or a.cls)
        if cls is not None:
            excluded[cls] += 1
            by_gen[gen]["excluded"] += 1
            if cls in o["exclude"]:
                continue
        counts["compared"] += 1
        by_gen[gen]["compared"] += 1
        ea, eb = a.entries, b.entries
        if ea is None or eb is None or (not ea) != (not eb):
            field = "no D field" if ea is None or eb is None else "dump"
            counts["differ"] += 1
            by_gen[gen]["differ"] += 1
            first_field[field] += 1
            mism.append(aid)
            if len(examples) < o["show"]:
                examples.append((aid, bid, None, field, ea, eb))
            continue
        if ea == eb:
            counts["equal"] += 1
            continue
        counts["differ"] += 1
        by_gen[gen]["differ"] += 1
        i, field = first_difference(ea, eb)
        first_field[field] += 1
        if i < min(len(ea), len(eb)):
            first_kind[entry_fields(eb[i])[1][:1] or "?"] += 1
        mism.append(aid)
        if len(examples) < o["show"]:
            examples.append((aid, bid, i, field, ea, eb))
    only_b = sum(1 for k in B if k not in seen_b)

    out = sys.stdout
    out.write("dcompare A=%s (%s) B=%s (%s) level %s\n" % (
        o["files"][0], kind_a, o["files"][1], kind_b, o["level"]))
    out.write("  layouts: A %d, B %d, compared %d, equal %d, DIFFER %d, missing in B %d, only in B %d\n" % (
        len(A), len(B), counts["compared"], counts["equal"], counts["differ"],
        counts["missing in B"], only_b))
    out.write("  excluded classes: %s\n" % ", ".join(
        "%s %d%s" % (k, excluded[k], "" if k in o["exclude"] else " (compared)") for k in CLASSES))
    if first_field:
        out.write("  first differing field: %s\n" % dict(first_field.most_common()))
    if first_kind:
        out.write("  first differing entry kind (B side; g guideline, b barrier, w widget): %s\n"
                  % dict(first_kind.most_common()))
    if not o["quiet"]:
        out.write("  per generator (compared / differ / excluded / missing):\n")
        for gen in sorted(by_gen):
            c = by_gen[gen]
            out.write("    %-16s %7d %7d %7d %7d\n" % (
                gen, c["compared"], c["differ"], c["excluded"], c["missing"]))
        for aid, bid, i, field, ea, eb in examples:
            out.write("  --- %s%s  first difference: %s%s\n" % (
                aid, "" if aid == bid else " vs " + bid, field,
                "" if i is None else " at entry %d" % i))
            if i is None:
                out.write("      A %s\n      B %s\n" % (
                    "-" if ea is None else (" ".join(ea) or "-"),
                    "-" if eb is None else (" ".join(eb) or "-")))
                continue
            lo = max(0, i - 1)
            out.write("      A [%d..] %s\n" % (lo, " ".join(ea[lo:i + 2]) or "(end)"))
            out.write("      B [%d..] %s\n" % (lo, " ".join(eb[lo:i + 2]) or "(end)"))
    if o["mismatch_ids"]:
        with open(o["mismatch_ids"], "w") as f:
            for k in mism:
                f.write(k + "\n")
    return 1 if counts["differ"] > 0 else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
