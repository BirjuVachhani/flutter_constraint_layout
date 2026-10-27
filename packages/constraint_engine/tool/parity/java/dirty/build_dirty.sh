#!/bin/bash
# build_dirty.sh: compiles DirtyTwice.java against upstream's core at the pin
# ($CL_CORE) and the oracle ($CL_ORACLE, java/build.sh) into $CL_DIRTY, its own
# directory. Light (seconds). Atomic, as build.sh: rebuild only between runs.
#   build_dirty.sh
set -e
. "$(dirname "$0")/../../env.sh"
need "$CL_CORE/androidx/constraintlayout/core/LinearSystem.class" "$CL_ORACLE/VOpDriver.class"
CP=$CL_CORE:$CL_ORACLE
NEW=$CL_DIRTY.new.$$
rm -rf "$NEW"; mkdir -p "$NEW"
javac -nowarn -encoding UTF-8 -d "$NEW" -cp "$CP" "$CL_TOOLS/java/dirty/DirtyTwice.java"
[ -d "$CL_DIRTY" ] && mv "$CL_DIRTY" "$CL_DIRTY.old.$$"
mv "$NEW" "$CL_DIRTY"
rm -rf "$CL_DIRTY.old.$$"
echo "built $CL_DIRTY"
