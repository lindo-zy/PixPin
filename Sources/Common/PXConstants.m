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

NSString * const PXNotificationResultUpdated = @"com.pixpin.screenshot/result/updated";

NSString * const PXKeyEnabled = @"Enabled";
NSString * const PXKeyDefaultResultAction = @"DefaultResultAction";
NSString * const PXKeyAutoSaveToPhotos = @"AutoSaveToPhotos";
NSString * const PXKeyCopyToClipboard = @"CopyToClipboard";
NSString * const PXKeyShowResultBubble = @"ShowResultBubble";
NSString * const PXKeyFloatingSnapShadow = @"FloatingSnapShadow";
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
NSString * const PXKeyAreaRememberLastRect = @"AreaRememberLastRect";
// 选区矩形以 NSStringFromCGRect 存储；与开关独立，关开关时清除。
NSString * const PXKeyAreaLastSelectionRect = @"AreaLastSelectionRect";
// 全屏标记收起把手位置以 NSStringFromCGPoint 存储；无开关，始终记忆。
NSString * const PXKeyMarkupHandleOrigin = @"MarkupHandleOrigin";

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
