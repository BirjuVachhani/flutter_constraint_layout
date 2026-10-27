#!/usr/bin/env python3
"""tcompare: compares measure-request transcripts layout by layout (FORMATS.md 8.5, 17).

Each input is either a vfuzz transcript side file (vfuzz --transcript: one line per
layout, `id \\t T<level> <entries>`, `T<level> -` for none) or a VOpDriver result file
run with -Dtranscript (id, status, geometry per level, then the extra fields, among
them `T<level> ...` per level in level order). The format is detected per file.
Usually A is the Dart side file and B the Java oracle, but any pairing works.

  tcompare.py <A> <B> [--level 0] [--exclude ND,HANG,SOE,JEXC] [--map GEN_A=GEN_B ...]
              [--nd FILE ...] [--show N] [--mismatch-ids FILE] [--quiet]
              [--order exact|block] [--history] [--skip GEN ...]

Equality: the two entry lists are identical, entry for entry and in order. An entry is
`<src>:<name>:<strategy>:<HB><VB>:<hdim>,<vdim>:<detail>:<mw>,<mh>,<mb>,<hasB><nsp>`.
A differing layout is classed by the first entry that differs and, in it, the first
differing field (src, name, strategy, behaviours, dims, detail, answer), or `count`
when one list is a prefix of the other (`block` under --order block when the Direct
blocks hold different numbers of entries; the lists are then shown with `|` at the
block's bounds and the block sorted).

--order block (the default at level 257; FORMATS.md 18): the entries of pass 0's Direct
block, from the first `P` or `D` entry to the last one, with the `F` entries nested in
the first one (the `F` entries right before it), compare as a multiset; the entries
before and after the block compare in order. The oracle iterates a dependents set in
insertion order only up to 10 entries (-XX:hashCode=2 treeifies the bin at the 11th),
and Android's own order there is the identity-hash order, random per launch, so the
order of Direct's requests is not a parity property. The layouts that differ in order
but are equal under the rule are reported per generator as `absorbed`. --order exact
(the default at other levels) compares every entry in order.
--history: a layout whose lists differ only in the hasBaseline flag of GONE answers
(detail `g`) or cache-hit answers (detail `c`) is counted as `history`, reported per
generator, and not as DIFFER. Both answers leave measuredHasBaseline as the previous
request set it, and BasicMeasure reuses one Measure across measures, so an in-place
sequence carries the last measure's flag where a fresh build has a new Measure (the
T2-inplace history of FORMATS.md 17.2; cache hits since level 257's CACHE_MEASURES).

Exclusions, judged on whichever input is a Java file (B first) and counted, as in
vcompare.py:
  ND    the line status is ND, or the id is ND in a --nd file (jbatch3.sh output)
  HANG  the line status is HANG
  SOE   the level's geometry status is SO (a Java stack overflow)
  JEXC  the line status or the level's geometry status is EXC:...
Use --exclude to choose which apply; every class is reported.
--level picks the T<level> field (the side file carries its level too).
--map T2-inplace=T2-fresh compares A's id T2-inplace:<seed> with B's T2-fresh:<seed>.
--skip GEN drops the layouts of generator GEN from both inputs and reports how many (as
vcompare.py's --skip).
--mismatch-ids writes the differing ids.
Exit status: 0 when nothing differs outside the exclusions, 1 otherwise (2 on usage).
"""
import re
import sys
from collections import Counter, defaultdict

USAGE = __doc__.split("\n\n")[1]
CLASSES = ("ND", "HANG", "SOE", "JEXC")
SIDE = re.compile(r"^T(-?\d+) (.*)$")
FIELDS = ("src", "name", "strategy", "behaviours", "dims", "detail", "answer")


def die(msg):
    sys.stderr.write("tcompare: %s\n%s\n" % (msg, USAGE))
    sys.exit(2)


def parse_args(argv):
    o = {"files": [], "level": "0", "exclude": "ND,HANG,SOE,JEXC", "map": {}, "nd": [],
         "show": 10, "mismatch_ids": None, "quiet": False, "order": None,
         "history": False, "skip": []}
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
        elif a == "--order":
            o["order"] = val(); i += 2
            if o["order"] not in ("exact", "block"):
                die("--order wants exact or block")
        elif a == "--history":
            o["history"] = True; i += 1
        elif a == "--skip":
            o["skip"].append(val()); i += 2
        elif a.startswith("--"):
            die("unknown option %s" % a)
        else:
            o["files"].append(a); i += 1
    if len(o["files"]) != 2:
        die("two input files are needed")
    if o["order"] is None:
        o["order"] = "block" if o["level"] == "257" else "exact"
    o["exclude"] = {x for x in o["exclude"].split(",") if x}
    for x in o["exclude"]:
        if x not in CLASSES:
            die("unknown exclusion %s" % x)
    return o


class Rec:
    """One layout of one input: its entries (None when the line has no T field for the
    level), and for a Java line the excluded class, if any."""
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
    tag = "T%s " % level
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
                    die("%s: not a transcript side line: %s" % (path, line[:80]))
                if m.group(1) != str(level):
                    die("%s: side file is level %s, not %s" % (path, m.group(1), level))
                recs[p[0]] = Rec(entries_of(m.group(2)))
                continue
            # A Java line: the T fields name the levels, in level order.
            tfields = [x for x in p[2:] if re.match(r"^T-?\d+ ", x)]
            levels = [x.split(" ", 1)[0][1:] for x in tfields]
            t = next((x for x in tfields if x.startswith(tag)), None)
            li = levels.index(str(level)) if str(level) in levels else 0
            cls = java_class(p, li)
            recs[p[0]] = Rec(entries_of(t[len(tag):]) if t is not None else None, cls)
    return recs, kind or "empty"


def direct_block(entries):
    """(lo, hi) of pass 0's Direct block in [entries]: from the first `P` or `D` entry
    (moved back over the `F` entries nested in it) to the last one, or None."""
    idx = [i for i, e in enumerate(entries) if e.startswith("P:") or e.startswith("D:")]
    if not idx:
        return None
    lo, hi = idx[0], idx[-1] + 1
    while lo > 0 and entries[lo - 1].startswith("F:"):
        lo -= 1
    return lo, hi


def canonical(entries, order):
    """The list under the order rule: with `block`, the Direct block sorted."""
    if order != "block":
        return entries
    blk = direct_block(entries)
    if blk is None:
        return entries
    lo, hi = blk
    return entries[:lo] + ["|"] + sorted(entries[lo:hi]) + ["|"] + entries[hi:]


def gone_flag_only(x, y):
    """Whether entries x and y differ only in the hasBaseline flag of a GONE or a
    cache-hit answer (the flag the reused Measure carried in)."""
    fx, fy = x.split(":"), y.split(":")
    if len(fx) != len(FIELDS) or len(fy) != len(FIELDS) or fx[:-1] != fy[:-1]:
        return False
    if fx[5] not in ("g", "c"):
        return False
    ax, ay = fx[6].split(","), fy[6].split(",")
    if len(ax) != 4 or len(ay) != 4 or ax[:3] != ay[:3]:
        return False
    return len(ax[3]) == 2 and len(ay[3]) == 2 and ax[3][1] == ay[3][1]


def history_only(a, b):
    """Whether lists a and b differ only in GONE answers' hasBaseline flags."""
    return len(a) == len(b) and all(x == y or gone_flag_only(x, y) for x, y in zip(a, b))


def first_difference(a, b):
    """(index, field) of the first difference between two entry lists."""
    for i, (x, y) in enumerate(zip(a, b)):
        if x == y:
            continue
        if x == "|" or y == "|":
            # A bound of the Direct block (--order block): the blocks differ in size.
            return i, "block"
        fx, fy = x.split(":"), y.split(":")
        if len(fx) != len(FIELDS) or len(fy) != len(FIELDS):
            return i, "entry"
        for name, u, v in zip(FIELDS, fx, fy):
            if u != v:
                return i, name
        return i, "entry"
    return min(len(a), len(b)), "count"


def main(argv):
    o = parse_args(argv)
    A, kind_a = load(o["files"][0], o["level"])
    B, kind_b = load(o["files"][1], o["level"])
    if kind_a == "java" and all(r.entries is None for r in A.values() if r.cls is None):
        die("%s has no T%s field: run VOpDriver with -Dtranscript" % (o["files"][0], o["level"]))
    if kind_b == "java" and all(r.entries is None for r in B.values() if r.cls is None):
        die("%s has no T%s field: run VOpDriver with -Dtranscript" % (o["files"][1], o["level"]))
    skipped = Counter()
    for side, recs in (("A", A), ("B", B)):
        for k in [k for k in recs if k.rpartition(":")[0] in o["skip"]]:
            del recs[k]
            skipped[side] += 1
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
    absorbed = Counter()
    history = Counter()
    excluded = Counter()
    first_field = Counter()
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
        if ea is None or eb is None:
            counts["no transcript"] += 1
            by_gen[gen]["differ"] += 1
            counts["differ"] += 1
            first_field["no transcript"] += 1
            mism.append(aid)
            if len(examples) < o["show"]:
                examples.append((aid, bid, None, "no transcript", ea, eb))
            continue
        if ea == eb:
            counts["equal"] += 1
            continue
        ca, cb = canonical(ea, o["order"]), canonical(eb, o["order"])
        if ca == cb:
            counts["equal"] += 1
            absorbed[gen] += 1
            continue
        if o["history"] and history_only(ca, cb):
            history[gen] += 1
            continue
        ea, eb = ca, cb
        counts["differ"] += 1
        by_gen[gen]["differ"] += 1
        i, field = first_difference(ea, eb)
        first_field[field] += 1
        mism.append(aid)
        if len(examples) < o["show"]:
            examples.append((aid, bid, i, field, ea, eb))
    only_b = sum(1 for k in B if k not in seen_b)

    out = sys.stdout
    out.write("tcompare A=%s (%s) B=%s (%s) level %s\n" % (
        o["files"][0], kind_a, o["files"][1], kind_b, o["level"]))
    out.write("  layouts: A %d, B %d, compared %d, equal %d, DIFFER %d, missing in B %d, only in B %d\n" % (
        len(A), len(B), counts["compared"], counts["equal"], counts["differ"],
        counts["missing in B"], only_b))
    if o["skip"]:
        out.write("  skipped generators %s: A %d, B %d\n" % (
            ",".join(o["skip"]), skipped["A"], skipped["B"]))
    out.write("  excluded classes: %s\n" % ", ".join(
        "%s %d%s" % (k, excluded[k], "" if k in o["exclude"] else " (compared)") for k in CLASSES))
    out.write("  order %s: absorbed by the Direct-block rule %d%s\n" % (
        o["order"], sum(absorbed.values()),
        "" if not absorbed else " (%s)" % ", ".join(
            "%s %d" % (g, n) for g, n in sorted(absorbed.items()))))
    if o["history"]:
        out.write("  history (hasBaseline flag of GONE or cache-hit answers only, not DIFFER): %d%s\n" % (
            sum(history.values()),
            "" if not history else " (%s)" % ", ".join(
                "%s %d" % (g, n) for g, n in sorted(history.items()))))
    if first_field:
        out.write("  first differing field: %s\n" % dict(first_field.most_common()))
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
                    "-" if ea is None else " ".join(ea), "-" if eb is None else " ".join(eb)))
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
