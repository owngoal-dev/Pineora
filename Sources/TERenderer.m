#import "TERenderer.h"

UIColor *TEColorFromSettings(id value, UIColor *fallback) {
    if (![value isKindOfClass:NSString.class]) return fallback;
    NSString *hex = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length != 6 && hex.length != 8) return fallback;
    if ([hex rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location != NSNotFound) return fallback;
    unsigned long long number = 0;
    if (![[NSScanner scannerWithString:hex] scanHexLongLong:&number]) return fallback;
    CGFloat alpha = hex.length == 8 ? (number & 255) / 255.0 : 1;
    if (hex.length == 8) number >>= 8;
    return [UIColor colorWithRed:((number >> 16) & 255) / 255.0 green:((number >> 8) & 255) / 255.0 blue:(number & 255) / 255.0 alpha:alpha];
}

UIFont *TEFontFromSettings(NSDictionary *settings, UIFont *fallback) {
    id value = settings[@"FontSize"];
    CGFloat size = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback.pointSize;
    if (!isfinite(size) || size <= 0 || size > 100) size = fallback.pointSize;
    NSString *name = settings[@"FontName"];
    UIFont *font = [name isKindOfClass:NSString.class] ? [UIFont fontWithName:name size:size] : nil;
    if (font) return font;
    NSString *weight = [settings[@"FontWeight"] isKindOfClass:NSString.class] ? [settings[@"FontWeight"] lowercaseString] : @"regular";
    CGFloat w = UIFontWeightRegular;
    if ([weight isEqualToString:@"bold"]) w = UIFontWeightBold;
    else if ([weight isEqualToString:@"semibold"]) w = UIFontWeightSemibold;
    else if ([weight isEqualToString:@"medium"]) w = UIFontWeightMedium;
    else if ([weight isEqualToString:@"light"]) w = UIFontWeightLight;
    else if ([weight isEqualToString:@"thin"]) w = UIFontWeightThin;
    else if ([weight isEqualToString:@"heavy"]) w = UIFontWeightHeavy;
    return [UIFont systemFontOfSize:size weight:w];
}

static CGFloat TEOffset(NSDictionary *settings, NSString *key) {
    id value = settings[key];
    CGFloat offset = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0;
    return isfinite(offset) ? MAX(-120, MIN(offset, 120)) : 0;
}

static void TEDrawCalendarText(NSString *text, NSDictionary *settings, CGFloat defaultSize,
                               UIColor *color, CGFloat centerY, CGSize size) {
    id fontSize = settings[@"FontSize"];
    if ([fontSize isKindOfClass:NSNumber.class] && [fontSize doubleValue] == 0) return;
    CGFloat ratio = size.width / 60.0;
    UIFont *font = TEFontFromSettings(settings ?: @{}, [UIFont systemFontOfSize:defaultSize]);
    font = [font fontWithSize:font.pointSize * ratio];
    NSDictionary *attributes = @{NSFontAttributeName: font,
        NSForegroundColorAttributeName: TEColorFromSettings(settings[@"TextColor"], color)};
    CGSize textSize = [text sizeWithAttributes:attributes];
    CGPoint point = CGPointMake((size.width - textSize.width) / 2 + TEOffset(settings, @"TextXoffset") * ratio,
        centerY * ratio - textSize.height / 2 + TEOffset(settings, @"TextYoffset") * ratio);
    [text drawAtPoint:point withAttributes:attributes];
}

UIImage *TEResizeImage(UIImage *source, CGSize size, CGFloat scale) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = scale;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [source drawInRect:(CGRect){CGPointZero, size}];
    }];
}

UIImage *TERenderIcon(UIImage *source, CGSize size, CGFloat scale, CGFloat cornerRadius,
                     BOOL masked, UIImage *mask, NSDictionary *dateSettings,
                     NSDictionary *daySettings, NSDate *date) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = scale;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        CGRect rect = (CGRect){CGPointZero, size};
        if (masked && mask == nil) {
            CGFloat radius = cornerRadius > 0 ? cornerRadius : MIN(size.width, size.height) * 0.225;
            [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:MIN(radius, MIN(size.width, size.height) / 2)] addClip];
        }
        [source drawInRect:rect];
        if (date != nil) {
            NSDateFormatter *formatter = [NSDateFormatter new];
            formatter.locale = NSLocale.currentLocale;
            formatter.calendar = NSCalendar.currentCalendar;
            formatter.timeZone = NSTimeZone.localTimeZone;
            formatter.dateFormat = @"d";
            TEDrawCalendarText([formatter stringFromDate:date], dateSettings, 30, UIColor.blackColor, 34, size);
            formatter.dateFormat = @"EEEE";
            TEDrawCalendarText([formatter stringFromDate:date], daySettings, 9, UIColor.redColor, 10, size);
        }
        if (masked && mask != nil) [mask drawInRect:rect blendMode:kCGBlendModeDestinationIn alpha:1];
    }];
}
