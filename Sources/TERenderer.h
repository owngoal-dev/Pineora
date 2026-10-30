#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// 纯图片处理，离线测试与 SpringBoard 共用；不接触屏幕或主题文件。
FOUNDATION_EXPORT UIImage *TERenderIcon(UIImage *source, CGSize size, CGFloat scale,
    CGFloat cornerRadius, BOOL masked, UIImage * _Nullable mask,
    NSDictionary * _Nullable dateSettings, NSDictionary * _Nullable daySettings,
    NSDate * _Nullable date);
FOUNDATION_EXPORT UIImage *TEResizeImage(UIImage *source, CGSize size, CGFloat scale);
FOUNDATION_EXPORT UIFont *TEFontFromSettings(NSDictionary *settings, UIFont *fallback);
FOUNDATION_EXPORT UIColor *TEColorFromSettings(id _Nullable value, UIColor *fallback);
NS_ASSUME_NONNULL_END
