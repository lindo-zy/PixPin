#import "PXLongShotSession.h"
#import "PXCaptureTask.h"
#import "PXCaptureProvider.h"
#import "PXLongShotScroller.h"
#import "../Common/PXLog.h"
#import "../Common/PXLongShotAligner.h"
#import "../Common/PXLongShotControl.h"
#import "../Output/PXLongImageComposer.h"
#import "../Output/PXLongPreviewCanvas.h"
#import "../Output/PXTemporaryFileStore.h"
#import "../Overlay/PXCaptureWindow.h"
#import "../Overlay/PXLongShotHUD.h"
#import <objc/message.h>
#import <stdatomic.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static dispatch_queue_t PXLongShotImageQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.pixpin.screenshot.longshot.images", DISPATCH_QUEUE_SERIAL); });
    return queue;
}
static id PXLongShotReadObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return nil; }
}

@interface PXLongShotSession () <PXLongShotHUDDelegate>
@property (nonatomic, strong) PXCaptureTask *task;
@property (nonatomic, copy) NSString *taskID;
@property (nonatomic, copy) NSString *captureMethod;
@property (nonatomic, copy) NSString *targetApplicationIdentifier;
@property (nonatomic, weak) id<PXLongShotSessionDelegate> delegate;
@property (nonatomic, strong) PXCaptureProvider *provider;
@property (nonatomic, strong) PXLongShotScroller *scroller;
@property (nonatomic, strong) PXLongShotCancellation *cancellation;
@property (nonatomic, strong) PXCaptureWindow *window;
@property (nonatomic, strong) PXLongShotHUD *hud;
@property (nonatomic, strong) NSTimer *sampleTimer;
@property (nonatomic, strong) id memoryObserver;
@property (nonatomic, strong) NSMutableArray<PXLongShotSlice *> *slices;
@property (nonatomic, strong) NSData *lastSeenSignatures;
@property (nonatomic, strong) PXLongPreviewCanvas *previewCanvas;
@property (nonatomic, assign) CGRect displayRect;
@property (nonatomic, assign) PXLongShotScrollPlan scrollPlan;
@property (nonatomic, assign) NSInteger fixedTop;
@property (nonatomic, assign) NSInteger fixedBottom;
@property (nonatomic, assign) NSInteger sameCount;
@property (nonatomic, assign) NSInteger unmatchedCount;
@property (nonatomic, assign) CFTimeInterval lastActivity;
@property (nonatomic, assign) CFTimeInterval nextSample;
@property (nonatomic, assign) BOOL autoScroll;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL scrolling;
@property (nonatomic, assign) BOOL stitching;
@property (nonatomic, assign) BOOL samplingStopped;
@property (nonatomic, assign) BOOL finishRequested;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) NSUInteger captureGeneration;
@property (nonatomic, assign) BOOL capturePending;
@property (nonatomic, assign) BOOL previewDisabled;
@property (nonatomic, assign) BOOL memoryWarningReceived;
@property (nonatomic, assign) BOOL stopAfterCurrentFrame;
- (void)handleLockStateChanged;
@end
static __weak PXLongShotSession *PXLockSession;
static atomic_uint_fast64_t PXLockGeneration;
static CFStringRef PXLockName = CFSTR("com.apple.springboard.lockstate");
static void PXLockCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                           const void *object, CFDictionaryRef userInfo) {
    uint_fast64_t generation = atomic_load(&PXLockGeneration);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation == atomic_load(&PXLockGeneration)) [PXLockSession handleLockStateChanged];
    });
}

@implementation PXLongShotSession
+ (instancetype)startWithTask:(PXCaptureTask *)task autoScroll:(BOOL)autoScroll
                   displayRect:(CGRect)displayRect
                     delegate:(id<PXLongShotSessionDelegate>)delegate {
    NSParameterAssert(NSThread.isMainThread);
    PXLongShotSession *session = [[self alloc] init];
    session.task = task;
    session.taskID = task.taskID;
    session.delegate = delegate;
    session.provider = [[PXCaptureProvider alloc] init];
    session.cancellation = [[PXLongShotCancellation alloc] init];
    session.slices = [NSMutableArray array];
    session.fixedTop = session.fixedBottom = -1;
    session.lastActivity = CACurrentMediaTime();
    session.autoScroll = autoScroll;
    session.displayRect = displayRect;
    if (autoScroll) session.scroller = [[PXLongShotScroller alloc] init];
    id app = PXLongShotReadObject(UIApplication.sharedApplication, @"_accessibilityFrontMostApplication");
    id identifier = PXLongShotReadObject(app, @"bundleIdentifier");
    if ([identifier isKindOfClass:NSString.class]) session.targetApplicationIdentifier = identifier;
    session.window = [PXCaptureWindow pxCaptureWindow];
    session.window.passesTouchesOutsideHostedContent = YES;
    session.hud = [[PXLongShotHUD alloc] initWithFrame:session.window.bounds];
    session.hud.delegate = session;
    [session.window hostContentView:session.hud];
    [session.window showAnimated:NO becomeKey:NO];
    atomic_fetch_add(&PXLockGeneration, 1);
    PXLockSession = session;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PXLockCallback,
                                    PXLockName, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    __weak PXLongShotSession *weakSession = session;
    session.memoryObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *note) { [weakSession pxHandleMemoryWarning]; }];
    UIImage *firstImage = task.baseImage;
    task.baseImage = nil;
    // 先让协调器保存会话，再启动可能失败的异步处理。
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![session pxIsTaskPresenting]) return;
        if (![session pxTargetIsCurrent]) { [session pxFail:@"请先打开需要滚动截图的 App"]; return; }
        if (session.autoScroll) {
            if (session.scroller.availabilityError) { [session pxFail:session.scroller.availabilityError]; return; }
            // HUD 小窗布局完成后读取实际面板矩形，自动滑动必须避开它。
            [session.hud layoutIfNeeded];
            PXLongShotScrollPlan plan;
            if (!PXLongShotBuildScrollPlan(session.displayRect, task.capturedScreenBounds,
                                           session.hud.panelFrame, &plan)) {
                [session pxFail:@"选区可滚动高度不足，请选择更大的内容区域"];
                return;
            }
            session.scrollPlan = plan;
            session.hud.statusText = @"自动滚动截取中，点「完成」停止";
            PXLogInfo(@"long shot automatic fullscreen started (task %@, rect=%@)", session.taskID,
                      NSStringFromCGRect(session.displayRect));
        } else {
            PXLogInfo(@"long shot manual fullscreen started (task %@)", session.taskID);
        }
        session.sampleTimer = [NSTimer timerWithTimeInterval:0.12 repeats:YES block:^(NSTimer *timer) {
            [weakSession pxTick];
        }];
        [NSRunLoop.mainRunLoop addTimer:session.sampleTimer forMode:NSRunLoopCommonModes];
        if (firstImage) {
            session.busy = YES;
            [session pxProcessImage:firstImage generation:++session.captureGeneration];
        } else [session pxStartCapture];
    });
    return session;
}
- (BOOL)isFinished { return self.finished; }
- (BOOL)pxIsTaskPresenting {
    return !self.finished && !self.cancellation.cancelled && self.task &&
           [self.task.taskID isEqualToString:self.taskID] && self.task.currentState == PXCaptureStatePresenting;
}
- (BOOL)pxTargetIsCurrent {
    id manager = PXLongShotReadObject(NSClassFromString(@"SBLockScreenManager"), @"sharedInstance");
    SEL selector = NSSelectorFromString(@"isUILocked");
    if (!manager || ![manager respondsToSelector:selector] || !self.targetApplicationIdentifier.length) return NO;
    @try { if (((BOOL (*)(id, SEL))objc_msgSend)(manager, selector)) return NO; }
    @catch (__unused NSException *exception) { return NO; }
    id app = PXLongShotReadObject(UIApplication.sharedApplication, @"_accessibilityFrontMostApplication");
    id identifier = PXLongShotReadObject(app, @"bundleIdentifier");
    return [identifier isKindOfClass:NSString.class] && [identifier isEqual:self.targetApplicationIdentifier];
}
- (void)pxTick {
    if (![self pxIsTaskPresenting] || self.samplingStopped || self.finishRequested) return;
    if (![self pxTargetIsCurrent]) { [self pxPause:@"前台 App 已变化，点「完成」保存已截内容"]; return; }
    CFTimeInterval now = CACurrentMediaTime();
    if (self.hud.isPreviewInteracting) self.lastActivity = now;
    // 自动模式由 滑动→静置→抓取 链条推进，tick 只做存活检查与状态兜底。
    if (self.autoScroll) return;
    if (self.busy) return;
    CFTimeInterval idle = now - self.lastActivity;
    if (idle >= 6 && self.slices.count) { [self longShotHUDDidTapFinish:self.hud]; return; }
    self.hud.statusText = idle >= 2
        ? [NSString stringWithFormat:@"静止 %ld 秒后完成\n滚动可继续", (long)MAX(1, (NSInteger)ceil(6 - idle))]
        : @"请缓慢向上滑动页面";
    if (now >= self.nextSample) [self pxStartCapture];
}
- (void)pxPause:(NSString *)message {
    if (![self pxIsTaskPresenting] || self.stitching) return;
    self.samplingStopped = YES;
    if (self.scrolling) [self.scroller cancel]; // 暂停即刻抬指，completion 内不会二次暂停。
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
    self.captureGeneration++;
    self.capturePending = NO;
    self.busy = NO;
    PXLogWarn(@"long shot stopped (task %@, slices=%lu): %@", self.taskID, (unsigned long)self.slices.count, message);
    if (!self.slices.count) [self pxFail:message];
    else if (self.finishRequested) [self pxStartStitch];
    else self.hud.statusText = message;
}
- (void)pxDisablePreview {
    self.previewDisabled = YES;
    // 后台正在使用的画布由该队列的局部强引用保活，退出后释放；禁止并发销毁 CGContext。
    self.previewCanvas = nil;
    [self.hud setPreviewImage:nil usedPixelHeight:0];
}
- (void)pxHandleMemoryWarning {
    if (![self pxIsTaskPresenting]) return;
    BOOL repeated = self.memoryWarningReceived;
    self.memoryWarningReceived = YES;
    [self pxDisablePreview];
    size_t availableBytes = PXLongShotAvailableMemoryBytes();
    size_t floorBytes = PXLongShotMemoryFloorBytes();
    PXLogWarn(@"long shot memory pressure (task %@, slices=%lu busy=%d repeated=%d stitching=%d available=%llu floor=%llu)",
              self.taskID, (unsigned long)self.slices.count, self.busy, repeated, self.stitching,
              (unsigned long long)availableBytes, (unsigned long long)floorBytes);
    if (self.stitching || self.samplingStopped || self.finishRequested) return;
    // SpringBoard 的 jetsam 限额只有几百 MB（实测 iPhone14,2/iOS 16.1 约 400MB），
    // 警告通常代表限额真的临近，按余量对比动态底线（限额 30%）判定是否熔断；
    // 余量不可知时退回“反复警告即停”。
    BOOL exhausted = (availableBytes != 0) ? (availableBytes < floorBytes) : repeated;
    if (!exhausted) {
        // 首片还在写盘时必须保留 generation，不能关闭会话；预览保持关闭即可继续。
        self.hud.statusText = @"已释放预览内存\n继续截取中";
        return;
    }
    self.stopAfterCurrentFrame = YES;
    if (self.scrolling) [self.scroller cancel];
    if (!self.busy && !self.scrolling && self.slices.count)
        [self pxPause:@"内存持续紧张，点「完成」保存已截内容"];
}
- (void)pxStartCapture {
    if (self.busy || ![self pxIsTaskPresenting]) return;
    // 暂停后不再采集；完成请求的末段抓取（finishRequested）除外。
    if (self.samplingStopped && !self.finishRequested) return;
    if (![self pxTargetIsCurrent]) { [self pxPause:@"前台 App 已变化，点「完成」保存已截内容"]; return; }
    self.busy = YES;
    self.capturePending = YES;
    NSUInteger generation = ++self.captureGeneration;
    __weak PXLongShotSession *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PXLongShotSession *s = weakSelf;
        if ([s pxIsTaskPresenting] && s.capturePending && generation == s.captureGeneration)
            [s pxPause:@"抓屏超时，点「完成」保存已截内容"];
    });
    @try {
        [self.provider captureExcludingWindows:@[self.window] completion:^(UIImage *image, BOOL partial, NSString *method, NSError *error) {
            PXLongShotSession *s = weakSelf;
            if (![s pxIsTaskPresenting] || generation != s.captureGeneration) return;
            s.capturePending = NO;
            if (![s.captureMethod isEqualToString:method]) {
                s.captureMethod = method;
                PXLogInfo(@"long shot capture method (task %@): %@", s.taskID, method);
            }
            if (![s pxTargetIsCurrent]) { [s pxPause:@"前台 App 已变化，点「完成」保存已截内容"]; return; }
            if (!image || partial) {
                PXLogWarn(@"long shot grab failed (task %@, method=%@ partial=%d)", s.taskID, method, partial);
                [s pxPause:@"无法取得完整屏幕，点「完成」保存已截内容"];
            } else [s pxProcessImage:image generation:generation];
        }];
    } @catch (__unused NSException *exception) {
        [self pxPause:@"抓屏接口异常，点「完成」保存已截内容"];
    }
}
- (void)pxProcessImage:(UIImage *)image generation:(NSUInteger)generation {
    NSInteger width = (NSInteger)CGImageGetWidth(image.CGImage), height = (NSInteger)CGImageGetHeight(image.CGImage);
    CGRect captureRect = CGRectMake(0, 0, width, height);
    if (self.autoScroll) {
        // 选区入口：采集裁片限定在选区内，签名与拼接都在裁片坐标系上进行。
        captureRect = PXConvertDisplayRectToPixel(self.displayRect, self.task.capturedScreenBounds.size,
                                                  CGSizeMake(width, height));
        if (CGRectIsEmpty(captureRect)) { [self pxPause:@"截取区域无效，请重新选择"]; return; }
    }
    NSInteger rows = (NSInteger)CGRectGetHeight(captureRect), columns = (NSInteger)CGRectGetWidth(captureRect);
    PXLongShotSlice *anchor = self.slices.lastObject;
    if (anchor && (columns != anchor.pixelWidth || rows != anchor.pixelHeight)) {
        [self pxPause:@"屏幕尺寸已变化，点「完成」保存已截内容"]; return;
    }
    NSString *directory = [self.task ensureTemporaryDirectory];
    if (!directory.length) { [self pxPause:@"临时目录创建失败"]; return; }
    NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"longframe_%06lu.jpg", (unsigned long)generation]];
    NSInteger fixedTop = self.fixedTop, fixedBottom = self.fixedBottom;
    PXLongShotCancellation *cancellation = self.cancellation;
    __weak PXLongShotSession *weakSelf = self;
    dispatch_async(PXLongShotImageQueue(), ^{
        @autoreleasepool {
            if (cancellation.cancelled) return;
            NSError *error = nil;
            PXLongShotSlice *slice = [PXLongImageComposer sliceFromScreenImage:image pixelRect:captureRect
                                      filePath:path cancellation:cancellation error:&error];
            PXLongShotFrameMatch match = {PXLongShotMatchForward, 0, 0, 0};
            if (slice && anchor)
                match = PXLongShotMatchFrames(anchor.rowSignatures.bytes, slice.rowSignatures.bytes, rows, fixedTop, fixedBottom);
            if (cancellation.cancelled) { [NSFileManager.defaultManager removeItemAtPath:path error:nil]; return; }
            dispatch_async(dispatch_get_main_queue(), ^{
                PXLongShotSession *s = weakSelf;
                if (![s pxIsTaskPresenting] || generation != s.captureGeneration) {
                    [NSFileManager.defaultManager removeItemAtPath:path error:nil]; return;
                }
                if (![s pxTargetIsCurrent]) { [NSFileManager.defaultManager removeItemAtPath:path error:nil];
                    [s pxPause:@"前台 App 已变化，点「完成」保存已截内容"]; return; }
                if (!slice) { [s pxPause:error.localizedDescription ?: @"分片处理失败"]; return; }
                NSInteger top = MAX(0, s.fixedTop), bottom = MAX(0, s.fixedBottom);
                NSInteger body = rows - top - bottom;
                BOOL unchanged = s.lastSeenSignatures.length == slice.rowSignatures.length &&
                    PXLongShotSignaturesAreDuplicate((const uint8_t *)s.lastSeenSignatures.bytes + top * 64, body,
                                                     (const uint8_t *)slice.rowSignatures.bytes + top * 64, body);
                s.lastSeenSignatures = slice.rowSignatures;
                if (!unchanged) { s.lastActivity = CACurrentMediaTime(); s.sameCount = 0; }
                else s.sameCount++;
                if (s.autoScroll && s.sameCount >= 2 && !s.finishRequested) {
                    // 连续两帧内容未变化：已到页面底部，自动完成（走完成路径收尾）。
                    PXLogInfo(@"long shot bottom reached (task %@, slices=%lu)", s.taskID,
                              (unsigned long)s.slices.count);
                    [s longShotHUDDidTapFinish:s.hud];
                }
                if (anchor && match.kind != PXLongShotMatchForward) {
                    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
                    s.busy = NO;
                    if (match.kind == PXLongShotMatchUncertain) {
                        s.unmatchedCount++;
                        if (s.unmatchedCount >= 3) { [s pxPause:@"无法可靠拼接，请点「完成」保存已截内容"]; return; }
                        if (!s.finishRequested) s.hud.statusText = @"正在重试对齐\n请放慢滚动";
                    } else {
                        s.unmatchedCount = 0;
                        if (match.kind == PXLongShotMatchReverse && !s.finishRequested)
                            s.hud.statusText = @"反向内容不追加\n请继续向上滑动";
                    }
                    [s pxCompleteFrame];
                    return;
                }
                s.unmatchedCount = 0;
                if (anchor) {
                    if (s.fixedTop < 0) { s.fixedTop = match.fixedTopRows; s.fixedBottom = match.fixedBottomRows; }
                    anchor.cropBottomRows = s.fixedBottom;
                    [anchor discardAlignmentSignature];
                    slice.cropTopRows = rows - s.fixedBottom - match.shiftRows;
                }
                [s.slices addObject:slice];
                [s.hud setSliceCount:(NSInteger)s.slices.count];
                PXLogInfo(@"long shot append (task %@, count=%lu shift=%ld fixed=%ld/%ld)", s.taskID,
                          (unsigned long)s.slices.count, (long)match.shiftRows, (long)s.fixedTop, (long)s.fixedBottom);
                [s pxUpdatePreview:generation];
            });
        }
    });
}
- (void)pxUpdatePreview:(NSUInteger)generation {
    if (self.previewDisabled) {
        self.busy = NO;
        [self pxCompleteFrame];
        return;
    }
    if (!self.previewCanvas) {
        CGFloat scale = MAX(1, self.task.capturedScreenScale);
        self.previewCanvas = [[PXLongPreviewCanvas alloc] initWithWidthPixels:(NSInteger)(PXLongShotHUDPreviewWidthPt * scale)
                                  maxPixels:500000 uiScale:scale cancellation:self.cancellation];
    }
    NSArray *slices = [self.slices copy];
    PXLongPreviewCanvas *canvas = self.previewCanvas;
    PXLongShotCancellation *cancellation = self.cancellation;
    __weak PXLongShotSession *weakSelf = self;
    dispatch_async(PXLongShotImageQueue(), ^{
        @autoreleasepool {
            if (cancellation.cancelled) return;
            UIImage *preview = [canvas updateWithSlices:slices];
            NSInteger height = canvas.usedPixelHeight;
            dispatch_async(dispatch_get_main_queue(), ^{
                PXLongShotSession *s = weakSelf;
                if (![s pxIsTaskPresenting] || generation != s.captureGeneration) return;
                s.busy = NO;
                if (!s.previewDisabled) {
                    if (preview) [s.hud setPreviewImage:preview usedPixelHeight:height];
                    else {
                        [s pxDisablePreview];
                        PXLogWarn(@"long shot preview disabled (task %@, slices=%lu)", s.taskID,
                                  (unsigned long)s.slices.count);
                    }
                }
                [s pxCompleteFrame];
            });
        }
    });
}
- (void)pxCompleteFrame {
    self.nextSample = CACurrentMediaTime() + (self.sameCount >= 3 ? 0.5 : 0.12);
    if (self.finishRequested || self.slices.count >= PXLongShotMaxSlices) { [self pxStartStitch]; return; }
    if (self.stopAfterCurrentFrame) {
        [self pxPause:@"内存持续紧张，点「完成」保存已截内容"];
        return;
    }
    if (self.autoScroll) [self pxScheduleAutoScroll];
}
#pragma mark - 自动滚动（选区工具栏入口）
- (void)pxScheduleAutoScroll {
    if (![self pxIsTaskPresenting] || self.finishRequested || self.stitching || self.samplingStopped) return;
    __weak PXLongShotSession *weakSession = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSession pxScrollOnce];
    });
}
- (void)pxScrollOnce {
    if (![self pxIsTaskPresenting] || self.finishRequested || self.stitching || self.samplingStopped ||
        self.stopAfterCurrentFrame) return;
    if (self.busy || self.scrolling || self.hud.isPreviewInteracting) { [self pxScheduleAutoScroll]; return; }
    if (![self pxTargetIsCurrent]) { [self pxPause:@"前台 App 已变化，点「完成」保存已截内容"]; return; }
    self.scrolling = YES;
    __weak PXLongShotSession *weakSelf = self;
    [self.scroller scrollWithPlan:self.scrollPlan completion:^(BOOL completed) {
        PXLongShotSession *s = weakSelf;
        if (!s) return;
        s.scrolling = NO;
        if (![s pxIsTaskPresenting]) return;
        if (!completed && !s.finishRequested && !s.samplingStopped && !s.stopAfterCurrentFrame)
            [s pxPause:@"自动滚动失败，点「完成」保存已截内容"];
        // 抬指后等动画与合成器稳定再抓取；完成请求不跳过这次末段抓取。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            PXLongShotSession *t = weakSelf;
            if (![t pxIsTaskPresenting]) return;
            [t pxStartCapture];
        });
    }];
}
- (void)longShotHUDDidTapFinish:(UIView *)hud {
    if (self.finishRequested || ![self pxIsTaskPresenting]) return;
    BOOL wasStopped = self.samplingStopped;
    self.finishRequested = YES;
    self.samplingStopped = YES;
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
    [self.hud setFinishing:YES];
    self.hud.statusText = @"正在收齐当前段…";
    PXLogInfo(@"long shot finish requested (task %@ busy=%d scrolling=%d)", self.taskID, self.busy, self.scrolling);
    if (self.scrolling) { [self.scroller cancel]; return; } // 抬指后由完成回调收末段。
    if (!self.busy) {
        // 资源保护已停止的会话直接保存，不为“完成”再分配一张整屏位图。
        if (wasStopped) [self pxStartStitch];
        else if ([self pxTargetIsCurrent]) [self pxStartCapture];
        else [self pxStartStitch];
    }
}
- (void)longShotHUDDidTapCancel:(UIView *)hud {
    if (self.finished) return;
    id<PXLongShotSessionDelegate> delegate = self.delegate;
    PXLogInfo(@"long shot cancelled (task %@)", self.taskID);
    [self pxTeardownRemovingFiles:YES];
    [delegate longShotSessionDidCancel:self];
}
- (void)handleLockStateChanged { [self longShotHUDDidTapCancel:self.hud]; }

- (void)pxStartStitch {
    if (self.busy || self.stitching || ![self pxIsTaskPresenting]) return;
    if (self.slices.count == 0) { [self pxFail:@"没有可保存的长截图内容"]; return; }
    self.busy = YES;
    self.stitching = YES;
    self.samplingStopped = YES;
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
    self.finishRequested = YES;
    [self.hud setFinishing:YES];
    self.hud.statusText = @"长图拼接中…";
    // 导出前丢弃预览，避免画布与 HUD 纹理叠加在正式拼接的内存峰值上。
    [self pxDisablePreview];
    NSString *directory = [self.task ensureTemporaryDirectory];
    if (directory.length == 0) { [self pxFail:@"临时目录创建失败"]; return; }
    NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"longshot.jpg"]];
    NSArray<PXLongShotSlice *> *slices = [self.slices copy];
    CGFloat screenScale = self.task.capturedScreenScale;
    PXLongShotCancellation *cancellation = self.cancellation;
    // 画布上限按任务限额收缩（SpringBoard 限额仅几百 MB），余量预算在拼接内逐片适配。
    NSInteger maxPixels = PXLongShotStitchPixelCap(PXLongShotProcessMemoryLimitBytes(),
                                                   PXLongShotMaxCanvasPixels);
    __weak PXLongShotSession *weakSelf = self;
    dispatch_async(PXLongShotImageQueue(), ^{
        @autoreleasepool {
            if (cancellation.cancelled) return;
            CGSize size = CGSizeZero;
            NSError *error = nil;
            UIImage *image = [PXLongImageComposer composedImageWithSlices:slices screenScale:screenScale
                                                                outputURL:url maxPixels:maxPixels cancellation:cancellation
                                                            progressBlock:^(NSInteger done, NSInteger total) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    PXLongShotSession *session = weakSelf;
                    if (!session || ![session pxIsTaskPresenting]) return;
                    session.hud.statusText = done >= total ? @"长图编码中…"
                        : [NSString stringWithFormat:@"拼接中 %ld/%ld 段…", (long)MAX(0, done - total / 2), (long)(total / 2)];
                });
            } outPixelSize:&size error:&error];
            if (cancellation.cancelled) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                PXLongShotSession *session = weakSelf;
                if (!session || ![session pxIsTaskPresenting]) return;
                session.busy = NO;
                if (!image) { [session pxFail:error.localizedDescription ?: @"长图拼接失败"]; return; }
                PXLogInfo(@"long shot stitched (task %@, %.0fx%.0f px)", session.task.taskID, size.width, size.height);
                id<PXLongShotSessionDelegate> delegate = session.delegate;
                [session pxTeardownRemovingFiles:NO];
                [delegate longShotSessionDidFinish:session resultImage:image];
            });
        }
    });
}


- (void)pxFail:(NSString *)message {
    if (self.finished) return;
    id<PXLongShotSessionDelegate> delegate = self.delegate;
    PXLogWarn(@"long shot failed (task %@): %@", self.taskID, message);
    [self pxTeardownRemovingFiles:YES];
    [delegate longShotSessionDidFail:self message:message];
}
- (void)teardownForExternalCancel {
    if (NSThread.isMainThread) [self pxTeardownRemovingFiles:YES];
    else dispatch_async(dispatch_get_main_queue(), ^{ [self pxTeardownRemovingFiles:YES]; });
}
- (void)pxTeardownRemovingFiles:(BOOL)remove {
    if (self.finished) return;
    self.finished = YES;
    self.cancellation.cancelled = YES;
    self.captureGeneration++;
    [self.scroller cancel]; // 同步抬指；dealloc 前必须结束滑动。
    self.scroller = nil;
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
    if (self.memoryObserver) [NSNotificationCenter.defaultCenter removeObserver:self.memoryObserver];
    self.memoryObserver = nil;
    atomic_fetch_add(&PXLockGeneration, 1);
    PXLockSession = nil;
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PXLockName, NULL);
    self.hud.delegate = nil;
    [self.window hideAndDestroyWithCompletion:nil];
    self.hud = nil;
    self.window = nil;
    self.slices = nil;
    self.previewCanvas = nil;
    self.lastSeenSignatures = nil;
    self.task = nil;
    self.delegate = nil;
    if (remove) {
        NSString *taskID = self.taskID;
        // 最后一个写盘/预览任务退出后再清理一次，覆盖取消与写盘交错的情况。
        dispatch_async(PXLongShotImageQueue(), ^{ [PXTemporaryFileStore removeTaskDirectory:taskID]; });
    }
}
@end
