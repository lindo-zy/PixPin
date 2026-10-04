#import <UIKit/UIKit.h>
#import "../Common/PXGeometry.h"

NS_ASSUME_NONNULL_BEGIN

@class PXCaptureTask;
@class PXLongShotSession;

@protocol PXLongShotSessionDelegate <NSObject>
/// 拼接成功。会话自身已开始收尾，协调器接手输出动作。
- (void)longShotSessionDidFinish:(PXLongShotSession *)session resultImage:(UIImage *)image;
/// 用户主动取消（HUD 取消键或锁屏）。会话已自行清理窗口与临时引用。
- (void)longShotSessionDidCancel:(PXLongShotSession *)session;
/// 拼接失败，走任务失败路径（诊断气泡）。
- (void)longShotSessionDidFail:(PXLongShotSession *)session message:(NSString *)message;
@end

/// 手动滚动长截图会话：用户在前台 App 自己滚动，逐段点「截取」，点「完成」后台拼接。
/// 线程模型与协调器一致：全部流程推进在主线程，后台只做图像处理；
/// 每个异步回调都复查任务状态，取消后到达的回调一律丢弃。
/// 分片 JPEG 落任务临时目录，内存中只驻留行签名；拼接画布受像素预算约束。
@interface PXLongShotSession : NSObject

/// 创建并展示会话窗口（主线程调用）。任务须处于 Presenting。
+ (instancetype)startWithTask:(PXCaptureTask *)task
                   displayRect:(CGRect)displayRect
                      delegate:(id<PXLongShotSessionDelegate>)delegate;

/// 外部取消（Darwin cancel / 失败路径）：只清理自身，不回调 delegate。幂等。
- (void)teardownForExternalCancel;

/// 会话是否已收尾（窗口已销毁）。
@property (nonatomic, assign, readonly) BOOL isFinished;

@end

NS_ASSUME_NONNULL_END
