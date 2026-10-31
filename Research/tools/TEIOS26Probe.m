// Read-only runtime metadata probe; no SpringBoard injection or UI actions.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <ptrauth.h>

// A minimal analysis-only Mach-O containing this image's mapped __TEXT.
// It is never signed, linked, loaded, or shipped. Addresses are unslid VM addresses.
static BOOL Snapshot(void) {
    IMP imp = class_getMethodImplementation(objc_getClass("SBIconImageView"), NSSelectorFromString(@"shouldDisplayImageLayer"));
    Dl_info info = {0};
    dladdr(ptrauth_strip((void *)imp, ptrauth_key_function_pointer), &info);
    const struct mach_header_64 *header = info.dli_fbase;
    if (!header || header->magic != MH_MAGIC_64) return NO;
    const struct load_command *command = (const void *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const void *)((const char *)command + command->cmdsize)) {
        if (command->cmd != LC_SEGMENT_64) continue;
        const struct segment_command_64 *segment = (const void *)command;
        if (strcmp(segment->segname, "__TEXT") != 0 || segment->vmsize > 64 * 1024 * 1024) continue;
        struct mach_header_64 h = {.magic=MH_MAGIC_64, .cputype=CPU_TYPE_ARM64, .cpusubtype=CPU_SUBTYPE_ARM64E, .filetype=MH_DYLIB, .ncmds=1, .sizeofcmds=sizeof(struct segment_command_64)+sizeof(struct section_64)};
        struct segment_command_64 s = {.cmd=LC_SEGMENT_64, .cmdsize=h.sizeofcmds, .vmaddr=segment->vmaddr, .vmsize=segment->vmsize, .fileoff=4096, .filesize=segment->vmsize, .maxprot=5, .initprot=5, .nsects=1};
        strcpy(s.segname, "__TEXT");
        struct section_64 section = {.addr=segment->vmaddr, .size=segment->vmsize, .offset=4096, .align=2, .flags=S_REGULAR|S_ATTR_PURE_INSTRUCTIONS|S_ATTR_SOME_INSTRUCTIONS};
        strcpy(section.segname, "__TEXT"); strcpy(section.sectname, "__text");
        NSMutableData *data = [NSMutableData dataWithLength:4096];
        memcpy(data.mutableBytes, &h, sizeof(h));
        memcpy((char *)data.mutableBytes+sizeof(h), &s, sizeof(s));
        memcpy((char *)data.mutableBytes+sizeof(h)+sizeof(s), &section, sizeof(section));
        [data appendBytes:header length:segment->vmsize];
        // Decode only the verified ARM64 adrp x1 / ldr x1 selector-stub pattern.
        NSMutableString *stubs = [NSMutableString string];
        const struct section_64 *sections = (const void *)(segment + 1);
        intptr_t slide = (intptr_t)header - (intptr_t)segment->vmaddr;
        for (uint32_t j = 0; j < segment->nsects; j++) {
            if (strcmp(sections[j].sectname, "__objc_stubs") != 0) continue;
            for (uint64_t k = 0; k + 8 <= sections[j].size; k += 32) {
                uintptr_t pc = sections[j].addr + slide + k;
                const uint32_t *words = (const void *)pc;
                if ((words[0] & 0x9f00001f) != 0x90000001 || (words[1] & 0xffc003ff) != 0xf9400021) continue;
                int64_t imm = ((words[0] >> 5) & 0x7ffff) * 4 | ((words[0] >> 29) & 3);
                if (imm & (1 << 20)) imm -= 1 << 21;
                uintptr_t ref = (pc & ~(uintptr_t)4095) + imm * 4096 + ((words[1] >> 10) & 4095) * 8;
                SEL selector = *(SEL *)ref;
                [stubs appendFormat:@"0x%llx %s\n", sections[j].addr + k, sel_getName(selector)];
            }
        }
        [stubs writeToFile:@"build/ios26-stubs.txt" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        BOOL written = [data writeToFile:@"build/SpringBoardHome-text.macho" atomically:YES];
        printf("SNAPSHOT %d vmaddr=0x%llx size=0x%llx\n", written, segment->vmaddr, segment->vmsize);
        return written;
    }
    return NO;
}

static void Dump(Class cls) {
    printf("\nCLASS %s super=%s image=%s\n", class_getName(cls), class_getName(class_getSuperclass(cls)), class_getImageName(cls));
    for (int meta = 0; meta < 2; meta++) {
        unsigned count = 0;
        Method *methods = class_copyMethodList(meta ? object_getClass(cls) : cls, &count);
        for (unsigned i = 0; i < count; i++) {
            Method m = methods[i];
            const char *name = sel_getName(method_getName(m));
            NSString *s = @(name).lowercaseString;
            if ([s containsString:@"image"] || [s containsString:@"icon"] || [s containsString:@"cache"] || [s containsString:@"variant"] || [s containsString:@"style"] || [s containsString:@"appearance"] || [s containsString:@"render"]) {
                Dl_info info = {0};
                const void *address = ptrauth_strip((void *)method_getImplementation(m), ptrauth_key_function_pointer);
                dladdr(address, &info);
                printf("%c %s %s offset=0x%llx\n", meta ? '+' : '-', name, method_getTypeEncoding(m), (unsigned long long)((uintptr_t)address - (uintptr_t)info.dli_fbase));
            }
        }
        free(methods);
    }
    unsigned count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    for (unsigned i = 0; i < count; i++) printf("IVAR %s %s\n", ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]));
    free(ivars);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        printf("OS %s\n", NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String);
        void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome", RTLD_LAZY | RTLD_GLOBAL);
        if (!handle) { fprintf(stderr, "%s\n", dlerror()); return 1; }
        if (argc == 2 && strcmp(argv[1], "--snapshot") == 0) return Snapshot() ? 0 : 1;
        if (argc > 1) {
            for (int i = 1; i < argc; i++) { Class cls = objc_getClass(argv[i]); if (cls) Dump(cls); else printf("MISSING %s\n", argv[i]); }
        } else {
            for (NSString *name in @[@"SBHIconImageCache", @"SBFolderIconImageCache", @"SBIconImageView", @"SBIconView", @"SBIcon", @"SBApplicationIcon", @"SBHIconManager", @"SBHClockApplicationIconImageView"]) {
                Class cls = objc_getClass(name.UTF8String);
                if (cls) Dump(cls); else printf("MISSING %s\n", name.UTF8String);
            }
            unsigned count = 0;
            Class *classes = objc_copyClassList(&count);
            for (unsigned i = 0; i < count; i++) {
                NSString *name = @(class_getName(classes[i]));
                if ([name containsString:@"Icon"] && ([name containsString:@"Image"] || [name containsString:@"Render"] || [name containsString:@"Mini"] || [name containsString:@"Folder"] || [name containsString:@"Library"])) printf("CANDIDATE %s\n", name.UTF8String);
            }
            free(classes);
        }
    }
    return 0;
}
