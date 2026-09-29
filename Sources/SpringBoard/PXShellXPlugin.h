#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// SHELLX 插件插入形式注册入口：把 PixPin 以 Snapper3 协议插件注册进 SHELLXPluginManager，
/// 使其出现在 SHELLX 设置页插件列表并接收 SHELLX 转发的截图。
/// SHELLX 未安装时探测链自然超时放弃，无任何副作用。
void PXShellXPluginInstall(void);

#ifdef __cplusplus
}
#endif
