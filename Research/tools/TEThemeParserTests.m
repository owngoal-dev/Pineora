// 仅离线解析测试；所有合成文件及产物写入项目 build/，真实主题只读。
// 在项目根目录编译：
// clang -fobjc-arc -fblocks -arch arm64e -Wall -Wextra -Werror \
//   -DAPELIN_PACKAGE_ID='"local.apelin.themeengine"' -ISources \
//   Research/tools/TEThemeParserTests.m Sources/TETheme.m \
//   -framework Foundation -framework UIKit -o build/TEThemeParserTests
// ldid -SResearch/tools/Tool.entitlements build/TEThemeParserTests
// ./build/TEThemeParserTests
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "TETheme.h"

static NSUInteger failures, checks;
static void Expect(BOOL result, NSString *message) {
    checks++;
    if (!result) failures++;
    printf("%s %s\n", result ? "PASS" : "FAIL", message.UTF8String);
}
static void MakeParent(NSString *path) {
    NSError *error = nil;
    BOOL made = [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                                     withIntermediateDirectories:YES attributes:nil error:&error];
    if (!made) @throw [NSException exceptionWithName:@"FixtureFailure" reason:error.description userInfo:nil];
}
static void Touch(NSString *path) {
    MakeParent(path);
    if (![[NSData data] writeToFile:path atomically:YES])
        @throw [NSException exceptionWithName:@"FixtureFailure" reason:path userInfo:nil];
}
static void Plist(NSDictionary *info, NSString *path) {
    MakeParent(path);
    if (![info writeToFile:path atomically:YES])
        @throw [NSException exceptionWithName:@"FixtureFailure" reason:path userInfo:nil];
}
static NSString *Icon(TETheme *theme, NSString *identifier, NSInteger scale) {
    return [theme iconPathForBundleIdentifier:identifier scale:scale].lastPathComponent;
}
static NSString *Resource(TETheme *theme, NSString *identifier, NSString *name, NSInteger scale) {
    return [theme resourcePathForBundleIdentifier:identifier resourceName:name scale:scale].lastPathComponent;
}
static void Link(NSString *path, NSString *destination) {
    MakeParent(path);
    NSError *error = nil;
    if (![NSFileManager.defaultManager createSymbolicLinkAtPath:path withDestinationPath:destination error:&error])
        @throw [NSException exceptionWithName:@"FixtureFailure" reason:error.description userInfo:nil];
}

int main(void) {
    @autoreleasepool {
        @try {
            NSString *project = NSProcessInfo.processInfo.environment[@"APELIN_PROJECT_ROOT"];
            if (project.length == 0) { fprintf(stderr, "APELIN_PROJECT_ROOT is required\n"); return 2; }
            project = [project.stringByStandardizingPath stringByResolvingSymlinksInPath];
            NSString *build = [[project stringByAppendingPathComponent:@"build"] stringByResolvingSymlinksInPath];
            if (![build hasPrefix:[project stringByAppendingString:@"/"]]) return 2;
            NSString *work = [build stringByAppendingPathComponent:[@"theme-parser-tests-" stringByAppendingString:NSUUID.UUID.UUIDString]];
            NSString *themePath = [work stringByAppendingPathComponent:@"Synthetic.theme"];
            void (^touch)(NSString *) = ^(NSString *relative) { Touch([themePath stringByAppendingPathComponent:relative]); };
            BOOL pad = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
            NSString *device = pad ? @"~ipad" : @"~iphone";
            NSString *other = pad ? @"~iphone" : @"~ipad";

            touch(@"IconBundles/com.test.app-large@3x~iphone.png");
            touch(@"IconBundles/com.test.app-large@3x~ipad.png");
            touch(@"IconBundles/com.test.app@2x~iphone-large.png");
            touch(@"IconBundles/com.test.app@2x~ipad-large.png");
            touch(@"IconBundles/com.test.app@3x.png");
            touch(@"IconBundles/com.test.app.child-large.png");
            touch(@"IconBundles/com.test.app.child.deep-large.png");
            touch(@"IconBundles/com.test.only.child-large.png");
            touch(@"IconBundles/com.test.applarge.png");
            touch(@"IconBundles/com.apple.springboard-large.png");
            touch(@"IconBundles/com.apple.mobileicons.framework-large.png");
            touch(@"Bundles/com.test.noinfo/AppIcon60x60@3x.png");
            touch(@"Bundles/com.test.noinfo/Background@3x.png");
            touch(@"Bundles/com.test.noinfo/AppIconMask@3x.png");
            touch(@"Bundles/com.test.noinfo/IconBadge@3x.png");
            touch(@"Bundles/com.test.noinfo/icon@3x.png");
            touch(@"Bundles/com.test.notapp/Background.png");
            touch(@"Bundles/com.test.notapp/ClockIconBackgroundSquare.png");
            touch(@"Bundles/com.test.notapp/iconography.png");
            touch(@"Bundles/com.test.notapp/AppIconMask.png");
            touch(@"Bundles/com.apple.springboard/ClockIconBackgroundSquare@2x~iphone.png");
            touch(@"Bundles/com.apple.springboard/SBBadgeBG@3x.png");
            touch(@"com.apple.mobileicons.framework/AppIconMask@3x~iphone.png");
            touch(@"com.test.legacy/iconlarge@2x.png");
            touch(@"Folders/com.test.folder/appicon@2x.png");
            touch(@"Bundles/Named.bundle/Primary60@3x.png");
            Plist(@{@"CFBundleIdentifier": @"com.test.declared", @"CFBundleIconFiles": @[@"Primary60"]},
                  [themePath stringByAppendingPathComponent:@"Bundles/Named.bundle/Info.plist"]);

            for (NSString *suffix in @[@"@3x", @"@2x", @""]) {
                for (NSString *idiom in @[device, @"", other])
                    touch([NSString stringWithFormat:@"Bundles/com.test.resources/Probe%@%@.png", suffix, idiom]);
            }
            touch([NSString stringWithFormat:@"Bundles/com.test.resources/Fallback@2x%@.png", device]);
            touch(@"Bundles/com.test.resources/Fallback@3x.png");
            touch(@"Bundles/com.test.resources/Generic@2x.png");
            touch(@"com.test.resources/LegacyOnly@3x.png");
            touch(@"Folders/com.test.resources/FolderOnly@2x.png");
            touch(@"com.test.resources/Probe@3x.png");
            touch(@"Folders/com.test.resources/Probe@3x.png");
            Touch([work stringByAppendingPathComponent:@"outside.png"]);
            Touch([work stringByAppendingPathComponent:@"External.theme/Secret@3x.png"]);
            Link([themePath stringByAppendingPathComponent:@"Bundles/com.test.resources/Escape@3x.png"], @"../../../outside.png");
            Link([themePath stringByAppendingPathComponent:@"Bundles/com.test.external"], @"../../External.theme");
            Link([themePath stringByAppendingPathComponent:@"IconBundles/com.test.symlink-large.png"], @"../../outside.png");
            Plist(@{@"CFBundleIdentifier": @"com.test.theme", @"CustomMetadata": @{@"kept": @YES},
                    @"Icons": @{@"com.test.explicit": @"Extra/Calendar.png",
                                @"com.test.escape": @"../outside.png",
                                @"com.test.absolute": [work stringByAppendingPathComponent:@"outside.png"],
                                @"com.test.escape.listed": @"Bundles/com.test.resources/Escape@3x.png"}},
                  [themePath stringByAppendingPathComponent:@"Info.plist"]);
            touch(@"Extra/Calendar.png");

            TETheme *theme = [TETheme themeAtPath:themePath];
            Expect(theme != nil, @"合成主题可解析");
            Expect([theme.info[@"CustomMetadata"] isEqual:@{@"kept": @YES}], @"info 保留原始元数据");
            Expect([theme.identifier isEqualToString:@"com.test.theme"], @"现有 identifier API 不变");
            Expect(!theme.legacy, @"现有 legacy API 不变");
            Expect([Icon(theme, @"com.test.app", 3) isEqualToString:[NSString stringWithFormat:@"com.test.app-large@3x%@.png", device]], @"-large / @3x / 设备后缀归为精确 ID");
            Expect(theme.iconPaths[@"com.test.app"] != nil && theme.iconPaths[@"com.test.app-large"] == nil, @"-large 不残留在索引键");
            Expect([Icon(theme, @"com.test.app", 2) isEqualToString:[NSString stringWithFormat:@"com.test.app@2x%@-large.png", device]], @"后缀不同排列也可规范化");
            Expect([Icon(theme, @"com.test.app", 1) containsString:@"@3x"], @"指定倍率缺失时回退 3x");
            Expect([Icon(theme, @"com.test.app.child", 3) isEqualToString:@"com.test.app.child-large.png"], @"精确 ID 优先于父前缀且允许倍率回退");
            for (NSUInteger i = 0; i < 20; i++) {
                Expect([Icon(theme, @"com.test.app.child.deep.widget", 3) isEqualToString:@"com.test.app.child.deep-large.png"], @"点边界前缀稳定选择最长 ID");
            }
            Expect(Icon(theme, @"com.test.app2", 3) == nil, @"app 不误命中 app2");
            Expect(Icon(theme, @"com.test.only", 3) == nil, @"不允许反向前缀命中 child");
            Expect(Icon(theme, @"com.test.applarg", 3) == nil, @"不允许截断匹配");
            Expect([Icon(theme, @"com.test.applarge", 1) isEqualToString:@"com.test.applarge.png"], @"没有连字符的 large 不猜测剥离");
            Expect([Icon(theme, @"com.test.noinfo", 3) isEqualToString:@"AppIcon60x60@3x.png"], @"无 Info.plist 的 Bundles ID 目录且 AppIcon 优于 icon");
            Expect(Icon(theme, @"com.test.notapp", 3) == nil, @"背景、Clock、Mask、iconography 不作应用图标");
            Expect(Icon(theme, @"com.apple.springboard", 3) == nil && Icon(theme, @"com.apple.mobileicons.framework", 3) == nil, @"保留资源目录不计为应用");
            Expect([Icon(theme, @"com.test.declared", 3) isEqualToString:@"Primary60@3x.png"], @"保留 .bundle Info 声明的应用图标");
            Expect([Icon(theme, @"com.test.legacy", 2) isEqualToString:@"iconlarge@2x.png"], @"旧 bundleID 目录应用图标");
            Expect([Icon(theme, @"com.test.folder", 2) isEqualToString:@"appicon@2x.png"], @"Folders/bundleID 目录应用图标");
            Expect([Icon(theme, @"com.test.explicit", 1) isEqualToString:@"Calendar.png"], @"保留 Icons 显式主题内声明");
            Expect([Resource(theme, @"com.test.resources", @"Probe", 3) isEqualToString:[NSString stringWithFormat:@"Probe@3x%@.png", device]], @"资源优先 @3x 当前设备");
            Expect([Resource(theme, @"com.test.resources", @"Probe.png", 2) isEqualToString:[NSString stringWithFormat:@"Probe@2x%@.png", device]], @"资源带 png 请求 2x 精确");
            Expect([Resource(theme, @"com.test.resources", @"Probe@2x~iphone.png", 3) isEqualToString:[NSString stringWithFormat:@"Probe@3x%@.png", device]], @"资源输入后缀规范化并使用请求倍率");
            Expect([Resource(theme, @"com.test.resources", @"Fallback", 3) isEqualToString:[NSString stringWithFormat:@"Fallback@2x%@.png", device]], @"资源当前设备 2x 优先通用 3x");
            Expect([Resource(theme, @"com.test.resources", @"Generic", 3) isEqualToString:@"Generic@2x.png"], @"资源通用倍率回退");
            Expect([Resource(theme, @"com.test.resources", @"LegacyOnly", 3) isEqualToString:@"LegacyOnly@3x.png"], @"资源从 Bundles 回退旧目录");
            Expect([Resource(theme, @"com.test.resources", @"FolderOnly", 3) isEqualToString:@"FolderOnly@2x.png"], @"资源回退 Folders 目录");
            Expect(Resource(theme, @"com.test.resources.widget", @"Probe", 3) == nil, @"扩展资源不模糊匹配 bundle ID");
            Expect(Resource(theme, @"../com.test.resources", @"Probe", 3) == nil, @"资源 ID 禁止路径穿越");
            Expect(Resource(theme, @"com.test.resources", @"../outside.png", 3) == nil, @"资源名禁止路径穿越");
            Expect(Resource(theme, @"com.test.resources", [work stringByAppendingPathComponent:@"outside.png"], 3) == nil, @"资源名禁止绝对路径");
            Expect(Resource(theme, @"com.test.resources", @"Escape", 3) == nil, @"资源文件符号链接不能逃出主题");
            Expect(Resource(theme, @"com.test.external", @"Secret", 3) == nil, @"资源目录符号链接不能逃出主题");
            Expect(Icon(theme, @"com.test.escape", 1) == nil && Icon(theme, @"com.test.absolute", 1) == nil &&
                   Icon(theme, @"com.test.escape.listed", 3) == nil && Icon(theme, @"com.test.symlink", 1) == nil, @"Icons 声明与 IconBundles 也遵守路径边界");
            Expect([TETheme themeAtPath:[work stringByAppendingPathComponent:@"Missing.theme"]] == nil, @"不存在的主题返回 nil");

            NSString *realRoot = [project stringByAppendingPathComponent:@"Research/work/viola-white/unpacked/var/jb/Library/Themes"];
            TETheme *viola = [TETheme themeAtPath:[realRoot stringByAppendingPathComponent:@"Viola White.theme"]];
            TETheme *mask = [TETheme themeAtPath:[realRoot stringByAppendingPathComponent:@"Viola White Mask.theme"]];
            TETheme *badge = [TETheme themeAtPath:[realRoot stringByAppendingPathComponent:@"Viola White Badges.theme"]];
            Expect(viola && mask && badge, @"三个真实 Viola White 主题可只读解析");
            Expect(viola.iconPaths.count == 1957, @"真实 Viola White 1957 个图标，不额外计入 SpringBoard");
            Expect(mask.iconPaths.count == 0 && badge.iconPaths.count == 0, @"真实遮罩与角标主题应用图标数为零");
            Expect([viola.info[@"PackageName"] isEqualToString:@"Viola White"], @"真实原始元数据可读");
            Expect([Icon(viola, @"com.apple.mobilesafari", 3) isEqualToString:@"com.apple.mobilesafari-large.png"], @"真实 -large Safari 精确解析");
            Expect([Resource(viola, @"com.apple.springboard", @"ClockIconHourHand", 3) isEqualToString:@"ClockIconHourHand@3x.png"], @"真实扩展资源一：Clock 指针");
            Expect([Resource(viola, @"com.apple.springboard", @"ClockIconBackgroundSquare", 3) isEqualToString:[NSString stringWithFormat:@"ClockIconBackgroundSquare@2x%@.png", device]], @"真实 Clock 背景设备倍率回退");
            Expect([Resource(mask, @"com.apple.mobileicons.framework", @"AppIconMask", 3) isEqualToString:[NSString stringWithFormat:@"AppIconMask@3x%@.png", device]], @"真实扩展资源二：旧目录遮罩");
            Expect([Resource(badge, @"com.apple.springboard", @"SBBadgeBG", 3) isEqualToString:@"SBBadgeBG@3x.png"], @"真实扩展资源三：角标");
            printf("REAL_COUNTS icons=%lu mask=%lu badge=%lu\n", (unsigned long)viola.iconPaths.count,
                   (unsigned long)mask.iconPaths.count, (unsigned long)badge.iconPaths.count);
            printf("FIXTURES %s\n", [work substringFromIndex:project.length + 1].UTF8String);
        } @catch (NSException *exception) {
            fprintf(stderr, "Fixture/test exception: %s\n", exception.reason.UTF8String);
            return 2;
        }
        printf("RESULT %lu checks, %lu failures\n", (unsigned long)checks, (unsigned long)failures);
    }
    return failures ? 1 : 0;
}
