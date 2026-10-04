#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 预览浮窗点宽（会话侧按它 × 屏幕缩放初始化预览画布）。
FOUNDATION_EXPORT const CGFloat PXLongShotHUDPreviewWidthPt;

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
/// 实时预览：image 为整幅增量长图（高度含画布分配余量），usedPixelHeight 为有效内容高。
/// 首次调用后显示预览浮窗；image 为 nil 保持现状。用户可点浮窗上方眼睛键收起/展开。
- (void)setPreviewImage:(nullable UIImage *)image usedPixelHeight:(NSInteger)usedPixelHeight;

@end

NS_ASSUME_NONNULL_END
