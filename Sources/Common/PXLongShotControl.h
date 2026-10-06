#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "PXLongShotAligner.h"

NS_ASSUME_NONNULL_BEGIN

/// 主线程取消、后台读取；不依赖已经销毁的 Window/会话对象。
@interface PXLongShotCancellation : NSObject
@property (atomic, assign, getter=isCancelled) BOOL cancelled;
@end

#ifdef __cplusplus
extern "C" {
#endif
/// 单次自动滚动的滑动路径：竖直滑动，start 为落指点、end 为抬指点。
/// start 靠下（上滑）为前进步进；start 靠上（下滑）为对齐判歧后的纠正性回滚。
typedef struct {
    CGPoint start;
    CGPoint end;
} PXLongShotScrollPlan;
typedef struct {
    BOOL progressed;
    NSInteger reverseFrames;
    NSInteger reverseRows;
} PXLongShotReboundState;
/// 使用相邻采样帧（不是最后追加帧）判断连续回退；手动模式不自动完成。
BOOL PXLongShotUpdateRebound(PXLongShotReboundState *state, PXLongShotFrameMatch adjacentMatch,
                             NSInteger bodyRows, BOOL automatic);
/// 返回 +1 的独立 RGBA 位图，不持有源图/IOSurface 的 provider。
CGImageRef _Nullable PXLongShotCreateOwnedBitmap(CGImageRef source) CF_RETURNS_RETAINED;

/// availableBytes 为当前进程余量；0 表示无法取得有效余量（SpringBoard 可能不是 app）。
/// 预算包含位图快照/编码的额外峰值，并保留 16MiB 给抓屏与系统；最低降到 256K 像素。
NSInteger PXLongShotCanvasPixelBudget(size_t availableBytes, NSInteger requestedPixels);

/// 会话继续采集所需的最低自身余量：按任务限额的 30% 动态计算。实测 iPhone14,2/iOS 16.1
/// 的 SpringBoard jetsam 限额只有约 400MB（jetsam 报告 highwater @408MB），固定阈值在
/// 小限额设备上形同虚设；限额未知时返回 48MiB 保底。
size_t PXLongShotMemoryFloorBytes(void);
/// iOS 上返回 os_proc_available_memory()；其余平台返回 0（表示余量未知）。
size_t PXLongShotAvailableMemoryBytes(void);
/// 任务内存限额估算：os_proc_available_memory + 当前 phys_footprint（task_vm_info），
/// 两者任一不可得时返回 0（表示未知）。
size_t PXLongShotProcessMemoryLimitBytes(void);
/// 当前 phys_footprint（task_vm_info），即 jetsam highwater 的计量口径；
/// 不可得时返回 0。逐帧遥测用，用于在 syslog 留下内存增长曲线。
size_t PXLongShotProcessFootprintBytes(void);
/// 拼接画布像素上限：按限额收缩（画布字节 ≈ 限额/16，对应像素 ≈ 限额/64），
/// 最低 1M 像素保证可用；限额未知时原样返回 requestedPixels。
NSInteger PXLongShotStitchPixelCap(size_t limitBytes, NSInteger requestedPixels);
/// 正文总高等比缩放到高度与像素预算内；同时消化整数舍入误差。
BOOL PXLongShotCanvasGeometry(NSInteger width, NSInteger totalHeight, NSInteger maxHeight,
                             NSInteger maxPixels, CGSize *size, CGFloat *scale);

/// 在 viewport∩screenBounds 安全区内规划一条避开 protectedRect 的竖直上滑：
/// 优先保留正文中线；小窗挡路时移到左右空带，无空带则尝试下方，带高不足 80pt 返回 NO。
/// 起滑点居中于滑动带：贴带底起滑会落进微信等 App 的 tabBar/输入栏，触摸被底栏
/// 消费、正文不滚（ShellX 起滑 0.60·H，手势全程在屏幕中部）。
BOOL PXLongShotBuildScrollPlan(CGRect viewport, CGRect screenBounds, CGRect protectedRect,
                              PXLongShotScrollPlan *plan);

/// 由前向上滑计划派生一次小步下滑的回滚计划（距离为原步长的 fraction 倍）：
/// 对齐判歧后重采无法解开内容固有的歧义，只有改变与锚点的比较基准才可能恢复。
/// 回滑限制在原滑动带内；输入非法或回退距离不足 24pt 返回 NO。
BOOL PXLongShotBuildCorrectiveScrollPlan(PXLongShotScrollPlan forwardPlan, CGFloat fraction,
                                         PXLongShotScrollPlan *correctPlan);

/// 原始像素坐标统一缩放后转换到 CG 底部原点，预览与最终拼接共用。
CGRect PXLongShotTileRect(CGFloat canvasHeight, NSInteger offset, NSInteger width,
                         NSInteger height, CGFloat scale);

/// 全帧只绘制 [cropTop, height-cropBottom)，相邻裁切边界统一舍入到整数像素。
/// 与预览和导出共用；缩放时不把抗锯齿裁切的黑底混入接缝。
void PXLongShotDrawTile(CGContextRef context, CGImageRef image, CGFloat canvasHeight,
                       NSInteger offset, NSInteger width, NSInteger height,
                       NSInteger cropTop, NSInteger cropBottom, CGFloat scale);
#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
