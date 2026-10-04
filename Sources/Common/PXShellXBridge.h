#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 工具栏可外调的 SHELLX 功能（Darwin 通知外调，依据 ShellX 3.1.1 逆向报告 2.1 节）。
typedef NS_ENUM(NSInteger, PXShellXAction) {
    PXShellXActionArea = 0,    // SHELLX 区域画板
    PXShellXActionInstant,     // SHELLX 即时模式
    PXShellXActionFreeze,      // SHELLX 冻结画板
    PXShellXActionClose,       // 关闭 SHELLX 画板
    PXShellXActionAssistive,   // 套壳截图
};

/// SHELLX 出向桥：运行时在场探测 + 总开关读取 + 通知外调。
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
/// 动作对应的 SHELLX 触发通知名（不检查可用性）；供调用方做自发自收抑制等配套处理。
+ (nullable NSString *)notificationNameForAction:(PXShellXAction)action;
/// 外调一个 SHELLX 动作；未装时只记日志不发通知。
+ (void)notifyAction:(PXShellXAction)action;

@end

NS_ASSUME_NONNULL_END
