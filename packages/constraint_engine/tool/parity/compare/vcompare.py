#!/usr/bin/env python3
"""vcompare: compares two result files layout by layout (FORMATS.md 1, 2, 8.2).

Each input is either a vfuzz file (id, features, path, status, geometry, ops), a Flutter
runner file in the same six fields with the path `fl-<tag>` (run_fl.sh, FORMATS.md 11),
or a Java result file from OpDriver/VOpDriver (id, status, geom(L1), geom(L2), ...). The
format is detected per file. Usually A is the Dart side and B the Java oracle, but any
pairing works (Dart against Dart, Java against Java). Flutter geometry can hold
non-integral numbers (Dart's double.toString); they compare as written, so 10.5 never
equals 10.

  vcompare.py <A> <B> [--level 257] [--levels 257,0] [--exclude ND,HANG,SOE,JEXC]
              [--status] [--map GEN_A=GEN_B ...] [--nd FILE ...] [--show N]
              [--helpers full|pos|ignore] [--mismatch-ids FILE] [--mismatch-in FILE]
              [--strict] [--quiet] [--skip GEN ...]

Equality: the container's size and every child's frame, in child order (a GONE
non-barrier child by size only, as the geometry format prints it). With --status, and
always for ids of the A corpus (A-*), the printed-exception status must match too
(ok against ok-printed is a difference). Thrown statuses (EXC:...) compare by class.

Exclusions, judged on the B side (the oracle) and counted:
  ND    B's line status is ND, or the id is ND in a --nd file (jbatch3.sh output)
  HANG  B's line status is HANG
  SOE   B's geometry status is SO (a Java stack overflow)
  JEXC  B threw out of layout(): line status EXC:..., or geometry status EXC:...
  UNMAPPED  a side could not express the layout (RoboOracle's or the Flutter runner's
        UNMAPPED:<reason>, judged on B, then on A); always excluded, counted per reason
Use --exclude to choose which of the first four apply; every class is reported.

--helpers: guideline and barrier frames are not pixels (Android's helper views are GONE
and never drawn; VOpDriver v2 prints them `(x, y) 0 x 0`, the current engine prints a
visible guideline `0 x H`). `full` (default) compares them like any child, `pos`
compares only their position, `ignore` skips them. Helper names come from the `g` and
`b` ops of whichever input is a vfuzz file. Flows and Groups are always compared.
--level picks B's (and A's, if it is a Java file) geometry column through --levels, the
level list the Java batch ran with (VOpDriver's `257,0` gives J257 then J0).
--map T-inplace=T-fresh compares A's id T-inplace:<seed> with B's T-fresh:<seed>.
--skip GEN drops the layouts of generator GEN from both inputs before anything is
compared, and reports how many it dropped (T2-inplace at a level where Android's live
views lay an in-place sequence out unlike its fresh build: the in-place gate,
gates/inplace_gates.sh, compares those with the live views instead).
--mismatch-ids writes the differing ids; --mismatch-in writes their corpus lines (from
whichever input is a vfuzz file) for the ND triple run (jbatch3.sh).
Exit status: 0 when nothing differs outside the exclusions, 1 otherwise (2 on usage).
"""
import re
import sys
from collections import Counter, defaultdict

USAGE = __doc__.split("\n\n")[1]

CLASSES = ("ND", "HANG", "SOE", "JEXC", "UNMAPPED")
PATHS = {"none", "graphfirst", "forced", "core0", "core257", "view0", "view257"}
# vfuzz's generic paths core<level> and view<level> (FORMATS.md 20).
LEVEL_PATH = re.compile(r"^(core|view)\d+$")
# A number as the geometry prints it: an int (Java, vfuzz) or a Dart double's
# toString (the Flutter runner: 10.5, 1e-7, Infinity, NaN).
NUM = r"(-?(?:\d+(?:\.\d+)?(?:e[-+]?\d+)?|Infinity)|NaN)"
GEOM_STATUS = re.compile(r"^!(.*?) \| (root %s x %s.*)$" % (NUM, NUM))
ROOT = re.compile(r"^root %s x %s$" % (NUM, NUM))
CHILD = re.compile(r"^(.*?): \(%s, %s\) %s x %s$" % (NUM, NUM, NUM, NUM))
GONE = re.compile(r"^(.*?): gone, %s x %s$" % (NUM, NUM))


def die(msg):
    sys.stderr.write("vcompare: %s\n%s\n" % (msg, USAGE))
    sys.exit(2)


def parse_args(argv):
    o = {
        "files": [], "level": "257", "levels": "257,0", "exclude": "ND,HANG,SOE,JEXC,UNMAPPED",
        "status": False, "map": {}, "nd": [], "show": 10, "mismatch_ids": None,
        "mismatch_in": None, "strict": False, "quiet": False, "helpers": "full",
        "skip": [],
    }
    i = 0
    while i < len(argv):
        a = argv[i]
        def val():
            if i + 1 >= len(argv):
                die("%s needs a value" % a)
            return argv[i + 1]
        if a == "--level":
            o["level"] = val(); i += 2
        elif a == "--levels":
            o["levels"] = val(); i += 2
        elif a == "--exclude":
            o["exclude"] = val(); i += 2
        elif a == "--status":
            o["status"] = True; i += 1
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
        elif a == "--mismatch-in":
            o["mismatch_in"] = val(); i += 2
        elif a == "--helpers":
            o["helpers"] = val(); i += 2
            if o["helpers"] not in ("full", "pos", "ignore"):
                die("--helpers wants full, pos or ignore")
        elif a == "--strict":
            o["strict"] = True; i += 1
        elif a == "--quiet":
            o["quiet"] = True; i += 1
        elif a == "--skip":
            o["skip"].append(val()); i += 2
        elif a.startswith("--"):
            die("unknown option %s" % a)
        else:
            o["files"].append(a); i += 1
    if len(o["files"]) != 2:
        die("two input files are needed")
    o["exclude"] = {x for x in o["exclude"].split(",") if x} | {"UNMAPPED"}
    for x in o["exclude"]:
        if x not in CLASSES:
            die("unknown exclusion %s" % x)
    return o


def is_vfuzz(fields):
    """A vfuzz line, or a Flutter runner line (path fl-<tag>, FORMATS.md 11)."""
    return len(fields) >= 6 and (fields[2] in PATHS or fields[2].startswith("fl-")
                                 or LEVEL_PATH.match(fields[2]) is not None)


def num(t):
    """A geometry number: int when integral as written, else float."""
    try:
        return int(t)
    except ValueError:
        return float(t)


def split_geom(g):
    """(status, body): status 'ok' or the text after '!', body from 'root' on."""
    if not g.startswith("!"):
        return "ok", g
    m = GEOM_STATUS.match(g)
    if m:
        return m.group(1), m.group(2)
    return g[1:], ""


def status_class(s):
    """ok, ok-printed, EXC, SO, HANG, ND, - (none), or the raw status."""
    if s.startswith("EXC"):
        return "EXC"
    return s


def parse_body(body):
    """[('root', w, h), (name, x, y, w, h) or (name, None, None, w, h)]"""
    if not body:
        return None
    parts = body.split(" | ")
    m = ROOT.match(parts[0])
    if not m:
        return None
    out = [("root", None, None, num(m.group(1)), num(m.group(2)))]
    for p in parts[1:]:
        c = CHILD.match(p)
        if c:
            out.append((c.group(1), num(c.group(2)), num(c.group(3)), num(c.group(4)), num(c.group(5))))
            continue
        c = GONE.match(p)
        if c:
            out.append((c.group(1), None, None, num(c.group(2)), num(c.group(3))))
            continue
        out.append((p, None, None, None, None))
    return out


class Rec:
    """One layout of one input: line status, geometry status, body, raw line, and
    the names of its guidelines and barriers (vfuzz inputs, with --helpers)."""
    __slots__ = ("line_status", "gstatus", "body", "line", "helpers")

    def __init__(self, line_status, gstatus, body, line, helpers=None):
        self.line_status, self.gstatus, self.body, self.line = line_status, gstatus, body, line
        self.helpers = helpers


def helper_names(ops):
    out = set()
    for op in ops.split(";"):
        if op.startswith("g ") or op.startswith("b "):
            out.add(op[2:])
    return frozenset(out)


def canon(body, helpers, mode):
    """The comparable form of a geometry body under the helper policy."""
    if mode == "full" or not helpers:
        return body
    parsed = parse_body(body)
    if parsed is None:
        return body
    out = []
    for e in parsed:
        if e[0] in helpers:
            if mode == "ignore":
                continue
            out.append((e[0], e[1], e[2]))
        else:
            out.append(e)
    return tuple(out)


def load(path, col_index, keep_line, want_helpers=False):
    """id -> Rec. col_index: which geometry column of a Java file (0-based)."""
    recs = {}
    kind = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            p = line.split("\t")
            if kind is None:
                kind = "vfuzz" if is_vfuzz(p) else "java"
            if kind == "vfuzz":
                if len(p) < 6:
                    continue
                # Without geometry, the line status stands for it (`-` on a
                # corpus-only file; EXC:... or UNMAPPED:... from the Flutter runner).
                st, body = split_geom(p[4]) if p[4] != "-" else (p[3], "")
                hs = helper_names(p[-1]) if want_helpers else None
                recs[p[0]] = Rec(p[3], st, body, line if keep_line else None, hs)
            else:
                ls = p[1] if len(p) > 1 else "?"
                g = p[2 + col_index] if len(p) > 2 + col_index else ""
                st, body = split_geom(g) if g else (ls, "")
                recs[p[0]] = Rec(ls, st, body, line if keep_line else None)
    return recs, kind or "empty"


def exclusion(b, a=None):
    """The excluded class of B's record (UNMAPPED also on A's), or None."""
    if b.line_status.startswith("UNMAPPED"):
        return "UNMAPPED"
    if a is not None and a.line_status.startswith("UNMAPPED"):
        return "UNMAPPED"
    if b.line_status == "ND":
        return "ND"
    if b.line_status == "HANG":
        return "HANG"
    if b.gstatus == "SO":
        return "SOE"
    if b.line_status.startswith("EXC") or b.gstatus.startswith("EXC"):
        return "JEXC"
    return None


def describe(a_body, b_body, limit=8):
    pa, pb = parse_body(a_body), parse_body(b_body)
    if pa is None or pb is None:
        return ["unparsable geometry"], 10 ** 9
    lines, maxd = [], 0
    if len(pa) != len(pb):
        lines.append("child count %d != %d" % (len(pa) - 1, len(pb) - 1))
    for x, y in zip(pa, pb):
        if x == y:
            continue
        if x[0] != y[0]:
            lines.append("order: %s != %s" % (x[0], y[0]))
            maxd = 10 ** 9
            continue
        d = 0
        for u, v in zip(x[1:], y[1:]):
            if u is None or v is None:
                if u != v:
                    d = 10 ** 6
            elif u != v:
                try:
                    d = max(d, abs(u - v))
                except (TypeError, ValueError, OverflowError):
                    d = 10 ** 6
                if d != d or d == float("inf"):  # NaN or Infinity
                    d = 10 ** 6
        maxd = max(maxd, d)
        def fmt(t):
            if t[0] == "root":
                return "%s x %s" % (t[3], t[4])
            if t[1] is None:
                return "gone %s x %s" % (t[3], t[4])
            return "(%s, %s) %s x %s" % t[1:]
        if len(lines) < limit:
            lines.append("%s: %s -> %s" % (x[0], fmt(x), fmt(y)))
    return lines, maxd


def drop_generators(gens, A, B):
    """Removes the ids of the generators [gens] from A and B; returns the counts."""
    skipped = Counter()
    if gens:
        for side, recs in (("A", A), ("B", B)):
            for k in [k for k in recs if k.rpartition(":")[0] in gens]:
                del recs[k]
                skipped[side] += 1
    return skipped


def main(argv):
    o = parse_args(argv)
    levels = o["levels"].split(",")
    if o["level"] not in levels:
        die("--level %s is not in --levels %s" % (o["level"], o["levels"]))
    col = levels.index(o["level"])
    want_lines = bool(o["mismatch_in"])
    wh = o["helpers"] != "full"
    try:
        A, kind_a = load(o["files"][0], col, want_lines, wh)
        B, kind_b = load(o["files"][1], col, want_lines, wh)
    except OSError as e:
        die("cannot read an input: %s" % e)
    skipped = drop_generators(o["skip"], A, B)
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
    excluded_ex = defaultdict(list)
    unmapped = Counter()
    status_diff = Counter()
    deltas = Counter()
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
        ex = "ND" if bid in nd_ids else exclusion(b, a)
        if ex == "UNMAPPED":
            um = b if b.line_status.startswith("UNMAPPED") else a
            unmapped[um.line_status.partition(":")[2] or "?"] += 1
        if ex is not None:
            excluded[ex] += 1
            by_gen[gen]["excl:" + ex] += 1
            if len(excluded_ex[ex]) < 3:
                excluded_ex[ex].append(aid)
            if ex in o["exclude"]:
                continue
        if a.line_status in ("ND", "HANG"):
            counts["A " + a.line_status] += 1
        counts["compared"] += 1
        by_gen[gen]["compared"] += 1
        sa, sb = status_class(a.gstatus), status_class(b.gstatus)
        check_status = o["status"] or gen.startswith("A-")
        same_frames = a.body == b.body
        if not same_frames and wh:
            hs = a.helpers or b.helpers
            same_frames = canon(a.body, hs, o["helpers"]) == canon(b.body, hs, o["helpers"])
        if sa != sb:
            status_diff["%s/%s" % (sa, sb)] += 1
        thrown_a, thrown_b = sa in ("EXC", "SO"), sb in ("EXC", "SO")
        same = same_frames and thrown_a == thrown_b and (not check_status or sa == sb)
        if same:
            counts["equal"] += 1
            continue
        counts["differ"] += 1
        by_gen[gen]["differ"] += 1
        if not same_frames:
            lines, maxd = describe(a.body, b.body)
            if isinstance(maxd, float) and maxd != int(maxd):  # Flutter fractions
                bucket = ("<1" if maxd < 1 else "1-2" if maxd < 2 else "2-3" if maxd < 3 else
                          "3-9" if maxd < 10 else "10+")
            else:
                bucket = "1" if maxd == 1 else ("2" if maxd == 2 else ("3-9" if maxd < 10 else "10+"))
            deltas[bucket] += 1
        else:
            lines, maxd = ["status %s != %s (frames equal)" % (a.gstatus, b.gstatus)], 0
            deltas["status only"] += 1
        mism.append(aid)
        if len(examples) < o["show"]:
            examples.append((aid, bid, a, b, lines))
    only_b = sum(1 for k in B if k not in seen_b)

    out = sys.stdout
    out.write("vcompare A=%s (%s) B=%s (%s) level %s helpers %s\n" % (
        o["files"][0], kind_a, o["files"][1], kind_b, o["level"], o["helpers"]))
    out.write("  layouts: A %d, B %d, compared %d, equal %d, DIFFER %d, missing in B %d, only in B %d\n" % (
        len(A), len(B), counts["compared"], counts["equal"], counts["differ"],
        counts["missing in B"], only_b))
    if o["skip"]:
        out.write("  skipped generators %s: A %d, B %d\n" % (
            ",".join(o["skip"]), skipped["A"], skipped["B"]))
    ex_txt = ", ".join("%s %d%s" % (k, excluded[k], "" if k in o["exclude"] else " (compared)")
                       for k in CLASSES)
    out.write("  excluded classes (B side; UNMAPPED on either side): %s\n" % ex_txt)
    if unmapped:
        out.write("    UNMAPPED reasons: %s\n" % dict(unmapped.most_common()))
    for k in CLASSES:
        if excluded_ex[k]:
            out.write("    %s e.g. %s\n" % (k, " ".join(excluded_ex[k])))
    if status_diff:
        out.write("  status pairs that differ (A/B, compared rows): %s\n" % dict(status_diff))
    if deltas:
        out.write("  largest delta per differing layout: %s\n" % dict(deltas))
    if not o["quiet"]:
        out.write("  per generator (compared / differ / excluded / missing):\n")
        for gen in sorted(by_gen):
            c = by_gen[gen]
            exc = sum(v for k, v in c.items() if k.startswith("excl:"))
            out.write("    %-16s %7d %7d %7d %7d\n" % (gen, c["compared"], c["differ"], exc, c["missing"]))
        for aid, bid, a, b, lines in examples:
            out.write("  --- %s%s  A %s  B %s\n" % (aid, "" if aid == bid else " vs " + bid, a.gstatus, b.gstatus))
            for l in lines:
                out.write("      %s\n" % l)
    if o["mismatch_ids"]:
        with open(o["mismatch_ids"], "w") as f:
            for k in mism:
                f.write(k + "\n")
    if o["mismatch_in"]:
        src = A if kind_a == "vfuzz" else (B if kind_b == "vfuzz" else None)
        if src is None:
            sys.stderr.write("vcompare: --mismatch-in needs a vfuzz input; not written\n")
        else:
            with open(o["mismatch_in"], "w") as f:
                for k in mism:
                    r = src.get(k if src is A else b_id(k))
                    if r is not None and r.line:
                        f.write(r.line + "\n")
    bad = counts["differ"] > 0 or (o["strict"] and (counts["missing in B"] or only_b))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
