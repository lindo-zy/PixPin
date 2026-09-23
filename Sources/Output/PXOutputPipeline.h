#import <UIKit/UIKit.h>
#import "../Common/PXGeometry.h"

@class PXCaptureTask;

NS_ASSUME_NONNULL_BEGIN

/// 输出管线：所有相册/剪贴板/分享动作的唯一入口。
/// UI 层禁止直接调用 PHPhotoLibrary / UIPasteboard（DEVELOPMENT.md 5.7）。
/// 幂等由 PXCaptureTask.claimOutputAction 保证；同一任务重复触发不会产生重复资源。
@interface PXOutputPipeline : NSObject

/// 当前任务执行默认动作。completion 永远在主线程；ok 表示全部子动作成功。
- (void)performAction:(PXOutputAction)action
              forTask:(PXCaptureTask *)task
      presentingWindow:(nullable UIWindow *)presentingWindow
           completion:(void (^)(BOOL ok, NSString *message))completion;

@end

NS_ASSUME_NONNULL_END
