// 离线自检：不加载 SpringBoard，只用 TETheme 解析一个合成主题目录。
// 编译（在项目根执行）：
//   clang -fobjc-arc -arch arm64e -DAPELIN_PACKAGE_ID='"wiki.qaq.pineora"' \
//     -ISources Research/tools/TEThemeTest.m Sources/TETheme.m \
//     -framework Foundation -o /tmp/tetheme-test && ldid -S /tmp/tetheme-test
#import <Foundation/Foundation.h>
#import "TETheme.h"

static int failures = 0;

static void Expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition) {
        failures++;
    }
}

static void Touch(NSString *path) {
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    [[NSData data] writeToFile:path atomically:YES];
}

static void WritePlist(NSDictionary *dict, NSString *path) {
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    [dict writeToFile:path atomically:YES];
}

int main(void) {
    @autoreleasepool {
        NSString *root = @"/tmp/te-theme-test";
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        NSString *theme = [root stringByAppendingPathComponent:@"Sample.theme"];

        // 现代格式
        Touch([theme stringByAppendingPathComponent:@"IconBundles/com.apple.mobilesafari@2x.png"]);
        Touch([theme stringByAppendingPathComponent:@"IconBundles/com.apple.mobilesafari@3x.png"]);
        Touch([theme stringByAppendingPathComponent:@"IconBundles/com.apple.mobiletimer.png"]);
        // 兼容格式
        WritePlist(@{@"CFBundleIdentifier": @"com.apple.Maps"},
                   [theme stringByAppendingPathComponent:@"Bundles/Maps.bundle/Info.plist"]);
        Touch([theme stringByAppendingPathComponent:@"Bundles/Maps.bundle/AppIcon60x60@3x.png"]);
        // 旧版格式
        Touch([theme stringByAppendingPathComponent:@"com.apple.Preferences/icon@2x.png"]);
        // Info.plist 显式声明
        Touch([theme stringByAppendingPathComponent:@"Extra/Calendar.png"]);
        WritePlist(@{@"CFBundleIdentifier": @"com.zhang.Sample",
                     @"Icons": @{@"com.apple.mobilecal": @[@"Extra/Calendar"]}},
                   [theme stringByAppendingPathComponent:@"Info.plist"]);

        TETheme *parsed = [TETheme themeAtPath:theme];
        Expect(parsed != nil, "主题可解析");
        Expect([parsed.identifier isEqualToString:@"com.zhang.Sample"], "读取 CFBundleIdentifier");
        Expect(parsed.iconPaths.count == 5, "五个 bundle 条目");  // safari/timer/Maps/Preferences/mobilecal
        Expect(!parsed.legacy, "有 IconBundles 不算旧版");

        NSString *safari3 = [parsed iconPathForBundleIdentifier:@"com.apple.mobilesafari" scale:3];
        Expect([safari3.lastPathComponent isEqualToString:@"com.apple.mobilesafari@3x.png"], "3x 精确命中");
        NSString *safari1 = [parsed iconPathForBundleIdentifier:@"com.apple.mobilesafari" scale:1];
        Expect([safari1.lastPathComponent isEqualToString:@"com.apple.mobilesafari@3x.png"], "1x 回退到最大倍率");
        NSString *timer3 = [parsed iconPathForBundleIdentifier:@"com.apple.mobiletimer" scale:3];
        Expect(timer3 != nil, "无倍率后缀的文件任何倍率都可用");

        NSString *maps = [parsed iconPathForBundleIdentifier:@"com.apple.Maps" scale:3];
        Expect([maps.lastPathComponent isEqualToString:@"AppIcon60x60@3x.png"], "Bundles 布局读取 bundle id");
        NSString *mapsFuzzy = [parsed iconPathForBundleIdentifier:@"com.apple.Maps.widget" scale:3];
        Expect(mapsFuzzy != nil, "模糊 bundle id 前缀匹配");

        NSString *prefs = [parsed iconPathForBundleIdentifier:@"com.apple.Preferences" scale:2];
        Expect([prefs.lastPathComponent isEqualToString:@"icon@2x.png"], "旧版目录布局");
        NSString *cal = [parsed iconPathForBundleIdentifier:@"com.apple.mobilecal" scale:1];
        Expect([cal.lastPathComponent isEqualToString:@"Calendar.png"], "Info.plist Icons 声明");

        Expect([parsed iconPathForBundleIdentifier:@"com.apple.nonexistent" scale:3] == nil, "未收录返回 nil");

        // 只有旧版结构的主题
        NSString *legacyTheme = [root stringByAppendingPathComponent:@"Old.theme"];
        Touch([legacyTheme stringByAppendingPathComponent:@"com.apple.mobilemail/appicon@2x.png"]);
        TETheme *legacyParsed = [TETheme themeAtPath:legacyTheme];
        Expect(legacyParsed.legacy, "无 IconBundles 判为旧版");
        Expect([legacyParsed iconPathForBundleIdentifier:@"com.apple.mobilemail" scale:2] != nil, "旧版 appicon 命中");

        Expect([TETheme themeAtPath:[root stringByAppendingPathComponent:@"Missing.theme"]] == nil, "不存在的目录返回 nil");

        printf("\n%d failure(s)\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
