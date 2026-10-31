// Pineora: runtime-checked Home Screen icon theming.
#import <UIKit/UIKit.h>
#import <os/log.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <notify.h>
#import "TECompat.h"
#import "TEIconStore.h"
#import "TELog.h"
#import "TEExtensions.h"
#import "TEIconPipeline.h"
#import "TEFolderPreview.h"

/// SBIconController.sharedInstance -> iconManager (SpringBoard runtime object graph).
static id TEIconManager(void) {
    static id manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        manager = TECallObject(TECallClassObject(@"SBIconController", @"sharedInstance"), @"iconManager");
    });
    return manager;
}

static BOOL TECallVoidSelector(id target, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    Method method = target ? class_getInstanceMethod(object_getClass(target), selector) : NULL;
    if (!method || strcmp(method_getTypeEncoding(method), "v16@0:8") != 0) return NO;
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [target performSelector:selector];
#pragma clang diagnostic pop
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static void TEPurgeIconCaches(void) {
    id manager = TEIconManager();
    if (!manager) {
        os_log_error(TELog(), "TEPurge no iconManager");
        return;
    }
    TEInvalidateFolderPreviewIcons();
    BOOL purged = TECallVoidSelector(TECallObject(manager, @"iconImageCache"), @"purgeAllCachedImages");
    BOOL folders = TECallVoidSelector(TECallObject(manager, @"folderIconImageCache"), @"informObserversOfUpdateForAllFolderIcons");
    os_log(TELog(), "TEPurge iconCache=%d folderCache=%d", purged, folders);
}

static void TEReloadThemes(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("pineora.theme-reload", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        @autoreleasepool {
            NSInteger count = [TEIconStore.sharedStore reload];
            dispatch_async(dispatch_get_main_queue(), ^{
                TEPurgeIconCaches();
                TERefreshExtensionViews();
                os_log(TELog(), "TEReload themes=%ld", (long)count);
            });
        }
    });
}

static void TERegisterNotifications(void) {
    static BOOL registered;
    if (registered) return;
    registered = YES;
    for (NSString *notification in @[UIApplicationSignificantTimeChangeNotification,
            NSSystemTimeZoneDidChangeNotification, NSCurrentLocaleDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:notification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                [TEIconStore.sharedStore invalidateImageCache];
                TEPurgeIconCaches();
                TERefreshExtensionViews();
            }];
    }
    for (NSString *name in @[[NSString stringWithFormat:@"%s/refresh", APELIN_PACKAGE_ID],
            @"com.spark.snowboard.refresh", @"com.spark.snowboard.refreshNow",
            @"com.spark.snowboard.purgeAndUpdateAllIcons"]) {
        int token = 0;
        uint32_t status = notify_register_dispatch(name.UTF8String, &token,
            dispatch_get_main_queue(), ^(int unusedToken) { (void)unusedToken; TEReloadThemes(); });
        if (status == NOTIFY_STATUS_OK) os_log(TELog(), "TENotify registered %{public}s", name.UTF8String);
        else os_log_error(TELog(), "TENotify failed %{public}s status=%u", name.UTF8String, status);
    }
}

static void (*TEOriginalDidFinishLaunching)(id, SEL, id);
static void TEHookedDidFinishLaunching(id self, SEL cmd, id application) {
    if (TEOriginalDidFinishLaunching) TEOriginalDidFinishLaunching(self, cmd, application);
    TEReloadThemes();
    TERegisterNotifications();
    os_log(TELog(), "TEStarted %{public}s", APELIN_BUILD_ID);
}

__attribute__((constructor)) static void TweakInitialize(void) {
    // Kept public and build-specific for apelin_package_confirm_loaded.
    os_log(TELog(), "ApelinLoaded %{public}s in %{public}s", APELIN_BUILD_ID, getprogname());
    Class springBoard = objc_getClass("SpringBoard");
    if (!springBoard) return;
    TEInstallExtensionHooks();
    TEInstallIconPipelineHooks();
    TEInstallFolderPreviewHooks();
    MSHookMessageEx(springBoard, @selector(applicationDidFinishLaunching:),
        (IMP)TEHookedDidFinishLaunching, (IMP *)&TEOriginalDidFinishLaunching);
}
