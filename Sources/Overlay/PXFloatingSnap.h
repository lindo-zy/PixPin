#import <UIKit/UIKit.h>
#import "../Common/PXGeometry.h"

NS_ASSUME_NONNULL_BEGIN

@class PXFloatingSnap;

@protocol PXFloatingSnapDelegate <NSObject>
- (void)floatingSnapDidRequestEdit:(PXFloatingSnap *)snap;
- (void)floatingSnapDidRequestOutput:(PXFloatingSnap *)snap action:(PXOutputAction)action;
- (void)floatingSnapDidClose:(PXFloatingSnap *)snap;
@end

/// 区域截图悬浮窗：把选区裁剪结果常驻屏幕展示，可拖动，点按展开 编辑/保存/复制/关闭 动作条。
/// 独立于截图任务生命周期：任务结束不销毁；仅用户关闭、转编辑或被新悬浮替换时释放。
/// 窗口层级低于选区/编辑器/结果气泡，触摸落在悬浮图之外时透传给系统（不挡宿主操作）。
@interface PXFloatingSnap : UIView

@property (nonatomic, weak, nullable) id<PXFloatingSnapDelegate> delegate;
@property (nonatomic, strong, readonly) UIImage *image;
@property (nonatomic, assign, readonly) PXCaptureMode captureMode;

+ (instancetype)presentWithImage:(UIImage *)image
                            mode:(PXCaptureMode)mode
                        delegate:(id<PXFloatingSnapDelegate>)delegate;

/// 新截图任务抓屏前隐藏（悬浮图不得被截入新截图）；任务结束后恢复展示。
- (void)hideForCapture;
- (void)restoreAfterCapture;

- (void)dismissWithCompletion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
