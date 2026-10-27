#!/bin/bash
# jrun.sh <in> <out> [levels] [-D...]: the primary oracle run. VOpDriver batch
# over <in> (ops = last field) with -XX:hashCode=2 (identity hashes are
# constant, so HashSet dependents iterate in insertion order), one build per
# level, restarting after a HANG (the JVM writes "id\tHANG" and exits 3). A
# line lost to a JVM crash is written as "id\tHANG" too.
# -XX:-OmitStackTraceInFastThrow keeps every printed exception's message and
# frame (P field excs) independent of JIT warm-up. Extra -D flags (FORMATS.md
# 8.1) pass through. The classpath is upstream's core ($CL_CORE, or $CL_CP
# when set, e.g. CL_CP=$CL_TRACE for -Dtrace) and the oracle ($CL_ORACLE).
# A heavy step: run it through `heavy` (env.sh) or your own lock.
. "$(dirname "$0")/../env.sh"
in=$1; out=$2; levels=${3:-257,0}
shift; shift; [ $# -gt 0 ] && shift
CORE=${CL_CP:-$CL_CORE}
CP=$CORE:$CL_ORACLE
need "$in" "$CL_ORACLE/VOpDriver.class"
prog=$out.progress; : > "$out"; start=0
while :; do
  java -XX:+UnlockExperimentalVMOptions -XX:hashCode=2 -Xmx1g -Xss32m -XX:+UseSerialGC -XX:-OmitStackTraceInFastThrow \
    -XX:CICompilerCount=2 "$@" -cp "$CP" VOpDriver batch "$in" "$out" "$prog" "$start" "$levels"
  [ "$(cat "$prog")" = "DONE" ] && break
  idx=$(cat "$prog")
  id=$(sed -n "$((idx + 1))p" "$in" | cut -f1)
  last=$(tail -n 1 "$out" | cut -f1)
  [ "$last" != "$id" ] && printf '%s\tHANG\n' "$id" >> "$out"
  start=$((idx + 1)); echo "jrun: restart after line $start ($id)" >&2
done
rm -f "$prog"
