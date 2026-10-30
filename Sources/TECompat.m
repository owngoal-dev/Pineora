#import "TECompat.h"
#import <objc/runtime.h>
#import <substrate.h>

NSString *TEBootstrapFilePath(NSString *path) {
    if (path.length == 0 || ![path hasPrefix:@"/"]) {
        return nil;
    }
    return ApelinBootstrapPath(path);
}

static Class TEClassNamed(NSString *name) {
    if (name.length == 0) {
        return Nil;
    }
    return objc_getClass(name.UTF8String);
}

BOOL TEHasInstanceMethod(NSString *className, NSString *selectorName) {
    Class cls = TEClassNamed(className);
    if (cls == Nil) {
        return NO;
    }
    return class_getInstanceMethod(cls, NSSelectorFromString(selectorName)) != NULL;
}

BOOL TEHasClassMethod(NSString *className, NSString *selectorName) {
    Class cls = TEClassNamed(className);
    if (cls == Nil) {
        return NO;
    }
    return class_getClassMethod(cls, NSSelectorFromString(selectorName)) != NULL;
}

BOOL TEInstallInstanceHook(NSString *className, NSString *selectorName,
                           IMP replacement, IMP *original) {
    Class cls = TEClassNamed(className);
    if (cls == Nil) {
        return NO;
    }
    SEL selector = NSSelectorFromString(selectorName);
    if (class_getInstanceMethod(cls, selector) == NULL) {
        return NO;
    }
    // MSHookMessageEx 与其它插件的钩子串联；原实现必然存在，替身也为必填项。
    static IMP sink;
    IMP *out = original != NULL ? original : &sink;
    MSHookMessageEx(cls, selector, replacement, out);
    return *out != NULL;
}

BOOL TEInstallClassHook(NSString *className, NSString *selectorName,
                        IMP replacement, IMP *original) {
    Class cls = TEClassNamed(className);
    if (cls == Nil) {
        return NO;
    }
    SEL selector = NSSelectorFromString(selectorName);
    if (class_getClassMethod(cls, selector) == NULL) {
        return NO;
    }
    static IMP sink;
    IMP *out = original != NULL ? original : &sink;
    MSHookMessageEx(object_getClass(cls), selector, replacement, out);
    return *out != NULL;
}

id TECallObject(id target, NSString *selectorName) {
    if (target == nil || selectorName.length == 0) {
        return nil;
    }
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) {
        return nil;
    }
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        return [target performSelector:selector];
#pragma clang diagnostic pop
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

id TECallClassObject(NSString *className, NSString *selectorName) {
    Class cls = TEClassNamed(className);
    if (cls == Nil) {
        return nil;
    }
    return TECallObject((id)cls, selectorName);
}

NSString *TEStringForSelectors(id object, NSArray<NSString *> *selectorNames) {
    for (NSString *selectorName in selectorNames) {
        id value = TECallObject(object, selectorName);
        if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
            return (NSString *)value;
        }
    }
    return nil;
}
