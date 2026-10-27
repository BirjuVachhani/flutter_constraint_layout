#!/usr/bin/env python3
"""keepbl: an in-place corpus without its in-place `bl N 0` and `hbl N 0` ops.

  keepbl.py <in> <out>

T-inplace and T2-inplace (dart/temit.dart, emitInPlaceT) write, after each mid-list `L`,
the baseline distance 0 and the baseline flag false of every regular widget (`bl N 0`,
`hbl N 0`): the in-place path of an earlier adapter, which cleared them between states.
Neither Android's view layer nor the current adapter does: ConstraintWidget.reset()
keeps mHasBaseline, and the layout params set it again only for a widget with a baseline
link. The RoboOracle never reads these ops, so its output is the same with or without
them; the engine reads them, and on 70 T2-inplace sequences at 64 and 321 (79 at 192
and 449) they decide the layout. The in-place gate (gates/inplace_gates.sh) runs both
sides on this corpus. Every line is copied with the ops after its first `L` filtered;
the line count and the dropped ops are printed.
"""
import sys

if len(sys.argv) != 3:
    sys.stderr.write(__doc__.split("\n\n")[1] + "\n")
    sys.exit(2)
src, dst = sys.argv[1], sys.argv[2]
n = 0
dropped = {"bl": 0, "hbl": 0}
with open(src) as f, open(dst, "w") as o:
    for line in f:
        fields = line.rstrip("\n").split("\t")
        out = []
        seen_l = False
        for op in fields[-1].split(";"):
            if op == "L":
                seen_l = True
            t = op.split(" ")
            if seen_l and t[0] in ("bl", "hbl") and len(t) == 3 and t[2] == "0":
                dropped[t[0]] += 1
                continue
            out.append(op)
        fields[-1] = ";".join(out)
        o.write("\t".join(fields) + "\n")
        n += 1
print("keepbl: %d lines; dropped after the first L: bl %d, hbl %d" % (n, dropped["bl"], dropped["hbl"]))
