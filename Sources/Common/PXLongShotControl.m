#import "PXLongShotControl.h"
#import <math.h>
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <os/proc.h>
#import <mach/mach.h>
#endif

@implementation PXLongShotCancellation
@end

CGImageRef PXLongShotCreateOwnedBitmap(CGImageRef source) {
    if (!source) return NULL;
    size_t width = CGImageGetWidth(source), height = CGImageGetHeight(source);
    if (!width || !height) return NULL;
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, color,
                                                   (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(color);
    if (!context) return NULL;
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), source);
    CGImageRef owned = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return owned;
}

BOOL PXLongShotUpdateRebound(PXLongShotReboundState *state, PXLongShotFrameMatch match,
                             NSInteger bodyRows, BOOL automatic) {
    if (!state) return NO;
    if (!automatic || bodyRows < 128) { *state = (PXLongShotReboundState){0}; return NO; }
    if (match.kind == PXLongShotMatchReverse && state->progressed && match.shiftRows > 0) {
        state->reverseFrames++;
        state->reverseRows += match.shiftRows;
        return state->reverseFrames >= 2 && state->reverseRows >= (NSInteger)ceil(bodyRows * 0.15);
    }
    if (match.kind == PXLongShotMatchForward) state->progressed = YES;
    state->reverseFrames = state->reverseRows = 0;
    return NO;
}

static const size_t PXLongShotMinFloorBytes = 48ull * 1024 * 1024;

size_t PXLongShotAvailableMemoryBytes(void) {
#if TARGET_OS_IPHONE
    return os_proc_available_memory();
#else
    return 0;
#endif
}

size_t PXLongShotProcessFootprintBytes(void) {
#if TARGET_OS_IPHONE
    task_vm_info_data_t vmInfo;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vmInfo, &count) != KERN_SUCCESS) return 0;
    return vmInfo.phys_footprint > 0 ? (size_t)vmInfo.phys_footprint : 0;
#else
    return 0;
#endif
}

size_t PXLongShotProcessMemoryLimitBytes(void) {
#if TARGET_OS_IPHONE
    size_t available = os_proc_available_memory();
    if (!available) return 0;
    size_t footprint = PXLongShotProcessFootprintBytes();
    if (!footprint) return 0;
    return available + footprint;
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
        CGRect obstacle = CGRectInset(protectedRect, -12, -12);
        // 右上小窗通常不覆盖正文中线，保留居中起滑，避免被迫向底栏靠近。
        if (CGRectIntersectsRect(rect, obstacle) && CGRectGetMidX(rect) >= CGRectGetMinX(obstacle) &&
            CGRectGetMidX(rect) <= CGRectGetMaxX(obstacle)) {
            CGFloat leftWidth = MAX(0, CGRectGetMinX(obstacle) - CGRectGetMinX(rect));
            CGFloat rightWidth = MAX(0, CGRectGetMaxX(rect) - CGRectGetMaxX(obstacle));
            if (MAX(leftWidth, rightWidth) >= 20) {
                if (leftWidth >= rightWidth) rect.size.width = leftWidth;
                else { rect.origin.x = CGRectGetMaxX(obstacle); rect.size.width = rightWidth; }
            } else {
                CGFloat bandBottom = CGRectGetMaxY(rect);
                rect.origin.y = MAX(CGRectGetMinY(rect), CGRectGetMaxY(obstacle));
                rect.size.height = bandBottom - rect.origin.y;
                if (rect.size.height < 80) return NO;
            }
        }
    }
    CGFloat distance = MIN((CGRectGetHeight(rect) - 20.0) * 0.60, 320.0);
    // 起滑点居中于滑动带：带底上方 10pt 在全屏模式下落在微信等 App 的 tabBar/输入栏，
    // 触摸被底栏消费、正文不滚（v1.9.8 逆向结论，ShellX 起滑 0.60·H 手势全程在屏幕
    // 中部）。居中放置后两端各留 ≥22pt 带内余量，远离上下边栏。
    CGFloat center = CGRectGetMinY(rect) + CGRectGetHeight(rect) / 2.0;
    plan->start = CGPointMake(CGRectGetMidX(rect), center + distance / 2.0);
    plan->end = CGPointMake(plan->start.x, center - distance / 2.0);
    return YES;
}

BOOL PXLongShotBuildCorrectiveScrollPlan(PXLongShotScrollPlan forwardPlan, CGFloat fraction,
                                         PXLongShotScrollPlan *correctPlan) {
    if (!correctPlan || !isfinite(fraction) || fraction <= 0.0 || fraction >= 1.0 ||
        !isfinite(forwardPlan.start.x) || !isfinite(forwardPlan.start.y) ||
        !isfinite(forwardPlan.end.x) || !isfinite(forwardPlan.end.y) ||
        forwardPlan.start.y <= forwardPlan.end.y) return NO;
    CGFloat distance = (forwardPlan.start.y - forwardPlan.end.y) * fraction;
    // 回滑起点略低于原终点，避免与前一次抬指点重叠；终点不越过原起点，保持在滑动带内。
    CGFloat top = forwardPlan.end.y + 2.0;
    CGFloat bottom = MIN(forwardPlan.start.y - 8.0, top + distance);
    if (bottom - top < 24.0) return NO;
    correctPlan->start = CGPointMake(forwardPlan.start.x, top);
    correctPlan->end = CGPointMake(forwardPlan.start.x, bottom);
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
    // 相邻段共用同一累计坐标的舍入，裁切边界不落在半个像素上。
    // 否则缩放后两次 clip 的覆盖率会把黑色底混入接缝，形成周期灰线。
    CGFloat top = ceil(offset * scale);
    CGFloat bottom = ceil((offset + visible) * scale);
    CGFloat drawWidth = ceil(width * scale);
    CGContextSaveGState(context);
    CGContextSetShouldAntialias(context, NO);
    CGContextClipToRect(context, CGRectMake(0, canvasHeight - bottom, drawWidth, bottom - top));
    CGRect tile = PXLongShotTileRect(canvasHeight, offset - cropTop, width, height, scale);
    tile.size.width = drawWidth;
    CGContextDrawImage(context, tile, image);
    CGContextRestoreGState(context);
}
