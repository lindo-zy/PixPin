#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 只判断协议归属；无效的 PixPin 指令也由 PixPin 拒绝，不继续交给系统打开。
FOUNDATION_EXPORT BOOL PXIsExternalURL(NSURL * _Nullable url);
/// 白名单解析。默认启动为全屏截图，不接受 query、fragment 或任意文件路径。
FOUNDATION_EXPORT NSString * _Nullable PXNotificationNameForExternalURL(NSURL * _Nullable url);

NS_ASSUME_NONNULL_END
