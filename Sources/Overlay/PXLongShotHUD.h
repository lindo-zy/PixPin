#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT const CGFloat PXLongShotHUDPreviewWidthPt;
@protocol PXLongShotHUDDelegate <NSObject>
- (void)longShotHUDDidTapFinish:(UIView *)hud;
- (void)longShotHUDDidTapCancel:(UIView *)hud;
@end
/// 全屏透明根视图；右上小窗集中显示累计预览、状态及完成/取消，窗外触摸穿透。
@interface PXLongShotHUD : UIView
@property (nonatomic, weak, nullable) id<PXLongShotHUDDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL isPreviewInteracting;
- (void)setFinishing:(BOOL)finishing;
- (void)setStatusText:(nullable NSString *)statusText;
- (void)setSliceCount:(NSInteger)count;
- (void)setPreviewImage:(nullable UIImage *)image usedPixelHeight:(NSInteger)usedPixelHeight;
@end
NS_ASSUME_NONNULL_END
