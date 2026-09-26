#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "../Common/PXConstants.h"
#import "../Common/PXExternalRequest.h"
#import "../Common/PXLog.h"
#import "../Capture/PXCaptureCoordinator.h"

// 跨进程请求入口：Darwin 通知只携带名称，不携带数据（DEVELOPMENT.md 2.2）。
// 回调线程不确定，统一跳主线程后交给协调器分发。

static void PXDispatchExternalRequest(NSString *name, NSString *source) {
    dispatch_async(dispatch_get_main_queue(), ^{
        PXLogInfo(@"external request source=%@ action=%@", source, name);
        [[PXCaptureCoordinator sharedCoordinator] handleDarwinNotificationName:name];
    });
}

static void PXHandleDarwinNotification(CFNotificationCenterRef center,
                                       void *observer,
                                       CFStringRef name,
                                       const void *object,
                                       CFDictionaryRef userInfo) {
    if (name) PXDispatchExternalRequest([(__bridge NSString *)name copy], @"darwin");
}

// withResult / withCompletion 为 FrontBoard 的 NSError * 回调；nil 表示请求已接收，
// 不表示图片已保存。只消费自己的 scheme，且消费后绝不调用原方法或再发一次通知。
typedef void (^PXOpenCompletion)(NSError *error);

static BOOL PXConsumeExternalURL(NSURL *url, PXOpenCompletion completion) {
    if (!PXIsExternalURL(url)) return NO;
    NSString *name = PXNotificationNameForExternalURL(url);
    if (name) {
        PXDispatchExternalRequest(name, @"url");
    } else {
        PXLogWarn(@"external URL rejected: invalid command");
    }
    if (completion) {
        completion(name ? nil : [NSError errorWithDomain:PXBundleID code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid PixPin command"}]);
    }
    return YES;
}

// 普通 App 通过 FrontBoard 发来的 URL 请求；本地 PullOver-X 使用同一接收点。
static id PXReadRequestObject(id object, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSURL *PXURLFromOpenRequest(id request) {
    id options = PXReadRequestObject(request, @"options");
    id value = PXReadRequestObject(options, @"url");
    if ([value isKindOfClass:NSURL.class]) return value;
    id dictionary = [options isKindOfClass:NSDictionary.class]
        ? options : PXReadRequestObject(options, @"dictionary");
    value = [dictionary isKindOfClass:NSDictionary.class] ? dictionary[@"__PayloadURL"] : nil;
    if ([value isKindOfClass:NSURL.class]) return value;
    return [value isKindOfClass:NSString.class] ? [NSURL URLWithString:value] : nil;
}

static void (*PXOriginalWorkspaceOpen)(id, SEL, id, id, PXOpenCompletion);
static void PXWorkspaceOpen(id self, SEL cmd, id service, id request, PXOpenCompletion completion) {
    if (PXConsumeExternalURL(PXURLFromOpenRequest(request), completion)) return;
    PXOriginalWorkspaceOpen(self, cmd, service, request, completion);
}

// SpringBoard 自身及其他插件的直接 URL 请求。系统版本之间存在带/不带
// notifyLSOnFailure 的两种入口，分别检查后安装，不猜测不存在的方法。
static void (*PXOriginalSpringBoardOpen)(id, SEL, NSURL *, id, BOOL, id, id, PXOpenCompletion);
static void PXSpringBoardOpen(id self, SEL cmd, NSURL *url, id app, BOOL animated,
                             id settings, id origin, PXOpenCompletion result) {
    if (PXConsumeExternalURL(url, result)) return;
    PXOriginalSpringBoardOpen(self, cmd, url, app, animated, settings, origin, result);
}

static void (*PXOriginalSpringBoardOpenNotify)(id, SEL, NSURL *, id, BOOL, id, id, BOOL, PXOpenCompletion);
static void PXSpringBoardOpenNotify(id self, SEL cmd, NSURL *url, id app, BOOL animated,
                                   id settings, id origin, BOOL notifyLS, PXOpenCompletion result) {
    if (PXConsumeExternalURL(url, result)) return;
    PXOriginalSpringBoardOpenNotify(self, cmd, url, app, animated, settings, origin, notifyLS, result);
}

static void PXInstallURLHook(Class cls, NSString *selectorName, IMP replacement, IMP *original) {
    SEL selector = NSSelectorFromString(selectorName);
    if (cls && class_getInstanceMethod(cls, selector)) {
        MSHookMessageEx(cls, selector, replacement, original);
        PXLogInfo(@"external URL hook installed: %@", selectorName);
    } else {
        PXLogWarn(@"external URL hook unavailable: %@", selectorName);
    }
}

%ctor {
    // 协调器构造会操作 UIDevice / 通知观察者，初始化也统一放到主线程。
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            [[PXCaptureCoordinator sharedCoordinator] start];

            CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
            CFStringRef names[] = {
                PXDarwinActivate,
                PXDarwinCaptureFull,
                PXDarwinCaptureArea,
                PXDarwinCaptureFreeze,
                PXDarwinCaptureInstant,
                PXDarwinCaptureMarkup,
                PXDarwinCaptureCancel,
                PXDarwinPreferencesReload,
            };
            for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
                CFNotificationCenterAddObserver(center,
                                                NULL,
                                                PXHandleDarwinNotification,
                                                names[i],
                                                NULL,
                                                CFNotificationSuspensionBehaviorDeliverImmediately);
            }

            PXInstallURLHook(NSClassFromString(@"SBMainWorkspace"),
                @"systemService:handleOpenApplicationRequest:withCompletion:",
                (IMP)PXWorkspaceOpen, (IMP *)&PXOriginalWorkspaceOpen);
            Class springBoard = NSClassFromString(@"SpringBoard");
            PXInstallURLHook(springBoard,
                @"applicationOpenURL:withApplication:animating:activationSettings:origin:withResult:",
                (IMP)PXSpringBoardOpen, (IMP *)&PXOriginalSpringBoardOpen);
            PXInstallURLHook(springBoard,
                @"applicationOpenURL:withApplication:animating:activationSettings:origin:notifyLSOnFailure:withResult:",
                (IMP)PXSpringBoardOpenNotify, (IMP *)&PXOriginalSpringBoardOpenNotify);

            PXLogInfo(@"loaded into SpringBoard");
        } @catch (NSException *exception) {
            PXLogError(@"ctor exception: %@", exception);
        }
    });
}
