#!/bin/bash
# RoboOracle batch runner (FORMATS.md section 10). A heavy step: run it
# through `heavy` (env.sh) or your own lock:
#   roborun.sh <in> <out> [start] [count] [pin|rel] [extra -D...]
# Compiles the oracle (src/) into $CL_ROBO/classes-<core> when a source is
# newer than its classes, then lays out every corpus line on real views
# (Robolectric 4.16, SDK 35, the ConstraintLayout 2.2.1 view layer) with
# -XX:hashCode=2 (dependents iterate in insertion order) and
# -XX:-OmitStackTraceInFastThrow (an exception's message does not depend on
# JIT warm-up). After a HANG (exit 3) it restarts on the next line. Needs
# view/fetch.sh's downloads, and for the pinned core (the default) $CL_CORE.
# The extra -D flags (FORMATS.md 10) include -Drobo.inplace=1 (in-place
# sequences on live views), -Drobo.level=<n> (the layout view's optimization
# level, default 257) and -Drobo.twice=dirty|layout (a second layout after a
# requestLayout, into <out>.twice).
set -u
. "$(dirname "$0")/../env.sh"
SRC=$CL_TOOLS/view/src
IN=$1; OUT=$2; START=${3:-0}; COUNT=${4:--1}; CORE=${5:-pin}
shift $(( $# < 5 ? $# : 5 ))
EXTRA=("$@")
CLASSES=$CL_ROBO/classes-$CORE
CP=$("$CL_TOOLS/view/robocp.sh" "$CORE") || exit 2
if [[ ! -d $CLASSES ]] || [[ -n $(find "$SRC" -name '*.java' -newer "$CLASSES/.stamp" 2>/dev/null) ]] || [[ ! -f $CLASSES/.stamp ]]; then
  rm -rf "$CLASSES"; mkdir -p "$CLASSES"
  nice -n 10 javac -nowarn -encoding UTF-8 -d "$CLASSES" -cp "$CP" $(find "$SRC" -name '*.java') || exit 2
  touch "$CLASSES/.stamp"
fi
PROGRESS=$OUT.progress
while :; do
  nice -n 10 java -XX:+UnlockExperimentalVMOptions -XX:hashCode=2 -Xmx1g -Xss32m -XX:+UseSerialGC \
    -XX:-OmitStackTraceInFastThrow -XX:CICompilerCount=2 -Drobolectric.offline=true \
    -Drobolectric.dependency.dir="$CL_ROBO/android-all" \
    -Drobo.in="$IN" -Drobo.out="$OUT" -Drobo.progress="$PROGRESS" -Drobo.start="$START" \
    -Drobo.count="$COUNT" ${EXTRA[@]+"${EXTRA[@]}"} -cp "$CP:$CLASSES" org.junit.runner.JUnitCore oracle.RoboOracle \
    > "$OUT.log.$START" 2>&1
  rc=$?
  if [[ $rc -eq 3 ]]; then
    last=$(cat "$PROGRESS")
    if [[ $COUNT -ge 0 ]]; then COUNT=$(( COUNT - (last + 1 - START) )); fi
    START=$(( last + 1 ))
    echo "roborun: HANG at line $last, restarting at $START" >&2
    continue
  fi
  grep -E 'RoboOracle:|^OK|^FAILURES|Tests run' "$OUT.log.$START" >&2
  exit $rc
done
