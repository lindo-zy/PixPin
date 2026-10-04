#import "PXLongPreviewCanvas.h"
#import "../Common/PXLongShotAligner.h"
#import <ImageIO/ImageIO.h>

/// 分辨率下限：预览宽低于该像素数后判饱和（再缩就看不清了）。
static const NSInteger PXLongPreviewMinWidthPixels = 40;

@interface PXLongPreviewCanvas () {
    CGContextRef _context;
}
@property (nonatomic, assign) NSInteger canvasWidth;       // 当前画布像素宽
@property (nonatomic, assign) NSInteger canvasHeightAlloc; // 画布分配高（px）= maxPixels / canvasWidth
@property (nonatomic, assign) CGFloat drawScale;           // 画布像素 / 原始像素（= canvasWidth / 分片宽）
@property (nonatomic, assign) NSInteger maxPixels;
@property (nonatomic, assign) CGFloat uiScale;
// 已收分片回放清单：path/w/h/offset（offset 为顶部原点累计像素，追加时即定，重建直接重放）。
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;
@property (nonatomic, assign) NSInteger totalHeight;
@end

@implementation PXLongPreviewCanvas

- (instancetype)initWithWidthPixels:(NSInteger)widthPixels maxPixels:(NSInteger)maxPixels uiScale:(CGFloat)uiScale {
    if (self = [super init]) {
        _canvasWidth = MAX(widthPixels, PXLongPreviewMinWidthPixels);
        _maxPixels = MAX(maxPixels, (NSInteger)_canvasWidth * 256);
        _canvasHeightAlloc = MAX(_maxPixels / _canvasWidth, 256);
        _drawScale = 1.0;   // 首片追加时按分片宽校正
        _uiScale = uiScale > 0 ? uiScale : 1.0;
        _items = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    if (_context) CGContextRelease(_context);
}

- (BOOL)saturated {
    return _context == NULL;
}

// MARK: - 画布维护

- (BOOL)pxCreateContextWithWidth:(NSInteger)width heightAlloc:(NSInteger)heightAlloc {
    if (_context) CGContextRelease(_context);
    self.canvasWidth = width;
    self.canvasHeightAlloc = heightAlloc;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    _context = CGBitmapContextCreate(NULL, (NSUInteger)width, (NSUInteger)heightAlloc, 8, 0,
                                         colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (!_context) return NO;
    CGContextSetFillColorWithColor(_context, [UIColor blackColor].CGColor);
    CGContextFillRect(_context, CGRectMake(0, 0, width, heightAlloc));
    CGContextSetInterpolationQuality(_context, kCGInterpolationLow);
    return YES;
}

- (BOOL)pxDrawSliceFile:(NSString *)path
              pixelWidth:(NSInteger)w
             pixelHeight:(NSInteger)h
                 offset:(NSInteger)offset {
    if (!_context) return NO;
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!source) return NO;
    CGImageRef tile = CGImageSourceCreateImageAtIndex(
        source, 0, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache: @NO});
    CFRelease(source);
    if (!tile) return NO;
    CGFloat p = self.drawScale;
    // 顶部原点累计坐标 → CG 底部原点画布：分配高固定，旧片位置不随追加移动。
    CGFloat destY = (CGFloat)self.canvasHeightAlloc - ((CGFloat)offset + h * p);
    CGContextDrawImage(_context, CGRectMake(0, destY, w * p, h * p), tile);
    CGImageRelease(tile);
    return YES;
}

/// 像素预算超限：缩画布宽并全量重放（低频；重放后预算内位置重新固定）。
- (BOOL)pxRescaleForTotalHeight:(NSInteger)totalHeight firstSliceWidth:(NSInteger)sliceWidth {
    CGFloat newWidth = floor(sqrt((CGFloat)self.maxPixels * (CGFloat)sliceWidth / (CGFloat)totalHeight));
    if (newWidth < (CGFloat)PXLongPreviewMinWidthPixels) return NO;   // 判饱和
    NSInteger width = (NSInteger)newWidth;
    CGFloat scale = (CGFloat)width / (CGFloat)sliceWidth;
    NSInteger heightAlloc = MAX(self.maxPixels / width, 256);
    if (![self pxCreateContextWithWidth:width heightAlloc:heightAlloc]) return NO;
    self.drawScale = scale;
    for (NSDictionary *item in self.items) {
        [self pxDrawSliceFile:item[@"path"]
                   pixelWidth:[item[@"w"] integerValue]
                  pixelHeight:[item[@"h"] integerValue]
                       offset:[item[@"offset"] integerValue]];
    }
    return YES;
}

// MARK: - API

- (nullable UIImage *)appendSliceFile:(NSString *)filePath
                            pixelWidth:(NSInteger)pixelWidth
                           pixelHeight:(NSInteger)pixelHeight
                            overlapRows:(NSInteger)overlapRows {
    if (self.saturated || pixelWidth < 1 || pixelHeight < 1) return nil;

    NSInteger offset = self.totalHeight - MAX(overlapRows, 0);
    NSInteger totalNew = offset + pixelHeight;
    NSDictionary *item = @{@"path": filePath, @"w": @(pixelWidth),
                           @"h": @(pixelHeight), @"offset": @(offset)};

    if (!_context) {
        // 首片：画布宽取目标预览宽，分配高由像素预算反推。
        self.drawScale = (CGFloat)self.canvasWidth / (CGFloat)pixelWidth;
        if (![self pxCreateContextWithWidth:self.canvasWidth heightAlloc:self.canvasHeightAlloc]) {
            return nil;
        }
    } else if ((CGFloat)totalNew * self.drawScale > (CGFloat)self.canvasHeightAlloc) {
        // 预算超限：整幅缩放重放；缩无可缩即判饱和（正式拼接不受影响）。
        [self.items addObject:item];
        self.totalHeight = totalNew;
        if (![self pxRescaleForTotalHeight:totalNew firstSliceWidth:pixelWidth]) {
            CGContextRelease(_context);
            _context = NULL;   // 置饱和，放弃预览
            [self.items removeAllObjects];
            return nil;
        }
        return [self pxSnapshotImage];
    }

    if (![self pxDrawSliceFile:filePath pixelWidth:pixelWidth pixelHeight:pixelHeight offset:offset]) {
        return nil;
    }
    [self.items addObject:item];
    self.totalHeight = totalNew;
    return [self pxSnapshotImage];
}

- (NSInteger)usedPixelHeight {
    return (NSInteger)ceil((CGFloat)self.totalHeight * self.drawScale);
}

// MARK: - 快照

- (nullable UIImage *)pxSnapshotImage {
    if (!_context) return nil;
    CGImageRef image = CGBitmapContextCreateImage(_context);
    if (!image) return nil;
    UIImage *result = [UIImage imageWithCGImage:image scale:self.uiScale orientation:UIImageOrientationUp];
    CGImageRelease(image);
    return result;
}

@end
