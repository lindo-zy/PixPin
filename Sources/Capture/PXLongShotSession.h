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

/// 全屏手动滚动、自动采集会话：主线程推进，串行后台对齐/预览/导出。
/// 每个回调验证会话代次、任务 ID 和取消标记；分片文件只存任务临时目录。
@interface PXLongShotSession : NSObject

/// 创建并展示会话窗口（主线程调用）。任务须处于 Presenting。
+ (instancetype)startWithTask:(PXCaptureTask *)task
                      delegate:(id<PXLongShotSessionDelegate>)delegate;

/// 外部取消（Darwin cancel / 失败路径）：只清理自身，不回调 delegate。幂等。
- (void)teardownForExternalCancel;

/// 会话是否已收尾（窗口已销毁）。
@property (nonatomic, assign, readonly) BOOL isFinished;

@end

NS_ASSUME_NONNULL_END
