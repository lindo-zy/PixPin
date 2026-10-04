#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 预览浮窗点宽（会话侧按它 × 屏幕缩放初始化预览画布）。
FOUNDATION_EXPORT const CGFloat PXLongShotHUDPreviewWidthPt;

@protocol PXLongShotHUDDelegate <NSObject>
- (void)longShotHUDDidTapFinish:(UIView *)hud;
- (void)longShotHUDDidTapCancel:(UIView *)hud;
@end

/// 长截图会话的悬浮控制条。
/// 根视图全屏透明：窗口层开启 passesTouchesOutsideHostedContent 后，只有控制条拦触摸，
/// 其余区域穿透给前台 App；会话自动滚动时临时收起预览，避免挡住注入路径。
/// 全部 UI 操作限定主线程；抓屏前由会话负责隐藏所在窗口。
@interface PXLongShotHUD : UIView

@property (nonatomic, weak, nullable) id<PXLongShotHUDDelegate> delegate;

/// 请求完成之后禁用完成键，避免重复请求；取消始终可用。
- (void)setFinishing:(BOOL)finishing;
- (void)setScrolling:(BOOL)scrolling;
/// HUD 顶边（屏幕点）；自动拖动不得进入此区域。
@property (nonatomic, assign, readonly) CGFloat scrollProtectedBottomY;
- (void)setStatusText:(nullable NSString *)statusText;
/// 刷新已采集段数；采集期间完成键始终可以发停止请求。
- (void)setSliceCount:(NSInteger)count;
/// 实时预览：image 为整幅增量长图（高度含画布分配余量），usedPixelHeight 为有效内容高。
/// 首次调用后显示预览浮窗；image 为 nil 保持现状。用户可点浮窗上方眼睛键收起/展开。
- (void)setPreviewImage:(nullable UIImage *)image usedPixelHeight:(NSInteger)usedPixelHeight;

@end

NS_ASSUME_NONNULL_END
