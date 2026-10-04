#import "PXLongPreviewCanvas.h"
#import "PXLongImageComposer.h"
#import <ImageIO/ImageIO.h>

/// 分辨率下限：预览宽低于该像素数后判饱和（再缩就看不清了）。
static const NSInteger PXLongPreviewMinWidthPixels = 40;

@interface PXLongPreviewCanvas () {
    CGContextRef _context;
    // 放弃标志：与 _context==NULL 语义分离——首片到达前 _context 本就是 NULL，
    // 不能把“未开始”当成“已饱和”，否则更新闸门会吞掉第一片。
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
                 offset:(NSInteger)offset cropTop:(NSInteger)top cropBottom:(NSInteger)bottom {
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
    PXLongShotDrawTile(_context, tile, self.canvasHeightAlloc, offset, w, h, top, bottom, self.drawScale);
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
                            offset:[item[@"offset"] integerValue]
                           cropTop:[item[@"top"] integerValue] cropBottom:[item[@"bottom"] integerValue]]) {
            return NO;
        }
    }
    return YES;
}

// MARK: - API

- (nullable UIImage *)updateWithSlices:(NSArray<PXLongShotSlice *> *)slices {
    if (self.cancellation.cancelled || self.saturated || slices.count == 0) return nil;
    NSMutableArray *next = [NSMutableArray array];
    NSInteger total = 0;
    for (PXLongShotSlice *slice in slices) {
        if (slice.renderedPixelHeight <= 0) return nil;
        [next addObject:@{@"path": slice.filePath, @"w": @(slice.pixelWidth), @"h": @(slice.pixelHeight),
                          @"top": @(slice.cropTopRows), @"bottom": @(slice.cropBottomRows), @"offset": @(total)}];
        total += slice.renderedPixelHeight;
    }
    BOOL incremental = _context && next.count == self.items.count + 1;
    for (NSUInteger i = 0; incremental && i < self.items.count; i++) {
        NSDictionary *old = self.items[i], *item = next[i];
        if (i + 1 == self.items.count) {
            NSMutableDictionary *adjusted = [old mutableCopy];
            adjusted[@"bottom"] = item[@"bottom"]; // 旧末帧现在不再保留页脚。
            incremental = [adjusted isEqual:item];
        } else incremental = [old isEqual:item];
    }
    NSInteger width = slices.firstObject.pixelWidth;
    self.items = next;
    self.totalHeight = total;
    if (_context && total * self.drawScale > self.canvasHeightAlloc) {
        if (![self pxRescaleForTotalHeight:total firstSliceWidth:width]) { [self pxAbandon]; return nil; }
    } else if (incremental) {
        NSDictionary *item = next.lastObject;
        if (![self pxDrawSliceFile:item[@"path"] pixelWidth:width pixelHeight:[item[@"h"] integerValue]
                           offset:[item[@"offset"] integerValue]
                          cropTop:[item[@"top"] integerValue] cropBottom:[item[@"bottom"] integerValue]]) {
            [self pxAbandon]; return nil;
        }
    } else {
        self.drawScale = (CGFloat)self.canvasWidth / width;
        if (![self pxCreateContextWithWidth:self.canvasWidth heightAlloc:self.canvasHeightAlloc]) {
            [self pxAbandon]; return nil;
        }
        for (NSDictionary *item in next) {
            if (![self pxDrawSliceFile:item[@"path"] pixelWidth:width pixelHeight:[item[@"h"] integerValue]
                               offset:[item[@"offset"] integerValue]
                              cropTop:[item[@"top"] integerValue] cropBottom:[item[@"bottom"] integerValue]]) {
                [self pxAbandon]; return nil;
            }
        }
    }
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
    CGImageRef cropped = CGImageCreateWithImageInRect(image, CGRectMake(0, 0, self.canvasWidth, self.usedPixelHeight));
    CGImageRelease(image);
    if (!cropped) return nil;
    UIImage *result = [UIImage imageWithCGImage:cropped scale:self.uiScale orientation:UIImageOrientationUp];
    CGImageRelease(cropped);
    return result;
}

@end
