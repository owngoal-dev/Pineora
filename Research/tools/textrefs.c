// textrefs: scan __TEXT,__text of a thin 64-bit Mach-O for ADRP+ADD / ADRP+LDR pairs
// and print "addr -> target kind" lines. Used to locate code that references cfstrings.
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <mach-o/loader.h>

static int64_t sext64(uint64_t v, int bits) {
    uint64_t m = 1ULL << (bits - 1);
    return (int64_t)((v ^ m) - m);
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: textrefs FILE\n"); return 2; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("open"); return 1; }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc((size_t)sz);
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) { fprintf(stderr, "short read\n"); return 1; }

    struct mach_header_64 *mh = (void *)buf;
    if (mh->magic != MH_MAGIC_64) { fprintf(stderr, "not a thin 64-bit Mach-O\n"); return 1; }
    uint32_t off = sizeof(*mh);
    uint32_t text_off = 0, text_addr = 0, text_size = 0;
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        struct load_command *lc = (void *)(buf + off);
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (void *)lc;
            if (strcmp(seg->segname, "__TEXT") == 0) {
                struct section_64 *sec = (void *)(seg + 1);
                for (uint32_t s = 0; s < seg->nsects; s++) {
                    if (strcmp(sec[s].sectname, "__text") == 0) {
                        text_off = sec[s].offset;
                        text_addr = (uint32_t)sec[s].addr;
                        text_size = (uint32_t)sec[s].size;
                    }
                }
            }
        }
        off += lc->cmdsize;
    }
    if (!text_size) { fprintf(stderr, "no __text\n"); return 1; }
    fprintf(stderr, "# text addr=0x%x off=0x%x size=0x%x\n", text_addr, text_off, text_size);

    uint32_t *n = (uint32_t *)(buf + text_off);
    long count = text_size / 4;
    for (long i = 0; i + 1 < count; i++) {
        uint32_t w = n[i];
        if ((w & 0x9F000000u) != 0x90000000u) continue;
        uint32_t rd = w & 0x1f;
        uint64_t immhi = (w >> 5) & 0x7ffff;
        uint64_t immlo = (w >> 29) & 3;
        int64_t imm = sext64((immhi << 2) | immlo, 21) << 12;
        uint64_t pc = (uint64_t)text_addr + (uint64_t)i * 4;
        uint64_t page = (pc & ~0xfffULL) + (uint64_t)imm;
        for (int k = 1; k <= 2 && i + k < count; k++) {
            uint32_t w2 = n[i + k];
            if (((w2 >> 5) & 0x1f) != rd) continue;
            if ((w2 & 0x7F800000u) == 0x11000000u) {          /* add */
                uint64_t imm12 = (w2 >> 10) & 0xfff;
                if ((w2 >> 22) & 3) imm12 <<= 12;
                printf("0x%llx 0x%llx add\n", (unsigned long long)pc,
                       (unsigned long long)(page + imm12));
                break;
            }
            if ((w2 & 0xFFC00000u) == 0xF9400000u) {          /* ldr x, [x, #imm] */
                uint64_t imm12 = (uint64_t)((w2 >> 10) & 0xfff) * 8;
                printf("0x%llx 0x%llx ldr\n", (unsigned long long)pc,
                       (unsigned long long)(page + imm12));
                break;
            }
        }
    }
    return 0;
}
