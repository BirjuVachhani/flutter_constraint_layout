#!/bin/bash
# vop.sh <VOpDriver arguments>: runs VOpDriver once on upstream's core at the
# pin ($CL_CORE, or $CL_CP) and the oracle ($CL_ORACLE), with jrun.sh's JVM
# flags, for the commands outside a batch (FORMATS.md 8.1):
#   vop.sh version      the build stamp (8.8)
#   vop.sh probes       ViewProbe's three probes through the view path
#   vop.sh serve 257    stdin "id\tops" lines, stdout result lines
# Batches go through jrun.sh, which restarts after a hang.
. "$(dirname "$0")/../env.sh"
need "$CL_ORACLE/VOpDriver.class"
exec java -XX:+UnlockExperimentalVMOptions -XX:hashCode=2 -Xmx1g -Xss32m -XX:+UseSerialGC \
  -XX:-OmitStackTraceInFastThrow -XX:CICompilerCount=2 -cp "${CL_CP:-$CL_CORE}:$CL_ORACLE" VOpDriver "$@"
