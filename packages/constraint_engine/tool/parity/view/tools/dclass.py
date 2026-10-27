"""Classify geometry differences between a Java-side file (a) and RoboOracle (b).

Usage: python3 -I dclass.py <a.java> <b.robo> <corpus.txt> [--show N] [--class C]

For each layout whose geometry differs, every differing child is tagged:
  gsize  a guideline whose position is equal and only the size differs
  guide  a guideline whose position differs
  barrier, widget, root
A layout is 'gsize-only' when every differing child is gsize. Prints counts per
generator and per class, and examples.
"""
import sys


def load(path, col=3):
    out = {}
    for line in open(path, encoding='utf-8'):
        f = line.rstrip('\n').split('\t')
        if len(f) < 2:
            continue
        out[f[0]] = (f[1], f[col - 1] if len(f) >= col else '-')
    return out


def kinds(ops):
    k = {}
    for op in ops.split(';'):
        t = op.split(' ')
        if t[0] in ('g', 'b', 'w', 'fl'):
            k[t[1]] = {'g': 'guide', 'b': 'barrier', 'w': 'widget', 'fl': 'flow'}[t[0]]
    return k


def parse(geom):
    parts = geom.split(' | ')
    d = {}
    for p in parts:
        if p.startswith('root '):
            d['root'] = p
        elif ': ' in p:
            n, v = p.split(': ', 1)
            d[n] = v
        else:
            d[p] = p
    return d


def pos(v):
    return v.split(')')[0] if v.startswith('(') else v


def main():
    args = sys.argv[1:]
    show, only = 3, None
    if '--show' in args:
        i = args.index('--show'); show = int(args[i + 1]); del args[i:i + 2]
    if '--class' in args:
        i = args.index('--class'); only = args[i + 1]; del args[i:i + 2]
    a, b = load(args[0]), load(args[1])
    corpus = {}
    for line in open(args[2], encoding='utf-8'):
        f = line.rstrip('\n').split('\t')
        corpus[f[0]] = f[-1]
    per = {}
    examples = {}
    totals = {}
    for i, (sb, gb) in b.items():
        if i not in a or sb.startswith('UNMAPPED'):
            continue
        sa, ga = a[i]
        if ga == gb:
            continue
        k = kinds(corpus.get(i, ''))
        da, db = parse(ga), parse(gb)
        tags = set()
        for n in set(da) | set(db):
            va, vb = da.get(n), db.get(n)
            if va == vb:
                continue
            kind = 'root' if n == 'root' else k.get(n, '?')
            if kind == 'guide' and va and vb and pos(va) == pos(vb):
                tags.add('gsize')
            else:
                tags.add(kind)
        cls = 'gsize-only' if tags == {'gsize'} else '+'.join(sorted(tags - {'gsize'}))
        gen = i.rsplit(':', 1)[0]
        per.setdefault(gen, {}).setdefault(cls, 0)
        per[gen][cls] += 1
        totals[cls] = totals.get(cls, 0) + 1
        examples.setdefault(cls, []).append(i)
    for cls in sorted(totals, key=lambda c: -totals[c]):
        print('%-28s %6d' % (cls, totals[cls]))
    print()
    for gen in sorted(per):
        print(gen, ', '.join('%s %d' % (c, n) for c, n in sorted(per[gen].items(), key=lambda x: -x[1])))
    for cls in sorted(totals):
        if only and cls != only:
            continue
        for i in examples[cls][:show]:
            print('\nEX', cls, i)
            da, db = parse(a[i][1]), parse(b[i][1])
            for n in sorted(set(da) | set(db)):
                if da.get(n) != db.get(n):
                    print('   %-10s a: %s' % (n, da.get(n)))
                    print('   %-10s b: %s' % ('', db.get(n)))


main()
