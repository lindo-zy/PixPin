#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - 长截图重叠对齐（纯逻辑层，宿主单测覆盖；禁止依赖 UIKit）

/// 行签名宽度：每行采样 64 个亮度值。
FOUNDATION_EXPORT const NSInteger PXLongShotSigWidth;

/// 从 RGBA8 缓冲计算一行签名：横向等距采样 SigWidth 列做 3 点均值亮度。
/// buffer 为顶部原点；bytesPerRow 支持带 stride 的位图。
void PXLongShotComputeRowSignature(const uint8_t *buffer,
                                    NSInteger pixelWidth,
                                    NSInteger bytesPerRow,
                                    NSInteger row,
                                    uint8_t *outSig);

/// 在 prev 行签名条中搜索 cur 顶部与 prev 底部的重叠行数（两段式：全长带匹配大重叠，
/// 变长短窗匹配小重叠）。返回可信匹配的重叠行数；内容带无纹理、匹配歧义或差异过大时
/// 返回 0（调用方按“无重叠”追加）。
/// sigs 为行主序：sigs[row * PXLongShotSigWidth + col]；bandRows 为首选全长带行数。
NSInteger PXLongShotSearchOverlap(const uint8_t *prevSigs, NSInteger prevRows,
                                  const uint8_t *curSigs, NSInteger curRows,
                                  NSInteger bandRows);

/// 重叠行数达到“几乎整片重复”即视为未滚动的重复截取。
BOOL PXLongShotIsDuplicateOverlap(NSInteger overlapRows, NSInteger sliceHeight);
/// 同尺寸整片签名比较；静止文字/纯色页也可去重，不依赖顶部匹配带是否有纹理。
BOOL PXLongShotSignaturesAreDuplicate(const uint8_t *prevSigs, NSInteger prevRows,
                                     const uint8_t *curSigs, NSInteger curRows);

NS_ASSUME_NONNULL_END
