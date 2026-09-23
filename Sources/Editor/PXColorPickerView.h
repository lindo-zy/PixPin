#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PXColorPickerView;

@protocol PXColorPickerViewDelegate <NSObject>
/// 点击“完成”确认颜色（调用方负责 dismiss）。
- (void)colorPicker:(PXColorPickerView *)picker didConfirmColor:(UIColor *)color;
/// 点击“取消”或点按空白区域（调用方负责 dismiss；拖动期间的实时预览由调用方自行回退）。
- (void)colorPickerDidCancel:(PXColorPickerView *)picker;
/// 拖动饱和度/亮度/色相过程中的实时回传（调用方可直接刷画布做即时预览）。
- (void)colorPicker:(PXColorPickerView *)picker didPreviewColor:(UIColor *)color;
@end

/// 自建 HSV 取色器：全屏半透明遮罩 + 底部弹出面板（饱和度/亮度二维区 + 色相条 +
/// 预览/Hex + 最近使用色）。不依赖 UIColorPickerViewController，规避 SpringBoard
/// 进程内系统取色器的呈现风险；风格与编辑器面板一致。
@interface PXColorPickerView : UIView

@property (nonatomic, weak, nullable) id<PXColorPickerViewDelegate> delegate;

- (instancetype)initWithColor:(nullable UIColor *)initialColor
                 recentColors:(NSArray<UIColor *> *)recentColors;

/// 加入 parent 全屏展示（含上滑入场动画）。
- (void)showInView:(UIView *)parent animated:(BOOL)animated completion:(nullable void (^)(void))completion;
/// 移除展示（含下滑离场动画，结束后自 superview 移除）。
- (void)dismissAnimated:(BOOL)animated completion:(nullable void (^)(void))completion;

+ (NSString *)hexStringForColor:(UIColor *)color;
+ (nullable UIColor *)colorFromHexString:(nullable NSString *)hex;

@end

NS_ASSUME_NONNULL_END
