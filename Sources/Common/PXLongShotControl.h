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

/// availableBytes 为当前进程余量；0 表示无法取得有效余量（SpringBoard 可能不是 app）。
/// 预算包含位图快照/编码的额外峰值，并保留 16MiB 给抓屏与系统；最低降到 256K 像素。
NSInteger PXLongShotCanvasPixelBudget(size_t availableBytes, NSInteger requestedPixels);

/// 会话继续采集所需的最低自身余量：一帧分片位图 + 抓屏表面 + 编码缓冲的瞬态峰值约
/// 40MiB，再留系统余量。低于该值才认定本进程真耗尽；系统级警告突发不据此熔断。
extern const size_t PXLongShotMemoryFloorBytes;
/// iOS 上返回 os_proc_available_memory()；其余平台返回 0（表示余量未知）。
size_t PXLongShotAvailableMemoryBytes(void);
/// 正文总高等比缩放到高度与像素预算内；同时消化整数舍入误差。
BOOL PXLongShotCanvasGeometry(NSInteger width, NSInteger totalHeight, NSInteger maxHeight,
                             NSInteger maxPixels, CGSize *size, CGFloat *scale);

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
