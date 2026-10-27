#!/usr/bin/env python3
"""tracediff: first divergence between a Dart and a Java solver trace (FORMATS.md 7, 7b).

  tracediff.py <A.trace> <B.trace> [--kinds K1,K2] [--ignore K1,K2] [--max N]
               [--context N] [--only ID[,ID...]] [--ids-out FILE] [--quiet]

Both files use TraceJava's grammar: one event per line, a `T <layoutId> <level>
<build>` line opening each layout and `E` closing it. Floats are `%08x` raw binary32
bits. The files are split into T blocks, blocks are matched by (layoutId, level, build),
and the events of each pair are compared in order. For each diverging layout it prints
the index of the first diverging event, both lines (floats decoded), the solver context
(the last PS, M, MZ and RS events before it) and the events just before it. Lines
before the first T are ignored.

--kinds keeps only the listed event kinds in both streams, --ignore drops them (for
instance --ignore O to skip value readbacks). --only restricts to some layout ids.
--ids-out writes one line per diverging layout: id, level, build, the index of the first
diverging event and its kinds (A/B), tab-separated.
Exit status: 0 when every matched block is identical and both files have the same
blocks, 1 otherwise, 2 on usage errors.
"""
import re
import struct
import sys
from collections import Counter

USAGE = __doc__.split("\n\n")[1]
HEX8 = re.compile(r"^[0-9a-f]{8}$")
CONTEXT_KINDS = ("PS", "M", "MZ", "RS")


def die(msg):
    sys.stderr.write("tracediff: %s\n%s\n" % (msg, USAGE))
    sys.exit(2)


def parse_args(argv):
    o = {"files": [], "kinds": None, "ignore": set(), "max": 20, "context": 6,
         "only": None, "quiet": False, "ids_out": None}
    i = 0
    while i < len(argv):
        a = argv[i]
        def val():
            if i + 1 >= len(argv):
                die("%s needs a value" % a)
            return argv[i + 1]
        if a == "--kinds":
            o["kinds"] = set(val().split(",")); i += 2
        elif a == "--ignore":
            o["ignore"] = set(val().split(",")); i += 2
        elif a == "--max":
            o["max"] = int(val()); i += 2
        elif a == "--context":
            o["context"] = int(val()); i += 2
        elif a == "--only":
            o["only"] = set(val().split(",")); i += 2
        elif a == "--ids-out":
            o["ids_out"] = val(); i += 2
        elif a == "--quiet":
            o["quiet"] = True; i += 1
        elif a.startswith("--"):
            die("unknown option %s" % a)
        else:
            o["files"].append(a); i += 1
    if len(o["files"]) != 2:
        die("two trace files are needed")
    return o


def index_blocks(path):
    """[(key, start_offset, end_offset)] in file order, key = (id, level, build)."""
    blocks = []
    key, start = None, None
    with open(path, "rb") as f:
        while True:
            pos = f.tell()
            raw = f.readline()
            if not raw:
                break
            if raw.startswith(b"T "):
                if key is not None:
                    blocks.append((key, start, pos))
                p = raw.decode("ascii", "replace").split()
                key = tuple(p[1:4]) if len(p) >= 4 else tuple(p[1:])
                start = pos
        if key is not None:
            blocks.append((key, start, f.tell()))
    return blocks


def read_block(f, start, end):
    f.seek(start)
    data = f.read(end - start).decode("ascii", "replace")
    return [l for l in data.split("\n") if l]


def keep(line, o):
    k = line.split(" ", 1)[0]
    if k in ("T", "E"):
        return True
    if o["kinds"] is not None and k not in o["kinds"]:
        return False
    return k not in o["ignore"]


def decode(line):
    """The line with every 8-hex-digit token followed by its binary32 value."""
    out = []
    for tok in line.split(" "):
        head, sep, tail = tok.rpartition(":")
        cand = tail if sep else tok
        if HEX8.match(cand):
            v = struct.unpack(">f", bytes.fromhex(cand))[0]
            out.append("%s(%r)" % (tok, v))
        else:
            out.append(tok)
    return " ".join(out)


def main(argv):
    o = parse_args(argv)
    fa, fb = o["files"]
    ia, ib = index_blocks(fa), index_blocks(fb)
    da = {}
    for key, s, e in ia:
        da.setdefault(key, (s, e))
    db = {}
    for key, s, e in ib:
        db.setdefault(key, (s, e))
    dup = (len(ia) - len(da)) + (len(ib) - len(db))
    keys = [k for k, _, _ in ia if k in db]
    seen = set()
    keys = [k for k in keys if not (k in seen or seen.add(k))]
    if o["only"] is not None:
        keys = [k for k in keys if k[0] in o["only"]]
    only_a = [k for k in da if k not in db]
    only_b = [k for k in db if k not in da]
    stats = Counter()
    kinds = Counter()
    reports = 0
    diverging = []
    out = sys.stdout
    with open(fa, "rb") as A, open(fb, "rb") as B:
        for key in keys:
            ea = [l for l in read_block(A, *da[key]) if keep(l, o)]
            eb = [l for l in read_block(B, *db[key]) if keep(l, o)]
            stats["compared"] += 1
            n = min(len(ea), len(eb))
            i = 0
            while i < n and ea[i] == eb[i]:
                i += 1
            if i == len(ea) == len(eb):
                stats["identical"] += 1
                continue
            stats["diverging"] += 1
            kind_b = eb[i].split(" ", 1)[0] if i < len(eb) else "<end>"
            kind_a = ea[i].split(" ", 1)[0] if i < len(ea) else "<end>"
            kinds["%s/%s" % (kind_a, kind_b)] += 1
            diverging.append((key, i, "%s/%s" % (kind_a, kind_b)))
            if o["quiet"] or reports >= o["max"]:
                continue
            reports += 1
            out.write("=== %s level %s build %s: first divergence at event %d (A %d events, B %d)\n"
                      % (key[0], key[1] if len(key) > 1 else "?", key[2] if len(key) > 2 else "?",
                         i, len(ea), len(eb)))
            ctx = {}
            for l in ea[:i]:
                k = l.split(" ", 1)[0]
                if k in CONTEXT_KINDS:
                    ctx[k] = l
            if ctx:
                out.write("  context: %s\n" % " | ".join(ctx[k] for k in CONTEXT_KINDS if k in ctx))
            for l in ea[max(0, i - o["context"]):i]:
                out.write("    = %s\n" % decode(l))
            out.write("  A %s\n" % (decode(ea[i]) if i < len(ea) else "<end of block>"))
            out.write("  B %s\n" % (decode(eb[i]) if i < len(eb) else "<end of block>"))
    out.write("tracediff: blocks A %d, B %d; compared %d, identical %d, diverging %d; "
              "only in A %d, only in B %d; duplicate keys %d\n"
              % (len(ia), len(ib), stats["compared"], stats["identical"], stats["diverging"],
                 len(only_a), len(only_b), dup))
    if kinds:
        out.write("  first diverging kinds (A/B): %s\n" % dict(kinds.most_common()))
    for name, lst in (("only in A", only_a), ("only in B", only_b)):
        if lst:
            out.write("  %s, e.g.: %s\n" % (name, ", ".join(" ".join(k) for k in lst[:5])))
    if o["ids_out"]:
        with open(o["ids_out"], "w") as f:
            for key, i, k in diverging:
                f.write("%s\t%s\t%s\t%d\t%s\n" % (key[0], key[1] if len(key) > 1 else "?",
                                                  key[2] if len(key) > 2 else "?", i, k))
    bad = stats["diverging"] or only_a or only_b
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
