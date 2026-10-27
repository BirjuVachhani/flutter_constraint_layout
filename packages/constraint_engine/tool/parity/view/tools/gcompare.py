"""Compare geometry by id between two result files (p0-view helper).

Usage: python3 -I gcompare.py <a> <b> [--show N] [--acol K] [--bcol K]

Each file is either a section 1 corpus/result line (id, features, path,
status, geometry, ops: geometry is field 5) or a Java result line (id,
status, geom...: geometry is field 3). The format is detected per line by
the field count unless --acol/--bcol give the 1-based geometry field. Lines
whose status is UNMAPPED, HANG, ND or EXC (outside the geometry) are counted
by class and not compared.
"""
import sys


def load(path, col):
    out = {}
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if not line or line.startswith('#'):
            continue
        f = line.split('\t')
        if col:
            status = f[1] if len(f) < 6 else f[3]
            geom = f[col - 1] if len(f) >= col else '-'
        elif len(f) >= 6:
            status, geom = f[3], f[4]
        else:
            status = f[1]
            geom = f[2] if len(f) > 2 else '-'
        out[f[0]] = (status, geom)
    return out


def klass(status):
    for k in ('UNMAPPED', 'HANG', 'ND', 'EXC', 'SO'):
        if status.startswith(k):
            return k
    return None


def main():
    args = sys.argv[1:]
    show = 5
    acol = bcol = 0
    if '--show' in args:
        i = args.index('--show'); show = int(args[i + 1]); del args[i:i + 2]
    if '--acol' in args:
        i = args.index('--acol'); acol = int(args[i + 1]); del args[i:i + 2]
    if '--bcol' in args:
        i = args.index('--bcol'); bcol = int(args[i + 1]); del args[i:i + 2]
    a, b = load(args[0], acol), load(args[1], bcol)
    common = [k for k in a if k in b]
    excluded = {}
    same = diff = 0
    shown = 0
    for k in common:
        sa, ga = a[k]
        sb, gb = b[k]
        ka, kb = klass(sa), klass(sb)
        if ka or kb:
            key = 'a:' + (ka or 'ok') + ' b:' + (kb or 'ok')
            excluded[key] = excluded.get(key, 0) + 1
            continue
        if ga == gb:
            same += 1
        else:
            diff += 1
            if shown < show:
                shown += 1
                print('DIFF', k)
                pa = ga.split(' | ')
                pb = gb.split(' | ')
                for x, y in zip(pa, pb):
                    if x != y:
                        print('   a:', x)
                        print('   b:', y)
    print('common %d, compared %d, equal %d, differ %d, only-a %d, only-b %d' % (
        len(common), same + diff, same, diff, len(a) - len(common), len(b) - len(common)))
    for k in sorted(excluded):
        print('  excluded', k, excluded[k])


main()
