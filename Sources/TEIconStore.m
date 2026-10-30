#import "TEIconStore.h"
#import "TECompat.h"
#import "TELog.h"
#import "TERenderer.h"

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
@property (atomic, assign) BOOL enabled;
@property (atomic, copy) NSArray<TETheme *> *themes;
@property (nonatomic, strong) NSCache<NSString *, id> *imageCache;
@property (nonatomic, strong) NSLock *lock;
@property (nonatomic, strong) NSCache<NSString *, id> *resourceCache;
@property (nonatomic, assign) NSUInteger generation;
@end

static NSUInteger TEImageCost(UIImage *image) {
    return image.CGImage ? CGImageGetBytesPerRow(image.CGImage) * CGImageGetHeight(image.CGImage) : 0;
}

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
        _imageCache = [NSCache new];
        _imageCache.name = @"Pineora.rendered";
        _imageCache.totalCostLimit = 24 * 1024 * 1024;
        _imageCache.countLimit = 512;
        _lock = [[NSLock alloc] init];
        _resourceCache = [NSCache new];
        _resourceCache.name = @"Pineora.resources";
        _resourceCache.totalCostLimit = 4 * 1024 * 1024;
        _resourceCache.countLimit = 128;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(teMemoryWarning:)
            name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

#pragma mark - 设置

- (void)teMemoryWarning:(NSNotification *)notification {
    (void)notification;
    [self invalidateImageCache];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

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
    BOOL hasSelection = [configured isKindOfClass:[NSArray class]];
    if (!hasSelection && requested.count == 0 && importSnowBoard) {
        [requested addObjectsFromArray:[self snowBoardLoadedThemePaths]];
    }
    // 没有任何配置时，自动启用全部发现到的 .theme，便于第一版直接看到效果。
    BOOL autoDiscover = !hasSelection && requested.count == 0;
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
    [self.resourceCache removeAllObjects];
    self.generation++;
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

- (NSDictionary *)settingsForKey:(NSString *)key {
    if (!self.enabled) return @{};
    for (TETheme *theme in self.themes) {
        id value = theme.info[key];
        if ([value isKindOfClass:NSDictionary.class]) return value;
    }
    return @{};
}

- (UIImage *)rawResourceForBundleIdentifier:(NSString *)bundleIdentifier name:(NSString *)name scale:(NSInteger)scale {
    if (!self.enabled) return nil;
    NSString *key = [NSString stringWithFormat:@"raw:%@:%@:%ld", bundleIdentifier, name, (long)scale];
    [self.lock lock];
    id cached = [self.resourceCache objectForKey:key];
    NSUInteger generation = self.generation;
    [self.lock unlock];
    if (cached) return cached == NSNull.null ? nil : cached;
    UIImage *image = nil;
    for (TETheme *theme in self.themes) {
        NSString *path = [theme resourcePathForBundleIdentifier:bundleIdentifier resourceName:name scale:scale];
        if (!path) continue;
        image = [UIImage imageWithContentsOfFile:path];
        if (!image.CGImage) continue;
        NSRange at = [path.lastPathComponent rangeOfString:@"@" options:NSBackwardsSearch];
        NSInteger sourceScale = at.location == NSNotFound ? 1 : [[path.lastPathComponent substringFromIndex:at.location + 1] integerValue];
        sourceScale = MAX(1, MIN(sourceScale, 4));
        image = [UIImage imageWithCGImage:image.CGImage scale:sourceScale orientation:UIImageOrientationUp];
        break;
    }
    [self.lock lock];
    if (generation == self.generation) [self.resourceCache setObject:image ?: (id)NSNull.null forKey:key cost:TEImageCost(image)];
    [self.lock unlock];
    return image;
}

- (UIImage *)resourceImageForBundleIdentifier:(NSString *)bundleIdentifier name:(NSString *)name size:(CGSize)size scale:(CGFloat)scale {
    if (!self.enabled || !isfinite(size.width) || !isfinite(size.height) || size.width <= 0 || size.height <= 0 || size.width > 512 || size.height > 512) return nil;
    scale = isfinite(scale) ? MAX(1, MIN(scale, 4)) : 3;
    NSString *key = [NSString stringWithFormat:@"resource:%@:%@:%g:%g:%g", bundleIdentifier, name, size.width, size.height, scale];
    [self.lock lock];
    id cached = [self.imageCache objectForKey:key];
    NSUInteger generation = self.generation;
    [self.lock unlock];
    if (cached) return cached == NSNull.null ? nil : cached;
    UIImage *raw = [self rawResourceForBundleIdentifier:bundleIdentifier name:name scale:(NSInteger)lround(scale)];
    if (!raw) return nil;
    UIImage *result = TEResizeImage(raw, size, scale);
    [self.lock lock];
    if (generation == self.generation) [self.imageCache setObject:result forKey:key cost:TEImageCost(result)];
    [self.lock unlock];
    return result;
}

- (UIImage *)imageForBundleIdentifier:(NSString *)bundleIdentifier scale:(NSInteger)scale {
    return [self imageForBundleIdentifier:bundleIdentifier size:CGSizeMake(60, 60)
                                  scale:scale cornerRadius:13.5 masked:YES];
}

- (UIImage *)imageForBundleIdentifier:(NSString *)bundleIdentifier size:(CGSize)size
    scale:(CGFloat)scale cornerRadius:(CGFloat)cornerRadius masked:(BOOL)masked {
    if (!self.enabled || bundleIdentifier.length == 0 || !isfinite(size.width) || !isfinite(size.height) ||
        size.width <= 0 || size.height <= 0 || size.width > 512 || size.height > 512) return nil;
    // 动态时钟由系统的实时视图处理，不能用带静态指针的 PNG 覆盖它。
    if ([bundleIdentifier isEqualToString:@"com.apple.mobiletimer"]) return nil;
    scale = isfinite(scale) ? MAX(1, MIN(scale, 4)) : 3;
    cornerRadius = isfinite(cornerRadius) ? MAX(0, cornerRadius) : 0;
    BOOL calendar = [bundleIdentifier isEqualToString:@"com.apple.mobilecal"];
    NSDate *date = calendar ? NSDate.date : nil;
    NSDateComponents *parts = calendar ? [NSCalendar.currentCalendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date] : nil;
    NSString *day = calendar ? [NSString stringWithFormat:@"%ld-%ld-%ld:%@:%@", (long)parts.year, (long)parts.month,
        (long)parts.day, NSTimeZone.localTimeZone.name, NSLocale.currentLocale.localeIdentifier] : @"";
    NSString *key = [NSString stringWithFormat:@"icon:%@:%g:%g:%g:%g:%d:%@", bundleIdentifier, size.width, size.height, scale, cornerRadius, masked, day];
    [self.lock lock];
    id cached = [self.imageCache objectForKey:key];
    NSUInteger generation = self.generation;
    [self.lock unlock];
    if (cached) return cached == NSNull.null ? nil : cached;
    UIImage *source = nil;
    BOOL shouldMask = masked;
    for (TETheme *theme in self.themes) {
        NSString *path = [theme iconPathForBundleIdentifier:bundleIdentifier scale:(NSInteger)lround(scale)];
        if (path == nil) continue;
        source = [UIImage imageWithContentsOfFile:path];
        if (source == nil) continue;
        id maskPreference = theme.info[@"IB-MaskIcons"];
        if ([maskPreference isKindOfClass:NSNumber.class] && ![maskPreference boolValue]) shouldMask = NO;
        break;
    }
    if (!source) {
        [self.lock lock];
        if (generation == self.generation) [self.imageCache setObject:NSNull.null forKey:key cost:0];
        [self.lock unlock];
        return nil;
    }
    UIImage *mask = shouldMask ? [self rawResourceForBundleIdentifier:@"com.apple.mobileicons.framework" name:@"AppIconMask" scale:(NSInteger)lround(scale)] : nil;
    UIImage *image = TERenderIcon(source, size, scale, cornerRadius, shouldMask, mask,
        calendar ? [self settingsForKey:@"CalendarIconDateSettings"] : nil,
        calendar ? [self settingsForKey:@"CalendarIconDaySettings"] : nil, date);
    [self.lock lock];
    if (generation == self.generation) [self.imageCache setObject:image forKey:key cost:TEImageCost(image)];
    [self.lock unlock];
    return image;
}

@end
