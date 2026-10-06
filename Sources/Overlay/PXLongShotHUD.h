#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT const CGFloat PXLongShotHUDPreviewWidthPt;
@protocol PXLongShotHUDDelegate <NSObject>
- (void)longShotHUDDidTapCapture:(UIView *)hud;
- (void)longShotHUDDidTapFinish:(UIView *)hud;
- (void)longShotHUDDidTapCancel:(UIView *)hud;
@end
/// 实际小尺寸窗口内的面板，集中显示预览、模式、截取/暂停/继续、完成和取消。
@interface PXLongShotHUD : UIView
@property (nonatomic, weak, nullable) id<PXLongShotHUDDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL isPreviewInteracting;
/// 状态面板当前实际布局矩形（屏幕坐标）；自动滚动用它避让滑动路径。
@property (nonatomic, assign, readonly) CGRect panelFrame;
- (void)setModeTitle:(NSString *)title;
- (void)setCaptureTitle:(NSString *)title enabled:(BOOL)enabled;
- (void)setFinishing:(BOOL)finishing;
- (void)setStatusText:(nullable NSString *)statusText;
- (void)setSliceCount:(NSInteger)count;
- (void)setPreviewImage:(nullable UIImage *)image usedPixelHeight:(NSInteger)usedPixelHeight;
@end
NS_ASSUME_NONNULL_END
