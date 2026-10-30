// 一个 .theme 目录的解析结果。
// 支持 IconBundles/<bundleID>[-large][@Nx][~iphone|~ipad].png，
// Bundles/<bundleID>/（或带 Info.plist 的 *.bundle）、旧 <bundleID>/、Folders/<bundleID>/。
// Info.plist 的 Icons 字典可显式声明 bundleID -> 主题内相对文件名（或数组）。
#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TETheme : NSObject

@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, assign, readonly) BOOL legacy;

/// 原始 Info.plist 元数据；缺失或无效时为空字典。
@property (nonatomic, copy, readonly) NSDictionary *info;

/// bundleID -> (scale -> 绝对路径)。布局依次优先 IconBundles / Bundles / 旧目录 / Folders / Icons；
/// 同布局同倍率优先当前设备变体，再按应用图标名称和字典序稳定选择。
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSDictionary<NSNumber *, NSString *> *> *iconPaths;

/// 解析失败（目录不可读）时返回 nil。
+ (nullable instancetype)themeAtPath:(NSString *)path;

/// 取某 bundle 指定倍率的图标路径；精确 ID 优先，模糊仅允许请求 ID 以“已收录 ID.”开头，选最长 ID。
/// 倍率按 精确 -> 3x -> 2x -> 1x -> 最大 回退。
- (nullable NSString *)iconPathForBundleIdentifier:(NSString *)bundleIdentifier scale:(NSInteger)scale;

/// 查找扩展资源，不加入 iconPaths；bundle ID 必须精确匹配（不模糊）。
/// 按 Bundles / 旧目录 / Folders 查找；每个布局内优先请求倍率的设备变体，
/// 再回退 3x / 2x / 1x 的设备变体与通用变体，最后另一设备变体。
/// resourceName 可带 .png、倍率或设备后缀；仅允许主题内安全相对路径，默认扩展名 png。
- (nullable NSString *)resourcePathForBundleIdentifier:(NSString *)bundleIdentifier
                                        resourceName:(NSString *)resourceName
                                               scale:(NSInteger)scale;

@end

NS_ASSUME_NONNULL_END
