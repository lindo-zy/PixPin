#import "PXLongShotSession.h"
#import "PXCaptureTask.h"
#import "PXCaptureProvider.h"
#import "PXLongShotScroller.h"
#import "PXLongShotTarget.h"
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
@property (nonatomic, assign) BOOL retryAlignment;
@property (nonatomic, assign) BOOL alignmentResampled;
@property (nonatomic, assign) BOOL needsSettledCapture;
@property (nonatomic, assign) CFTimeInterval lastActivity;
@property (nonatomic, assign) CFTimeInterval nextSample;
@property (nonatomic, assign) BOOL autoScroll;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL scrolling;
@property (nonatomic, assign) BOOL scrollPreparing;
@property (nonatomic, assign) BOOL autoStepScheduled;
@property (nonatomic, assign) NSUInteger flowGeneration;
@property (nonatomic, assign) PXLongShotReboundState rebound;
@property (nonatomic, assign) BOOL memoryRecoveryPending;
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
- (void)pxCheckFrameMemory;
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
    session.provider.detachesCapturedImage = YES;
    session.cancellation = [[PXLongShotCancellation alloc] init];
    session.slices = [NSMutableArray array];
    session.fixedTop = session.fixedBottom = -1;
    session.lastActivity = CACurrentMediaTime();
    session.autoScroll = autoScroll;
    session.displayRect = displayRect;
    if (autoScroll) session.scroller = [[PXLongShotScroller alloc] init];
    session.targetApplicationIdentifier = PXLongShotFrontmostIdentifier(UIApplication.sharedApplication);
    session.window = [PXCaptureWindow pxCaptureWindow];
    // Window 的实际表面只占 HUD 面板。全屏 Window 的 UIKit 空命中不能证明跨进程透传。
    UIEdgeInsets safe = session.window.windowScene.keyWindow.safeAreaInsets;
    CGRect screenBounds = task.capturedScreenBounds;
    CGFloat hudWidth = PXLongShotHUDPreviewWidthPt + 16;
    CGFloat hudHeight = MIN(242, screenBounds.size.height - safe.top - safe.bottom - 20);
    session.window.frame = CGRectMake(CGRectGetMaxX(screenBounds) - safe.right - 12 - hudWidth,
                                      CGRectGetMinY(screenBounds) + safe.top + 10, hudWidth, hudHeight);
    session.window.windowLevel = UIWindowLevelStatusBar;
    session.window.passesTouchesOutsideHostedContent = YES;
    session.hud = [[PXLongShotHUD alloc] initWithFrame:session.window.bounds];
    session.hud.delegate = session;
    [session.window hostContentView:session.hud];
    session.window.rootViewController.view.frame = session.window.bounds;
    session.hud.frame = session.window.bounds;
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
            // 手势期间 HUD 整窗隐藏，滑动路径只受选区和屏幕安全区约束。
            [session.hud layoutIfNeeded];
            PXLongShotScrollPlan plan;
            if (!PXLongShotBuildScrollPlan(session.displayRect, task.capturedScreenBounds,
                                           CGRectZero, &plan)) { // 手势期间 HUD 整窗隐藏，不占用滚动带。
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
        session.sampleTimer = [NSTimer timerWithTimeInterval:task.configSnapshot.longShotOptions.sampleInterval repeats:YES block:^(NSTimer *timer) {
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
    return PXLongShotTargetIsCurrent(UIApplication.sharedApplication, PXLongShotLockManager(),
                                     self.targetApplicationIdentifier);
}
- (void)pxTick {
    if (![self pxIsTaskPresenting] || self.samplingStopped || self.finishRequested || self.memoryRecoveryPending) return;
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
    self.flowGeneration++;
    self.autoStepScheduled = NO;
    self.retryAlignment = NO;
    self.alignmentResampled = NO;
    [self pxCancelScrolling];
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
- (void)pxRestoreHUD {
    if ([self pxIsTaskPresenting] && self.window.rootViewController) self.window.hidden = NO;
}
- (void)pxCancelScrolling {
    if (self.scrollPreparing) {
        self.scrollPreparing = NO;
        self.scrolling = NO;
        self.flowGeneration++;
        [self pxRestoreHUD];
    } else [self.scroller cancel];
}
// 不再抓末帧：资源不足/已完成采样时只处理当前在途帧，然后导出已落盘内容。
- (void)pxFinishCapturedContent:(NSString *)message {
    if (![self pxIsTaskPresenting] || self.stitching) return;
    self.finishRequested = YES;
    self.samplingStopped = YES;
    self.flowGeneration++;
    self.autoStepScheduled = NO;
    [self.sampleTimer invalidate];
    self.sampleTimer = nil;
    [self.hud setFinishing:YES];
    self.hud.statusText = message;
    [self pxCancelScrolling];
    PXLogInfo(@"long shot automatic finish (task %@ slices=%lu): %@", self.taskID,
              (unsigned long)self.slices.count, message);
    if (!self.busy && !self.scrolling) [self pxStartStitch];
}
- (void)pxHandleMemoryWarning {
    if (![self pxIsTaskPresenting]) return;
    BOOL repeated = self.memoryWarningReceived;
    self.memoryWarningReceived = YES;
    [self pxDisablePreview];
    // 先释放预览并切换抓屏路径；不把某种 API 的内存表现当作已验证事实。
    self.provider.fallbackOnlyCapture = YES;
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
    [self pxCancelScrolling];
    if (!self.busy && !self.scrolling) [self pxCompleteFrame];
}
- (void)pxStartCapture {
    if (self.busy || self.scrolling || self.memoryRecoveryPending || ![self pxIsTaskPresenting]) return;
    // 暂停后不再采集；完成请求的末段抓取（finishRequested）除外。
    if (self.samplingStopped && !self.finishRequested) return;
    if (self.stopAfterCurrentFrame) { [self pxCompleteFrame]; return; }
    if (![self pxTargetIsCurrent]) { [self pxPause:@"前台 App 已变化，点「完成」保存已截内容"]; return; }
    size_t available = PXLongShotAvailableMemoryBytes();
    if (available && available < PXLongShotMemoryFloorBytes()) {
        [self pxDisablePreview];
        available = PXLongShotAvailableMemoryBytes();
        if (available && available < PXLongShotMemoryFloorBytes()) {
            self.stopAfterCurrentFrame = YES;
            if (self.slices.count >= 2) [self pxFinishCapturedContent:@"内存紧张，自动完成"];
            else [self pxPause:@"内存不足，点「完成」保存当前截取"];
            return;
        }
    }
    self.busy = YES;
    self.capturePending = YES;
    self.needsSettledCapture = NO;
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
    NSData *previousSeen = self.lastSeenSignatures;
    PXLongShotOptions *options = self.task.configSnapshot.longShotOptions;
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
                                      filePath:path options:options cancellation:cancellation error:&error];
            PXLongShotFrameMatch match = {PXLongShotMatchForward, 0, 0, 0};
            if (slice && anchor)
                match = PXLongShotMatchFrames(anchor.rowSignatures.bytes, slice.rowSignatures.bytes, rows, fixedTop, fixedBottom);
            PXLongShotFrameMatch adjacent = match;
            if (slice && previousSeen.length == slice.rowSignatures.length && previousSeen != anchor.rowSignatures)
                adjacent = PXLongShotMatchFrames(previousSeen.bytes, slice.rowSignatures.bytes, rows, fixedTop, fixedBottom);
            // 未确认与已保存内容衔接时，不能用相邻帧的方向替代拼接可信度。
            if (match.kind == PXLongShotMatchUncertain) adjacent.kind = PXLongShotMatchUncertain;
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
                PXLongShotReboundState rebound = s.rebound;
                BOOL bounced = PXLongShotUpdateRebound(&rebound, adjacent, body, s.autoScroll && anchor != nil);
                s.rebound = rebound;
                if (bounced && s.slices.count >= 2 && !s.finishRequested)
                    [s pxFinishCapturedContent:@"到底回弹，自动完成"];
                if (s.autoScroll && s.sameCount >= 2 && !s.finishRequested && s.slices.count >= 2 &&
                    match.kind == PXLongShotMatchDuplicate) {
                    // 连续两帧内容未变化：已到页面底部，自动完成（走完成路径收尾）。
                    PXLogInfo(@"long shot bottom reached (task %@, slices=%lu)", s.taskID,
                              (unsigned long)s.slices.count);
                    [s pxFinishCapturedContent:@"内容静止，自动完成"];
                } else if (s.autoScroll && s.sameCount >= 3 && !s.finishRequested && s.slices.count < 2) {
                    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
                    [s pxPause:@"页面没有滚动，请确认正文可滚动或改用手动模式"];
                    return;
                }
                if (anchor && match.kind != PXLongShotMatchForward) {
                    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
                    s.busy = NO;
                    s.retryAlignment = match.kind == PXLongShotMatchUncertain;
                    if (match.kind == PXLongShotMatchUncertain) {
                        s.unmatchedCount++;
                        BOOL resampled = s.alignmentResampled;
                        // 判歧可能来自内容固有歧义（周期性列表/稀疏留白），与瞬态噪声不同源；
                        // 逐次留下 syslog 才能在真机上区分重采无效与偶发抖动。
                        PXLogWarn(@"long shot align uncertain (task %@, consecutive=%ld, slices=%lu, resampled=%d)",
                                  s.taskID, (long)s.unmatchedCount, (unsigned long)s.slices.count, resampled);
                        if (s.unmatchedCount >= 3) { [s pxPause:@"无法可靠拼接，请点「完成」保存已截内容"]; return; }
                        if (!s.finishRequested)
                            s.hud.statusText = resampled ? @"对齐仍有歧义\n小步回滚重试" : @"正在重试对齐\n请放慢滚动";
                    } else {
                        s.unmatchedCount = 0;
                        s.alignmentResampled = NO;
                        if (match.kind == PXLongShotMatchReverse && !s.finishRequested)
                            s.hud.statusText = @"反向内容不追加\n请继续向上滑动";
                    }
                    [s pxCompleteFrame];
                    return;
                }
                s.unmatchedCount = 0;
                s.retryAlignment = NO;
                s.alignmentResampled = NO;
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
// 每帧遥测 + 主动熔断：highwater jetsam 可能先于 MemoryWarning 击杀（警告不保证送达
// 或来得及处理），不能只依赖系统警告采样。逐帧留下 footprint/余量曲线到 syslog；
// 余量跌破动态底线时与警告 exhausted 路径同口径熔断。
- (void)pxCheckFrameMemory {
    size_t availableBytes = PXLongShotAvailableMemoryBytes();
    size_t floorBytes = PXLongShotMemoryFloorBytes();
    PXLogInfo(@"long shot mem (task %@, gen=%lu slices=%lu footprint=%llu available=%llu floor=%llu fallback=%d)",
              self.taskID, (unsigned long)self.captureGeneration, (unsigned long)self.slices.count,
              (unsigned long long)PXLongShotProcessFootprintBytes(), (unsigned long long)availableBytes,
              (unsigned long long)floorBytes, self.provider.fallbackOnlyCapture);
    if (!availableBytes) return;
    if (availableBytes >= floorBytes) { self.stopAfterCurrentFrame = NO; return; }
    PXLogWarn(@"long shot proactive memory trip (task %@, available=%llu floor=%llu)",
              self.taskID, (unsigned long long)availableBytes, (unsigned long long)floorBytes);
    BOOL canReleasePreview = !self.previewDisabled;
    [self pxDisablePreview];
    self.memoryWarningReceived = YES;
    self.provider.fallbackOnlyCapture = YES;
    if (canReleasePreview) {
        // 先让图像队列结束旧预览/快照引用，再复测；期间绝不发送下一次手势或抓屏。
        self.memoryRecoveryPending = YES;
        [self pxCancelScrolling];
        __weak PXLongShotSession *weakSelf = self;
        dispatch_async(PXLongShotImageQueue(), ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                PXLongShotSession *s = weakSelf;
                if (![s pxIsTaskPresenting]) return;
                s.memoryRecoveryPending = NO;
                [s pxCompleteFrame];
            });
        });
        return;
    }
    self.stopAfterCurrentFrame = YES;
    [self pxCancelScrolling];
}
- (void)pxCompleteFrame {
    if (![self pxIsTaskPresenting] || self.stitching) return;
    // 用同一串行队列作为释放屏障：不能在处理块的 autoreleasepool 退出前采样内存。
    self.busy = YES;
    NSUInteger generation = self.captureGeneration;
    __weak PXLongShotSession *weakSelf = self;
    dispatch_async(PXLongShotImageQueue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            PXLongShotSession *s = weakSelf;
            if (![s pxIsTaskPresenting] || s.stitching || generation != s.captureGeneration) return;
            s.busy = NO;
            [s pxCompleteFrameAfterRelease];
        });
    });
}
- (void)pxCompleteFrameAfterRelease {
    [self pxCheckFrameMemory];
    if (self.memoryRecoveryPending) return;
    PXLongShotOptions *options = self.task.configSnapshot.longShotOptions;
    self.nextSample = CACurrentMediaTime() + (self.sameCount >= 3 ? options.idleInterval : options.sampleInterval);
    if (self.finishRequested || self.slices.count >= (NSUInteger)options.maxSlices) { [self pxStartStitch]; return; }
    if (self.stopAfterCurrentFrame) {
        if (self.slices.count >= 2) [self pxFinishCapturedContent:@"内存紧张，自动完成"];
        else [self pxPause:@"内存不足，点「完成」保存当前截取"];
        return;
    }
    if (self.autoScroll && self.retryAlignment && self.alignmentResampled) {
        // 重采已确认页面静止仍判歧：同页重采只会复现同一结果，小步回滚改变与锚点的
        // 比较基准；不前滚以免扩大未捕获缺口。总上限仍由 unmatchedCount>=3 把守。
        PXLongShotScrollPlan corrective;
        self.alignmentResampled = NO;
        if (PXLongShotBuildCorrectiveScrollPlan(self.scrollPlan, 1.0 / 3.0, &corrective)) {
            self.busy = YES;
            NSUInteger flow = self.flowGeneration;
            __weak PXLongShotSession *weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(options.settleDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                PXLongShotSession *s = weakSelf;
                if (![s pxIsTaskPresenting] || s.flowGeneration != flow) return;
                s.busy = NO;
                if (s.samplingStopped && !s.finishRequested) return; // 已暂停：只等用户完成/取消
                // 静置窗口内点「完成」或内存熔断时不回滚：末段抓取/收尾入口自行分流，
                // 否则手势被 finishRequested/stopAfterCurrentFrame 拒绝后会话无人推进。
                if (s.finishRequested || s.stopAfterCurrentFrame) { [s pxStartCapture]; return; }
                [s pxScheduleGesturePlan:corrective];
            });
            return;
        }
        // 滑动带过窄等无法回滚的情形：退回重采，仍由 unmatchedCount>=3 兜底。
        PXLogWarn(@"long shot corrective rollback unavailable (task %@, slices=%lu)",
                  self.taskID, (unsigned long)self.slices.count);
    }
    if (self.autoScroll && (self.retryAlignment || self.needsSettledCapture)) {
        // 对齐未确认时重采当前页面，不能继续滚动扩大未捕获的缺口。
        if (self.retryAlignment) self.alignmentResampled = YES;
        self.busy = YES;
        NSUInteger flow = self.flowGeneration;
        __weak PXLongShotSession *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(options.settleDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            PXLongShotSession *s = weakSelf;
            if ([s pxIsTaskPresenting] && s.flowGeneration == flow) {
                s.busy = NO;
                [s pxStartCapture];
            }
        });
    } else if (self.autoScroll) [self pxScheduleAutoScroll];
}
#pragma mark - 自动滚动（选区工具栏入口）
- (void)pxScheduleAutoScroll {
    [self pxScheduleGesturePlan:self.scrollPlan];
}

// 常规步进与对齐判歧后的纠正性回滚共用调度与防重入；差别只在滑动带方向与距离。
- (void)pxScheduleGesturePlan:(PXLongShotScrollPlan)plan {
    if (![self pxIsTaskPresenting] || self.finishRequested || self.stitching || self.samplingStopped ||
        self.memoryRecoveryPending || self.autoStepScheduled) return;
    self.autoStepScheduled = YES;
    NSUInteger flow = self.flowGeneration;
    __weak PXLongShotSession *weakSession = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PXLongShotSession *s = weakSession;
        if (s.flowGeneration == flow) {
            s.autoStepScheduled = NO;
            [s pxRunGesturePlan:plan];
        }
    });
}
- (void)pxRunGesturePlan:(PXLongShotScrollPlan)plan {
    if (![self pxIsTaskPresenting] || self.finishRequested || self.stitching || self.samplingStopped ||
        self.stopAfterCurrentFrame || self.memoryRecoveryPending) return;
    if (self.busy || self.scrolling) return;
    if (self.hud.isPreviewInteracting) { [self pxScheduleGesturePlan:plan]; return; }
    if (![self pxTargetIsCurrent]) { [self pxPause:@"前台 App 已变化，点「完成」保存已截内容"]; return; }
    self.scrolling = YES;
    self.scrollPreparing = YES;
    NSUInteger flow = self.flowGeneration;
    self.window.hidden = YES;
    [CATransaction flush];
    __weak PXLongShotSession *weakSelf = self;
    // 合成器必须先移走本方表面，避免系统在 UIKit 命中之前把事件选给 SpringBoard。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 / 60.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      PXLongShotSession *prepared = weakSelf;
      if (![prepared pxIsTaskPresenting] || prepared.flowGeneration != flow || !prepared.scrollPreparing) return;
      prepared.scrollPreparing = NO;
      [prepared.scroller scrollWithPlan:plan duration:prepared.task.configSnapshot.longShotOptions.scrollDuration completion:^(BOOL completed) {
        PXLongShotSession *s = weakSelf;
        if (!s) return;
        s.scrolling = NO;
        [s pxRestoreHUD];
        if (![s pxIsTaskPresenting]) return;
        if (s.flowGeneration != flow || s.memoryRecoveryPending || s.stopAfterCurrentFrame) {
            if (s.finishRequested && !s.busy) [s pxStartStitch];
            return;
        }
        if (!completed && !s.finishRequested && !s.samplingStopped && !s.stopAfterCurrentFrame)
            { [s pxPause:@"自动滚动失败，点「完成」保存已截内容"]; return; }
        // 抬指后等动画与合成器稳定再抓取；完成请求不跳过这次末段抓取。
        s.busy = YES; // 静置属于本轮工作，不能在尚未抓屏时启动第二次手势。
        s.needsSettledCapture = YES;
        NSTimeInterval settle = s.task.configSnapshot.longShotOptions.settleDuration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(settle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            PXLongShotSession *t = weakSelf;
            if (![t pxIsTaskPresenting] || t.flowGeneration != flow ||
                (t.samplingStopped && !t.finishRequested)) return;
            t.busy = NO;
            [t pxStartCapture];
        });
      }];
    });
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
    if (self.scrollPreparing) {
        [self pxCancelScrolling];
        [self pxStartStitch];
        return;
    }
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
    self.flowGeneration++;
    self.autoStepScheduled = NO;
    self.retryAlignment = NO;
    self.alignmentResampled = NO;
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
    PXLongShotOptions *options = self.task.configSnapshot.longShotOptions;
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
                                                                outputURL:url maxPixels:maxPixels options:options cancellation:cancellation
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
    self.flowGeneration++;
    [self pxCancelScrolling]; // 同步抬指；dealloc 前必须结束滑动。
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
