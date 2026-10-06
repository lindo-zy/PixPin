#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const PXCaptureErrorDomain;

typedef NS_ENUM(NSInteger, PXCaptureError) {
    PXCaptureErrorNoSource = 1,           // 所有抓取路径都不可用
    PXCaptureErrorCaptureFailed = 2,      // 抓屏返回空结果
    PXCaptureErrorUnexpectedGeometry = 3, // 抓屏结果与屏幕几何不一致，宁可失败也不产出错误裁剪
};

/// 截图能力适配层：私有 API 只允许出现在本层，全部运行期 dlsym 解析。
/// 多级抓取策略（按序尝试，取第一个成功者）：
///   1. private-uicreate     — UIKit 私有 _UICreateScreenUIImage（整屏合成图）
///   2. private-uigetscreen  — UIKit 私有 UIGetScreenImage（整屏缓冲）
///   3. fallback-snapshot    — 公开 UIScreen 快照视图渲染（只能捕到 SpringBoard 自身窗口，结果标记 partial）
/// 返回的图片已归一化：upright、image.size = 屏幕点尺寸、image.scale = 屏幕缩放。
/// 回调永远在主线程。
@interface PXCaptureProvider : NSObject

/// 启动时解析结果（供启动日志）：private-uicreate / private-uigetscreen / fallback-snapshot。
+ (NSString *)resolvedCaptureMethod;

/// 最近一次抓屏实际使用的策略（主线程更新）。
@property (nonatomic, copy, readonly, nullable) NSString *lastCaptureMethod;
/// 内存保护降级开关（主线程读写）：跳过窗口排除 API，尝试整屏私有抓屏。
/// 普通路径先隐藏自有窗口；保持可见模式通过图层捕获排除后允许整屏私有抓屏。
@property (nonatomic, assign) BOOL fallbackOnlyCapture;
/// 长截图浮窗保持可见：优先配置图层捕获排除并使用原整屏私有抓屏路径。
/// 默认 NO，不改变其他截图调用方。
@property (nonatomic, assign) BOOL keepsExcludedWindowsVisible;
/// 连续采集专用：把抓屏表面绘制为独立 RGBA 位图，在回调前释放源图和临时对象。
@property (nonatomic, assign) BOOL detachesCapturedImage;

/// 长截图取消/导出后的主线程清理：恢复自有图层捕获位并释放窗口引用，幂等。
- (void)endVisibleWindowExclusion;

- (void)captureWithCompletion:(void (^)(UIImage *image,
                                        BOOL isPartial,
                                        NSString *captureMethod,
                                        NSError *error))completion;

/// 长截图专用：优先运行期检查 _snapshotExcludingWindows:withRect:；
/// 默认先隐藏传入窗口并等两帧；keepsExcludedWindowsVisible 为 YES 时始终可见。
/// 图层标记不可用时再试排除窗口快照；两者都失败才返回错误。
- (void)captureExcludingWindows:(NSArray<UIWindow *> *)windows
                    completion:(void (^)(UIImage *image, BOOL isPartial,
                                          NSString *captureMethod, NSError *error))completion;
@end

NS_ASSUME_NONNULL_END
