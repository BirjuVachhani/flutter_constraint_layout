"""dirty_split.py (FORMATS.md 19.2): splits a DirtyTwice output (`id \t first \t second`) into two Java result
files (`id \t ok \t geometry`, FORMATS.md 2) for vcompare: <out>.first.java
and <out>.second.java. HANG and THREW lines keep their status. Prints the
number of layouts whose second layout differs from the first."""
import sys
src = sys.argv[1]
n = differ = bad = 0
with open(src + '.first.java', 'w') as f1, open(src + '.second.java', 'w') as f2:
    for line in open(src):
        p = line.rstrip('\n').split('\t')
        n += 1
        if len(p) != 3:
            st = p[1] if len(p) > 1 else 'HANG'
            if st.startswith('THREW'):
                st = 'EXC:' + st[6:]
            f1.write(f'{p[0]}\t{st}\n'); f2.write(f'{p[0]}\t{st}\n'); bad += 1
            continue
        f1.write(f'{p[0]}\tok\t{p[1]}\n'); f2.write(f'{p[0]}\tok\t{p[2]}\n')
        if p[1] != p[2]:
            differ += 1
print(f'{src}: layouts {n}, second != first {differ}, HANG/THREW {bad}')
