#import "PXLongImageComposer.h"
#import "../Common/PXLog.h"
#import "../Common/PXLongShotAligner.h"
#import <ImageIO/ImageIO.h>
#import <math.h>

const NSInteger PXLongShotMaxSlices = 50;
const NSInteger PXLongShotMaxCanvasHeight = 16384;
// 24M 像素 ≈ 96MB 位图：手机全宽（~1320px）× 16384 高 ≈ 21.6M，在预算内不受影响；
// 宽幅设备（iPad 等）超预算后按比例二次缩宽，保证 CreateImage 复制瞬态可控。
const NSInteger PXLongShotMaxCanvasPixels = 24 * 1000 * 1000;
const CGFloat PXLongShotSliceJPEGQuality = 0.95;
const CGFloat PXLongShotOutputJPEGQuality = 0.9;
const NSInteger PXLongShotCopyMaxPixelHeight = 8192;

#pragma mark - 分片

@interface PXLongShotSlice ()
@property (nonatomic, copy, readwrite) NSString *filePath;
@property (nonatomic, assign, readwrite) NSInteger pixelWidth;
@property (nonatomic, assign, readwrite) NSInteger pixelHeight;
@property (nonatomic, strong, readwrite) NSData *rowSignatures;
@end

@implementation PXLongShotSlice
@end

static NSError *PXLongShotError(NSString *message) {
    return [NSError errorWithDomain:@"com.pixpin.screenshot.longshot"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL PXLongShotWriteJPEG(CGImageRef image, NSURL *url, CGFloat quality) {
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
        (__bridge CFURLRef)url, CFSTR("public.jpeg"), 1, NULL);
    if (!destination) return NO;
    CGImageDestinationAddImage(destination, image,
                               (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @(quality)});
    BOOL ok = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    return ok;
}

@implementation PXLongImageComposer

+ (nullable PXLongShotSlice *)sliceFromScreenImage:(UIImage *)screenImage
                                         pixelRect:(CGRect)pixelRect
                                          filePath:(NSString *)filePath
                                             error:(NSError **)error {
    CGImageRef source = screenImage.CGImage;
    NSInteger srcW = (NSInteger)CGImageGetWidth(source);
    NSInteger srcH = (NSInteger)CGImageGetHeight(source);
    CGRect rect = CGRectIntersection(pixelRect, CGRectMake(0, 0, srcW, srcH));
    NSInteger w = (NSInteger)CGRectGetWidth(rect);
    NSInteger h = (NSInteger)CGRectGetHeight(rect);
    if (w < 1 || h < 1) {
        if (error) *error = PXLongShotError(@"分片像素矩形无效");
        return nil;
    }

    // 与 PXCaptureCoordinator pxCropImage 同一套解码约束：IOSurface 惰性子图必须
    // 绘制成独立位图；pixelRect 为顶部原点，CG 上下文为底部原点，需翻转对齐。
    CGContextRef context = CGBitmapContextCreate(NULL, (NSUInteger)w, (NSUInteger)h, 8, 0,
                                                 CGImageGetColorSpace(source),
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    if (!context) {
        if (error) *error = PXLongShotError(@"分片位图创建失败");
        return nil;
    }
    CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, w, h));
    CGContextClipToRect(context, CGRectMake(0, 0, w, h));
    CGContextTranslateCTM(context, -rect.origin.x, h - srcH + rect.origin.y);
    CGContextDrawImage(context, CGRectMake(0, 0, srcW, srcH), source);

    // 签名在释放位图前从缓冲直接采样，避免再做一次降采样解码。
    NSInteger bytesPerRow = (NSInteger)CGBitmapContextGetBytesPerRow(context);
    uint8_t *buffer = (uint8_t *)CGBitmapContextGetData(context);
    NSMutableData *signatures = [NSMutableData dataWithLength:(NSUInteger)h * (NSUInteger)PXLongShotSigWidth];
    uint8_t *sigBytes = (uint8_t *)signatures.mutableBytes;
    if (buffer && sigBytes) {
        for (NSInteger r = 0; r < h; r++) {
            PXLongShotComputeRowSignature(buffer, w, bytesPerRow, r, sigBytes + r * PXLongShotSigWidth);
        }
    }

    CGImageRef cropped = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!cropped) {
        if (error) *error = PXLongShotError(@"分片图像提取失败");
        return nil;
    }

    BOOL written = PXLongShotWriteJPEG(cropped, [NSURL fileURLWithPath:filePath],
                                       PXLongShotSliceJPEGQuality);
    CGImageRelease(cropped);
    if (!written) {
        if (error) *error = PXLongShotError(@"分片写入磁盘失败");
        return nil;
    }

    PXLongShotSlice *slice = [[PXLongShotSlice alloc] init];
    slice.filePath = filePath;
    slice.pixelWidth = w;
    slice.pixelHeight = h;
    slice.rowSignatures = signatures;
    return slice;
}

#pragma mark - 拼接

+ (nullable UIImage *)composedImageWithSlices:(NSArray<PXLongShotSlice *> *)slices
                                  screenScale:(CGFloat)screenScale
                                    outputURL:(NSURL *)outputURL
                                progressBlock:(nullable void (^)(NSInteger done, NSInteger total))progressBlock
                                 outPixelSize:(CGSize *)outPixelSize
                                        error:(NSError **)error {
    if (slices.count == 0) {
        if (error) *error = PXLongShotError(@"没有可拼接的分片");
        return nil;
    }

    NSInteger sliceCount = (NSInteger)slices.count;
    // 进度口径 2n：前 n 步是对齐搜索（签名比对的耗时大头），后 n 步是逐片解码绘制。
    if (progressBlock) progressBlock(0, sliceCount * 2);

    // 逐片计算重叠并累计总高：offset 相对首片顶部（顶部原点像素）。
    NSInteger totalHeight = 0;
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray arrayWithCapacity:slices.count];
    for (NSInteger i = 0; i < sliceCount; i++) {
        PXLongShotSlice *slice = slices[i];
        NSInteger offset = totalHeight;
        if (i > 0) {
            PXLongShotSlice *prev = slices[i - 1];
            NSInteger overlap = PXLongShotSearchOverlap(
                prev.rowSignatures.bytes, prev.pixelHeight,
                slice.rowSignatures.bytes, slice.pixelHeight,
                MIN(slice.pixelHeight, 128));
            offset = totalHeight - overlap;
        }
        [offsets addObject:@(offset)];
        totalHeight = offset + slice.pixelHeight;
        if (progressBlock) progressBlock(i + 1, sliceCount * 2);
    }

    CGFloat scale = totalHeight > PXLongShotMaxCanvasHeight
        ? (CGFloat)PXLongShotMaxCanvasHeight / (CGFloat)totalHeight
        : 1.0;
    // 像素总量二次缩放：高度封顶后宽幅设备仍可能超预算（如 iPad 全宽 × 16384）。
    CGFloat scaledW = (CGFloat)slices[0].pixelWidth * scale;
    CGFloat scaledH = (CGFloat)totalHeight * scale;
    if (scaledW * scaledH > (CGFloat)PXLongShotMaxCanvasPixels) {
        scale *= sqrt((CGFloat)PXLongShotMaxCanvasPixels / (scaledW * scaledH));
    }
    NSInteger canvasW = MAX((NSInteger)(slices[0].pixelWidth * scale + 0.5), 1);
    NSInteger canvasH = MAX((NSInteger)(totalHeight * scale + 0.5), 1);
    if (canvasW <= 0 || canvasH <= 0 || (uint64_t)canvasW * (uint64_t)canvasH > (uint64_t)PXLongShotMaxCanvasPixels) {
        if (error) *error = PXLongShotError(@"拼接画布尺寸异常");
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef canvas = CGBitmapContextCreate(NULL, (NSUInteger)canvasW, (NSUInteger)canvasH, 8, 0,
                                                colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (!canvas) {
        if (error) *error = PXLongShotError(@"拼接画布创建失败");
        return nil;
    }
    CGContextSetFillColorWithColor(canvas, [UIColor blackColor].CGColor);
    CGContextFillRect(canvas, CGRectMake(0, 0, canvasW, canvasH));
    CGContextSetInterpolationQuality(canvas, kCGInterpolationMedium);

    BOOL drewAll = YES;
    for (NSInteger i = 0; i < (NSInteger)slices.count; i++) {
        @autoreleasepool {
            PXLongShotSlice *slice = slices[i];
            CGImageSourceRef source = CGImageSourceCreateWithURL(
                (__bridge CFURLRef)[NSURL fileURLWithPath:slice.filePath], NULL);
            if (!source) { drewAll = NO; continue; }
            CGImageRef tile = CGImageSourceCreateImageAtIndex(
                source, 0,
                (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache: @NO});
            CFRelease(source);
            if (!tile) { drewAll = NO; continue; }

            NSInteger offset = offsets[i].integerValue;
            CGFloat destW = slice.pixelWidth * scale;
            CGFloat destH = slice.pixelHeight * scale;
            // 顶部原点 → CG 底部原点：y = canvasH - (offset + sliceH) * scale。
            CGFloat destY = (CGFloat)canvasH - ((CGFloat)offset + destH);
            CGContextDrawImage(canvas, CGRectMake(0, destY, destW, destH), tile);
            CGImageRelease(tile);
        }
        if (progressBlock) progressBlock(sliceCount + i + 1, sliceCount * 2);
    }

    if (progressBlock) progressBlock(sliceCount * 2, sliceCount * 2);   // 进入编码阶段

    CGImageRef composed = CGBitmapContextCreateImage(canvas);
    CGContextRelease(canvas);
    if (!composed || !drewAll) {
        if (composed) CGImageRelease(composed);
        if (error) *error = PXLongShotError(@"分片绘制失败");
        return nil;
    }

    BOOL written = PXLongShotWriteJPEG(composed, outputURL, PXLongShotOutputJPEGQuality);
    if (outPixelSize) *outPixelSize = CGSizeMake(canvasW, canvasH);
    CGImageRelease(composed);
    if (!written) {
        if (error) *error = PXLongShotError(@"长图编码失败");
        return nil;
    }

    // 文件回读：resultImage 以磁盘为后端，拼接画布立即释放不驻留。
    CGImageSourceRef outSource = CGImageSourceCreateWithURL((__bridge CFURLRef)outputURL, NULL);
    CGImageRef outImage = outSource
        ? CGImageSourceCreateImageAtIndex(outSource, 0,
                                          (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache: @NO})
        : NULL;
    if (outSource) CFRelease(outSource);
    if (!outImage) {
        if (error) *error = PXLongShotError(@"长图回读失败");
        return nil;
    }
    UIImage *result = [UIImage imageWithCGImage:outImage scale:screenScale orientation:UIImageOrientationUp];
    CGImageRelease(outImage);
    if (!result) {
        if (error) *error = PXLongShotError(@"长图回读失败");
    }
    return result;
}

@end
