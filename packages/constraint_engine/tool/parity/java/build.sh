#!/bin/bash
# build.sh: compiles VOpDriver, ViewHost, DirectProbe and the access helpers
# (src/) against upstream's core at the pin ($CL_CORE, build_core.sh) into
# $CL_ORACLE. Light (seconds).
#   build.sh
# Atomic: it compiles into a fresh directory and swaps it in with one rename,
# so a JVM that is running from $CL_ORACLE never finds the directory missing.
# Still, rebuild only between runs: a running JVM loads not-yet-loaded classes
# from the new build. The sources are the oracle's v2 build ("VOpDriver
# version" prints the stamp), the one every parity result was measured with.
set -e
. "$(dirname "$0")/../env.sh"
D=$CL_TOOLS/java
need "$CL_CORE/androidx/constraintlayout/core/LinearSystem.class"
NEW=$CL_ORACLE.new.$$
rm -rf "$NEW"
mkdir -p "$NEW"
find "$D/src" -name '*.java' > "$NEW/.sources"
javac -nowarn -encoding UTF-8 -d "$NEW" -cp "$CL_CORE" @"$NEW/.sources"
rm -f "$NEW/.sources"
if [ -d "$CL_ORACLE" ]; then
  mv "$CL_ORACLE" "$CL_ORACLE.old.$$"
fi
mv "$NEW" "$CL_ORACLE"
rm -rf "$CL_ORACLE.old.$$"
echo "built $CL_ORACLE ($(grep -o 'VERSION = "[^"]*"' "$D/src/VOpDriver.java"))"
