// Isolated tests: no hooks installed, no windows shown, no user settings modified.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "../../Sources/TEIconRefresh.h"

static int checks, failures;
static void Check(BOOL ok, const char *message) {
    checks++; if (!ok) failures++;
    printf("%s %s\n", ok ? "PASS" : "FAIL", message);
}
@interface TERefreshTestImage : NSObject
@property (nonatomic) NSUInteger clears, updates;
@property (nonatomic) BOOL animated, stale, fail;
@end
@implementation TERefreshTestImage
- (void)clearCachedImages { self.clears++; self.stale = NO; }
- (void)updateImageAnimated:(BOOL)animated {
    if (self.fail) @throw [NSException exceptionWithName:@"Test" reason:nil userInfo:nil];
    self.updates++; self.animated = animated;
    Check(!self.stale, "image cleared before update");
}
@end
@interface TERefreshTestIcon : NSObject
@property (nonatomic, strong) id imageView;
@end
@implementation TERefreshTestIcon
- (id)_iconImageView { return self.imageView; }
@end
@interface TERefreshWrongSignature : NSObject
@end
@implementation TERefreshWrongSignature
- (void)clearCachedImages { abort(); }
- (void)updateImageAnimated:(id)value { (void)value; abort(); }
@end

// Real system SBIconImageView, but with synthetic image sources and no icon model.
static UIImage *source;
static UIImage *cached;
static NSUInteger reads;
static id Contents(id self, SEL cmd) { (void)self; (void)cmd; reads++; if (!cached) cached = source; return cached; }
static void Clear(id self, SEL cmd) { (void)self; (void)cmd; cached = nil; }
static UIImage *Solid(UIColor *color) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(60,60)] imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [color setFill]; UIRectFill(CGRectMake(0,0,60,60));
    }];
}
int main(void) {
    @autoreleasepool {
        TERefreshTestIcon *icon = [TERefreshTestIcon new];
        TERefreshTestImage *image = [TERefreshTestImage new];
        image.stale = YES; icon.imageView = image;
        Check(TERefreshIconImageView(icon), "refresh existing image view");
        Check(image.clears == 1 && image.updates == 1 && !image.animated, "one clear and one nonanimated fetch");
        Check(TERefreshIconImageView(icon), "repeat apply supported");
        Check(image.clears == 2 && image.updates == 2, "repeat apply fetches again");
        Check(!TERefreshIconImageView(nil), "nil container ignored");
        Check(!TERefreshIconImageView([NSObject new]), "unsupported container ignored");
        icon.imageView = nil;
        Check(!TERefreshIconImageView(icon), "absent image view ignored");
        icon.imageView = [TERefreshWrongSignature new];
        Check(!TERefreshIconImageView(icon), "wrong ABI rejected before any mutation");
        image.fail = YES; icon.imageView = image;
        Check(!TERefreshIconImageView(icon), "private API exception contained");

        void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome", RTLD_LAZY | RTLD_GLOBAL);
        Class base = objc_getClass("SBIconImageView");
        Check(handle && base, "system SBIconImageView available");
        if (base) {
            Class cls = objc_allocateClassPair(base, "TERefreshSystemTestImageView", 0);
            class_addMethod(cls, @selector(contentsImage), (IMP)Contents, "@16@0:8");
            class_addMethod(cls, @selector(squareContentsImage), (IMP)Contents, "@16@0:8");
            class_addMethod(cls, @selector(clearCachedImages), (IMP)Clear, "v16@0:8");
            objc_registerClassPair(cls);
            UIView *view = [[cls alloc] initWithFrame:CGRectMake(0,0,60,60)];
            icon.imageView = view;
            source = Solid(UIColor.redColor);
            Check(TERefreshIconImageView(icon), "real system image view accepts clear/update contract");
            NSUInteger previousReads = reads;
            source = Solid(UIColor.blueColor);
            Check(TERefreshIconImageView(icon), "real detached system image view refreshes again");
            Check(reads > previousReads && cached == source && view.window == nil, "native update refetches new source without a window or icon rebinding");
        }
        printf("RESULT %d checks, %d failures\n", checks, failures);
    }
    return failures ? 1 : 0;
}
