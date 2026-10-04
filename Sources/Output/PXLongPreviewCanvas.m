#import "PXLongPreviewCanvas.h"
#import "../Common/PXLongShotAligner.h"
#import <ImageIO/ImageIO.h>

/// 分辨率下限：预览宽低于该像素数后判饱和（再缩就看不清了）。
static const NSInteger PXLongPreviewMinWidthPixels = 40;

@interface PXLongPreviewCanvas () {
    CGContextRef _context;
    // 放弃标志：与 _context==NULL 语义分离——首片到达前 _context 本就是 NULL，
    // 不能把“未开始”当成“已饱和”，否则 appendSliceFile 顶部闸门会吞掉第一片。
    BOOL _gaveUp;
}
@property (nonatomic, assign) NSInteger canvasWidth;       // 当前画布像素宽
@property (nonatomic, assign) NSInteger canvasHeightAlloc; // 画布分配高（px）= maxPixels / canvasWidth
@property (nonatomic, assign) CGFloat drawScale;           // 画布像素 / 原始像素（= canvasWidth / 分片宽）
@property (nonatomic, assign) NSInteger maxPixels;
@property (nonatomic, assign) CGFloat uiScale;
// 已收分片回放清单：path/w/h/offset（offset 为顶部原点累计像素，追加时即定，重建直接重放）。
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;
@property (nonatomic, assign) NSInteger totalHeight;
@property (nonatomic, strong) PXLongShotCancellation *cancellation;
@end

@implementation PXLongPreviewCanvas

- (instancetype)initWithWidthPixels:(NSInteger)widthPixels maxPixels:(NSInteger)maxPixels uiScale:(CGFloat)uiScale
                       cancellation:(PXLongShotCancellation *)cancellation {
    if (self = [super init]) {
        _canvasWidth = MAX(widthPixels, PXLongPreviewMinWidthPixels);
        _maxPixels = MAX(maxPixels, (NSInteger)_canvasWidth * 256);
        _canvasHeightAlloc = MAX(_maxPixels / _canvasWidth, 256);
        _drawScale = 1.0;   // 首片追加时按分片宽校正
        _uiScale = uiScale > 0 ? uiScale : 1.0;
        _items = [[NSMutableArray alloc] init];
        _cancellation = cancellation;
    }
    return self;
}

- (void)dealloc {
    if (_context) CGContextRelease(_context);
}

- (BOOL)saturated {
    return _gaveUp;
}

// MARK: - 画布维护

- (BOOL)pxCreateContextWithWidth:(NSInteger)width heightAlloc:(NSInteger)heightAlloc {
    if (self.cancellation.cancelled) return NO;
    if (_context) CGContextRelease(_context);
    self.canvasWidth = width;
    self.canvasHeightAlloc = heightAlloc;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    _context = CGBitmapContextCreate(NULL, (NSUInteger)width, (NSUInteger)heightAlloc, 8, 0,
                                         colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (!_context || self.cancellation.cancelled) return NO;
    CGContextSetFillColorWithColor(_context, [UIColor blackColor].CGColor);
    CGContextFillRect(_context, CGRectMake(0, 0, width, heightAlloc));
    CGContextSetInterpolationQuality(_context, kCGInterpolationLow);
    return YES;
}

- (BOOL)pxDrawSliceFile:(NSString *)path
              pixelWidth:(NSInteger)w
             pixelHeight:(NSInteger)h
                 offset:(NSInteger)offset {
    if (!_context || self.cancellation.cancelled) return NO;
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!source) return NO;
    // 直接解码到预览所需尺寸；禁止先解码整片再缩绘，自动循环会放大内存与 CPU 峰值。
    NSInteger maxDimension = MAX(1, (NSInteger)ceil(MAX(w, h) * self.drawScale));
    CGImageRef tile = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maxDimension),
        (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES});
    CFRelease(source);
    if (!tile) return NO;
    CGContextDrawImage(_context, PXLongShotTileRect(self.canvasHeightAlloc, offset, w, h, self.drawScale), tile);
    CGImageRelease(tile);
    return YES;
}

/// 像素预算超限：缩画布宽并全量重放。
/// 目标宽按半量预算反推（几何退避）：缩放后有效高只占分配高一半，下次触发要等
/// 内容再翻倍——重放次数从线性降到对数级，避免长会话后期每截一段就整幅重放。
- (BOOL)pxRescaleForTotalHeight:(NSInteger)totalHeight firstSliceWidth:(NSInteger)sliceWidth {
    CGFloat newWidth = floor(sqrt(0.5 * (CGFloat)self.maxPixels * (CGFloat)sliceWidth / (CGFloat)totalHeight));
    if (newWidth < (CGFloat)PXLongPreviewMinWidthPixels) return NO;   // 缩到下限，判放弃
    NSInteger width = (NSInteger)newWidth;
    CGFloat scale = (CGFloat)width / (CGFloat)sliceWidth;
    NSInteger heightAlloc = MAX(self.maxPixels / width, 256);
    if (![self pxCreateContextWithWidth:width heightAlloc:heightAlloc]) return NO;
    self.drawScale = scale;
    // 重放即重建：任何一片绘失败都判放弃，宁可停更也不留一幅缺段预览。
    for (NSDictionary *item in self.items) {
        if (self.cancellation.cancelled) return NO;
        if (![self pxDrawSliceFile:item[@"path"]
                        pixelWidth:[item[@"w"] integerValue]
                       pixelHeight:[item[@"h"] integerValue]
                            offset:[item[@"offset"] integerValue]]) {
            return NO;
        }
    }
    return YES;
}

// MARK: - API

- (nullable UIImage *)appendSliceFile:(NSString *)filePath
                            pixelWidth:(NSInteger)pixelWidth
                           pixelHeight:(NSInteger)pixelHeight
                            overlapRows:(NSInteger)overlapRows {
    if (self.cancellation.cancelled || self.saturated || pixelWidth < 1 || pixelHeight < 1) return nil;

    NSInteger offset = self.totalHeight - MAX(overlapRows, 0);
    NSInteger totalNew = offset + pixelHeight;
    NSDictionary *item = @{@"path": filePath, @"w": @(pixelWidth),
                           @"h": @(pixelHeight), @"offset": @(offset)};

    if (!_context) {
        // 首片：画布宽取目标预览宽，分配高由像素预算反推。
        self.drawScale = (CGFloat)self.canvasWidth / (CGFloat)pixelWidth;
        if (![self pxCreateContextWithWidth:self.canvasWidth heightAlloc:self.canvasHeightAlloc]) {
            [self pxAbandon];
            return nil;
        }
    } else if ((CGFloat)totalNew * self.drawScale > (CGFloat)self.canvasHeightAlloc) {
        // 预算超限：整幅缩放重放；缩无可缩/建画布失败/重放缺段都判放弃（正式拼接不受影响）。
        [self.items addObject:item];
        self.totalHeight = totalNew;
        if (![self pxRescaleForTotalHeight:totalNew firstSliceWidth:pixelWidth]) {
            // pxCreateContextWithWidth 失败时旧上下文已在内部释放（_context 已是 NULL），判空防重复释放。
            if (_context) CGContextRelease(_context);
            _context = NULL;
            _gaveUp = YES;
            [self.items removeAllObjects];
            return nil;
        }
        return [self pxSnapshotOrAbandon];
    }

    if (![self pxDrawSliceFile:filePath pixelWidth:pixelWidth pixelHeight:pixelHeight offset:offset]) {
        [self pxAbandon];
        return nil;
    }
    [self.items addObject:item];
    self.totalHeight = totalNew;
    return [self pxSnapshotOrAbandon];
}

- (void)pxAbandon {
    if (_context) CGContextRelease(_context);
    _context = NULL;
    _gaveUp = YES;
    [self.items removeAllObjects];
}

- (UIImage *)pxSnapshotOrAbandon {
    UIImage *image = [self pxSnapshotImage];
    if (!image) [self pxAbandon];
    return image;
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
