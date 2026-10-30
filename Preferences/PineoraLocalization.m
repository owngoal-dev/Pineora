#import "PineoraLocalization.h"
#import "PineoraStore.h"

NSString *PineoraLocalizedString(NSString *key) {
    // Settings is the host; translations belong to Pineora's preference bundle.
    NSBundle *bundle = [NSBundle bundleForClass:[PineoraStore class]];
    return [bundle localizedStringForKey:key value:nil table:nil];
}
