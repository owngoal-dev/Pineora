#import "TEFolderPreview.h"
#import "TECompat.h"
#import "TEIconStore.h"
#import "TEExtensions.h"
#import "TELog.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSHashTable *TEPreviewIcons;
static NSLock *TEPreviewLock;

static void TEPreviewInitializeTracking(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        TEPreviewIcons = [NSHashTable weakObjectsHashTable];
        TEPreviewLock = [NSLock new];
    });
}

static void TEPreviewRecordIcon(id icon) {
    if (!icon) return;
    TEPreviewInitializeTracking();
    [TEPreviewLock lock];
    [TEPreviewIcons addObject:icon];
    [TEPreviewLock unlock];
}

static NSString *TEPreviewIdentifier(id icon) {
    NSString *identifier = TEStringForSelectors(icon,
        @[@"applicationBundleIdentifier", @"bundleIdentifier", @"leafIdentifier"]);
    if (!identifier.length) {
        @try { identifier = TEStringForSelectors([icon valueForKey:@"application"], @[@"bundleIdentifier"]); }
        @catch (__unused NSException *exception) { identifier = nil; }
    }
    return [identifier containsString:@"."] ? identifier : nil;
}

static UIImage *TEPreviewImage(id icon, TEIconImageInfo info, BOOL masked) {
    if (!icon || !TEIconStore.sharedStore.enabled) return nil;
    NSString *identifier = TEPreviewIdentifier(icon);
    if (!identifier) return nil;
    // The store validates dimensions and preserves theme masks / live-clock bypass.
    return [TEIconStore.sharedStore imageForBundleIdentifier:identifier size:info.size
        scale:info.scale cornerRadius:info.continuousCornerRadius masked:masked];
}

static BOOL TEPreviewHasMethod(id object, NSString *selector, const char *encoding) {
    Method method = object ? class_getInstanceMethod(object_getClass(object), NSSelectorFromString(selector)) : NULL;
    return method && strcmp(method_getTypeEncoding(method), encoding) == 0;
}

// This factory is used by the asynchronous model-layer path behind mini grids.
// Return the SAME system layer type via its existing UIImage adapter, not a
// UIImageView in a map whose consumers require native layer-view contracts.
static id (*TEOriginalPreviewLayer)(id, SEL, TEIconImageInfo, id, id, NSUInteger);
static id TEPreviewLayer(id self, SEL cmd, TEIconImageInfo info, id traits, id context, NSUInteger options) {
    TEPreviewRecordIcon(self);
    SEL adapter = NSSelectorFromString(@"makeIconLayerFromImage:");
    if (TEPreviewHasMethod(self, @"makeIconLayerFromImage:", "@24@0:8@16")) {
        // These are SBIcon image options, NOT SBHIconImageCache retrieval flags.
        // Mini-grid callers request option 1; preserve explicit square requests.
        UIImage *image = TEPreviewImage(self, info, (options & 1) != 0);
        if (image) {
            id layer = ((id (*)(id, SEL, id))objc_msgSend)(self, adapter, image);
            if (layer) return layer;
        }
    }
    return TEOriginalPreviewLayer(self, cmd, info, traits, context, options);
}

// The static/composited fallback calls SBIcon directly, bypassing image caches.
// Reuse the native mini-image resizer so its rendering format stays unchanged.
static UIImage *(*TEOriginalPreviewGrid)(id, SEL, CGSize, id, TEIconImageInfo, id, NSUInteger *);
static UIImage *TEPreviewGrid(id self, SEL cmd, CGSize cellSize, id icon,
                             TEIconImageInfo info, id appearance, NSUInteger *attributes) {
    TEPreviewRecordIcon(icon);
    if (isfinite(cellSize.width) && isfinite(cellSize.height) && cellSize.width > 0 &&
        cellSize.height > 0 && cellSize.width <= 512 && cellSize.height <= 512 &&
        TEPreviewHasMethod(self, @"gridCellImageOfSize:forIconImage:", "@40@0:8{CGSize=dd}16@32")) {
        UIImage *image = TEPreviewImage(icon, info, YES);
        if (image) {
            UIImage *result = ((id (*)(id, SEL, CGSize, id))objc_msgSend)(self,
                NSSelectorFromString(@"gridCellImageOfSize:forIconImage:"), cellSize, image);
            // The native class implementation leaves imageAttributes untouched.
            if (result) return result;
        }
    }
    return TEOriginalPreviewGrid(self, cmd, cellSize, icon, info, appearance, attributes);
}

void TEInvalidateFolderPreviewIcons(void) {
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26) return;
    TEPreviewInitializeTracking();
    [TEPreviewLock lock];
    NSArray *icons = TEPreviewIcons.allObjects;
    [TEPreviewLock unlock];
    NSUInteger count = 0;
    // Bump native image generations and notify observers, including mini grids.
    // This runs on theme changes, never on each layout or frame.
    for (id icon in icons) {
        if (!TEPreviewHasMethod(icon, @"reloadIconImage", "v16@0:8")) continue;
        @try {
            ((void (*)(id, SEL))objc_msgSend)(icon, NSSelectorFromString(@"reloadIconImage"));
            count++;
        } @catch (__unused NSException *exception) { }
    }
    os_log(TELog(), "TEPreview invalidated=%lu", (unsigned long)count);
}

void TEInstallFolderPreviewHooks(void) {
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        TEPreviewInitializeTracking();
        NSString *layerSelector = @"makeIconLayerNativelyOrFromImageIfNecessaryWithInfo:traitCollection:context:options:";
        NSString *gridSelector = @"gridCellImageOfSize:forIcon:iconImageInfo:imageAppearance:imageAttributes:";
        Method layer = class_getInstanceMethod(objc_getClass("SBIcon"), NSSelectorFromString(layerSelector));
        Method grid = class_getClassMethod(objc_getClass("SBFolderIconImageCache"), NSSelectorFromString(gridSelector));
        BOOL installedLayer = NO, installedGrid = NO;
        if (layer && strcmp(method_getTypeEncoding(layer), "@72@0:8{SBIconImageInfo={CGSize=dd}dd}16@48@56Q64") == 0) {
            installedLayer = TEInstallInstanceHook(@"SBIcon", layerSelector, (IMP)TEPreviewLayer, (IMP *)&TEOriginalPreviewLayer);
        }
        if (grid && strcmp(method_getTypeEncoding(grid), "@88@0:8{CGSize=dd}16@32{SBIconImageInfo={CGSize=dd}dd}40@72^Q80") == 0) {
            installedGrid = TEInstallClassHook(@"SBFolderIconImageCache", gridSelector, (IMP)TEPreviewGrid, (IMP *)&TEOriginalPreviewGrid);
        }
        os_log(TELog(), "TEPreview layerHook=%d gridHook=%d", installedLayer, installedGrid);
    });
}
