#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../../Sources/Common/PXConstants.h"
#import "../../Sources/Common/PXLongShotOptions.h"
#import "../../Sources/Common/PXLongShotControl.h"
#import "../../Sources/Capture/PXLongShotTarget.h"
#import "../../Sources/Output/PXLongImageComposer.h"
#import <math.h>

@interface PXTargetTestApplication : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, strong) id frontmost;
- (id)_accessibilityFrontMostApplication;
@end
@implementation PXTargetTestApplication
- (id)_accessibilityFrontMostApplication { return self.frontmost; }
@end
@interface PXTargetTestLock : NSObject
@property (nonatomic, assign) BOOL locked;
- (BOOL)isUILocked;
@end
@implementation PXTargetTestLock
- (BOOL)isUILocked { return self.locked; }
@end

static void PXOwnedProviderRelease(void *info, const void *bytes, size_t size) {
    (*(NSInteger *)info)++;
    free((void *)bytes);
}
static UIImage *PXMovingFrame(NSInteger offset) {
    const size_t width = 128, height = 600;
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, color,
                                                   (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(color);
    if (!context) return nil;
    uint8_t *bytes = CGBitmapContextGetData(context);
    for (NSInteger r = 0; r < (NSInteger)height; r++) {
        for (NSInteger x = 0; x < (NSInteger)width; x++) {
            uint32_t hash = (uint32_t)(offset + r) * 131u + (uint32_t)x;
            hash ^= hash >> 16; hash *= 0x7feb352d; hash ^= hash >> 15; hash *= 0x846ca68b; hash ^= hash >> 16;
            uint8_t *pixel = bytes + (r * width + x) * 4;
            pixel[0] = pixel[1] = pixel[2] = (uint8_t)hash;
            pixel[3] = 255;
        }
    }
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    UIImage *result = [UIImage imageWithCGImage:image scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(image);
    return result;
}

NSInteger PXRunLongShotOptionsTests(NSInteger *checkCount) {
    NSInteger checks = 0, failures = 0;
#define LS_CHECK(condition, name) do { checks++; if (!(condition)) { failures++; \
    printf("  FAIL: %s (line %d)\n", name, __LINE__); } else printf("  ok: %s\n", name); } while (0)
    printf("[long shot options, target guards, rebound, owned pixels and multi-frame export]\n");
    PXLongShotOptions *defaults = [[PXLongShotOptions alloc] initWithValues:@{}];
    LS_CHECK(defaults.autoScroll && defaults.maxSlices == 200 && defaults.maxCanvasHeight == 16384,
             "external long mode defaults to automatic without a four-frame limit");
    LS_CHECK(defaults.sampleInterval == 0.12 && defaults.idleInterval == 0.5 && defaults.scrollDuration == 0.62 &&
             defaults.settleDuration == 0.45 && defaults.sliceQuality == 0.95 && defaults.outputQuality == 0.9,
             "sampling and encoding defaults preserve existing values");
    NSArray *bad = @[@(-1), @(NAN), @(INFINITY), @"0.5", @YES, NSNull.null];
    for (id value in bad) {
        NSMutableDictionary *values = [NSMutableDictionary dictionary];
        for (NSString *key in PXLongShotOptions.preferenceKeys) if (![key isEqual:PXKeyLongShotAutoScroll]) values[key] = value;
        PXLongShotOptions *options = [[PXLongShotOptions alloc] initWithValues:values];
        LS_CHECK(options.maxSlices == 200 && options.maxCanvasHeight == 16384 && options.scrollDuration == 0.62 &&
                 options.outputQuality == 0.9, "invalid preference types and numbers safely fall back");
    }
    NSMutableDictionary *values = [@{PXKeyLongShotAutoScroll:@NO, PXKeyLongShotMaxSlices:@50,
        PXKeyLongShotMaxCanvasHeight:@1024, PXKeyLongShotScrollDuration:@1.2,
        PXKeyLongShotSliceQuality:@0.8, PXKeyLongShotOutputQuality:@0.7} mutableCopy];
    PXLongShotOptions *options = [[PXLongShotOptions alloc] initWithValues:values];
    values[PXKeyLongShotMaxSlices] = @2;
    LS_CHECK(!options.autoScroll && options.maxSlices == 50 && options.scrollDuration == 1.2 && options.sliceQuality == 0.8,
             "valid preferences create an independent immutable manual-mode snapshot");
    PXLongShotOptions *fractional = [[PXLongShotOptions alloc] initWithValues:@{PXKeyLongShotMaxSlices:@4.5,
        PXKeyLongShotMaxCanvasHeight:@32768, PXKeyLongShotSampleInterval:@1}];
    LS_CHECK(fractional.maxSlices == 200 && fractional.maxCanvasHeight == 16384 && fractional.idleInterval >= fractional.sampleInterval,
             "fractional counts and unsafe canvas sizes are rejected and idle timing stays ordered");

    PXTargetTestApplication *host = [PXTargetTestApplication new], *app = [PXTargetTestApplication new];
    app.bundleIdentifier = @"test.scrolling.app"; host.frontmost = app;
    PXTargetTestLock *lock = [PXTargetTestLock new];
    LS_CHECK(PXLongShotTargetIsCurrent(host, lock, app.bundleIdentifier), "unlocked matching app can continue");
    lock.locked = YES;
    LS_CHECK(!PXLongShotTargetIsCurrent(host, lock, app.bundleIdentifier), "lock stops both sampling and gestures");
    lock.locked = NO;
    LS_CHECK(!PXLongShotTargetIsCurrent(host, lock, @"other.app") && !PXLongShotTargetIsCurrent(host, nil, app.bundleIdentifier),
             "changed app and missing lock capability fail closed");
    host.frontmost = [NSObject new];
    LS_CHECK(!PXLongShotFrontmostIdentifier(host) && !PXLongShotFrontmostIdentifier([NSObject new]),
             "unavailable frontmost and identifier APIs cannot masquerade as a target");

    PXLongShotReboundState state = {0};
    PXLongShotFrameMatch reverse = {PXLongShotMatchReverse, 90, 0, 0};
    PXLongShotFrameMatch forward = {PXLongShotMatchForward, 120, 0, 0};
    LS_CHECK(!PXLongShotUpdateRebound(&state, reverse, 1000, YES) && state.reverseFrames == 0,
             "reverse frames before forward progress are not a bottom signal");
    PXLongShotUpdateRebound(&state, forward, 1000, YES);
    LS_CHECK(!PXLongShotUpdateRebound(&state, reverse, 1000, YES) &&
             PXLongShotUpdateRebound(&state, reverse, 1000, YES), "two adjacent reverse frames exceeding fifteen percent finish");
    LS_CHECK(!PXLongShotUpdateRebound(&state, reverse, 1000, NO) && !state.progressed,
             "manual reverse navigation never finishes automatically");
    PXLongShotUpdateRebound(&state, forward, 1000, YES);
    reverse.shiftRows = 10;
    LS_CHECK(!PXLongShotUpdateRebound(&state, reverse, 1000, YES) &&
             !PXLongShotUpdateRebound(&state, reverse, 1000, YES), "small jitter does not count as bottom bounce");
    PXLongShotUpdateRebound(&state, (PXLongShotFrameMatch){PXLongShotMatchDuplicate,0,0,0}, 1000, YES);
    LS_CHECK(state.reverseRows == 0 && state.reverseFrames == 0, "duplicate frame breaks consecutive reverse evidence");

    PXLongShotScrollPlan forwardBand = {CGPointMake(200, 810), CGPointMake(200, 490)};
    PXLongShotScrollPlan rollback = {0};
    LS_CHECK(PXLongShotBuildCorrectiveScrollPlan(forwardBand, 1.0 / 3.0, &rollback) &&
             rollback.start.x == 200 && rollback.start.y == 492 &&
             fabs(rollback.end.y - 598.667) < 0.01,
             "corrective plan rolls back one third of the band as a downward swipe");
    LS_CHECK(rollback.start.y < rollback.end.y && rollback.end.y < forwardBand.start.y,
             "corrective swipe stays inside the original gesture band");
    LS_CHECK(!PXLongShotBuildCorrectiveScrollPlan(forwardBand, 1.0 / 3.0, NULL) &&
             !PXLongShotBuildCorrectiveScrollPlan((PXLongShotScrollPlan){CGPointMake(200, NAN), CGPointMake(200, 490)},
                                                  1.0 / 3.0, &rollback) &&
             !PXLongShotBuildCorrectiveScrollPlan((PXLongShotScrollPlan){CGPointMake(200, 400), CGPointMake(200, 490)},
                                                  1.0 / 3.0, &rollback),
             "invalid forward plans and reversed bands refuse corrective derivation");
    LS_CHECK(!PXLongShotBuildCorrectiveScrollPlan((PXLongShotScrollPlan){CGPointMake(200, 505), CGPointMake(200, 490)},
                                                  1.0 / 3.0, &rollback),
             "bands too short for a meaningful rollback are rejected");
    LS_CHECK(!PXLongShotBuildCorrectiveScrollPlan(forwardBand, NAN, &rollback) &&
             !PXLongShotBuildCorrectiveScrollPlan(forwardBand, 0.0, &rollback) &&
             !PXLongShotBuildCorrectiveScrollPlan(forwardBand, 1.0, &rollback),
             "fraction must be strictly between zero and one");

    NSInteger released = 0;
    uint8_t *pixels = malloc(16 * 16 * 4);
    memset(pixels, 255, 16 * 16 * 4);
    CGDataProviderRef provider = CGDataProviderCreateWithData(&released, pixels, 16 * 16 * 4, PXOwnedProviderRelease);
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGImageRef source = CGImageCreate(16, 16, 8, 32, 64, color, (CGBitmapInfo)kCGImageAlphaPremultipliedLast, provider, NULL, NO,
                                      kCGRenderingIntentDefault);
    CGColorSpaceRelease(color); CGDataProviderRelease(provider);
    CGImageRef owned = PXLongShotCreateOwnedBitmap(source);
    CGImageRelease(source);
    LS_CHECK(owned && released == 1 && CGImageGetWidth(owned) == 16,
             "owned screenshot bitmap releases the source provider while its pixels remain usable");
    if (owned) CGImageRelease(owned);
    LS_CHECK(!PXLongShotCreateOwnedBitmap(NULL), "missing source image cannot allocate an owned screenshot");

    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    PXLongShotCancellation *cancel = [PXLongShotCancellation new];
    NSMutableArray<PXLongShotSlice *> *slices = [NSMutableArray array];
    for (NSInteger frame = 0; frame < 24; frame++) {
        @autoreleasepool {
            PXLongShotSlice *slice = [PXLongImageComposer sliceFromScreenImage:PXMovingFrame(frame * 120)
                pixelRect:CGRectMake(0,0,128,600) filePath:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%ld.jpg",(long)frame]]
                options:options cancellation:cancel error:nil];
            LS_CHECK(slice != nil, "independent scrolling frame writes to disk beyond four captures");
            if (!slice) break;
            PXLongShotSlice *previous = slices.lastObject;
            if (previous) {
                PXLongShotFrameMatch match = PXLongShotMatchFrames(previous.rowSignatures.bytes, slice.rowSignatures.bytes, 600, 0, 0);
                LS_CHECK(match.kind == PXLongShotMatchForward && match.shiftRows == 120,
                         "each real bitmap yields the expected overlap throughout twenty-four frames");
                slice.cropTopRows = 600 - match.shiftRows;
                [previous discardAlignmentSignature];
            }
            [slices addObject:slice];
        }
    }
    CGSize size = CGSizeZero;
    UIImage *result = [PXLongImageComposer composedImageWithSlices:slices screenScale:1
        outputURL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"long.jpg"]] maxPixels:8000000
        options:options cancellation:cancel progressBlock:nil outPixelSize:&size error:nil];
    LS_CHECK(result && slices.count == 24 && size.height <= 1024 && size.height > 900,
             "twenty-four aligned disk frames export under the configured height cap without dropping the tail");
    cancel.cancelled = YES;
    LS_CHECK(![PXLongImageComposer composedImageWithSlices:slices screenScale:1
        outputURL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"cancel.jpg"]] maxPixels:8000000
        options:options cancellation:cancel progressBlock:nil outPixelSize:nil error:nil], "cancelled multi-frame export creates no result");
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
    *checkCount = checks;
#undef LS_CHECK
    return failures;
}
