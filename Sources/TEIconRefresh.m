#import "TEIconRefresh.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>

static BOOL TERefreshHasMethod(id target, SEL selector, const char *encoding) {
    Method method = target ? class_getInstanceMethod(object_getClass(target), selector) : NULL;
    return method && strcmp(method_getTypeEncoding(method), encoding) == 0;
}

BOOL TERefreshIconImageView(id iconView) {
    SEL getter = NSSelectorFromString(@"_iconImageView");
    SEL clear = NSSelectorFromString(@"clearCachedImages");
    SEL update = NSSelectorFromString(@"updateImageAnimated:");
    if (!TERefreshHasMethod(iconView, getter, "@16@0:8")) return NO;
    @try {
        id imageView = ((id (*)(id, SEL))objc_msgSend)(iconView, getter);
        if (!TERefreshHasMethod(imageView, clear, "v16@0:8") ||
            !TERefreshHasMethod(imageView, update, "v20@0:8B16")) return NO;
        // Rebinding the same icon through SBIconView's container updater can be a no-op.
        // Invalidate the image view itself, then fetch through the newly reloaded cache.
        ((void (*)(id, SEL))objc_msgSend)(imageView, clear);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(imageView, update, NO);
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}
