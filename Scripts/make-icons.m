// 图标生成工具（macOS 宿主运行，产出到 PixPinPrefs/Resources/）。
// 用法：
//   clang -framework Foundation -framework AppKit -o /tmp/make-icons Scripts/make-icons.m
//   /tmp/make-icons <output_dir>
//   /tmp/make-icons <output_dir> --header-only  # 仅生成设置首页高清 Logo
// 重新生成：60×60 与 120×120(@2x) 两个尺寸的 PixPin.png。

#import <AppKit/AppKit.h>

static NSImage *PXRenderIcon(NSInteger pixelSize) {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(pixelSize, pixelSize)];
    [image lockFocus];

    CGFloat size = (CGFloat)pixelSize;
    CGFloat margin = size * 0.055;
    CGFloat radius = size * 0.225;

    // 背景：圆角矩形 + 蓝色渐变
    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(margin, margin, size - margin * 2, size - margin * 2)
                                                           xRadius:radius yRadius:radius];
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:0.20 green:0.52 blue:0.98 alpha:1.0]
                                                         endingColor:[NSColor colorWithSRGBRed:0.05 green:0.30 blue:0.80 alpha:1.0]];
    [gradient drawInBezierPath:background angle:-90.0];
    [background addClip];

    NSColor *white = [NSColor whiteColor];

    // 取景框四角（截图符号）
    CGFloat inset = size * 0.20;
    CGFloat corner = size * 0.17;
    CGFloat lineWidth = size * 0.075;
    CGFloat min = inset;
    CGFloat max = size - inset;
    NSBezierPath *brackets = [NSBezierPath bezierPath];
    brackets.lineWidth = lineWidth;
    brackets.lineCapStyle = NSLineCapStyleRound;
    brackets.lineJoinStyle = NSLineJoinStyleRound;

    // 左上
    [brackets moveToPoint:NSMakePoint(min, min + corner)];
    [brackets lineToPoint:NSMakePoint(min, min)];
    [brackets lineToPoint:NSMakePoint(min + corner, min)];
    // 右上
    [brackets moveToPoint:NSMakePoint(max - corner, min)];
    [brackets lineToPoint:NSMakePoint(max, min)];
    [brackets lineToPoint:NSMakePoint(max, min + corner)];
    // 右下
    [brackets moveToPoint:NSMakePoint(max, max - corner)];
    [brackets lineToPoint:NSMakePoint(max, max)];
    [brackets lineToPoint:NSMakePoint(max - corner, max)];
    // 左下
    [brackets moveToPoint:NSMakePoint(min + corner, max)];
    [brackets lineToPoint:NSMakePoint(min, max)];
    [brackets lineToPoint:NSMakePoint(min, max - corner)];
    [white setStroke];
    [brackets stroke];

    // 中心快门圆 + 芯点
    CGFloat center = size / 2.0;
    CGFloat ringRadius = size * 0.115;
    NSBezierPath *ring = [NSBezierPath bezierPath];
    ring.lineWidth = size * 0.06;
    [ring appendBezierPathWithArcWithCenter:NSMakePoint(center, center)
                                     radius:ringRadius
                                 startAngle:0.0
                                 endAngle:360.0];
    [white setStroke];
    [ring stroke];

    NSBezierPath *dot = [NSBezierPath bezierPath];
    [dot appendBezierPathWithArcWithCenter:NSMakePoint(center, center)
                                    radius:size * 0.045
                                startAngle:0.0
                                endAngle:360.0];
    [white setFill];
    [dot fill];

    [image unlockFocus];
    return image;
}

static BOOL PXWritePNG(NSImage *image, NSInteger pixelSize, NSString *path) {
    // 显式位图上下文（1x）：保证输出 PNG 的像素尺寸精确等于 pixelSize，
    // 不受宿主 retina 缩放影响。
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:pixelSize
                                                                    pixelsHigh:pixelSize
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                       isPlanar:NO
                                                                 colorSpaceName:NSCalibratedRGBColorSpace
                                                                    bytesPerRow:0
                                                                   bitsPerPixel:0];
    if (!rep) return NO;
    [rep setSize:NSMakeSize(pixelSize, pixelSize)];

    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    if (!context) return NO;

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    [image drawInRect:NSMakeRect(0, 0, pixelSize, pixelSize)
              fromRect:NSZeroRect
             operation:NSCompositingOperationCopy
              fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];

    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{NSImageInterlaced: @NO}];
    return [png writeToFile:path atomically:YES];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            printf("usage: make-icons <output_dir>\n");
            return 2;
        }
        NSString *outputDir = [NSString stringWithUTF8String:argv[1]];
        if (argc > 2 && [[NSString stringWithUTF8String:argv[2]] isEqualToString:@"--header-only"]) {
            BOOL ok = PXWritePNG(PXRenderIcon(512), 512,
                [outputDir stringByAppendingPathComponent:@"PixPinHeader.png"]);
            printf("header icon written: %d -> %s\n", ok, argv[1]);
            return ok ? 0 : 1;
        }
        NSImage *icon = PXRenderIcon(240);   // 以高分渲染，缩到目标尺寸保持边缘平滑

        BOOL ok1 = PXWritePNG(icon, 60, [outputDir stringByAppendingPathComponent:@"PixPin.png"]);
        BOOL ok2 = PXWritePNG(icon, 120, [outputDir stringByAppendingPathComponent:@"PixPin@2x.png"]);
        printf("icons written: %d %d -> %s\n", ok1, ok2, argv[1]);
        return (ok1 && ok2) ? 0 : 1;
    }
}
