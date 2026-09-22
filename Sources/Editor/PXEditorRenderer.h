#import <UIKit/UIKit.h>
#import "PXAnnotation.h"

NS_ASSUME_NONNULL_BEGIN

@class PXEditorDocument;

/// 标注合成：屏幕预览与导出共用同一套绘制路径，保证所见即所得。
/// 绘制坐标一律为“源图点空间”；调用方负责把 CGContext 变换到该空间。
@interface PXEditorRenderer : NSObject

/// 单个标注的绘制。ctx 需已处于图片点空间。
/// - sourceImage：magnifier 取样用；
/// - pixelatedImage：mosaic 底图（整图像素化，见 pixelatedImageForSourceImage...），可为 nil（灰块兜底）。
+ (void)drawAnnotation:(PXAnnotation *)annotation
             inContext:(CGContextRef)context
           sourceImage:(nullable UIImage *)sourceImage
        pixelatedImage:(nullable UIImage *)pixelatedImage;

/// 整图一次性像素化底图（ShellX generateBlurredImage 的像素化等价物）：
/// 马赛克标注只做裁剪贴图，拖拽/撤销不再逐帧重新生成。
/// blockSize 为点空间马赛克块边长；outputScale 控制产出位图密度（画布按屏幕密度、导出按源图密度）。
+ (nullable UIImage *)pixelatedImageForSourceImage:(UIImage *)sourceImage
                                         blockSize:(CGFloat)blockSize
                                       outputScale:(CGFloat)outputScale;

/// 后台合成导出图（源图 + 背景 + 标注），主线程回调。失败回调 nil。
+ (void)renderDocument:(PXEditorDocument *)document
            completion:(void (^)(UIImage *result))completion;

#pragma mark - 裁剪 / 旋转烘焙

/// 按点空间 rect 裁剪（自动截断到图内并落像素网格）。
+ (nullable UIImage *)cropImage:(UIImage *)image toRect:(CGRect)pointRect;

/// 标注集合随裁剪重映射：完全在裁剪框外的丢弃，其余平移进新坐标。
+ (NSArray<PXAnnotation *> *)annotationsByApplyingCrop:(CGRect)cropRect
                                          toAnnotations:(NSArray<PXAnnotation *> *)annotations;

/// 顺时针旋转 90° 烘焙底图（宽高互换）。
+ (nullable UIImage *)rotateImage90Clockwise:(UIImage *)image;

/// 标注几何随顺时针 90° 旋转重映射（文字保持水平，sticker 叠加旋转角）。
+ (NSArray<PXAnnotation *> *)annotationsByRotating90Clockwise:(NSArray<PXAnnotation *> *)annotations
                                                sourceImageSize:(CGSize)sourceSize;

@end

NS_ASSUME_NONNULL_END
