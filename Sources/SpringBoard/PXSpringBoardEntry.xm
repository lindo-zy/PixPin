#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../Common/PXConstants.h"
#import "../Common/PXLog.h"
#import "../Capture/PXCaptureCoordinator.h"

// 跨进程请求入口：Darwin 通知只携带名称，不携带数据（DEVELOPMENT.md 2.2）。
// 回调线程不确定，统一跳主线程后交给协调器分发。

static void PXHandleDarwinNotification(CFNotificationCenterRef center,
                                       void *observer,
                                       CFStringRef name,
                                       const void *object,
                                       CFDictionaryRef userInfo) {
    NSString *nameString = (__bridge NSString *)name;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[PXCaptureCoordinator sharedCoordinator] handleDarwinNotificationName:nameString];
    });
}

%ctor {
    @try {
        [[PXCaptureCoordinator sharedCoordinator] start];

        CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
        CFStringRef names[] = {
            PXDarwinCaptureFull,
            PXDarwinCaptureArea,
            PXDarwinCaptureFreeze,
            PXDarwinCaptureInstant,
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

        PXLogInfo(@"loaded into SpringBoard");
    } @catch (NSException *exception) {
        PXLogError(@"ctor exception: %@", exception);
    }
}
