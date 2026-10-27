#!/bin/bash
# ref_runs.sh: bit identity. The Dart outputs at 257 of the engine of this
# checkout, reduced to their content and hashed, so that two builds (before
# and after a change that must not move a pixel) compare line for line:
#   ref_runs.sh <outdir> [steps]
#   diff <reference outdir>/SHA256SUMS.content <outdir>/SHA256SUMS.content
# No Java run is needed: a reference that matched Java carries that over.
# Steps (default all, in this order):
#   R       core257 on R.in, with the Direct dump
#   A       core257 on A.in, with the Direct dump
#   T2core  core257 on T2core.in, with the Direct dump
#   VR2     view257 on VR2.in, with the Direct dump and the transcript
#   T2      view257 on T2.in, the same
#   trace   vtrace core257 on the trace sample (sample.in)
#   FL      the Flutter runner on FL.txt (tag p5a, with the dry-layout check):
#           the real adapter of the checkout the harness in $CL_FL resolves
#   twice   view257 --twice-links on VR2 and T2: the second layout in the
#           same container
#   FLr     the Flutter runner's replay mode: the adapter's second layout of
#           each FL layout
# Kept per step: <c>.<path>.isg.gz (id, status, geometry: fields 1, 4, 5), the
# side files gzipped (<c>.<path>.D.gz, .T.gz, .dry.gz, the trace), and the
# .guard file. SHA256SUMS.content gets the sha256 of each kept file's
# uncompressed content and of the full output file (<c>.<path>.txt, not kept:
# it repeats the corpus's op lists); SHA256SUMS gets the sha256 of the files
# kept. Each heavy step goes through `heavy` (env.sh). Needs $CL_BIN/vfuzz.exe
# and vtrace.exe built with -Dcl.trace=true.
set -u
. "$(dirname "$0")/../env.sh"
G=${1:?usage: ref_runs.sh <outdir> [steps]}
STEPS=${2:-"R A T2core VR2 T2 trace FL twice FLr"}
mkdir -p "$G"
G=$(cd "$G" && pwd)
B=$CL_BIN; C=$CL_CORPORA
F=$CL_REPO/packages/flutter_constraint_layout/tool/parity/fl_harness/run_fl.sh
cd "$G" || exit 2
sums() { # <name> <file>: the content sha256 of <file> under <name>
  printf '%s  %s\n' "$(nice -n 10 shasum -a 256 < "$2" | cut -d' ' -f1)" "$1" >> SHA256SUMS.content
}
keep() { # <file>: gzip it (no name, no time) and record both hashes
  sums "$1" "$1"
  nice -n 10 gzip -n -6 -f "$1"
  nice -n 10 shasum -a 256 "$1.gz" >> SHA256SUMS
}
isg() { # <full.txt>: keep id, status, geometry
  local base=${1%.txt}
  sums "$1" "$1"
  nice -n 10 cut -f1,4,5 "$1" > "$base.isg"
  keep "$base.isg"
  rm -f "$1"
}
for s in $STEPS; do
  echo "== $(date +%T) $s"
  case $s in
    R|A|T2core)
      need "$B/vfuzz.exe" "$C/$s.in"
      heavy "$B/vfuzz.exe" --corpus "$C/$s.in" "$s.core257.txt" --path core257 --direct "$s.core257.D" | tail -1
      isg "$s.core257.txt"; keep "$s.core257.D"; sums "$s.core257.guard" "$s.core257.txt.guard"
      mv "$s.core257.txt.guard" "$s.core257.guard"; mv "$s.core257.txt.sum" "$s.core257.sum" ;;
    VR2|T2)
      need "$B/vfuzz.exe" "$C/$s.in"
      heavy "$B/vfuzz.exe" --corpus "$C/$s.in" "$s.view257.txt" --path view257 \
        --direct "$s.view257.D" --transcript "$s.view257.T" | tail -1
      isg "$s.view257.txt"; keep "$s.view257.D"; keep "$s.view257.T"
      sums "$s.view257.guard" "$s.view257.txt.guard"
      mv "$s.view257.txt.guard" "$s.view257.guard"; mv "$s.view257.txt.sum" "$s.view257.sum" ;;
    trace)
      need "$B/vtrace.exe" "$C/sample.in"
      heavy "$B/vtrace.exe" "$C/sample.in" sample.core257.trace --path core257 --level 257
      keep sample.core257.trace ;;
    FL)
      need "$C/FL.txt"
      heavy "$F" "$C/FL.txt" "$G/FL.fl.txt" p5a dry | tail -4
      isg FL.fl.txt; mv FL.fl.txt.dry FL.fl.dry; keep FL.fl.dry ;;
    twice)
      # The same container laid out again (vfuzz --twice-links, FORMATS.md 18.6): kept are
      # the layouts whose second measure differs from the first (<c>.view257.twice). The
      # first measure is the plain run's, checked against <c>.view257.isg.gz.
      for c in VR2 T2; do
        need "$B/vfuzz.exe" "$C/$c.in"
        heavy "$B/vfuzz.exe" --corpus "$C/$c.in" "$c.twice.txt" --path view257 --twice-links | tail -1
        if nice -n 10 cut -f1,4,5 "$c.twice.txt" | cmp -s - <(gzip -dc "$c.view257.isg.gz"); then
          echo "   first measure = $c.view257.isg"
        else
          echo "   first measure DIFFERS from $c.view257.isg"
        fi
        mv "$c.twice.txt.twice" "$c.view257.twice"; keep "$c.view257.twice"
        rm -f "$c.twice.txt" "$c.twice.txt.sum" "$c.twice.txt.guard" "$c.twice.txt.err"
      done ;;
    FLr)
      # The Flutter runner's replay mode (FORMATS.md 19.1): each layout pumped once, then
      # laid out four more times in the same ConstraintLayout under cl.verifyReplay. Kept:
      # the second layout's frames (FLr.second.isg) and the per-layout replay record
      # (FLr.fl.replay). The first layout is the FL step's, checked against FL.fl.isg.gz.
      need "$C/FL.txt"
      heavy "$F" "$C/FL.txt" "$G/FLr.fl.txt" p5a replay | tail -4
      if nice -n 10 cut -f1,4,5 FLr.fl.txt | cmp -s - <(gzip -dc FL.fl.isg.gz); then
        echo "   first layout = FL.fl.isg"
      else
        echo "   first layout DIFFERS from FL.fl.isg"
      fi
      mv FLr.fl.txt.second FLr.second.txt; isg FLr.second.txt
      mv FLr.fl.txt.replay FLr.fl.replay; keep FLr.fl.replay
      rm -f FLr.fl.txt ;;
    *) echo "ref_runs.sh: unknown step $s" >&2; exit 2 ;;
  esac
done
echo "== $(date +%T) done"
