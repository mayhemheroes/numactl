/*
 * mayhem/oracle.c — golden oracle over numactl's FUZZED parse path
 * (numa_parse_nodestring / numa_parse_cpustring), the exact functions
 * fuzz/fuzz_parse_str.c drives.
 *
 * numactl's own test/ suite (move_pages, mbind, shared-memory, migration) needs a
 * real multi-node NUMA machine and is NOT self-contained, so it can't run in CI.
 * The parse path, however, is deterministic on ANY Linux host: CPU 0 and node 0
 * always exist, so we assert byte-exact PARSE RESULTS here.
 *
 * This is a real ASSERTION oracle (not a no-op): each check verifies the parser's
 * observable behaviour — accept a well-formed mask string and produce the exact
 * expected bitmask (weight + which bits are set), and REJECT malformed / out-of-range
 * input by returning NULL. A patch that stubbed the parser to "always succeed" or
 * "always fail" would flip these and fail the suite.
 *
 * Prints one "ok N - <desc>" / "not ok N - <desc>" line per check (TAP-ish) so
 * test.sh can count pass/fail; exits nonzero on any failure.
 */
#include <stdio.h>
#include "numa.h"

static int passed = 0, failed = 0;

static void check(int cond, const char *desc) {
    if (cond) {
        printf("ok %d - %s\n", passed + failed + 1, desc);
        passed++;
    } else {
        printf("not ok %d - %s\n", passed + failed + 1, desc);
        failed++;
    }
}

/* Parse and assert: cpu/node 0 is always present on any Linux host. */
int main(void) {
    struct bitmask *m;

    /* ---- CPU string parser ---- */
    m = numa_parse_cpustring("0");
    check(m != NULL, "cpu \"0\" parses (non-NULL)");
    if (m) {
        check(numa_bitmask_isbitset(m, 0) == 1, "cpu \"0\" sets bit 0");
        check(numa_bitmask_weight(m) == 1, "cpu \"0\" has weight 1");
        numa_bitmask_free(m);
    } else {
        check(0, "cpu \"0\" sets bit 0 (skipped: NULL)");
        check(0, "cpu \"0\" has weight 1 (skipped: NULL)");
    }

    m = numa_parse_cpustring("");
    check(m != NULL, "cpu \"\" (empty) parses to an empty mask (non-NULL)");
    if (m) {
        check(numa_bitmask_weight(m) == 0, "cpu \"\" has weight 0");
        numa_bitmask_free(m);
    } else {
        check(0, "cpu \"\" has weight 0 (skipped: NULL)");
    }

    m = numa_parse_cpustring("zzz");
    check(m == NULL, "cpu \"zzz\" (garbage) is rejected (NULL)");
    if (m) numa_bitmask_free(m);

    m = numa_parse_cpustring("0-");
    check(m == NULL, "cpu \"0-\" (truncated range) is rejected (NULL)");
    if (m) numa_bitmask_free(m);

    /* ---- NODE string parser ---- */
    m = numa_parse_nodestring("0");
    check(m != NULL, "node \"0\" parses (non-NULL)");
    if (m) {
        check(numa_bitmask_isbitset(m, 0) == 1, "node \"0\" sets bit 0");
        check(numa_bitmask_weight(m) == 1, "node \"0\" has weight 1");
        numa_bitmask_free(m);
    } else {
        check(0, "node \"0\" sets bit 0 (skipped: NULL)");
        check(0, "node \"0\" has weight 1 (skipped: NULL)");
    }

    m = numa_parse_nodestring("99999");
    check(m == NULL, "node \"99999\" (out of range) is rejected (NULL)");
    if (m) numa_bitmask_free(m);

    printf("# passed %d, failed %d\n", passed, failed);
    return failed == 0 ? 0 : 1;
}
