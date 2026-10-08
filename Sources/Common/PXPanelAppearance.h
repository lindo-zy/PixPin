#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 标记面板与设置页共用的磨砂调色层；读取时校验持久化的 RGBA 分量。
@interface PXPanelAppearance : NSObject
+ (UIColor *)tintColor;
+ (void)setTintColor:(UIColor *)color;
+ (void)installBackgroundInView:(UIView *)view;
+ (UIImage *)editorSliderThumbImage;
@end

NS_ASSUME_NONNULL_END
