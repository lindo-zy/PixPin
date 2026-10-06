#import "../../Sources/Capture/PXLongShotFrameStore.h"
#import "../../Sources/Common/PXConstants.h"
#import <ImageIO/ImageIO.h>

static UIImage *PXStoreTestFrameWithShadow(NSInteger offset, BOOL blank, BOOL shadow) {
    const NSInteger width = 384, height = 720;
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, color,
                                                   (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(color);
    uint8_t *pixels = CGBitmapContextGetData(context);
    for (NSInteger y = 0; y < height; y++) for (NSInteger x = 0; x < width; x++) {
        uint32_t hash = (uint32_t)((y < 72 || y >= 648) ? y : y + offset) * 131u + (uint32_t)x;
        hash ^= hash >> 16; hash *= 0x7feb352d; hash ^= hash >> 15; hash *= 0x846ca68b; hash ^= hash >> 16;
        uint8_t *p = pixels + (y * width + x) * 4;
        p[0] = p[1] = p[2] = blank ? 255 : (uint8_t)hash; p[3] = 255;
        if (shadow && x < 40 && y >= 72 && y < 648)
            p[0] = p[1] = p[2] = y >= 636 ? 90 : 243;
    }
    CGImageRef image = CGBitmapContextCreateImage(context); CGContextRelease(context);
    UIImage *result = [UIImage imageWithCGImage:image scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(image); return result;
}
static UIImage *PXStoreTestFrame(NSInteger offset, BOOL blank) {
    return PXStoreTestFrameWithShadow(offset, blank, NO);
}
NSInteger PXRunLongShotFrameStoreTests(NSInteger *checkCount) {
    NSInteger checks = 0, failures = 0;
#define FS_CHECK(condition, name) do { checks++; if (!(condition)) { failures++; \
    printf("  FAIL: %s (line %d)\n", name, __LINE__); } else printf("  ok: %s\n", name); } while (0)
    printf("[bounded frame store, fixed bars, discard and recovery]\n");
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    PXLongShotOptions *options = [[PXLongShotOptions alloc] initWithValues:@{}];
    PXLongShotCancellation *cancel = [PXLongShotCancellation new];
    PXLongShotFrameStore *store = [[PXLongShotFrameStore alloc] initWithDirectory:dir options:options cancellation:cancel scale:1];
    CGRect rect = CGRectMake(0, 0, 384, 720);
    PXLongShotFrameResult *first = [store consumeImage:PXStoreTestFrame(0, NO) pixelRect:rect error:nil];
    FS_CHECK(first.count == 1 && first.totalHeight == 720 && first.preview, "first frame persists and previews");
    for (NSInteger i = 0; i < 6; i++) @autoreleasepool {
        PXLongShotFrameResult *same = [store consumeImage:PXStoreTestFrame(0, NO) pixelRect:rect error:nil];
        FS_CHECK(same.match.kind == PXLongShotMatchDuplicate && same.count == 1 && !same.preview,
                 "stationary candidate neither appends nor redraws preview");
    }
    FS_CHECK([NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil].count == 1,
             "duplicate samples do not encode temporary JPEG files");
    for (NSInteger i = 1; i <= 23; i++) @autoreleasepool {
        PXLongShotFrameResult *result = [store consumeImage:PXStoreTestFrame(i * 120, NO) pixelRect:rect error:nil];
        FS_CHECK(result.count == i + 1 && result.match.kind == PXLongShotMatchForward && result.match.shiftRows == 120 &&
                 result.totalHeight == 720 + i * 120,
                 "twenty-four frames preserve fixed header and footer exactly once");
    }
    PXLongShotFrameResult *back = [store consumeImage:PXStoreTestFrame(22 * 120, NO) pixelRect:rect error:nil];
    FS_CHECK(back.count == 24 && back.match.kind == PXLongShotMatchReverse, "reverse frame cannot shorten or duplicate the result");
    PXLongShotFrameResult *blank = [store consumeImage:PXStoreTestFrame(0, YES) pixelRect:rect error:nil];
    FS_CHECK(blank.count == 24 && blank.match.kind == PXLongShotMatchUncertain, "unrelated blank frame leaves anchor intact");
    [store discardPreview];
    PXLongShotFrameResult *recovered = [store consumeImage:PXStoreTestFrame(24 * 120, NO) pixelRect:rect error:nil];
    FS_CHECK(recovered.count == 25 && !recovered.preview && recovered.totalHeight == 3600,
             "capture recovers from rejected candidates with preview released");
    NSError *geometryError;
    FS_CHECK(![store consumeImage:PXStoreTestFrame(25 * 120, NO) pixelRect:CGRectMake(0,0,300,720) error:&geometryError] && geometryError,
             "changed frame geometry cannot mutate the store");
    CGSize size;
    UIImage *output = [store exportToURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"output.jpg"]]
                              pixelSize:&size progress:nil error:nil];
    FS_CHECK(output && size.width == 384 && size.height == 3600, "disk slices export all twenty-five segments without duplicated fixed bars");
    cancel.cancelled = YES;
    FS_CHECK(![store consumeImage:PXStoreTestFrame(25 * 120, NO) pixelRect:rect error:nil], "cancelled store refuses new frames");
    [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
    NSString *cropDir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:cropDir withIntermediateDirectories:YES attributes:nil error:nil];
    PXLongShotFrameStore *cropStore = [[PXLongShotFrameStore alloc] initWithDirectory:cropDir options:options
                                                        cancellation:[PXLongShotCancellation new] scale:1];
    CGRect cropRect = CGRectMake(33, 100, 210, 500);
    PXLongShotFrameResult *cropFirst = [cropStore consumeImage:PXStoreTestFrame(0, NO) pixelRect:cropRect error:nil];
    PXLongShotFrameResult *cropNext = [cropStore consumeImage:PXStoreTestFrame(120, NO) pixelRect:cropRect error:nil];
    FS_CHECK(cropFirst.count == 1 && cropNext.count == 2 && cropNext.match.shiftRows == 120 && cropNext.totalHeight == 620,
             "non-origin region signature preserves motion and exact crop height");
    [NSFileManager.defaultManager removeItemAtPath:cropDir error:nil];
    // 视口底缘的阴影不能在每次拼接处重复，只保留最后一帧真实底缘。
    NSString *shadowDir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:shadowDir withIntermediateDirectories:YES attributes:nil error:nil];
    PXLongShotFrameStore *shadowStore = [[PXLongShotFrameStore alloc] initWithDirectory:shadowDir options:options
                                                          cancellation:[PXLongShotCancellation new] scale:1];
    PXLongShotFrameResult *shadowResult = nil;
    for (NSInteger i = 0; i < 6; i++) @autoreleasepool {
        shadowResult = [shadowStore consumeImage:PXStoreTestFrameWithShadow(i * 120, NO, YES) pixelRect:rect error:nil];
    }
    FS_CHECK(shadowResult.count == 6 && shadowResult.totalHeight == 1320,
             "interior overlap seams preserve exact accumulated scroll height");
    UIImage *shadowOutput = [shadowStore exportToURL:[NSURL fileURLWithPath:[shadowDir stringByAppendingPathComponent:@"shadow.jpg"]]
                                          pixelSize:&size progress:nil error:nil];
    CGColorSpaceRef shadowColor = CGColorSpaceCreateDeviceRGB();
    CGContextRef decoded = CGBitmapContextCreate(NULL, 384, 1320, 8, 0, shadowColor, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(shadowColor);
    BOOL clean = shadowOutput && decoded;
    if (clean) {
        CGContextDrawImage(decoded, CGRectMake(0, 0, 384, 1320), shadowOutput.CGImage);
        uint8_t *pixels = CGBitmapContextGetData(decoded);
        size_t stride = CGBitmapContextGetBytesPerRow(decoded);
        for (NSInteger y = 90; y < 1220; y++)
            if (abs(pixels[y * stride + 8 * 4] - 243) > 3) clean = NO;
    }
    FS_CHECK(clean, "viewport bottom shadows never repeat inside the composed body");
    if (decoded) CGContextRelease(decoded);
    [NSFileManager.defaultManager removeItemAtPath:shadowDir error:nil];
    // 可选用户视频诊断：只从本地读取；不把私人画面复制进仓库或产物。
    NSString *reference = NSProcessInfo.processInfo.environment[@"PX_LONGSHOT_REFERENCE_FRAMES"];
    if (reference.length) {
        NSString *out = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [NSFileManager.defaultManager createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil error:nil];
        PXLongShotFrameStore *referenceStore = [[PXLongShotFrameStore alloc] initWithDirectory:out options:options
                                                            cancellation:[PXLongShotCancellation new] scale:1];
        for (NSString *file in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:reference error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
            @autoreleasepool {
                CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:[reference stringByAppendingPathComponent:file]], NULL);
                CGImageRef cg = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
                if (source) CFRelease(source);
                if (!cg) continue;
                UIImage *image = [UIImage imageWithCGImage:cg scale:1 orientation:UIImageOrientationUp]; CGImageRelease(cg);
                // 排除录屏里参考工具的右侧小窗，保留上下固定栏。
                PXLongShotFrameResult *r = [referenceStore consumeImage:image pixelRect:CGRectMake(0,0,440,1280) error:nil];
                printf("  reference %s kind=%ld count=%ld shift=%ld fixed=%ld/%ld\n", file.UTF8String,
                        (long)r.match.kind,(long)r.count,(long)r.match.shiftRows,(long)r.match.fixedTopRows,(long)r.match.fixedBottomRows);
            }
        }
        [NSFileManager.defaultManager removeItemAtPath:out error:nil];
    }
    *checkCount = checks;
    return failures;
}
