#!/bin/bash
# graph_gates.sh: the gate at the dependency-graph levels. The engine of this
# checkout at OPTIMIZATION_GRAPH (64), STANDARD | GRAPH (321), GRAPH |
# GRAPH_WRAP (192) and STANDARD | GRAPH | GRAPH_WRAP (449), against Java at the
# same level (java_refs.sh graph). Target: 0 differences outside the excluded
# classes.
#   graph_gates.sh <outdir> [steps] [levels]
# Steps (default all): R and T2core on the core path at every level, VR2 and
# T2 on the view path at 321, 192 and 449. T2-inplace is left out (--skip):
# at these levels Android's live views lay many in-place sequences out unlike
# their fresh builds (the graph's runs and nodes keep state from the last
# graph, and some sequences throw), and inplace_gates.sh compares every one
# with the live views. Levels (default "64 321 192 449").
# Per corpus and level <c>.<lv>: .cmp.txt (vcompare, helpers full; ND, HANG,
# SOE and JEXC excluded, ND from the matching .nd file of $CL_JAVA when it
# exists), .pos.txt and .ignore.txt (helpers compared by position, or
# ignored), .ids (the differing ids), .gclass.txt and .gclass.tsv (each
# difference's route, which side's graph answered, and its mechanism: gclass
# on gclass_in.py's input; Java's solver result at the level is J0 at 64 and
# 192, J257 at 321 and 449). The Dart output is kept as <c>.<path>.isg.gz (id,
# status, geometry). summary.tsv gets one line per corpus and level.
# Needs $CL_BIN/vfuzz.exe (built with -Dcl.trace=true) and gclass.exe.
set -u
. "$(dirname "$0")/../env.sh"
G=${1:?usage: graph_gates.sh <outdir> [steps] [levels]}
STEPS=${2:-"R T2core VR2 T2"}
LEVELS=${3:-"64 321 192 449"}
mkdir -p "$G"
G=$(cd "$G" && pwd)
B=$CL_BIN; C=$CL_CORPORA; J=$CL_JAVA
CMP=$CL_TOOLS/compare
VC="nice -n 10 python3 -I $CMP/vcompare.py"
GI="nice -n 10 python3 -I $CMP/gclass_in.py"
need "$B/vfuzz.exe" "$B/gclass.exe"
cd "$G" || exit 2
[ -s summary.tsv ] || printf 'corpus\tlevel\tcompared\tequal\tdiffer\tND\tHANG\tSOE\tJEXC\tdiffer_pos\tdiffer_ignore\troutes\n' > summary.tsv
# compare <c> <lv> <dart.txt> <java> <levels> <solver> <solver levels> <solver level> <nd> [--map ...]
compare() {
  local c=$1 lv=$2 a=$3 j=$4 ls=$5 s=$6 sls=$7 sl=$8 nd=$9; shift 9
  local ndo=(); [ -s "$nd" ] && ndo=(--nd "$nd")
  $VC "$a" "$j" --levels $ls --level $lv ${ndo[@]+"${ndo[@]}"} "$@" --show 6 \
    --mismatch-ids $c.$lv.ids > $c.$lv.cmp.txt
  $VC "$a" "$j" --levels $ls --level $lv ${ndo[@]+"${ndo[@]}"} "$@" --helpers pos --quiet > $c.$lv.pos.txt
  $VC "$a" "$j" --levels $ls --level $lv ${ndo[@]+"${ndo[@]}"} "$@" --helpers ignore --quiet > $c.$lv.ignore.txt
  $GI --dart "$a" --java "$j" --levels $ls --level $lv --solver "$s" --solver-levels $sls \
    --solver-level $sl --ids $c.$lv.ids --out $c.$lv.gin.tsv "$@"
  nice -n 10 "$B/gclass.exe" $c.$lv.gin.tsv $c.$lv.gclass.tsv > $c.$lv.gclass.txt
  rm -f $c.$lv.gin.tsv
  nice -n 10 python3 -I - $c $lv >> summary.tsv <<'PY'
import re, sys
c, lv = sys.argv[1], sys.argv[2]
def nums(f):
    t = open(f).read()
    m = re.search(r"compared (\d+), equal (\d+), DIFFER (\d+)", t)
    e = dict(re.findall(r"(ND|HANG|SOE|JEXC) (\d+)", t.split("excluded classes", 1)[1].split("\n", 1)[0]))
    return m.groups(), e
(cmp_, eq, diff), ex = nums("%s.%s.cmp.txt" % (c, lv))
pos = nums("%s.%s.pos.txt" % (c, lv))[0][2]
ign = nums("%s.%s.ignore.txt" % (c, lv))[0][2]
routes = open("%s.%s.gclass.txt" % (c, lv)).readline().strip()
print("\t".join([c, lv, cmp_, eq, diff, ex["ND"], ex["HANG"], ex["SOE"], ex["JEXC"], pos, ign, routes]))
PY
  tail -n 1 summary.tsv | cut -f1-11 | sed 's/^/   /'
}
# java <c> <lv>: the Java reference file holding level <lv>, and its levels.
java() {
  case $2 in
    64|321) if [ "$1" = VR2 ] || [ "$1" = T2 ]; then echo "$J/$1.J321.java 321"; else echo "$J/$1.J64_321.java 64,321"; fi ;;
    192|449) echo "$J/$1.J192_449.java 192,449" ;;
  esac
}
for s in $STEPS; do
  echo "== $(date +%T) $s"
  case $s in
    R|T2core)
      in=$C/$s.in; js0=$J/R.java; ls0=257,0; js257=$js0; ls257=257,0
      if [ "$s" = T2core ]; then
        js0=$J/T2core0.java; ls0=0; js257=$J/T2core.J257d.java; ls257=257
      fi
      need "$in" "$js0" "$js257"
      for lv in $LEVELS; do
        read -r jf jl < <(java "$s" "$lv")
        need "$jf"
        heavy "$B/vfuzz.exe" --corpus "$in" "$s.core$lv.txt" --path "core$lv" | tail -1
        if [ "$lv" = 64 ] || [ "$lv" = 192 ]; then
          compare "$s" "$lv" "$s.core$lv.txt" "$jf" "$jl" "$js0" "$ls0" 0 "${jf%.java}.nd"
        else
          compare "$s" "$lv" "$s.core$lv.txt" "$jf" "$jl" "$js257" "$ls257" 257 "${jf%.java}.nd"
        fi
        nice -n 10 cut -f1,4,5 "$s.core$lv.txt" | nice -n 10 gzip -n -6 > "$s.core$lv.isg.gz"
        mv -f "$s.core$lv.txt.guard" "$s.core$lv.guard"
        rm -f "$s.core$lv.txt" "$s.core$lv.txt.sum" "$s.core$lv.txt.err"
      done ;;
    VR2|T2)
      map=(); [ "$s" = T2 ] && map=(--skip T2-inplace)
      need "$C/$s.in" "$J/$s.java"
      for lv in $LEVELS; do
        [ "$lv" = 64 ] && continue
        read -r jf jl < <(java "$s" "$lv")
        need "$jf"
        heavy "$B/vfuzz.exe" --corpus "$C/$s.in" "$s.view$lv.txt" --path "view$lv" | tail -1
        if [ "$lv" = 192 ]; then sj=0; else sj=257; fi
        compare "$s" "$lv" "$s.view$lv.txt" "$jf" "$jl" "$J/$s.java" 257,0 "$sj" "${jf%.java}.nd" \
          ${map[@]+"${map[@]}"}
        nice -n 10 cut -f1,4,5 "$s.view$lv.txt" | nice -n 10 gzip -n -6 > "$s.view$lv.isg.gz"
        mv -f "$s.view$lv.txt.guard" "$s.view$lv.guard"
        rm -f "$s.view$lv.txt" "$s.view$lv.txt.sum" "$s.view$lv.txt.err"
      done ;;
    *) echo "graph_gates.sh: unknown step $s" >&2; exit 2 ;;
  esac
done
echo "== $(date +%T) done; reports in $G"
