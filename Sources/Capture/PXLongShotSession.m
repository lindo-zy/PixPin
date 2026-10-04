#import "PXLongShotSession.h"
#import "PXCaptureTask.h"
#import "PXCaptureProvider.h"
#import "PXLongShotScroller.h"
#import "../Common/PXLog.h"
#import "../Common/PXLongShotAligner.h"
#import "../Common/PXLongShotControl.h"
#import "../Output/PXLongImageComposer.h"
#import "../Output/PXLongPreviewCanvas.h"
#import "../Overlay/PXCaptureWindow.h"
#import "../Overlay/PXLongShotHUD.h"
#import <stdatomic.h>

// 所有会话的位图工作共用串行队列；旧会话取消时不会与新会话分配多块大画布。
static dispatch_queue_t PXLongShotImageQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.pixpin.screenshot.longshot.images", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

@interface PXLongShotSession () <PXLongShotHUDDelegate>
@property (nonatomic, strong) PXCaptureTask *task;
@property (nonatomic, weak) id<PXLongShotSessionDelegate> delegate;
@property (nonatomic, strong) PXCaptureProvider *provider;
@property (nonatomic, strong) PXLongShotScroller *scroller;
@property (nonatomic, strong) PXLongShotCancellation *cancellation;
@property (nonatomic, strong) PXCaptureWindow *window;
@property (nonatomic, strong) PXLongShotHUD *hud;
@property (nonatomic, assign) CGRect displayRect;
@property (nonatomic, strong) NSMutableArray<PXLongShotSlice *> *slices;
@property (nonatomic, strong) PXLongPreviewCanvas *previewCanvas;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL scrolling;
@property (nonatomic, assign) BOOL settling;
@property (nonatomic, assign) BOOL autoRunning;
@property (nonatomic, assign) BOOL finishRequested;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) NSUInteger scheduleGeneration;
@property (nonatomic, assign) NSUInteger captureGeneration;
@property (nonatomic, assign) BOOL capturePending;
@property (nonatomic, assign) NSInteger duplicateCount;
- (void)handleLockStateChanged;
@end

static PXLongShotSession *_PXLongShotLockObserverSession;
static atomic_uint_fast64_t PXLongShotLockGeneration;
static CFStringRef PXLongShotLockStateName = CFSTR("com.apple.springboard.lockstate");

static void PXLongShotLockStateCallback(CFNotificationCenterRef center, void *observer,
                                        CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    uint_fast64_t generation = atomic_load(&PXLongShotLockGeneration);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation == atomic_load(&PXLongShotLockGeneration)) {
            [_PXLongShotLockObserverSession handleLockStateChanged];
        }
    });
}

@implementation PXLongShotSession

+ (instancetype)startWithTask:(PXCaptureTask *)task displayRect:(CGRect)displayRect
                     delegate:(id<PXLongShotSessionDelegate>)delegate {
    NSParameterAssert([NSThread isMainThread]);
    PXLongShotSession *session = [[self alloc] init];
    session.task = task;
    session.displayRect = displayRect;
    session.delegate = delegate;
    session.provider = [[PXCaptureProvider alloc] init];
    session.scroller = [[PXLongShotScroller alloc] init];
    session.cancellation = [[PXLongShotCancellation alloc] init];
    session.slices = [[NSMutableArray alloc] init];
    task.baseImage = nil; // 选区已确认，不再驻留选区界面的整屏底图。
    [session pxShowWindow];
    // 协调器先保存会话引用，再允许失败/完成回调，防止同步回调早于赋值。
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![session pxIsTaskPresenting]) return;
        PXLongShotScrollPlan plan;
        if (session.scroller.availabilityError) {
            [session pxFail:session.scroller.availabilityError];
        } else if (!PXLongShotBuildScrollPlan(displayRect, task.capturedScreenBounds,
                                              session.hud.scrollProtectedBottomY, &plan)) {
            [session pxFail:@"选区可滚动高度不足，请选择更大的内容区域"];
        } else {
            session.autoRunning = YES;
            PXLogInfo(@"long shot automatic capture started (task %@)", task.taskID);
            [session pxStartCapture]; // 首段在滚动前采集，不能丢掉当前页面顶部。
        }
    });
    return session;
}

- (BOOL)isFinished { return self.finished; }

- (void)pxShowWindow {
    self.window = [PXCaptureWindow pxCaptureWindow];
    self.window.passesTouchesOutsideHostedContent = YES;
    self.hud = [[PXLongShotHUD alloc] initWithFrame:self.window.bounds];
    self.hud.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.hud.delegate = self;
    [self.window hostContentView:self.hud];
    [self.window showAnimated:NO becomeKey:NO];
    atomic_fetch_add(&PXLongShotLockGeneration, 1);
    _PXLongShotLockObserverSession = self;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    PXLongShotLockStateCallback, PXLongShotLockStateName, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

#pragma mark - 自动滚动与结束请求（只在主线程推进）

- (void)pxScheduleNextScroll {
    if (![self pxIsTaskPresenting]) return;
    if (self.finishRequested) { [self pxStartStitch]; return; }
    if (!self.autoRunning) return;
    if (self.slices.count >= PXLongShotMaxSlices) {
        [self pxPause:@"已达最大段数，点「完成」保存长图"];
        return;
    }
    self.hud.statusText = @"自动滚动截取中，点「完成」停止";
    NSUInteger generation = ++self.scheduleGeneration;
    __weak PXLongShotSession *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PXLongShotSession *session = weakSelf;
        if (!session || generation != session.scheduleGeneration || ![session pxIsTaskPresenting] ||
            !session.autoRunning || session.finishRequested) return;
        [session pxScroll];
    });
}

- (void)pxScroll {
    if (self.busy || self.scrolling || self.settling || ![self pxIsTaskPresenting]) return;
    if (![self.scroller targetApplicationIsCurrent]) { [self pxPause:@"前台页面已变化，点「完成」保存已截内容"]; return; }
    PXLongShotScrollPlan plan;
    if (!PXLongShotBuildScrollPlan(self.displayRect, self.task.capturedScreenBounds,
                                   self.hud.scrollProtectedBottomY, &plan)) {
        [self pxPause:@"当前选区无法自动滚动，点「完成」保存已截内容"];
        return;
    }
    self.scrolling = YES;
    [self.hud setScrolling:YES]; // 避免右侧预览拦住注入路径；完成/取消始终可触摸。
    __weak PXLongShotSession *weakSelf = self;
    [self.scroller scrollWithPlan:plan completion:^(BOOL completed) {
        PXLongShotSession *session = weakSelf;
        if (!session || ![session pxIsTaskPresenting]) return;
        session.scrolling = NO;
        [session.hud setScrolling:NO];
        if (![session.scroller targetApplicationIsCurrent]) {
            [session pxPause:@"前台页面已变化，点「完成」保存已截内容"];
        } else if (completed || session.finishRequested) {
            [session pxWaitThenCapture];
        } else {
            [session pxPause:@"自动滚动失败，点「完成」保存已截内容"];
        }
    }];
}

- (void)pxWaitThenCapture {
    self.settling = YES;
    NSUInteger generation = ++self.scheduleGeneration;
    __weak PXLongShotSession *weakSelf = self;
    // 抬指后等动画与合成器稳定；完成请求不跳过这次末段抓取。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PXLongShotSession *session = weakSelf;
        if (!session || generation != session.scheduleGeneration || ![session pxIsTaskPresenting]) return;
        session.settling = NO;
        [session pxStartCapture];
    });
}

- (void)longShotHUDDidTapFinish:(UIView *)hud {
    if (self.finishRequested || ![self pxIsTaskPresenting]) return;
    self.finishRequested = YES;
    self.autoRunning = NO;
    [self.hud setFinishing:YES];
    self.hud.statusText = @"正在停止滚动并收齐当前段…";
    PXLogInfo(@"long shot stop requested (task %@, scrolling=%d busy=%d)",
              self.task.taskID, self.scrolling, self.busy);
    if (self.scrolling) {
        [self.scroller cancel]; // 同步抬指，回调转入等待/末段抓取。
    } else if (!self.busy && !self.settling) {
        self.scheduleGeneration++;
        [self pxStartStitch];
    }
}

- (void)longShotHUDDidTapCancel:(UIView *)hud {
    if (self.finished) return;
    id<PXLongShotSessionDelegate> delegate = self.delegate;
    PXLogInfo(@"long shot cancelled (task %@)", self.task.taskID);
    [self pxTeardown];
    [delegate longShotSessionDidCancel:self];
}

- (void)handleLockStateChanged {
    if (self.finished) return;
    // 锁屏通知也可能在解锁时到达；活跃自动会话统一取消，不恢复注入。
    [self longShotHUDDidTapCancel:self.hud];
}

- (void)pxPause:(NSString *)message {
    self.autoRunning = NO;
    self.scheduleGeneration++;
    self.settling = NO;
    self.busy = NO;
    self.capturePending = NO;
    self.captureGeneration++;
    self.window.hidden = NO;
    [self.hud setScrolling:NO];
    if (self.slices.count == 0) { [self pxFail:message]; return; }
    PXLogWarn(@"long shot automatic capture stopped (task %@): %@", self.task.taskID, message);
    if (self.finishRequested) [self pxStartStitch];
    else self.hud.statusText = message;
}

#pragma mark - 自动截取

- (void)pxStartCapture {
    if (self.busy || self.scrolling || self.finished || ![self pxIsTaskPresenting]) return;
    if (![self.scroller targetApplicationIsCurrent]) { [self pxPause:@"前台页面已变化，点「完成」保存已截内容"]; return; }
    self.busy = YES;
    self.capturePending = YES;
    NSUInteger generation = ++self.captureGeneration;
    self.hud.statusText = self.finishRequested ? @"正在截取最后一段…" : @"自动截取中…";
    self.window.hidden = YES;
    __weak PXLongShotSession *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PXLongShotSession *session = weakSelf;
        if (!session || ![session pxIsTaskPresenting] || !session.capturePending || generation != session.captureGeneration) return;
        [session pxPause:@"抓屏超时，已停止自动滚动，点「完成」保存已截内容"];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 / 60.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PXLongShotSession *session = weakSelf;
        if (!session || ![session pxIsTaskPresenting] || generation != session.captureGeneration) return;
        if (![session.scroller targetApplicationIsCurrent]) { [session pxPause:@"前台页面已变化，点「完成」保存已截内容"]; return; }
        @try {
            [session.provider captureWithCompletion:^(UIImage *image, BOOL partial, NSString *method, NSError *error) {
                PXLongShotSession *current = weakSelf;
                if (!current || ![current pxIsTaskPresenting] || generation != current.captureGeneration) return;
                current.capturePending = NO;
                current.window.hidden = NO;
                if (![current.scroller targetApplicationIsCurrent]) {
                    [current pxPause:@"前台页面已变化，点「完成」保存已截内容"];
                } else if (!image || partial) {
                    PXLogWarn(@"long shot capture failed (task %@, method=%@ partial=%d): %@",
                              current.task.taskID, method, partial, error.localizedDescription ?: @"unavailable");
                    [current pxPause:@"无法取得完整页面，已停止自动滚动"];
                } else {
                    [current pxProcessImage:image];
                }
            }];
        } @catch (NSException *exception) {
            PXLogWarn(@"long shot capture exception (task %@): %@", session.task.taskID, exception.name);
            [session pxPause:@"抓屏接口异常，已停止自动滚动"];
        }
    });
}

- (void)pxProcessImage:(UIImage *)image {
    CGSize pixels = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
    CGRect rect = PXConvertDisplayRectToPixel(self.displayRect, self.task.capturedScreenBounds.size, pixels);
    if (CGRectIsEmpty(rect)) { [self pxPause:@"截取区域无效，请重新选择"]; return; }
    NSString *directory = [self.task ensureTemporaryDirectory];
    if (directory.length == 0) { [self pxPause:@"临时目录创建失败"]; return; }
    NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"longslice_%03lu.jpg", (unsigned long)self.slices.count]];
    PXLongShotSlice *prev = self.slices.lastObject;
    PXLongShotCancellation *cancellation = self.cancellation;
    __weak PXLongShotSession *weakSelf = self;
    dispatch_async(PXLongShotImageQueue(), ^{
        @autoreleasepool {
            if (cancellation.cancelled) return;
            NSError *error = nil;
            PXLongShotSlice *slice = [PXLongImageComposer sliceFromScreenImage:image pixelRect:rect
                                                                       filePath:path cancellation:cancellation error:&error];
            NSInteger overlap = 0;
            BOOL duplicate = NO;
            if (slice && prev && !cancellation.cancelled) {
                duplicate = PXLongShotSignaturesAreDuplicate(prev.rowSignatures.bytes, prev.pixelHeight,
                                                             slice.rowSignatures.bytes, slice.pixelHeight);
                if (!duplicate) {
                    overlap = PXLongShotSearchOverlap(prev.rowSignatures.bytes, prev.pixelHeight,
                                                      slice.rowSignatures.bytes, slice.pixelHeight, MIN(slice.pixelHeight, 128));
                    // 固定页头可能给出近整片匹配；整片已经确认不同，不能因此丢掉真实新内容。
                    if (PXLongShotIsDuplicateOverlap(overlap, slice.pixelHeight)) overlap = 0;
                }
                if (duplicate) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
            }
            if (cancellation.cancelled) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                PXLongShotSession *session = weakSelf;
                if (!session || ![session pxIsTaskPresenting]) return;
                if (!slice) { [session pxPause:@"分片处理失败，已停止自动滚动"]; return; }
                if (duplicate) {
                    session.busy = NO;
                    session.duplicateCount++;
                    if (session.finishRequested) [session pxStartStitch];
                    else if (session.duplicateCount >= 2) [session pxPause:@"页面未继续滚动，点「完成」保存长图"];
                    else [session pxScheduleNextScroll];
                    return;
                }
                session.duplicateCount = 0;
                slice.overlapRows = overlap;
                [session.slices addObject:slice];
                [session.hud setSliceCount:(NSInteger)session.slices.count];
                PXLogInfo(@"long shot slice appended (task %@, count=%lu overlap=%ld)",
                          session.task.taskID, (unsigned long)session.slices.count, (long)overlap);
                [session pxUpdatePreview:slice];
            });
        }
    });
}

- (void)pxUpdatePreview:(PXLongShotSlice *)slice {
    if (!self.previewCanvas) {
        CGFloat uiScale = self.task.capturedScreenScale > 0 ? self.task.capturedScreenScale : 1.0;
        self.previewCanvas = [[PXLongPreviewCanvas alloc] initWithWidthPixels:(NSInteger)(PXLongShotHUDPreviewWidthPt * uiScale)
                                                                   maxPixels:2000000 uiScale:uiScale cancellation:self.cancellation];
    }
    PXLongPreviewCanvas *canvas = self.previewCanvas;
    if (canvas.saturated) { self.busy = NO; [self pxScheduleNextScroll]; return; }
    PXLongShotCancellation *cancellation = self.cancellation;
    __weak PXLongShotSession *weakSelf = self;
    dispatch_async(PXLongShotImageQueue(), ^{
        @autoreleasepool {
            if (cancellation.cancelled) return;
            UIImage *image = [canvas appendSliceFile:slice.filePath pixelWidth:slice.pixelWidth
                                        pixelHeight:slice.pixelHeight overlapRows:slice.overlapRows];
            NSInteger height = canvas.usedPixelHeight;
            dispatch_async(dispatch_get_main_queue(), ^{
                PXLongShotSession *session = weakSelf;
                if (!session || ![session pxIsTaskPresenting]) return;
                session.busy = NO;
                if (image) [session.hud setPreviewImage:image usedPixelHeight:height];
                else PXLogWarn(@"long shot preview stopped (task %@)", session.task.taskID);
                [session pxScheduleNextScroll];
            });
        }
    });
}

#pragma mark - 拼接（完成键只发停止请求，当前分片完成后才进入这里）

- (void)pxStartStitch {
    if (self.busy || self.scrolling || self.settling || ![self pxIsTaskPresenting]) return;
    if (self.slices.count == 0) { [self pxFail:@"没有可保存的长截图内容"]; return; }
    self.busy = YES;
    self.autoRunning = NO;
    self.finishRequested = YES;
    self.scheduleGeneration++;
    [self.hud setFinishing:YES];
    self.hud.statusText = @"长图拼接中…";
    NSString *directory = [self.task ensureTemporaryDirectory];
    if (directory.length == 0) { [self pxFail:@"临时目录创建失败"]; return; }
    NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"longshot.jpg"]];
    NSArray<PXLongShotSlice *> *slices = [self.slices copy];
    CGFloat screenScale = self.task.capturedScreenScale;
    PXLongShotCancellation *cancellation = self.cancellation;
    __weak PXLongShotSession *weakSelf = self;
    dispatch_async(PXLongShotImageQueue(), ^{
        @autoreleasepool {
            if (cancellation.cancelled) return;
            CGSize size = CGSizeZero;
            NSError *error = nil;
            UIImage *image = [PXLongImageComposer composedImageWithSlices:slices screenScale:screenScale
                                                                outputURL:url cancellation:cancellation
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
                [session pxTeardown];
                [delegate longShotSessionDidFinish:session resultImage:image];
            });
        }
    });
}

- (void)pxFail:(NSString *)message {
    if (self.finished) return;
    PXLogWarn(@"long shot failed (task %@): %@", self.task.taskID, message);
    id<PXLongShotSessionDelegate> delegate = self.delegate;
    [self pxTeardown];
    [delegate longShotSessionDidFail:self message:message];
}

- (void)teardownForExternalCancel {
    if (NSThread.isMainThread) [self pxTeardown];
    else dispatch_async(dispatch_get_main_queue(), ^{ [self pxTeardown]; });
}

- (void)pxTeardown {
    if (self.finished) return;
    self.finished = YES; // 必须先置位，scroller.cancel 的同步回调不得再启动末段抓取。
    self.cancellation.cancelled = YES;
    self.scheduleGeneration++;
    self.captureGeneration++;
    [self.scroller cancel];
    self.scroller = nil;
    atomic_fetch_add(&PXLongShotLockGeneration, 1); // 旧通知的主线程回调不得取消下一次会话。
    _PXLongShotLockObserverSession = nil;
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PXLongShotLockStateName, NULL);
    self.hud.delegate = nil;
    self.hud = nil;
    [self.window hideAndDestroyWithCompletion:nil];
    self.window = nil;
    self.slices = nil;
    self.previewCanvas = nil;
    self.task = nil;
    self.delegate = nil;
}

- (BOOL)pxIsTaskPresenting {
    return !self.finished && self.task && self.task.currentState == PXCaptureStatePresenting;
}

@end
