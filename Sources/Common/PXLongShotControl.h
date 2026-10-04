#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// 主线程取消、后台读取；不依赖已经销毁的 Window/会话对象。
@interface PXLongShotCancellation : NSObject
@property (atomic, assign, getter=isCancelled) BOOL cancelled;
@end

#ifdef __cplusplus
extern "C" {
#endif
/// 单次自动滚动的滑动路径：竖直上滑，start 靠下、end 靠上。
typedef struct {
    CGPoint start;
    CGPoint end;
} PXLongShotScrollPlan;

/// 在 viewport∩screenBounds 安全区内规划一条避开 protectedRect 的竖直上滑：
/// 滑动带压到 protectedRect 下缘以下（HUD 小窗悬在右上），带高不足 80pt 返回 NO。
BOOL PXLongShotBuildScrollPlan(CGRect viewport, CGRect screenBounds, CGRect protectedRect,
                              PXLongShotScrollPlan *plan);

/// 原始像素坐标统一缩放后转换到 CG 底部原点，预览与最终拼接共用。
CGRect PXLongShotTileRect(CGFloat canvasHeight, NSInteger offset, NSInteger width,
                         NSInteger height, CGFloat scale);

/// 全帧只绘制 [cropTop, height-cropBottom)，与预览和导出共用裁切几何。
void PXLongShotDrawTile(CGContextRef context, CGImageRef image, CGFloat canvasHeight,
                       NSInteger offset, NSInteger width, NSInteger height,
                       NSInteger cropTop, NSInteger cropBottom, CGFloat scale);
#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
