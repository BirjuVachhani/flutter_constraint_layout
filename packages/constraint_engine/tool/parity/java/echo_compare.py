#!/usr/bin/env python3
"""echo_compare.py <vop.out> <bl_java.txt> [levels]: VOpDriver (core path) against BL's
OpDriver results. Compares, per id, the status and the geometry fields of each level
(fields 2.. of both files). Prints counts and the first differences. Run with python3 -I."""
import sys
vop, bl = sys.argv[1], sys.argv[2]
nlev = len(sys.argv[3].split(',')) if len(sys.argv) > 3 else 2
mine = {}
for line in open(vop):
    p = line.rstrip('\n').split('\t')
    mine[p[0]] = p[1:2 + nlev]
seen = same = diff = 0
shown = 0
for line in open(bl):
    tab = line.find('\t')
    i = line[:tab]
    m = mine.get(i)
    if m is None:
        continue
    seen += 1
    q = line.rstrip('\n').split('\t')[1:2 + nlev]
    if q == m:
        same += 1
    else:
        diff += 1
        if shown < 5:
            shown += 1
            print('DIFF', i)
            for k in range(len(q)):
                if k >= len(m) or q[k] != m[k]:
                    print('  BL ', q[k][:300])
                    print('  VOP', (m[k] if k < len(m) else '<missing>')[:300])
missing = len(mine) - seen
statuses = {}
for v in mine.values():
    statuses[v[0]] = statuses.get(v[0], 0) + 1
print(f'VOpDriver lines {len(mine)}, matched in BL {seen}, missing in BL {missing}, '
      f'identical {same}, different {diff}, statuses {statuses}')
