#import "PXLongShotAligner.h"

const NSInteger PXLongShotSigWidth = 64;

// 重叠搜索判定阈值：均为“每字节平均亮度差”（0-255 尺度）。
static const CGFloat PXLongShotAcceptAvgDiff = 10.0;   // 平均差超过该值视为内容变化，不认重叠
static const CGFloat PXLongShotMarginAvgDiff = 4.0;    // 最优与次优差值需超过该值才认为匹配唯一
static const NSInteger PXLongShotMinOverlapRows = 16;  // 少于该行数的重叠不可信，按无重叠处理
static const NSInteger PXLongShotDuplicateSlackRows = 8;
static const uint8_t PXLongShotUniformBandRange = 8;   // 顶部带亮度极差小于该值视为无纹理

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

static CGFloat PXLongShotBandCost(const uint8_t *prevSigs, NSInteger prevRows,
                                   const uint8_t *curSigs, NSInteger bandRows, NSInteger anchorTop) {
    if (anchorTop < 0 || bandRows <= 0 || anchorTop + bandRows > prevRows) return CGFLOAT_MAX;
    const uint8_t *p = prevSigs + (size_t)anchorTop * PXLongShotSigWidth;
    size_t count = (size_t)bandRows * PXLongShotSigWidth;
    uint64_t total = 0;
    for (size_t i = 0; i < count; i++) total += p[i] > curSigs[i] ? p[i] - curSigs[i] : curSigs[i] - p[i];
    return (CGFloat)total / (CGFloat)count;
}

static NSInteger PXLongShotFindPeak(const uint8_t *prevSigs, NSInteger prevRows,
                                    const uint8_t *curSigs, NSInteger minOverlap,
                                    NSInteger maxOverlap, NSInteger fixedBand) {
    CGFloat best = CGFLOAT_MAX;
    NSInteger bestOverlap = 0;
    for (NSInteger o = minOverlap; o <= maxOverlap; o++) {
        CGFloat cost = PXLongShotBandCost(prevSigs, prevRows, curSigs, fixedBand > 0 ? fixedBand : o, prevRows - o);
        if (cost < best) { best = cost; bestOverlap = o; }
    }
    if (!bestOverlap || best > PXLongShotAcceptAvgDiff) return 0;
    // 相邻像素候选属于同一个匹配峰。文字边缘相邻行高度相关，不能把 ±1px 当成
    // 第二个独立匹配，否则精确文字匹配也会被误判歧义。周期/远处峰仍必须拒绝。
    NSInteger radius = MAX(2, (fixedBand > 0 ? fixedBand : bestOverlap) / 8);
    CGFloat second = CGFLOAT_MAX;
    for (NSInteger o = minOverlap; o <= maxOverlap; o++) {
        if (labs(o - bestOverlap) <= radius) continue;
        CGFloat cost = PXLongShotBandCost(prevSigs, prevRows, curSigs, fixedBand > 0 ? fixedBand : o, prevRows - o);
        second = MIN(second, cost);
    }
    return second - best >= PXLongShotMarginAvgDiff ? bestOverlap : 0;
}

NSInteger PXLongShotSearchOverlap(const uint8_t *prevSigs, NSInteger prevRows,
                                  const uint8_t *curSigs, NSInteger curRows, NSInteger bandRows) {
    if (!prevSigs || !curSigs || prevRows <= 0 || curRows <= 0) return 0;
    NSInteger fullBand = MIN(bandRows, MIN(prevRows, curRows));
    if (fullBand < PXLongShotMinOverlapRows) return 0;
    uint8_t lo = 255, hi = 0;
    for (NSInteger r = 0; r < fullBand; r++) {
        const uint8_t *line = curSigs + r * PXLongShotSigWidth;
        for (NSInteger c = 0; c < PXLongShotSigWidth; c++) { lo = MIN(lo, line[c]); hi = MAX(hi, line[c]); }
    }
    if (hi - lo < PXLongShotUniformBandRange) return 0;
    NSInteger maxOverlap = MIN(curRows, prevRows);
    NSInteger overlap = PXLongShotFindPeak(prevSigs, prevRows, curSigs, fullBand, maxOverlap, fullBand);
    if (overlap) return overlap;
    return PXLongShotFindPeak(prevSigs, prevRows, curSigs, PXLongShotMinOverlapRows, fullBand - 1, 0);
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

BOOL PXLongShotIsDuplicateOverlap(NSInteger overlapRows, NSInteger sliceHeight) {
    return sliceHeight > 0 && overlapRows >= sliceHeight - PXLongShotDuplicateSlackRows;
}
