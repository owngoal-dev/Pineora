#import "TEExtensions.h"
#import "TEIconStore.h"
#import "TECompat.h"
#import "TERenderer.h"
#import "TELog.h"
#import "TEIconRefresh.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSHashTable *TEVisibleIcons;
static NSHashTable *TEClockViews;
static char TEOriginalImageKey, TELastImageKey, TETextFrameKey, TEClockMaskCacheKey, TEBadgeTintKey;

TEIconImageInfo TEImageInfoForObject(id object) {
    TEIconImageInfo info = {CGSizeMake(60, 60), UIScreen.mainScreen.scale, 13.5};
    Method method = class_getInstanceMethod([object class], NSSelectorFromString(@"iconImageInfo"));
    char *type = method ? method_copyReturnType(method) : NULL;
    if (type && strcmp(type, "{SBIconImageInfo={CGSize=dd}dd}") == 0) {
        TEIconImageInfo candidate = ((TEIconImageInfo (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(@"iconImageInfo"));
        if (isfinite(candidate.size.width) && isfinite(candidate.size.height) && candidate.size.width > 0 && candidate.size.height > 0 &&
            candidate.size.width <= 512 && candidate.size.height <= 512 && isfinite(candidate.scale) && candidate.scale >= 1 && candidate.scale <= 4 &&
            isfinite(candidate.continuousCornerRadius) && candidate.continuousCornerRadius >= 0) info = candidate;
    }
    free(type);
    return info;
}

static id TEObjectIvar(id object, const char *name, Class expected) {
    Ivar ivar = class_getInstanceVariable([object class], name);
    if (!ivar || ivar_getTypeEncoding(ivar)[0] != '@') return nil;
    id value = object_getIvar(object, ivar);
    return [value isKindOfClass:expected] ? value : nil;
}

// 只在自己仍持有当前替换图时恢复，避免盖掉系统或另一个 tweak 的新值。
static void TEOverrideImage(UIImageView *view, UIImage *image) {
    if (!view) return;
    id previous = objc_getAssociatedObject(view, &TELastImageKey);
    if (image) {
        if (!previous || view.image != previous) objc_setAssociatedObject(view, &TEOriginalImageKey, view.image ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.image = image;
        objc_setAssociatedObject(view, &TELastImageKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (previous) {
        id original = objc_getAssociatedObject(view, &TEOriginalImageKey);
        if (view.image == previous) view.image = original == NSNull.null ? nil : original;
        objc_setAssociatedObject(view, &TELastImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &TEOriginalImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static CGFloat TETextOffset(NSDictionary *settings, NSString *name) {
    id value = settings[name];
    CGFloat number = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0;
    return isfinite(number) ? MAX(-60, MIN(number, 60)) : 0;
}

static void TEApplyTextOffset(UIImageView *view, NSDictionary *settings) {
    if (!view) return;
    NSDictionary *state = objc_getAssociatedObject(view, &TETextFrameKey);
    CGRect base = view.frame;
    if (state && CGRectEqualToRect(base, [state[@"last"] CGRectValue])) base = [state[@"base"] CGRectValue];
    CGRect result = CGRectOffset(base, TETextOffset(settings, @"TextXoffset"), TETextOffset(settings, @"TextYoffset"));
    view.frame = result;
    objc_setAssociatedObject(view, &TETextFrameKey, @{ @"base": [NSValue valueWithCGRect:base], @"last": [NSValue valueWithCGRect:result] }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void TEApplyBadgeTextColor(UIImageView *view, NSDictionary *settings) {
    if (!view) return;
    id colorValue = settings[@"TextColor"];
    if (![colorValue isKindOfClass:NSString.class]) { TEOverrideImage(view, nil); return; }
    id last = objc_getAssociatedObject(view, &TELastImageKey);
    UIImage *source = view.image;
    if (last && source == last) {
        id saved = objc_getAssociatedObject(view, &TEOriginalImageKey);
        source = [saved isKindOfClass:UIImage.class] ? saved : nil;
    }
    if (!source || source.size.width <= 0 || source.size.height <= 0) return;
    // 原生 _checkout 返回缓存 tuple，不能改它；只给当前 view 生成着色副本。
    NSDictionary *cached = objc_getAssociatedObject(view, &TEBadgeTintKey);
    UIImage *tinted = cached[@"image"];
    if (cached[@"source"] != source || ![cached[@"color"] isEqual:colorValue]) {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
        format.scale = source.scale; format.opaque = NO;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:source.size format:format];
        tinted = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
            CGRect rect = (CGRect){CGPointZero, source.size};
            [source drawInRect:rect];
            [TEColorFromSettings(colorValue, UIColor.whiteColor) setFill];
            UIRectFillUsingBlendMode(rect, kCGBlendModeSourceIn);
        }];
        objc_setAssociatedObject(view, &TEBadgeTintKey, @{@"source":source, @"color":colorValue, @"image":tinted}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    TEOverrideImage(view, tinted);
}

static void (*TEOriginalBadgeLayout)(id, SEL);
static void TEBadgeLayout(id self, SEL cmd) {
    TEOriginalBadgeLayout(self, cmd);
    TEIconStore *store = TEIconStore.sharedStore;
    UIImageView *background = TEObjectIvar(self, "_backgroundView", UIImageView.class);
    UIImage *raw = [store rawResourceForBundleIdentifier:@"com.apple.springboard" name:@"SBBadgeBG" scale:(NSInteger)lround(UIScreen.mainScreen.scale)];
    UIImage *stretch = raw ? [raw resizableImageWithCapInsets:UIEdgeInsetsMake(MAX(0, raw.size.height / 2 - 0.5), MAX(0, raw.size.width / 2 - 0.5),
        MAX(0, raw.size.height / 2 - 0.5), MAX(0, raw.size.width / 2 - 0.5)) resizingMode:UIImageResizingModeStretch] : nil;
    TEOverrideImage(background, stretch);
    NSDictionary *settings = [store settingsForKey:@"BadgeSettings"];
    TEApplyTextOffset(TEObjectIvar(self, "_textView", UIImageView.class), settings);
    TEApplyTextOffset(TEObjectIvar(self, "_incomingTextView", UIImageView.class), settings);
    TEApplyBadgeTextColor(TEObjectIvar(self, "_textView", UIImageView.class), settings);
    TEApplyBadgeTextColor(TEObjectIvar(self, "_incomingTextView", UIImageView.class), settings);
}

static UIFont *(*TEOriginalBadgeFont)(id, SEL);
static UIFont *TEBadgeFont(id self, SEL cmd) {
    UIFont *original = TEOriginalBadgeFont(self, cmd);
    NSDictionary *settings = [TEIconStore.sharedStore settingsForKey:@"BadgeSettings"];
    return settings.count ? TEFontFromSettings(settings, original ?: [UIFont systemFontOfSize:14]) : original;
}

static UIImage *TEClockBackground(id view, BOOL masked) {
    TEIconStore *store = TEIconStore.sharedStore;
    TEIconImageInfo info = TEImageInfoForObject(view);
    UIImage *raw = [store rawResourceForBundleIdentifier:@"com.apple.springboard" name:@"ClockIconBackgroundSquare" scale:(NSInteger)lround(info.scale)];
    if (!raw) return nil;
    // 图标缓存相同尺寸共用；圆角输出也缓存，时钟每秒读取不重复渲染。
    UIImage *result = [store resourceImageForBundleIdentifier:@"com.apple.springboard" name:@"ClockIconBackgroundSquare" size:info.size scale:info.scale];
    if (!masked) return result;
    UIImage *mask = [store rawResourceForBundleIdentifier:@"com.apple.mobileicons.framework" name:@"AppIconMask" scale:(NSInteger)lround(info.scale)];
    NSString *key = [NSString stringWithFormat:@"%g:%g:%g:%g:%p", info.size.width, info.size.height, info.scale, info.continuousCornerRadius, mask];
    NSDictionary *cached = objc_getAssociatedObject(result, &TEClockMaskCacheKey);
    if ([cached[@"key"] isEqualToString:key]) return cached[@"image"];
    UIImage *output = TERenderIcon(result, info.size, info.scale, info.continuousCornerRadius, YES, mask, nil, nil, nil);
    objc_setAssociatedObject(result, &TEClockMaskCacheKey, @{@"key":key, @"image":output}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return output;
}

static UIImage *(*TEOriginalClockContents)(id, SEL);
static UIImage *TEClockContents(id self, SEL cmd) { return TEClockBackground(self, YES) ?: TEOriginalClockContents(self, cmd); }
static UIImage *(*TEOriginalClockSquare)(id, SEL);
static UIImage *TEClockSquare(id self, SEL cmd) { return TEClockBackground(self, NO) ?: TEOriginalClockSquare(self, cmd); }

static void TEApplyClockLayers(id view) {
    NSArray *ivars = @[@"_hours", @"_minutes", @"_seconds", @"_hourMinuteDot", @"_secondDot"];
    NSArray *names = @[@"ClockIconHourHand", @"ClockIconMinuteHand", @"ClockIconSecondHand", @"ClockIconBlackDot", @"ClockIconRedDot"];
    TEIconImageInfo info = TEImageInfoForObject(view);
    for (NSUInteger i = 0; i < ivars.count; i++) {
        CALayer *layer = TEObjectIvar(view, [ivars[i] UTF8String], CALayer.class);
        if (!layer) continue;
        UIImage *image = [TEIconStore.sharedStore resourceImageForBundleIdentifier:@"com.apple.springboard" name:names[i] size:layer.bounds.size scale:info.scale];
        id last = objc_getAssociatedObject(layer, &TELastImageKey);
        if (image) {
            if (!last || layer.contents != last) objc_setAssociatedObject(layer, &TEOriginalImageKey, layer.contents ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            id contents = (__bridge id)image.CGImage;
            layer.contents = contents;
            objc_setAssociatedObject(layer, &TELastImageKey, contents, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (last) {
            id original = objc_getAssociatedObject(layer, &TEOriginalImageKey);
            if (layer.contents == last) layer.contents = original == NSNull.null ? nil : original;
            objc_setAssociatedObject(layer, &TELastImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(layer, &TEOriginalImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static void (*TEOriginalClockLayout)(id, SEL);
static void TEClockLayout(id self, SEL cmd) {
    TEOriginalClockLayout(self, cmd);
    [TEClockViews addObject:self];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    TEApplyClockLayers(self);
    [CATransaction commit];
}

static void (*TEOriginalIconLayout)(id, SEL);
static void TEIconLayout(id self, SEL cmd) { TEOriginalIconLayout(self, cmd); [TEVisibleIcons addObject:self]; }

static BOOL TEHook(id cls, NSString *name, BOOL meta, IMP replacement, IMP *original, const char *encoding) {
    Class target = meta ? object_getClass(cls) : cls;
    Method method = class_getInstanceMethod(target, NSSelectorFromString(name));
    if (!method || strcmp(method_getTypeEncoding(method), encoding) != 0) {
        os_log(TELog(), "TEExtension skipped %{public}s signature mismatch", name.UTF8String); return NO;
    }
    MSHookMessageEx(target, NSSelectorFromString(name), replacement, original);
    return *original != NULL;
}

void TERefreshExtensionViews(void) {
    NSUInteger refreshed = 0;
    NSUInteger unavailable = 0;
    // Settings can cover/detach the Home Screen while Apply runs. Refresh all live
    // icon views, not only those currently attached to a window (including Dock).
    for (UIView *view in TEVisibleIcons.allObjects) {
        if (TERefreshIconImageView(view)) refreshed++;
        else unavailable++;
        SEL badge = NSSelectorFromString(@"_updateAccessoryViewAnimated:");
        if ([view respondsToSelector:badge]) ((void (*)(id, SEL, BOOL))objc_msgSend)(view, badge, NO);
        [view setNeedsLayout];
    }
    os_log(TELog(), "TERefresh images=%lu unavailable=%lu", (unsigned long)refreshed, (unsigned long)unavailable);
    for (UIView *view in TEClockViews.allObjects) {
        TEApplyClockLayers(view);
        [view setNeedsLayout];
    }
}

void TEInstallExtensionHooks(void) {
    TEVisibleIcons = [NSHashTable weakObjectsHashTable];
    TEClockViews = [NSHashTable weakObjectsHashTable];
    NSUInteger count = 0;
    Class badge = objc_getClass("SBIconBadgeView");
    count += TEHook(badge, @"layoutSubviews", NO, (IMP)TEBadgeLayout, (IMP *)&TEOriginalBadgeLayout, "v16@0:8");
    count += TEHook(badge, @"font", NO, (IMP)TEBadgeFont, (IMP *)&TEOriginalBadgeFont, "@16@0:8");
    Class clock = objc_getClass("SBHClockApplicationIconImageView");
    count += TEHook(clock, @"contentsImage", NO, (IMP)TEClockContents, (IMP *)&TEOriginalClockContents, "@16@0:8");
    count += TEHook(clock, @"squareContentsImage", NO, (IMP)TEClockSquare, (IMP *)&TEOriginalClockSquare, "@16@0:8");
    count += TEHook(clock, @"layoutSubviews", NO, (IMP)TEClockLayout, (IMP *)&TEOriginalClockLayout, "v16@0:8");
    count += TEHook(objc_getClass("SBIconView"), @"layoutSubviews", NO, (IMP)TEIconLayout, (IMP *)&TEOriginalIconLayout, "v16@0:8");
    os_log(TELog(), "TEExtension installed=%lu (mask/calendar/badge/clock resources)", (unsigned long)count);
}
