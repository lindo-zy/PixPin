#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 工具栏可外调的 SHELLX 功能全集（SHELLX 插件文档 2/3 节 + 逆向保留项）。
/// 通知类动作走 Darwin notify_post；URL 类动作走 prefs:// 打开（文档未给等价通知）。
typedef NS_ENUM(NSInteger, PXShellXAction) {
    PXShellXActionArea = 0,    // 普通框选（官方通知 open）
    PXShellXActionInstant,     // 即时（官方通知 open.instant）
    PXShellXActionFreeze,      // 冻结（官方通知 open.freeze）
    PXShellXActionHistory,     // 图片记录（官方通知 history）
    PXShellXActionOpenLast,    // 最近一张悬浮（官方通知 openlast，无最近图片时无反应）
    PXShellXActionClose,       // 关闭框选/长截图/拼接（官方通知 close）
    PXShellXActionLongShot,    // 长截图（URL shellx_long）
    PXShellXActionFullShot,    // 整屏截一张（通知 AssistiveScreenshot；真机实测：文档所记 URL shellx_full 实际是套壳）
    PXShellXActionMark,        // 全屏标记（URL shellx_mark）
    PXShellXActionEdit,        // 编辑（URL shellx_edit）
    PXShellXActionAI2,         // 文字问答（URL shellx_ai2）
    PXShellXActionTranslate,   // 全屏翻译（URL shellx_translate）
    PXShellXActionScan,        // 全屏扫码（URL shellx_scan）
    PXShellXActionAssistive,   // 套壳截图（URL shellx_full；真机实测：逆向名 AssistiveScreenshot 通知实际是整屏）
};

/// SHELLX 出向桥：运行时在场探测 + 总开关读取 + 通知/URL 双通道外调。
/// 与 PXShellXPlugin 的入向注册互补；未装 SHELLX 时一切调用为安全 no-op。
@interface PXShellXBridge : NSObject

/// SHELLX 在场：SpringBoard 进程内能取到 SHELLXPluginManager 类（其 dylib 的
/// 全部通知观察者与该类同住，类在场即代表观察者已注册）。
+ (BOOL)isInstalled;
/// SHELLX 总开关：域 com.iosdump.screenshotshell 的 GlobalEnabled；键缺失视为关
/// （SHELLX 侧对关态通知直接 return，所以这里必须同口径）。
+ (BOOL)masterSwitchEnabled;
/// 工具栏 SHELLX 入口可用 = 在场 && 总开关开；不满足时调用方应隐藏全部 SHELLX 按钮。
+ (BOOL)toolbarAvailable;
/// 通知类动作对应的 SHELLX 触发通知名（不检查可用性）；URL 类动作返回 nil。
/// 供调用方做自发自收抑制等配套处理。
+ (nullable NSString *)notificationNameForAction:(PXShellXAction)action;
/// URL 类动作对应的 prefs:// 路由（不检查可用性）；通知类动作返回 nil。
+ (nullable NSURL *)urlForAction:(PXShellXAction)action;
/// 外调一个 SHELLX 动作：通知类 notify_post，URL 类经 SpringBoard 的 UIApplication
/// openURL 打开（SHELLX 在 URL 分发层拦截；本方 URL hook 对非 pixpin:// 一律放行）。
/// 未装时只记日志不触发。
+ (void)notifyAction:(PXShellXAction)action;

@end

NS_ASSUME_NONNULL_END
