/*
 * standalone_main.c — a tiny run-once driver so the OSS-Fuzz harness
 * (LLVMFuzzerTestOneInput) can be built WITHOUT the libFuzzer runtime, for
 * deterministic crash reproduction: it reads one input file (or stdin) and
 * feeds the bytes to LLVMFuzzerTestOneInput exactly once.
 *
 * The org base exports STANDALONE_FUZZ_MAIN; this file is the in-repo fallback
 * used by mayhem/build.sh so the build never depends on a path outside the repo.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int main(int argc, char **argv) {
    FILE *f = stdin;
    if (argc > 1) {
        f = fopen(argv[1], "rb");
        if (!f) {
            perror(argv[1]);
            return 1;
        }
    }

    size_t cap = 1 << 16, len = 0;
    uint8_t *buf = (uint8_t *)malloc(cap);
    if (!buf) return 1;
    for (;;) {
        if (len == cap) {
            cap *= 2;
            uint8_t *nb = (uint8_t *)realloc(buf, cap);
            if (!nb) { free(buf); if (f != stdin) fclose(f); return 1; }
            buf = nb;
        }
        size_t n = fread(buf + len, 1, cap - len, f);
        len += n;
        if (n == 0) break;
    }
    if (f != stdin) fclose(f);

    LLVMFuzzerTestOneInput(buf, len);

    free(buf);
    return 0;
}
