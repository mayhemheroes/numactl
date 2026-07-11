#!/usr/bin/env bash
#
# numactl/mayhem/test.sh — ASSERTION oracle over the FUZZED parse path. Compiles and runs
# mayhem/oracle.c, which links the just-built libnuma and asserts byte-exact results from
# numa_parse_nodestring / numa_parse_cpustring (the functions fuzz/fuzz_parse_str.c drives).
#
# WHY a custom oracle (not numactl's own test/ suite): numactl's test/ programs (move_pages,
# mbind_mig_pages, migrate_pages, tshared, ...) require a real multi-node NUMA machine and root /
# shared-memory access; they are NOT self-contained and cannot pass in CI. The PARSE path, in
# contrast, is deterministic on any Linux host (CPU 0 and node 0 always exist), so we assert it
# directly. This is a true oracle: it verifies accepted masks yield the exact expected bitmask and
# malformed/out-of-range strings are rejected (NULL) — a stubbed "always ok"/"always fail" parser
# would fail it. Additive: lives entirely under mayhem/.
#
# Emits a CTRF (ctrf.io) one-line summary; exit 0 iff no check failed.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

SRC="${SRC:-/mayhem}"
cd "$SRC"

: "${CC:=clang}"
LIBNUMA="$SRC/.libs/libnuma.a"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if [ ! -f "$LIBNUMA" ]; then
  echo "missing $LIBNUMA — run mayhem/build.sh first" >&2
  emit_ctrf "numactl-parse-oracle" 0 1 0; exit 2
fi

# build.sh builds libnuma.a WITH $SANITIZER_FLAGS, so the oracle must link the SAME flags to pull in
# the ASan/UBSan runtime (otherwise the instrumented archive leaves __asan_*/__ubsan_* undefined).
# This is still a functional assertion oracle — the sanitizers are just along for the ride. detect_leaks
# is disabled at run time so libnuma's one-time init allocations don't trip a leak failure.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
ORACLE="$SRC/mayhem-oracle"
$CC $SANITIZER_FLAGS -I"$SRC" "$SRC/mayhem/oracle.c" "$LIBNUMA" -o "$ORACLE" \
  || { echo "failed to compile mayhem/oracle.c" >&2; emit_ctrf "numactl-parse-oracle" 0 1 0; exit 2; }

echo "=== running parse-path oracle ==="
out="$(ASAN_OPTIONS=detect_leaks=0 "$ORACLE" 2>&1)"; rc=$?
echo "$out"

PASSED=$(printf '%s\n' "$out" | grep -c '^ok ')
FAILED=$(printf '%s\n' "$out" | grep -c '^not ok ')
: "${PASSED:=0}" "${FAILED:=0}"

# Cross-check the binary's exit code: any nonzero rc with no parsed failures is itself a failure.
if [ "$rc" -ne 0 ] && [ "$FAILED" -eq 0 ]; then FAILED=1; fi
if [ "$(( PASSED + FAILED ))" -eq 0 ]; then
  echo "oracle produced no TAP lines" >&2
  emit_ctrf "numactl-parse-oracle" 0 1 0; exit 1
fi

emit_ctrf "numactl-parse-oracle" "$PASSED" "$FAILED"
