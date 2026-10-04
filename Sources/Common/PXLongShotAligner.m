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

static NSInteger PXLongShotBandCost(const uint8_t *prevSigs, NSInteger prevRows,
                                    const uint8_t *curSigs,
                                    NSInteger bandRows, NSInteger anchorTop) {
    // cur 顶部 bandRows 行对齐到 prev 的 [anchorTop, anchorTop+bandRows)。
    if (anchorTop < 0 || anchorTop + bandRows > prevRows) return NSIntegerMax;
    const uint8_t *p = prevSigs + (size_t)anchorTop * PXLongShotSigWidth;
    const uint8_t *c = curSigs;
    size_t count = (size_t)bandRows * PXLongShotSigWidth;
    uint64_t total = 0;
    for (size_t i = 0; i < count; i++) {
        total += p[i] > c[i] ? p[i] - c[i] : c[i] - p[i];
    }
    return (NSInteger)(total / (uint64_t)count);
}

NSInteger PXLongShotSearchOverlap(const uint8_t *prevSigs, NSInteger prevRows,
                                  const uint8_t *curSigs, NSInteger curRows,
                                  NSInteger bandRows) {
    if (!prevSigs || !curSigs || prevRows <= 0 || curRows <= 0) return 0;
    NSInteger fullBand = MIN(bandRows, MIN(prevRows, curRows));
    if (fullBand < PXLongShotMinOverlapRows) return 0;

    // 顶部带无纹理（纯色/渐变过渡）时签名无判别力，按无重叠追加：
    // 均匀内容的重复行在视觉上不可见，宁重复不错位。
    uint8_t lo = 255, hi = 0;
    for (NSInteger r = 0; r < fullBand; r++) {
        const uint8_t *line = curSigs + r * PXLongShotSigWidth;
        for (NSInteger c = 0; c < PXLongShotSigWidth; c++) {
            lo = MIN(lo, line[c]);
            hi = MAX(hi, line[c]);
        }
    }
    if (hi - lo < PXLongShotUniformBandRange) return 0;

    // 重叠 o 意味着 cur[0..o) 与 prev[prevRows-o..prevRows) 相同。
    // 上限不预留 slack：近整片重叠（几乎没滚动）必须可被搜到，交由重复判定统一收口。
    NSInteger maxOverlap = MIN(curRows, prevRows);
    if (maxOverlap < PXLongShotMinOverlapRows) return 0;

    // 第一段：全长带只覆盖 o ≥ fullBand 的大重叠，判别力最强。
    NSInteger best = NSIntegerMax, second = NSIntegerMax, bestOverlap = 0;
    for (NSInteger o = fullBand; o <= maxOverlap; o++) {
        NSInteger cost = PXLongShotBandCost(prevSigs, prevRows, curSigs, fullBand, prevRows - o);
        if (cost < best) {
            second = best;
            best = cost;
            bestOverlap = o;
        } else if (cost < second) {
            second = cost;
        }
    }
    CGFloat bestAvg = best == NSIntegerMax ? CGFLOAT_MAX : (CGFloat)best;
    CGFloat secondAvg = (second == NSIntegerMax || best == NSIntegerMax) ? CGFLOAT_MAX : (CGFloat)second;
    if (bestAvg > PXLongShotAcceptAvgDiff || secondAvg - bestAvg < PXLongShotMarginAvgDiff) {
        // 第二段：小重叠（o < fullBand）用逐候选变长窗口精确比对，
        // 防止近整屏滚动被误判成无重叠（无重叠会把重叠内容整段重复进长图）。
        best = NSIntegerMax;
        second = NSIntegerMax;
        bestOverlap = 0;
        for (NSInteger o = PXLongShotMinOverlapRows; o < fullBand; o++) {
            NSInteger cost = PXLongShotBandCost(prevSigs, prevRows, curSigs, o, prevRows - o);
            if (cost < best) {
                second = best;
                best = cost;
                bestOverlap = o;
            } else if (cost < second) {
                second = cost;
            }
        }
        bestAvg = best == NSIntegerMax ? CGFLOAT_MAX : (CGFloat)best;
        secondAvg = (second == NSIntegerMax || best == NSIntegerMax) ? CGFLOAT_MAX : (CGFloat)second;
    }
    if (bestOverlap == 0 || bestAvg > PXLongShotAcceptAvgDiff) return 0;   // 内容变化太大
    if (secondAvg - bestAvg < PXLongShotMarginAvgDiff) return 0;           // 匹配不唯一
    return bestOverlap;
}

BOOL PXLongShotIsDuplicateOverlap(NSInteger overlapRows, NSInteger sliceHeight) {
    return sliceHeight > 0 && overlapRows >= sliceHeight - PXLongShotDuplicateSlackRows;
}
