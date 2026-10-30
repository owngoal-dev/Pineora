// stubsel: print every Objective-C "selector stub" (__TEXT,__objc_stubs) of a thin
// 64-bit Mach-O with the selector name it passes, so a "bl 0xADDR" in disassembly
// can be resolved to the message it sends.
// Assumes file offset == virtual address for the sections involved (true here) and
// DYLD_CHAINED_PTR_64 fixups with image base 0.
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <mach-o/loader.h>

int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("open"); return 1; }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc((size_t)sz);
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) { fprintf(stderr, "short read\n"); return 1; }

    struct mach_header_64 *mh = (void *)buf;
    uint32_t off = sizeof(*mh);
    uint32_t stubs_addr = 0, stubs_size = 0, stubs_off = 0;
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        struct load_command *lc = (void *)(buf + off);
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (void *)lc;
            struct section_64 *sec = (void *)(seg + 1);
            for (uint32_t s = 0; s < seg->nsects; s++) {
                if (strcmp(sec[s].segname, "__TEXT") == 0 &&
                    strcmp(sec[s].sectname, "__objc_stubs") == 0) {
                    stubs_addr = (uint32_t)sec[s].addr;
                    stubs_size = (uint32_t)sec[s].size;
                    stubs_off = sec[s].offset;
                }
            }
        }
        off += lc->cmdsize;
    }
    if (!stubs_size) { fprintf(stderr, "no __objc_stubs\n"); return 1; }

    for (uint32_t a = stubs_addr; a + 16 <= stubs_addr + stubs_size; a += 16) {
        uint32_t *w = (uint32_t *)(buf + stubs_off + (a - stubs_addr));
        /* adrp x1, page ; ldr x1, [x1, #imm] */
        if ((w[0] & 0x9F00001Fu) != 0x90000001u) continue;
        uint64_t immhi = (w[0] >> 5) & 0x7ffff, immlo = (w[0] >> 29) & 3;
        int64_t imm = ((int64_t)((immhi << 2) | immlo) << 43) >> 43; /* sign extend 21 */
        uint64_t page = (a & ~0xfffULL) + ((uint64_t)imm << 12);
        if ((w[1] & 0xFFC00000u) != 0xF9400000u || (w[1] & 0x1F) != 1 || ((w[1] >> 5) & 0x1F) != 1) continue;
        uint64_t got = page + (uint64_t)((w[1] >> 10) & 0xfff) * 8;
        if (got + 8 > (uint64_t)sz) continue;
        uint64_t v = *(uint64_t *)(buf + got);
        if (v >> 63) { printf("0x%x BIND 0x%llx\n", a, (unsigned long long)v); continue; }
        uint64_t selref = got;                      /* stub loads the selref slot itself */
        if (selref + 8 > (uint64_t)sz) { printf("0x%x ?selref 0x%llx\n", a, (unsigned long long)selref); continue; }
        uint64_t sv = v;
        uint64_t name = (sv & 0xFFFFFFFFFULL) | (((sv >> 36) & 255ULL) << 56);
        if (name >= (uint64_t)sz) { printf("0x%x ?name 0x%llx\n", a, (unsigned long long)name); continue; }
        char *s = (char *)(buf + name);
        if (strnlen(s, 256) == 256) { printf("0x%x ?str 0x%llx\n", a, (unsigned long long)name); continue; }
        printf("0x%x %s\n", a, s);
    }
    return 0;
}
