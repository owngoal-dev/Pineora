#pragma once
#import <UIKit/UIKit.h>
// 布局由本机 SpringBoardHome 只读反射核实：四个 double。
typedef struct { CGSize size; CGFloat scale; CGFloat continuousCornerRadius; } TEIconImageInfo;
FOUNDATION_EXPORT TEIconImageInfo TEImageInfoForObject(id object);
FOUNDATION_EXPORT void TEInstallExtensionHooks(void);
FOUNDATION_EXPORT void TERefreshExtensionViews(void);
