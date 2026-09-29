#import <UIKit/UIKit.h>
#import "../Common/PXGeometry.h"

NS_ASSUME_NONNULL_BEGIN

/// 截图任务协调器：接收请求、防重复、状态机、模式分发、结果输出调度。
/// 线程模型（防死锁核心约束）：
/// - 全部 UI 与流程推进都在主线程；
/// - taskLock 只保护 activeTask 指针与状态读写，绝不跨异步边界持有；
/// - 工程内禁止 dispatch_sync 到主线程的等待式写法（剪贴板单点除外且要求调用方在后台）；
/// - 后台只做图片处理，不碰任何 UI 对象。
@interface PXCaptureCoordinator : NSObject

+ (instancetype)sharedCoordinator;

/// %ctor 调用：初始化管线、清理上次残留的临时文件。
- (void)start;

/// Darwin 请求分发（主线程调用）。名称集中映射自 PXConstants。
- (void)handleDarwinNotificationName:(NSString *)name;

/// 发起截图请求（主线程调用；忙时静默丢弃并记录日志）。
- (void)requestCapture:(PXCaptureMode)mode;

/// 取消当前任务（任意线程；内部跳主线程执行）。
- (void)cancelActiveTask;

/// 外部图片直接进编辑器（结果气泡重编、SHELLX 插件转发共用入口；主线程调用；
/// 忙时静默丢弃并记录日志，isReedit 路径取消即结束）。
- (void)openEditorWithImage:(UIImage *)image mode:(PXCaptureMode)mode;

@end

NS_ASSUME_NONNULL_END
