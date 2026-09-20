#import "PXEditorRenderer.h"
#import "../Common/PXLog.h"

static const CGFloat PXDefaultMosaicBlockSize = 24.0;   // 像素

@implementation PXEditorRenderer

#pragma mark - 绘制

+ (void)drawAnnotation:(PXAnnotation *)annotation inContext:(CGContextRef)context {
    if (!annotation || !context) return;

    CGContextSaveGState(context);
    CGContextSetAlpha(context, annotation.alpha);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    CGContextSetStrokeColorWithColor(context, annotation.color.CGColor);
    CGContextSetFillColorWithColor(context, annotation.color.CGColor);
    CGContextSetLineWidth(context, annotation.lineWidth);

    switch (annotation.type) {
        case PXAnnotationTypeBrush:
        case PXAnnotationTypeHighlight: {
            CGFloat width = (annotation.type == PXAnnotationTypeHighlight) ? annotation.lineWidth * 3.0 : annotation.lineWidth;
            CGContextSetLineWidth(context, width);
            if (annotation.type == PXAnnotationTypeHighlight) {
                CGContextSetAlpha(context, annotation.alpha * 0.4);
            }
            [self pxStrokePoints:annotation.points inContext:context];
            break;
        }
        case PXAnnotationTypeLine: {
            if (annotation.points.count >= 2) {
                CGPoint start = [annotation.points[0] CGPointValue];
                CGPoint end = [annotation.points[annotation.points.count - 1] CGPointValue];
                CGContextMoveToPoint(context, start.x, start.y);
                CGContextAddLineToPoint(context, end.x, end.y);
                CGContextStrokePath(context);
            }
            break;
        }
        case PXAnnotationTypeArrow: {
            if (annotation.points.count >= 2) {
                [self pxDrawArrow:annotation inContext:context];
            }
            break;
        }
        case PXAnnotationTypeRectangle: {
            CGContextStrokeRect(context, annotation.rect);
            break;
        }
        case PXAnnotationTypeOval: {
            CGContextStrokeEllipseInRect(context, annotation.rect);
            break;
        }
        case PXAnnotationTypeMosaic: {
            // 马赛克需要源图像素；通用入口拿不到，画布与导出各自预处理成图片后走 image 类型绘制。
            break;
        }
        case PXAnnotationTypeText: {
            [self pxDrawText:annotation inContext:context];
            break;
        }
    }
    CGContextRestoreGState(context);
}

#pragma mark - 马赛克

/// 全部在“源图点空间”工作（标注坐标即该空间）；内部按 scale 换算像素裁剪。
+ (UIImage *)mosaicImageForSourceImage:(UIImage *)sourceImage rect:(CGRect)pointRect blockSize:(CGFloat)blockSize {
    return [self mosaicImageForSourceImage:sourceImage rect:pointRect blockSize:blockSize
                              outputScale:MAX(sourceImage.scale, 1.0)];
}

+ (UIImage *)mosaicImageForSourceImage:(UIImage *)sourceImage rect:(CGRect)pointRect
                             blockSize:(CGFloat)blockSize outputScale:(CGFloat)outputScale {
    if (!sourceImage.CGImage || CGRectIsEmpty(pointRect)) return nil;

    CGRect imageRect = CGRectMake(0, 0, sourceImage.size.width, sourceImage.size.height);
    pointRect = CGRectIntersection(pointRect, imageRect);
    if (CGRectIsEmpty(pointRect)) return nil;

    blockSize = MAX(blockSize, 4.0);
    CGSize downSize = CGSizeMake(MAX(pointRect.size.width / blockSize, 1.0),
                                 MAX(pointRect.size.height / blockSize, 1.0));

    // 先裁出区域（像素空间），再缩小（平均化）、最近邻放大 → 像素块效果。
    CGRect pixelRect = CGRectMake(floor(pointRect.origin.x * sourceImage.scale),
                                  floor(pointRect.origin.y * sourceImage.scale),
                                  ceil(pointRect.size.width * sourceImage.scale),
                                  ceil(pointRect.size.height * sourceImage.scale));
    CGImageRef regionCG = CGImageCreateWithImageInRect(sourceImage.CGImage, pixelRect);
    if (!regionCG) return nil;
    UIImage *regionImage = [UIImage imageWithCGImage:regionCG scale:sourceImage.scale orientation:UIImageOrientationUp];
    CGImageRelease(regionCG);

    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = 1.0;
    format.opaque = YES;
    UIGraphicsImageRenderer *downRenderer = [[UIGraphicsImageRenderer alloc] initWithSize:downSize format:format];
    UIImage *downImage = [downRenderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextSetInterpolationQuality(ctx.CGContext, kCGInterpolationLow);
        [regionImage drawInRect:CGRectMake(0, 0, downSize.width, downSize.height)];
    }];

    // 放大位图密度由 outputScale 决定：导出与源图一致（1:1 落像素），画布预览按屏幕显示密度，
    // 避免每个马赛克标注都按源图分辨率常驻内存。
    UIGraphicsImageRendererFormat *upFormat = [[UIGraphicsImageRendererFormat alloc] init];
    upFormat.scale = MAX(outputScale, 1.0);
    upFormat.opaque = YES;
    UIGraphicsImageRenderer *upRenderer = [[UIGraphicsImageRenderer alloc] initWithSize:pointRect.size format:upFormat];
    UIImage *upImage = [upRenderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextSetInterpolationQuality(ctx.CGContext, kCGInterpolationNone);
        [downImage drawInRect:CGRectMake(0, 0, pointRect.size.width, pointRect.size.height)];
    }];
    return upImage;
}

/// 把马赛克底图绘制到 ctx（画布与导出共用，pointRect 为点空间）。
+ (void)drawMosaicImage:(UIImage *)mosaicImage rect:(CGRect)pointRect inContext:(CGContextRef)context {
    if (!mosaicImage) return;
    CGContextSaveGState(context);
    CGContextClipToRect(context, pointRect);
    [mosaicImage drawInRect:pointRect];
    CGContextRestoreGState(context);
}

#pragma mark - 导出

+ (void)renderDocument:(PXEditorDocument *)document completion:(void (^)(UIImage *))completion {
    NSParameterAssert(completion);
    // 进入导出前在调用线程（主线程）对文档做快照，杜绝后台渲染与继续绘制的竞态。
    UIImage *source = document.sourceImage;
    UIColor *background = document.backgroundColor;
    NSArray<PXAnnotation *> *annotations = [document.annotations copy];
    CGImageRef sourceCG = source.CGImage;
    if (!sourceCG) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            UIImage *result = [self pxRenderSynchronouslyWithSource:source
                                                        annotations:annotations
                                                    backgroundColor:background];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
        }
    });
}

+ (nullable UIImage *)pxRenderSynchronouslyWithSource:(UIImage *)source
                                          annotations:(NSArray<PXAnnotation *> *)annotations
                                      backgroundColor:(UIColor *)backgroundColor {
    CGImageRef sourceCG = source.CGImage;
    if (!sourceCG) return nil;

    CGSize pointSize = source.size;   // 标注坐标即该点空间

    // 马赛克底图先在后台逐个生成。
    NSMutableDictionary<NSString *, UIImage *> *mosaicCache = [[NSMutableDictionary alloc] init];
    for (PXAnnotation *annotation in annotations) {
        if (annotation.type != PXAnnotationTypeMosaic) continue;
        UIImage *mosaic = [self mosaicImageForSourceImage:source rect:annotation.rect blockSize:PXDefaultMosaicBlockSize];
        if (mosaic) {
            mosaicCache[annotation.annotationID] = mosaic;
        }
    }

    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = source.scale;   // 与源图一致：点空间坐标 1:1 落到相同像素网格，分辨率不缩水
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:pointSize format:format];

    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
        CGContextRef ctx = rendererContext.CGContext;
        CGContextSetFillColorWithColor(ctx, backgroundColor.CGColor);
        CGContextFillRect(ctx, CGRectMake(0, 0, pointSize.width, pointSize.height));

        CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
        [source drawInRect:CGRectMake(0, 0, pointSize.width, pointSize.height)];

        for (PXAnnotation *annotation in annotations) {
            if (annotation.type == PXAnnotationTypeMosaic) {
                UIImage *mosaic = mosaicCache[annotation.annotationID];
                [self drawMosaicImage:mosaic rect:annotation.rect inContext:ctx];
            } else {
                [self drawAnnotation:annotation inContext:ctx];
            }
        }
    }];
}

#pragma mark - 私有绘制

+ (void)pxStrokePoints:(NSArray<NSValue *> *)points inContext:(CGContextRef)context {
    if (points.count == 0) return;
    if (points.count == 1) {
        // 单点：画一个圆点。
        CGPoint point = [points[0] CGPointValue];
        CGContextFillEllipseInRect(context, CGRectMake(point.x - 1, point.y - 1, 2, 2));
        return;
    }
    CGContextMoveToPoint(context, [points[0] CGPointValue].x, [points[0] CGPointValue].y);
    for (NSUInteger i = 1; i < points.count; i++) {
        CGPoint point = [points[i] CGPointValue];
        CGContextAddLineToPoint(context, point.x, point.y);
    }
    CGContextStrokePath(context);
}

+ (void)pxDrawArrow:(PXAnnotation *)annotation inContext:(CGContextRef)context {
    CGPoint start = [annotation.points[0] CGPointValue];
    CGPoint end = [annotation.points[annotation.points.count - 1] CGPointValue];
    CGContextMoveToPoint(context, start.x, start.y);
    CGContextAddLineToPoint(context, end.x, end.y);
    CGContextStrokePath(context);

    CGFloat angle = atan2(end.y - start.y, end.x - start.x);
    CGFloat headLength = MAX(annotation.lineWidth * 3.5, 12.0);
    CGFloat spread = 0.42;   // 箭头张角（弧度）的一半

    CGPoint wing1 = CGPointMake(end.x - headLength * cos(angle - spread), end.y - headLength * sin(angle - spread));
    CGPoint wing2 = CGPointMake(end.x - headLength * cos(angle + spread), end.y - headLength * sin(angle + spread));

    CGContextMoveToPoint(context, wing1.x, wing1.y);
    CGContextAddLineToPoint(context, end.x, end.y);
    CGContextAddLineToPoint(context, wing2.x, wing2.y);
    CGContextStrokePath(context);
}

+ (void)pxDrawText:(PXAnnotation *)annotation inContext:(CGContextRef)context {
    if (annotation.text.length == 0) return;
    UIFont *font = [PXAnnotation fontForAnnotation:annotation];

    // UIKit 字符串绘制使用 UIKit 坐标（y 向下）；CoreGraphics 位图上下文原点在左下。
    // 导出渲染走 UIGraphicsImageRenderer（其 ctx 已翻转回 UIKit 语义），直接绘制即可。
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: annotation.color,
        NSParagraphStyleAttributeName: style,
    };
    CGRect textRect = [annotation.text boundingRectWithSize:CGSizeMake(1200, CGFLOAT_MAX)
                                                    options:NSStringDrawingUsesLineFragmentOrigin
                                                 attributes:attributes
                                                    context:nil];
    CGRect drawRect = CGRectMake(annotation.rect.origin.x, annotation.rect.origin.y,
                                 ceil(textRect.size.width) + 4, ceil(textRect.size.height) + 4);
    [annotation.text drawInRect:drawRect withAttributes:attributes];
}

@end
