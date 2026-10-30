// 只读反射探针：独立进程加载系统框架，打印扩展 Hook 的真实签名。
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

static void Dump(Class cls) {
    if (!cls) return;
    printf("\nCLASS %s super=%s\n", class_getName(cls), class_getName(class_getSuperclass(cls)));
    for (int meta = 0; meta <= 1; meta++) {
        unsigned count = 0;
        Method *methods = class_copyMethodList(meta ? object_getClass(cls) : cls, &count);
        for (unsigned i = 0; i < count; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            BOOL show = NO;
            for (NSString *word in @[@"image", @"badge", @"layout", @"date", @"time", @"calendar", @"icon", @"mask", @"color", @"font", @"background"]) {
                if ([name rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound) show = YES;
            }
            if (show) printf("%c%s %s\n", meta ? '+' : '-', name.UTF8String, method_getTypeEncoding(methods[i]));
        }
        free(methods);
    }
    unsigned count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    for (unsigned i = 0; i < count; i++) printf("ivar %s %s\n", ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]));
    free(ivars);
}

int main(void) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome", RTLD_LAZY | RTLD_GLOBAL)) {
            fprintf(stderr, "%s\n", dlerror()); return 1;
        }
        for (NSString *name in @[@"SBHIconImageCache", @"SBIconImageView", @"SBLiveIconImageView", @"SBIconBadgeView", @"SBIconBadgeImage", @"SBHIconBadgeVisualStyle", @"SBIconView", @"SBHIconManager"]) Dump(objc_getClass(name.UTF8String));
        int count = objc_getClassList(NULL, 0);
        Class __unsafe_unretained *classes = (Class __unsafe_unretained *)calloc((size_t)count, sizeof(Class));
        int actual = objc_getClassList(classes, count);
        for (int i = 0; i < MIN(count, actual); i++) {
            NSString *name = @(class_getName(classes[i]));
            if (([name containsString:@"Clock"] || [name containsString:@"Calendar"]) &&
                [name hasPrefix:@"SB"] && ([name containsString:@"Icon"] || [name containsString:@"Image"])) Dump(classes[i]);
        }
        free(classes);
        Class badge = objc_getClass("SBIconBadgeView");
        Class background = objc_getClass("SBDarkeningImageView");
        printf("\nCONTRACT badge background subclassUIImageView=%d\n", [background isSubclassOfClass:UIImageView.class]);
        for (NSString *name in @[@"_createImageForText:font:highlighted:", @"_checkoutImageForText:font:highlighted:"]) {
            SEL selector = NSSelectorFromString(name);
            if (![badge respondsToSelector:selector]) continue;
            id result = ((id (*)(id, SEL, id, id, BOOL))objc_msgSend)(badge, selector, @"12", [UIFont systemFontOfSize:14], NO);
            printf("CONTRACT %s resultClass=%s isUIImage=%d\n", name.UTF8String, result ? class_getName([result class]) : "nil", [result isKindOfClass:UIImage.class]);
        }
    }
    return 0;
}
