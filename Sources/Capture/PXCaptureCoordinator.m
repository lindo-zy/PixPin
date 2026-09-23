#import "PXCaptureCoordinator.h"
#import "PXCaptureTask.h"
#import "PXCaptureProvider.h"
#import "../Common/PXConstants.h"
#import "../Common/PXLog.h"
#import "../Common/PXPreferences.h"
#import "../Output/PXOutputPipeline.h"
#import "../Output/PXTemporaryFileStore.h"
#import "../Overlay/PXCaptureWindow.h"
#import "../Overlay/PXSelectionView.h"
#import "../Overlay/PXResultBubble.h"
#import "../Editor/PXEditorViewController.h"
#import "../History/PXHistoryStore.h"
#import "../History/PXHistoryItem.h"
#import "../History/PXHistoryViewController.h"
#import "../Common/PXRuntimeStatus.h"

static const CGFloat PXFramesToWaitBeforeCapture = 2.0;

@interface PXCaptureCoordinator () <PXSelectionViewDelegate, PXResultBubbleDelegate,
                                    PXEditorViewControllerDelegate, PXHistoryViewControllerDelegate>
@property (nonatomic, strong) NSLock *taskLock;
@property (nonatomic, strong, nullable) PXCaptureTask *activeTask;      // taskLock 保护
@property (nonatomic, strong) PXCaptureProvider *provider;
@property (nonatomic, strong) PXOutputPipeline *pipeline;
// 以下引用只在主线程读写
@property (nonatomic, strong, nullable) PXCaptureWindow *captureWindow;
@property (nonatomic, strong, nullable) PXSelectionView *selectionView;
@property (nonatomic, strong, nullable) PXResultBubble *resultBubble;
@property (nonatomic, strong, nullable) PXCaptureWindow *editorWindow;
@property (nonatomic, strong, nullable) PXEditorViewController *editorController;
@property (nonatomic, strong, nullable) PXCaptureWindow *historyWindow;
@property (nonatomic, strong, nullable) UIImage *preEditImage;   // 进入编辑器前的结果图（取消编辑时恢复）
@end

static PXCaptureCoordinator *_sharedCoordinator = nil;

@implementation PXCaptureCoordinator

+ (instancetype)sharedCoordinator {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedCoordinator = [[PXCaptureCoordinator alloc] init];
    });
    return _sharedCoordinator;
}

- (instancetype)init {
    if (self = [super init]) {
        _taskLock = [[NSLock alloc] init];
        _provider = [[PXCaptureProvider alloc] init];
        _pipeline = [[PXOutputPipeline alloc] init];

        // 选区期间设备旋转会使基础快照与屏幕几何错位；直接取消任务保证正确性。
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pxOrientationDidChange:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)start {
    // tmp 清扫是纯磁盘 IO：不在 %ctor（主线程）同步执行。
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [PXTemporaryFileStore sweepAllTaskDirectories];
    });
    [PXPreferences config];
    [PXRuntimeStatus reportLoadedWithCaptureMethod:[PXCaptureProvider resolvedCaptureMethod]];
    PXLogInfo(@"coordinator started (capture method %@)", [PXCaptureProvider resolvedCaptureMethod]);
}

#pragma mark - 请求入口

- (void)handleDarwinNotificationName:(NSString *)name {
    if ([name isEqualToString:(__bridge NSString *)PXDarwinPreferencesReload]) {
        [PXPreferences reload];
        return;
    }
    if ([name isEqualToString:(__bridge NSString *)PXDarwinCaptureCancel]) {
        [self cancelActiveTask];
        return;
    }
    if ([name isEqualToString:(__bridge NSString *)PXDarwinHistoryOpen]) {
        [self pxPresentHistory];
        return;
    }

    PXCaptureMode mode = -1;
    if ([name isEqualToString:(__bridge NSString *)PXDarwinCaptureFull]) mode = PXCaptureModeFull;
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinCaptureArea]) mode = PXCaptureModeArea;
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinCaptureFreeze]) mode = PXCaptureModeFreeze;
    else if ([name isEqualToString:(__bridge NSString *)PXDarwinCaptureInstant]) mode = PXCaptureModeInstant;

    if (mode >= PXCaptureModeFull && mode <= PXCaptureModeInstant) {
        [self requestCapture:mode];
    }
}

- (void)requestCapture:(PXCaptureMode)mode {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self requestCapture:mode]; });
        return;
    }

    PXConfig *config = PXPreferences.config;
    if (![PXPreferences modeEnabled:mode config:config]) {
        PXLogInfo(@"mode %@ disabled, request ignored", PXStringFromCaptureMode(mode));
        [PXRuntimeStatus reportRequest:PXStringFromCaptureMode(mode) outcome:@"rejected-disabled"];
        return;
    }

    PXCaptureTask *task = [self pxAcquireTaskForMode:mode config:config];
    if (!task) {
        PXLogWarn(@"request ignored: another task is busy (%@)", PXStringFromCaptureMode(mode));
        [PXRuntimeStatus reportRequest:PXStringFromCaptureMode(mode) outcome:@"rejected-busy"];
        return;
    }

    [PXRuntimeStatus reportRequest:PXStringFromCaptureMode(mode) outcome:@"accepted"];
    [PXRuntimeStatus reportPhase:@"preparing"
                            mode:PXStringFromCaptureMode(mode)
                         message:@"请求已进入 SpringBoard 截图协调器"];

    [self pxRunCaptureForTask:task];
}

- (void)cancelActiveTask {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self cancelActiveTask]; });
        return;
    }

    PXCaptureTask *task = [self pxCurrentTask];
    if (!task) return;

    if (![task transitionToState:PXCaptureStateCancelling]) {
        PXLogWarn(@"cancel ignored for state %@", PXStringFromCaptureState(task.state));
        return;
    }
    [self pxDestroyCaptureWindow];
    [self pxDestroyEditorWindow];
    self.preEditImage = nil;   // 取消后不再持有整图引用（最长可驻留到下次编辑会话）
    [task transitionToState:PXCaptureStateCancelled];
    [PXTemporaryFileStore removeTaskDirectory:task.taskID];
    [self pxClearSlotIfCurrent:task];
    [PXRuntimeStatus reportPhase:@"cancelled"
                            mode:PXStringFromCaptureMode(task.mode)
                         message:@"任务已取消，覆盖窗口已释放"];
    PXLogInfo(@"task cancelled");
}

#pragma mark - 捕获流程

- (void)pxRunCaptureForTask:(PXCaptureTask *)task {
    if (![task transitionToState:PXCaptureStateCapturing]) {
        [self pxFailTask:task code:@"state" message:@"任务状态异常"];
        return;
    }
    [PXRuntimeStatus reportPhase:@"capturing"
                            mode:PXStringFromCaptureMode(task.mode)
                         message:@"正在获取屏幕快照"];

    // 抓屏前隐藏自有覆盖层，并等待两帧，确保合成器不再包含 PixPin 窗口。
    [self pxHideOwnOverlays];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PXFramesToWaitBeforeCapture / 60.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (![self pxIsTaskCurrent:task]) return;
        [self.provider captureWithCompletion:^(UIImage *image, BOOL isPartial, NSString *captureMethod, NSError *error) {
            if (![self pxIsTaskCurrent:task] || task.state != PXCaptureStateCapturing) {
                return;   // 已取消/已被新任务取代
            }
            if (!image) {
                [self pxFailTask:task code:@"capture" message:(error.localizedDescription ?: @"屏幕抓取失败")];
                return;
            }
            task.baseImage = image;
            task.isPartialCapture = isPartial;
            if (isPartial) {
                PXLogWarn(@"capture fell back to partial snapshot path");
            }
            if (![task transitionToState:PXCaptureStateCaptured]) return;
            [PXRuntimeStatus reportPhase:@"captured"
                                    mode:PXStringFromCaptureMode(task.mode)
                                 message:[NSString stringWithFormat:@"已获取 %.0f×%.0f 像素快照（%@）",
                                          image.size.width * image.scale,
                                          image.size.height * image.scale,
                                          captureMethod ?: @"unknown"]];

            if (task.mode == PXCaptureModeFull) {
                [self pxHandleFullscreenResult:task];
            } else {
                [self pxPresentSelectionForTask:task];
            }
        }];
    });
}

- (void)pxHandleFullscreenResult:(PXCaptureTask *)task {
    task.resultImage = task.baseImage;
    if (![task transitionToState:PXCaptureStatePresenting]) return;
    PXOutputAction action = task.configSnapshot.defaultResultAction;
    [self pxExecuteOutput:action forTask:task presentingWindow:nil];
}

- (void)pxPresentSelectionForTask:(PXCaptureTask *)task {
    if (![task transitionToState:PXCaptureStatePresenting]) return;

    [self pxDestroyCaptureWindow];
    PXCaptureWindow *window = [PXCaptureWindow pxCaptureWindow];
    PXSelectionView *view = [[PXSelectionView alloc] initWithFrame:window.bounds
                                                         baseImage:task.baseImage
                                                              mode:task.mode
                                                          delegate:self];
    [window hostContentView:view];
    self.captureWindow = window;
    self.selectionView = view;
    [window showAnimated:(task.mode != PXCaptureModeInstant)];
    [PXRuntimeStatus reportPhase:@"selection-visible"
                            mode:PXStringFromCaptureMode(task.mode)
                         message:[NSString stringWithFormat:@"冻结快照、选区和操作栏已提交显示；%@",
                                  window.hostingDescription]];
    PXLogInfo(@"selection presented (mode %@, task %@)", PXStringFromCaptureMode(task.mode), task.taskID);
}

#pragma mark - 选区回调

- (void)selectionView:(PXSelectionView *)view
   didConfirmDisplayRect:(CGRect)displayRect
                 action:(PXOutputAction)action {
    PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStatePresenting];
    if (!task) return;
    [self pxCropAndOutput:task displayRect:displayRect overrideAction:action];
}

- (void)selectionViewDidCancel:(PXSelectionView *)view {
    [self cancelActiveTask];
}

- (void)selectionViewDidRequestEditor:(PXSelectionView *)view displayRect:(CGRect)displayRect {
    PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStatePresenting];
    if (!task) return;
    [self pxCropInBackground:task displayRect:displayRect completion:^(UIImage *cropped) {
        if (![self pxIsTaskCurrent:task]) return;
        if (!cropped) {
            [self pxFailTask:task code:@"crop" message:@"选区裁剪失败"];
            return;
        }
        task.resultImage = cropped;
        [self pxDestroyCaptureWindow];
        [self pxPresentEditorForTask:task];
    }];
}

- (void)pxCropAndOutput:(PXCaptureTask *)task
             displayRect:(CGRect)displayRect
          overrideAction:(PXOutputAction)overrideAction {
    [self pxDestroyCaptureWindow];

    [self pxCropInBackground:task displayRect:displayRect completion:^(UIImage *cropped) {
        if (![self pxIsTaskCurrent:task]) return;
        if (!cropped) {
            [self pxFailTask:task code:@"crop" message:@"选区裁剪失败"];
            return;
        }
        task.resultImage = cropped;
        PXOutputAction action = (overrideAction == PXOutputActionPreviewOnly)
            ? task.configSnapshot.defaultResultAction
            : overrideAction;
        [self pxExecuteOutput:action forTask:task presentingWindow:nil];
    }];
}

#pragma mark - 裁剪

- (void)pxCropInBackground:(PXCaptureTask *)task
                displayRect:(CGRect)displayRect
                 completion:(void (^)(UIImage *))completion {
    if (!task.baseImage) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    // 只允许使用抓屏时刻的几何快照做换算，不使用实时 bounds。
    CGSize pixelSize = CGSizeMake(task.baseImage.size.width * task.baseImage.scale,
                                  task.baseImage.size.height * task.baseImage.scale);
    CGRect pixelRect = PXConvertDisplayRectToPixel(displayRect, task.capturedScreenBounds.size, pixelSize);
    if (CGRectIsEmpty(pixelRect)) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }

    UIImage *baseImage = task.baseImage;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *cropped = [self pxCropImage:baseImage pixelRect:pixelRect];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(cropped); });
    });
}

- (UIImage *)pxCropImage:(UIImage *)image pixelRect:(CGRect)pixelRect {
    CGImageRef cg = image.CGImage;
    if (!cg) return nil;
    CGImageRef cropped = CGImageCreateWithImageInRect(cg, pixelRect);
    if (!cropped) return nil;
    UIImage *result = [UIImage imageWithCGImage:cropped scale:image.scale orientation:UIImageOrientationUp];
    CGImageRelease(cropped);
    return result;
}

#pragma mark - 输出与收尾

- (void)pxExecuteOutput:(PXOutputAction)action
                 forTask:(PXCaptureTask *)task
        presentingWindow:(UIWindow *)presentingWindow {
    if (![task transitionToState:PXCaptureStateExporting]) {
        PXLogWarn(@"cannot output in state %@", PXStringFromCaptureState(task.state));
        return;
    }
    [PXRuntimeStatus reportPhase:@"exporting"
                            mode:PXStringFromCaptureMode(task.mode)
                         message:PXStringFromOutputAction(action)];
    [self.pipeline performAction:action
                          forTask:task
                presentingWindow:presentingWindow
                      completion:^(BOOL ok, NSString *message) {
        if (![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self pxReportCompletion:task ok:ok message:message]; });
            return;
        }
        [self pxReportCompletion:task ok:ok message:message];
    }];
}

- (void)pxReportCompletion:(PXCaptureTask *)task ok:(BOOL)ok message:(NSString *)message {
    if (![self pxIsTaskCurrent:task]) return;

    [PXRuntimeStatus reportResultOK:ok captureMethod:self.provider.lastCaptureMethod message:message];

    if (ok) {
        [task transitionToState:PXCaptureStateFinished];
        if (task.configSnapshot.screenshotHaptic) {
            UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [haptic impactOccurred];
        }
        [self pxRecordHistoryForTask:task];
        [PXRuntimeStatus reportPhase:@"finished"
                                mode:PXStringFromCaptureMode(task.mode)
                             message:(message ?: @"截图任务已完成")];
    } else {
        // 输出失败：保留临时文件供诊断，失败原因在气泡中显示（重新截图重试）。
        [task transitionToState:PXCaptureStateFailed];
        [task unclaimOutputAction:PXOutputActionSave];
        [task unclaimOutputAction:PXOutputActionCopy];
        [task unclaimOutputAction:PXOutputActionShare];
        PXLogWarn(@"output failed, temp files kept for retry (task %@)", task.taskID);
        [PXRuntimeStatus reportPhase:@"failed"
                                mode:PXStringFromCaptureMode(task.mode)
                             message:(message ?: @"输出失败")];
    }

    if (task.configSnapshot.showResultBubble) {
        // 先同步弹出气泡（即时反馈，也消除“待弹泡窗口期被新截图截入”的竞态），
        // 缩略图后台渲染后回填（P1-4：大图解码不占主线程）。
        CGFloat screenScale = [UIScreen mainScreen].scale;
        UIImage *resultImage = task.resultImage;
        self.resultBubble = [PXResultBubble presentWithImage:nil
                                                     message:(message ?: @"截图完成")
                                                        task:task
                                                   succeeded:ok
                                                    delegate:self];
        PXResultBubble *bubble = self.resultBubble;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                UIImage *thumbnail = [self pxThumbnailForImage:resultImage screenScale:screenScale];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [bubble updateThumbnailImage:thumbnail];
                });
            }
        });
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:PXNotificationResultUpdated object:nil];
    [self pxClearSlotIfCurrent:task];
}

#pragma mark - 历史记录

- (void)pxRecordHistoryForTask:(PXCaptureTask *)task {
    UIImage *image = task.resultImage;
    if (!image) {
        [PXTemporaryFileStore removeTaskDirectory:task.taskID];
        return;
    }

    // 管线保存时已写过 original.jpg 则直接复用（Store 拷贝字节，不再二次编码）；
    // 否则把 UIImage 交给 Store 在后台队列编码。任务临时目录在拷贝完成后清理。
    NSString *directory = [PXTemporaryFileStore directoryForTaskID:task.taskID create:NO];
    NSString *existingPath = [directory stringByAppendingPathComponent:@"original.jpg"];
    BOOL hasFile = [[NSFileManager defaultManager] fileExistsAtPath:existingPath];

    PXHistoryItem *item = [PXHistoryItem itemWithImage:image
                                                  mode:task.mode
                                              isEdited:task.isReeditFromHistory
                               originalAssetIdentifier:task.savedAssetIdentifier];
    item.pixelWidth = (NSInteger)(image.size.width * image.scale);
    item.pixelHeight = (NSInteger)(image.size.height * image.scale);
    item.originalPath = hasFile ? existingPath : nil;

    [[PXHistoryStore sharedStore] addItem:item
                               sourceImage:hasFile ? nil : image
                                limitCount:task.configSnapshot.historyLimit
                                completion:^{
        [PXTemporaryFileStore removeTaskDirectory:task.taskID];
        [[NSNotificationCenter defaultCenter] postNotificationName:PXNotificationHistoryChanged object:nil];
    }];
}

#pragma mark - 编辑器

- (void)pxPresentEditorForTask:(PXCaptureTask *)task {
    if (!task.resultImage) {
        [self pxFailTask:task code:@"editor" message:@"没有可编辑的结果"];
        return;
    }
    if (![task transitionToState:PXCaptureStateEditing]) {
        PXLogWarn(@"cannot enter editing in state %@", PXStringFromCaptureState(task.state));
        return;
    }

    // 取消编辑时恢复到进入编辑器前的结果（不是 baseImage 整屏快照）。
    self.preEditImage = task.resultImage;

    [self pxDestroyEditorWindow];
    PXEditorViewController *editor = [[PXEditorViewController alloc] initWithImage:task.resultImage delegate:self];
    PXCaptureWindow *window = [PXCaptureWindow pxCaptureWindow];
    window.rootViewController = editor;
    self.editorWindow = window;
    self.editorController = editor;
    [window showAnimated:NO];
}

/// 历史重编辑/气泡重编辑入口：以新任务进入编辑器。
- (void)openEditorWithImage:(UIImage *)image mode:(PXCaptureMode)mode {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self openEditorWithImage:image mode:mode]; });
        return;
    }
    PXConfig *config = PXPreferences.config;
    PXCaptureTask *task = [self pxAcquireTaskForMode:mode config:config];
    if (!task) {
        PXLogWarn(@"re-edit ignored: another task is busy");
        return;
    }
    task.isReeditFromHistory = YES;
    [self pxBeginEditorForAcquiredTask:task image:image];
}

/// 任务槽已由调用方占好的编辑器进入路径（历史异步读图完成后也走这里）。
- (void)pxBeginEditorForAcquiredTask:(PXCaptureTask *)task image:(UIImage *)image {
    task.baseImage = image;
    task.resultImage = image;
    [task transitionToState:PXCaptureStateCapturing];
    [task transitionToState:PXCaptureStateCaptured];
    [task transitionToState:PXCaptureStatePresenting];
    [self pxPresentEditorForTask:task];
}

- (void)editorController:(PXEditorViewController *)controller didFinishWithImage:(UIImage *)image {
    PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStateEditing];
    [self pxDestroyEditorWindow];
    self.preEditImage = nil;
    if (!task) return;

    task.resultImage = image;
    if (![task transitionToState:PXCaptureStatePresenting]) return;
    [self pxExecuteOutput:task.configSnapshot.defaultResultAction forTask:task presentingWindow:nil];
}

- (void)editorControllerDidCancel:(PXEditorViewController *)controller {
    PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStateEditing];
    [self pxDestroyEditorWindow];
    if (!task) return;

    // 取消编辑并恢复进入编辑器前的结果（原图未被破坏，DEVELOPMENT.md 5.6）。
    if (self.preEditImage) {
        task.resultImage = self.preEditImage;
    }
    self.preEditImage = nil;
    if (![task transitionToState:PXCaptureStatePresenting]) return;

    if (task.isReeditFromHistory) {
        [self cancelActiveTask];
    } else {
        [self pxExecuteOutput:task.configSnapshot.defaultResultAction forTask:task presentingWindow:nil];
    }
}

- (void)pxDestroyEditorWindow {
    if (self.editorController) {
        [self.editorController.view removeFromSuperview];
        self.editorController = nil;
    }
    if (self.editorWindow) {
        PXCaptureWindow *window = self.editorWindow;
        self.editorWindow = nil;
        [window hideAndDestroyWithCompletion:nil];
    }
}

#pragma mark - 历史查看器

- (void)pxPresentHistory {
    if (self.historyWindow) return;   // 已打开
    if (self.activeTask && PXCaptureStateIsBusy(self.activeTask.state)) {
        PXLogWarn(@"history open ignored: task busy");
        return;
    }

    // 预热历史索引：viewDidLoad 首次 allItems 不再在主线程同步读盘。
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [[PXHistoryStore sharedStore] allItems];
    });

    PXHistoryViewController *viewer = [[PXHistoryViewController alloc] init];
    viewer.delegate = self;
    PXCaptureWindow *window = [PXCaptureWindow pxCaptureWindow];
    window.rootViewController = viewer;
    self.historyWindow = window;
    [window showAnimated:YES];
}

- (void)historyViewControllerDidClose:(PXHistoryViewController *)controller {
    [self pxDestroyHistoryWindow];
}

- (void)historyViewController:(PXHistoryViewController *)controller didRequestReeditOfItem:(PXHistoryItem *)item {
    // 先占任务槽：后台读图期间新截图请求不会插队；失败/取消路径都会释放槽位。
    PXCaptureTask *task = [self pxAcquireTaskForMode:item.mode config:PXPreferences.config];
    if (!task) {
        PXLogWarn(@"re-edit ignored: another task is busy");
        return;
    }
    task.isReeditFromHistory = YES;
    [self pxDestroyHistoryWindow];

    // 整图读盘+解码放后台队列（SpringBoard 主线程禁止大图 IO，DEVELOPMENT.md 0.2）。
    [[PXHistoryStore sharedStore] loadImageForItem:item edited:YES completion:^(UIImage *image) {
        if (![self pxIsTaskCurrent:task]) return;   // 读图期间被取消/取代
        if (!image) {
            [self pxFailTask:task code:@"editor" message:@"历史记录图片读取失败"];
            return;
        }
        [self pxBeginEditorForAcquiredTask:task image:image];
    }];
}

- (void)pxDestroyHistoryWindow {
    if (self.historyWindow) {
        PXCaptureWindow *window = self.historyWindow;
        self.historyWindow = nil;
        [window hideAndDestroyWithCompletion:nil];
    }
}

#pragma mark - 气泡回调

- (void)resultBubbleDidTap:(PXResultBubble *)bubble {
    PXCaptureTask *task = bubble.task;
    UIImage *image = task.resultImage ?: task.baseImage;
    if (!image) return;
    // 编辑图保存为新资源（DEVELOPMENT.md 5.7：原图与编辑图是独立相册资源）。
    [bubble dismissWithCompletion:nil];
    [self openEditorWithImage:image mode:task.mode];
}

- (void)resultBubbleDidDismiss:(PXResultBubble *)bubble {
    // 只清理仍指向该气泡的引用，避免误清新气泡（交叠窗口极短但存在）。
    if (self.resultBubble == bubble) {
        self.resultBubble = nil;
    }
}

#pragma mark - 异常与辅助

- (void)pxOrientationDidChange:(NSNotification *)notification {
    // 选区期间旋转：基础快照与屏幕几何错位，直接取消。
    if (self.selectionView) {
        PXCaptureTask *task = [self pxCurrentTaskIfState:PXCaptureStatePresenting];
        if (task && task.mode != PXCaptureModeFull) {
            PXLogWarn(@"orientation changed during selection, cancelling task");
            [self cancelActiveTask];
        }
        return;
    }
}

- (void)pxFailTask:(PXCaptureTask *)task code:(NSString *)code message:(NSString *)message {
    task.errorCode = code;
    task.errorMessage = message;
    [self pxDestroyCaptureWindow];
    [task transitionToState:PXCaptureStateFailed];
    [PXTemporaryFileStore removeTaskDirectory:task.taskID];
    [PXRuntimeStatus reportResultOK:NO captureMethod:self.provider.lastCaptureMethod
                            message:[NSString stringWithFormat:@"[%@] %@", code, message]];
    [PXRuntimeStatus reportPhase:@"failed"
                            mode:PXStringFromCaptureMode(task.mode)
                         message:[NSString stringWithFormat:@"[%@] %@", code, message]];
    PXLogError(@"task failed [%@]: %@", code, message);
    // 失败气泡不受 ShowResultBubble 控制：失败原因必须可见（诊断优先）。
    self.resultBubble = [PXResultBubble presentWithImage:nil
                                                 message:message
                                                    task:nil
                                               succeeded:NO
                                                delegate:self];
    [self pxClearSlotIfCurrent:task];
}

- (void)pxHideOwnOverlays {
    if (self.resultBubble) {
        [self.resultBubble dismissWithCompletion:nil];
    }
    // 历史窗口没有任务绑定，不销毁会导致其进入后续截图结果。
    [self pxDestroyHistoryWindow];
}

- (void)pxDestroyCaptureWindow {
    if (self.selectionView) {
        [self.selectionView prepareForDismissal];
        self.selectionView = nil;
    }
    if (self.captureWindow) {
        PXCaptureWindow *window = self.captureWindow;
        self.captureWindow = nil;
        [window hideAndDestroyWithCompletion:nil];
    }
}

- (UIImage *)pxThumbnailForImage:(UIImage *)image screenScale:(CGFloat)screenScale {
    if (!image) return nil;
    CGSize target = CGSizeMake(88, 88);
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = screenScale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGFloat scale = MAX(target.width / image.size.width, target.height / image.size.height);
        CGSize drawSize = CGSizeMake(image.size.width * scale, image.size.height * scale);
        CGRect drawRect = CGRectMake((target.width - drawSize.width) / 2,
                                     (target.height - drawSize.height) / 2,
                                     drawSize.width, drawSize.height);
        [image drawInRect:drawRect];
    }];
}

#pragma mark - 任务槽（taskLock 只保护这些临界区）

- (PXCaptureTask *)pxAcquireTaskForMode:(PXCaptureMode)mode config:(PXConfig *)config {
    [self.taskLock lock];
    PXCaptureTask *task = nil;
    if (!self.activeTask || !PXCaptureStateIsBusy(self.activeTask.state)) {
        task = [[PXCaptureTask alloc] initWithMode:mode
                                             config:config
                                       screenBounds:[UIScreen mainScreen].bounds
                                        screenScale:[UIScreen mainScreen].scale];
        [task transitionToState:PXCaptureStatePreparing];
        self.activeTask = task;
    }
    [self.taskLock unlock];
    return task;
}

- (PXCaptureTask *)pxCurrentTask {
    [self.taskLock lock];
    PXCaptureTask *task = self.activeTask;
    [self.taskLock unlock];
    return task;
}

- (PXCaptureTask *)pxCurrentTaskIfState:(PXCaptureState)state {
    [self.taskLock lock];
    PXCaptureTask *task = self.activeTask;
    BOOL match = (task && task.state == state);
    [self.taskLock unlock];
    return match ? task : nil;
}

- (BOOL)pxIsTaskCurrent:(PXCaptureTask *)task {
    [self.taskLock lock];
    BOOL current = (self.activeTask == task);
    [self.taskLock unlock];
    return current;
}

- (void)pxClearSlotIfCurrent:(PXCaptureTask *)task {
    [self.taskLock lock];
    if (self.activeTask == task) {
        self.activeTask = nil;
    }
    [self.taskLock unlock];
}

@end
