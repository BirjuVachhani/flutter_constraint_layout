#!/bin/bash
# The FL runner over a corpus, two shards in parallel (flutter test
# --concurrency=2), in the harness that setup.sh set up in $CL_FL. A heavy
# step: run it through `heavy` (the engine's tool/parity/env.sh) or your own
# lock:
#   [FL_LEVEL=<n>] run_fl.sh <FL.txt> <out.txt> [tag] [dry] [inplace] [replay] [transcript]
# Writes <out.txt> (corpus lines, FORMATS.md 1, back in input order), plus
# <out.txt>.dry with `dry`, <out.txt>.fresh with `inplace`, <out.txt>.replay
# and <out.txt>.second with `replay` (under --dart-define=cl.verifyReplay=true),
# and <out.txt>.T with `transcript` (see lib/fl_runner.dart, FORMATS.md 11 and
# 19). FL_LEVEL in the environment sets Android's optimization level of every
# layout (default 257, the adapter's default).
set -e
. "$(cd "$(dirname "$0")" && pwd)/../../../../constraint_engine/tool/parity/env.sh"
abs() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd)" "$(basename "$1")"); }
[ $# -ge 2 ] || { echo "usage: run_fl.sh <FL.txt> <out.txt> [tag] [modes...]" >&2; exit 2; }
IN=$(abs "$1"); OUT=$(abs "$2"); TAG=${3:-today}
DRY=false; INPLACE=false; REPLAY=false; TRANSCRIPT=false
for a in "${@:4}"; do
  case $a in
    dry) DRY=true ;; inplace) INPLACE=true ;; replay) REPLAY=true ;;
    transcript) TRANSCRIPT=true ;;
    *) echo "run_fl.sh: unknown mode $a" >&2; exit 2 ;;
  esac
done
[ -f "$CL_FL/pubspec.yaml" ] || { echo "run_fl.sh: no harness in $CL_FL (run setup.sh)" >&2; exit 2; }
SUFFIXES=". .dry .fresh .replay .second .T"
cd "$CL_FL"
for s in $SUFFIXES; do s=${s#.}; s=${s:+.$s}; rm -f "$OUT.0$s" "$OUT.1$s"; done
nice -n 10 flutter test --concurrency=2 test/fl_shard0_test.dart test/fl_shard1_test.dart \
  --dart-define=FL_IN="$IN" --dart-define=FL_OUT="$OUT" --dart-define=FL_TAG="$TAG" \
  --dart-define=FL_DRY=$DRY --dart-define=FL_INPLACE=$INPLACE \
  --dart-define=FL_REPLAY=$REPLAY --dart-define=cl.verifyReplay=$REPLAY \
  --dart-define=FL_TRANSCRIPT=$TRANSCRIPT --dart-define=FL_LEVEL="${FL_LEVEL:-257}" 2>&1 \
  | grep -E '^FL |All tests passed|Some tests failed|Error' || true
# Shard k holds lines k, k+2, ...: interleave them back into input order.
merge() {
  python3 -I - "$1" "$2" "$3" <<'PY'
import sys
a = open(sys.argv[1]).read().splitlines()
b = open(sys.argv[2]).read().splitlines()
with open(sys.argv[3], 'w') as o:
    for i in range(max(len(a), len(b))):
        if i < len(a): o.write(a[i] + '\n')
        if i < len(b): o.write(b[i] + '\n')
PY
}
merge "$OUT.0" "$OUT.1" "$OUT"
[ "$DRY" = true ] && merge "$OUT.0.dry" "$OUT.1.dry" "$OUT.dry"
[ "$INPLACE" = true ] && merge "$OUT.0.fresh" "$OUT.1.fresh" "$OUT.fresh"
[ "$REPLAY" = true ] && merge "$OUT.0.replay" "$OUT.1.replay" "$OUT.replay" \
  && merge "$OUT.0.second" "$OUT.1.second" "$OUT.second"
[ "$TRANSCRIPT" = true ] && merge "$OUT.0.T" "$OUT.1.T" "$OUT.T"
for s in $SUFFIXES; do s=${s#.}; s=${s:+.$s}; rm -f "$OUT.0$s" "$OUT.1$s"; done
wc -l < "$OUT"
