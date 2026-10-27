#!/bin/bash
# vrun.sh <corpus R|VR|VR2|T|T2|A> <path> <outdir> [gen ...]
# Runs vfuzz on every generator of a corpus (or the listed ones) at its
# corpus seeds (vfuzz --seeds), writing <outdir>/<gen>.txt (+ .sum, .err) and
# <outdir>/summary.txt. `--path none` writes the corpus only (gates/corpora.sh
# does that). A heavy step: run it through `heavy` (env.sh) or your own lock,
# once for the whole loop.
# VFUZZ=<exe> picks the vfuzz build (default $CL_BIN/vfuzz.exe). R, VR and VR2
# read the configured floats back from the engine to print them (respec), so
# their op text depends on the engine they are generated with (README.md,
# step 3).
. "$(dirname "$0")/../env.sh"
VF=${VFUZZ:-$CL_BIN/vfuzz.exe}
corpus=$1; path=$2; out=$3
shift 3
[ -z "$out" ] && { echo "usage: vrun.sh <corpus> <path> <outdir> [gen ...]" >&2; exit 2; }
need "$VF"
mkdir -p "$out"
gens="$*"
[ -z "$gens" ] && gens=$("$VF" --list "$corpus")
for g in $gens; do
  read -r first count < <("$VF" --seeds "$g")
  "$VF" "$g" "$first" "$count" "$out/$g.txt" --path "$path" || echo "vrun: $g failed ($?)" >&2
done
cat "$out"/*.txt.sum > "$out/summary.txt" 2>/dev/null
echo "vrun: $corpus $path done: $(cat "$out"/*.txt 2>/dev/null | wc -l) lines in $out"
