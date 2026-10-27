"""Stratified sample of corpus lines (p0-view).

Usage: python3 -I sample.py <out> <perGen> <skipGen,...> <corpus>...
Writes the first <perGen> lines of every generator (the id before the last
':') found in the corpus files, skipping the listed generators, in file order.
"""
import sys


def main():
    out, per, skip = sys.argv[1], int(sys.argv[2]), set(filter(None, sys.argv[3].split(',')))
    counts = {}
    with open(out, 'w', encoding='utf-8') as o:
        for path in sys.argv[4:]:
            with open(path, encoding='utf-8') as f:
                for line in f:
                    if not line.strip():
                        continue
                    gid = line.split('\t', 1)[0]
                    gen = gid.rsplit(':', 1)[0]
                    if gen in skip or counts.get(gen, 0) >= per:
                        continue
                    counts[gen] = counts.get(gen, 0) + 1
                    o.write(line if line.endswith('\n') else line + '\n')
    for g in sorted(counts):
        print(g, counts[g])
    print('total', sum(counts.values()))


main()
