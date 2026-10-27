"""Streaming version of dclass.py for full corpora (p0-view).

Usage: python3 -I dstream.py <a.java> <b.robo> <corpus.txt> [--show N]
The three files must list the same ids in the same order (VOpDriver batch and
RoboOracle both keep the corpus order). Counts, per generator: compared,
equal, gsize-only (only a guideline's reported size differs), other
differences by child kind, and excluded statuses (UNMAPPED on b; HANG, ND or
EXC on a).
"""
import sys


def kinds(ops):
    k = {}
    for op in ops.split(';'):
        t = op.split(' ')
        if len(t) > 1 and t[0] in ('g', 'b', 'w', 'fl'):
            k[t[1]] = {'g': 'guide', 'b': 'barrier', 'w': 'widget', 'fl': 'flow'}[t[0]]
    return k


def parse(geom):
    d = {}
    for p in geom.split(' | '):
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
    show = 3
    if '--show' in args:
        i = args.index('--show'); show = int(args[i + 1]); del args[i:i + 2]
    fa, fb, fc = (open(p, encoding='utf-8') for p in args[:3])
    stats = {}
    examples = {}
    for la, lb, lc in zip(fa, fb, fc):
        a = la.rstrip('\n').split('\t')
        b = lb.rstrip('\n').split('\t')
        c = lc.rstrip('\n').split('\t')
        if not (a[0] == b[0] == c[0]):
            print('ORDER MISMATCH', a[0], b[0], c[0])
            return
        gen = a[0].rsplit(':', 1)[0]
        s = stats.setdefault(gen, {})
        sb = b[1]
        sa = a[1]
        if sb.startswith('UNMAPPED'):
            key = 'excl:' + sb
        elif sa != 'ok' and not sa.startswith('ok'):
            key = 'excl:a-' + sa.split(':')[0]
        else:
            ga, gb = a[2], b[2]
            if ga == gb:
                key = 'equal'
            else:
                k = kinds(c[-1])
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
                key = 'gsize-only' if tags == {'gsize'} else 'DIFF:' + '+'.join(sorted(tags - {'gsize'}))
                if key.startswith('DIFF') and len(examples.setdefault(key, [])) < show:
                    examples[key].append((a[0], ga, gb))
        s[key] = s.get(key, 0) + 1
    tot = {}
    for gen in sorted(stats):
        for k, v in stats[gen].items():
            tot[k] = tot.get(k, 0) + v
        print(gen, ' '.join('%s=%d' % kv for kv in sorted(stats[gen].items())))
    print('TOTAL', ' '.join('%s=%d' % kv for kv in sorted(tot.items())))
    for key, exs in examples.items():
        for i, ga, gb in exs:
            print('\nEX', key, i)
            da, db = parse(ga), parse(gb)
            for n in sorted(set(da) | set(db)):
                if da.get(n) != db.get(n):
                    print('   %-10s a: %s' % (n, da.get(n)))
                    print('   %-10s b: %s' % ('', db.get(n)))


main()
