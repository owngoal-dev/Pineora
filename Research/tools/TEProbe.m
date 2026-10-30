// 离线探针：只读取 SpringBoardHome 框架，检查我们的钩子目标在这台设备/iOS 上是否存在。
// 不注入、不加载 SpringBoard，只在独立进程里 dlopen 框架并做 Objective-C 反射。
// 编译与运行（项目根）：
//   clang -fobjc-arc -arch arm64e -framework Foundation -o "$TMPDIR/teprobe" Research/tools/TEProbe.m \
//     && ldid -S "$TMPDIR/teprobe" && "$TMPDIR/teprobe"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static void PrintSelector(Class cls, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    printf("  hook-target %-28s instance=%s\n", name.UTF8String,
           class_getInstanceMethod(cls, sel) != NULL ? "yes" : "NO");
}

/// 只打印含关键字的方法，用于找出真正的取图/清缓存入口。
static void DumpMatching(Class cls, NSArray<NSString *> *keywords, NSUInteger limit) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSUInteger printed = 0;
    for (unsigned int index = 0; index < count && printed < limit; index++) {
        NSString *name = NSStringFromSelector(method_getName(methods[index]));
        for (NSString *keyword in keywords) {
            if ([name rangeOfString:keyword].location != NSNotFound) {
                printf("    -%s\n", name.UTF8String);
                printed++;
                break;
            }
        }
    }
    free(methods);
}

int main(void) {
    @autoreleasepool {
        const char *framework = "/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome";
        void *handle = dlopen(framework, RTLD_LAZY | RTLD_GLOBAL);
        if (handle == NULL) {
            printf("dlopen failed: %s\n", dlerror());
            return 1;
        }
        for (NSString *className in @[@"SBHIconImageCache", @"SBFolderIconImageCache"]) {
            Class cls = objc_getClass(className.UTF8String);
            printf("\nclass %s: %s super=%s\n", className.UTF8String, cls != Nil ? "present" : "MISSING",
                   cls != Nil ? class_getName(class_getSuperclass(cls)) : "-");
            if (cls == Nil) {
                continue;
            }
            PrintSelector(cls, @"iconImageForIcon:");
            PrintSelector(cls, @"imageForIcon:");
            PrintSelector(cls, @"imageForIcon:withOptions:");
            PrintSelector(cls, @"imageForIcon:options:");
            PrintSelector(cls, @"purgeAllCachedImages");
            PrintSelector(cls, @"purgeCache");
            printf("  methods (image/Icon/cache):\n");
            DumpMatching(cls, @[@"Image", @"Icon", @"cache"], 25);
        }
        return 0;
    }
}
