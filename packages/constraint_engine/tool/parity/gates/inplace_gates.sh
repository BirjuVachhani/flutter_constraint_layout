#!/bin/bash
# inplace_gates.sh: the in-place gate. T2's in-place sequences (T2-inplace,
# 50,000), each state applied to the same widgets: the engine of this
# checkout through ViewHost (vfuzz view<level>: every mid-list L op is one
# ViewHost.measure, Android's dirty path) against Android's live views (the
# RoboOracle with -Drobo.inplace=1: every state's LayoutParams set again on
# the same views, so every measure takes the dirty path; FORMATS.md 10), at
# each level. Target, at every level: 0 differences in place and in the
# second layout outside the excluded classes, and the engine throws on
# exactly the sequences the live views throw on, at the same state.
#   inplace_gates.sh <outdir> [levels]   (default "0 64 192 256 257 321 449")
# The corpus is T2-inplace cut from $CL_CORPORA/T2.in without its in-place
# `bl N 0` and `hbl N 0` ops (compare/keepbl.py): they model an earlier
# adapter's in-place path, which cleared the baseline flags; neither Android
# nor the current adapter does, and the live views never read them. The
# fresh builds of the final states (T2-fresh) run too.
# Per level <lv>, in <outdir>:
#   TIP2.L<lv>.robo, .robo.fresh, .robo.twice  the live views in place, a fresh
#             build of each final state, and the dirty second layout of the
#             in-place views (-Drobo.twice=dirty: a child requests layout)
#   TIP2.view<lv>.isg   the engine in place (id, status, geometry), with
#             --twice-links; TIP2.view<lv>.second its second layouts
#   T2F.view<lv>.isg    the engine's fresh builds of the final states
#   inplace.L<lv>.txt   engine in place against the live views in place
#             (vcompare --strict --helpers full; JEXC and UNMAPPED excluded and
#             counted); .ids the differing ids
#   second.L<lv>.txt    engine second layout against the live views' dirty
#             second layout
#   fresh.L<lv>.txt     engine fresh builds against the live views' fresh builds
#   history.L<lv>.txt   (not a gate) live views in place against their own fresh
#             builds: the sequences whose in-place layout keeps history
#   throws.L<lv>.txt    the sequences each side threw on, and at which state:
#             the engine runs each one's states before the final one again
#             (TIP2.pre<lv>.in) to tell an earlier state from the final one
# summary.tsv gets one line per level. Needs $CL_BIN/vfuzz.exe, the RoboOracle
# (view/fetch.sh, $CL_ROBO) and $CL_CORE; every heavy step goes through
# `heavy` (env.sh). The live views take about 15 s per level, the engine 10 s.
set -u
. "$(dirname "$0")/../env.sh"
G=${1:?usage: inplace_gates.sh <outdir> [levels]}
LEVELS=${2:-"0 64 192 256 257 321 449"}
mkdir -p "$G"; G=$(cd "$G" && pwd)
B=$CL_BIN; C=$CL_CORPORA
CMP=$CL_TOOLS/compare
VC="nice -n 10 python3 -I $CMP/vcompare.py"
need "$B/vfuzz.exe" "$C/T2.in" "$CL_CORE"
cd "$G" || exit 2
if [ ! -s TIP2.keepbl.in ] || [ ! -s T2F.in ]; then
  grep '^T2-inplace:' "$C/T2.in" > TIP2.in
  grep '^T2-fresh:' "$C/T2.in" > T2F.in
  nice -n 10 python3 -I "$CMP/keepbl.py" TIP2.in TIP2.keepbl.in | sed 's/^/   /'
  rm -f TIP2.in
fi
[ -s summary.tsv ] || printf 'level\tcompared\tdiffer\tJEXC\tUNMAPPED\tsecond_differ\tfresh_differ\tthrows_engine\tthrows_android\tthrows_same\tearlier_engine\tearlier_android\tearlier_same\thistory\n' > summary.tsv
line() { sed -n 2,3p "$1" | sed 's/^/     /'; }
for lv in $LEVELS; do
  echo "== $(date +%T) level $lv"
  rm -f "TIP2.L$lv.robo" "TIP2.L$lv.robo.fresh" "TIP2.L$lv.robo.twice"
  heavy "$CL_TOOLS/view/roborun.sh" TIP2.keepbl.in "$G/TIP2.L$lv.robo" 0 -1 pin -Drobo.inplace=1 \
    -Drobo.twice=dirty -Drobo.level="$lv"
  rm -f "TIP2.L$lv.robo.progress" "TIP2.L$lv.robo.log.0"
  heavy "$B/vfuzz.exe" --corpus TIP2.keepbl.in "TIP2.view$lv.txt" --path "view$lv" --twice-links | tail -1
  nice -n 10 cut -f1,4,5 "TIP2.view$lv.txt" > "TIP2.view$lv.isg"
  mv -f "TIP2.view$lv.txt.twice" "TIP2.view$lv.twice"
  rm -f "TIP2.view$lv.txt" "TIP2.view$lv.txt.sum" "TIP2.view$lv.txt.guard" "TIP2.view$lv.txt.err"
  heavy "$B/vfuzz.exe" --corpus T2F.in "T2F.view$lv.txt" --path "view$lv" | tail -1
  nice -n 10 cut -f1,4,5 "T2F.view$lv.txt" > "T2F.view$lv.isg"
  rm -f "T2F.view$lv.txt" "T2F.view$lv.txt.sum" "T2F.view$lv.txt.guard" "T2F.view$lv.txt.err"
  # Every sequence's second layout: vfuzz lists only those that changed.
  nice -n 10 python3 -I - "TIP2.view$lv.isg" "TIP2.view$lv.twice" "TIP2.view$lv.second" <<'PY'
import sys
isg, twice, out = sys.argv[1:4]
second = {}
for l in open(twice):
    f = l.rstrip("\n").split("\t")
    if len(f) >= 4:
        second[f[0]] = f[3]
with open(out, "w") as o:
    for l in open(isg):
        f = l.rstrip("\n").split("\t")
        g = second.get(f[0], f[2])
        st = f[1]
        if f[0] in second:
            st = g[1:g.index(" | ")] if g.startswith("!") else "ok"
        o.write("%s\t%s\t%s\n" % (f[0], st, g))
PY
  R=TIP2.L$lv.robo
  $VC "TIP2.view$lv.isg" "$R" --levels 257 --level 257 --strict --helpers full --show 8 \
    --mismatch-ids "inplace.L$lv.ids" > "inplace.L$lv.txt"
  echo "   in place against the live views:"; line "inplace.L$lv.txt"
  $VC "TIP2.view$lv.second" "$R.twice" --levels 257 --level 257 --helpers full --show 8 \
    --mismatch-ids "second.L$lv.ids" > "second.L$lv.txt"
  echo "   second layout against the live views' dirty second layout:"; line "second.L$lv.txt"
  $VC "T2F.view$lv.isg" "$R.fresh" --levels 257 --level 257 --map T2-fresh=T2-inplace --strict \
    --helpers full --show 8 --mismatch-ids "fresh.L$lv.ids" > "fresh.L$lv.txt"
  echo "   fresh builds against the live views' fresh builds:"; line "fresh.L$lv.txt"
  $VC "$R" "$R.fresh" --levels 257 --level 257 --helpers full --show 4 > "history.L$lv.txt"
  # The throws: which sequences, and whether at an earlier state or the final
  # one (the live views write EXC:inplace for an earlier state).
  nice -n 10 python3 -I - "TIP2.view$lv.isg" "$R" TIP2.keepbl.in "TIP2.pre$lv.in" <<'PY'
import sys
isg, robo, corpus, pre = sys.argv[1:5]
dart = {l.split("\t")[0] for l in open(isg) if l.split("\t")[1].startswith("EXC")}
android = set()
for l in open(robo):
    f = l.rstrip("\n").split("\t")
    if f[1].startswith("EXC") or (len(f) > 2 and f[2].startswith("!EXC")):
        android.add(f[0])
with open(pre, "w") as o:
    for l in open(corpus):
        f = l.rstrip("\n").split("\t")
        if f[0] not in dart:
            continue
        ops = f[-1].split(";")
        last = max(i for i, op in enumerate(ops) if op == "L")
        f[0] += "#pre"
        f[-1] = ";".join(ops[:last])
        o.write("\t".join(f) + "\n")
PY
  if [ -s "TIP2.pre$lv.in" ]; then
    heavy "$B/vfuzz.exe" --corpus "TIP2.pre$lv.in" "TIP2.pre$lv.txt" --path "view$lv" > /dev/null
  else
    : > "TIP2.pre$lv.txt"
  fi
  rm -f "TIP2.pre$lv.txt.sum" "TIP2.pre$lv.txt.guard" "TIP2.pre$lv.txt.err"
  nice -n 10 python3 -I - "$lv" "TIP2.view$lv.isg" "$R" "TIP2.pre$lv.txt" "inplace.L$lv.txt" \
    "second.L$lv.txt" "fresh.L$lv.txt" "history.L$lv.txt" "throws.L$lv.txt" >> summary.tsv <<'PY'
import re, sys
lv, isg, robo, pre, inp, sec, fr, hist, out = sys.argv[1:10]
dart = {l.split("\t")[0] for l in open(isg) if l.split("\t")[1].startswith("EXC")}
android, android_early = set(), set()
for l in open(robo):
    f = l.rstrip("\n").split("\t")
    if f[1].startswith("EXC:inplace"):
        android.add(f[0]); android_early.add(f[0])
    elif f[1].startswith("EXC") or (len(f) > 2 and f[2].startswith("!EXC")):
        android.add(f[0])
dart_early = set()
for l in open(pre):
    f = l.rstrip("\n").split("\t")
    if len(f) > 3 and f[3].startswith("EXC"):
        dart_early.add(f[0][:-len("#pre")])
with open(out, "w") as o:
    for name, ids in (("engine", dart), ("android", android), ("engine, earlier state", dart_early),
                      ("android, earlier state", android_early)):
        o.write("%s\t%d\t%s\n" % (name, len(ids), " ".join(sorted(ids))))
def nums(path):
    t = open(path).read()
    m = re.search(r"compared (\d+), equal (\d+), DIFFER (\d+)", t)
    e = dict(re.findall(r"(JEXC|UNMAPPED) (\d+)", t.split("excluded classes", 1)[1].split("\n", 1)[0]))
    return m.group(1), m.group(3), e.get("JEXC", "0"), e.get("UNMAPPED", "0")
c, d, j, u = nums(inp)
print("\t".join([lv, c, d, j, u, nums(sec)[1], nums(fr)[1], str(len(dart)), str(len(android)),
                 "yes" if dart == android else "NO", str(len(dart_early)), str(len(android_early)),
                 "yes" if dart_early == android_early else "NO", nums(hist)[1]]))
PY
  tail -n 1 summary.tsv | awk -F'\t' '{printf "   throws: engine %s, live views %s, same sequences %s; at an earlier state: engine %s, live views %s, same %s\n   history (live views in place against their fresh builds): %s\n", $8, $9, $10, $11, $12, $13, $14}'
  rm -f "TIP2.L$lv.robo.fresh.progress"
done
echo "== $(date +%T) done; reports in $G"
column -t -s "$(printf '\t')" summary.tsv | sed 's/^/   /'
