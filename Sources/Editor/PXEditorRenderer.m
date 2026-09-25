#import "PXEditorRenderer.h"
#import "PXEditorDocument.h"
#import "../Common/PXLog.h"

@implementation PXEditorRenderer

#pragma mark - 绘制

+ (void)drawAnnotation:(PXAnnotation *)annotation
             inContext:(CGContextRef)context
           sourceImage:(UIImage *)sourceImage
        pixelatedImage:(UIImage *)pixelatedImage {
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
            [self pxStrokePoints:annotation.points lineWidth:width inContext:context];
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
            if (annotation.fillStyle == PXAnnotationFillStyleSolid) {
                CGContextFillRect(context, annotation.rect);
            } else {
                CGContextStrokeRect(context, annotation.rect);
            }
            break;
        }
        case PXAnnotationTypeOval: {
            if (annotation.fillStyle == PXAnnotationFillStyleSolid) {
                CGContextFillEllipseInRect(context, annotation.rect);
            } else {
                CGContextStrokeEllipseInRect(context, annotation.rect);
            }
            break;
        }
        case PXAnnotationTypeMosaic: {
            CGRect imageBounds = CGRectMake(0, 0, sourceImage.size.width, sourceImage.size.height);
            if (CGRectIsEmpty(imageBounds)) break;

            if (annotation.points.count > 0) {
                // 涂抹式：沿笔迹描边生成裁剪区域，再在区域内铺像素化底图。
                NSArray<NSValue *> *points = annotation.points;
                CGFloat smearWidth = MAX(annotation.lineWidth * 2.0, 8.0);
                if (points.count == 1) {
                    // 单点（轻点一下）：按圆点处理；moveto-only 路径的描边为空。
                    CGPoint p = [points[0] CGPointValue];
                    CGContextAddEllipseInRect(context,
                                              CGRectMake(p.x - smearWidth / 2.0, p.y - smearWidth / 2.0,
                                                         smearWidth, smearWidth));
                } else {
                    CGMutablePathRef strokePath = CGPathCreateMutable();
                    CGPathMoveToPoint(strokePath, NULL,
                                      [points[0] CGPointValue].x, [points[0] CGPointValue].y);
                    for (NSUInteger i = 1; i < points.count; i++) {
                        CGPoint p = [points[i] CGPointValue];
                        CGPathAddLineToPoint(strokePath, NULL, p.x, p.y);
                    }
                    CGContextSetLineWidth(context, smearWidth);
                    CGContextSetLineCap(context, kCGLineCapRound);
                    CGContextSetLineJoin(context, kCGLineJoinRound);
                    CGContextAddPath(context, strokePath);
                    CGPathRelease(strokePath);
                    CGContextReplacePathWithStrokedPath(context);
                }
                CGContextClip(context);
            } else {
                // 兼容旧矩形马赛克。
                CGRect clipRect = CGRectIntersection(annotation.rect, imageBounds);
                if (CGRectIsEmpty(clipRect)) break;
                CGContextClipToRect(context, clipRect);
            }

            if (pixelatedImage) {
                [pixelatedImage drawInRect:imageBounds];
            } else {
                // 预览底图未就绪时的占位（与源图等铺，裁剪区限制范围）。
                CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0.7 alpha:0.9].CGColor);
                CGContextFillRect(context, imageBounds);
            }
            break;
        }
        case PXAnnotationTypeSpotlight: {
            // 全域压暗 + 挖孔（even-odd），不破坏下层已绘制内容。
            CGMutablePathRef path = CGPathCreateMutable();
            CGPathAddRect(path, NULL, CGRectInfinite);
            if (annotation.holeIsEllipse) {
                CGPathAddEllipseInRect(path, NULL, annotation.rect);
            } else {
                CGPathAddRect(path, NULL, annotation.rect);
            }
            CGContextSetAlpha(context, 0.62);
            CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);
            CGContextAddPath(context, path);
            CGContextEOFillPath(context);   // even-odd：外环与挖孔相交数为 0，只压暗挖孔之外
            CGPathRelease(path);
            break;
        }
        case PXAnnotationTypeText: {
            [self pxDrawText:annotation inContext:context];
            break;
        }
        case PXAnnotationTypeMagnifier: {
            [self pxDrawMagnifier:annotation sourceImage:sourceImage inContext:context];
            break;
        }
        case PXAnnotationTypeSticker: {
            [self pxDrawSticker:annotation inContext:context];
            break;
        }
        case PXAnnotationTypeStamp: {
            [self pxDrawStamp:annotation inContext:context];
            break;
        }
        default:
            break;
    }
    CGContextRestoreGState(context);
}

#pragma mark - 像素化底图

+ (nullable UIImage *)pixelatedImageForSourceImage:(UIImage *)sourceImage
                                         blockSize:(CGFloat)blockSize
                                       outputScale:(CGFloat)outputScale {
    CGImageRef sourceCG = sourceImage.CGImage;
    if (!sourceCG || sourceImage.size.width < 1 || sourceImage.size.height < 1) return nil;

    blockSize = MAX(blockSize, 4.0);
    CGSize pointSize = sourceImage.size;
    CGSize downSize = CGSizeMake(MAX(pointSize.width / blockSize, 1.0),
                                 MAX(pointSize.height / blockSize, 1.0));

    UIGraphicsImageRendererFormat *downFormat = [[UIGraphicsImageRendererFormat alloc] init];
    downFormat.scale = 1.0;
    downFormat.opaque = YES;
    UIGraphicsImageRenderer *downRenderer = [[UIGraphicsImageRenderer alloc] initWithSize:downSize format:downFormat];
    UIImage *downImage = [downRenderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextSetInterpolationQuality(ctx.CGContext, kCGInterpolationLow);
        [sourceImage drawInRect:CGRectMake(0, 0, downSize.width, downSize.height)];
    }];

    UIGraphicsImageRendererFormat *upFormat = [[UIGraphicsImageRendererFormat alloc] init];
    upFormat.scale = MAX(outputScale, 1.0);
    upFormat.opaque = YES;
    UIGraphicsImageRenderer *upRenderer = [[UIGraphicsImageRenderer alloc] initWithSize:pointSize format:upFormat];
    return [upRenderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextSetInterpolationQuality(ctx.CGContext, kCGInterpolationNone);
        [downImage drawInRect:CGRectMake(0, 0, pointSize.width, pointSize.height)];
    }];
}

#pragma mark - 导出

+ (void)renderDocument:(PXEditorDocument *)document completion:(void (^)(UIImage *))completion {
    NSParameterAssert(completion);
    // 进入导出前在调用线程（主线程）对文档做快照，杜绝后台渲染与继续绘制的竞态。
    UIImage *source = document.sourceImage;
    UIColor *background = document.backgroundColor;
    NSArray<PXAnnotation *> *annotations = [document.annotations copy];
    if (!source.CGImage) {
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

    BOOL needsPixelated = NO;
    for (PXAnnotation *annotation in annotations) {
        if (annotation.type == PXAnnotationTypeMosaic) {
            needsPixelated = YES;
            break;
        }
    }
    UIImage *pixelated = nil;
    if (needsPixelated) {
        pixelated = [self pixelatedImageForSourceImage:source
                                             blockSize:[self pxMosaicBlockSizeForImage:source]
                                           outputScale:MAX(source.scale, 1.0)];
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
            [self drawAnnotation:annotation inContext:ctx sourceImage:source pixelatedImage:pixelated];
        }
    }];
}

#pragma mark - 裁剪 / 旋转烘焙

+ (nullable UIImage *)cropImage:(UIImage *)image toRect:(CGRect)pointRect {
    CGImageRef sourceCG = image.CGImage;
    if (!sourceCG) return nil;

    CGRect bounds = CGRectMake(0, 0, image.size.width, image.size.height);
    pointRect = CGRectIntersection(pointRect, bounds);
    if (CGRectIsEmpty(pointRect)) return nil;

    CGFloat scale = MAX(image.scale, 1.0);
    CGFloat minX = floor(CGRectGetMinX(pointRect) * scale);
    CGFloat minY = floor(CGRectGetMinY(pointRect) * scale);
    CGFloat maxX = ceil(CGRectGetMaxX(pointRect) * scale);
    CGFloat maxY = ceil(CGRectGetMaxY(pointRect) * scale);
    CGRect pixelRect = CGRectMake(minX, minY, maxX - minX, maxY - minY);
    pixelRect = CGRectIntersection(pixelRect,
                                   CGRectMake(0, 0, CGImageGetWidth(sourceCG), CGImageGetHeight(sourceCG)));
    if (CGRectIsEmpty(pixelRect)) return nil;

    // 重绘为独立像素图，文档替换底图后编辑画布直接使用这张裁剪结果。
    CGSize outputSize = CGSizeMake(pixelRect.size.width / scale, pixelRect.size.height / scale);
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = scale;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:outputSize format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextSetInterpolationQuality(context.CGContext, kCGInterpolationNone);
        [image drawInRect:CGRectMake(-pixelRect.origin.x / scale,
                                     -pixelRect.origin.y / scale,
                                     image.size.width, image.size.height)];
    }];
}

+ (NSArray<PXAnnotation *> *)annotationsByApplyingCrop:(CGRect)cropRect
                                          toAnnotations:(NSArray<PXAnnotation *> *)annotations {
    NSMutableArray<PXAnnotation *> *result = [[NSMutableArray alloc] init];
    for (PXAnnotation *annotation in annotations) {
        CGRect bounds = annotation.boundsInImageSpace;
        if (CGRectIsNull(bounds) || CGRectIsEmpty(bounds)) continue;
        if (CGRectIsEmpty(CGRectIntersection(bounds, cropRect))) continue;
        PXAnnotation *copy = [annotation copy];
        if (copy.points.count > 0) {
            NSMutableArray<NSValue *> *shifted = [[NSMutableArray alloc] init];
            for (NSValue *value in copy.points) {
                CGPoint p = [value CGPointValue];
                [shifted addObject:[NSValue valueWithCGPoint:CGPointMake(p.x - cropRect.origin.x,
                                                                         p.y - cropRect.origin.y)]];
            }
            copy.points = shifted;
        }
        if (!CGRectIsEmpty(copy.rect)) {
            copy.rect = CGRectOffset(copy.rect, -cropRect.origin.x, -cropRect.origin.y);
        }
        [result addObject:copy];
    }
    return result;
}

+ (nullable UIImage *)rotateImage90Clockwise:(UIImage *)image {
    CGImageRef sourceCG = image.CGImage;
    if (!sourceCG) return nil;

    CGSize oldSize = image.size;
    CGSize newSize = CGSizeMake(oldSize.height, oldSize.width);
    CGFloat scale = MAX(image.scale, 1.0);

    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = scale;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:newSize format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
        CGContextRef ctx = rendererContext.CGContext;
        // UIKit y-down 坐标系：平移到右上角再旋转 +90°，等价于内容顺时针旋转。
        CGContextTranslateCTM(ctx, newSize.width, 0);
        CGContextRotateCTM(ctx, M_PI_2);
        [image drawInRect:CGRectMake(0, 0, oldSize.width, oldSize.height)];
    }];
}

+ (NSArray<PXAnnotation *> *)annotationsByRotating90Clockwise:(NSArray<PXAnnotation *> *)annotations
                                                sourceImageSize:(CGSize)sourceSize {
    CGFloat oldHeight = sourceSize.height;
    NSMutableArray<PXAnnotation *> *result = [[NSMutableArray alloc] init];
    for (PXAnnotation *annotation in annotations) {
        PXAnnotation *copy = [annotation copy];
        if (copy.points.count > 0) {
            NSMutableArray<NSValue *> *rotated = [[NSMutableArray alloc] init];
            for (NSValue *value in copy.points) {
                CGPoint p = [value CGPointValue];
                [rotated addObject:[NSValue valueWithCGPoint:CGPointMake(oldHeight - p.y, p.x)]];
            }
            copy.points = rotated;
        }
        if (!CGRectIsEmpty(copy.rect)) {
            if (copy.type == PXAnnotationTypeText) {
                // 文字保持水平：映射中心点，尺寸不变。
                CGPoint center = CGPointMake(oldHeight - CGRectGetMidY(copy.rect), CGRectGetMidX(copy.rect));
                copy.rect = CGRectMake(center.x - copy.rect.size.width / 2.0,
                                       center.y - copy.rect.size.height / 2.0,
                                       copy.rect.size.width, copy.rect.size.height);
            } else {
                // 顶点规则：tl(x,y)→(H−y,x)，br(x+w,y+h)→(H−y−h,x+w)。
                CGFloat x = copy.rect.origin.x;
                CGFloat y = copy.rect.origin.y;
                CGFloat w = copy.rect.size.width;
                CGFloat h = copy.rect.size.height;
                copy.rect = CGRectMake(oldHeight - y - h, x, h, w);
            }
        }
        if (copy.type == PXAnnotationTypeSticker) {
            copy.rotation += M_PI_2;
        }
        [result addObject:copy];
    }
    return result;
}

#pragma mark - 私有绘制

+ (CGFloat)pxMosaicBlockSizeForImage:(UIImage *)image {
    CGFloat shortSide = MIN(image.size.width, image.size.height);
    return MAX(10.0, MIN(40.0, shortSide / 40.0));
}

+ (void)pxStrokePoints:(NSArray<NSValue *> *)points lineWidth:(CGFloat)lineWidth inContext:(CGContextRef)context {
    if (points.count == 0) return;
    if (points.count == 1) {
        // 单点：画一个圆点。
        CGPoint point = [points[0] CGPointValue];
        CGFloat radius = MAX(lineWidth / 2.0, 1.0);
        CGContextFillEllipseInRect(context, CGRectMake(point.x - radius, point.y - radius, radius * 2, radius * 2));
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
    CGFloat headLength = MAX(annotation.lineWidth * 3.5, annotation.lineWidth + 8.0);
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

    // UIKit 字符串绘制使用 UIKit 坐标（y 向下）；UIGraphicsImageRenderer 的 ctx 已是 UIKit 语义，直接绘制。
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: annotation.color,
        NSParagraphStyleAttributeName: style,
    };
    CGFloat boxWidth = annotation.rect.size.width > 0 ? annotation.rect.size.width : 400.0;
    CGRect textRect = [annotation.text boundingRectWithSize:CGSizeMake(boxWidth, CGFLOAT_MAX)
                                                    options:NSStringDrawingUsesLineFragmentOrigin
                                                 attributes:attributes
                                                    context:nil];
    CGRect drawRect = CGRectMake(annotation.rect.origin.x, annotation.rect.origin.y,
                                 ceil(textRect.size.width) + 4, ceil(textRect.size.height) + 4);
    // 半透明衬底提升任何底色上的可读性（ShellX SSEditLabel 的 effectStyle 简化版）。
    CGRect backingRect = CGRectInset(drawRect, -4, -2);
    CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:1.0 alpha:0.18].CGColor);
    UIBezierPath *backing = [UIBezierPath bezierPathWithRoundedRect:backingRect cornerRadius:4];
    CGContextAddPath(context, backing.CGPath);
    CGContextFillPath(context);

    CGContextSetFillColorWithColor(context, annotation.color.CGColor);
    [annotation.text drawInRect:drawRect withAttributes:attributes];
}

+ (void)pxDrawMagnifier:(PXAnnotation *)annotation
            sourceImage:(UIImage *)sourceImage
              inContext:(CGContextRef)context {
    CGRect rect = annotation.rect;
    CGFloat radius = MIN(rect.size.width, rect.size.height) / 2.0;
    if (radius <= 0 || !sourceImage.CGImage) return;
    CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    CGFloat zoom = MAX(annotation.zoom, 1.2);

    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, rect);
    CGContextClip(context);

    // 取样：center 附近 1/zoom 区域放大 zoom 倍绘制到圆内。
    CGContextTranslateCTM(context, center.x, center.y);
    CGContextScaleCTM(context, zoom, zoom);
    CGContextTranslateCTM(context, -center.x, -center.y);
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    [sourceImage drawInRect:CGRectMake(0, 0, sourceImage.size.width, sourceImage.size.height)];
    CGContextRestoreGState(context);

    // 白色主环 + 深色外圈，任何底色上都有边界。
    CGFloat ringWidth = MAX(4.0, radius * 0.10);
    CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(context, ringWidth);
    CGContextStrokeEllipseInRect(context, CGRectInset(rect, ringWidth / 2.0, ringWidth / 2.0));
    CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:0.1 alpha:0.85].CGColor);
    CGContextSetLineWidth(context, MAX(1.0, ringWidth * 0.3));
    CGContextStrokeEllipseInRect(context, CGRectInset(rect, ringWidth * 1.4, ringWidth * 1.4));
}

+ (void)pxDrawSticker:(PXAnnotation *)annotation inContext:(CGContextRef)context {
    NSString *emoji = annotation.stickerText;
    if (emoji.length == 0) return;

    CGPoint center = CGPointMake(CGRectGetMidX(annotation.rect), CGRectGetMidY(annotation.rect));
    CGFloat size = MIN(annotation.rect.size.width, annotation.rect.size.height);
    if (size <= 0) return;

    CGContextSaveGState(context);
    CGContextTranslateCTM(context, center.x, center.y);
    CGContextRotateCTM(context, annotation.rotation);
    NSDictionary *attributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:size * 0.86],
    };
    CGSize textSize = [emoji sizeWithAttributes:attributes];
    CGPoint origin = CGPointMake(-textSize.width / 2.0, -textSize.height / 2.0);
    [emoji drawAtPoint:origin withAttributes:attributes];
    CGContextRestoreGState(context);
}

+ (void)pxDrawStamp:(PXAnnotation *)annotation inContext:(CGContextRef)context {
    CGFloat size = MIN(annotation.rect.size.width, annotation.rect.size.height);
    if (size <= 0) return;

    // 白描边圆底 + 标注色 + 序号。
    CGContextSetFillColorWithColor(context, annotation.color.CGColor);
    CGContextFillEllipseInRect(context, annotation.rect);
    CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(context, MAX(2.0, size * 0.06));
    CGContextStrokeEllipseInRect(context, CGRectInset(annotation.rect, size * 0.03, size * 0.03));

    NSString *number = [NSString stringWithFormat:@"%ld", (long)MAX(annotation.stampNumber, 1)];
    NSDictionary *attributes = @{
        NSFontAttributeName: [UIFont fontWithName:@"PingFangSC-Semibold" size:size * 0.52]
            ?: [UIFont boldSystemFontOfSize:size * 0.52],
        NSForegroundColorAttributeName: [UIColor whiteColor],
    };
    CGSize textSize = [number sizeWithAttributes:attributes];
    CGPoint origin = CGPointMake(CGRectGetMidX(annotation.rect) - textSize.width / 2.0,
                                 CGRectGetMidY(annotation.rect) - textSize.height / 2.0);
    [number drawAtPoint:origin withAttributes:attributes];
}

@end
