#!/bin/bash
# fetch.sh: downloads what the RoboOracle runs on, from the official
# repositories, into $CL_ROBO (default $CL_PARITY_WORK/robo):
#
#   - Robolectric 4.16 and its runtime dependencies, from Maven Central
#     (https://repo1.maven.org/maven2), into $CL_ROBO/jars;
#   - Robolectric's Android 15 framework jar (android-all-instrumented
#     15-robolectric-13954326-i7, SDK 35), from Maven Central, into
#     $CL_ROBO/android-all, the directory Robolectric's offline mode reads;
#   - ConstraintLayout 2.2.1 (the AAR, whose classes.jar is the view layer,
#     and its sources jar), constraintlayout-core 1.1.1 (jar and sources), and
#     the androidx test, tracing and annotation libraries Robolectric loads,
#     from Google's Maven repository (https://dl.google.com/android/maven2),
#     each AAR's classes.jar extracted into $CL_ROBO/x/<name>/.
#
# Every file is checked against the SHA-1 the repository publishes next to it
# (<file>.sha1); a file already present with the right SHA-1 is kept, so a
# second run downloads nothing. About 400 MB, most of it Robolectric's native
# runtime (nativeruntime-dist-compat) and the Android jar.
#   fetch.sh
set -eu
. "$(dirname "$0")/../env.sh"
CENTRAL=https://repo1.maven.org/maven2
GOOGLE=https://dl.google.com/android/maven2

# fetch <repo> <group> <artifact> <version> <file> <dir>
fetch() {
  local repo=$1 group=$2 artifact=$3 version=$4 file=$5 dir=$6
  local url=$repo/${group//.//}/$artifact/$version/$file
  mkdir -p "$dir"
  local want
  want=$(curl -fsS "$url.sha1" | cut -c1-40)
  if [ -f "$dir/$file" ] && [ "$(shasum -a 1 "$dir/$file" | cut -c1-40)" = "$want" ]; then
    return
  fi
  echo "fetch $url"
  curl -fsS -o "$dir/$file.part" "$url"
  local got
  got=$(shasum -a 1 "$dir/$file.part" | cut -c1-40)
  if [ "$got" != "$want" ]; then
    echo "fetch.sh: SHA-1 of $file is $got, the repository says $want" >&2
    rm -f "$dir/$file.part"
    exit 1
  fi
  mv "$dir/$file.part" "$dir/$file"
}

# jar <repo> <group> <artifact> <version> [file]: into $CL_ROBO/jars.
jar() {
  fetch "$1" "$2" "$3" "$4" "${5:-$3-$4.jar}" "$CL_ROBO/jars"
}

# aar <group> <artifact> <version> <name>: from Google's Maven repository,
# with classes.jar extracted into $CL_ROBO/x/<name>.
aar() {
  fetch "$GOOGLE" "$1" "$2" "$3" "$2-$3.aar" "$CL_ROBO/aar"
  mkdir -p "$CL_ROBO/x/$4"
  unzip -o -q "$CL_ROBO/aar/$2-$3.aar" classes.jar -d "$CL_ROBO/x/$4"
}

for m in robolectric sandbox shadows-framework utils utils-reflector resources annotations \
         pluginapi plugins-maven-dependency-resolver shadowapi junit nativeruntime; do
  jar "$CENTRAL" org.robolectric "$m" 4.16
done
jar "$CENTRAL" org.robolectric nativeruntime-dist-compat 1.0.18
jar "$CENTRAL" javax.inject javax.inject 1
jar "$CENTRAL" javax.annotation javax.annotation-api 1.3.2
jar "$CENTRAL" org.bouncycastle bcprov-jdk18on 1.81
jar "$CENTRAL" org.conscrypt conscrypt-openjdk-uber 2.5.2
jar "$CENTRAL" org.yaml snakeyaml 2.4
jar "$CENTRAL" org.ow2.asm asm 9.8
jar "$CENTRAL" org.ow2.asm asm-commons 9.8
jar "$CENTRAL" org.ow2.asm asm-tree 9.8
jar "$CENTRAL" com.google.guava guava 33.4.8-android
jar "$CENTRAL" com.google.guava failureaccess 1.0.3
jar "$CENTRAL" com.almworks.sqlite4java sqlite4java 1.0.392
jar "$CENTRAL" com.ibm.icu icu4j 77.1
jar "$CENTRAL" com.google.auto.value auto-value-annotations 1.11.0
jar "$CENTRAL" com.google.errorprone error_prone_annotations 2.36.0
jar "$CENTRAL" junit junit 4.13.2
jar "$CENTRAL" org.hamcrest hamcrest-core 1.3
jar "$CENTRAL" org.jetbrains.kotlin kotlin-stdlib 2.0.21
jar "$GOOGLE" androidx.annotation annotation-jvm 1.8.1
jar "$GOOGLE" androidx.constraintlayout constraintlayout-core 1.1.1
jar "$GOOGLE" androidx.constraintlayout constraintlayout-core 1.1.1 constraintlayout-core-1.1.1-sources.jar
jar "$GOOGLE" androidx.constraintlayout constraintlayout 2.2.1 constraintlayout-2.2.1-sources.jar
fetch "$CENTRAL" org.robolectric android-all-instrumented 15-robolectric-13954326-i7 \
  android-all-instrumented-15-robolectric-13954326-i7.jar "$CL_ROBO/android-all"
aar androidx.test monitor 1.8.0 aar-monitor
aar androidx.test.espresso espresso-idling-resource 3.7.0 aar-idling
aar androidx.tracing tracing 1.2.0 aar-tracing
aar androidx.constraintlayout constraintlayout 2.2.1 cl221-aar
echo "fetched into $CL_ROBO"
