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
FOUNDATION_EXPORT CFStringRef const PXDarwinActivate;          // com.pixpin.screenshot/activate（全屏截图）
FOUNDATION_EXPORT CFStringRef const PXDarwinCaptureFull;        // com.pixpin.screenshot/capture/full
FOUNDATION_EXPORT CFStringRef const PXDarwinCaptureArea;        // com.pixpin.screenshot/capture/area
FOUNDATION_EXPORT CFStringRef const PXDarwinCaptureFreeze;      // com.pixpin.screenshot/capture/freeze
FOUNDATION_EXPORT CFStringRef const PXDarwinCaptureInstant;     // com.pixpin.screenshot/capture/instant
FOUNDATION_EXPORT CFStringRef const PXDarwinCaptureMarkup;      // com.pixpin.screenshot/capture/markup
FOUNDATION_EXPORT CFStringRef const PXDarwinCaptureLong;        // com.pixpin.screenshot/capture/long（全屏自动滚动，可切换手动）
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

// MARK: - SHELLX 出向触发名（SHELLX 自己注册的观察者，PixPin 工具栏按钮 notify_post 外调用。
// 官方名逐字取自 SHELLX 插件文档第 2 节，文档保证 SHELLX 监听；其中区域/即时/冻结/关闭
// 与上方兼容别名同名，自发通知会被本方观察者收到，外调方必须做自发自收抑制。
// 历史版本走 Snapper3 别名（com.jontelang.snapper3.*），现按官方文档统一切换；
// AssistiveScreenshot 是文档外的逆向入口，继续沿用逆向报告。名字写错即静默无效，
// 改前必须用 SHELLX 插件文档或二进制字符串表核对）

FOUNDATION_EXPORT CFStringRef const PXShellXTriggerArea;      // com.iosdump.screenshotshell.open → 普通框选
FOUNDATION_EXPORT CFStringRef const PXShellXTriggerInstant;   // com.iosdump.screenshotshell.open.instant → 即时
FOUNDATION_EXPORT CFStringRef const PXShellXTriggerFreeze;    // com.iosdump.screenshotshell.open.freeze → 冻结
FOUNDATION_EXPORT CFStringRef const PXShellXTriggerHistory;   // com.iosdump.screenshotshell.history → 图片记录
FOUNDATION_EXPORT CFStringRef const PXShellXTriggerOpenLast;  // com.iosdump.screenshotshell.openlast → 最近一张悬浮
FOUNDATION_EXPORT CFStringRef const PXShellXTriggerClose;     // com.iosdump.screenshotshell.close → 关闭框选/长截图/拼接
FOUNDATION_EXPORT CFStringRef const PXShellXTriggerAssistive; // com.iosdump.screenshotshell/AssistiveScreenshot → 套壳截图

// MARK: - SHELLX 出向 URL 路由（SHELLX 插件文档第 3 节：prefs://root=shellx_*，
// 快捷指令与其余插件同链路调用。文档未给这些功能的等价通知，只能走 URL：
// 经 SpringBoard URL 分发层由 SHELLX 拦截，本方 URL hook 对非 pixpin:// 一律放行）

FOUNDATION_EXPORT CFStringRef const PXShellXRouteLong;      // prefs://root=shellx_long → 长截图
FOUNDATION_EXPORT CFStringRef const PXShellXRouteFull;      // prefs://root=shellx_full → 整屏截一张
FOUNDATION_EXPORT CFStringRef const PXShellXRouteMark;      // prefs://root=shellx_mark → 全屏标记
FOUNDATION_EXPORT CFStringRef const PXShellXRouteEdit;      // prefs://root=shellx_edit → 编辑
FOUNDATION_EXPORT CFStringRef const PXShellXRouteAI2;       // prefs://root=shellx_ai2 → 文字问答
FOUNDATION_EXPORT CFStringRef const PXShellXRouteTranslate; // prefs://root=shellx_translate → 全屏翻译
FOUNDATION_EXPORT CFStringRef const PXShellXRouteScan;      // prefs://root=shellx_scan → 全屏扫码

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
FOUNDATION_EXPORT NSString * const PXKeyLongShotMode;
FOUNDATION_EXPORT NSString * const PXKeyLongShotAutoScroll; // 旧配置迁移
FOUNDATION_EXPORT NSString * const PXKeyLongShotSampleInterval;
FOUNDATION_EXPORT NSString * const PXKeyLongShotIdleInterval;
FOUNDATION_EXPORT NSString * const PXKeyLongShotScrollDuration;
FOUNDATION_EXPORT NSString * const PXKeyLongShotSettleDuration;
FOUNDATION_EXPORT NSString * const PXKeyLongShotMaxSlices;
FOUNDATION_EXPORT NSString * const PXKeyLongShotMaxCanvasHeight;
FOUNDATION_EXPORT NSString * const PXKeyLongShotSliceQuality;
FOUNDATION_EXPORT NSString * const PXKeyLongShotOutputQuality;

// MARK: - 默认值

FOUNDATION_EXPORT const NSInteger PXDefaultResultAction;             // PXOutputActionSave
FOUNDATION_EXPORT const CGFloat    PXDefaultEditorLineWidth;         // 4.0

// MARK: - 路径（集中管理，按需创建）

/// 截图任务临时文件根目录：<tmp>/PixPinTasks
NSString *PXTemporaryTasksRoot(void);

NS_ASSUME_NONNULL_END
