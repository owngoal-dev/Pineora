#import "TETheme.h"
#import "TELog.h"
#import <UIKit/UIKit.h>

typedef NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, NSString *> *> TEIconTable;

// 对目录与文件都做边界检查；解析符号链接，不能借主题内的链接读取主题外文件。
static BOOL TESafeRelativePath(NSString *value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0 || value.isAbsolutePath ||
        [value hasPrefix:@"~"] || [value containsString:@"\\"] || [value containsString:@":"] ||
        [value rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound) return NO;
    for (NSString *component in [value componentsSeparatedByString:@"/"]) {
        if (component.length == 0 || [component isEqualToString:@"."] || [component isEqualToString:@".."]) return NO;
    }
    return YES;
}

static BOOL TESafeIdentifier(NSString *identifier) {
    return TESafeRelativePath(identifier) && ![identifier containsString:@"/"] && ![identifier hasPrefix:@"."];
}

static NSString *TEContainedPath(NSString *root, NSString *relative, BOOL directory) {
    if (!TESafeRelativePath(relative)) return nil;
    NSString *candidate = [[root stringByAppendingPathComponent:relative] stringByResolvingSymlinksInPath];
    if (![candidate hasPrefix:[root stringByAppendingString:@"/"]]) return nil;
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:candidate isDirectory:&isDirectory] ||
        isDirectory != directory) return nil;
    return candidate;
}

static NSArray<NSString *> *TEEntries(NSString *root, NSString *relative) {
    NSString *directory = relative.length ? TEContainedPath(root, relative, YES) : root;
    if (!directory) return @[];
    return [[NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:NULL]
            sortedArrayUsingSelector:@selector(compare:)] ?: @[];
}

static NSDictionary *TEInfo(NSString *root, NSString *relative) {
    NSString *file = TEContainedPath(root, relative, NO);
    return file ? ([NSDictionary dictionaryWithContentsOfFile:file] ?: @{}) : @{};
}

static NSString *TEDeviceSuffix(void) {
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"~ipad" : @"~iphone";
}

// 去掉完整语法后缀，不猜测 "foobig" 或 "foolarge" 等有歧义的名字。
// 循环兼容 -large@3x~iphone 与 @3x~iphone-large 等组合。
static NSString *TEFileStem(NSString *file, BOOL stripLarge, NSInteger *scale, NSString **idiom) {
    NSString *stem = file.stringByDeletingPathExtension;
    NSInteger foundScale = 1;
    NSString *foundIdiom = @"";
    static NSRegularExpression *scaleExpression;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        scaleExpression = [NSRegularExpression regularExpressionWithPattern:@"@[1-9][0-9]*x$" options:0 error:NULL];
    });
    BOOL changed;
    do {
        changed = NO;
        for (NSString *suffix in @[@"~iphone", @"~ipad"]) {
            if ([stem hasSuffix:suffix]) {
                foundIdiom = suffix;
                stem = [stem substringToIndex:stem.length - suffix.length];
                changed = YES;
                break;
            }
        }
        NSTextCheckingResult *match = [scaleExpression firstMatchInString:stem options:0 range:NSMakeRange(0, stem.length)];
        if (match) {
            foundScale = [[stem substringWithRange:NSMakeRange(match.range.location + 1, match.range.length - 2)] integerValue];
            stem = [stem substringToIndex:match.range.location];
            changed = YES;
        }
        if (stripLarge && [stem hasSuffix:@"-large"]) {
            stem = [stem substringToIndex:stem.length - 6];
            changed = YES;
        }
    } while (changed);
    if (scale) *scale = MAX(1, foundScale);
    if (idiom) *idiom = foundIdiom;
    return stem;
}

static NSInteger TEIdiomRank(NSString *file) {
    NSString *idiom = nil;
    TEFileStem(file, YES, NULL, &idiom);
    return [idiom isEqualToString:TEDeviceSuffix()] ? 0 : (idiom.length ? 2 : 1);
}

static BOOL TEApplicationIdentifier(NSString *identifier) {
    if (!TESafeIdentifier(identifier)) return NO;
    for (NSString *reserved in @[@"com.apple.mobileicons.framework", @"com.apple.springboard"]) {
        if ([identifier.lowercaseString isEqualToString:reserved] ||
            [identifier.lowercaseString hasPrefix:[reserved stringByAppendingString:@"."]]) return NO;
    }
    return YES;
}

static BOOL TEExcludedIconName(NSString *stem) {
    NSString *lower = stem.lowercaseString;
    return [lower containsString:@"mask"] || [lower containsString:@"badge"] || [lower hasPrefix:@"clockicon"];
}

static BOOL TECommonApplicationIcon(NSString *stem) {
    if (TEExcludedIconName(stem)) return NO;
    static NSRegularExpression *expression;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        expression = [NSRegularExpression regularExpressionWithPattern:
                      @"^(appicon|icon)(?:[-_ ]?(?:[0-9]+(?:x[0-9]+)?|small|large|iphone|ipad|ios))*$"
                      options:NSRegularExpressionCaseInsensitive error:NULL];
    });
    return [expression firstMatchInString:stem options:0 range:NSMakeRange(0, stem.length)] != nil;
}

static NSSet<NSString *> *TEListedIconStems(NSDictionary *info) {
    NSMutableSet *stems = [NSMutableSet set];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *key in @[@"CFBundleIcons", @"CFBundleIcons~ipad"]) {
        id icons = info[key];
        id primary = [icons isKindOfClass:NSDictionary.class] ? icons[@"CFBundlePrimaryIcon"] : nil;
        id files = [primary isKindOfClass:NSDictionary.class] ? primary[@"CFBundleIconFiles"] : nil;
        if ([files isKindOfClass:NSArray.class]) [names addObjectsFromArray:files];
    }
    if ([info[@"CFBundleIconFiles"] isKindOfClass:NSArray.class]) [names addObjectsFromArray:info[@"CFBundleIconFiles"]];
    if ([info[@"CFBundleIconFile"] isKindOfClass:NSString.class]) [names addObject:info[@"CFBundleIconFile"]];
    for (id name in names) {
        if (!TESafeRelativePath(name)) continue;
        NSString *file = [name pathExtension].length ? name : [name stringByAppendingPathExtension:@"png"];
        [stems addObject:TEFileStem(file, YES, NULL, NULL)];
    }
    return stems;
}

static void TEAddIcon(TEIconTable *table, NSString *identifier, NSInteger scale, NSString *path) {
    if (!TEApplicationIdentifier(identifier) || !path) return;
    NSMutableDictionary *byScale = table[identifier];
    if (!byScale) table[identifier] = byScale = [NSMutableDictionary dictionary];
    if (!byScale[@(scale)]) byScale[@(scale)] = path;
}

static void TEScanApplicationDirectory(TEIconTable *table, NSString *root, NSString *relative,
                                        NSString *identifier, NSDictionary *info) {
    if (!TEApplicationIdentifier(identifier)) return;
    NSSet *listed = TEListedIconStems(info);
    NSArray *files = [TEEntries(root, relative) sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSInteger aRank = TEIdiomRank(a), bRank = TEIdiomRank(b);
        if (aRank != bRank) return aRank < bRank ? NSOrderedAscending : NSOrderedDescending;
        NSString *aStem = TEFileStem(a, YES, NULL, NULL), *bStem = TEFileStem(b, YES, NULL, NULL);
        NSInteger aScore = [listed containsObject:aStem] ? 0 : ([aStem.lowercaseString hasPrefix:@"appicon"] ? 1 : 2);
        NSInteger bScore = [listed containsObject:bStem] ? 0 : ([bStem.lowercaseString hasPrefix:@"appicon"] ? 1 : 2);
        if (aScore != bScore) return aScore < bScore ? NSOrderedAscending : NSOrderedDescending;
        return [a compare:b];
    }];
    for (NSString *file in files) {
        if (![file.pathExtension.lowercaseString isEqualToString:@"png"]) continue;
        NSInteger scale;
        NSString *stem = TEFileStem(file, YES, &scale, NULL);
        if (TEExcludedIconName(stem) || (!TECommonApplicationIcon(stem) && ![listed containsObject:stem])) continue;
        TEAddIcon(table, identifier, scale, TEContainedPath(root, [relative stringByAppendingPathComponent:file], NO));
    }
}

@interface TETheme ()
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<NSString *> *> *resourceDirectories;
@end

@implementation TETheme

+ (instancetype)themeAtPath:(NSString *)path {
    if (![path isKindOfClass:NSString.class] || path.length == 0) return nil;
    NSString *root = path.isAbsolutePath ? path : [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:path];
    root = [root.stringByStandardizingPath stringByResolvingSymlinksInPath];
    BOOL directory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:root isDirectory:&directory] || !directory ||
        ![NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:NULL]) return nil;
    TETheme *theme = [[self alloc] init];
    theme->_path = [root copy];
    theme->_name = [path.lastPathComponent copy];
    theme->_info = [TEInfo(root, @"Info.plist") copy];
    id identifier = theme.info[@"CFBundleIdentifier"];
    theme->_identifier = [([identifier isKindOfClass:NSString.class] && [identifier length] ? identifier : path.lastPathComponent) copy];
    TEIconTable *table = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *resources = [NSMutableDictionary dictionary];
    BOOL hasIconBundles = TEContainedPath(root, @"IconBundles", YES) != nil;
    BOOL hasBundles = TEContainedPath(root, @"Bundles", YES) != nil;

    NSArray *modernFiles = [TEEntries(root, @"IconBundles") sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSInteger ar = TEIdiomRank(a), br = TEIdiomRank(b);
        return ar == br ? [a compare:b] : (ar < br ? NSOrderedAscending : NSOrderedDescending);
    }];
    for (NSString *file in modernFiles) {
        if (![file.pathExtension.lowercaseString isEqualToString:@"png"]) continue;
        NSInteger scale;
        NSString *bundleID = TEFileStem(file, YES, &scale, NULL);
        TEAddIcon(table, bundleID, scale, TEContainedPath(root, [@"IconBundles" stringByAppendingPathComponent:file], NO));
    }

    // 稳定布局优先级；Info.plist 中的 ID 优先于目录名。无 Info 的 bundleID 目录同样可用。
    for (NSString *layout in @[@"Bundles", @"", @"Folders"]) {
        for (NSString *entry in TEEntries(root, layout)) {
            if (!TESafeIdentifier(entry) || ![entry containsString:@"."]) continue;
            NSString *relative = layout.length ? [layout stringByAppendingPathComponent:entry] : entry;
            if (!TEContainedPath(root, relative, YES)) continue;
            NSDictionary *info = TEInfo(root, [relative stringByAppendingPathComponent:@"Info.plist"]);
            id declaredID = info[@"CFBundleIdentifier"];
            NSString *bundleID = [declaredID isKindOfClass:NSString.class] && TESafeIdentifier(declaredID) ? declaredID : entry;
            if (declaredID == nil && ([@[@"bundle", @"app", @"theme"] containsObject:entry.pathExtension.lowercaseString])) continue;
            NSMutableArray *directories = resources[bundleID];
            if (!directories) resources[bundleID] = directories = [NSMutableArray array];
            [directories addObject:relative];
            TEScanApplicationDirectory(table, root, relative, bundleID, info);
        }
    }

    id icons = theme.info[@"Icons"];
    if ([icons isKindOfClass:NSDictionary.class]) {
        NSArray *keys = [[icons allKeys] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id key, __unused NSDictionary *bindings) {
            return [key isKindOfClass:NSString.class];
        }]];
        for (NSString *bundleID in [keys sortedArrayUsingSelector:@selector(compare:)]) {
            id value = icons[bundleID];
            NSArray *names = [value isKindOfClass:NSString.class] ? @[value] : ([value isKindOfClass:NSArray.class] ? value : @[]);
            for (id name in names) {
                if (!TESafeRelativePath(name)) continue;
                NSString *file = [name pathExtension].length ? name : [name stringByAppendingPathExtension:@"png"];
                NSInteger scale;
                NSString *stem = TEFileStem(file.lastPathComponent, YES, &scale, NULL);
                if (TEExcludedIconName(stem)) continue;
                TEAddIcon(table, bundleID, scale, TEContainedPath(root, file, NO));
            }
        }
    }
    NSMutableDictionary *frozenIcons = [NSMutableDictionary dictionary];
    for (NSString *key in table) frozenIcons[key] = [table[key] copy];
    theme->_iconPaths = [frozenIcons copy];
    NSMutableDictionary *frozenResources = [NSMutableDictionary dictionary];
    for (NSString *key in resources) frozenResources[key] = [resources[key] copy];
    theme.resourceDirectories = frozenResources;
    theme->_legacy = !hasIconBundles && (hasBundles || table.count > 0);
    os_log(TELog(), "TETheme %{public}s id=%{public}s icons=%lu legacy=%d",
           theme.path.lastPathComponent.UTF8String, theme.identifier.UTF8String,
           (unsigned long)theme.iconPaths.count, theme.legacy ? 1 : 0);
    return theme;
}

- (NSString *)iconPathForBundleIdentifier:(NSString *)bundleIdentifier scale:(NSInteger)scale {
    if (!TESafeIdentifier(bundleIdentifier)) return nil;
    NSDictionary<NSNumber *, NSString *> *byScale = self.iconPaths[bundleIdentifier];
    if (!byScale) {
        NSString *longest = nil;
        for (NSString *key in self.iconPaths) {
            if ([bundleIdentifier hasPrefix:[key stringByAppendingString:@"."]] &&
                (longest == nil || key.length > longest.length ||
                 (key.length == longest.length && [key compare:longest] == NSOrderedAscending))) longest = key;
        }
        byScale = longest ? self.iconPaths[longest] : nil;
    }
    if (byScale[@(scale)]) return byScale[@(scale)];
    for (NSNumber *fallback in @[@3, @2, @1]) if (byScale[fallback]) return byScale[fallback];
    NSNumber *largest = [byScale.allKeys sortedArrayUsingSelector:@selector(compare:)].lastObject;
    return largest ? byScale[largest] : nil;
}

- (NSString *)resourcePathForBundleIdentifier:(NSString *)bundleIdentifier resourceName:(NSString *)resourceName scale:(NSInteger)scale {
    if (!TESafeIdentifier(bundleIdentifier) || !TESafeRelativePath(resourceName)) return nil;
    NSString *file = resourceName.pathExtension.length ? resourceName : [resourceName stringByAppendingPathExtension:@"png"];
    // 只剥掉倍率和设备后缀；扩展资源名中的 -large 是资源名的一部分。
    NSString *stem = TEFileStem(file, NO, NULL, NULL);
    NSString *extension = file.pathExtension;
    NSMutableOrderedSet<NSNumber *> *scales = [NSMutableOrderedSet orderedSet];
    if (scale > 0) [scales addObject:@(scale)];
    [scales addObjectsFromArray:@[@3, @2, @1]];
    NSString *device = TEDeviceSuffix();
    NSString *other = [device isEqualToString:@"~iphone"] ? @"~ipad" : @"~iphone";
    NSMutableOrderedSet<NSString *> *variants = [NSMutableOrderedSet orderedSet];
    // 设备专属回退优先于通用；不会优先拿另一设备的遮罩。
    for (NSString *idiom in @[device, @"", other]) {
        for (NSNumber *number in scales) {
            NSString *suffix = number.integerValue == 1 ? @"" : [NSString stringWithFormat:@"@%@x", number];
            [variants addObject:[[NSString stringWithFormat:@"%@%@%@", stem, suffix, idiom] stringByAppendingPathExtension:extension]];
            if (number.integerValue == 1) {
                [variants addObject:[[NSString stringWithFormat:@"%@@1x%@", stem, idiom] stringByAppendingPathExtension:extension]];
            }
        }
    }
    for (NSString *directory in self.resourceDirectories[bundleIdentifier]) {
        for (NSString *variant in variants) {
            NSString *result = TEContainedPath(self.path, [directory stringByAppendingPathComponent:variant], NO);
            if (result) return result;
        }
    }
    return nil;
}

@end
