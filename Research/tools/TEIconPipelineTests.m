// Isolated on-device regression. No windows, UI automation, preferences writes,
// or SpringBoard injection. Only this process's framework classes are hooked.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "../../Sources/TEIconPipeline.m"
#import "../../Sources/TEFolderPreview.m"

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

static NSString *previewIdentifier;
static id PreviewIdentifier(id self, SEL cmd) { (void)self; (void)cmd; return previewIdentifier; }
static id previewTraits, previewContext;
static NSUInteger previewLayerFallbacks, previewGridFallbacks;
static id PreviewLayerFallback(id self, SEL cmd, TEIconImageInfo info, id traits, id context, NSUInteger options) {
    (void)self; (void)cmd;
    previewLayerFallbacks++;
    Check(info.size.width == 76 && traits == previewTraits && context == previewContext && options == 37,
        "preview layer fallback preserves struct, traits, context and options");
    return sentinel;
}
static UIImage *PreviewGridFallback(id self, SEL cmd, CGSize cell, id icon, TEIconImageInfo info, id appearance, NSUInteger *attributes) {
    (void)self; (void)cmd; (void)icon;
    previewGridFallbacks++;
    Check(cell.width == 12 && info.size.width == 76 && appearance == previewTraits && attributes && *attributes == 91,
        "preview grid fallback preserves cell, info, appearance and attribute pointer");
    return sentinel;
}
static BOOL PreviewHasRedCenter(UIImage *image) {
    if (!image.CGImage) return NO;
    uint8_t pixel[4] = {0};
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel,1,1,8,4,color,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGFloat width = CGImageGetWidth(image.CGImage), height = CGImageGetHeight(image.CGImage);
    CGContextDrawImage(context,CGRectMake(-floor(width/2),-floor(height/2),width,height),image.CGImage);
    CGContextRelease(context); CGColorSpaceRelease(color);
    return pixel[0] > 200 && pixel[1] < 50 && pixel[2] < 50 && pixel[3] > 200;
}
static UIImage *PreviewLayerPixels(id layer) {
    if (![layer isKindOfClass:CALayer.class]) return nil;
    id contents = [layer contents];
    if (!contents || CFGetTypeID((__bridge CFTypeRef)contents) != CGImageGetTypeID()) return nil;
    return [UIImage imageWithCGImage:(__bridge CGImageRef)contents];
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
        // Two preview paths: native mini-grid CALayers and static grid images.
        TEOriginalPreviewLayer = PreviewLayerFallback;
        TEOriginalPreviewGrid = PreviewGridFallback;
        Class iconBase = objc_getClass("SBIcon");
        Class previewClass = objc_allocateClassPair(iconBase, "TEPreviewIsolatedModelIcon", 0);
        class_addMethod(previewClass, @selector(applicationBundleIdentifier), (IMP)PreviewIdentifier, "@16@0:8");
        objc_registerClassPair(previewClass);
        id previewIcon = [previewClass new];
        previewIdentifier = @"test.pineora.icon";
        previewTraits = [UITraitCollection traitCollectionWithDisplayScale:2];
        previewContext = [NSObject new];
        TEIconImageInfo previewInfo = {CGSizeMake(76,76),2,16};
        id previewLayer = TEPreviewLayer(previewIcon,NULL,previewInfo,previewTraits,previewContext,1);
        UIImage *layerPixels = PreviewLayerPixels(previewLayer);
        Check(layerPixels && CGImageGetWidth(layerPixels.CGImage) == 152 && CornerAlpha(layerPixels) == 0,
            "native mini-grid layer contains rounded theme pixels at the requested resolution");
        id squareLayer = TEPreviewLayer(previewIcon,NULL,previewInfo,previewTraits,previewContext,0);
        Check(CornerAlpha(PreviewLayerPixels(squareLayer)) == 255,
            "model image options retain explicit square layer semantics");
        NSUInteger attributes = 91;
        CGSize cell = CGSizeMake(12,12);
        UIImage *miniImage = TEPreviewGrid(objc_getClass("SBFolderIconImageCache"),NULL,cell,icon,previewInfo,previewTraits,&attributes);
        Check(miniImage && miniImage.size.width == 12 && miniImage.size.height == 12 && CornerAlpha(miniImage) == 0,
            "static folder preview uses native resizer and preserves theme corner alpha");
        Check(attributes == 91, "themed static preview leaves native attribute output untouched");
        icon.applicationBundleIdentifier = @"test.pineora.missing";
        previewIdentifier = @"test.pineora.missing";
        Check(TEPreviewLayer(previewIcon,NULL,previewInfo,previewTraits,previewContext,37) == sentinel,
            "missing preview icon delegates to original layer factory");
        Check(TEPreviewGrid(objc_getClass("SBFolderIconImageCache"),NULL,cell,icon,previewInfo,previewTraits,&attributes) == sentinel,
            "missing preview icon delegates to original static grid generator");
        previewIdentifier = @"com.apple.mobiletimer";
        Check(TEPreviewLayer(previewIcon,NULL,previewInfo,previewTraits,previewContext,37) == sentinel,
            "live clock preview remains native");
        previewIdentifier = @"test.pineora.icon";
        icon.applicationBundleIdentifier = @"test.pineora.icon";
        [store setValue:@NO forKey:@"enabled"];
        Check(TEPreviewLayer(previewIcon,NULL,previewInfo,previewTraits,previewContext,37) == sentinel &&
            TEPreviewGrid(objc_getClass("SBFolderIconImageCache"),NULL,cell,icon,previewInfo,previewTraits,&attributes) == sentinel,
            "disabled theme restores both native preview paths");
        [store setValue:@YES forKey:@"enabled"];
        Check(previewLayerFallbacks == 3 && previewGridFallbacks == 2,
            "each preview fallback calls its original exactly once");
        TEInstallFolderPreviewHooks();
        Check(TEOriginalPreviewLayer && TEOriginalPreviewLayer != PreviewLayerFallback &&
            TEOriginalPreviewGrid && TEOriginalPreviewGrid != PreviewGridFallback,
            "both preview hooks installed against exact real system ABIs");
        SEL modelFactory = NSSelectorFromString(@"makeIconLayerNativelyOrFromImageIfNecessaryWithInfo:traitCollection:context:options:");
        id nativeLayer = ((id (*)(id,SEL,TEIconImageInfo,id,id,NSUInteger))objc_msgSend)(previewIcon,modelFactory,
            previewInfo,previewTraits,nil,1);
        Check(CornerAlpha(PreviewLayerPixels(nativeLayer)) == 0,
            "real model factory dispatch uses rounded themed native layer");
        SEL gridFactory = NSSelectorFromString(@"gridCellImageOfSize:forIcon:iconImageInfo:imageAppearance:imageAttributes:");
        UIImage *nativeMini = ((id (*)(id,SEL,CGSize,id,TEIconImageInfo,id,NSUInteger *))objc_msgSend)(
            objc_getClass("SBFolderIconImageCache"),gridFactory,cell,icon,previewInfo,nil,&attributes);
        Check(nativeMini.size.width == 12 && CornerAlpha(nativeMini) == 0,
            "real static preview dispatch uses a themed mini image");
        __block id backgroundLayer;
        __block BOOL previewRanOffMain = NO;
        dispatch_group_t previewGroup = dispatch_group_create();
        dispatch_group_async(previewGroup, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
            @autoreleasepool {
                previewRanOffMain = !NSThread.isMainThread;
                backgroundLayer = ((id (*)(id,SEL,TEIconImageInfo,id,id,NSUInteger))objc_msgSend)(previewIcon,modelFactory,
                    previewInfo,previewTraits,nil,1);
            }
        });
        if (dispatch_group_wait(previewGroup, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC))) {
            Check(NO, "background preview factory completes within its test deadline");
            return 2;
        }
        Check(previewRanOffMain, "background preview test actually executes off the main thread");
        Check([backgroundLayer isKindOfClass:CALayer.class], "background preview generation retains native CALayer contract");
        // The system adapter asynchronously sets contents off-main. Wait for
        // those contents, without displayIfNeeded: a plain CALayer has no draw
        // delegate, so explicitly redisplaying it would erase its image.
        NSDate *previewDeadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (!PreviewLayerPixels(backgroundLayer) && previewDeadline.timeIntervalSinceNow > 0) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
        }
        Check(PreviewHasRedCenter(PreviewLayerPixels(backgroundLayer)),
            "background native adapter asynchronously populates themed contents");
        [backgroundLayer setBounds:CGRectMake(0,0,76,76)];
        [backgroundLayer setContentsScale:2];
        UIGraphicsImageRendererFormat *backgroundFormat = [UIGraphicsImageRendererFormat preferredFormat];
        backgroundFormat.scale = 2; backgroundFormat.opaque = NO;
        UIImage *backgroundPixels = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(76,76) format:backgroundFormat]
            imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
                [backgroundLayer renderInContext:rendererContext.CGContext];
            }];
        NSData *backgroundPNG = UIImagePNGRepresentation(backgroundPixels);
        Check(backgroundPNG.length > 0 && CornerAlpha(backgroundPixels) == 0,
            "background native drawing-handler path preserves corner transparency");
        Check(PreviewHasRedCenter(layerPixels) && PreviewHasRedCenter(PreviewLayerPixels(nativeLayer)),
            "direct and hooked native layers contain the red theme fixture, not just transparent corners");
        Check(PreviewHasRedCenter(miniImage) && PreviewHasRedCenter(nativeMini),
            "direct and hooked static previews contain the red theme fixture");
        Check(PreviewHasRedCenter(backgroundPixels),
            "background drawing-handler rasterization contains the red theme fixture");
        NSUInteger generation = ((NSUInteger (*)(id,SEL))objc_msgSend)(previewIcon,NSSelectorFromString(@"imageGeneration"));
        TEInvalidateFolderPreviewIcons();
        Check(((NSUInteger (*)(id,SEL))objc_msgSend)(previewIcon,NSSelectorFromString(@"imageGeneration")) > generation,
            "theme reload invalidates the native model generation for tracked previews");
        __weak id weakIcon;
        @autoreleasepool {
            id temporary = [NSObject new];
            weakIcon = temporary; TEPreviewRecordIcon(temporary);
        }
        Check(weakIcon == nil, "preview tracking does not retain recycled model icons");
        printf("RESULT %d checks, %d failures\n", checks, failures);
    }
    return failures ? 1 : 0;
}
