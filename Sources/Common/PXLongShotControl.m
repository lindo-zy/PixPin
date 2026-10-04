#import "PXLongShotControl.h"
#import <math.h>

@implementation PXLongShotCancellation
@end

BOOL PXLongShotBuildScrollPlan(CGRect viewport, CGRect screenBounds, CGRect protectedRect,
                              PXLongShotScrollPlan *plan) {
    if (!plan || CGRectIsNull(viewport) || CGRectIsInfinite(viewport) ||
        CGRectIsEmpty(screenBounds) ||
        !isfinite(viewport.origin.x) || !isfinite(viewport.origin.y) ||
        !isfinite(viewport.size.width) || !isfinite(viewport.size.height) ||
        !isfinite(screenBounds.origin.x) || !isfinite(screenBounds.origin.y) ||
        !isfinite(screenBounds.size.width) || !isfinite(screenBounds.size.height) ||
        !isfinite(protectedRect.origin.x) || !isfinite(protectedRect.origin.y) ||
        !isfinite(protectedRect.size.width) || !isfinite(protectedRect.size.height)) return NO;
    CGRect safe = CGRectInset(screenBounds, 12.0, 24.0);
    CGRect rect = CGRectIntersection(viewport, safe);
    if (CGRectIsNull(rect) || CGRectGetHeight(rect) < 80.0 || CGRectGetWidth(rect) < 20.0) return NO;
    if (!CGRectIsEmpty(protectedRect)) {
        // HUD 小窗是触摸宿主：滑动带整体压到其下缘以下，防止合成滑动落在预览视图上。
        CGFloat bandTop = CGRectGetMaxY(protectedRect) + 12.0;
        CGFloat bandBottom = CGRectGetMaxY(rect);
        if (bandBottom - MAX(CGRectGetMinY(rect), bandTop) < 80.0) return NO;
        rect.origin.y = MAX(CGRectGetMinY(rect), bandTop);
        rect.size.height = bandBottom - rect.origin.y;
    }
    CGFloat distance = MIN((CGRectGetHeight(rect) - 20.0) * 0.60, 320.0);
    plan->start = CGPointMake(CGRectGetMidX(rect), CGRectGetMaxY(rect) - 10.0);
    plan->end = CGPointMake(plan->start.x, plan->start.y - distance);
    return YES;
}

CGRect PXLongShotTileRect(CGFloat canvasHeight, NSInteger offset, NSInteger width,
                         NSInteger height, CGFloat scale) {
    return CGRectMake(0, canvasHeight - ((CGFloat)offset + (CGFloat)height) * scale,
                      (CGFloat)width * scale, (CGFloat)height * scale);
}

void PXLongShotDrawTile(CGContextRef context, CGImageRef image, CGFloat canvasHeight,
                       NSInteger offset, NSInteger width, NSInteger height,
                       NSInteger cropTop, NSInteger cropBottom, CGFloat scale) {
    NSInteger visible = height - cropTop - cropBottom;
    if (!context || !image || visible <= 0 || cropTop < 0 || cropBottom < 0 || scale <= 0) return;
    CGContextSaveGState(context);
    CGContextClipToRect(context, PXLongShotTileRect(canvasHeight, offset, width, visible, scale));
    CGContextDrawImage(context, PXLongShotTileRect(canvasHeight, offset - cropTop, width, height, scale), image);
    CGContextRestoreGState(context);
}
