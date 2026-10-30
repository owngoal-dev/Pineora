#import "TEIconStore.h"
#import "TECompat.h"
#import "TELog.h"

NSString *const TEStoreDidReloadNotification = @"local.apelin.themeengine.store.reloaded";

// 系统路径：/var/mobile 在两种 bootstrap 下都是真实路径，不做前缀转换。
static NSString *const TEPreferencesDirectory = @"/var/mobile/Library/Preferences";
// 证据（Research/evidence/SnowBoardBase.dylib.metadata.txt）：
//   STRING 0x37dc5 /var/mobile/Library/Preferences/com.spark.snowboardprefs.plist
//   STRING 0x37c35 com.spark.snowboardprefs
// SnowBoard 的设置域是 com.spark.snowboardprefs；com.spark.snowboard.plist 作为兜底。
static NSArray<NSString *> *TESnowBoardPreferencesPaths(void) {
    return @[@"/var/mobile/Library/Preferences/com.spark.snowboardprefs.plist",
             @"/var/mobile/Library/Preferences/com.spark.snowboard.plist"];
}

@interface TEIconStore ()
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSArray<TETheme *> *themes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *imageCache;
@property (nonatomic, strong) NSLock *lock;
@end

@implementation TEIconStore

+ (instancetype)sharedStore {
    static TEIconStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[TEIconStore alloc] init];
    });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _themes = @[];
        _enabled = YES;
        _imageCache = [NSMutableDictionary dictionary];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

#pragma mark - 设置

- (NSString *)ownPreferencesPath {
    return [TEPreferencesDirectory stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%s.plist", APELIN_PACKAGE_ID]];
}

- (NSDictionary *)ownPreferences {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:[self ownPreferencesPath]];
    return [prefs isKindOfClass:[NSDictionary class]] ? prefs : @{};
}

- (BOOL)boolPreference:(NSDictionary *)prefs key:(NSString *)key fallback:(BOOL)fallback {
    id value = prefs[key];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

#pragma mark - 目录

- (NSArray<NSString *> *)themeSearchDirectories {
    NSMutableArray<NSString *> *directories = [NSMutableArray array];
    // 主题主目录是 bootstrap 路径。
    NSString *themes = TEBootstrapFilePath(@"/Library/Themes");
    if (themes.length > 0) {
        [directories addObject:themes];
    }
    // 用户可见目录是系统路径。
    [directories addObject:@"/var/mobile/Media/Snowboard/Themes"];
    return directories;
}

/// 把设置里的一项（绝对路径或目录名）解析成存在的主题目录。
- (nullable NSString *)resolveThemeEntry:(NSString *)entry searchDirectories:(NSArray<NSString *> *)searchDirectories {
    if (entry.length == 0) {
        return nil;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if ([entry hasPrefix:@"/"] && [fileManager fileExistsAtPath:entry isDirectory:&isDirectory] && isDirectory) {
        return entry;
    }
    for (NSString *base in searchDirectories) {
        NSString *candidate = [base stringByAppendingPathComponent:entry];
        if ([fileManager fileExistsAtPath:candidate isDirectory:&isDirectory] && isDirectory) {
            return candidate;
        }
    }
    return nil;
}

/// 从 SnowBoard 的设置里读出它已加载的主题路径（兼容已有选择）。
- (NSArray<NSString *> *)snowBoardLoadedThemePaths {
    NSDictionary *prefs = nil;
    for (NSString *path in TESnowBoardPreferencesPaths()) {
        NSDictionary *candidate = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([candidate isKindOfClass:[NSDictionary class]] && candidate.count > 0) {
            prefs = candidate;
            break;
        }
    }
    id loaded = prefs[@"LoadedThemes"];
    if (![loaded isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (id item in (NSArray *)loaded) {
        if ([item isKindOfClass:[NSString class]]) {
            [paths addObject:item];
        } else if ([item isKindOfClass:[NSURL class]]) {
            NSString *path = [(NSURL *)item path];
            if (path.length > 0) {
                [paths addObject:path];
            }
        } else if ([item isKindOfClass:[NSDictionary class]]) {
            // 兼容 SnowBoard 偏好里可能的字典形式（见 THEME/THEME_INFO/THEME_PACK 字符串）。
            for (NSString *key in @[@"ThemePath", @"Path", @"STLPath", @"THEME", @"path"]) {
                id value = ((NSDictionary *)item)[key];
                if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
                    [paths addObject:value];
                    break;
                }
            }
        }
    }
    return paths;
}

#pragma mark - 加载

- (NSInteger)reload {
    NSDictionary *prefs = [self ownPreferences];
    NSArray<NSString *> *searchDirectories = [self themeSearchDirectories];
    self.enabled = [self boolPreference:prefs key:@"Enabled" fallback:YES];
    BOOL importSnowBoard = [self boolPreference:prefs key:@"ImportSnowBoardThemes" fallback:YES];

    NSMutableArray<NSString *> *requested = [NSMutableArray array];
    id configured = prefs[@"Themes"];
    if ([configured isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)configured) {
            if ([item isKindOfClass:[NSString class]]) {
                [requested addObject:item];
            }
        }
    }
    if (requested.count == 0 && importSnowBoard) {
        [requested addObjectsFromArray:[self snowBoardLoadedThemePaths]];
    }
    // 没有任何配置时，自动启用全部发现到的 .theme，便于第一版直接看到效果。
    BOOL autoDiscover = requested.count == 0;
    if (autoDiscover) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        for (NSString *base in searchDirectories) {
            NSArray<NSString *> *entries = [fileManager contentsOfDirectoryAtPath:base error:NULL];
            for (NSString *entry in [entries sortedArrayUsingSelector:@selector(compare:)]) {
                if ([entry.pathExtension.lowercaseString isEqualToString:@"theme"]) {
                    [requested addObject:entry];
                }
            }
        }
    }

    NSMutableArray<TETheme *> *themes = [NSMutableArray array];
    for (NSString *entry in requested) {
        NSString *path = [self resolveThemeEntry:entry searchDirectories:searchDirectories];
        if (path == nil) {
            os_log_error(TELog(), "TEIconStore theme missing: %{public}s", entry.UTF8String);
            continue;
        }
        TETheme *theme = [TETheme themeAtPath:path];
        if (theme != nil) {
            [themes addObject:theme];
        }
    }
    self.themes = themes;
    [self invalidateImageCache];

    os_log(TELog(), "TEIconStore reload enabled=%d themes=%lu autoDiscover=%d",
           self.enabled ? 1 : 0, (unsigned long)themes.count, autoDiscover ? 1 : 0);
    [[NSNotificationCenter defaultCenter] postNotificationName:TEStoreDidReloadNotification object:self];
    return (NSInteger)themes.count;
}

#pragma mark - 取图

- (void)invalidateImageCache {
    [self.lock lock];
    [self.imageCache removeAllObjects];
    [self.lock unlock];
}

- (NSString *)iconPathForBundleIdentifier:(NSString *)bundleIdentifier scale:(NSInteger)scale {
    if (!self.enabled || bundleIdentifier.length == 0) {
        return nil;
    }
    // 主题顺序即优先级：先命中的主题生效。
    for (TETheme *theme in self.themes) {
        NSString *path = [theme iconPathForBundleIdentifier:bundleIdentifier scale:scale];
        if (path.length > 0) {
            return path;
        }
    }
    return nil;
}

- (UIImage *)imageForBundleIdentifier:(NSString *)bundleIdentifier scale:(NSInteger)scale {
    if (bundleIdentifier.length == 0) {
        return nil;
    }
    if (scale < 1) {
        scale = 1;
    }
    NSString *key = [NSString stringWithFormat:@"%@#%ld", bundleIdentifier, (long)scale];
    [self.lock lock];
    UIImage *cached = self.imageCache[key];
    [self.lock unlock];
    if (cached != nil) {
        return cached;
    }

    NSString *path = [self iconPathForBundleIdentifier:bundleIdentifier scale:scale];
    if (path == nil) {
        return nil;
    }
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (image == nil) {
        os_log_error(TELog(), "TEIconStore cannot decode %{public}s", path.UTF8String);
        return nil;
    }
    // imageWithContentsOfFile: 得到 scale 1 的图；按目标倍率重贴，尺寸才正确。
    if (image.scale != (CGFloat)scale) {
        image = [UIImage imageWithCGImage:image.CGImage scale:(CGFloat)scale orientation:UIImageOrientationUp];
    }
    if (image != nil) {
        [self.lock lock];
        self.imageCache[key] = image;
        [self.lock unlock];
    }
    return image;
}

@end
