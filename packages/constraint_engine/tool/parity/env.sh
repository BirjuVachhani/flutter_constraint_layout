# Sourced by every parity script: the locations they read and write, each an
# environment variable with a default under one work directory. Nothing here
# writes into the repository. See README.md in this directory.
#
#   CL_PARITY_WORK  the work directory (default ${TMPDIR:-/tmp}/cl_parity)
#   CL_UPSTREAM     upstream's androidx/constraintlayout checkout at the pin
#                   (default $CL_PARITY_WORK/upstream)
#   CL_CORE         upstream's core classes at the pin (java/build_core.sh)
#   CL_ORACLE       VOpDriver and its probes (java/build.sh)
#   CL_TRACE        TraceJava: the core with trace hooks (java/trace/build_trace.sh)
#   CL_DIRTY        DirtyTwice (java/dirty/build_dirty.sh)
#   CL_BIN          the compiled Dart tools (vfuzz.exe, vtrace.exe, gclass.exe)
#   CL_CORPORA      the corpus files (gates/corpora.sh)
#   CL_JAVA         the Java references (gates/java_refs.sh)
#   CL_ROBO         RoboOracle's downloads and classes (view/fetch.sh)
#   CL_FL           the Flutter harness, set up outside the repository
#                   (packages/flutter_constraint_layout/tool/parity/fl_harness)
#   CL_HEAVY        optional: a command that runs one heavy step at a time
#                   (a lock, a priority wrapper); empty runs them at nice 10
#   CL_CP           optional: replaces $CL_CORE on the classpath of jrun.sh
#                   and jbatch3.sh (TraceJava's runs set it to $CL_TRACE)

# tool/parity in this checkout, and the repository root.
CL_TOOLS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CL_REPO=$(cd "$CL_TOOLS/../../../.." && pwd)

: "${CL_PARITY_WORK:=${TMPDIR:-/tmp}/cl_parity}"
CL_PARITY_WORK=${CL_PARITY_WORK%/}
: "${CL_UPSTREAM:=$CL_PARITY_WORK/upstream}"
: "${CL_CORE:=$CL_PARITY_WORK/classes/core}"
: "${CL_ORACLE:=$CL_PARITY_WORK/classes/oracle}"
: "${CL_TRACE:=$CL_PARITY_WORK/classes/trace}"
: "${CL_DIRTY:=$CL_PARITY_WORK/classes/dirty}"
: "${CL_BIN:=$CL_PARITY_WORK/bin}"
: "${CL_CORPORA:=$CL_PARITY_WORK/corpora}"
: "${CL_JAVA:=$CL_PARITY_WORK/java}"
: "${CL_ROBO:=$CL_PARITY_WORK/robo}"
: "${CL_FL:=$CL_PARITY_WORK/fl}"
export CL_PARITY_WORK CL_UPSTREAM CL_CORE CL_ORACLE CL_TRACE CL_DIRTY CL_BIN \
  CL_CORPORA CL_JAVA CL_ROBO CL_FL CL_TOOLS CL_REPO

# The upstream commit the port is pinned to (UPSTREAM.md).
CL_PIN=9cd4b5a4079a14175f91dc897abd83270799364a

# heavy <command> [args...]: one heavy step (a JVM batch, a Dart corpus run, a
# Flutter test run), through $CL_HEAVY when it is set, else at nice 10.
heavy() {
  if [ -n "${CL_HEAVY:-}" ]; then
    "$CL_HEAVY" "$@"
  else
    nice -n 10 "$@"
  fi
}

# need <file>...: stop with a message when an input is missing.
need() {
  local f
  for f in "$@"; do
    if [ ! -e "$f" ]; then
      echo "missing $f (see tool/parity/README.md)" >&2
      exit 2
    fi
  done
}
