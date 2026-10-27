#!/bin/bash
# java_refs.sh: the Java references the gates compare with, from the corpora
# in $CL_CORPORA, into $CL_JAVA. The oracle is VOpDriver on upstream's core at
# the pin (java/jrun.sh: -XX:hashCode=2, restarts after a hang); the traces run
# it on TraceJava (CL_CP=$CL_TRACE), the dirty second layouts on DirtyTwice.
# Never rebuild the oracle while a run is going.
#   java_refs.sh [steps]
# Steps (default all; each is one or more heavy runs through `heavy`):
#   R        R.java (257,0, -Dprobe) and R.J257d.java (257, -Ddirect)
#   A        A.java (257,0, -Dprobe) and A.J0.java (0, -Dprobe)
#   VR2 T2   <c>.java (257,0, -Dprobe), <c>.J257dt.java (257, -Ddirect
#            -Dtranscript) and <c>.T0.java (0, -Dtranscript)
#   T2core   T2core.J257d.java (257, core path, -Ddirect) and T2core0.java (0,
#            core path, -Dprobe)
#   trace    sample.J257.trace and sample.J0.trace: TraceJava on the trace
#            sample, core path, at 257 and at 0 (with .java result files)
#   exc0     exc0.J257.{java,trace} and exc0.J0.{java,trace}: TraceJava on the
#            exception repros, -Dprobe
#   FL       FL.J257.java (257), FL.T257.java (257, -Dtranscript) and
#            FL.dirty.java (DirtyTwice: Android's dirty second layout, split
#            into FL.dirty.java.first.java and .second.java)
#   graph    the GRAPH levels: R and T2core (core path) at 64,321 and 192,449,
#            VR2 and T2 (view path) at 321 and 192,449: <c>.J64_321.java,
#            <c>.J321.java, <c>.J192_449.java
# The ND files (gates/nd.sh) are made from a gate's differing ids, later.
set -u
. "$(dirname "$0")/../env.sh"
STEPS=${1:-"R A VR2 T2 T2core trace exc0 FL graph"}
J=$CL_TOOLS/java/jrun.sh
C=$CL_CORPORA
mkdir -p "$CL_JAVA"
cd "$CL_JAVA" || exit 2
status() { awk -F'\t' '{s=$2; if (s=="ok" && substr($3,1,1)=="!") {split($3,a," [|] "); s=a[1]} print s}' "$1" | sed 's/^\(EXC:[^ ]*\).*/\1/' | sort | uniq -c | tr -s ' ' | tr '\n' ';'; }
run() { # <in> <out> <levels> [-D...]: one jrun.sh batch, then its statuses
  local in=$1 out=$2; shift 2
  need "$in"
  heavy "$J" "$in" "$out" "$@" 2>&1 | tail -3
  echo "   $(wc -l < "$out") lines in $out; statuses: $(status "$out")"
}
trace() { # <in> <out base> <level> [-D...]: TraceJava
  local in=$1 base=$2; shift 2
  need "$in" "$CL_TRACE/androidx/constraintlayout/core/SolverTrace.class"
  rm -f "$base.trace"
  heavy env CL_CP="$CL_TRACE" "$J" "$in" "$base.java" "$@" -Dtrace="$CL_JAVA/$base.trace" 2>&1 | tail -3
  echo "   $base.trace: $(grep -c '^T ' "$base.trace") blocks"
}
for s in $STEPS; do
  echo "== $(date +%T) $s"
  case $s in
    R)
      run "$C/R.in" R.java 257,0 -Dprobe
      run "$C/R.in" R.J257d.java 257 -Ddirect ;;
    A)
      run "$C/A.in" A.java 257,0 -Dprobe
      run "$C/A.in" A.J0.java 0 -Dprobe ;;
    VR2|T2)
      run "$C/$s.in" "$s.java" 257,0 -Dprobe
      run "$C/$s.in" "$s.J257dt.java" 257 -Ddirect -Dtranscript
      run "$C/$s.in" "$s.T0.java" 0 -Dtranscript ;;
    T2core)
      run "$C/T2core.in" T2core.J257d.java 257 -Dpath=core -Ddirect
      run "$C/T2core.in" T2core0.java 0 -Dprobe -Dpath=core ;;
    trace)
      trace "$C/sample.in" sample.J257 257 -Dpath=core
      trace "$C/sample.in" sample.J0 0 -Dpath=core ;;
    exc0)
      trace "$C/exc0.in" exc0.J257 257 -Dprobe
      trace "$C/exc0.in" exc0.J0 0 -Dprobe ;;
    FL)
      run "$C/FL.txt" FL.J257.java 257
      run "$C/FL.txt" FL.T257.java 257 -Dtranscript
      need "$CL_DIRTY/DirtyTwice.class"
      heavy "$CL_TOOLS/java/dirty/jdirty.sh" "$C/FL.txt" FL.dirty.java 257 - | tail -2
      python3 -I "$CL_TOOLS/java/dirty/dirty_split.py" FL.dirty.java ;;
    graph)
      run "$C/R.in" R.J64_321.java 64,321
      run "$C/R.in" R.J192_449.java 192,449
      run "$C/T2core.in" T2core.J64_321.java 64,321 -Dpath=core
      run "$C/T2core.in" T2core.J192_449.java 192,449 -Dpath=core
      for c in VR2 T2; do
        run "$C/$c.in" "$c.J321.java" 321
        run "$C/$c.in" "$c.J192_449.java" 192,449
      done ;;
    *) echo "java_refs.sh: unknown step $s" >&2; exit 2 ;;
  esac
done
echo "== $(date +%T) done: $CL_JAVA"
