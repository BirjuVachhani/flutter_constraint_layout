#!/bin/bash
# exc.sh: exception classification at level 0 or 257: the engine's caught and
# thrown exceptions on the adversarial corpus A, against the oracle at the same
# level (compare/exc_classify.py states the classes; target: no layout in
# classes ii and iv, every class-i layout `same`).
#   exc.sh <0|257> <outdir> [full]
# Repros (exc0.in, the 242 A layouts that print, throw, hang or overflow on
# either side): vfuzz --corpus core<level>, vtrace core<level> at <level>,
# exc_classify.py against TraceJava's trace at the level (exc0.J0.trace or
# exc0.J257.trace, java_refs.sh exc0).
# `full`: also all of A on core<level>: the classes over 360,000 layouts, the
# guard trips (every one must be a Java SO), and vcompare against the level's
# Java column with the printed status (257: A.java, ND from A.mism.nd, ND,
# HANG, SOE and JEXC excluded; 0: A.J0.java, HANG, SOE and JEXC excluded).
# Needs $CL_BIN/vfuzz.exe and vtrace.exe built with -Dcl.trace=true. Each Dart
# run goes through `heavy` (env.sh).
set -u
. "$(dirname "$0")/../env.sh"
LV=${1:?usage: exc.sh <0|257> <outdir> [full]}
OUT=${2:?usage: exc.sh <0|257> <outdir> [full]}
FULL=${3:-}
B=$CL_BIN; C=$CL_CORPORA; J=$CL_JAVA
CMP=$CL_TOOLS/compare
case $LV in
  0) JT=$J/exc0.J0.trace; JA=$J/A.J0.java; JL=0; ND=(); EXCL=HANG,SOE,JEXC ;;
  257) JT=$J/exc0.J257.trace; JA=$J/A.java; JL=257,0
       ND=(); [ -s "$J/A.mism.nd" ] && ND=(--nd "$J/A.mism.nd"); EXCL=ND,HANG,SOE,JEXC ;;
  *) echo "exc.sh: level must be 0 or 257" >&2; exit 2 ;;
esac
need "$B/vfuzz.exe" "$B/vtrace.exe" "$C/exc0.in" "$JT"
mkdir -p "$OUT"
echo "== $(date +%T) level $LV repros: $(wc -l < "$C/exc0.in") layouts"
heavy "$B/vfuzz.exe" --corpus "$C/exc0.in" "$OUT/exc0.core$LV.txt" --path "core$LV" | tail -1
heavy "$B/vtrace.exe" "$C/exc0.in" "$OUT/exc0.core$LV.trace" --path "core$LV" --level "$LV"
nice -n 10 python3 -I "$CMP/exc_classify.py" "$OUT/exc0.core$LV.txt" --level "$LV" \
  --dart-trace "$OUT/exc0.core$LV.trace" --java-trace "$JT" --guard "$OUT/exc0.core$LV.txt.guard" \
  --out "$OUT/exc0.table.tsv" | tee "$OUT/exc0.summary.txt"
if [ "$FULL" = full ]; then
  need "$C/A.in" "$JA"
  echo "== $(date +%T) all of A on core$LV"
  heavy "$B/vfuzz.exe" --corpus "$C/A.in" "$OUT/A.core$LV.txt" --path "core$LV" | tail -1
  nice -n 10 python3 -I "$CMP/exc_classify.py" "$OUT/A.core$LV.txt" --level "$LV" \
    --guard "$OUT/A.core$LV.txt.guard" --out "$OUT/A.table.tsv" > "$OUT/A.classes.txt"
  head -2 "$OUT/A.classes.txt"
  echo "guard trips: $(wc -l < "$OUT/A.core$LV.txt.guard") layouts"
  nice -n 10 python3 -I "$CMP/vcompare.py" "$OUT/A.core$LV.txt" "$JA" --levels "$JL" --level "$LV" \
    ${ND[@]+"${ND[@]}"} --exclude "$EXCL" --show 10 --mismatch-ids "$OUT/A_core${LV}_J$LV.ids" \
    > "$OUT/A_core${LV}_J$LV.txt"
  echo "A core$LV against J$LV (printed status included): $(sed -n 2,3p "$OUT/A_core${LV}_J$LV.txt" | tr -s ' ' | tr '\n' ' ')"
  # Keep the reports and the guard file; the frame file is superseded by them.
  rm -f "$OUT/A.core$LV.txt" "$OUT/A.core$LV.txt.sum"
fi
echo "reports in $OUT"
