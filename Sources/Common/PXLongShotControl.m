#import "PXLongShotControl.h"
#import <math.h>
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <os/proc.h>
#import <mach/mach.h>
#endif

@implementation PXLongShotCancellation
@end

static const size_t PXLongShotMinFloorBytes = 48ull * 1024 * 1024;

size_t PXLongShotAvailableMemoryBytes(void) {
#if TARGET_OS_IPHONE
    return os_proc_available_memory();
#else
    return 0;
#endif
}

size_t PXLongShotProcessMemoryLimitBytes(void) {
#if TARGET_OS_IPHONE
    size_t available = os_proc_available_memory();
    if (!available) return 0;
    task_vm_info_data_t vmInfo;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vmInfo, &count) != KERN_SUCCESS) return 0;
    if (vmInfo.phys_footprint <= 0) return 0;
    return available + (size_t)vmInfo.phys_footprint;
#else
    return 0;
#endif
}

size_t PXLongShotMemoryFloorBytes(void) {
    size_t limit = PXLongShotProcessMemoryLimitBytes();
    if (!limit) return PXLongShotMinFloorBytes;
    // SpringBoard 限额实测约 400MB：留 70% 给系统与自身基线，30%（约 126MB）
    // 作为采集底线——覆盖一帧分片位图 + 抓屏表面 + 编码缓冲的瞬态峰值。
    return MAX(PXLongShotMinFloorBytes, limit / 10 * 3);
}

NSInteger PXLongShotStitchPixelCap(size_t limitBytes, NSInteger requestedPixels) {
    if (!limitBytes) return requestedPixels;
    // 画布 RGBA 字节 ≈ 限额/16（400MB 限额 ≈ 25MB 画布），像素数即限额/64；
    // 最低 1M 像素（4MB）保底，未知限额时维持调用方传入的上限。
    return MIN(requestedPixels, MAX((NSInteger)1000000, (NSInteger)(limitBytes / 64)));
}

NSInteger PXLongShotCanvasPixelBudget(size_t availableBytes, NSInteger requestedPixels) {
    NSInteger budget = MAX(1, requestedPixels);
    if (!availableBytes) return budget;
    const size_t reserve = 16 * 1024 * 1024;
    size_t working = availableBytes > reserve ? availableBytes - reserve : 0;
    // RGBA 画布 + 快照/编码峰值按 3 倍画布预留，不将余量全部用尽。
    return MIN(budget, (NSInteger)MAX((size_t)256000, working / 12));
}

BOOL PXLongShotCanvasGeometry(NSInteger width, NSInteger totalHeight, NSInteger maxHeight,
                             NSInteger maxPixels, CGSize *size, CGFloat *outScale) {
    if (width <= 0 || totalHeight <= 0 || maxHeight <= 0 || maxPixels <= 0 || !size || !outScale) return NO;
    CGFloat scale = MIN(1.0, (CGFloat)maxHeight / (CGFloat)totalHeight);
    CGFloat pixels = (CGFloat)width * (CGFloat)totalHeight * scale * scale;
    if (pixels > (CGFloat)maxPixels) scale *= sqrt((CGFloat)maxPixels / pixels);
    NSInteger w = MAX(1, (NSInteger)floor((CGFloat)width * scale));
    scale = MIN(scale, (CGFloat)w / width);
    NSInteger h = MAX(1, (NSInteger)ceil((CGFloat)totalHeight * scale));
    while (w > 1 && ((uint64_t)w * (uint64_t)h > (uint64_t)maxPixels || h > maxHeight)) {
        w--;
        scale = MIN(scale, (CGFloat)w / width);
        h = MAX(1, (NSInteger)ceil((CGFloat)totalHeight * scale));
    }
    // 极细长图宽至少为 1；在高度约束下继续缩放，不能裁掉尾部。
    if (h > MIN(maxHeight, maxPixels)) {
        h = MIN(maxHeight, maxPixels);
        scale = (CGFloat)h / totalHeight;
    }
    *size = CGSizeMake(w, h);
    *outScale = scale;
    return YES;
}

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
