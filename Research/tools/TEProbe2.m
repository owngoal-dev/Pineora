// 离线探针：找出谁能给出一个 SBHIconImageCache 实例（用于刷新时清缓存）。
// 编译与运行（项目根）：
//   clang -fobjc-arc -arch arm64e -framework Foundation -o "$TMPDIR/teprobe2" Research/tools/TEProbe2.m \
//     && ldid -S "$TMPDIR/teprobe2" && "$TMPDIR/teprobe2"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static void DumpProperties(Class cls, NSUInteger limit) {
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &count);
    for (unsigned int index = 0; index < count && index < limit; index++) {
        const char *name = property_getName(properties[index]);
        printf("    prop %s\n", name);
    }
    free(properties);
}

static void DumpClassMethodsMatching(Class cls, NSString *keyword) {
    Class meta = object_getClass(cls);
    unsigned int count = 0;
    Method *methods = class_copyMethodList(meta, &count);
    for (unsigned int index = 0; index < count; index++) {
        NSString *name = NSStringFromSelector(method_getName(methods[index]));
        if ([name rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
            printf("    +%s\n", name.UTF8String);
        }
    }
    free(methods);
}

static void DumpInstanceMethodsMatching(Class cls, NSString *keyword) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int index = 0; index < count; index++) {
        NSString *name = NSStringFromSelector(method_getName(methods[index]));
        if ([name rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
            printf("    -%s\n", name.UTF8String);
        }
    }
    free(methods);
}

int main(void) {
    @autoreleasepool {
        void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome",
                             RTLD_LAZY | RTLD_GLOBAL);
        if (handle == NULL) {
            printf("dlopen failed: %s\n", dlerror());
            return 1;
        }
        for (NSString *className in @[@"SBHIconImageCache", @"SBHIconManager", @"SBHIconModel", @"SBIcon"]) {
            Class cls = objc_getClass(className.UTF8String);
            printf("\nclass %s: %s\n", className.UTF8String, cls != Nil ? "present" : "MISSING");
            if (cls == Nil) {
                continue;
            }
            printf("  +image/cache:\n");
            DumpClassMethodsMatching(cls, @"image");
            printf("  +shared:\n");
            DumpClassMethodsMatching(cls, @"shared");
            printf("  +cache:\n");
            DumpClassMethodsMatching(cls, @"cache");
            printf("  -iconImageCache:\n");
            DumpInstanceMethodsMatching(cls, @"iconImageCache");
            printf("  props (first 20):\n");
            DumpProperties(cls, 20);
        }
        return 0;
    }
}
