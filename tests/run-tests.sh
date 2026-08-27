#!/usr/bin/env bash
#
# Behavioural tests for the P2Rank image.
#
#   IMAGE=p2rank:local tests/run-tests.sh
#
# Every test runs the real image the way a user or a workflow engine would.
# No dependencies beyond bash, docker and coreutils.

set -uo pipefail

IMAGE="${IMAGE:-p2rank:local}"
EXPECTED_VERSION="${EXPECTED_VERSION:-2.5.1}"
MIN_JAVA="${MIN_JAVA:-17}"

pass=0
fail=0
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

if [ -t 1 ]; then
    red=$'\e[31m'; green=$'\e[32m'; dim=$'\e[2m'; reset=$'\e[0m'
else
    red=''; green=''; dim=''; reset=''
fi

ok()   { pass=$((pass + 1)); printf '%s  ok  %s%s\n' "$green" "$1" "$reset"; }
no()   { fail=$((fail + 1)); printf '%s NOT OK  %s%s\n' "$red" "$1" "$reset"; [ $# -gt 1 ] && printf '%s        %s%s\n' "$dim" "$2" "$reset"; }

# assert_contains <name> <haystack> <needle>
assert_contains() {
    case "$2" in
        *"$3"*) ok "$1" ;;
        *)      no "$1" "expected to contain '$3', got: $(printf '%.200s' "$2")" ;;
    esac
}

# assert_eq <name> <actual> <expected>
assert_eq() {
    if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$3', got '$2'"; fi
}

printf 'Testing image: %s\n\n' "$IMAGE"

# --- the tool is installed and runnable -----------------------------------
assert_contains "prank is on PATH" \
    "$(docker run --rm "$IMAGE" bash -lc 'command -v prank')" "/opt/p2rank/prank"

java_major="$(docker run --rm "$IMAGE" bash -lc 'java -version 2>&1 | head -1 | sed -E "s/.*\"([0-9]+).*/\1/"')"
if [ "${java_major:-0}" -ge "$MIN_JAVA" ] 2>/dev/null; then
    ok "java $java_major is >= $MIN_JAVA"
else
    no "java >= $MIN_JAVA" "got '$java_major'"
fi

assert_contains "reports P2Rank $EXPECTED_VERSION" \
    "$(docker run --rm "$IMAGE" 2>&1 | head -5)" "P2Rank $EXPECTED_VERSION"

# --- it actually predicts --------------------------------------------------
out="$(docker run --rm "$IMAGE" bash -lc \
    'prank predict -f /opt/p2rank/test_data/2W83.pdb -o /tmp/o >/dev/null 2>&1; cat /tmp/o/2W83.pdb_predictions.csv')"
assert_contains "prediction writes a CSV header" "$out" "name     ,  rank,   score"

pockets="$(printf '%s\n' "$out" | grep -c '^pocket')"
if [ "$pockets" -ge 1 ]; then ok "prediction finds pockets ($pockets)"; else no "prediction finds pockets" "found $pockets"; fi

top_score="$(printf '%s\n' "$out" | awk -F, '/^pocket1 /{gsub(/ /,"",$3); print $3}')"
if awk "BEGIN{exit !($top_score > 5)}" 2>/dev/null; then
    ok "top pocket score is plausible ($top_score)"
else
    no "top pocket score is plausible" "got '$top_score', expected > 5"
fi

# --- it works for whoever runs it -----------------------------------------
# Workflow engines pass --user; the image must not depend on being root.
assert_contains "runs as an arbitrary uid (1234)" \
    "$(docker run --rm -u 1234:1234 "$IMAGE" bash -lc \
        'prank predict -f /opt/p2rank/test_data/1fbl.pdb -o /tmp/o 2>&1 | tail -2')" "Finished successfully"

assert_contains "runs as root" \
    "$(docker run --rm -u 0:0 "$IMAGE" bash -lc \
        'prank predict -f /opt/p2rank/test_data/1fbl.pdb -o /tmp/o 2>&1 | tail -2')" "Finished successfully"

# Regression: a root-owned BioJava cache baked into the image made every
# non-root run spew download errors and refetch ligand definitions.
errors="$(docker run --rm -u 1234:1234 "$IMAGE" bash -lc \
    'prank predict -f /opt/p2rank/test_data/2W83.pdb -o /tmp/o 2>&1' | grep -c 'Could not download')"
assert_eq "no chem-comp cache errors as non-root" "$errors" "0"

# --- bind mounts round-trip correctly --------------------------------------
# Uses --user, as the README instructs: the image defaults to uid 1000, which
# cannot write a host directory owned by any other uid.
cp_out="$(docker run --rm -u "$(id -u):$(id -g)" -v "$workdir:/data" "$IMAGE" bash -lc \
    'cp /opt/p2rank/test_data/2W83.pdb /data/ && prank predict -f /data/2W83.pdb -o /data/out 2>&1 | tail -1')"
assert_contains "predicts into a bind mount" "$cp_out" "Finished successfully"

if [ -s "$workdir/out/2W83.pdb_predictions.csv" ]; then
    owner="$(stat -c %u "$workdir/out/2W83.pdb_predictions.csv")"
    assert_eq "output is owned by the invoking uid" "$owner" "$(id -u)"
else
    no "output is owned by the invoking uid" "no output file produced"
fi

# --- it does not need the network ------------------------------------------
# Predictions must be reproducible on an air-gapped cluster node.
online="$(docker run --rm "$IMAGE" bash -lc \
    'prank predict -f /opt/p2rank/test_data/2W83.pdb -o /tmp/o >/dev/null 2>&1; md5sum < /tmp/o/2W83.pdb_predictions.csv')"
offline="$(docker run --rm --network none "$IMAGE" bash -lc \
    'prank predict -f /opt/p2rank/test_data/2W83.pdb -o /tmp/o >/dev/null 2>&1; md5sum < /tmp/o/2W83.pdb_predictions.csv')"
assert_eq "offline results match online results" "$offline" "$online"

# --- heap sizing ------------------------------------------------------------
# Upstream's launcher pins -Xmx2048m; this image swaps in MaxRAMPercentage so
# the heap tracks the container limit and JAVA_OPTS can still override it.
heap="$(docker run --rm -m 2g -e JAVA_OPTS="-XX:+PrintFlagsFinal" "$IMAGE" 2>&1 | awk '/MaxHeapSize/{print $4; exit}')"
if [ -n "$heap" ] && [ "$heap" -gt 1000000000 ] && [ "$heap" -lt 2147483648 ]; then
    ok "heap follows the container limit ($((heap / 1024 / 1024)) MB under -m 2g)"
else
    no "heap follows the container limit" "MaxHeapSize=$heap under -m 2g"
fi

heap="$(docker run --rm -m 2g -e JAVA_OPTS="-Xmx777m -XX:+PrintFlagsFinal" "$IMAGE" 2>&1 | awk '/MaxHeapSize/{print $4; exit}')"
# The JVM rounds the heap up to its allocation granularity, so allow a little slack.
if [ -n "$heap" ] && [ "$heap" -ge 814743552 ] && [ "$heap" -lt 838860800 ]; then
    ok "JAVA_OPTS can override the heap ($((heap / 1024 / 1024)) MB for -Xmx777m)"
else
    no "JAVA_OPTS can override the heap" "MaxHeapSize=$heap, expected ~814743552"
fi

# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
