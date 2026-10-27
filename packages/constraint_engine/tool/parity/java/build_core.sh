#!/bin/bash
# build_core.sh: compiles upstream's core at the pin, every source file of
# constraintlayout/core/src/main/java in $CL_UPSTREAM (the
# androidx/constraintlayout checkout at commit $CL_PIN), together with three
# annotation stubs (stubs/androidx/annotation: NonNull, Nullable,
# RestrictTo), into $CL_CORE. A JDK 17 or later; the oracle was built and run
# on JDK 21. Light (seconds).
#   build_core.sh
# It refuses a checkout at another commit: the parity results hold for the pin.
set -eu
. "$(dirname "$0")/../env.sh"
SRC=$CL_UPSTREAM/constraintlayout/core/src/main/java
need "$SRC/androidx/constraintlayout/core/LinearSystem.java"
head=$(git -C "$CL_UPSTREAM" rev-parse HEAD 2>/dev/null || echo unknown)
if [ "$head" != "$CL_PIN" ]; then
  echo "build_core.sh: $CL_UPSTREAM is at $head, not at the pin $CL_PIN" >&2
  echo "  git -C $CL_UPSTREAM checkout $CL_PIN" >&2
  exit 2
fi
NEW=$CL_CORE.new.$$
rm -rf "$NEW"; mkdir -p "$NEW"
{ find "$SRC" -name '*.java'; find "$CL_TOOLS/java/stubs" -name '*.java'; } > "$NEW/.sources"
javac -nowarn -encoding UTF-8 -d "$NEW" @"$NEW/.sources"
rm -f "$NEW/.sources"
mkdir -p "$(dirname "$CL_CORE")"
[ -d "$CL_CORE" ] && mv "$CL_CORE" "$CL_CORE.old.$$"
mv "$NEW" "$CL_CORE"
rm -rf "$CL_CORE.old.$$"
echo "built $CL_CORE ($(find "$CL_CORE" -name '*.class' | wc -l | tr -d ' ') classes) from $SRC"
