#!/bin/bash
# corpora.sh: writes the corpus files every gate reads into $CL_CORPORA
# (FORMATS.md 1 and 3; README.md, step 3).
#   corpora.sh [steps]
# Steps (default all, in this order):
#   R VR VR2 T T2 A   every generator of the corpus at its seeds (vrun.sh with
#                     --path none), concatenated in the C-locale order of the
#                     generator names into <c>.in
#   T2core            T2 without T2-virtual, T2-atmost, T2-inplace and the ids
#                     of data/t2core_nd.ids (T2's layouts that Java's own
#                     identity-hash order decides): the T2 lists the core path
#                     runs, 379,995 layouts
#   sample            the 2,000 layouts of the solver-trace sample
#                     (data/trace_sample.ids), from R and T2, in that order
#   exc0              the 242 exception repros of A (data/exc0.ids)
#   FL                FL.txt: the first 3,000 lines the Flutter API can express
#                     from each of 20 generators of VR and T (ftree select; needs
#                     the Flutter harness in $CL_FL), 60,000 layouts
#   TIP               TIP.txt: the 50,000 in-place sequences of T (T-inplace)
# Needs $CL_BIN/vfuzz.exe (README.md, step 2). The generator steps are
# heavy (one vfuzz run per generator); each goes through `heavy` (env.sh).
set -eu
. "$(dirname "$0")/../env.sh"
STEPS=${1:-"R VR VR2 T T2 A T2core sample exc0 FL TIP"}
D=$CL_TOOLS/data
mkdir -p "$CL_CORPORA"
cd "$CL_CORPORA"
# pick <ids> <out> <corpus.in>...: the corpus lines of the ids, in the ids' order.
pick() {
  local ids=$1 out=$2; shift 2
  python3 -I - "$ids" "$out" "$@" <<'PY'
import sys
ids_path, out = sys.argv[1], sys.argv[2]
order = [l.strip() for l in open(ids_path) if l.strip()]
want = set(order)
found = {}
for path in sys.argv[3:]:
    for l in open(path):
        i = l.split("\t", 1)[0]
        if i in want and i not in found:
            found[i] = l
missing = [i for i in order if i not in found]
if missing:
    sys.exit("pick: %d ids not found, e.g. %s" % (len(missing), missing[0]))
with open(out, "w") as o:
    for i in order:
        o.write(found[i])
print("%s: %d lines" % (out, len(order)))
PY
}
for s in $STEPS; do
  echo "== $(date +%T) $s"
  case $s in
    R|VR|VR2|T|T2|A)
      need "$CL_BIN/vfuzz.exe"
      rm -rf "gen/$s"
      heavy "$CL_TOOLS/dart/vrun.sh" "$s" none "gen/$s"
      LC_ALL=C ls "gen/$s" | grep '\.txt$' | grep -v '^summary\.txt$' \
        | sed "s#^#gen/$s/#" | xargs cat > "$s.in"
      echo "   $s.in: $(wc -l < "$s.in") layouts" ;;
    T2core)
      need T2.in "$D/t2core_nd.ids"
      awk -F'\t' 'NR==FNR{nd[$1]=1; next} { g=$1; sub(/:.*/,"",g); if (g=="T2-virtual"||g=="T2-atmost"||g=="T2-inplace"||($1 in nd)) next; print }' \
        "$D/t2core_nd.ids" T2.in > T2core.in
      echo "   T2core.in: $(wc -l < T2core.in) layouts" ;;
    sample)
      need R.in T2.in
      pick "$D/trace_sample.ids" sample.in R.in T2.in ;;
    exc0)
      need A.in
      pick "$D/exc0.ids" exc0.in A.in ;;
    FL)
      need VR.in T.in "$CL_FL/bin/ftree.dart"
      mkdir -p "$CL_BIN"
      (cd "$CL_FL" && heavy dart compile exe bin/ftree.dart -o "$CL_BIN/ftree.exe" > /dev/null)
      heavy "$CL_BIN/ftree.exe" select 3000 FL.txt --gens \
        VR-fflist,VR-ffrtl,VR-ffsettings,VR-ffchat,VR-fftoolbar,VR-rscform,VR-rsccards,VR-rscnest,VR-fnrtl,VR-nbrscnest,T-measure,T-wrap,T-oddbias,T-chain,T-gone,T-depsorder,T-virtual,T-circle,T-ratio,T-pctmin \
        VR.in T.in | tail -3
      echo "   FL.txt: $(wc -l < FL.txt) layouts" ;;
    TIP)
      need T.in
      grep '^T-inplace:' T.in > TIP.txt
      echo "   TIP.txt: $(wc -l < TIP.txt) sequences" ;;
    *) echo "corpora.sh: unknown step $s" >&2; exit 2 ;;
  esac
done
echo "== $(date +%T) done: $CL_CORPORA"
