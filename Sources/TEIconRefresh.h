#import <Foundation/Foundation.h>

/// Refresh an existing SBIconView's image without rebinding or recreating its icon.
/// Returns NO when the system does not expose the expected runtime contract.
BOOL TERefreshIconImageView(id iconView);
