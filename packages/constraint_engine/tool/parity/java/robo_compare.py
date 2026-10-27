#!/usr/bin/env python3
"""robo_compare.py <vop.java> <robo.out>: VOpDriver's view path (levels 257) against
RoboOracle (FORMATS.md 10). Compares status and the 257 geometry per id; skips ids the
RoboOracle marked UNMAPPED. Run with python3 -I."""
import sys
def load(f):
    d = {}
    for line in open(f):
        p = line.rstrip('\n').split('\t')
        d[p[0]] = p[1:3]
    return d
vop, robo = load(sys.argv[1]), load(sys.argv[2])
same = diff = unmapped = missing = 0
shown = 0
for i, r in robo.items():
    if r[0].startswith('UNMAPPED'):
        unmapped += 1
        continue
    v = vop.get(i)
    if v is None:
        missing += 1
        continue
    if v == r:
        same += 1
    else:
        diff += 1
        if shown < 6:
            shown += 1
            print('DIFF', i)
            print('  VOP ', v)
            print('  ROBO', r)
print(f'robo {len(robo)}, unmapped {unmapped}, missing in VOpDriver {missing}, '
      f'identical {same}, different {diff}')
