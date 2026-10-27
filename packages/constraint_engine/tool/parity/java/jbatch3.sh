#!/bin/bash
# jbatch3.sh <in> <out> [levels] [primary.java]: ND detection (Android's own
# hash-order nondeterminism, README.md step 4), for the layouts that mismatch
# only. BL's jbatch3.sh on VOpDriver: three JVM runs side by side (default
# identity hash, -XX:hashCode=3, default hash), each building every layout
# three times at 257 (-Dbuilds=3). A layout is ND when its geometry differs
# within a run (status ND), between runs, or from the primary hashCode=2
# result when [primary.java] (a jrun.sh output) is given. Output: run a's
# lines with status ND where found. A heavy step (three JVMs side by side):
# run it through `heavy` (env.sh) or your own lock. The classpath is
# jrun.sh's.
. "$(dirname "$0")/../env.sh"
in=$1; out=$2; levels=${3:-257,0}; primary=${4:-}
CP=${CL_CP:-$CL_CORE}:$CL_ORACLE
need "$in" "$CL_ORACLE/VOpDriver.class"
run() { # <out> <jvm flags...>
  local o=$1; shift; local prog=$o.progress; : > "$o"; local start=0
  while :; do
    java "$@" -Dbuilds=3 -Xmx1g -Xss32m -XX:+UseSerialGC -XX:CICompilerCount=2 -XX:-OmitStackTraceInFastThrow -cp "$CP" \
      VOpDriver batch "$in" "$o" "$prog" "$start" "$levels"
    [ "$(cat "$prog")" = "DONE" ] && break
    local idx; idx=$(cat "$prog")
    local id; id=$(sed -n "$((idx + 1))p" "$in" | cut -f1)
    [ "$(tail -n 1 "$o" | cut -f1)" != "$id" ] && printf '%s\tHANG\n' "$id" >> "$o"
    start=$((idx + 1)); echo "jbatch3: restart after line $start" >&2
  done
  rm -f "$prog"
}
run "$out.a" &
run "$out.b" -XX:+UnlockExperimentalVMOptions -XX:hashCode=3 &
run "$out.c" &
wait
nlev=$(echo "$levels" | tr ',' '\n' | wc -l | tr -d ' ')
python3 -I - "$out" "$nlev" "$primary" <<'PY'
import sys
out, nlev, primary = sys.argv[1], int(sys.argv[2]), sys.argv[3]
def geoms(p):
    return tuple(p[2:2 + nlev]) if len(p) >= 2 + nlev else None
def load(f):
    d = {}
    for l in open(f):
        q = l.rstrip('\n').split('\t')
        d[q[0]] = (q[1], geoms(q))
    return d
others = [load(out + '.b'), load(out + '.c')]
if primary:
    others.append(load(primary))
nd = 0
with open(out, 'w') as o:
    for l in open(out + '.a'):
        p = l.rstrip('\n').split('\t')
        if len(p) > 2 and p[1] in ('ok', 'ND'):
            g = geoms(p)
            for d in others:
                q = d.get(p[0])
                if q is None or q[1] is None:
                    continue
                if q[1] != g or q[0] == 'ND':
                    p[1] = 'ND'
            if p[1] == 'ND':
                nd += 1
        o.write('\t'.join(p) + '\n')
print('jbatch3: %d ND' % nd, file=sys.stderr)
PY
rm -f "$out.a" "$out.b" "$out.c"
