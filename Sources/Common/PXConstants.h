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
FOUNDATION_EXPORT CFStringRef const PXDarwinCaptureLong;        // com.pixpin.screenshot/capture/long（手动滚动长截图）
FOUNDATION_EXPORT CFStringRef const PXDarwinCaptureCancel;      // com.pixpin.screenshot/capture/cancel
FOUNDATION_EXPORT CFStringRef const PXDarwinPreferencesReload;  // com.pixpin.screenshot/preferences/reload

// MARK: - Snapper3 兼容别名（外部按 Snapper3 公开通知约定发信号即可触发 PixPin）

FOUNDATION_EXPORT CFStringRef const PXDarwinSnapperForceOpen;        // com.jontelang.snapper3.force.open → 区域截图
FOUNDATION_EXPORT CFStringRef const PXDarwinSnapperForceInstantOpen; // com.jontelang.snapper3.forceinstant.open → 即时区域截图
FOUNDATION_EXPORT CFStringRef const PXDarwinSnapperForceFreezeOpen;  // com.jontelang.snapper3.forcefreeze.open → 冻结截图
FOUNDATION_EXPORT CFStringRef const PXDarwinSnapperCloseAll;         // com.jontelang.snapper3.close.all → 取消当前任务
FOUNDATION_EXPORT CFStringRef const PXDarwinSnapperCloseCrop;        // com.jontelang.snapper3.closecrop → 取消当前任务

// MARK: - SHELLX 兼容别名（SHELLX 约定调用方在 Darwin 或 Distributed 任一中心发一条，
// 两个中心都必须监听；history/openlast/ready 无对应功能不注册）

FOUNDATION_EXPORT CFStringRef const PXDarwinShellXOpen;        // com.iosdump.screenshotshell.open → 区域截图
FOUNDATION_EXPORT CFStringRef const PXDarwinShellXOpenInstant; // com.iosdump.screenshotshell.open.instant → 即时区域截图
FOUNDATION_EXPORT CFStringRef const PXDarwinShellXOpenFreeze;  // com.iosdump.screenshotshell.open.freeze → 冻结截图
FOUNDATION_EXPORT CFStringRef const PXDarwinShellXClose;       // com.iosdump.screenshotshell.close → 取消当前任务

// MARK: - 进程内通知名（同样不携带图片对象，只提示协调器刷新）

FOUNDATION_EXPORT NSString * const PXNotificationResultUpdated; // com.pixpin.screenshot/result/updated

// MARK: - 偏好键（集中定义）

FOUNDATION_EXPORT NSString * const PXKeyEnabled;
FOUNDATION_EXPORT NSString * const PXKeyDefaultResultAction;
FOUNDATION_EXPORT NSString * const PXKeyAutoSaveToPhotos;
FOUNDATION_EXPORT NSString * const PXKeyCopyToClipboard;
FOUNDATION_EXPORT NSString * const PXKeyShowResultBubble;
FOUNDATION_EXPORT NSString * const PXKeyFloatingSnapShadow;
FOUNDATION_EXPORT NSString * const PXKeyShowCompletionNotification;
FOUNDATION_EXPORT NSString * const PXKeyMuteScreenshotSound;
FOUNDATION_EXPORT NSString * const PXKeyScreenshotHaptic;
FOUNDATION_EXPORT NSString * const PXKeyEditorDefaultColor;
FOUNDATION_EXPORT NSString * const PXKeyEditorDefaultLineWidth;
FOUNDATION_EXPORT NSString * const PXKeyEditorActionOrder;
FOUNDATION_EXPORT NSString * const PXKeyEditorToolOrder;
FOUNDATION_EXPORT NSString * const PXKeyEditorActionHidden;
FOUNDATION_EXPORT NSString * const PXKeyEditorToolHidden;
FOUNDATION_EXPORT NSString * const PXKeyEditorActionNames;
FOUNDATION_EXPORT NSString * const PXKeyEditorToolNames;
FOUNDATION_EXPORT NSString * const PXKeyEditorActionIcons;
FOUNDATION_EXPORT NSString * const PXKeyEditorToolIcons;
FOUNDATION_EXPORT NSString * const PXKeyEditorButtonIconSize;
FOUNDATION_EXPORT NSString * const PXKeySelectionButtonOrder;
FOUNDATION_EXPORT NSString * const PXKeySelectionButtonHidden;
FOUNDATION_EXPORT NSString * const PXKeySelectionButtonNames;
FOUNDATION_EXPORT NSString * const PXKeySelectionButtonIcons;
FOUNDATION_EXPORT NSString * const PXKeySelectionButtonIconStyle;
FOUNDATION_EXPORT NSString * const PXKeyAreaRememberLastRect;
FOUNDATION_EXPORT NSString * const PXKeyAreaLastSelectionRect;
FOUNDATION_EXPORT NSString * const PXKeyMarkupHandleOrigin;

// MARK: - 默认值

FOUNDATION_EXPORT const NSInteger PXDefaultResultAction;             // PXOutputActionSave
FOUNDATION_EXPORT const CGFloat    PXDefaultEditorLineWidth;         // 4.0

// MARK: - 路径（集中管理，按需创建）

/// 截图任务临时文件根目录：<tmp>/PixPinTasks
NSString *PXTemporaryTasksRoot(void);

NS_ASSUME_NONNULL_END
