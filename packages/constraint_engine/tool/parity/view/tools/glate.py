"""Counts op lists that link to a guideline before orienting it (p0-view).

Usage: python3 -I glate.py <corpus.txt> [ids.txt]
A core Guideline is horizontal until `go` runs, so `c X L|R g ...` before
`go g 1` (or `c X T|B g ...` on a guideline later made vertical) finds no
anchor and the link is dropped; Android and today's adapter orient a
guideline when it is created, so they keep the link. Prints counts per
generator; with ids, also how many of those ids are affected.
"""
import sys
ids = set(l.strip().split('\t')[0] for l in open(sys.argv[2])) if len(sys.argv) > 2 else None
per, hit = {}, {}
for line in open(sys.argv[1]):
    f = line.rstrip('\n').split('\t')
    gen = f[0].rsplit(':', 1)[0]
    oriented, guides, late = {}, set(), False
    for op in f[-1].split(';'):
        t = op.split(' ')
        if t[0] == 'g':
            guides.add(t[1]); oriented[t[1]] = 0
        elif t[0] == 'go':
            oriented[t[1]] = int(t[2])
        elif t[0] == 'c' and len(t) > 4 and t[3] in guides:
            vertical_target = t[4] in ('L', 'R')
            if vertical_target != (oriented.get(t[3], 0) == 1):
                late = True
    key = f[0].replace('T-fresh:', 'T-inplace:')
    per[gen] = per.get(gen, 0) + (1 if late else 0)
    if ids is not None and late and key in ids:
        hit[gen] = hit.get(gen, 0) + 1
for g in sorted(per):
    print(g, 'lists linking to a not-yet-oriented guideline:', per[g], ('of the given ids: %d' % hit.get(g, 0)) if ids is not None else '')
