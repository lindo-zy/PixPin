#import <UIKit/UIKit.h>
#import "PXAnnotation.h"
#import "PXEditorDocument.h"

NS_ASSUME_NONNULL_BEGIN

/// 标注合成：屏幕预览与导出共用同一套绘制路径，保证所见即所得。
/// 绘制坐标一律为“图片像素空间”；调用方负责把 CGContext 变换到该空间。
@interface PXEditorRenderer : NSObject

/// 单个标注的绘制（画布绘制活动标注时复用）。ctx 需已变换到图片像素空间。
+ (void)drawAnnotation:(PXAnnotation *)annotation inContext:(CGContextRef)context;

/// 生成马赛克底图（区域内像素化）。画布与导出共用，保证一致。
+ (UIImage *)mosaicImageForSourceImage:(UIImage *)sourceImage rect:(CGRect)pixelRect blockSize:(CGFloat)blockSize;

/// 预览变体：outputScale 控制产出位图密度（画布按屏幕显示密度生成，避免按源图分辨率占内存）；
/// 马赛克块在点空间尺寸不变，仅边缘细节随密度变化，导出仍走全密度路径。
+ (UIImage *)mosaicImageForSourceImage:(UIImage *)sourceImage rect:(CGRect)pixelRect
                             blockSize:(CGFloat)blockSize outputScale:(CGFloat)outputScale;

/// 把马赛克底图绘制到 ctx（画布预览与导出共用）。
+ (void)drawMosaicImage:(UIImage *)mosaicImage rect:(CGRect)pixelRect inContext:(CGContextRef)context;

/// 后台合成导出图（源图 + 背景 + 标注），主线程回调。失败回调 nil。
+ (void)renderDocument:(PXEditorDocument *)document
            completion:(void (^)(UIImage *result))completion;

@end

NS_ASSUME_NONNULL_END
