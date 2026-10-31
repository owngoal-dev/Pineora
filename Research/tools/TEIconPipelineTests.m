// Isolated on-device regression. No windows, UI automation, preferences writes,
// or SpringBoard injection. Only this process's framework classes are hooked.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "../../Sources/TEIconPipeline.m"

static int checks, failures;
static void Check(BOOL ok, const char *name) { checks++; if (!ok) failures++; printf("%s %s\n", ok ? "PASS" : "FAIL", name); }

// Use the real installed hook provider, loaded by its dynamically resolved path.
void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original) {
    static void (*hook)(Class, SEL, IMP, IMP *);
    if (!hook) {
        // This test executable lives in Apelin's shared-container path alias,
        // not the installed tweak's bootstrap directory. Resolve its provider
        // from the run's toolchain environment, never persist the resolved root.
        NSString *toolchain = @(getenv("APELIN_TOOLCHAIN_BIN") ?: "");
        NSRange marker = [toolchain rangeOfString:@"/usr/lib/apelin/toolchains/"];
        if (marker.location == NSNotFound || marker.location == 0) exit(2);
        NSString *prefix = [toolchain substringToIndex:marker.location];
        void *library = dlopen([prefix stringByAppendingString:@"/usr/lib/libellekit.dylib"].UTF8String, RTLD_NOW);
        if (!library) fprintf(stderr, "provider dlopen: %s\n", dlerror());
        hook = library ? dlsym(library, "MSHookMessageEx") : NULL;
    }
    if (!hook) { fprintf(stderr, "hook provider unavailable\n"); exit(2); }
    hook(cls, selector, replacement, original);
}

@interface TEPipelineTestIcon : NSObject
@property (nonatomic, copy) NSString *applicationBundleIdentifier;
@end
@implementation TEPipelineTestIcon
@end
typedef struct SBIconImageInfo { CGSize size; CGFloat scale; CGFloat continuousCornerRadius; } TEPipelineNativeInfo;
@interface TEPipelineSizing : NSObject
@end
@implementation TEPipelineSizing
- (TEPipelineNativeInfo)iconImageInfo { return (TEPipelineNativeInfo){CGSizeMake(76,76), 2, 16}; }
@end

@interface TEPipelineNativeVariantFixture : NSObject {
@public
    id maskedCache;
    id unmaskedCache;
}
@end
@implementation TEPipelineNativeVariantFixture
@end

static UIImage *sentinel;
static NSUInteger legacyFallbacks;
static UIImage *LegacyFallback(id self, SEL cmd, id icon) {
    (void)self; (void)cmd; (void)icon; legacyFallbacks++; return sentinel;
}
static UIImage *LegacyOptionsFallback(id self, SEL cmd, id icon, NSUInteger options) {
    Check(options == 37, "legacy options forwarded unchanged");
    return LegacyFallback(self, cmd, icon);
}
static id expectedAppearance;
static NSUInteger fallbackCalls;
static UIImage *Fallback(id self, SEL cmd, id icon, id appearance, NSUInteger options) {
    (void)self; (void)cmd; (void)icon;
    fallbackCalls++;
    Check(appearance == expectedAppearance && options == 37, "original appearance and option bits preserved");
    return sentinel;
}
static id viewIcon;
static id IconForView(id self, SEL cmd) { (void)self; (void)cmd; return viewIcon; }
static BOOL AllowsLayer(id self, SEL cmd) { (void)self; (void)cmd; return YES; }
static BOOL NotSquare(id self, SEL cmd) { (void)self; (void)cmd; return NO; }
static int CornerAlpha(UIImage *image) {
    if (!image.CGImage) return -1;
    uint8_t pixel[4] = {0};
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixel,1,1,8,4,color,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGContextDrawImage(ctx, CGRectMake(0, 1-(CGFloat)CGImageGetHeight(image.CGImage), CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage)), image.CGImage);
    CGContextRelease(ctx); CGColorSpaceRelease(color);
    return pixel[3];
}

int main(void) {
    @autoreleasepool {
        void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome", RTLD_LAZY|RTLD_GLOBAL);
        Class nativeCache = objc_getClass("SBHIconImageCache");
        Check(handle && nativeCache, "system cache available for native flag oracle");
        NSString *root = @(getenv("APELIN_PROJECT_ROOT") ?: "");
        if (!root.length) return 2;
        NSString *themePath = [root stringByAppendingPathComponent:@"build/PipelineFixture.theme"];
        NSString *icons = [themePath stringByAppendingPathComponent:@"IconBundles"];
        [NSFileManager.defaultManager createDirectoryAtPath:icons withIntermediateDirectories:YES attributes:nil error:NULL];
        sentinel = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(60,60)] imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
            [UIColor.redColor setFill]; UIRectFill(CGRectMake(0,0,60,60));
        }];
        [UIImagePNGRepresentation(sentinel) writeToFile:[icons stringByAppendingPathComponent:@"test.pineora.icon.png"] atomically:YES];
        TETheme *theme = [TETheme themeAtPath:themePath];
        Check(theme != nil, "isolated fixture parsed");
        TEIconStore *store = TEIconStore.sharedStore;
        [store setValue:@[theme] forKey:@"themes"];
        [store setValue:@YES forKey:@"enabled"];
        TEPipelineTestIcon *icon = [TEPipelineTestIcon new]; icon.applicationBundleIdentifier = @"test.pineora.icon";
        TEPipelineSizing *sizing = [TEPipelineSizing new];
        expectedAppearance = [NSObject new];
        UIImage *masked = TEAppearanceImage(sizing, NULL, icon, expectedAppearance, 1);
        Check(masked && masked.size.width == 76 && masked.scale == 2 && CGImageGetWidth(masked.CGImage) == 152, "appearance hook honors iPad size and scale");
        Check(CornerAlpha(masked) == 0, "masked option preserves transparent corners");
        UIImage *square = TEAppearanceImage(sizing, NULL, icon, expectedAppearance, 2);
        Check(CornerAlpha(square) == 255, "explicit unmasked option preserves square pixels");

        // The six-instruction native method selects self+8 or self+16 and returns
        // that cache. Call the real IMP on an isolated layout-checked fixture;
        // neither native caches nor system objects are mutated.
        Ivar nativeMasked = class_getInstanceVariable(nativeCache, "_maskedCache");
        Ivar nativeUnmasked = class_getInstanceVariable(nativeCache, "_unmaskedCache");
        Ivar fixtureMasked = class_getInstanceVariable(TEPipelineNativeVariantFixture.class, "maskedCache");
        Ivar fixtureUnmasked = class_getInstanceVariable(TEPipelineNativeVariantFixture.class, "unmaskedCache");
        SEL variant = NSSelectorFromString(@"variantCacheForOptions:");
        Method variantMethod = class_getInstanceMethod(nativeCache, variant);
        BOOL layout = nativeMasked && nativeUnmasked && fixtureMasked && fixtureUnmasked &&
            ivar_getOffset(nativeMasked) == ivar_getOffset(fixtureMasked) &&
            ivar_getOffset(nativeUnmasked) == ivar_getOffset(fixtureUnmasked) &&
            variantMethod && strcmp(method_getTypeEncoding(variantMethod), "@24@0:8Q16") == 0;
        Check(layout, "native variant IMP ABI and both fixture offsets verified");
        if (layout) {
            TEPipelineNativeVariantFixture *fixture = [TEPipelineNativeVariantFixture new];
            fixture->maskedCache = [NSObject new]; fixture->unmaskedCache = [NSObject new];
            id (*nativeVariant)(id, SEL, NSUInteger) = (void *)method_getImplementation(variantMethod);
            NSUInteger flags[] = {0,1,2,3,4,5,6,7,32,33,34,35,36,37,38,39};
            UIImage *(*entries[])(id,SEL,id,id,NSUInteger) = {TEAppearanceImage,TEAppearanceCached,TEAppearanceReal,TETraitImage,TETraitCached,TETraitReal};
            for (NSUInteger i = 0; i < sizeof(flags)/sizeof(flags[0]); i++) {
                BOOL nativeIsMasked = nativeVariant(fixture, variant, flags[i]) == fixture->maskedCache;
                BOOL matches = YES;
                for (NSUInteger j = 0; j < 6; j++) {
                    UIImage *output = entries[j](sizing,NULL,icon,expectedAppearance,flags[i]);
                    matches &= CornerAlpha(output) == (nativeIsMasked ? 0 : 255);
                }
                char message[128];
                snprintf(message,sizeof(message),"all six appearance entries match native variant mask for options=%lu",(unsigned long)flags[i]);
                Check(matches,message);
            }
        }
        Check(TEImage(sizing,NULL,icon) == masked && TECached(sizing,NULL,icon) == masked,
            "legacy masked and cached entrances retain their output");
        Check(TEUnmasked(sizing,NULL,icon) == square && TECachedUnmasked(sizing,NULL,icon) == square,
            "legacy unmasked entrances retain their output");
        Check(TEImageOptions(sizing,NULL,icon,0) == masked && TEImageOptions(sizing,NULL,icon,37) == masked,
            "legacy options entrance keeps original always-masked semantics");
        Check(TEUnmaskedOptions(sizing,NULL,icon,0) == square && TEUnmaskedOptions(sizing,NULL,icon,37) == square,
            "legacy unmasked-options entrance remains unmasked");
        TEOriginalImage = TEOriginalCached = TEOriginalUnmasked = TEOriginalCachedUnmasked = LegacyFallback;
        TEOriginalImageOptions = TEOriginalUnmaskedOptions = LegacyOptionsFallback;
        icon.applicationBundleIdentifier = @"test.pineora.missing";
        Check(TEImage(sizing,NULL,icon) == sentinel && TECached(sizing,NULL,icon) == sentinel &&
            TEUnmasked(sizing,NULL,icon) == sentinel && TECachedUnmasked(sizing,NULL,icon) == sentinel &&
            TEImageOptions(sizing,NULL,icon,37) == sentinel && TEUnmaskedOptions(sizing,NULL,icon,37) == sentinel,
            "all six legacy misses chain to their saved originals");
        Check(legacyFallbacks == 6, "legacy misses invoke exactly one original each");
        icon.applicationBundleIdentifier = @"test.pineora.icon";
        Check(TEAppearanceCached(sizing,NULL,icon,nil,1) == masked, "appearance cache hit returns themed image");
        Check(TEAppearanceReal(sizing,NULL,icon,nil,1) == masked, "appearance real-image entry covered");
        Check(TETraitImage(sizing,NULL,icon,nil,1) == masked && TETraitCached(sizing,NULL,icon,nil,1) == masked && TETraitReal(sizing,NULL,icon,nil,1) == masked, "trait bridges return same themed output");
        TEOriginalAppearanceImage = TEOriginalAppearanceCached = TEOriginalAppearanceReal = Fallback;
        TEOriginalTraitImage = TEOriginalTraitCached = TEOriginalTraitReal = Fallback;
        icon.applicationBundleIdentifier = @"test.pineora.missing";
        UIImage *(*entries[])(id,SEL,id,id,NSUInteger) = {TEAppearanceImage,TEAppearanceCached,TEAppearanceReal,TETraitImage,TETraitCached,TETraitReal};
        for (NSUInteger i = 0; i < 6; i++) Check(entries[i](sizing,NULL,icon,expectedAppearance,37) == sentinel, "missing theme chains to saved original");
        icon.applicationBundleIdentifier = @"test.pineora.icon";
        [store setValue:@NO forKey:@"enabled"];
        Check(TEAppearanceImage(sizing,NULL,icon,expectedAppearance,37) == sentinel, "disabled store preserves native path");
        [store setValue:@YES forKey:@"enabled"];
        Check(fallbackCalls == 7, "exactly one original call for each fallback");

        Class base = objc_getClass("SBIconImageView");
        Check(handle && base, "current system image-view class loaded");
        TEInstallIconPipelineHooks();
        Check(TEOriginalAppearanceImage && TEOriginalAppearanceImage != Fallback &&
            TEOriginalAppearanceCached && TEOriginalAppearanceCached != Fallback &&
            TEOriginalAppearanceReal && TEOriginalAppearanceReal != Fallback &&
            TEOriginalTraitImage && TEOriginalTraitImage != Fallback &&
            TEOriginalTraitCached && TEOriginalTraitCached != Fallback &&
            TEOriginalTraitReal && TEOriginalTraitReal != Fallback,
            "six new hooks installed against actual system signatures");
        Class cls = objc_allocateClassPair(base, "TEPipelineIsolatedImageView", 0);
        class_addMethod(cls, @selector(iconForImage), (IMP)IconForView, "@16@0:8");
        class_addMethod(cls, @selector(showsSquareCorners), (IMP)NotSquare, "B16@0:8");
        class_addMethod(object_getClass(cls), @selector(allowsImageLayer), (IMP)AllowsLayer, "B16@0:8");
        objc_registerClassPair(cls);
        id view = [[cls alloc] initWithFrame:CGRectMake(0,0,76,76)];
        viewIcon = icon;
        SEL layerSelector = NSSelectorFromString(@"shouldDisplayImageLayer");
        Check(!((BOOL (*)(id,SEL))objc_msgSend)(view,layerSelector), "themed system view selects native bitmap branch");
        icon.applicationBundleIdentifier = @"test.pineora.missing";
        Check(((BOOL (*)(id,SEL))objc_msgSend)(view,layerSelector), "unthemed system view retains native layer branch");
        icon.applicationBundleIdentifier = @"com.apple.mobiletimer";
        Check(((BOOL (*)(id,SEL))objc_msgSend)(view,layerSelector), "live clock retains native layer branch");
        icon.applicationBundleIdentifier = @"test.pineora.icon";
        [store setValue:@NO forKey:@"enabled"];
        Check(((BOOL (*)(id,SEL))objc_msgSend)(view,layerSelector), "disabling theme restores native layer branch");
        [store setValue:@YES forKey:@"enabled"];
        // A genuine cache object and selector, not a direct call to our C function.
        id cache = [objc_getClass("SBHIconImageCache") new];
        UIImage *result = ((id (*)(id,SEL,id,id,NSUInteger))objc_msgSend)(cache,
            NSSelectorFromString(@"imageForIcon:imageAppearance:options:"), icon, nil, 0);
        Check([result isKindOfClass:UIImage.class] && result.CGImage, "actual system cache dispatch returns theme UIImage");
        Check(CornerAlpha(result) == 0, "actual cache options=0 returns transparent rounded corners");
        UIImage *unmaskedResult = ((id (*)(id,SEL,id,id,NSUInteger))objc_msgSend)(cache,
            NSSelectorFromString(@"imageForIcon:imageAppearance:options:"), icon, nil, 2);
        Check(CornerAlpha(unmaskedResult) == 255, "actual cache explicit unmasked request still returns square pixels");
        SEL display = NSSelectorFromString(@"updateImageContentsWithImage:imageAppearance:animated:shouldClearDisplayedLayer:");
        Method displayMethod = class_getInstanceMethod(base, display);
        BOOL displayABI = displayMethod && strcmp(method_getTypeEncoding(displayMethod), "v40@0:8@16@24B32B36") == 0;
        Check(displayABI, "native bitmap display method ABI verified");
        if (displayABI) {
            ((void (*)(id,SEL,id,id,BOOL,BOOL))objc_msgSend)(view,display,result,nil,NO,YES);
            UIImage *displayed = TECallObject(view,@"displayedImage");
            Check(displayed == result && CornerAlpha(displayed) == 0,
                "detached native image view displays the rounded default-cache image");
        }
        printf("RESULT %d checks, %d failures\n", checks, failures);
    }
    return failures ? 1 : 0;
}
