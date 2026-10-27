#!/bin/bash
# corpus_gates.sh: the parity gates at OPTIMIZATION_STANDARD (257) and at
# OPTIMIZATION_NONE (0): the engine of this checkout (the vfuzz and vtrace
# builds in $CL_BIN) against the Java references of java_refs.sh. Keeps the
# reports, the differing ids and the guard and twice files in <outdir>; the
# frame and side files are deleted. Target: 0 differences in every report.
#   corpus_gates.sh <outdir> [steps]
# Every comparison at 257 excludes the ND ids of $CL_JAVA/<corpus>.mism.nd
# when gates/nd.sh made one. Steps (default all):
#   R       core257 on R: frames against R.java (J257), the Direct dump against
#           R.J257d.java, guard trips (target 0)
#   A       core257 on A: frames and printed status against A.java (J257; ND,
#           HANG, SOE and JEXC excluded, ND from A.mism.nd when it exists);
#           every guard trip must be a Java stack overflow (guardcheck.py)
#   T2core  core257 on T2core: frames and the Direct dump against
#           T2core.J257d.java
#   VR2 T2  view257: frames against <c>.java (J257), the Direct dump and the
#           measure-request transcripts against <c>.J257dt.java (T2-inplace
#           compared with its T2-fresh build; T2's transcripts with
#           --history, which reports the GONE and cache-hit hasBaseline flags
#           Android keeps from an in-place sequence separately)
#   twice   VR2 and T2 laid out twice in the same container (vfuzz
#           --twice-links), at each level of $TWICE_LEVELS (default "257 0");
#           every layout whose second layout differs from its first must give
#           Android's own dirty second layout (DirtyTwice) at that level.
#           T2-inplace is left out: DirtyTwice's first layout of an in-place
#           sequence is VOpDriver's non-dirty one, so the in-place gate
#           (inplace_gates.sh) compares those second layouts with the live
#           views' dirty second layout instead
#   twicefull  the same, but DirtyTwice lays out every layout of VR2 and T2
#           (T2-inplace left out) at each level, and the engine's first and
#           second layouts are compared with DirtyTwice's on every layout (a
#           few minutes per corpus and level)
#   trace   vtrace core257 on the trace sample against TraceJava's
#           sample.J257.trace, event for event (tracediff.py)
#   level0  the same at OPTIMIZATION_NONE: core0 on R, A (A.J0.java; HANG,
#           SOE and JEXC excluded) and T2core, view0 frames and transcripts
#           on VR2 and T2, vtrace core0 against sample.J0.trace. T2-inplace is
#           left out (--skip): at level 0 Android's live views lay 187 of its
#           sequences out unlike their fresh builds (a barrier keeps the
#           resolved flag allSolved set), and inplace_gates.sh compares every
#           one with the live views
# Build $CL_BIN/vfuzz.exe and vtrace.exe with -Dcl.trace=true (README.md,
# step 2). Each Dart run goes through `heavy` (env.sh).
set -u
. "$(dirname "$0")/../env.sh"
G=${1:?usage: corpus_gates.sh <outdir> [steps]}
STEPS=${2:-"R A T2core VR2 T2 twice trace level0"}
TWICE_LEVELS=${TWICE_LEVELS:-"257 0"}
mkdir -p "$G"; G=$(cd "$G" && pwd)
B=$CL_BIN; C=$CL_CORPORA; J=$CL_JAVA
CMP=$CL_TOOLS/compare
VC="nice -n 10 python3 -I $CMP/vcompare.py"
DC="nice -n 10 python3 -I $CMP/dcompare.py"
TC="nice -n 10 python3 -I $CMP/tcompare.py"
need "$B/vfuzz.exe"
line() { sed -n 2,4p "$1" | sed 's/^/   /'; }
for s in $STEPS; do
  echo "== $(date +%T) $s"
  case $s in
    R)
      need "$C/R.in" "$J/R.java" "$J/R.J257d.java"
      heavy "$B/vfuzz.exe" --corpus "$C/R.in" "$G/R.core257.txt" --path core257 --direct "$G/R.D" | tail -1
      ndo=(); [ -s "$J/R.mism.nd" ] && ndo=(--nd "$J/R.mism.nd")
      $VC "$G/R.core257.txt" "$J/R.java" --levels 257,0 --level 257 ${ndo[@]+"${ndo[@]}"} --show 8 \
        --mismatch-ids "$G/R.frames.ids" > "$G/R.frames.txt"; line "$G/R.frames.txt"
      $DC "$G/R.D" "$J/R.J257d.java" --level 257 ${ndo[@]+"${ndo[@]}"} --show 8 --mismatch-ids "$G/R.D.ids" > "$G/R.D.txt"
      line "$G/R.D.txt"
      echo "   guard: $(wc -l < "$G/R.core257.txt.guard") layouts"
      rm -f "$G/R.core257.txt" "$G/R.D" ;;
    A)
      need "$C/A.in" "$J/A.java"
      heavy "$B/vfuzz.exe" --corpus "$C/A.in" "$G/A.core257.txt" --path core257 | tail -1
      ndo=(); [ -s "$J/A.mism.nd" ] && ndo=(--nd "$J/A.mism.nd")
      $VC "$G/A.core257.txt" "$J/A.java" --levels 257,0 --level 257 ${ndo[@]+"${ndo[@]}"} --show 8 \
        --mismatch-ids "$G/A.frames.ids" > "$G/A.frames.txt"
      line "$G/A.frames.txt"
      echo "   $(nice -n 10 python3 -I "$CMP/guardcheck.py" "$G/A.core257.txt.guard" "$J/A.java" 257,0 257)"
      rm -f "$G/A.core257.txt" ;;
    T2core)
      need "$C/T2core.in" "$J/T2core.J257d.java"
      heavy "$B/vfuzz.exe" --corpus "$C/T2core.in" "$G/T2core.core257.txt" --path core257 --direct "$G/T2core.D" | tail -1
      ndo=(); [ -s "$J/T2core.mism.nd" ] && ndo=(--nd "$J/T2core.mism.nd")
      $VC "$G/T2core.core257.txt" "$J/T2core.J257d.java" --levels 257 --level 257 ${ndo[@]+"${ndo[@]}"} --show 8 \
        --mismatch-ids "$G/T2core.frames.ids" > "$G/T2core.frames.txt"; line "$G/T2core.frames.txt"
      $DC "$G/T2core.D" "$J/T2core.J257d.java" --level 257 ${ndo[@]+"${ndo[@]}"} --show 8 --mismatch-ids "$G/T2core.D.ids" \
        > "$G/T2core.D.txt"; line "$G/T2core.D.txt"
      echo "   guard: $(wc -l < "$G/T2core.core257.txt.guard") layouts"
      rm -f "$G/T2core.core257.txt" "$G/T2core.D" ;;
    VR2|T2)
      need "$C/$s.in" "$J/$s.java" "$J/$s.J257dt.java"
      extra=(); textra=()
      if [ "$s" = T2 ]; then
        extra=(--map T2-inplace=T2-fresh); textra=(--map T2-inplace=T2-fresh --history)
      fi
      [ -s "$J/$s.mism.nd" ] && extra+=(--nd "$J/$s.mism.nd") && textra+=(--nd "$J/$s.mism.nd")
      heavy "$B/vfuzz.exe" --corpus "$C/$s.in" "$G/$s.view257.txt" --path view257 --direct "$G/$s.D" \
        --transcript "$G/$s.T" | tail -1
      $VC "$G/$s.view257.txt" "$J/$s.java" --levels 257,0 --level 257 ${extra[@]+"${extra[@]}"} --show 8 \
        --mismatch-ids "$G/$s.frames.ids" > "$G/$s.frames.txt"; line "$G/$s.frames.txt"
      $DC "$G/$s.D" "$J/$s.J257dt.java" --level 257 ${extra[@]+"${extra[@]}"} --show 8 \
        --mismatch-ids "$G/$s.D.ids" > "$G/$s.D.txt"; line "$G/$s.D.txt"
      $TC "$G/$s.T" "$J/$s.J257dt.java" --level 257 ${textra[@]+"${textra[@]}"} --show 8 \
        --mismatch-ids "$G/$s.T.ids" > "$G/$s.T.txt"
      sed -n 2,6p "$G/$s.T.txt" | sed 's/^/   /'
      echo "   guard: $(wc -l < "$G/$s.view257.txt.guard") layouts"
      rm -f "$G/$s.view257.txt" "$G/$s.D" "$G/$s.T" ;;
    twice|twicefull)
      need "$CL_DIRTY/DirtyTwice.class"
      for lv in $TWICE_LEVELS; do
        for c in VR2 T2; do
          need "$C/$c.in"
          in=$C/$c.in
          if [ "$c" = T2 ]; then
            grep -v '^T2-inplace:' "$C/T2.in" > "$G/T2.noinplace.in"; in=$G/T2.noinplace.in
          fi
          heavy "$B/vfuzz.exe" --corpus "$in" "$G/$c.twice.txt" --path "view$lv" --twice-links | tail -1
          mv "$G/$c.twice.txt.twice" "$G/$c.view$lv.twice"
          n=$(wc -l < "$G/$c.view$lv.twice" | tr -d ' ')
          echo "   $c at $lv: $n layouts whose second layout differs from the first"
          if [ "$s" = twicefull ]; then
            # Every layout: the engine's first and second layouts against DirtyTwice's.
            nice -n 10 cut -f1,4,5 "$G/$c.twice.txt" > "$G/$c.view$lv.isg"
            nice -n 10 python3 -I - "$G/$c.view$lv.isg" "$G/$c.view$lv.twice" "$G/$c.view$lv.second" <<'PY'
import sys
isg, twice, out = sys.argv[1:4]
second = {}
for l in open(twice):
    f = l.rstrip("\n").split("\t")
    if len(f) >= 4:
        second[f[0]] = f[3]
with open(out, "w") as o:
    for l in open(isg):
        f = l.rstrip("\n").split("\t")
        g = second.get(f[0], f[2])
        st = f[1]
        if f[0] in second:
            st = g[1:g.index(" | ")] if g.startswith("!") else "ok"
        o.write("%s\t%s\t%s\n" % (f[0], st, g))
PY
            heavy "$CL_TOOLS/java/dirty/jdirty.sh" "$in" "$G/$c.dirty$lv.java" "$lv" | tail -1
            nice -n 10 python3 -I "$CL_TOOLS/java/dirty/dirty_split.py" "$G/$c.dirty$lv.java" | sed 's/^/   /'
            for w in first second; do
              a=$G/$c.view$lv.isg; [ $w = second ] && a=$G/$c.view$lv.second
              $VC "$a" "$G/$c.dirty$lv.java.$w.java" --levels 257 --level 257 --strict --show 8 \
                --mismatch-ids "$G/$c.twice$lv.$w.ids" > "$G/$c.twice$lv.$w.txt"
              echo "   the engine's $w layout against DirtyTwice's:"; line "$G/$c.twice$lv.$w.txt"
            done
            rm -f "$G/$c.view$lv.isg" "$G/$c.view$lv.second" "$G/$c.dirty$lv.java" \
              "$G/$c.dirty$lv.java.first.java" "$G/$c.dirty$lv.java.second.java"
          fi
          rm -f "$G/$c.twice.txt" "$G/$c.twice.txt.sum" "$G/$c.twice.txt.guard" "$G/$c.twice.txt.err"
          [ "$s" = twicefull ] && continue
          [ "$n" = 0 ] && continue
          cut -f1 "$G/$c.view$lv.twice" > "$G/$c.twice$lv.ids"
          heavy "$CL_TOOLS/java/dirty/jdirty.sh" "$in" "$G/$c.dirty$lv.java" "$lv" "$G/$c.twice$lv.ids" | tail -1
          nice -n 10 python3 -I - "$G/$c.view$lv.twice" "$G/$c.dirty$lv.java" <<'PY'
import sys
dart = {}
for l in open(sys.argv[1]):
    p = l.rstrip("\n").split("\t")
    dart[p[0]] = (p[2], p[3])
same = differ = other = 0
for l in open(sys.argv[2]):
    p = l.rstrip("\n").split("\t")
    if p[0] not in dart:
        continue
    if len(p) != 3:
        other += 1
        print("   %s: Java %s" % (p[0], " ".join(p[1:])[:60]))
        continue
    if dart[p[0]] == (p[1], p[2]):
        same += 1
    else:
        differ += 1
        print("   %s: the second layout differs from Android's" % p[0])
print("   Android's dirty second layout: %d equal, %d differ, %d without one (HANG or THREW)"
      % (same, differ, other))
PY
        done
        rm -f "$G/T2.noinplace.in"
      done ;;
    trace)
      need "$B/vtrace.exe" "$C/sample.in" "$J/sample.J257.trace"
      heavy "$B/vtrace.exe" "$C/sample.in" "$G/sample.core257.trace" --path core257 --level 257
      nice -n 10 python3 -I "$CMP/tracediff.py" "$G/sample.core257.trace" "$J/sample.J257.trace" --max 5 \
        > "$G/trace257.txt"; tail -4 "$G/trace257.txt" | sed 's/^/   /'
      rm -f "$G/sample.core257.trace" ;;
    level0)
      need "$J/R.java" "$J/A.J0.java" "$J/T2core0.java" "$J/VR2.T0.java" "$J/T2.T0.java" "$J/sample.J0.trace"
      heavy "$B/vfuzz.exe" --corpus "$C/R.in" "$G/R.core0.txt" --path core0 | tail -1
      $VC "$G/R.core0.txt" "$J/R.java" --levels 257,0 --level 0 --show 8 \
        --mismatch-ids "$G/R.core0.ids" > "$G/R.core0.J0.txt"; line "$G/R.core0.J0.txt"
      heavy "$B/vfuzz.exe" --corpus "$C/A.in" "$G/A.core0.txt" --path core0 | tail -1
      $VC "$G/A.core0.txt" "$J/A.J0.java" --levels 0 --level 0 --exclude HANG,SOE,JEXC --show 8 \
        --mismatch-ids "$G/A.core0.ids" > "$G/A.core0.J0.txt"; line "$G/A.core0.J0.txt"
      heavy "$B/vfuzz.exe" --corpus "$C/T2core.in" "$G/T2core.core0.txt" --path core0 | tail -1
      $VC "$G/T2core.core0.txt" "$J/T2core0.java" --levels 0 --level 0 --show 8 \
        --mismatch-ids "$G/T2core.core0.ids" > "$G/T2core.core0.J0.txt"; line "$G/T2core.core0.J0.txt"
      for c in VR2 T2; do
        m=(); [ "$c" = T2 ] && m=(--skip T2-inplace)
        heavy "$B/vfuzz.exe" --corpus "$C/$c.in" "$G/$c.view0.txt" --path view0 --transcript "$G/$c.T0" | tail -1
        $VC "$G/$c.view0.txt" "$J/$c.java" --levels 257,0 --level 0 ${m[@]+"${m[@]}"} --show 8 \
          --mismatch-ids "$G/$c.view0.ids" > "$G/$c.view0.J0.txt"; line "$G/$c.view0.J0.txt"
        $TC "$G/$c.T0" "$J/$c.T0.java" --level 0 ${m[@]+"${m[@]}"} --show 8 > "$G/$c.T0.txt"
        sed -n 2,4p "$G/$c.T0.txt" | sed 's/^/   /'
        rm -f "$G/$c.view0.txt" "$G/$c.T0"
      done
      heavy "$B/vtrace.exe" "$C/sample.in" "$G/sample.core0.trace" --path core0 --level 0
      nice -n 10 python3 -I "$CMP/tracediff.py" "$G/sample.core0.trace" "$J/sample.J0.trace" --max 3 \
        > "$G/trace0.txt"; tail -3 "$G/trace0.txt" | sed 's/^/   /'
      rm -f "$G/R.core0.txt" "$G/A.core0.txt" "$G/T2core.core0.txt" "$G/sample.core0.trace" ;;
    *) echo "corpus_gates.sh: unknown step $s" >&2; exit 2 ;;
  esac
done
rm -f "$G"/*.txt.sum
echo "== $(date +%T) done; reports in $G"
