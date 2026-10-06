#import <UIKit/UIKit.h>
#import "../Common/PXGeometry.h"
#import "../Common/PXLongShotOptions.h"

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

/// 三种采集策略共用逐段管线；主线程状态机、串行后台帧存储和导出。
/// 创建后等待「截取」；智能每次保存当前段后短滑，自动重复同一步骤，采样由用户滚动。
/// displayRect 在所有模式中都限定采集范围，任务首屏快照不作为稍后截取的第一帧。
@interface PXLongShotSession : NSObject
+ (instancetype)startWithTask:(PXCaptureTask *)task
                         mode:(PXLongShotMode)mode
                  displayRect:(CGRect)displayRect
                     delegate:(id<PXLongShotSessionDelegate>)delegate;

/// 外部取消（Darwin cancel / 失败路径）：只清理自身，不回调 delegate。幂等。
- (void)teardownForExternalCancel;

/// 会话是否已收尾（窗口已销毁）。
@property (nonatomic, assign, readonly) BOOL isFinished;

@end

NS_ASSUME_NONNULL_END
