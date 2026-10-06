#import "PXOutputPipeline.h"
#import "PXPhotoWriter.h"
#import "PXClipboardWriter.h"
#import "PXSharePresenter.h"
#import "PXTemporaryFileStore.h"
#import "../Capture/PXCaptureTask.h"
#import "../Common/PXLog.h"

@implementation PXOutputPipeline

- (void)performAction:(PXOutputAction)action
              forTask:(PXCaptureTask *)task
     presentingWindow:(UIWindow *)presentingWindow
           completion:(void (^)(BOOL, NSString *))completion {
    void (^runOnMain)(void) = ^{
        [self pxPerformAction:action forTask:task presentingWindow:presentingWindow completion:completion];
    };
    if ([NSThread isMainThread]) {
        runOnMain();
    } else {
        dispatch_async(dispatch_get_main_queue(), runOnMain);
    }
}

#pragma mark - 动作分发

- (void)pxPerformAction:(PXOutputAction)action
                forTask:(PXCaptureTask *)task
       presentingWindow:(UIWindow *)presentingWindow
             completion:(void (^)(BOOL, NSString *))completion {
    if (!task) {
        completion(NO, @"任务无效");
        return;
    }

    switch (action) {
        case PXOutputActionPreviewOnly:
            completion(YES, nil);
            return;

        case PXOutputActionSave: {
            if (![task claimOutputAction:PXOutputActionSave]) {
                completion(YES, nil);
                return;
            }
            [self pxRunSave:task completion:completion];
            return;
        }

        case PXOutputActionCopy: {
            if (![task claimOutputAction:PXOutputActionCopy]) {
                completion(YES, nil);
                return;
            }
            [self pxRunCopy:task completion:completion];
            return;
        }

        case PXOutputActionSaveAndCopy: {
            BOOL needSave = [task claimOutputAction:PXOutputActionSave];
            BOOL needCopy = [task claimOutputAction:PXOutputActionCopy];
            if (!needSave && !needCopy) {
                completion(YES, nil);
                return;
            }
            [self pxRunCopyIfNeeded:task needCopy:needCopy completion:^(BOOL copyOK, NSString *copyMsg) {
                if (!needSave) {
                    completion(copyOK, copyMsg);
                    return;
                }
                [self pxRunSave:task completion:^(BOOL saveOK, NSString *saveMsg) {
                    completion(copyOK && saveOK, saveOK ? @"已保存并复制" : saveMsg);
                }];
            }];
            return;
        }

        case PXOutputActionShare: {
            if (![task claimOutputAction:PXOutputActionShare]) {
                completion(YES, nil);
                return;
            }
            [self pxRunShare:task presentingWindow:presentingWindow completion:completion];
            return;
        }

        case PXOutputActionSaveAndDeleteSource: {
            // 第一版不实现删除原图（必须是显式设置，且依赖相册资产 ID 查询），降级为普通保存。
            PXLogWarn(@"save+delete-source not implemented, falling back to plain save");
            if (![task claimOutputAction:PXOutputActionSave]) {
                completion(YES, nil);
                return;
            }
            [self pxRunSave:task completion:completion];
            return;
        }
    }
}

#pragma mark - 状态守卫

/// 输出动作允许的任务状态：Exporting（正常输出）与 Finished/Failed
/// （气泡快捷动作、失败重试）都放行；仅拒绝取消路径与空闲
/// （DEVELOPMENT.md 5.1：任务取消时不得继续写入相册）。
static BOOL PXOutputAllowedForState(PXCaptureState state) {
    switch (state) {
        case PXCaptureStateIdle:
        case PXCaptureStateCancelling:
        case PXCaptureStateCancelled:
            return NO;
        default:
            return YES;
    }
}

#pragma mark - 子动作

- (void)pxRunSave:(PXCaptureTask *)task completion:(void (^)(BOOL, NSString *))completion {
    UIImage *image = task.resultImage ?: task.baseImage;
    if (!image) {
        completion(NO, @"没有可保存的结果");
        return;
    }
    if (!PXOutputAllowedForState([task currentState])) {
        [task unclaimOutputAction:PXOutputActionSave];   // 回滚认领，允许后续重试
        completion(NO, @"任务已取消");
        return;
    }

    // 全尺寸 JPEG 编码与临时文件写入放后台队列，不阻塞 SpringBoard 主线程。
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            // 后台执行前复查取消态：收口“检查与执行之间发生取消”的窗口。
            if (!PXOutputAllowedForState([task currentState])) {
                [task unclaimOutputAction:PXOutputActionSave];
                dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, @"任务已取消"); });
                return;
            }
            // 已有落盘产物（长图 longshot.jpg）时不再重复 JPEG 编码：UIImageJPEGRepresentation
            // 的整幅解码是保存期最大内存尖峰，可恢复副本本来就已存在。
            NSString *stagedPath = task.resultFilePath;
            BOOL hasStagedFile = stagedPath.length > 0 &&
                [[NSFileManager defaultManager] fileExistsAtPath:stagedPath];
            if (!hasStagedFile) {
                // 保存前先落盘临时文件：相册失败时保留可恢复副本。
                [PXTemporaryFileStore writeImage:image taskID:task.taskID name:@"original.jpg" error:nil];
            }

            // 授权回调在 SpringBoard 内不保证到达（DEVELOPMENT.md 11.4）：超时兜底为失败并
            // 保留临时副本，避免任务永久卡在 exporting。settled 只在主线程读写（回调链固定主线程）。
            static const NSTimeInterval PXPhotoSaveTimeout = 15.0;
            __block BOOL settled = NO;
            // 超时块经 pendingCompletion 间接持有回调，taskID 单独拷贝：保存结束后
            // saveCompletion 立即置空回调，任务与结果图不被 15 秒计时扣到结束才释放。
            __block void (^pendingCompletion)(BOOL, NSString *) = completion;
            NSString *timedOutTaskID = [task.taskID copy];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PXPhotoSaveTimeout * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (settled) return;
                settled = YES;
                void (^fire)(BOOL, NSString *) = pendingCompletion;
                pendingCompletion = nil;
                if (!fire) return;
                PXLogError(@"photo save timed out (task %@), temp kept", timedOutTaskID);
                fire(NO, @"相册保存超时，已保留临时副本");
            });

            void (^saveCompletion)(NSString *, NSError *) = ^(NSString *identifier, NSError *error) {
                pendingCompletion = nil;   // 保存已结束：立即释放超时兜底持有的回调
                if (settled) return;   // 超时已兜底，丢弃迟到回调
                settled = YES;
                if (error) {
                    PXLogError(@"photo save failed: %@ (task %@, temp kept)", error, task.taskID);
                    completion(NO, @"相册保存失败，已保留临时副本");
                    return;
                }
                task.savedAssetIdentifier = identifier;
                PXLogInfo(@"photo saved: %@ (task %@)", identifier ?: @"(no id)", task.taskID);
                completion(YES, @"已保存到相册");
            };
            if (hasStagedFile) {
                // 文件直存：JPEG 原样入库，不做整幅解码/重编码（PXPhotoWriter）。
                [PXPhotoWriter saveImageFileAtPath:stagedPath completion:saveCompletion];
            } else {
                [PXPhotoWriter saveImage:image completion:saveCompletion];
            }
        }
    });
}

- (void)pxRunCopyIfNeeded:(PXCaptureTask *)task
                 needCopy:(BOOL)needCopy
               completion:(void (^)(BOOL, NSString *))completion {
    if (!needCopy) {
        completion(YES, nil);
        return;
    }
    [self pxRunCopy:task completion:completion];
}

- (void)pxRunCopy:(PXCaptureTask *)task completion:(void (^)(BOOL, NSString *))completion {
    UIImage *image = task.resultImage ?: task.baseImage;
    if (!image) {
        completion(NO, @"没有可复制的结果");
        return;
    }
    if (!PXOutputAllowedForState([task currentState])) {
        [task unclaimOutputAction:PXOutputActionCopy];
        completion(NO, @"任务已取消");
        return;
    }
    // PNG 编码放后台队列，最终写入回主线程（写入方内部保证线程切换）。
    [PXClipboardWriter copyImageAsync:image completion:^(BOOL ok) {
        completion(ok, ok ? @"已复制到剪贴板" : @"复制失败");
    }];
}

- (void)pxRunShare:(PXCaptureTask *)task
   presentingWindow:(UIWindow *)presentingWindow
         completion:(void (^)(BOOL, NSString *))completion {
    UIImage *image = task.resultImage ?: task.baseImage;
    UIViewController *host = presentingWindow.rootViewController;
    if (!image || !PXOutputAllowedForState([task currentState])) {
        [task unclaimOutputAction:PXOutputActionShare];
        completion(NO, @"任务已取消");
        return;
    }
    [PXSharePresenter shareImage:image fromViewController:host completion:^(BOOL completed) {
        completion(completed, completed ? @"分享完成" : @"分享已取消");
    }];
}

@end
