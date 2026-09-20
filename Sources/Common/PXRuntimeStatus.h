#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 运行状态上报：把注入时间、抓取方式、最近请求与结果写入
/// <Library>/PixPin/status.json，供设置页“查看运行状态”诊断读取。
/// 写入全部在内部串行队列执行，不阻塞调用方。
///
/// 诊断协议（排查“无法截图”的第一入口）：
/// - status.json 不存在 → tweak 未加载（注入器/filter 问题）；
/// - captureMethod = fallback-snapshot → 私有接口不可用，走了公开回退（结果仅含桌面自身）；
/// - lastResult = failed → message 里带具体错误。
@interface PXRuntimeStatus : NSObject

+ (void)reportLoadedWithCaptureMethod:(NSString *)captureMethod;
+ (void)reportRequest:(NSString *)modeName outcome:(NSString *)outcome;   // accepted / rejected-busy / rejected-disabled
+ (void)reportPhase:(NSString *)phase
                mode:(nullable NSString *)modeName
             message:(nullable NSString *)message;
+ (void)reportResultOK:(BOOL)ok
             captureMethod:(nullable NSString *)captureMethod
                   message:(nullable NSString *)message;

/// 设置页读取（任意进程可调）。文件不存在返回 nil。
+ (nullable NSDictionary *)readStatus;

+ (NSString *)statusFilePath;

@end

NS_ASSUME_NONNULL_END
