#import <Foundation/Foundation.h>

static NSUInteger checks;
static NSUInteger failures;

static void Check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) {
        failures++;
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    }
}

static NSArray<NSString *> *Specifiers(NSString *text) {
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:
        @"%(?:[0-9]+\\$)?(?:lld|llu|ld|lu|[@dDuUxXofegGs])|%%" options:0 error:NULL];
    NSMutableArray *result = [NSMutableArray array];
    for (NSTextCheckingResult *match in [pattern matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        [result addObject:[text substringWithRange:match.range]];
    }
    return result;
}

static NSDictionary *ReadCatalog(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) return nil;
    id catalog = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    return [catalog isKindOfClass:NSDictionary.class] ? catalog : nil;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *root = NSProcessInfo.processInfo.environment[@"APELIN_PROJECT_ROOT"];
        if (root.length == 0) return 2;
        NSString *resources = [root stringByAppendingPathComponent:@"Preferences/Resources"];
        NSArray *locales = @[@"en", @"zh-Hans", @"ja", @"ko"];
        NSMutableDictionary<NSString *, NSDictionary *> *catalogs = [NSMutableDictionary dictionary];
        NSRegularExpression *entryPattern = [NSRegularExpression regularExpressionWithPattern:
            @"(?m)^\"([^\"]+)\"\\s*=" options:0 error:NULL];
        for (NSString *locale in locales) {
            NSString *directory = [resources stringByAppendingPathComponent:[locale stringByAppendingPathExtension:@"lproj"]];
            NSString *path = [directory stringByAppendingPathComponent:@"Localizable.strings"];
            NSDictionary *catalog = ReadCatalog(path);
            Check(catalog != nil && catalog.count == 22, [locale stringByAppendingString:@": 22 entries"]);
            if (catalog == nil) continue;
            catalogs[locale] = catalog;
            NSString *raw = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
            NSUInteger entries = [entryPattern numberOfMatchesInString:raw options:0 range:NSMakeRange(0, raw.length)];
            Check(entries == catalog.count, [locale stringByAppendingString:@": no duplicate keys"]);
        }
        NSDictionary *source = catalogs[@"en"];
        if (source == nil) return 1;
        NSSet *keys = [NSSet setWithArray:source.allKeys];
        for (NSString *locale in locales) {
            NSDictionary *catalog = catalogs[locale];
            Check([[NSSet setWithArray:catalog.allKeys] isEqual:keys], [locale stringByAppendingString:@": key parity"]);
            for (NSString *key in source) {
                NSString *value = catalog[key];
                Check([value isKindOfClass:NSString.class] && value.length > 0,
                      [NSString stringWithFormat:@"%@/%@: nonempty", locale, key]);
                if (![value isKindOfClass:NSString.class]) continue;
                Check([Specifiers(value) isEqual:Specifiers(source[key])],
                      [NSString stringWithFormat:@"%@/%@: format parity", locale, key]);
                NSString *formatted = value;
                if ([key isEqual:@"theme.icon_count"]) {
                    for (NSNumber *count in @[@0, @1, @1970]) {
                        formatted = [NSString stringWithFormat:value, count.longValue];
                        Check([formatted containsString:count.stringValue], @"count format preserves value");
                    }
                } else if ([key isEqual:@"themes.install_footer"] || [key isEqual:@"themes.missing_footer"]) {
                    formatted = [NSString stringWithFormat:value, @"Example.theme"];
                    Check([formatted containsString:@"Example.theme"], @"theme format preserves argument");
                }
                Check(![formatted containsString:@"%@"] && ![formatted containsString:@"%ld"], @"no unresolved placeholders");
            }
        }
        NSMutableSet *usedKeys = [NSMutableSet set];
        NSRegularExpression *callPattern = [NSRegularExpression regularExpressionWithPattern:
            @"PineoraLocalizedString\\(@\"([^\"]+)\"\\)" options:0 error:NULL];
        for (NSString *file in @[@"PineoraSettingsController.m", @"PineoraStore.m"]) {
            NSString *path = [[root stringByAppendingPathComponent:@"Preferences"] stringByAppendingPathComponent:file];
            NSString *code = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
            Check(code != nil, [file stringByAppendingString:@": readable"]);
            for (NSTextCheckingResult *match in [callPattern matchesInString:code options:0 range:NSMakeRange(0, code.length)]) {
                [usedKeys addObject:[code substringWithRange:[match rangeAtIndex:1]]];
            }
        }
        Check([usedKeys isEqual:keys], @"all catalog keys used; every call translated");
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[resources stringByAppendingPathComponent:@"Info.plist"]];
        Check([info[@"CFBundleDevelopmentRegion"] isEqual:@"en"], @"English fallback");
        Check([[NSSet setWithArray:info[@"CFBundleLocalizations"]] isEqual:[NSSet setWithArray:locales]], @"exactly four supported locales");
        for (NSArray *pair in @[@[@"zh-CN", @"zh-Hans"], @[@"ja-JP", @"ja"], @[@"en-US", @"en"], @[@"ko-KR", @"ko"]]) {
            NSArray *preferred = [NSBundle preferredLocalizationsFromArray:locales forPreferences:@[pair[0]]];
            Check([preferred.firstObject isEqual:pair[1]], [@"language resolution: " stringByAppendingString:pair[0]]);
        }
        if (argc > 1) {
            NSString *bundlePath = [NSString stringWithUTF8String:argv[1]];
            NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
            Check(bundle != nil, @"packaged preference bundle opens");
            for (NSString *locale in locales) {
                NSString *path = [bundle pathForResource:@"Localizable" ofType:@"strings" inDirectory:nil forLocalization:locale];
                Check(path != nil && [ReadCatalog(path) isEqual:catalogs[locale]],
                      [locale stringByAppendingString:@": packaged strings match source"]);
            }
            NSString *selected = [bundle preferredLocalizations].firstObject;
            if (argc > 2) {
                Check([selected isEqual:[NSString stringWithUTF8String:argv[2]]], @"requested process language selected");
            }
            Check(catalogs[selected] != nil, @"bundle selects a supported language");
            for (NSString *key in source) {
                NSString *actual = [bundle localizedStringForKey:key value:nil table:nil];
                Check([actual isEqual:catalogs[selected][key]], [@"bundle lookup: " stringByAppendingString:key]);
            }
            printf("Selected bundle language: %s\n", selected.UTF8String);
        }
        printf("Localization checks: %lu; failures: %lu\n", (unsigned long)checks, (unsigned long)failures);
        return failures ? 1 : 0;
    }
}
