#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 长截图实时预览画布：逐段把已落盘分片绘入一块低分辨率增量画布，每次追加返回整幅
/// 预览 UIImage（重叠行数由会话按行签名算好传入，与正式拼接同源同值）。
/// 返回的 UIImage 高度为画布分配高，有效内容只占上部 usedPixelHeight——
/// 展示侧按 usedPixelHeight 裁切显示（contentModeTop + clipsToBounds）。
/// 线程约定：调用方（会话）以 busy 串行化，实例方法只在单一后台队列调用；
/// 画布占用像素超 maxPixels 时自动缩画布宽全量重放，缩到下限即判饱和停止更新。
@interface PXLongPreviewCanvas : NSObject

- (instancetype)initWithWidthPixels:(NSInteger)widthPixels
                          maxPixels:(NSInteger)maxPixels
                            uiScale:(CGFloat)uiScale;

/// 追加一片（已落盘 JPEG）。返回更新后的整幅预览；失败/饱和返回 nil。
/// overlapRows：与上一片的重叠行数（首片传 0；会话侧已用 PXLongShotSearchOverlap 算好）。
- (nullable UIImage *)appendSliceFile:(NSString *)filePath
                            pixelWidth:(NSInteger)pixelWidth
                           pixelHeight:(NSInteger)pixelHeight
                            overlapRows:(NSInteger)overlapRows;

/// 当前有效内容像素高（顶部原点累计 × 当前缩放）。
@property (nonatomic, assign, readonly) NSInteger usedPixelHeight;
/// 画布像素宽（展示侧换算点宽用：width / uiScale）。
@property (nonatomic, assign, readonly) NSInteger canvasWidth;
/// 已到像素下限，后续追加不再更新预览（正式拼接不受影响）。
@property (nonatomic, assign, readonly) BOOL saturated;

@end

NS_ASSUME_NONNULL_END
