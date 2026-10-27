#!/bin/bash
# build_trace.sh: TraceJava. Patches upstream's LinearSystem, ArrayRow,
# ArrayLinkedVariables, PriorityGoalRow and SolverVariable at the pin with
# trace hooks (mk_trace.py, sources from $CL_UPSTREAM), copies upstream's core
# classes ($CL_CORE) to $CL_TRACE and compiles the patched classes and the new
# SolverTrace over them. Light (seconds).
#   build_trace.sh
# Run VOpDriver on it with CL_CP=$CL_TRACE jrun.sh ... -Dtrace=<file> (FORMATS.md
# 7b). Without -Dtrace the patched classes behave and print exactly as upstream.
set -e
. "$(dirname "$0")/../../env.sh"
T=$CL_TOOLS/java/trace
need "$CL_CORE/androidx/constraintlayout/core/LinearSystem.class"
SRC=$CL_TRACE.src.$$
rm -rf "$SRC"; mkdir -p "$SRC"
python3 -I "$T/mk_trace.py" "$CL_UPSTREAM/constraintlayout/core/src/main/java" "$SRC"
cp "$T/SolverTrace.java" "$SRC/androidx/constraintlayout/core/SolverTrace.java"
rm -rf "$CL_TRACE"
mkdir -p "$CL_TRACE"
cp -R "$CL_CORE/." "$CL_TRACE/"
javac -nowarn -encoding UTF-8 -d "$CL_TRACE" -cp "$CL_CORE" \
  "$SRC"/androidx/constraintlayout/core/*.java
rm -rf "$SRC"
echo "built $CL_TRACE"
