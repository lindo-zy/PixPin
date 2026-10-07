#import "../Common/PXShellXBridge.h"
#import "../Common/PXConstants.h"
#import "../Common/PXLog.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>

// SHELLX 出向桥实现（依据 SHELLX 插件文档 2/3 节 + ShellX 3.1.1 逆向报告 2.1/2.2 节）。
// 与入向注册（PXShellXPlugin）不同，这里不触碰 SHELLX 的 ObjC 接口：通知类动作只发
// Darwin 通知（文档约定 SHELLX 两个中心都监听，调用方每次只发一条），URL 类动作经
// SpringBoard 的 UIApplication openURL 打开 prefs:// 路由（快捷指令同链路，SHELLX 在
// URL 分发层拦截）。名与路由常量集中在 PXConstants，逐字取自 SHELLX 插件文档。
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
        case PXShellXActionArea:      return (__bridge NSString *)PXShellXTriggerArea;
        case PXShellXActionInstant:   return (__bridge NSString *)PXShellXTriggerInstant;
        case PXShellXActionFreeze:    return (__bridge NSString *)PXShellXTriggerFreeze;
        case PXShellXActionHistory:   return (__bridge NSString *)PXShellXTriggerHistory;
        case PXShellXActionOpenLast:  return (__bridge NSString *)PXShellXTriggerOpenLast;
        case PXShellXActionClose:     return (__bridge NSString *)PXShellXTriggerClose;
        // 整屏截一张走 AssistiveScreenshot 通知：真机实测该通知即整屏截一张（2026-10-07
        // 用户核对），与逆向报告「通知=套壳截图」的推断相反，以真机为准。
        case PXShellXActionFullShot:  return (__bridge NSString *)PXShellXTriggerAssistive;
        case PXShellXActionLongShot:
        case PXShellXActionMark:
        case PXShellXActionEdit:
        case PXShellXActionAI2:
        case PXShellXActionTranslate:
        case PXShellXActionScan:
        case PXShellXActionAssistive:
            return nil;   // 走 prefs:// 路由
    }
    return nil;
}

+ (NSURL *)urlForAction:(PXShellXAction)action {
    CFStringRef route = NULL;
    switch (action) {
        case PXShellXActionLongShot:  route = PXShellXRouteLong; break;
        // 套壳截图走 shellx_full 路由：真机实测该路由即套壳截图（2026-10-07 用户核对），
        // 与官方文档「shellx_full=整屏截一张」的表述相反，以真机为准。
        case PXShellXActionAssistive: route = PXShellXRouteFull; break;
        case PXShellXActionMark:      route = PXShellXRouteMark; break;
        case PXShellXActionEdit:      route = PXShellXRouteEdit; break;
        case PXShellXActionAI2:       route = PXShellXRouteAI2; break;
        case PXShellXActionTranslate: route = PXShellXRouteTranslate; break;
        case PXShellXActionScan:      route = PXShellXRouteScan; break;
        case PXShellXActionArea:
        case PXShellXActionInstant:
        case PXShellXActionFreeze:
        case PXShellXActionHistory:
        case PXShellXActionOpenLast:
        case PXShellXActionClose:
        case PXShellXActionFullShot:
            return nil;   // 通知类动作不走 URL
    }
    if (!route) return nil;
    return [NSURL URLWithString:(__bridge NSString *)route];
}

+ (void)notifyAction:(PXShellXAction)action {
    if (![self isInstalled]) {
        PXLogInfo(@"shellx notify skipped: not installed");
        return;
    }
    NSString *name = [self notificationNameForAction:action];
    if (name) {
        notify_post(name.UTF8String);
        PXLogInfo(@"shellx notify posted: %@", name);
        return;
    }
    NSURL *url = [self urlForAction:action];
    if (!url) return;
    // SpringBoard 本身是 UIApplication 子类实例，openURL 走系统 URL 分发层；
    // 本方 hook（PXSpringBoardEntry）对非 pixpin:// 一律放行，SHELLX 侧拦截触发。
    // 回调线程不确定，只打日志。SHELLX 未拦截时系统会打开设置页对应面板，可据此排查。
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        PXLogInfo(@"shellx url opened: %@ success=%d", url, success);
    }];
}

@end
