// 运行时兼容层：私有类查找、方法探测、安全打补丁。
// 所有系统类都只在运行时按名字取，不链接任何私有框架。
#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "ApelinBootstrap.h"

NS_ASSUME_NONNULL_BEGIN

/// 把 bootstrap 逻辑路径（/Library/…）变成进程能打开的真实路径；
/// 系统路径（/var/mobile/…、/System/…）不要经过它。
NSString *_Nullable TEBootstrapFilePath(NSString *path);

/// 该类是否存在这个实例方法 / 类方法。
BOOL TEHasInstanceMethod(NSString *className, NSString *selectorName);
BOOL TEHasClassMethod(NSString *className, NSString *selectorName);

/// 仅当类和方法都存在时才安装钩子；返回是否装上。
BOOL TEInstallInstanceHook(NSString *className, NSString *selectorName,
                           IMP replacement, IMP _Nullable *_Nonnull original);
BOOL TEInstallClassHook(NSString *className, NSString *selectorName,
                        IMP replacement, IMP _Nullable *_Nonnull original);

/// 安全地取一个无参方法的对象返回值（不存在或抛异常时为 nil）。
id _Nullable TECallObject(id target, NSString *selectorName);
id _Nullable TECallClassObject(NSString *className, NSString *selectorName);

/// 在对象上依次尝试若干选择器，返回第一个非空字符串结果。
NSString *_Nullable TEStringForSelectors(id object, NSArray<NSString *> *selectorNames);

NS_ASSUME_NONNULL_END
