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
typedef struct {
    CGPoint start;
    CGPoint end;
} PXLongShotScrollPlan;

/// 拖动路径限制在选区和屏幕内，避开底部 HUD/系统手势区域；过小视口拒绝自动滚动。
BOOL PXLongShotBuildScrollPlan(CGRect viewport, CGRect screenBounds, CGFloat protectedBottomY,
                              PXLongShotScrollPlan *plan);
/// 原始像素坐标统一缩放后转换到 CG 底部原点，预览与最终拼接共用。
CGRect PXLongShotTileRect(CGFloat canvasHeight, NSInteger offset, NSInteger width,
                         NSInteger height, CGFloat scale);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
