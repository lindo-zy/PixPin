#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - 常量（本模块唯一数值来源）

/// 分片上限：防失控采集，也约束签名驻留内存（≤50 × 每片 ~180KB）。
FOUNDATION_EXPORT const NSInteger PXLongShotMaxSlices;
/// 画布像素高度预算：超出后整图等比降采样到预算内（GPU 纹理上限 16384）。
FOUNDATION_EXPORT const NSInteger PXLongShotMaxCanvasHeight;
/// 分片 JPEG 质量（拼接收口还会再编码一次，分片取高保真）。
FOUNDATION_EXPORT const CGFloat PXLongShotSliceJPEGQuality;
/// 长图输出 JPEG 质量。
FOUNDATION_EXPORT const CGFloat PXLongShotOutputJPEGQuality;
/// 超过该像素高度的成果禁止复制到剪贴板（UIPasteboard 编码尖峰会挤压 SpringBoard）。
FOUNDATION_EXPORT const NSInteger PXLongShotCopyMaxPixelHeight;

// MARK: - 分片

/// 一个已落盘分片：JPEG 文件 + 驻内存的行签名（pixelHeight × PXLongShotSigWidth 字节）。
/// 图片本体不驻留内存，拼接时按需从磁盘解码；签名计算见 Common/PXLongShotAligner.h。
@interface PXLongShotSlice : NSObject

@property (nonatomic, copy, readonly) NSString *filePath;
@property (nonatomic, assign, readonly) NSInteger pixelWidth;
@property (nonatomic, assign, readonly) NSInteger pixelHeight;
@property (nonatomic, strong, readonly) NSData *rowSignatures;

@end

// MARK: - 裁片与拼接

@interface PXLongImageComposer : NSObject

/// 从整屏抓图裁出 pixelRect（顶部原点像素坐标）写入 JPEG 文件并计算行签名。
/// 后台队列调用；抓图结果按 IOSurface 惰性子图处理，必须先解码成独立位图。
+ (nullable PXLongShotSlice *)sliceFromScreenImage:(UIImage *)screenImage
                                         pixelRect:(CGRect)pixelRect
                                          filePath:(NSString *)filePath
                                             error:(NSError **)error;

/// 拼接全部分片并编码 JPEG 到 outputURL（后台队列调用）。
/// 重叠行数在本方法内按签名统一计算（与会话期反馈同源同值）。
/// 画布超出 PXLongShotMaxCanvasHeight 时整图等比降采样。
/// 返回文件回读的 UIImage（scale = screenScale），画布随即释放，内存不驻留。
+ (nullable UIImage *)composedImageWithSlices:(NSArray<PXLongShotSlice *> *)slices
                                  screenScale:(CGFloat)screenScale
                                    outputURL:(NSURL *)outputURL
                                 outPixelSize:(nullable CGSize *)outPixelSize
                                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
