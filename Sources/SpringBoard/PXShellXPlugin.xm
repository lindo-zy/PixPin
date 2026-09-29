#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
#import <roothide.h>
#else
#import <rootless.h>
#endif
#import "PXShellXPlugin.h"
#import "../Common/PXConstants.h"
#import "../Common/PXLog.h"
#import "../Common/PXPreferences.h"
#import "../Capture/PXCaptureCoordinator.h"

// SHELLX 插件插入形式（依据 ShellX 3.1.1 逆向报告 2.2 节）：
// SHELLX 的设置页插件列表只展示通过 SHELLXPluginManager.registerPlugin: 自注册的
// 对象，插件需实现 Snapper3 协议 15 个方法。与通知别名不同，这是进程内 ObjC 运行时
// 接口，双方都必须注入 SpringBoard。类名/方法名以运行时探测为准，SHELLX 未安装或
// 新版改名时探测失败自动放弃，不能硬链接其符号。

// 协议名与 SHELLX 二进制内字符串一致，保证 conformsToProtocol: 检查可通过。
@protocol Snapper3Plugin <NSObject>
@optional
- (void)processImage:(UIImage *)image;
- (BOOL)removeSnapAfterProcessing;
- (NSString *)name;
- (nullable NSString *)info;
- (nullable UIImage *)image;
- (nullable UIImage *)imageForMenuAndSettings;
- (NSString *)pluginIdentifier;
- (nullable NSString *)tweakIdentifier;
- (nullable NSString *)email;
- (nullable NSString *)twitter;
- (nullable NSString *)website;
- (nullable NSString *)developer;
- (BOOL)showInSettings;
- (BOOL)shouldRegister;
- (BOOL)disabledInitially;
@end

@interface PXShellXPlugin : NSObject <Snapper3Plugin>
@end

@implementation PXShellXPlugin

- (NSString *)pluginIdentifier {
    return PXBundleID;
}

// Snapper3 约定：tweakIdentifier 用于 Sileo 深链，与包 ID 一致。
- (NSString *)tweakIdentifier {
    return PXBundleID;
}

// Snapper3 约定：name 不可为 nil。
- (NSString *)name {
    return @"PixPin";
}

- (NSString *)info {
    return @"接收 SHELLX 截图，交给 PixPin 悬浮展示与编辑。";
}

- (BOOL)shouldRegister {
    return YES;
}

- (BOOL)showInSettings {
    return YES;
}

- (BOOL)disabledInitially {
    return NO;
}

// 图片已由 PixPin 接管展示，SHELLX 侧快照随之收起，避免同一张图两处悬浮。
- (BOOL)removeSnapAfterProcessing {
    return YES;
}

- (nullable NSString *)developer {
    return @"lindo";
}

- (nullable NSString *)email {
    return nil;
}

- (nullable NSString *)twitter {
    return nil;
}

- (nullable NSString *)website {
    return nil;
}

// 图标读 PixPinPrefs bundle 内置 Logo；bundle 缺失时返回 nil（协议仅要求 name 非 nil）。
- (nullable UIImage *)image {
    return [self pxPluginIcon];
}

- (nullable UIImage *)imageForMenuAndSettings {
    return [self pxPluginIcon];
}

- (nullable UIImage *)pxPluginIcon {
#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
    NSString *path = jbroot(@"/Library/PreferenceBundles/PixPinPrefs.bundle/PixPin@2x.png");
#else
    NSString *path = ROOT_PATH_NS(@"/Library/PreferenceBundles/PixPinPrefs.bundle/PixPin@2x.png");
#endif
    if (!path.length) return nil;
    UIImage *loaded = [UIImage imageWithContentsOfFile:path];
    if (!loaded || !loaded.CGImage) return nil;
    // 按路径构造的 UIImage 缩放语义不保证：显式按 2x 重建，保证设置页显示尺寸正确。
    return [UIImage imageWithCGImage:loaded.CGImage scale:2.0 orientation:UIImageOrientationUp];
}

// SHELLX 截图操作菜单点击 PixPin 时的回调：走外部图片编辑入口（isReedit 路径，
// 取消即结束，不回写输出动作）。遵守总开关；不占用截图模式开关——没有发生抓屏。
- (void)processImage:(UIImage *)image {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self processImage:image]; });
        return;
    }
    if (!image) return;
    if (!PXPreferences.config.enabled) {
        PXLogInfo(@"shellx processImage ignored: master switch off");
        return;
    }
    PXLogInfo(@"shellx processImage: %.0fx%.0f px, opening editor",
              image.size.width * image.scale, image.size.height * image.scale);
    [[PXCaptureCoordinator sharedCoordinator] openEditorWithImage:image mode:PXCaptureModeFull];
}

@end

// SHELLX dylib 加载完成即完成 ObjC 类注册，ctor 阶段 objc_getClass 已可命中；
// 重试链只为覆盖极端加载顺序，未装 SHELLX 的设备 12 次探测后静默放弃。
static void PXShellXPluginRegisterAttempt(NSInteger remaining) {
    if (remaining <= 0) {
        PXLogInfo(@"shellx plugin registration skipped: SHELLXPluginManager not present");
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        Class managerClass = objc_getClass("SHELLXPluginManager");
        if (managerClass && [managerClass respondsToSelector:@selector(sharedInstance)]) {
            @try {
                id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, @selector(sharedInstance));
                if (!manager) {
                    PXLogWarn(@"shellx plugin manager sharedInstance unavailable");
                    return;
                }
                if ([manager respondsToSelector:@selector(registerPlugin:)]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(manager,
                        @selector(registerPlugin:), [[PXShellXPlugin alloc] init]);
                    PXLogInfo(@"shellx plugin registered (%@)", PXBundleID);
                    return;
                }
                PXLogWarn(@"shellx plugin manager lacks registerPlugin:");
            } @catch (NSException *exception) {
                PXLogError(@"shellx plugin registration failed: %@", exception);
            }
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            PXShellXPluginRegisterAttempt(remaining - 1);
        });
    });
}

void PXShellXPluginInstall(void) {
    PXShellXPluginRegisterAttempt(12);
}
