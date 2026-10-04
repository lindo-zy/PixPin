#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PXLongShotHUDDelegate <NSObject>
- (void)longShotHUDDidTapCapture:(UIView *)hud;
- (void)longShotHUDDidTapFinish:(UIView *)hud;
- (void)longShotHUDDidTapCancel:(UIView *)hud;
@end

/// 长截图会话的悬浮控制条。
/// 根视图全屏透明：窗口层开启 passesTouchesOutsideHostedContent 后，只有控制条拦触摸，
/// 其余区域全部穿透给前台 App，保证用户能直接滚动页面。
/// 全部 UI 操作限定主线程；抓屏前由会话负责隐藏所在窗口。
@interface PXLongShotHUD : UIView

@property (nonatomic, weak, nullable) id<PXLongShotHUDDelegate> delegate;

/// 忙碌时禁用 截取/完成（取消键保持可用）；statusText 为 nil 时保持原文。
- (void)setBusy:(BOOL)busy statusText:(nullable NSString *)statusText;
- (void)setStatusText:(nullable NSString *)statusText;
/// 已有分片数决定完成键可用性，并刷新计数文案。
- (void)setSliceCount:(NSInteger)count;

@end

NS_ASSUME_NONNULL_END
