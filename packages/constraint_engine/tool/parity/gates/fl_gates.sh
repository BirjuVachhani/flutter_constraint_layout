#!/bin/bash
# fl_gates.sh: the gates on real Flutter widget trees. The FL runner
# (packages/flutter_constraint_layout/tool/parity/fl_harness, set up in
# $CL_FL) lays every FL layout out through the adapter of this checkout, as a
# ConstraintLayout of ContentModelBox children (FORMATS.md 11 and 19).
#   fl_gates.sh <outdir> [steps]
# Steps (default all):
#   FL       frames against FL.J257.java, strict (non-integral numbers never
#            equal integral ones); the dry layout (getDryLayout) must equal
#            the laid-out size on every layout
#   TIP      every in-place sequence of TIP.txt pumped state by state into
#            the same ConstraintLayout: its final frames against a fresh
#            build of the final state, which is Android's reference at the
#            adapter's default level, 257 (the live views lay every in-place
#            sequence out as a fresh build there); at another level
#            (FL_LEVEL) compare with the RoboOracle in place instead
#            (FORMATS.md 21.1)
#   FLr      every FL layout laid out four more times in the same
#            ConstraintLayout under cl.verifyReplay: 0 replay mismatches, and
#            the second layout against Android's dirty second layout
#            (FL.dirty.java.second.java, java_refs.sh FL)
#   T        diagnostic: the measure-request transcripts against
#            FL.T257.java (tcompare.py --level 257)
# Each runner call goes through `heavy` (env.sh).
set -u
. "$(dirname "$0")/../env.sh"
G=${1:?usage: fl_gates.sh <outdir> [steps]}
STEPS=${2:-"FL TIP FLr T"}
mkdir -p "$G"; G=$(cd "$G" && pwd)
C=$CL_CORPORA; J=$CL_JAVA
F=$CL_REPO/packages/flutter_constraint_layout/tool/parity/fl_harness/run_fl.sh
CMP=$CL_TOOLS/compare
VC="nice -n 10 python3 -I $CMP/vcompare.py"
need "$CL_FL/pubspec.yaml"
line() { sed -n 2,4p "$1" | sed 's/^/   /'; }
for s in $STEPS; do
  echo "== $(date +%T) $s"
  case $s in
    FL)
      need "$C/FL.txt" "$J/FL.J257.java"
      heavy "$F" "$C/FL.txt" "$G/FL.out" gate dry | tail -3
      $VC "$G/FL.out" "$J/FL.J257.java" --levels 257 --level 257 --exclude ND,HANG,SOE,JEXC --strict \
        --show 8 --mismatch-ids "$G/FL.ids" > "$G/FL.txt"; line "$G/FL.txt"
      echo "   dry layout: $(awk -F'\t' '$2 != "equal"' "$G/FL.out.dry" | wc -l | tr -d ' ') of $(wc -l < "$G/FL.out.dry" | tr -d ' ') differ from the real size" ;;
    TIP)
      need "$C/TIP.txt"
      heavy "$F" "$C/TIP.txt" "$G/TIP.out" gate inplace | tail -3
      $VC "$G/TIP.out" "$G/TIP.out.fresh" --levels 257 --level 257 --exclude ND,HANG,SOE,JEXC \
        --show 8 --mismatch-ids "$G/TIP.ids" > "$G/TIP.txt"; line "$G/TIP.txt" ;;
    FLr)
      need "$C/FL.txt" "$J/FL.dirty.java.second.java"
      heavy "$F" "$C/FL.txt" "$G/FLr.out" gate replay | tail -3
      awk -F'\t' '$3 ~ /^replays / {split($4, m, " "); s += m[2]; split($3, r, " "); h += r[2]} END {print "   replays " h ", mismatches " s}' "$G/FLr.out.replay"
      $VC "$G/FLr.out.second" "$J/FL.dirty.java.second.java" --levels 257 --level 257 \
        --exclude ND,HANG,SOE,JEXC --strict --show 8 --mismatch-ids "$G/FLr.ids" > "$G/FLr.txt"
      line "$G/FLr.txt" ;;
    T)
      need "$C/FL.txt" "$J/FL.T257.java"
      heavy "$F" "$C/FL.txt" "$G/FLt.out" gate transcript | tail -3
      nice -n 10 python3 -I "$CMP/tcompare.py" "$G/FLt.out.T" "$J/FL.T257.java" --level 257 --show 8 \
        > "$G/FLt.txt"; sed -n 2,6p "$G/FLt.txt" | sed 's/^/   /' ;;
    *) echo "fl_gates.sh: unknown step $s" >&2; exit 2 ;;
  esac
done
echo "== $(date +%T) done; reports in $G"
