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

- (void)captureWithCompletion:(void (^)(UIImage *image,
                                        BOOL isPartial,
                                        NSString *captureMethod,
                                        NSError *error))completion;

/// 长截图专用：优先运行期检查 _snapshotExcludingWindows:withRect:；
/// 不可用时只在原始抓屏阶段短暂隐藏传入窗口，归一化前恢复。
- (void)captureExcludingWindows:(NSArray<UIWindow *> *)windows
                    completion:(void (^)(UIImage *image, BOOL isPartial,
                                          NSString *captureMethod, NSError *error))completion;
@end

NS_ASSUME_NONNULL_END
