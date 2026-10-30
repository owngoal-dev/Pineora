#import "PineoraStore.h"
#import "ApelinBootstrap.h"
#import "TETheme.h"
#import <notify.h>

static const CGFloat kPineoraPreviewSize = 29;

// 预览优先用这几个常见图标，都没有时取排序后的第一个。
static NSArray<NSString *> *PineoraPreviewBundleIdentifiers(void) {
    return @[@"com.apple.mobilesafari", @"com.apple.Preferences", @"com.apple.mobilephone", @"com.apple.camera"];
}

static NSString *PineoraPreferencesPath(void) {
    return [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%s.plist", APELIN_PACKAGE_ID];
}

// 与 TEIconStore 的兜底顺序一致。
static NSArray<NSString *> *PineoraSnowBoardPreferencesPaths(void) {
    return @[@"/var/mobile/Library/Preferences/com.spark.snowboardprefs.plist",
             @"/var/mobile/Library/Preferences/com.spark.snowboard.plist"];
}

@interface PineoraThemeItem ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *title;
@end

@implementation PineoraThemeItem
@end

@interface PineoraStore ()
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSArray<PineoraThemeItem *> *activeThemes;
@property (nonatomic, copy) NSArray<PineoraThemeItem *> *inactiveThemes;
@property (nonatomic, assign) BOOL hasExplicitSelection;
@property (nonatomic, copy) NSArray<NSString *> *missingThemeNames;
@property (nonatomic, assign) BOOL hasUnappliedChanges;
@property (nonatomic, copy) NSArray<NSString *> *searchDirectories;
@property (nonatomic, copy) NSArray<PineoraThemeItem *> *allThemes;
@end

@implementation PineoraStore

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _enabled = YES;
        _activeThemes = @[];
        _inactiveThemes = @[];
        _missingThemeNames = @[];
        _allThemes = @[];
        // 与 -[TEIconStore themeSearchDirectories] 相同：bootstrap 路径 + 系统路径。
        NSMutableArray<NSString *> *directories = [NSMutableArray array];
        NSString *themes = ApelinBootstrapPath(@"/Library/Themes");
        if (themes.length > 0) {
            [directories addObject:themes];
        }
        [directories addObject:@"/var/mobile/Media/Snowboard/Themes"];
        _searchDirectories = [directories copy];
    }
    return self;
}

#pragma mark - 读

- (NSDictionary *)readPreferences {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PineoraPreferencesPath()];
    return [prefs isKindOfClass:[NSDictionary class]] ? prefs : @{};
}

- (NSArray<PineoraThemeItem *> *)discoverThemes {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray<PineoraThemeItem *> *themes = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *base in self.searchDirectories) {
        NSArray<NSString *> *entries = [fileManager contentsOfDirectoryAtPath:base error:NULL];
        for (NSString *entry in [entries sortedArrayUsingSelector:@selector(compare:)]) {
            if (![entry.pathExtension.lowercaseString isEqualToString:@"theme"] || [seen containsObject:entry]) {
                continue;  // 同名时引擎按目录顺序取第一个，这里一样。
            }
            NSString *path = [base stringByAppendingPathComponent:entry];
            BOOL isDirectory = NO;
            if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
                continue;
            }
            [seen addObject:entry];
            PineoraThemeItem *item = [PineoraThemeItem new];
            item.name = entry;
            item.path = path;
            item.title = entry.stringByDeletingPathExtension;
            item.iconCount = -1;
            [themes addObject:item];
        }
    }
    return themes;
}

/// 与 -[TEIconStore resolveThemeEntry:searchDirectories:] 相同的解析。
- (nullable PineoraThemeItem *)themeForEntry:(NSString *)entry {
    if (entry.length == 0) {
        return nil;
    }
    NSString *resolved = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if ([entry hasPrefix:@"/"] && [fileManager fileExistsAtPath:entry isDirectory:&isDirectory] && isDirectory) {
        resolved = entry;
    } else {
        for (NSString *base in self.searchDirectories) {
            NSString *candidate = [base stringByAppendingPathComponent:entry];
            if ([fileManager fileExistsAtPath:candidate isDirectory:&isDirectory] && isDirectory) {
                resolved = candidate;
                break;
            }
        }
    }
    if (resolved == nil) {
        return nil;
    }
    for (PineoraThemeItem *item in self.allThemes) {
        if ([item.path isEqualToString:resolved]) {
            return item;
        }
    }
    return nil;
}

- (NSArray<NSString *> *)snowBoardLoadedThemeEntries {
    for (NSString *path in PineoraSnowBoardPreferencesPaths()) {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
        if (![prefs isKindOfClass:[NSDictionary class]] || prefs.count == 0) {
            continue;
        }
        id loaded = prefs[@"LoadedThemes"];
        if (![loaded isKindOfClass:[NSArray class]]) {
            return @[];
        }
        NSMutableArray<NSString *> *entries = [NSMutableArray array];
        for (id item in (NSArray *)loaded) {
            if ([item isKindOfClass:[NSString class]]) {
                [entries addObject:item];
            } else if ([item isKindOfClass:[NSDictionary class]]) {
                for (NSString *key in @[@"ThemePath", @"Path", @"STLPath", @"THEME", @"path"]) {
                    id value = ((NSDictionary *)item)[key];
                    if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
                        [entries addObject:value];
                        break;
                    }
                }
            }
        }
        return entries;
    }
    return @[];
}

- (void)reload {
    NSDictionary *prefs = [self readPreferences];
    id enabled = prefs[@"Enabled"];
    // 直接写 ivar：-setEnabled: 会写盘。
    _enabled = [enabled isKindOfClass:[NSNumber class]] ? [enabled boolValue] : YES;
    self.allThemes = [self discoverThemes];

    NSMutableArray<NSString *> *configured = [NSMutableArray array];
    id themes = prefs[@"Themes"];
    if ([themes isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)themes) {
            if ([item isKindOfClass:[NSString class]] && [item length] > 0) {
                [configured addObject:item];
            }
        }
    }
    self.hasExplicitSelection = [themes isKindOfClass:[NSArray class]];

    // 没有显式选择时，复现引擎的兜底：SnowBoard 的 LoadedThemes，再没有就是全部主题。
    NSArray<NSString *> *entries = configured;
    if (!self.hasExplicitSelection && entries.count == 0) {
        id import = prefs[@"ImportSnowBoardThemes"];
        BOOL importSnowBoard = [import isKindOfClass:[NSNumber class]] ? [import boolValue] : YES;
        entries = importSnowBoard ? [self snowBoardLoadedThemeEntries] : @[];
    }
    NSMutableArray<PineoraThemeItem *> *active = [NSMutableArray array];
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    if (!self.hasExplicitSelection && entries.count == 0) {
        [active addObjectsFromArray:self.allThemes];
    } else {
        for (NSString *entry in entries) {
            PineoraThemeItem *item = [self themeForEntry:entry];
            if (item == nil) {
                if (self.hasExplicitSelection) {
                    [missing addObject:entry];
                }
            } else if (![active containsObject:item]) {
                [active addObject:item];
            }
        }
    }
    self.activeThemes = active;
    self.missingThemeNames = missing;
    [self refreshInactive];
    NSLog(@"[PineoraPrefs] reload enabled=%d explicit=%d active=%lu all=%lu missing=%lu",
          self.enabled, self.hasExplicitSelection, (unsigned long)active.count,
          (unsigned long)self.allThemes.count, (unsigned long)missing.count);
}

- (void)refreshInactive {
    NSMutableArray<PineoraThemeItem *> *inactive = [NSMutableArray array];
    for (PineoraThemeItem *item in self.allThemes) {
        if (![self.activeThemes containsObject:item]) {
            [inactive addObject:item];
        }
    }
    self.inactiveThemes = inactive;
}

#pragma mark - 详情

static UIImage *PineoraRoundedPreview(UIImage *image) {
    CGFloat side = kPineoraPreviewSize;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context;
        CGRect rect = CGRectMake(0, 0, side, side);
        [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:side * 0.225] addClip];
        [image drawInRect:rect];
    }];
}

- (void)loadDetails:(void (^)(void))completion {
    NSArray<PineoraThemeItem *> *themes = self.allThemes;
    NSInteger scale = (NSInteger)lround([UIScreen mainScreen].scale);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for (PineoraThemeItem *item in themes) {
            // 用引擎自己的解析器，图标数与 SpringBoard 侧看到的一致。
            TETheme *theme = [TETheme themeAtPath:item.path];
            NSDictionary *icons = theme.iconPaths ?: @{};
            NSString *previewIdentifier = nil;
            for (NSString *identifier in PineoraPreviewBundleIdentifiers()) {
                if (icons[identifier] != nil) {
                    previewIdentifier = identifier;
                    break;
                }
            }
            if (previewIdentifier == nil) {
                previewIdentifier = [icons.allKeys sortedArrayUsingSelector:@selector(compare:)].firstObject;
            }
            NSString *previewPath = previewIdentifier != nil
                ? [theme iconPathForBundleIdentifier:previewIdentifier scale:scale] : nil;
            UIImage *image = previewPath != nil ? [UIImage imageWithContentsOfFile:previewPath] : nil;
            UIImage *preview = image != nil ? PineoraRoundedPreview(image) : nil;
            NSInteger count = (NSInteger)icons.count;
            dispatch_async(dispatch_get_main_queue(), ^{
                item.iconCount = count;
                item.preview = preview;
            });
        }
        dispatch_async(dispatch_get_main_queue(), completion);
    });
}

#pragma mark - 写

- (void)saveSelection {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (PineoraThemeItem *item in self.activeThemes) {
        [names addObject:item.name];
    }
    [names addObjectsFromArray:self.missingThemeNames];
    [self writeValue:names forKey:@"Themes"];
    self.hasExplicitSelection = YES;
}

- (void)writeValue:(id)value forKey:(NSString *)key {
    NSMutableDictionary *prefs = [[self readPreferences] mutableCopy];
    prefs[key] = value;
    NSError *error = nil;
    BOOL ok = [prefs writeToURL:[NSURL fileURLWithPath:PineoraPreferencesPath()] error:&error];
    if (ok) {
        self.hasUnappliedChanges = YES;
        NSLog(@"[PineoraPrefs] saved %@=%@", key, value);
    } else {
        NSLog(@"[PineoraPrefs] cannot write %@: %@", PineoraPreferencesPath(), error);
    }
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [self writeValue:@(enabled) forKey:@"Enabled"];
}

- (void)activateTheme:(PineoraThemeItem *)theme {
    if ([self.activeThemes containsObject:theme]) {
        return;
    }
    self.activeThemes = [self.activeThemes arrayByAddingObject:theme];
    [self refreshInactive];
    [self saveSelection];
}

- (void)deactivateTheme:(PineoraThemeItem *)theme {
    NSMutableArray<PineoraThemeItem *> *active = [self.activeThemes mutableCopy];
    [active removeObject:theme];
    self.activeThemes = active;
    [self refreshInactive];
    [self saveSelection];
}

- (void)moveActiveThemeAtIndex:(NSUInteger)from toIndex:(NSUInteger)to {
    if (from == to || from >= self.activeThemes.count || to >= self.activeThemes.count) {
        return;
    }
    NSMutableArray<PineoraThemeItem *> *active = [self.activeThemes mutableCopy];
    PineoraThemeItem *item = active[from];
    [active removeObjectAtIndex:from];
    [active insertObject:item atIndex:to];
    self.activeThemes = active;
    [self saveSelection];
}

- (void)apply {
    NSString *name = [NSString stringWithFormat:@"%s/refresh", APELIN_PACKAGE_ID];
    uint32_t status = notify_post(name.UTF8String);
    self.hasUnappliedChanges = NO;
    NSLog(@"[PineoraPrefs] posted %@ status=%u", name, status);
}

@end
