#!/bin/bash
# setup.sh: sets up the Flutter harness outside the repository, in $CL_FL
# (default $CL_PARITY_WORK/fl), resolving the adapter and the engine of a
# checkout (default: this one).
#   setup.sh [tree]
# Copies lib/, bin/, test/ and tool/ to $CL_FL, writes $CL_FL/pubspec.yaml
# from pubspec.yaml.in (path dependencies on <tree>/packages), copies the
# shared content model (the engine's tool/parity/dart/content.dart) to
# $CL_FL/shared/ for test/content_model_box_test.dart, and runs `flutter pub
# get` there. Run it again after changing the harness sources; the runner
# (run_fl.sh) then runs in $CL_FL. Nothing is written into the repository.
set -eu
H=$(cd "$(dirname "$0")" && pwd)
. "$H/../../../../constraint_engine/tool/parity/env.sh"
T=$(cd "${1:-$CL_REPO}" && pwd)
[ -f "$T/packages/flutter_constraint_layout/pubspec.yaml" ] || {
  echo "setup.sh: $T is not a checkout of this repository" >&2; exit 2; }
mkdir -p "$CL_FL"
D=$(cd "$CL_FL" && pwd)
case "$D/" in
  "$CL_REPO"/*) echo "setup.sh: \$CL_FL ($D) must be outside the repository" >&2; exit 2 ;;
esac
rm -rf "$D/lib" "$D/bin" "$D/test" "$D/tool" "$D/shared"
cp -R "$H/lib" "$H/bin" "$H/test" "$H/tool" "$D/"
mkdir -p "$D/shared"
cp "$CL_TOOLS/dart/content.dart" "$D/shared/content.dart"
sed "s#@TREE@#$T#g" "$H/pubspec.yaml.in" > "$D/pubspec.yaml"
(cd "$D" && nice -n 10 flutter pub get > pubget.log 2>&1) || {
  echo "setup.sh: flutter pub get failed, see $D/pubget.log" >&2; exit 1; }
python3 -I - "$D" "$T" <<'PY'
import json, sys
d, t = sys.argv[1], sys.argv[2]
pc = json.load(open(d + '/.dart_tool/package_config.json'))
for p in pc['packages']:
    if p['name'] in ('constraint_engine', 'flutter_constraint_layout'):
        print('%s -> %s' % (p['name'], p['rootUri']))
        assert t in p['rootUri'], 'the harness does not resolve the checkout'
PY
echo "harness at $D resolves $T"
