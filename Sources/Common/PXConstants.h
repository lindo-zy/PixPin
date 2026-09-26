#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - 包元数据（唯一命名来源，工程内禁止再硬编码）

/// 主 Bundle ID：com.pixpin.screenshot
FOUNDATION_EXPORT NSString * const PXBundleID;
/// 偏好域：com.pixpin.screenshot
FOUNDATION_EXPORT NSString * const PXPreferencesDomain;

// MARK: - Darwin 跨进程通知名（只发请求信号，不携带图片对象）

FOUNDATION_EXPORT NSString * const PXExternalURLScheme;        // pixpin
FOUNDATION_EXPORT CFStringRef const PXDarwinActivate;          // com.pixpin.screenshot/activate（全屏标记）
FOUNDATION_EXPORT CFStringRef const PXDarwinCaptureFull;        // com.pixpin.screenshot/capture/full
FOUNDATION_EXPORT CFStringRef const PXDarwinCaptureArea;        // com.pixpin.screenshot/capture/area
FOUNDATION_EXPORT CFStringRef const PXDarwinCaptureFreeze;      // com.pixpin.screenshot/capture/freeze
FOUNDATION_EXPORT CFStringRef const PXDarwinCaptureInstant;     // com.pixpin.screenshot/capture/instant
FOUNDATION_EXPORT CFStringRef const PXDarwinCaptureMarkup;      // com.pixpin.screenshot/capture/markup
FOUNDATION_EXPORT CFStringRef const PXDarwinCaptureCancel;      // com.pixpin.screenshot/capture/cancel
FOUNDATION_EXPORT CFStringRef const PXDarwinPreferencesReload;  // com.pixpin.screenshot/preferences/reload

// MARK: - 进程内通知名（同样不携带图片对象，只提示协调器刷新）

FOUNDATION_EXPORT NSString * const PXNotificationResultUpdated; // com.pixpin.screenshot/result/updated

// MARK: - 偏好键（集中定义）

FOUNDATION_EXPORT NSString * const PXKeyEnabled;
FOUNDATION_EXPORT NSString * const PXKeyFullscreenEnabled;
FOUNDATION_EXPORT NSString * const PXKeyAreaEnabled;
FOUNDATION_EXPORT NSString * const PXKeyFreezeEnabled;
FOUNDATION_EXPORT NSString * const PXKeyInstantEnabled;
FOUNDATION_EXPORT NSString * const PXKeyMarkupEnabled;
FOUNDATION_EXPORT NSString * const PXKeyDefaultResultAction;
FOUNDATION_EXPORT NSString * const PXKeyAutoSaveToPhotos;
FOUNDATION_EXPORT NSString * const PXKeyCopyToClipboard;
FOUNDATION_EXPORT NSString * const PXKeyShowResultBubble;
FOUNDATION_EXPORT NSString * const PXKeyShowCompletionNotification;
FOUNDATION_EXPORT NSString * const PXKeyMuteScreenshotSound;
FOUNDATION_EXPORT NSString * const PXKeyScreenshotHaptic;
FOUNDATION_EXPORT NSString * const PXKeyEditorDefaultColor;
FOUNDATION_EXPORT NSString * const PXKeyEditorDefaultLineWidth;

// MARK: - 默认值

FOUNDATION_EXPORT const NSInteger PXDefaultResultAction;             // PXOutputActionSave
FOUNDATION_EXPORT const CGFloat    PXDefaultEditorLineWidth;         // 4.0

// MARK: - 路径（集中管理，按需创建）

/// SpringBoard 与设置包共享的数据根目录：/var/mobile/Library/PixPin
NSString *PXLibraryDataDirectory(void);
/// 截图任务临时文件根目录：<tmp>/PixPinTasks
NSString *PXTemporaryTasksRoot(void);

NS_ASSUME_NONNULL_END
