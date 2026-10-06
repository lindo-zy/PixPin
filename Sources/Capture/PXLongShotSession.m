#import "PXLongShotSession.h"
#import "PXCaptureTask.h"
#import "PXCaptureProvider.h"
#import "PXLongShotScroller.h"
#import "PXLongShotTarget.h"
#import "PXLongShotFrameStore.h"
#import "../Common/PXLog.h"
#import "../Output/PXTemporaryFileStore.h"
#import "../Overlay/PXCaptureWindow.h"
#import "../Overlay/PXLongShotHUD.h"
#import <QuartzCore/QuartzCore.h>
#import <stdatomic.h>

// 一个阶段只有一个在途操作。running 表示用户是否要求继续，finishRequested 优先于 running。
typedef NS_ENUM(NSInteger, PXLongShotPhase) {
    PXLongShotPhaseReady, PXLongShotPhaseCapturing, PXLongShotPhaseProcessing,
    PXLongShotPhaseScrolling, PXLongShotPhaseSettling, PXLongShotPhaseExporting, PXLongShotPhaseFinished
};
static dispatch_queue_t PXLongShotImageQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.pixpin.longshot.frames", DISPATCH_QUEUE_SERIAL); });
    return queue;
}
@interface PXLongShotSession () <PXLongShotHUDDelegate>
@property (nonatomic, strong) PXCaptureTask *task;
@property (nonatomic, copy) NSString *taskID;
@property (nonatomic, weak) id<PXLongShotSessionDelegate> delegate;
@property (nonatomic, copy) NSString *target;
@property (nonatomic, strong) PXCaptureProvider *provider;
@property (nonatomic, strong) PXLongShotScroller *scroller;
@property (nonatomic, strong) PXLongShotCancellation *cancellation;
@property (nonatomic, strong) PXLongShotFrameStore *store;
@property (nonatomic, strong) PXCaptureWindow *window;
@property (nonatomic, strong) PXLongShotHUD *hud;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) id memoryObserver;
@property (nonatomic) PXLongShotMode mode;
@property (nonatomic) PXLongShotPhase phase;
@property (nonatomic) CGRect displayRect;
@property (nonatomic) PXLongShotScrollPlan plan;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSInteger count;
@property (nonatomic) NSInteger duplicates;
@property (nonatomic) NSInteger uncertain;
@property (nonatomic) BOOL running;
@property (nonatomic) BOOL finishRequested;
@property (nonatomic) BOOL terminalPause;
@property (nonatomic) BOOL memoryStopped;
@property (nonatomic) BOOL previewDisabled;
@property (nonatomic) CFTimeInterval nextSample;
- (void)pxCancel;
@end
static __weak PXLongShotSession *PXLockSession;
static atomic_uint_fast64_t PXLockGeneration;
static CFStringRef PXLockName = CFSTR("com.apple.springboard.lockstate");
static void PXLockCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                           const void *object, CFDictionaryRef userInfo) {
    uint_fast64_t generation = atomic_load(&PXLockGeneration);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation == atomic_load(&PXLockGeneration)) [PXLockSession pxCancel];
    });
}
// 会话收尾后的进程内存回收观测：0/5/30/60 秒各记一行 footprint/available（仅 syslog）。
// dispatch_after 只捕获 taskID 字符串与代数，不持有会话，观测自身不延长任务生命周期。
static void PXLongShotLogEndMemory(NSString *taskID, NSUInteger generation, NSInteger seconds) {
    PXLogInfo(@"long shot end memory (task %@ gen=%lu t=%lds footprint=%llu available=%llu)",
              taskID, (unsigned long)generation, (long)seconds,
              (unsigned long long)PXLongShotProcessFootprintBytes(),
              (unsigned long long)PXLongShotAvailableMemoryBytes());
}

static void PXLongShotScheduleEndMemoryLogs(NSString *taskID, NSUInteger generation) {
    static const NSInteger PXEndMemoryDelays[] = {0, 5, 30, 60};
    for (NSUInteger i = 0; i < sizeof(PXEndMemoryDelays) / sizeof(PXEndMemoryDelays[0]); i++) {
        NSInteger delay = PXEndMemoryDelays[i];
        NSString *capturedTaskID = [taskID copy];
        if (delay == 0) {
            PXLongShotLogEndMemory(capturedTaskID, generation, delay);
            continue;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PXLongShotLogEndMemory(capturedTaskID, generation, delay);
        });
    }
}
@implementation PXLongShotSession
+ (instancetype)startWithTask:(PXCaptureTask *)task mode:(PXLongShotMode)mode
                  displayRect:(CGRect)displayRect delegate:(id<PXLongShotSessionDelegate>)delegate {
    NSParameterAssert(NSThread.isMainThread);
    PXLongShotSession *s = [self new];
    s.task = task; s.taskID = task.taskID; s.delegate = delegate; s.mode = mode;
    s.displayRect = displayRect; s.phase = PXLongShotPhaseReady;
    s.target = PXLongShotFrontmostIdentifier(UIApplication.sharedApplication);
    s.provider = [PXCaptureProvider new]; s.provider.detachesCapturedImage = YES;
    s.provider.keepsExcludedWindowsVisible = YES;
    s.cancellation = [PXLongShotCancellation new];
    // 打开框选时的画面可能已过时；只有用户点截取时才建立第一帧。
    task.baseImage = nil;
    s.window = [PXCaptureWindow pxCaptureWindow];
    UIEdgeInsets safe = s.window.windowScene.keyWindow.safeAreaInsets;
    CGRect screen = task.capturedScreenBounds;
    CGFloat width = PXLongShotHUDPreviewWidthPt + 24;
    CGFloat height = MIN(278, screen.size.height - safe.top - safe.bottom - 20);
    s.window.frame = CGRectMake(CGRectGetMaxX(screen) - safe.right - width - 12,
                                CGRectGetMinY(screen) + safe.top + 10, width, height);
    s.window.windowLevel = UIWindowLevelStatusBar;
    s.window.passesTouchesOutsideHostedContent = YES;
    s.hud = [[PXLongShotHUD alloc] initWithFrame:s.window.bounds]; s.hud.delegate = s;
    [s.window hostContentView:s.hud];
    s.window.rootViewController.view.frame = s.window.bounds; s.hud.frame = s.window.bounds;
    [s.hud setModeTitle:mode == PXLongShotModeAutomatic ? @"自动拼接" :
                        mode == PXLongShotModeSmart ? @"智能拼接" : @"采样拼接"];
    [s.window showAnimated:NO becomeKey:NO];
    [s pxShowReady:@"点「截取」开始"];
    atomic_fetch_add(&PXLockGeneration, 1); PXLockSession = s;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PXLockCallback,
                                    PXLockName, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    __weak PXLongShotSession *weak = s;
    s.memoryObserver = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [weak pxMemoryWarning]; }];
    s.timer = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) { [weak pxTick]; }];
    [NSRunLoop.mainRunLoop addTimer:s.timer forMode:NSRunLoopCommonModes];
    PXLogInfo(@"long shot ready (task %@ mode=%ld rect=%@)", s.taskID, (long)mode, NSStringFromCGRect(displayRect));
    return s;
}
- (BOOL)isFinished { return self.phase == PXLongShotPhaseFinished; }
- (BOOL)pxLive {
    return !self.isFinished && !self.cancellation.cancelled && self.task.currentState == PXCaptureStatePresenting &&
           [self.taskID isEqual:self.task.taskID];
}
- (BOOL)pxTargetCurrent {
    return PXLongShotTargetIsCurrent(UIApplication.sharedApplication, PXLongShotLockManager(), self.target);
}
- (void)pxSetPhase:(PXLongShotPhase)phase {
    self.phase = phase;
    BOOL active = self.running && self.mode != PXLongShotModeSmart;
    BOOL enabled = !self.finishRequested && !self.terminalPause && !self.memoryStopped &&
                   (phase == PXLongShotPhaseReady || active);
    NSString *title = active ? @"暂停" : (self.count && self.mode != PXLongShotModeSmart ? @"继续" : @"截取");
    [self.hud setCaptureTitle:title enabled:enabled];
    [self.hud setFinishing:self.finishRequested || phase == PXLongShotPhaseExporting];
}
- (void)pxShowReady:(NSString *)message {
    [self pxSetPhase:PXLongShotPhaseReady]; self.hud.statusText = message;
}
- (void)pxTick {
    if (![self pxLive] || self.phase == PXLongShotPhaseExporting) return;
    if (![self pxTargetCurrent]) {
        if (!self.terminalPause) [self pxStop:@"前台 App 已变化\n点完成保存" terminal:YES];
        return;
    }
    if (self.running && self.mode == PXLongShotModeAutomatic && self.hud.isPreviewInteracting) {
        self.running = NO;
        [self pxSetPhase:self.phase]; self.hud.statusText = @"预览时暂停\n点继续恢复";
    }
    if (self.running && self.phase == PXLongShotPhaseReady && self.mode == PXLongShotModeSampling &&
        CACurrentMediaTime() >= self.nextSample && !self.hud.isPreviewInteracting) [self pxCapture];
}
- (void)longShotHUDDidTapCapture:(UIView *)hud {
    if (![self pxLive] || self.finishRequested || self.terminalPause || self.memoryStopped) return;
    if (self.running && self.mode != PXLongShotModeSmart) {
        self.running = NO;
        // 在途帧完成后停；不强行取消写盘或中途抬指导致漏段。
        [self pxSetPhase:self.phase]; self.hud.statusText = @"已暂停\n点继续或完成";
        return;
    }
    if (self.phase != PXLongShotPhaseReady) return;
    if (![self pxTargetCurrent]) { [self pxStop:@"请返回原 App\n点完成保存" terminal:YES]; return; }
    if (self.mode != PXLongShotModeSampling && !self.scroller) {
        self.scroller = [PXLongShotScroller new];
        if (self.scroller.availabilityError || !PXLongShotBuildScrollPlan(self.displayRect,
                self.task.capturedScreenBounds, self.window.frame, &_plan)) {
            [self pxStop:self.scroller.availabilityError ?: @"选区无法短滑\n请扩大正文区域" terminal:YES]; return;
        }
    }
    self.running = YES; self.duplicates = self.uncertain = 0;
    [self pxCapture];
}
- (void)pxStop:(NSString *)message terminal:(BOOL)terminal {
    if (![self pxLive] || self.phase == PXLongShotPhaseExporting) return;
    self.running = NO; self.terminalPause |= terminal;
    [self pxSetPhase:self.phase]; self.hud.statusText = message;
    PXLogWarn(@"long shot paused (task %@ phase=%ld count=%ld terminal=%d): %@",
              self.taskID, (long)self.phase, (long)self.count, terminal, message);
    if (self.finishRequested && self.phase == PXLongShotPhaseReady) [self pxExport];
}
- (BOOL)pxHasMemory {
    size_t available = PXLongShotAvailableMemoryBytes();
    return !available || available >= PXLongShotMemoryFloorBytes();
}
- (void)pxMemoryWarning {
    if (![self pxLive]) return;
    self.previewDisabled = YES; [self.hud setPreviewImage:nil usedPixelHeight:0];
    PXLongShotFrameStore *store = self.store;
    dispatch_async(PXLongShotImageQueue(), ^{ [store discardPreview]; });
    if (self.phase == PXLongShotPhaseExporting) return;
    // 不在资源不足时重抓末帧；已有内容由正在执行的操作释放后导出。
    // 可见浮窗不能回退到普通整屏抓取；内存警告时停止新快照，收尾已有帧。
    [self pxFinishForMemory];
}
- (void)pxFinishForMemory {
    self.memoryStopped = YES; self.finishRequested = YES; self.running = NO;
    [self pxSetPhase:self.phase]; self.hud.statusText = @"内存紧张\n保存已截内容";
    if (self.phase == PXLongShotPhaseReady) [self pxExport];
}
- (void)pxCapture {
    if (![self pxLive] || self.phase != PXLongShotPhaseReady) return;
    if (self.memoryStopped || self.terminalPause) { if (self.finishRequested) [self pxExport]; return; }
    if (![self pxTargetCurrent]) { [self pxStop:@"前台 App 已变化\n点完成保存" terminal:YES]; return; }
    if (![self pxHasMemory]) { [self pxFinishForMemory]; return; }
    if (!self.store) {
        NSString *directory = [self.task ensureTemporaryDirectory];
        if (!directory.length) { [self pxFail:@"临时目录创建失败"]; return; }
        self.store = [[PXLongShotFrameStore alloc] initWithDirectory:directory options:self.task.configSnapshot.longShotOptions
                                                    cancellation:self.cancellation scale:self.task.capturedScreenScale];
    }
    [self pxSetPhase:PXLongShotPhaseCapturing]; self.hud.statusText = @"正在截取当前段";
    NSUInteger token = ++self.generation;
    __weak PXLongShotSession *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        PXLongShotSession *s = weak;
        if (![s pxLive] || s.generation != token || s.phase != PXLongShotPhaseCapturing) return;
        s.generation++; // 迟到的抓屏结果不可恢复会话，更不能启动第二次抓屏。
        [s pxSetPhase:PXLongShotPhaseReady];
        [s pxStop:@"抓屏超时\n点完成保存" terminal:YES];
    });
    @try {
        [self.provider captureExcludingWindows:@[self.window] completion:^(UIImage *image, BOOL partial, NSString *method, NSError *error) {
            PXLongShotSession *s = weak;
            if (![s pxLive] || s.generation != token || s.phase != PXLongShotPhaseCapturing) return;
            if (!image || partial || ![s pxTargetCurrent]) {
                [s pxSetPhase:PXLongShotPhaseReady];
                [s pxStop:(!image || partial) ? (error.localizedDescription ?: @"抓屏失败\n点完成保存") :
                          @"前台 App 已变化\n点完成保存" terminal:YES];
                return;
            }
            PXLogInfo(@"long shot capture (task %@ method=%@ generation=%lu)", s.taskID, method, (unsigned long)token);
            [s pxProcess:image token:token];
        }];
    } @catch (__unused NSException *exception) {
        [self pxSetPhase:PXLongShotPhaseReady]; [self pxStop:@"抓屏接口异常\n点完成保存" terminal:YES];
    }
}
- (void)pxProcess:(UIImage *)image token:(NSUInteger)token {
    [self pxSetPhase:PXLongShotPhaseProcessing];
    CGRect rect = PXConvertDisplayRectToPixel(self.displayRect, self.task.capturedScreenBounds.size,
                        CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage)));
    PXLongShotFrameStore *store = self.store;
    __weak PXLongShotSession *weak = self;
    dispatch_async(PXLongShotImageQueue(), ^{
        __block PXLongShotFrameResult *result;
        __block NSError *error;
        @autoreleasepool { result = [store consumeImage:image pixelRect:rect error:&error]; }
        // 下一块作为释放屏障，当前块持有的抓屏对象先离开队列，才采样余量/进入下一步。
        dispatch_async(PXLongShotImageQueue(), ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                PXLongShotSession *s = weak;
                if (![s pxLive] || s.generation != token) return;
                [s pxSetPhase:PXLongShotPhaseReady];
                if (!result) { [s pxStop:error.localizedDescription ?: @"帧处理失败" terminal:YES]; return; }
                s.count = result.count;
                [s.hud setSliceCount:s.count];
                if (result.previewUnavailable) {
                    s.previewDisabled = YES; [s.hud setPreviewImage:nil usedPixelHeight:0];
                }
                if (result.preview && !s.previewDisabled) [s.hud setPreviewImage:result.preview
                                           usedPixelHeight:CGImageGetHeight(result.preview.CGImage)];
                PXLogInfo(@"long shot frame (task %@ mode=%ld kind=%ld count=%ld shift=%ld fixed=%ld/%ld footprint=%llu available=%llu)",
                    s.taskID, (long)s.mode, (long)result.match.kind, (long)s.count, (long)result.match.shiftRows,
                    (long)result.match.fixedTopRows, (long)result.match.fixedBottomRows,
                    (unsigned long long)PXLongShotProcessFootprintBytes(), (unsigned long long)PXLongShotAvailableMemoryBytes());
                [s pxAcceptResult:result];
            });
        });
    });
}
- (void)pxAcceptResult:(PXLongShotFrameResult *)result {
    PXLongShotMatchKind kind = result.match.kind;
    if (self.finishRequested || self.count >= self.task.configSnapshot.longShotOptions.maxSlices) {
        if (self.finishRequested && !self.memoryStopped &&
            (kind == PXLongShotMatchUncertain || kind == PXLongShotMatchReverse)) {
            // 不能把末段丢失伪装成完整成功。用户再次点完成才输出已可靠拼接的部分。
            self.finishRequested = NO;
            [self pxStop:@"末段未拼上\n再点完成存已截" terminal:YES];
            return;
        }
        [self pxExport]; return;
    }
    if (![self pxHasMemory]) { [self pxFinishForMemory]; return; }
    if (self.terminalPause || !self.running) {
        [self pxShowReady:self.terminalPause ? @"采集已停止\n点完成保存" : @"已暂停\n点继续或完成"]; return;
    }
    if (kind == PXLongShotMatchUncertain) {
        self.uncertain++;
        // 自动/智能只允许原地静置重采一次，绝不再前滚或盲目反向回滚。
        if (self.uncertain < 2 && self.mode != PXLongShotModeSampling) { [self pxSettleThenCapture:YES]; return; }
        if (self.mode == PXLongShotModeSampling && self.uncertain < 3) {
            self.nextSample = CACurrentMediaTime() + self.task.configSnapshot.longShotOptions.idleInterval; return;
        }
        [self pxStop:@"未找到可靠重叠\n稍回滑后点截取" terminal:NO]; return;
    }
    self.uncertain = 0;
    if (kind == PXLongShotMatchReverse) {
        [self pxStop:@"画面发生回退\n恢复位置后继续" terminal:NO]; return;
    }
    self.duplicates = kind == PXLongShotMatchDuplicate ? self.duplicates + 1 : 0;
    if (self.mode == PXLongShotModeAutomatic && self.duplicates >= 2) {
        // 至少已有一次可靠推进，再经过两次完整短滑/静置仍无新增内容才自动保存。
        // 从一开始就不滚的页面仍提示检查，不能假报到底。
        if (self.count > 1) {
            PXLogInfo(@"long shot auto finish (task %@ reason=no-progress count=%ld duplicates=%ld)",
                      self.taskID, (long)self.count, (long)self.duplicates);
            [self pxExport];
        } else [self pxStop:@"页面未滚动\n点完成或继续" terminal:NO];
        return;
    }
    if (self.mode == PXLongShotModeSampling) {
        self.nextSample = CACurrentMediaTime() + (self.duplicates ? self.task.configSnapshot.longShotOptions.idleInterval :
                                                                 self.task.configSnapshot.longShotOptions.sampleInterval);
        self.hud.statusText = @"请缓慢上滑页面\n点完成结束"; return;
    }
    [self pxScroll];
}
- (void)pxScroll {
    if (![self pxLive] || !self.running || self.phase != PXLongShotPhaseReady || self.finishRequested) return;
    if (![self pxTargetCurrent]) { [self pxStop:@"前台 App 已变化\n点完成保存" terminal:YES]; return; }
    [self pxSetPhase:PXLongShotPhaseScrolling]; self.hud.statusText = @"短滑到下一段";
    NSUInteger token = self.generation;
    __weak PXLongShotSession *weak = self;
    [self.scroller scrollWithPlan:self.plan duration:self.task.configSnapshot.longShotOptions.scrollDuration completion:^(BOOL completed) {
        PXLongShotSession *s = weak;
        if (![s pxLive] || s.generation != token) return;
        [s pxSetPhase:PXLongShotPhaseReady];
        if (s.memoryStopped || s.terminalPause) { if (s.finishRequested) [s pxExport]; return; }
        if (!completed) { [s pxStop:@"短滑失败\n点完成保存" terminal:YES]; return; }
        [s pxSettleThenCapture:s.mode == PXLongShotModeAutomatic || s.finishRequested];
    }];
}
- (void)pxSettleThenCapture:(BOOL)capture {
    [self pxSetPhase:PXLongShotPhaseSettling]; self.hud.statusText = @"等待画面稳定";
    NSUInteger token = self.generation;
    __weak PXLongShotSession *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.task.configSnapshot.longShotOptions.settleDuration * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
        PXLongShotSession *s = weak;
        if (![s pxLive] || s.generation != token) return;
        [s pxSetPhase:PXLongShotPhaseReady];
        if (s.memoryStopped || s.terminalPause) { if (s.finishRequested) [s pxExport]; return; }
        if (s.finishRequested || (capture && s.running)) { [s pxCapture]; return; }
        s.running = NO;
        [s pxShowReady:s.mode == PXLongShotModeSmart ? @"点截取下一段\n或点完成收尾" : @"已暂停\n点继续或完成"];
    });
}
- (void)longShotHUDDidTapFinish:(UIView *)hud {
    if (![self pxLive] || self.finishRequested) return;
    self.finishRequested = YES; self.running = NO; [self pxSetPhase:self.phase];
    self.hud.statusText = @"收齐当前段后保存";
    if (self.phase == PXLongShotPhaseReady) {
        if (self.terminalPause || self.memoryStopped)
            [self pxExport];
        else [self pxCapture];
    }
    // processing 自行收尾；scrolling/settling 在手势完整结束后收一次尾帧。
}
- (void)pxExport {
    if (![self pxLive] || self.phase != PXLongShotPhaseReady) return;
    if (!self.count) { [self pxFail:@"没有可保存的截图内容"]; return; }
    self.finishRequested = YES; self.running = NO;
    [self pxSetPhase:PXLongShotPhaseExporting]; self.hud.statusText = @"正在拼接长图";
    [self.timer invalidate]; self.timer = nil;
    [self.hud setPreviewImage:nil usedPixelHeight:0];
    NSURL *url = [NSURL fileURLWithPath:[[self.task existingTemporaryDirectory] stringByAppendingPathComponent:@"longshot.jpg"]];
    PXLongShotFrameStore *store = self.store;
    __weak PXLongShotSession *weak = self;
    dispatch_async(PXLongShotImageQueue(), ^{
        @autoreleasepool {
            NSError *error; CGSize size = CGSizeZero;
            UIImage *image = [store exportToURL:url pixelSize:&size progress:^(NSInteger done, NSInteger total) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    PXLongShotSession *s = weak;
                    if ([s pxLive] && s.phase == PXLongShotPhaseExporting)
                        s.hud.statusText = done >= total ? @"正在编码长图" : @"正在拼接长图";
                });
            } error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                PXLongShotSession *s = weak;
                if (![s pxLive]) return;
                if (!image) { [s pxFail:error.localizedDescription ?: @"长图导出失败"]; return; }
                PXLogInfo(@"long shot exported (task %@ count=%ld size=%@)", s.taskID, (long)s.count, NSStringFromCGSize(size));
                id<PXLongShotSessionDelegate> delegate = s.delegate;
                [s pxTeardown:NO]; [delegate longShotSessionDidFinish:s resultImage:image];
            });
        }
    });
}
- (void)longShotHUDDidTapCancel:(UIView *)hud { [self pxCancel]; }
- (void)pxCancel {
    if (self.isFinished) return;
    id<PXLongShotSessionDelegate> delegate = self.delegate;
    [self pxTeardown:YES]; [delegate longShotSessionDidCancel:self];
}
- (void)pxFail:(NSString *)message {
    if (self.isFinished) return;
    PXLogWarn(@"long shot failed (task %@): %@", self.taskID, message);
    id<PXLongShotSessionDelegate> delegate = self.delegate;
    [self pxTeardown:YES]; [delegate longShotSessionDidFail:self message:message];
}
- (void)teardownForExternalCancel {
    if (NSThread.isMainThread) [self pxTeardown:YES];
    else dispatch_async(dispatch_get_main_queue(), ^{ [self pxTeardown:YES]; });
}
- (void)pxTeardown:(BOOL)remove {
    if (self.isFinished) return;
    // 在自增前取值：gen 仍与最后一次采集的 generation 日志对应。
    NSString *endTaskID = self.taskID;
    NSUInteger endGeneration = self.generation;
    self.phase = PXLongShotPhaseFinished; self.generation++; self.cancellation.cancelled = YES;
    [self.scroller cancel]; self.scroller = nil;
    [self.timer invalidate]; self.timer = nil;
    if (self.memoryObserver) [NSNotificationCenter.defaultCenter removeObserver:self.memoryObserver];
    self.memoryObserver = nil;
    if (PXLockSession == self) {
        atomic_fetch_add(&PXLockGeneration, 1); PXLockSession = nil;
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PXLockName, NULL);
    }
    [self.provider endVisibleWindowExclusion];
    self.hud.delegate = nil; [self.window hideAndDestroyWithCompletion:nil];
    self.window = nil; self.hud = nil; self.store = nil; self.task = nil; self.delegate = nil;
    if (remove) {
        NSString *taskID = self.taskID;
        dispatch_async(PXLongShotImageQueue(), ^{ [PXTemporaryFileStore removeTaskDirectory:taskID]; });
    }
    // t=0 在资源释放后采样，5/30/60 秒观察进程回收趋势。
    PXLongShotScheduleEndMemoryLogs(endTaskID, endGeneration);
}
@end
