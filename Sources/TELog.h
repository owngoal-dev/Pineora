// ThemeEngine 的统一日志入口。subsystem 为包 ID，apelin_log_read 按它过滤。
#pragma once

#import <os/log.h>
#import <Foundation/Foundation.h>

static inline os_log_t TELog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create(APELIN_PACKAGE_ID, "engine");
    });
    return log;
}
