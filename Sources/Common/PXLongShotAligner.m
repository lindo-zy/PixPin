#import "PXLongShotAligner.h"
#import <math.h>
#import <stdlib.h>
const NSInteger PXLongShotSigWidth = 64;

void PXLongShotComputeRowSignature(const uint8_t *buffer,
                                   NSInteger pixelWidth,
                                   NSInteger bytesPerRow,
                                   NSInteger row,
                                   uint8_t *outSig) {
    const uint8_t *line = buffer + row * bytesPerRow;
    CGFloat stride = (CGFloat)MAX(pixelWidth, 1) / (CGFloat)PXLongShotSigWidth;
    for (NSInteger c = 0; c < PXLongShotSigWidth; c++) {
        NSInteger x0 = (NSInteger)((CGFloat)c * stride);
        NSInteger x1 = MIN(x0 + 1, pixelWidth - 1);
        NSInteger x2 = MIN(x0 + 2, pixelWidth - 1);
        // RGBA8：3 点横向均值亮度，抑制 JPEG 噪声与亚像素锯齿。
        uint32_t sum = 0;
        const NSInteger xs[3] = {x0, x1, x2};
        for (NSInteger i = 0; i < 3; i++) {
            const uint8_t *p = line + xs[i] * 4;
            sum += (uint32_t)((77 * p[0] + 150 * p[1] + 29 * p[2]) >> 8);
        }
        outSig[c] = (uint8_t)(sum / 3);
    }
}

BOOL PXLongShotSignaturesAreDuplicate(const uint8_t *prevSigs, NSInteger prevRows,
                                     const uint8_t *curSigs, NSInteger curRows) {
    if (!prevSigs || !curSigs || prevRows <= 0 || prevRows != curRows) return NO;
    size_t count = (size_t)prevRows * PXLongShotSigWidth;
    uint64_t total = 0;
    size_t changed = 0;
    for (size_t i = 0; i < count; i++) {
        uint8_t diff = prevSigs[i] > curSigs[i] ? prevSigs[i] - curSigs[i] : curSigs[i] - prevSigs[i];
        total += diff;
        if (diff > 12) changed++;
    }
    return (CGFloat)total / (CGFloat)count <= 0.75 && (CGFloat)changed / (CGFloat)count <= 0.02;
}


// 中部列用于运动估计，减小边缘时钟、滚动条和视频角标的干扰。
static CGFloat PXRowDifference(const uint8_t *a, const uint8_t *b) {
    NSUInteger sum = 0;
    for (NSInteger c = 8; c < 56; c++) sum += abs((int)a[c] - (int)b[c]);
    return (CGFloat)sum / 48.0;
}

static CGFloat PXShiftCost(const uint8_t *prev, const uint8_t *cur, NSInteger rows, NSInteger delta) {
    NSInteger overlap = rows - delta;
    if (overlap < 64) return CGFLOAT_MAX;
    uint64_t total = 0;
    // 全重叠带分布采样，不能仅拿固定页头或顶部白底作为锚点。
    for (NSInteger s = 0; s < 32; s++) {
        NSInteger r = (2 * s + 1) * overlap / 64;
        const uint8_t *a = prev + (r + delta) * PXLongShotSigWidth;
        const uint8_t *b = cur + r * PXLongShotSigWidth;
        for (NSInteger c = 8; c < 56; c += 3) total += abs((int)a[c] - (int)b[c]);
    }
    return (CGFloat)total / (32.0 * 16.0);
}

static NSInteger PXFindShift(const uint8_t *prev, const uint8_t *cur, NSInteger rows, CGFloat *cost) {
    CGFloat *costs = malloc((size_t)rows * sizeof(CGFloat));
    if (!costs) return 0;
    NSInteger bestDelta = 0;
    CGFloat best = CGFLOAT_MAX;
    for (NSInteger d = 3; d <= rows - 64; d++) {
        costs[d] = CGFLOAT_MAX;
        if (PXShiftCost(prev, cur, rows, d) > 8.0) continue;
        // 稀疏页上多个粗候选可能全部落在白底；先密集验证每个候选，再比较独立匹配峰。
        CGFloat sum = 0;
        NSInteger overlap = rows - d, count = (overlap + 3) / 4;
        for (NSInteger r = 0; r < overlap; r += 4) {
            sum += PXRowDifference(prev + (r + d) * PXLongShotSigWidth,
                                   cur + r * PXLongShotSigWidth);
            if (sum > 8.0 * count) break;
        }
        CGFloat v = sum / count;
        if (v > 8.0) continue;
        costs[d] = v;
        if (v < best) { best = v; bestDelta = d; }
    }
    CGFloat second = CGFLOAT_MAX;
    for (NSInteger d = 3; d <= rows - 64; d++) {
        if (labs(d - bestDelta) <= 3) continue;
        second = MIN(second, costs[d]);
    }
    free(costs);
    if (!bestDelta || second - best < 1.5) return 0;
    *cost = best;
    return bestDelta;
}

// 首次严格识别失败时允许固定栏中的局部状态图标/压缩噪声；连续 8 行的均值
// 必须稳定。此宽容只用于候选正文边界，位移仍受完整重叠验证和独立次峰约束。
static NSInteger PXStableEdge(const uint8_t *prev, const uint8_t *cur, NSInteger rows, BOOL bottom) {
    NSInteger limit = bottom ? rows / 4 : rows / 3;
    for (NSInteger r = 0; r < limit; r++) {
        CGFloat cost = 0;
        for (NSInteger j = 0; j < 8; j++) {
            NSInteger y = bottom ? rows - 1 - r - j : r + j;
            cost += PXRowDifference(prev + y * PXLongShotSigWidth, cur + y * PXLongShotSigWidth);
        }
        if (cost / 8 > 5.0) {
            // 窗口前瞻找到边界后逐行精化，避免每一段残留 7 行固定页脚。
            while (r < limit) {
                NSInteger y = bottom ? rows - 1 - r : r;
                if (PXRowDifference(prev + y * PXLongShotSigWidth, cur + y * PXLongShotSigWidth) > 5.0) break;
                r++;
            }
            return r;
        }
    }
    return limit;
}

PXLongShotFrameMatch PXLongShotMatchFrames(const uint8_t *prev, const uint8_t *cur,
                                          NSInteger rows, NSInteger fixedTop, NSInteger fixedBottom) {
    PXLongShotFrameMatch result = {PXLongShotMatchUncertain, 0, 0, 0};
    if (!prev || !cur || rows < 128) return result;
    NSInteger top = MAX(0, fixedTop), bottom = MAX(0, fixedBottom);
    if (fixedTop < 0 || fixedBottom < 0) {
        // 仅固定的连续首尾条带可排除；超过上限说明静止或无法辨认正文。
        if (PXLongShotSignaturesAreDuplicate(prev, rows, cur, rows)) {
            result.kind = PXLongShotMatchDuplicate;
            return result;
        }
        if (fixedTop < 0)
            while (top < rows / 3 && PXRowDifference(prev + top * 64, cur + top * 64) <= 2.0) top++;
        if (fixedBottom < 0)
            while (bottom < rows / 4 &&
                   PXRowDifference(prev + (rows - bottom - 1) * 64, cur + (rows - bottom - 1) * 64) <= 2.0) bottom++;
    }
    if (top > rows / 3 || bottom > rows / 4 || rows - top - bottom < 128) return result;
    result.fixedTopRows = top;
    result.fixedBottomRows = bottom;
    const uint8_t *a = prev + top * 64, *b = cur + top * 64;
    NSInteger bodyRows = rows - top - bottom;
    if (PXLongShotSignaturesAreDuplicate(a, bodyRows, b, bodyRows)) {
        result.kind = PXLongShotMatchDuplicate;
        return result;
    }
    CGFloat forwardCost = CGFLOAT_MAX, reverseCost = CGFLOAT_MAX;
    NSInteger forward = PXFindShift(a, b, bodyRows, &forwardCost);
    NSInteger reverse = PXFindShift(b, a, bodyRows, &reverseCost);
    if (forward && (!reverse || forwardCost + 1.5 < reverseCost)) {
        result.kind = PXLongShotMatchForward;
        result.shiftRows = forward;
    } else if (reverse && (!forward || reverseCost + 1.5 < forwardCost)) {
        result.kind = PXLongShotMatchReverse;
        result.shiftRows = reverse;
    }
    if (result.kind == PXLongShotMatchUncertain && (fixedTop < 0 || fixedBottom < 0)) {
        NSInteger tolerantTop = fixedTop < 0 ? PXStableEdge(prev, cur, rows, NO) : top;
        NSInteger tolerantBottom = fixedBottom < 0 ? PXStableEdge(prev, cur, rows, YES) : bottom;
        if (tolerantTop != top || tolerantBottom != bottom)
            return PXLongShotMatchFrames(prev, cur, rows, tolerantTop, tolerantBottom);
    }
    return result;
}
