#!/usr/bin/env bash
#
# numactl/mayhem/build.sh — build numactl's OSS-Fuzz harness as a sanitized libFuzzer target
# (+ a standalone reproducer), and build libnuma ITSELF instrumented so the fuzzed parser code
# (not just the harness) is covered.
#
# Fuzzed surface — fuzz/fuzz_parse_str.c (upstream OSS-Fuzz harness):
#   The whole input is taken as a NUL-terminated C string and fed to numactl's mask-string parsers:
#     numa_parse_nodestring(str)  — parse a NODE mask string ("0", "0-3", "0,2,4", "all", "!0", "+1")
#     numa_parse_cpustring(str)   — parse a CPU  mask string (same grammar); on success the resulting
#                                   bitmask is passed to numa_node_to_cpus_v2(0, mask).
#   Inputs are mask DESCRIPTION strings, NOT binary structs.
#
# Build contract comes from the org base ENV (CC/CXX/SANITIZER_FLAGS/LIB_FUZZING_ENGINE/SRC/
# STANDALONE_FUZZ_MAIN). $OUT defaults to /mayhem (the deploy location).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) for SANITIZER_FLAGS so an explicit empty --build-arg builds with NO sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${OUT:=/mayhem}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE OUT MAYHEM_JOBS

# $SRC is where the full repo was copied (the org base exports it; default to /mayhem).
SRC="${SRC:-/mayhem}"
cd "$SRC"

HARNESS_DIR="$SRC/mayhem/harnesses"

# The upstream harness (fuzz/fuzz_parse_str.c) calls numa_node_to_cpus_v2(), an EXPORTED libnuma
# symbol (versioned libnuma_1.2 in libnuma.c) that the public numa.h does not declare, and uses
# memcpy without #include <string.h>. Older clangs (what OSS-Fuzz used) made these a warning; clang
# >=16 makes implicit declarations a hard error. The implicit `int (...)` prototype matches the real
# signature, so the call links and runs correctly — demote it back to a warning for the HARNESS ONLY
# (libnuma itself is built with the unmodified flags above).
HARNESS_RELAX="-Wno-implicit-function-declaration -Wno-error=implicit-function-declaration"

# ── 1) Build libnuma WITH sanitizers via the autotools chain (the fuzzed parser is instrumented) ──
# Sanitizer flags flow into the library objects through CFLAGS. We only need the static archive.
./autogen.sh
./configure CC="$CC" CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS"
make -j"$MAYHEM_JOBS" libnuma.la

LIBNUMA="$SRC/.libs/libnuma.a"
[ -f "$LIBNUMA" ] || { echo "ERROR: $LIBNUMA not built" >&2; exit 1; }

# ── 2) Standalone run-once driver (no libFuzzer runtime) ───────────────────────────────────────
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$HARNESS_DIR/standalone_main.c" -o "$SRC/standalone_main.o"

# ── 3) Build the harness twice: libFuzzer (-> $OUT/fuzz_parse_str) + standalone reproducer ───────
# Link with CXX (libFuzzer / Centipede runtimes are C++). -I. so the harness finds numa.h.
# `-x c <harness> -x none` scopes the C language only to the harness source; the static archive
# that follows must NOT be parsed as a C source (-x none restores extension-based detection).
for harness in fuzz_parse_str; do
  # libFuzzer target
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $HARNESS_RELAX -I"$SRC" \
      -x c "$SRC/fuzz/$harness.c" -x none $LIB_FUZZING_ENGINE "$LIBNUMA" \
      -o "$OUT/$harness"

  # standalone reproducer (no libFuzzer runtime)
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $HARNESS_RELAX -I"$SRC" \
      -x c "$SRC/fuzz/$harness.c" -x none "$SRC/standalone_main.o" "$LIBNUMA" \
      -o "$OUT/$harness-standalone"

  echo "built $harness (+ standalone)"
done

echo "build.sh complete:"
ls -la "$OUT/fuzz_parse_str" "$OUT/fuzz_parse_str-standalone" 2>&1 || true
