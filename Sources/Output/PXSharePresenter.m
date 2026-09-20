#import "PXSharePresenter.h"
#import "../Common/PXConstants.h"
#import "../Common/PXLog.h"

@implementation PXSharePresenter

+ (void)shareImage:(UIImage *)image
            fromViewController:(UIViewController *)hostViewController
                    completion:(void (^)(BOOL))completion {
    if (!image) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
        return;
    }

    if (!hostViewController) {
        // 没有可用宿主时降级：后台写入临时根目录（随下次启动 sweep 清理），保证图片不丢。
        NSString *path = [PXTemporaryTasksRoot() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"share_%@.jpg", [NSUUID UUID].UUIDString]];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                NSData *data = UIImageJPEGRepresentation(image, 0.95);
                [data writeToFile:path atomically:YES];
                PXLogWarn(@"no host for share sheet, image dumped to %@", path);
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
        });
        return;
    }

    UIActivityViewController *activity = [[UIActivityViewController alloc]
                                          initWithActivityItems:@[image]
                                          applicationActivities:nil];
    activity.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed,
                                            NSArray *returnedItems, NSError *activityError) {
        if (activityError) {
            PXLogError(@"share activity error: %@", activityError);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(completed); });
    };

    dispatch_async(dispatch_get_main_queue(), ^{
        // present 失败（宿主已有 presented VC、窗口不可见等）时 completionWithItemsHandler
        // 不会触发，completion 必须兜底回调，否则任务卡在分享态、气泡 hold 永不释放。
        if (hostViewController.presentedViewController) {
            PXLogError(@"share sheet skipped: host already presenting %@", hostViewController);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }
        @try {
            [hostViewController presentViewController:activity animated:YES completion:nil];
            if (!hostViewController.presentedViewController) {
                PXLogError(@"share sheet present failed");
                dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            }
        } @catch (NSException *exception) {
            PXLogError(@"share sheet present exception: %@", exception);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
        }
    });
}

@end
