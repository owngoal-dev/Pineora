#import "TEIconPipeline.h"
#import "TECompat.h"
#import "TEIconStore.h"
#import "TEExtensions.h"
#import "TELog.h"
#import <objc/runtime.h>

static NSString *TEInferBundleIdentifier(id icon) {
    static NSArray<NSString *> *selectors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        selectors = @[@"applicationBundleIdentifier", @"bundleIdentifier", @"leafIdentifier"];
    });
    NSString *identifier = TEStringForSelectors(icon, selectors);
    if (!identifier.length) {
        @try {
            identifier = TEStringForSelectors([icon valueForKey:@"application"], @[@"bundleIdentifier"]);
        } @catch (__unused NSException *exception) {
            identifier = nil;
        }
    }
    return [identifier containsString:@"."] ? identifier : nil;
}

static UIImage *TEThemedImageForIcon(id sizingObject, id icon, BOOL masked) {
    TEIconStore *store = TEIconStore.sharedStore;
    if (!icon || !store.enabled) return nil;
    NSString *identifier = TEInferBundleIdentifier(icon);
    if (!identifier) return nil;
    TEIconImageInfo info = TEImageInfoForObject(sizingObject);
    return [store imageForBundleIdentifier:identifier size:info.size scale:info.scale
                             cornerRadius:info.continuousCornerRadius masked:masked];
}

// Each entry has its own saved IMP; calls continue to chain with other tweaks.
#define TE_SIMPLE_HOOK(Name, Masked) \
    static UIImage *(*TEOriginal##Name)(id, SEL, id); \
    static UIImage *TE##Name(id self, SEL cmd, id icon) { \
        UIImage *image = TEThemedImageForIcon(self, icon, Masked); \
        return image ?: (TEOriginal##Name ? TEOriginal##Name(self, cmd, icon) : nil); \
    }
TE_SIMPLE_HOOK(Image, YES)
TE_SIMPLE_HOOK(Cached, YES)
TE_SIMPLE_HOOK(Unmasked, NO)
TE_SIMPLE_HOOK(CachedUnmasked, NO)

// The native imageCacheRetrievalOptions uses bit 0 for masking (verified on 26.0.1).
#define TE_OPTIONS_HOOK(Name, Masked) \
    static UIImage *(*TEOriginal##Name)(id, SEL, id, NSUInteger); \
    static UIImage *TE##Name(id self, SEL cmd, id icon, NSUInteger options) { \
        return TEThemedImageForIcon(self, icon, Masked) ?: TEOriginal##Name(self, cmd, icon, options); \
    }
// Keep the legacy entry's masking behavior unchanged. Only the new iOS 26
// appearance-aware API interprets its independently verified option bits.
TE_OPTIONS_HOOK(ImageOptions, YES)
TE_OPTIONS_HOOK(UnmaskedOptions, NO)

// iOS 18+/26 views no longer pass through imageForIcon: or imageForIcon:options:.
// Their appearance-aware path and trait-collection bridges must be covered too.
#define TE_APPEARANCE_HOOK(Name) \
    static UIImage *(*TEOriginal##Name)(id, SEL, id, id, NSUInteger); \
    static UIImage *TE##Name(id self, SEL cmd, id icon, id appearance, NSUInteger options) { \
        return TEThemedImageForIcon(self, icon, (options & 1) != 0) \
            ?: TEOriginal##Name(self, cmd, icon, appearance, options); \
    }
TE_APPEARANCE_HOOK(AppearanceImage)
TE_APPEARANCE_HOOK(AppearanceCached)
TE_APPEARANCE_HOOK(AppearanceReal)
TE_APPEARANCE_HOOK(TraitImage)
TE_APPEARANCE_HOOK(TraitCached)
TE_APPEARANCE_HOOK(TraitReal)

static BOOL (*TEOriginalShouldDisplayImageLayer)(id, SEL);
static BOOL TEShouldDisplayImageLayer(id self, SEL cmd) {
    BOOL original = TEOriginalShouldDisplayImageLayer(self, cmd);
    if (!original) return NO;
    // Glass icons use IconRendering layers, bypassing every UIImage cache hook.
    // Select the system's existing bitmap branch only for a successfully rendered
    // themed icon. Missing/disabled icons and the live clock keep native layers.
    id icon = TECallObject(self, @"iconForImage");
    if (!TEThemedImageForIcon(self, icon, YES)) return original;
    static BOOL logged;
    if (!logged) {
        logged = YES;
        os_log(TELog(), "TEPipeline themed icon using native bitmap branch build=%{public}s", APELIN_BUILD_ID);
    }
    return NO;
}

static BOOL TEHookPipeline(NSString *className, NSString *selectorName, IMP replacement,
                            IMP *original, const char *encoding) {
    Method method = class_getInstanceMethod(objc_getClass(className.UTF8String), NSSelectorFromString(selectorName));
    if (!method) return NO; // The method is optional on older releases.
    if (strcmp(method_getTypeEncoding(method), encoding) != 0) {
        os_log_error(TELog(), "TEPipeline skipped %{public}s actual=%{public}s", selectorName.UTF8String,
                     method_getTypeEncoding(method));
        return NO;
    }
    return TEInstallInstanceHook(className, selectorName, replacement, original);
}

void TEInstallIconPipelineHooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSUInteger count = 0;
#define TE_INSTALL(Selector, Name, Encoding) \
        count += TEHookPipeline(@"SBHIconImageCache", @Selector, (IMP)TE##Name, (IMP *)&TEOriginal##Name, Encoding)
        TE_INSTALL("imageForIcon:", Image, "@24@0:8@16");
        TE_INSTALL("cachedImageForIcon:", Cached, "@24@0:8@16");
        TE_INSTALL("unmaskedImageForIcon:", Unmasked, "@24@0:8@16");
        TE_INSTALL("cachedUnmaskedImageForIcon:", CachedUnmasked, "@24@0:8@16");
        TE_INSTALL("imageForIcon:options:", ImageOptions, "@32@0:8@16Q24");
        TE_INSTALL("unmaskedImageForIcon:options:", UnmaskedOptions, "@32@0:8@16Q24");
        BOOL layer = NO;
        NSInteger majorVersion = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
        // 18.0 SDK introduces SBHIconImageAppearance and its retrieval exports.
        // Each optional method still needs the exact runtime ABI above.
        if (majorVersion >= 18) {
            TE_INSTALL("imageForIcon:imageAppearance:options:", AppearanceImage, "@40@0:8@16@24Q32");
            TE_INSTALL("cachedImageForIcon:imageAppearance:options:", AppearanceCached, "@40@0:8@16@24Q32");
            TE_INSTALL("realImageForIcon:imageAppearance:options:", AppearanceReal, "@40@0:8@16@24Q32");
            TE_INSTALL("imageForIcon:compatibleWithTraitCollection:options:", TraitImage, "@40@0:8@16@24Q32");
            TE_INSTALL("cachedImageForIcon:compatibleWithTraitCollection:options:", TraitCached, "@40@0:8@16@24Q32");
            TE_INSTALL("realImageForIcon:compatibleWithTraitCollection:options:", TraitReal, "@40@0:8@16@24Q32");
        }
        if (majorVersion >= 26) {
            layer = TEHookPipeline(@"SBIconImageView", @"shouldDisplayImageLayer", (IMP)TEShouldDisplayImageLayer,
                (IMP *)&TEOriginalShouldDisplayImageLayer, "B16@0:8");
        }
#undef TE_INSTALL
        os_log(TELog(), "TEPipeline cacheHooks=%lu layerBridge=%d", (unsigned long)count, layer);
    });
}
