// 仅在独立进程创建离屏 UIImageView；不安装 Hook、不显示窗口、不读写屏幕。
#import "../../Sources/TEExtensions.m"
#import <dlfcn.h>
NSString *TEBootstrapFilePath(NSString *path) { return ApelinBootstrapPath(path); }
void MSHookMessageEx(Class cls, SEL cmd, IMP hook, IMP *original) {
    (void)cls; (void)cmd; (void)hook; (void)original;
    abort(); // 本测试不应安装任何 Hook。
}
static int checks, failures;
static void Check(BOOL result, const char *message) { checks++; if (!result) failures++; printf("%s %s\n", result ? "PASS" : "FAIL", message); }
static UIImage *Solid(UIColor *color) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(20, 20)] imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [color setFill]; UIRectFill(CGRectMake(0, 0, 20, 20));
    }];
}
static CGRect OpaqueBounds(UIImage *image) {
    size_t width = CGImageGetWidth(image.CGImage), height = CGImageGetHeight(image.CGImage);
    NSMutableData *data = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, width, height, 8, width * 4,
        space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image.CGImage);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    const unsigned char *bytes = data.bytes;
    CGRect result = CGRectNull;
    for (size_t y = 0; y < height; y++) {
        for (size_t x = 0; x < width; x++) {
            if (bytes[(y * width + x) * 4 + 3] > 127)
                result = CGRectUnion(result, CGRectMake(x, y, 1, 1));
        }
    }
    return result;
}

static void CheckClockLayers(void) {
    void *framework = dlopen("/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome", RTLD_LAZY | RTLD_GLOBAL);
    Class cls = NSClassFromString(@"SBHClockApplicationIconImageView");
    Check(framework && cls, "本机系统时钟工厂可用（不创建窗口）");
    if (!framework || !cls) return;
    const char *root = getenv("APELIN_PROJECT_ROOT");
    Check(root && *root, "测试资源根目录可用");
    if (!root || !*root) return;
    NSString *directory = [@(root) stringByAppendingPathComponent:
        @"Research/work/viola-white/unpacked/var/jb/Library/Themes/Viola White.theme/Bundles/com.apple.springboard"];
    NSArray *selectors = @[@"makeHoursHandLayerWithImageSet:", @"makeMinutesHandLayerWithImageSet:", @"makeSecondsHandLayerWithImageSet:"];
    NSArray *resources = @[@"ClockIconHourHand", @"ClockIconMinuteHand", @"ClockIconSecondHand"];
    for (NSNumber *size in @[@60, @80]) {
        TEIconImageInfo info = {CGSizeMake(size.doubleValue, size.doubleValue), 3, 13.5};
        // 不依赖私有 metrics 字段布局；对齐缓冲区足够容纳已探测的结构。
        double metrics[128] = {0};
        ((void (*)(id, SEL, void *, TEIconImageInfo))objc_msgSend)(cls,
            NSSelectorFromString(@"getMetrics:forIconImageInfo:"), metrics, info);
        id images = ((id (*)(id, SEL, void *))objc_msgSend)(cls,
            NSSelectorFromString(@"imageSetForMetrics:"), metrics);
        for (NSUInteger i = 0; i < selectors.count; i++) {
            CALayer *layer = ((id (*)(id, SEL, id))objc_msgSend)(cls, NSSelectorFromString(selectors[i]), images);
            NSString *path = [directory stringByAppendingPathComponent:[resources[i] stringByAppendingString:@"@3x.png"]];
            UIImage *raw = [UIImage imageWithContentsOfFile:path];
            Check(raw.CGImage != NULL && layer != nil, "真实指针素材和原生图层均可用");
            if (!raw.CGImage || !layer) continue;
            UIImage *fixed = TEClockLayerImage(raw, layer.bounds.size, info.scale);
            CGRect opaque = OpaqueBounds(fixed);
            CGFloat expectedWidth = opaque.size.height * raw.size.width / raw.size.height;
            Check(fabs(opaque.size.width - expectedWidth) < 2, "60pt/80pt 指针保留素材宽高比，不横向拉粗");
            CGFloat canvasWidth = CGImageGetWidth(fixed.CGImage);
            Check(fabs(CGRectGetMidX(opaque) - canvasWidth / 2) <= 0.5, "细指针在原生旋转画布内居中");
            Check(CGImageGetWidth(fixed.CGImage) == (size_t)lround(layer.bounds.size.width * 3) &&
                  CGImageGetHeight(fixed.CGImage) == (size_t)lround(layer.bounds.size.height * 3), "输出画布与原生图层像素尺寸一致");
            Check(TEClockLayerImage(raw, layer.bounds.size, info.scale) == fixed, "每秒布局复用指针贴图缓存");
            UIImage *old = TEResizeImage(raw, layer.bounds.size, info.scale);
            if (i < 2) Check(OpaqueBounds(old).size.width > opaque.size.width * 2,
                "旧铺满路径确实把真实时针、分针拉粗两倍以上");
        }
    }
    Check(TEClockLayerImage(nil, CGSizeMake(10, 30), 3) == nil, "缺少资源回退原生指针");
    Check(TEClockLayerImage(Solid(UIColor.redColor), CGSizeZero, 3) == nil, "空图层安全回退");
    Check(TEClockLayerImage(Solid(UIColor.redColor), CGSizeMake(NAN, 30), 3) == nil, "非法图层尺寸安全回退");
    UIImage *dot = TEClockLayerImage(Solid(UIColor.redColor), CGSizeMake(9, 12), 3);
    CGRect dotBounds = OpaqueBounds(dot);
    Check(fabs(dotBounds.size.width - dotBounds.size.height) <= 1, "中心点等比例绘制（半像素边界取整误差不超过 1px）");
}

int main(void) {
    @autoreleasepool {
        UIImage *original = Solid(UIColor.whiteColor), *replacement = Solid(UIColor.redColor), *systemUpdate = Solid(UIColor.greenColor);
        UIImageView *view = [[UIImageView alloc] initWithImage:original];
        TEOverrideImage(view, replacement);
        Check(view.image == replacement, "视图接入主题图片");
        TEOverrideImage(view, nil);
        Check(view.image == original, "停用恢复原图");
        TEOverrideImage(view, replacement); view.image = systemUpdate;
        TEOverrideImage(view, nil);
        Check(view.image == systemUpdate, "停用不覆盖系统后来更新的图片");
        view.image = original;
        TEApplyBadgeTextColor(view, @{@"TextColor":@"#123456"});
        UIImage *tinted = view.image;
        Check(tinted != original, "已缓存原生文字也能生成主题着色副本");
        TEApplyBadgeTextColor(view, @{@"TextColor":@"#123456"});
        Check(view.image == tinted, "重复布局复用文字着色图");
        TEApplyBadgeTextColor(view, @{@"TextColor":@"#654321"});
        Check(view.image != tinted, "切换文字颜色更新副本");
        TEApplyBadgeTextColor(view, @{});
        Check(view.image == original, "停用文字颜色恢复原生缓存图");
        view.frame = CGRectMake(10, 10, 20, 20);
        TEApplyTextOffset(view, @{@"TextXoffset":@2,@"TextYoffset":@3});
        Check(view.frame.origin.x == 12 && view.frame.origin.y == 13, "主题文字位置偏移生效");
        TEApplyTextOffset(view, @{@"TextXoffset":@2,@"TextYoffset":@3});
        Check(view.frame.origin.x == 12 && view.frame.origin.y == 13, "反复布局不累计偏移");
        TEApplyTextOffset(view, @{});
        Check(view.frame.origin.x == 10 && view.frame.origin.y == 10, "停用位置偏移恢复基准");
        view.frame = CGRectMake(30, 40, 20, 20);
        TEApplyTextOffset(view, @{@"TextXoffset":@2});
        Check(view.frame.origin.x == 32 && view.frame.origin.y == 40, "系统重新布局后使用新基准");
        CheckClockLayers();
        printf("RESULT %d checks, %d failures\n", checks, failures);
    }
    return failures ? 1 : 0;
}
