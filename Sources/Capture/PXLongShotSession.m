#import "PXLongShotSession.h"
#import "PXCaptureTask.h"
#import "PXCaptureProvider.h"
#import "../Common/PXLog.h"
#import "../Common/PXLongShotAligner.h"
#import "../Output/PXLongImageComposer.h"
#import "../Overlay/PXCaptureWindow.h"
#import "../Overlay/PXLongShotHUD.h"

@interface PXLongShotSession () <PXLongShotHUDDelegate>
@property (nonatomic, strong) PXCaptureTask *task;
@property (nonatomic, weak) id<PXLongShotSessionDelegate> delegate;
@property (nonatomic, strong) PXCaptureProvider *provider;
@property (nonatomic, strong) PXCaptureWindow *window;
@property (nonatomic, strong) PXLongShotHUD *hud;
@property (nonatomic, assign) CGRect displayRect;
@property (nonatomic, strong) NSMutableArray<PXLongShotSlice *> *slices;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL finished;
- (void)handleLockStateChanged;
@end

// 抓屏前等待帧数：与协调器 pxRunCaptureForTask 的两帧等待同一口径。
static const CGFloat PXLongShotFramesToWaitBeforeCapture = 2.0;

// 会话期锁屏监听：锁屏后选区几何与画面不再可信，统一按用户取消收尾。
// 静态引用即“当前活跃会话”单槽；移除观察者与置空都只在主线程收尾路径发生。
static PXLongShotSession *_PXLongShotLockObserverSession = nil;
static CFStringRef PXLongShotLockStateName = CFSTR("com.apple.springboard.lockstate");

static void PXLongShotLockStateCallback(CFNotificationCenterRef center,
                                        void *observer,
                                        CFStringRef name,
                                        const void *object,
                                        CFDictionaryRef userInfo) {
    // Darwin 回调线程不确定；只转发到活跃会话，逻辑收口在主线程。
    dispatch_async(dispatch_get_main_queue(), ^{
        [_PXLongShotLockObserverSession handleLockStateChanged];
    });
}

@implementation PXLongShotSession

+ (instancetype)startWithTask:(PXCaptureTask *)task
                  displayRect:(CGRect)displayRect
                     delegate:(id<PXLongShotSessionDelegate>)delegate {
    NSParameterAssert([NSThread isMainThread]);
    PXLongShotSession *session = [[PXLongShotSession alloc] initWithTask:task
                                                             displayRect:displayRect
                                                                delegate:delegate];
    [session pxShowWindow];
    return session;
}

- (instancetype)initWithTask:(PXCaptureTask *)task
                 displayRect:(CGRect)displayRect
                    delegate:(id<PXLongShotSessionDelegate>)delegate {
    if (self = [super init]) {
        _task = task;
        _displayRect = displayRect;
        _delegate = delegate;
        _provider = [[PXCaptureProvider alloc] init];
        _slices = [[NSMutableArray alloc] init];
    }
    return self;
}

- (BOOL)isFinished {
    return _finished;
}

- (void)pxShowWindow {
    PXCaptureWindow *window = [PXCaptureWindow pxCaptureWindow];
    window.passesTouchesOutsideHostedContent = YES;
    PXLongShotHUD *hud = [[PXLongShotHUD alloc] initWithFrame:window.bounds];
    hud.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    hud.delegate = self;
    [window hostContentView:hud];
    self.window = window;
    self.hud = hud;
    [window showAnimated:NO becomeKey:NO];
    _PXLongShotLockObserverSession = self;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    PXLongShotLockStateCallback,
                                    PXLongShotLockStateName,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    PXLogInfo(@"long shot session started (task %@, rect %@)",
              self.task.taskID, NSStringFromCGRect(self.displayRect));
}

#pragma mark - HUD 回调

- (void)longShotHUDDidTapCapture:(UIView *)hud {
    [self pxStartCapture];
}

- (void)longShotHUDDidTapFinish:(UIView *)hud {
    [self pxStartStitch];
}

- (void)longShotHUDDidTapCancel:(UIView *)hud {
    PXLogInfo(@"long shot cancelled by user (task %@)", self.task.taskID);
    id<PXLongShotSessionDelegate> delegate = self.delegate;
    [self pxTeardown];
    [delegate longShotSessionDidCancel:self];
}

- (void)handleLockStateChanged {
    if (self.finished) return;
    PXLogInfo(@"long shot cancelled by lock (task %@)", self.task.taskID);
    id<PXLongShotSessionDelegate> delegate = self.delegate;
    [self pxTeardown];
    [delegate longShotSessionDidCancel:self];
}

#pragma mark - 截取

- (void)pxStartCapture {
    if (self.busy || self.finished) return;
    if (![self pxIsTaskPresenting]) return;
    if (self.slices.count >= PXLongShotMaxSlices) {
        self.hud.statusText = @"已达最大段数，点「完成」拼接";
        return;
    }

    self.busy = YES;
    [self.hud setBusy:YES statusText:@"截取中…"];
    // 抓屏前隐藏会话窗口并等两帧，保证合成器画面不含 PixPin 控件（与协调器同口径）。
    self.window.hidden = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PXLongShotFramesToWaitBeforeCapture / 60.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (![self pxIsTaskPresenting]) return;
        [self.provider captureWithCompletion:^(UIImage *image, BOOL isPartial, NSString *captureMethod, NSError *error) {
            if (![self pxIsTaskPresenting]) return;
            // 抓屏已返回，立即恢复控件再进入后台处理，减少控件不可见时间。
            self.window.hidden = NO;
            if (!image) {
                self.busy = NO;
                [self.hud setBusy:NO statusText:@"抓屏失败，请重试"];
                PXLogWarn(@"long shot grab failed: %@ (task %@)",
                          error.localizedDescription ?: @"empty", self.task.taskID);
                return;
            }
            [self pxProcessGrabbedImage:image];
        }];
    });
}

- (void)pxProcessGrabbedImage:(UIImage *)image {
    CGSize pixelSize = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
    // 只使用抓屏时刻的几何快照换算，不使用实时 bounds（DEVELOPMENT.md 4.1 口径）。
    CGRect pixelRect = PXConvertDisplayRectToPixel(self.displayRect,
                                                   self.task.capturedScreenBounds.size,
                                                   pixelSize);
    if (CGRectIsEmpty(pixelRect)) {
        self.busy = NO;
        [self.hud setBusy:NO statusText:@"截取区域无效，请重新选择"];
        return;
    }
    NSString *directory = [self.task ensureTemporaryDirectory];
    NSString *filePath = [directory stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"longslice_%03ld.jpg", (long)self.slices.count]];
    PXCaptureTask *task = self.task;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSError *error = nil;
            PXLongShotSlice *slice = [PXLongImageComposer sliceFromScreenImage:image
                                                                     pixelRect:pixelRect
                                                                      filePath:filePath
                                                                         error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![self pxIsTaskPresenting]) return;
                self.busy = NO;
                if (!slice) {
                    [self.hud setBusy:NO statusText:@"截取失败，请重试"];
                    PXLogWarn(@"long shot slice failed: %@ (task %@)",
                              error.localizedDescription ?: @"nil", task.taskID);
                    return;
                }
                [self pxAppendSlice:slice];
            });
        }
    });
}

- (void)pxAppendSlice:(PXLongShotSlice *)slice {
    if (self.slices.count > 0) {
        PXLongShotSlice *prev = self.slices.lastObject;
        NSInteger overlap = PXLongShotSearchOverlap(prev.rowSignatures.bytes, prev.pixelHeight,
                                                    slice.rowSignatures.bytes, slice.pixelHeight,
                                                    MIN(slice.pixelHeight, 128));
        if (PXLongShotIsDuplicateOverlap(overlap, slice.pixelHeight)) {
            [NSFileManager.defaultManager removeItemAtPath:slice.filePath error:nil];
            [self.hud setBusy:NO statusText:@"未检测到新内容，请继续滚动后再截取"];
            return;
        }
    }
    [self.slices addObject:slice];
    [self.hud setSliceCount:(NSInteger)self.slices.count];
    NSString *status = self.slices.count >= PXLongShotMaxSlices
        ? @"已达最大段数，点「完成」拼接"
        : @"继续滚动，或点「完成」拼接";
    [self.hud setBusy:NO statusText:status];
    PXLogInfo(@"long shot slice appended (task %@, count %lu, %ldx%ld)",
              self.task.taskID, (unsigned long)self.slices.count,
              (long)slice.pixelWidth, (long)slice.pixelHeight);
}

#pragma mark - 拼接

- (void)pxStartStitch {
    if (self.busy || self.finished) return;
    if (self.slices.count == 0) return;
    if (![self pxIsTaskPresenting]) return;

    self.busy = YES;
    [self.hud setBusy:YES
            statusText:[NSString stringWithFormat:@"拼接中…（%lu 段）", (unsigned long)self.slices.count]];
    NSString *directory = [self.task ensureTemporaryDirectory];
    NSURL *outputURL = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"longshot.jpg"]];
    NSArray<PXLongShotSlice *> *slices = [self.slices copy];
    CGFloat screenScale = self.task.capturedScreenScale;
    PXCaptureTask *task = self.task;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            CGSize pixelSize = CGSizeZero;
            NSError *error = nil;
            UIImage *image = [PXLongImageComposer composedImageWithSlices:slices
                                                              screenScale:screenScale
                                                                outputURL:outputURL
                                                             outPixelSize:&pixelSize
                                                                    error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![self pxIsTaskPresenting]) return;
                self.busy = NO;
                if (!image) {
                    PXLogError(@"long shot stitch failed: %@ (task %@)",
                               error.localizedDescription ?: @"nil", task.taskID);
                    id<PXLongShotSessionDelegate> delegate = self.delegate;
                    [self pxTeardown];
                    [delegate longShotSessionDidFail:self message:(error.localizedDescription ?: @"长图拼接失败")];
                    return;
                }
                PXLogInfo(@"long shot stitched (task %@, %.0fx%.0f px)",
                          task.taskID, pixelSize.width, pixelSize.height);
                id<PXLongShotSessionDelegate> delegate = self.delegate;
                [self pxTeardown];
                [delegate longShotSessionDidFinish:self resultImage:image];
            });
        }
    });
}

#pragma mark - 收尾

- (void)teardownForExternalCancel {
    if ([NSThread isMainThread]) {
        [self pxTeardown];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self pxTeardown];
        });
    }
}

- (void)pxTeardown {
    if (self.finished) return;
    self.finished = YES;
    _PXLongShotLockObserverSession = nil;
    // 只摘自己注册的锁屏观察（observer=NULL + 具名）；不能清空整个中心，
    // 协调器/入口的 Darwin 观察者同样以 NULL 注册。
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       NULL, PXLongShotLockStateName, NULL);
    self.hud.delegate = nil;
    self.hud = nil;
    [self.window hideAndDestroyWithCompletion:nil];
    self.window = nil;
    // 分片文件随任务临时目录统一回收（成功/失败/取消路径都已挂 removeTaskDirectory）。
    self.slices = nil;
    self.task = nil;
    self.delegate = nil;
    PXLogInfo(@"long shot session finished");
}

/// 异步回调统一闸门：任务已取消/转出 Presenting 时丢弃。
- (BOOL)pxIsTaskPresenting {
    return !self.finished && self.task != nil && self.task.currentState == PXCaptureStatePresenting;
}

@end
