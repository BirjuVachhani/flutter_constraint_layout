#!/bin/bash
# jdirty.sh <in> <out> [level] [ids] [-D...]: DirtyTwice (FORMATS.md 19) over <in>
# (ops = last field), every line or only the ids listed in [ids] (`-` for all),
# at [level] (default 257), with -XX:hashCode=2 as jrun.sh, restarting after a
# HANG. Writes `id \t first \t second` (two geometries, FORMATS.md 2) or
# `id \t HANG` or `id \t THREW <exception>`. Extra -D flags pass through
# (-Dorient=kept, -Dpath=...). A heavy step: run it through `heavy` (env.sh)
# or your own lock. Needs $CL_CORE, $CL_ORACLE and $CL_DIRTY (build_dirty.sh).
. "$(dirname "$0")/../../env.sh"
in=$1; out=$2; level=${3:-257}; ids=${4:--}
shift; shift; [ $# -gt 0 ] && shift; [ $# -gt 0 ] && shift
CP=$CL_CORE:$CL_ORACLE:$CL_DIRTY
need "$in" "$CL_DIRTY/DirtyTwice.class"
: > "$out"; start=0
while :; do
  r=$(java -XX:+UnlockExperimentalVMOptions -XX:hashCode=2 -Xmx1g -Xss32m -XX:+UseSerialGC \
      -XX:-OmitStackTraceInFastThrow -XX:CICompilerCount=2 "$@" -cp "$CP" \
      DirtyTwice "$in" "$ids" "$out" "$start" "$level" | grep -E '^(NEXT|DONE)' | tail -1)
  case "$r" in
    NEXT*) start=${r#NEXT }; echo "jdirty: restart at $start" >&2 ;;
    DONE*) echo "$r"; break ;;
    *) echo "jdirty: the JVM stopped without DONE ($r)" >&2; exit 1 ;;
  esac
done
