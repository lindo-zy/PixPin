#import "PXConstants.h"

NSString * const PXBundleID = @"com.pixpin.screenshot";
NSString * const PXPreferencesDomain = @"com.pixpin.screenshot";

CFStringRef const PXDarwinCaptureFull = CFSTR("com.pixpin.screenshot/capture/full");
CFStringRef const PXDarwinCaptureArea = CFSTR("com.pixpin.screenshot/capture/area");
CFStringRef const PXDarwinCaptureFreeze = CFSTR("com.pixpin.screenshot/capture/freeze");
CFStringRef const PXDarwinCaptureInstant = CFSTR("com.pixpin.screenshot/capture/instant");
CFStringRef const PXDarwinCaptureCancel = CFSTR("com.pixpin.screenshot/capture/cancel");
CFStringRef const PXDarwinPreferencesReload = CFSTR("com.pixpin.screenshot/preferences/reload");

NSString * const PXNotificationResultUpdated = @"com.pixpin.screenshot/result/updated";

NSString * const PXKeyEnabled = @"Enabled";
NSString * const PXKeyFullscreenEnabled = @"FullscreenEnabled";
NSString * const PXKeyAreaEnabled = @"AreaEnabled";
NSString * const PXKeyFreezeEnabled = @"FreezeEnabled";
NSString * const PXKeyInstantEnabled = @"InstantEnabled";
NSString * const PXKeyDefaultResultAction = @"DefaultResultAction";
NSString * const PXKeyAutoSaveToPhotos = @"AutoSaveToPhotos";
NSString * const PXKeyCopyToClipboard = @"CopyToClipboard";
NSString * const PXKeyShowResultBubble = @"ShowResultBubble";
NSString * const PXKeyShowCompletionNotification = @"ShowCompletionNotification";
NSString * const PXKeyMuteScreenshotSound = @"MuteScreenshotSound";
NSString * const PXKeyScreenshotHaptic = @"ScreenshotHaptic";
NSString * const PXKeyEditorDefaultColor = @"EditorDefaultColor";
NSString * const PXKeyEditorDefaultLineWidth = @"EditorDefaultLineWidth";
NSString * const PXKeyEditorRecentColors = @"EditorRecentColors";

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

NSString *PXLibraryDataDirectory(void) {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Preferences 在 Settings 进程内，截图主逻辑在 SpringBoard 内。如果使用各进程的
        // NSSearchPath，某些系统版本会落到不同容器，导致测试页永远读不到运行状态。
        NSString *mobileHome = NSHomeDirectoryForUser(@"mobile");
        if (mobileHome.length == 0) mobileHome = @"/var/mobile";
        NSString *library = [mobileHome stringByAppendingPathComponent:@"Library"];
        NSString *root = [library stringByAppendingPathComponent:@"PixPin"];
        path = PXCreateDirectoryIfNeeded(root, nil) ?: [NSTemporaryDirectory() stringByAppendingPathComponent:@"PixPin"];
    });
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
