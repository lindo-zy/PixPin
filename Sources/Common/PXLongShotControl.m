#import "PXLongShotControl.h"
#import <math.h>

@implementation PXLongShotCancellation
@end

BOOL PXLongShotBuildScrollPlan(CGRect viewport, CGRect screenBounds, CGFloat protectedBottomY,
                              PXLongShotScrollPlan *plan) {
    if (!plan || CGRectIsNull(viewport) || CGRectIsInfinite(viewport) ||
        CGRectIsEmpty(screenBounds) || !isfinite(protectedBottomY) ||
        !isfinite(viewport.origin.x) || !isfinite(viewport.origin.y) ||
        !isfinite(viewport.size.width) || !isfinite(viewport.size.height) ||
        !isfinite(screenBounds.origin.x) || !isfinite(screenBounds.origin.y) ||
        !isfinite(screenBounds.size.width) || !isfinite(screenBounds.size.height)) return NO;
    CGRect safe = CGRectInset(screenBounds, 12.0, 24.0);
    CGFloat bottom = MIN(CGRectGetMaxY(safe), protectedBottomY - 12.0);
    safe.size.height = MAX(0.0, bottom - CGRectGetMinY(safe));
    CGRect rect = CGRectIntersection(viewport, safe);
    if (CGRectIsNull(rect) || CGRectGetHeight(rect) < 80.0 || CGRectGetWidth(rect) < 20.0) return NO;
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
