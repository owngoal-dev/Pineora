// 图标仓库：读设置、扫描主题、按 bundle id + 倍率取图并缓存。
// 设置文件（系统路径，不经 bootstrap 转换）：
//   /var/mobile/Library/Preferences/<package id>.plist
// 键：
//   Enabled                  BOOL，默认 YES
//   Themes                   array<string>，主题目录（绝对路径或 /Library/Themes 下的名字）
//   ImportSnowBoardThemes    BOOL，默认 YES：没有 Themes 时沿用 SnowBoard 的 LoadedThemes
//   FuzzyBundleIdentifiers   BOOL，默认 YES
#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "TETheme.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TEStoreDidReloadNotification;  // 进程内通知名

@interface TEIconStore : NSObject

+ (instancetype)sharedStore;

@property (atomic, assign, readonly) BOOL enabled;
@property (atomic, copy, readonly) NSArray<TETheme *> *themes;

/// 重新读设置与主题（幂等，可反复调用）。返回解析成功的主题数。
- (NSInteger)reload;

/// 清空本进程的图片缓存（不影响 SpringBoard 自己的图标缓存）。
- (void)invalidateImageCache;

/// 指定 bundle 与倍率的图标；没有主题文件时为 nil。
- (nullable UIImage *)imageForBundleIdentifier:(NSString *)bundleIdentifier scale:(NSInteger)scale;

/// 指定渲染尺寸及蒙版状态；避免把原始 PNG 直接交给已蒙版缓存。
- (nullable UIImage *)imageForBundleIdentifier:(NSString *)bundleIdentifier size:(CGSize)size
    scale:(CGFloat)scale cornerRadius:(CGFloat)cornerRadius masked:(BOOL)masked;
/// 按已启用主题顺序取扩展资源；不包含路径时为 nil。
- (nullable UIImage *)resourceImageForBundleIdentifier:(NSString *)bundleIdentifier
    name:(NSString *)name size:(CGSize)size scale:(CGFloat)scale;
- (nullable UIImage *)rawResourceForBundleIdentifier:(NSString *)bundleIdentifier
    name:(NSString *)name scale:(NSInteger)scale;
- (NSDictionary *)settingsForKey:(NSString *)key;

/// 同上，但只返回路径。
- (nullable NSString *)iconPathForBundleIdentifier:(NSString *)bundleIdentifier scale:(NSInteger)scale;

/// 主题搜索目录（逻辑路径已解析为可打开路径）。
- (NSArray<NSString *> *)themeSearchDirectories;

@end

NS_ASSUME_NONNULL_END
