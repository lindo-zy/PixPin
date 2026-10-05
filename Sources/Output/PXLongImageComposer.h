#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>
#import "../Common/PXLongShotControl.h"

NS_ASSUME_NONNULL_BEGIN

// MARK: - 常量（本模块唯一数值来源）

/// 整屏帧上限：防失控采集；只有最近帧保留用于对齐的签名。
FOUNDATION_EXPORT const NSInteger PXLongShotMaxSlices;
/// 画布像素高度预算：超出后整图等比降采样到预算内（GPU 纹理上限 16384）。
FOUNDATION_EXPORT const NSInteger PXLongShotMaxCanvasHeight;
/// 画布像素总量预算（宽×高）：位图最高约 32MB。高度上限之后的第一性约束——
/// 快照/编码可能额外占内存；本预算只约束画布，跨会话位图工作由会话串行化。
FOUNDATION_EXPORT const NSInteger PXLongShotMaxCanvasPixels;
/// 分片 JPEG 质量（拼接收口还会再编码一次，分片取高保真）。
FOUNDATION_EXPORT const CGFloat PXLongShotSliceJPEGQuality;
/// 长图输出 JPEG 质量。
FOUNDATION_EXPORT const CGFloat PXLongShotOutputJPEGQuality;
/// 超过该像素高度的成果禁止复制到剪贴板（UIPasteboard 编码尖峰会挤压 SpringBoard）。
FOUNDATION_EXPORT const NSInteger PXLongShotCopyMaxPixelHeight;

// MARK: - 分片

/// 一个已落盘整屏帧：JPEG 文件 + 最近帧的行签名。
/// 图片本体不驻留内存，拼接时按需从磁盘解码；签名计算见 Common/PXLongShotAligner.h。
@interface PXLongShotSlice : NSObject

@property (nonatomic, copy, readonly) NSString *filePath;
@property (nonatomic, assign, readonly) NSInteger pixelWidth;
@property (nonatomic, assign, readonly) NSInteger pixelHeight;
@property (nonatomic, strong, readonly) NSData *rowSignatures;
/// 对齐完成后旧帧不再需要签名，导出仅使用 JPEG。
- (void)discardAlignmentSignature;
/// 整屏帧中的有效裁片：顶部保留首帧，底部保留末帧，中间仅保留新正文。
@property (nonatomic, assign) NSInteger cropTopRows;
@property (nonatomic, assign) NSInteger cropBottomRows;
@property (nonatomic, assign, readonly) NSInteger renderedPixelHeight;

@end

// MARK: - 裁片与拼接

@interface PXLongImageComposer : NSObject

/// 从整屏抓图裁出 pixelRect（顶部原点像素坐标）写入 JPEG 文件并计算行签名。
/// 后台队列调用；抓图结果按 IOSurface 惰性子图处理，必须先解码成独立位图。
+ (nullable PXLongShotSlice *)sliceFromScreenImage:(UIImage *)screenImage
                                         pixelRect:(CGRect)pixelRect
                                          filePath:(NSString *)filePath
                                      cancellation:(PXLongShotCancellation *)cancellation
                                             error:(NSError **)error;

/// 拼接全部分片并编码 JPEG 到 outputURL（后台队列调用）。
/// 裁片位置采用会话入列时保存的 cropTopRows/cropBottomRows。
/// maxPixels 与进程实时余量共同约束画布，最高 PXLongShotMaxCanvasPixels；
/// 高度上限仍为 PXLongShotMaxCanvasHeight。分配失败则减半预算重试，保留完整图尾。
/// progressBlock（可空，调用线程即后台线程）：进度口径 2n——前 n 为偏移累计、
/// 后 n 为逐片绘制；done==total 后进入编码阶段。
/// 返回文件回读的 UIImage（scale = screenScale），画布随即释放，内存不驻留。
+ (nullable UIImage *)composedImageWithSlices:(NSArray<PXLongShotSlice *> *)slices
                                  screenScale:(CGFloat)screenScale
                                    outputURL:(NSURL *)outputURL
                                    maxPixels:(NSInteger)maxPixels
                                 cancellation:(PXLongShotCancellation *)cancellation
                                progressBlock:(nullable void (^)(NSInteger done, NSInteger total))progressBlock
                                 outPixelSize:(nullable CGSize *)outPixelSize
                                        error:(NSError **)error;

/// 从已落盘 JPEG 直接降采样出小尺寸缩略图（ImageIO 解码峰值受 maxPixelSize 约束，
/// 不整幅解码原图）。用于结果气泡缩略图，避免为 88pt 小图解出整幅长图。
+ (nullable UIImage *)thumbnailImageFromFile:(NSString *)filePath
                                 screenScale:(CGFloat)screenScale
                                maxPixelSize:(CGFloat)maxPixelSize;

@end

NS_ASSUME_NONNULL_END
