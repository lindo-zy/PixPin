#import "../Common/PXShellXBridge.h"
#import "../Common/PXConstants.h"
#import "../Common/PXLog.h"
#import <objc/runtime.h>
#import <notify.h>

// SHELLX 出向桥实现（依据 ShellX 3.1.1 逆向报告 2.1/2.2 节）。与入向注册
// （PXShellXPlugin）不同，这里只发 Darwin 通知、不触碰 SHELLX 的 ObjC 接口，
// 通知名常量集中在 PXConstants（逐字取自 SHELLX 二进制字符串表）。
// 探测不设重试链：调用时机全部是用户主动交互，远晚于 SpringBoard 注入期。

static NSString * const PXShellXPrefsDomain = @"com.iosdump.screenshotshell";
static NSString * const PXShellXMasterSwitchKey = @"GlobalEnabled";

@implementation PXShellXBridge

+ (BOOL)isInstalled {
    return objc_getClass("SHELLXPluginManager") != nil;
}

+ (BOOL)masterSwitchEnabled {
    if (![self isInstalled]) return NO;
    CFPreferencesAppSynchronize((__bridge CFStringRef)PXShellXPrefsDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(
        (__bridge CFStringRef)PXShellXMasterSwitchKey,
        (__bridge CFStringRef)PXShellXPrefsDomain));
    return [value isKindOfClass:[NSNumber class]] && [(NSNumber *)value boolValue];
}

+ (BOOL)toolbarAvailable {
    return [self isInstalled] && [self masterSwitchEnabled];
}

+ (NSString *)notificationNameForAction:(PXShellXAction)action {
    switch (action) {
        case PXShellXActionArea:     return (__bridge NSString *)PXShellXTriggerArea;
        case PXShellXActionInstant:  return (__bridge NSString *)PXShellXTriggerInstant;
        case PXShellXActionFreeze:   return (__bridge NSString *)PXShellXTriggerFreeze;
        case PXShellXActionClose:    return (__bridge NSString *)PXShellXTriggerClose;
        case PXShellXActionAssistive: return (__bridge NSString *)PXShellXTriggerAssistive;
    }
    return nil;
}

+ (void)notifyAction:(PXShellXAction)action {
    NSString *name = [self notificationNameForAction:action];
    if (!name) return;
    if (![self isInstalled]) {
        PXLogInfo(@"shellx notify skipped: not installed");
        return;
    }
    notify_post(name.UTF8String);
    PXLogInfo(@"shellx notify posted: %@", name);
}

@end
