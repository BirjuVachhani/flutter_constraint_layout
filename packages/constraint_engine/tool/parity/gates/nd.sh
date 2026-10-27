#!/bin/bash
# nd.sh: ND detection (java/jbatch3.sh, the triple run) on the layouts a gate
# found different, so that the next run of the gate can exclude the layouts
# whose Java result depends on identity hashes (ND). Only differing layouts are
# checked: a layout the port matches needs no check.
#   nd.sh <corpus> <levels> <ids> [core]
# <corpus> is R, A, VR2, T2 or T2core ($CL_CORPORA/<corpus>.in), <levels> the
# primary run's levels (257,0, 64,321, 321 or 192,449), <ids> a gate's
# --mismatch-ids file (T2-inplace ids are checked as their T2-fresh build), and
# `core` runs the core path (T2core). Writes $CL_JAVA/<corpus>.<suffix>.nd,
# the file the gates read: <corpus>.mism.nd at 257,0 (257 for T2core), else
# <corpus>.J<levels with _>.nd (J64_321, J321, J192_449). Its lines: ND lines
# whole, the others id and status. One heavy run (three JVMs).
set -u
. "$(dirname "$0")/../env.sh"
c=${1:?usage: nd.sh <corpus> <levels> <ids> [core]}; lv=${2:?usage}; ids=${3:?usage}
core=${4:-}
need "$CL_CORPORA/$c.in" "$ids"
# ND is a notion of the levels the gates exclude it at: 257 (whose primary
# runs hold J257 and J0, or J257 alone for T2core) and the GRAPH levels.
case $c:$lv in
  T2core:257) primary=$CL_JAVA/T2core.J257d.java; out=$CL_JAVA/T2core.mism.nd ;;
  T2core:257,0) echo "nd.sh: T2core's primary run at 257 has one level: pass 257" >&2; exit 2 ;;
  *:257,0) primary=$CL_JAVA/$c.java; out=$CL_JAVA/$c.mism.nd ;;
  *:64,321|*:321|*:192,449) primary=$CL_JAVA/$c.J${lv/,/_}.java; out=$CL_JAVA/$c.J${lv/,/_}.nd ;;
  *) echo "nd.sh: levels must be 257,0 (257 for T2core), 64,321, 321 or 192,449" >&2; exit 2 ;;
esac
tmp=$out.in
sed 's/^T2-inplace:/T2-fresh:/' "$ids" | sort -u > "$out.ids"
awk -F'\t' 'NR==FNR {want[$1]=1; next} ($1 in want)' "$out.ids" "$CL_CORPORA/$c.in" > "$tmp"
echo "nd.sh: $(wc -l < "$tmp") layouts of $c at $lv"
p=(); [ -s "$primary" ] && p=("$primary")
if [ "$core" = core ]; then
  heavy env JAVA_TOOL_OPTIONS=-Dpath=core "$CL_TOOLS/java/jbatch3.sh" "$tmp" "$out.raw" "$lv" ${p[@]+"${p[@]}"} 2>&1 \
    | grep -v '^Picked up JAVA_TOOL_OPTIONS' | tail -2
else
  heavy "$CL_TOOLS/java/jbatch3.sh" "$tmp" "$out.raw" "$lv" ${p[@]+"${p[@]}"} 2>&1 | tail -2
fi
awk -F'\t' 'BEGIN{OFS="\t"} $2=="ND"{print; next} {print $1, $2}' "$out.raw" > "$out"
rm -f "$tmp" "$out.raw" "$out.ids"
awk -F'\t' '{print $2}' "$out" | sort | uniq -c
