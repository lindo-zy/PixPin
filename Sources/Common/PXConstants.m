#import "PXConstants.h"

NSString * const PXBundleID = @"com.pixpin.screenshot";
NSString * const PXPreferencesDomain = @"com.pixpin.screenshot";

NSString * const PXExternalURLScheme = @"pixpin";
CFStringRef const PXDarwinActivate = CFSTR("com.pixpin.screenshot/activate");
CFStringRef const PXDarwinCaptureFull = CFSTR("com.pixpin.screenshot/capture/full");
CFStringRef const PXDarwinCaptureArea = CFSTR("com.pixpin.screenshot/capture/area");
CFStringRef const PXDarwinCaptureFreeze = CFSTR("com.pixpin.screenshot/capture/freeze");
CFStringRef const PXDarwinCaptureInstant = CFSTR("com.pixpin.screenshot/capture/instant");
CFStringRef const PXDarwinCaptureMarkup = CFSTR("com.pixpin.screenshot/capture/markup");
CFStringRef const PXDarwinCaptureLong = CFSTR("com.pixpin.screenshot/capture/long");
CFStringRef const PXDarwinCaptureCancel = CFSTR("com.pixpin.screenshot/capture/cancel");
CFStringRef const PXDarwinPreferencesReload = CFSTR("com.pixpin.screenshot/preferences/reload");

CFStringRef const PXDarwinSnapperForceOpen = CFSTR("com.jontelang.snapper3.force.open");
CFStringRef const PXDarwinSnapperForceInstantOpen = CFSTR("com.jontelang.snapper3.forceinstant.open");
CFStringRef const PXDarwinSnapperForceFreezeOpen = CFSTR("com.jontelang.snapper3.forcefreeze.open");
CFStringRef const PXDarwinSnapperCloseAll = CFSTR("com.jontelang.snapper3.close.all");
CFStringRef const PXDarwinSnapperCloseCrop = CFSTR("com.jontelang.snapper3.closecrop");

CFStringRef const PXDarwinShellXOpen = CFSTR("com.iosdump.screenshotshell.open");
CFStringRef const PXDarwinShellXOpenInstant = CFSTR("com.iosdump.screenshotshell.open.instant");
CFStringRef const PXDarwinShellXOpenFreeze = CFSTR("com.iosdump.screenshotshell.open.freeze");
CFStringRef const PXDarwinShellXClose = CFSTR("com.iosdump.screenshotshell.close");

CFStringRef const PXShellXTriggerArea = CFSTR("com.iosdump.screenshotshell.open");
CFStringRef const PXShellXTriggerInstant = CFSTR("com.iosdump.screenshotshell.open.instant");
CFStringRef const PXShellXTriggerFreeze = CFSTR("com.iosdump.screenshotshell.open.freeze");
CFStringRef const PXShellXTriggerHistory = CFSTR("com.iosdump.screenshotshell.history");
CFStringRef const PXShellXTriggerOpenLast = CFSTR("com.iosdump.screenshotshell.openlast");
CFStringRef const PXShellXTriggerClose = CFSTR("com.iosdump.screenshotshell.close");
CFStringRef const PXShellXTriggerAssistive = CFSTR("com.iosdump.screenshotshell/AssistiveScreenshot");

CFStringRef const PXShellXRouteLong = CFSTR("prefs://root=shellx_long");
CFStringRef const PXShellXRouteFull = CFSTR("prefs://root=shellx_full");
CFStringRef const PXShellXRouteMark = CFSTR("prefs://root=shellx_mark");
CFStringRef const PXShellXRouteEdit = CFSTR("prefs://root=shellx_edit");
CFStringRef const PXShellXRouteAI2 = CFSTR("prefs://root=shellx_ai2");
CFStringRef const PXShellXRouteTranslate = CFSTR("prefs://root=shellx_translate");
CFStringRef const PXShellXRouteScan = CFSTR("prefs://root=shellx_scan");

NSString * const PXNotificationResultUpdated = @"com.pixpin.screenshot/result/updated";

NSString * const PXKeyEnabled = @"Enabled";
NSString * const PXKeyDefaultResultAction = @"DefaultResultAction";
// 保存同时复制：任何保存动作同时写入剪贴板（默认开）。
NSString * const PXKeySaveAlsoCopy = @"SaveAlsoCopy";
NSString * const PXKeyAutoSaveToPhotos = @"AutoSaveToPhotos";
NSString * const PXKeyCopyToClipboard = @"CopyToClipboard";
NSString * const PXKeyShowResultBubble = @"ShowResultBubble";
NSString * const PXKeyFloatingSnapShadow = @"FloatingSnapShadow";
// 选区边缘吸附距离：0=关闭，拖动选框时边距屏幕边缘不超过该值即对齐边缘。
NSString * const PXKeySelectionSnapEdgeDistance = @"SelectionSnapEdgeDistance";
NSString * const PXKeyShowCompletionNotification = @"ShowCompletionNotification";
NSString * const PXKeyMuteScreenshotSound = @"MuteScreenshotSound";
NSString * const PXKeyScreenshotHaptic = @"ScreenshotHaptic";
NSString * const PXKeyEditorDefaultColor = @"EditorDefaultColor";
NSString * const PXKeyEditorDefaultLineWidth = @"EditorDefaultLineWidth";
NSString * const PXKeyEditorActionOrder = @"EditorActionOrder";
NSString * const PXKeyEditorToolOrder = @"EditorToolOrder";
NSString * const PXKeyEditorActionHidden = @"EditorActionHidden";
NSString * const PXKeyEditorToolHidden = @"EditorToolHidden";
NSString * const PXKeyEditorActionNames = @"EditorActionNames";
NSString * const PXKeyEditorToolNames = @"EditorToolNames";
NSString * const PXKeyEditorActionIcons = @"EditorActionIcons";
NSString * const PXKeyEditorToolIcons = @"EditorToolIcons";
NSString * const PXKeyEditorButtonIconSize = @"EditorButtonIconSize";
NSString * const PXKeySelectionButtonOrder = @"SelectionButtonOrder";
NSString * const PXKeySelectionButtonHidden = @"SelectionButtonHidden";
NSString * const PXKeySelectionButtonNames = @"SelectionButtonNames";
NSString * const PXKeySelectionButtonIcons = @"SelectionButtonIcons";
NSString * const PXKeySelectionButtonIconStyle = @"SelectionButtonIconStyle";
// 自定义 URL 按钮：行记录 CSV，行间 \n、字段间逗号（id,name,icon,url）；由 PXEditorOrder 解析。
NSString * const PXKeySelectionCustomButtons = @"SelectionCustomButtons";
NSString * const PXKeyAreaRememberLastRect = @"AreaRememberLastRect";
// 选区矩形以 NSStringFromCGRect 存储；与开关独立，关开关时清除。
NSString * const PXKeyAreaLastSelectionRect = @"AreaLastSelectionRect";
// 全屏标记收起把手位置以 NSStringFromCGPoint 存储；无开关，始终记忆。
NSString * const PXKeyMarkupHandleOrigin = @"MarkupHandleOrigin";
NSString * const PXKeyLongShotMode = @"LongShotMode";
NSString * const PXKeyLongShotAutoScroll = @"LongShotAutoScroll";
NSString * const PXKeyLongShotSampleInterval = @"LongShotSampleInterval";
NSString * const PXKeyLongShotIdleInterval = @"LongShotIdleInterval";
NSString * const PXKeyLongShotScrollDuration = @"LongShotScrollDuration";
NSString * const PXKeyLongShotSettleDuration = @"LongShotSettleDuration";
NSString * const PXKeyLongShotMaxSlices = @"LongShotMaxSlices";
NSString * const PXKeyLongShotMaxCanvasHeight = @"LongShotMaxCanvasHeight";
NSString * const PXKeyLongShotSliceQuality = @"LongShotSliceQuality";
NSString * const PXKeyLongShotOutputQuality = @"LongShotOutputQuality";

const NSInteger PXDefaultResultAction = 0;
const CGFloat PXDefaultEditorLineWidth = 4.0;

static NSString *PXCreateDirectoryIfNeeded(NSString *path, NSError **error) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:path
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:error]) {
            return nil;
        }
    }
    return path;
}

NSString *PXTemporaryTasksRoot(void) {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"PixPinTasks"];
        path = PXCreateDirectoryIfNeeded(root, nil) ?: [NSTemporaryDirectory() stringByAppendingPathComponent:@"PixPinTasks"];
    });
    return path;
}
