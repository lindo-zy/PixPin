#import "../../Sources/Capture/PXCaptureProvider.h"
#import "../../Sources/Capture/PXCaptureLayerExclusion.h"

@interface PXMaskTestLayer : NSObject
@property (nonatomic) unsigned disableUpdateMask;
@property (nonatomic) BOOL ignoresWrites;
@end
@implementation PXMaskTestLayer
- (void)setDisableUpdateMask:(unsigned)mask { if (!self.ignoresWrites) _disableUpdateMask = mask; }
@end
@interface PXWideMaskTestLayer : NSObject
@property (nonatomic) uint64_t disableUpdateMask;
@end
@implementation PXWideMaskTestLayer
@end
static UIImage *PXPrivateCaptureFixture;
static BOOL PXDisablePrimaryCapture;
static NSInteger PXScreenCaptureCalls, PXLegacyCaptureCalls;
static NSPointerArray *PXCaptureProbes;   // 弱引用探针：仅观察 mock 产出图像的销毁时机
// 由真实 PXCaptureProvider 的 dlsym 解析这两个宿主符号。
// _UICreateScreenUIImage 按真实接口惯例返回 +1（NS_RETURNS_RETAINED），每次独立新建：
// provider 若未按 +1 接管所有权，探针将常驻不销毁（逐帧原图泄漏回归测试）。
UIImage *_UICreateScreenUIImage(void) NS_RETURNS_RETAINED;
UIImage *_UICreateScreenUIImage(void) {
    PXScreenCaptureCalls++;
    if (PXDisablePrimaryCapture) return nil;
    UIImage *image = [[UIImage alloc] initWithCGImage:PXPrivateCaptureFixture.CGImage
                                                scale:1 orientation:UIImageOrientationUp];
    [PXCaptureProbes addPointer:(__bridge void *)image];
    return image;
}
CGImageRef UIGetScreenImage(void) {
    PXLegacyCaptureCalls++;
    return CGImageRetain(PXPrivateCaptureFixture.CGImage);
}
static BOOL PXWaitCapture(PXCaptureProvider *provider, UIWindow *window, BOOL cancelImmediately) {
    __block BOOL done = NO, success = NO;
    [provider captureExcludingWindows:@[window] completion:^(UIImage *image, BOOL partial, NSString *method, NSError *error) {
        success = image != nil && !partial && !error; done = YES;
    }];
    if (cancelImmediately) { [provider endVisibleWindowExclusion]; window.rootViewController = nil; }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return done && success;
}
NSInteger PXRunCaptureProviderTests(NSInteger *checkCount) {
    NSInteger checks = 0, failures = 0;
#define CAP_CHECK(c, name) do { checks++; if (!(c)) { failures++; printf("  FAIL: %s (line %d)\n", name, __LINE__); } else printf("  ok: %s\n", name); } while (0)
    printf("[visible capture exclusion and private fallback]\n");
    PXMaskTestLayer *layer = [PXMaskTestLayer new]; layer.disableUpdateMask = 0x40;
    PXCaptureLayerExclusion *guard = [PXCaptureLayerExclusion beginWithLayers:@[layer]];
    CAP_CHECK(guard.isActive && layer.disableUpdateMask == 0x52, "capture bits preserve existing layer flags");
    layer.disableUpdateMask |= 0x80;
    [guard invalidate]; [guard invalidate];
    CAP_CHECK(!guard.isActive && layer.disableUpdateMask == 0xc0, "idempotent cleanup preserves subsequent non-capture flags");
    layer.disableUpdateMask = 0x42;
    guard = [PXCaptureLayerExclusion beginWithLayers:@[layer]]; [guard invalidate];
    CAP_CHECK(layer.disableUpdateMask == 0x42, "preexisting capture bit survives cleanup");
    CAP_CHECK(![PXCaptureLayerExclusion beginWithLayers:@[]] &&
              ![PXCaptureLayerExclusion beginWithLayers:@[[NSObject new]]], "missing layer capability fails without exception");
    layer.disableUpdateMask = 0x40;
    CAP_CHECK((![PXCaptureLayerExclusion beginWithLayers:@[layer, [NSObject new]]] && layer.disableUpdateMask == 0x40),
              "partial setup rolls back all previously changed layers");
    layer.ignoresWrites = YES;
    CAP_CHECK(![PXCaptureLayerExclusion beginWithLayers:@[layer]], "silent setter failure cannot enable unprotected capture");
    layer.ignoresWrites = NO;
    guard = [PXCaptureLayerExclusion beginWithLayers:@[layer, layer]];
    [guard invalidate];
    CAP_CHECK(layer.disableUpdateMask == 0x40, "duplicate layer references never leave capture bits behind");
    PXWideMaskTestLayer *wide = [PXWideMaskTestLayer new];
    wide.disableUpdateMask = (1ULL << 40) | 0x40;
    guard = [PXCaptureLayerExclusion beginWithLayers:@[wide]];
    CAP_CHECK(guard.isActive && wide.disableUpdateMask == ((1ULL << 40) | 0x52), "wide ABI preserves high mask bits");
    [guard invalidate];
    CAP_CHECK(wide.disableUpdateMask == ((1ULL << 40) | 0x40), "wide mask restores without truncation");
    @autoreleasepool {
        __unused PXCaptureLayerExclusion *released = [PXCaptureLayerExclusion beginWithLayers:@[layer]];
    }
    CAP_CHECK(layer.disableUpdateMask == 0x40, "unexpected guard release restores exclusion on main thread");

    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 64, 256, 8, 0, color, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(color);
    CGContextSetRGBFillColor(context, 0.8, 0.8, 0.8, 1); CGContextFillRect(context, CGRectMake(0,0,64,256));
    CGImageRef cg = CGBitmapContextCreateImage(context); CGContextRelease(context);
    PXPrivateCaptureFixture = [UIImage imageWithCGImage:cg scale:1 orientation:UIImageOrientationUp]; CGImageRelease(cg);
    PXCaptureProbes = [NSPointerArray weakObjectsPointerArray];
    UIWindow *window = [UIWindow new]; window.layer = layer; window.rootViewController = [NSObject new];
    PXCaptureProvider *provider = [PXCaptureProvider new]; provider.keepsExcludedWindowsVisible = YES;
    provider.detachesCapturedImage = YES;
    CAP_CHECK(PXWaitCapture(provider, window, NO) && PXScreenCaptureCalls == 1 &&
              [provider.lastCaptureMethod isEqual:@"private-uicreate"],
              "first frame succeeds through real provider when excluding-windows snapshot returns nil");
    CAP_CHECK(!window.hidden && window.hiddenChanges == 0 && layer.disableUpdateMask == 0x52,
              "capture never toggles visible HUD hidden state");
    provider.fallbackOnlyCapture = YES;
    CAP_CHECK(PXWaitCapture(provider, window, NO) && PXScreenCaptureCalls == 2,
              "skip-snapshot mode still captures protected visible window");
    PXDisablePrimaryCapture = YES;
    CAP_CHECK(PXWaitCapture(provider, window, NO) && PXLegacyCaptureCalls == 1 &&
              [provider.lastCaptureMethod isEqual:@"private-uigetscreen"],
              "legacy screen capture remains available if primary private capture returns nil");
    PXDisablePrimaryCapture = NO;
    [provider endVisibleWindowExclusion];
    CAP_CHECK(layer.disableUpdateMask == 0x40, "provider teardown restores window layer flags");
    CAP_CHECK(!PXWaitCapture(provider, window, YES) && PXScreenCaptureCalls == 3 && layer.disableUpdateMask == 0x40,
              "cancel before capture commit restores flags and suppresses late screen capture");
    window.rootViewController = [NSObject new]; window.layer = [NSObject new];
    CAP_CHECK(!PXWaitCapture(provider, window, NO) && PXScreenCaptureCalls == 3 && PXLegacyCaptureCalls == 1,
              "unsupported exclusion never captures HUD into unprotected full screen");
    // 逐帧原图销毁：以上每帧从 mock 以 +1 取得的抓屏原图都必须已在帧生命周期内释放。
    BOOL probesReleased = NO;
    NSDate *probeDeadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!probesReleased && probeDeadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        probesReleased = PXCaptureProbes.allObjects.count == 0;
    }
    CAP_CHECK(probesReleased, "+1 screen image returned by private API is released within frame lifecycle");
    [provider endVisibleWindowExclusion]; PXPrivateCaptureFixture = nil;
    *checkCount = checks; return failures;
}
