// ThemeEngine — SnowBoard 图标主题的功能等价实现（第一版）
//
// 静态逆向结论对应的做法：
//   - 主题来源：/Library/Themes/*.theme（bootstrap 路径）+ 用户 Media 目录
//   - 图标文件：IconBundles/、Bundles/、旧版 <bundleID>/ 三种布局
//   - 替换点：SpringBoard 的图标图片缓存 SBHIconImageCache 的取图方法，把主题图直接
//     交给调用方；方法名经本机 SpringBoardHome 反射确认（见 Research/tools/TEProbe.m）：
//     -imageForIcon:、-cachedImageForIcon:、-unmaskedImageForIcon: 都存在且只带一个参数
//   - 刷新：Darwin 通知（自己的名字 + SnowBoard 的通知名兼容），清缓存后重扫主题
//
// 这里没有搬运 SnowBoard 的二进制或源码，全部是按观察到的行为重写的实现。
#import <UIKit/UIKit.h>
#import <os/log.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <notify.h>

#import "TECompat.h"
#import "TEIconStore.h"
#import "TELog.h"

#pragma mark - 取 bundle id

static NSString *TEInferBundleIdentifier(id icon) {
    static NSArray<NSString *> *selectors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        selectors = @[@"applicationBundleIdentifier", @"bundleIdentifier", @"leafIdentifier"];
    });
    NSString *identifier = TEStringForSelectors(icon, selectors);
    if (identifier.length == 0) {
        // SBApplicationIcon 的兜底：icon -> application -> bundleIdentifier
        @try {
            id application = [icon valueForKey:@"application"];
            if (application != nil) {
                identifier = TEStringForSelectors(application, @[@"bundleIdentifier"]);
            }
        } @catch (__unused NSException *exception) {
            identifier = nil;
        }
    }
    // 只接受形如 com.apple.xxx 的标识，避免把 UUID 当 bundle id。
    return [identifier containsString:@"."] ? identifier : nil;
}

static NSInteger TEScreenScale(void) {
    CGFloat scale = [UIScreen mainScreen].scale;
    if (scale < 1) {
        scale = 2;
    }
    return (NSInteger)lround(scale);
}

/// 主题图；没有命中时返回 nil，调用方继续走系统实现。
static UIImage *TEThemedImageForIcon(id icon) {
    if (icon == nil) {
        return nil;
    }
    TEIconStore *store = [TEIconStore sharedStore];
    if (!store.enabled) {
        return nil;
    }
    NSString *bundleIdentifier = TEInferBundleIdentifier(icon);
    if (bundleIdentifier == nil) {
        return nil;
    }
    return [store imageForBundleIdentifier:bundleIdentifier scale:TEScreenScale()];
}

#pragma mark - 钩子

// 每个 selector 保存独立的原实现，避免回退到其它方法或递归。
static UIImage *(*TEOriginalIconCacheImage)(id, SEL, id);
static UIImage *(*TEOriginalCachedIconCacheImage)(id, SEL, id);
static UIImage *(*TEOriginalUnmaskedIconCacheImage)(id, SEL, id);

static UIImage *TEHookIconCacheImage(id self, SEL _cmd, id icon) {
    UIImage *image = TEThemedImageForIcon(icon);
    if (image != nil) {
        return image;
    }
    return TEOriginalIconCacheImage != NULL ? TEOriginalIconCacheImage(self, _cmd, icon) : nil;
}

static UIImage *TEHookCachedIconCacheImage(id self, SEL _cmd, id icon) {
    UIImage *image = TEThemedImageForIcon(icon);
    return image != nil ? image : (TEOriginalCachedIconCacheImage != NULL
        ? TEOriginalCachedIconCacheImage(self, _cmd, icon) : nil);
}

static UIImage *TEHookUnmaskedIconCacheImage(id self, SEL _cmd, id icon) {
    UIImage *image = TEThemedImageForIcon(icon);
    return image != nil ? image : (TEOriginalUnmaskedIconCacheImage != NULL
        ? TEOriginalUnmaskedIconCacheImage(self, _cmd, icon) : nil);
}

/// SBIconController.sharedInstance -> iconManager（SpringBoard 的运行期对象图）。
static id TEIconManager(void) {
    static id manager = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        id controller = TECallClassObject(@"SBIconController", @"sharedInstance");
        manager = TECallObject(controller, @"iconManager");
    });
    return manager;
}

static BOOL TECallVoidSelector(id target, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (target == nil || ![target respondsToSelector:selector]) {
        return NO;
    }
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

/// 让 SpringBoard 丢弃已缓存的图标图片，并让文件夹图标重绘。
/// 我们已经在取图方法里返回主题图，所以这里只为让屏幕上的旧图立刻换新。
static void TEPurgeIconCaches(void) {
    id manager = TEIconManager();
    if (manager == nil) {
        os_log_error(TELog(), "TEPurge no iconManager");
        return;
    }
    // SBHIconManager -iconImageCache / -folderIconImageCache（反射确认存在）。
    id iconCache = TECallObject(manager, @"iconImageCache");
    BOOL purged = TECallVoidSelector(iconCache, @"purgeAllCachedImages");
    id folderCache = TECallObject(manager, @"folderIconImageCache");
    BOOL folders = TECallVoidSelector(folderCache, @"informObserversOfUpdateForAllFolderIcons");
    os_log(TELog(), "TEPurge iconCache=%d folderCache=%d", purged ? 1 : 0, folders ? 1 : 0);
}

static void TEReloadThemes(void) {
    NSInteger count = [[TEIconStore sharedStore] reload];
    TEPurgeIconCaches();
    os_log(TELog(), "TEReload themes=%ld", (long)count);
}

#pragma mark - 通知

static void TERegisterNotifications(void) {
    NSArray<NSString *> *names = @[
        [NSString stringWithFormat:@"%s/refresh", APELIN_PACKAGE_ID],
        @"com.spark.snowboard.refresh",
        @"com.spark.snowboard.refreshNow",
        @"com.spark.snowboard.purgeAndUpdateAllIcons",
    ];
    static BOOL registered = NO;
    if (registered) {
        return;
    }
    registered = YES;
    for (NSString *name in names) {
        int token = 0;
        uint32_t status = notify_register_dispatch(name.UTF8String, &token,
                                                   dispatch_get_main_queue(), ^(int unusedToken) {
            (void)unusedToken;
            TEReloadThemes();
        });
        if (status == NOTIFY_STATUS_OK) {
            os_log(TELog(), "TENotify registered %{public}s", name.UTF8String);
        } else {
            os_log_error(TELog(), "TENotify failed %{public}s status=%u", name.UTF8String, status);
        }
    }
}

#pragma mark - SpringBoard 启动

static void (*TEOriginalDidFinishLaunching)(id, SEL, id);

static void TEHookedDidFinishLaunching(id self, SEL _cmd, id application) {
    if (TEOriginalDidFinishLaunching != NULL) {
        TEOriginalDidFinishLaunching(self, _cmd, application);
    }
    TEReloadThemes();
    TERegisterNotifications();
    os_log(TELog(), "TEStarted %{public}s", APELIN_BUILD_ID);
}

#pragma mark - 安装

__attribute__((constructor)) static void TweakInitialize(void) {
    // apelin_package_confirm_loaded 依赖这一行，保持公开且带 build id。
    os_log(TELog(), "ApelinLoaded %{public}s in %{public}s", APELIN_BUILD_ID, getprogname());

    if (objc_getClass("SpringBoard") == Nil) {
        return;  // 过滤器只指向 SpringBoard，其它进程直接退出。
    }

    // 先准备好主题表，避免 SpringBoard 第一批取图时才做磁盘扫描。
    [[TEIconStore sharedStore] reload];

    // 目标方法经本机 SpringBoardHome 反射确认（Research/tools/TEProbe.m）：
    //   SBHIconImageCache -imageForIcon: / -cachedImageForIcon: / -unmaskedImageForIcon:
    // 两个带 options 参数的变体没有钩：参数类型未证实，猜错会破坏调用约定。
    NSMutableArray<NSString *> *hooked = [NSMutableArray array];
    NSArray<NSString *> *selectorNames = @[@"imageForIcon:", @"cachedImageForIcon:", @"unmaskedImageForIcon:"];
    IMP replacements[] = {(IMP)TEHookIconCacheImage, (IMP)TEHookCachedIconCacheImage,
                          (IMP)TEHookUnmaskedIconCacheImage};
    IMP *originals[] = {(IMP *)&TEOriginalIconCacheImage, (IMP *)&TEOriginalCachedIconCacheImage,
                        (IMP *)&TEOriginalUnmaskedIconCacheImage};
    for (NSUInteger index = 0; index < selectorNames.count; index++) {
        NSString *selectorName = selectorNames[index];
        if (TEInstallInstanceHook(@"SBHIconImageCache", selectorName,
                                  replacements[index], originals[index])) {
            [hooked addObject:selectorName];
        }
    }
    os_log(hooked.count > 0 ? TELog() : TELog(), "TEHooks count=%lu names=%{public}s",
           (unsigned long)hooked.count,
           hooked.count > 0 ? [[hooked componentsJoinedByString:@","] UTF8String] : "none");
    if (hooked.count == 0) {
        os_log_error(TELog(), "TEHooks none: SBHIconImageCache not found on this iOS build");
    }

    Class springBoard = objc_getClass("SpringBoard");
    if (springBoard != Nil) {
        MSHookMessageEx(springBoard, @selector(applicationDidFinishLaunching:),
                        (IMP)TEHookedDidFinishLaunching, (IMP *)&TEOriginalDidFinishLaunching);
    }
}
