// 一个 .theme 目录的解析结果。
// 主题格式（对齐 SnowBoard 观察到的三种布局）：
//   1. 现代：IconBundles/<bundleID>[@2x|@3x].png
//   2. 兼容：Bundles/<名字>.bundle/Info.plist(CFBundleIdentifier) + AppIcon*.png
//   3. 旧版：<bundleID>/appicon[@2x].png、icon@2x.png、iconlarge.png
// 另外 Info.plist 里的 Icons 字典可以显式声明 bundleID -> 文件名（或文件名数组）。
#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TETheme : NSObject

@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, assign, readonly) BOOL legacy;

/// bundleID -> (scale -> 绝对路径)。同一 bundle/scale 先出现的优先。
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSDictionary<NSNumber *, NSString *> *> *iconPaths;

/// 解析失败（目录不可读）时返回 nil。
+ (nullable instancetype)themeAtPath:(NSString *)path;

/// 取某 bundle 指定倍率的图标路径；找不到时按 精确 -> 3x -> 2x -> 1x -> 最大 回退。
- (nullable NSString *)iconPathForBundleIdentifier:(NSString *)bundleIdentifier scale:(NSInteger)scale;

@end

NS_ASSUME_NONNULL_END
