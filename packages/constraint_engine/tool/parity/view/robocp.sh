#!/bin/bash
# Prints the runtime classpath of the RoboOracle (Robolectric 4.16, SDK 35):
# the jars fetch.sh downloaded into $CL_ROBO, the classes.jar of each AAR, the
# core, and the Android framework jar last.
#   robocp.sh [core]   core: pin (default, $CL_CORE, upstream's core at the
#                      pin) | rel (constraintlayout-core 1.1.1)
#                      view layer: the ConstraintLayout 2.2.1 AAR's classes.jar
set -e
. "$(dirname "$0")/../env.sh"
J=$CL_ROBO/jars
X=$CL_ROBO/x
jar() { # artifact version [file]
  local f=$J/${3:-$1-$2.jar}
  if [ ! -f "$f" ]; then echo "missing $f (run view/fetch.sh)" >&2; exit 2; fi
  printf '%s' "$f"
}
cp=()
for m in robolectric sandbox shadows-framework utils utils-reflector resources annotations \
         pluginapi plugins-maven-dependency-resolver shadowapi junit nativeruntime; do
  cp+=("$(jar "$m" 4.16)")
done
cp+=("$(jar nativeruntime-dist-compat 1.0.18)")
cp+=("$(jar javax.inject 1)")
cp+=("$(jar javax.annotation-api 1.3.2)")
cp+=("$(jar bcprov-jdk18on 1.81)")
cp+=("$(jar conscrypt-openjdk-uber 2.5.2)")
cp+=("$(jar snakeyaml 2.4)")
cp+=("$(jar asm 9.8)")
cp+=("$(jar asm-commons 9.8)")
cp+=("$(jar asm-tree 9.8)")
cp+=("$(jar guava 33.4.8-android)")
cp+=("$(jar failureaccess 1.0.3)")
cp+=("$(jar sqlite4java 1.0.392)")
cp+=("$(jar icu4j 77.1)")
cp+=("$(jar auto-value-annotations 1.11.0)")
cp+=("$(jar error_prone_annotations 2.36.0)")
cp+=("$(jar junit 4.13.2)")
cp+=("$(jar hamcrest-core 1.3)")
cp+=("$(jar annotation-jvm 1.8.1)")
cp+=("$(jar kotlin-stdlib 2.0.21)")
for x in aar-monitor aar-idling aar-tracing cl221-aar; do
  [ -f "$X/$x/classes.jar" ] || { echo "missing $X/$x/classes.jar (run view/fetch.sh)" >&2; exit 2; }
  cp+=("$X/$x/classes.jar")
done
case "${1:-pin}" in
  pin) need "$CL_CORE/androidx/constraintlayout/core/LinearSystem.class"; cp+=("$CL_CORE") ;;
  rel) cp+=("$(jar constraintlayout-core 1.1.1)") ;;
  *) echo "core must be pin or rel" >&2; exit 2 ;;
esac
A=$CL_ROBO/android-all/android-all-instrumented-15-robolectric-13954326-i7.jar
[ -f "$A" ] || { echo "missing $A (run view/fetch.sh)" >&2; exit 2; }
cp+=("$A")
(IFS=:; printf '%s\n' "${cp[*]}")
