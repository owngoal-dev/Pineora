// Regenerate the Settings row icons on iOS; does not read or capture the screen.
// clang -arch arm64e -fobjc-arc -framework UIKit -framework QuartzCore -framework CoreGraphics \
//   Tools/GenerateSettingsIcon.m -o build/GenerateSettingsIcon
// ldid -SResearch/tools/Tool.entitlements build/GenerateSettingsIcon
// ./build/GenerateSettingsIcon Preferences/Resources
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc != 2 || argv[1][0] == '\0') {
            fprintf(stderr, "Usage: GenerateSettingsIcon <existing output directory>\n");
            return 1;
        }
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory) return 1;
        // Match Pineora's header: indigo tile, white semibold pointed brush.
        const CGFloat side = 29;
        UIView *tile = [[UIView alloc] initWithFrame:CGRectMake(0, 0, side, side)];
        tile.backgroundColor = [[UIColor systemIndigoColor] resolvedColorWithTraitCollection:
            [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark]];
        tile.layer.cornerRadius = side / 4;
        tile.layer.cornerCurve = kCACornerCurveContinuous;
        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration
            configurationWithPointSize:30 * side / 64 weight:UIImageSymbolWeightSemibold];
        UIImage *symbol = [UIImage systemImageNamed:@"paintbrush.pointed.fill" withConfiguration:configuration];
        if (!symbol) return 1;
        UIImageView *glyph = [[UIImageView alloc] initWithImage:symbol];
        glyph.tintColor = UIColor.whiteColor;
        glyph.contentMode = UIViewContentModeCenter;
        glyph.frame = tile.bounds;
        [tile addSubview:glyph];
        [tile layoutIfNeeded];
        for (NSUInteger scale = 1; scale <= 3; scale++) {
            UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
            format.scale = scale;
            format.opaque = NO;
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:tile.bounds.size format:format];
            UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [tile.layer renderInContext:context.CGContext];
            }];
            NSString *name = scale == 1 ? @"Pineora.png" : [NSString stringWithFormat:@"Pineora@%lux.png", (unsigned long)scale];
            NSError *error = nil;
            NSData *png = UIImagePNGRepresentation(image);
            if (!png || ![png writeToFile:[directory stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:&error]) {
                fprintf(stderr, "Could not write %s: %s\n", name.UTF8String, error.localizedDescription.UTF8String ?: "PNG encoding failed");
                return 1;
            }
            UIImage *decoded = [UIImage imageWithContentsOfFile:[directory stringByAppendingPathComponent:name]];
            if (!decoded || CGImageGetWidth(decoded.CGImage) != (size_t)(side * scale) || CGImageGetHeight(decoded.CGImage) != (size_t)(side * scale)) return 1;
            printf("Validated %s: %lux%lu pixels\n", name.UTF8String, (unsigned long)CGImageGetWidth(decoded.CGImage), (unsigned long)CGImageGetHeight(decoded.CGImage));
        }
    }
    return 0;
}
