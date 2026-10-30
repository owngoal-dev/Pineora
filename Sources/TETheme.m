#import "TETheme.h"
#import "TELog.h"

// 从 "X@3x.png" 得到倍率 3 与基名 "X"；无 @Nx 时为 1。
static NSInteger TEScaleFromFileName(NSString *fileName, NSString *_Nullable *_Nullable baseName) {
    NSString *base = fileName.stringByDeletingPathExtension;
    NSInteger scale = 1;
    NSRange at = [base rangeOfString:@"@" options:NSBackwardsSearch];
    if (at.location != NSNotFound) {
        NSString *suffix = [base substringFromIndex:at.location + 1];
        if ([suffix hasSuffix:@"x"] && suffix.length > 1) {
            NSInteger value = [[suffix substringToIndex:suffix.length - 1] integerValue];
            if (value >= 1 && value <= 4) {
                scale = value;
                base = [base substringToIndex:at.location];
            }
        }
    }
    if (baseName != NULL) {
        *baseName = base;
    }
    return scale;
}

// 图标文件名打分：AppIcon* / icon* 优先，其余按名字长度做稳定次序。
static NSInteger TEFileNameScore(NSString *fileName) {
    NSString *lower = fileName.lowercaseString;
    if ([lower hasPrefix:@"appicon"]) {
        return 3;
    }
    if ([lower hasPrefix:@"icon"]) {
        return 2;
    }
    return 1;
}

static NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, NSString *> *> *TENewIconTable(void) {
    return [NSMutableDictionary dictionary];
}

static void TEAddIcon(NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, NSString *> *> *table,
                      NSString *bundleIdentifier, NSInteger scale, NSString *path) {
    if (bundleIdentifier.length == 0 || path.length == 0) {
        return;
    }
    NSMutableDictionary<NSNumber *, NSString *> *byScale = table[bundleIdentifier];
    if (byScale == nil) {
        byScale = [NSMutableDictionary dictionary];
        table[bundleIdentifier] = byScale;
    }
    NSNumber *key = @(scale);
    NSString *existing = byScale[key];
    if (existing == nil || TEFileNameScore(path.lastPathComponent) < TEFileNameScore(existing.lastPathComponent)) {
        byScale[key] = path;
    }
}

@implementation TETheme

+ (instancetype)themeAtPath:(NSString *)path {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
        return nil;
    }
    TETheme *theme = [[TETheme alloc] init];
    if (theme == nil) {
        return nil;
    }
    theme->_path = [path copy];
    theme->_name = path.lastPathComponent;

    // Info.plist 可能是二进制，也可能是 XML。
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                          [path stringByAppendingPathComponent:@"Info.plist"]];
    NSString *identifier = nil;
    if ([info[@"CFBundleIdentifier"] isKindOfClass:[NSString class]]) {
        identifier = info[@"CFBundleIdentifier"];
    }
    theme->_identifier = identifier.length > 0 ? [identifier copy] : [path.lastPathComponent copy];

    NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, NSString *> *> *table = TENewIconTable();

    // 1. 现代格式：IconBundles
    BOOL hasIconBundles = [fileManager fileExistsAtPath:[path stringByAppendingPathComponent:@"IconBundles"]
                                            isDirectory:&isDirectory] && isDirectory;
    if (hasIconBundles) {
        NSString *folder = [path stringByAppendingPathComponent:@"IconBundles"];
        for (NSString *file in [fileManager contentsOfDirectoryAtPath:folder error:NULL]) {
            if (![file.pathExtension.lowercaseString isEqualToString:@"png"]) {
                continue;
            }
            NSString *base = nil;
            NSInteger scale = TEScaleFromFileName(file, &base);
            TEAddIcon(table, base, scale, [folder stringByAppendingPathComponent:file]);
        }
    }

    // 2. 兼容格式：Bundles/<X>.bundle，bundle 的 Info.plist 给出 bundle id
    BOOL hasBundles = [fileManager fileExistsAtPath:[path stringByAppendingPathComponent:@"Bundles"]
                                        isDirectory:&isDirectory] && isDirectory;
    if (hasBundles) {
        NSString *bundles = [path stringByAppendingPathComponent:@"Bundles"];
        for (NSString *entry in [fileManager contentsOfDirectoryAtPath:bundles error:NULL]) {
            if (![entry.pathExtension.lowercaseString isEqualToString:@"bundle"]) {
                continue;
            }
            NSString *bundlePath = [bundles stringByAppendingPathComponent:entry];
            NSDictionary *bundleInfo = [NSDictionary dictionaryWithContentsOfFile:
                                        [bundlePath stringByAppendingPathComponent:@"Info.plist"]];
            NSString *bundleIdentifier = bundleInfo[@"CFBundleIdentifier"];
            if (![bundleIdentifier isKindOfClass:[NSString class]] || bundleIdentifier.length == 0) {
                continue;
            }
            // CFBundleIconFiles 里列出的名字优先，其余 png 作为回退。
            NSMutableArray<NSString *> *listed = [NSMutableArray array];
            id iconFiles = bundleInfo[@"CFBundleIcons"];
            if ([iconFiles isKindOfClass:[NSDictionary class]]) {
                id primary = iconFiles[@"CFBundlePrimaryIcon"];
                if ([primary isKindOfClass:[NSDictionary class]]) {
                    id names = primary[@"CFBundleIconFiles"];
                    if ([names isKindOfClass:[NSArray class]]) {
                        [listed addObjectsFromArray:names];
                    }
                }
            }
            id flatNames = bundleInfo[@"CFBundleIconFiles"];
            if ([flatNames isKindOfClass:[NSArray class]]) {
                [listed addObjectsFromArray:flatNames];
            }
            for (NSString *name in listed) {
                if (![name isKindOfClass:[NSString class]] || name.length == 0) {
                    continue;
                }
                NSString *fileName = name.pathExtension.length > 0 ? name : [name stringByAppendingPathExtension:@"png"];
                NSString *candidate = [bundlePath stringByAppendingPathComponent:fileName];
                if (![fileManager fileExistsAtPath:candidate]) {
                    continue;
                }
                NSString *base = nil;
                NSInteger scale = TEScaleFromFileName(fileName, &base);
                TEAddIcon(table, bundleIdentifier, scale, candidate);
            }
            for (NSString *file in [fileManager contentsOfDirectoryAtPath:bundlePath error:NULL]) {
                if (![file.pathExtension.lowercaseString isEqualToString:@"png"]) {
                    continue;
                }
                NSString *base = nil;
                NSInteger scale = TEScaleFromFileName(file, &base);
                TEAddIcon(table, bundleIdentifier, scale, [bundlePath stringByAppendingPathComponent:file]);
            }
        }
    }

    // 3. 旧版格式：<bundleID>/ 目录
    for (NSString *entry in [fileManager contentsOfDirectoryAtPath:path error:NULL]) {
        if ([entry isEqualToString:@"IconBundles"] || [entry isEqualToString:@"Bundles"] ||
            [entry hasPrefix:@"."]) {
            continue;
        }
        NSString *child = [path stringByAppendingPathComponent:entry];
        BOOL childIsDirectory = NO;
        if (![fileManager fileExistsAtPath:child isDirectory:&childIsDirectory] || !childIsDirectory) {
            continue;
        }
        // 只有形如 com.apple.xxx 的目录才当作 bundle id 目录。
        if ([entry componentsSeparatedByString:@"."].count < 2) {
            continue;
        }
        for (NSString *file in [fileManager contentsOfDirectoryAtPath:child error:NULL]) {
            if (![file.pathExtension.lowercaseString isEqualToString:@"png"]) {
                continue;
            }
            NSString *base = nil;
            NSInteger scale = TEScaleFromFileName(file, &base);
            // appicon / icon / iconlarge 都归到同一个 bundle id。
            TEAddIcon(table, entry, scale, [child stringByAppendingPathComponent:file]);
        }
    }

    // 4. Info.plist 的 Icons 字典：bundleID -> 文件名或文件名数组
    id iconsValue = info[@"Icons"];
    if ([iconsValue isKindOfClass:[NSDictionary class]]) {
        NSDictionary *icons = iconsValue;
        for (NSString *bundleIdentifier in icons) {
            id value = icons[bundleIdentifier];
            NSArray<NSString *> *names = nil;
            if ([value isKindOfClass:[NSString class]]) {
                names = @[value];
            } else if ([value isKindOfClass:[NSArray class]]) {
                names = value;
            }
            for (NSString *name in names) {
                if (![name isKindOfClass:[NSString class]] || name.length == 0) {
                    continue;
                }
                NSString *fileName = name.pathExtension.length > 0 ? name : [name stringByAppendingPathExtension:@"png"];
                NSString *candidate = [path stringByAppendingPathComponent:fileName];
                if (![fileManager fileExistsAtPath:candidate]) {
                    continue;
                }
                NSString *base = nil;
                NSInteger scale = TEScaleFromFileName(fileName, &base);
                TEAddIcon(table, bundleIdentifier, scale, candidate);
            }
        }
    }

    theme->_iconPaths = [table copy];
    // 没有 IconBundles、却有 Bundles 或旧版目录时，按旧版主题对待。
    theme->_legacy = !hasIconBundles && (hasBundles || table.count > 0);

    os_log(TELog(), "TETheme %{public}s id=%{public}s icons=%lu legacy=%d",
           theme.path.lastPathComponent.UTF8String, theme.identifier.UTF8String,
           (unsigned long)theme.iconPaths.count, theme.legacy ? 1 : 0);
    return theme;
}

- (NSString *)iconPathForBundleIdentifier:(NSString *)bundleIdentifier scale:(NSInteger)scale {
    if (bundleIdentifier.length == 0) {
        return nil;
    }
    NSDictionary<NSNumber *, NSString *> *byScale = self.iconPaths[bundleIdentifier];
    if (byScale == nil) {
        // SnowBoard 的 FuzzyBundleIdentifiers：允许前缀匹配。
        for (NSString *key in self.iconPaths) {
            if ([bundleIdentifier hasPrefix:key] || [key hasPrefix:bundleIdentifier]) {
                byScale = self.iconPaths[key];
                break;
            }
        }
    }
    if (byScale.count == 0) {
        return nil;
    }
    NSString *exact = byScale[@(scale)];
    if (exact != nil) {
        return exact;
    }
    for (NSNumber *candidate in @[@3, @2, @1]) {
        if (candidate.integerValue == scale) {
            continue;
        }
        NSString *path = byScale[candidate];
        if (path != nil) {
            return path;
        }
    }
    // 最大倍率兜底。
    NSNumber *largest = [byScale.allKeys sortedArrayUsingSelector:@selector(compare:)].lastObject;
    return largest != nil ? byScale[largest] : nil;
}

@end
