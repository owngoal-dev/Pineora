// Pineora 设置模型：读写引擎的设置文件、列出主题、发刷新通知。
//
// 与 Sources/TEIconStore.m 的约定（以代码为准）：
//   文件  /var/mobile/Library/Preferences/<包 ID>.plist（系统路径，直接读写，不经 cfprefsd：
//         引擎用 dictionaryWithContentsOfFile: 读它，cfprefsd 懒写盘且 roothide 会重定向）
//   键    Enabled (BOOL)、Themes (array<主题目录名>)；其余键原样保留
//   刷新  Darwin 通知 <包 ID>/refresh
// Themes 只写目录名（X.theme）不写绝对路径：引擎在 roothide 下解析不了 /Library/Themes/… 这种逻辑路径。
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PineoraThemeItem : NSObject
@property (nonatomic, copy, readonly) NSString *name;   // 目录名，写进 Themes
@property (nonatomic, copy, readonly) NSString *path;   // 可打开的真实路径
@property (nonatomic, copy, readonly) NSString *title;  // 去掉 .theme 的显示名
@property (nonatomic, assign) NSInteger iconCount;      // 解析前为 -1
@property (nonatomic, strong, nullable) UIImage *preview;
@property (nonatomic, copy, nullable) NSString *summary; // 应用图标数与扩展能力
@end

@interface PineoraStore : NSObject

@property (nonatomic, assign, readonly) BOOL enabled;
/// 按优先级排列；没有显式选择时是引擎此刻会用的主题。
@property (nonatomic, copy, readonly) NSArray<PineoraThemeItem *> *activeThemes;
@property (nonatomic, copy, readonly) NSArray<PineoraThemeItem *> *inactiveThemes;
/// 设置文件里有 Themes 数组（可以为空）。为 NO 时沿用 SnowBoard 的 LoadedThemes，再没有就启用全部主题。
@property (nonatomic, assign, readonly) BOOL hasExplicitSelection;
/// Themes 里有、但两个主题目录里都找不到的名字；保存时原样留在末尾。
@property (nonatomic, copy, readonly) NSArray<NSString *> *missingThemeNames;
/// 保存过、但还没发刷新通知。
@property (nonatomic, assign, readonly) BOOL hasUnappliedChanges;
@property (nonatomic, copy, readonly) NSArray<NSString *> *searchDirectories;

/// 重读设置文件与主题目录。
- (void)reload;
/// 在后台解析每个主题的图标数与预览图，完成后在主线程回调。
- (void)loadDetails:(void (^)(void))completion;

- (void)setEnabled:(BOOL)enabled;
- (void)activateTheme:(PineoraThemeItem *)theme;
- (void)deactivateTheme:(PineoraThemeItem *)theme;
- (void)moveActiveThemeAtIndex:(NSUInteger)from toIndex:(NSUInteger)to;

/// 发 <包 ID>/refresh，让 SpringBoard 重扫主题并清图标缓存。
- (void)apply;

@end

NS_ASSUME_NONNULL_END
