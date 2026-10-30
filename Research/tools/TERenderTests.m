// 离线渲染回归：只读项目中的真实主题，图片输出留在 build/，不触碰屏幕。
#import <UIKit/UIKit.h>
#import "TERenderer.h"
#import "TEIconStore.h"
#import "ApelinBootstrap.h"

NSString *TEBootstrapFilePath(NSString *path) { return ApelinBootstrapPath(path); }

@interface TERenderTestStore : TEIconStore
@property (nonatomic, copy) NSString *fixtureDirectory;
@property (nonatomic, copy) NSDictionary *fixturePreferences;
@end
@implementation TERenderTestStore
- (NSArray *)themeSearchDirectories { return @[self.fixtureDirectory]; }
- (NSDictionary *)ownPreferences { return self.fixturePreferences ?: @{}; }
@end

static int checks, failures;
static void Check(BOOL result, const char *name) { checks++; if (!result) failures++; printf("%s %s\n", result ? "PASS" : "FAIL", name); }
static NSData *Pixels(UIImage *image) {
    if (!image.CGImage) return nil;
    size_t width = CGImageGetWidth(image.CGImage), height = CGImageGetHeight(image.CGImage);
    NSMutableData *data = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, width, height, 8, width * 4, color, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image.CGImage);
    CGContextRelease(context); CGColorSpaceRelease(color);
    return data;
}
static int Alpha(UIImage *image, NSUInteger x, NSUInteger y) {
    NSData *data = Pixels(image);
    NSUInteger width = CGImageGetWidth(image.CGImage);
    return ((const unsigned char *)data.bytes)[(y * width + x) * 4 + 3];
}
static NSUInteger ColoredPixels(UIImage *image) {
    NSData *data = Pixels(image);
    const unsigned char *bytes = data.bytes;
    NSUInteger count = 0;
    for (NSUInteger i = 0; i + 3 < data.length; i += 4) {
        if (bytes[i + 3] > 200 && (abs((int)bytes[i] - bytes[i+1]) > 30 || abs((int)bytes[i] - bytes[i+2]) > 30)) count++;
    }
    return count;
}
int main(void) {
    @autoreleasepool {
        const char *environment = getenv("APELIN_PROJECT_ROOT");
        if (!environment || !*environment) return 2;
        NSString *root = @(environment);
        NSString *directory = [root stringByAppendingPathComponent:@"Research/work/viola-white/unpacked/var/jb/Library/Themes"];
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(60, 60)];
        UIImage *white = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) { [UIColor.whiteColor setFill]; UIRectFill(CGRectMake(0, 0, 60, 60)); }];
        UIImage *rounded = TERenderIcon(white, CGSizeMake(60, 60), 3, 13.5, YES, nil, nil, nil, nil);
        UIImage *square = TERenderIcon(white, CGSizeMake(60, 60), 3, 13.5, NO, nil, nil, nil, nil);
        Check(CGImageGetWidth(rounded.CGImage) == 180 && rounded.scale == 3 && rounded.size.width == 60, "图标统一为 60pt / 180px / 3x");
        Check(Alpha(rounded, 0, 0) == 0 && Alpha(rounded, 90, 90) == 255, "默认圆角四角透明、中心不透明");
        Check(Alpha(square, 0, 0) == 255, "未蒙版入口保留原始方图");
        TERenderTestStore *store = [TERenderTestStore new];
        store.fixtureDirectory = directory;
        store.fixturePreferences = @{@"Themes":@[@"Viola White Mask.theme", @"Viola White Badges.theme", @"Viola White.theme"]};
        Check([store reload] == 3, "解析并启用三个真实主题");
        UIImage *mask = [store rawResourceForBundleIdentifier:@"com.apple.mobileicons.framework" name:@"AppIconMask" scale:3];
        UIImage *masked = TERenderIcon(white, CGSizeMake(60, 60), 3, 0, YES, mask, nil, nil, nil);
        Check(mask != nil && Alpha(masked, 0, 0) == 0 && Alpha(masked, 90, 90) == 255, "真实 AppIconMask 的 alpha 正确应用");
        UIImage *safari = [store imageForBundleIdentifier:@"com.apple.mobilesafari" scale:3];
        Check(safari != nil && Alpha(safari, 0, 0) == 0 && safari.size.width == 60, "Safari 精确匹配且输出已蒙版尺寸");
        Check([store imageForBundleIdentifier:@"com.apple.mobilesafari.fake2" scale:3] != nil, "点边界子 bundle 可回退父图标");
        Check([store imageForBundleIdentifier:@"com.apple.mobilesafariFake" scale:3] == nil, "非点边界不误匹配其它图标");
        Check([store imageForBundleIdentifier:@"com.apple.mobiletimer" scale:3] == nil, "时钟不返回带静态指针的 PNG");
        UIImage *badge = [store rawResourceForBundleIdentifier:@"com.apple.springboard" name:@"SBBadgeBG" scale:3];
        Check(badge != nil && badge.size.width == 24 && badge.scale == 3, "角标 72px 资源恢复为 24pt / 3x");
        UIImage *hand = [store resourceImageForBundleIdentifier:@"com.apple.springboard" name:@"ClockIconHourHand" size:CGSizeMake(3, 29) scale:3];
        Check(hand != nil && CGImageGetWidth(hand.CGImage) == 9 && CGImageGetHeight(hand.CGImage) == 87, "动态时钟指针按系统图层尺寸归一化");
        NSDictionary *settings = [store settingsForKey:@"CalendarIconDateSettings"];
        Check([settings[@"FontSize"] integerValue] == 30 && [settings[@"TextColor"] isEqual:@"#6A71D7"], "独立日历样式遵循已启用主题优先级");
        Check([TEFontFromSettings(@{@"FontSize":@14,@"FontWeight":@"Bold"}, [UIFont systemFontOfSize:12]) pointSize] == 14, "主题字体大小与粗体设置可解析");
        Check(TEColorFromSettings(@"not-a-color", UIColor.redColor) == UIColor.redColor, "非法颜色回退默认值");
        NSDateComponents *components = [NSDateComponents new]; components.year = 2026; components.month = 10; components.day = 30; components.hour = 12;
        NSDate *date = [NSCalendar.currentCalendar dateFromComponents:components];
        NSDictionary *dateStyle = @{@"FontSize":@30, @"FontWeight":@"Bold", @"TextColor":@"#FD9351", @"TextYoffset":@3};
        NSDictionary *hidden = @{@"FontSize":@0};
        UIImage *calendar = TERenderIcon(white, CGSizeMake(60, 60), 3, 13.5, YES, mask, dateStyle, hidden, date);
        Check(ColoredPixels(calendar) > 100, "日历不是空白图，确实绘制主题色日期");
        UIImage *tomorrow = TERenderIcon(white, CGSizeMake(60, 60), 3, 13.5, YES, mask, dateStyle, hidden, [date dateByAddingTimeInterval:86400]);
        Check(![Pixels(calendar) isEqual:Pixels(tomorrow)], "日期变化产生不同图像");
        UIImage *noText = TERenderIcon(white, CGSizeMake(60, 60), 3, 13.5, YES, mask, hidden, hidden, date);
        Check([Pixels(noText) isEqual:Pixels(masked)], "FontSize=0 隐藏日期和星期文字");
        Check([store imageForBundleIdentifier:@"com.apple.mobilecal" scale:3] != nil, "真实日历背景和配置完成组合");
        NSCache *cache = [store valueForKey:@"imageCache"];
        Check(cache.totalCostLimit == 24 * 1024 * 1024 && cache.countLimit == 512, "渲染缓存配置了成本与条目上限");
        Check([cache objectForKey:@"icon:com.apple.mobilesafariFake:60:60:3:13.5:1:"] == NSNull.null, "缺失图标加入负缓存避免重复扫描");
        [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        Check([cache objectForKey:@"icon:com.apple.mobilesafariFake:60:60:3:13.5:1:"] == nil, "内存警告清除图片与负缓存");
        Check([store imageForBundleIdentifier:@"com.apple.mobilesafari" scale:3] != nil, "内存警告后图标可重新渲染");
        store.fixturePreferences = @{@"Themes":@[]};
        Check([store reload] == 0, "停用全部不触发自动启用");
        Check([store rawResourceForBundleIdentifier:@"com.apple.springboard" name:@"SBBadgeBG" scale:3] == nil, "停用角标后资源缓存清空");
        store.fixturePreferences = @{@"Enabled":@NO,@"Themes":@[@"Viola White.theme"]};
        [store reload];
        Check([store imageForBundleIdentifier:@"com.apple.mobilesafari" scale:3] == nil, "关闭总开关恢复系统取图");
        NSString *output = [root stringByAppendingPathComponent:@"build/RenderRegression"];
        [NSFileManager.defaultManager createDirectoryAtPath:output withIntermediateDirectories:YES attributes:nil error:NULL];
        [UIImagePNGRepresentation(safari) writeToFile:[output stringByAppendingPathComponent:@"safari-masked.png"] atomically:YES];
        [UIImagePNGRepresentation(calendar) writeToFile:[output stringByAppendingPathComponent:@"calendar-day30.png"] atomically:YES];
        printf("RESULT %d checks, %d failures\n", checks, failures);
    }
    return failures ? 1 : 0;
}
