#!/usr/bin/env python3
"""vstats: Phase 0 statistics from VOpDriver's DirectProbe field (FORMATS.md 8.3).

  vstats.py <java.txt> [<java.txt> ...] [--level 257] [--by gen|group|none]
            [--label NAME]

Reads VOpDriver result lines (`id \\t status \\t geom... \\t P<level> ...`) run with
-Dprobe, and reports, per group of layouts:

- the share where Direct resolves every axis (`res=a/n` with a == n);
- the distribution of the residual system at pass 0's first minimize(): stored rows,
  variables, free (non-final) variables and goal entries;
- the pass count and the solver-loop iterations per pass;
- the share with a trivial first iteration (`triv=1`: no stored row, empty goal);
- measurer calls, cache hits, too-small flags and printed exceptions.

--by gen groups by generator (the id before ':'), --by group by corpus group (R's bar
and nob halves, VR's, T's and A's), --by none reports one total. Lines without a P
field for the level (HANG, a thrown layout) are counted apart.
"""
import re
import sys
from collections import Counter, defaultdict

BAR = {"fflist", "ffrtl", "ffsettings", "ffchat", "fftoolbar", "rscform", "rsccards", "rscnest"}
NOB = {"fnlist", "fnrtl", "fnsettings", "fnchat", "fntoolbar", "nbrscform", "nbrsccards", "nbrscnest"}
KV = re.compile(r"(\w+)=(\S+)")


def group_of(gen, by):
    if by == "none":
        return "all"
    if by == "gen":
        return gen
    base = gen[3:] if gen.startswith("VR-") else gen
    prefix = "VR " if gen.startswith("VR-") else ("R " if gen in BAR or gen in NOB else "")
    if base in BAR:
        return prefix + "bar"
    if base in NOB:
        return prefix + "nob"
    if gen.startswith("T-"):
        return "T"
    if gen.startswith("A-"):
        return "A"
    return "other"


def parse_p(field):
    """The key=value pairs of a P field (excs, which can hold spaces, dropped)."""
    head = field.split(" excs=", 1)[0]
    return dict(KV.findall(head))


def pct(xs, q):
    if not xs:
        return "-"
    xs = sorted(xs)
    i = min(len(xs) - 1, int(round(q * (len(xs) - 1))))
    return str(xs[i])


def buckets(xs, edges=(0, 4, 16, 64, 256)):
    out = Counter()
    for x in xs:
        if x == 0:
            out["0"] += 1
            continue
        lo = 1
        for e in edges[1:]:
            if x <= e:
                out["%d-%d" % (lo, e)] += 1
                break
            lo = e + 1
        else:
            out["%d+" % (edges[-1] + 1)] += 1
    order = ["0"] + ["%d-%d" % (a + 1 if a else 1, b) for a, b in zip(edges, edges[1:])] + ["%d+" % (edges[-1] + 1)]
    return " ".join("%s:%d" % (k, out[k]) for k in order if out[k])


class Acc:
    def __init__(self):
        self.n = 0
        self.nop = 0
        self.status = Counter()
        self.res_all = 0
        self.res_known = 0
        self.axes_unres = []
        self.rows, self.vars, self.free, self.goal = [], [], [], []
        self.passes = Counter()
        self.it_first = Counter()
        self.multi_it = 0
        self.it_total = []
        self.triv = Counter()
        self.meas, self.hits = [], []
        self.ts = Counter()
        self.exc = 0

    def add(self, status, p):
        self.n += 1
        self.status[status] += 1
        res = p.get("res", "-")
        if res != "-" and "/" in res:
            a, b = res.split("/")
            self.res_known += 1
            if a == b:
                self.res_all += 1
            self.axes_unres.append(int(b) - int(a))
        for key, lst in (("rows", self.rows), ("vars", self.vars), ("free", self.free), ("goal", self.goal)):
            v = p.get(key, "-")
            if v != "-":
                lst.append(int(v))
        self.passes[p.get("passes", "?")] += 1
        its = p.get("it", "")
        if its:
            parts = [int(x) for x in its.split(",") if x.isdigit()]
            if parts:
                self.it_first[parts[0]] += 1
                self.it_total.append(sum(parts))
                if any(x > 1 for x in parts):
                    self.multi_it += 1
        self.triv[p.get("triv", "?")] += 1
        for key, lst in (("meas", self.meas), ("hits", self.hits)):
            v = p.get(key, "")
            if v.isdigit():
                lst.append(int(v))
        self.ts[p.get("ts", "?")] += 1
        if p.get("exc", "0") not in ("0", ""):
            self.exc += 1

    def report(self, name, out):
        def share(k, n):
            return "%d (%.2f%%)" % (k, 100.0 * k / n) if n else "%d" % k
        out.write("== %s: %d layouts with a P field, %d without\n" % (name, self.n, self.nop))
        if self.n == 0:
            return
        out.write("  status: %s\n" % dict(self.status.most_common()))
        out.write("  Direct resolves every axis: %s of %d with Direct\n"
                  % (share(self.res_all, self.res_known), self.res_known))
        if self.axes_unres:
            out.write("    unresolved axes per layout: p50 %s p90 %s p99 %s max %s; %s\n" % (
                pct(self.axes_unres, .5), pct(self.axes_unres, .9), pct(self.axes_unres, .99),
                max(self.axes_unres), buckets(self.axes_unres)))
        for name_, lst in (("rows", self.rows), ("vars", self.vars), ("free vars", self.free), ("goal", self.goal)):
            if lst:
                out.write("  residual %-9s p50 %s p90 %s p99 %s max %s mean %.1f; %s\n" % (
                    name_, pct(lst, .5), pct(lst, .9), pct(lst, .99), max(lst), sum(lst) / len(lst), buckets(lst)))
        out.write("  passes: %s\n" % " ".join("%s:%s" % (k, share(v, self.n)) for k, v in sorted(self.passes.items())))
        out.write("  iterations in pass 0: %s\n" % " ".join("%s:%d" % (k, v) for k, v in sorted(self.it_first.items())))
        if self.it_total:
            out.write("  iterations, all passes: p50 %s p90 %s max %s; a pass with more than one: %s\n" % (
                pct(self.it_total, .5), pct(self.it_total, .9), max(self.it_total), share(self.multi_it, self.n)))
        out.write("  trivial first iteration: %s (triv values %s)\n" % (share(self.triv.get("1", 0), self.n), dict(self.triv)))
        if self.meas:
            out.write("  measurer calls: p50 %s p90 %s max %s mean %.1f; cache hits mean %.2f\n" % (
                pct(self.meas, .5), pct(self.meas, .9), max(self.meas), sum(self.meas) / len(self.meas),
                (sum(self.hits) / len(self.hits)) if self.hits else 0.0))
        out.write("  too-small flags: %s; printed exceptions: %d\n" % (dict(self.ts), self.exc))


def main(argv):
    files, level, by, label = [], "257", "group", None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--level":
            level = argv[i + 1]; i += 2
        elif a == "--by":
            by = argv[i + 1]; i += 2
        elif a == "--label":
            label = argv[i + 1]; i += 2
        elif a.startswith("--"):
            sys.stderr.write(__doc__)
            return 2
        else:
            files.append(a); i += 1
    if not files:
        sys.stderr.write(__doc__)
        return 2
    tag = "P%s " % level
    accs = defaultdict(Acc)
    total = Acc()
    for fn in files:
        with open(fn, encoding="utf-8", errors="replace") as f:
            for raw in f:
                p = raw.rstrip("\n").split("\t")
                if len(p) < 2:
                    continue
                gen = p[0].rpartition(":")[0]
                g = group_of(gen, by)
                field = next((x for x in p[2:] if x.startswith(tag)), None)
                if field is None:
                    accs[g].nop += 1
                    total.nop += 1
                    continue
                kv = parse_p(field[len(tag):])
                accs[g].add(p[1], kv)
                total.add(p[1], kv)
    out = sys.stdout
    out.write("vstats %s level %s (%s)\n" % (label or " ".join(files), level, by))
    for g in sorted(accs):
        accs[g].report(g, out)
    if len(accs) > 1:
        total.report("total", out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
