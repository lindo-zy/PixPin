#import "PXLongShotControl.h"
#import <math.h>

@implementation PXLongShotCancellation
@end

CGRect PXLongShotTileRect(CGFloat canvasHeight, NSInteger offset, NSInteger width,
                         NSInteger height, CGFloat scale) {
    return CGRectMake(0, canvasHeight - ((CGFloat)offset + (CGFloat)height) * scale,
                      (CGFloat)width * scale, (CGFloat)height * scale);
}

void PXLongShotDrawTile(CGContextRef context, CGImageRef image, CGFloat canvasHeight,
                       NSInteger offset, NSInteger width, NSInteger height,
                       NSInteger cropTop, NSInteger cropBottom, CGFloat scale) {
    NSInteger visible = height - cropTop - cropBottom;
    if (!context || !image || visible <= 0 || cropTop < 0 || cropBottom < 0 || scale <= 0) return;
    CGContextSaveGState(context);
    CGContextClipToRect(context, PXLongShotTileRect(canvasHeight, offset, width, visible, scale));
    CGContextDrawImage(context, PXLongShotTileRect(canvasHeight, offset - cropTop, width, height, scale), image);
    CGContextRestoreGState(context);
}
